// Read-only: reachability of the static functions in Tank's generators (assets/tank/v3/tools_src and
// assets/tank/v4/tools_src) from the bake entry points. Run it from the repo root. A func counts as live when an
// entry point reaches it; so does whatever a reached module's top-level code (constants, inner classes) names.
// Everything is .gdignore'd, so no gate sees these files: this walk is the only check.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
const root = `${process.cwd()}/assets/tank/`;
const list = (dir) => existsSync(root + dir) ? readdirSync(root + dir).filter(f => f.endsWith('.gd')).map(f => dir + f) : [];
const files = [...list('v3/tools_src/'), ...list('v3/tools_src/env/'), ...list('v4/tools_src/')];
const mods = {};
for (const f of files) {
  const src = readFileSync(root + f, 'utf8');
  const aliases = {};
  for (const m of src.matchAll(/^const (\w+) *:?= *preload\("res:\/\/assets\/tank\/(v[34]\/tools_src\/[\w/]+\.gd)"\)/gm)) aliases[m[1]] = m[2];
  const funcs = {};
  const lines = src.split(/\r?\n/);
  let cur = null; const top = [];
  for (const l of lines) {
    const m = l.match(/^(?:static )?func (\w+)/);
    if (m) { cur = m[1]; funcs[cur] = []; continue; }
    if (cur && /^(const|var|class|##|#)\b/.test(l)) cur = null;
    if (cur) funcs[cur].push(l); else top.push(l.replace(/"[^"]*"/g, '""').replace(/#.*$/, ''));
  }
  mods[f] = { aliases, funcs, top: top.join('\n'), lines: lines.length };
}
const seen = new Set();
const reached = new Set();
function names(f, text) {
  for (const m of text.matchAll(/\b([A-Z]\w*)\.(\w+)/g)) { const t = mods[f].aliases[m[1]]; if (t) visit(t, m[2]); }
  // Calls and Callable refs by bare name
  for (const m of text.matchAll(/\b([A-Za-z_]\w*)\b/g)) if (mods[f].funcs[m[1]]) visit(f, m[1]);
}
function visit(f, fn) {
  const k = f + '::' + fn; if (seen.has(k) || !mods[f]?.funcs[fn]) return; seen.add(k);
  reach(f);
  names(f, mods[f].funcs[fn].join('\n'));
}
function reach(f) {
  if (reached.has(f) || !mods[f]) return;
  reached.add(f);
  names(f, mods[f].top);
}
const v4 = files.filter(f => f.startsWith('v4/'));
const entry = ['v3/tools_src/bake.gd', 'v3/tools_src/r6_base.gd', 'v3/tools_src/env/env_planes.gd', 'v3/tools_src/env/contact.gd', ...v4];
const roots = process.argv.slice(2).length ? process.argv.slice(2) : entry;
for (const r of roots) {
  reach(r);
  for (const fn of Object.keys(mods[r]?.funcs || {})) visit(r, fn);
}
for (const f of files) {
  const all = Object.keys(mods[f].funcs); const live = all.filter(x => seen.has(f + '::' + x));
  const liveLines = live.reduce((a, x) => a + mods[f].funcs[x].length + 1, 0);
  console.log(`${f}: ${mods[f].lines}L funcs ${live.length}/${all.length} live, ~${liveLines} live lines; dead: ${all.filter(x => !seen.has(f + '::' + x)).join(' ')}`);
}
