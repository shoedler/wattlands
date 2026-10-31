// The Lights machine stays warm and low: an owner who rode it called the old one ear piercing, and these numbers are
// why (2-8 kHz at -4 dB of its own total, the highest of the six seats, and +6 dB in its loudest moment). A zap or a
// buzz brought back fails here. ear_band.mjs prints every number. What these can't say is whether an hour of it is
// pleasant: nobody has listened.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MIX_RATE, simulate } from '../../../../tools/audio/lib/offline_mix.mjs';
import { centroidHz, crewMix, earBand, lineHz, MACHINES, openBank, reachOf, RPMS, solo, soloLufs, thirdOctaves, toMono, WORKING } from './ear_band.mjs';
import { hardRide, openBank as openReadBank, readOf } from './read_over.mjs';

/** Every limit is in dB against the signal's own total. The old machine's reading is on the right. */
const LIMIT = {
  solo: -27, // -8.3 to -3.6; now -29.5 at worst, 110 rpm, where the rpm pitch lifts the body
  soloMostSensitive: -25, // 2-5 kHz: -7.5 to -7.2
  soloWorstFrame: -14, // +5.7 to +6.9
  mix: -12, // -6.3
  mixWorstFrame: 3.5, // +4.5
};
const MOST_SENSITIVE = [2000, 5000];
/** Everything the machine plays: none of it may reach up there. */
const DULL_SOUNDS = ['arc_relay', 'arc_relay_over', 'arc_spark', 'belt_tick', 'arc_thrum', 'arc_thrum_open'];

const bank = openBank();
const LOADS = [0.6, 1.0, 1.2, 1.5];

function working(power) {
  const t = Math.min(1, Math.max(0, (power - 1.18) / 0.24));
  return { power, reach: reachOf(power), over: t * t * (3 - 2 * t) };
}

for (const rpm of RPMS) {
  for (const power of LOADS) {
    test(`the Lights machine alone at ${rpm} rpm, power ${power}, keeps out of 2-8 kHz`, () => {
      const x = solo(bank, 'arc', rpm, working(power));
      const e = earBand(x);
      assert.ok(e.share <= LIMIT.solo, `2-8 kHz ${e.share.toFixed(1)} dB of its total, limit ${LIMIT.solo}`);
      assert.ok(e.worst <= LIMIT.soloWorstFrame, `loudest moment ${e.worst.toFixed(1)} dB, limit ${LIMIT.soloWorstFrame}`);
      const s = earBand(x, MOST_SENSITIVE);
      assert.ok(s.share <= LIMIT.soloMostSensitive, `2-5 kHz ${s.share.toFixed(1)} dB, limit ${LIMIT.soloMostSensitive}`);
    });
  }
}

test('a full crew with the Lights machine leading keeps out of 2-8 kHz too', () => {
  const e = earBand(toMono(crewMix(bank, 'arc').master));
  assert.ok(e.share <= LIMIT.mix, `2-8 kHz ${e.share.toFixed(1)} dB of the mix, limit ${LIMIT.mix}`);
  assert.ok(e.worst <= LIMIT.mixWorstFrame, `loudest moment ${e.worst.toFixed(1)} dB, limit ${LIMIT.mixWorstFrame}`);
});

test('no stroke and no body of the machine reaches 2 kHz: no zap, no buzz', () => {
  for (const sound of DULL_SOUNDS) {
    const x = solo(bank, 'arc', 90, working(1.5), { pick: (s) => s === sound });
    const e = earBand(x, [2000, 9000]);
    assert.ok(e.share <= -30, `${sound}: ${e.share.toFixed(1)} dB above 2 kHz, limit -30`);
  }
});

test('it sits under the diesel at every cadence', () => {
  for (const rpm of RPMS) {
    const arc = soloLufs(bank, 'arc', rpm, { power: 1, reach: 1 });
    const diesel = soloLufs(bank, 'diesel', rpm, { power: 1, ...WORKING.diesel });
    assert.ok(arc <= diesel - 0.5, `${rpm} rpm: Lights ${arc.toFixed(2)}, diesel ${diesel.toFixed(2)} LUFS`);
  }
});

test('as another rider, under a diesel that leads, it never comes through', () => {
  const readBank = openReadBank();
  const arc = new Set([...readBank.doc.machines.arc.events, ...readBank.doc.machines.arc.loops].map((e) => e.sound));
  const r = readOf(readBank, hardRide('diesel', { power: 1 }), (s) => arc.has(s), 1, 7, 0.5);
  assert.ok(r.db < -6, `best band ${r.db.toFixed(1)} dB at ${r.hz} Hz`);
});

/** Each stroke: its first 40 ms against the 30 ms before it, in dB. */
function strokeRises(rpm, params) {
  const x = solo(bank, 'arc', rpm, params, { revs: 20 });
  const s = (20 * 60) / rpm;
  const sim = simulate(bank, { segments: [{ rpm, s, params }], machines: [{ id: 'l', machine: 'arc', lead: true }], duration: s });
  const rms = (from, to) => {
    let e = 0;
    for (let i = from; i < to; i++) e += x[i] * x[i];
    return 10 * Math.log10(e / Math.max(1, to - from) + 1e-30);
  };
  const out = [];
  for (const v of sim.voices) {
    if (v.sound !== 'arc_relay' || v.t < 1 || v.t > s - 0.2) continue;
    const at = Math.round(v.t * MIX_RATE);
    out.push(rms(at, at + Math.round(0.04 * MIX_RATE)) - rms(at - Math.round(0.03 * MIX_RATE), at));
  }
  return out;
}

for (const rpm of RPMS) {
  test(`every stroke at ${rpm} rpm stands clear of the thrum: a cadence you can hear`, () => {
    const rises = strokeRises(rpm, { power: 1, reach: 1 });
    assert.ok(rises.length >= 30, `${rises.length} strokes`);
    const lowest = Math.min(...rises);
    assert.ok(lowest >= 5, `the weakest stroke rises ${lowest.toFixed(1)} dB`);
  });

  test(`at ${rpm} rpm the rider's stroke reads over a full crew`, () => {
    const readBank = openReadBank();
    const r = readOf(readBank, hardRide('arc', { rpm, power: 1 }), (s) => s === 'arc_relay', 1, 7, 0.1);
    assert.ok(r.db >= 6, `best band ${r.db.toFixed(1)} dB at ${r.hz} Hz`);
    assert.ok(r.hz < 2000, `reads at ${r.hz} Hz, where it should be dull`);
  });
}

test('power is heard: louder, and the body opens', () => {
  const lufs = (power) => soloLufs(bank, 'arc', 90, { power, reach: reachOf(power) });
  assert.ok(lufs(1.2) - lufs(0.5) >= 6, `${lufs(0.5).toFixed(1)} to ${lufs(1.2).toFixed(1)} LUFS`);
  const whole = (power) => solo(bank, 'arc', 90, { power, reach: reachOf(power) });
  const lo = centroidHz(whole(0.5));
  const hi = centroidHz(whole(1.2));
  assert.ok(hi / lo >= 1.1, `centroid ${lo.toFixed(0)} to ${hi.toFixed(0)} Hz`);
});

test('reach is heard: the stroke grows, and the sparks only come at the top', () => {
  const low = { power: 1, reach: 0.25 };
  const high = { power: 1, reach: 1 };
  const db = soloLufs(bank, 'arc', 90, high) - soloLufs(bank, 'arc', 90, low);
  assert.ok(db >= 1.5, `${db.toFixed(2)} LU from reach 0.25 to 1`);
  const sparks = (params) => simulate(bank, { segments: [{ rpm: 90, s: 8, params }], machines: [{ id: 'l', machine: 'arc', lead: true }], duration: 8 }).voices.filter((v) => v.sound === 'arc_spark');
  assert.equal(sparks(low).length, 0);
  assert.equal(sparks({ power: 1, reach: 0.8 }).length, 0);
  assert.ok(sparks(high).length >= 20);
});

test('most sparks are lost under the thrum: only an occasional one is heard', () => {
  const peaks = [];
  for (let v = 0; v < bank.variants('arc_spark'); v++) {
    const f = bank.file('arc_spark', v);
    let peak = 0;
    for (const s of f.data[0]) peak = Math.max(peak, Math.abs(s));
    peaks.push(20 * Math.log10(peak));
  }
  const top = Math.max(...peaks);
  const heard = peaks.filter((p) => p > top - 6).length;
  assert.equal(heard, 2, peaks.map((p) => p.toFixed(1)).join(' '));
  // D1's onset floor is 22 dB under the entry's peak: the quiet ones still count as strokes.
  assert.ok(Math.min(...peaks) >= top - 20, peaks.map((p) => p.toFixed(1)).join(' '));
});

test('over is heard: a second stroke between the first, and the body climbs', () => {
  const under = soloLufs(bank, 'arc', 90, { power: 1.2, reach: 1, over: 0 });
  const over = soloLufs(bank, 'arc', 90, { power: 1.2, reach: 1, over: 1 });
  assert.ok(over - under >= 1.5, `${under.toFixed(2)} to ${over.toFixed(2)} LUFS`);
});

/** The third-octaves the machines' bodies live in. */
function bodyShape(machine) {
  return thirdOctaves(solo(bank, machine, 90, { power: 1, ...WORKING[machine] })).filter((b) => b.hz <= 2000);
}

test('its body is its own: under 2 kHz no seat comes within 5 dB of its shape, and the Gun stays furthest', () => {
  const arc = bodyShape('arc');
  for (const m of MACHINES) {
    if (m === 'arc') continue;
    const other = bodyShape(m);
    const d = Math.sqrt(arc.reduce((a, b, i) => a + (b.db - other[i].db) ** 2, 0) / arc.length);
    assert.ok(d >= (m === 'dynamo' ? 10 : 5), `${m}: ${d.toFixed(1)} dB rms`);
  }
});

test("it does not sing the Gun's whine: its loud lines stay off the dynamo's", () => {
  const line = (machine, sound) => lineHz(solo(bank, machine, 90, { power: 1, ...WORKING[machine] }, { pick: (s) => s === sound }));
  const whine = line('dynamo', 'dynamo_whine');
  assert.ok(Math.abs(whine - 380) < 15, `the whine is at ${whine.toFixed(0)} Hz`);
  const thrum = line('arc', 'arc_thrum');
  assert.ok(thrum < 150, `the thrum's line is at ${thrum.toFixed(0)} Hz`);
  const open = line('arc', 'arc_thrum_open');
  assert.ok(Math.abs(open - whine) >= 40, `the open body's line is at ${open.toFixed(0)} Hz, the whine's at ${whine.toFixed(0)}`);
});
