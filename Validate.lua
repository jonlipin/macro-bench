-- Macro Bench checking. Three passes, none of which run the macro:
--
--   1. Lint     the grammar and the slots: unknown commands, conditions that do not exist, brackets
--               left open, clauses nothing can reach, two casts where only one can fire, spells you
--               do not have, and the 255 character wall.
--   2. Script   /run and /script bodies are handed to loadstring, which compiles them and reports a
--               real syntax error with a position, without executing a single line. The same pass
--               flags calls the game will refuse from a macro during combat, which is the usual
--               reason a script macro that "works" dies in a raid.
--   3. Resolve  SecureCmdOptionParse is the client's own condition parser; asking it what a line
--               resolves to right now shows which clause is winning, and changes as you hold shift.
--
-- Findings are { level = "error" | "warn" | "note", line = block index, clause = n, text = ... }.

local ADDON, ns = ...
local V = {}
ns.Validate = V

local G
local format, strlower, concat = string.format, string.lower, table.concat

local COLORS = { error = "|cffff5050", warn = "|cffffaa33", note = "|cff9dc8ff" }
local MARKS = { error = "|cffff5050!|r", warn = "|cffffaa33!|r", note = "|cff9dc8ffi|r" }
local RANK = { error = 1, warn = 2, note = 3 }

function V.LevelColor(level) return COLORS[level] or "|cffffffff" end
function V.LevelMark(level) return MARKS[level] or "" end

-- ------------------------------------------------------------------
-- "Did you mean" for a misspelt command or condition
-- ------------------------------------------------------------------
local function Distance(a, b)
	if a == b then return 0 end
	local la, lb = #a, #b
	if la == 0 then return lb end
	if lb == 0 then return la end
	if math.abs(la - lb) > 2 then return 99 end
	local prev, cur = {}, {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		cur[0] = i
		local ca = a:sub(i, i)
		for j = 1, lb do
			local cost = (ca == b:sub(j, j)) and 0 or 1
			local m = prev[j] + 1
			if cur[j - 1] + 1 < m then m = cur[j - 1] + 1 end
			if prev[j - 1] + cost < m then m = prev[j - 1] + cost end
			cur[j] = m
		end
		for j = 0, lb do prev[j] = cur[j] end
	end
	return prev[lb]
end

local function Closest(word, list)
	local best, bestD = nil, 3
	word = strlower(word or "")
	for _, candidate in ipairs(list) do
		local d = Distance(word, candidate)
		if d < bestD then best, bestD = candidate, d end
	end
	return best
end

local function DidYouMean(word, list)
	local guess = Closest(word, list)
	return guess and format(" Did you mean |cffffd100%s|r?", guess) or ""
end

-- ------------------------------------------------------------------
-- Scripts
-- ------------------------------------------------------------------
-- Functions the game will not let a macro call in combat (they need a real key press behind them,
-- and a script does not count as one). Harmless out of combat, silently dead in a fight.
local PROTECTED = {
	CastSpellByName = true, CastSpell = true, UseAction = true, UseItemByName = true,
	UseContainerItem = true, UseInventoryItem = true, TargetUnit = true, TargetNearestEnemy = true,
	TargetNearestFriend = true, TargetLastTarget = true, ClearTarget = true, AssistUnit = true,
	FocusUnit = true, PetAttack = true, StartAttack = true, AttackTarget = true, RunMacro = true,
	RunMacroText = true, PickupAction = true, PlaceAction = true, PickupSpell = true,
	CancelUnitBuff = true, CancelShapeshiftForm = true, JumpOrAscendStart = true,
	InteractUnit = true, FollowUnit = true, SpellStopCasting = true, SpellStopTargeting = true,
}

local function Compile(body)
	local fn = loadstring or load
	if not fn then return nil, nil end -- no compiler on this client; say nothing rather than guess
	local ok, chunk, err = pcall(fn, body, "macro")
	if not ok then return false, tostring(chunk) end
	if chunk then return true end
	-- loadstring gives the message as its second return; strip its own chunk name.
	err = tostring(err or "syntax error")
	err = err:gsub('^%[string "[^"]*"%]:', "line "):gsub("^macro:", "line ")
	return false, err
end

local function CheckScript(body, index, out)
	body = G.Trim(body or "")
	if body == "" then
		out[#out + 1] = { level = "warn", line = index, text = "This script line has nothing in it." }
		return
	end
	local ok, err = Compile(body)
	if ok == false then
		out[#out + 1] = { level = "error", line = index, text = "Lua will not compile this: " .. err }
	elseif ok == nil then
		out[#out + 1] = { level = "note", line = index, text = "This client will not let the addon compile scripts, so the Lua here is unchecked." }
	end
	for name in body:gmatch("([%a_][%w_]*)%s*%(") do
		if PROTECTED[name] then
			out[#out + 1] = { level = "warn", line = index, text = format(
				"%s() is protected: the game refuses it from a script while you are in combat. Use the macro command for it instead.", name) }
		end
	end
	if body:find("\n") then
		out[#out + 1] = { level = "warn", line = index, text = "A script has to be one line. Separate statements with a semicolon." }
	end
end

-- ------------------------------------------------------------------
-- Conditions
-- ------------------------------------------------------------------
local function CheckCond(cond, index, clauseIndex, out)
	if cond == "" then return end
	if cond:find("[%[%]]") then
		out[#out + 1] = { level = "error", line = index, clause = clauseIndex, text = "A bracket inside the conditions: " .. cond }
	end
	local terms = G.Terms(cond)
	if #terms == 0 then return end
	for _, t in ipairs(terms) do
		if t.unit then
			local known = G.KnownUnit(t.unit)
			if known == false then
				out[#out + 1] = { level = "error", line = index, clause = clauseIndex, text = format(
					"There is no unit called |cffffd100%s|r.%s", t.unit, DidYouMean(t.unit, G.UNITS)) }
			end
			-- Letters only, so it could be a player's name; but if it is one letter away from a real
			-- unit it is far more likely to be a slip than a character called Moueseover.
			if known == nil then
				local guess = Closest(t.unit, G.UNITS)
				if guess then
					out[#out + 1] = { level = "warn", line = index, clause = clauseIndex, text = format(
						"|cffffd100@%s|r is not a unit. Did you mean |cffffd100@%s|r? If it is somebody's name, this is fine.", t.unit, guess) }
				end
			end
		elseif not t.key then
			out[#out + 1] = { level = "error", line = index, clause = clauseIndex, text = format(
				"|cffffd100%s|r is not a condition.", G.Trim(t.raw)) }
		else
			local def = G.CondDef(t.key)
			if not def then
				out[#out + 1] = { level = "error", line = index, clause = clauseIndex, text = format(
					"There is no |cffffd100%s|r condition.%s", t.key, DidYouMean(t.key, G.CONDORDER)) }
			elseif def.only then
				out[#out + 1] = { level = "note", line = index, clause = clauseIndex, text = format(
					"|cffffd100%s|r came in with %s. On this client the clause it is in can never be true.", t.key, def.only) }
			else
				local value = t.value
				if not def.takes then
					if value and value ~= "" then
						out[#out + 1] = { level = "warn", line = index, clause = clauseIndex, text = format(
							"|cffffd100%s|r reads nothing after the colon, so \"%s\" is ignored.", t.key, value) }
					end
				elseif def.takes == "number" then
					if value and value ~= "" then
						for piece in value:gmatch("[^/]+") do
							if not tonumber(piece) then
								out[#out + 1] = { level = "error", line = index, clause = clauseIndex, text = format(
									"|cffffd100%s|r wants a number, not \"%s\".", t.key, piece) }
							end
						end
					end
				elseif def.takes == "mod" then
					if value and value ~= "" then
						for piece in value:gmatch("[^/]+") do
							local m = strlower(G.Trim(piece))
							local okMod = false
							for _, known in ipairs(G.MODS) do if m == known then okMod = true end end
							if not okMod then
								out[#out + 1] = { level = "error", line = index, clause = clauseIndex, text = format(
									"|cffffd100mod:%s|r is not a modifier. Use shift, ctrl, alt or none.", piece) }
							end
						end
					end
				end
			end
		end
	end
end

-- ------------------------------------------------------------------
-- Arguments
-- ------------------------------------------------------------------
local RESET_WORDS = { target = true, combat = true, alt = true, ctrl = true, shift = true, strict = true }

local function CheckSpellName(name, index, out, what)
	name = G.Trim(name or "")
	if name == "" then return end
	if tonumber(name) then
		out[#out + 1] = { level = "error", line = index, text = format(
			"A macro takes a spell's name, not its id (%s).", name) }
		return
	end
	local knows = ns.KnowsSpell(G.StripRank(name))
	if knows == false then
		out[#out + 1] = { level = "note", line = index, text = format(
			"|cffffd100%s|r is not in your spellbook. Fine if it is a pet spell, an item or another character's macro.", name) }
	end
end

local function CheckArg(b, index, out)
	local kind = G.BlockArgKind(b)
	local takesCond = G.BlockTakesCond(b)
	for j, cl in ipairs(b.clauses or {}) do
		local arg = G.Trim(cl.arg)
		if takesCond and arg:find("^%[") then
			out[#out + 1] = { level = "error", line = index, clause = j, text = "A condition bracket is not closed: " .. arg }
		elseif kind == "spell" then
			CheckSpellName(arg, index, out)
		elseif kind == "subject" then
			-- #showtooltip: a spell, an item, or a slot number, and empty is the usual case.
			if arg ~= "" and not tonumber(arg) and not ns.ItemInfo(arg) then CheckSpellName(arg, index, out) end
		elseif kind == "spells" then
			for piece in arg:gmatch("[^,]+") do CheckSpellName(piece, index, out) end
		elseif kind == "sequence" then
			local rest = arg
			local reset = rest:match("^[Rr][Ee][Ss][Ee][Tt]=(%S+)")
			if reset then
				rest = G.Trim(rest:sub(#reset + 7))
				for piece in reset:gmatch("[^/]+") do
					if not tonumber(piece) and not RESET_WORDS[strlower(piece)] then
						out[#out + 1] = { level = "error", line = index, clause = j, text = format(
							"|cffffd100reset=%s|r: it takes a number of seconds, target, combat, shift, ctrl or alt, joined with /.", piece) }
					end
				end
			elseif strlower(rest):find("reset") then
				out[#out + 1] = { level = "warn", line = index, clause = j, text = "A castsequence reset has to be the first thing after the command, as reset=combat." }
			end
			local count = 0
			for piece in rest:gmatch("[^,]+") do
				count = count + 1
				CheckSpellName(piece, index, out)
			end
			if count == 1 and rest ~= "" then
				out[#out + 1] = { level = "note", line = index, clause = j, text = "A sequence of one spell is just a cast; separate the steps with commas." }
			end
		elseif kind == "item" or kind == "items" then
			if arg ~= "" and not tonumber(arg) then
				for piece in arg:gmatch("[^,]+") do
					piece = G.Trim(piece)
					local bag, slot = piece:match("^(%d+)%s+(%d+)$")
					if not bag and not tonumber(piece) then
						local count = ns.ItemCount(piece)
						if count == 0 then
							out[#out + 1] = { level = "note", line = index, text = format(
								"You are not carrying |cffffd100%s|r right now.", piece) }
						end
					end
				end
			end
		elseif kind == "slotitem" then
			if arg ~= "" and not arg:match("^%d+") then
				out[#out + 1] = { level = "error", line = index, clause = j, text = "/equipslot needs the slot number first, as \"16 Thunderfury\"." }
			end
		elseif kind == "number" then
			if arg ~= "" and not tonumber((arg:match("^(%S+)"))) then
				out[#out + 1] = { level = "error", line = index, clause = j, text = format("/%s wants a number.", b.cmd or "?") }
			end
		elseif kind == "unit" then
			if arg ~= "" then
				local known = G.KnownUnit(arg)
				if known == false then
					out[#out + 1] = { level = "warn", line = index, clause = j, text = format(
						"|cffffd100%s|r is not a unit or a name.%s", arg, DidYouMean(arg, G.UNITS)) }
				end
			end
		elseif kind == "none" then
			if arg ~= "" then
				out[#out + 1] = { level = "note", line = index, clause = j, text = format(
					"/%s reads nothing after it, so \"%s\" does nothing.", b.cmd or "?", arg) }
			end
		end
	end
end

-- ------------------------------------------------------------------
-- The whole macro
-- ------------------------------------------------------------------
function V.Check(blocks)
	G = ns.Grammar
	local out = {}
	blocks = blocks or {}
	local text = G.Compile(blocks)
	local length = #text

	local actionable, tooltips, firstAction = 0, 0, nil
	local gcdLines = {}

	for i, b in ipairs(blocks) do
		if b.kind == "cmd" or b.kind == "script" then
			actionable = actionable + 1
			firstAction = firstAction or i
		end
		if b.kind == "tooltip" then
			tooltips = tooltips + 1
			if firstAction then
				out[#out + 1] = { level = "warn", line = i, text = "The game only reads #showtooltip as the first line of a macro; here it does nothing." }
			end
			if tooltips == 2 then
				out[#out + 1] = { level = "warn", line = i, text = "A macro has one tooltip. Only the first #showtooltip counts." }
			end
			CheckArg(b, i, out)
			for j, cl in ipairs(b.clauses or {}) do
				for _, cond in ipairs(cl.conds or {}) do CheckCond(cond, i, j, out) end
			end
		elseif b.kind == "comment" then
			if length > 200 then
				out[#out + 1] = { level = "note", line = i, text = "The game ignores this line, but its characters still count towards the 255." }
			end
		elseif b.kind == "script" then
			CheckScript(b.body, i, out)
		elseif b.kind == "cmd" then
			local def = G.Def(b.cmd)
			if not G.KnownCommand(b.cmd) then
				local names = {}
				for _, name in ipairs(G.ORDER) do names[#names + 1] = name end
				out[#out + 1] = { level = "error", line = i, text = format(
					"There is no |cffffd100/%s|r command.%s", b.cmd or "?", DidYouMean(b.cmd, names)) }
			elseif not def then
				out[#out + 1] = { level = "note", line = i, text = format(
					"|cffffd100/%s|r is a chat or addon command, so Macro Bench cannot check what comes after it.", b.cmd) }
			end
			-- Conditions in front of something that does not read them. These were never parsed as
			-- conditions, so they are still sitting at the front of the argument.
			if def and not def.cond then
				for j, cl in ipairs(b.clauses or {}) do
					if G.Trim(cl.arg or ""):match("^%[") then
						out[#out + 1] = { level = "warn", line = i, clause = j, text = format(
							"/%s does not read conditions: the brackets go out as part of the text.", b.cmd) }
						break
					end
				end
			end
			if def and def.cond then
				local openEnded = nil
				for j, cl in ipairs(b.clauses or {}) do
					for _, cond in ipairs(cl.conds or {}) do CheckCond(cond, i, j, out) end
					if openEnded then
						out[#out + 1] = { level = "warn", line = i, clause = j, text = format(
							"This can never run: the clause above it (%d) has no conditions, so that one always wins.", openEnded) }
						break
					end
					local unconditional = #(cl.conds or {}) == 0
					for _, cond in ipairs(cl.conds or {}) do
						if G.Trim(cond) == "" then unconditional = true end
					end
					if unconditional and G.Trim(cl.arg) ~= "" then openEnded = j end
				end
			end
			CheckArg(b, i, out)
			if def and def.gcd == "spell" then
				for _, cl in ipairs(b.clauses or {}) do
					if #(cl.conds or {}) == 0 and G.Trim(cl.arg) ~= "" then
						gcdLines[#gcdLines + 1] = i
						break
					end
				end
			end
		end
	end

	if #gcdLines > 1 then
		local words = {}
		for _, i in ipairs(gcdLines) do words[#words + 1] = "line " .. i end
		out[#out + 1] = { level = "warn", line = gcdLines[2], text = format(
			"%s all cast with nothing to tell them apart. One press casts the first one only; give them conditions, or put them in one /castsequence.",
			concat(words, ", ")) }
	end

	if length > ns.MACRO_LIMIT then
		table.insert(out, 1, { level = "error", text = format(
			"%d characters. The game keeps 255, so %d would be cut off.", length, length - ns.MACRO_LIMIT) })
	elseif length > ns.MACRO_LIMIT - 20 and length > 0 then
		table.insert(out, 1, { level = "note", text = format("%d characters, %d left.", length, ns.MACRO_LIMIT - length) })
	end

	if actionable == 0 and #blocks > 0 then
		out[#out + 1] = { level = "note", text = "Nothing here does anything yet." }
	end

	table.sort(out, function(a, b)
		local ra, rb = RANK[a.level] or 9, RANK[b.level] or 9
		if ra ~= rb then return ra < rb end
		return (a.line or 0) < (b.line or 0)
	end)
	return out, length
end

function V.Worst(findings)
	local worst
	for _, f in ipairs(findings or {}) do
		if not worst or (RANK[f.level] or 9) < (RANK[worst] or 9) then worst = f.level end
	end
	return worst
end

-- The findings that belong to one line, for the mark on its row.
function V.ForLine(findings, index)
	local list = {}
	for _, f in ipairs(findings or {}) do
		if f.line == index then list[#list + 1] = f end
	end
	return list
end

-- ------------------------------------------------------------------
-- Resolve: what the client's own parser makes of a line right now
-- ------------------------------------------------------------------
function V.Resolve(block)
	G = ns.Grammar
	if type(SecureCmdOptionParse) ~= "function" then return nil end
	if not block or not G.BlockTakesCond(block) then return nil end
	local hasCond = false
	for _, cl in ipairs(block.clauses or {}) do
		if #(cl.conds or {}) > 0 then hasCond = true break end
	end
	if not hasCond then return nil end
	local text = G.CompileBlock(block)
	local body = text:match("^/%S+%s*(.*)$") or text:match("^#showtooltip%s*(.*)$")
	if not body or body == "" then return nil end
	local ok, action, target = pcall(SecureCmdOptionParse, body)
	if not ok then return nil end
	action = ns.Clean(action)
	target = ns.Clean(target)
	if action == nil or action == "" then return false end -- nothing would happen right now
	return action, target
end

-- ------------------------------------------------------------------
-- Every macro you own
-- ------------------------------------------------------------------
function V.ScanAll()
	G = ns.Grammar
	local list = ns.MacroList()
	local bad = 0
	ns.Print(format("Looking at %d macro%s.", #list, #list == 1 and "" or "s"))
	for _, m in ipairs(list) do
		local findings = V.Check(G.Parse(m.body))
		local worst = V.Worst(findings)
		if worst == "error" or worst == "warn" then
			bad = bad + 1
			ns.Print(format("|cffffd100%s|r (slot %d)%s", m.name, m.index, m.perChar and ", this character" or ""))
			for _, f in ipairs(findings) do
				if f.level ~= "note" then
					ns.Print("    " .. V.LevelColor(f.level) .. (f.line and ("line " .. f.line .. ": ") or "") .. f.text .. "|r")
				end
			end
		end
	end
	if bad == 0 then
		ns.Print("Nothing wrong with any of them.")
	else
		ns.Print(format("%d macro%s worth a look. Load one with |cffffd100/macrobench load <name>|r.", bad, bad == 1 and "" or "s"))
	end
end
