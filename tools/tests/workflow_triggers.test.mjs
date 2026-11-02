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
  test(`${name}: a push runs on branches only, never on a tag`, () => {
    assert.match(fs.readFileSync(path.join(dir, name), 'utf8'), /^ {2}push:\n {4}branches: /m);
  });
}
