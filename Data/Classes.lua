--[[ WellMet — static class/buff data. No logic here.

Spells are defined by their English NAME and resolved to ids at runtime
(Core/Spells.lua): Forever's spell ids can't be assumed to match Classic's, and
a name resolves to the rank the player actually has.
]]

local ADDON, ns = ...

-- Classes a buff can be cast ON (Forever has all nine, cross-faction).
ns.TargetClasses = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Buffs by CASTER class.
--   buffs[key] = { name = English spell name, alt = { other names that also count as "has it" },
--                  icon = texture shown in settings when the client can't resolve the spell (not learned yet) }
--   order      = display/cycle order of the keys
--   mode       = "assign": one buff per TARGET class, chosen in settings (Paladin blessings).
--                "stack":  several buffs per target, each switched on/off per target class (Mage).
--   stack buffs also carry: defaultClasses (target classes it is ON for by default; "UNKNOWN" = class
--   unreadable) and exclusive (the buff it replaces, so only one of the two can be on for a class).
-- Priest / Druid ("stack"): add here later.
local MANA_CLASSES = { PALADIN = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true, HUNTER = true, UNKNOWN = true }

ns.CasterData = {
	PALADIN = {
		mode = "assign",
		title = "Which blessing on which class",
		order = { "MIGHT", "WISDOM" },
		buffs = {
			MIGHT  = { key = "MIGHT",  name = "Blessing of Might",  alt = { "Greater Blessing of Might" },  icon = "Interface\\Icons\\Spell_Holy_FistOfJustice" },
			WISDOM = { key = "WISDOM", name = "Blessing of Wisdom", alt = { "Greater Blessing of Wisdom" }, icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
		},
	},
	MAGE = {
		mode = "stack",
		title = "Which buffs on which class",
		order = { "INTELLECT", "DAMPEN", "AMPLIFY" },
		buffs = {
			-- Arcane Brilliance (the group version) also counts as having it.
			INTELLECT = { key = "INTELLECT", name = "Arcane Intellect", alt = { "Arcane Brilliance" }, defaultClasses = MANA_CLASSES,
			icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
			DAMPEN    = { key = "DAMPEN",    name = "Dampen Magic",     defaultClasses = {}, exclusive = "AMPLIFY",
			icon = "Interface\\Icons\\Spell_Nature_AbolishMagic" },
			AMPLIFY   = { key = "AMPLIFY",   name = "Amplify Magic",    defaultClasses = {}, exclusive = "DAMPEN",
			icon = "Interface\\Icons\\Spell_Holy_FlashHeal" },
		},
	},
}

-- Each buff knows its position in the caster's order (used to keep one person's buffs in order).
for _, caster in pairs(ns.CasterData) do
	for i, key in ipairs(caster.order) do caster.buffs[key].index = i end
end

-- Default blessing per target class (all editable in settings). "NONE" skips the class.
ns.DefaultAssign = {
	WARRIOR = "MIGHT", ROGUE = "MIGHT",
	HUNTER = "WISDOM", PALADIN = "WISDOM", PRIEST = "WISDOM", SHAMAN = "WISDOM",
	MAGE = "WISDOM", WARLOCK = "WISDOM", DRUID = "WISDOM",
}

-- Does this character's class have buffs in WellMet? If not, no other file does anything.
ns.supported = ns.CasterData[select(2, UnitClass("player"))] ~= nil
