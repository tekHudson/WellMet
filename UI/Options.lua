--[[ WellMet — settings panel (Blizzard Settings API canvas, stock templates only).

Left column:  key, targeting, behavior.
Right column: which blessing goes on which target class (Paladin).
]]

local ADDON, ns = ...
local WM = ns.WM

local ASSIGN_LABEL = { MIGHT = "Might", WISDOM = "Wisdom", NONE = "Skip" }
local ASSIGN_CYCLE = { "MIGHT", "WISDOM", "NONE" }
local RADIUS_CYCLE = { 0, 28, 10 }
local RADIUS_LABEL = { [0] = "Cast range (max)", [28] = "28 yards", [10] = "10 yards" }

local function cycle(list, current)
	for i, v in ipairs(list) do
		if v == current then return list[i % #list + 1] end
	end
	return list[1]
end

local function className(class)
	return (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

local function classColored(class)
	local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
	local text = className(class)
	if c then
		local function byte(x) return math.floor(x * 255 + 0.5) end
		return string.format("|cff%02x%02x%02x%s|r", byte(c.r), byte(c.g), byte(c.b), text)
	end
	return text
end

local function makeCheck(parent, label, get, set, x, y)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(self) set(self:GetChecked()) end)
	cb.refresh = function() cb:SetChecked(get()) end
	return cb
end

local function makeButton(parent, text, width, x, y, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function makeHeader(parent, text, x, y)
	local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	h:SetPoint("TOPLEFT", x, y)
	h:SetText(text)
	h:SetTextColor(1, 0.82, 0)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetSize(280, 1)
	line:SetPoint("TOPLEFT", x, y - 16)
	line:SetColorTexture(1, 0.82, 0, 0.35)
	return h
end

function WM:CreateOptions()
	local panel = CreateFrame("Frame", "WellMetOptionsPanel", UIParent)
	panel.name = "WellMet"
	panel:Hide()
	local refreshers = {}

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("WellMet")
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetText("One key buffs the next nearby player who needs it. Macro: /click WellMetCast")

	local LX, RX = 16, 340
	local y = -64

	----------------------------------------------------------------
	makeHeader(panel, "Key", LX, y); y = y - 28
	local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	keyLabel:SetPoint("TOPLEFT", LX + 8, y - 4)
	makeButton(panel, "Open Key Bindings", 150, LX + 150, y, function()
		Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, BINDING_HEADER_WELLMET)
	end)
	refreshers[#refreshers + 1] = function()
		local k1, k2 = GetBindingKey(ns.CLICK_ACTION)
		keyLabel:SetText("Key: " .. (k1 and ("|cff66ff66" .. k1 .. (k2 and (", " .. k2) or "") .. "|r") or "|cffaaaaaanot set|r"))
	end
	y = y - 30

	----------------------------------------------------------------
	makeHeader(panel, "Who", LX, y); y = y - 28
	local function check(label, key)
		local cb = makeCheck(panel, label, function() return WM.db[key] end, function(v) WM.db[key] = v and true or false end, LX + 4, y)
		refreshers[#refreshers + 1] = cb.refresh
		y = y - 26
	end
	check("Include players outside my group (needs nameplates)", "strangers")
	check("Group members first", "groupFirst")
	check("Buff myself too (first)", "includeSelf")

	local radiusBtn = makeButton(panel, "", 200, LX + 8, y, function(self)
		WM.db.radius = cycle(RADIUS_CYCLE, WM.db.radius)
		for _, r in ipairs(refreshers) do r() end
	end)
	local radiusNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	radiusNote:SetPoint("LEFT", radiusBtn, "RIGHT", 8, 0)
	radiusNote:SetText("search radius")
	refreshers[#refreshers + 1] = function() radiusBtn:SetText(RADIUS_LABEL[WM.db.radius] or tostring(WM.db.radius)) end
	y = y - 34

	local npStatus = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	npStatus:SetPoint("TOPLEFT", LX + 8, y)
	npStatus:SetWidth(290); npStatus:SetJustifyH("LEFT")
	y = y - 18
	local npButton = makeButton(panel, "Turn on friendly nameplates", 200, LX + 8, y, function()
		if InCombatLockdown() then npStatus:SetText("Change this after combat."); return end
		SetCVar("nameplateShowFriendlyPlayers", 1)
		for _, r in ipairs(refreshers) do r() end
	end)
	refreshers[#refreshers + 1] = function()
		local on = ns.Discovery.NameplatesOn()
		npStatus:SetText("Friendly player nameplates: " .. (on == nil and "unknown" or (on and "|cff66ff66on|r" or "|cffff6666OFF|r - strangers can't be found")))
		npButton:SetShown(on == false)
	end
	y = y - 36

	----------------------------------------------------------------
	makeHeader(panel, "Behavior", LX, y); y = y - 28
	check("Allow casting while mounted (dismounts you)", "allowMounted")
	do
		local cb = makeCheck(panel, "Show the minimap button",
			function() return not WM.db.minimap.hide end,
			function(v) WM.db.minimap.hide = not v; if WM.minimap then WM.minimap:SetShown(v) end end, LX + 4, y)
		refreshers[#refreshers + 1] = cb.refresh
		y = y - 26
	end
	check("Debug: record the log and show why a press did nothing", "debug")
	y = y - 6
	makeButton(panel, "Open log (/wellmet log)", 200, LX + 8, y, function() WM:ShowLog() end)

	----------------------------------------------------------------
	-- Right column: assignments
	local ry = -64
	makeHeader(panel, "Which blessing on which class", RX, ry); ry = ry - 28
	local assignButtons = {}
	local function assignRow(class, label)
		local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("TOPLEFT", RX + 8, ry - 4)
		text:SetText(label)
		local b = makeButton(panel, "", 110, RX + 160, ry, function()
			local current = class and ns.AssignedKey(class) or WM.db.unknownClass
			local nextKey = cycle(ASSIGN_CYCLE, current)
			if class then WM.db.assign[class] = nextKey else WM.db.unknownClass = nextKey end
			for _, r in ipairs(refreshers) do r() end
		end)
		refreshers[#refreshers + 1] = function()
			b:SetText(ASSIGN_LABEL[class and ns.AssignedKey(class) or WM.db.unknownClass] or "?")
		end
		ry = ry - 28
	end
	for _, class in ipairs(ns.TargetClasses) do assignRow(class, classColored(class)) end
	assignRow(nil, "|cffaaaaaaClass unreadable|r")
	local help = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", RX + 8, ry - 6)
	help:SetWidth(280); help:SetJustifyH("LEFT")
	help:SetText("Click a button to cycle Might / Wisdom / Skip. \"Class unreadable\" is used when the game hides a stranger's class.")

	----------------------------------------------------------------
	panel:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
	WM.refreshOptions = function() for _, r in ipairs(refreshers) do r() end end

	local category = Settings.RegisterCanvasLayoutCategory(panel, "WellMet")
	Settings.RegisterAddOnCategory(category)
	WM.optionsCategory = category
	WM.optionsPanel = panel
end

function WM:OpenOptions()
	Settings.OpenToCategory(WM.optionsCategory:GetID())
end
