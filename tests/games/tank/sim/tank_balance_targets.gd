class_name TankBalanceTargets
extends RefCounted
## T1-T5 of brief 2.4 evaluated on a list of TankBalanceHarness results (the tuning loop's quick
## check: the gates are tests/games/tank/sim/check_sims.mjs over the full simulation matrix).
## Returns [{id, ok, text}], one entry per target; a target no run applies to reads "skipped".
## T1-T5 are Normal's targets (a result without a difficulty counts as Normal); d1() holds the
## difficulty table and adds a table of rows.
##
## The difficulty targets the content is tuned to (compliant autopilot crews, seeds 1-3 for the
## tuning, seeds 4-6 as the check against overfit; no effort number, plan or governor input differs):
##   Easy    never loses: every run a victory, no loss, grade A or S.
##   Normal  usually wins: most seeds a victory, at most 1 loss, grade B or better.
##   Hard    expect to fail: 1-2 losses on most seeds, none above 4, grade C or better, never S with a
##           loss. ambush_15 defaults to it: 15 minutes, one or two failures, a whole workout.
##   Compliance 0.85: no loss on Easy, more losses than the compliant rider on Normal and Hard.
##   Only 1.0 and 0.85 are judged: these riders never rescue, so 0.7 reads harsher than the real matrix.


static func evaluate(results: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(t1(results))
	out.append(t2(results))
	out.append(t3(results))
	out.append(t4(results))
	out.append(t5(results))
	return out


static func _verdict(id: String, problems: Array[String], runs: int) -> Dictionary:
	if runs == 0:
		return {"id": id, "ok": true, "text": "%s skipped (no applicable run)" % id}
	var text := "%s %s (%d runs)" % [id, "met" if problems.is_empty() else "MISSED", runs]
	if not problems.is_empty():
		text += ": " + "; ".join(problems.slice(0, 40))
	return {"id": id, "ok": problems.is_empty(), "text": text}


static func _normal(r: Dictionary) -> bool:
	return str(r.get("difficulty", TankIds.DIFF_NORMAL)) == TankIds.DIFF_NORMAL


static func _compliant(r: Dictionary) -> bool:
	return float(r["compliance"]) > 0.999 and str(r["content"]) == "ashfall_road" and _normal(r)


## T1: compliant crews: every Advance 120-280 s, gun line 60-160 s, boss 120-330 s (check_sims.mjs
## T1_RANGES of ashfall_road), no overrun, at most 1 breakdown, grade B or better.
static func t1(results: Array) -> Dictionary:
	var problems: Array[String] = []
	var runs := 0
	var ranges := {
		TankIds.SEG_ADVANCE: [120.0, 280.0],
		TankIds.SEG_GUN_LINE: [60.0, 160.0],
		TankIds.SEG_BOSS: [120.0, 330.0],
	}
	for r: Dictionary in results:
		if not _compliant(r):
			continue
		runs += 1
		var at := "crew %d seed %d" % [r["crew"], r["seed"]]
		for s: Dictionary in r["segments"]:
			var seg := str(s["seg"])
			if not ranges.has(seg):
				continue
			var lim: Array = ranges[seg]
			var dur := float(s["dur_s"])
			if dur < float(lim[0]) or dur > float(lim[1]):
				problems.append("%s %s %d lasted %.0f s" % [at, seg, s["stage"], dur])
			if bool(s["overran"]):
				problems.append("%s: %s %d overran" % [at, seg, s["stage"]])
		if int(r["breakdowns"]) > 1:
			problems.append("%s: %d breakdowns" % [at, r["breakdowns"]])
		if not ["S", "A", "B"].has(str(r["grade"])):
			problems.append("%s: grade %s" % [at, r["grade"]])
	return _verdict("T1", problems, runs)


## T2: the dynamo's applied target spends >= 30 s above 80% FTP per stage (Advance + gun line) and
## >= 60 s in the boss, and is back to <= 65% within 120 s of a gun line's or the boss's end.
static func t2(results: Array) -> Dictionary:
	var problems: Array[String] = []
	var runs := 0
	for r: Dictionary in results:
		if not _compliant(r) or int(r["crew"]) < 2:
			continue
		runs += 1
		var at := "crew %d seed %d" % [r["crew"], r["seed"]]
		var per_stage := {}
		for d: Dictionary in r["dynamo"]:
			var st := int(d["stage"])
			per_stage[st] = float(per_stage.get(st, 0.0)) + float(d["above80_s"])
			var back := float(d["back_to_65_s"])
			if str(d["seg"]) != TankIds.SEG_ADVANCE and back > 120.0:
				problems.append(
					"%s: stage %d %s back to 65%% after %.0f s" % [at, st, d["seg"], back]
				)
		for st: int in per_stage:
			var need := 60.0 if st == 4 else 30.0
			if float(per_stage[st]) < need:
				problems.append(
					"%s: stage %d %.0f s above 80%% (need %.0f)" % [at, st, per_stage[st], need]
				)
	return _verdict("T2", problems, runs)


## T3: a compliant loader builds each heavy shell in 18-35 s (the 5 s window included) and gets
## >= 6 s at grade 0 per shell.
static func t3(results: Array) -> Dictionary:
	var problems: Array[String] = []
	var runs := 0
	for r: Dictionary in results:
		if not _compliant(r) or int(r["crew"]) < 3:
			continue
		runs += 1
		var heavy := 0
		for s: Dictionary in r["shells"]:
			if int(s["shell"]) != TankIds.SHELL_HEAVY or str(s["seg"]) == TankIds.SEG_DEPOT:
				continue
			heavy += 1
			var at := "crew %d seed %d t=%.0f" % [r["crew"], r["seed"], s["t"]]
			# Like check_sims.mjs: the first shell of a segment is only held to the maximum
			# (pressure holds across a checkpoint).
			var too_fast := float(s["build_s"]) < 18.0 and not bool(s.get("first", false))
			if too_fast or float(s["build_s"]) > 35.0:
				problems.append("%s: built in %.1f s" % [at, s["build_s"]])
			if float(s["grade0_s"]) < 6.0:
				problems.append("%s: %.1f s at grade 0" % [at, s["grade0_s"]])
		if heavy == 0:
			problems.append("crew %d seed %d: no heavy shell was built" % [r["crew"], r["seed"]])
	return _verdict("T3", problems, runs)


## T4: a compliant solo rider spends >= 60% of each Advance on Drive.
static func t4(results: Array) -> Dictionary:
	var problems: Array[String] = []
	var runs := 0
	for r: Dictionary in results:
		if not _compliant(r) or int(r["crew"]) != 1:
			continue
		runs += 1
		for d: Dictionary in r["drive_share"]:
			if float(d["share"]) < 0.6:
				problems.append(
					(
						"seed %d stage %d: Drive %.0f%%"
						% [r["seed"], d["stage"], 100.0 * float(d["share"])]
					)
				)
	return _verdict("T4", problems, runs)


## T5: the mean score falls strictly from 100% to 85% to 70% compliance (per crew size that has
## all three).
static func t5(results: Array) -> Dictionary:
	var problems: Array[String] = []
	var runs := 0
	for crew: int in [1, 2, 3, 4]:
		var means := {}
		for c: float in [1.0, 0.85, 0.7]:
			var total := 0.0
			var n := 0
			for r: Dictionary in results:
				var same := int(r["crew"]) == crew and absf(float(r["compliance"]) - c) < 0.001
				if same and str(r["content"]) == "ashfall_road" and _normal(r):
					total += float(r["score"])
					n += 1
			if n > 0:
				means[c] = total / n
		if means.size() == 3:
			runs += 1
			if not (
				float(means[1.0]) > float(means[0.85]) and float(means[0.85]) > float(means[0.7])
			):
				problems.append(
					(
						"crew %d: mean scores %.0f / %.0f / %.0f"
						% [crew, means[1.0], means[0.85], means[0.7]]
					)
				)
	return _verdict("T5", problems, runs)


## D1 (SPEC_TANK 9.3) over the results that name a difficulty, per content, difficulty, crew and
## compliance. Compliant: Easy wins always with no loss and grades A or S; Normal wins on most
## seeds, at most 1 loss, grade B or better; Hard has 1-2 losses on most seeds and none above 4,
## grade C or better. Compliance 0.85: Easy no loss, the others more losses than compliant. A grade
## of S with a loss is a miss everywhere. Other compliance values are shown, not judged (the
## synthetic riders never rescue, so their 0.7 rows read harsher than the real matrix). `rows` is
## the table: one line per group.
static func d1(results: Array) -> Dictionary:
	var groups := {}
	for r: Dictionary in results:
		if not r.has("difficulty"):
			continue
		var key := [
			r["content"], r["difficulty"], int(r["crew"]), snappedf(float(r["compliance"]), 0.01)
		]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(r)
	var problems: Array[String] = []
	var rows: Array[String] = []
	for key: Array in groups:
		var runs: Array = groups[key]
		var at := "%s %s crew %d c%.2f" % key
		var losses: Array[int] = []
		var wins := 0
		var grades: PackedStringArray = []
		for r: Dictionary in runs:
			losses.append(int(r["losses"]))
			wins += 1 if str(r["outcome"]) == TankIds.OUTCOME_VICTORY else 0
			grades.append(str(r["grade"]))
			if str(r["grade"]) == "S" and int(r["losses"]) > 0:
				problems.append("%s seed %d: grade S with a loss" % [at, r["seed"]])
		var compliant_mean := _mean_losses(groups, [key[0], key[1], key[2], 1.0])
		for p: String in _d1_group(key, losses, wins, grades, compliant_mean):
			problems.append("%s: %s" % [at, p])
		rows.append(
			(
				"%s: losses %s wins %d/%d grades %s"
				% [at, str(losses), wins, runs.size(), ",".join(grades)]
			)
		)
	var out := _verdict("D1", problems, groups.size())
	out["rows"] = rows
	return out


## Seeds that a "most seeds" target asks for: 2 of 3, and 1 of 1.
static func _most(n: int) -> int:
	return ceili(2.0 * n / 3.0)


static func _mean_losses(groups: Dictionary, key: Array) -> float:
	if not groups.has(key):
		return -1.0
	var total := 0
	for r: Dictionary in groups[key]:
		total += int(r["losses"])
	return float(total) / (groups[key] as Array).size()


static func _d1_group(
	key: Array, losses: Array[int], wins: int, grades: PackedStringArray, compliant_mean: float
) -> Array[String]:
	var out: Array[String] = []
	var diff := str(key[1])
	var n := losses.size()
	var most := int(losses.max())
	var total := 0
	var in_band := 0
	for l in losses:
		total += l
		in_band += 1 if l >= 1 and l <= 2 else 0
	if is_equal_approx(float(key[3]), 0.85):
		if diff == TankIds.DIFF_EASY:
			if most > 0:
				out.append("%d losses at most on Easy (none)" % most)
		elif compliant_mean >= 0.0 and not float(total) / n > compliant_mean:
			out.append(
				"mean losses %.2f not above compliant %.2f" % [float(total) / n, compliant_mean]
			)
		return out
	if not is_equal_approx(float(key[3]), 1.0):
		return out
	match diff:
		TankIds.DIFF_EASY:
			if wins < n:
				out.append("%d of %d won (all)" % [wins, n])
			if most > 0:
				out.append("%d losses at most (none)" % most)
			out.append_array(_grades_in(grades, ["S", "A"]))
		TankIds.DIFF_NORMAL:
			if wins < _most(n):
				out.append("%d of %d won (at least %d)" % [wins, n, _most(n)])
			if most > 1:
				out.append("%d losses at most (1)" % most)
			out.append_array(_grades_in(grades, ["S", "A", "B"]))
		TankIds.DIFF_HARD:
			if in_band < _most(n):
				out.append("%d of %d with 1-2 losses (at least %d)" % [in_band, n, _most(n)])
			if most > 4:
				out.append("%d losses at most (4)" % most)
			out.append_array(_grades_in(grades, ["S", "A", "B", "C"]))
	return out


static func _grades_in(grades: PackedStringArray, allowed: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for g in grades:
		if not allowed.has(g):
			out.append("grade %s (%s)" % [g, "/".join(allowed)])
	return out
