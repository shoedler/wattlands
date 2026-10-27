class_name TankBalanceTargets
extends RefCounted
## T1-T5 of brief 2.4 evaluated on a list of TankBalanceHarness results (the tuning loop's quick
## check: the gates are tests/games/tank/sim/check_sims.mjs over the full simulation matrix).
## Returns [{id, ok, text}], one entry per target; a target no run applies to reads "skipped".


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


static func _compliant(r: Dictionary) -> bool:
	return float(r["compliance"]) > 0.999 and str(r["content"]) == "ashfall_road"


## T1: compliant crews: every Advance 150-240 s, gun line 80-160 s, boss 180-330 s, no overrun,
## at most 1 breakdown, grade B or better.
static func t1(results: Array) -> Dictionary:
	var problems: Array[String] = []
	var runs := 0
	var ranges := {
		TankIds.SEG_ADVANCE: [150.0, 240.0],
		TankIds.SEG_GUN_LINE: [80.0, 160.0],
		TankIds.SEG_BOSS: [180.0, 330.0],
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
				if same and str(r["content"]) == "ashfall_road":
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
