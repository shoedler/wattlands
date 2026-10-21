// Tests for tools/new_game, tools/new_game.ps1 and tools/lib/new_game.mjs (BRIEF 3.6, BRIEF 7.1
// "tools/new_game refusing an id whose paths exist", docs/OWNERSHIP.md TL1 and C17). Every scaffold
// goes into a temp tree; nothing here writes into this checkout. No Godot needed.
import { test, describe, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { REPO, TOOLS, IS_WIN, BASH, GIT, powershellExe, runProc, rmQuiet } from './helpers.mjs';
import { rewrite, classPrefix, titleOf, validateId, stripUids, scaffold, TREES } from '../lib/new_game.mjs';

const temps = [];
after(() => {
  for (const d of temps) rmQuiet(d);
});

function tempRoot(name) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), `wattlands-new-game-${name}-`));
  temps.push(d);
  return d;
}

function write(root, rel, data) {
  const f = path.join(root, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, data);
}

/** Every file under `dir`, as forward-slash paths relative to it. */
function listFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  const walk = (rel) => {
    for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true })) {
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) walk(r);
      else out.push(r);
    }
  };
  walk('');
  return out.sort();
}

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52]);

/** A small synthetic template that exercises every rewriting rule. */
function fixtureRoot(name) {
  const root = tempRoot(name);
  write(root, 'src/games/_template/game.json', '{\n  "id": "_template", "title": "Template",\n  "entry": "res://src/games/_template/template_game.gd"\n}\n');
  write(root, 'src/games/_template/template_game.gd', 'class_name TemplateGame\nextends GameModule\n## The template game.\nconst KEY := "_TEMPLATE_HELLO"\nconst OLD := "TEMPLATE_BYE"\nvar rules := TemplateRules\nconst DIR := "res://content/_template/default.json"\nconst SRC := "_template"\n');
  write(root, 'src/games/_template/template_game.gd.uid', 'uid://abc123\n');
  write(root, 'src/games/_template/view/template_scene.tscn', '[gd_scene load_steps=2 format=3 uid="uid://b7x"]\n\n[ext_resource type="Script" uid="uid://c9y" path="res://src/games/_template/template_game.gd" id="1"]\n');
  write(root, 'src/games/_template/view/template_scene.tscn.import', '[remap]\n');
  write(root, 'content/_template/strings.csv', 'keys,en\n_TEMPLATE_HELLO,Hello\n');
  write(root, 'content/_template/strings.en.translation', 'binary-ish');
  write(root, 'content/_template/strings.csv.import', '[remap]\n');
  write(root, 'assets/_template/sprites/template_icon.png', PNG);
  write(root, 'tests/games/_template/test_template_rules.gd', 'extends GutTest\nconst F := preload("res://tests/games/_template/template_fakes.gd")\n');
  return root;
}

function snapshotTree(root) {
  return listFiles(root).map((f) => `${f}:${fs.readFileSync(path.join(root, f)).toString('base64')}`);
}

describe('rewriting rules', () => {
  test('class prefix, title and key prefix come from the id', () => {
    assert.equal(classPrefix('siege'), 'Siege');
    assert.equal(classPrefix('big_fish'), 'BigFish');
    assert.equal(classPrefix('tank2'), 'Tank2');
    assert.equal(titleOf('big_fish'), 'Big Fish');
    assert.equal(titleOf('fishing'), 'Fishing');
  });

  test('every template spelling is rewritten, in the right order', () => {
    const src = [
      'class_name TemplateGame',
      'var k := "_TEMPLATE_LAP_DONE"',
      'var k2 := "TEMPLATE_OLD"',
      'res://src/games/_template/template_game.gd',
      'test_template_rules.gd',
      '"source": "_template"',
      'the template game',
    ].join('\n');
    assert.equal(
      rewrite(src, 'big_fish'),
      [
        'class_name BigFishGame',
        'var k := "BIG_FISH_LAP_DONE"',
        'var k2 := "BIG_FISH_OLD"',
        'res://src/games/big_fish/big_fish_game.gd',
        'test_big_fish_rules.gd',
        '"source": "big_fish"',
        'the template game',
      ].join('\n'),
    );
  });

  test('uid attributes are stripped from scenes and resources', () => {
    assert.equal(
      stripUids('[gd_scene format=3 uid="uid://b7x"]\n[ext_resource type="Script" uid="uid://c9y" path="res://a.gd" id="1"]'),
      '[gd_scene format=3]\n[ext_resource type="Script" path="res://a.gd" id="1"]',
    );
  });

  test('ids must be lower case, start with a letter and never be the template', () => {
    for (const ok of ['siege', 'tank', 'fishing', 'big_fish', 'demo2', 'a']) assert.equal(validateId(ok), '', ok);
    for (const bad of ['', 'Siege', '1abc', '_template', '_x', 'a-b', 'a b', 'siège', 'demo/x', '..']) {
      assert.notEqual(validateId(bad), '', JSON.stringify(bad));
    }
  });
});

describe('scaffold', () => {
  test('copies and rewrites every template tree, skipping generated files', () => {
    const root = fixtureRoot('copy');
    const r = scaffold(root, 'big_fish');
    assert.equal(r.code, 0, r.message);
    assert.deepEqual(listFiles(path.join(root, 'src/games/big_fish')), ['big_fish_game.gd', 'game.json', 'view/big_fish_scene.tscn']);
    assert.deepEqual(listFiles(path.join(root, 'content/big_fish')), ['strings.csv']);
    assert.deepEqual(listFiles(path.join(root, 'assets/big_fish')), ['sprites/big_fish_icon.png']);
    assert.deepEqual(listFiles(path.join(root, 'tests/games/big_fish')), ['test_big_fish_rules.gd']);
    const gd = fs.readFileSync(path.join(root, 'src/games/big_fish/big_fish_game.gd'), 'utf8');
    assert.match(gd, /^class_name BigFishGame\n/);
    assert.match(gd, /"BIG_FISH_HELLO"/);
    assert.match(gd, /"BIG_FISH_BYE"/);
    assert.match(gd, /var rules := BigFishRules/);
    assert.match(gd, /res:\/\/content\/big_fish\/default\.json/);
    assert.match(gd, /const SRC := "big_fish"/);
    const scene = fs.readFileSync(path.join(root, 'src/games/big_fish/view/big_fish_scene.tscn'), 'utf8');
    assert.doesNotMatch(scene, /uid=/);
    assert.match(scene, /path="res:\/\/src\/games\/big_fish\/big_fish_game\.gd"/);
    assert.equal(fs.readFileSync(path.join(root, 'content/big_fish/strings.csv'), 'utf8'), 'keys,en\nBIG_FISH_HELLO,Hello\n');
    assert.deepEqual(fs.readFileSync(path.join(root, 'assets/big_fish/sprites/big_fish_icon.png')), PNG, 'binary files are copied byte for byte');
    const manifest = JSON.parse(fs.readFileSync(path.join(root, 'src/games/big_fish/game.json'), 'utf8'));
    assert.deepEqual(manifest, { id: 'big_fish', title: 'Big Fish', entry: 'res://src/games/big_fish/big_fish_game.gd' });
    assert.equal(fs.readFileSync(path.join(root, 'tests/games/big_fish/test_big_fish_rules.gd'), 'utf8'),
      'extends GutTest\nconst F := preload("res://tests/games/big_fish/big_fish_fakes.gd")\n');
    assert.ok(fs.existsSync(path.join(root, 'src/games/_template/template_game.gd.uid')), 'the template is untouched');
  });

  test('no .uid, .import or .translation file is ever copied', () => {
    const root = fixtureRoot('generated');
    assert.equal(scaffold(root, 'demo').code, 0);
    for (const tree of TREES) {
      for (const f of listFiles(path.join(root, tree, 'demo'))) assert.doesNotMatch(f, /\.(uid|import|translation)$/, f);
    }
  });

  test('writes the CI workflow and the three docs fragments', () => {
    const root = fixtureRoot('fragments');
    const r = scaffold(root, 'demo');
    assert.equal(r.code, 0);
    const wf = fs.readFileSync(path.join(root, '.github/workflows/game-demo.yml'), 'utf8');
    assert.match(wf, /^name: game-demo$/m);
    assert.match(wf, /runs-on: ubuntu-latest/);
    assert.match(wf, /tools\/run_tests --only=gut --gdir=res:\/\/tests\/games\/demo/);
    assert.match(wf, /tools\/check_scripts\.gd/);
    assert.doesNotMatch(wf, /\t/, 'YAML never uses tabs');
    for (const dir of ['docs/decisions', 'docs/credits.d', 'docs/changelog.d']) {
      assert.match(fs.readFileSync(path.join(root, dir, 'demo.md'), 'utf8'), /demo/);
    }
    assert.ok(r.written.includes('.github/workflows/game-demo.yml'));
  });

  test('an existing docs fragment is kept and never causes a refusal (OWNERSHIP C17)', () => {
    const root = fixtureRoot('keep');
    write(root, 'docs/decisions/demo.md', '# my decisions written before new_game\n');
    const r = scaffold(root, 'demo');
    assert.equal(r.code, 0, r.message);
    assert.deepEqual(r.kept, ['docs/decisions/demo.md']);
    assert.equal(fs.readFileSync(path.join(root, 'docs/decisions/demo.md'), 'utf8'), '# my decisions written before new_game\n');
    assert.ok(fs.existsSync(path.join(root, 'docs/credits.d/demo.md')));
  });

  for (const target of ['src/games/demo/x.gd', 'content/demo/x.json', 'assets/demo/x.png', 'tests/games/demo/x.gd', '.github/workflows/game-demo.yml']) {
    test(`refuses with exit 1 and writes nothing when ${target.split('/x')[0]} exists`, () => {
      const root = fixtureRoot('refuse');
      write(root, target, 'already here');
      const before = snapshotTree(root);
      const r = scaffold(root, 'demo');
      assert.equal(r.code, 1);
      assert.match(r.message, /refusing/);
      assert.match(r.message, /Nothing was written/);
      assert.deepEqual(snapshotTree(root), before);
    });
  }

  test('a bad id exits 2 and writes nothing', () => {
    const root = fixtureRoot('badid');
    const before = snapshotTree(root);
    for (const id of ['', 'Demo', '_template', '9lives']) {
      const r = scaffold(root, id);
      assert.equal(r.code, 2, id);
      assert.deepEqual(snapshotTree(root), before, id);
    }
  });

  test('--dry-run plans every file and writes nothing', () => {
    const root = fixtureRoot('dry');
    const before = snapshotTree(root);
    const r = scaffold(root, 'demo', { dryRun: true });
    assert.equal(r.code, 0);
    assert.match(r.message, /write src\/games\/demo\/demo_game\.gd/);
    assert.match(r.message, /write \.github\/workflows\/game-demo\.yml/);
    assert.deepEqual(snapshotTree(root), before);
  });

  test('a missing template is refused', () => {
    const root = tempRoot('empty');
    const r = scaffold(root, 'demo');
    assert.equal(r.code, 1);
    assert.match(r.message, /no template/);
    assert.deepEqual(listFiles(root), []);
  });
});

describe('the real template', () => {
  /** A temp tree holding this checkout's template trees only. */
  function realTemplateRoot() {
    const root = tempRoot('real');
    for (const tree of TREES) {
      const src = path.join(REPO, tree, '_template');
      if (fs.existsSync(src)) fs.cpSync(src, path.join(root, tree, '_template'), { recursive: true });
    }
    return root;
  }

  test('scaffolds a game with no template name left anywhere', () => {
    const root = realTemplateRoot();
    const r = scaffold(root, 'demo');
    assert.equal(r.code, 0, r.message);
    let gdFiles = 0;
    for (const tree of TREES) {
      for (const f of listFiles(path.join(root, tree, 'demo'))) {
        assert.doesNotMatch(f, /template/i, `file name ${tree}/demo/${f}`);
        const text = fs.readFileSync(path.join(root, tree, 'demo', f), 'utf8');
        assert.doesNotMatch(text, /_template|TEMPLATE_|Template[A-Z(]/, `${tree}/demo/${f}`);
        const cls = /^class_name (\w+)/m.exec(text);
        if (cls) assert.match(cls[1], /^Demo/, `${f}: game classes carry the game's prefix`);
        if (f.endsWith('.gd')) gdFiles += 1;
      }
    }
    assert.ok(gdFiles >= 6, `${gdFiles} scripts`);
    const manifest = JSON.parse(fs.readFileSync(path.join(root, 'src/games/demo/game.json'), 'utf8'));
    assert.equal(manifest.id, 'demo');
    assert.equal(manifest.title, 'Demo');
    const entry = manifest.entry.replace('res://', '');
    assert.ok(fs.existsSync(path.join(root, entry)), `entry ${manifest.entry} exists`);
    for (const c of manifest.contents) assert.ok(fs.existsSync(path.join(root, 'content/demo', `${c}.json`)), c);
    const keys = fs
      .readFileSync(path.join(root, 'content/demo/strings.csv'), 'utf8')
      .trim()
      .split('\n')
      .slice(1)
      .map((l) => l.split(',')[0]);
    assert.ok(keys.length > 5);
    for (const k of keys) assert.match(k, /^DEMO_[A-Z0-9_]+$/);
    assert.ok(fs.existsSync(path.join(root, 'tests/games/demo/integration/test_demo_session.gd')));
  });

  test('the template folders hold no generated file that would be skipped silently', () => {
    // .uid and .import files of the template are committed (CLAUDE.md) but must not be copied.
    const root = realTemplateRoot();
    scaffold(root, 'demo');
    for (const f of listFiles(path.join(root, 'src/games/demo'))) assert.doesNotMatch(f, /\.(uid|import)$/);
  });
});

describe('the wrappers', () => {
  const read = (rel) => fs.readFileSync(path.join(REPO, rel), 'utf8');

  test('tools/new_game is a bash script with a shebang, committed executable', () => {
    assert.match(read('tools/new_game'), /^#!\/usr\/bin\/env bash\n/);
    assert.match(read('tools/new_game'), /lib\/new_game\.mjs/);
    if (GIT) {
      const r = spawnSync(GIT, ['-C', REPO, 'ls-files', '-s', 'tools/new_game'], { encoding: 'utf8' });
      if (r.stdout.trim()) assert.match(r.stdout, /^100755 /, 'git add --chmod=+x tools/new_game');
    }
  });

  test('tools/new_game.ps1 keeps CRLF and runs the same Node core', () => {
    const ps = read('tools/new_game.ps1');
    assert.ok(ps.includes('\r\n') && !/[^\r]\n/.test(ps), 'CRLF only');
    assert.match(ps, /new_game\.mjs/);
  });

  const shells = [{ name: 'bash', ok: Boolean(BASH) }];
  if (IS_WIN) shells.push({ name: 'PowerShell', ok: Boolean(powershellExe()) });
  for (const sh of shells) {
    test(`${sh.name}: scaffolds, then refuses the same id, then rejects a bad id`, { skip: !sh.ok && `no ${sh.name}` }, async () => {
      const root = fixtureRoot(`wrap-${sh.name}`);
      const run = (args) =>
        sh.name === 'bash'
          ? runProc(BASH, [path.join(TOOLS, 'new_game').replaceAll('\\', '/'), ...args], { cwd: root })
          : runProc(powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(TOOLS, 'new_game.ps1'), ...args], { cwd: root });
      const first = await run(['demo', `--root=${root}`]);
      assert.equal(first.code, 0, first.stderr + first.stdout);
      assert.match(first.stdout, /scaffolded "demo"/);
      assert.ok(fs.existsSync(path.join(root, 'src/games/demo/demo_game.gd')));
      const again = await run(['demo', `--root=${root}`]);
      assert.equal(again.code, 1);
      assert.match(again.stderr, /refusing to scaffold "demo"/);
      const bad = await run(['Demo', `--root=${root}`]);
      assert.equal(bad.code, 2);
      assert.match(bad.stderr, /not a game id/);
    });
  }
});
