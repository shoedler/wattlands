// Tests for tools/env.sh and tools/env.ps1 (BRIEF 1): both locks are set, and the art pipeline's
// variables come through untouched. Values are compared inside the child shell and only a verdict is
// printed, so no key value ever reaches the test output.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { TOOLS, IS_WIN, BASH, minimalEnv, runProc, powershellExe } from './helpers.mjs';

const ENV_SH = path.join(TOOLS, 'env.sh');
const ENV_PS1 = path.join(TOOLS, 'env.ps1');
const ART = { FAL_KEY: 'dummy-key-123', WATTLANDS_ALLOW_ART: 'dummy-allow' };
const ART_NAMES = /\b(FAL_KEY|WATTLANDS_ALLOW_ART)\b/;

const BASH_CHECK = `
  [ "\${WATTLANDS_NO_HW_CONTROL-}" = 1 ] && echo HW_OK
  [ "\${WATTLANDS_NO_NETWORK_INTEGRATIONS-}" = 1 ] && echo NET_OK
  [ "\${FAL_KEY-}" = dummy-key-123 ] && echo FAL_SAME
  [ "\${WATTLANDS_ALLOW_ART-}" = dummy-allow ] && echo ART_SAME
  [ -z "\${FAL_KEY+x}" ] && echo FAL_UNSET
  [ -z "\${WATTLANDS_ALLOW_ART+x}" ] && echo ART_UNSET
  true`;

const PS_CHECK = [
  "if ($env:WATTLANDS_NO_HW_CONTROL -eq '1') { 'HW_OK' }",
  "if ($env:WATTLANDS_NO_NETWORK_INTEGRATIONS -eq '1') { 'NET_OK' }",
  "if ($env:FAL_KEY -ceq 'dummy-key-123') { 'FAL_SAME' }",
  "if ($env:WATTLANDS_ALLOW_ART -ceq 'dummy-allow') { 'ART_SAME' }",
  "if ($null -eq $env:FAL_KEY) { 'FAL_UNSET' }",
  "if ($null -eq $env:WATTLANDS_ALLOW_ART) { 'ART_UNSET' }",
].join('; ');

const verdicts = (stdout) => new Set(stdout.split(/\r?\n/).map((s) => s.trim()).filter(Boolean));

describe('tools/env.sh', { skip: !BASH && 'bash not found' }, () => {
  const source = (env, prefix = '') =>
    runProc(BASH, ['-c', `${prefix}. "$1"\n${BASH_CHECK}`, 'env-test', ENV_SH.replaceAll('\\', '/')], { env });

  test('sets both locks and passes dummy art variables through unchanged', async () => {
    const r = await source(minimalEnv(ART));
    assert.equal(r.code, 0, r.stderr);
    const v = verdicts(r.stdout);
    for (const want of ['HW_OK', 'NET_OK', 'FAL_SAME', 'ART_SAME']) assert.ok(v.has(want), `${want} in ${[...v]}`);
    assert.equal(r.stderr, '', 'sourcing prints nothing');
  });

  test('leaves unset art variables unset', async () => {
    const v = verdicts((await source(minimalEnv())).stdout);
    assert.ok(v.has('FAL_UNSET') && v.has('ART_UNSET') && v.has('HW_OK') && v.has('NET_OK'), [...v].join(' '));
  });

  test('works in a "set -eu" shell and overrides a dropped lock', async () => {
    const r = await source(minimalEnv({ WATTLANDS_NO_HW_CONTROL: '0' }), 'set -eu\n');
    assert.equal(r.code, 0, r.stderr);
    assert.ok(verdicts(r.stdout).has('HW_OK'));
  });

  test('running it instead of sourcing it is harmless and says so', async () => {
    const r = await runProc(BASH, [ENV_SH.replaceAll('\\', '/')], { env: minimalEnv() });
    assert.equal(r.code, 0);
    assert.match(r.stderr, /source this file/);
  });
});

describe('tools/env.ps1', { skip: !IS_WIN && 'Windows PowerShell 5.1 only' }, () => {
  const dotSource = (env) =>
    runProc(powershellExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', `. '${ENV_PS1.replaceAll("'", "''")}'; ${PS_CHECK}`], { env });

  test('sets both locks and passes dummy art variables through unchanged', async () => {
    const r = await dotSource(minimalEnv(ART));
    assert.equal(r.code, 0, r.stderr);
    const v = verdicts(r.stdout);
    for (const want of ['HW_OK', 'NET_OK', 'FAL_SAME', 'ART_SAME']) assert.ok(v.has(want), `${want} in ${[...v]}`);
  });

  test('leaves unset art variables unset', async () => {
    const v = verdicts((await dotSource(minimalEnv())).stdout);
    assert.ok(v.has('FAL_UNSET') && v.has('ART_UNSET') && v.has('HW_OK') && v.has('NET_OK'), [...v].join(' '));
  });
});

// The env scripts and the Godot wrappers never name the art variables outside comments (BRIEF 1:
// they never set, unset or print them). tools/run_tests is different on purpose: it removes both
// for its own process tree (docs/OWNERSHIP.md TL5), tested in run_tests.test.mjs.
function stripComments(text, kind) {
  let t = text;
  if (kind === 'ps') t = t.replace(/<#[\s\S]*?#>/g, '');
  if (kind === 'js') t = t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  if (kind === 'sh' || kind === 'ps' || kind === 'gd') t = t.replace(/(^|\s)#.*$/gm, '$1');
  return t;
}

describe('art variables are never named in code', () => {
  const files = [
    ['env.sh', 'sh'],
    ['env.ps1', 'ps'],
    ['godot.sh', 'sh'],
    ['godot.ps1', 'ps'],
    ['lib/godot_lock.mjs', 'js'],
    ['lib/wrapper_common.ps1', 'ps'],
    ['check_scripts.gd', 'gd'],
  ];
  for (const [rel, kind] of files) {
    test(rel, () => {
      const code = stripComments(fs.readFileSync(path.join(TOOLS, rel), 'utf8'), kind);
      assert.doesNotMatch(code, ART_NAMES);
    });
  }

  test('the comment stripper still sees code', () => {
    assert.match(stripComments('export FAL_KEY=x # note', 'sh'), ART_NAMES);
    assert.doesNotMatch(stripComments('# FAL_KEY is Simon\'s\nexport A=1', 'sh'), ART_NAMES);
    assert.match(stripComments('$env:WATTLANDS_ALLOW_ART = 1 <# x #>', 'ps'), ART_NAMES);
  });
});
