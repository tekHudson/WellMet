--[[ WellMet — who is around?

Candidates, nearest tier first:
  tier 0  you
  tier 1  group members (party / raid units)
  tier 2  everyone else: your target, and friendly-player nameplates

Strangers can ONLY be found through nameplates (there is no API to list nearby
players), so "Friendly Player Nameplates" must be on. Candidates are deduplicated
by GUID so a group member who also has a nameplate is counted once, as tier 1.

Every identity read is guarded: Forever can hand back secret values, which we
treat as "unknown" (class -> nil -> the "unknown class" default; guid -> a
per-unit fallback key).
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local Discovery = {}
ns.Discovery = Discovery

local seen = {}        -- candidate key -> { order = arrival serial, last = time last seen }
local serial = 0

local function safe(v)
	if issecretvalue(v) then return nil end
	return v
end

-- Is friendly-player nameplate display on? (CVar string "1"/"0"; nil if unavailable.)
function Discovery.NameplatesOn()
	local v = GetCVar("nameplateShowFriendlyPlayers")
	if v == nil then return nil end
	return v == "1"
end

-- Forever names are "First Last", but UnitName on a stranger gives only the first word.
-- `/targetexact` needs the whole name, and the only place it is readable is the text on the
-- player's own nameplate. The name's FontString has been named differently from build to build, so
-- every text field on the plate (its UnitFrame first, then the plate itself) is looked at, and the
-- one that reads exactly "<their first name> <one more word>" is the full name.
-- Returns "First Last", or nil + a plain reason (what was hidden or what the plate showed instead).
local function plateFullName(plate, firstName)
	if type(firstName) ~= "string" then return nil, "UnitName is hidden" end
	local seen, hidden = {}, 0
	local function look(owner)
		for _, region in pairs(owner) do
			if type(region) == "table" and type(region.GetText) == "function" then
				local text = region:GetText()
				if issecretvalue(text) then
					hidden = hidden + 1
				elseif type(text) == "string" and text ~= "" then
					text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
					local first, last = text:match("^(%S+)%s+(%S+)$")
					if first == firstName and not text:find("[\r\n|/;]") then return first .. " " .. last end
					seen[#seen + 1] = text
				end
			end
		end
	end
	local frame = plate and plate.UnitFrame
	local found = (frame and look(frame)) or (plate and look(plate))
	if found then return found end
	if hidden > 0 and #seen == 0 then return nil, "the plate's text is hidden (" .. hidden .. " field(s))" end
	if #seen == 0 then return nil, "the plate has no readable text" end
	return nil, "no plate text reads '" .. firstName .. " <one word>' (saw: " .. table.concat(seen, " | ", 1, math.min(#seen, 4)) .. ")"
end

-- Build a candidate for `unit`, or nil + the reason it was rejected.
local function describe(unit, tier, plate)
	if not UnitExists(unit) then return nil, "does not exist" end
	if not UnitIsPlayer(unit) then return nil, "not a player" end
	if not UnitCanAssist("player", unit) then return nil, "can't assist" end
	if UnitIsDeadOrGhost(unit) then return nil, "dead" end
	if tier == 1 and not UnitIsConnected(unit) then return nil, "offline" end
	if not UnitIsVisible(unit) then return nil, "not visible" end
	local guid = safe(UnitGUID(unit))
	local _, class = UnitClass(unit)
	local name = safe(UnitName(unit))
	local fullName
	if plate then
		local why
		fullName, why = plateFullName(plate, name)
		if not fullName then return nil, "full name not readable from the nameplate: " .. why end
	end
	return {
		unit = unit, tier = tier, guid = guid,
		key = guid or ("unit:" .. unit),
		name = name or unit,
		fullName = fullName,
		class = safe(class),
	}
end

local function groupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	else
		for i = 1, 4 do units[#units + 1] = "party" .. i end
	end
	return units
end

-- Returns: candidates (list), rejected (list of { unit, reason }), info (table).
function Discovery.Discover()
	local now = GetTime()
	local list, byKey, rejected = {}, {}, {}
	local info = { nameplates = 0 }

	local function add(unit, tier, order, plate)
		local cand, why = describe(unit, tier, plate)
		if not cand then
			rejected[#rejected + 1] = { unit = unit, reason = why }
			return
		end
		if byKey[cand.key] then return end            -- already counted at a better tier
		byKey[cand.key] = cand
		local rec = seen[cand.key]
		if not rec then serial = serial + 1; rec = { order = serial }; seen[cand.key] = rec end
		rec.last = now
		cand.order = order or rec.order
		list[#list + 1] = cand
	end

	add("player", 0, 0)

	if WM.db.party.enabled then
		for _, unit in ipairs(groupUnits()) do
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				add(unit, 1, tonumber(unit:match("%d+")) or 0)
			end
		end
	end

	if WM.db.others.enabled and UnitExists("target") and not UnitIsUnit("target", "player") then
		add("target", 2)
	end

	if WM.db.others.enabled then
		local plates = C_NamePlate.GetNamePlates()
		info.nameplates = plates and #plates or 0
		for _, plate in ipairs(plates or {}) do
			local unit = plate:GetUnit()          -- Blizzard_NamePlateBase.lua; there is no namePlateUnitToken field
			if unit then
				add(unit, 2, nil, plate)
			else
				rejected[#rejected + 1] = { unit = "(nameplate)", reason = "plate has no unit" }
			end
		end
	end

	-- Forget people we haven't seen for a while so the table can't grow forever.
	for key, rec in pairs(seen) do
		if now - rec.last > 120 then seen[key] = nil end
	end
	return list, rejected, info
end

-- Nameplate events only matter for logging; the list is rebuilt on every press.
function WM:NAME_PLATE_UNIT_ADDED() end
function WM:NAME_PLATE_UNIT_REMOVED() end
