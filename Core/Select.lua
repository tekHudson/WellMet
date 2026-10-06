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

function Select.Reset()
	for k in pairs(memory) do memory[k] = nil end
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
function Select.BuffsFor(caster, class, settings)
	if caster.mode == "stack" then
		local list = {}
		for _, key in ipairs(caster.order) do
			local buff = caster.buffs[key]
			if ns.StackEnabled(buff, class, settings.stack) then list[#list + 1] = buff end
		end
		if #list == 0 then return nil, "no buffs are switched on for this class" end
		return list
	end
	local key
	if class then
		key = settings.assign[class] or ns.DefaultAssign[class]
	else
		key = settings.unknownClass
	end
	if key == nil or key == "NONE" then return nil, "assignment: skip this class" end
	local buff = caster.buffs[key]
	if not buff then return nil, "no buff '" .. ns.SafeStr(key) .. "' for this caster" end
	return { buff }
end

local function tierOf(entry, settings)
	local t = entry.cand.tier
	if t == 2 and settings.groupFirst == false then return 1 end
	return t
end

local function before(settings)
	return function(a, b)
		local ta, tb = tierOf(a, settings), tierOf(b, settings)
		if ta ~= tb then return ta < tb end
		if a.dist ~= b.dist then return a.dist < b.dist end
		if a.cand.order ~= b.cand.order then return a.cand.order < b.cand.order end
		if a.cand.key ~= b.cand.key then return a.cand.key < b.cand.key end
		return (a.buff.index or 0) < (b.buff.index or 0)       -- same person: the caster's buff order
	end
end

-- ctx = { now, settings, caster, probe }
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

	-- Why this (person, buff) pair can't be cast right now, or nil (+ the distance when it can).
	local function whyNot(cand, buff)
		if not known(buff) then return buff.name .. " is not learned" end
		local blocked, left = Select.IsBlocked(cand.key, buff.name, now)
		if blocked then return string.format("tried recently (%.0fs left)", left) end
		if cand.tier ~= 0 then
			local r = probe.inRange(buff, cand.unit)
			if r ~= true then return (r == false) and "out of cast range" or "range unknown" end
		end
		local dist = probe.distance(cand)
		if (settings.radius or 0) > 0 and (not dist or dist > settings.radius) then
			return "outside the " .. settings.radius .. " yd radius"
		end
		local lacks = probe.lacks(cand.unit, buff)
		if lacks == false then return "already has " .. buff.name end
		if lacks == nil then return "aura info unavailable right now" end
		return nil, dist
	end

	for _, cand in ipairs(cands) do
		local gate
		if cand.tier == 0 and not settings.includeSelf then
			gate = "buffing yourself is turned off"
		elseif cand.tier == 2 and not settings.strangers then
			gate = "players outside the group are turned off"
		end
		if gate then
			skipped[#skipped + 1] = { cand = cand, reason = gate }
		else
			local buffs, why = Select.BuffsFor(ctx.caster, cand.class, settings)
			if not buffs then
				skipped[#skipped + 1] = { cand = cand, reason = why }
			else
				for _, buff in ipairs(buffs) do
					local reason, dist = whyNot(cand, buff)
					if reason then
						skipped[#skipped + 1] = { cand = cand, reason = reason, buff = buff }
					else
						eligible[#eligible + 1] = { cand = cand, buff = buff, dist = dist or math.huge }
					end
				end
			end
		end
	end

	table.sort(eligible, before(settings))
	return eligible[1], skipped, eligible
end
