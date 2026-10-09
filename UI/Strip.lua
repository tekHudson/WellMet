--[[ WellMet — the reminder strip: three small chips, Self / Party / Raid, that say who still needs a buff.

A chip shows how many people in that group the key would buff right now (same rules as a key press: in
range, learned, section on, not just tried). Orange with a count = someone needs a buff; a check = all
covered; grey "?" = can't tell (Forever hides other players' buffs in combat). Party is your own party,
Raid is everyone else in your raid, so in a 5-man group there is no Raid chip. Strangers (Others) are not
counted: they are only found when you press the key.

Off by default (settings > General). Shift-drag moves it.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local INTERVAL = 1        -- seconds between looks while it is shown
local CHIP_W, CHIP_H, GAP = 66, 22, 4
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"

local CHIPS = {
	{ key = "self",  label = "Self" },
	{ key = "party", label = "Party" },
	{ key = "raid",  label = "Raid" },
}

-- Which raid subgroup is this raid unit in? nil when unknown.
local function subgroupOf(unit)
	local n = tonumber(unit:match("^raid(%d+)$"))
	if n and GetRaidRosterInfo then return select(3, GetRaidRosterInfo(n)) end
end

local function mySubgroup()
	for i = 1, GetNumGroupMembers() do
		if UnitIsUnit("raid" .. i, "player") then return subgroupOf("raid" .. i) end
	end
end

-- The chips to show and what each says. Returns a list of { key, label, count, state }:
--   state "need" (count people need a buff), "ok" (nobody does), "unknown" (can't tell right now).
-- Pure enough to test: all the game's answers come through ns.Probe and Discovery.
function ns.StripModel()
	local db = WM.db
	local inRaid = IsInRaid()
	local inGroup = inRaid or GetNumGroupMembers() > 0
	local show = { self = db.self.enabled, party = db.party.enabled and inGroup, raid = db.party.enabled and inRaid }

	local readable = not InCombatLockdown() and ns.AurasReadable()
	local people = { self = {}, party = {}, raid = {} }
	if readable then
		local cands = ns.Discovery.Discover({ groupOnly = true })
		local ctx = { now = GetTime(), settings = db, caster = WM.caster, probe = ns.Probe }
		local _, _, eligible = ns.Select.Pick(cands, ctx)
		local mine = inRaid and mySubgroup() or nil
		for _, e in ipairs(eligible) do
			local c = e.cand
			local bucket = "self"
			if c.tier == 1 then
				bucket = "party"
				if inRaid and mine and subgroupOf(c.unit) ~= mine then bucket = "raid" end
			end
			people[bucket][c.key] = true
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

local strip, chips
local elapsed = 0

local function build()
	strip = CreateFrame("Frame", "WellMetStrip", UIParent)
	strip:SetSize(CHIP_W, CHIP_H)
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
		GameTooltip:AddLine("Who still needs a buff. Shift-drag to move.", 1, 1, 1)
		GameTooltip:Show()
	end)
	strip:SetScript("OnLeave", function() GameTooltip:Hide() end)

	chips = {}
	for i, chip in ipairs(CHIPS) do
		local f = CreateFrame("Frame", "WellMetStripChip" .. chip.label, strip)
		f:SetSize(CHIP_W, CHIP_H)
		local border = f:CreateTexture(nil, "BACKGROUND")
		border:SetAllPoints()
		local bg = f:CreateTexture(nil, "BORDER")
		bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
		bg:SetColorTexture(0.09, 0.1, 0.13, 0.9)
		local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("CENTER")
		chips[chip.key] = { frame = f, border = border, text = text }
	end
	strip:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= INTERVAL then elapsed = 0; WM:RefreshStrip() end
	end)
end

local COLORS = {
	need    = { 1.00, 0.54, 0.24 },
	ok      = { 0.31, 0.82, 0.55 },
	unknown = { 0.55, 0.55, 0.55 },
}

function WM:RefreshStrip()
	if not strip or not WM.db.strip.enabled then return end
	local model = ns.StripModel()
	WM.stripModel = model
	for _, c in pairs(chips) do c.frame:Hide() end
	for i, m in ipairs(model) do
		local c = chips[m.key]
		local color = COLORS[m.state]
		c.frame:ClearAllPoints()
		c.frame:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * (CHIP_W + GAP), 0)
		c.border:SetColorTexture(color[1], color[2], color[3], m.state == "need" and 1 or 0.45)
		c.text:SetTextColor(color[1], color[2], color[3])
		c.text:SetText(m.label .. " " .. (m.state == "need" and m.count or m.state == "ok" and CHECK or "?"))
		c.frame:Show()
	end
	strip:SetWidth(math.max(1, #model * (CHIP_W + GAP) - GAP))
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
		strip:Show()
		elapsed = 0
		WM:RefreshStrip()
	else
		strip:Hide()
	end
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
