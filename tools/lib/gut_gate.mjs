// tools/lib/gut_gate.mjs: the BRIEF 7 pass rule for a GUT run, shared by tools/run_tests and its tests.
// Zero dependencies.
//
// A GUT run passes only if: the exit code is 0, the log contains "Run Summary", the JUnit file's
// test count is above 0 and at least the required count (the previous green count, or --min-count),
// and the log contains none of FORBIDDEN.

import fs from 'node:fs';

export const FORBIDDEN = ['SCRIPT ERROR', 'Parse Error', 'Debugger Break', 'Ignoring script', 'Nothing was run'];
export const SUMMARY_MARKER = 'Run Summary';

function attr(tag, name) {
  const m = new RegExp(`\\b${name}="(\\d+)"`).exec(tag);
  return m ? Number(m[1]) : null;
}

/** Test counts from a JUnit XML string: {tests, failures} or null when it holds no count. */
export function junitCounts(xml) {
  if (typeof xml !== 'string' || xml.trim() === '') return null;
  const root = /<testsuites\b[^>]*>/.exec(xml);
  if (root) {
    const tests = attr(root[0], 'tests');
    if (tests !== null) return { tests, failures: attr(root[0], 'failures') ?? 0 };
  }
  const suites = [...xml.matchAll(/<testsuite\b[^>]*>/g)];
  if (suites.length > 0 && suites.every((s) => attr(s[0], 'tests') !== null)) {
    return {
      tests: suites.reduce((sum, s) => sum + attr(s[0], 'tests'), 0),
      failures: suites.reduce((sum, s) => sum + (attr(s[0], 'failures') ?? 0), 0),
    };
  }
  const cases = (xml.match(/<testcase\b/g) || []).length;
  if (cases > 0 || /<testsuites?\b/.test(xml)) return { tests: cases, failures: (xml.match(/<failure\b/g) || []).length };
  return null;
}

/**
 * Applies the gate. `previousGreen` is the stored green count (null if none); `minCount`, when set,
 * replaces it as the required count; a `narrow` run (a subset of tests) only needs a count above 0.
 * Returns {pass, tests, failures, required, reasons}.
 */
export function evaluateGut({ exitCode, log, junitXml, previousGreen = null, minCount = null, narrow = false }) {
  const reasons = [];
  const counts = junitCounts(junitXml);
  const tests = counts ? counts.tests : 0;
  let required = 1;
  if (minCount !== null && minCount !== undefined) required = Math.max(1, minCount);
  else if (!narrow && previousGreen) required = Math.max(1, previousGreen);

  if (exitCode !== 0) reasons.push(`GUT exit code ${exitCode}`);
  const text = typeof log === 'string' ? log : '';
  if (!text.includes(SUMMARY_MARKER)) reasons.push(`log has no "${SUMMARY_MARKER}"`);
  if (!counts) reasons.push('no JUnit test count (missing or empty JUnit file)');
  else if (tests <= 0) reasons.push('JUnit reports 0 tests');
  else if (tests < required) reasons.push(`JUnit reports ${tests} tests, fewer than the required ${required}`);
  for (const bad of FORBIDDEN) {
    if (text.includes(bad)) reasons.push(`log contains "${bad}"`);
  }
  return { pass: reasons.length === 0, tests, failures: counts ? counts.failures : null, required, reasons };
}

export function readGreenCount(file) {
  try {
    const n = Number.parseInt(fs.readFileSync(file, 'utf8').trim(), 10);
    return Number.isInteger(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

export function writeGreenCount(file, n) {
  fs.writeFileSync(file, `${n}\n`);
}
