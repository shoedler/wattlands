// Tests for tools/qa/verify_move.mjs: the block parser, then the CLI on a temp git repo. No Godot.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { TOOLS } from './helpers.mjs';
import { diffCount, parseBlocks, verify } from '../qa/verify_move.mjs';

const SCRIPT = path.join(TOOLS, 'qa', 'verify_move.mjs');

const OLD = `class_name Old
extends RefCounted
## The file's doc, loose.

# --- Palette ---
## The ink.
const INK := Color("#112233")
const RAMP := [
	1,
	2,
]
static var _key: int = 0
@onready var label: Label = null


# --- Work ---
signal done(a: int)

enum Mode { A, B }


## Paints.
static func paint(
	img: Image, kind: String
) -> void:
	var x := 1
# a comment at column zero inside the body
	x += 1

	img.fill(Color.RED)


@rpc("any_peer")
func ping() -> void:
	pass


class Cv:
	extends RefCounted
	var w: int = 0

	func size() -> int:
		return w
`;

const split = () => [
  {
    path: 'a.gd',
    text: `class_name A
extends RefCounted

# --- Palette ---
## The ink.
const INK := Color("#112233")
const RAMP := [
	1,
	2,
]
static var _key: int = 0
@onready var label: Label = null
`,
  },
  {
    path: 'b.gd',
    text: `class_name B
extends A
## The file's doc, loose.

signal done(a: int)

enum Mode { A, B }


## Paints.
static func paint(
	img: Image, kind: String
) -> void:
	var x := 1
# a comment at column zero inside the body
	x += 1

	img.fill(Color.RED)


@rpc("any_peer")
func ping() -> void:
	pass


class Cv:
	extends RefCounted
	var w: int = 0

	func size() -> int:
		return w
`,
  },
];

describe('parseBlocks', () => {
  const { blocks, loose } = parseBlocks(OLD);
  const byName = Object.fromEntries(blocks.map((b) => [b.name, b]));

  test('finds every kind of block and no class_name, extends or header', () => {
    assert.deepEqual(blocks.map((b) => `${b.kind} ${b.name}`), [
      'const INK',
      'const RAMP',
      'static var _key',
      'var label',
      'signal done',
      'enum Mode',
      'static func paint',
      'func ping',
      'class Cv',
    ]);
  });

  test('a block holds its comments, annotations, signature and whole body, without trailing blanks', () => {
    assert.ok(byName.INK.text.startsWith('## The ink.\nconst INK'));
    assert.ok(byName.RAMP.text.endsWith('\t2,\n]'));
    assert.ok(byName.ping.text.startsWith('@rpc("any_peer")\nfunc ping'));
    assert.ok(byName.paint.text.startsWith('## Paints.\nstatic func paint(\n'));
    assert.ok(byName.paint.text.includes(') -> void:'));
    assert.ok(byName.paint.text.includes('# a comment at column zero inside the body'));
    assert.ok(byName.paint.text.endsWith('img.fill(Color.RED)'));
    assert.ok(byName.Cv.text.endsWith('return w'));
  });

  test('only a comment attached to nothing is loose, and headers are ignored', () => {
    assert.deepEqual(loose, ["## The file's doc, loose."]);
  });

  test('a triple-quoted string with column-zero text stays inside its block', () => {
    const { blocks: b } = parseBlocks('const S := """\nraw\n"""\nconst T := 1\n');
    assert.deepEqual(b.map((x) => x.name), ['S', 'T']);
    assert.equal(b[0].text, 'const S := """\nraw\n"""');
  });
});

describe('verify', () => {
  test('a clean split passes', () => {
    const r = verify(OLD, split());
    assert.deepEqual(r.errors, []);
    assert.deepEqual(r.droppedComments, []);
    assert.deepEqual(r.extra, []);
    assert.equal(r.ok, true);
  });

  test('CRLF on either side changes nothing', () => {
    const r = verify(OLD.replaceAll('\n', '\r\n'), split().map((t) => ({ ...t, text: t.text.replaceAll('\n', '\r\n') })));
    assert.equal(r.ok, true);
  });

  test('a changed character fails and names the block', () => {
    const t = split();
    t[1].text = t[1].text.replace('x += 1', 'x += 2');
    const r = verify(OLD, t);
    assert.equal(r.ok, false);
    assert.match(r.errors.join('\n'), /static func paint: changed, -1 \+1 lines in b\.gd/);
  });

  test('a changed attached comment fails', () => {
    const t = split();
    t[0].text = t[0].text.replace('## The ink.', '## The ink!');
    assert.match(verify(OLD, t).errors.join('\n'), /const INK: changed/);
  });

  test('a dropped func fails', () => {
    const t = split();
    t[1].text = t[1].text.replace('@rpc("any_peer")\nfunc ping() -> void:\n\tpass\n', '');
    assert.match(verify(OLD, t).errors.join('\n'), /func ping: dropped/);
  });

  test('a block in two targets fails', () => {
    const t = split();
    t[0].text += '\n\nconst EXTRA := 1\n';
    t[1].text = `${t[1].text}\n\n## The ink.\nconst INK := Color("#112233")\n`;
    const r = verify(OLD, t);
    assert.match(r.errors.join('\n'), /const INK: occurs 2 times/);
  });

  test('an allowed func may differ, and prints its diff count', () => {
    const t = split();
    t[1].text = t[1].text.replace('x += 1', 'x += 2');
    const r = verify(OLD, t, ['paint']);
    assert.equal(r.ok, true);
    assert.deepEqual(r.allowed, ['static func paint: allowed, -1 +1 lines in b.gd']);
  });

  test('an allowed func must still exist', () => {
    const t = split();
    t[1].text = t[1].text.replace('@rpc("any_peer")\nfunc ping() -> void:\n\tpass\n', '');
    assert.equal(verify(OLD, t, ['ping']).ok, false);
  });

  test('new blocks and dropped loose comments are reported but do not fail', () => {
    const t = split();
    t[0].text += '\n\nfunc helper() -> void:\n\tpass\n';
    t[1].text = t[1].text.replace("## The file's doc, loose.\n", '');
    const r = verify(OLD, t);
    assert.equal(r.ok, true);
    assert.deepEqual(r.extra, ['func helper in a.gd']);
    assert.deepEqual(r.droppedComments, ["## The file's doc, loose."]);
  });
});

test('diffCount counts lines, not positions', () => {
  assert.deepEqual(diffCount('a\nb\nb', 'b\nc\nd'), { removed: 2, added: 2 });
});

describe('the command line, on a temp git repo', () => {
  const git = (cwd, ...args) => {
    const r = spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...args], { cwd, encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    return r.stdout.trim();
  };
  const cli = (cwd, ...args) => spawnSync(process.execPath, [SCRIPT, ...args], { cwd, encoding: 'utf8' });
  const repo = () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'verify_move-'));
    git(dir, 'init', '-q');
    fs.writeFileSync(path.join(dir, 'old.gd'), OLD);
    git(dir, 'add', '.');
    git(dir, 'commit', '-q', '-m', 'base');
    const base = git(dir, 'rev-parse', 'HEAD');
    for (const t of split()) fs.writeFileSync(path.join(dir, t.path), t.text);
    return { dir, base };
  };

  test('a good move exits 0', (t) => {
    const { dir, base } = repo();
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const r = cli(dir, `--base=${base}`, '--from=old.gd', '--to=a.gd,b.gd');
    assert.equal(r.status, 0, r.stdout + r.stderr);
    assert.match(r.stdout, /verify_move: ok/);
  });

  test('one changed character exits 1, and --allow lets it through', (t) => {
    const { dir, base } = repo();
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const b = path.join(dir, 'b.gd');
    fs.writeFileSync(b, fs.readFileSync(b, 'utf8').replace('Color.RED', 'Color.BLUE'));
    const r = cli(dir, `--base=${base}`, '--from=old.gd', '--to=a.gd,b.gd');
    assert.equal(r.status, 1);
    assert.match(r.stdout, /FAIL static func paint: changed/);
    assert.equal(cli(dir, `--base=${base}`, '--from=old.gd', '--to=a.gd,b.gd', '--allow=paint').status, 0);
  });

  test('a dropped func exits 1', (t) => {
    const { dir, base } = repo();
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const b = path.join(dir, 'b.gd');
    fs.writeFileSync(b, fs.readFileSync(b, 'utf8').replace('@rpc("any_peer")\nfunc ping() -> void:\n\tpass\n', ''));
    const r = cli(dir, `--base=${base}`, '--from=old.gd', '--to=a.gd,b.gd');
    assert.equal(r.status, 1);
    assert.match(r.stdout, /FAIL func ping: dropped/);
  });

  test('bad flags, an unknown rev and a missing target exit 2', (t) => {
    const { dir, base } = repo();
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    assert.equal(cli(dir, '--from=old.gd').status, 2);
    assert.equal(cli(dir, '--base=nope', '--from=old.gd', '--to=a.gd').status, 2);
    assert.equal(cli(dir, `--base=${base}`, '--from=old.gd', '--to=nope.gd').status, 2);
  });
});
