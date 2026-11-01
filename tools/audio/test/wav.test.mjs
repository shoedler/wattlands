import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decodeWav, deinterleave, encodeWav, readCapture } from '../lib/wav.mjs';

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

test('a capture reads as PCM16 or float32, and float keeps what is over full scale', () => {
  const head = Buffer.alloc(44);
  head.write('RIFF', 0, 'ascii');
  head.writeUInt32LE(36 + 8, 4);
  head.write('WAVEfmt ', 8, 'ascii');
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(3, 20);
  head.writeUInt16LE(2, 22);
  head.writeUInt32LE(48000, 24);
  head.writeUInt32LE(48000 * 8, 28);
  head.writeUInt16LE(8, 32);
  head.writeUInt16LE(32, 34);
  head.write('data', 36, 'ascii');
  head.writeUInt32LE(8, 40);
  const data = Buffer.alloc(8);
  data.writeFloatLE(1.5, 0);
  data.writeFloatLE(-0.25, 4);
  const c = readCapture(Buffer.concat([head, data]));
  assert.equal(c.rate, 48000);
  assert.equal(c.x[0][0], 1.5);
  assert.equal(c.x[1][0], -0.25);
  const pcm = readCapture(encodeWav(Int16Array.from([16384, -16384]), { rate: 22050, ch: 2 }));
  assert.equal(pcm.x[0][0], 0.5);
  assert.equal(pcm.x[1][0], -0.5);
  head.writeUInt16LE(7, 20);
  assert.throws(() => readCapture(Buffer.concat([head, data])));
});
