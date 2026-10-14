--[[ WellMet — buff back: whoever just buffed you goes to the front of the list.

When another player puts a NEW buff on you, they are remembered for 10 seconds. A key press in that time tries them first,
if they need a buff (the same rules as any press: in range, learned, section on, not just tried). Once the cast is sent,
or after 10 seconds, they are forgotten. Only new buffs count, and only when the game says who cast them: a caster the
game does not name (a stranger out of sight, an NPC) is ignored. Nothing is tracked in combat, when auras are hidden.

On by default (settings > Refresh running-out buffs > Buff back first).
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local BuffBack = {}
ns.BuffBack = BuffBack

local SECONDS = 10
BuffBack.SECONDS = SECONDS
local recent = {}          -- guid -> { name, at }

function BuffBack.Note(guid, name, now)
	recent[guid] = { name = name, at = now }
end

function BuffBack.Forget(guid)
	recent[guid] = nil
end

-- guid -> record of everyone who buffed you in the last 10 seconds ({} when nobody; nil while the setting is off).
function BuffBack.Active(now)
	if not WM.db.buffBack.enabled then return nil end
	local set = {}
	for guid, rec in pairs(recent) do
		if now - rec.at > SECONDS then recent[guid] = nil else set[guid] = rec end
	end
	return set
end

local function readable(v) return v ~= nil and not issecretvalue(v) end

-- UNIT_AURA on you: note the casters of buffs that were just added.
function BuffBack.OnAura(unit, info)
	if unit ~= "player" or not WM.db.buffBack.enabled then return end
	if InCombatLockdown() or not ns.AurasReadable() then return end
	if type(info) ~= "table" or issecrettable(info) or type(info.addedAuras) ~= "table" then return end
	for _, aura in ipairs(info.addedAuras) do
		if type(aura) == "table" and not issecrettable(aura) and aura.isHelpful ~= false then
			local source = aura.sourceUnit
			if readable(source) and not UnitIsUnit("player", source) and UnitIsPlayer(source) then
				local guid = UnitGUID(source)
				if readable(guid) then
					local name = UnitName(source)
					BuffBack.Note(guid, readable(name) and name or "?", GetTime())
					WM:Log("buffed by " .. ns.SafeStr(name) .. " (" .. ns.SafeStr(aura.name) .. "): first in line for " .. SECONDS .. "s")
				end
			end
		end
	end
end

local frame = CreateFrame("Frame")
ns.buffBackFrame = frame
frame:SetScript("OnEvent", function(_, _, unit, info) BuffBack.OnAura(unit, info) end)

-- Listen only while the setting is on (called at login and when it changes).
function WM:ApplyBuffBack()
	if WM.db.buffBack.enabled then frame:RegisterUnitEvent("UNIT_AURA", "player") else frame:UnregisterEvent("UNIT_AURA") end
end
