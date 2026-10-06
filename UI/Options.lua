--[[ WellMet — settings panel (Blizzard Settings API canvas, stock templates only).

Left column:  key, targeting, behavior.
Right column: which blessing goes on which target class (Paladin).
]]

local ADDON, ns = ...
local WM = ns.WM

local ICON_SIZE = 20
local SKIP_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"     -- the red "pass" cross

local function iconText(texture)
	return ("|T%s:%d|t"):format(tostring(texture), ICON_SIZE)
end

-- Assignment choices for a target class: the Paladin blessings (icon + name in the open list),
-- and "Skip". The closed dropdown shows just the icon (assignIcon).
local function assignOptions()
	local options = {}
	local caster = ns.CasterData.PALADIN
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		options[#options + 1] = { value = key, label = iconText(ns.SpellIcon(buff)) .. " " .. buff.name }
	end
	options[#options + 1] = { value = "NONE", label = iconText(SKIP_ICON) .. " Skip this class" }
	return options
end

local function assignIcon(value)
	if value == "NONE" then return iconText(SKIP_ICON) end
	return iconText(ns.SpellIcon(ns.CasterData.PALADIN.buffs[value]))
end
local RADIUS_OPTIONS = {
	{ value = 0,  label = "Cast range (max)" },
	{ value = 28, label = "28 yards" },
	{ value = 10, label = "10 yards" },
}

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

-- Stock Blizzard dropdown: click, pick one of `options` ({ value, label }). The closed dropdown shows
-- the selected label. `dd.refresh()` re-reads `get()` (for the panel's refresh pass).
-- `options` may be a function (re-evaluated whenever the menu is built). `closedText(value)` optionally
-- changes what the CLOSED dropdown shows for the selected value (e.g. just an icon).
local function makeDropdown(parent, width, x, y, options, get, set, closedText)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", x, y)
	dd:SetWidth(width)
	if closedText then
		dd:SetSelectionTranslator(function(selection) return closedText(selection.data) end)
	end
	dd:SetupMenu(function(_, root)
		for _, o in ipairs(type(options) == "function" and options() or options) do
			root:CreateRadio(o.label, function() return get() == o.value end, function() set(o.value) end, o.value)
		end
	end)
	dd.refresh = function() dd:GenerateMenu() end
	return dd
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

	local radiusDD = makeDropdown(panel, 170, LX + 8, y, RADIUS_OPTIONS,
		function() return WM.db.radius end, function(v) WM.db.radius = v end)
	refreshers[#refreshers + 1] = radiusDD.refresh
	local radiusNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	radiusNote:SetPoint("LEFT", radiusDD, "RIGHT", 8, 0)
	radiusNote:SetText("search radius")
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
	local function assignRow(class, label)
		local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("TOPLEFT", RX + 8, ry - 4)
		text:SetText(label)
		local dd = makeDropdown(panel, 70, RX + 120, ry + 2, assignOptions,
			function() return class and ns.AssignedKey(class) or WM.db.unknownClass end,
			function(v) if class then WM.db.assign[class] = v else WM.db.unknownClass = v end end,
			assignIcon)
		refreshers[#refreshers + 1] = dd.refresh
		ry = ry - 30
	end
	local classes = { unpack(ns.TargetClasses) }
	table.sort(classes, function(a, b) return className(a):lower() < className(b):lower() end)      -- alphabetical by displayed name
	for _, class in ipairs(classes) do assignRow(class, classColored(class)) end
	assignRow(nil, "|cffaaaaaaClass unreadable|r")
	local help = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", RX + 8, ry - 6)
	help:SetWidth(280); help:SetJustifyH("LEFT")
	help:SetText("Pick the blessing for each class (open the list to see names). \"Class unreadable\" is used when the game hides a stranger's class.")

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
