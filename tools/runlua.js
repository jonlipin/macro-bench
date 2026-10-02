// Runs a Lua script in fengari (a Lua 5.3 VM in JS) with just enough of the game's API stubbed to
// load the addon's own files. The point is to exercise the real Grammar.Parse and Grammar.Compile
// rather than a reimplementation of them.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// print() goes to stdout.
lua.lua_register(L, to_luastring('print'), function (L) {
  const n = lua.lua_gettop(L);
  const parts = [];
  for (let i = 1; i <= n; i++) parts.push(to_jsstring(lauxlib.luaL_tolstring(L, i)));
  console.log(parts.join('\t'));
  return 0;
});

function dostring(src, chunkname) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(chunkname)) !== lua.LUA_OK) {
    throw new Error('load ' + chunkname + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
  if (lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
    throw new Error('LUA ERROR: ' + to_jsstring(lauxlib.luaL_tolstring(L, -1)));
  }
}

// The handful of game globals the addon touches while loading.
dostring(`
  ns = { report = {}, db = {} }
  function UnitClass() return "Warlock", "WARLOCK" end
  function UnitName(u) return "Someone", "" end
  function UnitExists() return false end
  function GetTime() return 0 end
  LOCALIZED_CLASS_NAMES_MALE = nil
  function ns.SafeIcon(i) return i end
  function ns.IconFor() return nil end
  function ns.IconName() return nil end
  function ns.KnowsSpell() return true end
  function ns.SpellInfo(n) return n end
  function ns.ItemInfo(n) return n end
`, 'stubs.lua');

// Load an addon file the way the game does: its vararg is the addon name and the shared table.
function loadAddonFile(file) {
  const src = fs.readFileSync(path.join('..', file), 'utf8');
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(file)) !== lua.LUA_OK) {
    throw new Error('load ' + file + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
  lua.lua_pushstring(L, to_luastring('MacroBench'));
  lua.lua_getglobal(L, to_luastring('ns'));
  if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) {
    throw new Error('LUA ERROR in ' + file + ': ' + to_jsstring(lauxlib.luaL_tolstring(L, -1)));
  }
}

for (const f of (process.env.MB_FILES || 'Grammar.lua,Templates.lua').split(',')) loadAddonFile(f);

const script = process.argv[2];
if (script) dostring(fs.readFileSync(script, 'utf8'), path.basename(script));
