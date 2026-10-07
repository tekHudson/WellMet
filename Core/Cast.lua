--[[ WellMet — the cast button, the key press, and what happens after the cast.

One secure button, `WellMetCast`. A key press (or `/click WellMetCast`) fires its
PreClick: out of combat we discover who is around, pick the best target
(Core/Select.lua) and set the button's `spell` / `unit` attributes, and the secure
click that follows casts it. Attributes can't change in combat, so in combat the
press just says so.

Afterwards the cast events tell us what happened: UNIT_SPELLCAST_SENT confirms an
attempt (the target goes into the "just tried" memory, so the next press moves on),
and UI_ERROR_MESSAGE (out of range, line of sight, a stronger buff already there)
puts that target on a longer skip.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local BUTTON_NAME = "WellMetCast"
local CLICK_ACTION = "CLICK " .. BUTTON_NAME .. ":LeftButton"

local TRIED_SECONDS    = 8     -- skip someone we just cast on (until the aura shows)
local FAILED_SECONDS   = 5     -- out of range: people move
local LOS_SECONDS      = 20    -- line of sight: someone behind a wall usually stays behind it
local LOS_REPEAT_SECONDS = 60  -- ...and when the same person fails line of sight again soon after
local LOS_REPEAT_WINDOW  = 120
local QUEUE_WINDOW     = 0.4   -- a press this close to the end of the cooldown goes through (the game queues it)
local STRONGER_SECONDS = 300   -- a stronger buff from someone else is already on them
local DEBOUNCE         = 0.15

----------------------------------------------------------------------
-- The secure button (created at load so the binding / macro always finds it)
----------------------------------------------------------------------
local button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
button:SetSize(1, 1)
button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -64, -64)
button:SetAlpha(0)
button:RegisterForClicks("AnyDown", "AnyUp")
ns.castButton = button

local lastPress = 0

local function clearArm(b)
	b:SetAttribute("type", nil)
	b:SetAttribute("spell", nil)
	b:SetAttribute("unit", nil)
	b:SetAttribute("macrotext", nil)
end

-- The buff names for the "Nobody nearby needs ..." message. A stack caster only lists buffs that are
-- switched on for at least one target class in a section that is on.
local function names(caster)
	local list = {}
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		local used = false
		for _, sectionKey in ipairs(ns.SECTIONS) do
			local section = WM.db[sectionKey]
			if section.enabled and not (buff.partyOnly and sectionKey == "others") then
				for _, class in ipairs(ns.TargetClasses) do
					if caster.mode == "stack" then
						used = used or ns.StackEnabled(buff, class, section.stack)
					else
						used = used or ns.AssignedKey(section, class) == key
					end
				end
			end
		end
		if used then list[#list + 1] = buff.name end
	end
	return table.concat(list, " / ")
end

-- Called from PreClick. `b` is the secure button.
-- `fromMacro`: the click was an up with no down before it, i.e. a `/click WellMetCast` macro.
function WM:OnPress(b, fromMacro)
	local now = GetTime()
	if now - lastPress < DEBOUNCE then
		WM:Log("press ignored: debounce (second event for the same press)")
		return
	end
	lastPress = now

	if InCombatLockdown() then
		WM:Note("Can't buff in combat.")
		WM:Log("press blocked: in combat")
		return
	end
	clearArm(b)

	if UnitOnTaxi("player") or IsFlying() then
		WM:Note("Not while flying.")
		WM:Log("press blocked: flying / on taxi")
		return
	end
	if IsMounted() and not WM.db.allowMounted then
		WM:Note("Dismount first (casting would dismount you). You can change this in /wellmet.")
		WM:Log("press blocked: mounted")
		return
	end

	local cands, rejected, info = ns.Discovery.Discover()
	local ctx = { now = now, settings = WM.db, caster = WM.caster, probe = ns.Probe }
	local best, skipped = ns.Select.Pick(cands, ctx)
	WM.lastPick = { best = best, skipped = skipped, rejected = rejected, info = info, at = now, cands = cands }

	if not best then
		local list = names(WM.caster)
		local msg = (list ~= "") and ("Nobody nearby needs " .. list .. ".") or "Nothing needs buffing right now."
		if not ns.AurasReadable() then
			msg = "Buff info is restricted right now (combat or an encounter), so WellMet can't tell who needs a buff."
		elseif WM.db.others.enabled and ns.Discovery.NameplatesOn() == false then
			msg = msg .. " Friendly player nameplates are OFF, so only your group can be found (turn them on in /wellmet)."
		end
		WM:Note(msg)
		WM:Log("press: no target.", #cands, "candidates,", #skipped, "skipped,", info.nameplates, "nameplates")
		return
	end

	local cand, buff = best.cand, best.buff
	-- Mashing the key during the global cooldown only produces "Spell is not ready yet" and re-targets for nothing,
	-- so do nothing until the cooldown is nearly over.
	local wait = ns.CooldownLeft(buff)
	if wait and wait > QUEUE_WINDOW then
		WM:Log("press ignored:", buff.name, "is on cooldown", string.format("(%.1fs left)", wait))
		return
	end
	if cand.fullName and fromMacro then
		-- Strangers are targeted by a secure macro, and the client won't run a macro from inside
		-- a `/click` macro (a bound key works). Say so instead of silently doing nothing.
		WM:Note("Strangers can only be buffed with the bound key, not a /click macro. Group members still work from the macro.")
		WM:Log("press blocked: stranger " .. ns.SafeStr(cand.name) .. " from a /click macro")
		return
	end
	if cand.fullName then
		-- A `nameplateN` unit token can't be cast on or targeted from here: the client silently
		-- drops it (no event, no error), as a spell attribute, a [@nameplateN] conditional and
		-- /target nameplateN alike. Strangers are targeted by their full name instead (the way
		-- NearbyBuff does it); /cleartarget first so a failed lookup can't cast on your old target.
		b:SetAttribute("type", "macro")
		b:SetAttribute("macrotext", "/stopmacro [combat]\n/cleartarget\n/targetexact " .. cand.fullName
			.. "\n/cast [@target,exists,help,nodead] " .. buff.name)
	else
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", buff.name)
		b:SetAttribute("unit", cand.unit)
	end
	WM.pending = { key = cand.key, spell = buff.name, unit = cand.unit, name = cand.name, at = now }
	WM:Log("press: armed", buff.name, "on", cand.name, "(" .. cand.unit .. ",", "tier " .. cand.tier .. ",",
		"dist " .. ns.SafeStr(best.dist ~= math.huge and best.dist or "?") .. ")" .. (best.note and (" - " .. best.note) or ""))
end

-- A bound key sends down then up; `/click WellMetCast` sends only up. The secure handler
-- acts on key-down only when `useOnKeyDown` is true (SecureTemplates.lua), so we set it per
-- click: act on a down, ignore the up that follows it, act on an up that has no down before.
local keyIsDown = false
button:SetScript("PreClick", function(self, mouseButton, down)
	WM:Log("click: PreClick", ns.SafeStr(mouseButton), "down=" .. ns.SafeStr(down))
	local previousDown = keyIsDown
	local release = (not down) and previousDown
	keyIsDown = down and true or false
	if not InCombatLockdown() then self:SetAttribute("useOnKeyDown", (down or release) and true or false) end
	if release then
		WM:Log("click: key release after a down press, ignored")
		return
	end
	WM:OnPress(self, not down)      -- an up that isn't the end of a key press = /click macro
end)
-- After the secure handler ran: what it was armed with (type nil = nothing will cast)
button:SetScript("PostClick", function(self, mouseButton, down)
	WM:Log("click: PostClick", ns.SafeStr(mouseButton), "down=" .. ns.SafeStr(down),
		"type=" .. ns.SafeStr(self:GetAttribute("type")), "spell=" .. ns.SafeStr(self:GetAttribute("spell")),
		"unit=" .. ns.SafeStr(self:GetAttribute("unit")), "macro=" .. ns.SafeStr(self:GetAttribute("macrotext")))
	if self:GetAttribute("macrotext") then
		C_Timer.After(0.3, function()
			WM:Log("click: +0.3s target exists=" .. ns.SafeStr(UnitExists("target")), "name=" .. ns.SafeStr(UnitName("target")),
				"casting=" .. ns.SafeStr((UnitCastingInfo("player"))))
		end)
	end
	local unit, spell = self:GetAttribute("unit"), self:GetAttribute("spell")
	if not unit and self:GetAttribute("macrotext") then
		local text = self:GetAttribute("macrotext")
		unit, spell = "target", text:match("/cast %[[^%]]*%] ([^\n]+)")
	end
	if unit and spell then
		WM:Log("click: state", "exists=" .. ns.SafeStr(UnitExists(unit)), "visible=" .. ns.SafeStr(UnitIsVisible(unit)),
			"inRange=" .. ns.SafeStr(C_Spell.IsSpellInRange(spell, unit)), "usable=" .. ns.SafeStr((C_Spell.IsSpellUsable(spell))),
			"targeting=" .. ns.SafeStr(SpellIsTargeting()), "gcd=" .. ns.SafeStr((C_Spell.GetSpellCooldown(spell) or {}).duration))
	end
	-- The action has run by now. Disarm, so a later press in combat (when attributes can't be changed, and
	-- OnPress refuses) cannot repeat a stale cast on a stale unit.
	if not InCombatLockdown() then clearArm(self) end
end)

----------------------------------------------------------------------
-- After the cast
----------------------------------------------------------------------
local function failureKind(message)
	if message == nil then return nil end
	if message == _G.SPELL_FAILED_AURA_BOUNCED then return "stronger" end
	if message == _G.SPELL_FAILED_LINE_OF_SIGHT or message == _G.SPELL_FAILED_VISION_OBSCURED then return "los" end
	if message == _G.SPELL_FAILED_OUT_OF_RANGE or message == _G.ERR_OUT_OF_RANGE then return "range" end
	return nil
end
ns.FailureKind = failureKind

local castFrame = CreateFrame("Frame")
ns.castFrame = castFrame

local function pendingRecent()
	local p = WM.pending
	if p and GetTime() - p.at < 4 then return p end
end
ns.PendingRecent = pendingRecent

local function onSent(_, _, castGUID, spellID)
	local p = pendingRecent()
	if not p or ns.SpellName(spellID) ~= p.spell then return end
	p.sent, p.castGUID = true, castGUID
	ns.Select.Mark(p.key, p.spell, TRIED_SECONDS)
	WM:Log("cast sent:", p.spell, "->", p.name)
end

local function onSucceeded(_, castGUID)
	local p = WM.pending
	if not p or not p.sent or p.castGUID ~= castGUID then return end
	WM:Note("Buffed " .. ns.SafeStr(p.name) .. " with " .. p.spell .. ".")
	WM:Log("cast ok:", p.spell, "->", p.name)
	WM.pending = nil
end

local losFails = {}          -- target key -> time of its last line-of-sight failure
function ns.ForgetFailures() for k in pairs(losFails) do losFails[k] = nil end end

local function onError(_, message)
	local p = pendingRecent()
	local kind = failureKind(message)
	if not p or not kind then return end
	local seconds = FAILED_SECONDS
	if kind == "stronger" then
		seconds = STRONGER_SECONDS
	elseif kind == "los" then
		local last = losFails[p.key]
		local now = GetTime()
		seconds = (last and now - last < LOS_REPEAT_WINDOW) and LOS_REPEAT_SECONDS or LOS_SECONDS
		losFails[p.key] = now
	end
	ns.Select.Mark(p.key, p.spell, seconds)
	WM:Log("cast failed:", ns.SafeStr(message), "-> skipping", p.name, "for", seconds .. "s")
	WM.pending = nil
end

function ns.SpellName(spellID)
	return spellID and C_Spell.GetSpellName(spellID) or nil
end

castFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "UNIT_SPELLCAST_SENT" then
		local _, target, castGUID, spellID = ...
		onSent(target, nil, castGUID, spellID)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, castGUID = ...
		onSucceeded(nil, castGUID)
	elseif event == "UI_ERROR_MESSAGE" then
		local errorType, message = ...
		if pendingRecent() then WM:Log("evt UI_ERROR_MESSAGE", ns.SafeStr(errorType), ns.SafeStr(message)) end
		onError(nil, message)
	elseif event == "PLAYER_TARGET_CHANGED" then
		if pendingRecent() then WM:Log("evt PLAYER_TARGET_CHANGED exists=" .. ns.SafeStr(UnitExists("target")), "name=" .. ns.SafeStr(UnitName("target"))) end
	else
		-- UNIT_SPELLCAST_FAILED / FAILED_QUIET / INTERRUPTED: why a cast died after it started
		if pendingRecent() then WM:Log("evt", event, ns.SafeStr(select(2, ...)), ns.SafeStr(select(3, ...)), ns.SafeStr(select(4, ...))) end
	end
end)

----------------------------------------------------------------------
-- Keybind: the action is declared in Bindings.xml, so the key is chosen in Blizzard's own
-- Key Bindings window (under "WellMet"). These globals must exist when that window builds.
----------------------------------------------------------------------
_G.BINDING_HEADER_WELLMET = "WellMet"
-- "(WellMet)" is in the name on purpose: the Key Bindings search matches words in binding names only, so
-- searching "WellMet" finds exactly this binding (see WM:OpenKeyBindings).
_G["BINDING_NAME_" .. CLICK_ACTION] = "Buff the next nearby player (WellMet)"
ns.CLICK_ACTION = CLICK_ACTION

----------------------------------------------------------------------
-- Init (PLAYER_LOGIN)
----------------------------------------------------------------------
function WM:InitCast()
	for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
		castFrame:RegisterUnitEvent(e, "player")
	end
	castFrame:RegisterEvent("UI_ERROR_MESSAGE")
	castFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
end
