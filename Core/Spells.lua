--[[ WellMet — spell / aura / range / distance probes.

The only module that asks the client "does X have the buff?", "is X in range?",
"how far is X?". Core/Select.lua is handed these as a `probe` table so the
selection logic stays pure and testable.

Forever notes:
  * Spells are resolved by NAME (ids differ from Classic and from rank to rank).
  * Aura reads are unreadable under addon restrictions (combat): a missing aura
    then means "unknown", never "missing".
  * UnitDistanceSquared only works for group members; for strangers the best we
    can do is CheckInteractDistance brackets (about 10 and 28 yards).
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

----------------------------------------------------------------------
-- Spell resolution
----------------------------------------------------------------------

-- The spell id for a buff's NAME (the rank the player has), or nil.
function ns.SpellId(buff)
	local info = C_Spell.GetSpellInfo(buff.name)
	return info and info.spellID or nil
end

-- The spell's icon for the settings UI: the client's own when it can describe the spell, else the icon
-- stored in Data/Classes.lua (the client can't describe a spell the player hasn't learned).
function ns.SpellIcon(buff)
	local info = C_Spell.GetSpellInfo(buff.name)
	return info and info.iconID or buff.icon
end

function ns.IsKnown(buff)
	local id = ns.SpellId(buff)
	return id ~= nil and C_SpellBook.IsSpellKnown(id) and true or false
end

----------------------------------------------------------------------
-- Ranks (casting a lower rank on a low-level target)
--   A buff cast by name goes out as your highest rank, and the game refuses it on a target that is too low level
--   (the spellbook / action bar pick a lower rank by themselves; a name cast does not). So the learned ranks are read from
--   the spellbook (each entry has its own spell id, "Rank N" text and the level it is learned at: /wellmet ranks shows
--   them) and a lower one is cast by id when the target is too low.
----------------------------------------------------------------------
-- A rank can be cast on a target whose level is at least (the level the rank is learned at) minus this. Measured on Forever
-- 1.60.1 with /wellmet ranktest (2026-10-21, Mage, 30 target levels): a gap of 10 was accepted (level 18, Arcane Intellect
-- learned at 28), 11 was refused (level 17); the same on a Paladin (Blessing of Might learned at 12: level 2 accepted, level 1 refused). A refused cast (SPELL_FAILED_LOWLEVEL) still steps down one more rank, see Core/Cast.lua.
ns.RANK_LEVEL_GAP = 10

local rankCache = {}      -- buff name -> list of { id, sub, level }, highest level first

local function readable(v) return v ~= nil and not issecretvalue(v) end

-- Every learned rank of `name`, highest first (empty list when the spellbook can't be read).
function ns.Ranks(name)
	local list = rankCache[name]
	if list then return list end
	list = {}
	pcall(function()
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
				if item and item.name == name and not item.isPassive then
					local id = item.spellID or item.actionID
					local level = C_Spell.GetSpellLevelLearned(id)
					if readable(id) and readable(level) and C_SpellBook.IsSpellKnown(id) then
						list[#list + 1] = { id = id, sub = item.subName, level = level }
					end
				end
			end
		end
	end)
	table.sort(list, function(a, b) return a.level > b.level end)
	rankCache[name] = list
	return list
end

-- A rank that failed on a target ("too low level"): never try that rank or a higher one on them again this session.
local tooHigh = {}      -- "key|name" -> the level of the lowest rank refused so far

function ns.RankRefused(key, name, rank) tooHigh[key .. "|" .. name] = rank.level end
function ns.RankReset() for k in pairs(tooHigh) do tooHigh[k] = nil end end

-- The rank to cast on a target, or nil to cast the plain name (the highest rank, as before): when the level of the target
-- is unknown, there is only one rank, or the highest rank already fits.
-- Returns the rank, and true when it is not the highest one.
function ns.RankFor(buff, targetLevel, targetKey)
	if not readable(targetLevel) or type(targetLevel) ~= "number" or targetLevel < 1 then return nil end
	local ranks = ns.Ranks(buff.name)
	if #ranks < 2 then return nil end
	local refused = tooHigh[(targetKey or "") .. "|" .. buff.name]
	local chosen
	for _, rank in ipairs(ranks) do
		if (not refused or rank.level < refused) and rank.level - ns.RANK_LEVEL_GAP <= targetLevel then chosen = rank; break end
	end
	if not chosen then      -- nothing fits: the lowest rank not refused yet
		for i = #ranks, 1, -1 do
			if not refused or ranks[i].level < refused then chosen = ranks[i]; break end
		end
	end
	if not chosen or chosen == ranks[1] then return nil end
	return chosen, true
end

-- Re-resolve ids for the caster's buffs (login, and when spells change).
function WM:InitSpells()
	for k in pairs(rankCache) do rankCache[k] = nil end
	for _, key in ipairs(WM.caster.all) do
		local buff = WM.caster.buffs[key]
		buff.id = ns.SpellId(buff)
		buff.known = buff.id ~= nil and C_SpellBook.IsSpellKnown(buff.id) and true or false
		WM:Log("spell", buff.name, "id=" .. ns.SafeStr(buff.id), "known=" .. ns.SafeStr(buff.known))
	end
end

----------------------------------------------------------------------
-- Aura / range / distance
----------------------------------------------------------------------

-- Can we read other units' auras right now? (false in combat, encounters, ...)
function ns.AurasReadable()
	return not C_Secrets.ShouldAurasBeSecret()
end

-- Does `unit` LACK the buff? true = lacks it, false = has it (or an alternate),
-- nil = can't tell (auras unreadable right now).
function ns.Lacks(unit, buff)
	local names = { buff.name }
	for _, alt in ipairs(buff.alt or {}) do names[#names + 1] = alt end
	for _, name in ipairs(names) do
		local aura = C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL")
		if aura then
			if issecrettable(aura) then return nil end
			return false
		end
	end
	if C_Secrets.ShouldAurasBeSecret() then return nil end
	return true
end

-- What is on `unit` for this buff (the buff itself or any `alt`, e.g. the Greater version)?
--   "mine"   one of them was cast by you        (aura.sourceUnit is you; Blizzard's own AuraUtil asks the same)
--   "other"  there, but cast by someone else (or the caster isn't known)
--   "absent" not there
--   nil      can't tell right now (auras hidden)
function ns.AuraState(unit, buff)
	local names = { buff.name }
	for _, alt in ipairs(buff.alt or {}) do names[#names + 1] = alt end
	local found
	for _, name in ipairs(names) do
		local aura = C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL")
		if aura then
			if issecrettable(aura) then return nil end
			local source = aura.sourceUnit
			if issecretvalue(source) then return nil end
			if source ~= nil and UnitIsUnit("player", source) then return "mine" end
			found = "other"
		end
	end
	if found then return found end
	if C_Secrets.ShouldAurasBeSecret() then return nil end
	return "absent"
end

-- How long is left on this buff on `unit` (the buff itself or any `alt`)? For the debug report: finds out whether the
-- game gives other players' aura times at all. Returns nil when the buff is not on them, else
-- { name, source = "mine" | "other" | "unknown", duration, left } where duration / left are numbers, "none" (the aura has
-- no end), "hidden" (a secret value) or "not given" (the field is missing).
function ns.AuraTimes(unit, buff)
	local names = { buff.name }
	for _, alt in ipairs(buff.alt or {}) do names[#names + 1] = alt end
	for _, name in ipairs(names) do
		local aura = C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL")
		if aura then
			if issecrettable(aura) then return { name = name, source = "unknown", duration = "hidden", left = "hidden" } end
			local source = aura.sourceUnit
			local who = "other"
			if issecretvalue(source) then who = "unknown"
			elseif source == nil then who = "unknown"
			elseif UnitIsUnit("player", source) then who = "mine" end
			local function number(v)
				if issecretvalue(v) then return "hidden" end
				if v == nil then return "not given" end
				return v
			end
			local duration, expires = number(aura.duration), number(aura.expirationTime)
			local left = expires
			if type(expires) == "number" then
				left = (expires == 0) and "none" or math.max(0, expires - GetTime())
			end
			return { name = name, source = who, duration = duration, left = left }
		end
	end
	return nil
end

-- How much of this buff's time is LEFT on `unit`, as a share (0 to 1): 0.2 = the last fifth. nil when the buff is not there,
-- has no end, or the game does not give its time.
function ns.AuraRemaining(unit, buff)
	local t = ns.AuraTimes(unit, buff)
	if not t or type(t.left) ~= "number" or type(t.duration) ~= "number" or t.duration <= 0 then return nil end
	return math.min(1, t.left / t.duration)
end

-- Seconds until `buff` can be cast (the global cooldown counts), 0 when it is ready, nil when the game hides it.
function ns.CooldownLeft(buff)
	local cd = C_Spell.GetSpellCooldown(buff.name)
	if not cd or issecrettable(cd) then return nil end
	local start, duration = cd.startTime, cd.duration
	if issecretvalue(start) or issecretvalue(duration) then return nil end
	if not start or not duration or duration <= 0 then return 0 end
	return math.max(0, start + duration - GetTime())
end

-- Is `unit` within cast range of the buff? true / false / nil (unknown or invalid).
function ns.InRange(buff, unit)
	return C_Spell.IsSpellInRange(buff.name, unit)
end

-- Distance to a candidate in yards, or nil when unknown/far.
--   group members: exact (UnitDistanceSquared)
--   others:        10 or 28 yd brackets (CheckInteractDistance duel / inspect)
function ns.Distance(cand)
	if cand.tier == 0 then return 0 end
	if cand.tier == 1 then
		local distSq, checked = UnitDistanceSquared(cand.unit)
		if checked and distSq then return math.sqrt(distSq) end
	end
	if CheckInteractDistance(cand.unit, 3) then return 10 end
	if CheckInteractDistance(cand.unit, 1) then return 28 end
	return nil
end

-- The probe handed to Select.Pick.
ns.Probe = {
	known    = ns.IsKnown,
	inRange  = ns.InRange,
	lacks    = ns.Lacks,
	state    = ns.AuraState,
	remaining = ns.AuraRemaining,
	distance = ns.Distance,
}
