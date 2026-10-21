#!/usr/bin/env node
// A stand-in scripted peer for the harness tests: speaks the stdout contract of
// docs/ARCHITECTURE.md "Scripted peers" and writes a report, without Godot. Faults come from
// FAKE_PEER_FAULT: script_error, desync, event_mismatch, warmup, double_upload, state,
// host_exit, no_fit, wrong_peer, fast_victim.
import fs from 'node:fs';
import path from 'node:path';
import { leaseTokenValid } from '../../lib/godot_lock.mjs';

const sep = process.argv.indexOf('--');
const args = sep >= 0 ? process.argv.slice(sep + 1) : [];
const flag = (k) => {
  const a = args.find((x) => x.startsWith(`--${k}=`));
  return a ? a.slice(k.length + 3) : null;
};
const has = (k) => args.includes(`--${k}`);
const fault = process.env.FAKE_PEER_FAULT ?? '';
const sessionMs = Number(process.env.FAKE_PEER_SESSION_MS ?? 2500);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const say = (l) => process.stdout.write(`${l}\n`);
const die = (code, msg) => {
  process.stderr.write(`fake_peer: ${msg}\n`);
  process.exit(code);
};

// The harness's promises to every peer.
if (!leaseTokenValid(process.env.WATTLANDS_GODOT_LEASE_TOKEN)) die(3, 'no valid WATTLANDS_GODOT_LEASE_TOKEN');
if (!flag('mock-trainer')) die(4, 'no --mock-trainer');
if (process.env.WATTLANDS_NO_HW_CONTROL !== '1' || process.env.WATTLANDS_NO_NETWORK_INTEGRATIONS !== '1') die(5, 'locks not set');
if (process.env.FAL_KEY !== undefined || process.env.WATTLANDS_ALLOW_ART !== undefined) die(6, 'art variables leaked');
for (const k of ['game', 'relay', 'profile-dir', 'report', 'strava-base', 'seed', 'wait-peers']) if (!flag(k)) die(7, `no --${k}`);
for (const k of ['autopilot', 'e2e']) if (!has(k)) die(7, `no --${k}`);
if (flag('sim-speed') !== '1') die(7, '--sim-speed must be 1');

const profile = flag('profile-dir');
const report = flag('report');
const isHost = has('host');
if (!isHost && !flag('join')) die(8, 'neither --host nor --join');
const role = isHost ? 'host' : path.basename(path.dirname(profile));
let peerId = isHost ? 1 : role === 'client1' ? 2 : 3;
const tokenFile = path.join(profile, 'reconnect_token.json');
const rejoin = !isHost && fs.existsSync(tokenFile);
if (rejoin && fault === 'wrong_peer') peerId = 9;
if (!isHost) fs.writeFileSync(tokenFile, JSON.stringify({ token: 'fake' }));

const ALL = [
  { type: 'phase_started', peer: 1, index: 0 },
  { type: 'phase_started', peer: 2, index: 0 },
  { type: 'phase_started', peer: 3, index: 0 },
  { type: 'fake_event', n: 1 },
  { type: 'phase_started', peer: 1, index: 1 },
  { type: 'phase_started', peer: 2, index: 1 },
  { type: 'phase_started', peer: 3, index: 1 },
  { type: 'fake_event', n: 2, x: 0.5 },
  { type: 'phase_started', peer: 1, index: 2 },
  { type: 'phase_started', peer: 2, index: 2 },
  { type: 'phase_started', peer: 3, index: 2 },
  { type: 'results', grade: 'A', rows: [{ peer_id: 1, kj: 12.5 }, { peer_id: 2, kj: 12.4 }, { peer_id: 3, kj: 11.9 }] },
];

if (isHost) say('WATTLANDS_ROOM K7QX2M');
say(`WATTLANDS_PEER ${peerId}`);
say('WATTLANDS_STATE lobby');
await sleep(100);
say('WATTLANDS_STATE running');
if (fault === 'script_error' && role === 'client1') process.stderr.write('SCRIPT ERROR: fake failure\n   at: fake.gd:1\n');
if (fault === 'push_error' && role === 'host') process.stderr.write('ERROR: something went wrong\n');
await sleep(fault === 'fast_victim' && role === 'client2' && !rejoin ? 0 : sessionMs);
say('WATTLANDS_STATE cooldown');
await sleep(300);
say('WATTLANDS_STATE results');

let events = ALL.map((e, i) => ({ t: i + (isHost ? 0 : 0.2), ...e }));
if (rejoin) {
  const from = ALL.findIndex((e) => e.type === 'fake_event' && e.n === 2);
  events = [{ t: 0, type: 'phase_started', peer: 3, index: 1 }, ...events.slice(from)];
}
events.unshift({ t: 0, type: 'session_state', state: 'running' });
if (fault === 'event_mismatch' && role === 'client1') events = events.map((e) => (e.type === 'fake_event' && e.n === 2 ? { ...e, n: 3 } : e));

const trace = [
  { t: 0, mode: 'ERG', applied_target_w: 100, applied_pct: 50, applied_grade_pct: 0, warmup_active: true, clamped_by: [], rescue: false, afk: false },
  { t: 1, mode: 'ERG', applied_target_w: 130, applied_pct: fault === 'warmup' && isHost ? 70 : 65, applied_grade_pct: 0, warmup_active: true, clamped_by: [], rescue: false, afk: false },
  { t: 2, mode: 'SIM', applied_target_w: 0, applied_pct: 0, applied_grade_pct: 2.5, warmup_active: true, clamped_by: ['warmup'], rescue: false, afk: false },
];
const directives = isHost
  ? [{ id: 1, peer: 1, kind: 'request', requested: { target_pct: 70 }, applied: { target_pct: 65 }, clamped_by: ['warmup'], refused: false, reason: '', t: 5 }]
  : [];

const fitPaths = [];
if (!(fault === 'no_fit' && role === 'client1')) {
  const fit = path.join(profile, 'rides', `${role}${rejoin ? '_rejoin' : ''}.fit`);
  fs.mkdirSync(path.dirname(fit), { recursive: true });
  fs.writeFileSync(fit, 'FAKEFIT');
  fitPaths.push(fit.replaceAll('\\', '/'));
}

const uploads = [];
if (has('strava-auto-upload')) {
  if (!flag('strava-client-id') || !flag('strava-client-secret')) die(9, 'auto-upload without credentials');
  const times = fault === 'double_upload' ? 2 : 1;
  for (let i = 0; i < times; i++) {
    const res = await fetch(`${flag('strava-base')}/api/v3/uploads`, { method: 'POST', body: 'FAKEFIT' });
    const up = await res.json();
    uploads.push({ state: 'uploaded', activity_id: up.activity_id });
  }
}

const out = {
  role: isHost ? 'HOST' : 'CLIENT',
  peer_id: peerId,
  room: 'K7QX2M',
  game_id: flag('game'),
  content_id: 'e2e',
  exit_reason: 'complete',
  events,
  directives,
  trace,
  fit_paths: fitPaths,
  uploads,
  desync_warnings: fault === 'desync' && role === 'client1' ? 1 : 0,
  script_errors: 0,
  final_state: { score: 100 + (fault === 'state' && role === 'client1' ? 50 : 0), distance_m: 1000.4, local_peer: peerId },
};
fs.mkdirSync(path.dirname(report), { recursive: true });
fs.writeFileSync(report, JSON.stringify(out, null, 2));
say('WATTLANDS_DONE complete');
process.exit(fault === 'host_exit' && isHost ? 1 : 0);
