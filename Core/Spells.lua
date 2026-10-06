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

-- Re-resolve ids for the caster's buffs (login, and when spells change).
function WM:InitSpells()
	for _, key in ipairs(WM.caster.order) do
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
	distance = ns.Distance,
}
