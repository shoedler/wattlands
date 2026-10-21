// W4r2 R24: a submit that never left this machine (connection refused, no DNS answer, a failed TLS
// handshake) is not money spent: it is submit_failed, the budget share is released, and the run
// stops submitting. A lost answer after connecting still counts as paid (W3 ART-W3-3, budget.test.mjs).
// Mock only: no key, no WATTLANDS_ALLOW_ART.
import assert from 'node:assert/strict';
import net from 'node:net';
import { test } from 'node:test';
import { FalError, notSentCode, transportCode } from '../lib/fal.mjs';
import { submitSurelyRejected } from '../lib/generate.mjs';
import { childEnv, makeRoot, mockArgs, mockFor, readManifest, removeRoot, runGenerate, smallArt } from './helpers.mjs';

const GAME = 'off';

/** A loopback port nothing listens on. */
async function closedPort() {
  const s = net.createServer();
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  const { port } = s.address();
  await new Promise((r) => s.close(r));
  return port;
}

function art3() {
  return smallArt({
    sprites: [
      { id: 's0', prompt: 'sprite zero', size: [32, 32] },
      { id: 's1', prompt: 'sprite one', size: [32, 32] },
      { id: 's2', prompt: 'sprite two', size: [32, 32] },
    ],
  });
}

test('connect-phase and TLS errors prove the submit never left; resets and timeouts do not', () => {
  const fetchFailed = (cause) => Object.assign(new TypeError('fetch failed'), { cause });
  assert.equal(transportCode(fetchFailed({ code: 'ECONNREFUSED' })), 'ECONNREFUSED');
  const both = new AggregateError([Object.assign(new Error('a'), { code: 'ECONNREFUSED' })], 'all failed');
  assert.equal(transportCode(fetchFailed(both)), 'ECONNREFUSED', 'happy eyeballs: the code sits on the inner errors');
  assert.equal(transportCode(new Error('plain')), null);
  for (const code of ['ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN', 'UND_ERR_CONNECT_TIMEOUT', 'CERT_HAS_EXPIRED', 'ERR_TLS_CERT_ALTNAME_INVALID', 'ERR_SSL_WRONG_VERSION_NUMBER']) {
    assert.ok(notSentCode(code), code);
    assert.ok(submitSurelyRejected(new FalError(`POST failed: ${code}`, { code, notSent: notSentCode(code) })), code);
  }
  for (const code of ['ECONNRESET', 'EPIPE', 'UND_ERR_SOCKET', 'UND_ERR_HEADERS_TIMEOUT', null]) {
    assert.ok(!notSentCode(code), String(code));
    assert.ok(!submitSurelyRejected(new FalError(`POST failed: ${code}`, { code, notSent: notSentCode(code) })), `${code} stays ambiguous`);
  }
  assert.ok(submitSurelyRejected(new FalError('HTTP 500', { status: 500 })));
  assert.ok(!submitSurelyRejected(new FalError('not JSON', { status: 200 })), 'an unreadable answer stays ambiguous');
});

test('an offline run pays nothing, stops submitting, and a later run pays each sprite once', async (t) => {
  const root = makeRoot(GAME, art3());
  t.after(() => removeRoot(root));
  const env = childEnv();
  const down = { url: `http://127.0.0.1:${await closedPort()}` };
  const a = await runGenerate(mockArgs(GAME, root, down, ['--concurrency=1']), { env });
  assert.equal(a.code, 1, a.stdout + a.stderr);
  assert.match(a.stderr, /s0: submit failed: .*ECONNREFUSED.*nothing was paid/);
  assert.match(a.stderr, /stopped submitting: fal can't be reached/);
  assert.match(a.stderr, /not submitted: s1, s2/);
  assert.doesNotMatch(a.stderr, /counted as paid/);
  let m = readManifest(root, GAME);
  assert.deepEqual(m.requests.map((e) => `${e.sprite}:${e.status}:${e.paid}`), ['s0:submit_failed:false'], 'one attempt, not paid');
  assert.equal(m.spend.total_usd, 0, 'nothing spent');

  const mock = await mockFor(t);
  const b = await runGenerate(mockArgs(GAME, root, mock), { env });
  assert.equal(b.code, 0, b.stdout + b.stderr);
  m = readManifest(root, GAME);
  assert.equal(mock.state.counts.submit, 3, 'each sprite paid once');
  assert.equal(m.spend.total_usd, mock.state.billed_total_usd, 'the manifest spend is what fal billed');
});
