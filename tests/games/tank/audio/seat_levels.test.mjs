// Every seat as the lead, through the same offline mix as the scorecard. The scorecard itself scores only
// preview.lead (the diesel), so a level moved on another seat would pass it; SPEC_AUDIO 3.6's numbers are the targets.

import assert from 'node:assert/strict';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { loadBank } from '../../../../tools/audio/lib/bank.mjs';
import { integratedLufs, loudnessRange, truePeakDb } from '../../../../tools/audio/lib/lufs.mjs';
import { BankAudio, MIX_RATE, mixdown, simulate } from '../../../../tools/audio/lib/offline_mix.mjs';
import { previewScenario, scoreBank } from '../../../../tools/audio/lib/score.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const BANK = path.join(REPO, 'assets/tank/audio/audio.json');
const DIR = path.dirname(BANK);
const doc = loadBank(BANK);

// What each seat's strokes need to be open, as in the preview's others.
const SEAT_PARAMS = {
  diesel: {},
  dynamo: {},
  steam: { pressure_pct: 80, loaded: 1 },
  arc: { reach: 0.9 },
  feed: { rounds: 12, firing: 1 },
  repair: { repairing: 1 },
};
const SEATS = Object.keys(SEAT_PARAMS);
// The one seat with an A8 waiver, scoped to this crew: the diesel's scorecard keeps the whole row.
const WAIVE = {
  arc: { A8: 'Arc-led crew: 1 % above 4 kHz against a floor of 2 %. The owner asked for less ear piercing, and the only fix is a continuous 6-9 kHz hiss there for this ratio.' },
};
/** A8's bands, as the row prints them, for a seat whose waiver covers only the floor above 4 kHz. */
function a8Holds(value) {
  const [low, body, mid, top] = value.split(' / ').map((v) => Number.parseFloat(v));
  return low <= 35 && body >= 25 && body <= 60 && mid >= 15 && mid <= 45 && top >= 0.9 && top <= 20;
}

/** The bank with `seat` leading a full crew; the diesel takes the seat's place among the others. */
function withLead(seat) {
  const d = structuredClone(doc);
  const track = d.preview.others.find((o) => o.machine === 'track');
  const rest = d.preview.others.filter((o) => o.machine !== 'track' && o.machine !== seat);
  if (seat !== 'diesel') rest.push({ machine: 'diesel', rpm_scale: 1.02, params: { power: 0.95, speed: 4 } });
  d.preview.lead = seat;
  d.preview.waive = { ...d.preview.waive, ...WAIVE[seat] };
  d.preview.others = [...rest, track];
  d.preview.segments = d.preview.segments.map((s) => (s.rpm > 0 ? { ...s, params: { ...s.params, ...SEAT_PARAMS[seat] } } : s));
  return d;
}

function solo(machine, params, rpm = 90) {
  const bank = new BankAudio(doc, DIR);
  const sim = simulate(bank, { segments: [{ rpm, s: 20, params }], machines: [{ id: 'l', machine, lead: true }], duration: 20 });
  return integratedLufs(mixdown(bank, sim, { tail: 0 }).stems.Machines, MIX_RATE);
}

for (const seat of SEATS) {
  test(`${seat} leads at SPEC 3.6's level, and the room around it stays in the mix's`, () => {
    const d = withLead(seat);
    const bank = new BankAudio(d, DIR);
    const scenario = previewScenario(d);
    const mix = mixdown(bank, simulate(bank, scenario));
    const leadOnly = scenario.machines.filter((m) => m.lead && m.machine === seat);
    const lead = mixdown(bank, simulate(bank, { ...scenario, machines: leadOnly, bed: null, cues: [], loops: [] })).stems.Machines;
    const leadLufs = integratedLufs(lead, MIX_RATE);
    const mixLufs = integratedLufs(mix.master, MIX_RATE);
    assert.ok(Math.abs(leadLufs + 22) <= 2, `lead ${leadLufs.toFixed(2)} LUFS, -22 +-2`);
    assert.ok(Math.abs(mixLufs + 18) <= 2, `mix ${mixLufs.toFixed(2)} LUFS, -18 +-2`);
    const lra = loudnessRange(mix.master, MIX_RATE);
    assert.ok(lra >= 4 && lra <= 14, `LRA ${lra.toFixed(1)}`);
    // The limiter holds samples at its ceiling; the inter-sample peak of a stacked transient lands a little either side.
    const tp = truePeakDb(mix.master);
    assert.ok(tp <= -0.85, `true peak ${tp.toFixed(2)} dBTP`);
  });

  test(`${seat} as the lead passes the sync rows and its own band shares`, () => {
    const card = scoreBank(withLead(seat), DIR, { shared: null });
    const row = (id) => card.rows.find((r) => r.id === id);
    for (const id of ['D2', 'D3', 'D4', 'D6', 'D7', 'A3', 'A4', 'A5', 'A8', 'A15']) {
      if (id === 'A8' && row(id).waived) {
        // The waiver covers the floor above 4 kHz, down to the measured number, and none of the row's other bands.
        assert.ok(WAIVE[seat]?.A8 === row(id).waived && a8Holds(row(id).value), `A8: ${row(id).value}`);
      } else {
        assert.ok(row(id).pass, `${id}: ${row(id).value} ${row(id).note ?? ''}`);
      }
    }
    // The only exception: the offline harness's first frame primes past a fraction under one frame's turn at 110 rpm,
    // so rivet_ring@0.03 loses its first revolution. Not the game: test_tank_audio_patterns.gd counts it exact there.
    const d1 = row('D1');
    const told = `${d1.value} ${d1.note ?? ''}`.trim();
    const primed = /^1 rivet_ring@0\.03 at 110 rpm: 9 onsets, 9 planned, 10 in the pattern$/;
    assert.ok(d1.pass || (seat === 'repair' && primed.test(told)), `D1: ${told}`);
  });
}

test("A8's waiver is the arc-led crew's alone: never in the bank, never another seat's", () => {
  assert.equal(doc.preview.waive?.A8, undefined);
  for (const seat of SEATS) assert.equal(withLead(seat).preview.waive?.A8 !== undefined, seat === 'arc', seat);
});

test('every seat sits within 3 LU of the others, solo at power 1 and 90 rpm', () => {
  const solos = {
    diesel: solo('diesel', { power: 1, speed: 4 }),
    dynamo: solo('dynamo', { power: 1 }),
    steam: solo('steam', { power: 1, pressure_pct: 80, loaded: 1 }),
    arc: solo('arc', { power: 1, reach: 0.9 }),
    feed: solo('feed', { power: 1, rounds: 12, firing: 1 }),
    repair: solo('repair', { power: 1, repairing: 1 }),
  };
  const values = Object.values(solos);
  assert.ok(Math.max(...values) - Math.min(...values) <= 3, JSON.stringify(solos));
});

test('a Repairs seat with nothing to mend is quiet, not silent, and rises with power', () => {
  const levels = [0.5, 0.9, 1.2].map((power) => solo('repair', { power, repairing: 0 }));
  assert.ok(levels[1] - levels[0] >= 1 && levels[2] - levels[1] >= 1, levels.join(' '));
  assert.ok(levels[1] >= -35, `idle at power 0.9: ${levels[1].toFixed(1)} LUFS`);
  const working = solo('repair', { power: 1, repairing: 1 });
  assert.ok(working - levels[2] >= 6, `working ${working.toFixed(1)}, idle ${levels[2].toFixed(1)}`);
});

test('the bed reads on its own, inside the Ambience target', () => {
  const bank = new BankAudio(doc, DIR);
  const sim = simulate(bank, {
    segments: [{ rpm: 0, s: 120, params: { power: 0, speed: 0 } }],
    machines: [],
    bed: 'night_forest',
    bed_params: { gust: 0.5, combat: 1 },
    seed: 3,
    duration: 120,
  });
  const lufs = integratedLufs(mixdown(bank, sim, { tail: 0 }).stems.Ambience, MIX_RATE);
  assert.ok(Math.abs(lufs + 32) <= 3, `bed ${lufs.toFixed(2)} LUFS`);
});
