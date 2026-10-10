// A name used above the line its local is declared on is not that local: Lua has not seen the
// declaration yet, so the name compiles to a global lookup, which is nil. It runs until the moment
// the line is reached, then dies with "attempt to call a nil value (global 'x')". This has bitten
// twice, so it is checked.
const luaparse = require('luaparse');
const fs = require('fs');

function blockDecls(body) {
  const at = new Map();
  const put = (n, line) => { if (n && n.type === 'Identifier' && !at.has(n.name)) at.set(n.name, line); };
  for (const st of body || []) {
    if (st.type === 'LocalStatement') st.variables.forEach(v => put(v, st.loc.start.line));
    else if (st.type === 'FunctionDeclaration' && st.isLocal) put(st.identifier, st.loc.start.line);
  }
  return at;
}

function analyze(file) {
  const ast = luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.1', locations: true });
  const found = [];
  const scopes = [];
  const declare = n => { if (n && n.type === 'Identifier') scopes[scopes.length - 1].at.set(n.name, 0); };
  const push = body => scopes.push({ at: blockDecls(body) });

  const use = (name, line) => {
    let later = null;
    for (let i = scopes.length - 1; i >= 0; i--) {
      const declared = scopes[i].at.get(name);
      if (declared === undefined) continue;
      if (declared <= line) return;
      if (later === null) later = declared;
    }
    if (later !== null) found.push({ name, line, declared: later });
  };

  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) return node.forEach(walk);
    switch (node.type) {
      case 'LocalStatement': walk(node.init); return;
      case 'FunctionDeclaration':
        if (!node.isLocal && node.identifier) walk(node.identifier);
        push(node.body); node.parameters.forEach(declare); walk(node.body); scopes.pop();
        return;
      case 'ForNumericStatement':
        walk(node.start); walk(node.end); walk(node.step);
        push(node.body); declare(node.variable); walk(node.body); scopes.pop();
        return;
      case 'ForGenericStatement':
        walk(node.iterators);
        push(node.body); node.variables.forEach(declare); walk(node.body); scopes.pop();
        return;
      case 'DoStatement': case 'WhileStatement': case 'RepeatStatement': case 'IfClause':
      case 'ElseifClause': case 'ElseClause':
        push(node.body);
        for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc') walk(node[k]);
        scopes.pop();
        return;
      case 'Identifier': use(node.name, node.loc.start.line); return;
      case 'MemberExpression': walk(node.base); return;
      case 'TableKeyString': walk(node.value); return;
    }
    for (const k of Object.keys(node)) if (k !== 'type' && k !== 'loc') walk(node[k]);
  };
  push(ast.body);
  walk(ast.body);
  return found;
}

let bad = 0;
for (const file of process.argv.slice(2)) {
  const found = analyze(file);
  bad += found.length;
  console.log(`${found.length ? 'EARLY' : 'ok   '}${require('path').basename(file).padEnd(14)} ${found.length} used before declared`);
  found.forEach(f => console.log(`        line ${f.line}: '${f.name}' is a global here; its local is declared on line ${f.declared}`));
}
process.exit(bad ? 1 : 0);
