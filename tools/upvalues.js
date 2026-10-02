// Lua 5.1 lets a function reach at most 60 locals of the scopes around it. The test VM is 5.3 and
// allows far more, so this counts them the way the game's own Lua would, before the game refuses to
// load the file at all.
const luaparse = require('luaparse');
const fs = require('fs');
const LIMIT = 60;

function analyse(file) {
  const ast = luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.1', locations: true });
  const funcs = [];
  const scopes = [{ vars: new Set(), fn: null }];
  const declare = n => { if (n && n.type === 'Identifier') scopes[scopes.length - 1].vars.add(n.name); };
  const use = name => {
    for (let i = scopes.length - 1; i >= 0; i--) {
      if (scopes[i].vars.has(name)) {
        const owner = scopes[i].fn;
        for (let j = scopes.length - 1; j >= 0; j--) {
          const f = scopes[j].fn;
          if (!f || f === owner) break;
          f.upvalues.add(name);
        }
        return;
      }
    }
  };
  const walk = (node, fn) => {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) return node.forEach(n => walk(n, fn));
    switch (node.type) {
      case 'LocalStatement':
        walk(node.init, fn); node.variables.forEach(declare); return;
      case 'FunctionDeclaration': {
        if (node.isLocal && node.identifier) declare(node.identifier);
        else if (node.identifier) walk(node.identifier, fn);
        const id = node.identifier;
        const rec = {
          line: node.loc.start.line,
          name: id ? (id.name || ((id.base ? id.base.name : '?') + ':' + (id.identifier ? id.identifier.name : '?'))) : '(anonymous)',
          upvalues: new Set(),
        };
        funcs.push(rec);
        scopes.push({ vars: new Set(), fn: rec });
        node.parameters.forEach(declare);
        walk(node.body, rec);
        scopes.pop();
        return;
      }
      case 'ForNumericStatement':
        walk(node.start, fn); walk(node.end, fn); walk(node.step, fn);
        scopes.push({ vars: new Set(), fn }); declare(node.variable); walk(node.body, fn); scopes.pop();
        return;
      case 'ForGenericStatement':
        walk(node.iterators, fn);
        scopes.push({ vars: new Set(), fn }); node.variables.forEach(declare); walk(node.body, fn); scopes.pop();
        return;
      case 'DoStatement': case 'WhileStatement': case 'RepeatStatement': case 'IfClause':
      case 'ElseifClause': case 'ElseClause':
        scopes.push({ vars: new Set(), fn });
        for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc') walk(node[k], fn);
        scopes.pop();
        return;
      case 'Identifier': use(node.name); return;
      case 'MemberExpression': walk(node.base, fn); return;
      case 'TableKeyString': walk(node.value, fn); return;
    }
    for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc') walk(node[k], fn);
  };
  walk(ast.body, null);
  return funcs;
}

let bad = 0;
for (const file of process.argv.slice(2)) {
  const funcs = analyse(file).sort((a, b) => b.upvalues.size - a.upvalues.size);
  const worst = funcs.slice(0, 3).map(f => `${f.name}@${f.line}=${f.upvalues.size}`).join('  ');
  const over = funcs.filter(f => f.upvalues.size > LIMIT);
  bad += over.length;
  console.log(`${over.length ? 'OVER ' : 'ok   '}${require('path').basename(file).padEnd(14)} worst: ${worst}`);
  over.forEach(f => console.log(`        ${f.name} at line ${f.line} holds ${f.upvalues.size} upvalues (Lua 5.1 allows ${LIMIT})`));
}
process.exit(bad ? 1 : 0);
