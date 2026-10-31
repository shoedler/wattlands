import assert from 'node:assert/strict';
import { test } from 'node:test';
import { importParamMismatches, importParams, importSkeleton, readImportParams, updateImportParams } from '../lib/import_file.mjs';

const GODOT_FILLED = `[remap]

importer="wav"
type="AudioStreamWAV"
uid="uid://abc123"
path="res://.godot/imported/x.wav-1.sample"

[deps]

source_file="res://assets/tank/audio/x.wav"
dest_files=["res://.godot/imported/x.wav-1.sample"]

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=1
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
`;

test('importParams: the spec\'s modes, trim always off', () => {
  const pcm = importParams({ loop: false, compress: 'pcm' });
  assert.equal(pcm['edit/loop_mode'], 1);
  assert.equal(pcm['compress/mode'], 0);
  assert.equal(pcm['edit/trim'], false);
  assert.equal(pcm['edit/normalize'], false);
  const qoa = importParams({ loop: true, compress: 'qoa' });
  assert.equal(qoa['edit/loop_mode'], 2);
  assert.equal(qoa['compress/mode'], 2);
  assert.equal(qoa['edit/loop_end'], -1, 'frames - 1 to Godot: the guard frame stays out of the period');
  assert.throws(() => importParams({ compress: 'vorbis' }), /unknown compress/);
});

test('the skeleton names its source and importer', () => {
  const text = importSkeleton('res://assets/tank/audio/x.wav', importParams({ loop: true }));
  assert.match(text, /^\[remap\]\n\nimporter="wav"\ntype="AudioStreamWAV"\n/);
  assert.match(text, /source_file="res:\/\/assets\/tank\/audio\/x\.wav"/);
  assert.equal(readImportParams(text)['edit/loop_mode'], '2');
  assert.ok(!text.includes('uid='), 'Godot makes the uid');
});

test('updateImportParams changes params only: uid, path and dest_files stay', () => {
  const out = updateImportParams(GODOT_FILLED, importParams({ loop: true, compress: 'qoa' }));
  assert.match(out, /uid="uid:\/\/abc123"/);
  assert.match(out, /path="res:\/\/\.godot\/imported\/x\.wav-1\.sample"/);
  assert.match(out, /dest_files=\["res:\/\/\.godot\/imported\/x\.wav-1\.sample"\]/);
  assert.match(out, /edit\/loop_mode=2/);
  assert.match(out, /compress\/mode=2/);
  assert.equal(out.split('\n').length, GODOT_FILLED.split('\n').length);
});

test('updateImportParams leaves a file alone when nothing changes, and adds a missing key', () => {
  const same = updateImportParams(GODOT_FILLED, importParams({ loop: false, compress: 'pcm' }));
  assert.equal(same, GODOT_FILLED);
  const added = updateImportParams(GODOT_FILLED, { 'edit/new_thing': 3 });
  assert.equal(readImportParams(added)['edit/new_thing'], '3');
  assert.throws(() => updateImportParams('[remap]\n', { a: 1 }), /no \[params\]/);
});

test('importParamMismatches names what differs', () => {
  assert.deepEqual(importParamMismatches(GODOT_FILLED, importParams({ loop: false, compress: 'pcm' })), []);
  const bad = importParamMismatches(GODOT_FILLED, importParams({ loop: true, compress: 'pcm' }));
  assert.deepEqual(bad, ['edit/loop_mode: 1 != 2']);
});
