--[[ WellMet — settings (Blizzard Settings API canvas panels, stock templates only).

A main panel plus one sub-panel per section, listed under WellMet in the settings tree:
  WellMet        key, a checkbox per section (ticking one switches the section on and shows its page), mounted
                 behavior, minimap button, debug
  Self           your own buffs (aura / armor / ...) and the buff you put on yourself
  Party / Raid   who in your group gets what, a macro button
  Others         strangers: who gets what, nameplates
Each section has its own on/off switch and its own choices.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local ICON_SIZE = 20
local SKIP_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"     -- the red "pass" cross

-- `dim`: darkened (an inline texture can't be desaturated, but it can take a vertex colour).
local function iconText(texture, dim)
	if dim then
		return ("|T%s:%d:%d:0:0:64:64:0:64:0:64:110:110:110|t"):format(tostring(texture), ICON_SIZE, ICON_SIZE)
	end
	return ("|T%s:%d|t"):format(tostring(texture), ICON_SIZE)
end

-- A buff the player hasn't learned (or the client can't resolve): shown greyed, with an "Unknown" tooltip.
local function unknownBuff(buff) return not ns.IsKnown(buff) end

local function buffLabel(buff)
	if unknownBuff(buff) then
		return iconText(ns.SpellIcon(buff), true) .. " |cff808080" .. buff.name .. "|r"
	end
	return iconText(ns.SpellIcon(buff)) .. " " .. buff.name
end

local function unknownTooltip(tooltip)
	GameTooltip_SetTitle(tooltip, "Unknown")
	GameTooltip_AddNormalLine(tooltip, "You haven't learned this spell yet.")
end

-- Assign mode (Paladin): the caster's buffs (icon + name in the open list) and "Skip". The closed
-- dropdown shows just the icon (assignIcon).
local function assignOptions(caster, sectionKey, secondary)
	local options = {}
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		if not (buff.partyOnly and sectionKey == "others") then       -- party-only spells are never offered for strangers
			options[#options + 1] = { value = key, label = buffLabel(buff), unknown = unknownBuff(buff) }
		end
	end
	options[#options + 1] = { value = "NONE", label = iconText(SKIP_ICON) .. (secondary and " No fallback" or " Skip this class") }
	return options
end

local function assignIcon(caster, value)
	if value == "NONE" then return iconText(SKIP_ICON) end
	local buff = caster.buffs[value]
	return iconText(ns.SpellIcon(buff), unknownBuff(buff))
end

-- A "Yourself" category (an aura, an armor): "best learned" (when the category has one), each choice, and None.
local function selfOptions(caster, cat)
	local options = {}
	if cat.auto then
		local shown, learned
		for _, key in ipairs(cat.auto) do
			shown = shown or caster.buffs[key]
			if ns.IsKnown(caster.buffs[key]) then learned = caster.buffs[key]; break end
		end
		local buff = learned or shown
		local dim = learned == nil
		options[#options + 1] = {
			value = "AUTO", unknown = dim,
			label = iconText(ns.SpellIcon(buff), dim) .. " " .. (dim and ("|cff808080" .. cat.autoLabel .. "|r") or cat.autoLabel),
		}
	end
	for _, key in ipairs(cat.choices) do
		local buff = caster.buffs[key]
		options[#options + 1] = { value = key, label = buffLabel(buff), unknown = unknownBuff(buff) }
	end
	options[#options + 1] = { value = "NONE", label = iconText(SKIP_ICON) .. " None" }
	return options
end

-- Stack mode (Mage): one checkbox per buff; the closed dropdown shows the icons of the buffs that are on.
local function stackOptions(caster, sectionKey)
	local options = {}
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		if not (buff.partyOnly and sectionKey == "others") then
			options[#options + 1] = { value = key, label = buffLabel(buff), unknown = unknownBuff(buff) }
		end
	end
	return options
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

local function makeCheck(parent, label, get, set, x, y, name)
	local cb = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(self) set(self:GetChecked()) end)
	cb.refresh = function() cb:SetChecked(get()) end
	return cb
end

local function makeButton(parent, text, width, x, y, onClick, name)
	local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
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
local function makeDropdown(parent, name, width, x, y, options, get, set, closedText)
	local dd = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", x, y)
	dd:SetWidth(width)
	if closedText then
		dd:SetSelectionTranslator(function(selection) return closedText(selection.data) end)
	end
	dd:SetupMenu(function(_, root)
		for _, o in ipairs(type(options) == "function" and options() or options) do
			local item = root:CreateRadio(o.label, function() return get() == o.value end, function() set(o.value) end, o.value)
			if o.unknown then item:SetTooltip(unknownTooltip) end
		end
	end)
	dd.refresh = function() dd:GenerateMenu() end
	return dd
end

-- Multi-select version: checkbox items that stay open while you tick. `isOn(value)` / `toggle(value)`.
-- `closedText(valuesOn)` builds what the CLOSED dropdown shows (e.g. the icons of everything ticked).
local function makeChecklist(parent, name, width, x, y, options, isOn, toggle, closedText)
	local dd = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", x, y)
	dd:SetWidth(width)
	dd:SetSelectionText(function(selections)
		local on = {}
		for _, sel in ipairs(selections) do on[#on + 1] = sel.data end
		return closedText(on)
	end)
	dd:SetupMenu(function(_, root)
		for _, o in ipairs(type(options) == "function" and options() or options) do
			local item = root:CreateCheckbox(o.label, function() return isOn(o.value) end, function() toggle(o.value) end, o.value)
			if o.unknown then item:SetTooltip(unknownTooltip) end
		end
	end)
	dd.refresh = function() dd:GenerateMenu() end
	return dd
end

local function makeHeader(parent, text, x, y, width)
	local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	h:SetPoint("TOPLEFT", x, y)
	h:SetText(text)
	h:SetTextColor(1, 0.82, 0)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetSize(width or 540, 1)
	line:SetPoint("TOPLEFT", x, y - 16)
	line:SetColorTexture(1, 0.82, 0, 0.35)
	return h
end

-- A body of text under a header (wraps at the panel width).
local function makeText(parent, text, x, y, font)
	local t = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
	t:SetPoint("TOPLEFT", x, y)
	t:SetWidth(540); t:SetJustifyH("LEFT")
	t:SetText(text)
	return t
end

-- A hidden canvas panel with a title and a subtitle. Panels start hidden (a shown frame at login once
-- locked the keyboard); the settings screen shows them. `panel.refreshers` re-read the saved values on show.
local function newPanel(globalName, displayName, title, subtitle)
	local panel = CreateFrame("Frame", globalName, UIParent)
	panel.name = displayName
	panel:Hide()
	panel.refreshers = {}
	local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText(title)
	makeText(panel, subtitle, 16, -44)
	panel:SetScript("OnShow", function() for _, r in ipairs(panel.refreshers) do r() end end)
	return panel
end

local SECTION_TITLE = { self = "Self", party = "Party / Raid", others = "Others" }
local SECTION_CHECK_WIDTH = { self = 110, party = 190, others = 130 }          -- room each checkbox and its label take in the row
local panels = {}                   -- section key -> panel (nil when the class has no such section)

-- The "which buffs on which class" table for one section (Party / Raid or Others): one row per target class,
-- alphabetical by displayed name. Assign mode (Paladin): a one-choice dropdown. Stack mode (Mage, Druid): a
-- checkbox dropdown. Returns the y below the table.
local function buildClassTable(panel, sectionKey, y)
	local caster = WM.caster
	local cfg = WM.db[sectionKey]
	local classes = { unpack(ns.TargetClasses) }
	table.sort(classes, function(a, b) return className(a):lower() < className(b):lower() end)
	-- Strangers get a fallback: a Paladin has one blessing per target, so when the primary is already on someone
	-- from another Paladin, the secondary is cast instead. (In a group people agree who casts what.)
	local withSecondary = caster.mode == "assign" and sectionKey == "others"
	if withSecondary then
		local first = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		first:SetPoint("TOPLEFT", 150, y + 4); first:SetText("Primary")
		local second = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		second:SetPoint("TOPLEFT", 240, y + 4); second:SetText("Secondary (if they have the primary)")
		y = y - 12
	end
	for _, class in ipairs(classes) do
		local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("TOPLEFT", 24, y - 4)
		text:SetText(classColored(class))
		local name = "WellMet" .. sectionKey:sub(1, 1):upper() .. sectionKey:sub(2) .. "Class" .. class
		local dd
		if caster.mode == "stack" then
			dd = makeChecklist(panel, name, 110, 150, y + 2, function() return stackOptions(caster, sectionKey) end,
				function(key) return ns.StackEnabled(caster.buffs[key], class, cfg.stack) end,
				function(key)
					local buff = caster.buffs[key]
					ns.StackSet(caster, buff, class, not ns.StackEnabled(buff, class, cfg.stack), cfg.stack)
				end,
				function(on)
					if #on == 0 then return "|cffaaaaaanone|r" end
					local parts = {}
					for _, key in ipairs(on) do
						local buff = caster.buffs[key]
						parts[#parts + 1] = iconText(ns.SpellIcon(buff), unknownBuff(buff))
					end
					return table.concat(parts)
				end)
		else
			dd = makeDropdown(panel, name, 70, 150, y + 2, function() return assignOptions(caster, sectionKey) end,
				function() return ns.AssignedKey(cfg, class) end,
				function(v) cfg.assign[class] = v end,
				function(value) return assignIcon(caster, value) end)
		end
		panel.refreshers[#panel.refreshers + 1] = dd.refresh
		if withSecondary then
			local dd2 = makeDropdown(panel, name .. "Second", 70, 240, y + 2, function() return assignOptions(caster, sectionKey, true) end,
				function() return cfg.assign2[class] or "NONE" end,
				function(v) cfg.assign2[class] = v end,
				function(value) return assignIcon(caster, value) end)
			panel.refreshers[#panel.refreshers + 1] = dd2.refresh
		end
		y = y - 30
	end
	return y
end

local function buildRadius(panel, sectionKey, y)
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 24, y - 4)
	text:SetText("Search radius")
	local name = "WellMet" .. sectionKey:sub(1, 1):upper() .. sectionKey:sub(2) .. "Radius"
	local dd = makeDropdown(panel, name, 170, 150, y + 2, RADIUS_OPTIONS,
		function() return WM.db[sectionKey].radius end, function(v) WM.db[sectionKey].radius = v end)
	panel.refreshers[#panel.refreshers + 1] = dd.refresh
	return y - 36
end

local function buildSelfPanel(caster, subtitle)
	local panel = newPanel("WellMetSelfPanel", "Self", "Self", subtitle)
	local y = -76
	local cfg = WM.db.self

	if #caster.selfCategories > 0 then
		makeHeader(panel, "Your own buffs", 16, y); y = y - 28
	end
	for _, cat in ipairs(caster.selfCategories) do
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 24, y - 4)
		label:SetText(cat.title)
		local dd = makeDropdown(panel, "WellMetSelfCat" .. cat.key, 230, 170, y + 2, function() return selfOptions(caster, cat) end,
			function() return cfg.choice[cat.key] or cat.default end,
			function(v) cfg.choice[cat.key] = v end)
		panel.refreshers[#panel.refreshers + 1] = dd.refresh
		y = y - 30
	end

	-- the buff this class puts on others, cast on yourself too (a Paladin's blessing, a Mage's Arcane Intellect)
	do
		y = y - 8
		makeHeader(panel, "On yourself", 16, y); y = y - 28
		local class = WM.classToken
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 24, y - 4)
		label:SetText(caster.mode == "stack" and "Buffs" or "Blessing")
		local dd
		if caster.mode == "stack" then
			dd = makeChecklist(panel, "WellMetSelfOwn", 110, 170, y + 2, function() return stackOptions(caster, "self") end,
				function(key) return ns.StackEnabled(caster.buffs[key], class, cfg.stack) end,
				function(key)
					local buff = caster.buffs[key]
					ns.StackSet(caster, buff, class, not ns.StackEnabled(buff, class, cfg.stack), cfg.stack)
				end,
				function(on)
					if #on == 0 then return "|cffaaaaaanone|r" end
					local parts = {}
					for _, key in ipairs(on) do
						local buff = caster.buffs[key]
						parts[#parts + 1] = iconText(ns.SpellIcon(buff), unknownBuff(buff))
					end
					return table.concat(parts)
				end)
		else
			dd = makeDropdown(panel, "WellMetSelfOwn", 70, 170, y + 2, function() return assignOptions(caster, "self") end,
				function() return ns.AssignedKey(cfg, class) end,
				function(v) cfg.assign[class] = v end,
				function(value) return assignIcon(caster, value) end)
		end
		panel.refreshers[#panel.refreshers + 1] = dd.refresh
		y = y - 36
	end

	return panel
end

local function buildPartyPanel(caster)
	local panel = newPanel("WellMetPartyPanel", "Party / Raid", "Party / Raid",
		"Buffs for the people in your group. Each section has its own choices, so this table can differ from Others.")
	local y = -76
	y = buildRadius(panel, "party", y)
	makeHeader(panel, caster.title, 16, y); y = y - 28
	buildClassTable(panel, "party", y)
	return panel
end

local function buildOthersPanel(caster)
	local panel = newPanel("WellMetOthersPanel", "Others", "Others",
		"Players who are not in your group. They are found through friendly player nameplates, and need the key (not a macro).")
	local y = -76
	y = buildRadius(panel, "others", y)

	local npStatus = makeText(panel, "", 24, y)
	y = y - 20
	local npButton = makeButton(panel, "Turn on friendly nameplates", 200, 24, y, function()
		if InCombatLockdown() then npStatus:SetText("Change this after combat."); return end
		SetCVar("nameplateShowFriendlyPlayers", 1)
		for _, r in ipairs(panel.refreshers) do r() end
	end)
	panel.refreshers[#panel.refreshers + 1] = function()
		local on = ns.Discovery.NameplatesOn()
		npStatus:SetText("Friendly player nameplates: " .. (on == nil and "unknown" or (on and "|cff66ff66on|r" or "|cffff6666OFF|r - strangers can't be found")))
		npButton:SetShown(on == false)
	end
	y = y - 40
	makeHeader(panel, caster.title, 16, y); y = y - 28
	buildClassTable(panel, "others", y)
	return panel
end

local function buildMainPanel(subs)
	local panel = newPanel("WellMetOptionsPanel", "WellMet", "WellMet",
		"One key buffs you, then the next nearby player who needs it. Choose what each part does under Self, Party / Raid and Others.")
	local y = -76

	makeHeader(panel, "Key", 16, y); y = y - 28
	local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	keyLabel:SetPoint("TOPLEFT", 24, y - 4)
	makeButton(panel, "Open Key Bindings", 150, 190, y, function() WM:OpenKeyBindings() end)
	panel.refreshers[#panel.refreshers + 1] = function()
		local k1, k2 = GetBindingKey(ns.CLICK_ACTION)
		keyLabel:SetText("Key: " .. (k1 and ("|cff66ff66" .. k1 .. (k2 and (", " .. k2) or "") .. "|r") or "|cffaaaaaanot set|r"))
	end
	y = y - 40

	makeHeader(panel, "Sections", 16, y); y = y - 24
	makeText(panel, "Tick a section to turn it on. Its settings page then appears under WellMet in this list; untick it and the page goes away.", 24, y)
	y = y - 30
	-- the section checkboxes sit side by side in one row
	local x = 20
	for _, sectionKey in ipairs(ns.SECTIONS) do
		if panels[sectionKey] then
			local cb = makeCheck(panel, SECTION_TITLE[sectionKey], function() return WM.db[sectionKey].enabled end,
				function(v)
					WM.db[sectionKey].enabled = v and true or false
					WM:ApplySectionVisibility(true)
				end, x, y, "WellMetShow" .. sectionKey:sub(1, 1):upper() .. sectionKey:sub(2))
			panel.refreshers[#panel.refreshers + 1] = cb.refresh
			x = x + SECTION_CHECK_WIDTH[sectionKey]
		end
	end
	y = y - 40

	makeHeader(panel, "General", 16, y); y = y - 28
	local function check(label, get, set)
		local cb = makeCheck(panel, label, get, set, 20, y)
		panel.refreshers[#panel.refreshers + 1] = cb.refresh
		y = y - 26
	end
	check("Allow casting while mounted (dismounts you)", function() return WM.db.allowMounted end, function(v) WM.db.allowMounted = v and true or false end)
	check("Show the minimap button", function() return not WM.db.minimap.hide end,
		function(v) WM.db.minimap.hide = not v; if WM.minimap then WM.minimap:SetShown(v) end end)
	y = y - 6
	-- Debug records the log and shows why a press did nothing. The button shows the state and flips it.
	local debugButton
	debugButton = makeButton(panel, "", 110, 24, y, function()
		WM:ToggleDebug()
		debugButton:SetText(WM.db.debug and "Debug: On" or "Debug: Off")
	end, "WellMetDebugButton")
	panel.refreshers[#panel.refreshers + 1] = function() debugButton:SetText(WM.db.debug and "Debug: On" or "Debug: Off") end
	makeButton(panel, "Open log", 110, 142, y, function() WM:ShowLog() end, "WellMetLogButton")
	makeButton(panel, "Create macro", 130, 274, y, function() WM:CreateMacro() end, "WellMetMacroButton")
	y = y - 30
	makeText(panel, "Debug records a log you can copy and shows why a press did nothing.", 24, y)
	y = y - 20
	makeText(panel, "Create macro puts a /click WellMetCast macro on your cursor: click an action bar slot. It buffs you and your group, "
		.. "not strangers (the game won't run that from inside a macro), so strangers need the key.", 24, y)
	return panel
end

function WM:CreateOptions()
	local caster = WM.caster
	panels.self = buildSelfPanel(caster,
		"Your own buffs: an aura, an armor... and the buff you put on yourself. With the other sections off, WellMet is just this.")
	panels.party = buildPartyPanel(caster)
	panels.others = buildOthersPanel(caster)
	local main = buildMainPanel()

	local category = Settings.RegisterCanvasLayoutCategory(main, "WellMet")
	Settings.RegisterAddOnCategory(category)
	WM.optionsCategory = category
	WM.optionsSub = {}
	for _, sectionKey in ipairs(ns.SECTIONS) do
		if panels[sectionKey] then
			WM.optionsSub[sectionKey] = Settings.RegisterCanvasLayoutSubcategory(category, panels[sectionKey], SECTION_TITLE[sectionKey])
		end
	end
	WM.optionsPanel = main
	WM.optionsPanels = panels
	WM:ApplySectionVisibility()
	WM.refreshOptions = function()
		for _, panel in pairs(panels) do for _, r in ipairs(panel.refreshers) do r() end end
		for _, r in ipairs(main.refreshers) do r() end
	end
end

-- Open Blizzard's Key Bindings screen with its search box filled in so only WellMet's binding is listed. The
-- search matches single words against binding NAMES (not section headers), and ours contains "WellMet"
-- (Core/Cast.lua), which nothing else does. The box is filled a moment after the screen opens, because
-- opening clears it.
local STEP = 0.1
function WM:OpenKeyBindings()
	Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
	C_Timer.After(STEP, function() SettingsPanel.SearchBox:SetText(BINDING_HEADER_WELLMET) end)
end

-- A section that is switched off has no page in the settings list. The list skips any category with a
-- `redirectCategory` (Blizzard uses that for pages it hides), so a switched-off section's page gets one,
-- and the list is rebuilt when a checkbox changes it.
function WM:ApplySectionVisibility(rebuild)
	for sectionKey, subcategory in pairs(WM.optionsSub) do
		subcategory.redirectCategory = (not WM.db[sectionKey].enabled) and WM.optionsCategory or nil
	end
	if rebuild then SettingsPanel:GetCategoryList():CreateCategories() end
end

-- Open the settings, optionally on one section ("self", "party", "others"). A switched-off section has no
-- page, so that opens the main page and says why.
function WM:OpenOptions(sectionKey)
	local category = WM.optionsCategory
	if sectionKey and WM.optionsSub[sectionKey] then
		if WM.db[sectionKey].enabled then
			category = WM.optionsSub[sectionKey]
		else
			WM:Print("The " .. SECTION_TITLE[sectionKey] .. " section is switched off. Tick it under Sections to turn it on.")
		end
	end
	Settings.OpenToCategory(category:GetID())
end
