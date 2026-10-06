--[[ WellMet — static class/buff data. No logic here.

Spells are defined by their English NAME and resolved to ids at runtime
(Core/Spells.lua): Forever's spell ids can't be assumed to match Classic's, and
a name resolves to the rank the player actually has.
]]

local ADDON, ns = ...

-- Classes a buff can be cast ON (Forever has all nine, cross-faction).
ns.TargetClasses = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Buffs by CASTER class.
--   buffs[key] = { name = English spell name, alt = { other names that also count as "has it" } }
--   order      = display/cycle order of the keys
--   mode       = "assign": one buff per TARGET class, chosen in settings (Paladin blessings).
-- Priest / Mage / Druid ("stack"): add here later (several buffs per target, each toggleable).
ns.CasterData = {
	PALADIN = {
		mode = "assign",
		order = { "MIGHT", "WISDOM" },
		buffs = {
			MIGHT  = { key = "MIGHT",  name = "Blessing of Might",  alt = { "Greater Blessing of Might" } },
			WISDOM = { key = "WISDOM", name = "Blessing of Wisdom", alt = { "Greater Blessing of Wisdom" } },
		},
	},
}

-- Default blessing per target class (all editable in settings). "NONE" skips the class.
ns.DefaultAssign = {
	WARRIOR = "MIGHT", ROGUE = "MIGHT",
	HUNTER = "WISDOM", PALADIN = "WISDOM", PRIEST = "WISDOM", SHAMAN = "WISDOM",
	MAGE = "WISDOM", WARLOCK = "WISDOM", DRUID = "WISDOM",
}
