--[[ WellMet — saved variables with a tiny recursive defaults merge. ]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

-- Three independent sections, one per kind of target. Each has its own on/off, its own buff choices, and
-- (party / others) its own search radius. Self is on, Party/Raid is on, Others (strangers) is off until you
-- turn it on.
--   assign: Paladin: target class -> buff key ("NONE" skips); the 1st choice; a class with no slot set uses ns.DefaultPrio
--   stack:  Mage / Druid: buff key -> { target class -> true/false }; falls back to the buff's defaultClasses
--   assign2..assign5: Paladin: the 2nd .. 5th choice per target class, used when the earlier ones are not learned or already on them from someone else
--            from someone else; "NONE" / missing = no fallback
--   choice: (self only) own-buff category key -> buff key | "AUTO" | "NONE"; falls back to the category's default
-- For the Self section the "target class" is your own class (the buff you cast on yourself).
ns.SECTIONS = { "self", "party", "others" }
ns.SECTION_OF_TIER = { [0] = "self", [1] = "party", [2] = "others" }

local DEFAULTS = {
	schema       = 2,
	allowMounted = false,      -- refuse to cast while mounted (casting would dismount you)
	skipPvP      = true,       -- don't buff a PvP-flagged player while you are not flagged (buffing one would flag you too)
	minimap      = { hide = false, angle = 200 },   -- minimap button: hidden?, position around the minimap (degrees)
	strip        = { enabled = false, onlyWhenMissing = false, point = "TOP", x = 0, y = -140 },   -- the Self / Group reminder strip: shown?, draw only the icons that need a buff?, where
	refresh      = { enabled = true, percent = 20 },   -- buff people whose buff is running out: when this share of its time is left
	castOnTarget = { enabled = true },    -- a player you target by hand is buffed even if their buff has plenty of time left
	buffBack     = { enabled = true },    -- whoever just buffed you (last 10 s) is buffed first, if they need it
	requests     = { enabled = true, list = {} },    -- what players asked for in chat: list[casterClass][guid] = { buff, name, class, at }
	rankTest     = {},         -- /wellmet ranktest results: class -> target level -> which ranks were refused / accepted
	debug        = false,      -- record the /wellmet log and show press-time chat messages
	self   = { enabled = true,  choice = {}, assign = {}, assign2 = {}, assign3 = {}, assign4 = {}, assign5 = {}, stack = {} },
	party  = { enabled = true,  radius = 0,  assign = {}, assign2 = {}, assign3 = {}, assign4 = {}, assign5 = {}, stack = {} },    -- radius 0 = the buff's own cast range, else 10 or 28 yards
	others = { enabled = false, radius = 0,  assign = {}, assign2 = {}, assign3 = {}, assign4 = {}, assign5 = {}, stack = {} },    -- assign..assign5: Paladin blessings per target class, in order (1st, 2nd, ...)
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

-- Paladin blessings per target class are an ORDERED list: assign (1st), assign2 .. assign5. A class that has no slot set
-- at all uses ns.DefaultPrio; once any slot is set the class uses exactly the slots as saved ("NONE" / nil = empty).
ns.PRIO_FIELDS = { "assign", "assign2", "assign3", "assign4", "assign5" }

local function slotOf(field)
	for n, f in ipairs(ns.PRIO_FIELDS) do if f == field then return n end end
end

local function customised(cfg, class)
	for _, f in ipairs(ns.PRIO_FIELDS) do
		if cfg[f] and cfg[f][class] ~= nil then return true end
	end
	return false
end

-- The key in slot n for a class ("NONE" when empty).
function ns.PrioSlot(cfg, class, n)
	local f = ns.PRIO_FIELDS[n]
	if customised(cfg, class) then return (cfg[f] and cfg[f][class]) or "NONE" end
	local def = ns.DefaultPrio[class]
	return (def and def[n]) or "NONE"
end

-- The class's blessings in order: empties and repeats dropped (a list of keys; empty = skip this class).
function ns.PrioList(cfg, class)
	local list, seen = {}, {}
	for n = 1, #ns.PRIO_FIELDS do
		local key = ns.PrioSlot(cfg, class, n)
		if key ~= "NONE" and not seen[key] then seen[key] = true; list[#list + 1] = key end
	end
	return list
end

-- Put `key` in slot n for a class. A key already in another slot swaps places with it, so nothing appears twice.
function ns.PrioSet(cfg, class, n, key)
	local vals = {}
	for i = 1, #ns.PRIO_FIELDS do vals[i] = ns.PrioSlot(cfg, class, i) end      -- freezes the defaults the first time a class is edited
	if key ~= "NONE" then
		for i = 1, #vals do
			if i ~= n and vals[i] == key then vals[i] = vals[n] end
		end
	end
	vals[n] = key
	for i, f in ipairs(ns.PRIO_FIELDS) do
		cfg[f] = cfg[f] or {}
		cfg[f][class] = vals[i]
	end
end

-- "Set all classes" (Party / Raid and Others pages). All of these act on every class in ns.TargetClasses at once.
-- Assign mode (Paladin): `field` is "assign" (1st choice), "assign2" (2nd) ... "assign5".
-- How many classes have `key` in that slot ("NONE" counts the empty ones).
function ns.AssignCount(cfg, field, key)
	local n, slot = 0, slotOf(field)
	for _, class in ipairs(ns.TargetClasses) do
		if ns.PrioSlot(cfg, class, slot) == key then n = n + 1 end
	end
	return n
end

-- Click on a blessing: every class gets it in that slot. When every class already has it there, the click empties the slot instead.
-- (Clicking "none" when everything is already none changes nothing.)
function ns.SetAllAssign(cfg, field, key)
	local target, slot = key, slotOf(field)
	if key ~= "NONE" and ns.AssignCount(cfg, field, key) == #ns.TargetClasses then target = "NONE" end
	for _, class in ipairs(ns.TargetClasses) do ns.PrioSet(cfg, class, slot, target) end
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
	return ns.PrioSlot(section, class, 1)
end
