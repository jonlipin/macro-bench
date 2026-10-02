#!/bin/sh
# Everything that can be checked without the game. Run from tools/.
set -e
F="../Core.lua ../Grammar.lua ../Validate.lua ../Templates.lua ../Tutorial.lua ../UI.lua"
echo "=== syntax (Lua 5.1) ==="      && node syntax.js $F
echo "=== upvalue limit ==="         && node upvalues.js $F
echo "=== used before declared ===" && node tooearly.js $F
echo "=== templates: round trip, length, script bodies ==="
MB_FILES=Grammar.lua,Templates.lua node runlua.js audit.lua
