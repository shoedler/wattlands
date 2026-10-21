// Tests for tools/lib/gut_gate.mjs: BRIEF 7's pass rule for a GUT run.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { junitCounts, evaluateGut, FORBIDDEN } from '../lib/gut_gate.mjs';

const GUT_XML = (n, failures = 0) =>
  `<?xml version="1.0" encoding="UTF-8"?>\n<testsuites name="GutTests" failures="${failures}" tests="${n}">\n` +
  `  <testsuite name="res://tests/unit/test_a.gd" tests="${n}" failures="${failures}" skipped="0" time="0.01">\n` +
  `  </testsuite>\n</testsuites>\n`;
const GREEN_LOG = 'GUT 9.7.1\n...\n==============================================\n= Run Summary\n==============================================\nAll tests passed!\n';

describe('junitCounts', () => {
  test('reads the GUT root element', () => {
    assert.deepEqual(junitCounts(GUT_XML(42, 1)), { tests: 42, failures: 1, skipped: 0 });
  });
  test('sums testsuite counts when the root has none', () => {
    const xml = '<testsuites><testsuite tests="3" failures="1"></testsuite><testsuite tests="4"></testsuite></testsuites>';
    assert.deepEqual(junitCounts(xml), { tests: 7, failures: 1, skipped: 0 });
  });
  test('counts skipped (pending) tests from the root or the testcases', () => {
    assert.equal(junitCounts('<testsuites tests="3" failures="0" skipped="1"></testsuites>').skipped, 1);
    const cases = '<testsuites tests="2" failures="0"><testsuite tests="2"><testcase name="a"><skipped/></testcase><testcase name="b"/></testsuite></testsuites>';
    assert.equal(junitCounts(cases).skipped, 1);
  });
  test('counts testcases as a last resort', () => {
    const xml = '<testsuite name="x"><testcase name="a"/><testcase name="b"><failure/></testcase></testsuite>';
    assert.deepEqual(junitCounts(xml), { tests: 2, failures: 1 });
  });
  test('returns null for a missing or empty file', () => {
    assert.equal(junitCounts(''), null);
    assert.equal(junitCounts(undefined), null);
    assert.equal(junitCounts('garbage'), null);
  });
});

describe('evaluateGut', () => {
  const green = { exitCode: 0, log: GREEN_LOG, junitXml: GUT_XML(10) };

  test('passes a clean run', () => {
    const v = evaluateGut(green);
    assert.equal(v.pass, true, v.reasons.join('; '));
    assert.equal(v.tests, 10);
  });

  test('fails a non-zero exit code', () => {
    assert.equal(evaluateGut({ ...green, exitCode: 1 }).pass, false);
  });

  test('fails pending or risky tests (W3 QT-3) unless allowed', () => {
    const log = `${GREEN_LOG}\n\x1b[33mRisky/Pending        2\x1b[0m\n`;
    const v = evaluateGut({ ...green, log });
    assert.equal(v.pass, false);
    assert.equal(v.pending, 2);
    assert.match(v.reasons.join('; '), /pending or risky/);
    const skipped = evaluateGut({ ...green, junitXml: '<testsuites tests="10" failures="0" skipped="1"></testsuites>' });
    assert.equal(skipped.pass, false);
    assert.equal(evaluateGut({ ...green, log, allowPending: true }).pass, true);
  });

  test('allowlisted environment guards may stay pending; others still fail', () => {
    const xml = '<testsuites tests="3" failures="0" skipped="2">'
      + '<testsuite name="tests/ble/test_gdble_surface.gd" tests="2" skipped="1">'
      + '<testcase name="test_methods" status="pending" classname="tests/ble/test_gdble_surface.gd"><skipped/></testcase>'
      + '<testcase name="test_ok" status="pass" classname="tests/ble/test_gdble_surface.gd"></testcase></testsuite>'
      + '<testsuite name="tests/x/test_y.gd" tests="1" skipped="1">'
      + '<testcase name="test_guarded" status="pending" classname="tests/x/test_y.gd"><skipped/></testcase></testsuite></testsuites>';
    const log = `${GREEN_LOG}\nRisky/Pending        2\n`;
    const onlyFile = evaluateGut({ ...green, log, junitXml: xml, pendingAllowlist: ['tests/ble/test_gdble_surface.gd'] });
    assert.equal(onlyFile.pass, false, 'the second pending test is not excused');
    assert.match(onlyFile.reasons.join('; '), /tests\/x\/test_y\.gd::test_guarded/);
    const both = evaluateGut({ ...green, log, junitXml: xml,
      pendingAllowlist: ['tests/ble/test_gdble_surface.gd', 'tests/x/test_y.gd::test_guarded'] });
    assert.equal(both.pass, true, both.reasons.join('; '));
    assert.equal(both.excused, 2);
  });

  test('fails without "Run Summary"', () => {
    const v = evaluateGut({ ...green, log: 'crashed early' });
    assert.equal(v.pass, false);
    assert.match(v.reasons.join(), /Run Summary/);
  });

  test('fails with 0 tests or no JUnit file', () => {
    assert.equal(evaluateGut({ ...green, junitXml: GUT_XML(0) }).pass, false);
    assert.equal(evaluateGut({ ...green, junitXml: '' }).pass, false);
  });

  test('fails below the previous green count; --min-count overrides it', () => {
    assert.equal(evaluateGut({ ...green, previousGreen: 11 }).pass, false);
    assert.equal(evaluateGut({ ...green, previousGreen: 10 }).pass, true);
    assert.equal(evaluateGut({ ...green, previousGreen: 11, minCount: 9 }).pass, true);
    assert.equal(evaluateGut({ ...green, previousGreen: 5, minCount: 12 }).pass, false);
  });

  test('a narrow run ignores the previous green count but still needs tests', () => {
    assert.equal(evaluateGut({ ...green, junitXml: GUT_XML(2), previousGreen: 10, narrow: true }).pass, true);
    assert.equal(evaluateGut({ ...green, junitXml: GUT_XML(0), narrow: true }).pass, false);
  });

  for (const bad of FORBIDDEN) {
    test(`fails when the log contains "${bad}"`, () => {
      const v = evaluateGut({ ...green, log: `${GREEN_LOG}\n${bad}: something\n` });
      assert.equal(v.pass, false);
      assert.match(v.reasons.join(), new RegExp(bad));
    });
  }

  test('the forbidden list is exactly BRIEF 7\'s', () => {
    assert.deepEqual(FORBIDDEN, ['SCRIPT ERROR', 'Parse Error', 'Debugger Break', 'Ignoring script', 'Nothing was run']);
  });
});
