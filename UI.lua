-- Macro Bench window. Two pages, like the spellbook it borrows its art from.
--
--   Left    templates and parts: your own macros and drafts, the parts a macro is built from, and a
--           chapter of templates for everything in general plus one per class, your own class
--           first. Its chapters are side tabs, as the spellbook's are, so the page stays narrow.
--   Right   the bench. One line of the macro is one chain of parts, read left to right:
--
--               [Cast] › [held down: shift] › [aimed at: mouseover, enemy, alive] › [Polymorph]
--
--           Every part is dragged about on its own and opens its own options when clicked. Under
--           the chain, always visible, is the macro text those parts add up to, and beside it what
--           the check found. Chain and text are the same macro seen twice: change one and the other
--           follows, and both are editable.
--
-- Every template goes through pcall with a fallback; "/macrobench debug" lists what resolved.

local ADDON, ns = ...
local UI = {}
ns.UI = UI

local FRAME_W, FRAME_H = 1360, 764
local ICON = "Interface\\Icons\\INV_Scroll_03"
local BOOK_W = 412
local PART_H, PART_GAP, LINE_GAP = 42, 8, 12
local BOOK_ROW, HEAD_ROW = 40, 22
-- Where the bench starts: to the right of the tab strip and the page beside it.
local BENCH_L = BOOK_W + 10

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local strlower, format = string.lower, string.format

local G, V, T
local frame, body, bookPane, chainPane, partPane
local textWindow, checkWindow, checkNote, checkStatus
local bookList, checkList
local chainScroll, chainContent, chainEmpty, linkHost
local partScroll, partContent
local parts, plates, links, editors
local partsScroll, partsContent, palette, palHeads
local bookTop, classButtons
UI.focus = {}
UI.corners = {}
local partTitle, partIcon, partHint, partEmpty, partButtons
local textBox, textScroll, charCount
local nameBox, iconButton, perCharCheck, statusText
local findings = {}
local book = { tab = "BLOCKS", class = "WARRIOR", search = "" }

-- ------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------
local function TryCreateFrame(ftype, name, parent, candidates)
	for _, c in ipairs(candidates) do
		local tmpl, check = c[1], c[2]
		local ok, f = pcall(CreateFrame, ftype, name, parent, tmpl)
		if ok and f and (not check or check(f)) then
			ns.report["template " .. tmpl] = "ok"
			return f, tmpl
		end
		ns.report["template " .. tmpl] = "missing"
		if ok and f then f:Hide() end
	end
	return CreateFrame(ftype, name, parent), nil
end

local function HasAtlas(atlas)
	if not C_Texture or not C_Texture.GetAtlasInfo then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
	return ok and info ~= nil
end

local function TextTooltip(owner, title, ...)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(title, 1, 0.82, 0)
	for i = 1, select("#", ...) do
		local line = select(i, ...)
		if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
	end
	GameTooltip:Show()
end

local function HideTooltip() GameTooltip:Hide() end

local function MakeButton(parent, text, width, tip)
	local b = TryCreateFrame("Button", nil, parent, { { "UIPanelButtonTemplate" }, { "GameMenuButtonTemplate" } })
	b:SetSize(width or 100, 22)
	if b.SetText then b:SetText(text) end
	if tip then
		b:SetScript("OnEnter", function(self) TextTooltip(self, text, tip) end)
		b:SetScript("OnLeave", HideTooltip)
	end
	return b
end

local function CreateCheck(parent)
	local cb
	for _, tmpl in ipairs({ "UICheckButtonTemplate", "ChatConfigCheckButtonTemplate", "InterfaceOptionsCheckButtonTemplate" }) do
		local ok, made = pcall(CreateFrame, "CheckButton", nil, parent, tmpl)
		if ok and made and made.SetChecked then
			cb = made
			ns.report["check button"] = tmpl
			break
		end
	end
	if not cb then
		cb = CreateFrame("CheckButton", nil, parent)
		cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
		cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
		cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
		cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
		ns.report["check button"] = "bare"
	end
	return cb
end

local function TrimIcon(tex)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	return tex
end

local function Plate(parent, r, g, b, a)
	local t = parent:CreateTexture(nil, "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(r or 0, g or 0, b or 0, a or 0.4)
	return t
end

-- A one pixel border, drawn rather than built from a template, so it works whatever the client has.
local function Outline(f)
	local o = { parts = {} }
	for i = 1, 4 do o.parts[i] = f:CreateTexture(nil, "OVERLAY") end
	o.parts[1]:SetPoint("TOPLEFT")
	o.parts[1]:SetPoint("TOPRIGHT")
	o.parts[1]:SetHeight(1)
	o.parts[2]:SetPoint("BOTTOMLEFT")
	o.parts[2]:SetPoint("BOTTOMRIGHT")
	o.parts[2]:SetHeight(1)
	o.parts[3]:SetPoint("TOPLEFT")
	o.parts[3]:SetPoint("BOTTOMLEFT")
	o.parts[3]:SetWidth(1)
	o.parts[4]:SetPoint("TOPRIGHT")
	o.parts[4]:SetPoint("BOTTOMRIGHT")
	o.parts[4]:SetWidth(1)
	function o:Set(r, g, b, a)
		for _, p in ipairs(self.parts) do
			p:SetColorTexture(r, g, b, a or 1)
			p:Show()
		end
	end
	return o
end

local function Pane(parent, title, left, right, top, height, bottom)
	local p = CreateFrame("Frame", nil, parent)
	p:SetPoint("TOP", parent, "TOP", 0, -(top or 0))
	if height then p:SetHeight(height)
	else p:SetPoint("BOTTOM", parent, "BOTTOM", 0, bottom or 2) end
	if left then p:SetPoint("LEFT", parent, "LEFT", left, 0) else p:SetPoint("LEFT", parent, "LEFT", 2, 0) end
	if right then p:SetPoint("RIGHT", parent, "LEFT", right, 0) else p:SetPoint("RIGHT", parent, "RIGHT", -2, 0) end
	Plate(p, 0, 0, 0, 0.42)
	local strip = p:CreateTexture(nil, "BACKGROUND", nil, 2)
	strip:SetPoint("TOPLEFT")
	strip:SetPoint("TOPRIGHT")
	strip:SetHeight(20)
	strip:SetColorTexture(0.12, 0.09, 0.03, 0.9)
	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", 8, -4)
	p.title:SetText(title)
	p.note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.note:SetPoint("TOPRIGHT", -8, -5)
	return p
end

local function CreateList(parent, rowHeight, createRow, updateRow)
	local list = { rows = {} }
	local sf = TryCreateFrame("ScrollFrame", nil, parent, {
		{ "MacroBenchScrollFrameTemplate" }, { "UIPanelScrollFrameTemplate" },
	})
	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(10, 10)
	sf:SetScrollChild(content)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = max(0, content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * 42)))
	end)
	list.frame, list.content = sf, content
	function list:Update(items)
		self.items = items
		content:SetWidth(max(10, sf:GetWidth() - 6))
		local y = 0
		for i, item in ipairs(items) do
			local row = self.rows[i]
			if not row then
				row = createRow(content, i)
				self.rows[i] = row
			end
			local h = (type(rowHeight) == "function") and rowHeight(item) or rowHeight
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			-- The right edge is pinned to the scroll frame rather than to the content: a scroll
			-- child's own width is not known until the client has laid the window out, and a row
			-- that measured itself before that would wrap its text in the wrong place.
			row:SetPoint("RIGHT", sf, "RIGHT", -2, 0)
			row:SetHeight(h)
			row.index = i
			updateRow(row, item, i)
			row:Show()
			y = y + h
		end
		for i = #items + 1, #self.rows do self.rows[i]:Hide() end
		content:SetHeight(max(y, sf:GetHeight()))
		if sf.UpdateScrollChildRect then pcall(sf.UpdateScrollChildRect, sf) end
		local maxScroll = max(0, y - sf:GetHeight())
		if sf:GetVerticalScroll() > maxScroll then sf:SetVerticalScroll(maxScroll) end
	end
	function list:IsOver() return sf:IsVisible() and sf:IsMouseOver() end
	return list
end

-- ------------------------------------------------------------------
-- Reading and writing the macro
-- ------------------------------------------------------------------
local function Block(i) return ns.bench.blocks[i] end
local function Clause(i, j)
	local b = Block(i)
	return b and b.clauses and b.clauses[j] or nil
end
local function CondAt(i, j, c)
	local cl = Clause(i, j)
	return cl and cl.conds and cl.conds[c] or ""
end
local function SetCondAt(i, j, c, text)
	local cl = Clause(i, j)
	if not cl then return end
	cl.conds = cl.conds or {}
	text = G.Trim(text or "")
	if text == "" then
		table.remove(cl.conds, c)
	else
		cl.conds[min(c, #cl.conds + 1)] = text
	end
end

function UI:Changed(fromText)
	ns.bench.dirty = true
	if not fromText then ns.bench.text = G.Compile(ns.bench.blocks) end
	self:Refresh(fromText)
end

function UI:InsertBlocks(blocks, at)
	local list = ns.bench.blocks
	at = max(1, min(at or (#list + 1), #list + 1))
	for i = #blocks, 1, -1 do table.insert(list, at, blocks[i]) end
	self.sel = { block = at, kind = "action" }
	self:Changed()
end

function UI:RemoveBlock(index)
	table.remove(ns.bench.blocks, index)
	self.sel = nil
	self:Changed()
end

function UI:MoveBlock(from, to)
	local list = ns.bench.blocks
	local b = list[from]
	if not b then return end
	table.remove(list, from)
	if to > from then to = to - 1 end
	to = max(1, min(to, #list + 1))
	table.insert(list, to, b)
	self.sel = { block = to, kind = "action" }
	self:Changed()
end

function UI:DuplicateBlock(index)
	local b = Block(index)
	if not b then return end
	local copy = G.Parse(G.CompileBlock(b))[1]
	if copy then self:InsertBlocks({ copy }, index + 1) end
end

-- Changing which command a line is. Conditions are kept when both sides read them.
function UI:SetCommand(index, cmd)
	local b = Block(index)
	if not b then return end
	local text
	if b.kind == "script" then text = b.body
	elseif b.kind == "comment" or b.kind == "raw" then text = b.text
	elseif b.clauses and b.clauses[1] then text = b.clauses[1].arg end
	local new = G.NewBlock(cmd, G.Trim(text or ""))
	if new.clauses and b.clauses then
		-- Carry the whole clause list over, argument and all, and keep the new command's first
		-- argument only when the old line had nothing in it.
		local carried = {}
		for j, cl in ipairs(b.clauses) do
			carried[j] = { conds = cl.conds or {}, arg = cl.arg or "" }
		end
		if #carried > 0 then new.clauses = carried end
	end
	ns.bench.blocks[index] = new
	self.sel = { block = index, kind = "action" }
	self:Changed()
end

function UI:SetArg(clauseIndex, text)
	local i = self.sel and self.sel.block
	local b = i and Block(i)
	if not b then return end
	if b.kind == "script" then b.body = text
	elseif b.kind == "comment" then b.text = (text:sub(1, 1) == "#") and text or ("# " .. text)
	elseif b.kind == "raw" then b.text = text
	else
		local cl = Clause(i, clauseIndex or 1)
		if cl then cl.arg = text end
	end
	-- Everything is redrawn, including the macro text. A box with the keyboard in it is never
	-- written to, so whatever is being typed survives.
	self:Changed()
end

-- ------------------------------------------------------------------
-- The parts of a line
-- ------------------------------------------------------------------
-- kind: action | when | or | arg | otherwise | add
local function PartsOf(b, i)
	local items = { { block = i, kind = "action" } }
	local function add(t)
		t.block = i
		items[#items + 1] = t
	end
	if b.kind == "cmd" or b.kind == "tooltip" then
		for j, cl in ipairs(b.clauses or {}) do
			if j > 1 then add({ kind = "otherwise", clause = j }) end
			for c, cond in ipairs(cl.conds or {}) do
				if c > 1 then add({ kind = "or", clause = j, cond = c }) end
				local buckets = G.SplitCond(cond)
				local any = false
				for _, bucket in ipairs(G.BUCKET_ORDER) do
					if #(buckets[bucket] or {}) > 0 then
						add({ kind = "when", clause = j, cond = c, bucket = bucket })
						any = true
					end
				end
				if not any then add({ kind = "when", clause = j, cond = c, bucket = "other" }) end
			end
			if G.BlockArgKind(b) ~= "none" then add({ kind = "arg", clause = j }) end
			add({ kind = "add", clause = j })
		end
	else
		add({ kind = "arg", clause = 1 })
	end
	return items
end

local function SameSel(a, b)
	if not a or not b then return false end
	return a.block == b.block and a.kind == b.kind and (a.clause or 0) == (b.clause or 0)
		and (a.cond or 0) == (b.cond or 0) and (a.bucket or "") == (b.bucket or "")
end

-- ------------------------------------------------------------------
-- The spellbook's own art
-- ------------------------------------------------------------------
local KNOWN_ART = { tab = "spellbook-Tab-Frame-C60", tabActiveGlow = "spellbook-Tab-Frame-glow-gradient-C60" }
local bookArt
local function BookArt()
	if bookArt ~= nil then return bookArt or nil end
	bookArt = false
	if ns.db.plainBook then return end
	local art = {}
	for key, atlas in pairs(KNOWN_ART) do
		if HasAtlas(atlas) then art[key] = atlas end
	end
	if not art.tab then return end
	bookArt = art
	ns.report["book tab art"] = "spellbook atlas"
	return art
end

local TAB_W, TAB_H, TAB_GAP = 43, 37, 2
local function CreateBookTab(holder, pane, token, index)
	local tab = CreateFrame("CheckButton", nil, holder)
	tab:SetSize(TAB_W, TAB_H)
	tab:SetPoint("BOTTOMLEFT", pane, "TOPLEFT", 2 + (index - 1) * (TAB_W + TAB_GAP), 2)
	local art = BookArt()
	local back = tab:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", 4, -3)
	back:SetPoint("BOTTOMRIGHT", -4, 0)
	back:SetColorTexture(0.02, 0.02, 0.02, 1)
	local icon = tab:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOP", 0, -4)
	icon:SetSize(TAB_W - 12, TAB_W - 12)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local classToken = token
	if token == "CLASSES" then classToken = select(2, UnitClass("player")) end
	if token == "MINE" then icon:SetTexture(ns.SafeIcon("INV_Misc_Note_01"))
	elseif token == "BLOCKS" then icon:SetTexture(ns.SafeIcon("INV_Misc_Book_09"))
	elseif token == "GENERAL" then icon:SetTexture(ns.SafeIcon("INV_Scroll_03"))
	elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] then
		icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
		local c = CLASS_ICON_TCOORDS[classToken]
		icon:SetTexCoord(c[1], c[2], c[3], c[4])
	else
		icon:SetTexture(ns.QUESTION)
	end
	if art and art.tab then
		local frameTex = tab:CreateTexture(nil, "OVERLAY")
		frameTex:SetAllPoints()
		frameTex:SetAtlas(art.tab)
		if art.tabActiveGlow then
			tab.glow = tab:CreateTexture(nil, "OVERLAY", nil, -1)
			tab.glow:SetPoint("TOPLEFT", 0, 1)
			tab.glow:SetPoint("BOTTOMRIGHT", 0, 0)
			tab.glow:SetAtlas(art.tabActiveGlow)
			tab.glow:Hide()
		end
	else
		tab.outline = Outline(tab)
		ns.report["book tab art"] = "plain"
	end
	tab:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	tab.token = token
	tab:SetScript("OnClick", function(self)
		book.tab = self.token
		ns.db.lastTab = self.token
		UI:RefreshBook()
		UI:SyncTabs()
	end)
	tab:SetScript("OnEnter", function(self)
		local extra
		if self.token == "MINE" then extra = "Everything you have kept here, and every macro in your macro slots. Click one to put it on the bench."
		elseif self.token == "BLOCKS" then extra = "The parts a macro is built from. Drag one onto the chain, or click to add it."
		else extra = "Whole macros to start from. Click one to put it on the bench." end
		TextTooltip(self, T.Label(self.token), extra)
	end)
	tab:SetScript("OnLeave", HideTooltip)
	return tab
end

-- The window re-levels itself whenever it is shown or clicked, so whatever sits on its border has
-- to be put back above that art each time. Without this a corner button is there to be hovered but
-- not to be seen.
function UI:LiftCorners()
	if not frame then return end
	-- Measured against the close button, not the window: the close button is the thing on this
	-- border that is certainly drawn, so one above it is certainly drawn too. Taken again on every
	-- show and every raise, because the window re-levels itself and its close button with it.
	local above = frame.CloseButton or frame
	local strata = above.GetFrameStrata and above:GetFrameStrata() or frame:GetFrameStrata()
	local level = ((above.GetFrameLevel and above:GetFrameLevel()) or frame:GetFrameLevel() or 1) + 1
	ns.report["corner buttons"] = (strata or "?") .. " level " .. level
	for _, f in ipairs(self.corners or {}) do
		if f.SetFrameStrata and strata then f:SetFrameStrata(strata) end
		if f.SetFrameLevel then f:SetFrameLevel(level) end
	end
end

function UI:SyncTabs()
	for _, tab in ipairs(self.tabs or {}) do
		local on = tab.token == book.tab
		tab:SetChecked(on)
		if tab.glow then tab.glow:SetShown(on) end
		if tab.outline then tab.outline:Set(on and 1 or 0.45, on and 0.82 or 0.4, on and 0.1 or 0.33, 1) end
		tab:SetAlpha(on and 1 or 0.7)
	end
end

-- ------------------------------------------------------------------
-- Dragging
-- ------------------------------------------------------------------
local ghost, caret
local function Ghost()
	if ghost then return ghost end
	ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetSize(220, 24)
	ghost:SetFrameStrata("TOOLTIP")
	Plate(ghost, 0.05, 0.05, 0.05, 0.9)
	ghost.icon = TrimIcon(ghost:CreateTexture(nil, "ARTWORK"))
	ghost.icon:SetSize(20, 20)
	ghost.icon:SetPoint("LEFT", 2, 0)
	ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 4, 0)
	ghost.text:SetPoint("RIGHT", -4, 0)
	ghost.text:SetJustifyH("LEFT")
	ghost:Hide()
	ghost:SetScript("OnUpdate", function() UI:DragUpdate() end)
	return ghost
end

function UI:DragUpdate()
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	ghost:ClearAllPoints()
	ghost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 26)
	local payload = self.drag
	if not payload then return end
	-- A whole line being moved, or a new line arriving, shows where it will land. A part being
	-- moved onto a line highlights that line instead.
	if payload.moveLine or payload.proto or payload.blocks then
		self:ShowCaret(chainScroll:IsMouseOver() and self:LineDropIndex() or nil)
	else
		self:ShowCaret(nil)
		local line = self:LineUnderCursor()
		for i, plate in ipairs(plates) do
			if plate:IsShown() then plate.glow:SetShown(i == line) end
		end
	end
end

function UI:ShowCaret(at)
	if not caret then
		caret = chainContent:CreateTexture(nil, "OVERLAY")
		caret:SetHeight(3)
		caret:SetColorTexture(1, 0.82, 0, 0.9)
		caret:Hide()
	end
	if not at then caret:Hide() return end
	local count = #ns.bench.blocks
	caret:ClearAllPoints()
	if count == 0 then
		caret:SetPoint("TOPLEFT", chainContent, "TOPLEFT", 8, -8)
		caret:SetPoint("TOPRIGHT", chainContent, "TOPRIGHT", -8, -8)
	elseif at > count then
		caret:SetPoint("BOTTOMLEFT", plates[count], "BOTTOMLEFT", 0, -3)
		caret:SetPoint("BOTTOMRIGHT", plates[count], "BOTTOMRIGHT", 0, -3)
	else
		caret:SetPoint("TOPLEFT", plates[at], "TOPLEFT", 0, 3)
		caret:SetPoint("TOPRIGHT", plates[at], "TOPRIGHT", 0, 3)
	end
	caret:Show()
end

function UI:StartDrag(payload, icon, label)
	self.drag = payload
	local g = Ghost()
	g.icon:SetTexture(icon or ns.QUESTION)
	g.text:SetText(label or "")
	g:Show()
end

function UI:LineUnderCursor()
	local scale = chainScroll:GetEffectiveScale()
	local _, cy = GetCursorPosition()
	cy = cy / scale
	for i = 1, #ns.bench.blocks do
		local plate = plates[i]
		if plate and plate:IsShown() and plate:GetTop() and cy <= plate:GetTop() and cy >= plate:GetBottom() then
			return i
		end
	end
	return nil
end

function UI:LineDropIndex()
	local count = #ns.bench.blocks
	if count == 0 then return 1 end
	local scale = chainScroll:GetEffectiveScale()
	local _, cy = GetCursorPosition()
	cy = cy / scale
	for i = 1, count do
		local plate = plates[i]
		if plate and plate:IsShown() and plate:GetTop() then
			local mid = (plate:GetTop() + plate:GetBottom()) / 2
			if cy > mid then return i end
			if cy > plate:GetBottom() then return i + 1 end
		end
	end
	return count + 1
end

function UI:EndDrag()
	local payload = self.drag
	self.drag = nil
	if ghost then ghost:Hide() end
	self:ShowCaret(nil)
	for _, plate in ipairs(plates or {}) do plate.glow:Hide() end
	if not payload then return end
	local overChain = chainScroll:IsMouseOver()
	if payload.movePart then
		local target = self:LineUnderCursor()
		local from = payload.movePart
		if target and overChain then
			self:MovePart(from, target)
		elseif not overChain and not bookList:IsOver() then
			SetCondAt(from.block, from.clause, from.cond,
				G.SetBucket(CondAt(from.block, from.clause, from.cond), from.bucket, ""))
			self:Changed()
		end
		return
	end
	if payload.partProto then
		local target = overChain and (self:LineUnderCursor() or #ns.bench.blocks) or nil
		if target and target > 0 then self:AddPart(target, 1, payload.partProto) end
		return
	end
	if not overChain then
		if payload.moveLine then self:RemoveBlock(payload.moveLine) end
		return
	end
	local at = self:LineDropIndex()
	if payload.moveLine then self:MoveBlock(payload.moveLine, at)
	elseif payload.blocks then self:InsertBlocks(payload.blocks, at)
	elseif payload.proto then self:InsertBlocks({ G.NewBlock(payload.proto.cmd, payload.proto.arg or "", payload.proto.cond) }, at) end
end

-- Moving a set of conditions from one line to another: the terms go, the rest of both lines stay.
function UI:MovePart(from, toBlock)
	local text = G.BucketText(CondAt(from.block, from.clause, from.cond), from.bucket)
	if text == "" then return end
	if from.block == toBlock then return end
	SetCondAt(from.block, from.clause, from.cond,
		G.SetBucket(CondAt(from.block, from.clause, from.cond), from.bucket, ""))
	local target = Block(toBlock)
	if not target or not target.clauses or not target.clauses[1] then
		self:Changed()
		return
	end
	local cl = target.clauses[1]
	cl.conds = cl.conds or {}
	if #cl.conds == 0 then cl.conds[1] = "" end
	cl.conds[1] = G.SetBucket(cl.conds[1], from.bucket, text)
	self.sel = { block = toBlock, kind = "when", clause = 1, cond = 1, bucket = from.bucket }
	self:Changed()
end

-- A part from the book dropped on a line, or picked from the "+" panel. condIndex says which set of
-- brackets it belongs in, so adding a condition to an empty "or" set does not land in the first one.
function UI:AddPart(blockIndex, clauseIndex, proto, condIndex)
	local b = Block(blockIndex)
	if not b then return end
	if proto.part == "otherwise" then
		if not b.clauses then return end
		b.clauses[#b.clauses + 1] = { conds = {}, arg = "" }
		self.sel = { block = blockIndex, kind = "otherwise", clause = #b.clauses }
		self:Changed()
		return
	end
	if proto.part == "or" then
		local cl = Clause(blockIndex, clauseIndex) or (b.clauses and b.clauses[1])
		if not cl then return end
		cl.conds = cl.conds or {}
		cl.conds[#cl.conds + 1] = ""
		self.sel = { block = blockIndex, kind = "when", clause = clauseIndex or 1, cond = #cl.conds, bucket = "other" }
		self:Changed()
		return
	end
	if not G.BlockTakesCond(b) then
		ns.Print("That line does not read conditions, so there is nothing for this to do.")
		return
	end
	local cl = Clause(blockIndex, clauseIndex) or (b.clauses and b.clauses[1])
	if not cl then return end
	cl.conds = cl.conds or {}
	local at = min(condIndex or 1, #cl.conds + 1)
	if cl.conds[at] == nil then cl.conds[at] = "" end
	local seed = proto.seed or ""
	if seed ~= "" and G.BucketText(cl.conds[at], proto.part) == "" then
		cl.conds[at] = G.SetBucket(cl.conds[at], proto.part, seed)
	end
	self.sel = { block = blockIndex, kind = "when", clause = clauseIndex or 1, cond = at, bucket = proto.part }
	self:Changed()
end

-- ------------------------------------------------------------------
-- The chain
-- ------------------------------------------------------------------
local PART_LOOK = {
	action = { 0.20, 0.15, 0.04, "the action" },
	when = { 0.06, 0.13, 0.20, nil },
	arg = { 0.07, 0.16, 0.08, "what" },
	otherwise = { 0.14, 0.14, 0.14, nil },
	["or"] = { 0.14, 0.14, 0.14, nil },
	add = { 0.10, 0.10, 0.10, nil },
}

local function PartWords(item)
	local b = Block(item.block)
	if not b then return "", "" end
	if item.kind == "action" then
		return "the action", G.BlockLabel(b)
	elseif item.kind == "otherwise" then
		return "", "otherwise"
	elseif item.kind == "or" then
		return "", "or"
	elseif item.kind == "add" then
		return "", "+"
	elseif item.kind == "when" then
		local cond = CondAt(item.block, item.clause, item.cond)
		if G.Trim(cond) == "" then return "", "add a condition" end
		local text = G.BucketText(cond, item.bucket)
		local words = G.CondLabel(text)
		return G.BUCKET_LABEL[item.bucket] or "when", (words ~= "" and words or "anything")
	else
		local kind = G.BlockArgKind(b)
		local label = (kind == "spell" and "spell") or (kind == "item" and "item")
			or (kind == "sequence" and "in order") or (kind == "unit" and "unit")
			or (kind == "lua" and "script") or (kind == "subject" and "shown as") or "what"
		local text
		if b.kind == "script" then text = b.body
		elseif b.kind == "comment" or b.kind == "raw" then text = b.text
		else
			local cl = Clause(item.block, item.clause)
			text = cl and cl.arg
		end
		text = G.Trim(text or "")
		return label, (text ~= "" and text or "…")
	end
end

-- How every block on the bench is painted, whatever it is: the chain and the parts list in the book
-- both go through here, so a block in the list is the same object you are about to drop.
-- icon: a texture, or true for the pale placeholder, or nil for none. Gives back its width.
local function StylePart(p, kindWord, value, look, icon, minWidth, selected)
	p.kindText:SetText((kindWord and kindWord ~= "") and ("|cff7a7a7a" .. kindWord .. "|r") or "")
	p.valueText:SetText(value or "")
	local hasIcon = icon ~= nil
	if hasIcon then
		p.icon:SetTexture(icon == true and ns.SafeIcon("INV_Misc_Note_01") or icon)
		p.icon:SetAlpha(icon == true and 0.3 or 1)
	end
	p.icon:SetShown(hasIcon)
	local inset = hasIcon and 26 or 8
	p.kindText:ClearAllPoints()
	p.kindText:SetPoint("TOPLEFT", inset, -4)
	p.kindText:SetPoint("TOPRIGHT", -6, -4)
	p.valueText:ClearAllPoints()
	p.valueText:SetPoint("TOPLEFT", inset, -19)
	p.valueText:SetPoint("TOPRIGHT", -6, -19)
	local textWidth = max(p.kindText:GetStringWidth(), p.valueText:GetStringWidth())
	local w = min(230, max(minWidth or 76, ceil(textWidth) + inset + 12))
	p:SetWidth(w)
	p.bg:SetColorTexture(look[1], look[2], look[3], 0.9)
	if selected then p.outline:Set(1, 0.82, 0, 1) else p.outline:Set(0.28, 0.26, 0.2, 1) end
	return w
end

-- The bare frame a block is drawn on. The scripts on it are set by whoever is using it.
local function CreatePartFrame(parent)
	local p = CreateFrame("Button", nil, parent)
	p:SetHeight(PART_H)
	p.bg = Plate(p, 0.1, 0.1, 0.1, 0.9)
	p.outline = Outline(p)
	p:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	p.icon = TrimIcon(p:CreateTexture(nil, "ARTWORK"))
	p.icon:SetSize(18, 18)
	p.icon:SetPoint("LEFT", 5, 0)
	p.kindText = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.kindText:SetJustifyH("LEFT")
	p.kindText:SetMaxLines(1)
	p.valueText = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.valueText:SetJustifyH("LEFT")
	p.valueText:SetMaxLines(1)
	return p
end

local function CreatePart(parent)
	local p = CreatePartFrame(parent)
	p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnClick", function(self, button)
		local item = self.item
		if not item then return end
		if button == "RightButton" then
			UI:RemovePart(item)
		elseif item.kind == "add" then
			UI.sel = item
			UI:RefreshChain()
			UI:RefreshPart()
		else
			UI.sel = item
			UI:RefreshChain()
			UI:RefreshPart()
		end
	end)
	p:SetScript("OnDragStart", function(self)
		local item = self.item
		if not item then return end
		if item.kind == "action" then
			UI:StartDrag({ moveLine = item.block }, self.icon:GetTexture(), "line " .. item.block)
		elseif item.kind == "when" then
			UI:StartDrag({ movePart = item }, nil, select(2, PartWords(item)))
		end
	end)
	p:SetScript("OnDragStop", function() UI:EndDrag() end)
	p:SetScript("OnReceiveDrag", function(self)
		local item = self.item
		UI:DropOnLine(item and item.block)
	end)
	p:SetScript("OnEnter", function(self)
		local item = self.item
		if not item then return end
		local b = Block(item.block)
		if not b then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		local kindWord, value = PartWords(item)
		GameTooltip:AddLine(format("Line %d · %s", item.block, kindWord ~= "" and kindWord or value), 1, 0.82, 0)
		GameTooltip:AddLine(G.CompileBlock(b), 1, 1, 1, true)
		if item.kind == "when" then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(G.BUCKET_HINT[item.bucket] or "", 0.8, 0.8, 0.8, true)
		end
		local list = V.ForLine(findings, item.block)
		if #list > 0 then
			GameTooltip:AddLine(" ")
			for _, f in ipairs(list) do GameTooltip:AddLine(V.LevelColor(f.level) .. f.text .. "|r", 1, 1, 1, true) end
		end
		GameTooltip:AddLine(" ")
		if item.kind == "action" then
			GameTooltip:AddLine("Click to change what this line does. Drag to move the whole line. Right-click to take it out.", 0.5, 0.8, 1)
		elseif item.kind == "when" then
			GameTooltip:AddLine("Click to set it. Drag it onto another line to move it there. Right-click to take it off.", 0.5, 0.8, 1)
		elseif item.kind == "add" then
			GameTooltip:AddLine("Add a condition or another attempt to this line.", 0.5, 0.8, 1)
		else
			GameTooltip:AddLine("Click to fill it in. A spell or item dropped here goes straight in.", 0.5, 0.8, 1)
		end
		GameTooltip:Show()
	end)
	p:SetScript("OnLeave", HideTooltip)
	return p
end

-- ---- The same blocks, in the book, ready to be dragged in ----------
-- What a palette entry looks like as a block: the words it will wear once it is on a line.
local function ProtoLook(proto)
	if proto.part then
		if proto.part == "otherwise" then return "", "otherwise", PART_LOOK.otherwise end
		if proto.part == "or" then return "", "or", PART_LOOK["or"] end
		-- In the list a condition block wears the range it covers, in grey: what it will say once it
		-- is on a line is up to you, and one gold value there reads as the only thing it can be.
		local words = proto.shows or (proto.seed and G.CondLabel(proto.seed)) or "anything"
		return G.BUCKET_LABEL[proto.part] or "when", "|cffa0a0a0" .. words .. "|r", PART_LOOK.when
	end
	local def = G.Def(proto.cmd)
	local label = proto.label or (def and def.label) or proto.cmd
	local look = PART_LOOK.action
	if proto.cmd == "#" or proto.cmd == "raw" then look = PART_LOOK.otherwise end
	return "the action", label, look, ns.SafeIcon(proto.icon)
end

local function CreatePaletteTile(parent)
	local t = CreatePartFrame(parent)
	t:RegisterForDrag("LeftButton")
	t:SetScript("OnDragStart", function(self)
		local proto = self.proto
		if not proto then return end
		local _, value = ProtoLook(proto)
		if proto.part then
			UI:StartDrag({ partProto = proto }, self.icon:IsShown() and self.icon:GetTexture() or nil, value)
		else
			UI:StartDrag({ proto = proto }, self.icon:GetTexture(), value)
		end
	end)
	t:SetScript("OnDragStop", function() UI:EndDrag() end)
	t:SetScript("OnClick", function(self)
		local proto = self.proto
		if not proto then return end
		if proto.part then
			local at = (UI.sel and UI.sel.block) or #ns.bench.blocks
			if at < 1 then
				ns.Print("Put an action on the bench first, then this says when it runs.")
				return
			end
			UI:AddPart(at, (UI.sel and UI.sel.clause) or 1, proto, UI.sel and UI.sel.cond)
		else
			UI:InsertBlocks({ G.NewBlock(proto.cmd, proto.arg or "", proto.cond) }, #ns.bench.blocks + 1)
		end
	end)
	t:SetScript("OnEnter", function(self)
		local proto = self.proto
		if not proto then return end
		local def = proto.cmd and G.Def(proto.cmd)
		local label = proto.label or (def and def.label) or proto.cmd or proto.part
		local shown
		if proto.part then shown = "a condition block"
		elseif proto.cmd == "raw" then shown = "any line at all"
		elseif proto.cmd == "#" then shown = "# a note"
		elseif proto.cmd:sub(1, 1) == "#" then shown = proto.cmd
		else shown = "/" .. proto.cmd .. ((proto.arg or "") ~= "" and (" " .. proto.arg) or "") end
		TextTooltip(self, label, "|cff7f7f7f" .. shown .. "|r", proto.tip,
			proto.part and "Drag it onto a line, or click to add it to the line you are working on."
			or "Drag it onto the chain, or click to put it at the end.")
	end)
	t:SetScript("OnLeave", HideTooltip)
	return t
end

-- The parts chapter: the same blocks, flowing across the page and wrapping, rather than a list.
function UI:LayoutParts()
	local width = partsScroll:GetWidth()
	if width < 80 then width = BOOK_W - 24 end
	local right = width - 8
	local y, used, usedHeads = 6, 0, 0
	for _, section in ipairs(T.PALETTE) do
		usedHeads = usedHeads + 1
		local head = palHeads[usedHeads]
		if not head then
			head = partsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			head:SetTextColor(1, 0.82, 0)
			palHeads[usedHeads] = head
		end
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", partsContent, "TOPLEFT", 6, -y)
		head:SetText(section.heading)
		head:Show()
		y = y + 18
		local x = 6
		for _, proto in ipairs(section.items) do
			used = used + 1
			local t = palette[used]
			if not t then
				t = CreatePaletteTile(partsContent)
				palette[used] = t
			end
			t.proto = proto
			local kindWord, value, look, icon = ProtoLook(proto)
			local w = StylePart(t, kindWord, value, look, icon, 90, false)
			if x + w > right and x > 6 then
				x = 6
				y = y + PART_H + 6
			end
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", partsContent, "TOPLEFT", x, -y)
			t:Show()
			x = x + w + 6
		end
		y = y + PART_H + 14
	end
	for i = used + 1, #palette do palette[i]:Hide() end
	for i = usedHeads + 1, #palHeads do palHeads[i]:Hide() end
	partsContent:SetWidth(max(10, width - 6))
	partsContent:SetHeight(max(y, partsScroll:GetHeight()))
end

function UI:RemovePart(item)
	if not item then return end
	if item.kind == "action" then
		self:RemoveBlock(item.block)
	elseif item.kind == "when" then
		SetCondAt(item.block, item.clause, item.cond,
			G.SetBucket(CondAt(item.block, item.clause, item.cond), item.bucket, ""))
		self.sel = nil
		self:Changed()
	elseif item.kind == "or" then
		local cl = Clause(item.block, item.clause)
		if cl and cl.conds then table.remove(cl.conds, item.cond) end
		self.sel = nil
		self:Changed()
	elseif item.kind == "otherwise" then
		local b = Block(item.block)
		if b and b.clauses and #b.clauses > 1 then table.remove(b.clauses, item.clause) end
		self.sel = nil
		self:Changed()
	elseif item.kind == "arg" then
		self:SetArgOf(item, "")
	end
end

function UI:SetArgOf(item, text)
	local b = Block(item.block)
	if not b then return end
	if b.kind == "script" then b.body = text
	elseif b.kind == "comment" then b.text = "# " .. text
	elseif b.kind == "raw" then b.text = text
	else
		local cl = Clause(item.block, item.clause)
		if cl then cl.arg = text end
	end
	self:Changed()
end

local function CreatePlate(parent)
	local plate = CreateFrame("Frame", nil, parent)
	Plate(plate, 0.06, 0.06, 0.06, 0.55)
	plate.num = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	plate.num:SetPoint("TOPLEFT", 6, -6)
	plate.mark = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	plate.mark:SetPoint("TOPLEFT", 20, -6)
	-- Under the line number, so a whole line can go without hunting for the right block first.
	plate.del = CreateFrame("Button", nil, plate)
	plate.del:SetSize(16, 16)
	plate.del:SetPoint("TOPLEFT", 5, -22)
	plate.del:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	plate.del:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
	plate.del:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	plate.del:SetScript("OnClick", function(self)
		UI:RemoveBlock(self:GetParent().blockIndex)
	end)
	plate.del:SetScript("OnEnter", function(self)
		TextTooltip(self, "Take this line out", format("Line %d and everything on it.", self:GetParent().blockIndex or 0))
	end)
	plate.del:SetScript("OnLeave", HideTooltip)
	plate.rail = plate:CreateTexture(nil, "ARTWORK")
	plate.rail:SetHeight(1)
	plate.rail:SetColorTexture(0.35, 0.32, 0.25, 0.8)
	plate.glow = plate:CreateTexture(nil, "OVERLAY")
	plate.glow:SetAllPoints()
	plate.glow:SetColorTexture(1, 0.82, 0, 0.12)
	plate.glow:Hide()
	plate:EnableMouse(true)
	plate:SetScript("OnReceiveDrag", function(self) UI:DropOnLine(self.blockIndex) end)
	plate:SetScript("OnMouseUp", function(self) UI:DropOnLine(self.blockIndex) end)
	return plate
end

function UI:DropOnLine(index)
	local block = ns.BlockFromCursor()
	if not block then return end
	if block.kind == "macro_text" then
		self:InsertBlocks(G.Parse(block.text), index or (#ns.bench.blocks + 1))
		return
	end
	local subject = G.BlockSubject(block)
	local b = index and Block(index)
	if b and subject and (b.kind == "cmd" or b.kind == "tooltip") and b.clauses and b.clauses[1] then
		b.clauses[1].arg = subject
		if b.kind == "cmd" and G.Def(b.cmd) and G.Def(b.cmd).gcd then b.cmd = block.cmd end
		self.sel = { block = index, kind = "arg", clause = 1 }
		self:Changed()
		return
	end
	self:InsertBlocks({ block }, index or (#ns.bench.blocks + 1))
end

-- The words between two parts, so a line reads as a sentence rather than a row of boxes.
local function ConnectorWord(prev, item)
	if not prev then return nil end
	if item.kind == "add" then return nil end
	if item.kind == "or" or item.kind == "otherwise" then return nil end
	if prev.kind == "or" or prev.kind == "otherwise" then return nil end
	if item.kind == "when" then
		if prev.kind == "when" then return "and" end
		return "when"
	end
	if prev.kind == "when" then return "then" end
	return "›"
end

function UI:RefreshChain()
	local blocks = ns.bench.blocks
	local width = chainScroll:GetWidth()
	if width < 120 then width = FRAME_W - BENCH_L - 70 end
	local right = width - 16
	local y, used, usedPlates, usedLinks = 8, 0, 0, 0

	for i, b in ipairs(blocks) do
		local items = PartsOf(b, i)
		local x, lineTop, rows = 34, y, 1
		local prev
		for _, item in ipairs(items) do
			used = used + 1
			local p = parts[used]
			if not p then
				p = CreatePart(chainContent)
				parts[used] = p
			end
			p.item = item
			-- The part is written first, then measured, so its width is its own words.
			local kindWord, value = PartWords(item)
			local icon
			if item.kind == "action" or item.kind == "arg" then
				local subject, subjectKind = G.BlockSubject(b)
				local found = subject and ns.IconFor(subject, subjectKind)
				icon = found or (item.kind == "action" and true or nil)
			end
			local w = StylePart(p, kindWord, value, PART_LOOK[item.kind] or PART_LOOK.when, icon,
				(item.kind == "add" and 28) or (item.kind == "or" and 34) or 76, SameSel(UI.sel, item))

			-- The connector that comes before it, measured so it has room of its own.
			local word = ConnectorWord(prev, item)
			local link, linkW = nil, 0
			if word then
				usedLinks = usedLinks + 1
				link = links[usedLinks]
				if not link then
					-- On a frame above the line plates: a plate is a frame of its own, and its
					-- background would otherwise draw over a word written on the content.
					link = linkHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
					links[usedLinks] = link
				end
				link:SetText(word == "›" and "|cff8a8a8a›|r" or ("|cff7a7a7a" .. word .. "|r"))
				linkW = ceil(link:GetStringWidth()) + 10
			end

			if x + linkW + w > right and x > 34 then
				x = 34
				rows = rows + 1
				y = y + PART_H + 4
			end
			if link then
				link:ClearAllPoints()
				link:SetPoint("LEFT", chainContent, "TOPLEFT", x + 5, -(y + PART_H / 2))
				link:Show()
				x = x + linkW
			end
			p:ClearAllPoints()
			p:SetPoint("TOPLEFT", chainContent, "TOPLEFT", x, -y)
			p:Show()
			x = x + w + PART_GAP
			prev = item
		end

		usedPlates = usedPlates + 1
		local plate = plates[usedPlates]
		if not plate then
			plate = CreatePlate(chainContent)
			plates[usedPlates] = plate
		end
		plate.blockIndex = i
		plate:ClearAllPoints()
		plate:SetPoint("TOPLEFT", chainContent, "TOPLEFT", 4, -(lineTop - 4))
		plate:SetWidth(right + 8)
		plate:SetHeight(rows * (PART_H + 4) + 4)
		plate:SetFrameLevel(chainContent:GetFrameLevel() + 1)
		plate.num:SetText("|cff7a7a7a" .. i .. "|r")
		local worst = V.Worst(V.ForLine(findings, i))
		plate.mark:SetText(worst and V.LevelMark(worst) or "")
		-- The rail the parts sit on, so one line reads as one chain. Only drawn when the line fits
		-- on a single row; wrapped lines would need it in two pieces and it adds nothing there.
		plate.rail:ClearAllPoints()
		plate.rail:SetPoint("TOPLEFT", plate, "TOPLEFT", 30, -(PART_H / 2 + 4))
		plate.rail:SetPoint("TOPRIGHT", plate, "TOPLEFT", max(40, min(right, x - PART_GAP)), -(PART_H / 2 + 4))
		plate.rail:SetShown(rows == 1)
		plate:Show()
		y = y + PART_H + LINE_GAP
	end

	for i = used + 1, #parts do parts[i]:Hide() end
	for i = usedPlates + 1, #plates do plates[i]:Hide() end
	for i = usedLinks + 1, #links do links[i]:Hide() end
	for _, p in ipairs(parts) do
		if p:IsShown() then p:SetFrameLevel(chainContent:GetFrameLevel() + 5) end
	end
	chainContent:SetWidth(max(10, width - 6))
	chainContent:SetHeight(max(chainScroll:GetHeight(), y + 4))
	chainEmpty:SetShown(#blocks == 0)
end

-- ------------------------------------------------------------------
-- The part panel: what the selected part is made of
-- ------------------------------------------------------------------
local ARG_HINT = {
	spell = "The spell's name, exactly as the spellbook writes it. Drop one in from the spellbook and it fills itself in.",
	subject = "Leave it empty and the game works out what to show. Or name a spell, an item, or a slot number: 13 and 14 are your trinkets.",
	sequence = "The steps, separated by commas. Begin with reset=combat, reset=target or a number of seconds to say when it goes back to the first.",
	spells = "Several spells, separated by commas.",
	item = "The item's name, a bag and slot (\"1 3\"), or a slot number: 13 and 14 are trinkets, 16 the main hand.",
	items = "Several items, separated by commas.",
	slotitem = "The slot number first, then the item: \"16 Thunderfury\".",
	unit = "A unit the game knows (player, target, mouseover, focus, party1…) or somebody's name.",
	number = "A number.",
	lua = "One line of Lua, compiled as you type to check it but never run. Separate statements with a semicolon.",
	text = "Whatever you want to say.",
	frame = "The name of the button to click, as the other addon calls it.",
	none = "Nothing goes after this one: the command is the whole line.",
}

local COMMON_CMDS = {
	{ "cast", "Cast" }, { "castsequence", "Cast in order" }, { "castrandom", "At random" },
	{ "use", "Use item" }, { "#showtooltip", "Show tooltip" }, { "target", "Target" },
	{ "targetenemy", "Nearest enemy" }, { "cleartarget", "Clear target" }, { "focus", "Set focus" },
	{ "assist", "Assist" }, { "startattack", "Start attacking" }, { "stopattack", "Stop attacking" },
	{ "stopcasting", "Stop casting" }, { "stopmacro", "Stop here" }, { "cancelaura", "Cancel a buff" },
	{ "cancelform", "Leave form" }, { "equipslot", "Equip to slot" }, { "dismount", "Dismount" },
	{ "petattack", "Pet: attack" }, { "petfollow", "Pet: follow" }, { "say", "Say" }, { "run", "Script" },
}

-- The condition of the part being edited, and how to write it back. These come before the controls
-- that use them: a local declared later would not be the same name to a function written above it.
local function SelCond()
	local s = UI.sel
	if not s or s.kind ~= "when" then return "" end
	return CondAt(s.block, s.clause, s.cond)
end

local function SetSelBucket(text)
	local s = UI.sel
	if not s or s.kind ~= "when" then return end
	SetCondAt(s.block, s.clause, s.cond, G.SetBucket(SelCond(), s.bucket, text))
	UI:Changed()
end

-- Every condition the game has, in the block it belongs to. Ones that only ask yes or no are a
-- three-way button; ones that take something after the colon get a box. Between them these cover the
-- whole condition table, so there is nothing a macro can say that has no control here.
local MOD_TRI = {
	{ "mod:shift", "Shift" }, { "mod:ctrl", "Ctrl" }, { "mod:alt", "Alt" }, { "mod", "Any modifier" },
	{ "button:1", "Left click" }, { "button:2", "Right click" }, { "button:3", "Middle click" },
	{ "button:4", "Button 4" }, { "button:5", "Button 5" },
}

local TARGET_UNITS = {
	{ "@mouseover", "Mouseover" }, { "@target", "Target" }, { "@focus", "Focus" }, { "@player", "Me" },
	{ "@pet", "Pet" }, { "@targettarget", "Target's target" }, { "@party1", "Party 1" }, { "@none", "Nothing" },
}
local TARGET_TRI = {
	{ "harm", "An enemy" }, { "help", "Friendly" }, { "exists", "There at all" }, { "dead", "Dead" },
	{ "party", "In your party" }, { "raid", "In your raid" }, { "unithasvehicleui", "In a vehicle" },
}

local STATE_TRI = {
	{ "combat", "In combat" }, { "stealth", "Stealthed" }, { "mounted", "Mounted" }, { "swimming", "Swimming" },
	{ "flying", "Flying" }, { "flyable", "Flying allowed" }, { "indoors", "Indoors" }, { "outdoors", "Outdoors" },
	{ "resting", "Resting" }, { "shapeshift", "In any form" }, { "cursor", "Cursor holding something" },
	{ "extrabar", "Extra bar" }, { "overridebar", "Override bar" }, { "possessbar", "Possess bar" },
	{ "vehicleui", "Vehicle interface" }, { "canexitvehicle", "Can leave vehicle" },
}
local STATE_VALUE = {
	{ "pet", "Pet", "The pet's name or its kind: Succubus, Voidwalker, Felhunter, Imp. Empty with \"not\" ticked is [nopet], which is how you check you have none." },
	{ "form", "Form or stance", "The number the game gives it: 1, 2, 3. Several with a slash, as 1/3. Also written stance: in older macros." },
	{ "group", "Group", "party or raid." },
	{ "channeling", "Channelling", "A spell's name, or empty for anything at all." },
	{ "equipped", "Equipped", "An item type or a slot: Shields, Daggers, Thrown, Wands, 16." },
	{ "actionbar", "Action bar page", "1 to 6." },
	{ "bonusbar", "Bonus bar", "1 to 5. The bar a form or a vehicle swaps in." },
	{ "known", "Spell known", "A spell's name. Later expansions only: on this client the clause can never be true." },
}

-- A control with three answers: not asked at all, must be true, must be false.
local function TriButton(parent, term, label, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 20)
	b.bg = Plate(b, 0.09, 0.09, 0.09, 0.85)
	b.outline = Outline(b)
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 6, 0)
	b.label:SetPoint("RIGHT", -32, 0)
	b.label:SetJustifyH("LEFT")
	b.label:SetMaxLines(1)
	b.label:SetText(label)
	b.state = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.state:SetPoint("RIGHT", -6, 0)
	b.term = term
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, button)
		local text = G.BucketText(SelCond(), UI.sel.bucket)
		local now = G.TermState(text, self.term)
		local want
		if button == "RightButton" then
			want = (now == nil and "no") or (now == "no" and "yes") or nil
		else
			want = (now == nil and "yes") or (now == "yes" and "no") or nil
		end
		SetSelBucket(G.SetTermState(text, self.term, want))
	end)
	b:SetScript("OnEnter", function(self)
		TextTooltip(self, label,
			"Click to cycle: not asked, must be true, must be false. Right-click goes round the other way.",
			"In the macro: [" .. self.term .. "] or [no" .. self.term .. "]")
	end)
	b:SetScript("OnLeave", HideTooltip)
	function b:Sync(text)
		local state = G.TermState(text, self.term)
		if state == "yes" then
			self.state:SetText("|cff40ff40yes|r")
			self.outline:Set(0.25, 0.6, 0.25, 1)
			self.bg:SetColorTexture(0.05, 0.15, 0.05, 0.9)
		elseif state == "no" then
			self.state:SetText("|cffff5050no|r")
			self.outline:Set(0.6, 0.25, 0.25, 1)
			self.bg:SetColorTexture(0.16, 0.05, 0.05, 0.9)
		else
			self.state:SetText("|cff5a5a5a–|r")
			self.outline:Set(0.28, 0.26, 0.2, 1)
			self.bg:SetColorTexture(0.09, 0.09, 0.09, 0.85)
		end
	end
	return b
end

local function TriGrid(parent, defs, cols, colW, y0)
	local made = {}
	for i, def in ipairs(defs) do
		local b = TriButton(parent, def[1], def[2], colW - 8)
		b:SetPoint("TOPLEFT", ((i - 1) % cols) * colW, y0 - floor((i - 1) / cols) * 23)
		made[#made + 1] = b
	end
	return made, ceil(#defs / cols) * 23
end

-- A condition that takes something after the colon. The button in the middle says what the row is
-- doing in words — not asked, is, is not — rather than a bare tick box, which reads as "on" when it
-- means "not". Typing in the box turns the row on by itself, so a filled-in row is never idle.
-- bare: the condition means something with nothing after the colon, as [pet] does. Where it does
-- not, emptying the box takes the condition off altogether.
local VALUE_BARE = { pet = true, channeling = true, group = true, form = true }

local function ValueRow(parent, def, x, y, width)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(width, 22)
	row:SetPoint("TOPLEFT", x, y)
	row.key = def[1]
	row.bare = VALUE_BARE[def[1]] or false
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 0, 0)
	row.label:SetWidth(104)
	row.label:SetJustifyH("LEFT")
	row.label:SetMaxLines(1)
	row.label:SetText(def[2])

	local state = CreateFrame("Button", nil, row)
	state:SetSize(58, 20)
	state:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
	state.bg = Plate(state, 0.09, 0.09, 0.09, 0.85)
	state.outline = Outline(state)
	state:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	state.text = state:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	state.text:SetAllPoints()
	row.state = state

	row.box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.box:SetSize(max(70, width - 190), 20)
	row.box:SetPoint("LEFT", state, "RIGHT", 10, 0)
	row.box:SetAutoFocus(false)

	local function Write()
		local value = G.Trim(row.box:GetText())
		local want = row.state.value
		if value ~= "" and not want then want = "yes" end
		if value == "" and not row.bare then want = nil end
		row.state.value = want
		local text = G.BucketText(SelCond(), UI.sel.bucket)
		if not want then
			SetSelBucket(G.SetKeyTerm(text, row.key, "", false))
		else
			SetSelBucket(G.SetKeyTerm(text, row.key, value, want == "no", true))
		end
	end

	state:SetScript("OnClick", function(self)
		local now = self.value
		self.value = (now == nil and "yes") or (now == "yes" and "no") or nil
		Write()
	end)
	state:SetScript("OnEnter", function(self)
		TextTooltip(self, def[2],
			"Click to cycle: not asked at all, is, is not.",
			"In the macro: [" .. row.key .. ":…] or [no" .. row.key .. ":…]" .. (row.bare and (", and [" .. row.key .. "] on its own") or ""))
	end)
	state:SetScript("OnLeave", HideTooltip)

	row.box:SetScript("OnTextChanged", function(self, userInput) if userInput then Write() end end)
	row.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	row.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	row.box:SetScript("OnEnter", function(self) TextTooltip(self, def[2], def[3]) end)
	row.box:SetScript("OnLeave", HideTooltip)

	function row:Sync(text)
		local value, neg, present = G.GetKeyTerm(text, self.key)
		self.state.value = present and (neg and "no" or "yes") or nil
		if not self.box:HasFocus() then self.box:SetText(value) end
		if self.state.value == "yes" then
			self.state.text:SetText("|cff40ff40is|r")
			self.state.outline:Set(0.25, 0.6, 0.25, 1)
			self.state.bg:SetColorTexture(0.05, 0.15, 0.05, 0.9)
			self.label:SetTextColor(1, 1, 1)
		elseif self.state.value == "no" then
			self.state.text:SetText("|cffff5050is not|r")
			self.state.outline:Set(0.6, 0.25, 0.25, 1)
			self.state.bg:SetColorTexture(0.16, 0.05, 0.05, 0.9)
			self.label:SetTextColor(1, 1, 1)
		else
			self.state.text:SetText("|cff5a5a5anot asked|r")
			self.state.outline:Set(0.28, 0.26, 0.2, 1)
			self.state.bg:SetColorTexture(0.09, 0.09, 0.09, 0.85)
			self.label:SetTextColor(0.6, 0.6, 0.6)
		end
	end
	return row
end

-- The one unit the line is aimed at, and any name the game will take.
local function UnitRow(parent, y, width)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetSize(width, 46)
	row.buttons = {}
	local function SetUnit(term)
		local keep = {}
		for _, t in ipairs(G.Terms(G.BucketText(SelCond(), "target"))) do
			if not t.unit then keep[#keep + 1] = G.TermText(t) end
		end
		if term and term ~= "" then table.insert(keep, 1, term) end
		SetSelBucket(table.concat(keep, ","))
	end
	for i, def in ipairs(TARGET_UNITS) do
		local b = CreateCheck(row)
		b:SetSize(20, 20)
		b:SetPoint("TOPLEFT", ((i - 1) % 4) * 200, -floor((i - 1) / 4) * 22)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", b, "RIGHT", 1, 0)
		fs:SetText(def[2])
		b.term = def[1]
		b:SetScript("OnClick", function(self) SetUnit(self:GetChecked() and self.term or nil) end)
		row.buttons[#row.buttons + 1] = b
	end
	row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.nameLabel:SetPoint("TOPLEFT", 800, -2)
	row.nameLabel:SetText("or a name")
	row.name = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.name:SetSize(130, 20)
	row.name:SetPoint("TOPLEFT", 810, -20)
	row.name:SetAutoFocus(false)
	row.name:SetScript("OnEnterPressed", function(self)
		local text = G.Trim(self:GetText())
		SetUnit(text ~= "" and ("@" .. text) or nil)
		self:ClearFocus()
	end)
	row.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	row.name:SetScript("OnEnter", function(self)
		TextTooltip(self, "Somebody by name", "A player's name works where a unit does: @Thrall. Press enter to set it.")
	end)
	row.name:SetScript("OnLeave", HideTooltip)
	function row:Sync(text)
		local unit
		for _, t in ipairs(G.Terms(text)) do
			if t.unit then unit = "@" .. t.unit end
		end
		local known = false
		for _, b in ipairs(self.buttons) do
			local on = unit ~= nil and strlower(b.term) == strlower(unit)
			b:SetChecked(on)
			if on then known = true end
		end
		if not self.name:HasFocus() then self.name:SetText((unit and not known) and unit:sub(2) or "") end
	end
	return row
end

-- Whatever the controls above do not cover, in the game's own words. Nothing is ever hidden.
local function RawRow(parent, y, width, bucket)
	local row = CreateFrame("Frame", nil, parent)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetSize(width, 44)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.label:SetPoint("TOPLEFT", 0, 0)
	row.label:SetText("All of this block, as the game reads it")
	row.box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.box:SetSize(max(120, width - 40), 20)
	row.box:SetPoint("TOPLEFT", 6, -16)
	row.box:SetAutoFocus(false)
	row.box:SetScript("OnTextChanged", function(self, userInput) if userInput then SetSelBucket(self:GetText()) end end)
	row.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	row.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	function row:Sync(text)
		if not self.box:HasFocus() then self.box:SetText(text) end
	end
	return row
end

local function CreateEditors(host, scroll)
	local E = {}
	-- Every editor is the same size as the panel and as tall as it needs to be; the panel scrolls
	-- when one is taller than the room there is.
	local function Place(e, height)
		e:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
		e:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -8, 0)
		e:SetHeight(height)
		e.h = height
	end

	-- ---- the action -------------------------------------------------
	local action = CreateFrame("Frame", nil, host)
	Place(action, 116)
	action.buttons = {}
	for i, def in ipairs(COMMON_CMDS) do
		local b = MakeButton(action, def[2], 104)
		b:SetHeight(20)
		b:SetPoint("TOPLEFT", ((i - 1) % 8) * 108, -floor((i - 1) / 8) * 23)
		b.cmd = def[1]
		b:SetScript("OnClick", function(self)
			if UI.sel then UI:SetCommand(UI.sel.block, self.cmd) end
		end)
		action.buttons[i] = b
	end
	local typedLabel = action:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	typedLabel:SetPoint("TOPLEFT", 0, -74)
	typedLabel:SetText("or any other command:  /")
	local typed = CreateFrame("EditBox", nil, action, "InputBoxTemplate")
	typed:SetSize(150, 20)
	typed:SetPoint("LEFT", typedLabel, "RIGHT", 10, 0)
	typed:SetAutoFocus(false)
	typed:SetScript("OnEnterPressed", function(self)
		local cmd = G.Trim(self:GetText()):gsub("^/", "")
		if cmd ~= "" and UI.sel then UI:SetCommand(UI.sel.block, strlower(cmd)) end
		self:ClearFocus()
	end)
	typed:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	action.typed = typed
	function action:Sync()
		local b = Block(UI.sel.block)
		local current = b and (b.kind == "tooltip" and "#showtooltip" or b.cmd)
		for _, button in ipairs(self.buttons) do
			local on = button.cmd == current
			if button.SetNormalFontObject then
				button:SetNormalFontObject(on and "GameFontNormalSmall" or "GameFontHighlightSmall")
			end
			button:SetAlpha(on and 1 or 0.75)
		end
		if not self.typed:HasFocus() then self.typed:SetText((current and not G.Def(current)) and current or "") end
	end
	E.action = action

	-- ---- held down --------------------------------------------------
	local mods = CreateFrame("Frame", nil, host)
	mods.rows = {}
	local modHint = mods:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	modHint:SetPoint("TOPLEFT", 0, 0)
	modHint:SetText("A mouse button asks which button pressed the macro, so one key can do two things.")
	local made, used = TriGrid(mods, MOD_TRI, 4, 200, -18)
	for _, b in ipairs(made) do mods.rows[#mods.rows + 1] = b end
	mods.rows[#mods.rows + 1] = RawRow(mods, -used - 26, 560, "mods")
	Place(mods, used + 76)
	function mods:Sync()
		local text = G.BucketText(SelCond(), "mods")
		for _, row in ipairs(self.rows) do row:Sync(text) end
	end
	E.mods = mods

	-- ---- aimed at ---------------------------------------------------
	local target = CreateFrame("Frame", nil, host)
	target.rows = {}
	local unitLabel = target:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	unitLabel:SetPoint("TOPLEFT", 0, 0)
	unitLabel:SetText("Aimed at")
	target.rows[#target.rows + 1] = UnitRow(target, -18, 960)
	local stateLabel = target:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	stateLabel:SetPoint("TOPLEFT", 0, -68)
	stateLabel:SetText("and it is")
	local tri, triH = TriGrid(target, TARGET_TRI, 4, 200, -86)
	for _, b in ipairs(tri) do target.rows[#target.rows + 1] = b end
	target.rows[#target.rows + 1] = RawRow(target, -90 - triH, 560, "target")
	Place(target, 140 + triH)
	function target:Sync()
		local text = G.BucketText(SelCond(), "target")
		for _, row in ipairs(self.rows) do row:Sync(text) end
	end
	E.target = target

	-- ---- only when --------------------------------------------------
	local state = CreateFrame("Frame", nil, host)
	state.rows = {}
	local stri, stateH = TriGrid(state, STATE_TRI, 4, 215, 0)
	for _, b in ipairs(stri) do state.rows[#state.rows + 1] = b end
	local valueLabel = state:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	valueLabel:SetPoint("TOPLEFT", 0, -stateH - 8)
	valueLabel:SetText("and these take an answer")
	for i, def in ipairs(STATE_VALUE) do
		state.rows[#state.rows + 1] = ValueRow(state, def,
			((i - 1) % 2) * 440, -stateH - 30 - floor((i - 1) / 2) * 24, 430)
	end
	local valueH = ceil(#STATE_VALUE / 2) * 24
	state.rows[#state.rows + 1] = RawRow(state, -stateH - 36 - valueH, 560, "state")
	Place(state, stateH + valueH + 86)
	function state:Sync()
		local text = G.BucketText(SelCond(), "state")
		for _, row in ipairs(self.rows) do row:Sync(text) end
	end
	E.state = state

	-- ---- anything else, written out ---------------------------------
	local other = CreateFrame("Frame", nil, host)
	other.rows = { RawRow(other, 0, 560, "other") }
	local otherWords = other:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	otherWords:SetPoint("TOPLEFT", 6, -46)
	otherWords:SetPoint("RIGHT", other, "RIGHT", -10, 0)
	otherWords:SetJustifyH("LEFT")
	other.words = otherWords
	Place(other, 80)
	function other:Sync()
		local s = UI.sel
		local text = G.BucketText(SelCond(), s.bucket or "other")
		for _, row in ipairs(self.rows) do row:Sync(text) end
		local words = G.CondLabel(text)
		self.words:SetText(words ~= "" and ("Runs when: " .. words)
			or "Anything the other blocks do not cover, written as the game reads it: channeling:Drain Life, worn:Shields, spec:2.")
	end
	E.other = other

	-- ---- the argument -----------------------------------------------
	local arg = CreateFrame("Frame", nil, host)
	Place(arg, 210)
	local argBox = CreateFrame("EditBox", nil, arg, "InputBoxTemplate")
	argBox:SetSize(420, 20)
	argBox:SetPoint("TOPLEFT", 6, 0)
	argBox:SetAutoFocus(false)
	argBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput and UI.sel then UI:SetArg(UI.sel.clause or 1, self:GetText()) end
		arg:SyncSuggestions()
	end)
	argBox:SetScript("OnTabPressed", function() UI:AcceptSuggestion(arg.first) end)
	argBox:SetScript("OnEditFocusGained", function() arg:SyncSuggestions() end)
	argBox:SetScript("OnEditFocusLost", function()
		-- Left open for a moment, so a click on a suggestion lands before they go.
		if C_Timer and C_Timer.After then
			C_Timer.After(0.15, function() if not argBox:HasFocus() then arg:SyncSuggestions() end end)
		else
			arg:SyncSuggestions()
		end
	end)
	argBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	argBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	argBox:SetScript("OnReceiveDrag", function() UI:DropOnLine(UI.sel and UI.sel.block) end)
	-- The window you drag the answer out of, opened from here rather than hunted for.
	local pick = MakeButton(arg, "Open the spellbook", 140)
	pick:SetPoint("LEFT", argBox, "RIGHT", 12, 0)
	pick:SetScript("OnClick", function(self)
		if self.what == "bags" then
			local ok, why = ns.OpenBags()
			arg.note:SetText(ok and "" or ("|cffffaa33" .. (why or "") .. "|r"))
			return
		end
		-- One click: it loads the spellbook addon if the client has not yet, and says so.
		local ok, why, loaded = ns.OpenSpellBook(true)
		if ok then
			arg.note:SetText(loaded
				and "|cff9d9d9dLoaded the spellbook to open it. If the game starts refusing its own clicks this session, a /reload puts that right.|r"
				or "")
		else
			arg.note:SetText("|cffffaa33" .. (why or "It would not open.") .. "|r")
		end
	end)
	pick:SetScript("OnEnter", function(self)
		if self.what == "bags" then
			TextTooltip(self, "Your bags", "Opens them so you can drag an item onto the box beside this, or onto the line itself.")
		else
			TextTooltip(self, "The spellbook", "Opens it so you can drag a spell onto the box beside this, or onto the line itself. The spell arrives named exactly as a macro needs it.")
		end
	end)
	pick:SetScript("OnLeave", HideTooltip)
	arg.pick = pick

	-- What the game makes of what has been typed: the spell or item it matches, with its own
	-- tooltip on hover, so a name that is nearly right is caught here and not in a fight.
	local match = CreateFrame("Button", nil, arg)
	match:SetSize(340, 22)
	match:SetPoint("TOPLEFT", argBox, "BOTTOMLEFT", 0, -8)
	match.icon = TrimIcon(match:CreateTexture(nil, "ARTWORK"))
	match.icon:SetSize(18, 18)
	match.icon:SetPoint("LEFT", 0, 0)
	match.text = match:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	match.text:SetPoint("LEFT", match.icon, "RIGHT", 6, 0)
	match.text:SetPoint("RIGHT", 0, 0)
	match.text:SetJustifyH("LEFT")
	match.text:SetMaxLines(1)
	match:SetScript("OnEnter", function(self)
		if not self.id then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local shown
		if self.what == "item" then
			shown = (GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, self.id))
				or pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.id)
		else
			shown = (GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, self.id))
				or pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. self.id)
		end
		if not shown then
			GameTooltip:AddLine(self.name or "", 1, 0.82, 0)
			GameTooltip:AddLine("This client would not give up its tooltip.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	match:SetScript("OnLeave", HideTooltip)
	arg.match = match

	local note = arg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", match, "BOTTOMLEFT", 0, -6)
	note:SetPoint("RIGHT", arg, "RIGHT", -12, 0)
	note:SetJustifyH("LEFT")
	arg.note = note

	-- What is being typed, finished. The rows appear under the box as soon as two letters are in,
	-- and clicking one writes the whole name — so a spell can be had without ever spelling it out.
	arg.suggestions = {}
	for i = 1, 6 do
		local row = CreateFrame("Button", nil, arg)
		row:SetSize(360, 18)
		row:SetPoint("TOPLEFT", argBox, "BOTTOMLEFT", 0, -28 - (i - 1) * 18)
		row.bg = Plate(row, 0.12, 0.12, 0.12, 0.7)
		row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		row.icon = TrimIcon(row:CreateTexture(nil, "ARTWORK"))
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 3, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetMaxLines(1)
		row:SetScript("OnClick", function(self) UI:AcceptSuggestion(self.value) end)
		row:Hide()
		arg.suggestions[i] = row
	end

	local argResolve = arg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	argResolve:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -6)
	arg.box, arg.resolve = argBox, argResolve

	-- The spell or item a clause is naming, with the sequence's reset and its later steps stripped.
	local function SubjectOf(b, clauseIndex)
		local kind = G.BlockArgKind(b)
		local cl = Clause(UI.sel.block, clauseIndex or 1)
		local text = G.Trim(cl and cl.arg or "")
		if text == "" then return nil, kind end
		if kind == "sequence" then
			text = text:gsub("^[Rr][Ee][Ss][Ee][Tt]=%S+%s*", "")
			text = G.Trim(text:match("^([^,]+)") or text)
		elseif kind == "spells" or kind == "items" then
			text = G.Trim(text:match("^([^,]+)") or text)
		elseif kind == "slotitem" then
			text = G.Trim((text:gsub("^%d+%s*", "")))
		end
		return (text ~= "" and text or nil), kind
	end

	-- A sequence and a random list are several names in one box, so only the one being typed is
	-- searched, and only that one is replaced when a suggestion is taken.
	local function Fragment(text, kind)
		text = text or ""
		local cut = 0
		if kind == "sequence" or kind == "spells" or kind == "items" then
			for pos in text:gmatch("()[,]") do cut = pos end
		end
		if cut == 0 and kind == "sequence" then
			local reset = text:match("^([Rr][Ee][Ss][Ee][Tt]=%S+%s+)")
			if reset then cut = #reset end
		end
		local prefix, rest = text:sub(1, cut), text:sub(cut + 1)
		local gap = rest:match("^(%s*)") or ""
		return prefix .. gap, rest:sub(#gap + 1)
	end
	arg.Fragment = Fragment

	function arg:SyncSuggestions()
		local s = UI.sel
		local b = s and Block(s.block)
		local rows = self.suggestions
		local found = {}
		if b and self.box:HasFocus() then
			local kind = G.BlockArgKind(b)
			if kind ~= "lua" and kind ~= "text" and kind ~= "none" and kind ~= "number" then
				local _, fragment = Fragment(self.box:GetText(), kind)
				found = ns.Suggest(fragment, kind, #rows)
			end
		end
		for i, row in ipairs(rows) do
			local entry = found[i]
			if entry then
				row.value = entry.name
				row.icon:SetTexture(entry.icon or ns.QUESTION)
				row.text:SetText(entry.name .. (entry.what == "item" and "  |cff7a7a7aitem|r" or ""))
				row:Show()
			else
				row.value = nil
				row:Hide()
			end
		end
		self.first = found[1] and found[1].name or nil
	end

	function arg:SyncMatch()
		local s = UI.sel
		local b = s and Block(s.block)
		if not b or b.kind == "script" or b.kind == "comment" or b.kind == "raw" then
			self.match:Hide()
			return
		end
		local subject, kind = SubjectOf(b, s.clause)
		if not subject then
			self.match:Hide()
			return
		end
		self.match:Show()
		local itemFirst = (kind == "item" or kind == "items" or kind == "slotitem")
		local name, icon, id, what
		if not itemFirst then
			name, icon, id = ns.SpellInfo(G.StripRank(subject))
			what = "spell"
		end
		if not id then
			local itemId, itemIcon = ns.ItemInfo(subject)
			if itemId then
				name, icon, id, what = subject, itemIcon, itemId, "item"
			end
		end
		if not id and itemFirst then
			name, icon, id = ns.SpellInfo(G.StripRank(subject))
			what = "spell"
		end
		self.match.id, self.match.name, self.match.what = id, name, what
		if id then
			self.match.icon:SetTexture(icon or ns.QUESTION)
			self.match.icon:Show()
			local extra = ""
			if kind == "sequence" or kind == "spells" or kind == "items" then extra = "  |cff7a7a7a(first of the list)|r" end
			self.match.text:SetText(format("|cff40ff40%s|r  |cff7a7a7a%s %d|r%s", name or subject,
				what == "item" and "item" or "spell", id, extra))
		elseif tonumber(subject) then
			self.match.icon:SetTexture(ns.IconFor(subject, kind) or ns.QUESTION)
			self.match.icon:Show()
			self.match.text:SetText(format("|cff9dc8ffslot %s|r  |cff7a7a7a13 and 14 are your trinkets, 16 the main hand|r", subject))
		else
			self.match.icon:Hide()
			self.match.text:SetText("|cffffaa33No spell or item of that name on this character.|r")
		end
	end

	function arg:Sync()
		local s = UI.sel
		local b = Block(s.block)
		local kind = G.BlockArgKind(b)
		if kind == "spell" or kind == "spells" or kind == "sequence" or kind == "subject" then
			self.pick.what = "spell"
			self.pick:SetText("Open the spellbook")
			self.pick:Show()
		elseif kind == "item" or kind == "items" or kind == "slotitem" then
			self.pick.what = "bags"
			self.pick:SetText("Open your bags")
			self.pick:Show()
		else
			self.pick:Hide()
		end
		local text
		if b.kind == "script" then text = b.body
		elseif b.kind == "comment" then text = (b.text or ""):gsub("^#%s*", "")
		elseif b.kind == "raw" then text = b.text
		else
			local cl = Clause(s.block, s.clause or 1)
			text = cl and cl.arg
		end
		if not self.box:HasFocus() then self.box:SetText(text or "") end
		self:SyncMatch()
		self:SyncSuggestions()
	end
	E.arg = arg

	-- ---- "+" and the separators -------------------------------------
	local add = CreateFrame("Frame", nil, host)
	Place(add, 64)
	local addDefs = {
		{ part = "mods", seed = "mod:shift", label = "Modifier", tip = "Shift, ctrl or alt held down." },
		{ part = "target", seed = "@mouseover", label = "Target filter", tip = "What the line is aimed at, and what has to be true of it." },
		{ part = "state", seed = "combat", label = "My state", tip = "In combat, stealthed, mounted, in a form." },
		{ part = "or", label = "Or these instead", tip = "Another set of brackets on the same attempt: if the first lot do not apply, the game tries these." },
		{ part = "otherwise", label = "Otherwise", tip = "Another attempt at the line, after the semicolon, read when nothing above applied." },
	}
	for i, def in ipairs(addDefs) do
		local b = MakeButton(add, def.label, 128, def.tip)
		b:SetHeight(22)
		b:SetPoint("TOPLEFT", ((i - 1) % 4) * 132, -floor((i - 1) / 4) * 26)
		b:SetScript("OnClick", function()
			local s = UI.sel
			if s then UI:AddPart(s.block, s.clause or 1, def, s.cond) end
		end)
	end
	function add:Sync() end
	E.add = add

	-- ---- otherwise / or ---------------------------------------------
	local sep = CreateFrame("Frame", nil, host)
	Place(sep, 104)
	sep.text = sep:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sep.text:SetPoint("TOPLEFT", 0, 0)
	sep.text:SetPoint("RIGHT", sep, "RIGHT", -10, 0)
	sep.text:SetJustifyH("LEFT")
	function sep:Sync()
		local s = UI.sel
		if s.kind == "otherwise" then
			self.text:SetText("Everything after this is another attempt at the same line, read only when none of the conditions before it applied. In the macro text it is the part after the semicolon.\n\nRight-click the block, or use Take it out, to drop this attempt.")
		else
			self.text:SetText("A second set of brackets on the same attempt. The game tries the first set; if they do not apply it tries these, and the first set that does decides what happens.\n\nRight-click the block, or use Take it out, to drop this set.")
		end
	end
	E.sep = sep

	for _, e in pairs(E) do e:Hide() end
	return E
end

-- Taking a suggestion: the name goes in where the part being typed was, and the keyboard stays in
-- the box so the next one can be typed straight after.
function UI:AcceptSuggestion(name)
	local editor = editors and editors.arg
	local s = self.sel
	if not name or not editor or not s then return end
	local b = Block(s.block)
	if not b then return end
	local kind = G.BlockArgKind(b)
	local prefix = editor.Fragment(editor.box:GetText(), kind)
	local text = prefix .. name
	self:SetArg(s.clause or 1, text)
	editor.box:SetText(text)
	editor.box:SetCursorPosition(#text)
	editor.box:SetFocus()
	editor:SyncSuggestions()
end

function UI:RefreshPart()
	local s = self.sel
	local b = s and Block(s.block)
	-- Which editor this is, worked out before anything is hidden: hiding a frame takes the keyboard
	-- out of any box inside it, and a box is redrawn on every keystroke. So the one that is already
	-- up is left alone rather than hidden and shown again, and typing into it survives.
	local wanted
	if b then
		if s.kind == "action" then wanted = editors.action
		elseif s.kind == "arg" then wanted = editors.arg
		elseif s.kind == "add" then wanted = editors.add
		elseif s.kind == "otherwise" or s.kind == "or" then wanted = editors.sep
		elseif s.kind == "when" then
			if G.Trim(CondAt(s.block, s.clause, s.cond)) == "" then
				wanted = editors.add
			else
				wanted = editors[s.bucket] or editors.other
			end
		end
	end
	for _, e in pairs(editors) do
		if e ~= wanted then e:Hide() end
	end
	partEmpty:SetShown(b == nil)
	partIcon:SetShown(b ~= nil)
	for _, button in pairs(partButtons) do button:SetShown(b ~= nil) end
	if not b then
		partTitle:SetText("")
		partHint:SetText("")
		return
	end

	local kindWord, value = PartWords(s)
	local subject, subjectKind = G.BlockSubject(b)
	partIcon:SetTexture((subject and ns.IconFor(subject, subjectKind)) or ns.SafeIcon("INV_Misc_Note_01"))
	partTitle:SetText(format("Line %d  |cffffffff%s|r  |cff7a7a7a%s|r",
		s.block, G.BlockLabel(b), kindWord ~= "" and ("· " .. kindWord) or ""))

	local editor, hint = wanted, ""
	if s.kind == "action" then hint = "What this line of the macro does. Everything else on the line hangs off it."
	elseif s.kind == "arg" then hint = ARG_HINT[G.BlockArgKind(b)] or ""
	elseif s.kind == "add" then hint = "Add another part to this line."
	elseif s.kind == "when" then
		hint = (editor == editors.add) and "This set of brackets is empty. What should it ask?" or (G.BUCKET_HINT[s.bucket] or "")
	end
	partHint:SetText(hint)
	if editor then
		editor:Show()
		editor:Sync()
		partContent:SetWidth(max(10, partScroll:GetWidth() - 6))
		partContent:SetHeight(max(editor.h or 100, partScroll:GetHeight()))
		-- Back to the top only when a different part has been opened, so the panel does not jump
		-- about underneath a row being typed into.
		local key = s.block .. ":" .. s.kind .. ":" .. (s.clause or 0) .. ":" .. (s.cond or 0) .. ":" .. (s.bucket or "")
		if key ~= self.shownKey then
			partScroll:SetVerticalScroll(0)
			self.shownKey = key
		end
	end
	self:RefreshResolve()
end

function UI:RefreshResolve()
	local s = self.sel
	local b = s and Block(s.block)
	if not b then return end
	local action, target = V.Resolve(b)
	local text
	if action == nil then text = ""
	elseif action == false then text = "|cff888888As things stand, this line does nothing.|r"
	else text = "|cff7fd4ffAs things stand: " .. tostring(action) .. (target and (" on " .. tostring(target)) or "") .. "|r" end
	partPane.note:SetText(text)
	if editors.arg:IsShown() then editors.arg.resolve:SetText(text) end
end

-- ------------------------------------------------------------------
-- The book's pages
-- ------------------------------------------------------------------
local function CreateBookRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row.bg = Plate(row, 0.08, 0.08, 0.08, 0.35)
	row.bg:ClearAllPoints()
	row.bg:SetPoint("TOPLEFT", 2, -1)
	row.bg:SetPoint("BOTTOMRIGHT", -2, 1)
	row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	row.icon = TrimIcon(row:CreateTexture(nil, "ARTWORK"))
	row.icon:SetSize(26, 26)
	row.icon:SetPoint("LEFT", 6, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", 40, -3)
	row.name:SetPoint("RIGHT", -24, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetMaxLines(1)
	row.why = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.why:SetPoint("TOPLEFT", 40, -19)
	row.why:SetPoint("RIGHT", -24, 0)
	row.why:SetJustifyH("LEFT")
	row.why:SetMaxLines(1)
	row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.tag:SetPoint("BOTTOMRIGHT", -6, 3)
	row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.heading:SetPoint("BOTTOMLEFT", 8, 4)
	row.heading:SetTextColor(1, 0.82, 0)
	row.del = CreateFrame("Button", nil, row)
	row.del:SetSize(16, 16)
	row.del:SetPoint("TOPRIGHT", -4, -4)
	row.del:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	row.del:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	row.del:Hide()
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function(self)
		local e = self.entry
		if not e then return end
		if e.proto and e.proto.part then
			UI:StartDrag({ partProto = e.proto }, self.icon:GetTexture(), self.name:GetText())
		elseif e.proto then
			UI:StartDrag({ proto = e.proto }, self.icon:GetTexture(), self.name:GetText())
		elseif e.text then
			UI:StartDrag({ blocks = G.Parse(e.text) }, self.icon:GetTexture(), self.name:GetText())
		end
	end)
	row:SetScript("OnDragStop", function() UI:EndDrag() end)
	return row
end

local function BookEntries()
	local out = {}
	local query = G.Trim(book.search or "")
	if query ~= "" then
		local hits = T.Search(query) or {}
		out[#out + 1] = { heading = format("%d template%s matching \"%s\"", #hits, #hits == 1 and "" or "s", query) }
		for _, hit in ipairs(hits) do
			out[#out + 1] = { text = hit.entry.text, name = hit.entry.name, why = hit.entry.why, tag = T.Label(hit.token) }
		end
		local matched = 0
		for _, section in ipairs(T.PALETTE) do
			for _, item in ipairs(section.items) do
				local label = item.label or (G.Def(item.cmd) and G.Def(item.cmd).label) or item.cmd or item.part
				if strlower(label .. " " .. (item.cmd or item.part or "") .. " " .. (item.tip or "")):find(strlower(query), 1, true) then
					if matched == 0 then out[#out + 1] = { heading = "Parts" } end
					matched = matched + 1
					out[#out + 1] = { proto = item }
				end
			end
		end
		return out
	end
	if book.tab == "BLOCKS" then
		for _, section in ipairs(T.PALETTE) do
			out[#out + 1] = { heading = section.heading }
			for _, item in ipairs(section.items) do out[#out + 1] = { proto = item } end
		end
		return out
	end
	if book.tab == "MINE" then
		local drafts = ns.Drafts()
		out[#out + 1] = { heading = format("Kept here (%d, no limit)", #drafts) }
		if #drafts == 0 then
			out[#out + 1] = { note = "Nothing yet. \"Keep here\" puts whatever is on the bench into this list, as many as you like." }
		end
		local sorted = {}
		for _, d in ipairs(drafts) do sorted[#sorted + 1] = d end
		table.sort(sorted, function(a, b) return (a.stamp or 0) > (b.stamp or 0) end)
		for _, d in ipairs(sorted) do
			out[#out + 1] = { text = d.text, name = d.name, why = (d.text or ""):gsub("\n", " | "), draft = d, icon = d.icon }
		end
		local macros = ns.MacroList()
		local counts = ns.macroCounts or {}
		out[#out + 1] = { heading = format("In the game (%d of %d, %d of %d here)",
			counts.account or 0, counts.accountCap or 0, counts.char or 0, counts.charCap or 0) }
		for _, m in ipairs(macros) do
			out[#out + 1] = {
				text = m.body, name = m.name, why = (m.body or ""):gsub("\n", " | "),
				icon = m.icon, slot = m.index, perChar = m.perChar,
				tag = m.perChar and "yours" or ("slot " .. m.index),
			}
		end
		return out
	end
	local chapter = book.tab == "CLASSES" and book.class or book.tab
	local list = T[chapter] or {}
	out[#out + 1] = { heading = format("%s (%d)", T.Label(chapter), #list) }
	for _, e in ipairs(list) do out[#out + 1] = { text = e.text, name = e.name, why = e.why } end
	return out
end

local function BookRowHeight(entry)
	if entry.heading then return HEAD_ROW end
	if entry.note then return 40 end
	return BOOK_ROW
end

local function UpdateBookRow(row, entry)
	row.entry = entry
	local isHeading = entry.heading ~= nil
	row.heading:SetShown(isHeading)
	row.icon:SetShown(not isHeading and not entry.note)
	row.del:Hide()
	row.bg:SetShown(not isHeading)
	if isHeading then
		row.heading:SetText(entry.heading)
		row.name:SetText("")
		row.why:SetText("")
		row.tag:SetText("")
		row:EnableMouse(false)
		row:SetScript("OnClick", nil)
		row:SetScript("OnEnter", nil)
		row:SetScript("OnLeave", nil)
		return
	end
	row:EnableMouse(true)
	if entry.note then
		row:SetScript("OnClick", nil)
		row:SetScript("OnEnter", nil)
		row:SetScript("OnLeave", nil)
		row.name:SetText("")
		row.why:ClearAllPoints()
		row.why:SetPoint("TOPLEFT", 10, -6)
		row.why:SetPoint("RIGHT", -10, 0)
		row.why:SetMaxLines(2)
		row.why:SetText("|cff9d9d9d" .. entry.note .. "|r")
		row.tag:SetText("")
		return
	end
	row.why:ClearAllPoints()
	row.why:SetPoint("TOPLEFT", 40, -19)
	row.why:SetPoint("RIGHT", -24, 0)
	row.why:SetMaxLines(1)
	if entry.proto then
		local proto = entry.proto
		local def = proto.cmd and G.Def(proto.cmd)
		local label = proto.label or (def and def.label) or proto.cmd or proto.part
		row.icon:SetTexture(ns.SafeIcon(proto.icon))
		row.name:SetText(label)
		local shown
		if proto.part then shown = "a condition block"
		elseif proto.cmd == "raw" then shown = "any line at all"
		elseif proto.cmd == "#" then shown = "# a note"
		elseif proto.cmd:sub(1, 1) == "#" then shown = proto.cmd
		else shown = "/" .. proto.cmd end
		row.why:SetText("|cff7f7f7f" .. shown .. ((proto.arg or "") ~= "" and (" " .. proto.arg) or "") .. "|r")
		row.tag:SetText("")
		row:SetScript("OnClick", function()
			if proto.part then
				local at = (UI.sel and UI.sel.block) or #ns.bench.blocks
				if at < 1 then
					ns.Print("Put an action on the bench first, then this decides when it runs.")
					return
				end
				UI:AddPart(at, (UI.sel and UI.sel.clause) or 1, proto)
			else
				UI:InsertBlocks({ G.NewBlock(proto.cmd, proto.arg or "", proto.cond) }, #ns.bench.blocks + 1)
			end
		end)
		row:SetScript("OnEnter", function(self)
			TextTooltip(self, label, proto.tip or (def and def.label),
				proto.part and "Drag it onto a line, or click to add it to the line you are working on."
				or "Drag it onto the chain, or click to put it at the end.")
		end)
		row:SetScript("OnLeave", HideTooltip)
		return
	end
	row.icon:SetTexture(entry.icon and ns.SafeIcon(entry.icon) or T.Icon(entry))
	row.name:SetText(entry.name or "?")
	row.why:SetText(entry.why or "")
	row.tag:SetText(entry.tag or "")
	if entry.draft then
		row.del:Show()
		row.del:SetScript("OnClick", function()
			ns.DeleteDraft(entry.draft.uid)
			ns.Print("Took \"" .. (entry.draft.name or "?") .. "\" out of the library.")
			UI:RefreshBook()
		end)
		row.del:SetScript("OnEnter", function(self) TextTooltip(self, "Forget it", "Takes it out of the library. Your macro slots are left alone.") end)
		row.del:SetScript("OnLeave", HideTooltip)
	end
	row:SetScript("OnClick", function() UI:LoadEntry(entry) end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(entry.name or "?", 1, 0.82, 0)
		if entry.why and entry.why ~= "" and not entry.draft and not entry.slot then
			GameTooltip:AddLine(entry.why, 1, 1, 1, true)
			GameTooltip:AddLine(" ")
		end
		for line in (entry.text or ""):gmatch("[^\n]+") do GameTooltip:AddLine(line, 1, 1, 1, true) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format("%d characters.", #(entry.text or "")), 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Click to put it on the bench.", 0.5, 0.8, 1)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", HideTooltip)
end

function UI:LoadEntry(entry)
	if ns.bench.dirty and ns.BenchLength() > 0 and self.confirmEntry ~= entry then
		self.confirmEntry = entry
		ns.Print("The bench has unsaved work on it. Click again to replace it, or keep it first.")
		return
	end
	self.confirmEntry = nil
	if entry.draft then
		ns.LoadDraft(entry.draft)
	else
		ns.bench.name = entry.name or ""
		ns.bench.icon = entry.icon or ns.QUESTION
		ns.bench.perChar = entry.perChar or false
		ns.bench.slot = entry.slot
		ns.bench.draft = nil
		ns.SetBenchText(entry.text or "")
	end
	ns.bench.dirty = false
	self.sel = #ns.bench.blocks > 0 and { block = 1, kind = "action" } or nil
	self:Refresh()
end

-- ------------------------------------------------------------------
-- The check pane
-- ------------------------------------------------------------------
local function CreateCheckRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("TOPLEFT", 8, -2)
	row.text:SetPoint("RIGHT", -8, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetJustifyV("TOP")
	if row.text.SetWordWrap then row.text:SetWordWrap(true) end
	row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	return row
end

local function CheckRowHeight(f) return f.height or 18 end

local function UpdateCheckRow(row, f)
	local where = f.line and format("line %d: ", f.line) or ""
	row.text:SetText(V.LevelColor(f.level) .. V.LevelMark(f.level) .. " " .. where .. f.text .. "|r")
	row:SetScript("OnClick", function()
		if f.line and Block(f.line) then
			UI.sel = { block = f.line, kind = "action" }
			UI:RefreshChain()
			UI:RefreshPart()
		end
	end)
end

-- ------------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------------
function UI:RefreshText()
	if not textBox then return end
	if not textBox:HasFocus() then
		self.syncing = true
		textBox:SetText(ns.bench.text or "")
		self.syncing = nil
	end
	self:RefreshTextCount()
end

function UI:RefreshTextCount()
	local len = #(ns.bench.text or "")
	local color = "|cff40ff40"
	if len > ns.MACRO_LIMIT then color = "|cffff5050"
	elseif len > ns.MACRO_LIMIT - 20 then color = "|cffffaa33" end
	charCount:SetText(format("%s%d|r / %d", color, len, ns.MACRO_LIMIT))
end

function UI:RefreshCheck()
	findings = V.Check(ns.bench.blocks)
	local items = {}
	for _, f in ipairs(findings) do
		f.height = 18
		items[#items + 1] = f
	end
	checkList:Update(items)
	local changed = false
	for i, f in ipairs(items) do
		local row = checkList.rows[i]
		if row then
			local h = max(18, ceil(row.text:GetStringHeight()) + 6)
			if h ~= f.height then
				f.height = h
				changed = true
			end
		end
	end
	if changed then checkList:Update(items) end
	local counts = { error = 0, warn = 0, note = 0 }
	for _, f in ipairs(findings) do counts[f.level] = (counts[f.level] or 0) + 1 end
	local parts2 = {}
	if counts.error > 0 then parts2[#parts2 + 1] = "|cffff5050" .. counts.error .. " wrong|r" end
	if counts.warn > 0 then parts2[#parts2 + 1] = "|cffffaa33" .. counts.warn .. " to look at|r" end
	if counts.note > 0 then parts2[#parts2 + 1] = "|cff9dc8ff" .. counts.note .. " worth knowing|r" end
	local summary = #parts2 > 0 and table.concat(parts2, "   ") or "|cff40ff40nothing wrong|r"
	if ns.BenchLength() == 0 then summary = "|cff9d9d9dnothing on the bench yet|r" end
	checkNote:SetText(summary)
	checkStatus.text:SetText("The check: " .. summary)
end

function UI:RefreshBook()
	if not bookList then return end
	-- The parts chapter is the blocks themselves, laid out across the page; everything else is a
	-- list of whole macros, which reads better as rows.
	local grid = book.tab == "BLOCKS" and G.Trim(book.search or "") == ""
	local classes = book.tab == "CLASSES" and G.Trim(book.search or "") == ""
	bookTop:SetHeight(classes and 28 or 1)
	for _, b in ipairs(classButtons) do
		b:SetShown(classes)
		local on = b.token == book.class
		b:SetChecked(on)
		b.outline:Set(on and 1 or 0.3, on and 0.82 or 0.28, on and 0.1 or 0.22, on and 1 or 0.8)
		b:SetAlpha(on and 1 or 0.6)
	end
	partsScroll:SetShown(grid)
	bookList.frame:SetShown(not grid)
	if grid then
		self:LayoutParts()
	else
		bookList:Update(BookEntries())
	end
end

function UI:RefreshFooter()
	if not nameBox then return end
	if not nameBox:HasFocus() then nameBox:SetText(ns.bench.name or "") end
	iconButton.icon:SetTexture(ns.BenchIcon())
	perCharCheck:SetChecked(ns.bench.perChar and true or false)
	local name = G.Trim(ns.bench.name or "")
	local where
	if ns.bench.slot then
		where = format("|cffffd100%s|r — saving replaces macro slot %d.", name ~= "" and name or "?", ns.bench.slot)
	elseif ns.bench.draft then
		where = format("|cffffd100%s|r — kept in the library, not in a macro slot yet.", name ~= "" and name or "?")
	elseif name ~= "" then
		where = format("|cffffd100%s|r — new, saved nowhere yet.", name)
	else
		where = "|cff9d9d9dA new macro. Give it a name at the bottom before you save it.|r"
	end
	if ns.bench.dirty and ns.BenchLength() > 0 then where = where .. " |cffffaa33Unsaved changes.|r" end
	local queued = ns.QueuedWrites()
	if queued > 0 then where = where .. format(" |cffffaa33%d waiting for the fight to end.|r", queued) end
	statusText:SetText(where)
end

-- The selection has to survive the macro changing under it.
function UI:ValidateSelection()
	local s = self.sel
	if not s then return end
	local b = Block(s.block)
	if not b then
		self.sel = nil
		return
	end
	for _, item in ipairs(PartsOf(b, s.block)) do
		if SameSel(item, s) then
			self.sel = item
			return
		end
	end
	self.sel = { block = s.block, kind = "action" }
end

function UI:Refresh(fromText)
	if not frame then return end
	self:ValidateSelection()
	self:RefreshCheck()
	self:RefreshChain()
	self:RefreshPart()
	if fromText then self:RefreshTextCount() else self:RefreshText() end
	self:RefreshFooter()
	if book.tab == "MINE" then self:RefreshBook() end
	if ns.Tutorial then ns.Tutorial:Check() end
	chainPane.note:SetText(format("%d line%s", #ns.bench.blocks, #ns.bench.blocks == 1 and "" or "s"))
end

function UI:Tick()
	if not frame or not frame:IsShown() then return end
	if self.sel then self:RefreshResolve() end
end

-- What a tutorial step wants to point at. "palette:Cast" finds the block called Cast in the parts
-- list, wherever it has ended up on the page.
function UI:FocusFrame(name)
	if not name or not frame or not frame:IsShown() then return nil end
	local label = name:match("^palette:(.+)$")
	if label then
		if book.tab ~= "BLOCKS" then return self.focus["tab:BLOCKS"] end
		for _, tile in ipairs(palette or {}) do
			if tile:IsShown() and tile.proto then
				local def = tile.proto.cmd and G.Def(tile.proto.cmd)
				local text = tile.proto.label or (def and def.label) or tile.proto.cmd or tile.proto.part
				if text and strlower(text) == strlower(label) then return tile end
			end
		end
		return self.focus["tab:BLOCKS"]
	end
	if name == "part" then
		-- Whichever block is open, so a step about its box points at the box's own panel.
		return self.focus.panel
	end
	return self.focus[name]
end

function UI:MacrosChanged()
	if frame and frame:IsShown() and book.tab == "MINE" then self:RefreshBook() end
end

function UI:TextEdited(text)
	if self.syncing then return end
	ns.SetBenchText(text)
	ns.bench.dirty = true
	self:Refresh(true)
end

-- ------------------------------------------------------------------
-- Saving
-- ------------------------------------------------------------------
function UI:SaveToSlot()
	local ok, err = ns.WriteMacro({ name = ns.bench.name, replace = ns.bench.slot })
	if ok == true then
		ns.bench.dirty = false
		ns.Print(format("Saved |cffffd100%s|r to macro slot %d. \"Put on cursor\" hands it to you to drop on a bar.", ns.bench.name, err))
	elseif ok == "queued" then
		ns.Print("The game will not let a macro be written during a fight. It goes in the moment this one ends.")
	else
		ns.Print(err or "Could not save it.")
	end
	self:Refresh()
end

function UI:Keep()
	local draft = ns.SaveDraft()
	ns.bench.dirty = false
	ns.Print(format("Kept |cffffd100%s|r in the library.", draft.name))
	self:Refresh()
	self:RefreshBook()
end

function UI:NewMacro()
	if ns.bench.dirty and ns.BenchLength() > 0 and not self.confirmNew then
		self.confirmNew = true
		ns.Print("The bench has unsaved work on it. Click New macro again to clear it.")
		return
	end
	self.confirmNew = nil
	ns.ClearBench()
	ns.bench.dirty = false
	self.sel = nil
	self:Refresh()
end

-- ------------------------------------------------------------------
-- Build
-- ------------------------------------------------------------------
local function BuildFrame()
	G, V, T = ns.Grammar, ns.Validate, ns.Templates
	parts, plates, links, palette, palHeads, partButtons = {}, {}, {}, {}, {}, {}
	local frameTemplate
	frame, frameTemplate = TryCreateFrame("Frame", "MacroBenchFrame", UIParent, {
		{ "ButtonFrameTemplate", function(f) return f.Inset ~= nil end },
		{ "BasicFrameTemplateWithInset", function(f) return f.Inset ~= nil end },
		{ "BackdropTemplate" },
	})
	UI.frame = frame
	frame:SetSize(FRAME_W, FRAME_H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	-- Another addon in the same strata would otherwise interleave with this one: its window over
	-- our panes, our panes over its window. Toplevel puts whichever was clicked last in front.
	if frame.SetToplevel then frame:SetToplevel(true) end
	frame:SetScript("OnMouseDown", function(self)
		if self.Raise then self:Raise() end
		UI:LiftCorners()
	end)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if self.SetUserPlaced then self:SetUserPlaced(false) end
		local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		ns.db.window = { x = self:GetLeft() * s, y = self:GetTop() * s }
	end)
	if ns.db.windowScale then frame:SetScale(max(0.55, min(1.6, ns.db.windowScale))) end
	frame:Hide()
	tinsert(UISpecialFrames, "MacroBenchFrame")
	frame:HookScript("OnShow", function()
		UI:LiftCorners()
		-- Parts measure their own words, and nothing has a real width until the client has laid the
		-- window out, which happens after this. So the first draw is done again a frame later.
		if C_Timer and C_Timer.After then C_Timer.After(0, function() UI:Refresh() end) end
	end)
	frame:HookScript("OnHide", function() ns.SaveBench() end)

	if frame.SetTitle then frame:SetTitle("Macro Bench")
	elseif frame.TitleText then frame.TitleText:SetText("Macro Bench")
	elseif frame.TitleContainer and frame.TitleContainer.TitleText then frame.TitleContainer.TitleText:SetText("Macro Bench")
	else
		local t = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOP", 0, -12)
		t:SetText("Macro Bench")
	end
	if frame.SetPortraitToAsset then frame:SetPortraitToAsset(ICON)
	elseif frame.portrait and SetPortraitToTexture then SetPortraitToTexture(frame.portrait, ICON)
	elseif frame.PortraitContainer and frame.PortraitContainer.portrait then frame.PortraitContainer.portrait:SetTexture(ICON) end

	if not frameTemplate or frameTemplate == "BackdropTemplate" then
		if frame.SetBackdrop then
			frame:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
		end
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)
	end

	-- Up beside the close button, where a question mark belongs.
	-- Built the way Aura Ledger builds its own, which is known to come out visible on this client:
	-- a plain button that takes its strata and its level from the close button beside it rather than
	-- from the window, and that wears the client's own red button art, with a bordered box and then
	-- a plain fill as fallbacks. A templated button parented to the window went behind the border.
	local help = CreateFrame("Button", nil, frame)
	help:SetSize(24, 22)
	if frame.CloseButton then
		help:SetPoint("RIGHT", frame.CloseButton, "LEFT", 0, 0)
	else
		help:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -2)
	end
	local plate = "none"
	for _, atlas in ipairs({ "RedButton", "UI-RedButton" }) do
		if HasAtlas(atlas) and help.SetNormalAtlas then
			help:SetNormalAtlas(atlas)
			if HasAtlas(atlas .. "-Pressed") and help.SetPushedAtlas then help:SetPushedAtlas(atlas .. "-Pressed") end
			plate = atlas
			break
		end
	end
	if plate == "none" then
		local okb, box = pcall(CreateFrame, "Frame", nil, help, "BackdropTemplate")
		if okb and box and box.SetBackdrop then
			box:SetPoint("TOPLEFT", 1, -1)
			box:SetPoint("BOTTOMRIGHT", -1, 1)
			box:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 8, edgeSize = 8,
				insets = { left = 2, right = 2, top = 2, bottom = 2 },
			})
			box:SetBackdropColor(0.35, 0.05, 0.05, 1)
			box:SetBackdropBorderColor(1, 0.82, 0)
			plate = "bordered box"
		else
			local fill = help:CreateTexture(nil, "BACKGROUND")
			fill:SetPoint("TOPLEFT", 1, -1)
			fill:SetPoint("BOTTOMRIGHT", -1, 1)
			fill:SetColorTexture(0.35, 0.05, 0.05, 1)
			plate = "plain fill"
		end
	end
	ns.report["help button plate"] = plate
	local qmark = help:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	qmark:SetPoint("CENTER")
	qmark:SetText("?")
	qmark:SetTextColor(1, 0.92, 0.4)
	qmark:SetShadowColor(0, 0, 0, 1)
	qmark:SetShadowOffset(1, -1)
	if HasAtlas("RedButton-Highlight") and help.SetHighlightAtlas then
		help:SetHighlightAtlas("RedButton-Highlight")
	else
		help:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	end
	help:SetScript("OnClick", function() ns.Tutorial:Toggle() end)
	help:SetScript("OnEnter", function(self)
		TextTooltip(self, "Tutorials", "Five macros built a step at a time, on this bench, with your own spells. It can be left at any point, and this button brings it back.")
	end)
	help:SetScript("OnLeave", HideTooltip)
	UI.corners[#UI.corners + 1] = help
	UI.focus.help = help

	local hasBand = frameTemplate == "ButtonFrameTemplate"
	body = CreateFrame("Frame", nil, frame)
	if frame.Inset then
		body:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 0, hasBand and 0 or -30)
		body:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", 0, hasBand and 0 or 24)
	else
		body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -64)
		body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 36)
	end

end

local function BuildBook()
	-- ---- The book -------------------------------------------------
	bookPane = Pane(body, "Templates and parts", 2, BOOK_W + 2, 42)
	local searchLabel = bookPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	searchLabel:SetPoint("TOPLEFT", 8, -26)
	searchLabel:SetText("Search")
	local searchBox = CreateFrame("EditBox", nil, bookPane, "InputBoxTemplate")
	searchBox:SetSize(BOOK_W - 86, 20)
	searchBox:SetPoint("TOPLEFT", searchLabel, "TOPRIGHT", 14, 4)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnTextChanged", function(self, userInput)
		if not userInput then return end
		book.search = self:GetText()
		UI:RefreshBook()
	end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		book.search = ""
		self:ClearFocus()
		UI:RefreshBook()
	end)
	searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	-- The nine classes are a row of icons inside the Classes chapter rather than nine tabs. The band
	-- is only as tall as it needs to be, so every other chapter starts right under the search box.
	bookTop = CreateFrame("Frame", nil, bookPane)
	bookTop:SetPoint("TOPLEFT", bookPane, "TOPLEFT", 6, -48)
	bookTop:SetPoint("RIGHT", bookPane, "RIGHT", -8, 0)
	bookTop:SetHeight(1)
	classButtons = {}
	for index, token in ipairs(T.ClassOrder()) do
		local b = CreateFrame("CheckButton", nil, bookTop)
		b:SetSize(26, 26)
		b:SetPoint("TOPLEFT", (index - 1) * 30, 0)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token] then
			icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
			local c = CLASS_ICON_TCOORDS[token]
			icon:SetTexCoord(c[1], c[2], c[3], c[4])
		else
			icon:SetTexture(ns.QUESTION)
		end
		b.outline = Outline(b)
		b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		b.token = token
		b:SetScript("OnClick", function(self)
			book.class = self.token
			ns.db.lastClass = self.token
			UI:RefreshBook()
		end)
		b:SetScript("OnEnter", function(self)
			TextTooltip(self, T.Label(self.token), format("%d macros to start from.", #(T[self.token] or {})))
		end)
		b:SetScript("OnLeave", HideTooltip)
		b:Hide()
		classButtons[#classButtons + 1] = b
	end

	bookList = CreateList(bookPane, BookRowHeight, CreateBookRow, UpdateBookRow)
	bookList.frame:SetPoint("TOPLEFT", bookTop, "BOTTOMLEFT", -2, -4)
	bookList.frame:SetPoint("BOTTOMRIGHT", bookPane, "BOTTOMRIGHT", -8, 4)

	-- The parts chapter has its own scroll, because the blocks flow across the page rather than
	-- sitting in rows of one.
	partsScroll = TryCreateFrame("ScrollFrame", nil, bookPane, {
		{ "MacroBenchScrollFrameTemplate" }, { "UIPanelScrollFrameTemplate" },
	})
	partsScroll:SetPoint("TOPLEFT", bookTop, "BOTTOMLEFT", -2, -4)
	partsScroll:SetPoint("BOTTOMRIGHT", bookPane, "BOTTOMRIGHT", -8, 4)
	partsContent = CreateFrame("Frame", nil, partsScroll)
	partsContent:SetSize(10, 10)
	partsScroll:SetScrollChild(partsContent)
	partsScroll:EnableMouseWheel(true)
	partsScroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = max(0, partsContent:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * 42)))
	end)
	partsScroll:Hide()
	UI.tabs = {}
	for index, token in ipairs(T.Order()) do
		local tab = CreateBookTab(body, bookPane, token, index)
		UI.tabs[#UI.tabs + 1] = tab
		UI.focus["tab:" .. token] = tab
	end

end

local function BuildChain()
	-- ---- The chain ------------------------------------------------
	chainPane = Pane(body, "The macro", BENCH_L, nil, 2, 398)

	-- The macro text and the check live in windows of their own, opened from here.
	local checkButton = MakeButton(chainPane, "Check", 70,
		"Everything the check found, worst first. Click a finding to jump to the line it is about.")
	checkButton:SetHeight(18)
	checkButton:SetPoint("TOPRIGHT", chainPane, "TOPRIGHT", -6, -1)
	checkButton:SetScript("OnClick", function() UI:ToggleWindow(checkWindow) end)
	local textButton = MakeButton(chainPane, "Macro text", 84,
		"The macro as text, editable. Type in it and the chain follows; change the chain and it rewrites itself.")
	textButton:SetHeight(18)
	textButton:SetPoint("RIGHT", checkButton, "LEFT", -4, 0)
	textButton:SetScript("OnClick", function() UI:ToggleWindow(textWindow) end)
	-- The same tutorials as the ? in the title bar, somewhere nothing can draw over them.
	local tutorialButton = MakeButton(chainPane, "Tutorial", 72,
		"Five macros built a step at a time, on this bench, with your own spells.")
	tutorialButton:SetHeight(18)
	tutorialButton:SetPoint("RIGHT", textButton, "LEFT", -4, 0)
	tutorialButton:SetScript("OnClick", function() ns.Tutorial:Toggle() end)
	chainPane.note:ClearAllPoints()
	chainPane.note:SetPoint("RIGHT", tutorialButton, "LEFT", -8, 0)

	statusText = chainPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statusText:SetPoint("TOPLEFT", 8, -26)
	statusText:SetPoint("RIGHT", -8, 0)
	statusText:SetJustifyH("LEFT")
	statusText:SetMaxLines(1)

	chainScroll = TryCreateFrame("ScrollFrame", nil, chainPane, {
		{ "MacroBenchScrollFrameTemplate" }, { "UIPanelScrollFrameTemplate" },
	})
	chainScroll:SetPoint("TOPLEFT", chainPane, "TOPLEFT", 4, -44)
	chainScroll:SetPoint("BOTTOMRIGHT", chainPane, "BOTTOMRIGHT", -8, 4)
	chainContent = CreateFrame("Frame", nil, chainScroll)
	chainContent:SetSize(10, 10)
	chainScroll:SetScrollChild(chainContent)
	linkHost = CreateFrame("Frame", nil, chainContent)
	linkHost:SetAllPoints()
	linkHost:SetFrameLevel(chainContent:GetFrameLevel() + 4)
	chainScroll:EnableMouseWheel(true)
	chainScroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = max(0, chainContent:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * 40)))
	end)
	chainScroll:EnableMouse(true)
	chainScroll:SetScript("OnReceiveDrag", function() UI:DropOnLine(nil) end)
	chainScroll:SetScript("OnMouseUp", function() UI:DropOnLine(nil) end)

	UI.focus.chain = chainScroll
	chainEmpty = chainPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	chainEmpty:SetPoint("TOPLEFT", chainScroll, "TOPLEFT", 14, -14)
	chainEmpty:SetPoint("RIGHT", chainScroll, "RIGHT", -14, 0)
	chainEmpty:SetJustifyH("LEFT")
	chainEmpty:SetText("Nothing on the bench yet.\n\n1. Drag an action in from the left — Cast, Use item, Target — or drop a spell straight out of your spellbook.\n2. Drag a Modifier, Target filter or My state block onto that line to say when it runs.\n3. Click any part to set it up down here.\n4. Name it at the bottom and save it to a macro slot.")

end

local function BuildPart()
	-- ---- The part being worked on ----------------------------------
	-- The header is three bands that must not run into each other: the buttons and the title on the
	-- first, the hint on the second, the editor below both. The editor starts under the deepest of
	-- them, which is the icon.
	partPane = Pane(body, "The part you are working on", BENCH_L, nil, 404, 212)
	partIcon = TrimIcon(partPane:CreateTexture(nil, "ARTWORK"))
	partIcon:SetSize(24, 24)
	partIcon:SetPoint("TOPLEFT", 10, -28)
	partTitle = partPane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	partTitle:SetPoint("TOPLEFT", 44, -30)
	partTitle:SetPoint("RIGHT", partPane, "RIGHT", -372, 0)
	partTitle:SetJustifyH("LEFT")
	partTitle:SetMaxLines(1)
	partHint = partPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	partHint:SetPoint("TOPLEFT", 44, -52)
	partHint:SetPoint("RIGHT", partPane, "RIGHT", -12, 0)
	partHint:SetJustifyH("LEFT")
	partHint:SetMaxLines(1)
	partEmpty = partPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	partEmpty:SetPoint("TOPLEFT", 12, -56)
	partEmpty:SetText("Click any part of the chain above and it opens here.")

	partButtons.remove = MakeButton(partPane, "Take it out", 90, "Takes this part out. Right-clicking it in the chain does the same.")
	partButtons.remove:SetPoint("TOPRIGHT", partPane, "TOPRIGHT", -10, -26)
	partButtons.remove:SetScript("OnClick", function() UI:RemovePart(UI.sel) end)
	partButtons.copy = MakeButton(partPane, "Duplicate line", 100, "Puts a copy of this whole line straight after it.")
	partButtons.copy:SetPoint("RIGHT", partButtons.remove, "LEFT", -4, 0)
	partButtons.copy:SetScript("OnClick", function()
		if UI.sel then UI:DuplicateBlock(UI.sel.block) end
	end)
	partButtons.up = MakeButton(partPane, "Move up", 74, "Moves this line one earlier in the macro.")
	partButtons.up:SetPoint("RIGHT", partButtons.copy, "LEFT", -4, 0)
	partButtons.up:SetScript("OnClick", function()
		if UI.sel and UI.sel.block > 1 then UI:MoveBlock(UI.sel.block, UI.sel.block - 1) end
	end)
	partButtons.down = MakeButton(partPane, "Move down", 82, "Moves this line one later in the macro.")
	partButtons.down:SetPoint("RIGHT", partButtons.up, "LEFT", -4, 0)
	partButtons.down:SetScript("OnClick", function()
		if UI.sel then UI:MoveBlock(UI.sel.block, UI.sel.block + 2) end
	end)

	-- A line between the header and the editor, so the two bands cannot be read as one.
	local partRule = partPane:CreateTexture(nil, "ARTWORK")
	partRule:SetPoint("TOPLEFT", partPane, "TOPLEFT", 10, -68)
	partRule:SetPoint("TOPRIGHT", partPane, "TOPRIGHT", -10, -68)
	partRule:SetHeight(1)
	partRule:SetColorTexture(0.35, 0.32, 0.25, 0.5)

	-- The editors live in a scroll of their own: the state block has every condition the game has
	-- in it, which is taller than the panel, and the rest are shorter than it.
	partScroll = TryCreateFrame("ScrollFrame", nil, partPane, {
		{ "MacroBenchScrollFrameTemplate" }, { "UIPanelScrollFrameTemplate" },
	})
	partScroll:SetPoint("TOPLEFT", partPane, "TOPLEFT", 10, -72)
	partScroll:SetPoint("BOTTOMRIGHT", partPane, "BOTTOMRIGHT", -10, 6)
	partContent = CreateFrame("Frame", nil, partScroll)
	partContent:SetSize(10, 10)
	partScroll:SetScrollChild(partContent)
	partScroll:EnableMouseWheel(true)
	partScroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = max(0, partContent:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(min(maxScroll, max(0, self:GetVerticalScroll() - delta * 30)))
	end)

	editors = CreateEditors(partContent, partScroll)
	UI.focus.panel = partPane

end

-- A window of its own: the macro text and the check are not needed at every moment, and the room
-- they took is worth more to the chain. Both are opened from the buttons on the macro's header.
local function CreateWindow(globalName, title, w, h)
	local f, template = TryCreateFrame("Frame", globalName, UIParent, {
		{ "BasicFrameTemplateWithInset", function(x) return x.Inset ~= nil end },
		{ "BackdropTemplate" },
	})
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	if f.SetToplevel then f:SetToplevel(true) end
	f:SetScript("OnMouseDown", function(self) if self.Raise then self:Raise() end end)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if f.SetTitle then f:SetTitle(title)
	elseif f.TitleText then f.TitleText:SetText(title)
	else
		local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOP", 0, -10)
		t:SetText(title)
	end
	if not template or template == "BackdropTemplate" then
		if f.SetBackdrop then
			f:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
		end
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)
	end
	f.body = CreateFrame("Frame", nil, f)
	if f.Inset then
		f.body:SetPoint("TOPLEFT", f.Inset, "TOPLEFT", 4, -4)
		f.body:SetPoint("BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT", -4, 4)
	else
		f.body:SetPoint("TOPLEFT", 14, -34)
		f.body:SetPoint("BOTTOMRIGHT", -14, 14)
	end
	f:Hide()
	tinsert(UISpecialFrames, globalName)
	return f
end

local function BuildTextAndCheck()
	-- ---- The macro text, in a window of its own --------------------
	textWindow = CreateWindow("MacroBenchTextFrame", "The macro text", 560, 280)
	local pane = textWindow.body
	charCount = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	charCount:SetPoint("TOPRIGHT", -8, -2)
	local textHint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	textHint:SetPoint("TOPLEFT", 8, -2)
	textHint:SetPoint("RIGHT", charCount, "LEFT", -8, 0)
	textHint:SetJustifyH("LEFT")
	textHint:SetText("Type here and the chain follows. Either side is the macro.")

	textScroll = TryCreateFrame("ScrollFrame", nil, pane, {
		{ "MacroBenchScrollFrameTemplate" }, { "UIPanelScrollFrameTemplate" },
	})
	textScroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -22)
	textScroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 6)
	local textBg = CreateFrame("Frame", nil, pane)
	textBg:SetPoint("TOPLEFT", textScroll, "TOPLEFT", -4, 4)
	textBg:SetPoint("BOTTOMRIGHT", textScroll, "BOTTOMRIGHT", 4, -4)
	textBg:SetFrameLevel(max(0, textScroll:GetFrameLevel() - 1))
	Plate(textBg, 0, 0, 0, 0.6)

	textBox = CreateFrame("EditBox", nil, textScroll)
	textBox:SetMultiLine(true)
	textBox:SetAutoFocus(false)
	textBox:SetMaxLetters(1024)
	textBox:SetFontObject(ChatFontNormal or GameFontHighlight)
	textBox:SetWidth(514)
	textBox:SetHeight(200)
	textBox:SetTextInsets(4, 4, 2, 2)
	textScroll:SetScrollChild(textBox)
	textBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then UI:TextEdited(self:GetText()) end
		if type(ScrollingEdit_OnTextChanged) == "function" then pcall(ScrollingEdit_OnTextChanged, self, textScroll) end
	end)
	textBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
		if type(ScrollingEdit_OnCursorChanged) == "function" then pcall(ScrollingEdit_OnCursorChanged, self, x, y, w, h) end
	end)
	textBox:SetScript("OnUpdate", function(self, elapsed)
		if type(ScrollingEdit_OnUpdate) == "function" then pcall(ScrollingEdit_OnUpdate, self, elapsed, textScroll) end
	end)
	textBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	textBox:SetScript("OnEditFocusLost", function() UI:Refresh() end)

	-- ---- What the check found, in a window of its own ---------------
	checkWindow = CreateWindow("MacroBenchCheckFrame", "What the check found", 560, 340)
	checkNote = checkWindow.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	checkNote:SetPoint("TOPLEFT", 8, -2)
	checkNote:SetPoint("RIGHT", -8, 0)
	checkNote:SetJustifyH("LEFT")
	checkList = CreateList(checkWindow.body, CheckRowHeight, CreateCheckRow, UpdateCheckRow)
	checkList.frame:SetPoint("TOPLEFT", checkWindow.body, "TOPLEFT", 4, -20)
	checkList.frame:SetPoint("BOTTOMRIGHT", checkWindow.body, "BOTTOMRIGHT", -8, 4)
end

-- Opening one of them puts it beside the bench the first time, and where you left it after that.
function UI:ToggleWindow(w)
	if not w then return end
	if w:IsShown() then
		w:Hide()
		return
	end
	if not w.placed then
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
		w.placed = true
	end
	w:Show()
	if w == checkWindow then self.checkSeen = true end
	self:Refresh()
end

local function BuildFooter()
	-- ---- The footer ------------------------------------------------
	local footer = CreateFrame("Frame", nil, body)
	footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", BENCH_L, 2)
	footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -2, 2)
	footer:SetHeight(38)
	Plate(footer, 0, 0, 0, 0.42)

	iconButton = CreateFrame("Button", nil, footer)
	iconButton:SetSize(28, 28)
	iconButton:SetPoint("LEFT", 8, 0)
	iconButton.icon = TrimIcon(iconButton:CreateTexture(nil, "ARTWORK"))
	iconButton.icon:SetAllPoints()
	iconButton:SetScript("OnEnter", function(self)
		TextTooltip(self, "The icon", "Taken from the first spell or item the macro names, the way the game does it. Click for the plain question mark instead.")
	end)
	iconButton:SetScript("OnLeave", HideTooltip)
	iconButton:SetScript("OnClick", function()
		ns.bench.plainIcon = not ns.bench.plainIcon
		ns.bench.dirty = true
		UI:RefreshFooter()
	end)

	local nameLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameLabel:SetPoint("LEFT", iconButton, "RIGHT", 8, 0)
	nameLabel:SetText("Name")
	nameBox = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
	nameBox:SetSize(140, 20)
	nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 12, 0)
	nameBox:SetAutoFocus(false)
	nameBox:SetScript("OnTextChanged", function(self, userInput)
		if not userInput then return end
		ns.bench.name = self:GetText()
		ns.bench.dirty = true
		UI:RefreshFooter()
	end)
	nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	UI.focus.name = nameBox

	perCharCheck = CreateCheck(footer)
	perCharCheck:SetSize(22, 22)
	perCharCheck:SetPoint("LEFT", nameBox, "RIGHT", 12, 0)
	local perCharLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	perCharLabel:SetPoint("LEFT", perCharCheck, "RIGHT", 2, 0)
	perCharLabel:SetText("this character")
	perCharCheck:SetScript("OnClick", function(self)
		ns.bench.perChar = self:GetChecked() and true or false
		ns.bench.dirty = true
		UI:RefreshFooter()
	end)
	perCharCheck:SetScript("OnEnter", function(self)
		local a, c = ns.MacroCaps()
		TextTooltip(self, "Which set of slots", format("The account shares %d macro slots; each character has %d of its own.", a, c))
	end)
	perCharCheck:SetScript("OnLeave", HideTooltip)

	local saveButton = MakeButton(footer, "Save to a macro slot", 140,
		"Writes it into one of the game's own macro slots, which is what makes it a real macro you can put on a bar. Not allowed during a fight; it waits.")
	saveButton:SetPoint("RIGHT", -8, 0)
	saveButton:SetScript("OnClick", function() UI:SaveToSlot() end)
	UI.focus.save = saveButton
	local cursorButton = MakeButton(footer, "Put on cursor", 104,
		"Picks the saved macro up so you can drop it on an action bar. The drop has to be your own click: no addon may put something on a bar for you.")
	cursorButton:SetPoint("RIGHT", saveButton, "LEFT", -5, 0)
	cursorButton:SetScript("OnClick", function()
		local ok, err = ns.PickupBench()
		if not ok then ns.Print(err) end
	end)
	local keepButton = MakeButton(footer, "Keep here", 84,
		"Keeps it in this addon's own library, where there is no limit on how many you have. It does not touch your macro slots.")
	keepButton:SetPoint("RIGHT", cursorButton, "LEFT", -5, 0)
	keepButton:SetScript("OnClick", function() UI:Keep() end)
	local newButton = MakeButton(footer, "New macro", 92, "Clears the bench and starts again.")
	UI.focus.new = newButton
	newButton:SetPoint("RIGHT", keepButton, "LEFT", -5, 0)
	newButton:SetScript("OnClick", function() UI:NewMacro() end)

	-- How the macro stands, at a glance, without opening the check. It goes in the grey band the
	-- window's own art puts along the bottom, where it has the whole width to itself rather than
	-- whatever is left between the tick box and the buttons. That band is outside the inset, so it
	-- is parented to the window and lifted above the border, which is a frame of its own here.
	checkStatus = CreateFrame("Button", nil, frame)
	checkStatus:SetHeight(18)
	checkStatus:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 5)
	checkStatus:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 5)
	UI.corners[#UI.corners + 1] = checkStatus
	checkStatus.text = checkStatus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	checkStatus.text:SetAllPoints()
	checkStatus.text:SetJustifyH("LEFT")
	checkStatus.text:SetMaxLines(1)
	checkStatus:SetScript("OnClick", function() UI:ToggleWindow(checkWindow) end)
	checkStatus:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("What the check found", 1, 0.82, 0)
		local shown = 0
		for _, f in ipairs(findings) do
			GameTooltip:AddLine(V.LevelColor(f.level) .. (f.line and ("line " .. f.line .. ": ") or "") .. f.text .. "|r", 1, 1, 1, true)
			shown = shown + 1
			if shown == 5 then break end
		end
		if #findings == 0 then GameTooltip:AddLine("Nothing wrong with it.", 0.5, 1, 0.5) end
		if #findings > shown then GameTooltip:AddLine(format("and %d more.", #findings - shown), 0.6, 0.6, 0.6) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click to open the whole list.", 0.5, 0.8, 1)
		GameTooltip:Show()
	end)
	checkStatus:SetScript("OnLeave", HideTooltip)
	UI.focus.check = checkStatus

end

local function Build()
	BuildFrame()
	BuildBook()
	BuildChain()
	BuildPart()
	BuildTextAndCheck()
	BuildFooter()
	local ticker = CreateFrame("Frame", nil, frame)
	ticker.elapsed = 0
	ticker:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed < 0.25 then return end
		self.elapsed = 0
		UI:Tick()
	end)

	UI:SyncTabs()
	UI:LiftCorners()
	-- The book is drawn here rather than only from Refresh, which redraws it for the My macros
	-- chapter alone: on the first open every other chapter was left as it was built, which is to
	-- say empty, with the class band showing over it.
	UI:RefreshBook()
	UI:Refresh()
end

-- ------------------------------------------------------------------
-- Minimap button
-- ------------------------------------------------------------------
local function PlaceMinimapButton()
	local b = UI.minimapButton
	if not b then return end
	local angle = math.rad(ns.db.minimapAngle or 200)
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
end

function UI:UpdateMinimapButton()
	if not ns.db.minimap then
		if self.minimapButton then self.minimapButton:Hide() end
		return
	end
	if not self.minimapButton then
		local b = CreateFrame("Button", "MacroBenchMinimapButton", Minimap)
		b:SetSize(31, 31)
		b:SetFrameStrata("MEDIUM")
		local icon = b:CreateTexture(nil, "BACKGROUND")
		icon:SetSize(20, 20)
		icon:SetPoint("CENTER", 0, 1)
		icon:SetTexture(ICON)
		TrimIcon(icon)
		local border = b:CreateTexture(nil, "OVERLAY")
		border:SetSize(53, 53)
		border:SetPoint("TOPLEFT")
		border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		b:RegisterForDrag("LeftButton")
		b:SetScript("OnDragStart", function(self)
			self:SetScript("OnUpdate", function()
				local mx, my = Minimap:GetCenter()
				local scale = Minimap:GetEffectiveScale()
				local cx, cy = GetCursorPosition()
				ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
				PlaceMinimapButton()
			end)
		end)
		b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, button)
			if button == "RightButton" then ns.Tutorial:Toggle() else UI:Toggle() end
		end)
		b:SetScript("OnEnter", function(self)
			TextTooltip(self, "Macro Bench", "Build a macro from blocks and watch the text write itself.", "Left-click to open. Right-click for the tutorials.")
		end)
		b:SetScript("OnLeave", HideTooltip)
		self.minimapButton = b
	end
	self.minimapButton:Show()
	PlaceMinimapButton()
end

-- ------------------------------------------------------------------
-- Showing
-- ------------------------------------------------------------------
function UI:Show()
	if not frame then Build() end
	if ns.db.window and ns.db.window.x then
		frame:ClearAllPoints()
		local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.window.x / s, ns.db.window.y / s)
	end
	frame:Show()
	self:Refresh()
end

function UI:Hide()
	if frame then frame:Hide() end
end

function UI:Toggle()
	if frame and frame:IsShown() then self:Hide() else self:Show() end
end

function UI:Init()
	G, V, T = ns.Grammar, ns.Validate, ns.Templates
	book.tab = ns.db.lastTab or "BLOCKS"
	book.class = ns.db.lastClass or select(2, UnitClass("player")) or "WARRIOR"
	self:UpdateMinimapButton()
end
