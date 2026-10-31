// Tests for tools/lib/sim_report.mjs, the helpers the games' check_sims.mjs import. No Godot.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { pick, result } from '../lib/sim_report.mjs';

describe('result', () => {
  test('no problems is a PASS, with the extra after the title', () => {
    assert.deepEqual(result('S1', 'crews finish', [], '3 runs'), {
      id: 'S1',
      status: 'PASS',
      summary: 'crews finish: 3 runs',
      details: [],
    });
  });

  test('any problem is a FAIL and the problems are the details', () => {
    const r = result('S2', 'zero riders', ['s2: no end reason']);
    assert.equal(r.status, 'FAIL');
    assert.equal(r.summary, 'zero riders');
    assert.deepEqual(r.details, ['s2: no end reason']);
  });
});

describe('pick', () => {
  const a = { name: 'a' };
  const b = { name: 'b' };

  test('splits the names into found pairs and missing names, in the order asked', () => {
    assert.deepEqual(pick({ a, b }, ['b', 'gone', 'a']), { found: [['b', b], ['a', a]], missing: ['gone'] });
  });

  test('no names finds nothing, and no reports leaves every name missing', () => {
    assert.deepEqual(pick({ a }, []), { found: [], missing: [] });
    assert.deepEqual(pick({}, ['a']), { found: [], missing: ['a'] });
  });
});
