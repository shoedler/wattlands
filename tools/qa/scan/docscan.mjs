// Read-only: backticked paths and class names in docs that don't exist in the tree; orphan .uid and .import files.
import { execSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
const repo = process.cwd();
const all = execSync('git ls-files', { cwd: repo, encoding: 'utf8', maxBuffer: 1e9 }).split('\n').filter(Boolean);
const set = new Set(all);
const dirs = new Set(); for (const f of all) { const p = f.split('/'); for (let i = 1; i < p.length; i++) dirs.add(p.slice(0, i).join('/')); }
const orph = all.filter(f => /\.(uid|import)$/.test(f) && !set.has(f.replace(/\.(uid|import)$/, '')));
console.log('ORPHAN uid/import:', orph.length); for (const o of orph) console.log('  ' + o);
const classes = new Set();
for (const f of all.filter(f => f.endsWith('.gd'))) { const m = readFileSync(`${repo}/${f}`, 'utf8').match(/^class_name\s+(\w+)/m); if (m) classes.add(m[1]); }
const allText = all.filter(f => /\.(gd)$/.test(f)).map(f => readFileSync(`${repo}/${f}`, 'utf8')).join('\n');
const docs = process.argv.slice(2);
const exts = /\.(gd|json|csv|png|tscn|mjs|sh|ps1|yml|md|cfg|py|ts|webp|gdshader|tres|txt)$/;
for (const d of docs) {
  const t = readFileSync(`${repo}/${d}`, 'utf8'); const lines = t.split(/\r?\n/);
  const bad = [];
  lines.forEach((l, i) => {
    for (const m of l.matchAll(/`([^`\n]+)`/g)) {
      const raw = m[1].trim().replace(/^res:\/\//, '').replace(/[,.;:]$/, '');
      const tok = raw.split(/\s/)[0];
      if (/^[A-Za-z_.][\w./-]*$/.test(tok) && tok.includes('/') && (exts.test(tok) || tok.endsWith('/')) && !tok.includes('<') && !tok.startsWith('build/') && !tok.startsWith('user:')) {
        const clean = tok.replace(/\/$/, '');
        if (!set.has(clean) && !dirs.has(clean) && !existsSync(`${repo}/${clean}`)) {
          // relative to the doc?
          const rel = d.split('/').slice(0, -1).join('/') + '/' + clean;
          if (!set.has(rel) && !dirs.has(rel)) bad.push(`${d}:${i + 1} path ${tok}`);
        }
      } else if (/^[A-Z][a-z]+[A-Z][A-Za-z0-9]*(\.[a-z_]+)?(\(\))?$/.test(tok)) {
        const cls = tok.split('.')[0].replace('()', '');
        if (!classes.has(cls) && !allText.includes(cls)) bad.push(`${d}:${i + 1} class ${tok}`);
      }
    }
  });
  console.log(`\n== ${d}: ${bad.length}`); for (const b of bad.slice(0, 40)) console.log('  ' + b);
}
