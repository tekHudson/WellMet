--[[ WellMet — static class/buff data. No logic here.

Spells are defined by their English NAME and resolved to ids at runtime
(Core/Spells.lua): Forever's spell ids can't be assumed to match Classic's, and
a name resolves to the rank the player actually has.
]]

local ADDON, ns = ...

-- Classes a buff can be cast ON (Forever has all nine, cross-faction).
ns.TargetClasses = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Spell names and levels were checked against the Forever spellbook database (foreverchanges.pro/spellbook/<class>)
-- on 2026-10-06; only spells you can actually CAST belong here (Omen of Clarity is a passive on Forever, so it is not
-- listed); Forever has no Sanctity Aura (it appears in other addons' lists).
-- Only classes that can buff OTHER players are supported (Paladin, Mage, Druid, Priest). On Warlock, Warrior, Hunter,
-- Shaman and Rogue WellMet does not load at all: one self buff is nothing a key bind of the spell itself can't do.
-- Buffs by CASTER class.
--   buffs[key] = { name = English spell name, alt = { other names that also count as "has it" },
--                  icon = texture shown in settings when the client can't resolve the spell (not learned yet) }
--   order      = display/cycle order of the keys
--   mode       = "assign": one buff per TARGET class, chosen in settings (Paladin blessings).
--                "stack":  several buffs per target, each switched on/off per target class (Mage).
--   stack buffs also carry: defaultClasses (target classes it is ON for by default) and exclusive (the buff it replaces, so only one of the two can be on for a class).
--   selfCategories = the caster's OWN buffs, one choice per category (an aura, an armor), cast on yourself
--   first. A category is { key, title, default = <buff key | "AUTO" | "NONE">, choices = { buff keys },
--   auto = { buff keys, best first }, autoLabel }. "AUTO" means the first buff in `auto` that is learned.
--   Self buffs live in `buffs` with selfOnly = true and are not part of `order`.
local ALL_CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
local MANA_CLASSES = { PALADIN = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true, HUNTER = true }

ns.CasterData = {
	PALADIN = {
		mode = "assign",
		title = "Which blessing on which class",
		order = { "MIGHT", "WISDOM" },
		buffs = {
			MIGHT  = { key = "MIGHT",  name = "Blessing of Might",  alt = { "Greater Blessing of Might" },  icon = "Interface\\Icons\\Spell_Holy_FistOfJustice" },
			WISDOM = { key = "WISDOM", name = "Blessing of Wisdom", alt = { "Greater Blessing of Wisdom" }, icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom" },
			DEVOTION      = { key = "DEVOTION",      selfOnly = true, name = "Devotion Aura",          icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
			RETRIBUTION   = { key = "RETRIBUTION",   selfOnly = true, name = "Retribution Aura",       icon = "Interface\\Icons\\Spell_Holy_AuraOfLight" },
			CONCENTRATION = { key = "CONCENTRATION", selfOnly = true, name = "Concentration Aura",     icon = "Interface\\Icons\\Spell_Holy_MindSooth" },
			SHADOW_RES    = { key = "SHADOW_RES",    selfOnly = true, name = "Shadow Resistance Aura", icon = "Interface\\Icons\\Spell_Shadow_SealOfKings" },
			FROST_RES     = { key = "FROST_RES",     selfOnly = true, name = "Frost Resistance Aura",  icon = "Interface\\Icons\\Spell_Frost_WizardMark" },
			FIRE_RES      = { key = "FIRE_RES",      selfOnly = true, name = "Fire Resistance Aura",   icon = "Interface\\Icons\\Spell_Fire_SealOfFire" },
			RIGHTEOUS_FURY = { key = "RIGHTEOUS_FURY", selfOnly = true, name = "Righteous Fury",       icon = "Interface\\Icons\\Spell_Holy_SealOfFury" },
		},
		selfCategories = {
			{ key = "AURA", title = "Aura", default = "DEVOTION",
			  choices = { "DEVOTION", "RETRIBUTION", "CONCENTRATION", "SHADOW_RES", "FROST_RES", "FIRE_RES" } },
			{ key = "FURY", title = "Righteous Fury", default = "NONE", choices = { "RIGHTEOUS_FURY" } },
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
			ICE_ARMOR   = { key = "ICE_ARMOR",   selfOnly = true, name = "Ice Armor",   icon = "Interface\\Icons\\Spell_Frost_FrostArmor02" },
			FROST_ARMOR = { key = "FROST_ARMOR", selfOnly = true, name = "Frost Armor", icon = "Interface\\Icons\\Spell_Frost_FrostArmor02" },
			MAGE_ARMOR  = { key = "MAGE_ARMOR",  selfOnly = true, name = "Mage Armor",  icon = "Interface\\Icons\\Spell_MageArmor" },
		},
		selfCategories = {
			{ key = "ARMOR", title = "Armor", default = "AUTO", auto = { "ICE_ARMOR", "FROST_ARMOR" },
			  autoLabel = "Frost / Ice Armor (best learned)", choices = { "MAGE_ARMOR" } },
		},
	},
	DRUID = {
		mode = "stack",
		title = "Which buffs on which class",
		order = { "MARK", "THORNS" },
		buffs = {
			-- Gift of the Wild (the group version) also counts as having Mark of the Wild.
			MARK   = { key = "MARK",   name = "Mark of the Wild", alt = { "Gift of the Wild" }, defaultClasses = ALL_CLASSES,
			           icon = "Interface\\Icons\\Spell_Nature_Regeneration" },
			THORNS = { key = "THORNS", name = "Thorns", defaultClasses = {}, icon = "Interface\\Icons\\Spell_Nature_Thorns" },
		},
		-- no selfCategories: Omen of Clarity is a passive in Forever (nothing to cast), and Druid forms are not buffs
	},
	PRIEST = {
		mode = "stack",
		title = "Which buffs on which class",
		order = { "FORTITUDE", "SPIRIT", "SHADOW_PROT" },
		buffs = {
			-- The group versions (Prayer of ...) also count as having the single-target buff.
			FORTITUDE   = { key = "FORTITUDE", name = "Power Word: Fortitude", alt = { "Prayer of Fortitude" }, defaultClasses = ALL_CLASSES,
			                icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
			SPIRIT      = { key = "SPIRIT", name = "Divine Spirit", alt = { "Prayer of Spirit" }, defaultClasses = MANA_CLASSES,
			                icon = "Interface\\Icons\\Spell_Holy_DivineSpirit" },
			SHADOW_PROT = { key = "SHADOW_PROT", name = "Shadow Protection", alt = { "Prayer of Shadow Protection" }, defaultClasses = {},
			                icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
			INNER_FIRE  = { key = "INNER_FIRE", selfOnly = true, name = "Inner Fire", icon = "Interface\\Icons\\Spell_Holy_InnerFire" },
		},
		selfCategories = {
			{ key = "FIRE", title = "Inner Fire", default = "INNER_FIRE", choices = { "INNER_FIRE" } },
		},
	},
}

-- Each buff knows its position in the caster's order (used to keep one person's buffs in order). The
-- caster's own buffs sort BEFORE everything else (negative index, in category order). `all` lists every
-- buff key (others first, then own) for spell resolution and the debug report.
for _, caster in pairs(ns.CasterData) do
	caster.selfCategories = caster.selfCategories or {}
	caster.all = {}
	for i, key in ipairs(caster.order) do caster.buffs[key].index = i; caster.all[#caster.all + 1] = key end
	local n = -1000
	for _, cat in ipairs(caster.selfCategories) do
		local keys = {}
		for _, key in ipairs(cat.auto or {}) do keys[#keys + 1] = key end
		for _, key in ipairs(cat.choices) do keys[#keys + 1] = key end
		for _, key in ipairs(keys) do
			n = n + 1
			caster.buffs[key].index = n
			caster.all[#caster.all + 1] = key
		end
	end
end

-- Default blessing per target class (all editable in settings). "NONE" skips the class.
ns.DefaultAssign = {
	WARRIOR = "MIGHT", ROGUE = "MIGHT",
	HUNTER = "WISDOM", PALADIN = "WISDOM", PRIEST = "WISDOM", SHAMAN = "WISDOM",
	MAGE = "WISDOM", WARLOCK = "WISDOM", DRUID = "WISDOM",
}

-- Does this character's class have buffs in WellMet? If not, no other file does anything.
ns.supported = ns.CasterData[select(2, UnitClass("player"))] ~= nil
