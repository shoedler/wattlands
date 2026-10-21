// --dry-run (BRIEF 3.10, docs/OWNERSHIP.md ART2): prints each sprite's request size, aspect error,
// estimated cost and the total, lists sprites outside the endpoint limits, and contacts nothing.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import {
  childEnv,
  DUMMY_KEY_PARTS,
  makeRoot,
  mockArgs,
  mockFor,
  NO_NETWORK_PRELOAD,
  removeRoot,
  runGenerate,
  smallArt,
} from './helpers.mjs';

const GAME = 'dry';

async function setup(t, art = smallArt()) {
  const mock = await mockFor(t);
  const root = makeRoot(GAME, art);
  t.after(() => removeRoot(root));
  return { mock, root };
}

test('the plan: request sizes, aspect error in %, estimates, total and the sprites outside the limits', async (t) => {
  const { mock, root } = await setup(t);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--dry-run']), { env: childEnv() });
  assert.equal(r.code, 0, r.stderr);
  const out = r.stdout;
  assert.match(out, /art plan for dry: openai\/gpt-image-2\.5\/sunburst\/text-to-image, quality high \(dry run: nothing contacted\)/);
  assert.match(out, /boat\s+80x32\s+1600x640\s+\+0\.00%\s+\$0\.0700\s+new/);
  assert.match(out, /reef\s+416x18\s+\d+x\d+\s+-8\d\.\d\d%\s+\$0\.0700\s+new \(tile segment\)/);
  assert.match(out, /total: 4 request\(s\) to pay, \$0\.2800 estimated; 0 cached; budget \$10\.0000/);
  assert.match(out, /budget: the plan fits/);
  assert.match(out, /outside the endpoint limits \(requested at the nearest allowed aspect\):\n\s+reef 416x18 \(23\.11:1\) -> \d+x\d+ \(3\.00:1\)/);
  assert.equal(mock.state.log.length, 0, 'the mock was never contacted');
  assert.equal(fs.existsSync(path.join(root, 'assets', GAME, 'art_manifest.json')), false, 'no manifest written');
  assert.equal(fs.existsSync(path.join(root, '.art_cache')), false);
});

test('--json gives the same plan as data', async (t) => {
  const { mock, root } = await setup(t);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--dry-run', '--json']), { env: childEnv() });
  assert.equal(r.code, 0);
  const plan = JSON.parse(r.stdout);
  assert.equal(plan.sprites.length, 4);
  assert.equal(plan.to_pay_usd, 0.28);
  const reef = plan.sprites.find((s) => s.id === 'reef');
  assert.equal(reef.outside_limits, true);
  assert.equal(reef.tile, true);
  assert.deepEqual(plan.outside_limits, ['reef']);
  const boat = plan.sprites.find((s) => s.id === 'boat');
  assert.deepEqual(boat.request, [1600, 640]);
  assert.equal(boat.aspect_error_pct, 0);
  assert.equal(mock.state.log.length, 0);
});

test('cached sprites cost nothing in the plan; --only narrows it; a small budget shows the stop', async (t) => {
  const { mock, root } = await setup(t);
  assert.equal((await runGenerate(mockArgs(GAME, root, mock, ['--only=boat']), { env: childEnv() })).code, 0);
  const before = mock.state.log.length;
  let r = await runGenerate(mockArgs(GAME, root, mock, ['--dry-run']), { env: childEnv() });
  assert.match(r.stdout, /boat\s+80x32\s+1600x640\s+\+0\.00%\s+\$0\.0000\s+cached/);
  assert.match(r.stdout, /total: 3 request\(s\) to pay, \$0\.2100 estimated; 1 cached/);
  assert.match(r.stdout, /manifest spend so far \$0\.0700/);
  r = await runGenerate(mockArgs(GAME, root, mock, ['--dry-run', '--only=fish_tuna']), { env: childEnv() });
  assert.doesNotMatch(r.stdout, /boat/);
  assert.match(r.stdout, /fish_tuna/);
  r = await runGenerate(mockArgs(GAME, root, mock, ['--dry-run', '--budget=0.1']), { env: childEnv() });
  assert.match(r.stdout, /budget: this run would stop before bg_sky/);
  r = await runGenerate(mockArgs(GAME, root, mock, ['--dry-run', '--reroll=boat']), { env: childEnv() });
  assert.match(r.stdout, /boat\s+80x32\s+1600x640\s+\+0\.00%\s+\$0\.0700\s+reroll/);
  assert.equal(mock.state.log.length, before, 'dry runs never contact the mock');
});

test('a dry run opens no socket and needs no key, even with a dummy key set', async (t) => {
  const root = makeRoot(GAME, smallArt());
  t.after(() => removeRoot(root));
  const log = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wattlands_nonet_')), 'attempts.log');
  t.after(() => fs.rmSync(path.dirname(log), { recursive: true, force: true }));
  // A loopback --mock URL nobody listens on: the dry run must not try it.
  const r = await runGenerate([`--game=${GAME}`, `--root=${root}`, '--mock=http://127.0.0.1:9', '--dry-run'], {
    env: childEnv({ dummyKey: true, extra: { NO_NET_LOG: log } }),
    preload: NO_NETWORK_PRELOAD,
  });
  assert.equal(r.code, 0, r.stderr);
  assert.equal(fs.existsSync(log), false, fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '');
  for (const p of DUMMY_KEY_PARTS) assert.equal(r.stdout.includes(p) || r.stderr.includes(p), false);
});
