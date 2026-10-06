--[[ WellMet — settings panel (Blizzard Settings API canvas, stock templates only).

Left column:  key, targeting, behavior.
Right column: yourself (your own aura / armor / ...), then which buffs go on which target class.
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
local function assignOptions(caster)
	local options = {}
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		options[#options + 1] = { value = key, label = buffLabel(buff), unknown = unknownBuff(buff) }
	end
	options[#options + 1] = { value = "NONE", label = iconText(SKIP_ICON) .. " Skip this class" }
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
local function stackOptions(caster)
	local options = {}
	for _, key in ipairs(caster.order) do
		local buff = caster.buffs[key]
		options[#options + 1] = { value = key, label = buffLabel(buff), unknown = unknownBuff(buff) }
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
			local item = root:CreateRadio(o.label, function() return get() == o.value end, function() set(o.value) end, o.value)
			if o.unknown then item:SetTooltip(unknownTooltip) end
		end
	end)
	dd.refresh = function() dd:GenerateMenu() end
	return dd
end

-- Multi-select version: checkbox items that stay open while you tick. `isOn(value)` / `toggle(value)`.
-- `closedText(valuesOn)` builds what the CLOSED dropdown shows (e.g. the icons of everything ticked).
local function makeChecklist(parent, width, x, y, options, isOn, toggle, closedText)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
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
	makeButton(panel, "Open Key Bindings", 150, LX + 150, y, function() WM:OpenKeyBindings() end)
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
	-- Right column: which buffs go on which target class (depends on the player's class)
	local ry = -64

	-- Your own buffs (auras, armors): cast on yourself first, one choice per category. Above the class table.
	if #WM.caster.selfCategories > 0 then
		makeHeader(panel, "Yourself", RX, ry); ry = ry - 28
		for _, cat in ipairs(WM.caster.selfCategories) do
			local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			label:SetPoint("TOPLEFT", RX + 8, ry - 4)
			label:SetText(cat.title)
			local dd = makeDropdown(panel, 170, RX + 118, ry + 2, function() return selfOptions(WM.caster, cat) end,
				function() return WM.db.selfChoice[cat.key] or cat.default end,
				function(v) WM.db.selfChoice[cat.key] = v end)
			refreshers[#refreshers + 1] = dd.refresh
			ry = ry - 30
		end
		ry = ry - 14
	end

	local caster = WM.caster
	if caster.mode == "self" then caster = nil end          -- nothing is cast on other players: no class table
	if caster then makeHeader(panel, caster.title, RX, ry); ry = ry - 28 end

	local function classRow(class, label, addControl)
		local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("TOPLEFT", RX + 8, ry - 4)
		text:SetText(label)
		refreshers[#refreshers + 1] = addControl(RX + 120, ry + 2).refresh
		ry = ry - 30
	end

	local help = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	help:SetWidth(280); help:SetJustifyH("LEFT")

	if caster then
		local classes = { unpack(ns.TargetClasses) }
		table.sort(classes, function(a, b) return className(a):lower() < className(b):lower() end)      -- alphabetical by displayed name
		local rows = {}
		for _, class in ipairs(classes) do rows[#rows + 1] = { class = class, label = classColored(class) } end

		for _, row in ipairs(rows) do
			local class = row.class
			if caster.mode == "stack" then
				classRow(class, row.label, function(x, y)
					return makeChecklist(panel, 100, x, y, function() return stackOptions(caster) end,
						function(key) return ns.StackEnabled(caster.buffs[key], class, WM.db.stack) end,
						function(key)
							local buff = caster.buffs[key]
							ns.StackSet(caster, buff, class, not ns.StackEnabled(buff, class, WM.db.stack))
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
				end)
			else
				classRow(class, row.label, function(x, y)
					return makeDropdown(panel, 70, x, y, function() return assignOptions(caster) end,
						function() return ns.AssignedKey(class) end,
						function(v) WM.db.assign[class] = v end,
						function(value) return assignIcon(caster, value) end)
				end)
			end
		end
		help:SetPoint("TOPLEFT", RX + 8, ry - 6)
		if caster.mode == "stack" then
			help:SetText("Tick the buffs for each class (open the list to see names). Dampen and Amplify Magic replace each other, so ticking one clears the other.")
		else
			help:SetText("Pick the blessing for each class (open the list to see names).")
		end
	end

	----------------------------------------------------------------
	panel:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
	WM.refreshOptions = function() for _, r in ipairs(refreshers) do r() end end

	local category = Settings.RegisterCanvasLayoutCategory(panel, "WellMet")
	Settings.RegisterAddOnCategory(category)
	WM.optionsCategory = category
	WM.optionsPanel = panel
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

function WM:OpenOptions()
	Settings.OpenToCategory(WM.optionsCategory:GetID())
end
