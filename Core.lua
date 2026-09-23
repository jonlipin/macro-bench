-- Macro Bench core: saved data, the draft library, the game's own macro slots, slash commands.
--
-- Two places hold macros. The game has a fixed number of macro slots (shared by the account, plus a
-- few per character) and each slot holds at most 255 characters. Macro Bench keeps its own library in
-- the saved variables, which has no limit at all: build and keep as many as you like, and put the
-- ones you are actually using into real slots. Writing a slot is not allowed during combat, so those
-- writes are queued and go in the moment the fight ends.
--
-- This client can hide values from addons ("secret values"): a read comes back secret rather than
-- wrong. Every lookup here goes through pcall and Clean(), so a spell that cannot be read is
-- reported as "cannot tell" rather than as "you do not know it".

local ADDON, ns = ...
ns.VERSION = "1.7.0"
ns.report = {}
ns.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
ns.MACRO_LIMIT = 255

local max, min, floor = math.max, math.min, math.floor
local strlower, format = string.lower, string.format

-- ------------------------------------------------------------------
-- Printing, and a log kept in the saved variables
-- ------------------------------------------------------------------
local LOG_CAP = 2000
local pendingLog = {}
local function LogLine(text)
	local line = (date and date("%H:%M:%S") or "") .. " " .. tostring(text)
	if ns.db then
		ns.db.log = ns.db.log or {}
		local list = ns.db.log
		for _, l in ipairs(pendingLog) do list[#list + 1] = l end
		for i = #pendingLog, 1, -1 do pendingLog[i] = nil end
		list[#list + 1] = line
		if #list > LOG_CAP + 200 then
			local keep = {}
			for i = #list - LOG_CAP + 1, #list do keep[#keep + 1] = list[i] end
			ns.db.log = keep
		end
	else
		pendingLog[#pendingLog + 1] = line
	end
end
ns.LogLine = LogLine

local function Print(msg)
	if issecretvalue and issecretvalue(msg) then msg = "(secret value)" end
	msg = tostring(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffMacro Bench:|r " .. msg)
	LogLine((msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end
ns.Print = Print

local function Clean(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
ns.Clean = Clean

function ns.YesNo(v) return v and "|cff40ff40yes|r" or "|cffff5050no|r" end

-- ------------------------------------------------------------------
-- Spells and items
-- ------------------------------------------------------------------
-- name, icon, id for a spell id or name. Nil when the client will not say, which on this client can
-- mean "you do not have it" or "not while you are in combat".
function ns.SpellInfo(idOrName)
	if not idOrName or idOrName == "" then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, idOrName)
		if ok and type(info) == "table" and Clean(info.name) then
			return Clean(info.name), Clean(info.iconID) or Clean(info.originalIconID), Clean(info.spellID)
		end
	end
	if GetSpellInfo then
		local ok, name, _, icon, _, _, _, id = pcall(GetSpellInfo, idOrName)
		if ok and Clean(name) then return Clean(name), Clean(icon), Clean(id) end
	end
	return nil
end

-- true when the spell is in your spellbook, false when it is not, nil when the client will not say.
function ns.KnowsSpell(name)
	if not name or name == "" then return nil end
	local resolved = ns.SpellInfo(name)
	if resolved then return true end
	if tonumber(name) and IsSpellKnown then
		local ok, known = pcall(IsSpellKnown, tonumber(name))
		if ok then return Clean(known) == true end
	end
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then return nil end
	return false
end

function ns.ItemInfo(idOrName)
	if not idOrName or idOrName == "" then return nil end
	if C_Item and C_Item.GetItemInfoInstant then
		local ok, id, _, _, icon = pcall(C_Item.GetItemInfoInstant, idOrName)
		if ok and Clean(id) then return Clean(id), Clean(icon) end
	end
	if GetItemInfoInstant then
		local ok, id, _, _, icon = pcall(GetItemInfoInstant, idOrName)
		if ok and Clean(id) then return Clean(id), Clean(icon) end
	end
	return nil
end

-- How many you are carrying; nil when the client will not say.
function ns.ItemCount(nameOrId)
	local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not fn then return nil end
	local ok, n = pcall(fn, nameOrId)
	if ok then return Clean(n) end
	return nil
end

-- The icon a block should wear.
function ns.IconFor(subject, kind)
	if not subject then return nil end
	-- A bare number is an inventory slot, which is how a macro names a trinket or a weapon.
	local slot = tonumber(subject)
	if slot and GetInventoryItemTexture then
		local ok, tex = pcall(GetInventoryItemTexture, "player", slot)
		if ok and Clean(tex) then return Clean(tex) end
	end
	if kind == "item" or kind == "items" or kind == "slotitem" then
		local _, icon = ns.ItemInfo(subject)
		if icon then return icon end
		local n = tonumber(subject)
		if n and GetInventoryItemTexture then
			local ok, tex = pcall(GetInventoryItemTexture, "player", n)
			if ok and Clean(tex) then return Clean(tex) end
		end
		return nil
	end
	local _, icon = ns.SpellInfo(ns.Grammar.StripRank(subject))
	if icon then return icon end
	local _, itemIcon = ns.ItemInfo(subject)
	return itemIcon
end

-- ------------------------------------------------------------------
-- What you have, for finishing a name as it is typed
-- ------------------------------------------------------------------
-- Every spell in your spellbook and every item in your bags, read once and kept until the game says
-- one of them changed. Passives are left out: a macro cannot cast them.
local spellCache, itemCache

function ns.ForgetLists(which)
	if which ~= "items" then spellCache = nil end
	if which ~= "spells" then itemCache = nil end
end

function ns.SpellBookList()
	if spellCache then return spellCache end
	local out, seen = {}, {}
	local function Add(name, icon, passive)
		name = Clean(name)
		if passive or not name or name == "" or seen[strlower(name)] then return end
		seen[strlower(name)] = true
		out[#out + 1] = { name = name, icon = Clean(icon), what = "spell" }
	end
	if C_SpellBook and C_SpellBook.GetNumSpellBookItems and Enum and Enum.SpellBookSpellBank then
		for _, bank in ipairs({ Enum.SpellBookSpellBank.Player, Enum.SpellBookSpellBank.Pet }) do
			local ok, num = pcall(C_SpellBook.GetNumSpellBookItems, bank)
			num = ok and Clean(num) or 0
			for i = 1, num do
				local okInfo, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
				if okInfo and type(info) == "table" then
					Add(info.name, info.iconID, info.isPassive)
				end
			end
		end
	end
	if #out == 0 and GetNumSpellTabs and GetSpellBookItemName then
		local total = 0
		for tab = 1, (GetNumSpellTabs() or 0) do
			local ok, _, _, offset, numSpells = pcall(GetSpellTabInfo, tab)
			if ok and offset and numSpells then total = max(total, offset + numSpells) end
		end
		for i = 1, total do
			local ok, name = pcall(GetSpellBookItemName, i, BOOKTYPE_SPELL or "spell")
			local icon
			if GetSpellBookItemTexture then
				local okTex, tex = pcall(GetSpellBookItemTexture, i, BOOKTYPE_SPELL or "spell")
				icon = okTex and Clean(tex) or nil
			end
			if ok then Add(name, icon) end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	spellCache = out
	return out
end

function ns.BagItemList()
	if itemCache then return itemCache end
	local out, seen = {}, {}
	local function Add(name, icon)
		name = Clean(name)
		if not name or name == "" or seen[strlower(name)] then return end
		seen[strlower(name)] = true
		out[#out + 1] = { name = name, icon = Clean(icon), what = "item" }
	end
	local container = C_Container
	local numBags = (NUM_BAG_SLOTS or 4)
	for bag = 0, numBags do
		local slots = 0
		if container and container.GetContainerNumSlots then
			local ok, n = pcall(container.GetContainerNumSlots, bag)
			slots = ok and Clean(n) or 0
		elseif GetContainerNumSlots then
			local ok, n = pcall(GetContainerNumSlots, bag)
			slots = ok and Clean(n) or 0
		end
		for slot = 1, slots do
			local link, icon
			if container and container.GetContainerItemInfo then
				local ok, info = pcall(container.GetContainerItemInfo, bag, slot)
				if ok and type(info) == "table" then
					link, icon = Clean(info.hyperlink), Clean(info.iconFileID)
				end
			elseif GetContainerItemInfo then
				local ok, tex, _, _, _, _, _, itemLink = pcall(GetContainerItemInfo, bag, slot)
				if ok then link, icon = Clean(itemLink), Clean(tex) end
			end
			if link then Add(link:match("%[(.-)%]"), icon) end
		end
	end
	-- What you are wearing, so "Trinket" completes even when it is not in a bag.
	for slot = 1, 19 do
		local link
		if GetInventoryItemLink then
			local ok, l = pcall(GetInventoryItemLink, "player", slot)
			link = ok and Clean(l) or nil
		end
		if link then
			local icon
			if GetInventoryItemTexture then
				local okTex, tex = pcall(GetInventoryItemTexture, "player", slot)
				icon = okTex and Clean(tex) or nil
			end
			Add(link:match("%[(.-)%]"), icon)
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	itemCache = out
	return out
end

-- What could finish what has been typed. Names that start with it come first, then names that
-- merely contain it, which is how you find "Greater Healing Wave" by typing "heal".
function ns.Suggest(text, kind, limit)
	text = strlower(ns.Grammar.Trim(text or ""))
	if text == "" or #text < 2 then return {} end
	limit = limit or 6
	local lists = {}
	if kind == "item" or kind == "items" or kind == "slotitem" then
		lists[1], lists[2] = ns.BagItemList(), ns.SpellBookList()
	elseif kind == "subject" then
		lists[1], lists[2] = ns.SpellBookList(), ns.BagItemList()
	else
		lists[1] = ns.SpellBookList()
	end
	local starts, holds = {}, {}
	for _, list in ipairs(lists) do
		for _, entry in ipairs(list) do
			local name = strlower(entry.name)
			if name == text then
				-- Already exactly what they have: nothing to finish.
			elseif name:sub(1, #text) == text then
				starts[#starts + 1] = entry
			elseif name:find(text, 1, true) then
				holds[#holds + 1] = entry
			end
		end
	end
	local out = {}
	for _, entry in ipairs(starts) do
		if #out >= limit then return out end
		out[#out + 1] = entry
	end
	for _, entry in ipairs(holds) do
		if #out >= limit then return out end
		out[#out + 1] = entry
	end
	return out
end

-- ------------------------------------------------------------------
-- Saved data
-- ------------------------------------------------------------------
local function CharKey()
	local name = UnitName and UnitName("player") or "?"
	local realm = GetRealmName and GetRealmName() or "?"
	return (name or "?") .. " - " .. (realm or "?")
end
ns.CharKey = CharKey

local DEFAULTS = {
	minimap = true,
	minimapAngle = 200,
	plainBook = false,
	confirmOverwrite = true,
}

function ns.InitDB()
	MacroBenchDB = MacroBenchDB or {}
	local db = MacroBenchDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end
	db.drafts = db.drafts or {}
	db.log = db.log or {}
	ns.db = db
	-- What is on the bench right now, kept per character. The blocks themselves are never saved:
	-- they are read back out of the text at login, which is the same rule the whole addon runs on.
	db.bench = db.bench or {}
	local saved = db.bench[CharKey()] or {}
	ns.bench = {
		name = saved.name or "",
		icon = saved.icon or ns.QUESTION,
		perChar = saved.perChar or false,
		text = saved.text or "",
		draft = saved.draft,
	}
	ns.bench.blocks = ns.Grammar.Parse(ns.bench.text)
	return db
end

function ns.SaveBench()
	if not ns.db or not ns.bench then return end
	ns.db.bench = ns.db.bench or {}
	ns.db.bench[CharKey()] = {
		name = ns.bench.name, icon = ns.bench.icon, perChar = ns.bench.perChar,
		text = ns.bench.text, draft = ns.bench.draft,
	}
end

function ns.NewUid()
	ns.db.uid = (ns.db.uid or 0) + 1
	return ns.db.uid
end

-- ---- The bench: the macro being built ------------------------------
-- Text and blocks are kept in step by whichever side changed; these are the two doors.
function ns.SetBenchBlocks(blocks)
	ns.bench.blocks = blocks or {}
	ns.bench.text = ns.Grammar.Compile(ns.bench.blocks)
end

function ns.SetBenchText(text)
	ns.bench.text = text or ""
	ns.bench.blocks = ns.Grammar.Parse(ns.bench.text)
end

function ns.BenchLength()
	return #(ns.bench.text or "")
end

function ns.ClearBench()
	ns.bench.name = ""
	ns.bench.icon = ns.QUESTION
	ns.bench.perChar = false
	ns.bench.slot = nil
	ns.bench.draft = nil
	ns.SetBenchBlocks({})
end

-- The icon the macro should use: whatever was chosen, or the first spell or item named in it.
function ns.BenchIcon()
	if ns.bench.plainIcon then return ns.QUESTION end
	if ns.bench.icon and ns.bench.icon ~= ns.QUESTION then return ns.bench.icon end
	for _, b in ipairs(ns.bench.blocks or {}) do
		local subject, kind = ns.Grammar.BlockSubject(b)
		if subject then
			local icon = ns.IconFor(subject, kind)
			if icon then return icon end
		end
	end
	return ns.QUESTION
end

-- ---- The library ---------------------------------------------------
function ns.Drafts() return ns.db.drafts end

function ns.SaveDraft()
	local text = ns.bench.text or ""
	local name = ns.Grammar.Trim(ns.bench.name or "")
	if name == "" then name = "Untitled" end
	local draft = ns.bench.draft and ns.FindDraft(ns.bench.draft)
	if not draft then
		draft = { uid = ns.NewUid() }
		ns.db.drafts[#ns.db.drafts + 1] = draft
	end
	draft.name = name
	draft.text = text
	draft.icon = ns.bench.icon
	draft.perChar = ns.bench.perChar
	draft.class = select(2, UnitClass("player"))
	draft.stamp = time and time() or 0
	ns.bench.draft = draft.uid
	ns.bench.name = name
	return draft
end

function ns.FindDraft(uid)
	for _, d in ipairs(ns.db.drafts) do
		if d.uid == uid then return d end
	end
end

function ns.DeleteDraft(uid)
	for i, d in ipairs(ns.db.drafts) do
		if d.uid == uid then
			table.remove(ns.db.drafts, i)
			if ns.bench.draft == uid then ns.bench.draft = nil end
			return true
		end
	end
end

function ns.LoadDraft(d)
	if not d then return end
	ns.bench.name = d.name or ""
	ns.bench.icon = d.icon or ns.QUESTION
	ns.bench.perChar = d.perChar or false
	ns.bench.draft = d.uid
	ns.bench.slot = nil
	ns.SetBenchText(d.text or "")
end

-- ------------------------------------------------------------------
-- The game's macro slots
-- ------------------------------------------------------------------
function ns.MacroCaps()
	local account = MAX_ACCOUNT_MACROS or 120
	local char = MAX_CHARACTER_MACROS or 18
	return account, char
end

-- Every macro that exists, account ones then per-character ones.
function ns.MacroList()
	local out = {}
	local account, char = ns.MacroCaps()
	local numAccount, numChar = 0, 0
	if GetNumMacros then
		local ok, a, c = pcall(GetNumMacros)
		if ok then numAccount, numChar = Clean(a) or 0, Clean(c) or 0 end
	end
	local function Read(index, perChar)
		local ok, name, icon, body = pcall(GetMacroInfo, index)
		if ok and Clean(name) then
			out[#out + 1] = { index = index, name = Clean(name), icon = Clean(icon), body = Clean(body) or "", perChar = perChar }
		end
	end
	for i = 1, numAccount do Read(i, false) end
	for i = 1, numChar do Read(account + i, true) end
	ns.macroCounts = { account = numAccount, char = numChar, accountCap = account, charCap = char }
	return out
end

-- What is in one slot right now, for showing somebody what they are about to replace.
function ns.MacroAt(index)
	if not index then return nil end
	local ok, name, icon, body = pcall(GetMacroInfo, index)
	if ok and Clean(name) then
		return { index = index, name = Clean(name), icon = Clean(icon), body = Clean(body) or "" }
	end
	return nil
end

function ns.FindMacroSlot(name)
	if not name or name == "" then return nil end
	for _, m in ipairs(ns.MacroList()) do
		if strlower(m.name) == strlower(name) then return m.index, m end
	end
end

-- CreateMacro wants an icon it can resolve: a file id, or a texture name without the path.
local function IconArg(icon)
	if type(icon) == "number" then return icon end
	icon = tostring(icon or ns.QUESTION)
	local short = icon:match("([^\\/]+)$")
	return short or "INV_Misc_QuestionMark"
end

local queue = {}

-- Writes the bench into a real macro slot. Returns true when it went in, false plus why when it
-- cannot, or "queued" when it is waiting for combat to end.
function ns.WriteMacro(opts)
	opts = opts or {}
	local name = ns.Grammar.Trim(opts.name or ns.bench.name or "")
	local body = opts.body or ns.bench.text or ""
	local icon = opts.icon or ns.BenchIcon()
	local perChar = opts.perChar
	if perChar == nil then perChar = ns.bench.perChar end
	if name == "" then return false, "The macro needs a name." end
	if body == "" then return false, "There is nothing to save yet." end
	if #body > ns.MACRO_LIMIT then
		return false, format("The macro is %d characters; the game allows %d.", #body, ns.MACRO_LIMIT)
	end
	if InCombatLockdown and InCombatLockdown() then
		queue[#queue + 1] = { name = name, body = body, icon = icon, perChar = perChar, replace = opts.replace }
		return "queued"
	end
	local index = opts.replace or ns.FindMacroSlot(name)
	if index then
		local ok, err = pcall(EditMacro, index, name, IconArg(icon), body)
		if not ok then return false, tostring(err) end
		ns.bench.slot = index
		LogLine("edited macro " .. index .. " " .. name)
		return true, index
	end
	local accountUsed, charUsed = 0, 0
	if GetNumMacros then
		local ok, a, c = pcall(GetNumMacros)
		if ok then accountUsed, charUsed = Clean(a) or 0, Clean(c) or 0 end
	end
	local accountCap, charCap = ns.MacroCaps()
	if perChar and charUsed >= charCap then
		return false, format("All %d of this character's macro slots are full.", charCap)
	end
	if not perChar and accountUsed >= accountCap then
		return false, format("All %d account macro slots are full. Try a per-character one.", accountCap)
	end
	local ok, newIndex = pcall(CreateMacro, name, IconArg(icon), body, perChar and 1 or nil)
	if not ok then return false, tostring(newIndex) end
	if not newIndex then return false, "The game would not make the macro." end
	ns.bench.slot = newIndex
	LogLine("created macro " .. tostring(newIndex) .. " " .. name)
	return true, newIndex
end

local function FlushQueue()
	if #queue == 0 then return end
	local pending = queue
	queue = {}
	for _, item in ipairs(pending) do
		local ok, err = ns.WriteMacro(item)
		if ok == true then
			Print(format("Saved |cffffd100%s|r now that the fight is over.", item.name))
		elseif ok == false then
			Print(format("Could not save |cffffd100%s|r: %s", item.name, tostring(err)))
		end
	end
end

function ns.QueuedWrites() return #queue end

-- Puts the macro on the cursor so it can be dropped onto an action bar. The drop itself has to be
-- the player's own click: no addon may place something on a bar for you.
function ns.PickupBench()
	local index = ns.bench.slot or ns.FindMacroSlot(ns.bench.name)
	if not index then return false, "Save it to a macro slot first." end
	local ok = pcall(PickupMacro, index)
	if not ok then return false, "The game would not pick it up." end
	return true
end

-- ------------------------------------------------------------------
-- Opening the windows you drag things out of
-- ------------------------------------------------------------------
-- On this client the spellbook is an addon of its own, and loading a Blizzard addon from addon code
-- taints it: the game may then refuse protected things done from that window, such as dragging a
-- spell onto an action bar. Dragging a spell onto this addon is not protected, so for what the
-- button is for the taint costs nothing, and a /reload clears it. So it loads it when asked
-- (allowLoad) and says so once. Returns whether it opened, why not, and whether it had to load it.
function ns.OpenSpellBook(allowLoad)
	local function Hide(f)
		if HideUIPanel then return pcall(HideUIPanel, f) end
		return pcall(f.Hide, f)
	end
	if PlayerSpellsFrame and PlayerSpellsFrame.IsShown and PlayerSpellsFrame:IsShown() then
		Hide(PlayerSpellsFrame)
		return true
	end
	if SpellBookFrame and SpellBookFrame.IsShown and SpellBookFrame:IsShown() then
		Hide(SpellBookFrame)
		return true
	end
	if PlayerSpellsFrame then
		if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
			local ok = pcall(PlayerSpellsUtil.ToggleSpellBookFrame)
			if ok then
				ns.report["spellbook"] = "PlayerSpellsUtil"
				return true
			end
		end
		if ShowUIPanel and pcall(ShowUIPanel, PlayerSpellsFrame) then
			ns.report["spellbook"] = "ShowUIPanel"
			return true
		end
	end
	if SpellBookFrame then
		if ToggleSpellBook and pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell") then
			ns.report["spellbook"] = "ToggleSpellBook"
			return true
		end
		if ShowUIPanel and pcall(ShowUIPanel, SpellBookFrame) then
			ns.report["spellbook"] = "ShowUIPanel (classic)"
			return true
		end
	end
	ns.report["spellbook"] = "not loaded"
	if allowLoad then
		local ok, why = ns.LoadSpellBook()
		if ok then return true, nil, true end
		return false, why
	end
	return false, "The spellbook has not been loaded yet. |cffffd100P|r opens it."
end

-- Loading it anyway, when the player has been told what it costs and asked twice.
function ns.LoadSpellBook()
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if not load then return false, "This client will not let one addon load another." end
	for _, name in ipairs({ "Blizzard_PlayerSpells", "Blizzard_Spellbook" }) do
		local ok, loaded = pcall(load, name)
		if ok and loaded ~= false then
			local opened, why = ns.OpenSpellBook()
			if opened then
				LogLine("loaded " .. name .. " on request")
				return true
			end
			return false, why
		end
	end
	return false, "The spellbook addon would not load. |cffffd100P|r still opens it."
end

function ns.OpenBags()
	local fn = OpenAllBags or ToggleAllBags
	if fn and pcall(fn) then return true end
	return false, "This client will not let an addon open your bags. |cffffd100B|r opens them."
end

-- ------------------------------------------------------------------
-- The cursor: dragging a spell, item or macro out of the game's own frames
-- ------------------------------------------------------------------
-- Gives back a block for whatever is on the cursor, and clears it. GetCursorInfo has had several
-- shapes over the years, so every return is looked at rather than assumed.
function ns.BlockFromCursor()
	if not GetCursorInfo then return nil end
	local ok, kind, a, b, c = pcall(GetCursorInfo)
	if not ok or not kind then return nil end
	kind = Clean(kind)
	local block, note
	if kind == "spell" then
		-- ("spell", index, bank, spellID) on this client; older ones leave the id out.
		local id = Clean(c) or Clean(b)
		local name = ns.SpellInfo(tonumber(id) or id)
		if not name and C_SpellBook and C_SpellBook.GetSpellBookItemName then
			local okn, n = pcall(C_SpellBook.GetSpellBookItemName, Clean(a), Clean(b) or 0)
			name = Clean(n)
		end
		if name then
			block = ns.Grammar.NewBlock("cast", name)
			note = name
		end
	elseif kind == "item" then
		local link = Clean(b)
		local name = link and link:match("%[(.-)%]")
		name = name or select(1, ns.ItemInfo(Clean(a)))
		if type(name) == "number" then name = nil end
		if not name and Clean(a) then
			local okn, itemName = pcall(function() return (C_Item and C_Item.GetItemInfo or GetItemInfo)(Clean(a)) end)
			if okn then name = Clean(itemName) end
		end
		if name then
			block = ns.Grammar.NewBlock("use", name)
			note = name
		end
	elseif kind == "macro" then
		local index = tonumber(Clean(a))
		if index then
			local okm, mname, _, mbody = pcall(GetMacroInfo, index)
			if okm and Clean(mbody) then
				block = { kind = "macro_text", text = Clean(mbody), name = Clean(mname) }
				note = Clean(mname)
			end
		end
	elseif kind == "mount" or kind == "battlepet" or kind == "toy" then
		local name
		if kind == "mount" and C_MountJournal then
			local okm, n = pcall(C_MountJournal.GetMountInfoByID, Clean(a))
			name = Clean(n)
		elseif kind == "toy" and C_ToyBox then
			local okt, _, n = pcall(C_ToyBox.GetToyInfo, Clean(a))
			name = Clean(n)
		end
		if name then
			block = ns.Grammar.NewBlock(kind == "toy" and "use" or "cast", name)
			note = name
		end
	end
	if block then
		if ClearCursor then pcall(ClearCursor) end
		return block, note
	end
	return nil
end

-- ------------------------------------------------------------------
-- Events
-- ------------------------------------------------------------------
local events = CreateFrame("Frame")
-- An event this client has never heard of is an error, not a quiet no, and the names for the same
-- thing move about between clients: a spell learned is LEARNED_SPELL_IN_SKILL_LINE here and
-- LEARNED_SPELL_IN_TAB elsewhere. So each one is asked for on its own and what took is reported.
local function Register(event)
	local ok = pcall(events.RegisterEvent, events, event)
	ns.report["event " .. event] = ok and "ok" or "not on this client"
	return ok
end
Register("ADDON_LOADED")
Register("PLAYER_LOGIN")
Register("PLAYER_REGEN_ENABLED")
Register("UPDATE_MACROS")
Register("PLAYER_LOGOUT")
Register("SPELLS_CHANGED")
Register("LEARNED_SPELL_IN_SKILL_LINE")
Register("LEARNED_SPELL_IN_TAB")
Register("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		ns.InitDB()
	elseif event == "PLAYER_LOGIN" then
		if not ns.db then ns.InitDB() end
		ns.Grammar.ForgetClientCommands()
		ns.UI:Init()
	elseif event == "PLAYER_REGEN_ENABLED" then
		FlushQueue()
	elseif event == "PLAYER_LOGOUT" then
		ns.SaveBench()
	elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" then
		ns.ForgetLists("spells")
	elseif event == "BAG_UPDATE_DELAYED" then
		ns.ForgetLists("items")
	elseif event == "UPDATE_MACROS" then
		if ns.UI and ns.UI.MacrosChanged then ns.UI:MacrosChanged() end
	end
end)

-- ------------------------------------------------------------------
-- Slash commands
-- ------------------------------------------------------------------
local function Usage()
	Print("commands:")
	Print("  |cffffd100/macrobench|r open or close the bench")
	Print("  |cffffd100/macrobench check|r check what is on the bench and print the findings")
	Print("  |cffffd100/macrobench load <name>|r put one of your game macros on the bench")
	Print("  |cffffd100/macrobench tutorial|r a macro built a step at a time, with your own spells")
	Print("  |cffffd100/macrobench scan|r check every macro you have and list the broken ones")
	Print("  |cffffd100/macrobench confirm|r ask, or stop asking, before a macro slot is replaced")
	Print("  |cffffd100/macrobench minimap|r show or hide the minimap button")
	Print("  |cffffd100/macrobench debug|r what this client allowed")
end

local function Command(input)
	input = ns.Grammar.Trim(input or "")
	local cmd, rest = input:match("^(%S*)%s*(.*)$")
	cmd = strlower(cmd or "")
	if cmd == "" then
		ns.UI:Toggle()
	elseif cmd == "check" then
		local findings = ns.Validate.Check(ns.bench.blocks)
		if #findings == 0 then
			Print("Nothing wrong with it. " .. ns.BenchLength() .. " of " .. ns.MACRO_LIMIT .. " characters.")
		else
			Print(#findings .. " thing" .. (#findings == 1 and "" or "s") .. " to look at:")
			for _, f in ipairs(findings) do
				Print("  " .. ns.Validate.LevelColor(f.level) .. (f.line and ("line " .. f.line .. ": ") or "") .. f.text .. "|r")
			end
		end
	elseif cmd == "load" then
		local index, m = ns.FindMacroSlot(rest)
		if not index then Print("No macro called \"" .. rest .. "\".") return end
		ns.bench.name, ns.bench.icon, ns.bench.perChar, ns.bench.slot = m.name, m.icon, m.perChar, m.index
		ns.bench.draft = nil
		ns.SetBenchText(m.body)
		ns.UI:Show()
		ns.UI:Refresh()
		Print("Loaded " .. m.name .. " onto the bench.")
	elseif cmd == "tutorial" or cmd == "tutorials" or cmd == "help" then
		ns.Tutorial:Toggle()
	elseif cmd == "scan" then
		ns.Validate.ScanAll()
	elseif cmd == "confirm" then
		ns.db.confirmOverwrite = not (ns.db.confirmOverwrite ~= false)
		Print("Ask before a macro slot is replaced: " .. ns.YesNo(ns.db.confirmOverwrite ~= false))
	elseif cmd == "minimap" then
		ns.db.minimap = not ns.db.minimap
		ns.UI:UpdateMinimapButton()
		Print("Minimap button: " .. ns.YesNo(ns.db.minimap))
	elseif cmd == "debug" then
		Print("Macro Bench " .. ns.VERSION)
		local a, c = ns.MacroCaps()
		local list = ns.MacroList()
		Print(format("macro slots: %d of %d account, %d of %d character",
			ns.macroCounts and ns.macroCounts.account or 0, a, ns.macroCounts and ns.macroCounts.char or 0, c))
		Print("drafts kept here: " .. #ns.db.drafts .. ", macros in the game: " .. #list)
		Print("conditions resolve live: " .. ns.YesNo(type(SecureCmdOptionParse) == "function"))
		Print("scripts can be syntax checked: " .. ns.YesNo(type(loadstring) == "function" or type(load) == "function"))
		Print("queued writes waiting for combat to end: " .. #queue)
		local keys = {}
		for k in pairs(ns.report) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do Print("  " .. k .. ": " .. tostring(ns.report[k])) end
	else
		Usage()
	end
end

SLASH_MACROBENCH1 = "/macrobench"
SLASH_MACROBENCH2 = "/mbench"
SLASH_MACROBENCH3 = "/mb"
SlashCmdList.MACROBENCH = Command

function MacroBench_OnAddonCompartmentClick()
	ns.UI:Toggle()
end
