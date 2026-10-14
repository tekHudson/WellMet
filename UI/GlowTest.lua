--[[ WellMet — TEMPORARY highlight test (not for release). Shows a row of labelled squares on screen at login, each using a
different highlight the client might have, so a screenshot shows which ones exist and how they look. /wellmet glowtest toggles it. ]]

local ADDON, ns = ...
if not ns.supported then return end
local WM = ns.WM

local frames
local ICON = "Interface\\Icons\\Spell_Holy_MagicalSentry"

local TESTS = {
	{ "1 gold border\n(current)", function(f)
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetPoint("CENTER"); t:SetSize(74, 74)
		t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); t:SetBlendMode("ADD"); t:SetVertexColor(1, 0.8, 0.25)
		return "ok"
	end },
	{ "2 ActionButton_\nShowOverlayGlow", function(f)
		if not ActionButton_ShowOverlayGlow then return "missing" end
		ActionButton_ShowOverlayGlow(f); return "ok"
	end },
	{ "3 ActionButtonSpell\nAlertManager", function(f)
		if not ActionButtonSpellAlertManager then return "missing" end
		ActionButtonSpellAlertManager:ShowAlert(f); return "ok"
	end },
	{ "4 AutoCastShine\n(sparkles)", function(f)
		local s = CreateFrame("Frame", nil, f, "AutoCastShineTemplate")
		s:SetAllPoints(f)
		if AutoCastShine_AutoCastStart then AutoCastShine_AutoCastStart(s) else return "no start fn" end
		return "ok"
	end },
	{ "5 ActionBarButton\nSpellActivationAlert", function(f)
		local a = CreateFrame("Frame", nil, f, "ActionBarButtonSpellActivationAlert")
		a:SetSize(40 * 1.4, 40 * 1.4); a:SetPoint("CENTER")
		if a.animIn then a.animIn:Play() elseif a.ProcStartAnim then a.ProcStartAnim:Play() end
		return "ok"
	end },
}

local function build()
	frames = {}
	local seen = {}
	for i, test in ipairs(TESTS) do
		local f = CreateFrame("Frame", "WellMetGlowTest" .. i, UIParent)
		f:SetSize(40, 40)
		f:SetPoint("CENTER", UIParent, "CENTER", (i - 3) * 120, 160)
		f:SetFrameStrata("HIGH")
		local icon = f:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(); icon:SetTexture(ICON)
		local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOP", f, "BOTTOM", 0, -26)
		local ok, result = pcall(test[2], f)
		label:SetText(test[1] .. "\n" .. (ok and result or ("ERROR " .. tostring(result))))
		seen[#seen + 1] = test[1]:gsub("\n", " ") .. ": " .. (ok and result or ("ERROR " .. tostring(result)))
		frames[i] = f
	end
	WM:Print("glow test (screenshot the row above your character):\n  " .. table.concat(seen, "\n  "))
end

function WM:GlowTest(show)
	if frames then
		if show == false or (show == nil and frames[1]:IsShown()) then
			for _, f in ipairs(frames) do f:Hide() end
		else
			for _, f in ipairs(frames) do f:Show() end
		end
		return
	end
	pcall(build)
end
