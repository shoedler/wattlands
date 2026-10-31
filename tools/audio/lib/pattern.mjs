// A JS port of the kit's pure classes, so the offline preview runs the logic the game runs:
// CrankClock, AudioCurve, CadenceVoice.plan, LayeredLoop, AmbienceBed. The parity table in
// tests/audio/test_audio_parity.gd and test/pattern.test.mjs holds both ports to the same numbers.

import { uniform, xorshift32 } from './dsp.mjs';

export const STOP_RPM = 1.0;
export const LATE_MAX_S = 0.08;
export const OFF_DB = -60.0;

export class CrankClock {
  revs = 0;

  /** Returns the whole revolutions crossed by this call. */
  advance(rpm, dt) {
    if (rpm <= STOP_RPM || dt <= 0) return 0;
    const was = Math.floor(this.revs);
    this.revs += (rpm / 60) * dt;
    return Math.floor(this.revs) - was;
  }

  frac() {
    return this.revs - Math.floor(this.revs);
  }
}

// --- AudioCurve ---

/** {param, points: [[x, y], ...]} piecewise linear, clamped; {param, ratio: r} = value / r. Missing reads 0. */
export function curveEval(curve, params) {
  const v = Number(params[curve.param] ?? 0);
  if (curve.points) {
    const p = curve.points;
    if (v <= p[0][0]) return p[0][1];
    for (let i = 1; i < p.length; i++) {
      if (v <= p[i][0]) return p[i - 1][1] + ((p[i][1] - p[i - 1][1]) * (v - p[i - 1][0])) / (p[i][0] - p[i - 1][0]);
    }
    return p[p.length - 1][1];
  }
  return v / curve.ratio;
}

export function curveSumDb(curves, params) {
  let s = 0;
  for (const c of curves ?? []) s += curveEval(c, params);
  return s;
}

export function curveProduct(curves, params) {
  let s = 1;
  for (const c of curves ?? []) s *= curveEval(c, params);
  return s;
}

/** {param, min?, max?}, both inclusive; {} passes. */
export function curvePasses(when, params) {
  if (!when || when.param === undefined) return true;
  const v = Number(params[when.param] ?? 0);
  if (when.min !== undefined && v < when.min) return false;
  if (when.max !== undefined && v > when.max) return false;
  return true;
}

// --- CadenceVoice ---

/** One machine's stroke pattern. plan() partitions the revs axis; every event k+f falls in exactly one interval. */
export class CadenceVoice {
  fired = 0;
  late = 0;
  dropped = 0;
  gated = 0;
  _to = 0;
  _primed = false;
  _rr = new Map();

  /** events: bank events; `at` is a number or array, each value one internal entry. variantsOf(sound) -> count. */
  constructor(events, variantsOf = () => 1) {
    this._events = [];
    this._cycle = new Array(events.length).fill(0);
    events.forEach((ev, src) => {
      for (const at of [ev.at].flat()) this._events.push({ ...ev, at, src });
    });
    this._events.sort((a, b) => a.at - b.at);
    this._variantsOf = variantsOf;
  }

  plan(revs, rpm, horizonS, params, lead) {
    const out = [];
    if (!this._primed || revs < this._to - 1) {
      this._primed = true;
      this._to = revs;
    }
    if (rpm <= STOP_RPM) {
      this._to = Math.max(this._to, revs);
      return out;
    }
    const rate = rpm / 60;
    let from = this._to;
    const oldest = revs - rate * LATE_MAX_S;
    if (from < oldest) {
      this.dropped += this._countBetween(from, oldest);
      from = oldest;
    }
    const to = Math.max(revs + rate * horizonS, from);
    for (let rev = Math.floor(from); rev <= Math.floor(to); rev++) {
      for (const ev of this._events) {
        const pos = rev + ev.at;
        if (pos <= from) continue;
        if (pos > to) break;
        if (!this._passes(ev, params, lead)) {
          this.gated += 1;
          continue;
        }
        out.push(this._emit(ev, pos, Math.max((pos - revs) / rate, 0), params));
      }
    }
    this._to = to;
    return out;
  }

  _countBetween(a, b) {
    let n = 0;
    for (let rev = Math.floor(a); rev <= Math.floor(b); rev++) {
      for (const ev of this._events) {
        const pos = rev + ev.at;
        if (pos > a && pos <= b) n++;
      }
    }
    return n;
  }

  _passes(ev, params, lead) {
    return !(ev.lead_only === true && !lead) && curvePasses(ev.when, params);
  }

  _emit(ev, pos, atS, params) {
    this.fired += 1;
    if (atS <= 0) this.late += 1;
    const count = this._variantsOf(ev.sound);
    const rr = this._rr.get(ev.sound) ?? 0;
    this._rr.set(ev.sound, rr + 1);
    const table = ev.pitch_table ?? [];
    let pitch = curveProduct(ev.pitch_by, params);
    if (table.length > 0) {
      pitch += table[this._cycle[ev.src] % table.length];
      this._cycle[ev.src] += 1;
    }
    return {
      sound: ev.sound,
      variant: rr % Math.max(1, count),
      at_s: atS,
      db: (ev.db ?? 0) + curveSumDb(ev.db_by, params),
      pitch,
      pos,
      priority: ev.priority ?? 5,
    };
  }
}

// --- LayeredLoop ---

const OPEN_TAU_S = 0.04;
const CLOSE_DB_PER_S = 600;
const DEFAULT_SLEW_S = 0.25;
const BURST_MAX_S = 1.0;

/** Loop layers whose pitch and gain follow params. See SPEC_AUDIO 1.2 for the envelope rules. */
export class LayeredLoop {
  constructor(layers) {
    this.layers = layers;
    this.count = layers.length;
    this.pitch = new Float64Array(layers.length).fill(1);
    this.db = new Float64Array(layers.length).fill(OFF_DB);
    this.on = new Uint8Array(layers.length);
  }

  update(params, trimDb, lead, dt) {
    for (let i = 0; i < this.count; i++) {
      const l = this.layers[i];
      const wants =
        (lead || l.other === true) &&
        (l.min_rpm === undefined || Number(params.rpm ?? 0) >= l.min_rpm) &&
        curvePasses(l.when, params);
      const target = wants ? Math.max(OFF_DB, (l.db ?? 0) + curveSumDb(l.db_by, params) + trimDb) : OFF_DB;
      if (target > OFF_DB) {
        const pitchTarget = curveProduct(l.pitch_by, params);
        if (this.on[i] === 0) this.pitch[i] = pitchTarget;
        else this.pitch[i] += (pitchTarget - this.pitch[i]) * (1 - Math.exp(-dt / (l.slew_s ?? DEFAULT_SLEW_S)));
      }
      this._moveDb(i, target, dt);
    }
  }

  /** Every layer closes, whatever the params say: a stopped machine, a named loop no longer asked for. */
  close(dt) {
    for (let i = 0; i < this.count; i++) this._moveDb(i, OFF_DB, dt);
  }

  _moveDb(i, target, dt) {
    if (target > this.db[i]) this.db[i] += (target - this.db[i]) * (1 - Math.exp(-dt / OPEN_TAU_S));
    else this.db[i] = Math.max(target, this.db[i] - CLOSE_DB_PER_S * dt);
    this.on[i] = this.db[i] > OFF_DB ? 1 : 0;
  }
}

// --- AmbienceBed ---

/** A bed's layers plus spots on seeded timers. update() returns the spots due now. */
export class AmbienceBed {
  constructor(spec, seed, variantsOf = () => 1) {
    this.loops = new LayeredLoop(spec.layers ?? []);
    this._next = xorshift32(seed);
    this._variantsOf = variantsOf;
    this._spots = (spec.spots ?? []).map((s) => ({ s, wait: this._range(s.gap_s, 1), rr: 0 }));
    this._minGap = spec.spot_min_gap_s ?? 0;
    this._sinceDetail = Infinity;
  }

  _u() {
    return uniform(this._next);
  }

  _gap(s) {
    return this._range(s.gap_s);
  }

  _range(r, fallback = 0) {
    if (r === undefined) return fallback;
    if (typeof r === 'number') return r;
    return r[0] + (r[1] - r[0]) * this._u();
  }

  _isDetail(s) {
    return this._minGap > 0 && [s.gap_s ?? 1].flat()[0] >= this._minGap;
  }

  update(params, dt) {
    const out = [];
    this._sinceDetail += dt;
    for (const e of this._spots) {
      e.wait -= dt;
      if (e.wait > 0) continue;
      const detail = this._isDetail(e.s);
      if (detail && this._sinceDetail < this._minGap) {
        e.wait = this._minGap * (1 + this._u()) - this._sinceDetail;
        continue;
      }
      e.wait = this._gap(e.s);
      if (!curvePasses(e.s.when, params)) continue;
      const burst = e.s.burst ? Math.round(this._range(e.s.burst, 1)) : 1;
      for (let i = 0; i < Math.max(burst, 1); i++) {
        const atS = i * (e.s.burst_gap_s ?? 0);
        if (atS > BURST_MAX_S) break;
        out.push({
          sound: e.s.sound,
          variant: e.rr % Math.max(1, this._variantsOf(e.s.sound)),
          at_s: atS,
          db: this._range(e.s.db) + curveSumDb(e.s.db_by, params),
          pitch: this._range(e.s.pitch, 1),
        });
        e.rr += 1;
      }
      if (detail) this._sinceDetail = -out[out.length - 1].at_s;
    }
    return out;
  }
}
