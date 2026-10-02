// What the game's loadstring() would say about a /run body, without running it.
// Usage: node syntax.js file.lua ...   (or: echo 'body' | node syntax.js -)
const luaparse = require('luaparse');
const fs = require('fs');

function check(label, src) {
  try {
    const ast = luaparse.parse(src, { luaVersion: '5.1' });
    const kinds = ast.body.map(s => s.type.replace('Statement', '')).join(', ');
    console.log(`ok    ${label}`);
    console.log(`      ${ast.body.length} statement(s): ${kinds}`);
    return true;
  } catch (e) {
    console.log(`ERROR ${label}`);
    console.log(`      ${e.message}`);
    return false;
  }
}

const args = process.argv.slice(2);
let bad = 0;
if (args[0] === '-') {
  const src = fs.readFileSync(0, 'utf8');
  if (!check('(stdin)', src)) bad++;
} else {
  for (const f of args) if (!check(require('path').basename(f), fs.readFileSync(f, 'utf8'))) bad++;
}
process.exit(bad ? 1 : 0);
