// Read-only dead-code scan. Word-token counts, so string-based references (call, has_method, connect,
// JSON, tscn) count as uses. A hit list, not a proof: every entry gets a manual look.
import { execSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
const repo = process.cwd();
const all = execSync('git ls-files', { cwd: repo, encoding: 'utf8', maxBuffer: 1e9 }).split('\n').filter(Boolean);
const TEXT = /\.(gd|gdshader|tscn|tres|json|csv|cfg|godot|mjs|sh|ps1|yml|py|ts)$|^tools\/(run_tests|screenshot|new_game|run_game_sim)$/;
const isDoc = f => f.endsWith('.md');
const runtimeRoots = f => f.startsWith('src/') || f.startsWith('addons/wattlands/') || f.startsWith('content/') || f === 'project.godot' || f.startsWith('assets/');
const testRoots = f => f.startsWith('tests/');
const toolRoots = f => f.startsWith('tools/') || f.startsWith('server/');
const texts = new Map();
for (const f of all) { if (!TEXT.test(f) || f.startsWith('addons/gut/') || f.startsWith('addons/gdble/')) continue; try { texts.set(f, readFileSync(`${repo}/${f}`, 'utf8')); } catch {} }
const RT = new Map(), TE = new Map(), TO = new Map();
const tok = /[A-Za-z_][A-Za-z_0-9]*/g;
const perFile = new Map();
for (const [f, t] of texts) {
  const m = testRoots(f) ? TE : toolRoots(f) ? TO : RT;
  const inFile = new Map();
  for (const w of t.match(tok) || []) { m.set(w, (m.get(w) || 0) + 1); inFile.set(w, (inFile.get(w) || 0) + 1); }
  perFile.set(f, inFile);
}
const gd = [...texts.keys()].filter(f => f.endsWith('.gd') && (f.startsWith('src/') || f.startsWith('addons/wattlands/')));
const mode = process.argv[2];
if (mode === 'classes') {
  for (const f of gd) {
    const m = texts.get(f).match(/^class_name\s+(\w+)/m); if (!m) continue;
    const n = m[1]; const self = perFile.get(f).get(n) || 0;
    const rt = (RT.get(n) || 0) - self, te = TE.get(n) || 0, to = TO.get(n) || 0;
    if (rt === 0) console.log(`${n}\t${f}\t${texts.get(f).split('\n').length}L\trt=0 tests=${te} tools=${to}`);
  }
}
if (mode === 'noclass') {
  for (const f of gd) {
    if (/^class_name\s+/m.test(texts.get(f))) continue;
    const base = f.split('/').pop(); let hits = [];
    for (const [g, t] of texts) if (g !== f && t.includes(base)) hits.push(g);
    console.log(`${f}\t${texts.get(f).split('\n').length}L\tref by: ${hits.slice(0, 4).join(', ')}`);
  }
}
if (mode === 'funcs') {
  const engine = /^(_ready|_process|_physics_process|_draw|_init|_input|_unhandled_input|_enter_tree|_exit_tree|_notification|_gui_input|_to_string|_get_minimum_size)$/;
  const virt = /^(configure|build_effort_plans|sim_step|autopilot_intents|on_rescue|on_afk|local_intents|snapshot|apply_snapshot|apply_event|client_predict|int_fields|make_view|hud_spec|results|apply_progress|before_each|after_each)$/;
  const rows = [];
  for (const f of gd) {
    const t = texts.get(f); const re = /^(?:static )?func\s+(\w+)/gm; let m;
    while ((m = re.exec(t))) {
      const n = m[1]; if (engine.test(n) || virt.test(n)) continue;
      const rt = RT.get(n) || 0, te = TE.get(n) || 0, to = TO.get(n) || 0;
      const line = t.slice(0, m.index).split('\n').length;
      if (rt <= 1) rows.push({ n, f, line, rt, te, to });
    }
  }
  const kind = process.argv[3];
  for (const r of rows) {
    if (kind === 'zero' && r.te === 0 && r.to === 0) console.log(`${r.f}:${r.line} ${r.n}`);
    if (kind === 'testonly' && (r.te > 0 || r.to > 0)) console.log(`${r.f}:${r.line} ${r.n} tests=${r.te}`);
  }
}
if (mode === 'consts') {
  for (const f of gd) {
    const t = texts.get(f); const re = /^(?:const|var|signal)\s+(\w+)/gm; let m;
    while ((m = re.exec(t))) {
      const n = m[1]; const rt = RT.get(n) || 0, te = TE.get(n) || 0, to = TO.get(n) || 0;
      if (rt <= 1 && te === 0 && to === 0) console.log(`${f}:${t.slice(0, m.index).split('\n').length} ${n}`);
    }
  }
}
if (mode === 'assets') {
  const bins = all.filter(f => /\.(png|webp|jpg|ttf|otf|wav|ogg|mp3|svg|glb)$/.test(f) && (f.startsWith('assets/') || f.startsWith('src/') || f.startsWith('addons/wattlands/')));
  const allText = [...texts.entries()].filter(([f]) => !f.includes('tools_src'));
  for (const b of bins) {
    const base = b.split('/').pop(); const stem = base.replace(/\.[^.]+$/, '');
    let rt = 0, te = 0, ts = 0;
    for (const [f, t] of texts) {
      if (t.includes(stem)) { if (f.includes('tools_src')) ts++; else if (testRoots(f)) te++; else rt++; }
    }
    if (rt === 0) console.log(`${(statSync(`${repo}/${b}`).size / 1024).toFixed(1)}KB\t${b}\trt=0 tests=${te} tools_src=${ts}`);
  }
}
if (mode === 'strings') {
  const csvs = all.filter(f => /^content\/.*\.csv$/.test(f));
  for (const c of csvs) {
    const keys = readFileSync(`${repo}/${c}`, 'utf8').split(/\r?\n/).slice(1).map(l => l.split(',')[0]).filter(Boolean);
    const dead = [];
    for (const k of keys) {
      const rt = (RT.get(k) || 0) - (perFile.get(c)?.get(k) || 0); const te = TE.get(k) || 0;
      if (rt <= 0) dead.push(k + (te ? '(t)' : ''));
    }
    console.log(`${c}: ${keys.length} keys, ${dead.length} unreferenced literally: ${dead.slice(0, 60).join(' ')}`);
  }
}
if (mode === 'content') {
  for (const f of all.filter(x => /^content\/.*\.(json|zwo)$/.test(x))) {
    const base = f.split('/').pop(); let hits = 0;
    for (const [g, t] of texts) if (g !== f && !g.startsWith('tests/') && t.includes(base)) hits++;
    if (!hits) console.log('no literal ref:', f);
  }
}
