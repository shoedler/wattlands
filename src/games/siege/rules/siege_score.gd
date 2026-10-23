class_name SiegeScore
extends RefCounted
## Score, grade and XP (brief 2.8). Owner: B1 "rules". Pure.
##
## Score (waves 1..N, the warm-up excluded) = gate + breaches + earnings:
##   gate      40 x mean(gate HP / max at each wave end) (no wave ended yet: the gate now)
##   breaches  max(0, 30 - 15 x breaches)
##   earnings  30 x min(1, team denarii earned / par), par = 0.75 x the team's planned P_eff in
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


## The grade for `score` (band edges inclusive: 90 is S, 89.99 is A).
static func grade(c: SiegeContent, score: float) -> String:
	for g: String in ["S", "A", "B", "C"]:
		if score >= c.num("score.grades." + g, 0.0) - 1e-9:
			return g
	return "D"


## Session XP for a rider who rode `kj` with the team grade `g`.
static func xp(c: SiegeContent, kj: float, g: String) -> int:
	return roundi(kj / c.num("xp.kj_per_xp", 10.0)) + int(c.num("xp.grade_bonus." + g, 0.0))
