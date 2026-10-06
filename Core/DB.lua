--[[ WellMet — saved variables with a tiny recursive defaults merge. ]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local DEFAULTS = {
	radius       = 0,          -- 0 = the buff's own cast range, else 10 or 28 yards
	strangers    = true,       -- include players outside the group (needs friendly nameplates)
	groupFirst   = true,       -- group members before strangers
	includeSelf  = true,       -- buff yourself too (first)
	allowMounted = false,      -- refuse to cast while mounted (casting would dismount you)
	minimap      = { hide = false, angle = 200 },   -- minimap button: hidden?, position around the minimap (degrees)
	debug        = false,      -- record the /wellmet log and show press-time chat messages
	assign       = {},         -- Paladin: target class -> buff key ("NONE" skips); falls back to ns.DefaultAssign
	selfChoice   = {},         -- own-buff category key -> buff key | "AUTO" | "NONE"; falls back to the category's default
	stack        = {},         -- Mage: buff key -> { target class -> true/false }; falls back to the buff's defaultClasses
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

function WM:InitDB()
	WellMetDB = WellMetDB or {}
	WellMetDB.profile = applyDefaults(WellMetDB.profile or {}, DEFAULTS)
	WM.db = WellMetDB.profile
end

-- Is a "stack" buff (Mage) switched on for this target class?
function ns.StackEnabled(buff, class, stack)
	local saved = stack and stack[buff.key]
	if saved and saved[class] ~= nil then return saved[class] end
	return buff.defaultClasses and buff.defaultClasses[class] or false
end

-- Switch a stack buff on/off for a class; switching one on switches off the buff it replaces.
function ns.StackSet(caster, buff, class, on)
	local stack = WM.db.stack
	stack[buff.key] = stack[buff.key] or {}
	stack[buff.key][class] = on and true or false
	if on and buff.exclusive then
		local other = caster.buffs[buff.exclusive]
		stack[other.key] = stack[other.key] or {}
		stack[other.key][class] = false
	end
end

-- The buff key assigned to a target class.
function ns.AssignedKey(class)
	return WM.db.assign[class] or ns.DefaultAssign[class]
end
