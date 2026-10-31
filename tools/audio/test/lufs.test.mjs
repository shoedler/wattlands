import assert from 'node:assert/strict';
import { test } from 'node:test';
import { integratedLufs, kWeighting, loudnessRange, momentaryMaxLufs, momentaryTrack, truePeakDb } from '../lib/lufs.mjs';
import { dbToGain } from '../lib/dsp.mjs';
import { sineWave } from './helpers.mjs';

function near(a, b, tol, msg) {
  assert.ok(Math.abs(a - b) <= tol, `${msg ?? ''} ${a} vs ${b}`);
}

test('K-weighting at 48 kHz gives the coefficients printed in BS.1770', () => {
  const { shelf, hp } = kWeighting(48000);
  near(shelf.b0, 1.53512485958697, 1e-9);
  near(shelf.b1, -2.69169618940638, 1e-9);
  near(shelf.b2, 1.19839281085285, 1e-9);
  near(shelf.a1, -1.69065929318241, 1e-9);
  near(shelf.a2, 0.73248077421585, 1e-9);
  near(hp.a1, -1.99004745483398, 1e-9);
  near(hp.a2, 0.99007225036621, 1e-9);
});

test('EBU R128: a 1 kHz stereo sine at -23 dBFS reads -23 LUFS at any rate', () => {
  for (const rate of [11025, 22050, 44100, 48000]) {
    const x = sineWave(997, 20, rate, dbToGain(-23));
    near(integratedLufs([x, x], rate), -23, 0.1, `${rate} Hz`);
  }
});

test('mono counts one channel: 3 dB under stereo', () => {
  const x = sineWave(997, 5, 22050, dbToGain(-23));
  near(integratedLufs([x], 22050), -26.01, 0.1);
});

test('the absolute gate drops silence, the relative gate drops the quiet part', () => {
  const rate = 22050;
  const loud = sineWave(997, 10, rate, dbToGain(-23));
  const withSilence = new Float64Array(loud.length * 2);
  withSilence.set(loud, loud.length);
  near(integratedLufs([withSilence, withSilence], rate), -23, 0.1, 'silence');
  const quiet = sineWave(997, 10, rate, dbToGain(-43));
  const both = new Float64Array(loud.length * 2);
  both.set(quiet, 0);
  both.set(loud, loud.length);
  near(integratedLufs([both, both], rate), -23, 0.2, 'relative gate');
  assert.equal(integratedLufs([new Float64Array(rate)], rate), -120);
});

test('momentary max follows the loudest 400 ms; a short sound counts as padded', () => {
  const rate = 22050;
  const x = sineWave(997, 5, rate, dbToGain(-40));
  const burst = sineWave(997, 1, rate, dbToGain(-20));
  x.set(burst, rate * 2);
  near(momentaryMaxLufs([x, x], rate), -20, 0.2);
  const short = sineWave(997, 0.1, rate, dbToGain(-20));
  near(momentaryMaxLufs([short, short], rate), -20 - 6.02, 0.3, '100 ms in 400 ms');
  const t = momentaryTrack([x, x], rate);
  assert.equal(t[0].t, 0);
  near(t[0].lufs, -40, 0.2);
  assert.ok(t.some((b) => Math.abs(b.lufs + 20) < 0.2));
});

test('loudness range: EBU Tech 3342 case 1, 20 s at -20 then 20 s at -30 reads 10 LU', () => {
  const rate = 11025;
  const a = sineWave(997, 20, rate, dbToGain(-20));
  const b = sineWave(997, 20, rate, dbToGain(-30));
  const x = new Float64Array(a.length + b.length);
  x.set(a, 0);
  x.set(b, a.length);
  near(loudnessRange([x, x], rate), 10, 1);
  assert.ok(loudnessRange([a, a], rate) < 0.5, 'steady is 0');
  assert.equal(loudnessRange([new Float64Array(rate * 5)], rate), 0);
});

test('true peak finds the peak between samples', () => {
  const rate = 44100;
  const x = new Float64Array(4000);
  for (let i = 0; i < x.length; i++) x[i] = Math.sin((Math.PI / 2) * i + Math.PI / 4);
  // Sample peak 0.707: a sine at rate / 4, 45 degrees off the samples, truly peaks at 1.0.
  near(Math.max(...x.map(Math.abs)), Math.SQRT1_2, 1e-9);
  near(truePeakDb([x]), 0, 0.3);
  assert.ok(truePeakDb([sineWave(1000, 0.1, rate, 0.5)]) < -5.9);
  assert.equal(truePeakDb([new Float64Array(100)]), -Infinity);
});
