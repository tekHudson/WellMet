--[[ WellMet — saved variables with a tiny recursive defaults merge. ]]

local ADDON, ns = ...
local WM = ns.WM

local DEFAULTS = {
	radius       = 0,          -- 0 = the buff's own cast range, else 10 or 28 yards
	strangers    = true,       -- include players outside the group (needs friendly nameplates)
	groupFirst   = true,       -- group members before strangers
	includeSelf  = true,       -- buff yourself too (first)
	allowMounted = false,      -- refuse to cast while mounted (casting would dismount you)
	unknownClass = "WISDOM",   -- blessing for targets whose class can't be read
	minimap      = { hide = false, angle = 200 },   -- minimap button: hidden?, position around the minimap (degrees)
	debug        = false,      -- record the /wellmet log and show press-time chat messages
	assign       = {},         -- target class -> buff key ("NONE" skips); falls back to ns.DefaultAssign
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

-- The buff key assigned to a target class (nil class = unreadable class).
function ns.AssignedKey(class)
	if not class then return WM.db.unknownClass end
	return WM.db.assign[class] or ns.DefaultAssign[class]
end
