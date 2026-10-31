import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decodeWav, deinterleave, encodeWav } from '../lib/wav.mjs';

test('a WAV round-trips, canonical header', () => {
  const s = Int16Array.from([0, 16, -16, 32752, -32752, 8]);
  const b = encodeWav(s, { rate: 22050, ch: 2 });
  assert.equal(b.length, 44 + 12);
  assert.equal(b.toString('ascii', 0, 4), 'RIFF');
  assert.equal(b.readUInt32LE(4), 36 + 12);
  assert.equal(b.readUInt32LE(28), 22050 * 4);
  const d = decodeWav(b);
  assert.equal(d.rate, 22050);
  assert.equal(d.ch, 2);
  assert.equal(d.frames, 3);
  assert.deepEqual(d.samples, s);
});

test('decodeWav steps over other chunks', () => {
  const plain = encodeWav(Int16Array.from([1, 2]), { rate: 11025, ch: 1 });
  const extra = Buffer.concat([plain.subarray(0, 36), Buffer.from('LIST'), Buffer.from([3, 0, 0, 0, 9, 9, 9, 0]), plain.subarray(36)]);
  assert.deepEqual(decodeWav(extra).samples, Int16Array.from([1, 2]));
});

test('decodeWav refuses what is not PCM16', () => {
  assert.throws(() => decodeWav(Buffer.from('nope nope nope')), /RIFF/);
  const b = encodeWav(Int16Array.from([1]), { rate: 11025, ch: 1 });
  b.writeUInt16LE(3, 20);
  assert.throws(() => decodeWav(b), /only PCM16/);
  assert.throws(() => decodeWav(encodeWav(new Int16Array(0), { rate: 11025, ch: 1 }).subarray(0, 36)), /no data chunk/);
});

test('deinterleave splits and scales', () => {
  const [l, r] = deinterleave(Int16Array.from([16384, -16384, 0, 8192]), 2);
  assert.deepEqual([...l], [0.5, 0]);
  assert.deepEqual([...r], [-0.5, 0.25]);
});
