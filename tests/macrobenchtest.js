// Offline checks for Macro Bench: loads the addon's Lua into fengari against a stubbed client and
// drives the slash command.
//   NODE_PATH=<dir with fengari> node tests/macrobenchtest.js [--verbose]
'use strict';
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const ROOT = path.join(__dirname, '..');
const VERBOSE = process.argv.includes('--verbose');
const FILES = ['Core.lua', 'Grammar.lua', 'UI.lua'];

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
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:GetEffectiveScale() return 1 end
function CreateFrame(kind, name)
  local f = setmetatable({ scripts = {}, events = {}, name = name }, Frame)
  T.frames[#T.frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = CreateFrame("Frame", "UIParent")
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
function run(name, body) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const code = STUBS + loader() +
    `local function check(ok, what) if ok then CHECKS_PASS = (CHECKS_PASS or 0) + 1 else error("FAILED: " .. what, 2) end end\n` +
    body;
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

console.log(`\n${pass} checks passed, ${fail} scenario${fail === 1 ? '' : 's'} failed`);
process.exit(fail ? 1 : 0);
