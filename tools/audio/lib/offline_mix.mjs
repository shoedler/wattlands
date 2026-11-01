// The offline renderer: runs a scenario through the kit's logic (pattern.mjs) at 60 frames a second,
// then mixes the voices to bus stems at 44100 Hz with cubic resampling, code-driven ducks and a hard
// limiter. No Godot, no audio device, no ffmpeg.

import fs from 'node:fs';
import path from 'node:path';
import { dbToGain } from './dsp.mjs';
import { OFF_DB, STOP_RPM, AmbienceBed, CadenceVoice, CrankClock, LayeredLoop, curveEval } from './pattern.mjs';
import { renderSound } from './recipe.mjs';
import { soundFiles } from './bank.mjs';
import { decodeWav, deinterleave } from './wav.mjs';

export const MIX_RATE = 44100;
export const FRAME_DT = 1 / 60;
// The kit's horizon at this frame rate (game_audio_kit.gd): a stroke can be planned this far ahead of its frame.
export const STROKE_HORIZON_S = Math.min(0.05, Math.max(0.012, 1.5 * FRAME_DT));
// The kit's limiter ceiling is -1 dB. On sample peaks this one stays 0.25 dB under that, which keeps the true peak of a 9 kHz band-limited mix at or under -1 dBTP.
const LIMITER_CEILING = dbToGain(-1.25);
const LIMITER_LOOKAHEAD = 66;
const LIMITER_RELEASE_S = 0.1;
// HudLayer._play is the only way a safety prompt reaches WlSfx, and it plays every sound at this level (hud_layer.gd). A test pins the two together.
export const PROMPT_VOICE_DB = -4;
// WlSfx.play's ducks (sfx.gd). A test pins the two together.
export const SAFETY_DUCK = [
  { bus: 'Machines', db: -14, attack_s: 0.02, release_s: 2 },
  { bus: 'Ambience', db: -14, attack_s: 0.02, release_s: 2 },
  { bus: 'Sfx', db: -20, attack_s: 0.02, release_s: 2 },
];
// WlSfx's trim of the UI voices under a safety prompt (sfx.gd). A test pins the two together.
export const PROMPT_UI_DUCK = { bus: 'UI', db: -10, attack_s: 0.02, release_s: 2 };
export const PROMPT_UI_SPARED = new Set(['countdown', 'click']);
export const STEM_BUSES = ['Machines', 'Ambience', 'Sfx', 'UI', 'Master'];
// AudioBuses.PAN_STEP and PAN_MAX. A test pins the two together.
export const PAN_STEP = 0.25;
export const PAN_MAX = 0.75;

/** A bank's audio: each file read from disk when present, else rendered in memory. Cached. */
export class BankAudio {
  constructor(doc, dir) {
    this.doc = doc;
    this.dir = dir;
    this._cache = new Map();
  }

  variants(id) {
    return this.doc.sounds[id]?.variants ?? 1;
  }

  /** {rate, ch, frames, preroll, loopFrames, data: Float64Array[]} */
  file(id, variant = 0) {
    const key = `${id}#${variant}`;
    let f = this._cache.get(key);
    if (f) return f;
    const sound = this.doc.sounds[id];
    if (!sound) throw new Error(`no sound "${id}"`);
    const stem = soundFiles(id, sound)[variant].stem;
    const wavPath = this.dir ? path.join(this.dir, `${stem}.wav`) : null;
    if (wavPath && fs.existsSync(wavPath)) {
      const w = decodeWav(fs.readFileSync(wavPath));
      const preroll = sound.locked === true ? Math.round(0.08 * w.rate) : 0;
      f = { rate: w.rate, ch: w.ch, frames: w.frames, preroll, loopFrames: sound.loop === true ? w.frames - 1 : 0, data: deinterleave(w.samples, w.ch) };
    } else {
      const r = renderSound(id, sound, variant, { game: this.doc.game });
      f = { rate: r.rate, ch: r.ch, frames: r.frames, preroll: r.preroll, loopFrames: r.loopFrames, data: deinterleave(r.samples, r.ch) };
    }
    this._cache.set(key, f);
    return f;
  }
}

function segmentAt(segments, t) {
  let at = 0;
  for (const s of segments) {
    if (t < at + s.s) return s;
    at += s.s;
  }
  return segments[segments.length - 1];
}

export function segmentsLength(segments) {
  return segments.reduce((a, s) => a + s.s, 0);
}

/**
 * Run a scenario through the kit's logic: no audio yet. A scenario:
 * {segments, machines: [{id, machine, lead, rpm_scale, rpm_by, params, strokes, loops}], bed,
 *  bed_params, cues: [{t, cue, vars, lead}], loops: [{id, t0, t1, params, lead}], prompts: [{t, name}],
 *  hud: [{t, sound}], shared, seed, duration}
 * A loops id keeps one track across its entries, as a game's set_loop does: only its params change.
 * hud: the _shared sounds HudLayer plays on UI at that moment; they need scenario.shared, and without it stay out.
 * Returns {voices, tracks, ducks, thinned, voicePeak, loopPeak, events, duration}.
 */
export function simulate(bank, scenario) {
  const doc = bank.doc;
  const mix = doc.mix ?? {};
  const duration = scenario.duration ?? segmentsLength(scenario.segments);
  const frames = Math.ceil(duration / FRAME_DT);
  const others = scenario.machines.filter((m) => !m.lead).length;
  const otherDb = (mix.other_db ?? -10) + (others > 2 ? (mix.other_doubling_db ?? -3) * Math.log2(others / 2) : 0);
  const spectatorDb = scenario.machines.some((m) => m.lead) ? 0 : 4;
  const minGap = mix.other_min_gap_s ?? 0.06;
  const variantsOf = (id) => bank.variants(id);
  const voices = [];
  const tracks = [];
  const events = [];
  const ducks = [];
  let thinned = 0;
  let lastOther = -Infinity;
  const addTrack = (sound, bus, lead, label) => {
    const t = { sound, bus, lead, label, pitch: new Float32Array(frames + 1), db: new Float32Array(frames + 1).fill(OFF_DB) };
    tracks.push(t);
    return t;
  };
  const rigs = scenario.machines.map((m, index) => {
    const def = doc.machines?.[m.machine];
    if (!def) throw new Error(`no machine "${m.machine}"`);
    const bus = def.bus ?? 'Machines';
    const layers = m.loops === false ? [] : (def.loops ?? []);
    return {
      m,
      bus,
      index,
      clock: new CrankClock(),
      voice: new CadenceVoice(m.strokes === false ? [] : (def.events ?? []), variantsOf),
      loops: new LayeredLoop(layers),
      tracks: layers.map((l) => addTrack(l.sound, bus, m.lead, `${m.id}:${l.sound}`)),
    };
  });
  const bedSpec = scenario.bed ? doc.beds?.[scenario.bed] : null;
  const bed = bedSpec ? new AmbienceBed(bedSpec, scenario.seed ?? 1, variantsOf) : null;
  const bedTracks = bedSpec ? (bedSpec.layers ?? []).map((l) => addTrack(l.sound, 'Ambience', true, `bed:${l.sound}`)) : [];
  const namedById = new Map();
  for (const nl of scenario.loops ?? []) {
    const def = doc.loops?.[nl.id];
    if (!def) throw new Error(`no loops entry "${nl.id}"`);
    const lead = nl.lead !== false;
    const key = `${nl.id}:${lead}`;
    if (!namedById.has(key)) {
      const layers = def.layers ?? [];
      namedById.set(key, { lead, entries: [], loops: new LayeredLoop(layers), tracks: layers.map((l) => addTrack(l.sound, def.bus ?? 'Sfx', lead, `loop:${nl.id}:${l.sound}`)) });
    }
    namedById.get(key).entries.push(nl);
  }
  const namedLoops = [...namedById.values()];
  const cueQueue = [...(scenario.cues ?? [])].sort((a, b) => a.t - b.t);
  const promptQueue = [...(scenario.prompts ?? [])].sort((a, b) => a.t - b.t);
  const hudQueue = scenario.shared ? [...(scenario.hud ?? [])].sort((a, b) => a.t - b.t) : [];
  const cueRr = new Map();
  const playCue = (c, t) => {
    const def = doc.cues?.[c.cue];
    if (!def) throw new Error(`no cue "${c.cue}"`);
    const vars = c.vars ?? {};
    const lead = c.lead !== false;
    const trim = lead ? 0 : (def.other_db ?? mix.other_db ?? -10);
    for (const h of def.hits ?? []) {
      const delay = (h.delay_s ?? 0) + (h.delay_var ? Number(vars[h.delay_var] ?? 0) : 0);
      const pitch = (h.pitch ?? 1) * (h.pitch_var ? Number(vars[h.pitch_var] ?? 1) : 1);
      const db = (h.db ?? 0) + trim + (h.db_var ? Number(vars[h.db_var] ?? 0) : 0);
      const rr = cueRr.get(h.sound) ?? 0;
      cueRr.set(h.sound, rr + 1);
      const pan = h.pan_var ? Number(vars[h.pan_var] ?? 0) : 0;
      const chosen = h.variant_var && vars[h.variant_var] !== undefined ? Number(vars[h.variant_var]) : rr;
      const v = { sound: h.sound, variant: chosen % Math.max(1, bank.variants(h.sound)), t: t + delay, db, pitch, bus: h.bus ?? 'Sfx', priority: h.priority ?? 6, lead, cue: c.cue, pan, crowd: h.crowd === true && (mix.crowd_voices ?? 0) > 0 };
      if (h.flight) {
        const panTo = h.flight.pan_to_var ? Number(vars[h.flight.pan_to_var] ?? pan) : pan;
        const dur = Math.max(0.05, h.flight.dur_var ? Number(vars[h.flight.dur_var] ?? h.flight.dur_s ?? 1) : (h.flight.dur_s ?? 1));
        v.flight = { dur, panTo, gain: h.flight.gain ?? [[0, 0]], pitch: h.flight.pitch ?? null };
      }
      voices.push(v);
      events.push({ t: v.t, sound: v.sound, variant: v.variant, db, kind: 'cue', cue: c.cue, thinned: false, pan, flight: v.flight?.dur });
    }
    if (lead) for (const d of def.duck ?? []) ducks.push({ ...d, t });
  };
  for (let f = 0; f < frames; f++) {
    const t = (f + 1) * FRAME_DT;
    const seg = segmentAt(scenario.segments, f * FRAME_DT);
    const planned = [];
    for (const rig of rigs) {
      const params = { ...seg.params, ...rig.m.params };
      const rpm = rig.m.rpm_by ? curveEval(rig.m.rpm_by, params) : seg.rpm * (rig.m.rpm_scale ?? 1);
      params.rpm = rpm;
      rig.clock.advance(rpm, FRAME_DT);
      for (const ev of rig.voice.plan(rig.clock.revs, rpm, STROKE_HORIZON_S, params, rig.m.lead)) planned.push({ ev, rig, at: t + ev.at_s });
      const trim = rig.m.lead ? 0 : otherDb + spectatorDb;
      if (rpm <= STOP_RPM) rig.loops.close(FRAME_DT);
      else rig.loops.update(params, trim, rig.m.lead, FRAME_DT);
      for (let i = 0; i < rig.loops.count; i++) {
        rig.tracks[i].pitch[f + 1] = rig.loops.pitch[i];
        rig.tracks[i].db[f + 1] = rig.loops.db[i];
      }
    }
    planned.sort((a, b) => a.at - b.at || a.rig.index - b.rig.index);
    for (const { ev, rig, at } of planned) {
      const lead = rig.m.lead;
      if (!lead) {
        if (at - lastOther < minGap) {
          thinned += 1;
          events.push({ t: at, sound: ev.sound, variant: ev.variant, db: ev.db, kind: 'stroke', machine: rig.m.id, thinned: true });
          continue;
        }
        lastOther = at;
      }
      const db = ev.db + (lead ? 0 : otherDb + spectatorDb);
      const pitch = Math.max(0.8, Math.min(1.2, ev.pitch));
      voices.push({ sound: ev.sound, variant: ev.variant, t: at, db, pitch, bus: rig.bus, priority: lead ? ev.priority : 3, lead, machine: rig.m.id });
      events.push({ t: at, sound: ev.sound, variant: ev.variant, db, kind: 'stroke', machine: rig.m.id, lead, thinned: false, pos: ev.pos });
    }
    while (cueQueue.length > 0 && cueQueue[0].t <= t) playCue(cueQueue.shift(), t);
    while (promptQueue.length > 0 && promptQueue[0].t <= t) {
      const p = promptQueue.shift();
      voices.push({ shared: true, sound: p.name, variant: 0, t, db: PROMPT_VOICE_DB, pitch: 1, bus: 'Master', priority: 10, lead: true });
      for (const d of SAFETY_DUCK) ducks.push({ ...d, t });
      ducks.push({ ...PROMPT_UI_DUCK, t });
    }
    while (hudQueue.length > 0 && hudQueue[0].t <= t) {
      const h = hudQueue.shift();
      voices.push({ shared: true, sound: h.sound, variant: 0, t, db: PROMPT_VOICE_DB, pitch: 1, bus: 'UI', priority: 6, lead: true });
      events.push({ t, sound: h.sound, variant: 0, db: PROMPT_VOICE_DB, kind: 'hud', thinned: false });
    }
    for (const nl of namedLoops) {
      const now = nl.entries.find((e) => t >= e.t0 && t < e.t1);
      if (now) nl.loops.update({ ...now.params }, nl.lead ? 0 : (mix.other_db ?? -10), nl.lead, FRAME_DT);
      else nl.loops.close(FRAME_DT);
      for (let i = 0; i < nl.loops.count; i++) {
        nl.tracks[i].pitch[f + 1] = nl.loops.pitch[i];
        nl.tracks[i].db[f + 1] = nl.loops.db[i];
      }
    }
    if (bed) {
      const params = { ...(scenario.bed_params ?? {}), ...seg.params };
      bed.loops.update(params, 0, true, FRAME_DT);
      for (let i = 0; i < bed.loops.count; i++) {
        bedTracks[i].pitch[f + 1] = bed.loops.pitch[i];
        bedTracks[i].db[f + 1] = bed.loops.db[i];
      }
      for (const s of bed.update(params, FRAME_DT)) {
        const at = t + s.at_s;
        voices.push({ sound: s.sound, variant: s.variant, t: at, db: s.db, pitch: s.pitch, bus: 'Ambience', priority: 2, lead: true, spot: true });
        events.push({ t: at, sound: s.sound, variant: s.variant, db: s.db, kind: 'spot', thinned: false });
      }
    }
  }
  events.sort((a, b) => a.t - b.t);
  const pooled = applyVoicePools(bank, voices, mix, scenario.shared ?? null);
  return { voices: pooled.voices, tracks, ducks, thinned, voicePeak: pooled.peak, loopPeak: loopPeak(tracks, frames), events, duration };
}

function voiceLength(bank, shared, v) {
  if (v.flight) return v.flight.dur;
  const f = (v.shared ? shared : bank).file(v.sound, v.variant);
  return (f.frames - f.preroll) / (f.rate * v.pitch);
}

/** The kit's voice pools: Machines 16, Sfx 16, Ambience spots 6, a crowd hit's own; the oldest voice of lowest priority is stolen. */
function applyVoicePools(bank, voices, mix, shared) {
  const caps = { Machines: mix.machine_voices ?? 16, Sfx: mix.sfx_voices ?? 16, Ambience: mix.spot_voices ?? 6, Crowd: mix.crowd_voices ?? 0 };
  const active = { Machines: [], Sfx: [], Ambience: [], Crowd: [] };
  const peak = { Machines: 0, Sfx: 0, Ambience: 0, Crowd: 0 };
  const sorted = [...voices].sort((a, b) => a.t - b.t);
  const kept = [];
  for (const v of sorted) {
    v.end = v.t + voiceLength(bank, shared, v);
    const key = v.crowd ? 'Crowd' : v.bus;
    const pool = active[key];
    if (!pool) {
      kept.push(v);
      continue;
    }
    active[key] = pool.filter((a) => a.end > v.t);
    const now = active[key];
    if (now.length >= caps[key]) {
      if (v.spot) continue;
      let victim = null;
      for (const a of now) {
        if (a.priority > v.priority) continue;
        if (a.lead && !v.lead) continue;
        if (victim === null || a.priority < victim.priority || (a.priority === victim.priority && a.t < victim.t)) victim = a;
      }
      if (victim === null) continue;
      victim.end = v.t;
      now.splice(now.indexOf(victim), 1);
    }
    now.push(v);
    peak[key] = Math.max(peak[key], now.length);
    kept.push(v);
  }
  return { voices: kept, peak };
}

function loopPeak(tracks, frames) {
  let max = 0;
  for (let f = 0; f <= frames; f++) {
    let n = 0;
    for (const t of tracks) if (t.db[f] > OFF_DB) n++;
    if (n > max) max = n;
  }
  return max;
}

function newStem(n) {
  return [new Float64Array(n), new Float64Array(n)];
}

function cubic(x, i, u, loopFrames) {
  const n = loopFrames > 0 ? loopFrames : x.length;
  const at = (k) => {
    if (loopFrames > 0) return x[((k % n) + n) % n];
    return k >= 0 && k < n ? x[k] : 0;
  };
  const a = at(i - 1);
  const b = at(i);
  const c = at(i + 1);
  const d = at(i + 2);
  return b + 0.5 * u * (c - a + u * (2 * a - 5 * b + 4 * c - d + u * (3 * (b - c) + d - a)));
}

/** The left and right gains of a mono voice at `pan`, as AudioEffectPanner applies them on the nearest of AudioBuses' sends. */
export function panGains(pan = 0, bus = 'Sfx') {
  if (bus !== 'Sfx') return [1, 1];
  const q = Math.round(Math.max(-PAN_MAX, Math.min(PAN_MAX, pan)) / PAN_STEP) * PAN_STEP;
  return [1 - q, 1 + q];
}

/** A flight: its loop read at the pitch its curve asks for, its level and side moved once per frame like the kit does. */
function mixFlight(file, v, stem, total) {
  const f = v.flight;
  const period = file.loopFrames > 0 ? file.loopFrames : file.frames;
  const start = Math.round(v.t * MIX_RATE);
  const end = Math.min(total, Math.round(v.end * MIX_RATE));
  const frameLen = Math.round(FRAME_DT * MIX_RATE);
  const l = file.data[0];
  let pos = 0;
  for (let n = Math.max(0, start); n < end; n += frameLen) {
    const u = Math.min(1, (n - start) / MIX_RATE / f.dur);
    const g = dbToGain(v.db + curveEval({ param: 'u', points: f.gain }, { u }));
    const pitch = v.pitch * (f.pitch ? curveEval({ param: 'u', points: f.pitch }, { u }) : 1);
    const [gl, gr] = panGains(v.pan + (f.panTo - v.pan) * u, v.bus);
    const step = (file.rate * Math.max(0.05, Math.min(4, pitch))) / MIX_RATE;
    for (let k = 0; k < frameLen && n + k < end; k++) {
      const i = Math.floor(pos);
      const a = cubic(l, i, pos - i, period) * g;
      stem[0][n + k] += a * gl;
      stem[1][n + k] += a * gr;
      pos += step;
      if (pos >= period) pos -= period;
    }
  }
}

function mixVoice(file, v, stem, total) {
  if (v.flight) {
    mixFlight(file, v, stem, total);
    return;
  }
  const gain = dbToGain(v.db);
  const step = (file.rate * v.pitch) / MIX_RATE;
  const start = Math.round(v.t * MIX_RATE);
  const end = Math.min(total, Math.round(v.end * MIX_RATE));
  const fade = 44;
  const l = file.data[0];
  const r = file.ch > 1 ? file.data[1] : l;
  const [gl, gr] = panGains(v.pan ?? 0, v.bus);
  for (let n = Math.max(0, start); n < end; n++) {
    const pos = file.preroll + (n - start) * step;
    const i = Math.floor(pos);
    if (i >= file.frames) break;
    const u = pos - i;
    const g = gain * Math.min(1, (end - n) / fade);
    const a = cubic(l, i, u, 0);
    stem[0][n] += a * g * gl;
    stem[1][n] += (r === l ? a : cubic(r, i, u, 0)) * g * gr;
  }
}

function mixTrack(file, track, stem, total) {
  const period = file.loopFrames > 0 ? file.loopFrames : file.frames;
  const frameLen = FRAME_DT * MIX_RATE;
  const l = file.data[0];
  const r = file.ch > 1 ? file.data[1] : l;
  let pos = 0;
  for (let n = 0; n < total; n++) {
    const fp = n / frameLen;
    const f = Math.floor(fp);
    if (f + 1 >= track.db.length) break;
    const u0 = fp - f;
    const d0 = track.db[f];
    const d1 = track.db[f + 1];
    if (d0 <= OFF_DB && d1 <= OFF_DB) {
      pos = 0;
      continue;
    }
    const g = dbToGain(d0 + (d1 - d0) * u0);
    const p0 = track.pitch[f] || track.pitch[f + 1] || 1;
    const p1 = track.pitch[f + 1] || p0;
    const pitch = Math.max(0.05, Math.min(4, p0 + (p1 - p0) * u0));
    const i = Math.floor(pos);
    const u = pos - i;
    const a = cubic(l, i, u, period);
    stem[0][n] += a * g;
    stem[1][n] += (r === l ? a : cubic(r, i, u, period)) * g;
    pos += (file.rate * pitch) / MIX_RATE;
    if (pos >= period) pos -= period;
  }
}

/** One voice of a simulation alone, from its own start, as a mono track, for the rows that weigh it against the mix. */
export function renderVoice(bank, v, shared = null) {
  const n = Math.max(1, Math.ceil((v.end - v.t) * MIX_RATE));
  const stem = newStem(n);
  mixVoice((v.shared ? shared : bank).file(v.sound, v.variant), { ...v, t: 0, end: v.end - v.t }, stem, n);
  return stem[0].map((a, i) => (a + stem[1][i]) / 2);
}

/** The envelope in dB of one duck trigger at time t. */
function duckEnvelope(d, t) {
  const u = t - d.t;
  if (u < 0) return 0;
  const a = d.attack_s ?? 0.01;
  if (u < a) return (d.db * u) / a;
  const r = d.release_s ?? 0.35;
  if (u < a + r) return d.db * (1 - (u - a) / r);
  return 0;
}

function applyDucks(stem, ducks) {
  if (ducks.length === 0) return;
  const block = 64;
  const n = stem[0].length;
  for (let at = 0; at < n; at += block) {
    const t = at / MIX_RATE;
    let deepest = 0;
    for (const d of ducks) deepest = Math.min(deepest, duckEnvelope(d, t));
    if (deepest === 0) continue;
    const g = dbToGain(deepest);
    for (let i = at; i < Math.min(n, at + block); i++) {
      stem[0][i] *= g;
      stem[1][i] *= g;
    }
  }
}

/** The mix's hard limiter: instant look-ahead attack, one-pole release. Returns a new stem. */
export function limit(stem, ceiling = LIMITER_CEILING) {
  const n = stem[0].length;
  const g = new Float64Array(n);
  const rel = Math.exp(-1 / (LIMITER_RELEASE_S * MIX_RATE));
  let env = 1;
  for (let i = 0; i < n; i++) {
    const p = Math.max(Math.abs(stem[0][i]), Math.abs(stem[1][i]));
    const want = p > ceiling ? ceiling / p : 1;
    env = want < env ? want : 1 - (1 - env) * rel;
    g[i] = env;
  }
  const slope = 1 / LIMITER_LOOKAHEAD;
  for (let i = n - 2; i >= 0; i--) {
    if (g[i] > g[i + 1] + slope) g[i] = g[i + 1] + slope;
  }
  const out = newStem(n);
  for (let i = 0; i < n; i++) {
    out[0][i] = stem[0][i] * g[i];
    out[1][i] = stem[1][i] * g[i];
  }
  return out;
}

/**
 * Mix a simulation to stems. Returns {stems: {Machines, Ambience, Sfx, UI, Master}, sum (before the
 * limiter), master (after), n}.
 */
export function mixdown(bank, sim, { shared = null, tail = 0.5 } = {}) {
  const n = Math.ceil((sim.duration + tail) * MIX_RATE);
  const stems = Object.fromEntries(STEM_BUSES.map((b) => [b, newStem(n)]));
  const addVoice = (v) => {
    if (v.t >= sim.duration + tail) return;
    const file = (v.shared ? shared : bank).file(v.sound, v.variant);
    mixVoice(file, v, stems[v.bus] ?? stems.Sfx, n);
  };
  // A prompt's trim of the UI is per voice in the game: the voices it spares join the stem after the duck.
  const spared = (v) => v.bus === 'UI' && PROMPT_UI_SPARED.has(v.sound);
  for (const v of sim.voices) if (!spared(v)) addVoice(v);
  for (const t of sim.tracks) mixTrack(bank.file(t.sound, 0), t, stems[t.bus] ?? stems.Sfx, n);
  for (const bus of STEM_BUSES) {
    const ds = sim.ducks.filter((d) => d.bus === bus);
    applyDucks(stems[bus], ds);
  }
  for (const v of sim.voices) if (spared(v)) addVoice(v);
  const sum = newStem(n);
  for (const bus of STEM_BUSES) {
    for (let i = 0; i < n; i++) {
      sum[0][i] += stems[bus][0][i];
      sum[1][i] += stems[bus][1][i];
    }
  }
  return { stems, sum, master: limit(sum), n };
}

/** Two channels -> a 16-bit stereo sample array for encodeWav. */
export function toInt16(stem) {
  const n = stem[0].length;
  const out = new Int16Array(n * 2);
  for (let i = 0; i < n; i++) {
    out[i * 2] = Math.max(-32768, Math.min(32767, Math.round(stem[0][i] * 32767)));
    out[i * 2 + 1] = Math.max(-32768, Math.min(32767, Math.round(stem[1][i] * 32767)));
  }
  return out;
}

