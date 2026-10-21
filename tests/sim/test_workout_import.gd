# gdlint: disable=max-public-methods
extends GutTest
## WorkoutImport.parse_zwo (BRIEF 3.7, 4.6.1, 4.6.8): every supported tag, IntervalsT
## expansion, FreeRide as SIM, unsupported tags skipped with warnings, the warm-up prefix,
## and every clamp kind reported, from the fixtures in tests/fixtures/zwo/.

const DIR := "res://tests/fixtures/zwo/"
const EPS := 1e-6


func _load(name: String) -> Dictionary:
	return WorkoutImport.parse_zwo_file(DIR + name)


func _phases(r: Dictionary) -> Array:
	return r["phases"]


func _rules(r: Dictionary) -> Array:
	var out: Array = []
	for rec: Dictionary in r["clamp_records"]:
		out.append(rec["rule"])
	return out


func _assert_erg(
	p: PlanPhase, kind: String, from_pct: float, to_pct: float, dur: float, lap: bool, what: String
) -> void:
	assert_eq(p.mode, Wl.ERG, what + " mode")
	assert_eq(p.kind, kind, what + " kind")
	assert_almost_eq(p.target_pct, from_pct, EPS, what + " target_pct")
	if absf(from_pct - to_pct) > EPS:
		assert_true(p.has_ramp(), what + " has a ramp")
		assert_almost_eq(p.ramp_to_pct, to_pct, EPS, what + " ramp_to_pct")
	else:
		assert_false(p.has_ramp(), what + " has no ramp")
	assert_almost_eq(p.duration_s, dur, EPS, what + " duration_s")
	assert_eq(p.lap, lap, what + " lap")
	assert_false(p.label.is_empty(), what + " has a label")


## Independent check of what the PlanValidator enforces (BRIEF 3.6, 4.6.1, 4.6.8), with the
## conservative per-phase reading: a phase counts by its peak for its whole length.
func _assert_plan_safe(phases: Array, what: String) -> void:
	var t := 0.0
	var acc_105 := 0.0
	var acc_120 := 0.0
	var reset_run := 0.0
	var switches: Array[float] = []
	var prev_mode := ""
	for i in phases.size():
		var p: PlanPhase = phases[i]
		var tag := "%s phase %d" % [what, i]
		assert_true(Wl.is_phase_kind(p.kind) and p.kind != Wl.COOLDOWN, tag + ": kind %s" % p.kind)
		assert_gt(p.duration_s, 0.0, tag + ": positive duration")
		if not prev_mode.is_empty() and p.mode != prev_mode:
			switches.append(t)
		prev_mode = p.mode
		if p.mode == Wl.ERG:
			var peak := p.peak_pct()
			assert_true(peak <= 150.0 + EPS, tag + ": <= 150%")
			assert_true(p.target_pct >= 0.0, tag + ": >= 0%")
			if t < 300.0 - EPS:
				assert_true(peak <= 65.0 + EPS, tag + (": warm-up <= 65%% (peak %.2f)" % peak))
			if p.duration_s > 300.0 + EPS:
				assert_true(peak <= 105.0 + EPS, tag + ": long phase <= 105%")
			if peak > 120.0 + EPS:
				acc_120 += p.duration_s
			if peak > 105.0 + EPS:
				acc_105 += p.duration_s
			assert_true(acc_120 <= 60.0 + EPS, tag + ": <= 60 s above 120%")
			assert_true(acc_105 <= 300.0 + EPS, tag + ": <= 300 s above 105%")
			if peak <= 90.0 + EPS:
				reset_run += p.duration_s
				if reset_run >= 120.0 - EPS:
					acc_105 = 0.0
					acc_120 = 0.0
			else:
				reset_run = 0.0
		else:
			assert_eq(p.grade_source, Wl.GRADE_FLAT, tag + ": SIM flat")
			reset_run = 0.0
		t += p.duration_s
	if prev_mode == Wl.SIM:
		switches.append(t)  # the appended ERG cool-down
	for k in range(1, switches.size()):
		assert_true(
			switches[k] - switches[k - 1] >= 30.0 - EPS,
			"%s: switches at %.1f and %.1f are >= 30 s apart" % [what, switches[k - 1], switches[k]]
		)


func test_all_tags_fixture() -> void:
	var r := _load("all_tags.zwo")
	assert_true(r["ok"], str(r["error"]))
	assert_eq(r["error"], "")
	assert_eq(r["name"], "All tags")
	assert_eq(r["description"], "Every supported tag & two unsupported ones")
	assert_false(r["prefix_inserted"], "opens with its own Warmup within limits")
	assert_eq((r["clamps"] as Array).size(), 0, "nothing to clamp: %s" % [r["clamps"]])
	var ph := _phases(r)
	assert_eq(ph.size(), 12)
	_assert_erg(ph[0], Wl.WARMUP, 40.0, 65.0, 300.0, true, "Warmup")
	_assert_erg(ph[1], Wl.WORK, 88.0, 88.0, 240.0, true, "SteadyState 0.88")
	for k in 3:
		_assert_erg(ph[2 + 2 * k], Wl.WORK, 110.0, 110.0, 60.0, true, "IntervalsT on %d" % (k + 1))
		_assert_erg(
			ph[3 + 2 * k], Wl.RECOVERY, 50.0, 50.0, 120.0, true, "IntervalsT off %d" % (k + 1)
		)
	_assert_erg(ph[8], Wl.WORK, 60.0, 90.0, 180.0, true, "Ramp by its upper end")
	var free: PlanPhase = ph[9]
	assert_eq(free.mode, Wl.SIM, "FreeRide is SIM")
	assert_eq(free.kind, Wl.FREE)
	assert_eq(free.grade_source, Wl.GRADE_FLAT)
	assert_eq(free.duration_s, 60.0)
	assert_true(free.lap)
	_assert_erg(ph[10], Wl.RECOVERY, 70.0, 70.0, 120.0, true, "SteadyState 0.70")
	_assert_erg(
		ph[11], Wl.RECOVERY, 70.0, 40.0, 300.0, true, "Cooldown ramps PowerLow -> PowerHigh"
	)
	assert_almost_eq(float(r["total_s"]), 1740.0, EPS)
	assert_eq(ph[0].meta.get("cadence_rpm"), 85.0, "Cadence kept in meta")
	assert_eq(ph[2].meta.get("cadence_rpm"), 100.0, "IntervalsT on cadence")
	assert_eq(ph[3].meta.get("cadence_rpm"), 85.0, "IntervalsT CadenceResting")
	assert_eq(ph[8].meta.get("zwo_block"), 5, "phases point back to their element number")
	_assert_plan_safe(ph, "all_tags")


func test_all_tags_labels() -> void:
	var ph := _phases(_load("all_tags.zwo"))
	var labels: Array = []
	for p: PlanPhase in ph:
		labels.append(p.label)
		assert_false(p.label.begins_with("SIM_ZWO_"), "label translated: %s" % p.label)
	assert_eq(labels[0], "Warm-up 40-65%")
	assert_eq(labels[1], "Steady 88%")
	assert_eq(labels[2], "Interval 1/3 110%")
	assert_eq(labels[3], "Recovery 1/3 50%")
	assert_eq(labels[6], "Interval 3/3 110%")
	assert_eq(labels[8], "Ramp 60-90%")
	assert_eq(labels[9], "Free ride")
	assert_eq(labels[11], "Cool-down ramp 70-40%")


func test_unsupported_tags_are_skipped_with_warnings() -> void:
	var r := _load("all_tags.zwo")
	var w: Array = r["warnings"]
	assert_eq(w.size(), 2, "MaxEffort once, the textevents in one line: %s" % [w])
	assert_string_contains(str(w[0]), "Block 4")
	assert_string_contains(str(w[0]), "<MaxEffort>")
	assert_string_contains(str(w[1]), "3 <textevent>")
	var tags: Array = []
	for b: Dictionary in r["blocks"]:
		tags.append(b["tag"])
	assert_eq(
		tags, ["Warmup", "SteadyState", "IntervalsT", "Ramp", "FreeRide", "SteadyState", "Cooldown"]
	)


func test_raw_blocks() -> void:
	var r := _load("all_tags.zwo")
	var blocks: Array = r["blocks"]
	assert_eq(blocks.size(), 7)
	for b: Dictionary in blocks:
		for key in [
			"tag",
			"duration_s",
			"power_lo",
			"power_hi",
			"repeat",
			"on_s",
			"off_s",
			"on_power",
			"off_power",
			"cadence",
			"index"
		]:
			assert_true(b.has(key), "%s has %s" % [b["tag"], key])
	var warm: Dictionary = blocks[0]
	assert_eq(warm["index"], 1)
	assert_almost_eq(float(warm["power_lo"]), 0.40, EPS, "fractions as in the file")
	assert_almost_eq(float(warm["power_hi"]), 0.65, EPS)
	var iv: Dictionary = blocks[2]
	assert_eq(iv["tag"], "IntervalsT")
	assert_eq(iv["index"], 3)
	assert_eq(iv["repeat"], 3)
	assert_eq(float(iv["on_s"]), 60.0)
	assert_eq(float(iv["off_s"]), 120.0)
	assert_almost_eq(float(iv["on_power"]), 1.10, EPS)
	assert_almost_eq(float(iv["off_power"]), 0.50, EPS)
	assert_eq(float(iv["duration_s"]), 540.0, "Repeat x (on + off)")
	assert_eq(float(iv["cadence"]), 100.0)
	assert_eq(float(iv["cadence_resting"]), 85.0)
	var ramp: Dictionary = blocks[3]
	assert_eq(ramp["index"], 5, "element numbers count the skipped MaxEffort")
	var free: Dictionary = blocks[4]
	assert_eq(free["tag"], "FreeRide")
	assert_eq(float(free["power_lo"]), -1.0)
	assert_eq(float(free["duration_s"]), 60.0)
	var cool: Dictionary = blocks[6]
	assert_almost_eq(float(cool["power_lo"]), 0.70, EPS)
	assert_almost_eq(float(cool["power_hi"]), 0.40, EPS)


func test_prefix_inserted_when_missing() -> void:
	var r := _load("no_warmup.zwo")
	assert_true(r["ok"])
	assert_true(r["prefix_inserted"])
	var ph := _phases(r)
	assert_eq(ph.size(), 3)
	_assert_erg(ph[0], Wl.WARMUP, 50.0, 65.0, 300.0, true, "prefix")
	assert_eq(ph[0].label, "Warm-up")
	assert_eq(ph[0].meta.get("zwo_block"), 0, "the prefix has no block")
	_assert_erg(ph[1], Wl.WORK, 90.0, 90.0, 600.0, true, "main set untouched")
	_assert_erg(ph[2], Wl.RECOVERY, 55.0, 55.0, 300.0, true, "SteadyState 0.55")
	assert_eq((r["clamps"] as Array).size(), 0)
	assert_almost_eq(float(r["total_s"]), 1200.0, EPS)
	_assert_plan_safe(ph, "no_warmup")


func test_no_prefix_when_first_300_s_are_easy() -> void:
	var r := _load("easy_start.zwo")
	assert_true(r["ok"])
	assert_false(r["prefix_inserted"])
	var ph := _phases(r)
	assert_eq(ph.size(), 3)
	_assert_erg(ph[0], Wl.RECOVERY, 55.0, 55.0, 200.0, true, "easy start")
	_assert_erg(ph[1], Wl.RECOVERY, 55.0, 65.0, 100.0, true, "Ramp below 76% is RECOVERY")
	_assert_erg(ph[2], Wl.WORK, 95.0, 95.0, 300.0, true, "starts at 300 s, outside the warm-up")
	assert_eq((r["clamps"] as Array).size(), 0)
	_assert_plan_safe(ph, "easy_start")


func test_own_warmup_is_split_at_300_s() -> void:
	var r := _load("warmup_split.zwo")
	assert_true(r["ok"])
	assert_false(r["prefix_inserted"], "the file's own Warmup is kept")
	var ph := _phases(r)
	assert_eq(ph.size(), 3)
	_assert_erg(ph[0], Wl.WARMUP, 25.0, 50.0, 300.0, true, "first 300 s of the ramp")
	_assert_erg(ph[1], Wl.WARMUP, 50.0, 75.0, 300.0, false, "the rest continues the lap")
	_assert_erg(ph[2], Wl.WORK, 85.0, 85.0, 300.0, true, "main set")
	assert_eq(_rules(r), [WorkoutImport.RULE_WARMUP_SPLIT])
	var rec: Dictionary = (r["clamp_records"] as Array)[0]
	assert_eq(rec["block"], 1)
	assert_eq(rec["phase"], 0)
	assert_eq(rec["from_pct"], [25.0, 75.0])
	assert_eq(rec["to_pct"], [25.0, 50.0])
	assert_string_contains(str(r["clamps"][0]), "Block 1")
	assert_string_contains(str(r["clamps"][0]), "split at 5:00")
	_assert_plan_safe(ph, "warmup_split")


func test_warmup_clamps_inside_the_first_300_s() -> void:
	var r := _load("warmup_clamp.zwo")
	assert_true(r["ok"])
	assert_false(r["prefix_inserted"])
	var ph := _phases(r)
	assert_eq(ph.size(), 4)
	_assert_erg(ph[0], Wl.WARMUP, 50.0, 65.0, 120.0, true, "Warmup end clamped 80 -> 65")
	_assert_erg(ph[1], Wl.WORK, 65.0, 65.0, 180.0, true, "SteadyState part inside the warm-up")
	_assert_erg(ph[2], Wl.WORK, 95.0, 95.0, 420.0, false, "SteadyState part after 300 s")
	_assert_erg(ph[3], Wl.RECOVERY, 50.0, 50.0, 240.0, true, "recovery")
	assert_eq(
		_rules(r),
		[WorkoutImport.RULE_WARMUP, WorkoutImport.RULE_WARMUP_SPLIT, WorkoutImport.RULE_WARMUP]
	)
	var recs: Array = r["clamp_records"]
	assert_eq(recs[0]["phase"], 0)
	assert_eq(recs[0]["from_pct"], [50.0, 80.0])
	assert_eq(recs[0]["to_pct"], [50.0, 65.0])
	assert_eq(recs[1]["block"], 2)
	assert_eq(recs[1]["phase"], 1)
	assert_eq(recs[2]["phase"], 1)
	assert_eq(recs[2]["from_pct"], [95.0, 95.0])
	assert_eq(recs[2]["to_pct"], [65.0, 65.0])
	assert_string_contains(str(r["clamps"][0]), "Block 1 (Warm-up 50-80%): 50-80% to 50-65%")
	assert_string_contains(str(r["clamps"][0]), "first 5 minutes")
	assert_string_contains(str(r["clamps"][2]), "Block 2 (Steady 95%): 95% to 65%")
	_assert_plan_safe(ph, "warmup_clamp")


func test_ceiling_and_long_phase_caps() -> void:
	var r := _load("caps.zwo")
	assert_true(r["ok"])
	assert_true(r["prefix_inserted"])
	var ph := _phases(r)
	assert_eq(ph.size(), 5)
	_assert_erg(ph[1], Wl.WORK, 150.0, 150.0, 30.0, true, "160% capped at 150%")
	_assert_erg(ph[3], Wl.WORK, 105.0, 105.0, 600.0, true, "a 600 s block at 110% capped at 105%")
	assert_eq(_rules(r), [WorkoutImport.RULE_CEILING, WorkoutImport.RULE_LONG_PHASE])
	var recs: Array = r["clamp_records"]
	assert_eq(recs[0]["phase"], 1)
	assert_eq(recs[0]["block"], 1)
	assert_eq(recs[0]["from_pct"], [160.0, 160.0])
	assert_eq(recs[0]["to_pct"], [150.0, 150.0])
	assert_eq(recs[1]["phase"], 3)
	assert_eq(recs[1]["block"], 3)
	assert_eq(recs[1]["to_pct"], [105.0, 105.0])
	assert_string_contains(str(r["clamps"][0]), "150% FTP")
	assert_string_contains(str(r["clamps"][1]), "longer than 5 minutes")
	assert_eq(r["blocks"][0]["power_hi"], 1.6, "raw blocks keep the file's values")
	_assert_plan_safe(ph, "caps")


func test_limit_120_clamps_the_offending_intervals() -> void:
	var r := _load("limits_120.zwo")
	assert_true(r["ok"])
	var ph := _phases(r)
	assert_eq(ph.size(), 10)
	# 30 s on at 130%: the first two reach exactly 60 s above 120% (allowed); 30 s off at 50%
	# is no reset, so the third and fourth are clamped to 120%.
	_assert_erg(ph[1], Wl.WORK, 130.0, 130.0, 30.0, true, "on 1")
	_assert_erg(ph[3], Wl.WORK, 130.0, 130.0, 30.0, true, "on 2")
	_assert_erg(ph[5], Wl.WORK, 120.0, 120.0, 30.0, true, "on 3 clamped")
	_assert_erg(ph[7], Wl.WORK, 120.0, 120.0, 30.0, true, "on 4 clamped")
	assert_eq(_rules(r), [WorkoutImport.RULE_LIMIT_120, WorkoutImport.RULE_LIMIT_120])
	assert_eq(r["clamp_records"][0]["phase"], 5)
	assert_eq(r["clamp_records"][1]["phase"], 7)
	assert_eq(r["clamp_records"][0]["block"], 2)
	assert_string_contains(str(r["clamps"][0]), "Interval 3/4 130%")
	assert_string_contains(str(r["clamps"][0]), "60 s above 120%")
	_assert_plan_safe(ph, "limits_120")


func test_limit_105_and_the_reset() -> void:
	var r := _load("limits_105.zwo")
	assert_true(r["ok"])
	var ph := _phases(r)
	assert_eq(ph.size(), 8)
	_assert_erg(ph[1], Wl.WORK, 110.0, 110.0, 200.0, true, "200 s above 105%")
	_assert_erg(ph[3], Wl.WORK, 105.0, 105.0, 200.0, true, "would make 400 s: clamped")
	_assert_erg(ph[5], Wl.WORK, 110.0, 110.0, 100.0, true, "makes exactly 300 s: allowed")
	_assert_erg(ph[7], Wl.WORK, 110.0, 110.0, 200.0, true, "after exactly 120 s at 50%: reset")
	assert_eq(_rules(r), [WorkoutImport.RULE_LIMIT_105])
	assert_eq(r["clamp_records"][0]["phase"], 3)
	assert_eq(r["clamp_records"][0]["block"], 4)
	assert_string_contains(str(r["clamps"][0]), "5 minutes above 105%")
	_assert_plan_safe(ph, "limits_105")


func test_short_sim_and_erg_runs_are_extended_to_30_s() -> void:
	var r := _load("spacing.zwo")
	assert_true(r["ok"])
	var ph := _phases(r)
	assert_eq(ph.size(), 8)
	var modes: Array = []
	var lens: Array = []
	for p: PlanPhase in ph:
		modes.append(p.mode)
		lens.append(p.duration_s)
	assert_eq(modes, [Wl.ERG, Wl.SIM, Wl.ERG, Wl.SIM, Wl.ERG, Wl.SIM, Wl.ERG, Wl.SIM])
	assert_eq(
		lens,
		[300.0, 30.0, 120.0, 60.0, 30.0, 45.0, 60.0, 30.0],
		(
			"20 s free ride, 10 s ERG gap and the final 15 s free ride"
			+ " (before the ERG cool-down) grow to 30 s"
		)
	)
	assert_eq(
		_rules(r),
		[
			WorkoutImport.RULE_SWITCH_SPACING,
			WorkoutImport.RULE_SWITCH_SPACING,
			WorkoutImport.RULE_SWITCH_SPACING
		]
	)
	var recs: Array = r["clamp_records"]
	assert_eq([recs[0]["phase"], recs[1]["phase"], recs[2]["phase"]], [1, 4, 7])
	assert_eq([recs[0]["from_s"], recs[1]["from_s"], recs[2]["from_s"]], [20.0, 10.0, 15.0])
	assert_eq([recs[0]["to_s"], recs[1]["to_s"], recs[2]["to_s"]], [30.0, 30.0, 30.0])
	assert_eq(recs[0]["from_pct"], [])
	assert_string_contains(str(r["clamps"][0]), "Block 2 (Free ride): 20 s to 30 s")
	assert_string_contains(str(r["clamps"][0]), "30 s apart")
	assert_almost_eq(float(r["total_s"]), 675.0, EPS)
	_assert_plan_safe(ph, "spacing")


func test_free_ride_first_then_prefix() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<FreeRide Duration="20"/>
		<SteadyState Duration="300" Power="0.9"/>
		</workout></workout_file>"""
		)
	)
	assert_true(r["ok"])
	assert_true(r["prefix_inserted"], "the 90% block starts inside the first 300 s")
	var ph := _phases(r)
	assert_eq(ph.size(), 3)
	assert_eq(ph[0].label, "Warm-up")
	assert_eq(ph[1].mode, Wl.SIM)
	assert_eq(ph[1].duration_s, 30.0, "the free ride now sits between two switches")
	assert_eq(_rules(r), [WorkoutImport.RULE_SWITCH_SPACING])
	_assert_plan_safe(ph, "free_first")


func test_sim_first_is_a_warmup_within_limits() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<FreeRide Duration="300"/>
		<SteadyState Duration="300" Power="0.9"/>
		</workout></workout_file>"""
		)
	)
	assert_true(r["ok"])
	assert_false(
		r["prefix_inserted"], "SIM is allowed in the first 300 s (the governor clamps its grade)"
	)
	assert_eq(_phases(r).size(), 2)
	assert_eq((r["clamps"] as Array).size(), 0)
	_assert_plan_safe(_phases(r), "sim_first")


func test_every_clamp_kind_is_reported() -> void:
	var seen := {}
	for f in ["warmup_clamp.zwo", "caps.zwo", "limits_120.zwo", "limits_105.zwo", "spacing.zwo"]:
		var r := _load(f)
		var recs: Array = r["clamp_records"]
		var texts: Array = r["clamps"]
		assert_eq(texts.size(), recs.size(), f)
		for i in recs.size():
			seen[recs[i]["rule"]] = true
			assert_eq(texts[i], recs[i]["text"], "%s: clamps[] mirrors clamp_records[].text" % f)
			assert_false(str(texts[i]).contains("SIM_ZWO_"), "%s: text translated" % f)
			assert_true(
				int(recs[i]["phase"]) >= 0 and int(recs[i]["phase"]) < _phases(r).size(),
				"%s: phase index" % f
			)
	for rule in [
		WorkoutImport.RULE_WARMUP,
		WorkoutImport.RULE_WARMUP_SPLIT,
		WorkoutImport.RULE_CEILING,
		WorkoutImport.RULE_LONG_PHASE,
		WorkoutImport.RULE_LIMIT_105,
		WorkoutImport.RULE_LIMIT_120,
		WorkoutImport.RULE_SWITCH_SPACING
	]:
		assert_true(seen.has(rule), "clamp rule %s reported by some fixture" % rule)
	assert_eq(WorkoutImport.RULE_WARMUP, Wl.CLAMP_WARMUP)
	assert_eq(WorkoutImport.RULE_CEILING, Wl.CLAMP_CEILING)
	assert_eq(WorkoutImport.RULE_LONG_PHASE, Wl.CLAMP_LONG_PHASE)
	assert_eq(WorkoutImport.RULE_LIMIT_105, Wl.CLAMP_LIMIT_105)
	assert_eq(WorkoutImport.RULE_LIMIT_120, Wl.CLAMP_LIMIT_120)


func test_real_world_quirks() -> void:
	var r := _load("real_world.zwo")
	assert_true(r["ok"], str(r["error"]))
	assert_eq(r["name"], "Over & unders", "entities decoded")
	assert_eq(r["description"], "Sweet spot <b>over-unders</b>", "CDATA kept verbatim")
	var w: Array = r["warnings"]
	assert_eq(w.size(), 5, "%s" % [w])
	assert_string_contains(str(w[0]), "Block 2: power 88 was read as a percentage")
	assert_string_contains(str(w[1]), "Block 3: <SteadyState> has no valid duration")
	assert_string_contains(str(w[2]), "Block 4: <SteadyState> has no valid power")
	assert_string_contains(str(w[3]), "Block 5: <IntervalsT> uses the mean")
	assert_string_contains(str(w[4]), "Block 6: <Ramp> has a negative power")
	var idx: Array = []
	for b: Dictionary in r["blocks"]:
		idx.append(b["index"])
	assert_eq(idx, [1, 2, 5, 7], "lower-case tags accepted, bad blocks skipped")
	var ph := _phases(r)
	assert_eq(ph.size(), 8)
	_assert_erg(ph[0], Wl.WARMUP, 45.0, 62.86, 300.0, true, "lower-case warmup split at 300 s")
	_assert_erg(ph[1], Wl.WARMUP, 62.86, 70.0, 120.0, false, "rest of the warm-up")
	_assert_erg(ph[2], Wl.WORK, 88.0, 88.0, 300.0, true, "88 read as 88%")
	_assert_erg(ph[3], Wl.WORK, 100.0, 100.0, 120.0, true, "mean of PowerOnLow and PowerOnHigh")
	_assert_erg(ph[4], Wl.RECOVERY, 80.0, 80.0, 60.0, true, "IntervalsT off")
	_assert_erg(ph[7], Wl.RECOVERY, 60.0, 40.0, 300.0, true, "lower-case cooldown")
	assert_eq(ph[0].label, "Warm-up 45-62.9%")
	assert_eq(_rules(r), [WorkoutImport.RULE_WARMUP_SPLIT])
	_assert_plan_safe(ph, "real_world")


func test_entities_are_decoded_once() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file>
		<name>&amp;lt;tag&amp;gt; &amp; co &#65;&#x42;</name>
		<workout><SteadyState Duration="&#54;0" Power="0.5"/></workout>
		</workout_file>"""
		)
	)
	assert_true(r["ok"], str(r["error"]))
	assert_eq(r["name"], "&lt;tag&gt; & co AB", "one level of entities, numeric ones too")
	assert_eq(float(r["blocks"][0]["duration_s"]), 60.0, "entities in attribute values")


func test_kind_thresholds() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<SteadyState Duration="300" Power="0.5"/>
		<SteadyState Duration="60" Power="0.76"/>
		<SteadyState Duration="60" Power="0.75"/>
		<Ramp Duration="60" PowerLow="0.9" PowerHigh="0.6"/>
		<Ramp Duration="60" PowerLow="0.5" PowerHigh="0.75"/>
		<Warmup Duration="60" PowerLow="0.9" PowerHigh="1.0"/>
		<Cooldown Duration="60" PowerLow="0.9" PowerHigh="0.8"/>
		</workout></workout_file>"""
		)
	)
	assert_true(r["ok"])
	var kinds: Array = []
	for p: PlanPhase in _phases(r):
		kinds.append(p.kind)
	assert_eq(
		kinds, [Wl.RECOVERY, Wl.WORK, Wl.RECOVERY, Wl.WORK, Wl.RECOVERY, Wl.WARMUP, Wl.RECOVERY]
	)


func test_intervals_without_off_phases() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<SteadyState Duration="300" Power="0.5"/>
		<IntervalsT Repeat="3" OnDuration="20" OffDuration="0" OnPower="0.6"/>
		</workout></workout_file>"""
		)
	)
	assert_true(r["ok"])
	var ph := _phases(r)
	assert_eq(ph.size(), 4, "OffDuration 0 gives on phases only")
	for i in range(1, 4):
		_assert_erg(ph[i], Wl.WORK, 60.0, 60.0, 20.0, true, "on %d" % i)
	assert_eq(r["blocks"][1]["off_power"], -1.0)


func test_rejected_files() -> void:
	for f in ["not_xml.zwo", "wrong_root.zwo", "truncated.zwo", "unsupported_only.zwo"]:
		var r := _load(f)
		assert_false(r["ok"], f)
		assert_false(str(r["error"]).is_empty(), "%s: error set" % f)
		assert_false(str(r["error"]).contains("SIM_ZWO_"), "%s: error translated" % f)
		assert_eq((r["phases"] as Array).size(), 0, "%s: no phases" % f)
	assert_string_contains(str(_load("wrong_root.zwo")["error"]), "<plan>")
	assert_string_contains(str(_load("truncated.zwo")["error"]), "never closed")
	var none := _load("unsupported_only.zwo")
	assert_string_contains(str(none["error"]), "no supported blocks")
	assert_eq((none["warnings"] as Array).size(), 2, "both skipped tags listed")


func test_empty_and_missing() -> void:
	var r := WorkoutImport.parse_zwo("")
	assert_false(r["ok"])
	assert_string_contains(str(r["error"]), "empty")
	var no_workout := WorkoutImport.parse_zwo("<workout_file><name>x</name></workout_file>")
	assert_false(no_workout["ok"])
	assert_string_contains(str(no_workout["error"]), "<workout>")
	var missing := WorkoutImport.parse_zwo_file(DIR + "does_not_exist.zwo")
	assert_false(missing["ok"])
	assert_string_contains(str(missing["error"]), "missing")
	assert_string_contains(str(missing["error"]), "does_not_exist.zwo", "names the path")
	for key in [
		"phases",
		"blocks",
		"clamps",
		"warnings",
		"name",
		"description",
		"clamp_records",
		"prefix_inserted",
		"total_s"
	]:
		assert_true(missing.has(key), "missing-file result has %s" % key)
	assert_true(missing["phases"] is Array and (missing["phases"] as Array).is_empty())


func test_result_shape() -> void:
	var r := _load("all_tags.zwo")
	for key in [
		"ok",
		"name",
		"description",
		"phases",
		"blocks",
		"clamps",
		"warnings",
		"error",
		"clamp_records",
		"prefix_inserted",
		"total_s"
	]:
		assert_true(r.has(key), "result has %s" % key)
	assert_true(r["phases"] is Array)
	for p: Variant in r["phases"]:
		assert_true(p is PlanPhase)
	var failed := WorkoutImport.parse_zwo("nope")
	for key in ["ok", "name", "description", "phases", "blocks", "clamps", "warnings", "error"]:
		assert_true(failed.has(key), "failed result has %s" % key)


func test_to_plan_copies_the_phases() -> void:
	var r := _load("no_warmup.zwo")
	var plan := WorkoutImport.to_plan(r)
	assert_eq(plan.size(), 3)
	assert_false(plan.cooldown_appended, "the PlanValidator appends the cool-down")
	assert_eq(plan.phase(1).to_dict(), (r["phases"][1] as PlanPhase).to_dict())
	plan.phase(1).target_pct = 10.0
	assert_eq((r["phases"][1] as PlanPhase).target_pct, 90.0, "copies, not the result's objects")
	assert_eq(WorkoutImport.to_plan(WorkoutImport.parse_zwo("nope")).size(), 0)


func test_every_phase_has_a_lap_except_split_tails() -> void:
	for f in ["all_tags.zwo", "no_warmup.zwo", "caps.zwo", "limits_120.zwo", "spacing.zwo"]:
		for p: PlanPhase in _phases(_load(f)):
			assert_true(p.lap, "%s: %s laps" % [f, p.label])


func test_deterministic() -> void:
	var a := _load("real_world.zwo")
	var b := _load("real_world.zwo")
	var da: Array = []
	var db: Array = []
	for p: PlanPhase in a["phases"]:
		da.append(p.to_dict())
	for p: PlanPhase in b["phases"]:
		db.append(p.to_dict())
	assert_eq(JSON.stringify(da), JSON.stringify(db))
	assert_eq(a["clamps"], b["clamps"])
	assert_eq(a["warnings"], b["warnings"])


func test_byte_order_mark_is_ignored() -> void:
	var xml := """<?xml version="1.0" encoding="UTF-8"?><workout_file><name>BOM</name><workout>
		<SteadyState Duration="300" Power="0.6"/></workout></workout_file>"""
	var r := WorkoutImport.parse_zwo(WorkoutImport.BOM + xml)
	assert_true(r["ok"], str(r["error"]))
	assert_eq(r["name"], "BOM")
	assert_eq(_phases(r).size(), 1)


func test_durations_are_whole_seconds() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<SteadyState Duration="299.6" Power="0.5"/>
		<FreeRide Duration="29.999999"/>
		<SteadyState Duration="0.4" Power="0.5"/>
		<IntervalsT Repeat="2" OnDuration="59.5" OffDuration="0.3" OnPower="0.6" OffPower="0.5"/>
		</workout></workout_file>"""
		)
	)
	assert_true(r["ok"], str(r["error"]))
	var lens: Array = []
	for p: PlanPhase in _phases(r):
		lens.append(p.duration_s)
	assert_eq(lens, [300.0, 30.0, 60.0, 60.0], "rounded; a 0.3 s OffDuration means no off phases")
	assert_eq((r["clamps"] as Array).size(), 0, "29.999999 s is a 30 s free ride, no spacing clamp")
	var w: Array = r["warnings"]
	assert_eq(w.size(), 1, "%s" % [w])
	assert_string_contains(str(w[0]), "Block 3: <SteadyState> has no valid duration")
	assert_eq(float(r["blocks"][0]["duration_s"]), 300.0)


func test_repeat_is_limited() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<SteadyState Duration="300" Power="0.5"/>
		<IntervalsT Repeat="100000" OnDuration="10" OffDuration="10" OnPower="0.6" OffPower="0.5"/>
		</workout></workout_file>"""
		)
	)
	assert_true(r["ok"], str(r["error"]))
	assert_eq(int(r["blocks"][1]["repeat"]), WorkoutImport.MAX_REPEAT)
	assert_eq(_phases(r).size(), 1 + 2 * WorkoutImport.MAX_REPEAT)
	var w: Array = r["warnings"]
	assert_eq(w.size(), 1, "%s" % [w])
	assert_string_contains(str(w[0]), "Block 2: Repeat 100000 was limited to 200")
	var exact := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<IntervalsT Repeat="200.9" OnDuration="10" OffDuration="10" OnPower="0.6" OffPower="0.5"/>
		</workout></workout_file>"""
		)
	)
	assert_eq(int(exact["blocks"][0]["repeat"]), 200)
	assert_eq((exact["warnings"] as Array).size(), 0, "200 itself is allowed")


func test_workouts_longer_than_a_day_are_rejected() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<SteadyState Duration="86401" Power="0.5"/></workout></workout_file>"""
		)
	)
	assert_false(r["ok"])
	assert_string_contains(str(r["error"]), "longer than 24 hours")
	assert_eq(_phases(r).size(), 0)
	var day := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<IntervalsT Repeat="144" OnDuration="300" OffDuration="300" OnPower="0.6" OffPower="0.5"/>
		</workout></workout_file>"""
		)
	)
	assert_true(day["ok"], "exactly 24 h is accepted")
	assert_almost_eq(float(day["total_s"]), WorkoutImport.MAX_TOTAL_S, EPS)


func test_split_block_keeps_the_long_phase_cap() -> void:
	# A 600 s Warmup ramp 30 -> 120%: split at 300 s (75%), the first part clamped to 65%; the
	# second part is only 300 s long, but its block is 600 s, so it caps at 105%.
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><workout>
		<Warmup Duration="600" PowerLow="0.30" PowerHigh="1.20"/>
		<SteadyState Duration="120" Power="0.5"/>
		</workout></workout_file>"""
		)
	)
	assert_true(r["ok"], str(r["error"]))
	assert_false(r["prefix_inserted"])
	var ph := _phases(r)
	assert_eq(ph.size(), 3)
	_assert_erg(ph[0], Wl.WARMUP, 30.0, 65.0, 300.0, true, "inside the warm-up")
	_assert_erg(ph[1], Wl.WARMUP, 75.0, 105.0, 300.0, false, "the block's second half")
	assert_eq(
		_rules(r),
		[WorkoutImport.RULE_WARMUP_SPLIT, WorkoutImport.RULE_WARMUP, WorkoutImport.RULE_LONG_PHASE]
	)
	var rec: Dictionary = (r["clamp_records"] as Array)[2]
	assert_eq(rec["phase"], 1)
	assert_eq(rec["from_pct"], [75.0, 120.0])
	assert_eq(rec["to_pct"], [75.0, 105.0])
	_assert_plan_safe(ph, "split_long")


func test_random_workouts_always_import_safely() -> void:
	# Seeded random .zwo files with every tag, powers 20-180% and lengths 5-900 s: each must
	# import (ok), satisfy the PlanValidator's rules, never make a block harder, keep laps and
	# be deterministic.
	var rng := SeededRng.make(20261021)
	var clamped := 0
	for n in 300:
		var xml := _random_zwo(rng)
		var r := WorkoutImport.parse_zwo(xml)
		var what := "random %d" % n
		assert_true(r["ok"], "%s: %s" % [what, r["error"]])
		if not bool(r["ok"]):
			continue
		var ph := _phases(r)
		_assert_plan_safe(ph, what)
		var total := 0.0
		for p: PlanPhase in ph:
			total += p.duration_s
		assert_almost_eq(float(r["total_s"]), total, EPS, what + ": total_s")
		_assert_never_harder(r, what)
		for i in ph.size():
			var p: PlanPhase = ph[i]
			assert_false(p.label.is_empty() or p.label.begins_with("SIM_ZWO_"), what + ": label")
			if not p.lap:
				var prev: PlanPhase = ph[i - 1] if i > 0 else null
				assert_true(
					prev != null and prev.meta.get("zwo_block") == p.meta.get("zwo_block"),
					what + ": only a split part continues its block's lap"
				)
		var again := WorkoutImport.parse_zwo(xml)
		assert_eq(_dicts(_phases(again)), _dicts(ph), what + ": deterministic")
		assert_eq(again["clamps"], r["clamps"], what + ": same clamps")
		if not (r["clamps"] as Array).is_empty():
			clamped += 1
	assert_gt(clamped, 100, "the sweep exercises the clamps")


func test_imported_plans_pass_the_plan_validator() -> void:
	# Becomes active once sdk-runtime's PlanValidator replaces the W0 stub (BRIEF 3.7: the
	# importer clamps, the validator only accepts or rejects): every fixture and random
	# workout must validate with no error and no warning.
	var probe := PlanValidator.validate(EffortPlan.of([PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "w")]))
	if (probe["errors"] as Array).has("not implemented"):
		pending("PlanValidator is still the W0 stub in this worktree")
		return
	var results: Array = []
	for f in [
		"all_tags.zwo",
		"caps.zwo",
		"easy_start.zwo",
		"limits_105.zwo",
		"limits_120.zwo",
		"no_warmup.zwo",
		"real_world.zwo",
		"spacing.zwo",
		"warmup_clamp.zwo",
		"warmup_split.zwo"
	]:
		results.append([f, _load(f)])
	var rng := SeededRng.make(7)
	for n in 100:
		results.append(["random %d" % n, WorkoutImport.parse_zwo(_random_zwo(rng))])
	for item: Array in results:
		var r: Dictionary = item[1]
		assert_true(r["ok"], str(item[0]))
		var v := PlanValidator.validate(WorkoutImport.to_plan(r))
		assert_true(v["ok"], "%s: %s" % [item[0], v["errors"]])
		assert_eq((v["warnings"] as Array).size(), 0, "%s: %s" % [item[0], v["warnings"]])
		var fin := PlanValidator.finalize(WorkoutImport.to_plan(r))
		assert_not_null(fin, str(item[0]))
		if fin != null:
			assert_true(fin.cooldown_appended)
			assert_eq(fin.size(), (r["phases"] as Array).size() + 1, "only the cool-down added")


func _dicts(phases: Array) -> String:
	var out: Array = []
	for p: PlanPhase in phases:
		out.append(p.to_dict())
	return JSON.stringify(out)


## A random .zwo with 1-10 blocks; the first one is always supported.
func _random_zwo(rng: RandomNumberGenerator) -> String:
	var lines: Array[String] = []
	var count := SeededRng.range_i(rng, 1, 10)
	for i in count:
		var pick := SeededRng.range_i(rng, 0, 5 if i == 0 else 6)
		var d := SeededRng.range_i(rng, 5, 900)
		var a := SeededRng.range_f(rng, 0.2, 1.8)
		var b := SeededRng.range_f(rng, 0.2, 1.8)
		match pick:
			0:
				lines.append('<SteadyState Duration="%d" Power="%.2f"/>' % [d, a])
			1:
				lines.append(
					(
						'<Warmup Duration="%d" PowerLow="%.2f" PowerHigh="%.2f"/>'
						% [d, minf(a, b), maxf(a, b)]
					)
				)
			2:
				lines.append('<Ramp Duration="%d" PowerLow="%.2f" PowerHigh="%.2f"/>' % [d, a, b])
			3:
				lines.append(
					(
						'<Cooldown Duration="%d" PowerLow="%.2f" PowerHigh="%.2f"/>'
						% [d, maxf(a, b), minf(a, b)]
					)
				)
			4:
				(
					lines
					. append(
						(
							'<IntervalsT Repeat="%d" OnDuration="%d" OffDuration="%d" OnPower="%.2f" OffPower="%.2f"/>'
							% [
								SeededRng.range_i(rng, 1, 8),
								SeededRng.range_i(rng, 5, 300),
								SeededRng.range_i(rng, 0, 300),
								a,
								b
							]
						)
					)
				)
			5:
				lines.append('<FreeRide Duration="%d"/>' % SeededRng.range_i(rng, 5, 400))
			_:
				lines.append('<MaxEffort Duration="%d"/>' % d)
	return (
		"<workout_file><name>Random</name><workout>\n%s\n</workout></workout_file>"
		% "\n".join(lines)
	)


## No ERG phase is above its block's own highest value (the importer only lowers targets).
func _assert_never_harder(r: Dictionary, what: String) -> void:
	var raw_peak := {}
	for b: Dictionary in r["blocks"]:
		var peak := maxf(float(b["power_lo"]), float(b["power_hi"]))
		if str(b["tag"]) == WorkoutImport.TAG_INTERVALS:
			peak = maxf(float(b["on_power"]), float(b["off_power"]))
		raw_peak[int(b["index"])] = roundf(peak * 10000.0) / 100.0
	for p: PlanPhase in r["phases"]:
		var block := int(p.meta.get("zwo_block", -1))
		if p.mode != Wl.ERG:
			continue
		if block == 0:
			assert_true(p.peak_pct() <= WorkoutImport.PREFIX_TO_PCT + EPS, what + ": prefix")
			continue
		assert_true(raw_peak.has(block), "%s: phase points at block %d" % [what, block])
		assert_true(
			p.peak_pct() <= float(raw_peak.get(block, 0.0)) + EPS,
			(
				"%s: block %d %.2f <= %.2f"
				% [what, block, p.peak_pct(), float(raw_peak.get(block, 0.0))]
			)
		)


func test_non_bike_sport_type_warns() -> void:
	var r := (
		WorkoutImport
		. parse_zwo(
			"""<workout_file><sportType>run</sportType><workout>
		<SteadyState Duration="300" Power="0.6"/></workout></workout_file>"""
		)
	)
	assert_true(r["ok"])
	assert_eq((r["warnings"] as Array).size(), 1)
	assert_string_contains(str(r["warnings"][0]), '"run"')
