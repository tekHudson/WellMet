--[[ WellMet — saved variables with a tiny recursive defaults merge. ]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

-- Three independent sections, one per kind of target. Each has its own on/off, its own buff choices, and
-- (party / others) its own search radius. Self is on, Party/Raid is on, Others (strangers) is off until you
-- turn it on.
--   assign: Paladin: target class -> buff key ("NONE" skips); falls back to ns.DefaultAssign
--   stack:  Mage / Druid: buff key -> { target class -> true/false }; falls back to the buff's defaultClasses
--   assign2: (others only, Paladin) the SECONDARY blessing per target class, cast when a stranger already has the primary
--            from someone else; "NONE" / missing = no fallback
--   choice: (self only) own-buff category key -> buff key | "AUTO" | "NONE"; falls back to the category's default
-- For the Self section the "target class" is your own class (the buff you cast on yourself).
ns.SECTIONS = { "self", "party", "others" }
ns.SECTION_OF_TIER = { [0] = "self", [1] = "party", [2] = "others" }

local DEFAULTS = {
	schema       = 2,
	allowMounted = false,      -- refuse to cast while mounted (casting would dismount you)
	minimap      = { hide = false, angle = 200 },   -- minimap button: hidden?, position around the minimap (degrees)
	strip        = { enabled = false, onlyWhenMissing = false, point = "TOP", x = 0, y = -140 },   -- the Self / Group reminder strip: shown?, draw only the icons that need a buff?, where
	debug        = false,      -- record the /wellmet log and show press-time chat messages
	self   = { enabled = true,  choice = {}, assign = {}, stack = {} },
	party  = { enabled = true,  radius = 0,  assign = {}, stack = {} },    -- radius 0 = the buff's own cast range, else 10 or 28 yards
	others = { enabled = false, radius = 0,  assign = {}, assign2 = {}, stack = {} },    -- assign2: Paladin's fallback blessing per class, strangers only
}

local function applyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			applyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
	return target
end
ns.applyDefaults = applyDefaults

local function copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = (type(v) == "table") and copy(v) or v end
	return out
end

-- Settings from before the three sections (flat radius / strangers / assign / ...) become the three sections,
-- so an existing player keeps the same behavior: strangers stay on if they were on.
local function migrate(p)
	if p.schema == 2 then return end
	local old = p.strangers ~= nil or p.includeSelf ~= nil or p.radius ~= nil or p.assign ~= nil or p.stack ~= nil or p.selfChoice ~= nil
	if old then
		p.self   = { enabled = p.includeSelf ~= false, choice = copy(p.selfChoice), assign = copy(p.assign), stack = copy(p.stack) }
		p.party  = { enabled = true, radius = p.radius or 0, assign = copy(p.assign), stack = copy(p.stack) }
		p.others = { enabled = p.strangers ~= false, radius = p.radius or 0, assign = copy(p.assign), stack = copy(p.stack) }
	end
	for _, k in ipairs({ "radius", "strangers", "groupFirst", "includeSelf", "assign", "stack", "selfChoice", "unknownClass" }) do p[k] = nil end
	p.schema = 2
end

function WM:InitDB()
	WellMetDB = WellMetDB or {}
	local profile = WellMetDB.profile or {}
	migrate(profile)
	WellMetDB.profile = applyDefaults(profile, DEFAULTS)
	WM.db = WellMetDB.profile
end

-- The settings of the section a target tier belongs to (0 you, 1 group, 2 everyone else).
function ns.SectionFor(tier)
	return WM.db[ns.SECTION_OF_TIER[tier]]
end

-- Is a "stack" buff (Mage) switched on for this target class?
function ns.StackEnabled(buff, class, stack)
	local saved = stack and stack[buff.key]
	if saved and saved[class] ~= nil then return saved[class] end
	return buff.defaultClasses and buff.defaultClasses[class] or false
end

-- Switch a stack buff on/off for a class in one section's `stack` table; switching one on switches off the buff it replaces.
function ns.StackSet(caster, buff, class, on, stack)
	stack[buff.key] = stack[buff.key] or {}
	stack[buff.key][class] = on and true or false
	if on and buff.exclusive then
		local other = caster.buffs[buff.exclusive]
		stack[other.key] = stack[other.key] or {}
		stack[other.key][class] = false
	end
end

-- "Set all classes" (Party / Raid and Others pages). All of these act on every class in ns.TargetClasses at once.
-- Assign mode (Paladin): `field` is "assign" (the primary) or "assign2" (the stranger fallback).
local function assignValue(cfg, field, class)
	if field == "assign" then return ns.AssignedKey(cfg, class) end
	return cfg.assign2[class] or "NONE"
end

-- How many classes are set to `key` ("NONE" counts the skipped / no-fallback ones).
function ns.AssignCount(cfg, field, key)
	local n = 0
	for _, class in ipairs(ns.TargetClasses) do
		if assignValue(cfg, field, class) == key then n = n + 1 end
	end
	return n
end

-- Click on a blessing: every class gets it. When every class already has it, the click clears them all instead.
-- (Clicking "none" when everything is already none changes nothing.)
function ns.SetAllAssign(cfg, field, key)
	local target = key
	if key ~= "NONE" and ns.AssignCount(cfg, field, key) == #ns.TargetClasses then target = "NONE" end
	for _, class in ipairs(ns.TargetClasses) do cfg[field][class] = target end
end

-- Stack mode (Mage, Druid, Priest): how many classes have this buff switched on.
function ns.StackCount(buff, stack)
	local n = 0
	for _, class in ipairs(ns.TargetClasses) do
		if ns.StackEnabled(buff, class, stack) then n = n + 1 end
	end
	return n
end

-- Click on a buff: add it to every class, or remove it from every class when they all have it already.
function ns.SetAllStack(caster, buff, stack)
	local on = ns.StackCount(buff, stack) < #ns.TargetClasses
	for _, class in ipairs(ns.TargetClasses) do ns.StackSet(caster, buff, class, on, stack) end
end

-- The buff key a section assigns to a target class.
function ns.AssignedKey(section, class)
	return section.assign[class] or ns.DefaultAssign[class]
end
