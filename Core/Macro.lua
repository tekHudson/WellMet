--[[ WellMet — writes the "/click WellMetCast" macro for you.

The macro buffs you and your group (the key is for strangers: the game won't run WellMet's targeting macro
from inside another macro). It uses the icon Tek picked for his own WM macro (file id 4630437; a macro can
only use an icon from the game's own list, so the gold WM texture the addon ships can't be used here).
It never overwrites a macro: if "WM" already exists and does something else, it says so and stops.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local MACRO_NAME = "WM"
local MACRO_ICON = 4630437
local MACRO_BODY = "/click WellMetCast"

-- The index of the macro called `name` (account macros come first, then this character's), and its body.
local function findMacro(name)
	local last = Constants.MacroConsts.MAX_ACCOUNT_MACROS + Constants.MacroConsts.MAX_CHARACTER_MACROS
	for index = 1, last do
		local macroName, _, body = GetMacroInfo(index)
		if macroName == name then return index, body end
	end
end

-- Creates the macro (or finds the one you already have) and puts it on the cursor, ready to drop on a bar.
function WM:CreateMacro()
	if InCombatLockdown() then
		WM:Print("Can't make a macro in combat.")
		return
	end
	local index, body = findMacro(MACRO_NAME)
	if index then
		if not (body and body:find(MACRO_BODY, 1, true)) then
			WM:Print("You already have a macro called \"" .. MACRO_NAME .. "\" that does something else. Rename or delete it, then try again.")
			return
		end
		PickupMacro(index)
		WM:Print("Your \"" .. MACRO_NAME .. "\" macro is on your cursor: click an action bar slot to place it.")
		return
	end

	local maxAccount, maxCharacter = Constants.MacroConsts.MAX_ACCOUNT_MACROS, Constants.MacroConsts.MAX_CHARACTER_MACROS
	local numAccount, numCharacter = GetNumMacros()
	local forCharacter = numAccount >= maxAccount            -- account macros are shared by all your characters
	if forCharacter and numCharacter >= maxCharacter then
		WM:Print("No free macro slot. Delete a macro and try again.")
		return
	end
	index = CreateMacro(MACRO_NAME, MACRO_ICON, MACRO_BODY, forCharacter)
	PickupMacro(index)
	WM:Print("Macro \"" .. MACRO_NAME .. "\" created and on your cursor: click an action bar slot to place it.")
end
