// Offline checks for Macro Bench: loads the addon's Lua into fengari against a stubbed client and
// drives the slash command.
//   NODE_PATH=<dir with fengari> node tests/macrobenchtest.js [--verbose]
'use strict';
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const ROOT = path.join(__dirname, '..');
const VERBOSE = process.argv.includes('--verbose');
const FILES = ['Core.lua', 'Grammar.lua', 'UI.lua', 'Styles.lua', 'MacroBench_Skins.lua'];

const STUBS = `
T = { prints = {}, frames = {}, tutorial = { toggled = 0, shown = 0 } }
unpack = unpack or table.unpack
strlower, strupper, strtrim, format = string.lower, string.upper, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end, string.format
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
function date() return "12:00:00" end
function GetTime() return 100 end
function InCombatLockdown() return false end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) T.prints[#T.prints + 1] = m end }
SlashCmdList = {}
-- Any frame method the addon calls is there and does nothing, unless it is given a body below.
local Frame = {}
Frame.__index = function(self, k) return Frame[k] or function() end end
function Frame:SetScript(n, f) self.scripts[n] = f end
function Frame:GetParent() return rawget(self, "parent") end
function Frame:SetParent(p) self.parent = p end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:GetEffectiveScale() return 1 end
-- These have to hand back something, since the addon keeps hold of what they return and goes on
-- to set textures and text on it.
function Frame:CreateTexture() return CreateFrame("Texture") end
function Frame:CreateFontString() return CreateFrame("FontString") end
function CreateFrame(kind, name, parent)
  local f = setmetatable({ scripts = {}, events = {}, name = name, parent = parent }, Frame)
  T.frames[#T.frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = CreateFrame("Frame", "UIParent")
-- The minimap button hangs off this one, so the minimap has to exist before it can be built.
Minimap = CreateFrame("Frame", "Minimap")
function T.fire(e, ...)
  for _, f in ipairs(T.frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end
end
function T.said(text)
  for _, m in ipairs(T.prints) do if m:find(text, 1, true) then return true end end
  return false
end
`;

// The addon's own files, in TOC order, each given the same namespace table the client would hand it.
function loader() {
  const toc = fs.readFileSync(path.join(ROOT, 'MacroBench.toc'), 'utf8');
  const order = toc.split(/\r?\n/).filter(l => FILES.includes(l.trim())).map(l => l.trim());
  let code = 'NS = {}\n';
  for (const f of order) {
    const src = fs.readFileSync(path.join(ROOT, f), 'utf8');
    code += `assert(load(${JSON.stringify(src)}, "@${f}"))("MacroBench", NS)\n`;
  }
  // What the files left out would have provided: the tutorial records what it was asked to do.
  code += `NS.Tutorial = { Toggle = function() T.tutorial.toggled = T.tutorial.toggled + 1 end,
                       Show = function() T.tutorial.shown = T.tutorial.shown + 1 end }
NS.Validate = NS.Validate or { ScanAll = function() end, Check = function() return {} end }
T.fire("ADDON_LOADED", "MacroBench")
MB = SlashCmdList.MACROBENCH
-- The window itself is not built here: the bench is opened on a bare frame, and drawing it is skipped.
function T.open()
  local i = 1
  while true do
    local name = debug.getupvalue(NS.UI.Show, i)
    if not name then error("UI:Show has no frame upvalue") end
    if name == "frame" then debug.setupvalue(NS.UI.Show, i, T.window) break end
    i = i + 1
  end
  NS.UI:Show()
end
T.window = CreateFrame("Frame")
NS.UI.Refresh = function() end
C_Timer = nil
`;
  return code;
}

let pass = 0, fail = 0;
const CHECK = `local function check(ok, what) if ok then CHECKS_PASS = (CHECKS_PASS or 0) + 1 else error("FAILED: " .. what, 2) end end\n`;
function run(name, body) { runLua(name, STUBS + loader() + CHECK + body); }
function runLua(name, code) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const status = lauxlib.luaL_dostring(L, to_luastring(code));
  if (VERBOSE) {
    lua.lua_getglobal(L, to_luastring('T'));
    if (lua.lua_istable(L, -1)) {
      lua.lua_getfield(L, -1, to_luastring('prints'));
      const n = lauxlib.luaL_len(L, -1);
      for (let i = 1; i <= n; i++) { lua.lua_geti(L, -1, i); console.log('     | ' + lua.lua_tojsstring(L, -1)); lua.lua_pop(L, 1); }
      lua.lua_pop(L, 2);
    } else lua.lua_pop(L, 1);
  }
  if (status !== 0) { fail++; console.log('FAIL ' + name + ': ' + lua.lua_tojsstring(L, -1)); return; }
  lua.lua_getglobal(L, to_luastring('CHECKS_PASS'));
  pass += lua.lua_tonumber(L, -1) || 0;
  console.log('ok   ' + name);
}

run('the help lists every command, pets included', `
  MB("nonsense")
  for _, word in ipairs({ "check", "load <name>", "tutorial", "scan", "pets", "confirm", "minimap", "debug" }) do
    check(T.said("/macrobench " .. word .. "|r"), "help has /macrobench " .. word)
  end
  check(T.said("pets forget"), "help mentions pets forget")
`);

run('plain tutorials and tutorial and help toggle the tutorials', `
  MB("tutorials") check(T.tutorial.toggled == 1, "tutorials toggles")
  MB("tutorial") check(T.tutorial.toggled == 2, "tutorial toggles")
  MB("help") check(T.tutorial.toggled == 3, "help toggles")
  MB("TUTORIALS") check(T.tutorial.toggled == 4, "the word is not case sensitive")
`);

run('tutorials again resets the offer instead of toggling', `
  NS.db.offeredTutorial = true
  MB("tutorials again")
  check(T.tutorial.toggled == 0, "tutorials again does not toggle the tutorials")
  check(NS.db.offeredTutorial == nil, "the offer is forgotten")
  check(T.said("offer themselves next time"), "and it says so")
`);

run('the tutorials offer themselves on a fresh install, once', `
  T.open() check(T.tutorial.shown == 1, "offered the first time")
  T.window.shown = false T.open() check(T.tutorial.shown == 1, "not again")
`);

run('tutorials again offers them once more, even with drafts kept', `
  NS.db.offeredTutorial = true
  NS.db.drafts[1] = { name = "kept", text = "/cast Fear" }
  T.open() check(T.tutorial.shown == 0, "with drafts kept and already offered, nothing")
  MB("tutorials again")
  T.window.shown = false T.open() check(T.tutorial.shown == 1, "offered after tutorials again")
  T.window.shown = false T.open() check(T.tutorial.shown == 1, "and only that once")
`);

run('pets and pets forget still reach their branch', `
  MB("pets") check(T.said("Nothing yet") or T.said("spells your pets know"), "pets answers")
  check(T.tutorial.toggled == 0, "pets toggles nothing")
  MB("pets forget") check(T.said("Forgotten."), "pets forget answers")
`);

run('the minimap button can be switched off, from the box or the command', `
  check(NS.db.minimap == true, "it starts shown")
  check(type(NS.UI.ToggleSettings) == "function", "there is a settings window to open")
  check(type(NS.UI.RefreshSettings) == "function", "and a way to put its tick box back in step")
  -- Called here before the window has ever been built, which is the state it is in after a login
  -- when the command is used and the bench has not been opened.
  NS.UI:RefreshSettings()
  check(true, "putting the box in step before it exists does nothing rather than erroring")
  MB("minimap")
  check(NS.db.minimap == false, "the command hides it")
  check(T.said("Minimap button: "), "and says which way it went")
  MB("minimap")
  check(NS.db.minimap == true, "and brings it back")
  check(_G.MacroBenchMinimapButton ~= nil, "the button itself was built")
`);

run('with the Blizzard look the skin file draws nothing', `
  check(NS.report.skin == "Blizzard (EllesmereUI is not loaded)", "the debug report says why the look is Blizzard's")
  check(NS.db.style == "auto" and NS.db.darkAlpha == 0.92, "the style starts on Automatic, Dark at 92%")
  T.fire("PLAYER_ENTERING_WORLD")
  check(NS.Styles.S == nil and NS.Styles.Applied() == nil, "with no EllesmereUI, Automatic draws no style")
  for _, hook in ipairs({ "SkinButton", "SkinCheck", "SkinEditBox", "SkinPanel", "SkinTile", "SkinText",
                          "SkinTabSelected", "SkinCommandButton", "SkinWindow", "SkinMainWindow" }) do
    check(type(NS[hook]) == "function", hook .. " is there for UI.lua to call, and waits for a style")
  end
`);

run('the style command', `
  MB("style blizzard")
  check(NS.db.style == "blizzard" and T.said("Window style: Blizzard. In use: Blizzard."), "style blizzard")
  MB("style") check(NS.db.style == "dark", "style on its own steps to the next one")
  MB("style auto") check(NS.db.style == "auto" and T.said("Window style: Automatic."), "style auto")
  MB("style purple") check(NS.db.style == "auto" and T.said("Styles: auto, blizzard, dark."), "an unknown word changes nothing")
  MB("nonsense") check(T.said("/macrobench style|r"), "the help lists it")
`);

// ---- The whole window, built on a fuller stand-in for the client -------------------------------
// Every method the addon's files call with a colon exists and does nothing unless given a body
// below. Fields are only there when a stand-in template puts them there, the way the client's own
// templates do, so an "if frame.Inset" in the addon reads the same here as in the game.
const FULL_FILES = (() => {
  const toc = fs.readFileSync(path.join(ROOT, 'MacroBench.toc'), 'utf8');
  return toc.split(/\r?\n/).map(l => l.trim()).filter(l => l.endsWith('.lua'));
})();
const METHODS = (() => {
  const names = new Set();
  for (const f of FULL_FILES) {
    const src = fs.readFileSync(path.join(ROOT, f), 'utf8');
    for (const m of src.matchAll(/:([A-Z][A-Za-z0-9_]*)\s*\(/g)) names.add(m[1]);
  }
  return [...names];
})();

const CLIENT = String.raw`
T = { prints = {}, frames = {}, made = {}, regions = {} }
unpack = unpack or table.unpack
strlower, strupper, format = string.lower, string.upper, string.format
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert, tremove = table.insert, table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
function date() return "12:00:00" end
function time() return 1000 end
function GetTime() return 100 end
function InCombatLockdown() return T.combat == true end
-- The game's panel functions refuse an addon in combat ("Interface action blocked"), and the X of
-- the client's templates goes through them (SharedUIPanelTemplates.lua). T.blocked counts refusals.
T.blocked = 0
function HideUIPanel(f) if InCombatLockdown() then T.blocked = T.blocked + 1 return end if f then f:Hide() end end
function ShowUIPanel(f) if InCombatLockdown() then T.blocked = T.blocked + 1 return end if f then f:Show() end end
function UIPanelCloseButton_OnClick(self)
  local parent = self:GetParent()
  if parent then
    if parent.onCloseCallback then parent.onCloseCallback(self) else HideUIPanel(parent) end
  end
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) T.prints[#T.prints + 1] = m end }
SlashCmdList = {}
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts/FRIZQT.TTF"
function GetCursorPosition() return 0, 0 end
function UnitClass() return "Warlock", "WARLOCK" end
function UnitName() return "Vatik", "Voidpact" end
function GetRealmName() return "Test" end
function hooksecurefunc(a, b, c)
  local t, name, fn = a, b, c
  if type(a) == "string" then t, name, fn = _G, a, b end
  local old = t[name]
  t[name] = function(...) local r = { old(...) } fn(...) return unpack(r) end
end

local M = {}
for _, name in ipairs(METHODS) do M[name] = function() end end
local Meta = { __index = M }
local function add(list, x) list[#list + 1] = x end
local function new(kind, parent)
  return setmetatable({ kind = kind, parent = parent, scripts = {}, events = {}, children = {}, regions = {},
    shown = true, alpha = 1, level = parent and ((parent.level or 0) + 1) or 1 }, Meta)
end
local function region(self, kind)
  local r = new(kind, self)
  add(self.regions, r)
  add(T.regions, r)
  return r
end
function M:CreateTexture(_, layer, _, sub)
  local t = region(self, "Texture")
  t.layer, t.sub = layer, sub
  return t
end
function M:CreateFontString() return region(self, "FontString") end
function M:CreateMaskTexture() return region(self, "MaskTexture") end
function M:SetScript(n, f) self.scripts[n] = f end
function M:GetScript(n) return self.scripts[n] end
function M:HookScript(n, f)
  local old = self.scripts[n]
  self.scripts[n] = old and function(...) old(...) f(...) end or f
end
function M:RegisterEvent(e) self.events[e] = true end
function M:UnregisterEvent(e) self.events[e] = nil end
function M:UnregisterAllEvents() self.events = {} end
function M:Show()
  if self.shown then return end
  self.shown = true
  if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function M:Hide()
  if not self.shown then return end
  self.shown = false
  if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:IsShown() return self.shown end
function M:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function M:SetSize(w, h) self.w, self.h = w, h end
function M:SetWidth(w) self.w = w end
function M:SetHeight(h) self.h = h end
function M:GetWidth() return self.w or 300 end
function M:GetHeight() return self.h or 200 end
function M:GetSize() return self:GetWidth(), self:GetHeight() end
function M:GetLeft() return 0 end
function M:GetRight() return 300 end
function M:GetTop() return 600 end
function M:GetBottom() return 0 end
function M:GetCenter() return 150, 300 end
function M:GetEffectiveScale() return 1 end
function M:SetText(t)
  self.text = t
  if (self.kind == "Button" or self.kind == "CheckButton") then
    self.fontString = self.fontString or self:CreateFontString()
    self.fontString.text = t
  end
end
function M:GetText() return self.text or "" end
function M:GetFontString() return self.fontString end
function M:GetStringWidth() return #(self.text or "") * 6 end
function M:GetStringHeight() return 12 end
function M:SetFrameLevel(l) self.level = l end
function M:GetFrameLevel() return self.level end
function M:SetFrameStrata(s) self.strata = s end
function M:GetFrameStrata() return self.strata or "MEDIUM" end
function M:GetParent() return self.parent end
function M:GetChildren() return unpack(self.children) end
function M:GetRegions() return unpack(self.regions) end
function M:GetObjectType() return self.kind end
function M:IsObjectType(t) return self.kind == t or (t == "Texture" and self.kind == "MaskTexture") end
function M:GetName() return self.name end
function M:SetFont(p, s) self.font = { p, s } end
function M:GetFont() return self.font and self.font[1] or "Fonts/FRIZQT.TTF", self.font and self.font[2] or 12 end
function M:SetTextColor(r, g, b) self.color = { r, g, b } end
function M:SetAlpha(a) self.alpha = a end
function M:GetAlpha() return self.alpha end
function M:SetTexture(t) self.texture = t end
function M:GetTexture() return self.texture end
function M:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
function M:SetBlendMode(m) self.blend = m end
for _, k in ipairs({ "Highlight", "Normal", "Pushed", "Disabled", "Checked" }) do
  M["Set" .. k .. "Texture"] = function(self, t, blend)
    self[k] = self[k] or self:CreateTexture()
    self[k].texture, self[k].blend = t, blend
  end
  M["Get" .. k .. "Texture"] = function(self) return self[k] end
end
-- Atlases are looked up by name, without regard to case, the way the client does; T.ATLASES says
-- which ones this client has. These three are the game's own close button, which Forever ships.
T.ATLASES = { ["redbutton-exit"] = true, ["redbutton-exit-pressed"] = true, ["redbutton-highlight"] = true }
C_Texture = { GetAtlasInfo = function(name)
  if type(name) == "string" and T.ATLASES[name:lower()] then return { width = 18, height = 19 } end
end }
function M:SetAtlas(a) self.atlas = a end
for _, k in ipairs({ "Highlight", "Normal", "Pushed" }) do
  M["Set" .. k .. "Atlas"] = function(self, a, blend)
    self[k] = self[k] or self:CreateTexture()
    self[k].atlas, self[k].blend = a, blend
  end
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function M:SetGradient(dir, from, to) self.gradient = { dir, from, to } end
function M:SetFontObject(f) self.fontObject = f end
function M:SetEnabled(v) self.disabled = not v end
function M:Enable() self.disabled = false end
function M:Disable() self.disabled = true end
function M:IsEnabled() return not self.disabled end
function M:SetValue(v)
  self.sliderValue = v
  if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
function M:GetValue() return self.sliderValue end
function M:SetChecked(v) self.checked = v end
function M:GetChecked() return self.checked end
function M:HasFocus() return false end
function M:GetVerticalScroll() return 0 end
function M:IsMouseOver() return false end
function M:GetNumMaskTextures() return 0 end
function M:IsForbidden() return false end

-- What the client's templates hang on a frame, as far as the addon or the skin looks.
local TEMPLATES = {}
T.TEMPLATES = TEMPLATES
local function child(f, kind, template) return CreateFrame(kind or "Frame", nil, f, template) end
TEMPLATES.ButtonFrameTemplate = function(f)
  f.Inset = child(f)
  f.CloseButton = child(f, "Button", "UIPanelCloseButton")
  f.PortraitContainer = child(f)
  f.PortraitContainer.portrait = f.PortraitContainer:CreateTexture()
  f.TitleContainer = child(f)
  f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
  f.NineSlice = child(f)
  f.Bg = f:CreateTexture()
end
TEMPLATES.BasicFrameTemplateWithInset = function(f)
  f.Inset = child(f)
  f.CloseButton = child(f, "Button", "UIPanelCloseButton")
  f.TitleText = f:CreateFontString()
  f.Bg = f:CreateTexture()
end
TEMPLATES.UIPanelButtonTemplate = function(f)
  f.Left, f.Middle, f.Right = f:CreateTexture(), f:CreateTexture(), f:CreateTexture()
end
TEMPLATES.InputBoxTemplate = function(f)
  f.Left, f.Middle, f.Right = f:CreateTexture(), f:CreateTexture(), f:CreateTexture()
end
TEMPLATES.UICheckButtonTemplate = function(f) f:SetCheckedTexture("check") end
TEMPLATES.UIPanelCloseButton = function(f)
  f:SetNormalTexture("x")
  f.scripts.OnClick = function(self) UIPanelCloseButton_OnClick(self) end
end
TEMPLATES.BackdropTemplate = function() end
TEMPLATES.MacroBenchScrollFrameTemplate = function(f)
  f.ScrollBar = child(f, "EventFrame")
  f.ScrollBar.Track, f.ScrollBar.Back, f.ScrollBar.Forward = child(f.ScrollBar), child(f.ScrollBar, "Button"), child(f.ScrollBar, "Button")
end

function CreateFrame(kind, name, parent, template)
  if template and not TEMPLATES[template] then error("no template " .. template) end
  local f = new(kind, parent)
  f.name, f.template = name, template
  if parent then add(parent.children, f) end
  T.frames[#T.frames + 1] = f
  T.made[#T.made + 1] = f
  if name then _G[name] = f end
  if template then TEMPLATES[template](f) end
  return f
end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
function T.fire(e, ...)
  for _, f in ipairs(T.frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end
end
function T.said(text)
  for _, m in ipairs(T.prints) do if m:find(text, 1, true) then return true end end
  return false
end
`;

// A stand-in EllesmereUI: its facade records every call, and Shell lays a border frame over the
// window six levels up, as the real one does.
const EUI_STANDIN = String.raw`
EUI = { by = {}, opts = {}, keep = {}, selected = {}, border = {}, iconParent = {}, bad = {} }
function EUI.did(f, what) return type(f) == "table" and EUI.by[f] ~= nil and (EUI.by[f][what] or 0) > 0 end
local WANT = { Button = "Button", WhiteButtonLabel = "Button", EditBox = "EditBox", Checkbox = "CheckButton",
  CloseButton = "Button", Font = "FontString", White = "FontString", SquareIcon = "Texture", Tab = "CheckButton" }
local function rec(name)
  return function(f)
    if type(f) ~= "table" or (WANT[name] and f.kind ~= WANT[name]) then
      EUI.bad[#EUI.bad + 1] = name .. " on " .. (type(f) == "table" and tostring(f.kind) or type(f))
      return
    end
    local d = EUI.by[f] or {}
    EUI.by[f] = d
    d[name] = (d[name] or 0) + 1
  end
end
EUI_S = { apiVersion = 3, GetStyle = function() return "eui" end }
for _, n in ipairs({ "Inset", "FadeRegions", "WhiteButtonLabel", "EditBox", "Checkbox", "ScrollBar", "Tab",
                     "CloseButton", "Font", "White" }) do EUI_S[n] = rec(n) end
EUI_S.Shell = function(f, opts)
  rec("Shell")(f)
  EUI.opts[f] = opts or {}
  local border = CreateFrame("Frame", nil, f)
  border:SetFrameLevel(f:GetFrameLevel() + 6)
  EUI.border[f] = border
end
EUI_S.Panel = function(f, opts) rec("Panel")(f) EUI.opts[f] = opts or {} end
EUI_S.Button = function(f, keep) rec("Button")(f) EUI.keep[f] = keep end
EUI_S.SquareIcon = function(icon, parent) rec("SquareIcon")(icon) EUI.iconParent[icon] = parent or false end
EUI_S.SetTabSelection = function(tab, on) rec("SetTabSelection")(tab) EUI.selected[tab] = on end
EllesmereUI = { RegisterSkin = function(name, fn) EUI.name, EUI.fn = name, fn end }
if EUI_DISPATCH ~= false then EllesmereUI._DispatchSkinRegistration = function() end end
`;

// Dark is drawn for real, by Styles.lua. Each of its calls is recorded on the way through into the
// same tables the EllesmereUI stand-in fills, so one set of checks reads both. Dark calls some of
// its own functions with whatever a template may or may not have (a NineSlice, say), so only the
// calls that need a particular kind of object are held to it.
const DARK_RECORDER = String.raw`
EUI = { by = {}, opts = {}, keep = {}, selected = {}, border = {}, iconParent = {}, bad = {} }
function EUI.did(f, what) return type(f) == "table" and EUI.by[f] ~= nil and (EUI.by[f][what] or 0) > 0 end
local WANT = { Button = "Button", WhiteButtonLabel = "Button", EditBox = "EditBox", Checkbox = "CheckButton",
  CloseButton = "Button", Font = "FontString", White = "FontString", SquareIcon = "Texture", Tab = "CheckButton" }
local D = NS.Styles.Dark
for _, name in ipairs({ "Shell", "Panel", "Inset", "FadeRegions", "FadeNineSlice", "Button", "WhiteButtonLabel",
                        "StateButtonLabel", "EditBox", "Checkbox", "Dropdown", "ScrollBar", "Tab", "SetTabSelection",
                        "CloseButton", "PageButton", "SquareIcon", "SortHeaderBar", "Font", "White", "ApplyBarFill" }) do
  local real = D[name]
  D[name] = function(f, a, ...)
    if WANT[name] and (type(f) ~= "table" or f.kind ~= WANT[name]) then
      EUI.bad[#EUI.bad + 1] = name .. " on " .. (type(f) == "table" and tostring(f.kind) or type(f))
    elseif type(f) == "table" then
      local d = EUI.by[f] or {}
      EUI.by[f] = d
      d[name] = (d[name] or 0) + 1
      if name == "Shell" or name == "Panel" then EUI.opts[f] = a or {} end
      if name == "Button" then EUI.keep[f] = a end
      if name == "SquareIcon" then EUI.iconParent[f] = a or false end
      if name == "SetTabSelection" then EUI.selected[f] = a end
    end
    return real(f, a, ...)
  end
end
-- Dark's window backdrop: the gradient texture it lays at the very back of a window.
function T.backdrop(w)
  for _, r in ipairs(w.regions) do
    if r.layer == "BACKGROUND" and r.sub == -8 and r.gradient then return r end
  end
end
`;

function loaderFull() {
  let code = `METHODS = { ${METHODS.map(m => JSON.stringify(m)).join(', ')} }\n`;
  code += CLIENT;
  return code;
}
function filesFull() {
  let code = 'NS = {}\n';
  for (const f of FULL_FILES) {
    const src = fs.readFileSync(path.join(ROOT, f), 'utf8');
    code += `assert(load(${JSON.stringify(src)}, "@${f}"))("MacroBench", NS)\n`;
  }
  return code + `T.fire("ADDON_LOADED", "MacroBench")\nT.fire("PLAYER_LOGIN")\nMB = SlashCmdList.MACROBENCH\n`;
}

// Opens everything there is to open: the bench with three lines on it, the action editor, the
// steps editor with a row per step, every chapter of the book, the icons, the settings, the
// tutorials, and a drag.
const DRIVE = String.raw`
function T.drive()
  local UI = NS.UI
  NS.db.offeredTutorial = true
  NS.SetBenchText("#showtooltip\n/cast [@mouseover,harm] Fear; Shadow Bolt\n/castsequence reset=combat Corruption, Immolate")
  NS.db.drafts[#NS.db.drafts + 1] = { uid = "d1", name = "kept", text = "/cast Fear", stamp = 1 }
  MB("")
  UI.sel = { block = 2, kind = "action" } UI:Refresh()
  UI.sel = { block = 3, kind = "arg", clause = 1 } UI:Refresh()
  for i = #UI.tabs, 1, -1 do UI.tabs[i].scripts.OnClick(UI.tabs[i]) end
  UI:ShowIconPicker()
  UI:ToggleSettings()
  NS.Tutorial:Toggle()
  UI:StartDrag({ proto = { cmd = "cast" } }, nil, "Cast")
  UI:EndDrag()
  UI.sel = { block = 2, kind = "action" } UI:Refresh()
end
`;

// Every window, button and pooled row the drive above built, looked at for its skin.
const SKIN_CHECKS = String.raw`
function T.checkSkinned(check, report)
  local UI = NS.UI
  local function under(f, root) while f do if f == root then return true end f = f.parent end return false end
  -- What a corner button has to be above: EllesmereUI's border frame, or the window itself for Dark.
  local function top(w) return EUI.border[w] and EUI.border[w].level or w.level end
  report = report or "EllesmereUI (eui style)"
  check(NS.report.skin == report, "the debug report says the look is " .. report .. ": " .. tostring(NS.report.skin))
  local errors = {}
  for k, v in pairs(NS.report) do if k:find("skin error", 1, true) then errors[#errors + 1] = k .. " = " .. tostring(v) end end
  check(#errors == 0, "no skin errors: " .. table.concat(errors, "; "))
  check(#EUI.bad == 0, "every call got the kind of object it is for: " .. table.concat(EUI.bad, ", "))

  local main = _G.MacroBenchFrame
  local windows = { main, _G.MacroBenchTextFrame, _G.MacroBenchCheckFrame, _G.MacroBenchIconFrame,
    _G.MacroBenchSettingsFrame, _G.MacroBenchTutorialFrame }
  for i = 1, 6 do
    local w = windows[i]
    check(w ~= nil, "window " .. i .. " was built")
    local name = w.name
    check(EUI.did(w, "Shell"), name .. " has the theme's window shell")
    check(EUI.did(w.Inset, "Inset"), name .. " has its inset stripped")
    check(EUI.did(w.CloseButton, "CloseButton"), name .. " has the theme's close button")
    check(w.CloseButton.level > top(w), name .. " close button is above the border")
  end
  check(EUI.opts[main].bottomBar == 26, "the bench keeps a strip along the bottom for the check's summary")
  check(EUI.did(main.PortraitContainer, "FadeRegions"), "the bench's portrait is gone")
  check(EUI.did(main.TitleContainer.TitleText, "Font"), "the bench's title is in the theme's font")
  check(#UI.corners == 3, "three corner buttons")
  for i, c in ipairs(UI.corners) do check(c.level > top(main), "corner button " .. i .. " is above the border") end
  check(EUI.did(UI.focus.help, "Button"), "the ? button is a theme button")
  check(EUI.did(UI.focus.settings, "Button"), "the cog is a theme button")
  check(EUI.keep[UI.focus.settings] and EUI.keep[UI.focus.settings][1] == "gear" and UI.focus.settings.gear ~= nil, "and keeps its gear")

  local counts = { button = 0, box = 0, tick = 0, scroll = 0 }
  for _, f in ipairs(T.made) do
    if f.template == "UIPanelButtonTemplate" then
      counts.button = counts.button + 1
      check(EUI.did(f, "Button") and EUI.did(f, "WhiteButtonLabel") and EUI.did(f.fontString, "Font"),
        "button " .. tostring(f.text) .. " is a theme button with a white label in the theme's font")
    elseif f.template == "InputBoxTemplate" then
      counts.box = counts.box + 1
      check(EUI.did(f, "EditBox"), "every text box is a theme box")
    elseif f.template == "UICheckButtonTemplate" then
      counts.tick = counts.tick + 1
      check(EUI.did(f, "Checkbox"), "every tick box is a theme tick box")
    elseif f.template == "MacroBenchScrollFrameTemplate" then
      counts.scroll = counts.scroll + 1
      check(EUI.did(f.ScrollBar, "ScrollBar"), "every scroll bar is the theme's strip")
    end
  end
  check(counts.button > 40, "the panel buttons were all looked at (" .. counts.button .. ")")
  check(counts.box >= 10, "the text boxes were all looked at (" .. counts.box .. ")")
  check(counts.tick >= 10, "the tick boxes were all looked at (" .. counts.tick .. ")")
  check(counts.scroll == 6, "all six scroll frames were looked at (" .. counts.scroll .. ")")

  local cast = 0
  for _, f in ipairs(T.made) do
    if f.cmd and f.template == "UIPanelButtonTemplate" then
      local gold = f.fontString.color and f.fontString.color[1] == 1 and f.fontString.color[2] == 0.82
      if f.cmd == "cast" then cast = cast + 1 check(gold, "the line's own command is gold") end
      if f.cmd ~= "cast" then check(EUI.did(f.fontString, "White") and not gold, "the other commands are white") end
    end
  end
  check(cast == 1, "the command buttons were found")

  for i, tab in ipairs(UI.tabs) do
    check(EUI.did(tab, "Tab"), "book tab " .. tab.token .. " is a theme tab")
    check(tab.Icon ~= nil, "and keeps its icon")
    check(EUI.selected[tab] == (i == 1), "only the open chapter shows as selected (" .. tab.token .. ")")
  end
  UI.tabs[2].scripts.OnClick(UI.tabs[2])
  check(EUI.selected[UI.tabs[2]] == true and EUI.selected[UI.tabs[1]] == false, "the selection follows a click")
  UI.tabs[1].scripts.OnClick(UI.tabs[1])

  local panes, panels = 0, 0
  for _, f in ipairs(T.made) do
    if f.plate and f.plate.kind == "Texture" then
      panels = panels + 1
      local underlay
      for _, c in ipairs(f.children) do if EUI.did(c, "Panel") then underlay = c end end
      check(underlay ~= nil and underlay.level == f.level, "a panel has the theme's panel just under it")
      check(f.plate.alpha == 0, "and its own fill is gone")
      if f.strip then
        panes = panes + 1
        check(f.strip.colorTexture[1] == 0 and f.strip.colorTexture[4] == 0.5, "a pane's title strip is darkened")
      end
    end
  end
  check(panes == 3 and panels == 5, "three panes, the footer and the text box's backing (" .. panes .. ", " .. panels .. ")")

  local kinds = { part = 0, plate = 0, bookRow = 0, step = 0, picker = 0 }
  local bordered = 0
  for _, f in ipairs(T.made) do
    if f.kindText then
      kinds.part = kinds.part + 1
      check(EUI.did(f.kindText, "Font") and EUI.did(f.valueText, "Font"), "a block's words are in the theme's font")
      check(EUI.did(f.icon, "SquareIcon") and EUI.iconParent[f.icon] == false, "a block's icon is squared, with no edge left behind")
      check(f.Highlight.colorTexture and f.Highlight.colorTexture[4] == 0.1, "a block's hover is the theme's wash")
    end
    if f.rail then
      kinds.plate = kinds.plate + 1
      check(EUI.did(f.del, "CloseButton") and EUI.did(f.num, "Font"), "a line plate's take-out button is the theme's X")
    end
    if f.heading and f.why then
      kinds.bookRow = kinds.bookRow + 1
      check(EUI.did(f.del, "CloseButton") and EUI.did(f.icon, "SquareIcon") and EUI.did(f.name, "Font"), "a book row is done")
    end
    if f.number and f.del then
      kinds.step = kinds.step + 1
      check(EUI.did(f.del, "CloseButton") and EUI.did(f.number, "Font"), "a step row is done")
    end
    if f.icon and EUI.iconParent[f.icon] == f then bordered = bordered + 1 end
  end
  for _, b in ipairs(_G.MacroBenchIconFrame.buttons) do
    kinds.picker = kinds.picker + 1
    check(EUI.did(b.icon, "SquareIcon"), "an icon to choose from is squared")
  end
  for k, n in pairs(kinds) do check(n > 0, "pooled " .. k .. " frames were built and looked at (" .. n .. ")") end
  check(bordered == 1, "only the macro's own icon in the footer gets the square edge")

  local fonts, missed = 0, {}
  for _, r in ipairs(T.regions) do
    if r.kind == "FontString" then
      for _, w in ipairs(windows) do
        if under(r, w) then
          fonts = fonts + 1
          if not EUI.did(r, "Font") then missed[#missed + 1] = tostring(r.text) end
          break
        end
      end
    end
  end
  check(fonts > 200 and #missed == 0, fonts .. " lines of text, all in the theme's font; missed: " .. table.concat(missed, " | "))
end

-- The X that takes out a line plate, a step or a kept macro.
function T.takeOuts()
  local list = {}
  for _, f in ipairs(T.made) do
    if f.del and (f.rail or f.number or f.heading) then list[#list + 1] = f.del end
  end
  return list
end

-- mode "art": the red X off the game's close buttons. mode "x": the plain x written without it.
-- Either way, nothing is left wearing the minimize button art, which this client does not draw.
function T.checkTakeOuts(check, mode)
  local kinds = { plate = 0, step = 0, book = 0 }
  for _, f in ipairs(T.made) do
    local d = f.del
    local kind = d and ((f.rail and "plate") or (f.number and "step") or (f.heading and "book"))
    if kind then
      kinds[kind] = kinds[kind] + 1
      if mode == "art" then
        check(d.Normal and d.Normal.atlas == "RedButton-Exit" and d.Normal.alpha == 1, kind .. " take-out button wears the game's red X")
        check(d.Pushed and d.Pushed.atlas == "RedButton-exit-pressed", "and its pressed look")
        check(d.Highlight and d.Highlight.atlas == "RedButton-Highlight" and d.Highlight.blend == "ADD", "and its hover")
        check(d.mark == nil, "and writes no x over it")
      else
        check(d.Normal == nil and d.mark and d.mark.text == "x" and d.mark.alpha == 1, kind .. " take-out button writes a plain x")
        check(d.mark.color and d.mark.color[1] == 1, "in red")
      end
    end
  end
  for k, n in pairs(kinds) do check(n > 0, k .. " take-out buttons were built (" .. n .. ")") end
  check(NS.report["take out buttons"] == (mode == "art" and "RedButton-Exit" or "a plain x"), "the report says which")
  local old = {}
  for _, r in ipairs(T.regions) do
    if type(r.texture) == "string" and r.texture:find("MinimizeButton", 1, true) then old[#old + 1] = r.texture end
  end
  check(#old == 0, "no texture is the minimize button art: " .. table.concat(old, ", "))
end

-- on: the slider is live (Dark); off: grayed, for the other styles.
function T.checkSlider(check, on)
  local s = _G.MacroBenchSettingsFrame.opacity
  local what = on and "live" or "grayed"
  check(s.disabled == not on and s.alpha == (on and 1 or 0.5), "the opacity slider is " .. what)
  check(s.mbLabel.fontObject == (on and "GameFontHighlight" or "GameFontDisable"), "and its label says so")
  check(s.mbValue.fontObject == (on and "GameFontNormal" or "GameFontDisable"), "and its value too")
end

-- Every window's X, in combat and out: the game's own click goes through HideUIPanel, which the
-- client refuses in combat, so each X has to hide its window itself. Closing the bench saves it.
function T.checkCloses(check)
  local saves, save = 0, NS.SaveBench
  NS.SaveBench = function(...) saves = saves + 1 return save(...) end
  for _, name in ipairs({ "MacroBenchFrame", "MacroBenchTextFrame", "MacroBenchCheckFrame", "MacroBenchIconFrame",
      "MacroBenchSettingsFrame", "MacroBenchTutorialFrame" }) do
    local w = _G[name]
    local x = w.CloseButton or w.mbClose
    check(x and x.scripts.OnClick ~= nil, name .. " has an X")
    local was = T.blocked
    w:Show()
    T.combat = true
    x.scripts.OnClick(x, "LeftButton")
    T.combat = false
    check(not w.shown and T.blocked == was, name .. ": in combat its X still closes it, nothing refused (" .. (T.blocked - was) .. ")")
    w:Show()
    x.scripts.OnClick(x, "LeftButton")
    check(not w.shown and T.blocked == was, name .. ": out of combat its X closes it")
  end
  check(saves == 2, "the bench is saved each time its X closes it (" .. saves .. ")")
  NS.SaveBench = save
end

-- What only Dark does: its backdrop, the opacity setting, and the reload offered on leaving it.
function T.checkDark(check)
  local windows = { "MacroBenchFrame", "MacroBenchTextFrame", "MacroBenchCheckFrame", "MacroBenchIconFrame",
    "MacroBenchSettingsFrame", "MacroBenchTutorialFrame" }
  local function alphas(want)
    for _, name in ipairs(windows) do
      local bd = T.backdrop(_G[name])
      check(bd and bd.gradient[2].a == want and bd.gradient[3].a == want, name .. " has Dark's backdrop at " .. want)
    end
  end
  alphas(0.92)

  local blocks = 0
  for _, f in ipairs(T.made) do
    if f.kindText then
      blocks = blocks + 1
      check(f.bg.alpha == 1 and f.bg.colorTexture and f.bg.colorTexture[4] == 0.9, "a block keeps its own color")
      for _, part in ipairs(f.outline.parts) do check(part.alpha == 1, "and its selection outline") end
    end
  end
  check(blocks > 0, "blocks were found (" .. blocks .. ")")

  local xs = 0
  for _, d in ipairs(T.takeOuts()) do
    xs = xs + 1
    check(EUI.did(d, "CloseButton") and d.Normal.alpha == 0, "a take-out button's red X gives way to Dark's")
    local strokes = 0
    for _, r in ipairs(d.regions) do if r.layer == "OVERLAY" and r.colorTexture then strokes = strokes + 1 end end
    check(strokes == 2, "which is two strokes")
  end
  check(xs > 0, "take-out buttons were found")

  local w = _G.MacroBenchSettingsFrame
  T.checkSlider(check, true)
  w.opacity:SetValue(40)
  check(NS.db.darkAlpha == 0.4 and w.opacity.mbValue.text == "40%", "the slider sets the opacity")
  alphas(0.4)

  w.styleButton.scripts.OnClick(w.styleButton, "LeftButton")
  local prompt = _G.MacroBenchReloadPrompt
  check(NS.db.style == "auto", "the button steps on to Automatic")
  check(prompt and prompt.shown and prompt.text.text:find("Switching Macro Bench to Blizzard takes a reload", 1, true),
    "leaving Dark offers a reload")
  check(EUI.did(prompt, "Shell"), "in Dark's own look")
  check(w.styleNote.text:find("Type /reload to switch to Blizzard", 1, true), "and the note under the button says so")
  T.checkSlider(check, false)
  w.styleButton.scripts.OnClick(w.styleButton, "RightButton")
  check(NS.db.style == "dark" and not prompt.shown, "back to Dark, and the offer goes away")
  T.checkSlider(check, true)
  MB("style blizzard")
  check(prompt.shown and T.said("Window style: Blizzard. |cffffd100Type /reload to switch to Blizzard."), "the command offers it too")
  check(w.styleButton.text == "Window style: Blizzard", "and the settings window follows the command")
  T.checkSlider(check, false)

  local errors = {}
  for k, v in pairs(NS.report) do if k:find("skin error", 1, true) then errors[#errors + 1] = k .. " = " .. tostring(v) end end
  check(#errors == 0 and #EUI.bad == 0, "no skin errors: " .. table.concat(errors, "; ") .. table.concat(EUI.bad, ", "))
end
`;

function runFull(name, opts, body) {
  let pre = (opts.eui ? `EUI_DISPATCH = ${opts.dispatch === false ? 'false' : 'true'}\n` + EUI_STANDIN : '');
  if (opts.atlases) pre += `T.ATLASES = ${opts.atlases}\n`;
  const post = opts.dark ? DARK_RECORDER : '';
  runLua(name, loaderFull() + pre + filesFull() + post + DRIVE + SKIN_CHECKS + CHECK + body);
}

runFull('without EllesmereUI the whole window builds as it always has', {}, `
  T.drive()
  check(NS.report.skin == "Blizzard (EllesmereUI is not loaded)", "the report says EllesmereUI is not loaded")
  check(_G.MacroBenchFrame and _G.MacroBenchFrame.shown, "the bench is open")
  for _, name in ipairs({ "MacroBenchTextFrame", "MacroBenchCheckFrame", "MacroBenchIconFrame", "MacroBenchSettingsFrame", "MacroBenchTutorialFrame" }) do
    check(_G[name] ~= nil, name .. " was built")
  end
  local plates = 0
  for _, f in ipairs(T.made) do
    if f.plate and f.plate.kind == "Texture" then plates = plates + 1 check(f.plate.alpha == 1, "every panel keeps its own fill") end
    if f.kindText then check(f.Highlight.colorTexture == nil, "every block keeps the game's glow") end
  end
  check(plates == 5, "the five panels were built")
  local errors = 0
  for k in pairs(NS.report) do if k:find("skin", 1, true) and k ~= "skin" then errors = errors + 1 end end
  check(errors == 0, "nothing about skins in the report but the one line")
  T.fire("PLAYER_ENTERING_WORLD")
  check(NS.Styles.S == nil, "and no style is drawn once the world is up")
  for _, r in ipairs(T.regions) do
    if r.layer == "BACKGROUND" and r.sub == -8 then check(false, "a Dark backdrop was laid") end
  end
  T.checkTakeOuts(check, "art")
  T.checkSlider(check, false)
`);

runFull('on a client without the close button atlas, the take-out buttons are a plain x', { atlases: '{}' }, `
  T.drive()
  check(NS.report["take out buttons"] == "a plain x", "the report says which: " .. tostring(NS.report["take out buttons"]))
  T.checkTakeOuts(check, "x")
`);

runFull('Dark chosen: every window and pooled frame is drawn as it is built', { dark: true }, `
  NS.db.style = "dark"
  T.fire("PLAYER_ENTERING_WORLD")
  check(NS.Styles.Applied() == "dark" and NS.Styles.S == NS.Styles.Dark, "Dark is drawn once the world is up")
  T.drive()
  T.checkSkinned(check, "Dark")
  T.checkDark(check)
`);

runFull('Dark chosen in the settings after the bench was built: it is drawn at once', { dark: true }, `
  T.fire("PLAYER_ENTERING_WORLD")
  T.drive()
  check(next(EUI.by) == nil, "nothing is drawn with the Blizzard look")
  local w = _G.MacroBenchSettingsFrame
  T.checkSlider(check, false)
  w.styleButton.scripts.OnClick(w.styleButton, "LeftButton")
  check(NS.db.style == "blizzard" and NS.Styles.S == nil, "Automatic, then Blizzard: still nothing drawn")
  w.styleButton.scripts.OnClick(w.styleButton, "LeftButton")
  check(NS.db.style == "dark" and NS.Styles.Applied() == "dark", "then Dark, drawn without a reload")
  check(not (_G.MacroBenchReloadPrompt and _G.MacroBenchReloadPrompt.shown), "so no reload is offered")
  check(w.styleButton.text == "Window style: Dark", "the button says Dark")
  NS.UI:Refresh()
  T.checkSkinned(check, "Dark")
  T.checkDark(check)
`);

runFull('Dark with no close button atlas: the plain x gives way to the drawn X', { dark: true, atlases: '{}' }, `
  NS.db.style = "dark"
  T.fire("PLAYER_ENTERING_WORLD")
  T.drive()
  local n = 0
  for _, d in ipairs(T.takeOuts()) do
    n = n + 1
    check(EUI.did(d, "CloseButton") and d.mark.alpha == 0, "the x is hidden under Dark's X")
  end
  check(n > 0, "take-out buttons were found")
  local errors = 0
  for k in pairs(NS.report) do if k:find("skin error", 1, true) then errors = errors + 1 end end
  check(errors == 0 and #EUI.bad == 0, "no skin errors")
`);

runFull('Dark on a client without the window templates', { dark: true }, `
  T.TEMPLATES.ButtonFrameTemplate, T.TEMPLATES.BasicFrameTemplateWithInset = nil, nil
  NS.db.style = "dark"
  T.fire("PLAYER_ENTERING_WORLD")
  T.drive()
  for _, name in ipairs({ "MacroBenchFrame", "MacroBenchTextFrame", "MacroBenchCheckFrame", "MacroBenchIconFrame", "MacroBenchSettingsFrame", "MacroBenchTutorialFrame" }) do
    local w = _G[name]
    check(EUI.did(w, "Shell") and T.backdrop(w) ~= nil, name .. " has Dark's backdrop")
    check(EUI.did(w.mbClose, "CloseButton") and w.mbClose.level > w.level, name .. " has Dark's close button, on top")
  end
  local errors = 0
  for k in pairs(NS.report) do if k:find("skin error", 1, true) then errors = errors + 1 end end
  check(errors == 0 and #EUI.bad == 0, "no skin errors")
`);

runFull('Blizzard chosen with EllesmereUI running: nothing is drawn', { eui: true }, `
  NS.db.style = "blizzard"
  EUI.fn(EUI_S)
  T.fire("PLAYER_ENTERING_WORLD")
  T.drive()
  check(next(EUI.by) == nil and NS.Styles.S == nil, "EllesmereUI's look is not used")
  check(NS.report.skin == "Blizzard (chosen in the options)", "the report says why: " .. tostring(NS.report.skin))
  T.checkTakeOuts(check, "art")
  T.checkSlider(check, false)
`);

runFull('with EllesmereUI calling back at login, everything built later is skinned as it is built', { eui: true }, `
  check(EUI.name == "MacroBench", "registered under the folder name")
  check(NS.report.skin:find("^Blizzard") ~= nil, "Blizzard's look until EllesmereUI calls back")
  EUI.fn(EUI_S)
  T.drive()
  T.checkSkinned(check)
`);

runFull('with the bench built before EllesmereUI calls back, the waiting list is done when it does', { eui: true }, `
  T.drive()
  check(next(EUI.by) == nil, "nothing is touched before EllesmereUI calls back")
  EUI.fn(EUI_S)
  NS.UI:Refresh()
  T.checkSkinned(check)
`);

runFull('on a client without the window templates, the fallback windows are skinned too', { eui: true }, `
  T.TEMPLATES.ButtonFrameTemplate, T.TEMPLATES.BasicFrameTemplateWithInset = nil, nil
  EUI.fn(EUI_S)
  T.drive()
  local main = _G.MacroBenchFrame
  check(main.template == "BackdropTemplate" and main.CloseButton == nil, "the bench fell back to a plain backdrop")
  for _, name in ipairs({ "MacroBenchFrame", "MacroBenchTextFrame", "MacroBenchCheckFrame", "MacroBenchIconFrame", "MacroBenchSettingsFrame", "MacroBenchTutorialFrame" }) do
    local w = _G[name]
    check(EUI.did(w, "Shell"), name .. " has the theme's window shell")
    check(EUI.did(w.mbClose, "CloseButton"), name .. " has the theme's close button")
    check(w.mbClose.level > EUI.border[w].level, name .. " close button is above the border")
  end
  main:Hide() main:Show()
  for i, c in ipairs(NS.UI.corners) do check(c.level > EUI.border[main].level, "corner button " .. i .. " is above the border after a show") end
  local errors = 0
  for k in pairs(NS.report) do if k:find("skin error", 1, true) then errors = errors + 1 end end
  check(errors == 0 and #EUI.bad == 0, "no skin errors")
`);

runFull('every window closes from its X in combat, nothing refused', {}, `
  T.drive()
  T.checkCloses(check)
`);

runFull('the fallback windows close from their X in combat too', {}, `
  T.TEMPLATES.ButtonFrameTemplate, T.TEMPLATES.BasicFrameTemplateWithInset = nil, nil
  T.drive()
  check(_G.MacroBenchFrame.CloseButton == nil and _G.MacroBenchFrame.mbClose ~= nil, "the bench fell back to its own X")
  T.checkCloses(check)
`);

runFull('in Dark every window still closes from its X in combat', { dark: true }, `
  NS.db.style = "dark"
  T.fire("PLAYER_ENTERING_WORLD")
  T.drive()
  check(EUI.did(_G.MacroBenchFrame.CloseButton, "CloseButton"), "Dark dressed the bench's X")
  T.checkCloses(check)
`);

runFull('with EllesmereUI every window still closes from its X in combat', { eui: true }, `
  EUI.fn(EUI_S)
  T.drive()
  check(EUI.did(_G.MacroBenchFrame.CloseButton, "CloseButton"), "EllesmereUI dressed the bench's X")
  T.checkCloses(check)
`);

runFull('EllesmereUI loaded with its Blizzard Skins+ module off', { eui: true, dispatch: false }, `
  T.fire("PLAYER_ENTERING_WORLD")
  check(NS.report.skin == "Blizzard (EllesmereUI's Blizzard Skins+ module is off)", "the report says the module is off")
  T.drive()
  check(next(EUI.by) == nil, "and nothing is skinned")
`);

runFull('EllesmereUI running but switched off for Macro Bench', { eui: true }, `
  T.fire("PLAYER_ENTERING_WORLD")
  check(NS.report.skin == "Blizzard (switched off for Macro Bench in EllesmereUI's options)", "the report says it is switched off")
`);

run('minimap button: left where a collector puts it, dragged round the rim on the minimap', `
-- A minimap button collector (EllesmereUI's, for one) takes the button off the minimap. Neither a
-- refresh nor a drag tick may put it back on the rim then; on the minimap a drag still moves it.
do
  NS.UI:UpdateMinimapButton()
  local mm = MacroBenchMinimapButton
  local function Script(f, e) return f.scripts[e] end
  local holder = CreateFrame("Frame", nil, UIParent)
  local own, setPoint = rawget(mm, "SetPoint"), mm.SetPoint
  local moves, rel = 0, nil
  rawset(mm, "SetPoint", function(self, ...) moves = moves + 1 rel = select(2, ...) return setPoint(self, ...) end)
  local center, escale, cursor = rawget(Minimap, "GetCenter"), rawget(Minimap, "GetEffectiveScale"), GetCursorPosition
  rawset(Minimap, "GetCenter", function() return 500, 500 end)
  rawset(Minimap, "GetEffectiveScale", function() return 1 end)
  GetCursorPosition = function() return 600, 560 end
  -- The game has both: a degree based global atan2 and the radian based math.atan2.
  local atan2Was, mathAtan2Was = atan2, math.atan2
  atan2 = atan2 or function(y, x) return math.deg(math.atan(y, x)) end
  math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  local function Drag()
    local start, stop = Script(mm, "OnDragStart"), Script(mm, "OnDragStop")
    if not start then return false end
    start(mm)
    local tick = Script(mm, "OnUpdate")
    if tick then tick(mm, 0.02) end
    if stop then stop(mm) end
    return tick ~= nil
  end
  mm:SetParent(holder)
  Drag()
  NS.UI:UpdateMinimapButton()
  check(moves == 0, "minimap: a button a collector (EllesmereUI's) has taken stays where the collector put it")
  mm:SetParent(Minimap)
  local dragged = Drag()
  check(dragged and moves > 0 and rel == Minimap, "minimap: on the minimap a drag still moves it round the rim")
  rawset(mm, "SetPoint", own)
  rawset(Minimap, "GetCenter", center)
  rawset(Minimap, "GetEffectiveScale", escale)
  GetCursorPosition = cursor
  atan2, math.atan2 = atan2Was, mathAtan2Was
end
`);

console.log(`\n${pass} checks passed, ${fail} scenario${fail === 1 ? '' : 's'} failed`);
process.exit(fail ? 1 : 0);
