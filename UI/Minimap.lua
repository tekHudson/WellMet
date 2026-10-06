--[[ WellMet — minimap button (native, no libraries).

Left-click opens the settings, right-click opens the copyable log, drag moves it around the
minimap. The icon is Icons/Icon.tga: "WM" in IM Fell English SC (SIL OFL), antiqued gold on dark
grey, 128x128.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local ICON = "Interface\\AddOns\\WellMet\\Icons\\Icon"
local RIM = 5        -- how far past the minimap's edge the button's centre sits (on the border art)

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
		if button == "RightButton" then WM:ShowLog() else WM:OpenOptions() end
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
		GameTooltip:AddLine("Right-click: log", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	b:SetShown(not WM.db.minimap.hide)
	WM.minimap = b
end
