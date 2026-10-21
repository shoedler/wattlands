// The budget stop (BRIEF 3.10): generate.mjs stops before this run's estimated spend would pass
// --budget (default $10), summing max(estimate, billed) per request.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { childEnv, makeRoot, mockArgs, mockFor, readManifest, removeRoot, runGenerate, smallArt } from './helpers.mjs';

const GAME = 'bud';

/** n transparent sprites, each requested at the base price ($0.07 on sunburst). */
function artWith(n) {
  return smallArt({
    sprites: Array.from({ length: n }, (_, i) => ({ id: `s${i}`, prompt: `sprite number ${i}`, size: [32, 32] })),
  });
}

async function setup(t, n, mockConfig = {}) {
  const mock = await mockFor(t, mockConfig);
  const root = makeRoot(GAME, artWith(n));
  t.after(() => removeRoot(root));
  return { mock, root };
}

test('the run stops before the request that would pass --budget and exits 3', async (t) => {
  const { mock, root } = await setup(t, 5);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--budget=0.2', '--concurrency=1']), { env: childEnv() });
  assert.equal(r.code, 3, r.stderr + r.stdout);
  assert.equal(mock.state.counts.submit, 2, '2 x $0.07 = $0.14; a third would make $0.21');
  assert.match(r.stderr, /budget stop: s2 \(\$0\.0700\) would take this run's estimated spend from \$0\.1400 past the --budget of \$0\.2000; not paid: s2, s3, s4/);
  const m = readManifest(root, GAME);
  assert.equal(m.requests.length, 2);
  assert.equal(m.spend.total_usd, 0.14);
});

test('an exact fit is allowed', async (t) => {
  const { mock, root } = await setup(t, 3);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--budget=0.21']), { env: childEnv() });
  assert.equal(r.code, 0, r.stderr);
  assert.equal(mock.state.counts.submit, 3);
});

test('a budget below one request pays for nothing', async (t) => {
  const { mock, root } = await setup(t, 2);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--budget=0.05']), { env: childEnv() });
  assert.equal(r.code, 3);
  assert.equal(mock.state.counts.submit, 0);
});

test('billed amounts above the estimate count: the stop sums max(estimate, billed)', async (t) => {
  // Each request bills $0.10 against a $0.07 estimate. With concurrency 1 the run knows the bills:
  // $0.10 after one, then $0.10 + $0.07 = $0.17 <= $0.25 so a second goes, then $0.20 + $0.07 > $0.25.
  const { mock, root } = await setup(t, 5, { report_billed: true, billed_usd: 0.1 });
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--budget=0.25', '--concurrency=1']), { env: childEnv() });
  assert.equal(r.code, 3, r.stderr);
  assert.equal(mock.state.counts.submit, 2);
  assert.match(r.stderr, /from \$0\.2000 past the --budget of \$0\.2500/);
  assert.equal(readManifest(root, GAME).spend.total_usd, 0.2);
});

test('cached and recovered results cost nothing against the budget', async (t) => {
  const { mock, root } = await setup(t, 3);
  assert.equal((await runGenerate(mockArgs(GAME, root, mock), { env: childEnv() })).code, 0);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--budget=0']), { env: childEnv() });
  assert.equal(r.code, 0, r.stderr);
  assert.match(r.stdout, /0 paid, 3 cached/);
});

test('the default budget is $10', async (t) => {
  const { mock, root } = await setup(t, 1);
  const r = await runGenerate(mockArgs(GAME, root, mock), { env: childEnv() });
  assert.equal(r.code, 0);
  assert.match(r.stdout, /of \$10\.0000 budget/);
});

test('with several requests in flight the stop still holds the estimate line', async (t) => {
  const { mock, root } = await setup(t, 8);
  const r = await runGenerate(mockArgs(GAME, root, mock, ['--budget=0.35', '--concurrency=4']), { env: childEnv() });
  assert.equal(r.code, 3);
  assert.equal(mock.state.counts.submit, 5);
  assert.ok(readManifest(root, GAME).spend.total_usd <= 0.35);
});
