--[[ WellMet — bootstrap: shared namespace, logging, event dispatch, slash commands.

One key buffs the next nearby player who needs it (WoW Forever only). Press the
key (or `/click WellMetCast` from a macro) and the addon picks someone nearby who
lacks your buff and casts it; press again and it moves on to the next person.

Layout:
  Data/Classes.lua    which classes can buff whom (data, no logic)
  Core/DB.lua         saved variables + defaults
  Core/Spells.lua     spell/aura/range/distance probes (the only place that touches those APIs)
  Core/Discovery.lua  who is around: you, group, target, friendly nameplates
  Core/Select.lua     pure selection logic + "just tried" memory (unit-tested headless)
  Core/Cast.lua       the secure button, PreClick pick, keybind, cast feedback
  Core/Debug.lua      /wellmet log: copyable state dump + event log
  UI/Options.lua      Settings panel
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing

local WM = {}
_G.WellMet = WM
ns.WM = WM
ns.ADDON = ADDON

WM.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0"

----------------------------------------------------------------------
-- Debug log: a ring buffer that is filled ONLY while the debug setting is on (written on
-- key presses, picks and cast results). `/wellmet log` shows it. WM:Note is the same gate
-- for chat: press-time messages stay silent unless debug is on.
----------------------------------------------------------------------
local LOG_MAX = 500
local logbuf, logn = {}, 0

-- tostring that never throws (values can be unreadable secrets on Forever).
function ns.SafeStr(v)
	local ok, s = pcall(tostring, v)
	return ok and s or "<unreadable>"
end

function WM:Log(...)
	if not (WM.db and WM.db.debug) then return end
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = ns.SafeStr((select(i, ...))) end
	local line = string.format("%8.2f  %s", GetTime() % 100000, table.concat(parts, " "))
	logn = logn + 1
	logbuf[(logn - 1) % LOG_MAX + 1] = line
end

-- Log lines, oldest first.
function ns.LogLines()
	local out = {}
	for i = math.max(1, logn - LOG_MAX + 1), logn do out[#out + 1] = logbuf[(i - 1) % LOG_MAX + 1] end
	return out
end

function ns.ClearLog()
	logbuf, logn = {}, 0
end

local PREFIX = "|cff66ddffWellMet:|r "
function WM:Print(...)
	print(PREFIX .. strjoin(" ", tostringall(...)))
end

-- Chat message that only shows while debug is on (why a press did nothing, "Buffed ...").
function WM:Note(...)
	if WM.db and WM.db.debug then WM:Print(...) end
end

----------------------------------------------------------------------
-- Event dispatch: WM:RegisterEvent("X") -> calls WM:X(event, ...)
----------------------------------------------------------------------
local frame = CreateFrame("Frame", "WellMetEventFrame")
ns.eventFrame = frame
local registered = {}

function WM:RegisterEvent(event)
	if not registered[event] then
		registered[event] = true
		frame:RegisterEvent(event)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	local handler = WM[event]
	if handler then handler(WM, event, ...) end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

function WM:ADDON_LOADED(_, name)
	if name ~= ADDON then return end
	frame:UnregisterEvent("ADDON_LOADED")
	WM:InitDB()
end

function WM:PLAYER_LOGIN()
	WM.player = UnitName("player")
	WM.classToken = select(2, UnitClass("player"))
	WM.caster = ns.CasterData[WM.classToken]

	WM:InitSpells()
	WM:InitCast()
	WM:CreateOptions()
	WM:CreateMinimap()

	WM:RegisterEvent("SPELLS_CHANGED")
	WM:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	WM:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

	WM:SetupSlash()
	WM:Print("v" .. WM.version .. " loaded. /wellmet for settings.")
	if not GetBindingKey(ns.CLICK_ACTION) then
		WM:Print("No key set yet: bind one under Key Bindings > WellMet (/wellmet has a button for it).")
	end
end

function WM:SPELLS_CHANGED()
	WM:InitSpells()
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
function WM:SetupSlash()
	SLASH_WELLMET1 = "/wellmet"
	SLASH_WELLMET2 = "/wmet"
	SLASH_WELLMET3 = "/well"     -- NOT /wm: that is Blizzard's world-marker command (secure, parsed first)
	_G.SlashCmdList["WELLMET"] = function(msg)
		msg = (msg or ""):trim()
		local command, arg = msg:match("^(%S+)%s*(.-)$")
		command = (command or ""):lower()
		if command == "" or command == "config" or command == "settings" then
			WM:OpenOptions()
		elseif command == "log" or command == "why" or command == "diag" then
			if arg:lower() == "clear" then
				ns.ClearLog(); WM:Print("log cleared")
			else
				WM:ShowLog()
			end
		elseif command == "debug" then
			WM.db.debug = not WM.db.debug
			WM:Log("debug turned on")
			WM:Print("debug: " .. (WM.db.debug and "ON (recording the log, showing press messages)" or "OFF") .. "  (/wellmet log opens the copyable log)")
		elseif command == "forget" then
			ns.Select.Reset(); WM:Print("forgot who was recently tried")
		else
			WM:Print("/wellmet — settings | log (or why) — copyable report | log clear | forget | debug  (set the key under Key Bindings > WellMet)")
			WM:Print("Macro: /click WellMetCast")
		end
	end
end
