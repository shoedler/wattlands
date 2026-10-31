// The result helpers the games' tests/games/<id>/sim/check_sims.mjs share. tools/lib/safety_pins.json
// pins both functions here: tools/gate check follows each game's import to this file.

export function result(id, title, problems, extra = '') {
  const ok = problems.length === 0;
  return { id, status: ok ? 'PASS' : 'FAIL', summary: `${title}${extra ? `: ${extra}` : ''}`, details: problems };
}

/** [[name, report]] for `names`; `missing` lists the names not present. */
export function pick(reports, names) {
  const found = [];
  const missing = [];
  for (const n of names) (reports[n] ? found : missing).push(n);
  return { found: found.map((n) => [n, reports[n]]), missing };
}
