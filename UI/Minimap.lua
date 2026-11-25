--[[ WellMet — minimap button (native, no libraries).

Left-click opens the settings, right-click opens the quick menu (own buffs, reminder icons), Ctrl-click announces how to
request a buff, Shift-click opens the copyable log, drag moves it around the minimap. The icon is Icons/Icon.tga: "WM" in IM Fell English SC (SIL OFL), antiqued gold on dark
grey, 128x128.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local ICON = "Interface\\AddOns\\WellMet\\Icons\\Icon"
local RIM = 5        -- how far past the minimap's edge the button's centre sits (on the border art)

-- Quick menu (right-click): one radio group per own-buff category (aura, armor ...) that saves at once, plus the
-- reminder strip toggle. Offers "best learned" (when the category has one), the learned choices, and None.
local function iconTag(buff)
	local tex = ns.SpellIcon(buff)
	return tex and ("|T" .. tex .. ":14|t ") or ""
end

function WM:OpenQuickMenu(owner)
	if not (_G.MenuUtil and MenuUtil.CreateContextMenu) then WM:OpenOptions(); return end
	local caster = WM.caster
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("WellMet: yourself")
		for _, cat in ipairs(caster.selfCategories) do
			local function radio(label, value)
				root:CreateRadio(label,
					function() return (WM.db.self.choice[cat.key] or cat.default) == value end,
					function() WM.db.self.choice[cat.key] = value; WM:Log("quick menu: " .. cat.key .. " = " .. value) end)
			end
			root:CreateTitle(cat.title)
			if cat.auto then radio(cat.autoLabel, "AUTO") end
			for _, key in ipairs(cat.choices) do
				local buff = caster.buffs[key]
				if ns.IsKnown(buff) then radio(iconTag(buff) .. buff.name, key) end
			end
			radio("None", "NONE")
		end
		root:CreateDivider()
		root:CreateCheckbox("Reminder icons",
			function() return WM.db.strip.enabled end,
			function() WM:ToggleStrip() end)
		root:CreateButton("Settings", function() WM:OpenOptions() end)
	end)
end

function WM:CreateMinimap()
	local b = CreateFrame("Button", "WellMetMinimap", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 7, -6)

	local function reposition()
		local angle = math.rad(WM.db.minimap.angle)
		b:ClearAllPoints()
		local radius = Minimap:GetWidth() / 2 + RIM      -- follows the minimap's real size (198 px on Forever)
		b:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
	end
	reposition()

	b:SetScript("OnClick", function(_, button)
		WM:Log("minimap click: " .. ns.SafeStr(button) .. " shift=" .. ns.SafeStr(IsShiftKeyDown()) .. " ctrl=" .. ns.SafeStr(IsControlKeyDown()))
		if IsShiftKeyDown() then WM:ShowLog()
		elseif IsControlKeyDown() then WM:Announce()
		elseif button == "RightButton" then WM:OpenQuickMenu(b)
		else WM:OpenOptions() end
	end)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function()
		b:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			WM.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			reposition()
		end)
	end)
	b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("WellMet")
		local key = GetBindingKey(ns.CLICK_ACTION)
		GameTooltip:AddLine(key and ("Key: " .. key) or "No key bound (Key Bindings > WellMet)", 1, 1, 1)
		GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
		GameTooltip:AddLine("Right-click: quick menu (aura, armor ...)", 1, 1, 1)
		GameTooltip:AddLine("Ctrl-click: announce how to request a buff", 1, 1, 1)
		GameTooltip:AddLine("Shift-click: log", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	b:SetShown(not WM.db.minimap.hide)
	WM.minimap = b
end
