// A release's tag push must not run CI again: the push to main just ran it on the same commit, and
// GitHub ignores `paths` on a new tag, so every workflow would run twice. A `branches` filter is
// what leaves tags out.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const dir = path.join(root, '.github/workflows');
const names = fs.readdirSync(dir).filter((n) => n.endsWith('.yml'));

test('there are workflows to check', () => {
  assert.ok(names.length > 0);
});

for (const name of names) {
  const text = fs.readFileSync(path.join(dir, name), 'utf8');

  test(`${name}: a push runs on main only, never on a tag or a stray branch`, () => {
    if (/^ {2}push:/m.test(text)) assert.match(text, /^ {2}push:\n {4}branches: \[main\]/m);
    else assert.match(text, /^ {2}pull_request:/m, 'a workflow with no push runs on pull requests');
  });

  // A public repository takes pull requests from forks, so nothing here may reach a write token or
  // a secret from their code.
  test(`${name}: read-only token, and no way for a fork to reach a secret`, () => {
    assert.match(text, /^permissions:\n {2}contents: read$/m);
    assert.doesNotMatch(text, /pull_request_target|workflow_run|secrets\./);
  });
}
