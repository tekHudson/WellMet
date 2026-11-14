--[[ WellMet — /wellmet ranktest: find out which rank the game accepts on a target of each level.

Stand somewhere crowded (a city) and turn it on. Every key press then picks a nearby player whose level has not been
tested yet and casts your highest rank of a buff on them BY ID. If the game says the target is too low level, the next
press tries the same player with the next rank down, until one is accepted. Each level is written down once:
which ranks were refused and which was accepted (kept per class). `/wellmet ranktest report` shows the table and what it says about the
level rule (the gap between a rank's learned level and the target's level); the results survive a /reload.

It buffs real players, so use it where that is welcome. Nothing happens in combat or without a key press.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local RankTest = {}
ns.RankTest = RankTest

local MAX_ERRORS = 2        -- other failures (range, line of sight ...) for one level before it is given up on

RankTest.active = false

-- Results are kept per class (Mage and Paladin buffs have different ranks), in WM.db.rankTest[classToken][target level].
local function results()
	WM.db.rankTest = WM.db.rankTest or {}
	WM.db.rankTest[WM.classToken] = WM.db.rankTest[WM.classToken] or {}
	return WM.db.rankTest[WM.classToken]
end

local function readableLevel(unit)
	local level = UnitLevel(unit)
	if issecretvalue(level) or type(level) ~= "number" or level < 1 then return nil end
	return level
end

-- The buff to test with: the first learned, non-self buff with two or more ranks (strangers can't take party-only ones).
local function testBuff(cand)
	for _, key in ipairs(WM.caster.order) do
		local buff = WM.caster.buffs[key]
		if not buff.selfOnly and not (buff.partyOnly and cand.tier == 2) and ns.IsKnown(buff) and #ns.Ranks(buff.name) >= 2 then
			return buff
		end
	end
end

-- The next rank to try on a level: the highest one below every rank already refused there.
local function nextRank(buff, rec)
	local floor = math.huge
	for _, level in ipairs(rec.refused) do floor = math.min(floor, level) end
	for _, rank in ipairs(ns.Ranks(buff.name)) do
		if rank.level < floor then return rank end
	end
end

-- Choose who to cast on. cands: Discovery's list. Returns { cand, buff, rank, level } or nil + a reason.
function RankTest.Next(cands)
	local res = results()
	-- a level that is still being worked out comes first (its person is refused / retried until a rank is accepted)
	for level, rec in pairs(res) do
		if not rec.done then
			for _, cand in ipairs(cands) do
				if cand.tier ~= 0 and cand.key == rec.key then
					local buff = WM.caster.buffs[rec.buff]
					local rank = buff and nextRank(buff, rec)
					if rank then return { cand = cand, buff = buff, rank = rank, level = level } end
					rec.done = true
				end
			end
		end
	end
	-- otherwise the nearest player at a level not tested yet
	local best, bestDist
	local why = { others = 0, noName = 0, noLevel = 0, tested = 0, noBuff = 0, range = 0 }
	for _, cand in ipairs(cands) do
		if cand.tier ~= 0 then
			why.others = why.others + 1
			if cand.tier == 2 and not cand.fullName then
				why.noName = why.noName + 1
			else
				local level = readableLevel(cand.unit)
				if not level then
					why.noLevel = why.noLevel + 1
				elseif res[level] then
					why.tested = why.tested + 1
				else
					local buff = testBuff(cand)
					if not buff then
						why.noBuff = why.noBuff + 1
					elseif ns.Probe.inRange(buff, cand.unit) ~= true then
						why.range = why.range + 1
					else
						local dist = ns.Probe.distance(cand) or math.huge
						if not best or dist < bestDist then best, bestDist = { cand = cand, buff = buff, level = level }, dist end
					end
				end
			end
		end
	end
	if not best then
		return nil, string.format("no player at a new level to cast on. Of %d other players found: %d at a level already tested, %d out of range, %d with an unreadable level, %d with no readable name, %d where no buff of yours has two or more ranks",
			why.others, why.tested, why.range, why.noLevel, why.noName, why.noBuff)
	end
	best.rank = nextRank(best.buff, { refused = {} })
	res[best.level] = { name = best.cand.name, key = best.cand.key, buff = best.buff.key, refused = {}, errors = 0, done = false }
	return best
end

local function rankOf(p)
	for _, rank in ipairs(ns.Ranks(p.spell)) do
		if rank.level == p.rankLevel then return rank end
	end
end

-- The cast was accepted by the game (UNIT_SPELLCAST_SUCCEEDED).
function RankTest.Accepted(p)
	local rec = results()[p.testLevel]
	if not rec then return end
	local rank = rankOf(p)
	rec.accepted, rec.done = rank and rank.sub or "?", true
	rec.acceptedLevel = p.rankLevel
	WM:Log("ranktest: level " .. p.testLevel .. " accepted " .. ns.SafeStr(rec.accepted) .. " (learned at " .. ns.SafeStr(p.rankLevel) .. ")")
	WM:Note("Rank test: level " .. p.testLevel .. " took " .. ns.SafeStr(rec.accepted) .. ".")
end

-- The cast failed. kind: "lowlevel" (the rank is too high for them) or anything else (range, line of sight, unknown).
function RankTest.Failed(p, message, kind)
	local rec = results()[p.testLevel]
	if not rec then return end
	if kind == "lowlevel" then
		rec.refused[#rec.refused + 1] = p.rankLevel
		WM:Log("ranktest: level " .. p.testLevel .. " refused rank learned at " .. ns.SafeStr(p.rankLevel) .. ": " .. ns.SafeStr(message))
		WM:Note("Rank test: level " .. p.testLevel .. " refused that rank. Press again for the next one down.")
	else
		rec.errors = rec.errors + 1
		rec.lastError = ns.SafeStr(message)
		WM:Log("ranktest: level " .. p.testLevel .. " failed with: " .. ns.SafeStr(message) .. " (" .. rec.errors .. "/" .. MAX_ERRORS .. ")")
		if rec.errors >= MAX_ERRORS then rec.done = true end
	end
end

function RankTest.Reset()      -- this class only
	WM.db.rankTest = WM.db.rankTest or {}
	WM.db.rankTest[WM.classToken] = {}
end

function RankTest.Toggle()
	RankTest.active = not RankTest.active
	return RankTest.active
end

-- The table, and what it says about the rule.
function RankTest.Report()
	local out = { "WellMet rank test  " .. date("%Y-%m-%d %H:%M:%S"), "client " .. ns.SafeStr((GetBuildInfo())) .. "  " .. ns.SafeStr(WM.classToken) .. "  player level " .. ns.SafeStr(UnitLevel("player")), "" }
	local res, levels = results(), {}
	for level in pairs(res) do levels[#levels + 1] = level end
	table.sort(levels)
	if #levels == 0 then out[#out + 1] = "nothing tested yet (/wellmet ranktest, then press the key near players)" end
	local maxAccepted, minRefused
	for _, level in ipairs(levels) do
		local rec = res[level]
		local buff = WM.caster.buffs[rec.buff]
		local refused = {}
		for _, rl in ipairs(rec.refused) do
			refused[#refused + 1] = rl .. "(gap " .. (rl - level) .. ")"
			minRefused = math.min(minRefused or math.huge, rl - level)
		end
		if rec.acceptedLevel then maxAccepted = math.max(maxAccepted or -math.huge, rec.acceptedLevel - level) end
		out[#out + 1] = string.format("target level %-3d %-12s %-18s refused (rank learned at level): %-28s accepted: %s%s", level, ns.SafeStr(rec.name), buff and buff.name or "?",
			#refused > 0 and table.concat(refused, " ") or "none", rec.accepted and (rec.accepted .. " (learned at " .. ns.SafeStr(rec.acceptedLevel) .. ", gap " .. (rec.acceptedLevel - level) .. ")") or (rec.done and "none" or "(in progress)"),
			rec.lastError and ("   last other error: " .. rec.lastError) or "")
	end
	out[#out + 1] = ""
	out[#out + 1] = "gap = the rank's learned level minus the target's level."
	if maxAccepted and minRefused then
		out[#out + 1] = string.format("largest gap accepted: %d   smallest gap refused: %d   %s", maxAccepted, minRefused,
			maxAccepted < minRefused and ("-> consistent: a rank works when gap <= " .. maxAccepted .. " (WellMet guesses " .. ns.RANK_LEVEL_GAP .. ")") or "-> NOT a single gap rule, send this report as it is")
	elseif maxAccepted then
		out[#out + 1] = "largest gap accepted: " .. maxAccepted .. "   (nothing refused yet, so the limit is not known)"
	end
	return table.concat(out, "\n")
end

function WM:RankTestCommand(arg)
	arg = (arg or ""):lower()
	if arg == "report" then
		WM:ShowLog(false, RankTest.Report())
	elseif arg == "reset" then
		RankTest.Reset(); WM:Print("rank test results cleared")
	else
		local on = RankTest.Toggle()
		if on then
			WM:Print("rank test ON: in a crowded place press your key repeatedly. Each press casts your highest rank of a buff on a player at a level not tested yet, then steps down while it is refused. /wellmet ranktest report shows the table; /wellmet ranktest turns it off.")
		else
			WM:Print("rank test OFF (/wellmet ranktest report shows the results)")
		end
	end
end
