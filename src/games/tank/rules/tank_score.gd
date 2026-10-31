class_name TankScore
extends RefCounted
## Score, grade, XP and unlocks (brief 2.8), from TankState and scoring.json / cosmetics.json.
## Owner: rules (G0 wrote the formulas; rules keeps them and adds the tests).
##
## Score = scale x (w_band x band + w_acc x accuracy + w_obj x objectives + w_surv x survival):
##   band       crew mean of each rider's WORK time in band / WORK time (0 with no WORK time)
##   accuracy   main-gun hits / shots, 0 when no shot was fired
##   objectives stage_frac x stages completed without overrun / stages + boss_frac if the
##              Behemoth died (stages: the mission's score_stages, default scoring.json's)
##   survival   max(0, 1 - survival_per_breakdown x breakdowns - survival_per_loss x losses)
## Grades: S >= 900, A >= 800, B >= 650, C >= 500, else D; any loss caps it at loss_grade_cap (A).
## XP = round(kJ / 10) + grade bonus.


## {score, grade, band, accuracy, objectives, survival} for the crew.
static func summary(state: TankState) -> Dictionary:
	var c := state.content
	var band := 0.0
	var n := 0
	for r in state.riders:
		band += r.band_s / r.work_s if r.work_s > 0.0 else 0.0
		n += 1
	band = band / n if n > 0 else 0.0
	var sc := state.score
	var accuracy: float = float(sc.hits) / sc.shots if sc.shots > 0 else 0.0
	var stages := float(c.mission().get("score_stages", c.num("scoring", "objectives.stages", 3.0)))
	var objectives := (
		c.num("scoring", "objectives.stage_frac", 0.6) * minf(sc.stages_clean, stages) / stages
		+ (c.num("scoring", "objectives.boss_frac", 0.4) if sc.behemoth_killed else 0.0)
	)
	var survival := maxf(
		0.0,
		(
			1.0
			- c.num("scoring", "survival_per_breakdown", 0.25) * sc.breakdowns
			- c.num("scoring", "survival_per_loss", 0.35) * sc.losses
		)
	)
	var score := (
		c.num("scoring", "scale", 1000.0)
		* (
			c.num("scoring", "weights.band", 0.3) * band
			+ c.num("scoring", "weights.accuracy", 0.2) * accuracy
			+ c.num("scoring", "weights.objectives", 0.3) * objectives
			+ c.num("scoring", "weights.survival", 0.2) * survival
		)
	)
	return {
		"score": score,
		"grade": _capped(c, grade_of(c, score), sc.losses),
		"band": band,
		"accuracy": accuracy,
		"objectives": objectives,
		"survival": survival,
	}


static func grade_of(c: TankContent, score: float) -> String:
	for g: String in ["S", "A", "B", "C"]:
		if score >= c.num("scoring", "grades.%s" % g, INF):
			return g
	return "D"


## Any loss caps the grade at scoring.json loss_grade_cap (S needs none); never lifts a lower one.
static func _capped(c: TankContent, grade: String, losses: int) -> String:
	if losses <= 0:
		return grade
	var order := TankContentSchema.GRADES
	var cap := str(c.value("scoring", "loss_grade_cap", "A"))
	return order[maxi(order.find(grade), order.find(cap))]


static func xp(c: TankContent, kj: float, grade: String) -> int:
	return (
		roundi(kj / c.num("scoring", "xp.kj_per_xp", 10.0))
		+ int(c.num("scoring", "xp.grade_bonus.%s" % grade, 0.0))
	)


## The unlock ids a session earned (cosmetics.json order): finish, grade (min_grade or better),
## behemoth_no_breakdown (no loss either). `finished` is false for a run cut short (timeout or pause).
static func unlocks(state: TankState, grade: String, finished: bool) -> Array[String]:
	var out: Array[String] = []
	if not finished:
		return out
	var order := TankContentSchema.GRADES
	for u: Variant in state.content.unlocks():
		var ok := false
		match str(u.get("rule", "")):
			"finish":
				ok = true
			"grade":
				ok = order.find(grade) <= order.find(str(u.get("min_grade", "S")))
			"behemoth_no_breakdown":
				ok = (
					state.score.behemoth_killed
					and state.score.breakdowns == 0
					and state.score.losses == 0
				)
		if ok:
			out.append(str(u["id"]))
	return out
