--[[ WellMet — /wellmet log (alias why, diag): a copyable report.

Opens a window whose text is pre-selected: Ctrl+C, then paste it to whoever is
helping. The report has:
  * overview + settings
  * diagnostics: restriction state, nameplate CVar, API facts we depend on
  * "Right now": everyone WellMet can see and why each was picked or skipped
    (this is the "why didn't it buff X?" answer)
  * the always-on event log (presses, picks, casts, errors)
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local S = ns.SafeStr
local function yn(v) return v and "yes" or "no" end

----------------------------------------------------------------------
-- Raw cast / error events into the log (independent of Core/Cast.lua's logic)
----------------------------------------------------------------------
local evFrame = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
	pcall(evFrame.RegisterUnitEvent, evFrame, e, "player")
end
for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
	pcall(evFrame.RegisterEvent, evFrame, e)
end
-- Only WellMet's own casts (and anything right after one of its presses) belong in the log: everything else the
-- player casts (Smite, Skinning, Attack ...) just buries the useful lines. UI_ERROR_MESSAGE is logged by Core/Cast.lua.
local function isOurSpell(name)
	if not name or not WM.caster then return false end
	for _, buff in pairs(WM.caster.buffs) do
		if buff.name == name then return true end
	end
	return false
end
evFrame:SetScript("OnEvent", function(_, event, ...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = S((select(i, ...))) end
	if event:find("^UNIT_SPELLCAST") then
		local id = tonumber(parts[event == "UNIT_SPELLCAST_SENT" and 4 or 3])
		local name = id and ns.SpellName(id)
		if not (isOurSpell(name) or (ns.PendingRecent and ns.PendingRecent())) then return end
		if id then parts[#parts + 1] = "[" .. S(name) .. "]" end
	end
	WM:Log("evt", event, table.concat(parts, " "))
end)

----------------------------------------------------------------------
-- Chat probe: can WellMet read whispers, party and raid chat? (debug only)
--   Forever makes chat text, sender and guid secret during chat messaging lockdown (encounters, Mythic+, PvP,
--   dungeon / raid maps). This listens ONLY while debug is on and logs what could be read for each message, so a
--   chat feature can be designed from facts. It never records what anyone said: only whether the text, the sender
--   and the guid were readable, how long the text was, and whether it began with "!".
----------------------------------------------------------------------
local CHAT_EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" }
local chatStats = {}                 -- event -> { seen, text, sender, guid }: how many messages, and how many parts were readable
local chatFrame = CreateFrame("Frame")
ns.chatFrame = chatFrame

local function readable(v) return v ~= nil and not issecretvalue(v) end

chatFrame:SetScript("OnEvent", function(_, event, text, sender, ...)
	local guid = select(10, ...)                     -- text, sender, then language, channel, target, flags, zone id, index, base name, language id, line id, guid
	local textOk, senderOk, guidOk = readable(text), readable(sender), readable(guid)
	local st = chatStats[event] or { seen = 0, text = 0, sender = 0, guid = 0 }
	chatStats[event] = st
	st.seen = st.seen + 1
	if textOk then st.text = st.text + 1 end
	if senderOk then st.sender = st.sender + 1 end
	if guidOk then st.guid = st.guid + 1 end
	local what = "SECRET"
	if textOk then
		what = "readable len=" .. #text .. (text:sub(1, 1) == "!" and " starts-with-!" or "")
	end
	WM:Log("chat", event, "text=" .. what, "sender=" .. (senderOk and "readable" or "SECRET"), "guid=" .. (guidOk and "readable" or "SECRET"),
		"lockdown=" .. S(C_ChatInfo.InChatMessagingLockdown()), "combat=" .. yn(InCombatLockdown()))
end)

-- Listen to chat only while debug is on (called at login and whenever debug is switched).
function WM:ApplyChatProbe()
	for _, e in ipairs(CHAT_EVENTS) do
		if WM.db.debug then chatFrame:RegisterEvent(e) else chatFrame:UnregisterEvent(e) end
	end
end

local clearLog = ns.ClearLog
function ns.ClearLog()
	clearLog()
	for k in pairs(chatStats) do chatStats[k] = nil end
end

----------------------------------------------------------------------
-- Report sections
----------------------------------------------------------------------
local function section(out, title, fn)
	out[#out + 1] = ""
	out[#out + 1] = "== " .. title
	local ok, err = pcall(fn, function(line) out[#out + 1] = line end)
	if not ok then out[#out + 1] = "  !! error building this section: " .. S(err) end
end

local function candLine(c)
	return string.format("%-14s unit=%-12s tier=%s class=%s guid=%s", S(c.name), S(c.unit), S(c.tier), S(c.class), c.guid and "readable" or "UNREADABLE")
end

function WM:BuildReport()
	local out = { "WellMet report  " .. date("%Y-%m-%d %H:%M:%S") }
	local db = WM.db or {}

	section(out, "Overview", function(add)
		local version, build, _, toc = GetBuildInfo()
		add(string.format("addon %s (build %s) | client %s (%s) interface %s", S(WM.version), S(ns.BUILD), S(version), S(build), S(toc)))
		add(string.format("player=%s class=%s", S(WM.player), S(WM.classToken)))
		add(string.format("sections: self=%s  party/raid=%s (radius %s)  others=%s (radius %s)  allowMounted=%s",
			yn(db.self.enabled), yn(db.party.enabled), S(db.party.radius), yn(db.others.enabled), S(db.others.radius), yn(db.allowMounted)))
		add("debug=" .. yn(db.debug))
		add(string.format("inCombat=%s  mounted=%s  flying=%s  taxi=%s", yn(InCombatLockdown()), yn(IsMounted()), yn(IsFlying()), yn(UnitOnTaxi("player"))))
	end)

	section(out, "Diagnostics", function(add)
		add(string.format("auras readable: %s  (ShouldAurasBeSecret=%s, HasSecretRestrictions=%s)",
			yn(ns.AurasReadable()), yn(C_Secrets.ShouldAurasBeSecret()), yn(C_Secrets.HasSecretRestrictions())))
		add("friendly player nameplates (CVar nameplateShowFriendlyPlayers): " .. S(GetCVar("nameplateShowFriendlyPlayers")))
		local k1, k2 = GetBindingKey(ns.CLICK_ACTION)
		add(string.format("key (Key Bindings > WellMet): %s", k1 and (k1 .. (k2 and (", " .. k2) or "")) or "NOT SET"))
		add(string.format("failure strings: LOS=%s range=%s ERR_OUT_OF_RANGE=%s vision=%s bounced=%s",
			yn(_G.SPELL_FAILED_LINE_OF_SIGHT), yn(_G.SPELL_FAILED_OUT_OF_RANGE), yn(_G.ERR_OUT_OF_RANGE),
			yn(_G.SPELL_FAILED_VISION_OBSCURED), yn(_G.SPELL_FAILED_AURA_BOUNCED)))
		for _, key in ipairs(WM.caster.all) do
			local buff = WM.caster.buffs[key]
			add(string.format("buff %-14s %-24s id=%s known=%s", key, buff.name, S(ns.SpellId(buff)), yn(ns.IsKnown(buff))))
		end
	end)

	section(out, "Chat reading (debug probe: whispers, party, raid)", function(add)
		add(string.format("chat messaging lockdown right now: %s   (the probe only listens while debug is ON: %s)",
			S(C_ChatInfo.InChatMessagingLockdown()), yn(db.debug)))
		local any
		for _, e in ipairs(CHAT_EVENTS) do
			local st = chatStats[e]
			if st then
				any = true
				add(string.format("  %-24s %d seen: text readable %d, sender readable %d, guid readable %d", e, st.seen, st.text, st.sender, st.guid))
			end
		end
		if not any then add("  no chat messages seen yet. With debug on, send yourself a whisper or say something in party / raid, then reopen this.") end
	end)

	section(out, "Buff requests (beta)", function(add)
		local list = ns.Requests.List()
		add("listening for requests: " .. yn(db.requests.enabled) .. "   saved for " .. WM.classToken .. ": " .. ns.Requests.Count(list))
		for _, req in pairs(list) do
			add("  " .. ns.SafeStr(req.name) .. (req.class and (" (" .. req.class .. ")") or "") .. " -> " .. ns.Requests.Describe(WM.caster, req))
		end
	end)

	section(out, "Right now (what a key press would see)", function(add)
		local cands, rejected, info = ns.Discovery.Discover()
		add(string.format("%d candidates, %d rejected, %d nameplates visible", #cands, #rejected, info.nameplates))
		local ctx = { now = GetTime(), settings = db, caster = WM.caster, probe = ns.Probe, requests = ns.Requests.Active() }
		local best, skipped, eligible = ns.Select.Pick(cands, ctx)
		for i, e in ipairs(eligible) do
			add(string.format("  ELIGIBLE #%d  %s  -> %s  dist=%s%s", i, candLine(e.cand), e.buff.name,
				e.dist == math.huge and "?" or S(e.dist), (e == best) and "   <== next press" or ""))
		end
		for _, s in ipairs(skipped) do
			add(string.format("  skipped      %s  (%s)", candLine(s.cand), s.reason))
		end
		for _, r in ipairs(rejected) do
			add(string.format("  rejected     %-12s (%s)", S(r.unit), r.reason))
		end
		local recent = ns.Select.MemorySnapshot(GetTime())
		add("recently tried: " .. (#recent > 0 and table.concat(recent, ", ") or "nobody"))
	end)

	local log = ns.LogLines()
	out[#out + 1] = ""
	out[#out + 1] = "== Event log (oldest first; time is GetTime seconds)"
	if #log == 0 then
		out[#out + 1] = db.debug and "  (empty)" or "  (empty: debug is OFF, so nothing is recorded. Turn it on with /wellmet debug, press the key, then reopen this.)"
	end
	for _, l in ipairs(log) do out[#out + 1] = l end
	return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- Copyable window
----------------------------------------------------------------------
local W, H = 760, 500

local function buildWindow()
	local f = CreateFrame("Frame", "WellMetLogFrame", UIParent, "BackdropTemplate")
	f:SetSize(W, H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
	f:Hide()
	table.insert(UISpecialFrames, "WellMetLogFrame")

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("WellMet log - click in the text, Ctrl+A then Ctrl+C to copy")

	local sf = CreateFrame("ScrollFrame", "WellMetLogScroll", f, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 14, -38)
	sf:SetPoint("BOTTOMRIGHT", -34, 44)

	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true)
	eb:SetFontObject("ChatFontNormal")
	eb:SetWidth(W - 56)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(0)
	sf:SetScrollChild(eb)
	-- Read-only in effect: typing is reverted so the text stays accurate.
	eb:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self.orig and not self.restoring then
			self.restoring = true
			self:SetText(self.orig)
			self.restoring = false
		end
	end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
	f.edit = eb
	f.scroll = sf

	local function button(text, point, x, fn)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(110, 24)
		b:SetPoint(point, x, 14)
		b:SetText(text)
		b:SetScript("OnClick", fn)
		return b
	end
	button("Refresh", "BOTTOMLEFT", 16, function() WM:ShowLog() end)
	button("Clear log", "BOTTOMLEFT", 136, function()
		ns.ClearLog()
		WM:ShowLog(true)     -- jump to the bottom, where the (now empty) event log is
		WM:Print("log cleared")
	end)
	button("Close", "BOTTOMRIGHT", -16, function() f:Hide() end)
	return f
end

function WM:ShowLog(scrollToEnd)
	if not WM.logFrame then WM.logFrame = buildWindow() end
	local f = WM.logFrame
	local text = WM:BuildReport()
	f.edit.orig = text
	f.edit:SetText(text)
	f.edit:SetCursorPosition(0)
	f:Show()
	f.edit:SetFocus()
	f.edit:HighlightText()
	if scrollToEnd then
		-- the scroll range is only updated after the new text is laid out
		C_Timer.After(0, function() f.scroll:SetVerticalScroll(f.scroll:GetVerticalScrollRange()) end)
	end
end
