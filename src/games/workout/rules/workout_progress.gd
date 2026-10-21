class_name WorkoutProgress
extends RefCounted
## Workout's simple progression in ctx.progress (BRIEF 3.6): totals (rides, kJ, XP, time in
## band, sprints hit), a level from XP, the best grade, and cosmetic pennant unlocks. The
## newest unlock becomes the equipped pennant ("pennant"), which the ride view draws for
## the local rider. Local to each peer; nothing is sent anywhere.

const XP_PER_LEVEL := 1000.0
const GRADES: Array[String] = ["D", "C", "B", "A", "S"]
## In unlock order. Each needs every listed total (after this ride) or the grade.
const UNLOCKS: Array[Dictionary] = [
	{"id": "pennant_swallowtail", "rides": 1.0},
	{"id": "pennant_chevron", "rides": 5.0},
	{"id": "pennant_star", "grade": "S"},
	{"id": "pennant_bolt", "sprints_hit": 10.0},
	{"id": "pennant_gold", "kj": 5000.0},
]
const PENNANT_STYLES: Array[String] = ["", "pennant_swallowtail", "pennant_chevron", "pennant_star", "pennant_bolt", "pennant_gold"]


## Updates `progress` from the local rider's row and returns the new unlock ids.
static func apply(results: GameResults, progress: ProgressStore, local_peer: int) -> Array:
	if results == null or progress == null:
		return []
	var row := results.row(local_peer)
	if row.is_empty():
		return []
	var hits := 0
	for s: Variant in row.get("sprints", []):
		if s is Dictionary and bool(s.get("hit", false)):
			hits += 1
	var stats: Dictionary = row.get("stats", {})
	var grade := str(stats.get(WorkoutResults.STAT_GRADE, GameResults.grade_from_fraction(float(row.get("time_in_band_pct", 0.0)) / 100.0)))
	var totals := {
		"rides": progress.add("rides", 1.0),
		"kj": progress.add("kj_total", float(row.get("kj", 0.0))),
		"xp": progress.add("xp_total", float(row.get("xp", 0))),
		"tib_s": progress.add("tib_s_total", float(row.get("time_in_band_s", 0.0))),
		"sprints_hit": progress.add("sprints_hit_total", float(hits)),
	}
	progress.set_value("level", level_for(float(totals["xp"])))
	var best := str(progress.get_value("best_grade", ""))
	if GRADES.find(grade) > GRADES.find(best):
		progress.set_value("best_grade", grade)
	var have: Array = []
	var stored: Variant = progress.get_value("unlocks", [])
	if stored is Array:
		have = (stored as Array).duplicate()
	var fresh: Array = []
	for u in UNLOCKS:
		var id := str(u["id"])
		if have.has(id):
			continue
		if _met(u, totals, grade):
			have.append(id)
			fresh.append(id)
	progress.set_value("unlocks", have)
	if not fresh.is_empty():
		progress.set_value("pennant", fresh.back())
	return fresh


static func level_for(xp_total: float) -> int:
	return 1 + int(floor(maxf(xp_total, 0.0) / XP_PER_LEVEL))


## The equipped pennant style id ("" = the plain pennant).
static func equipped(progress: ProgressStore) -> String:
	if progress == null:
		return ""
	var id := str(progress.get_value("pennant", ""))
	return id if PENNANT_STYLES.has(id) else ""


static func _met(u: Dictionary, totals: Dictionary, grade: String) -> bool:
	for key: Variant in u.keys():
		if key == "id":
			continue
		if key == "grade":
			if grade != str(u["grade"]):
				return false
		elif float(totals.get(key, 0.0)) < float(u[key]):
			return false
	return true
