--[[ WellMet — ask for a buff back.

After you buff a STRANGER (not in your party or raid), WellMet can whisper them asking for a buff of their
class in return, when you lack it and their level is close to yours. Off by default (settings > Group tools).

  - only strangers, only a player whose class buffs others (Paladin, Mage, Druid, Priest), only within `levels`
    levels of yours, only a buff you lack, never in combat or a chat lockdown;
  - each person is asked at most once per session (their GUID is remembered until /reload);
  - the text is yours: {name} (their name), {spell} (the buff you ask for), {mybuff} (the buff you just cast on them).

Choose / Render are pure (no WoW API) so they are tested headless.
]]

local ADDON, ns = ...
if not ns.supported then return end      -- this class has no buffs: WellMet does nothing
local WM = ns.WM

local BuffAsk = {}
ns.BuffAsk = BuffAsk

BuffAsk.DEFAULT_MESSAGE = "Hi {name}, thanks for the company! If you have a moment, could you buff me back with {spell}?"
BuffAsk.MAX = 255        -- the longest chat line the game sends

local asked = {}         -- guid -> true, this session

-- The buff to ask a player of class `targetClass` for: the first one their class gives that works on strangers, that suits
-- your own class and that you lack. `lacks(buff)` is true / false / nil (can't tell). Returns the buff, or nil + a reason.
function BuffAsk.Choose(targetClass, myClass, lacks)
	local caster = ns.CasterData[targetClass]
	if not caster then return nil, "their class has no buffs for others" end
	local keys = {}
	if caster.mode == "assign" then
		for _, key in ipairs(ns.DefaultPrio[myClass] or {}) do keys[#keys + 1] = key end
		for _, key in ipairs(caster.order) do keys[#keys + 1] = key end
	else
		for _, key in ipairs(caster.order) do
			local buff = caster.buffs[key]
			if buff.defaultClasses and buff.defaultClasses[myClass] then keys[#keys + 1] = key end
		end
	end
	local unknown = false
	for _, key in ipairs(keys) do
		local buff = caster.buffs[key]
		if buff and not buff.partyOnly then
			local l = lacks(buff)
			if l == true then return buff end
			if l == nil then unknown = true end
		end
	end
	return nil, unknown and "can't read your auras" or "you already have their buffs"
end

-- Fill the {placeholders}; unknown ones stay as typed. Capped at what one chat line holds.
function BuffAsk.Render(template, vars)
	local text = tostring(template or ""):gsub("{(%w+)}", function(k) return vars[k] end)
	if #text > BuffAsk.MAX then text = text:sub(1, BuffAsk.MAX) end
	return text
end

-- Who to whisper: "Name-Realm" from the GUID when the game gives it (a player from another realm needs the realm),
-- else the full name read off the nameplate.
function BuffAsk.Address(p)
	if p.guid and type(UnitNameFromGUID) == "function" then
		local ok, name, realm = pcall(UnitNameFromGUID, p.guid)
		if ok and type(name) == "string" and not issecretvalue(name) and name ~= "" then
			if type(realm) == "string" and not issecretvalue(realm) and realm ~= "" then return name .. "-" .. realm end
		end
	end
	return p.fullName
end

-- Called when a cast of yours on `p` (WM.pending: name, fullName, guid, class, level, stranger, spell) succeeded.
function BuffAsk.Maybe(p)
	local cfg = WM.db.askBack
	if not cfg or not cfg.enabled then return end
	local function skip(why) WM:Log("ask back: skipped " .. ns.SafeStr(p.name) .. " - " .. why) end
	if not p.stranger or not p.fullName then return skip("not a stranger (or no full name)") end
	if p.guid and asked[p.guid] then return skip("already asked this session") end
	local lvl, mine = p.level, UnitLevel("player")
	if type(lvl) ~= "number" or issecretvalue(lvl) or type(mine) ~= "number" then return skip("level not readable") end
	if math.abs(lvl - mine) > (cfg.levels or 10) then return skip("level " .. lvl .. " is more than " .. (cfg.levels or 10) .. " from yours") end
	if InCombatLockdown() then return skip("in combat") end
	local buff, why = BuffAsk.Choose(p.class, WM.classToken, function(b) return ns.Lacks("player", b) end)
	if not buff then return skip(why) end
	local text = BuffAsk.Render(cfg.message ~= "" and cfg.message or BuffAsk.DEFAULT_MESSAGE,
		{ name = p.name, spell = buff.name, mybuff = p.spell })
	if ns.Requests.Reply(BuffAsk.Address(p), text) then
		if p.guid then asked[p.guid] = true end
		WM:Log("ask back: whispered " .. ns.SafeStr(p.fullName) .. " asking for " .. buff.name)
	end
end

function BuffAsk.Forget() for k in pairs(asked) do asked[k] = nil end end
