#!/usr/bin/env node
// MOCKUP: the Castellum Rotae HUD over the art frame, in art px on the 960 x 540 base (x2 at 1080p).
// One PNG per state in STATES.   node src/games/siege/art/hud_mock.mjs --out=<dir>
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Raster } from './raster.mjs';
import { Scene } from './scene.mjs';
import { Life } from './life.mjs';
import { hex } from './v3.mjs';
import * as W from './world.mjs';
import { writePng, toRgba8 } from './png.mjs';
import { FACES, drawText, measure } from './hud_font.mjs';
import { rgb, C, SLOT, ICON, SHAPE, PEG } from './hud_parts.mjs';

const repo = join(dirname(fileURLToPath(import.meta.url)), '../../../..');
const arg = (k, d) => (process.argv.find((a) => a.startsWith(`--${k}=`)) ?? `=${d}`).split('=')[1];
const out = arg('out', join(repo, 'build/siege_hud_mock'));

class Canvas {
  constructor(base) {
    this.w = 960;
    this.h = 540;
    this.px = Uint8ClampedArray.from(base);
  }
  put(x, y, c, a = 1) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 4;
    for (let k = 0; k < 3; k++) this.px[i + k] = this.px[i + k] * (1 - a) + c[k] * a;
  }
  rect(x, y, w, h, c, a = 1) {
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.put(x + i, y + j, c, a);
  }
  text(str, x, y, face, c, opts = {}) {
    const f = FACES[face];
    const tw = measure(str, f);
    const sx = opts.right ? x - tw : opts.center ? x - Math.floor(tw / 2) : x;
    // only the big faces cast a shadow on the wax; below that it clogs the letters
    if (f.cap >= 14 && opts.shadow !== false) drawText(str, sx + 1, y + 1, f, (px, py) => this.put(px, py, rgb('#0b0705'), 0.85));
    drawText(str, sx, y, f, (px, py) => this.put(px, py, c));
    return sx + tw;
  }
  icon(rows, x, y, c) {
    rows.forEach((row, j) => {
      for (let i = 0; i < row.length; i++) {
        const k = row[i];
        if (k === '.') continue;
        this.put(x + i, y + j, k === '+' ? C.stoneHi : k === 'o' ? C.ink : k === '=' ? C.bronze : c);
      }
    });
  }
}

// The plate: dark wax in a limestone frame with a brick course, the fort's wall in section.
function plate(g, x, y, w, h, opts = {}) {
  g.rect(x + 2, y + h, w, 2, [0, 0, 0], 0.42);
  g.rect(x + w, y + 2, 2, h, [0, 0, 0], 0.42);
  const frame = opts.frame ?? C.stone;
  g.rect(x, y, w, h, frame);
  g.rect(x, y, w, 1, opts.frame ? frame : C.stoneHi);
  g.rect(x, y + h - 1, w, 1, C.stoneLo);
  g.rect(x + w - 1, y, 1, h, C.stoneLo);
  // coursing: a joint every few pixels along the stone
  if (!opts.frame) {
    for (let i = 5; i < w - 3; i += 9) {
      g.put(x + i, y + 1, C.stoneLo);
      g.put(x + i + 4, y + h - 2, C.stoneLo);
    }
    for (let j = 5; j < h - 3; j += 9) {
      g.put(x + 1, y + j, C.stoneLo);
      g.put(x + w - 2, y + j + 4, C.stoneLo);
    }
  }
  g.rect(x + 2, y + 2, w - 4, h - 4, opts.frame ? C.oxblood : C.brick);
  g.rect(x + 3, y + 3, w - 6, h - 6, opts.fill ?? C.wax);
  let seed = x * 31 + y * 17;
  for (let j = y + 3; j < y + h - 3; j++) {
    for (let i = x + 3; i < x + w - 3; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      if (seed % 23 === 0) g.put(i, j, C.waxLift);
    }
  }
}

// The tabula ansata: an inscription plaque with dovetail handles, straight on the outside, a peg
// hole in each and an inset moulding.
function ansata(g, x, y, str, opts = {}) {
  const face = opts.face ?? 'LABEL';
  const f = FACES[face];
  const lead = opts.lead ?? 0;
  const tw = measure(str, f) + lead;
  const h = f.cap + 8;
  const w = tw + 10;
  const stone = opts.stone ?? C.stone;
  const hi = opts.hi ?? C.stoneHi;
  const lo = opts.lo ?? C.stoneLo;
  const mid = (h - 1) / 2;
  for (let i = 1; i <= 5; i++) {
    const half = Math.round(mid * (0.4 + 0.12 * i));
    for (let j = Math.floor(mid - half); j <= Math.ceil(mid + half); j++) {
      const c = i === 5 ? lo : stone;
      g.put(x - i, y + j, c);
      g.put(x + w - 1 + i, y + j, c);
    }
  }
  g.put(x - 3, y + Math.round(mid), C.ink);
  g.put(x + w + 2, y + Math.round(mid), C.ink);
  g.rect(x, y, w, h, stone);
  g.rect(x, y, w, 1, hi);
  g.rect(x, y + h - 1, w, 1, lo);
  g.rect(x + 1, y + 1, w - 2, 1, lo);
  g.rect(x + 1, y + h - 2, w - 2, 1, hi);
  drawText(str, x + 5 + lead, y + 4, f, (px, py) => g.put(px, py, opts.ink ?? C.ink));
  return { x, w, h };
}

const bar = (g, x, y, w, h, f, c, track = C.track) => {
  g.rect(x, y, w, h, track);
  g.rect(x, y, Math.round(w * Math.max(0, Math.min(1, f))), h, c);
};

// A red chip with light text: the alarm is never coloured text alone.
function chip(g, str, x, y, face = 'LABEL', right = false, bg = C.alarm, fg = C.text) {
  const f = FACES[face];
  const w = measure(str, f) + 6;
  const lx = right ? x - w : x;
  g.rect(lx, y - 2, w, f.cap + 4, bg);
  drawText(str, lx + 3, y, f, (px, py) => g.put(px, py, fg));
  return lx + w;
}

const STATIONS = [
  { icon: 'mine', name: 'GOLD MINE', cap: 2 },
  { icon: 'ballista', name: 'TREE BALLISTA', cap: 1 },
  { icon: 'onager', name: 'GREAT ONAGER', cap: 2 },
  { icon: 'arrows', name: 'ARROW ORGAN', cap: 2 },
  { icon: 'tar', name: 'TAR WORKS', cap: 1 },
];

// short: warm-up ramp, build break, three waves with breaks, cool-down
const PHASES = [
  { d: 300, p: 50, q: 65, k: 'warm' }, { d: 120, p: 50, k: 'rest' }, { d: 300, p: 95, k: 'work' }, { d: 180, p: 50, k: 'rest' },
  { d: 300, p: 95, k: 'work' }, { d: 180, p: 50, k: 'rest' }, { d: 300, p: 95, k: 'work' }, { d: 180, p: 50, q: 40, k: 'cool' },
];

// Top left: where you are in the session (the clock lives in the cockpit), and the road's news.
function session(g, s) {
  const x = 150;
  const y = 8;
  const w = 258;
  const h = s.enemies.length || s.warning ? 72 : 52;
  plate(g, x, y, w, h);
  ansata(g, x + 10, y + 5, s.title);
  g.text(s.end, x + w - 8, y + 9, 'LABEL', C.dim, { right: true });
  const sx = x + 8;
  const sy = y + 26;
  const sw = w - 16;
  const sh = 18;
  const total = PHASES.reduce((a, b) => a + b.d, 0);
  let at = 0;
  PHASES.forEach((p, i) => {
    const bx = sx + Math.round((at / total) * sw);
    const bw = Math.round(((at + p.d) / total) * sw) - Math.round((at / total) * sw);
    const col = p.k === 'work' ? C.terra : p.k === 'warm' || p.k === 'cool' ? C.warm : C.verd;
    const past = at + p.d <= s.elapsed;
    for (let c = 1; c < bw; c++) {
      const pct = p.p + ((p.q ?? p.p) - p.p) * (c / bw);
      const bh = Math.round((pct / 100) * sh);
      g.rect(bx + c, sy + sh - bh, 1, bh, col, past ? 0.4 : 1);
    }
    if (i === s.phase) {
      g.rect(bx, sy - 1, bw + 1, 1, C.bronzeHi);
      g.rect(bx, sy + sh, bw + 1, 1, C.bronzeHi);
      g.rect(bx, sy - 1, 1, sh + 2, C.bronzeHi);
      g.rect(bx + bw, sy - 1, 1, sh + 2, C.bronzeHi);
    }
    at += p.d;
  });
  g.rect(sx + Math.round((s.elapsed / total) * sw), sy - 3, 1, sh + 6, C.text);
  if (!(s.enemies.length || s.warning)) return;
  g.rect(x + 3, y + 49, w - 6, 1, C.waxLine);
  let cx = x + 9;
  for (const e of s.enemies) {
    g.icon(ICON[e.icon], cx, y + 54, e.warn ? C.text : C.stone);
    cx += 14;
    cx = g.text(String(e.n), cx, y + 56, 'LABEL', C.text) + 8;
  }
  if (s.warning) g.text(s.warning, x + w - 8, y + 56, 'LABEL', C.text, { right: true });
}

// Teammates only: your own numbers are in the cockpit. Each card hangs a vexillum in the rider's
// colour; a lamp, not a strip, says in band or out.
function crew(g, s) {
  const y = 8;
  s.riders.filter((r) => !r.you).forEach((r, i) => {
    const x = 470 + i * 92;
    const w = 90;
    const h = 60;
    plate(g, x, y, w, h);
    g.rect(x + 3, y + 3, w - 6, 8, SLOT[r.slot], r.afk ? 0.45 : 1);
    for (let f = x + 4; f < x + w - 4; f += 3) g.put(f, y + 11, SLOT[r.slot], r.afk ? 0.45 : 1);
    g.icon(SHAPE[r.slot], x + 6, y + 15, SLOT[r.slot]);
    g.text(r.name, x + 16, y + 14, 'LABEL', C.text);
    const end = g.text(r.w === null ? '--' : String(r.w), x + 6, y + 26, 'NUM', r.afk ? C.dim : C.text);
    g.text('W', end + 2, y + 31, 'LABEL', C.dim);
    g.text(`${r.pct}%`, x + w - 6, y + 31, 'LABEL', C.dim, { right: true });
    g.icon(ICON[STATIONS[r.st].icon], x + 6, y + 44, C.stone);
    if (r.mark) {
      if (r.markAlarm) chip(g, r.mark, x + w - 5, y + 46, 'LABEL', true);
      else g.text(r.mark, x + w - 6, y + 46, 'LABEL', r.markCol ?? C.dim, { right: true });
    } else {
      const lamp = r.state === 0 ? C.good : r.state < 0 ? C.under : C.amber;
      g.rect(x + w - 13, y + 46, 7, 7, lamp);
    }
  });
}

function fort(g, s) {
  const x = 804;
  const y = 8;
  const w = 148;
  const h = 68;
  plate(g, x, y, w, h, s.gateLow ? { frame: C.alarm } : {});
  // digits keep 2 px of the chip above and below
  ansata(g, x + 8, y + 6, 'GATE');
  g.text('/' + s.gateMax, x + w - 7, y + 19, 'LABEL', C.dim, { right: true });
  const gr = x + w - 7 - measure('/' + s.gateMax, FACES.LABEL) - 2;
  if (s.gateLow) g.rect(gr - measure(`${s.gate}`, FACES.KEY28) - 3, y + 3, measure(`${s.gate}`, FACES.KEY28) + 6, 34, C.alarm);
  g.text(`${s.gate}`, gr, y + 6, 'KEY28', C.text, { right: true });
  bar(g, x + 7, y + 37, w - 14, 3, s.gate / s.gateMax, s.gateLow ? C.alarm : C.stone);
  g.text('TAR', x + 7, y + 44, 'LABEL', C.bronzeHi);
  const e = g.text(`${s.curtain}`, x + 36, y + 41, 'NUM', s.curtain > 0 ? C.text : C.dim);
  g.text('/200', e + 2, y + 46, 'LABEL', C.dim);
  g.text(`${s.tarL} L`, x + w - 7, y + 46, 'LABEL', C.dim, { right: true });
  bar(g, x + 7, y + 58, w - 14, 4, s.curtain / 200, C.pitch);
  if (s.curtain > 0) g.rect(x + 7, y + 58, Math.round(((w - 14) * s.curtain) / 200), 1, C.bronzeHi);
}

function goldPlate(g, s) {
  const x = 804;
  const y = 78;
  const big = !!s.shop;
  const h = big ? 36 : 24;
  plate(g, x, y, 148, h);
  g.icon(ICON.denarius, x + 8, y + Math.floor((h - 10) / 2), C.gold);
  g.text('GOLD', x + 22, y + Math.floor((h - 9) / 2), 'LABEL', C.gold);
  g.text(`${s.gold}`, x + 141, y + Math.floor((h - (big ? 24 : 14)) / 2), big ? 'KEY' : 'NUM', C.gold, { right: true });
  return y + h + 2;
}

function routeCard(g, s, y) {
  const x = 804;
  const w = 148;
  const rowH = 17;
  const h = 23 + rowH * 5 + (s.coupling !== undefined ? 13 : 0);
  plate(g, x, y, w, h);
  ansata(g, x + 8, y + 4, 'STATIONS');
  g.text('< >', x + w - 7, y + 8, 'LABEL', C.dim, { right: true });
  STATIONS.forEach((st, i) => {
    const ry = y + 23 + i * rowH;
    const here = s.mine === i;
    if (here) {
      g.rect(x + 3, ry - 2, w - 6, rowH - 1, C.bronzeLo);
      g.rect(x + 3, ry - 2, 2, rowH - 1, C.bronzeHi);
    } else if (s.goingTo === i) {
      g.rect(x + 3, ry - 2, 2, rowH - 1, C.bronzeHi);
    }
    g.icon(ICON[st.icon], x + 6, ry, here ? C.text : C.stone);
    g.text(st.name, x + 21, ry + 2, 'LABEL', C.text);
    const riders = s.riders.filter((r) => r.st === i);
    if (s.hot === i && !here) g.rect(x + 3, ry - 1, 2, rowH - 3, C.alarm);
    for (let c = 0; c < st.cap; c++) {
      const px = x + w - 6 - (st.cap - c) * 8;
      const r = riders[c];
      if (r) g.icon(SHAPE[r.slot], px, ry + 2, SLOT[r.slot]);
      else g.icon(PEG, px + 1, ry + 3, C.dim);
    }
  });
  if (s.coupling !== undefined) {
    const by = y + 23 + rowH * 5;
    g.text('COUPLING', x + 7, by, 'LABEL', C.bronzeHi);
    bar(g, x + 76, by + 2, w - 83, 5, s.coupling, C.bronzeHi);
  }
  return y + h + 2;
}

function overdrive(g, s, y) {
  const x = 804;
  const o = s.od;
  const lit = o.mode === 'prompt' || o.mode === 'on';
  plate(g, x, y, 148, 36, { fill: lit ? rgb('#3a2412') : C.wax });
  g.rect(x + 8, y + 7, 3, 22, C.bronzeLo);
  g.rect(x + 6, o.mode === 'on' ? y + 23 : y + 7, 7, 4, C.bronzeHi);
  g.text(o.top, x + 18, y + 7, 'LABEL', lit ? C.gold : C.text);
  if (o.sub) g.text(o.sub, x + 18, y + 18, 'LABEL', lit ? C.text : C.dim);
  if (o.fill > 0 && o.fill < 1) bar(g, x + 18, y + 30, 122, 2, o.fill, C.gold);
}

// The cockpit: the one place a rider on the rivet looks. Clock, watts and cadence side by side at
// 72 px, one instruction, what comes next. The heart rate cell exists only with a sensor.
function cockpit(g, s) {
  const me = s.me;
  const hasHr = me.hr !== undefined;
  const x = 456;
  const w = hasHr ? 404 : 344;
  const h = 112;
  const y = 420;
  plate(g, x, y, w, h);
  // whose: a plaque on the frame, right-aligned, in the rider's colour and shape, with the station
  const name = me.name + ' · ' + STATIONS[s.mine].name;
  const tagW = measure(name, FACES.LABEL) + 21;
  const tag = ansata(g, x + w - tagW - 12, y - 14, name, { lead: 11 });
  g.icon(SHAPE[me.slot], tag.x + 4, y - 10, SLOT[me.slot]);

  const cap = y + 6;
  const num = y + 21;
  const gy = y + 60;
  const top = y + 6;
  const rule = 56;
  // the clock
  g.text(me.clockCap, x + 9, cap, 'BODY', C.dim);
  g.text(me.clock, x + 9, num, 'KEY36', me.clockSoon ? C.gold : C.text);
  let cx = x + 9 + 92;
  g.rect(cx, top, 1, rule + 2, C.waxLine);
  cx += 7;
  // the watts: the applied target above them, %FTP and the opt-in W/kg beside
  g.text(me.targetCap, cx, cap, 'BODY', C.dim);
  const wCol = me.w === null ? C.dim : C.text;
  g.text(me.w === null ? '--' : String(me.w), cx, num, 'KEY36', wCol);
  const side = cx + 78;
  g.text(me.pct + '%', side, num + 1, 'NUM', wCol);
  if (me.state !== 0 && me.w !== null) g.icon(me.state < 0 ? ICON.up : ICON.down, side + 34, num + 3, me.state < 0 ? C.under : C.amber);
  if (me.wkg) g.text(me.wkg + ' WKG', side, num + 22, 'LABEL', C.dim);
  // the band, flat, with a needle
  const gw = 132;
  g.rect(cx, gy, gw, 5, C.track);
  if (me.band) g.rect(cx + Math.round((gw * me.band[0]) / me.scale), gy, Math.round((gw * (me.band[1] - me.band[0])) / me.scale), 5, C.verd);
  if (me.w !== null) g.rect(cx + Math.min(gw - 2, Math.round((gw * me.w) / me.scale)), gy - 2, 2, 9, C.text);
  cx += gw + 5;
  g.rect(cx, top, 1, rule + 2, C.waxLine);
  cx += 7;
  // the cadence, what the rider controls in ERG; low cadence is the alarm
  g.text(me.cadCap ?? 'RPM ' + me.cband[0] + '-' + me.cband[1], cx, cap, 'BODY', C.dim);
  if (me.cadLow) g.rect(cx - 2, num - 2, 66, 40, C.alarm);
  g.text(String(me.cad), cx, num, 'KEY36', me.cadStale ? C.dim : C.text);
  if (me.cadLow) g.icon(ICON.up, cx + 54, num + 1, C.text);
  const cw = 86;
  g.rect(cx, gy, cw, 5, C.track);
  g.rect(cx + Math.round((cw * (me.cband[0] - 30)) / 120), gy, Math.round((cw * (me.cband[1] - me.cband[0])) / 120), 5, C.verd);
  g.rect(cx + Math.round((cw * (me.cad - 30)) / 120), gy - 2, 2, 9, C.text);
  // the heart rate: cream digits, muted heart. Dropout shows dashes; no sensor, no cell.
  if (hasHr) {
    cx += cw + 4;
    g.rect(cx, top, 1, rule + 2, C.waxLine);
    cx += 6;
    g.icon(ICON.heart, cx, cap + 3, C.heart);
    g.text('BPM', cx + 9, cap, 'BODY', C.dim);
    g.text(me.hr === null ? '--' : String(me.hr), cx, num + 6, 'KEY', me.hr === null ? C.dim : C.text);
  }

  g.rect(x + 3, y + 69, w - 6, 1, C.waxLine);
  // one instruction, from the state; only an alarm sits on a red chip; SIM says so in bronze
  if (me.lineAlarm) chip(g, me.line, x + 9, y + 73, 'LINE');
  else g.text(me.line, x + 9, y + 73, 'LINE', me.lineCol ?? C.gold);
  if (me.sim) chip(g, 'SIM: YOU SHIFT', x + w - 9, y + 75, 'LABEL', true, C.bronze, C.ink);
  else g.text('ERG', x + w - 9, y + 75, 'LABEL', C.dim, { right: true });
  g.rect(x + 3, y + 90, w - 6, 1, C.waxLine);
  // what comes next, then the reserve (a thin bar; a number only when it matters), or the gear in SIM
  g.text(me.next, x + 9, y + 94, 'BODY', C.text);
  const rx = x + w - 9;
  if (me.sim) {
    const gs = String(me.gear);
    g.text(gs, rx, y + 93, 'NUM', C.bronzeHi, { right: true });
    g.text('GEAR', rx - measure(gs, FACES.NUM) - 4, y + 96, 'LABEL', C.text, { right: true });
  } else {
    const low = me.wbal < 0.5;
    g.text("W'", rx - 72, y + 96, 'LABEL', C.dim);
    bar(g, rx - 56, y + 99, low ? 26 : 56, 3, me.wbal, C.under);
    if (low) g.text(Math.round(me.wbal * 100) + '%', rx, y + 96, 'LABEL', C.text, { right: true });
  }
}

function worldTag(g, x, y, str) {
  const f = FACES.LABEL;
  const w = measure(str, f) + 8;
  const lx = Math.round(x - w / 2);
  g.rect(lx, y, w, 14, C.alarm);
  drawText(str, lx + 4, y + 3, f, (px, py) => g.put(px, py, C.text));
  g.rect(x, y + 14, 1, 5, C.alarm);
}

function gateBanner(g, str) {
  const x = 300;
  const y = 372;
  const f = FACES.LINE;
  const w = measure(str, f) + 20;
  g.rect(x + 2, y + 2, w, 22, [0, 0, 0], 0.4);
  g.rect(x, y, w, 22, C.oxblood);
  g.rect(x, y, w, 1, C.alarm);
  g.rect(x, y + 21, w, 1, C.alarm);
  drawText(str, x + 10, y + 4, f, (px, py) => g.put(px, py, C.text));
  // the leader to the gate
  for (let j = 0; j < 62; j++) g.put(380 - Math.floor(j / 8), y - j, C.oxblood);
}

function shop(g, s) {
  const x = 8;
  const y = 382;
  const w = 340;
  const h = 150;
  plate(g, x, y, w, h);
  ansata(g, x + 10, y + 5, 'QUARTERMASTER');
  g.text(s.shop.countdown, x + w - 9, y + 9, 'LABEL', C.gold, { right: true });
  s.shop.rows.forEach((r, i) => {
    const ry = y + 26 + i * 24;
    if (r.sel) {
      g.rect(x + 4, ry, w - 8, 22, C.bronzeLo);
      g.rect(x + 4, ry, 2, 22, C.bronzeHi);
      g.text('>', x + 9, ry + 5, 'BODY', C.gold);
    }
    g.text(r.text, x + 20, ry + 5, 'BODY', r.ok ? C.text : C.dim);
    if (r.note) g.text(r.note, x + w - 50, ry + 7, 'LABEL', r.ok ? C.gold : C.dim, { right: true });
    if (r.cost !== undefined) {
      g.icon(ICON.denarius, x + w - 44, ry + 6, r.ok ? C.gold : C.dim);
      g.text(`${r.cost}`, x + w - 9, ry + 5, 'BODY', r.ok ? C.gold : C.dim, { right: true });
    }
  });
}

const CREW = (a, b, c, d) => [
  { slot: 0, name: 'SIMON', you: true, ...a },
  { slot: 1, name: 'RIDER 2', ...b },
  { slot: 2, name: 'RIDER 3', ...c },
  { slot: 3, name: 'RIDER 4', ...d },
];
const BASE_ME = { name: 'SIMON', slot: 0, scale: 320, cband: [80, 100] };

const STATES = {
  // steady in a wave, heart rate sensor, W/kg opted in
  wave: {
    title: 'WAVE 2 OF 3', end: 'ENDS IN 14:15', elapsed: 1005, phase: 4,
    enemies: [{ icon: 'spear', n: 87 }, { icon: 'shield', n: 18 }, { icon: 'chariot', n: 6 }, { icon: 'ram', n: 1 }],
    riders: CREW({ st: 3 }, { w: 188, pct: 94, st: 2, state: 0 }, { w: 214, pct: 95, st: 2, state: 0 }, { w: 166, pct: 83, st: 3, state: -1 }),
    gate: 98, gateMax: 130, curtain: 120, tarL: 210, gold: 53, mine: 3, hot: 1,
    od: { mode: 'prompt', top: 'OVERDRIVE READY', sub: 'SURGE TO START', fill: 1 },
    me: { ...BASE_ME, clockCap: 'WAVE LEFT', clock: '3:15', targetCap: 'TARGET 190 W', w: 192, pct: 96, wkg: '2.7', state: 0, band: [180, 200], cad: 88, hr: 151, line: 'SPIN 80-100', next: 'NEXT: BREAK, 3:00 AT 100 W', wbal: 0.92 },
  },
  // the 30 s sprint: SIM, the rider shifts, the band is 1.2-1.4 x FTP
  overdrive: {
    title: 'WAVE 2 OF 3', end: 'ENDS IN 14:00', elapsed: 1020, phase: 4,
    enemies: [{ icon: 'spear', n: 62 }, { icon: 'shield', n: 21 }, { icon: 'chariot', n: 9 }],
    riders: CREW({ st: 1 }, { w: 188, pct: 94, st: 2, state: 0 }, { w: 190, pct: 95, st: 2, state: 0 }, { w: 188, pct: 94, st: 3, state: 0, mark: 'OD 0:12', markCol: C.gold }),
    gate: 97, gateMax: 130, curtain: 80, tarL: 180, gold: 61, mine: 1,
    od: { mode: 'on', top: 'OVERDRIVE 0:22', sub: 'DOUBLE OUTPUT', fill: 0.73 },
    me: { ...BASE_ME, sim: true, gear: 15, clockCap: 'SPRINT LEFT', clock: '0:22', targetCap: 'SPRINT 240-280', w: 262, pct: 131, state: 0, band: [240, 280], cad: 96, hr: 168, line: 'SPRINT 240-280 W, SHIFT UP', next: 'THEN: ERG AT 190 W' },
  },
  // the road is the problem: gate failing, a tower near, cadence sagging, a sensor dropped
  alarm: {
    title: 'WAVE 3 OF 3', end: 'ENDS IN 7:40', elapsed: 1400, phase: 6,
    enemies: [{ icon: 'tower', n: 1, warn: true }, { icon: 'spear', n: 45 }, { icon: 'shield', n: 12 }],
    warning: 'TOWER 110 M',
    riders: CREW({ st: 1 }, { w: 188, pct: 94, st: 2, state: 0 }, { w: 0, pct: 0, st: 4, state: -1, afk: true, mark: 'AFK' }, { w: 92, pct: 46, st: 3, state: -1, mark: 'RESCUE', markAlarm: true }),
    gate: 24, gateMax: 180, gateLow: true, curtain: 0, tarL: 40, gold: 30, mine: 1, hot: 4, coupling: 0.6, goingTo: 4,
    od: { mode: 'cool', top: 'RECHARGING', sub: '1:14', fill: 0.2 },
    me: { ...BASE_ME, clockCap: 'WAVE LEFT', clock: '4:40', targetCap: 'TARGET 190 W', w: 191, pct: 95, state: 0, band: [180, 200], cad: 62, cadLow: true, hr: null, line: 'SPIN UP: RESCUE AT 45', lineAlarm: true, next: 'NEXT: COOL-DOWN, 3:00 AT 100 W', wbal: 0.34 },
  },
  // your own rescue: the applied target, never the plan
  rescue: {
    title: 'WAVE 2 OF 3', end: 'ENDS IN 15:02', elapsed: 958, phase: 4,
    enemies: [{ icon: 'spear', n: 74 }, { icon: 'chariot', n: 3 }],
    riders: CREW({ st: 3 }, { w: 188, pct: 94, st: 2, state: 0 }, { w: 190, pct: 95, st: 2, state: 0 }, { w: 188, pct: 94, st: 3, state: 0 }),
    gate: 109, gateMax: 130, curtain: 40, tarL: 210, gold: 48, mine: 3,
    od: { mode: 'off', top: 'OVERDRIVE', sub: 'NOT IN RESCUE', fill: 0 },
    me: { ...BASE_ME, clockCap: 'WAVE LEFT', clock: '4:02', targetCap: 'RESCUE 100 W', cadCap: 'RPM 70+', w: 104, pct: 52, state: 0, band: [95, 105], cad: 58, cadLow: true, hr: 172, line: 'RESCUE: SPIN 70+', lineAlarm: true, next: 'THEN: RAMP BACK TO 190 W', wbal: 0.71 },
  },
  // the warm-up: the ramp, the platform's banner
  warmup: {
    title: 'WARM-UP WAVE', end: 'ENDS IN 28:30', elapsed: 150, phase: 0,
    enemies: [{ icon: 'spear', n: 12 }],
    riders: CREW({ st: 3 }, { w: 118, pct: 58, st: 1, state: 0 }, { w: 116, pct: 58, st: 3, state: 0 }, { w: 115, pct: 57, st: 2, state: 0 }),
    gate: 130, gateMax: 130, curtain: 0, tarL: 300, gold: 42, mine: 3,
    od: { mode: 'off', top: 'OVERDRIVE', sub: 'NOT IN WARM-UP', fill: 0 },
    me: { ...BASE_ME, clockCap: 'WARM-UP', clock: '2:30', targetCap: 'RAMP 115-130', w: 116, pct: 58, state: 0, band: [110, 121], cad: 86, hr: 118, line: 'SETTLE IN, SPIN 80-100', next: 'NEXT: BUILD BREAK, 2:00 AT 100 W', wbal: 1 },
  },
  // the cool-down: the plan's last ramp, the road empty, the ride still counts
  cooldown: {
    title: 'COOL-DOWN', end: 'ENDS IN 1:40', elapsed: 1760, phase: 7, noLife: true,
    enemies: [],
    riders: CREW({ st: 0 }, { w: 92, pct: 46, st: 0, state: 0 }, { w: 90, pct: 45, st: 0, state: 0 }, { w: 91, pct: 45, st: 0, state: 0 }),
    gate: 115, gateMax: 180, curtain: 0, tarL: 120, gold: 18, mine: 0,
    od: { mode: 'off', top: 'OVERDRIVE', sub: 'WAVES ONLY', fill: 0 },
    me: { ...BASE_ME, clockCap: 'COOL-DOWN', clock: '1:40', targetCap: 'RAMP 90-80 W', w: 91, pct: 45, state: 0, band: [80, 96], cad: 84, hr: 122, line: 'SPIN IT OUT', next: 'NEXT: RESULTS', wbal: 0.88 },
  },
  // a break with the shop open, no heart rate sensor: the cell is gone, the plate narrower
  break: {
    title: 'BUILD BREAK', end: 'ENDS IN 24:30', elapsed: 390, phase: 1, noLife: true,
    enemies: [],
    riders: CREW({ st: 0 }, { w: 99, pct: 50, st: 0, state: 0 }, { w: 100, pct: 50, st: 0, state: 0 }, { w: 98, pct: 49, st: 0, state: 0 }),
    gate: 130, gateMax: 130, curtain: 0, tarL: 300, gold: 40, mine: 0,
    od: { mode: 'off', top: 'OVERDRIVE', sub: 'WAVES ONLY', fill: 0 },
    me: { ...BASE_ME, clockCap: 'BREAK LEFT', clock: '0:30', targetCap: 'TARGET 100 W', w: 101, pct: 50, state: 0, band: [95, 105], cad: 90, line: 'LOAD UP IN 0:30, SPIN UP', next: 'NEXT: WAVE 1, 5:00 AT 190 W', wbal: 1, clockSoon: true },
    shop: {
      countdown: 'PICKS IN 8 S',
      rows: [
        { text: 'TREE BALLISTA +40% OUTPUT', cost: 40, ok: true, sel: true, note: 'BEST' },
        { text: 'SAVE GOLD', ok: true },
        { text: 'GREAT ONAGER SPECIAL', cost: 70, ok: false, note: '30 MORE' },
        { text: 'BUILD A SCORPION', cost: 60, ok: false, note: '20 MORE' },
        { text: 'MORE ITEMS: 2 OF 5', ok: true },
      ],
    },
  },
};

const post = { skyTop: hex('#c8c3ba'), skyBottom: hex('#c8c3ba') };
const baseFrame = (life) => {
  W.build();
  const r = new Raster(960, 540, W.CAMERA.ox, W.CAMERA.oy, W.CAMERA.k);
  const scene = new Scene(r);
  scene.build();
  r.render();
  if (life) new Life(r, scene).run();
  const frame = r.finish({ ...post, focusTop: 95, focusBottom: 500, rampTop: 80, rampBottom: 40, blurTop: 3, blurBottom: 3 });
  return toRgba8(960, 540, frame, 1).data;
};
const withLife = baseFrame(true);
const empty = baseFrame(false);

for (const [name, s] of Object.entries(STATES)) {
  const g = new Canvas(s.noLife ? empty : withLife);
  session(g, s);
  crew(g, s);
  fort(g, s);
  const ry = goldPlate(g, s);
  const oy = routeCard(g, s, ry);
  overdrive(g, s, oy);
  cockpit(g, s);
  if (s.shop) shop(g, s);
  if (name === 'alarm') {
    gateBanner(g, 'THE GATE IS FAILING');
    worldTag(g, 236, 300, 'TOWER 110 M');
  }
  const o = new Uint8ClampedArray(1920 * 1080 * 4);
  for (let y = 0; y < 1080; y++) {
    for (let x = 0; x < 1920; x++) {
      const si = ((y >> 1) * 960 + (x >> 1)) * 4;
      const di = (y * 1920 + x) * 4;
      o[di] = g.px[si];
      o[di + 1] = g.px[si + 1];
      o[di + 2] = g.px[si + 2];
      o[di + 3] = 255;
    }
  }
  writePng(join(out, `hud_${name}.png`), 1920, 1080, o);
}
console.log(`hud mock -> ${out}`);
