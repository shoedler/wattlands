// What fast's GUT selection and planShards assume, checked on this repo's tree: no game's own code, tests or
// content names another game; game test groups that name res://build are found. Reads every game's own paths.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { REPO } from './helpers.mjs';
import { buildDirGroups, crossGameRefs, CROSS_SCAN_ROOTS, formatCrossRef, isScannedFile, listGutFiles } from '../lib/gate_core.mjs';

function registeredIds() {
  const root = path.join(REPO, 'src', 'games');
  return fs.readdirSync(root, { withFileTypes: true })
    .filter((e) => e.isDirectory() && e.name !== '_template' && fs.existsSync(path.join(root, e.name, 'game.json')))
    .map((e) => e.name)
    .sort();
}

function sourcesUnder(roots, keep) {
  const out = {};
  const walk = (rel) => {
    let entries;
    try {
      entries = fs.readdirSync(path.join(REPO, rel), { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;
      const child = `${rel}/${e.name}`;
      if (e.isDirectory()) walk(child);
      else if (keep(child)) out[child] = fs.readFileSync(path.join(REPO, child), 'utf8');
    }
  };
  for (const r of roots) walk(r.replace(/\/$/, ''));
  return out;
}

test("no game's own code, tests or content names another game, on this tree", () => {
  const ids = registeredIds();
  assert.ok(ids.length >= 2, `registered games: ${ids.join(', ')}`);
  const roots = ids.flatMap((id) => CROSS_SCAN_ROOTS.map((r) => r.replaceAll('<id>', id)));
  const sources = sourcesUnder(roots, isScannedFile);
  assert.ok(Object.keys(sources).length > 100, `${Object.keys(sources).length} files scanned`);
  assert.deepEqual(crossGameRefs(sources, ids).map(formatCrossRef), []);
});

// Not a rule: a game group that names res://build only stops splitting. This says which do today.
test('the game test groups that name res://build stay whole, and they are game groups', () => {
  const sources = sourcesUnder(['tests/games'], (f) => f.endsWith('.gd'));
  const pinned = buildDirGroups(sources, listGutFiles(REPO));
  for (const g of pinned) assert.match(g, /^tests\/games\/[^/]+\//, g);
});
