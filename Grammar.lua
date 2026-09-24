-- Macro Bench grammar: the macro language itself.
--
-- Everything in this addon turns on one rule: the macro TEXT is what is real. Blocks are a view of
-- it. So this file holds one pair of functions, Parse and Compile, and they are each other's
-- inverse: Compile(Parse(text)) gives the same macro back (whitespace normalised), for every macro,
-- including ones this addon does not understand. Anything unrecognized becomes a "raw" block that
-- compiles back out verbatim, so nothing a player pasted in can ever be lost by round-tripping.
--
-- A block is plain data (it goes into the saved variables as it stands):
--   { kind = "tooltip",           clauses = { { conds = { "mod:shift" }, arg = "Frostbolt" }, ... } }
--   { kind = "cmd", cmd = "cast", clauses = { ... } }
--   { kind = "script", cmd = "run", body = "..." }
--   { kind = "comment", text = "# ..." }
--   { kind = "raw", text = "..." }      anything else, kept exactly
--   { kind = "blank" }                  an empty line
-- A clause is one "[conds] argument" group; several clauses are separated by ";" in the macro and
-- shown as "otherwise" rows in the window. Several conds on one clause are Blizzard's OR: "[a][b] X".

local ADDON, ns = ...
local G = {}
ns.Grammar = G

local strlower, format, concat = string.lower, string.format, table.concat

-- ------------------------------------------------------------------
-- Commands
-- ------------------------------------------------------------------
-- cond   the command reads [conditions]; on anything else they are just part of the text
-- arg    what the argument is, so the window can offer the right picker and the check can look it up
-- gcd    casting this costs the global cooldown, so only the first such line in a macro can fire
local COMMANDS = {}
local ALIASES = {}
local ORDER = {}

local function Cmd(name, def)
	def.cmd = name
	COMMANDS[name] = def
	ORDER[#ORDER + 1] = name
	if def.aliases then
		for _, a in ipairs(def.aliases) do ALIASES[a] = name end
	end
end

-- gcd: "spell" means it spends the global cooldown, so only the first such line in a macro can
-- fire on one press. Items are not the same: using a trinket and then another, or a poison and then
-- the weapon slot, is an ordinary macro that works.
Cmd("cast", { label = "Cast", arg = "spell", cond = true, gcd = "spell", aliases = { "spell" } })
Cmd("castsequence", { label = "Cast in order", arg = "sequence", cond = true, gcd = "spell" })
Cmd("castrandom", { label = "Cast one at random", arg = "spells", cond = true, gcd = "spell" })
Cmd("use", { label = "Use item", arg = "item", cond = true, gcd = "item" })
Cmd("userandom", { label = "Use one at random", arg = "items", cond = true, gcd = "item" })
Cmd("click", { label = "Click a button", arg = "frame", cond = true, gcd = "item" })
Cmd("stopcasting", { label = "Stop casting", arg = "none", cond = true })
Cmd("stopmacro", { label = "Stop here", arg = "none", cond = true })
Cmd("stopattack", { label = "Stop attacking", arg = "none", cond = true })
Cmd("startattack", { label = "Start attacking", arg = "none", cond = true })
Cmd("cancelaura", { label = "Cancel a buff", arg = "spell", cond = true })
Cmd("cancelform", { label = "Leave form", arg = "none", cond = true })
Cmd("cancelqueuedspell", { label = "Cancel queued spell", arg = "none", cond = true })
Cmd("target", { label = "Target", arg = "unit", cond = true })
Cmd("targetexact", { label = "Target exactly", arg = "text", cond = true })
Cmd("targetenemy", { label = "Target nearest enemy", arg = "none", cond = true })
Cmd("targetfriend", { label = "Target nearest friend", arg = "none", cond = true })
Cmd("targetparty", { label = "Target next in party", arg = "none", cond = true })
Cmd("targetraid", { label = "Target next in raid", arg = "none", cond = true })
Cmd("targetlasttarget", { label = "Target last target", arg = "none", cond = true })
Cmd("targetlastenemy", { label = "Target last enemy", arg = "none", cond = true })
Cmd("cleartarget", { label = "Clear target", arg = "none", cond = true })
Cmd("focus", { label = "Set focus", arg = "unit", cond = true })
Cmd("clearfocus", { label = "Clear focus", arg = "none", cond = true })
Cmd("assist", { label = "Assist", arg = "unit", cond = true })
Cmd("equip", { label = "Equip", arg = "item", cond = true })
Cmd("equipslot", { label = "Equip to slot", arg = "slotitem", cond = true })
Cmd("equipset", { label = "Equip set", arg = "text", cond = true })
Cmd("dismount", { label = "Dismount", arg = "none", cond = true })
Cmd("leavevehicle", { label = "Leave vehicle", arg = "none", cond = true })
Cmd("changeactionbar", { label = "Change action bar", arg = "number", cond = true })
Cmd("swapactionbar", { label = "Swap action bars", arg = "number", cond = true })
Cmd("petattack", { label = "Pet: attack", arg = "unit", cond = true })
Cmd("petfollow", { label = "Pet: follow", arg = "none", cond = true })
Cmd("petstay", { label = "Pet: stay", arg = "none", cond = true })
Cmd("petpassive", { label = "Pet: passive", arg = "none", cond = true })
Cmd("petdefensive", { label = "Pet: defensive", arg = "none", cond = true })
Cmd("petaggressive", { label = "Pet: aggressive", arg = "none", cond = true })
Cmd("petautocaston", { label = "Pet: autocast on", arg = "spell", cond = true })
Cmd("petautocastoff", { label = "Pet: autocast off", arg = "spell", cond = true })
Cmd("usetalents", { label = "Use talent set", arg = "number", cond = true })

-- Not secure commands: conditions in front of these are not read, they are simply said out loud.
Cmd("say", { label = "Say", arg = "text", aliases = { "s" } })
Cmd("yell", { label = "Yell", arg = "text", aliases = { "y" } })
Cmd("party", { label = "Party", arg = "text", aliases = { "p" } })
Cmd("raid", { label = "Raid", arg = "text" })
Cmd("raidwarning", { label = "Raid warning", arg = "text", aliases = { "rw" } })
Cmd("guild", { label = "Guild", arg = "text", aliases = { "g" } })
Cmd("officer", { label = "Officer", arg = "text", aliases = { "o" } })
Cmd("whisper", { label = "Whisper", arg = "text", aliases = { "w", "tell", "t" } })
Cmd("emote", { label = "Emote", arg = "text", aliases = { "me", "em" } })
Cmd("run", { label = "Script", arg = "lua", script = true, aliases = { "script" } })
Cmd("macro", { label = "Run a macro", arg = "text" })
Cmd("follow", { label = "Follow", arg = "unit", aliases = { "f" } })
Cmd("inspect", { label = "Inspect", arg = "unit" })
Cmd("trade", { label = "Trade", arg = "unit" })
Cmd("duel", { label = "Duel", arg = "unit" })
Cmd("invite", { label = "Invite", arg = "unit", aliases = { "inv" } })
Cmd("reload", { label = "Reload the interface", arg = "none", aliases = { "rl" } })
Cmd("combatlog", { label = "Combat log on or off", arg = "none" })
Cmd("dance", { label = "Dance", arg = "none" })

G.COMMANDS, G.ORDER = COMMANDS, ORDER

-- The canonical command for what was typed ("/s" -> "say"), or nil when it is not one of ours.
function G.Canon(cmd)
	if not cmd then return nil end
	cmd = strlower(cmd)
	return COMMANDS[cmd] and cmd or ALIASES[cmd]
end

function G.Def(cmd)
	local canon = G.Canon(cmd)
	return canon and COMMANDS[canon] or nil
end

-- Does the client itself know this slash command? Everything above and everything any addon or the
-- client has registered: chat commands live in SlashCmdList under a token, the secure ones that only
-- work from a macro live in SecureCmdList, and the words themselves are the SLASH_* globals.
local clientCmds
local function ClientCommands()
	if clientCmds then return clientCmds end
	clientCmds = {}
	local function AddToken(token)
		-- SLASH_TOKEN1, SLASH_TOKEN2 ... hold the words, localized.
		for i = 1, 8 do
			local word = _G["SLASH_" .. token .. i]
			if not word then break end
			if type(word) == "string" and word:sub(1, 1) == "/" then clientCmds[strlower(word:sub(2))] = true end
		end
	end
	if type(SlashCmdList) == "table" then
		for token in pairs(SlashCmdList) do AddToken(token) end
	end
	if type(SecureCmdList) == "table" then
		for token in pairs(SecureCmdList) do
			AddToken(token)
			clientCmds[strlower(token)] = true
		end
	end
	if type(hash_SlashCmdList) == "table" then
		for word in pairs(hash_SlashCmdList) do
			if type(word) == "string" and word:sub(1, 1) == "/" then clientCmds[strlower(word:sub(2))] = true end
		end
	end
	return clientCmds
end

-- Called again after login, when every addon has registered what it registers.
function G.ForgetClientCommands() clientCmds = nil end

function G.KnownCommand(cmd)
	if G.Canon(cmd) then return true end
	return ClientCommands()[strlower(cmd or "")] == true
end

-- ------------------------------------------------------------------
-- Conditions
-- ------------------------------------------------------------------
-- takes  what follows the colon: nil none, "number", "mod", "word", "spell", "slot", "list"
-- only   this client may not have it at all; the check says so rather than pretending
local CONDS = {}
local CONDALIAS = {}
local CONDORDER = {}
local function Cond(name, def)
	def.name = name
	CONDS[name] = def
	CONDORDER[#CONDORDER + 1] = name
	if def.aliases then for _, a in ipairs(def.aliases) do CONDALIAS[a] = name end end
end

Cond("help", { label = "friendly target" })
Cond("harm", { label = "hostile target" })
Cond("exists", { label = "the unit is there" })
Cond("dead", { label = "the unit is dead" })
Cond("combat", { label = "in combat" })
Cond("mod", { label = "modifier held", takes = "mod", aliases = { "modifier" } })
Cond("button", { label = "mouse button", takes = "number", aliases = { "btn" } })
Cond("stealth", { label = "stealthed" })
Cond("form", { label = "shapeshift form", takes = "number", aliases = { "stance" } })
Cond("shapeshift", { label = "in any form" })
Cond("pet", { label = "pet out", takes = "word" })
Cond("party", { label = "the unit is in your party" })
Cond("raid", { label = "the unit is in your raid" })
Cond("group", { label = "in a group", takes = "word" })
Cond("channeling", { label = "channeling", takes = "spell" })
Cond("mounted", { label = "mounted" })
Cond("swimming", { label = "swimming" })
Cond("flying", { label = "flying" })
Cond("flyable", { label = "flying is allowed here" })
Cond("indoors", { label = "indoors" })
Cond("outdoors", { label = "outdoors" })
Cond("resting", { label = "resting" })
Cond("cursor", { label = "something on the cursor" })
Cond("equipped", { label = "item type equipped", takes = "word", aliases = { "worn" } })
Cond("actionbar", { label = "action bar page", takes = "number", aliases = { "bar" } })
Cond("bonusbar", { label = "bonus bar", takes = "number" })
Cond("extrabar", { label = "extra action bar showing" })
Cond("overridebar", { label = "override bar showing" })
Cond("possessbar", { label = "possess bar showing" })
Cond("canexitvehicle", { label = "can leave the vehicle" })
Cond("vehicleui", { label = "vehicle interface showing" })
Cond("unithasvehicleui", { label = "the unit has a vehicle interface" })
Cond("spec", { label = "specialisation", takes = "number", only = "later expansions" })
Cond("talent", { label = "talent taken", takes = "list", only = "later expansions" })
Cond("known", { label = "spell known", takes = "spell", only = "later expansions" })
Cond("petbattle", { label = "in a pet battle", only = "later expansions" })
Cond("advflyable", { label = "skyriding is allowed here", only = "later expansions" })

G.CONDS, G.CONDORDER = CONDS, CONDORDER

function G.CondDef(name)
	if not name then return nil end
	name = strlower(name)
	return CONDS[name] or (CONDALIAS[name] and CONDS[CONDALIAS[name]]) or nil
end

G.MODS = { "shift", "ctrl", "alt", "none" }

G.UNITS = {
	"player", "target", "targettarget", "mouseover", "focus", "focustarget", "pet", "pettarget",
	"party1", "party2", "party3", "party4", "partypet1", "partypet2", "partypet3", "partypet4",
	"arena1", "arena2", "arena3", "arena4", "arena5", "boss1", "boss2", "boss3", "boss4",
	"none", "vehicle", "npc",
}

local UNITSET = {}
for _, u in ipairs(G.UNITS) do UNITSET[u] = true end

-- Is this a unit the game will accept? true, false, or nil when it could be a player's name
-- (@Thrall is perfectly good, and no list can hold every name).
function G.KnownUnit(unit)
	if not unit or unit == "" then return false end
	local u = strlower(unit)
	if UNITSET[u] then return true end
	if u:match("^raid%d+$") or u:match("^raidpet%d+$") or u:match("^party%d$") or u:match("^partypet%d$") then return true end
	if u:match("^boss%d$") or u:match("^arena%d$") or u:match("^arenapet%d$") then return true end
	if u:match("^soft%a+$") then return true end
	-- A name: a letter, then letters only, possibly with a realm after a dash.
	if unit:match("^[^%d%p]+$") or unit:match("^[^%d%p]+%-[^%d%p]+$") then return nil end
	return false
end

-- ------------------------------------------------------------------
-- Terms: one item inside the brackets, e.g. "mod:shift", "@mouseover", "nodead"
-- ------------------------------------------------------------------
-- { neg = true/false, key = "mod", value = "shift", unit = "mouseover", raw = "..." }
function G.ParseTerm(raw)
	local t = { raw = raw }
	local s = raw:match("^%s*(.-)%s*$")
	if s == "" then return nil end
	local unit = s:match("^@(.+)$") or s:match("^target%s*=%s*(.+)$")
	if unit then
		t.unit = unit
		t.key = "@"
		t.value = unit
		return t
	end
	local body = s
	local key, value = body:match("^([%a]+)%s*:%s*(.*)$")
	if not key then key = body:match("^([%a]+)$") end
	if not key then return t end -- unparseable; kept as raw so it still compiles back
	-- "no" in front negates, but only when what is left is a condition we know ("nodead", not "none").
	if strlower(key):sub(1, 2) == "no" and G.CondDef(key:sub(3)) then
		t.neg = true
		key = key:sub(3)
	end
	t.key = strlower(key)
	t.value = value
	return t
end

function G.Terms(cond)
	local out = {}
	for piece in tostring(cond or ""):gmatch("[^,]+") do
		local t = G.ParseTerm(piece)
		if t then out[#out + 1] = t end
	end
	return out
end

function G.TermText(t)
	if t.unit then return "@" .. t.unit end
	local s = (t.neg and "no" or "") .. (t.key or "")
	if t.value and t.value ~= "" then s = s .. ":" .. t.value end
	return s
end

-- The words a chip shows: short, and in English rather than macro.
local TERM_WORDS = {
	["@player"] = "on me", ["@target"] = "on target", ["@mouseover"] = "on mouseover",
	["@focus"] = "on focus", ["@pet"] = "on pet", ["@targettarget"] = "on target's target",
	harm = "enemy", noharm = "not an enemy", help = "friendly", nohelp = "not friendly",
	exists = "exists", noexists = "nothing there", dead = "dead", nodead = "alive",
	combat = "in combat", nocombat = "out of combat", stealth = "stealthed", nostealth = "not stealthed",
	mounted = "mounted", nomounted = "not mounted", nomod = "no modifier",
	["mod:shift"] = "shift", ["mod:ctrl"] = "ctrl", ["mod:alt"] = "alt",
	pet = "pet out", nopet = "no pet", cursor = "on the cursor",
	swimming = "swimming", flying = "flying", resting = "resting",
	indoors = "indoors", outdoors = "outdoors", shapeshift = "in a form", noshapeshift = "no form",
}

function G.TermLabel(t)
	local text = G.TermText(t)
	local word = TERM_WORDS[strlower(text)]
	if word then return word end
	-- form and stance are the same condition under two names; the words are the same either way.
	if t.key == "form" or t.key == "stance" then
		if not t.value or t.value == "" then return t.neg and "in no form" or "in a form" end
		return (t.neg and "not in form " or "in form ") .. t.value
	end
	if t.key == "button" or t.key == "btn" then
		local named = ({ ["1"] = "left click", ["2"] = "right click", ["3"] = "middle click" })[t.value or ""]
		return (t.neg and "not " or "") .. (named or ("button " .. (t.value or "?")))
	end
	if t.key == "pet" and t.value and t.value ~= "" then
		return (t.neg and "no " or "") .. t.value .. " out"
	end
	if t.key == "group" then return (t.neg and "not in a " or "in a ") .. (t.value or "group") end
	local def = G.CondDef(t.key)
	if def then return (t.neg and "not " or "") .. def.label .. (t.value and t.value ~= "" and (" " .. t.value) or "") end
	return text
end

-- A whole condition in words: "shift, on mouseover, enemy".
function G.CondLabel(cond)
	local parts = {}
	for _, t in ipairs(G.Terms(cond)) do parts[#parts + 1] = G.TermLabel(t) end
	return concat(parts, ", ")
end

-- ---- Buckets: a condition split into the parts the bench shows ------
-- One set of brackets holds several kinds of question at once: what you are holding down, what the
-- spell is aimed at, and what is true of you. The bench shows those as separate blocks, so terms are
-- sorted into buckets and put back together again. Order inside the brackets means nothing to the
-- game, so a condition that has been edited comes back in bucket order; one that has only been read
-- is never rewritten, which is what keeps text the player typed exactly as they typed it.
G.BUCKET_ORDER = { "mods", "target", "state", "other" }
G.BUCKET_LABEL = { mods = "pressed with", target = "aimed at", state = "only when", other = "condition" }
G.BUCKET_HINT = {
	mods = "Which modifier keys have to be down, and which mouse button pressed the macro. Several modifiers means all of them at once.",
	target = "Which unit the line is aimed at, and what has to be true of it.",
	state = "What has to be true of you: in combat, in a form, stealthed, mounted.",
	other = "Conditions that do not fit the other blocks, written out as the game reads them.",
}

local TARGET_KEYS = {
	help = true, harm = true, exists = true, dead = true, party = true, raid = true,
	unithasvehicleui = true,
}
local MOD_KEYS = { mod = true, modifier = true, button = true, btn = true }

function G.BucketOf(t)
	if not t then return "other" end
	if t.unit then return "target" end
	local key = t.key
	if not key then return "other" end
	if MOD_KEYS[key] then return "mods" end
	if TARGET_KEYS[key] then return "target" end
	if G.CondDef(key) then return "state" end
	return "other"
end

-- { mods = { "mod:shift" }, target = { "@mouseover", "harm" }, state = {}, other = {} }
function G.SplitCond(cond)
	local out = { mods = {}, target = {}, state = {}, other = {} }
	for _, t in ipairs(G.Terms(cond)) do
		local bucket = G.BucketOf(t)
		local list = out[bucket]
		list[#list + 1] = G.TermText(t)
	end
	return out
end

function G.JoinBuckets(buckets)
	local parts = {}
	for _, bucket in ipairs(G.BUCKET_ORDER) do
		for _, term in ipairs(buckets[bucket] or {}) do parts[#parts + 1] = term end
	end
	return concat(parts, ",")
end

function G.BucketText(cond, bucket)
	return concat(G.SplitCond(cond)[bucket] or {}, ",")
end

-- The whole condition again with one bucket replaced by the terms given (or emptied).
function G.SetBucket(cond, bucket, text)
	local buckets = G.SplitCond(cond)
	local list = {}
	for piece in tostring(text or ""):gmatch("[^,]+") do
		-- G.Trim rather than the local one: that is declared further down the file, so the name
		-- would be read as a global here and come back nil.
		piece = G.Trim(piece)
		if piece ~= "" then list[#list + 1] = piece end
	end
	-- The unit reads first in the block that holds it: "on mouseover, an enemy, alive".
	if bucket == "target" then
		local units, rest = {}, {}
		for _, term in ipairs(list) do
			if term:sub(1, 1) == "@" then units[#units + 1] = term else rest[#rest + 1] = term end
		end
		list = units
		for _, term in ipairs(rest) do list[#list + 1] = term end
	end
	buckets[bucket] = list
	return G.JoinBuckets(buckets)
end

-- Adding or removing one term inside its own bucket, leaving the rest of the condition alone.
function G.ToggleInBucket(cond, bucket, term, force)
	local text = G.ToggleTerm(G.BucketText(cond, bucket), term, force)
	return G.SetBucket(cond, bucket, text)
end

-- ---- One condition at a time, for the controls that edit them ------
-- Two names for the same condition ("form" and "stance") are one condition here.
local function SameKey(a, b)
	local da, db = G.CondDef(a), G.CondDef(b)
	return ((da and da.name) or a) == ((db and db.name) or b)
end

-- "yes" when the condition is asked for, "no" when its opposite is, nil when it is not mentioned.
function G.TermState(cond, term)
	if G.HasTerm(cond, term) then return "yes" end
	if G.HasTerm(cond, "no" .. term) then return "no" end
	return nil
end

function G.SetTermState(cond, term, state)
	local lower, noLower = strlower(term), "no" .. strlower(term)
	local out = {}
	for _, t in ipairs(G.Terms(cond)) do
		local text = strlower(G.TermText(t))
		if text ~= lower and text ~= noLower then out[#out + 1] = G.TermText(t) end
	end
	if state == "yes" then out[#out + 1] = term
	elseif state == "no" then out[#out + 1] = "no" .. term end
	return concat(out, ",")
end

-- The value on a condition that takes one: pet:Succubus, form:1/3, channeling:Drain Life.
-- Returns the value, whether it is negated, and whether the condition is there at all.
function G.GetKeyTerm(cond, key)
	for _, t in ipairs(G.Terms(cond)) do
		if not t.unit and t.key and SameKey(t.key, key) then
			return t.value or "", t.neg and true or false, true
		end
	end
	return "", false, false
end

-- Writes that condition back. An empty value with no "not" takes the condition off altogether,
-- unless "bare" says to keep it: [pet] on its own is a question the game will answer. An empty
-- value with "not" is the bare negative, which is how [nopet] is written.
function G.SetKeyTerm(cond, key, value, neg, bare)
	local out = {}
	for _, t in ipairs(G.Terms(cond)) do
		if t.unit or not t.key or not SameKey(t.key, key) then out[#out + 1] = G.TermText(t) end
	end
	value = G.Trim(value or "")
	if value ~= "" or neg or bare then
		out[#out + 1] = (neg and "no" or "") .. key .. (value ~= "" and (":" .. value) or "")
	end
	return concat(out, ",")
end

-- ---- Toggling terms, for the condition blocks ----------------------
-- Terms that cannot both be true of the same macro, so picking one drops the other.
local EXCLUSIVE = {
	{ "combat", "nocombat" }, { "stealth", "nostealth" }, { "harm", "help" },
	{ "dead", "nodead" }, { "mounted", "nomounted" }, { "pet", "nopet" },
	{ "shapeshift", "noshapeshift" },
}
local EXCL = {}
for _, pair in ipairs(EXCLUSIVE) do
	EXCL[pair[1]] = pair[2]
	EXCL[pair[2]] = pair[1]
end

function G.HasTerm(cond, term)
	term = strlower(term)
	for _, t in ipairs(G.Terms(cond)) do
		if strlower(G.TermText(t)) == term then return true end
	end
	return false
end

-- Adds or removes one term and gives the condition string back. Only one @unit at a time, "nomod"
-- and the mod: terms push each other out, and opposites replace each other.
function G.ToggleTerm(cond, term, force)
	local want = (force == nil) and (not G.HasTerm(cond, term)) or force and true or false
	local lower = strlower(term)
	local isUnit = lower:sub(1, 1) == "@"
	local isMod = lower:match("^mod:") ~= nil
	local out = {}
	for _, t in ipairs(G.Terms(cond)) do
		local text = strlower(G.TermText(t))
		local drop = text == lower
		if want then
			if isUnit and t.unit then drop = true end
			if isMod and (text == "nomod" or text == "nomodifier") then drop = true end
			if lower == "nomod" and text:match("^mod") then drop = true end
			if EXCL[lower] and text == EXCL[lower] then drop = true end
		end
		if not drop then out[#out + 1] = G.TermText(t) end
	end
	if want then out[#out + 1] = term end
	return concat(out, ",")
end

-- ------------------------------------------------------------------
-- Parse: macro text -> blocks
-- ------------------------------------------------------------------
local function Trim(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end
G.Trim = Trim

-- "[a][b] Spell; Other" -> two clauses, the first with two conditions.
function G.ParseClauses(rest)
	local clauses = {}
	rest = tostring(rest or "")
	for piece in (rest .. ";"):gmatch("([^;]*);") do
		local arg = Trim(piece)
		local conds = {}
		while true do
			local inner, after = arg:match("^%[(.-)%]%s*(.*)$")
			if not inner then break end
			conds[#conds + 1] = Trim(inner)
			arg = after
		end
		clauses[#clauses + 1] = { conds = conds, arg = Trim(arg) }
	end
	-- "a; " leaves a trailing empty clause the player did not write; drop it, keep real ones.
	while #clauses > 1 and #clauses[#clauses].conds == 0 and clauses[#clauses].arg == "" do
		clauses[#clauses] = nil
	end
	if #clauses == 0 then clauses[1] = { conds = {}, arg = "" } end
	return clauses
end

function G.ParseLine(line)
	local trimmed = Trim(line)
	if trimmed == "" then return { kind = "blank" } end
	if strlower(trimmed):match("^#showtooltip") then
		-- Written any way round ("#ShowTooltip"); the length is what matters, and it is written
		-- back the way the game's own help writes it.
		return { kind = "tooltip", clauses = G.ParseClauses(Trim(trimmed:sub(13))) }
	end
	if trimmed:sub(1, 1) == "#" then return { kind = "comment", text = trimmed } end
	if trimmed:sub(1, 1) == "/" then
		local cmd, rest = trimmed:match("^/([^%s]+)%s*(.*)$")
		if cmd then
			local lower = strlower(cmd)
			local def = G.Def(lower)
			if def and def.script then return { kind = "script", cmd = lower, body = rest } end
			if def and def.cond then return { kind = "cmd", cmd = lower, clauses = G.ParseClauses(rest) } end
			-- Not a conditional command: the whole rest is one plain argument, brackets and all.
			return { kind = "cmd", cmd = lower, plain = true, clauses = { { conds = {}, arg = Trim(rest) } } }
		end
	end
	return { kind = "raw", text = line }
end

function G.Parse(text)
	local blocks = {}
	text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
	if text == "" then return blocks end
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		blocks[#blocks + 1] = G.ParseLine(line)
	end
	-- A macro ending in a newline is the same macro; do not keep a phantom last line.
	if #blocks > 1 and blocks[#blocks].kind == "blank" and text:sub(-1) == "\n" then blocks[#blocks] = nil end
	return blocks
end

-- ------------------------------------------------------------------
-- Compile: blocks -> macro text
-- ------------------------------------------------------------------
function G.CompileBlock(b)
	if not b then return "" end
	if b.kind == "blank" then return "" end
	if b.kind == "raw" then return b.text or "" end
	if b.kind == "comment" then return b.text or "#" end
	if b.kind == "script" then
		local body = b.body or ""
		return "/" .. (b.cmd or "run") .. (body ~= "" and (" " .. body) or "")
	end
	local head = (b.kind == "tooltip") and "#showtooltip" or ("/" .. (b.cmd or "cast"))
	local parts = {}
	for _, cl in ipairs(b.clauses or {}) do
		local s = ""
		for _, c in ipairs(cl.conds or {}) do
			if c and c ~= "" then s = s .. "[" .. c .. "]" end
		end
		local arg = Trim(cl.arg)
		if arg ~= "" then s = (s == "") and arg or (s .. " " .. arg) end
		if s ~= "" then parts[#parts + 1] = s end
	end
	local body = concat(parts, "; ")
	if body == "" then return head end
	return head .. " " .. body
end

function G.Compile(blocks)
	local lines = {}
	for i, b in ipairs(blocks or {}) do lines[i] = G.CompileBlock(b) end
	return concat(lines, "\n")
end

-- ------------------------------------------------------------------
-- Blocks: making and reading them
-- ------------------------------------------------------------------
function G.NewBlock(cmd, arg, cond)
	if cmd == "#showtooltip" then return { kind = "tooltip", clauses = { { conds = cond and { cond } or {}, arg = arg or "" } } } end
	local def = G.Def(cmd)
	if def and def.script then return { kind = "script", cmd = cmd, body = arg or "" } end
	if cmd == "#" then return { kind = "comment", text = "# " .. (arg or "") } end
	if cmd == "raw" then return { kind = "raw", text = arg or "" } end
	return { kind = "cmd", cmd = cmd, plain = (def and not def.cond) or nil, clauses = { { conds = cond and { cond } or {}, arg = arg or "" } } }
end

-- The words on a block's row.
function G.BlockLabel(b)
	if b.kind == "tooltip" then return "Show tooltip" end
	if b.kind == "comment" then return "Note" end
	if b.kind == "blank" then return "(empty line)" end
	if b.kind == "raw" then return "Text" end
	if b.kind == "script" then return "Script" end
	local def = G.Def(b.cmd)
	return (def and def.label) or ("/" .. (b.cmd or "?"))
end

function G.BlockArgKind(b)
	-- #showtooltip takes a spell, an item, or an inventory slot number, so it gets its own kind.
	if b.kind == "tooltip" then return "subject" end
	if b.kind == "script" then return "lua" end
	if b.kind == "comment" or b.kind == "raw" then return "text" end
	local def = G.Def(b.cmd)
	return def and def.arg or "text"
end

-- Does this block read conditions at all?
function G.BlockTakesCond(b)
	if b.kind == "tooltip" then return true end
	if b.kind ~= "cmd" then return false end
	local def = G.Def(b.cmd)
	return (def and def.cond) and true or false
end

-- The spell or item on a block, for the icon and for checking: the first clause that names one.
function G.BlockSubject(b)
	if b.kind ~= "cmd" and b.kind ~= "tooltip" then return nil end
	local kind = G.BlockArgKind(b)
	for _, cl in ipairs(b.clauses or {}) do
		local arg = Trim(cl.arg)
		if arg ~= "" then
			if kind == "sequence" then
				arg = arg:gsub("^reset=%S+%s*", "")
				arg = Trim((arg:match("^([^,]+)") or arg))
			elseif kind == "spells" or kind == "items" then
				arg = Trim((arg:match("^([^,]+)") or arg))
			elseif kind == "slotitem" then
				arg = Trim((arg:gsub("^%d+%s*", "")))
			end
			if arg ~= "" then return arg, kind end
		end
	end
	return nil
end

-- ---- A list argument: a sequence, or several to pick from at random ----
-- "reset=combat A, B" is a reset and a list of steps, not one string. These take it apart and put
-- it back, so the window can offer a box per step rather than one box holding commas.
function G.SplitSteps(arg)
	arg = Trim(arg or "")
	local reset = arg:match("^[Rr][Ee][Ss][Ee][Tt]=(%S+)")
	if reset then arg = Trim(arg:sub(#reset + 7)) end
	local steps = {}
	for piece in arg:gmatch("[^,]+") do
		piece = Trim(piece)
		if piece ~= "" then steps[#steps + 1] = piece end
	end
	return reset, steps
end

function G.JoinSteps(reset, steps)
	local body = concat(steps or {}, ", ")
	reset = Trim(reset or "")
	if reset ~= "" then
		return "reset=" .. reset .. (body ~= "" and (" " .. body) or "")
	end
	return body
end

-- The reset broken into what it asks for: seconds, combat, target, and anything else left as it is.
function G.SplitReset(reset)
	local out = { others = {} }
	for piece in tostring(reset or ""):gmatch("[^/]+") do
		piece = Trim(piece)
		local lower = strlower(piece)
		if tonumber(piece) then out.seconds = piece
		elseif lower == "combat" then out.combat = true
		elseif lower == "target" then out.target = true
		else out.others[#out.others + 1] = piece end
	end
	return out
end

function G.JoinReset(parts)
	local list = {}
	if parts.seconds and Trim(parts.seconds) ~= "" then list[#list + 1] = Trim(parts.seconds) end
	if parts.combat then list[#list + 1] = "combat" end
	if parts.target then list[#list + 1] = "target" end
	for _, other in ipairs(parts.others or {}) do list[#list + 1] = other end
	return concat(list, "/")
end

-- Strips "(Rank 3)" so a spell can be looked up by name. Only a rank: plenty of spells have
-- brackets of their own ("Faerie Fire (Feral)"), and taking those off would look up the wrong spell.
function G.StripRank(name)
	if not name then return nil end
	name = tostring(name)
	name = name:gsub("%s*%([Rr][Aa][Nn][Kk]%s*%d+%)", "")
	name = name:gsub("%s*%(%d+%)$", "")
	return Trim(name)
end
