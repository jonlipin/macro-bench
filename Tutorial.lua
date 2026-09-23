-- Macro Bench tutorials: a few macros built a step at a time, in your own window, on your own
-- character, with your own spells. Not a video and not a wall of text — each step asks for one
-- thing and watches the bench until it is there, then moves on by itself.
--
-- A step is done when its "done" says so. That is one of:
--   a string   a pattern looked for in the macro text, case ignored
--   a table    several of those, all of which have to be there
--   a function asked with ns, for the few steps the text cannot answer
-- The macro text is what every step reads, because the text is what is real: a step passes the same
-- way whether you dragged a block, clicked a button, or typed it yourself.

local ADDON, ns = ...
local Tut = {}
ns.Tutorial = Tut

local format, strlower = string.format, string.lower

local function Text() return strlower(ns.bench.text or "") end
local function Saved() return ns.bench.slot ~= nil end
local function Lines(cmd)
	local n = 0
	for _, b in ipairs(ns.bench.blocks or {}) do
		if b.kind == "cmd" and b.cmd == cmd then n = n + 1 end
	end
	return n
end

-- ------------------------------------------------------------------
-- The lessons
-- ------------------------------------------------------------------
Tut.LESSONS = {
	{
		id = "mouseover",
		name = "Aim a spell at whoever you point at",
		why = "The mouseover macro. One key that heals, or hits, whatever is under your mouse without ever changing target.",
		steps = {
			{ focus = "new", text = "Click |cffffd100New macro|r at the bottom of the window, so we start with an empty bench.",
			  done = function() return ns.BenchLength() == 0 end },
			{ focus = "palette:Cast", text = "In the |cffffd100Parts|r chapter on the left, find the gold |cffffd100Cast|r block and click it. It lands at the end of the chain.",
			  hint = "Dragging it onto the chain does the same thing, and lets you choose where it goes.",
			  done = "^/cast" },
			{ focus = "part", text = "The block is open in the panel underneath. Click into its box and type a spell you actually have — a heal if you have one, otherwise anything.",
			  hint = "Under the box it tells you whether the game recognised the name, and hovering that shows the spell's own tooltip.",
			  done = "^/cast%s+%a" },
			{ focus = "palette:Target filter", text = "Now click the blue |cffffd100Target filter|r block in the parts list. It lands on the line aimed at your mouseover.",
			  hint = "That is [@mouseover] in the macro text.",
			  done = "@mouseover" },
			{ focus = "part", text = "In the panel, tick |cffffd100Friendly|r and |cffffd100Alive|r under \"and it is\", so the line cannot fire on an enemy or on a corpse.",
			  hint = "Swap Friendly for An enemy if you are building a damage macro instead.",
			  done = { "@mouseover", "help", "nodead" } },
			{ focus = "chain", text = "Click the |cffffd100+|r block at the end of the line and choose |cffffd100Or these instead|r. That is a second set of brackets: if there is no mouseover, the game tries the next set.",
			  done = "%]%s*%[" },
			{ focus = "part", text = "Fill that second set in: give it a |cffffd100Target filter|r aimed at |cffffd100Target|r, friendly and alive. Now it heals your mouseover, or your target if there is none.",
			  done = { "@mouseover", "@target" } },
			{ text = "Give the macro a name at the bottom and click |cffffd100Save to a macro slot|r. Then \"Put on cursor\" and drop it on a bar.",
			  focus = "save", done = Saved },
		},
	},
	{
		id = "modifier",
		name = "Two spells on one key",
		why = "The plain spell on its own, another while you hold shift. The pattern behind half of everyone's action bar.",
		steps = {
			{ focus = "new", text = "Click |cffffd100New macro|r to start clean.",
			  done = function() return ns.BenchLength() == 0 end },
			{ focus = "palette:Cast", text = "Click the |cffffd100Cast|r block in the parts list, then type the spell you press most often into its box.",
			  done = "^/cast%s+%a" },
			{ focus = "palette:Modifier", text = "Click the |cffffd100Modifier|r block in the parts list. It lands on the line set to shift.",
			  hint = "Three-way buttons: click Shift again and it asks for shift NOT being held.",
			  done = "mod:shift" },
			{ focus = "chain", text = "That is the shift spell. Now click the |cffffd100+|r block at the end of the line and choose |cffffd100Otherwise|r — the part after the semicolon, read when shift is not down.",
			  done = ";" },
			{ focus = "chain", text = "Click the new |cffffd100…|r block after \"otherwise\" and type the everyday spell into it.",
			  done = function()
				  local text = Text()
				  local after = text:match(";%s*(.+)$")
				  return after ~= nil and after:match("%a") ~= nil
			  end },
			{ focus = "palette:#showtooltip", text = "Add a |cffffd100#showtooltip|r block so the button wears the right icon and cooldown. It has to be the first line — drag it to the top if it is not.",
			  hint = "The check will tell you if it is in the wrong place.",
			  done = "^#showtooltip" },
			{ text = "Name it at the bottom and |cffffd100Save to a macro slot|r.",
			  focus = "save", done = Saved },
		},
	},
	{
		id = "trinket",
		name = "A trinket and a spell on one press",
		why = "Several lines on one key, and the rule that decides which of them can fire together.",
		steps = {
			{ focus = "new", text = "Click |cffffd100New macro|r to start clean.",
			  done = function() return ns.BenchLength() == 0 end },
			{ focus = "palette:Use trinket", text = "Click the |cffffd100Use trinket|r block in the parts list. It arrives as /use 13, which is your top trinket slot.",
			  hint = "13 is the top trinket, 14 the bottom one, 16 your main hand. Naming slots rather than items means the macro keeps working when the gear changes.",
			  done = "/use%s+13" },
			{ focus = "palette:Use item", text = "Add a second |cffffd100Use item|r block and put |cffffd10014|r in its box, for the other trinket.",
			  done = { "/use%s+13", "/use%s+14" } },
			{ focus = "palette:Cast", text = "Now add a |cffffd100Cast|r block and name your burst spell. Two /use lines are fine together; two /cast lines are not, and the check would tell you so.",
			  done = "^/cast%s+%a" },
			{ focus = "check", text = "Look at the footer: it says how the check stands. Click it to see everything it found.",
			  hint = "A note about a spell you do not have is fine. An error in red is worth fixing before you save.",
			  done = function() return ns.UI and ns.UI.checkSeen == true end },
			{ text = "Name it and |cffffd100Save to a macro slot|r.",
			  focus = "save", done = Saved },
		},
	},
	{
		id = "sequence",
		name = "A list of spells, one per press",
		why = "Castsequence: openers, totem sets, anything with an order. And what makes it start over.",
		steps = {
			{ focus = "new", text = "Click |cffffd100New macro|r to start clean.",
			  done = function() return ns.BenchLength() == 0 end },
			{ focus = "palette:Cast in order", text = "Click |cffffd100Cast in order|r in the parts list. It arrives saying reset=combat.",
			  done = "^/castsequence" },
			{ focus = "part", text = "Click its box and put two spells after the reset, separated by a comma: |cffffd100reset=combat Spell One, Spell Two|r.",
			  hint = "Each press casts the next one. It goes back to the first when you leave combat.",
			  done = "reset=%S+%s+.-,%s*%a" },
			{ focus = "part", text = "Try |cffffd100reset=target|r instead of reset=combat, so changing target starts the list again.",
			  hint = "A number works too: reset=5 starts over after five seconds. Join several with a slash.",
			  done = "reset=target" },
			{ focus = "palette:#showtooltip", text = "Add a |cffffd100#showtooltip|r block at the top so the button shows whichever spell comes next.",
			  done = "^#showtooltip" },
			{ text = "Name it and |cffffd100Save to a macro slot|r.",
			  focus = "save", done = Saved },
		},
	},
	{
		id = "state",
		name = "A line that only runs sometimes",
		why = "Conditions about you rather than your target: in combat, in a form, which pet is out.",
		steps = {
			{ focus = "new", text = "Click |cffffd100New macro|r to start clean.",
			  done = function() return ns.BenchLength() == 0 end },
			{ focus = "palette:Cast", text = "Add a |cffffd100Cast|r block and name a spell.",
			  done = "^/cast%s+%a" },
			{ focus = "palette:My state", text = "Click the |cffffd100My state|r block in the parts list. It lands set to \"in combat\".",
			  done = "combat" },
			{ focus = "part", text = "Open it and look: every condition the game has about you is in there. Click |cffffd100In combat|r twice, so it reads |cffff5050no|r — the line now only runs out of combat.",
			  hint = "Three-way buttons everywhere: not asked, must be true, must be false.",
			  done = "nocombat" },
			{ focus = "part", text = "Look at the right of the panel: it says what the line does |cffffd100as things stand|r, answered by the game itself. Step into combat and it changes.",
			  hint = "That is the client's own condition parser, not a guess.",
			  done = function() return true end },
			{ text = "Name it and |cffffd100Save to a macro slot|r, or start another tutorial.",
			  focus = "save", done = Saved },
		},
	},
}

-- ------------------------------------------------------------------
-- Is this step done?
-- ------------------------------------------------------------------
local function StepDone(step)
	local done = step.done
	if type(done) == "function" then
		local ok, result = pcall(done, ns)
		return ok and result and true or false
	end
	local text = Text()
	if type(done) == "string" then return text:find(strlower(done)) ~= nil end
	if type(done) == "table" then
		for _, pattern in ipairs(done) do
			if not text:find(strlower(pattern)) then return false end
		end
		return true
	end
	return false
end

function Tut:Lesson(id)
	for _, lesson in ipairs(self.LESSONS) do
		if lesson.id == id then return lesson end
	end
end

function Tut:Start(id)
	local lesson = self:Lesson(id)
	if not lesson then return end
	self.lesson, self.step = lesson, 1
	-- Skip anything already true, so starting a tutorial halfway through a macro is not a wall.
	while self.step < #lesson.steps and StepDone(lesson.steps[self.step]) do
		self.step = self.step + 1
	end
	ns.db.lastLesson = id
	self:Show()
	self:Refresh()
end

function Tut:Stop()
	self.lesson, self.step = nil, nil
	self:Refresh()
end

-- Called whenever the macro changes, and on a slow tick while the window is open.
function Tut:Check()
	if not self.lesson or not self.frame or not self.frame:IsShown() then return end
	local steps = self.lesson.steps
	local moved = false
	while self.step <= #steps and StepDone(steps[self.step]) do
		if self.step == #steps then
			self.step = #steps + 1
			moved = true
			break
		end
		self.step = self.step + 1
		moved = true
	end
	if moved then
		if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_SELECT then
			pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_SELECT)
		end
		self:Refresh()
	end
end

-- ------------------------------------------------------------------
-- The window
-- ------------------------------------------------------------------
local function TryCreateFrame(ftype, name, parent, candidates)
	for _, c in ipairs(candidates) do
		local ok, f = pcall(CreateFrame, ftype, name, parent, c[1])
		if ok and f and (not c[2] or c[2](f)) then return f, c[1] end
		if ok and f then f:Hide() end
	end
	return CreateFrame(ftype, name, parent), nil
end

local function Button(parent, text, width)
	local b = TryCreateFrame("Button", nil, parent, { { "UIPanelButtonTemplate" }, { "GameMenuButtonTemplate" } })
	b:SetSize(width or 100, 22)
	if b.SetText then b:SetText(text) end
	return b
end

-- A gold frame drawn round whatever the step is talking about, pulsing so the eye finds it. It is
-- anchored to that thing rather than placed, so it follows when the page is laid out again.
local function Glow()
	if Tut.glow then return Tut.glow end
	local g = CreateFrame("Frame", nil, UIParent)
	g:SetFrameStrata("FULLSCREEN_DIALOG")
	g.edges = {}
	for i = 1, 4 do
		local t = g:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 0.82, 0, 1)
		g.edges[i] = t
	end
	g.edges[1]:SetPoint("TOPLEFT")
	g.edges[1]:SetPoint("TOPRIGHT")
	g.edges[1]:SetHeight(2)
	g.edges[2]:SetPoint("BOTTOMLEFT")
	g.edges[2]:SetPoint("BOTTOMRIGHT")
	g.edges[2]:SetHeight(2)
	g.edges[3]:SetPoint("TOPLEFT")
	g.edges[3]:SetPoint("BOTTOMLEFT")
	g.edges[3]:SetWidth(2)
	g.edges[4]:SetPoint("TOPRIGHT")
	g.edges[4]:SetPoint("BOTTOMRIGHT")
	g.edges[4]:SetWidth(2)
	g:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		local a = 0.45 + 0.35 * math.sin(self.t * 3)
		for _, edge in ipairs(self.edges) do edge:SetAlpha(a) end
	end)
	g:Hide()
	Tut.glow = g
	return g
end

function Tut:PointAt(target)
	local g = Glow()
	local f = target and ns.UI and ns.UI.FocusFrame and ns.UI:FocusFrame(target)
	if not f or not f.IsVisible or not f:IsVisible() then
		g:Hide()
		return
	end
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
	g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
	g:Show()
end

function Tut:Build()
	local f, template = TryCreateFrame("Frame", "MacroBenchTutorialFrame", UIParent, {
		{ "BasicFrameTemplateWithInset", function(x) return x.Inset ~= nil end },
		{ "BackdropTemplate" },
	})
	f:SetSize(420, 360)
	f:SetPoint("CENTER", UIParent, "CENTER", 360, 0)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	if f.SetToplevel then f:SetToplevel(true) end
	f:SetScript("OnMouseDown", function(self) if self.Raise then self:Raise() end end)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if f.SetTitle then f:SetTitle("Macro Bench tutorials")
	elseif f.TitleText then f.TitleText:SetText("Macro Bench tutorials") end
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
	local body = CreateFrame("Frame", nil, f)
	if f.Inset then
		body:SetPoint("TOPLEFT", f.Inset, "TOPLEFT", 6, -6)
		body:SetPoint("BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT", -6, 6)
	else
		body:SetPoint("TOPLEFT", 16, -34)
		body:SetPoint("BOTTOMRIGHT", -16, 16)
	end
	f.body = body

	-- ---- the list of lessons ----------------------------------------
	local pick = CreateFrame("Frame", nil, body)
	pick:SetAllPoints()
	pick.intro = pick:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pick.intro:SetPoint("TOPLEFT", 4, -2)
	pick.intro:SetPoint("RIGHT", -4, 0)
	pick.intro:SetJustifyH("LEFT")
	pick.intro:SetText("Pick one. Each builds a real macro on the bench, a step at a time, with your own spells — and you can stop and carry on whenever you like.")
	pick.buttons = {}
	local y = -40
	for _, lesson in ipairs(self.LESSONS) do
		local b = CreateFrame("Button", nil, pick)
		b:SetPoint("TOPLEFT", 2, y)
		b:SetPoint("RIGHT", -2, 0)
		b:SetHeight(46)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.1, 0.1, 0.1, 0.6)
		b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		b.name:SetPoint("TOPLEFT", 8, -4)
		b.name:SetPoint("RIGHT", -8, 0)
		b.name:SetJustifyH("LEFT")
		b.name:SetText(lesson.name)
		b.why = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		b.why:SetPoint("TOPLEFT", 8, -20)
		b.why:SetPoint("RIGHT", -8, 0)
		b.why:SetJustifyH("LEFT")
		b.why:SetText(lesson.why)
		b.why:SetMaxLines(2)
		b.id = lesson.id
		b:SetScript("OnClick", function(self2) Tut:Start(self2.id) end)
		pick.buttons[#pick.buttons + 1] = b
		y = y - 50
	end
	f.pick = pick

	-- ---- one lesson, a step at a time --------------------------------
	local run = CreateFrame("Frame", nil, body)
	run:SetAllPoints()
	run.name = run:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	run.name:SetPoint("TOPLEFT", 4, -2)
	run.name:SetPoint("RIGHT", -4, 0)
	run.name:SetJustifyH("LEFT")
	run.count = run:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	run.count:SetPoint("TOPLEFT", 4, -22)
	run.step = run:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	run.step:SetPoint("TOPLEFT", 4, -46)
	run.step:SetPoint("RIGHT", -4, 0)
	run.step:SetJustifyH("LEFT")
	run.step:SetJustifyV("TOP")
	run.hint = run:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	run.hint:SetPoint("TOPLEFT", 4, -130)
	run.hint:SetPoint("RIGHT", -4, 0)
	run.hint:SetJustifyH("LEFT")
	run.hint:SetJustifyV("TOP")

	run.back = Button(run, "Back", 70)
	run.back:SetPoint("BOTTOMLEFT", 2, 2)
	run.back:SetScript("OnClick", function()
		Tut.step = math.max(1, (Tut.step or 1) - 1)
		Tut:Refresh()
	end)
	run.skip = Button(run, "Skip this step", 110)
	run.skip:SetPoint("LEFT", run.back, "RIGHT", 4, 0)
	run.skip:SetScript("OnClick", function()
		Tut.step = (Tut.step or 1) + 1
		Tut:Refresh()
	end)
	run.another = Button(run, "Another tutorial", 130)
	run.another:SetPoint("BOTTOMRIGHT", -2, 2)
	run.another:SetScript("OnClick", function() Tut:Stop() end)
	f.run = run

	local ticker = CreateFrame("Frame", nil, f)
	ticker.elapsed = 0
	ticker:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed < 0.4 then return end
		self.elapsed = 0
		Tut:Check()
		local lesson = Tut.lesson
		if lesson and Tut.step and lesson.steps[Tut.step] then Tut:PointAt(lesson.steps[Tut.step].focus) end
	end)

	f:HookScript("OnHide", function() if Tut.glow then Tut.glow:Hide() end end)
	f:Hide()
	tinsert(UISpecialFrames, "MacroBenchTutorialFrame")
	self.frame = f
	return f
end

function Tut:Refresh()
	local f = self.frame
	if not f then return end
	local lesson = self.lesson
	f.pick:SetShown(lesson == nil)
	f.run:SetShown(lesson ~= nil)
	if not lesson then
		self:PointAt(nil)
		return
	end
	local steps = lesson.steps
	f.run.name:SetText(lesson.name)
	if self.step > #steps then
		self:PointAt(nil)
		f.run.count:SetText("|cff40ff40Done.|r")
		f.run.step:SetText(format("That is the macro built. %s\n\nEverything you did here you can do again on your own: the blocks are the same blocks, and the text under them is the macro the game will keep.",
			ns.bench.slot and ("It is in macro slot " .. ns.bench.slot .. ".") or "Save it to a macro slot when you are happy with it."))
		f.run.hint:SetText("")
		f.run.back:Show()
		f.run.skip:Hide()
		return
	end
	local step = steps[self.step]
	f.run.count:SetText(format("Step %d of %d", self.step, #steps))
	f.run.step:SetText(step.text or "")
	f.run.hint:SetText(step.hint and ("|cff9dc8ff" .. step.hint .. "|r") or "")
	f.run.back:SetShown(self.step > 1)
	f.run.skip:Show()
	self:PointAt(step.focus)
end

function Tut:Show()
	if not self.frame then self:Build() end
	self.frame:Show()
	self:Refresh()
end

function Tut:Toggle()
	if not self.frame then self:Build() end
	if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
