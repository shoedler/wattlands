class_name SiegeScore
extends RefCounted
## Score, grade and XP (brief 2.8). Pure.
##
## Score (waves 1..N, the warm-up excluded) = gate + breaches + earnings:
##   gate      40 x mean(gate HP / max at each wave end) (no wave ended yet: the gate now)
##   breaches  max(0, 30 - 15 x breaches)
##   earnings  30 x min(1, team gold earned / par), par = 0.75 x the team's planned P_eff in
##             kJ from the warm-up to the last wave (SiegeState.planned_kj)
## Grades: S >= 90, A >= 78, B >= 64, C >= 48, otherwise D (balance.json score.grades).
## XP = round(kJ / 10) + the grade bonus (S 60, A 40, B 25, C 10, D 0).


## {"score", "grade", "gate", "breaches", "earnings", "par"} for `state`.
static func compute(state: SiegeState) -> Dictionary:
	var c := state.content
	var fracs: Array[float] = state.wave_gate_frac
	var mean := state.gate_hp / maxf(state.gate_max, 1.0)
	if not fracs.is_empty():
		mean = 0.0
		for f in fracs:
			mean += f
		mean /= fracs.size()
	var gate := c.num("score.gate_pts", 40.0) * mean
	var br := maxf(
		0.0, c.num("score.breach_pts", 30.0) - c.num("score.breach_cost", 15.0) * state.breaches
	)
	var par := c.num("score.par_frac", 0.75) * state.planned_kj
	var earn := (
		c.num("score.earn_pts", 30.0) * (minf(1.0, state.team_earned / par) if par > 0.0 else 0.0)
	)
	var score := gate + br + earn
	return {
		"score": score,
		"grade": grade(c, score),
		"gate": gate,
		"breaches": br,
		"earnings": earn,
		"par": par
	}


## The Strava title tag (GameResults.ride_tag): "<mission> - won" when the gate stood all shift
## (no breach, the "stands" result), "<mission> - lost" when it fell. The mission is the shift.
static func ride_tag(state: SiegeState, content_id: String, strings: GameStrings) -> String:
	var key := "SIEGE_MISSION_" + content_id.to_upper()
	var mission := strings.t(key) if strings.has(key) else content_id
	return strings.t("SIEGE_RIDE_LOST" if state.breaches > 0 else "SIEGE_RIDE_WON", [mission])


## The Strava description lines (GameResults.ride_lines): score and grade, breaches, engines
## stopped and the team's kills.
static func ride_lines(state: SiegeState, res: GameResults, strings: GameStrings) -> Array[String]:
	var kills := 0
	for row in res.rows:
		kills += int((row.get("stats", {}) as Dictionary).get("SIEGE_STAT_KILLS", 0))
	return [
		strings.t("SIEGE_RIDE_SCORE", [roundi(res.score), res.grade]),
		strings.t("SIEGE_RIDE_BREACHES", [state.breaches]),
		strings.t("SIEGE_RIDE_ENGINES", [state.engines_stopped, state.engines_total]),
		strings.t("SIEGE_RIDE_KILLS", [kills]),
	]


## The grade for `score` (band edges inclusive: 90 is S, 89.99 is A).
static func grade(c: SiegeContent, score: float) -> String:
	for g: String in ["S", "A", "B", "C"]:
		if score >= c.num("score.grades." + g, 0.0) - 1e-9:
			return g
	return "D"


## Session XP for a rider who rode `kj` with the team grade `g`.
static func xp(c: SiegeContent, kj: float, g: String) -> int:
	return roundi(kj / c.num("xp.kj_per_xp", 10.0)) + int(c.num("xp.grade_bonus." + g, 0.0))
