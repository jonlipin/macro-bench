-- Macro Bench's pieces in the window styles. Styles.lua does the choosing and the drawing
-- (Blizzard, Dark, or EllesmereUI's look, picked under Settings > Look); this file says what
-- Macro Bench has to restyle. With the Blizzard look nothing here draws anything.
--
-- The bench is built the first time it is opened, which is mostly after the style is drawn, so
-- nearly everything arrives through the ns.Skin* calls UI.lua and Tutorial.lua make as they build.
-- Whatever is built before then waits in a list, and is done when a style is drawn: at login, or
-- the moment Dark is chosen. The list only ever holds frames the addon keeps for good anyway.
--
-- The blocks of the chain, the blocks in the parts list and the three-way condition buttons keep
-- their own colors and their own selection outlines: the color is what says which kind of part a
-- block is, and whether a condition is not asked, true or false. They take the style's font, hover
-- and X only.

local ADDON, ns = ...
local Styles = ns.Styles
local Try = Styles.Try
local UI = ns.UI

local waiting = {}
local borders = {} -- window -> the frames EllesmereUI laid over it for its border (Dark adds none)

local function IsTable(x) return type(x) == "table" end
local function S() return Styles.S end

-- Done now if a style is drawn, and kept until one is if not.
local function Skin(what, fn, f, extra)
	if not IsTable(f) then return end
	if S() then
		Try(what, fn, f, extra)
	else
		waiting[#waiting + 1] = { what, fn, f, extra }
	end
end

-- Every line of text in the style's font at its own size, and every scroll bar in the style's thin
-- strip, on a frame and on everything inside it.
local function Dress(f, depth)
	depth = depth or 0
	if depth > 16 then return end
	if IsTable(f.ScrollBar) and f.ScrollBar ~= f then S().ScrollBar(f.ScrollBar) end
	if f.GetRegions then
		for _, r in ipairs({ f:GetRegions() }) do
			if IsTable(r) and r.IsObjectType and r:IsObjectType("FontString") then S().Font(r) end
		end
	end
	if f.GetChildren then
		for _, child in ipairs({ f:GetChildren() }) do
			if IsTable(child) then Dress(child, depth + 1) end
		end
	end
end

-- The game's bevelled glow under the mouse gives way to a faint white wash.
local function FlatHover(button)
	local hl = button.GetHighlightTexture and button:GetHighlightTexture()
	if IsTable(hl) and hl.SetColorTexture then
		hl:SetColorTexture(1, 1, 1, 0.1)
		if hl.SetBlendMode then hl:SetBlendMode("BLEND") end
	end
end

local function RaiseAbove(button, parent)
	local level = parent:GetFrameLevel() or 1
	for _, child in ipairs({ parent:GetChildren() }) do
		if child ~= button then level = math.max(level, child:GetFrameLevel() or 0) end
	end
	button:SetFrameLevel(level + 1)
end

-- By key, then by the name the older templates give it.
local function Part(win, key)
	if IsTable(win[key]) then return win[key] end
	local name = win.GetName and win:GetName()
	if name and IsTable(_G[name .. key]) then return _G[name .. key] end
end

local function CloseOf(win)
	return Part(win, "CloseButton") or (IsTable(win.mbClose) and win.mbClose) or nil
end

-- The window backdrop and border, the way EllesmereUI does its own windows: no portrait, the title
-- in the middle of the title bar, and the close button back on top of the border, which EllesmereUI
-- lays over the whole window as a frame of its own. Dark draws on the window itself.
local function Shell(win, opts)
	local before = {}
	for _, child in ipairs({ win:GetChildren() }) do before[child] = true end
	S().Shell(win, opts)
	local added = {}
	for _, child in ipairs({ win:GetChildren() }) do
		if not before[child] then added[#added + 1] = child end
	end
	borders[win] = added

	if IsTable(win.Inset) then S().Inset(win.Inset) end
	if IsTable(win.Bg) and win.Bg.SetAlpha then win.Bg:SetAlpha(0) end
	if IsTable(win.PortraitContainer) then S().FadeRegions(win.PortraitContainer) end
	local title = (IsTable(win.TitleContainer) and IsTable(win.TitleContainer.TitleText) and win.TitleContainer.TitleText)
		or Part(win, "TitleText")
	if title and title.ClearAllPoints then
		title:ClearAllPoints()
		title:SetPoint("CENTER", win, "TOP", 0, -12)
		if title.SetJustifyH then title:SetJustifyH("CENTER") end
	end
	local close = CloseOf(win)
	if close then
		S().CloseButton(close)
		RaiseAbove(close, win)
	end
	Dress(win)
end

-- ---- pieces, as they are built ---------------------------------------------------------------

-- The client's own panel buttons: Save to a macro slot, Keep here, Take it out, and the rest.
function ns.SkinButton(b)
	Skin("button", function(button)
		S().Button(button)
		S().WhiteButtonLabel(button)
		local fs = button.GetFontString and button:GetFontString()
		if IsTable(fs) then S().Font(fs) end
	end, b)
end

-- The command buttons mark the line's own command in gold, by font object, on every redraw.
function ns.SkinCommandButton(b, on)
	if not S() then return end
	Try("command button", function()
		local fs = b.GetFontString and b:GetFontString()
		if not IsTable(fs) then return end
		S().Font(fs)
		if on then fs:SetTextColor(1, 0.82, 0) else S().White(fs) end
	end)
end

-- Words written on the page later: the headings in the parts list, and "when" and "and" between
-- the blocks of a line.
function ns.SkinText(fs)
	Skin("text", function(text) S().Font(text) end, fs)
end

function ns.SkinCheck(cb)
	Skin("tick box", function(box) S().Checkbox(box) end, cb)
end

function ns.SkinEditBox(box)
	Skin("text box", function(eb) S().EditBox(eb) end, box)
end

-- A pane keeps its title strip, darkened to the style's title bar, and its own icon and rule. The
-- style's panel goes on a frame of its own just under it, because S.Panel fades every texture on
-- the frame it is given, and EllesmereUI fades them again whenever it repaints its own windows.
-- inset: the darker fill, for the box the macro text is typed into.
function ns.SkinPanel(f, inset)
	Skin("pane", function(pane, darker)
		local under = CreateFrame("Frame", nil, pane)
		under:SetAllPoints()
		under:SetFrameLevel(pane:GetFrameLevel() or 1)
		S().Panel(under, darker and { inset = true } or nil)
		if IsTable(pane.plate) then pane.plate:SetAlpha(0) end
		if IsTable(pane.strip) then pane.strip:SetColorTexture(0, 0, 0, 0.5) end
	end, f, inset)
end

-- Everything the addon draws for itself: the blocks, the line plates, the condition buttons, the
-- rows of the lists, the icons to choose from. bordered: the icon is always shown, so it can have
-- the square edge too; on the others the edge would be left behind when the icon hides.
function ns.SkinTile(f, bordered)
	Skin("tile", function(tile, edge)
		Dress(tile)
		if IsTable(tile.icon) then S().SquareIcon(tile.icon, edge and tile or nil) end
		FlatHover(tile)
		if IsTable(tile.del) then
			S().CloseButton(tile.del)
			-- The plain x UI.lua writes when the game's X art is missing; the style draws its own.
			if IsTable(tile.del.mark) then tile.del.mark:SetAlpha(0) end
		end
	end, f, bordered)
end

function ns.SkinTabSelected(tab, on)
	local skin = S()
	if not (skin and skin.SetTabSelection) then return end
	Try("tab selection", skin.SetTabSelection, tab, on and true or false)
end

-- The macro text, the check, the icons, the settings and the tutorials.
function ns.SkinWindow(win)
	Skin("window " .. tostring(win.GetName and win:GetName() or "?"), function(w) Shell(w) end, win)
end

-- The corner buttons are put back above the close button every time the window is shown or
-- clicked. Should the window have no close button of the template's own, that is not above
-- EllesmereUI's border, so they are put above that too.
local function AboveBorder()
	local top = 0
	for _, f in ipairs(borders[UI.frame] or {}) do top = math.max(top, f:GetFrameLevel() or 0) end
	for _, f in ipairs(UI.corners or {}) do
		if (f:GetFrameLevel() or 0) <= top then f:SetFrameLevel(top + 1) end
	end
end

local function SkinBookTab(tab)
	S().Tab(tab)
	-- Without the spellbook's art a tab draws its own edge, which would show over the style's.
	if IsTable(tab.outline) and IsTable(tab.outline.parts) then
		for _, part in ipairs(tab.outline.parts) do part:SetAlpha(0) end
	end
end

function ns.SkinMainWindow(win)
	Skin("bench window", function(w)
		-- The band along the bottom keeps a strip of its own, as the window's own art had one: the
		-- check's summary is written there.
		Shell(w, { bottomBar = 26 })
		local help, cog = UI.focus and UI.focus.help, UI.focus and UI.focus.settings
		if IsTable(help) then S().Button(help) end
		if IsTable(cog) then S().Button(cog, { "gear" }) end
		for _, tab in ipairs(UI.tabs or {}) do Try("book tab", SkinBookTab, tab) end
		if hooksecurefunc then hooksecurefunc(UI, "LiftCorners", AboveBorder) end
		UI:SyncTabs()
		UI:LiftCorners()
	end, win)
end

-- ---- a style is drawn -------------------------------------------------------------------------

-- Anything built before then, in the order it was built.
local function SkinAll()
	local list = waiting
	waiting = {}
	for _, job in ipairs(list) do Try(job[1], job[2], job[3], job[4]) end
end

Styles.Setup({
	addon = ADDON,
	title = "Macro Bench",
	db = function() return ns.db end,
	report = ns.report,
	accent = { 1, 0.82, 0 }, -- the gold the bench marks a chosen block and the line's command with
	skin = SkinAll,
})
