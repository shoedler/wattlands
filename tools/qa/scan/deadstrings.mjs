// Read-only: csv keys with no literal use and no code that builds them from a literal prefix.
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const repo = process.cwd();
const all = execSync('git ls-files', { cwd: repo, encoding: 'utf8', maxBuffer: 1e9 }).split('\n').filter(Boolean);
const code = all.filter(f => /\.(gd|tscn|json|mjs)$/.test(f) && !f.startsWith('addons/gut') && !f.startsWith('tests/')).map(f => readFileSync(`${repo}/${f}`, 'utf8')).join('\n');
for (const c of all.filter(f => /^content\/.*\.csv$/.test(f))) {
  const keys = readFileSync(`${repo}/${c}`, 'utf8').split(/\r?\n/).slice(1).map(l => l.split(',')[0]).filter(Boolean);
  const dead = [];
  for (const k of keys) {
    if (code.includes(k)) continue;
    const parts = k.split('_'); let built = false;
    for (let i = parts.length - 1; i >= 2; i--) { const p = parts.slice(0, i).join('_') + '_'; if (code.includes(`"${p}`) || code.includes(`'${p}`)) { built = true; break; } }
    if (!built) dead.push(k);
  }
  console.log(`${c}: ${keys.length} keys, ${dead.length} dead: ${dead.join(' ')}`);
}
