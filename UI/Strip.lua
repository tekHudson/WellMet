--[[ WellMet — the reminder strip: two action-button style icons, Self and Group, that say who still needs a buff.

An icon is lit (gold glowing edge) when someone it stands for needs a buff the key would cast right now (same rules
as a key press: in range, learned, section on, not just tried). Dark with a green check = everyone is covered.
Dark with a grey ? = can't tell (Forever hides other players' buffs in combat). Group is your party and your raid
together. An icon whose section is switched off (or Group when you are not in a group) is not drawn. Strangers
(Others) are not counted: they are only found when you press the key.

Off by default (settings > Buff reminder). With "only when a buff is missing" an icon is drawn only while it needs one.
Shift-drag moves it.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local INTERVAL = 1        -- seconds between looks while it is shown
local SIZE, GAP = 40, 6

-- One person / a group of people (the Looking-for-Group icons). Change the paths here to change the art.
local CHIPS = {
	{ key = "self",  label = "Self",  icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
	{ key = "group", label = "Group", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
}
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local GLOW_TEXTURE  = "Interface\\Buttons\\UI-ActionButton-Border"

-- The icons to show and what each says. Returns a list of { key, label, count, state }:
--   state "need" (count people need a buff), "ok" (nobody does), "unknown" (can't tell right now).
-- All the game's answers come through ns.Probe and Discovery, so this is testable headless.
function ns.StripModel()
	local db = WM.db
	local inGroup = IsInRaid() or GetNumGroupMembers() > 0
	local show = { self = db.self.enabled, group = db.party.enabled and inGroup }

	local readable = not InCombatLockdown() and ns.AurasReadable()
	local people = { self = {}, group = {} }
	if readable then
		local cands = ns.Discovery.Discover({ groupOnly = true })
		local ctx = { now = GetTime(), settings = db, caster = WM.caster, probe = ns.Probe, requests = ns.Requests.Active() }
		local _, _, eligible = ns.Select.Pick(cands, ctx)
		for _, e in ipairs(eligible) do
			people[e.cand.tier == 0 and "self" or "group"][e.cand.key] = true
		end
	end

	local model = {}
	for _, chip in ipairs(CHIPS) do
		if show[chip.key] then
			local n = 0
			for _ in pairs(people[chip.key]) do n = n + 1 end
			model[#model + 1] = {
				key = chip.key, label = chip.label, count = n,
				state = (not readable) and "unknown" or (n > 0 and "need" or "ok"),
			}
		end
	end
	return model
end

-- Which of the model's icons get drawn: all of them, or with "only when a buff is missing" just the ones that need one.
function ns.StripDrawn(model)
	if not WM.db.strip.onlyWhenMissing then return model end
	local missing = {}
	for _, m in ipairs(model) do if m.state == "need" then missing[#missing + 1] = m end end
	return missing
end

local strip, chips, driver
local elapsed = 0

local function build()
	strip = CreateFrame("Frame", "WellMetStrip", UIParent)
	strip:SetSize(SIZE, SIZE)
	strip:SetFrameStrata("MEDIUM")
	strip:SetClampedToScreen(true)
	strip:SetMovable(true)
	strip:EnableMouse(true)
	strip:RegisterForDrag("LeftButton")
	strip:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
	strip:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		local s = WM.db.strip
		if point then s.point, s.x, s.y = point, x, y end
	end)
	strip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("WellMet")
		for _, m in ipairs(WM.stripModel or {}) do
			local text = m.state == "need" and (m.count .. (m.count == 1 and " needs" or " need") .. " a buff")
				or m.state == "ok" and "everyone is covered" or "can't tell right now (combat)"
			GameTooltip:AddLine(m.label .. ": " .. text, 1, 1, 1)
		end
		GameTooltip:AddLine("Shift-drag to move.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	strip:SetScript("OnLeave", function() GameTooltip:Hide() end)

	chips = {}
	for _, chip in ipairs(CHIPS) do
		local f = CreateFrame("Frame", "WellMetStrip" .. chip.label, strip)
		f:SetSize(SIZE, SIZE)
		local black = f:CreateTexture(nil, "BACKGROUND")
		black:SetAllPoints()
		black:SetColorTexture(0, 0, 0, 1)
		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
		icon:SetTexture(chip.icon)
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local glow = f:CreateTexture(nil, "OVERLAY")
		glow:SetPoint("CENTER")
		glow:SetSize(SIZE * 1.85, SIZE * 1.85)
		glow:SetTexture(GLOW_TEXTURE)
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(1, 0.8, 0.25)
		local check = f:CreateTexture(nil, "OVERLAY")
		check:SetPoint("CENTER")
		check:SetSize(SIZE * 0.6, SIZE * 0.6)
		check:SetTexture(CHECK_TEXTURE)
		local mark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		mark:SetPoint("CENTER")
		mark:SetText("?")
		mark:SetTextColor(0.75, 0.75, 0.75)
		chips[chip.key] = { frame = f, icon = icon, glow = glow, check = check, mark = mark }
	end
	-- The timer lives on its own frame: the strip itself is hidden whenever there is nothing to draw, and a hidden
	-- frame gets no OnUpdate, so it could never come back.
	driver = CreateFrame("Frame", "WellMetStripDriver", UIParent)
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= INTERVAL then elapsed = 0; WM:RefreshStrip() end
	end)
	driver:Hide()
end

function WM:RefreshStrip()
	if not strip or not WM.db.strip.enabled then return end
	local model = ns.StripModel()
	WM.stripModel = model
	for _, c in pairs(chips) do c.frame:Hide() end
	model = ns.StripDrawn(model)
	for i, m in ipairs(model) do
		local c = chips[m.key]
		local need, ok = m.state == "need", m.state == "ok"
		c.frame:ClearAllPoints()
		c.frame:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * (SIZE + GAP), 0)
		c.glow:SetShown(need)
		c.icon:SetDesaturated(not need)
		c.icon:SetVertexColor(need and 1 or 0.4, need and 1 or 0.4, need and 1 or 0.4)
		c.check:SetShown(ok)
		c.mark:SetShown(m.state == "unknown")
		c.frame:Show()
	end
	strip:SetWidth(math.max(1, #model * (SIZE + GAP) - GAP))
	strip:SetShown(#model > 0)
end

local function place()
	local s = WM.db.strip
	strip:ClearAllPoints()
	strip:SetPoint(s.point, UIParent, s.point, s.x, s.y)
end

-- Show or hide the strip to match the setting (the checkbox and /wellmet strip both call this).
function WM:ApplyStrip()
	if not strip then return end
	if WM.db.strip.enabled then
		place()
		driver:Show()
		strip:Show()
		elapsed = 0
		WM:RefreshStrip()
	else
		driver:Hide()
		strip:Hide()
	end
end

-- Flip the strip on / off (/wellmet strip and the minimap button's right-click). Returns the new state.
function WM:ToggleStrip()
	WM.db.strip.enabled = not WM.db.strip.enabled
	WM:ApplyStrip()
	if WM.refreshOptions then WM.refreshOptions() end
	return WM.db.strip.enabled
end

function WM:ResetStripPosition()
	local s = WM.db.strip
	s.point, s.x, s.y = "TOP", 0, -140
	if strip then place() end
end

function WM:CreateStrip()
	build()
	WM:RegisterEvent("PLAYER_REGEN_DISABLED")
	WM:RegisterEvent("PLAYER_REGEN_ENABLED")
	WM:RegisterEvent("GROUP_ROSTER_UPDATE")
	WM.strip = strip
	WM:ApplyStrip()
end

function WM:PLAYER_REGEN_DISABLED() WM:RefreshStrip() end
function WM:PLAYER_REGEN_ENABLED() WM:RefreshStrip() end
function WM:GROUP_ROSTER_UPDATE() WM:RefreshStrip() end
