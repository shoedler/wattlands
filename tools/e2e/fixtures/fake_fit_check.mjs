#!/usr/bin/env node
// A stand-in for tools/fit_check/check.mjs: a file is valid when it starts with "FAKEFIT".
import fs from 'node:fs';

const files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const out = { ok: true, files: [] };
for (const f of files) {
  let errors = [];
  try {
    if (!fs.readFileSync(f, 'utf8').startsWith('FAKEFIT')) errors = ['not a FIT file'];
  } catch (e) {
    errors = [e.code];
  }
  if (errors.length) out.ok = false;
  out.files.push({ path: f, ok: errors.length === 0, errors });
}
process.stdout.write(`${JSON.stringify(out)}\n`);
process.exit(out.ok ? 0 : 1);
