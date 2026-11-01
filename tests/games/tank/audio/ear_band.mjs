// How much of a machine sits where the ear is most sensitive, and for how long. Run it to read the numbers:
//   node tests/games/tank/audio/ear_band.mjs [--wav=<dir>]
// --wav also writes the Lights machine alone at 60, 90 and 110 rpm and a full crew with it leading.
// lights_band.test.mjs holds the Lights machine to these numbers. Nobody's ear is in them: they say where the energy
// is, not whether an hour of it is pleasant.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadBank } from '../../../../tools/audio/lib/bank.mjs';
import { EAR_BAND, centroidHz, earBand, lineHz, thirdOctaves } from '../../../../tools/audio/lib/ear_band.mjs';
import { integratedLufs } from '../../../../tools/audio/lib/lufs.mjs';
import { BankAudio, MIX_RATE, mixdown, simulate, toInt16 } from '../../../../tools/audio/lib/offline_mix.mjs';
import { previewScenario } from '../../../../tools/audio/lib/score.mjs';
import { encodeWav } from '../../../../tools/audio/lib/wav.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
export const BANK = path.join(REPO, 'assets/tank/audio/audio.json');
export const DIR = path.dirname(BANK);

export { EAR_BAND, centroidHz, earBand, lineHz, thirdOctaves };
export const RPMS = [60, 90, 110];
/** What each seat's strokes need to be open, as in the preview's others. */
export const WORKING = {
  diesel: { speed: 4 },
  dynamo: {},
  steam: { pressure_pct: 80, loaded: 1 },
  arc: { reach: 1 },
  feed: { rounds: 12, firing: 1 },
  repair: { repairing: 1 },
};
export const MACHINES = Object.keys(WORKING);

export function openBank() {
  const doc = loadBank(BANK);
  return new BankAudio(doc, DIR);
}

export function toMono(stem) {
  const out = new Float64Array(stem[0].length);
  for (let i = 0; i < out.length; i++) out[i] = 0.5 * (stem[0][i] + stem[1][i]);
  return out;
}

/** One machine alone, as its rider hears it. `pick` narrows it to some of its sounds. */
export function soloStem(bank, machine, rpm, params, { revs = 20, pick = null, seconds = null } = {}) {
  const s = seconds ?? (revs * 60) / rpm;
  const sim = simulate(bank, { segments: [{ rpm, s, params }], machines: [{ id: 'l', machine, lead: true }], duration: s });
  const kept = pick ? { ...sim, voices: sim.voices.filter((v) => pick(v.sound)), tracks: sim.tracks.filter((t) => pick(t.sound)) } : sim;
  return mixdown(bank, kept, { tail: 0 }).stems.Machines;
}

export function solo(bank, machine, rpm, params, opts = {}) {
  return toMono(soloStem(bank, machine, rpm, params, opts));
}

export function soloLufs(bank, machine, rpm, params, opts = {}) {
  return integratedLufs(soloStem(bank, machine, rpm, params, opts), MIX_RATE);
}

/** The preview's full crew with `seat` leading, as seat_levels.test.mjs has it. `without`: machines left out. */
export function crewScenario(bank, seat, { without = [] } = {}) {
  const d = bank.doc;
  const others = d.preview.others.filter((o) => o.machine !== seat && !without.includes(o.machine));
  if (seat !== 'diesel' && !without.includes('diesel')) {
    const at = others.findIndex((o) => o.machine === 'track');
    others.splice(at, 0, { machine: 'diesel', rpm_scale: 1.02, params: { power: 0.95, speed: 4 } });
  }
  const segments = d.preview.segments.map((s) => (s.rpm > 0 ? { ...s, params: { ...s.params, ...WORKING[seat] } } : s));
  return previewScenario({ ...d, preview: { ...d.preview, lead: seat, others, segments } });
}

export function crewMix(bank, seat, opts = {}) {
  return mixdown(bank, simulate(bank, crewScenario(bank, seat, opts)));
}

const f1 = (v) => v.toFixed(1).padStart(6);

function bySound(bank, machine, params) {
  const out = [`  ${machine}, power ${params.power}`];
  const def = bank.doc.machines[machine];
  for (const [kind, sounds] of [['stroke', def.events], ['loop', def.loops]]) {
    for (const sound of new Set(sounds.map((e) => e.sound))) {
      const x = solo(bank, machine, 90, params, { pick: (s) => s === sound });
      if (x.every((v) => v === 0)) continue;
      const e = earBand(x);
      out.push(`    ${kind.padEnd(6)} ${sound.padEnd(18)} ${f1(e.level)} ${f1(e.share)}`);
    }
  }
  return out;
}

function table() {
  const bank = openBank();
  const out = ['Each machine alone, power 1, working: 2-8 kHz against its own total. share, A-weighted share, loudest 186 ms, level dBFS'];
  for (const m of MACHINES) {
    for (const rpm of RPMS) {
      const e = earBand(solo(bank, m, rpm, { power: 1, ...WORKING[m] }));
      out.push(`  ${m.padEnd(7)} ${String(rpm).padStart(3)} rpm  ${f1(e.share)} ${f1(e.aShare)} ${f1(e.worst)} ${f1(e.level)}`);
    }
  }
  out.push('Sound by sound, 90 rpm, power 1 (the Lights machine also at power 1.5): 2-8 kHz level dBFS, its own share');
  for (const m of MACHINES) out.push(...bySound(bank, m, { power: 1, ...WORKING[m] }));
  out.push(...bySound(bank, 'arc', { power: 1.5, over: 1, reach: 1 }));
  out.push('The Lights machine by load, 90 rpm: LUFS, centroid Hz, share, level dBFS');
  for (const power of [0.3, 0.6, 0.9, 1.0, 1.2, 1.3, 1.5]) {
    const over = Math.min(1, Math.max(0, (power - 1.18) / 0.24));
    const params = { power, over: over * over * (3 - 2 * over), reach: reachOf(power) };
    const x = solo(bank, 'arc', 90, params);
    const e = earBand(x);
    out.push(`  power ${power.toFixed(1)}  ${f1(soloLufs(bank, 'arc', 90, params))} ${f1(centroidHz(x))} ${f1(e.share)} ${f1(e.level)}`);
  }
  out.push('Third octaves of the Lights machine alone, 90 rpm, power 1, dB against its total');
  out.push(`  ${thirdOctaves(solo(bank, 'arc', 90, { power: 1, reach: 1 }))
    .map((b) => `${b.hz}:${b.db.toFixed(0)}`)
    .join(' ')}`);
  out.push('A full crew, each seat leading: 2-8 kHz of the mix against its total, LUFS');
  for (const m of MACHINES) {
    const master = crewMix(bank, m).master;
    const e = earBand(toMono(master));
    out.push(`  ${m.padEnd(7)} ${f1(e.share)} ${f1(e.aShare)} ${f1(e.worst)} ${f1(e.level)}  ${f1(integratedLufs(master, MIX_RATE))}`);
  }
  const withArc = earBand(toMono(crewMix(bank, 'diesel').master));
  const noArc = earBand(toMono(crewMix(bank, 'diesel', { without: ['arc'] }).master));
  out.push(`What the Lights machine adds to 2-8 kHz with the diesel leading: ${(withArc.level - noArc.level).toFixed(2)} dB`);
  return out.join('\n');
}

/** TankAudio.ladder_reach. */
export function reachOf(power) {
  const t = Math.min(1, Math.max(0, (power - 0.3) / 0.6));
  return 0.25 + 0.75 * t * t * (3 - 2 * t);
}

function writeWavs(dir, label) {
  const bank = openBank();
  fs.mkdirSync(dir, { recursive: true });
  for (const rpm of RPMS) {
    const stem = soloStem(bank, 'arc', rpm, { power: 1, reach: 1 }, { revs: 30 });
    fs.writeFileSync(path.join(dir, `${label}_${rpm}.wav`), encodeWav(toInt16(stem), { rate: MIX_RATE, ch: 2 }));
  }
  const mix = crewMix(bank, 'arc');
  fs.writeFileSync(path.join(dir, `${label}_leading_crew.wav`), encodeWav(toInt16(mix.master), { rate: MIX_RATE, ch: 2 }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const wav = process.argv.find((a) => a.startsWith('--wav='));
  const label = process.argv.find((a) => a.startsWith('--label='));
  if (wav) writeWavs(wav.slice(6), label ? label.slice(8) : 'tank_lights');
  process.stdout.write(`${table()}\n`);
}
