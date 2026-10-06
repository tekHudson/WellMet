-- Headless tests for WellMet. Stubs a controllable WoW world and loads the real
-- addon files in TOC order.  Run from the repo root:  luajit tests/run.lua  (or lua)
--
-- Stubs mirror the documented Forever API (wow-ui-source `forever` branch). They
-- guard logic and structure; they do not replace tests/TEST_PLAN.md in-game.

local unpack = unpack or table.unpack
local failures, passes = 0, 0
local function check(name, cond, detail)
	if cond then passes = passes + 1; print("  ok   " .. name)
	else failures = failures + 1; print("  FAIL " .. name .. (detail and (" -- " .. tostring(detail)) or "")) end
end

local function readFile(path)
	local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close(); return s
end

----------------------------------------------------------------------
-- World + environment
----------------------------------------------------------------------
local function newWorld()
	local W = {
		now = 1000, combat = false, mounted = false, flying = false, taxi = false,
		restricted = false, raid = false, groupSize = 0,
		cvars = { nameplateShowFriendlyPlayers = "1" },
		units = {}, plates = {}, known = {}, spells = {},
		bindings = {},           -- key -> action (pre-existing bindings)
		overrides = {},          -- key -> action set by addon
		prints = {}, sentCalls = 0,
	}
	W.spells = { ["Blessing of Might"] = 19834, ["Blessing of Wisdom"] = 19742 }
	W.known = { [19834] = true, [19742] = true }
	return W
end

-- Add a unit to the world. opts: class, guid, name, dist (yards), interact ('near'|'mid'|nil), auras {names}, inRange
local function addUnit(W, unit, opts)
	opts = opts or {}
	W.units[unit] = {
		exists = true, isPlayer = opts.isPlayer ~= false, canAssist = opts.canAssist ~= false,
		dead = opts.dead or false, connected = opts.connected ~= false, visible = opts.visible ~= false,
		guid = opts.guid or ("Player-" .. unit), name = opts.name or unit, class = opts.class,
		distSq = opts.dist and opts.dist * opts.dist or nil, checked = opts.dist ~= nil,
		interact = opts.interact, auras = opts.auras or {}, inRange = (opts.inRange == nil) and true or opts.inRange,
		secretGuid = opts.secretGuid, secretClass = opts.secretClass,
	}
	return W.units[unit]
end

local SECRET = { __secret = true }

local function proxy()
	local p = {}
	return setmetatable(p, { __index = function() return proxy() end, __call = function() return proxy() end })
end

local function newEnv(W)
	local E = { W = W, frames = {} }
	local g = setmetatable({}, { __index = _G })
	E.g = g
	g._G = g
	g.unpack = unpack
	g.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	g.table = setmetatable({ wipe = g.wipe }, { __index = table })
	g.tostringall = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return unpack(t) end
	g.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
	g.date = os.date
	g.UISpecialFrames = {}
	g.SlashCmdList = {}
	if not string.trim then string.trim = function(str) return (str:gsub("^%s+", ""):gsub("%s+$", "")) end end
	g.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end W.prints[#W.prints + 1] = table.concat(t, " ") end

	g.GetTime = function() return W.now end
	g.GetBuildInfo = function() return "1.60.1", "70205", "Oct 3 2026", 16001 end
	g.C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
	g.InCombatLockdown = function() return W.combat end
	g.IsMounted = function() return W.mounted end
	g.IsFlying = function() return W.flying end
	g.UnitOnTaxi = function() return W.taxi end
	g.IsInRaid = function() return W.raid end
	g.GetNumGroupMembers = function() return W.groupSize end
	g.IsAltKeyDown = function() return false end
	g.IsControlKeyDown = function() return false end
	g.IsShiftKeyDown = function() return false end
	g.GetCVar = function(k) return W.cvars[k] end
	g.SetCVar = function(k, v) W.cvars[k] = tostring(v) end
	g.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
		SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
	g.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
	g.SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight"
	g.SPELL_FAILED_OUT_OF_RANGE = "Out of range"
	g.ERR_OUT_OF_RANGE = "Out of range."
	g.SPELL_FAILED_VISION_OBSCURED = "Vision obscured"
	g.SPELL_FAILED_AURA_BOUNCED = "A more powerful spell is already active"

	-- frames: stateful attributes/scripts, everything else a harmless proxy
	g.CreateFrame = function(kind, name, parent, template)
		local f = { attrs = {}, scripts = {}, kind = kind, name = name, template = template }
		function f:SetAttribute(k, v) self.attrs[k] = v end
		function f:GetAttribute(k) return self.attrs[k] end
		function f:SetScript(k, fn) self.scripts[k] = fn end
		function f:GetScript(k) return self.scripts[k] end
		function f:GetName() return self.name end
		function f:GetChecked() return self.checked end
		function f:SetChecked(v) self.checked = v end
		function f:GetText() return self.text end
		function f:SetText(t) self.text = t end
		function f:SetPoint(...) self.lastPoint = { ... } end
		function f:SetupMenu(fn) self.menuGen = fn end
		function f:SetSelectionTranslator(fn) self.selTranslator = fn end
		function f:SetSelectionText(fn) self.selText = fn end
		function f:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
		function f:RegisterUnitEvent(e) self.events = self.events or {}; self.events[e] = true end
		E.frames[#E.frames + 1] = f
		if name then g[name] = f end
		return setmetatable(f, { __index = function() return proxy() end })
	end

	-- units
	local function U(unit) return W.units[unit] end
	g.UnitExists = function(u) return U(u) ~= nil and U(u).exists end
	g.UnitIsPlayer = function(u) return U(u) and U(u).isPlayer end
	g.UnitCanAssist = function(_, u) return U(u) and U(u).canAssist end
	g.UnitIsDeadOrGhost = function(u) return U(u) and U(u).dead end
	g.UnitIsConnected = function(u) return U(u) and U(u).connected end
	g.UnitIsVisible = function(u) return U(u) and U(u).visible end
	g.UnitGUID = function(u) local x = U(u); if not x then return nil end; if x.secretGuid then return SECRET end; return x.guid end
	g.UnitName = function(u) return U(u) and U(u).name end
	g.UnitClass = function(u) local x = U(u); if not x then return nil end; if x.secretClass then return SECRET, SECRET end; return x.class, x.class end
	g.UnitIsUnit = function(a, b) return U(a) and U(b) and U(a).guid == U(b).guid end
	g.UnitDistanceSquared = function(u) local x = U(u); if not x then return 0, false end; return x.distSq or 0, x.checked end
	g.CheckInteractDistance = function(u, i)
		local x = U(u); if not x then return false end
		if i == 3 then return x.interact == "near" end
		if i == 1 then return x.interact == "near" or x.interact == "mid" end
		return false
	end
	g.issecretvalue = function(v) return v == SECRET end
	g.issecrettable = function(v) return type(v) == "table" and v.__secret == true end

	-- spells / auras / secrets
	g.C_Spell = {
		GetSpellInfo = function(name) local id = W.spells[name]; return id and { name = name, spellID = id, iconID = 1000000 + id } or nil end,
		GetSpellName = function(id) for n, i in pairs(W.spells) do if i == id then return n end end end,
		IsSpellInRange = function(name, unit) local x = U(unit); if not x then return nil end; return x.inRange end,
	}
	g.C_SpellBook = { IsSpellKnown = function(id) return W.known[id] or false end }
	g.C_Secrets = {
		ShouldAurasBeSecret = function() return W.restricted end,
		HasSecretRestrictions = function() return true end,
	}
	g.C_UnitAuras = {
		GetAuraDataBySpellName = function(unit, name)
			if W.restricted then return nil end
			local x = U(unit); if x and x.auras[name] then return { name = name } end
		end,
	}
	g.C_NamePlate = { GetNamePlates = function() local t = {} for i, tok in ipairs(W.plates) do local u = W.units[tok]
		t[i] = { GetUnit = function() return tok end,
			UnitFrame = { name = { GetText = function() return u and (u.plateText or (u.name .. " Surname")) end } } } end return t end }

	-- bindings
	g.Minimap = { GetWidth = function() return 198 end, GetCenter = function() return 0, 0 end, GetEffectiveScale = function() return 1 end }
	g.C_Timer = { After = function(_, fn) fn() end }        -- run at once; the real delay doesn't matter here
	g.GetBindingAction = function(key) return W.overrides[key] or W.bindings[key] or "" end
	g.GetBindingKey = function(action) for key, a in pairs(W.bindings) do if a == action then return key end end end
	g.ClearOverrideBindings = function() W.overrides = {} end
	g.SetOverrideBindingClick = function(_, _, key, btn, mouse) W.overrides[key] = "CLICK " .. btn .. ":" .. mouse end

	-- settings
	g.Settings = {
		RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
		RegisterAddOnCategory = function() end,
		OpenToCategory = function(id, section) W.openedCategory = id; W.openedSection = section end,
	}
	return E
end

local TOC_FILES = {}
for line in readFile("WellMet_Camelot.toc"):gmatch("[^\r\n]+") do
	if line:match("%.lua$") and not line:match("^#") then TOC_FILES[#TOC_FILES + 1] = (line:gsub("\\", "/")) end
end

local function load(opts)
	opts = opts or {}
	local W = newWorld()
	local E = newEnv(W)
	local ns = {}
	addUnit(W, "player", { class = opts.class or "PALADIN", name = "Tek", guid = "Player-Tek" })    -- before the files load: the class decides
	for _, f in ipairs(TOC_FILES) do
		local chunk, err = loadfile(f, "t", E.g)
		if not chunk then error(err) end
		if setfenv then setfenv(chunk, E.g) end
		chunk("WellMet", ns)
	end
	local WM = ns.WM
	if not ns.supported then return nil, ns, E, W end
	WM:ADDON_LOADED("ADDON_LOADED", "WellMet")
	if opts.login ~= false then WM:PLAYER_LOGIN() end
	if WM.db and opts.debug ~= false then WM.db.debug = true end     -- most checks read press messages / the log
	return WM, ns, E, W
end

local function press(E)
	local b = E.g.WellMetCast
	b.scripts.PreClick(b, "LeftButton", true)
	return b
end

local function printed(W, needle)
	for _, p in ipairs(W.prints) do if p:find(needle, 1, true) then return true end end
	return false
end

----------------------------------------------------------------------
print("== Structure")
do
	local files = {}
	for _, f in ipairs(TOC_FILES) do files[#files + 1] = f end
	local allExist = true
	for _, f in ipairs(files) do local h = io.open(f); if h then h:close() else allExist = false end end
	check("every file listed in the TOC exists", allExist and #files > 5)
	local toc = readFile("WellMet_Camelot.toc")
	check("TOC targets Forever (Interface 16001)", toc:find("## Interface: 16001", 1, true) ~= nil)
	check("no unsuffixed WellMet.toc (Forever-only)", io.open("WellMet.toc") == nil)
	check("Bindings.xml binds the cast button", readFile("Bindings.xml"):find("CLICK WellMetCast:LeftButton", 1, true) ~= nil)
	check("SavedVariables declared", toc:find("## SavedVariables: WellMetDB", 1, true) ~= nil)

	-- Forever has no flat legacy globals; none may creep in.
	local forbidden = { "[^_%.%w]GetSpellInfo%(", "[^_%.%w]GetItemCount%(", "IsPlayerSpell", "[^_%.%w]UnitAura%(", "[^_%.%w]UnitBuff%(",
		"[^_%.%w]UnitDebuff%(", "[^_%.%w]GetSpellCooldown%(", "InterfaceOptions_AddCategory", "[^_%.%w]IsSpellKnown%(" }
	local clean, bad = true, nil
	for _, f in ipairs(files) do
		local n = 0
		for line in readFile(f):gmatch("[^\n]*") do
			n = n + 1
			local code = line:gsub("%-%-.*$", "")
			for _, pat in ipairs(forbidden) do
				if code:find(pat) then clean = false; bad = bad or (f .. ":" .. n .. " " .. pat) end
			end
		end
	end
	check("no legacy/removed globals in the code", clean, bad)
	-- Select.lua must stay pure (no WoW API calls, so it stays unit-testable).
	local pure = true
	for line in readFile("Core/Select.lua"):gmatch("[^\n]*") do
		local code = line:gsub("%-%-.*$", "")
		if code:find("C_%u") or code:find("%f[%w]Unit%u%w*%(") or code:find("CreateFrame") then pure = false end
	end
	check("Core/Select.lua makes no WoW API calls", pure)
end

----------------------------------------------------------------------
print("== Selection logic (pure)")
do
	local WM, ns, E, W = load()
	local Select = ns.Select
	local MIGHT, WISDOM = WM.caster.buffs.MIGHT, WM.caster.buffs.WISDOM

	local function cand(key, tier, class, order, extra)
		local c = { unit = key, key = key, name = key, tier = tier, class = class, order = order or 1 }
		for k, v in pairs(extra or {}) do c[k] = v end
		return c
	end
	-- fake probe: tables keyed by cand key
	local function probe(opts)
		opts = opts or {}
		return {
			known = function(buff) if opts.known then return opts.known[buff.key] end return true end,
			inRange = function(_, unit) if opts.range and opts.range[unit] ~= nil then return opts.range[unit] end return true end,
			lacks = function(unit) if opts.has and opts.has[unit] == "unknown" then return nil end if opts.has and opts.has[unit] then return false end return true end,
			distance = function(c) return opts.dist and opts.dist[c.key] or nil end,
		}
	end
	local function settings(over)
		local s = { assign = {}, strangers = true, groupFirst = true, includeSelf = true, radius = 0 }
		for k, v in pairs(over or {}) do s[k] = v end
		return s
	end
	local function ctx(p, s) return { now = 100, settings = s or settings(), caster = WM.caster, probe = p or probe() } end

	local best = Select.Pick({ cand("stranger", 2, "MAGE", 1), cand("grp", 1, "MAGE", 1), cand("me", 0, "PALADIN", 0) }, ctx())
	check("tier order: you, then group, then strangers", best.cand.key == "me")
	best = Select.Pick({ cand("stranger", 2, "MAGE", 1), cand("grp", 1, "MAGE", 1) }, ctx())
	check("group before strangers", best.cand.key == "grp")
	best = Select.Pick({ cand("stranger", 2, "MAGE", 1), cand("grp", 1, "MAGE", 1) }, ctx(nil, settings({ groupFirst = false })))
	check("group-first off: strangers rank equal to group (by distance/order)", best.cand.key == "stranger" or best.cand.key == "grp")
	best = Select.Pick({ cand("far", 2, "MAGE", 1), cand("near", 2, "MAGE", 2) }, ctx(probe({ dist = { far = 28, near = 10 } })))
	check("nearest first within a tier", best.cand.key == "near")
	best = Select.Pick({ cand("unknownDist", 2, "MAGE", 1), cand("known", 2, "MAGE", 2) }, ctx(probe({ dist = { known = 28 } })))
	check("unknown distance sorts last", best.cand.key == "known")
	best = Select.Pick({ cand("b", 2, "MAGE", 5), cand("a", 2, "MAGE", 2) }, ctx())
	check("ties break by arrival order", best.cand.key == "a")

	-- filters
	local _, skipped = Select.Pick({ cand("has", 2, "MAGE") }, ctx(probe({ has = { has = true } })))
	check("skips someone who already has the buff", #skipped == 1 and skipped[1].reason:find("already has", 1, true) ~= nil)
	_, skipped = Select.Pick({ cand("u", 2, "MAGE") }, ctx(probe({ has = { u = "unknown" } })))
	check("skips (not buffs) when aura info is unreadable", #skipped == 1 and skipped[1].reason:find("unavailable", 1, true) ~= nil)
	_, skipped = Select.Pick({ cand("o", 2, "MAGE") }, ctx(probe({ range = { o = false } })))
	check("skips out of cast range", skipped[1] and skipped[1].reason == "out of cast range")
	_, skipped = Select.Pick({ cand("o", 2, "MAGE") }, ctx(probe({ range = { o = false } })))
	local nilRangeBest, nilSkipped = Select.Pick({ cand("o", 2, "MAGE") }, ctx(probe({ range = { o = nil } })))
	check("range check defaults to in-range in the fake probe", nilRangeBest ~= nil)
	_, skipped = Select.Pick({ cand("x", 2, "MAGE") }, ctx(probe({ known = { WISDOM = false, MIGHT = false } })))
	check("skips when the spell isn't learned", skipped[1] and skipped[1].reason:find("not learned", 1, true) ~= nil)
	_, skipped = Select.Pick({ cand("me", 0, "PALADIN") }, ctx(nil, settings({ includeSelf = false })))
	check("self can be turned off", skipped[1] and skipped[1].reason:find("yourself", 1, true) ~= nil)
	_, skipped = Select.Pick({ cand("s", 2, "MAGE") }, ctx(nil, settings({ strangers = false })))
	check("strangers can be turned off", skipped[1] and skipped[1].reason:find("outside the group", 1, true) ~= nil)

	-- radius
	local pk = probe({ dist = { near = 10, mid = 28 } })
	best = Select.Pick({ cand("mid", 2, "MAGE", 1), cand("near", 2, "MAGE", 2), cand("far", 2, "MAGE", 3) }, ctx(pk, settings({ radius = 10 })))
	check("10 yd radius keeps only the 10 yd bracket", best.cand.key == "near")
	local _, sk = Select.Pick({ cand("mid", 2, "MAGE", 1), cand("far", 2, "MAGE", 3) }, ctx(pk, settings({ radius = 10 })))
	check("outside-radius targets are skipped (incl. unknown distance)", #sk == 2)
	best = Select.Pick({ cand("mid", 2, "MAGE", 1) }, ctx(pk, settings({ radius = 28 })))
	check("28 yd radius accepts the 28 yd bracket", best and best.cand.key == "mid")

	-- assignments
	best = Select.Pick({ cand("w", 2, "WARRIOR") }, ctx())
	check("warrior gets Might by default", best.buff.key == "MIGHT")
	best = Select.Pick({ cand("m", 2, "MAGE") }, ctx())
	check("mage gets Wisdom by default", best.buff.key == "WISDOM")
	best = Select.Pick({ cand("w", 2, "WARRIOR") }, ctx(nil, settings({ assign = { WARRIOR = "WISDOM" } })))
	check("assignment override is honored", best.buff.key == "WISDOM")
	_, skipped = Select.Pick({ cand("w", 2, "WARRIOR") }, ctx(nil, settings({ assign = { WARRIOR = "NONE" } })))
	check("a class set to Skip is skipped", skipped[1] and skipped[1].reason:find("skip this class", 1, true) ~= nil)
	best, skipped = Select.Pick({ cand("?", 2, nil) }, ctx())
	check("a person whose class can't be read is skipped, with a reason", best == nil and skipped[1].reason:find("class not readable", 1, true) ~= nil)

	-- rotation memory
	Select.Reset()
	local list = { cand("a", 2, "MAGE", 1), cand("b", 2, "MAGE", 2) }
	best = Select.Pick(list, ctx())
	Select.Mark(best.cand.key, best.buff.name, 8, 100)
	local second = Select.Pick(list, ctx())
	check("after trying A, the next press picks B", best.cand.key == "a" and second.cand.key == "b")
	local c3 = { now = 109, settings = settings(), caster = WM.caster, probe = probe() }
	local third = Select.Pick(list, c3)
	check("the memory expires", third.cand.key == "a")
	Select.Reset()
	check("Reset clears the memory", Select.Pick(list, ctx()).cand.key == "a")
end

----------------------------------------------------------------------
print("== Discovery")
do
	local WM, ns, E, W = load()
	local D = ns.Discovery
	W.groupSize = 3
	addUnit(W, "party1", { class = "WARRIOR", name = "Wally", guid = "G-wally", dist = 12 })
	addUnit(W, "party2", { class = "MAGE", name = "Mia", guid = "G-mia", dist = 30 })
	addUnit(W, "nameplate1", { class = "PRIEST", name = "Stranger", guid = "G-stranger" })
	addUnit(W, "nameplate2", { class = "MAGE", name = "MiaPlate", guid = "G-mia" })      -- same person as party2
	addUnit(W, "nameplate3", { isPlayer = false, name = "Boar" })
	addUnit(W, "nameplate4", { canAssist = false, name = "EnemyPlayer", class = "ROGUE" })
	addUnit(W, "nameplate5", { dead = true, name = "Ghost", class = "HUNTER" })
	W.plates = { "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5" }
	local list, rejected, info = D.Discover()
	local byName = {}
	for _, c in ipairs(list) do byName[c.name] = c end
	check("includes you (tier 0), group (tier 1), strangers (tier 2)",
		byName.Tek and byName.Tek.tier == 0 and byName.Wally.tier == 1 and byName.Stranger.tier == 2)
	check("a group member with a nameplate is counted once, as group", byName.Mia and byName.Mia.tier == 1 and not byName.MiaPlate)
	check("non-players, hostiles and dead players are rejected", not byName.Boar and not byName.EnemyPlayer and not byName.Ghost and #rejected >= 3)
	check("reports how many nameplates it saw", info.nameplates == 5)
	check("group order follows the roster index", byName.Wally.order == 1 and byName.Mia.order == 2)

	-- secret identity is treated as unknown
	addUnit(W, "nameplate6", { class = "MAGE", name = "Hidden", secretGuid = true, secretClass = true })
	W.plates = { "nameplate6" }
	list = D.Discover()
	local hidden
	for _, c in ipairs(list) do if c.name == "Hidden" then hidden = c end end
	check("secret class/GUID: kept, class nil, per-unit key", hidden and hidden.class == nil and hidden.guid == nil and hidden.key == "unit:nameplate6")

	-- full name comes from the plate text; anything that isn't exactly "First Last" is rejected
	addUnit(W, "nameplate7", { class = "MAGE", name = "Ann" }); W.units.nameplate7.plateText = "|cffffffffAnn Lee|r"
	addUnit(W, "nameplate8", { class = "MAGE", name = "Bob" }); W.units.nameplate8.plateText = "Guild Master"
	addUnit(W, "nameplate9", { class = "MAGE", name = "Cyd" }); W.units.nameplate9.plateText = "Cyd"
	W.plates = { "nameplate7", "nameplate8", "nameplate9" }
	list, rejected = D.Discover()
	local full = {}
	for _, c in ipairs(list) do full[c.name] = c.fullName end
	check("stranger full name is read from the plate (colour codes stripped)", full.Ann == "Ann Lee")
	check("a plate whose text isn't 'First Last' is rejected with a reason", full.Bob == nil and full.Cyd == nil
		and #rejected == 2 and rejected[1].reason:find("full name", 1, true) ~= nil)

	-- strangers off: nameplates ignored
	WM.db.strangers = false
	W.plates = { "nameplate1" }
	list = D.Discover()
	local sawStranger
	for _, c in ipairs(list) do if c.name == "Stranger" then sawStranger = true end end
	check("nameplates are ignored when strangers are turned off", not sawStranger)
	WM.db.strangers = true

	-- target as a stranger
	W.plates = {}
	addUnit(W, "target", { class = "DRUID", name = "Targeted", guid = "G-targeted" })
	list = D.Discover()
	local sawTarget
	for _, c in ipairs(list) do if c.name == "Targeted" then sawTarget = c end end
	check("your friendly target is included as a stranger", sawTarget and sawTarget.tier == 2)

	W.cvars.nameplateShowFriendlyPlayers = "0"
	check("nameplate CVar is read", D.NameplatesOn() == false)
	W.cvars.nameplateShowFriendlyPlayers = nil
	check("unavailable CVar reads as unknown", D.NameplatesOn() == nil)
end

----------------------------------------------------------------------
print("== Spells / auras")
do
	local WM, ns, E, W = load()
	local MIGHT = WM.caster.buffs.MIGHT
	check("spell resolves by name to the known rank id", ns.SpellId(MIGHT) == 19834 and ns.IsKnown(MIGHT) == true)
	check("InitSpells records id + known on the buff", MIGHT.id == 19834 and MIGHT.known == true)
	W.known[19834] = nil
	check("a spell the player doesn't know is not known", ns.IsKnown(MIGHT) == false)
	W.known[19834] = true

	addUnit(W, "party1", { auras = { ["Blessing of Might"] = true } })
	addUnit(W, "party2", { auras = {} })
	addUnit(W, "party3", { auras = { ["Greater Blessing of Might"] = true } })
	check("Lacks: has the buff -> false", ns.Lacks("party1", MIGHT) == false)
	check("Lacks: missing -> true", ns.Lacks("party2", MIGHT) == true)
	check("Lacks: Greater version counts as having it", ns.Lacks("party3", MIGHT) == false)
	W.restricted = true
	check("Lacks: restricted + not seen -> nil (unknown, never 'missing')", ns.Lacks("party2", MIGHT) == nil)
	check("AurasReadable false under restrictions", ns.AurasReadable() == false)
	W.restricted = false

	check("Distance: you = 0", ns.Distance({ tier = 0, unit = "player" }) == 0)
	addUnit(W, "party5", { dist = 15 })
	check("Distance: group member is exact", math.abs(ns.Distance({ tier = 1, unit = "party5" }) - 15) < 0.001)
	addUnit(W, "nameplate7", { interact = "near" })
	addUnit(W, "nameplate8", { interact = "mid" })
	addUnit(W, "nameplate9", {})
	check("Distance: stranger brackets 10 / 28 / unknown",
		ns.Distance({ tier = 2, unit = "nameplate7" }) == 10 and ns.Distance({ tier = 2, unit = "nameplate8" }) == 28 and ns.Distance({ tier = 2, unit = "nameplate9" }) == nil)
	check("InRange passes the spell name and unit through", ns.InRange(MIGHT, "party1") == true)
end

----------------------------------------------------------------------
print("== Press -> cast")
do
	local WM, ns, E, W = load()
	W.groupSize = 2
	addUnit(W, "party1", { class = "WARRIOR", name = "Wally", guid = "G-wally", dist = 8, auras = {} })
	addUnit(W, "nameplate1", { class = "PRIEST", name = "Stranger", guid = "G-stranger", interact = "mid", auras = {} })
	W.plates = { "nameplate1" }
	W.units.player.auras = { ["Blessing of Wisdom"] = true }       -- you're already buffed

	local b = press(E)
	check("press arms a spell cast on the best target (group member first)",
		b.attrs.type == "spell" and b.attrs.spell == "Blessing of Might" and b.attrs.unit == "party1")
	check("the pick is remembered for the cast events", WM.pending and WM.pending.name == "Wally")

	-- a /click macro sends only an up click: group still works, strangers are refused with a message
	do
		local WM2, _, E2, W2 = load()
		W2.groupSize = 0
		addUnit(W2, "nameplate1", { class = "PRIEST", name = "Stranger", guid = "G-stranger", interact = "mid", auras = {} })
		W2.plates = { "nameplate1" }
		W2.units.player.auras = { ["Blessing of Wisdom"] = true }
		local b2 = E2.g.WellMetCast
		b2.scripts.PreClick(b2, "LeftButton", false)
		check("a stranger press from a /click macro is refused, with a message",
			b2.attrs.type == nil and printed(W2, "bound key"))
	end

	-- cast events: SENT marks the target as tried, so the next press moves on
	local castFrame = ns.castFrame
	castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SENT", "player", "Wally", "Cast-1", 19834)
	W.now = W.now + 1
	b = press(E)
	check("after a cast attempt the next press goes to someone else",
		b.attrs.type == "macro" and b.attrs.macrotext:find("/targetexact Stranger Surname\n/cast [@target,exists,help,nodead] Blessing of Wisdom", 1, true) ~= nil and b.attrs.unit == nil and b.attrs.spell == nil)
	castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 19834)

	-- "Buffed" line
	W.prints = {}
	WM.pending = { key = "G-wally", spell = "Blessing of Might", unit = "party1", name = "Wally", at = W.now }
	castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SENT", "player", "Wally", "Cast-2", 19834)
	castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 19834)
	check("'Buffed' line after a successful cast (debug on)", printed(W, "Buffed Wally with Blessing of Might"))

	-- debug off: no chat notes and no log lines (startup message aside)
	do
		local WM3, ns3, E3, W3 = load({ debug = false })
		local startup = #W3.prints
		local logBefore = #ns3.LogLines()
		W3.units.player.auras = { ["Blessing of Wisdom"] = true }
		W3.combat = true
		local b3 = E3.g.WellMetCast
		b3.scripts.PreClick(b3, "LeftButton", true)
		check("debug off: a blocked press prints nothing", #W3.prints == startup)
		check("debug off: the log stays empty", #ns3.LogLines() == logBefore)
		WM3.db.debug = true
		W3.combat = false; W3.now = W3.now + 10
		b3.scripts.PreClick(b3, "LeftButton", true)
		check("debug on: the log records the press", #ns3.LogLines() > logBefore)
	end

	-- failures
	ns.Select.Reset(); W.now = W.now + 100
	b = press(E)
	local target = b.attrs.unit
	castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SENT", "player", "x", "Cast-3", W.spells[b.attrs.spell])
	castFrame.scripts.OnEvent(castFrame, "UI_ERROR_MESSAGE", 1, "Target not in line of sight")
	check("line-of-sight failure puts the target on a skip", select(1, ns.Select.IsBlocked(WM.pending and WM.pending.key or "G-wally", b.attrs.spell, W.now)) ~= nil)

	ns.Select.Reset(); W.now = W.now + 100; W.prints = {}
	W.units.party1.auras = { ["Blessing of Might"] = true }
	W.units.nameplate1.auras = { ["Blessing of Wisdom"] = true }
	b = press(E)
	check("nobody needs it: no arm + a clear message", b.attrs.type == nil and printed(W, "Nobody nearby needs"))
	W.units.party1.auras = {}; W.units.nameplate1.auras = {}

	-- guards
	W.prints = {}; W.now = W.now + 100
	W.combat = true
	b = press(E)
	check("in combat: nothing armed + message", b.attrs.type == nil and printed(W, "combat"))
	W.combat = false
	W.now = W.now + 1; W.prints = {}
	W.mounted = true
	b = press(E)
	check("mounted: refuses by default", b.attrs.type == nil and printed(W, "Dismount"))
	WM.db.allowMounted = true; W.now = W.now + 1
	b = press(E)
	check("mounted: allowed when the setting is on", b.attrs.type == "spell")
	W.mounted = false; WM.db.allowMounted = false
	W.now = W.now + 1; W.prints = {}; W.flying = true
	b = press(E)
	check("flying: refuses", b.attrs.type == nil and printed(W, "flying"))
	W.flying = false
	W.now = W.now + 1; W.prints = {}; W.restricted = true
	b = press(E)
	check("auras restricted: says so instead of guessing", b.attrs.type == nil and printed(W, "restricted"))
	W.restricted = false
	W.now = W.now + 1; W.prints = {}
	W.cvars.nameplateShowFriendlyPlayers = "0"; W.plates = {}
	W.units.party1.auras = { ["Blessing of Might"] = true }
	b = press(E)
	check("empty + nameplates off: points at the nameplate setting", printed(W, "nameplates are OFF"))
	W.cvars.nameplateShowFriendlyPlayers = "1"
	W.units.party1.auras = {}

	-- debounce: a second event for the same key press must not re-pick
	W.now = W.now + 100
	b = press(E)
	local first = b.attrs.unit
	b.attrs.unit = "sentinel"
	W.now = W.now + 0.05
	press(E)
	check("a second event within 0.15s is ignored (debounce)", b.attrs.unit == "sentinel")

	-- stronger buff => long skip
	ns.Select.Reset(); W.now = W.now + 100
	b = press(E)
	local key = WM.pending.key
	castFrame.scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SENT", "player", "x", "Cast-9", W.spells[b.attrs.spell])
	castFrame.scripts.OnEvent(castFrame, "UI_ERROR_MESSAGE", 1, "A more powerful spell is already active")
	local blocked, left = ns.Select.IsBlocked(key, b.attrs.spell, W.now + 100)
	check("a stronger buff already present skips that player for minutes", blocked == true and left > 150)
end

----------------------------------------------------------------------
print("== Keybind")
do
	local WM, ns, E, W = load({ login = false })
	check("binding header/name globals exist at file load (the Key Bindings window needs them)",
		E.g.BINDING_HEADER_WELLMET == "WellMet" and E.g["BINDING_NAME_CLICK WellMetCast:LeftButton"] ~= nil)
	local xml = readFile("Bindings.xml")
	check("Bindings.xml declares the cast button under the WellMet category",
		xml:find('name="CLICK WellMetCast:LeftButton"', 1, true) and xml:find('category="BINDING_HEADER_WELLMET"', 1, true))
	check("the addon does not make its own key bindings (Blizzard's Key Bindings window owns the key)",
		not readFile("Core/Cast.lua"):find("SetOverrideBinding", 1, true) and not readFile("UI/Options.lua"):find("EnableKeyboard", 1, true))

	WM:PLAYER_LOGIN()
	check("startup hint when no key is bound", printed(W, "No key set yet"))
	W.bindings.F8 = "CLICK WellMetCast:LeftButton"
	W.prints = {}
	WM:PLAYER_LOGIN()
	check("no hint once a key is bound in Key Bindings", not printed(W, "No key set yet"))
	check("the report shows the bound key", WM:BuildReport():find("F8", 1, true) ~= nil)
	W.bindings.F8 = nil
	check("the report says when no key is set", WM:BuildReport():find("NOT SET", 1, true) ~= nil)
end

----------------------------------------------------------------------
print("== Mage (stack mode)")
do
	local WM, ns, E, W = load({ class = "MAGE", login = false })
	W.spells["Arcane Intellect"] = 1459; W.spells["Dampen Magic"] = 604; W.spells["Amplify Magic"] = 1008
	W.known[1459] = true; W.known[604] = true; W.known[1008] = true
	WM:PLAYER_LOGIN(); WM.db.debug = true
	local B = WM.caster and WM.caster.buffs
	check("a Mage loads in stack mode with Intellect / Dampen / Amplify", WM.caster and WM.caster.mode == "stack" and #WM.caster.order == 3
		and B.INTELLECT.name == "Arcane Intellect" and B.DAMPEN.name == "Dampen Magic" and B.AMPLIFY.name == "Amplify Magic")

	local Select = ns.Select
	local function cand(key, class, order) return { unit = key, key = key, name = key, tier = 2, class = class, order = order or 1 } end
	local probe = { known = function() return true end, inRange = function() return true end, lacks = function() return true end, distance = function() return nil end }
	local function ctx(settings) return { now = 100, settings = settings, caster = WM.caster, probe = probe } end
	local s = { assign = {}, stack = {}, strangers = true, groupFirst = true, includeSelf = true, radius = 0 }

	local best, skipped, eligible = Select.Pick({ cand("w", "WARRIOR"), cand("p", "PRIEST") }, ctx(s))
	check("Intellect goes on a mana class by default, not on a Warrior",
		best.cand.key == "p" and best.buff.key == "INTELLECT" and #eligible == 1 and skipped[1].reason:find("no buffs are switched on", 1, true) ~= nil)
	best = Select.Pick({ cand("?", nil) }, ctx(s))
	check("Mage: a person whose class can't be read is skipped", best == nil)
	best = Select.Pick({ cand("r", "ROGUE") }, ctx(s))
	check("Rogue gets nothing by default", best == nil)

	-- stacking
	ns.StackSet(WM.caster, B.DAMPEN, "PRIEST", true)
	local _, _, el = Select.Pick({ cand("p", "PRIEST") }, ctx({ assign = {}, stack = WM.db.stack, strangers = true, groupFirst = true, includeSelf = true, radius = 0 }))
	check("with Dampen on, one person yields Intellect then Dampen", #el == 2 and el[1].buff.key == "INTELLECT" and el[2].buff.key == "DAMPEN")
	Select.Mark("p", "Arcane Intellect", 8, 100)
	best = Select.Pick({ cand("p", "PRIEST"), cand("q", "PRIEST", 2) }, ctx({ assign = {}, stack = WM.db.stack, strangers = true, groupFirst = true, includeSelf = true, radius = 0 }))
	check("after Intellect was just cast, the next press does Dampen on the same person", best.cand.key == "p" and best.buff.key == "DAMPEN")
	Select.Reset()

	-- Dampen / Amplify replace each other
	ns.StackSet(WM.caster, B.AMPLIFY, "PRIEST", true)
	check("switching Amplify on switches Dampen off for that class",
		ns.StackEnabled(B.AMPLIFY, "PRIEST", WM.db.stack) and not ns.StackEnabled(B.DAMPEN, "PRIEST", WM.db.stack))
	check("...and leaves other classes alone", not ns.StackEnabled(B.AMPLIFY, "MAGE", WM.db.stack) and ns.StackEnabled(B.INTELLECT, "MAGE", WM.db.stack))
	WM.db.stack = {}

	-- Arcane Brilliance counts as having Intellect
	addUnit(W, "party1", { class = "PRIEST", name = "Pria", guid = "G-pria", auras = { ["Arcane Brilliance"] = true } })
	check("Arcane Brilliance counts as having Arcane Intellect", ns.Lacks("party1", B.INTELLECT) == false)

	-- a key press: you first (Mage -> Intellect on yourself via the direct spell path)
	W.units.player.auras = {}
	W.groupSize = 0
	local btn = press(E)
	check("a press buffs you with Arcane Intellect", btn.attrs.type == "spell" and btn.attrs.spell == "Arcane Intellect" and btn.attrs.unit == "player")
	ns.Select.Reset()

	-- nobody needs anything: the message names only the buffs that are switched on somewhere
	W.units.player.auras = { ["Arcane Intellect"] = true }
	W.prints = {}
	W.now = W.now + 100
	press(E)
	check("'Nobody nearby needs ...' lists only the switched-on buffs (no Dampen / Amplify by default)",
		printed(W, "Nobody nearby needs Arcane Intellect.") and not printed(W, "Dampen"))
	W.units.player.auras = {}

	-- settings: one multi-select dropdown per class (10 = radius + 9 classes)
	local dds = {}
	for _, f in ipairs(E.frames) do if f.template == "WowStyle1DropdownTemplate" then dds[#dds + 1] = f end end
	local nSelf = #WM.caster.selfCategories      -- the "Yourself" dropdown(s) sit between the radius and the class rows
	check("Mage settings have the self dropdown + radius + 9 classes", nSelf == 1 and #dds == nSelf + 10)
	local function checklist(dd)
		local items = {}
		dd.menuGen(dd, { CreateCheckbox = function(_, label, isSelected, toggle, data)
			local item = { label = label, on = isSelected(), toggle = toggle, data = data }
			items[#items + 1] = item
			return { SetTooltip = function(_, fn) item.tooltip = fn end }
		end })
		return items
	end
	local priest = checklist(dds[nSelf + 6])      -- Druid, Hunter, Mage, Paladin, Priest -> 6th dropdown (1st is the radius)
	check("a class dropdown lists the three buffs with icons; Intellect is ticked by default",
		#priest == 3 and priest[1].label:find("|T1001459:", 1, true) and priest[1].label:find("Arcane Intellect", 1, true) and priest[1].on and not priest[2].on and not priest[3].on)
	priest[2].toggle()
	check("ticking Dampen Magic saves it", checklist(dds[nSelf + 6])[2].on and ns.StackEnabled(B.DAMPEN, "PRIEST", WM.db.stack))
	checklist(dds[nSelf + 6])[3].toggle()
	check("ticking Amplify Magic unticks Dampen Magic", checklist(dds[nSelf + 6])[3].on and not checklist(dds[nSelf + 6])[2].on)
	check("the closed dropdown shows the icons of what is ticked",
		dds[nSelf + 6].selText({ { data = "INTELLECT" }, { data = "AMPLIFY" } }) == "|T1001459:20|t|T1001008:20|t" and dds[nSelf + 6].selText({}):find("none", 1, true) ~= nil)
	WM.db.stack = {}

	-- a spell the player hasn't learned: its own icon (from the data), greyed, with an "Unknown" tooltip
	W.known[1008] = nil; W.spells["Amplify Magic"] = nil
	local unk = checklist(dds[nSelf + 6])
	check("an unlearned buff keeps its real icon (from the data file), not a question mark",
		unk[3].label:find("Spell_Holy_FlashHeal", 1, true) ~= nil and not unk[3].label:find("134400", 1, true))
	check("...with the icon dimmed and the name greyed", unk[3].label:find(":110:110:110|t", 1, true) ~= nil and unk[3].label:find("|cff808080Amplify Magic|r", 1, true) ~= nil)
	check("a learned buff in the same list is not greyed", not unk[1].label:find("110:110:110", 1, true) and not unk[1].label:find("808080", 1, true))
	local lines = {}
	E.g.GameTooltip_SetTitle = function(_, text) lines[#lines + 1] = text end
	E.g.GameTooltip_AddNormalLine = function(_, text) lines[#lines + 1] = text end
	check("only the unlearned buff has a tooltip, and it says Unknown", unk[3].tooltip ~= nil and unk[1].tooltip == nil and unk[2].tooltip == nil)
	unk[3].tooltip({})
	check("the tooltip title is 'Unknown'", lines[1] == "Unknown")
	check("the closed dropdown dims an unlearned buff's icon too", dds[nSelf + 6].selText({ { data = "AMPLIFY" } }):find("110:110:110", 1, true) ~= nil)
end

----------------------------------------------------------------------
print("== Self buffs (aura, armor)")
do
	local function learn(W, list) for name, id in pairs(list) do W.spells[name] = id; W.known[id] = true end end
	local PALLY = { ["Devotion Aura"] = 465, ["Retribution Aura"] = 7294, ["Righteous Fury"] = 25780 }

	-- Paladin: aura first, then the blessing on yourself
	local WM, ns, E, W = load()
	learn(W, PALLY)
	W.groupSize = 0
	W.units.player.auras = {}
	local b = press(E)
	check("Paladin: the first press casts the chosen aura (Devotion by default) on you", b.attrs.type == "spell" and b.attrs.spell == "Devotion Aura" and b.attrs.unit == "player")
	W.units.player.auras = { ["Devotion Aura"] = true }
	W.now = W.now + 100; ns.Select.Reset()
	b = press(E)
	check("...once you have it, the next press is the blessing on yourself", b.attrs.spell == "Blessing of Wisdom" and b.attrs.unit == "player")
	WM.db.selfChoice.AURA = "RETRIBUTION"
	W.now = W.now + 100; ns.Select.Reset()
	b = press(E)
	check("a different aura choice is used", b.attrs.spell == "Retribution Aura")
	WM.db.selfChoice.AURA = "NONE"
	W.now = W.now + 100; ns.Select.Reset()
	b = press(E)
	check("aura set to None: skipped", b.attrs.spell == "Blessing of Wisdom")
	WM.db.selfChoice.AURA = nil
	W.units.player.auras = { ["Devotion Aura"] = true }
	W.now = W.now + 100; ns.Select.Reset()
	check("Righteous Fury is off by default", press(E).attrs.spell == "Blessing of Wisdom")
	WM.db.selfChoice.FURY = "RIGHTEOUS_FURY"
	W.now = W.now + 100; ns.Select.Reset()
	check("...and cast after the aura once it is chosen", press(E).attrs.spell == "Righteous Fury")
	WM.db.selfChoice.FURY = nil
	WM.db.includeSelf = false
	W.now = W.now + 100; ns.Select.Reset()
	W.units.player.auras = {}
	check("'Buff myself' off also turns off the self buffs", press(E).attrs.type == nil)
	WM.db.includeSelf = true
	W.now = W.now + 100; ns.Select.Reset()
	W.known[465] = nil
	local best, skipped = ns.Select.Pick({ { unit = "player", key = "me", name = "Tek", tier = 0, class = "PALADIN", order = 0 } },
		{ now = 100, settings = WM.db, caster = WM.caster, probe = ns.Probe })
	check("an aura you haven't learned is skipped with a reason", best.buff.key == "WISDOM" and skipped[1].reason:find("Devotion Aura is not learned", 1, true) ~= nil)

	-- Mage: the armor line resolves to the best learned one
	local WMm, nsm, Em, Wm = load({ class = "MAGE", login = false })
	learn(Wm, { ["Frost Armor"] = 168, ["Mage Armor"] = 6117 })
	WMm:PLAYER_LOGIN(); WMm.db.debug = true
	Wm.groupSize = 0
	check("Mage: 'best learned' picks Frost Armor when Ice Armor isn't learned", press(Em).attrs.spell == "Frost Armor")
	learn(Wm, { ["Ice Armor"] = 7302 })
	Wm.now = Wm.now + 100; nsm.Select.Reset()
	check("...and Ice Armor once it is learned", press(Em).attrs.spell == "Ice Armor")
	WMm.db.selfChoice.ARMOR = "MAGE_ARMOR"
	Wm.now = Wm.now + 100; nsm.Select.Reset()
	check("a specific choice (Mage Armor) overrides 'best learned'", press(Em).attrs.spell == "Mage Armor")
	WMm.db.selfChoice.ARMOR = nil
	-- armor AND Intellect both learned and both missing: the armor must come first, then Intellect
	learn(Wm, { ["Arcane Intellect"] = 1459 })
	Wm.units.player.auras = {}
	Wm.now = Wm.now + 100; nsm.Select.Reset()
	local _, _, order = nsm.Select.Pick({ { unit = "player", key = "me", name = "Tek", tier = 0, class = "MAGE", order = 0 } },
		{ now = 100, settings = WMm.db, caster = WMm.caster, probe = nsm.Probe })
	check("Mage with nothing on: Ice Armor is listed before Arcane Intellect", #order == 2 and order[1].buff.key == "ICE_ARMOR" and order[2].buff.key == "INTELLECT")
	Wm.now = Wm.now + 100; nsm.Select.Reset()
	check("...and a press casts the armor first", press(Em).attrs.spell == "Ice Armor")
	Wm.units.player.auras = { ["Ice Armor"] = true }
	Wm.now = Wm.now + 100; nsm.Select.Reset()
	check("with the armor on, the Mage moves on to Arcane Intellect or nothing (armor is not repeated)", press(Em).attrs.spell ~= "Ice Armor")

	-- Warlock: only buffs itself; becomes a supported class
	local WMw, nsw, Ew, Ww = load({ class = "WARLOCK", login = false })
	learn(Ww, { ["Demon Skin"] = 687 })
	WMw:PLAYER_LOGIN(); WMw.db.debug = true
	check("Warlock is supported and only buffs itself", nsw.supported == true and WMw.caster.mode == "self" and #WMw.caster.order == 0)
	addUnit(Ww, "nameplate1", { class = "PRIEST", name = "Stranger", guid = "G-s", interact = "mid", auras = {} })
	Ww.plates = { "nameplate1" }
	local bw = press(Ew)
	check("Warlock: casts the best learned armor on itself, ignoring other players",
		bw.attrs.type == "spell" and bw.attrs.spell == "Demon Skin" and bw.attrs.unit == "player")
	Ww.units.player.auras = { ["Demon Skin"] = true }
	Ww.now = Ww.now + 100; nsw.Select.Reset()
	Ww.prints = {}
	check("Warlock with the armor on: nothing happens and says so", press(Ew).attrs.type == nil and printed(Ww, "Nothing needs buffing"))
	local _, skipW = nsw.Select.Pick({ { unit = "nameplate1", key = "s", name = "S", tier = 2, class = "PRIEST", order = 1 } },
		{ now = 100, settings = WMw.db, caster = WMw.caster, probe = nsw.Probe })
	check("...and other players are not even listed as skipped", #skipW == 0)
	learn(Ww, { ["Demon Armor"] = 706 })
	Ww.units.player.auras = {}
	Ww.now = Ww.now + 100; nsw.Select.Reset()
	check("Warlock: Demon Armor beats Demon Skin once learned", press(Ew).attrs.spell == "Demon Armor")
	WMw.db.selfChoice.ARMOR = "NONE"
	Ww.now = Ww.now + 100; nsw.Select.Reset()
	check("Warlock: armor set to None casts nothing", press(Ew).attrs.type == nil)
	check("Forever has no Fel Armor or Sanctity Aura", WMw.caster.buffs.FEL_ARMOR == nil and WM.caster.buffs.SANCTITY == nil)

	-- Priest, Shaman, Hunter, Warrior: their own buffs, nothing on other players
	local function selfClass(class, spells)
		local WMx, nsx, Ex, Wx = load({ class = class, login = false })
		learn(Wx, spells)
		WMx:PLAYER_LOGIN(); WMx.db.debug = true
		Wx.groupSize = 0
		return WMx, nsx, Ex, Wx
	end
	do
		local WMp, nsp, Ep = selfClass("PRIEST", { ["Inner Fire"] = 588 })
		check("Priest: supported, self only, casts Inner Fire on itself", nsp.supported and WMp.caster.mode == "self" and press(Ep).attrs.spell == "Inner Fire")
		local WMs, nss, Es, Ws = selfClass("SHAMAN", { ["Lightning Shield"] = 324 })
		check("Shaman: Lightning Shield by default", press(Es).attrs.spell == "Lightning Shield")
		learn(Ws, { ["Water Shield"] = 408510 })
		WMs.db.selfChoice.SHIELD = "WATER_SHIELD"
		Ws.now = Ws.now + 100; nss.Select.Reset()
		check("Shaman: Water Shield when chosen", press(Es).attrs.spell == "Water Shield")
		local WMh, nsh, Eh, Wh = selfClass("HUNTER", { ["Aspect of the Monkey"] = 13163 })
		check("Hunter: 'best learned' falls back to Aspect of the Monkey", press(Eh).attrs.spell == "Aspect of the Monkey")
		learn(Wh, { ["Aspect of the Hawk"] = 13165, ["Aspect of the Cheetah"] = 5118 })
		Wh.now = Wh.now + 100; nsh.Select.Reset()
		check("Hunter: ...and Aspect of the Hawk once learned", press(Eh).attrs.spell == "Aspect of the Hawk")
		WMh.db.selfChoice.ASPECT = "CHEETAH"
		Wh.now = Wh.now + 100; nsh.Select.Reset()
		check("Hunter: a chosen aspect (Cheetah) overrides", press(Eh).attrs.spell == "Aspect of the Cheetah")
		local WMw2, nsw2, Ew2 = selfClass("WARRIOR", { ["Battle Shout"] = 6673 })
		check("Warrior: supported, casts Battle Shout on itself", nsw2.supported and press(Ew2).attrs.spell == "Battle Shout" and press(Ew2).attrs.unit == "player")
		check("Rogue and Druid still have nothing, so they stay unsupported",
			select(2, load({ class = "ROGUE", login = false })).supported == false and select(2, load({ class = "DRUID", login = false })).supported == false)
		check("none of the spells missing from Forever are in the data (Commanding Shout, Heart of the Lion, Viper, Falcon)",
			not readFile("Data/Classes.lua"):find('name = "Commanding Shout"', 1, true) and not readFile("Data/Classes.lua"):find('name = "Aspect of the Viper"', 1, true)
			and not readFile("Data/Classes.lua"):find('name = "Heart of the Lion"', 1, true) and not readFile("Data/Classes.lua"):find('name = "Aspect of the Falcon"', 1, true))
	end

	-- settings: a "Yourself" dropdown per category, before everything else
	local dds = {}
	for _, f in ipairs(E.frames) do if f.template == "WowStyle1DropdownTemplate" then dds[#dds + 1] = f end end
	local function menu(dd)
		local items = {}
		dd.menuGen(dd, { CreateRadio = function(_, label, isSelected, setSelected, data)
			local item = { label = label, selected = isSelected(), pick = setSelected, data = data }
			items[#items + 1] = item
			return { SetTooltip = function(_, fn) item.tooltip = fn end }
		end })
		return items
	end
	-- placement: Yourself is in the right column (x past the left column), above the first class row
	local selfPt, firstClassPt, radiusPt = dds[2].lastPoint, dds[3].lastPoint, dds[1].lastPoint
	local fury2Pt, classPt = dds[3].lastPoint, dds[4].lastPoint
	check("Yourself sits in the right column, above the class rows",
		selfPt[2] > radiusPt[2] + 200 and selfPt[3] > classPt[3] and fury2Pt[3] < selfPt[3] and fury2Pt[3] > classPt[3])
	local aura = menu(dds[2])      -- dds[1] is the radius
	check("Paladin settings: the Aura dropdown lists the 6 auras plus None; Devotion is selected",
		#aura == 7 and aura[1].data == "DEVOTION" and aura[1].selected and aura[7].data == "NONE")
	check("...an unlearned aura (Devotion, forgotten above) is greyed with a tooltip; a learned one (Retribution) is plain",
		aura[1].label:find("808080", 1, true) ~= nil and aura[1].tooltip ~= nil and not aura[2].label:find("808080", 1, true) and aura[2].tooltip == nil)
	local fury = menu(dds[3])
	check("Righteous Fury dropdown: the spell or None, None selected by default", #fury == 2 and fury[2].selected and fury[1].data == "RIGHTEOUS_FURY")
	aura[3].pick()
	check("picking an aura saves it", WM.db.selfChoice.AURA == "CONCENTRATION")
	WM.db.selfChoice.AURA = nil
end

----------------------------------------------------------------------
print("== Minimap button")
do
	local WM, ns, E, W = load()
	local mb = E.g.WellMetMinimap
	check("minimap button is created, shown by default, with a saved position", mb ~= nil and WM.db.minimap.hide == false and WM.db.minimap.angle == 200)
	check("minimap button uses the shipped WM icon, and the file exists",
		readFile("UI/Minimap.lua"):find('Interface\\\\AddOns\\\\WellMet\\\\Icons\\\\Icon"', 1, true) ~= nil
		and #readFile("Icons/Icon.tga") > 18 and readFile("WellMet_Camelot.toc"):find("IconTexture: Interface\\AddOns\\WellMet\\Icons\\Icon", 1, true) ~= nil)
	local p = mb.lastPoint
	local want = (198 / 2 + 5)
	check("button sits on the rim: radius = half the minimap width + 5, at the saved angle (200 deg)",
		p and p[1] == "CENTER" and math.abs(p[4] - want * math.cos(math.rad(200))) < 0.01 and math.abs(p[5] - want * math.sin(math.rad(200))) < 0.01)
	W.openedCategory = nil
	mb.scripts.OnClick(mb, "LeftButton")
	check("left-click opens the settings", W.openedCategory == 1)
	local opened = false
	WM.ShowLog = function() opened = true end
	mb.scripts.OnClick(mb, "RightButton")
	check("right-click opens the log", opened)
	check("a fresh profile shows the button by default", load().db.minimap.hide == false)
end

----------------------------------------------------------------------
print("== Slash, options, report")
do
	local WM, ns, E, W = load()
	local slash = E.g.SlashCmdList.WELLMET
	check("slash commands registered (/wellmet, /wmet, /well)", slash ~= nil and E.g.SLASH_WELLMET1 == "/wellmet" and E.g.SLASH_WELLMET2 == "/wmet" and E.g.SLASH_WELLMET3 == "/well")
	check("/wm is NOT claimed (Blizzard's world-marker command)", E.g.SLASH_WELLMET1 ~= "/wm" and E.g.SLASH_WELLMET2 ~= "/wm" and E.g.SLASH_WELLMET3 ~= "/wm")
	slash("bind F5")
	check("/wellmet bind is gone (falls through to the help, binds nothing)", next(W.overrides) == nil and printed(W, "Key Bindings"))
	slash("debug")
	check("/wellmet debug toggles debug (the harness starts with it on)", WM.db.debug == false)
	slash("debug")
	check("...and back on", WM.db.debug == true)
	slash("")
	check("/wellmet opens the settings panel", W.openedCategory == 1)

	-- "Open Key Bindings": open the Key Bindings screen with the search box set to "WellMet", which matches only our binding
	do
		E.g.Settings.KEYBINDINGS_CATEGORY_ID = 99
		local typed
		E.g.SettingsPanel = { SearchBox = { SetText = function(_, text) typed = text end } }
		W.openedCategory = nil
		WM:OpenKeyBindings()
		check("Open Key Bindings opens the Key Bindings category", W.openedCategory == 99)
		check("...and searches for 'WellMet'", typed == "WellMet")
		-- the game's search matches each typed word as a plain substring of a binding's NAME
		local bindingName = E.g["BINDING_NAME_CLICK WellMetCast:LeftButton"]
		check("our binding's name contains the search word, so the search finds it", bindingName:upper():find(typed:upper(), 1, true) ~= nil)
		check("...and it is one word, so no other binding matches by accident (the search matches any typed word)", not typed:find("%s"))
	end
	check("options panel builds with stock templates", WM.optionsPanel ~= nil and WM.refreshOptions ~= nil)
	check("refreshing the options runs without error", pcall(WM.refreshOptions))

	-- dropdowns: 1 radius + 9 classes, each listing its choices as radio items
	local function menuOf(dd)
		local items = {}
		dd.menuGen(dd, { CreateRadio = function(_, label, isSelected, setSelected, data)
			local item = { label = label, selected = isSelected(), pick = setSelected, data = data }
			items[#items + 1] = item
			return { SetTooltip = function(_, fn) item.tooltip = fn end }
		end })
		return items
	end
	local dds = {}
	for _, f in ipairs(E.frames) do if f.template == "WowStyle1DropdownTemplate" then dds[#dds + 1] = f end end
	local nSelf = #WM.caster.selfCategories      -- the "Yourself" dropdowns sit between the radius and the class rows
	check("self dropdowns + radius + 9 classes, no cycle buttons and no 'class unreadable' row", #dds == nSelf + 10 and not readFile("UI/Options.lua"):find("Class unreadable", 1, true) and not readFile("UI/Options.lua"):find("cycle(", 1, true))
	local radius = menuOf(dds[1])          -- order: radius (left column), then Yourself, then the class rows (right column)
	check("radius dropdown lists cast range / 28 / 10 and marks the saved one", #radius == 3 and radius[1].selected and not radius[2].selected)
	radius[2].pick()
	check("picking 28 yards saves it", WM.db.radius == 28)
	local warrior = menuOf(dds[nSelf + 10])         -- classes are alphabetical, so Warrior is the last class row
	check("a class dropdown lists Might / Wisdom / Skip, each with a spell icon in the open list",
		#warrior == 3 and warrior[1].label:find("Blessing of Might", 1, true) and warrior[1].label:find("|T1019834:", 1, true)
		and warrior[2].label:find("|T1019742:", 1, true) and warrior[3].label:find("Skip this class", 1, true) and warrior[3].label:find("|T", 1, true))
	check("menu items carry their value, and the closed dropdown shows only the icon",
		warrior[1].data == "MIGHT" and warrior[3].data == "NONE" and dds[nSelf + 10].selTranslator ~= nil
		and dds[nSelf + 10].selTranslator({ data = "WISDOM" }) == "|T1019742:20|t")
	check("the class default is the selected item (Warrior -> Might)", warrior[1].selected and not warrior[2].selected)
	check("Hunter defaults to Wisdom, Rogue to Might", ns.AssignedKey("HUNTER") == "WISDOM" and ns.AssignedKey("ROGUE") == "MIGHT")
	warrior[2].pick()
	-- row order: picking "Skip" on each class row in turn must hit the classes alphabetically
	do
		local saved = WM.db.assign
		WM.db.assign = {}
		local order = {}
		for i = nSelf + 2, nSelf + 10 do
			menuOf(dds[i])[3].pick()
			for k in pairs(WM.db.assign) do
				local seen = false
				for _, o in ipairs(order) do if o == k then seen = true end end
				if not seen then order[#order + 1] = k end
			end
		end
		check("class rows are alphabetical (Druid ... Warrior)", table.concat(order, ",") == "DRUID,HUNTER,MAGE,PALADIN,PRIEST,ROGUE,SHAMAN,WARLOCK,WARRIOR")
		WM.db.assign = saved
	end
	check("picking Wisdom for Warrior saves it", WM.db.assign.WARRIOR == "WISDOM" and menuOf(dds[nSelf + 10])[2].selected)
	WM.db.radius, WM.db.assign.WARRIOR = 0, nil     -- leave the settings as found

	-- report
	W.groupSize = 1
	addUnit(W, "party1", { class = "WARRIOR", name = "Wally", guid = "G-wally", dist = 8 })
	addUnit(W, "nameplate1", { class = "PRIEST", name = "Stranger", guid = "G-s", auras = { ["Blessing of Wisdom"] = true } })
	W.plates = { "nameplate1" }
	WM:Log("hello", "log")
	local r = WM:BuildReport()
	check("report has overview, diagnostics, 'right now' and the event log",
		r:find("== Overview", 1, true) and r:find("== Diagnostics", 1, true) and r:find("== Right now", 1, true) and r:find("== Event log", 1, true))
	check("report shows who is eligible and who is skipped, with reasons",
		r:find("ELIGIBLE #1", 1, true) and r:find("<== next press", 1, true) and r:find("already has Blessing of Wisdom", 1, true))
	check("report notes the nameplate CVar and bound key", r:find("nameplateShowFriendlyPlayers", 1, true) and r:find("Key Bindings > WellMet", 1, true))
	check("ShowLog builds the window", pcall(function() WM:ShowLog() end))
	do   -- the window's Clear log button empties the log, rebuilds the report and says so
		WM:Log("a line that should disappear")
		check("log has the line before clearing", (WM:BuildReport()):find("a line that should disappear", 1, true) ~= nil)
		local clearBtn
		for _, f in ipairs(E.frames) do if f.text == "Clear log" then clearBtn = f end end
		check("the window has a Clear log button", clearBtn ~= nil)
		W.prints = {}
		clearBtn.scripts.OnClick(clearBtn)
		check("Clear log empties the log", #ns.LogLines() == 0 and not WM.logFrame.edit.orig:find("a line that should disappear", 1, true))
		check("Clear log confirms in chat", printed(W, "log cleared"))
	end

	-- log ring buffer
	ns.ClearLog()
	for i = 1, 520 do WM:Log("line", i) end
	local lines = ns.LogLines()
	check("log keeps the newest 500 lines in order", #lines == 500 and lines[1]:find("line 21$") and lines[500]:find("line 520$"))
	local bomb = setmetatable({}, { __tostring = function() error("secret!") end })
	check("SafeStr survives unreadable values", ns.SafeStr(bomb) == "<unreadable>" and pcall(function() WM:Log("x", bomb, nil) end))

	-- a class with no buffs: WellMet does nothing at all
	do
		local WM2, ns2, E2, W2 = load({ class = "ROGUE" })
		check("a class with no buffs is not supported, and WellMet stays out of the way", ns2.supported == false and WM2 == nil and ns2.WM == nil)
		check("...it creates no frames, button, settings, minimap button, slash commands or chat messages",
			#E2.frames == 0 and E2.g.WellMetCast == nil and E2.g.WellMetMinimap == nil and E2.g.WellMetOptionsPanel == nil
			and (E2.g.SlashCmdList == nil or E2.g.SlashCmdList.WELLMET == nil) and #W2.prints == 0)
		local _, ns3 = load({ class = "MAGE", login = false })
		check("Paladin and Mage are supported", ns3.supported == true and select(2, load({ login = false })).supported == true)
	end
end

print(string.format("\n%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
