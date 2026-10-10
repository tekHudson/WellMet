--[[ WellMet — buff requests (beta): players tell you in chat which buff they want, and it is remembered.

A player writes "!bom" (or "!fort", "!ai" ... the words are each buff's `tags` in Data/Classes.lua) in party or raid
chat, or whispers it to you. That replaces your class default for THAT person: the key buffs them with what they
asked for. "!none" = no buff from you, "!default" = back to the class default. Requests are stored in the saved
variables, per caster class (a Paladin's "!bom" means nothing to a Mage), until the person changes it or you clear
them (settings, or /wellmet requests clear).

Off by default (settings > Buff requests (beta)). While it is off nothing is listened to and saved requests are
ignored. Forever hides chat text, sender and guid during a chat messaging lockdown (an encounter, a Mythic+ run,
a PvP match), so a message in that time is ignored; requests already saved still work.

Parse / Set / Describe are pure (no WoW API) so they are tested headless.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local Requests = {}
ns.Requests = Requests

local EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }
local NONE_WORDS    = { none = true, skip = true, no = true, off = true }
local DEFAULT_WORDS = { default = true, clear = true, reset = true, auto = true }

-- What a chat line asks for. Returns nil (not a request), or "set", buffKey / "none" / "clear".
function Requests.Parse(caster, text)
	if type(text) ~= "string" then return nil end
	local body = text:match("^%s*!(.*)$")
	if not body then return nil end
	body = body:lower():gsub("^%s*buff%s+", "")
	local word = body:match("^%s*([%w_]+)")
	if not word then return nil end
	if NONE_WORDS[word] then return "none" end
	if DEFAULT_WORDS[word] then return "clear" end
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		if word == key:lower() then return "set", key end
		for _, tag in ipairs(buff.tags or {}) do
			if word == tag then return "set", key end
		end
	end
	return nil
end

-- Store / change / clear one player's request in `list`. buffKey: a buff key, "NONE", or nil to clear.
function Requests.Set(list, guid, name, class, buffKey, now)
	if buffKey == nil then list[guid] = nil; return end
	list[guid] = { buff = buffKey, name = name, class = class, at = now }
end

function Requests.Count(list)
	local n = 0
	for _ in pairs(list or {}) do n = n + 1 end
	return n
end

-- A request in words, e.g. "Blessing of Might" / "no buff from you".
function Requests.Describe(caster, req)
	if req.buff == "NONE" then return "no buff from you" end
	local buff = caster.buffs[req.buff]
	return buff and buff.name or ("unknown buff " .. ns.SafeStr(req.buff))
end

-- The line the announce sends: the first tag of each buff a player can ask for.
function Requests.AnnounceText(caster)
	local tags = {}
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		tags[#tags + 1] = "!" .. ((buff.tags and buff.tags[1]) or key:lower())
	end
	return "WellMet: tell me your buff in chat or by whisper: " .. table.concat(tags, " ") .. "  (!none = no buff, !default = reset)"
end

-- This caster's saved requests, whatever the setting.
function Requests.List()
	local all = WM.db.requests.list
	all[WM.classToken] = all[WM.classToken] or {}
	return all[WM.classToken]
end

-- The requests Select should honor: nil while the feature is off.
function Requests.Active()
	if not WM.db.requests.enabled then return nil end
	return Requests.List()
end

local function readable(v) return v ~= nil and not issecretvalue(v) end

-- A chat line arrived. `...` is what follows text and sender in a CHAT_MSG_* event (the guid is the tenth).
function Requests.OnChat(event, text, sender, ...)
	if not WM.db.requests.enabled then return end
	local guid = select(10, ...)
	if not (readable(text) and readable(sender) and readable(guid)) then
		WM:Log("request ignored: chat text / sender / guid is hidden right now (" .. event .. ")")
		return
	end
	local kind, key = Requests.Parse(WM.caster, text)
	if not kind then return end
	if guid == UnitGUID("player") then return end           -- your own line (an announce echoing back)
	local _, class = GetPlayerInfoByGUID(guid)
	local list = Requests.List()
	local name = (tostring(sender):gsub("%-.*$", ""))
	if kind == "clear" then
		Requests.Set(list, guid, name, class, nil)
		WM:Print(name .. ": back to the default buff.")
		WM:Log("request: " .. name .. " cleared")
	else
		local buffKey = (kind == "none") and "NONE" or key
		Requests.Set(list, guid, name, class, buffKey, time())
		WM:Print(name .. " asked for: " .. Requests.Describe(WM.caster, list[guid]) .. ".")
		WM:Log("request: " .. name .. " -> " .. buffKey .. " via " .. event)
	end
	if WM.refreshOptions then WM.refreshOptions() end
end

local frame = CreateFrame("Frame")
ns.requestFrame = frame
frame:SetScript("OnEvent", function(_, event, text, sender, ...) Requests.OnChat(event, text, sender, ...) end)

-- Listen to chat only while the setting is on (called at login and when it changes).
function WM:ApplyRequests()
	for _, e in ipairs(EVENTS) do
		if WM.db.requests.enabled then frame:RegisterEvent(e) else frame:UnregisterEvent(e) end
	end
end

-- Say how to ask, in party or raid chat. Only ever on your click / command, never by itself.
function WM:Announce()
	if not WM.db.requests.enabled then
		WM:Print("Turn on 'Listen for buff requests (beta)' in /wellmet first.")
		return false
	end
	local channel
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
	elseif IsInRaid() then channel = "RAID"
	elseif IsInGroup() then channel = "PARTY" end
	if not channel then
		WM:Print("You are not in a group.")
		return false
	end
	local locked = C_ChatInfo.InChatMessagingLockdown()
	if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then locked = locked or C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() end
	if locked then
		WM:Print("Can't announce right now: the game blocks addon chat during an encounter, Mythic+ or a PvP match.")
		return false
	end
	SendChatMessage(Requests.AnnounceText(WM.caster), channel)
	WM:Log("announce sent to " .. channel)
	return true
end

-- Slash: /wellmet requests (list) | /wellmet requests clear
function WM:RequestsCommand(arg)
	local list = Requests.List()
	if arg:lower() == "clear" then
		WM:ClearRequests()
		WM:Print("forgot all saved buff requests")
		return
	end
	WM:Print("Buff requests (beta) are " .. (WM.db.requests.enabled and "ON" or "OFF") .. ": " .. Requests.Count(list) .. " saved.")
	for guid, req in pairs(list) do
		WM:Print("  " .. ns.SafeStr(req.name) .. (req.class and (" (" .. req.class .. ")") or "") .. ": " .. Requests.Describe(WM.caster, req))
	end
end

function WM:ClearRequests()
	local list = Requests.List()
	for guid in pairs(list) do list[guid] = nil end
	if WM.refreshOptions then WM.refreshOptions() end
end
