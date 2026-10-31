// Read-only: per "# ---" section of a GDScript file: its size and which other sections its code names.
import { readFileSync } from 'node:fs';
const file = process.argv[2];
const lines = readFileSync(file, 'utf8').split(/\r?\n/);
const secs = [{ name: 'HEAD', start: 0, names: new Set(), text: [] }];
const owner = new Map();
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  const m = l.match(/^# --- (.+?) -+\s*$/);
  if (m) { secs.push({ name: m[1].slice(0, 28), start: i, names: new Set(), text: [] }); continue; }
  const s = secs[secs.length - 1];
  s.text.push(l);
  const d = l.match(/^(?:static )?(?:func|var|const)\s+(\w+)/) || l.match(/^class\s+(\w+)/);
  if (d) { owner.set(d[1], s.name); s.names.add(d[1]); }
}
const nameToSec = owner;
for (const s of secs) {
  const deps = new Map();
  const code = s.text.map(t => t.replace(/#.*$/, '').replace(/"[^"]*"/g, '""')).join('\n');
  for (const m of code.matchAll(/(^|[^.\w])([A-Za-z_]\w*)/g)) {
    const o = nameToSec.get(m[2]);
    if (o && o !== s.name) { if (!deps.has(o)) deps.set(o, new Set()); deps.get(o).add(m[2]); }
  }
  console.log(`\n[${s.name}] L${s.start + 1} ${s.text.length} lines`);
  for (const [o, set] of deps) console.log(`   -> ${o}: ${[...set].slice(0, 14).join(' ')}${set.size > 14 ? ' +' + (set.size - 14) : ''}`);
}
