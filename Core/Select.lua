--[[ WellMet — choosing who to buff next. PURE LOGIC: no WoW API calls.

Everything the client knows comes in through `ctx.probe` (see Core/Spells.lua),
so this file is unit-tested headless (tests/run.lua).

Order of eligible targets:
  1. tier   (you, then group, then everyone else; with "group first" off, group
            and strangers are equal)
  2. distance, nearest first (unknown distance last)
  3. arrival order (when we first saw them), then key — deterministic
A "just tried" memory (per target + spell) makes the next press move on to a
different person even before the new aura shows up.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing

local Select = {}
ns.Select = Select

local memory = {}      -- "key|spell" -> time until which that target is skipped

local function memKey(key, spell) return key .. "|" .. spell end

function Select.Mark(key, spell, seconds, now)
	memory[memKey(key, spell)] = (now or GetTime()) + seconds
end

-- Returns true, secondsLeft when `key` was tried recently with `spell`.
function Select.IsBlocked(key, spell, now)
	local k = memKey(key, spell)
	local untilTime = memory[k]
	if not untilTime then return false end
	if now >= untilTime then memory[k] = nil; return false end
	return true, untilTime - now
end

-- A short failure (line of sight, out of range) gets one free retry: the first one only releases the person so the next
-- press can try them again; the second within `window` seconds returns true, meaning skip them now.
local failedAt = {}
function Select.RetryUsed(key, spell, now, window)
	local k = memKey(key, spell)
	local first = failedAt[k]
	if first and now - first <= window then failedAt[k] = nil; return true end
	failedAt[k] = now
	return false
end

function Select.Succeeded(key, spell)
	failedAt[memKey(key, spell)] = nil
end

function Select.Reset()
	for k in pairs(memory) do memory[k] = nil end
	for k in pairs(failedAt) do failedAt[k] = nil end
end

function Select.MemorySnapshot(now)
	local out = {}
	for k, untilTime in pairs(memory) do
		if untilTime > now then out[#out + 1] = string.format("%s (%.0fs)", k, untilTime - now) end
	end
	table.sort(out)
	return out
end

-- Which buffs does this target get? Returns a list of buffs, or nil + reason.
--   assign mode (Paladin): exactly one, chosen per target class.
--   stack mode  (Mage):    every buff switched on for the target class.
function Select.BuffsFor(caster, class, cfg)
	if not class then return nil, "class not readable, so no buff is chosen" end
	if caster.mode == "stack" then
		local list = {}
		for _, key in ipairs(caster.order) do
			local buff = caster.buffs[key]
			if ns.StackEnabled(buff, class, cfg.stack) then list[#list + 1] = buff end
		end
		if #list == 0 then return nil, "no buffs are switched on for this class" end
		return list
	end
	local key = cfg.assign[class] or ns.DefaultAssign[class]
	if key == nil or key == "NONE" then return nil, "assignment: skip this class" end
	local buff = caster.buffs[key]
	if not buff then return nil, "no buff '" .. ns.SafeStr(key) .. "' for this caster" end
	return { buff }
end

-- The SECONDARY blessing for a stranger of this class (Paladin, Others section only), or nil.
-- Cast when the stranger already wears the primary from someone else. Ignored if it is the primary itself.
function Select.SecondaryFor(caster, class, cfg, primary)
	local key = cfg.assign2 and cfg.assign2[class]
	if not key or key == "NONE" then return nil end
	local buff = caster.buffs[key]
	if not buff or buff == primary or buff.selfOnly then return nil end
	return buff
end

-- The caster's own buff for one category (an aura, an armor), or nil (+ a reason when it can't be chosen).
--   choice "NONE": nothing. "AUTO": the first spell in category.auto that is learned.
function Select.SelfBuff(caster, cat, cfg, isKnown)
	local choice = (cfg.choice and cfg.choice[cat.key]) or cat.default
	if choice == nil or choice == "NONE" then return nil end
	if choice == "AUTO" then
		for _, key in ipairs(cat.auto) do
			if isKnown(caster.buffs[key]) then return caster.buffs[key] end
		end
		return nil, "none of the " .. cat.title:lower() .. " spells is learned"
	end
	return caster.buffs[choice]
end

-- You, then your group, then everyone else; nearest first within each.
local function before()
	return function(a, b)
		-- someone MISSING a buff comes before someone whose buff is merely running out; those go most urgent first
		local ra, rb = a.refresh, b.refresh
		if (ra ~= nil) ~= (rb ~= nil) then return rb ~= nil end
		if ra and rb and ra ~= rb then return ra < rb end
		local ta, tb = a.cand.tier, b.cand.tier
		if ta ~= tb then return ta < tb end
		if a.dist ~= b.dist then return a.dist < b.dist end
		if a.cand.order ~= b.cand.order then return a.cand.order < b.cand.order end
		if a.cand.key ~= b.cand.key then return a.cand.key < b.cand.key end
		return (a.buff.index or 0) < (b.buff.index or 0)       -- same person: the caster's buff order
	end
end

-- ctx = { now, settings, caster, probe, requests }   (requests: guid -> { buff } from chat, or nil when that feature is off)
-- cands: list of { unit, tier, key, name, class, order, ... }
-- Returns: best (or nil), skipped = { { cand, reason, buff }, ... }, eligible (sorted).
-- An entry is one (person, buff) pair: a stack-mode caster can have several per person.
function Select.Pick(cands, ctx)
	local now, settings, probe = ctx.now, ctx.settings, ctx.probe
	local eligible, skipped, knownMemo = {}, {}, {}

	local function known(buff)
		local v = knownMemo[buff]
		if v == nil then v = probe.known(buff) and true or false; knownMemo[buff] = v end
		return v
	end

	-- Is this buff on them but nearly gone? Returns the share of its time that is left (e.g. 0.12) when that is at or below
	-- the "refresh" setting, else nil. A Paladin only refreshes his OWN blessing (a recast would replace another Paladin's).
	local function refreshFraction(cand, buff)
		local r = settings.refresh
		if not (r and r.enabled and probe.remaining) then return nil end
		if ctx.caster.mode == "assign" and probe.state and probe.state(cand.unit, buff) ~= "mine" then return nil end
		local share = probe.remaining(cand.unit, buff)
		if share and share <= (r.percent or 20) / 100 then return share end
		return nil
	end

	-- Why this (person, buff) pair can't be cast right now, or nil (+ the distance when it can; + the share of time left
	-- when it is a refresh of a buff that is running out).
	local function whyNot(cand, buff, cfg, skipAura)
		if buff.partyOnly and cand.tier == 2 then return buff.name .. " only works on party and raid members" end
		if not known(buff) then return buff.name .. " is not learned" end
		local blocked, left = Select.IsBlocked(cand.key, buff.name, now)
		if blocked then return string.format("tried recently (%.0fs left)", left) end
		if cand.tier ~= 0 then
			local r = probe.inRange(buff, cand.unit)
			if r ~= true then return (r == false) and "out of cast range" or "range unknown" end
		end
		local dist = probe.distance(cand)
		local radius = cfg.radius or 0
		if radius > 0 and (not dist or dist > radius) then
			return "outside the " .. radius .. " yd radius"
		end
		if skipAura then return nil, dist end
		local lacks = probe.lacks(cand.unit, buff)
		if lacks == false then
			local share = refreshFraction(cand, buff)
			if share then return nil, dist, share end
			return "already has " .. buff.name
		end
		if lacks == nil then return "aura info unavailable right now" end
		return nil, dist
	end

	local function add(cand, buff, cfg)
		local reason, dist, share = whyNot(cand, buff, cfg)
		if reason then
			skipped[#skipped + 1] = { cand = cand, reason = reason, buff = buff }
		else
			eligible[#eligible + 1] = { cand = cand, buff = buff, dist = dist or math.huge, refresh = share,
				note = share and string.format("refresh: %d%% of its time left", math.floor(share * 100 + 0.5)) or nil }
		end
	end

	-- Primary + secondary blessing for a stranger. A Paladin has only ONE blessing on a target at a time, so:
	--   one of yours already there        -> nothing to do (a second cast would replace it)
	--   no primary on them                -> the primary
	--   primary there from someone else   -> the secondary, if they don't have it either
	local function considerPair(cand, primary, secondary, cfg)
		local sP, sS = probe.state(cand.unit, primary), probe.state(cand.unit, secondary)
		local function skip(buff, reason) skipped[#skipped + 1] = { cand = cand, reason = reason, buff = buff } end
		if sP == nil or sS == nil then return skip(primary, "aura info unavailable right now") end
		local chosen, note, share
		if sP == "mine" then
			share = refreshFraction(cand, primary)
			if not share then return skip(primary, "already has your " .. primary.name) end
			chosen = primary
		elseif sS == "mine" then
			share = refreshFraction(cand, secondary)
			if not share then return skip(secondary, "already has your " .. secondary.name) end
			chosen = secondary
		elseif sP == "absent" then
			chosen = primary
		elseif sS == "absent" then
			chosen, note = secondary, primary.name .. " is on them from someone else, so " .. secondary.name .. " instead"
		else
			return skip(primary, "already has " .. primary.name .. " and " .. secondary.name .. " (from others)")
		end
		local reason, dist = whyNot(cand, chosen, cfg, true)
		if reason then return skip(chosen, reason) end
		if share then note = string.format("refresh: %d%% of its time left", math.floor(share * 100 + 0.5)) end
		eligible[#eligible + 1] = { cand = cand, buff = chosen, dist = dist or math.huge, note = note, refresh = share }
	end

	local function consider(cand)
		local cfg = settings[ns.SECTION_OF_TIER[cand.tier]]
		if not cfg.enabled then
			skipped[#skipped + 1] = { cand = cand, reason = "the " .. ({ [0] = "Self", [1] = "Party / Raid", [2] = "Others" })[cand.tier] .. " section is switched off" }
			return
		end
		if cand.tier == 0 then
			-- your own buffs first (armor, aura, ...); they sort ahead of everything else
			for _, cat in ipairs(ctx.caster.selfCategories) do
				local buff, why = Select.SelfBuff(ctx.caster, cat, cfg, known)
				if buff then
					add(cand, buff, cfg)
				elseif why then
					skipped[#skipped + 1] = { cand = cand, reason = why }
				end
			end
		end
		-- a player who asked for a buff in chat gets that one instead of their class default
		local req = ctx.requests and cand.tier ~= 0 and cand.guid and ctx.requests[cand.guid]
		if req then
			if req.buff == "NONE" then
				skipped[#skipped + 1] = { cand = cand, reason = "asked for no buff (!none)" }
				return
			end
			local want = ctx.caster.buffs[req.buff]
			if want and not want.selfOnly then return add(cand, want, cfg) end
		end
		local buffs, why = Select.BuffsFor(ctx.caster, cand.class, cfg)
		if not buffs then
			skipped[#skipped + 1] = { cand = cand, reason = why }
			return
		end
		if cand.tier == 2 and ctx.caster.mode == "assign" then
			local secondary = Select.SecondaryFor(ctx.caster, cand.class, cfg, buffs[1])
			if secondary then return considerPair(cand, buffs[1], secondary, cfg) end
		end
		for _, buff in ipairs(buffs) do add(cand, buff, cfg) end
	end

	for _, cand in ipairs(cands) do consider(cand) end

	table.sort(eligible, before())
	return eligible[1], skipped, eligible
end
