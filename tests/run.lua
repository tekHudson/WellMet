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
		units = {}, plates = {}, known = {}, spells = {}, macros = {}, sent = {},
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
	g.IsInGroup = function() return W.groupSize > 0 end
	g.IsInInstance = function() return W.inInstance or false, W.inInstance and "party" or "none" end
	g.C_ChatInfo = {
		InChatMessagingLockdown = function() return W.lockdown or false end,
		SendChatMessage = function(msg, chatType)
			if W.sendError then error(W.sendError) end
			W.sent[#W.sent + 1] = { msg = msg, chatType = chatType }
		end,
	}
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
		local function events(self) local ev = rawget(self, "events"); if not ev then ev = {}; rawset(self, "events", ev) end; return ev end
		function f:RegisterEvent(e) events(self)[e] = true end
		function f:UnregisterEvent(e) events(self)[e] = nil end
		function f:HookScript(k, fn)
			local old = self.scripts[k]
			self.scripts[k] = function(...) if old then old(...) end fn(...) end
		end
		function f:RegisterUnitEvent(e) events(self)[e] = true end
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
	g.Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 3, MAX_CHARACTER_MACROS = 2 } }       -- small limits so "full" is easy to test
	g.GetMacroInfo = function(i) local m = W.macros[i]; if m then return m.name, m.icon, m.body end end
	g.GetNumMacros = function() local a, c = 0, 0 for i, m in pairs(W.macros) do if i <= 3 then a = a + 1 else c = c + 1 end end return a, c end
	g.CreateMacro = function(name, icon, body, forCharacter)
		local first, last = forCharacter and 4 or 1, forCharacter and 5 or 3
		for i = first, last do
			if not W.macros[i] then W.macros[i] = { name = name, icon = icon, body = body }; return i end
		end
	end
	g.PickupMacro = function(i) W.cursorMacro = i end
	g.C_Timer = { After = function(_, fn) fn() end }        -- run at once; the real delay doesn't matter here
	g.GetBindingAction = function(key) return W.overrides[key] or W.bindings[key] or "" end
	g.GetBindingKey = function(action) for key, a in pairs(W.bindings) do if a == action then return key end end end
	g.ClearOverrideBindings = function() W.overrides = {} end
	g.SetOverrideBindingClick = function(_, _, key, btn, mouse) W.overrides[key] = "CLICK " .. btn .. ":" .. mouse end

	-- settings
	g.Settings = {
		RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
		RegisterCanvasLayoutSubcategory = function(_, panel, name)
			W.subcategories = W.subcategories or {}
			local id = 100 + #W.subcategories + 1
			W.subcategories[#W.subcategories + 1] = { id = id, name = name, panel = panel }
			return { GetID = function() return id end }
		end,
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
	if opts.others ~= false then WM.db.others.enabled = true end          -- a fresh profile has Others off; most checks need strangers
	if opts.login ~= false then WM:PLAYER_LOGIN() end
	if WM.db and opts.debug ~= false then WM.db.debug = true end     -- most checks read press messages / the log
	return WM, ns, E, W
end

local function press(E)
	local b = E.g.WellMetCast
	b.scripts.PreClick(b, "LeftButton", true)
	return b
end

-- A settings table in the three-section shape for Select.Pick. `over` may carry the old flat names for brevity:
-- radius, assign, stack, selfChoice (copied into the sections) and includeSelf / strangers (the on/off switches).
local function mkSettings(over)
	over = over or {}
	local function section(enabled)
		return { enabled = enabled, radius = over.radius or 0, assign = over.assign or {}, stack = over.stack or {}, choice = over.selfChoice or {} }
	end
	return { self = section(over.includeSelf ~= false), party = section(true), others = section(over.strangers ~= false) }
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
	local function settings(over) return mkSettings(over) end
	local function ctx(p, s) return { now = 100, settings = s or settings(), caster = WM.caster, probe = p or probe() } end

	local best = Select.Pick({ cand("stranger", 2, "MAGE", 1), cand("grp", 1, "MAGE", 1), cand("me", 0, "PALADIN", 0) }, ctx())
	check("tier order: you, then group, then strangers", best.cand.key == "me")
	best = Select.Pick({ cand("stranger", 2, "MAGE", 1), cand("grp", 1, "MAGE", 1) }, ctx())
	check("group before strangers", best.cand.key == "grp")
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
	check("the Self section can be turned off", skipped[1] and skipped[1].reason:find("Self section is switched off", 1, true) ~= nil)
	_, skipped = Select.Pick({ cand("s", 2, "MAGE") }, ctx(nil, settings({ strangers = false })))
	check("the Others section can be turned off", skipped[1] and skipped[1].reason:find("Others section is switched off", 1, true) ~= nil)

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
	WM.db.others.enabled = false
	W.plates = { "nameplate1" }
	list = D.Discover()
	local sawStranger
	for _, c in ipairs(list) do if c.name == "Stranger" then sawStranger = true end end
	check("nameplates are ignored when strangers are turned off", not sawStranger)
	WM.db.others.enabled = true

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
	local s = mkSettings()

	local best, skipped, eligible = Select.Pick({ cand("w", "WARRIOR"), cand("p", "PRIEST") }, ctx(s))
	check("Intellect goes on a mana class by default, not on a Warrior",
		best.cand.key == "p" and best.buff.key == "INTELLECT" and #eligible == 1 and skipped[1].reason:find("no buffs are switched on", 1, true) ~= nil)
	best = Select.Pick({ cand("?", nil) }, ctx(s))
	check("Mage: a person whose class can't be read is skipped", best == nil)
	best = Select.Pick({ cand("r", "ROGUE") }, ctx(s))
	check("Rogue gets nothing by default", best == nil)

	-- stacking
	ns.StackSet(WM.caster, B.DAMPEN, "PRIEST", true, WM.db.party.stack)
	local _, _, el = Select.Pick({ cand("p", "PRIEST") }, ctx(mkSettings({ stack = WM.db.party.stack })))
	check("with Dampen on, one person yields Intellect then Dampen", #el == 2 and el[1].buff.key == "INTELLECT" and el[2].buff.key == "DAMPEN")
	Select.Mark("p", "Arcane Intellect", 8, 100)
	best = Select.Pick({ cand("p", "PRIEST"), cand("q", "PRIEST", 2) }, ctx(mkSettings({ stack = WM.db.party.stack })))
	check("after Intellect was just cast, the next press does Dampen on the same person", best.cand.key == "p" and best.buff.key == "DAMPEN")
	Select.Reset()

	-- Dampen / Amplify replace each other
	ns.StackSet(WM.caster, B.AMPLIFY, "PRIEST", true, WM.db.party.stack)
	check("switching Amplify on switches Dampen off for that class",
		ns.StackEnabled(B.AMPLIFY, "PRIEST", WM.db.party.stack) and not ns.StackEnabled(B.DAMPEN, "PRIEST", WM.db.party.stack))
	check("...and leaves other classes alone", not ns.StackEnabled(B.AMPLIFY, "MAGE", WM.db.party.stack) and ns.StackEnabled(B.INTELLECT, "MAGE", WM.db.party.stack))
	WM.db.party.stack = {}

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

	-- settings: Party / Raid and Others each have a multi-select dropdown per class (found by name)
	local function dd(name) return E.g[name] end
	local classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
	local complete = true
	for _, section in ipairs({ "Party", "Others" }) do
		for _, class in ipairs(classes) do if not dd("WellMet" .. section .. "Class" .. class) then complete = false end end
	end
	check("Mage settings: a dropdown per class in both Party / Raid and Others, plus the Self ones",
		complete and dd("WellMetPartyRadius") and dd("WellMetOthersRadius") and dd("WellMetSelfCatARMOR") and dd("WellMetSelfOwn"))
	local function checklist(dd)
		local items = {}
		dd.menuGen(dd, { CreateCheckbox = function(_, label, isSelected, toggle, data)
			local item = { label = label, on = isSelected(), toggle = toggle, data = data }
			items[#items + 1] = item
			return { SetTooltip = function(_, fn) item.tooltip = fn end }
		end })
		return items
	end
	local priest = checklist(dd("WellMetPartyClassPRIEST"))      -- Druid, Hunter, Mage, Paladin, Priest -> 6th dropdown (1st is the radius)
	check("a class dropdown lists the three buffs with icons; Intellect is ticked by default",
		#priest == 3 and priest[1].label:find("|T1001459:", 1, true) and priest[1].label:find("Arcane Intellect", 1, true) and priest[1].on and not priest[2].on and not priest[3].on)
	priest[2].toggle()
	check("ticking Dampen Magic saves it", checklist(dd("WellMetPartyClassPRIEST"))[2].on and ns.StackEnabled(B.DAMPEN, "PRIEST", WM.db.party.stack))
	checklist(dd("WellMetPartyClassPRIEST"))[3].toggle()
	check("ticking Amplify Magic unticks Dampen Magic", checklist(dd("WellMetPartyClassPRIEST"))[3].on and not checklist(dd("WellMetPartyClassPRIEST"))[2].on)
	check("the closed dropdown shows the icons of what is ticked",
		dd("WellMetPartyClassPRIEST").selText({ { data = "INTELLECT" }, { data = "AMPLIFY" } }) == "|T1001459:20|t|T1001008:20|t" and dd("WellMetPartyClassPRIEST").selText({}):find("none", 1, true) ~= nil)
	WM.db.party.stack = {}

	-- a spell the player hasn't learned: its own icon (from the data), greyed, with an "Unknown" tooltip
	W.known[1008] = nil; W.spells["Amplify Magic"] = nil
	local unk = checklist(dd("WellMetPartyClassPRIEST"))
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
	check("the closed dropdown dims an unlearned buff's icon too", dd("WellMetPartyClassPRIEST").selText({ { data = "AMPLIFY" } }):find("110:110:110", 1, true) ~= nil)
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
	WM.db.self.choice.AURA = "RETRIBUTION"
	W.now = W.now + 100; ns.Select.Reset()
	b = press(E)
	check("a different aura choice is used", b.attrs.spell == "Retribution Aura")
	WM.db.self.choice.AURA = "NONE"
	W.now = W.now + 100; ns.Select.Reset()
	b = press(E)
	check("aura set to None: skipped", b.attrs.spell == "Blessing of Wisdom")
	WM.db.self.choice.AURA = nil
	W.units.player.auras = { ["Devotion Aura"] = true }
	W.now = W.now + 100; ns.Select.Reset()
	check("Righteous Fury is off by default", press(E).attrs.spell == "Blessing of Wisdom")
	WM.db.self.choice.FURY = "RIGHTEOUS_FURY"
	W.now = W.now + 100; ns.Select.Reset()
	check("...and cast after the aura once it is chosen", press(E).attrs.spell == "Righteous Fury")
	WM.db.self.choice.FURY = nil
	WM.db.self.enabled = false
	W.now = W.now + 100; ns.Select.Reset()
	W.units.player.auras = {}
	check("'Buff myself' off also turns off the self buffs", press(E).attrs.type == nil)
	WM.db.self.enabled = true
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
	WMm.db.self.choice.ARMOR = "MAGE_ARMOR"
	Wm.now = Wm.now + 100; nsm.Select.Reset()
	check("a specific choice (Mage Armor) overrides 'best learned'", press(Em).attrs.spell == "Mage Armor")
	WMm.db.self.choice.ARMOR = nil
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

	-- Priest: Inner Fire on yourself, then Fortitude and Divine Spirit (Shadow Protection is off by default)
	local WMw, nsw, Ew, Ww = load({ class = "PRIEST", login = false })
	learn(Ww, { ["Inner Fire"] = 588, ["Power Word: Fortitude"] = 1243, ["Divine Spirit"] = 14752, ["Shadow Protection"] = 976 })
	WMw:PLAYER_LOGIN(); WMw.db.debug = true
	Ww.groupSize = 0
	local P = WMw.caster.buffs
	check("Priest is supported, in stack mode: Fortitude / Divine Spirit / Shadow Protection on others, Inner Fire on itself",
		nsw.supported == true and WMw.caster.mode == "stack" and #WMw.caster.order == 3 and P.FORTITUDE.name == "Power Word: Fortitude"
		and P.SPIRIT.name == "Divine Spirit" and P.SHADOW_PROT.name == "Shadow Protection" and P.INNER_FIRE.selfOnly == true)
	check("Priest defaults: Fortitude for every class, Divine Spirit for mana classes only, Shadow Protection for none",
		nsw.StackEnabled(P.FORTITUDE, "WARRIOR", WMw.db.party.stack) and nsw.StackEnabled(P.FORTITUDE, "ROGUE", WMw.db.party.stack)
		and nsw.StackEnabled(P.SPIRIT, "MAGE", WMw.db.party.stack) and nsw.StackEnabled(P.SPIRIT, "PRIEST", WMw.db.party.stack)
		and not nsw.StackEnabled(P.SPIRIT, "WARRIOR", WMw.db.party.stack) and not nsw.StackEnabled(P.SPIRIT, "ROGUE", WMw.db.party.stack)
		and not nsw.StackEnabled(P.SHADOW_PROT, "MAGE", WMw.db.party.stack))
	local _, _, pOrder = nsw.Select.Pick({ { unit = "player", key = "me", name = "Tek", tier = 0, class = "PRIEST", order = 0 } },
		{ now = 100, settings = WMw.db, caster = WMw.caster, probe = nsw.Probe })
	local seq = {}
	for _, e in ipairs(pOrder) do seq[#seq + 1] = e.buff.key end
	check("Priest on yourself: Inner Fire first, then Fortitude, then Divine Spirit", table.concat(seq, ",") == "INNER_FIRE,FORTITUDE,SPIRIT")
	check("Priest: the first press casts Inner Fire", press(Ew).attrs.spell == "Inner Fire")
	Ww.units.player.auras = { ["Inner Fire"] = true }
	Ww.now = Ww.now + 100; nsw.Select.Reset()
	check("...then Power Word: Fortitude", press(Ew).attrs.spell == "Power Word: Fortitude")
	Ww.units.player.auras = { ["Inner Fire"] = true, ["Prayer of Fortitude"] = true }
	Ww.now = Ww.now + 100; nsw.Select.Reset()
	check("...Prayer of Fortitude (the group version) counts as having Fortitude, so Divine Spirit is next", press(Ew).attrs.spell == "Divine Spirit")
	Ww.units.player.auras = { ["Inner Fire"] = true, ["Prayer of Fortitude"] = true, ["Prayer of Spirit"] = true }
	Ww.now = Ww.now + 100; nsw.Select.Reset()
	check("...and Prayer of Spirit counts as having Divine Spirit: nothing left", press(Ew).attrs.type == nil)
	WMw.db.self.choice.FIRE = "NONE"
	Ww.units.player.auras = {}
	Ww.now = Ww.now + 100; nsw.Select.Reset()
	check("Priest: Inner Fire set to None skips it", press(Ew).attrs.spell == "Power Word: Fortitude")
	nsw.StackSet(WMw.caster, P.SHADOW_PROT, "WARRIOR", true, WMw.db.party.stack)
	check("Shadow Protection can be ticked per class, and is separate from the others (no exclusivity)",
		nsw.StackEnabled(P.SHADOW_PROT, "WARRIOR", WMw.db.party.stack) and nsw.StackEnabled(P.FORTITUDE, "WARRIOR", WMw.db.party.stack))
	check("Forever has no Sanctity Aura or Fel Armor", WM.caster.buffs.SANCTITY == nil and WMw.caster.buffs.FEL_ARMOR == nil)

	-- Priest, Shaman, Hunter, Warrior: their own buffs, nothing on other players
	local function selfClass(class, spells)
		local WMx, nsx, Ex, Wx = load({ class = class, login = false })
		learn(Wx, spells)
		WMx:PLAYER_LOGIN(); WMx.db.debug = true
		Wx.groupSize = 0
		return WMx, nsx, Ex, Wx
	end
	do
		-- classes that can't buff other players do not load at all
		for _, class in ipairs({ "WARLOCK", "WARRIOR", "HUNTER", "SHAMAN", "ROGUE" }) do
			local WMx, nsx, Ex, Wx = load({ class = class })
			check(class .. ": not supported, so WellMet creates nothing and prints nothing",
				nsx.supported == false and WMx == nil and #Ex.frames == 0 and #Wx.prints == 0 and Ex.g.WellMetCast == nil)
		end

		-- Druid: Mark of the Wild on everyone by default, Thorns optional, Omen of Clarity on yourself
		local WMd, nsd, Ed, Wd = selfClass("DRUID", { ["Mark of the Wild"] = 1126, ["Thorns"] = 467 })
		local D = WMd.caster.buffs
		check("Druid: supported, stack mode, Mark of the Wild and Thorns on others; no self-only buffs (Omen of Clarity is a passive on Forever)",
			nsd.supported and WMd.caster.mode == "stack" and D.MARK.name == "Mark of the Wild" and D.THORNS.name == "Thorns"
			and D.OMEN == nil and #WMd.caster.selfCategories == 0)
		check("Druid: Mark of the Wild is on for every class by default, Thorns for none",
			nsd.StackEnabled(D.MARK, "WARRIOR", WMd.db.party.stack) and nsd.StackEnabled(D.MARK, "MAGE", WMd.db.party.stack) and nsd.StackEnabled(D.MARK, "DRUID", WMd.db.party.stack)
			and not nsd.StackEnabled(D.THORNS, "WARRIOR", WMd.db.party.stack))
		check("Druid: on a fresh profile Thorns is OFF on yourself and in every section, Mark of the Wild is ON on yourself",
			not nsd.StackEnabled(D.THORNS, "DRUID", WMd.db.self.stack) and nsd.StackEnabled(D.MARK, "DRUID", WMd.db.self.stack)
			and not nsd.StackEnabled(D.THORNS, "DRUID", WMd.db.party.stack) and not nsd.StackEnabled(D.THORNS, "DRUID", WMd.db.others.stack))
		check("Druid Self page: no own-buff dropdowns (nothing to choose), just the buffs on yourself",
			Ed.g.WellMetSelfOwn ~= nil and Ed.g.WellMetSelfCatOMEN == nil and Ed.g.WellMetSelfCatARMOR == nil)
		check("Druid: the first press casts Mark of the Wild on you", press(Ed).attrs.spell == "Mark of the Wild")
		Wd.units.player.auras = { ["Gift of the Wild"] = true }
		Wd.now = Wd.now + 100; nsd.Select.Reset()
		Wd.prints = {}
		check("...and Gift of the Wild counts as having Mark of the Wild", press(Ed).attrs.type == nil)
		nsd.StackSet(WMd.caster, D.THORNS, "MAGE", true, WMd.db.party.stack)
		check("Thorns can be ticked per class (it is a separate buff, not exclusive with Mark)", nsd.StackEnabled(D.THORNS, "MAGE", WMd.db.party.stack) and nsd.StackEnabled(D.MARK, "MAGE", WMd.db.party.stack))
		check("none of the spells missing from Forever are in the data (Commanding Shout, Heart of the Lion, Viper, Falcon)",
			not readFile("Data/Classes.lua"):find('name = "Commanding Shout"', 1, true) and not readFile("Data/Classes.lua"):find('name = "Aspect of the Viper"', 1, true)
			and not readFile("Data/Classes.lua"):find('name = "Heart of the Lion"', 1, true) and not readFile("Data/Classes.lua"):find('name = "Aspect of the Falcon"', 1, true))
	end

	-- settings: the Self panel's dropdowns, found by name
	local function menu(dd)
		local items = {}
		dd.menuGen(dd, { CreateRadio = function(_, label, isSelected, setSelected, data)
			local item = { label = label, selected = isSelected(), pick = setSelected, data = data }
			items[#items + 1] = item
			return { SetTooltip = function(_, fn) item.tooltip = fn end }
		end })
		return items
	end
	local aura = menu(E.g.WellMetSelfCatAURA)
	check("Paladin settings: the Aura dropdown lists the 6 auras plus None; Devotion is selected",
		#aura == 7 and aura[1].data == "DEVOTION" and aura[1].selected and aura[7].data == "NONE")
	check("...an unlearned aura (Devotion, forgotten above) is greyed with a tooltip; a learned one (Retribution) is plain",
		aura[1].label:find("808080", 1, true) ~= nil and aura[1].tooltip ~= nil and not aura[2].label:find("808080", 1, true) and aura[2].tooltip == nil)
	local fury = menu(E.g.WellMetSelfCatFURY)
	check("Righteous Fury dropdown: the spell or None, None selected by default", #fury == 2 and fury[2].selected and fury[1].data == "RIGHTEOUS_FURY")
	aura[3].pick()
	check("picking an aura saves it", WM.db.self.choice.AURA == "CONCENTRATION")
	WM.db.self.choice.AURA = nil
end

----------------------------------------------------------------------
print("== Sections (Self / Party-Raid / Others), migration, macro")
do
	-- defaults for a fresh profile
	local WM, ns, E, W = load({ others = false })
	check("a fresh profile: Self on, Party / Raid on, Others off, radius 0",
		WM.db.self.enabled and WM.db.party.enabled and not WM.db.others.enabled and WM.db.party.radius == 0 and WM.db.others.radius == 0 and WM.db.schema == 2)

	-- the settings tree: a main panel plus one sub-panel per section the class can use
	local names = {}
	for _, sub in ipairs(W.subcategories or {}) do names[#names + 1] = sub.name end
	check("Paladin: sub-panels Self, Party / Raid, Others", table.concat(names, "|") == "Self|Party / Raid|Others")
	for _, class in ipairs({ "MAGE", "DRUID", "PRIEST" }) do
		local _, _, _, Wc = load({ class = class })
		local cnames = {}
		for _, sub in ipairs(Wc.subcategories or {}) do cnames[#cnames + 1] = sub.name end
		check(class .. ": all three sub-panels (every supported class buffs other players)", table.concat(cnames, "|") == "Self|Party / Raid|Others")
	end
	local Ew = E
	check("the Create macro button is on the main page (General), and not on the Self or Party / Raid pages",
		E.g.WellMetMacroButton ~= nil and not readFile("UI/Options.lua"):find("buildMacroBlock", 1, true))
	local mb = E.g.WellMetMacroButton
	W.macros = {}
	mb.scripts.OnClick(mb)
	check("...and pressing it makes the macro", W.macros[1] and W.macros[1].name == "WM" and W.cursorMacro == 1)

	-- opening a section
	W.openedCategory = nil
	WM:OpenOptions("party")
	check("OpenOptions('party') opens the Party / Raid sub-panel", W.openedCategory == WM.optionsSub.party:GetID() and WM.optionsSub.party:GetID() ~= WM.optionsCategory:GetID())
	WM:OpenOptions()
	check("OpenOptions() opens the main panel", W.openedCategory == 1)
	local slash = E.g.SlashCmdList.WELLMET
	-- the three section checkboxes are one row, left to right, with no Open buttons
	local ps, pp, po = E.g.WellMetShowSelf.lastPoint, E.g.WellMetShowParty.lastPoint, E.g.WellMetShowOthers.lastPoint
	check("the section checkboxes sit side by side (same row, left to right)", ps[3] == pp[3] and pp[3] == po[3] and ps[2] < pp[2] and pp[2] < po[2])
	check("...and there are no Open buttons on the main page", not readFile("UI/Options.lua"):find("openButtons", 1, true))
	-- section pages follow the checkboxes on the main page
	local rebuilt = 0
	E.g.SettingsPanel = { GetCategoryList = function() return { CreateCategories = function() rebuilt = rebuilt + 1 end } end }
	check("a fresh profile: Self and Party / Raid pages are listed, the Others page is hidden",
		WM.optionsSub.self.redirectCategory == nil and WM.optionsSub.party.redirectCategory == nil and WM.optionsSub.others.redirectCategory == WM.optionsCategory)
	W.openedCategory = nil; W.prints = {}
	slash("others")
	check("/wellmet others while Others is off: opens the main page and says to tick it", W.openedCategory == 1 and printed(W, "Others section is switched off"))
	local box = E.g.WellMetShowOthers
	box.checked = true
	box.scripts.OnClick(box)
	check("ticking Others on the main page switches the section on, shows its page and rebuilds the list",
		WM.db.others.enabled == true and WM.optionsSub.others.redirectCategory == nil and rebuilt == 1)
	slash("others"); check("/wellmet others", W.openedCategory == WM.optionsSub.others:GetID())
	box.checked = false
	box.scripts.OnClick(box)
	check("unticking hides the page again", WM.db.others.enabled == false and WM.optionsSub.others.redirectCategory == WM.optionsCategory and rebuilt == 2)
	E.g.WellMetShowSelf.checked = false
	E.g.WellMetShowSelf.scripts.OnClick(E.g.WellMetShowSelf)
	check("Self can be unticked too: its page goes, its switch is off", WM.db.self.enabled == false and WM.optionsSub.self.redirectCategory == WM.optionsCategory)
	E.g.WellMetShowSelf.checked = true
	E.g.WellMetShowSelf.scripts.OnClick(E.g.WellMetShowSelf)
	WM.db.others.enabled = true; WM:ApplySectionVisibility()
	check("the sub-pages have no switch of their own any more (the main page owns them)",
		not readFile("UI/Options.lua"):find("buildEnableCheck", 1, true))
	slash("raid"); check("/wellmet raid opens Party / Raid", W.openedCategory == WM.optionsSub.party:GetID())

	-- independence: each section has its own switch, choices and radius
	local function press2(WMx, Ex) local b = Ex.g.WellMetCast; b.scripts.PreClick(b, "LeftButton", true); return b end
	local WM2, ns2, E2, W2 = load()
	W2.groupSize = 1
	addUnit(W2, "party1", { class = "WARRIOR", name = "Wally", guid = "G-wally", dist = 8, auras = {} })
	addUnit(W2, "nameplate1", { class = "PRIEST", name = "Stranger", guid = "G-stranger", interact = "mid", auras = {} })
	W2.plates = { "nameplate1" }
	W2.units.player.auras = { ["Blessing of Wisdom"] = true, ["Devotion Aura"] = true }
	W2.spells["Devotion Aura"] = 465; W2.known[465] = true
	WM2.db.party.enabled = false
	local cands = ns2.Discovery.Discover()
	local sawGroup, sawStranger = false, false
	for _, c in ipairs(cands) do if c.tier == 1 then sawGroup = true elseif c.tier == 2 then sawStranger = true end end
	check("Party / Raid off: group members are not even looked at; strangers still are", not sawGroup and sawStranger)
	WM2.db.party.enabled = true; WM2.db.others.enabled = false
	cands = ns2.Discovery.Discover()
	sawGroup, sawStranger = false, false
	for _, c in ipairs(cands) do if c.tier == 1 then sawGroup = true elseif c.tier == 2 then sawStranger = true end end
	check("Others off: strangers are not looked at; the group still is", sawGroup and not sawStranger)

	-- self only: with the other two sections off the addon is just your own buffs
	WM2.db.party.enabled = false; WM2.db.others.enabled = false
	W2.units.player.auras = {}
	local b = press(E2)
	check("only Self on: the key casts your own buff and nothing else is considered", b.attrs.spell == "Devotion Aura" and b.attrs.unit == "player")
	W2.units.player.auras = { ["Devotion Aura"] = true, ["Blessing of Wisdom"] = true }
	W2.now = W2.now + 100; ns2.Select.Reset()
	check("...and with nothing of yours missing it casts nothing (the group and strangers are off)", press(E2).attrs.type == nil)
	WM2.db.self.enabled = false
	W2.units.player.auras = {}
	W2.now = W2.now + 100; ns2.Select.Reset()
	check("Self off: your own buffs are not cast", press(E2).attrs.type == nil)
	WM2.db.self.enabled = true

	-- separate radii
	WM2.db.party.enabled = true; WM2.db.others.enabled = true
	WM2.db.party.radius = 10; WM2.db.others.radius = 0
	W2.units.player.auras = { ["Devotion Aura"] = true, ["Blessing of Wisdom"] = true }
	W2.units.party1.distSq = 15 * 15                           -- group member at 15 yards
	local best, skipped = ns2.Select.Pick({ { unit = "party1", key = "G-wally", name = "Wally", tier = 1, class = "WARRIOR", order = 1 },
		{ unit = "nameplate1", key = "G-s", name = "S", tier = 2, class = "PRIEST", order = 2 } }, { now = 100, settings = WM2.db, caster = WM2.caster, probe = ns2.Probe })
	local reasons = {}
	for _, sk in ipairs(skipped) do reasons[sk.cand.key] = sk.reason end
	check("Party / Raid radius 10 skips a group member at 15 yd, while Others (radius 0) still takes strangers",
		reasons["G-wally"] and reasons["G-wally"]:find("10 yd radius", 1, true) and best and best.cand.key == "G-s")
	WM2.db.party.radius = 0

	-- migration of a pre-sections profile keeps the same behavior
	local WM3, ns3, E3 = load({ login = false })
	E3.g.WellMetDB = { profile = { radius = 28, strangers = true, groupFirst = true, includeSelf = false, allowMounted = true, debug = true,
		assign = { WARRIOR = "WISDOM" }, stack = {}, selfChoice = { AURA = "RETRIBUTION" }, unknownClass = "MIGHT" } }
	WM3:InitDB()
	local d = WM3.db
	check("migration: strangers were on, so Others stays on; Self follows 'buff myself'; radius and choices carry over",
		d.schema == 2 and d.others.enabled == true and d.party.enabled == true and d.self.enabled == false
		and d.party.radius == 28 and d.others.radius == 28 and d.party.assign.WARRIOR == "WISDOM" and d.others.assign.WARRIOR == "WISDOM"
		and d.self.choice.AURA == "RETRIBUTION" and d.allowMounted == true and d.debug == true)
	check("...and the old flat keys are gone", d.radius == nil and d.strangers == nil and d.assign == nil and d.stack == nil and d.selfChoice == nil and d.includeSelf == nil and d.groupFirst == nil)
	WM3:InitDB()
	check("migrating twice changes nothing", WM3.db.party.radius == 28 and WM3.db.self.enabled == false)

	-- the macro button
	local WM4, ns4, E4, W4 = load()
	WM4:CreateMacro()
	check("Create macro: an account macro 'WM' with the picked icon and /click WellMetCast, on the cursor",
		W4.macros[1] and W4.macros[1].name == "WM" and W4.macros[1].icon == 4630437 and W4.macros[1].body == "/click WellMetCast" and W4.cursorMacro == 1)
	check("...and it says so", printed(W4, "created") and printed(W4, "cursor"))
	W4.cursorMacro = nil; W4.prints = {}
	WM4:CreateMacro()
	check("pressing it again reuses the macro (no second copy) and puts it on the cursor", W4.macros[2] == nil and W4.cursorMacro == 1 and printed(W4, "cursor"))
	W4.macros[1].body = "/cast Something Else"
	W4.prints = {}; W4.cursorMacro = nil
	WM4:CreateMacro()
	check("a different macro already called WM is never overwritten", W4.macros[1].body == "/cast Something Else" and W4.cursorMacro == nil and printed(W4, "does something else"))
	W4.macros = { { name = "a", body = "" }, { name = "b", body = "" }, { name = "c", body = "" } }
	W4.prints = {}
	WM4:CreateMacro()
	check("account macros full: it makes a character macro instead", W4.macros[4] and W4.macros[4].name == "WM")
	W4.macros = { { name = "a", body = "" }, { name = "b", body = "" }, { name = "c", body = "" }, { name = "d", body = "" }, { name = "e", body = "" } }
	W4.prints = {}; W4.cursorMacro = nil
	WM4:CreateMacro()
	check("every slot full: it says so and creates nothing", W4.cursorMacro == nil and printed(W4, "No free macro slot"))
	W4.macros = {}; W4.combat = true; W4.prints = {}
	WM4:CreateMacro()
	check("in combat: no macro is made", W4.macros[1] == nil and printed(W4, "combat"))
	E4.g.SlashCmdList.WELLMET("macro")
end

----------------------------------------------------------------------
print("== Chat probe")
do
	local WM, ns, E, W = load({ debug = false })
	local slash = E.g.SlashCmdList.WELLMET
	check("debug is off to begin with", WM.db.debug == false)
	slash("probe")
	check("/wellmet probe turns debug on (its findings are log lines) and listens to party, raid and instance chat",
		WM.db.debug == true)
	local chatFrame
	for _, f in ipairs(E.frames) do local ev = rawget(f, "events"); if ev and ev.CHAT_MSG_PARTY then chatFrame = f end end
	check("...registering all six chat events", chatFrame and chatFrame.events.CHAT_MSG_PARTY_LEADER and chatFrame.events.CHAT_MSG_RAID
		and chatFrame.events.CHAT_MSG_RAID_LEADER and chatFrame.events.CHAT_MSG_INSTANCE_CHAT and chatFrame.events.CHAT_MSG_INSTANCE_CHAT_LEADER)

	-- a readable message is logged with its text; a secret one is logged as SECRET
	W.lockdown = false
	chatFrame.scripts.OnEvent(chatFrame, "CHAT_MSG_PARTY", "!buff might", "Bob", "", "", "", "", 0, 0, "", 0, 1, "Player-1-bob")
	addUnit(W, "hidden", { secretGuid = true })
	local SECRET = E.g.UnitGUID("hidden")
	W.lockdown = true; W.inInstance = true
	chatFrame.scripts.OnEvent(chatFrame, "CHAT_MSG_RAID", SECRET, SECRET, "", "", "", "", 0, 0, "", 0, 2, SECRET)
	local report = WM:BuildReport()
	check("a readable party message is logged with text, sender and guid, and the lockdown state",
		report:find("probe chat CHAT_MSG_PARTY text=!buff might sender=Bob guid=Player-1-bob lockdown=false instance=false(none)", 1, true) ~= nil)
	check("a secret raid message is logged as SECRET (text, sender and guid), with lockdown=true and the instance type",
		report:find("probe chat CHAT_MSG_RAID text=SECRET sender=SECRET guid=SECRET lockdown=true instance=true(party)", 1, true) ~= nil)
	W.lockdown = false; W.inInstance = false

	-- sending
	W.groupSize = 0
	slash("probe send")
	check("send with no group: nothing is sent, and it says why", #W.sent == 0 and printed(W, "Join a party"))
	W.groupSize = 2
	slash("probe send")
	check("send in a party: one line goes to PARTY and the result is logged",
		#W.sent == 1 and W.sent[1].chatType == "PARTY" and W.sent[1].msg:find("%[WellMet%] chat probe %(slash command%)") ~= nil
		and WM:BuildReport():find("probe send slash command PARTY ok", 1, true) ~= nil)
	W.raid = true
	slash("probe send")
	check("in a raid it goes to RAID", W.sent[2] and W.sent[2].chatType == "RAID")
	W.raid = false
	W.sendError = "chat restricted"
	slash("probe send")
	check("a refused send is caught and the error is logged", WM:BuildReport():find("probe send slash command PARTY ERROR", 1, true) ~= nil and #W.sent == 2)
	W.sendError = nil

	-- the next press sends (a key press, then a macro press), exactly once
	local btn = E.g.WellMetCast
	slash("probe press")
	btn.scripts.PreClick(btn, "LeftButton", true)
	check("probe press: the next KEY press sends one line", #W.sent == 3 and W.sent[3].msg:find("(key press)", 1, true) ~= nil)
	btn.scripts.PreClick(btn, "LeftButton", false)
	check("...and only that one press (the key's release does not send again)", #W.sent == 3)
	slash("probe press")
	W.now = W.now + 100
	btn.scripts.PreClick(btn, "LeftButton", false)
	check("probe press: a MACRO press (an up click) sends and is labelled as a macro press", #W.sent == 4 and W.sent[4].msg:find("(macro press)", 1, true) ~= nil)
	check("a press when not armed sends nothing", (function() btn.scripts.PreClick(btn, "LeftButton", true); return #W.sent == 4 end)())

	-- stop listening
	slash("probe")
	check("a second /wellmet probe stops listening", not chatFrame.events.CHAT_MSG_PARTY and not chatFrame.events.CHAT_MSG_RAID)
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
	local PARTY = "WellMetPartyClass"
	local partyOrder = {}
	for _, f in ipairs(E.frames) do if type(f.name) == "string" and f.name:find("^" .. PARTY) then partyOrder[#partyOrder + 1] = f.name:sub(#PARTY + 1) end end
	check("Party / Raid has a dropdown per class, alphabetical (Druid ... Warrior), and no cycle buttons or 'class unreadable' row",
		table.concat(partyOrder, ",") == "DRUID,HUNTER,MAGE,PALADIN,PRIEST,ROGUE,SHAMAN,WARLOCK,WARRIOR"
		and not readFile("UI/Options.lua"):find("Class unreadable", 1, true) and not readFile("UI/Options.lua"):find("cycle(", 1, true))
	local radius = menuOf(E.g.WellMetPartyRadius)
	check("radius dropdown lists cast range / 28 / 10 and marks the saved one", #radius == 3 and radius[1].selected and not radius[2].selected)
	radius[2].pick()
	check("picking 28 yards saves it for Party / Raid only", WM.db.party.radius == 28 and WM.db.others.radius == 0)
	local warrior = menuOf(E.g.WellMetPartyClassWARRIOR)
	check("a class dropdown lists Might / Wisdom / Skip, each with a spell icon in the open list",
		#warrior == 3 and warrior[1].label:find("Blessing of Might", 1, true) and warrior[1].label:find("|T1019834:", 1, true)
		and warrior[2].label:find("|T1019742:", 1, true) and warrior[3].label:find("Skip this class", 1, true) and warrior[3].label:find("|T", 1, true))
	check("menu items carry their value, and the closed dropdown shows only the icon",
		warrior[1].data == "MIGHT" and warrior[3].data == "NONE" and E.g.WellMetPartyClassWARRIOR.selTranslator ~= nil
		and E.g.WellMetPartyClassWARRIOR.selTranslator({ data = "WISDOM" }) == "|T1019742:20|t")
	check("the class default is the selected item (Warrior -> Might)", warrior[1].selected and not warrior[2].selected)
	check("Hunter defaults to Wisdom, Rogue to Might", ns.AssignedKey(WM.db.party, "HUNTER") == "WISDOM" and ns.AssignedKey(WM.db.party, "ROGUE") == "MIGHT")
	warrior[2].pick()
	check("picking Wisdom for Warrior saves it in Party / Raid, and Others is untouched",
		WM.db.party.assign.WARRIOR == "WISDOM" and WM.db.others.assign.WARRIOR == nil and menuOf(E.g.WellMetPartyClassWARRIOR)[2].selected
		and menuOf(E.g.WellMetOthersClassWARRIOR)[1].selected)
	menuOf(E.g.WellMetOthersClassWARRIOR)[3].pick()
	check("...each section keeps its own table (Others: Skip, Party / Raid: Wisdom)", WM.db.others.assign.WARRIOR == "NONE" and WM.db.party.assign.WARRIOR == "WISDOM")
	WM.db.party.radius, WM.db.party.assign.WARRIOR, WM.db.others.assign.WARRIOR = 0, nil, nil     -- leave the settings as found

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
