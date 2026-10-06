--[[ WellMet — chat probe (temporary diagnostic).

Question it answers: can the addon READ party / raid chat and SEND a line to the group, and from which
kind of action? The planned "ask for the buffs you want in party chat" feature depends on both:
  - CHAT_MSG_* text, sender and guid are secret values in "chat messaging lockdown" (encounters, Mythic+,
    PvP matches, and inside dungeons and raids), so reading may only work in the open world.
  - C_ChatInfo.SendChatMessage is flagged RestrictedForMacroChatMessages, so sending from inside a macro
    may be refused even where a typed command works.

Use (everything it learns goes to /wellmet log, which this turns on):
  /wellmet probe          start / stop listening to party, raid and instance chat
  /wellmet probe send     send one test line to your group from this slash command
  /wellmet probe press    the NEXT press of the key or the macro sends one test line to your group
Then /wellmet log and read the lines starting with "probe".
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local EVENTS = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }

local frame = CreateFrame("Frame")
local listening, armed = false, false

-- A value for the log: "SECRET" when the game hides it, else its text (cut to 60 characters).
local function shown(value)
	if issecretvalue(value) then return "SECRET" end
	local text = ns.SafeStr(value)
	return (#text > 60) and (text:sub(1, 60) .. "...") or text
end

-- Everything that decides whether chat is readable / sendable right now.
local function state()
	local inInstance, instanceType = IsInInstance()
	return string.format("lockdown=%s instance=%s(%s) group=%s raid=%s", ns.SafeStr(C_ChatInfo.InChatMessagingLockdown()),
		ns.SafeStr(inInstance), ns.SafeStr(instanceType), ns.SafeStr(IsInGroup()), ns.SafeStr(IsInRaid()))
end

-- payload: text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex,
-- channelBaseName, languageID, lineID, guid, ...
frame:SetScript("OnEvent", function(_, event, text, sender, _, _, _, _, _, _, _, _, _, guid)
	WM:Log("probe chat", event, "text=" .. shown(text), "sender=" .. shown(sender), "guid=" .. shown(guid), state())
end)

local function channel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end

-- Send one test line to the group and log what happened. `origin` says what triggered it.
function WM:ProbeSend(origin)
	local chatType = channel()
	if not chatType then
		WM:Log("probe send", origin, "not in a group", state())
		WM:Print("Join a party or raid first, then try again.")
		return false
	end
	local ok, err = pcall(C_ChatInfo.SendChatMessage, "[WellMet] chat probe (" .. origin .. ")", chatType)
	WM:Log("probe send", origin, chatType, ok and "ok" or ("ERROR " .. ns.SafeStr(err)), state())
	return ok
end

-- A press of the key (down) or the /click macro (up with no down before) while armed: send from there.
if ns.castButton then
	ns.castButton:HookScript("PreClick", function(_, _, down)
		if not armed then return end
		armed = false
		WM:ProbeSend(down and "key press" or "macro press")
	end)
end

-- /wellmet probe [send | press]
function WM:Probe(arg)
	WM.db.debug = true                                    -- the probe's findings are log lines
	arg = (arg or ""):lower()
	if arg == "send" then
		WM:ProbeSend("slash command")
		WM:Print("Probe: sent from a slash command. See /wellmet log.")
	elseif arg == "press" then
		armed = true
		WM:Print("Probe: the next press of the key or the macro will send one test line to your group.")
	else
		listening = not listening
		for _, event in ipairs(EVENTS) do
			if listening then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
		end
		WM:Log("probe", listening and "listening" or "stopped", state())
		if listening then
			WM:Print("Chat probe ON (debug is on too). Ask a group member to type something, then try /wellmet probe send and /wellmet probe press, then /wellmet log.")
		else
			WM:Print("Chat probe stopped.")
		end
	end
end
