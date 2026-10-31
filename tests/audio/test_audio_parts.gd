extends GutTest
## The kit's pure parts (SPEC_AUDIO 1.2): CadenceVoice's events, AudioCurve, LayeredLoop, AmbienceBed, LiftOffDetector.

const DT := 1.0 / 60.0


func test_voice_events_carry_level_pitch_and_priority() -> void:
	var voice := (
		CadenceVoice
		. new(
			[
				{
					"at": [0.5],
					"sound": "s",
					"db": -3.0,
					"db_by": [{"param": "power", "points": [[0, -9], [1, 0]]}],
					"pitch_by": [{"param": "rpm", "ratio": 120}],
					"priority": 7,
				}
			]
		)
	)
	voice.plan(0.0, 60.0, 0.0, {}, true)
	var events := voice.plan(0.49, 60.0, 0.025, {"power": 0.5, "rpm": 60.0}, true)
	assert_eq(events.size(), 1)
	var ev := events[0]
	assert_eq(ev["sound"], "s")
	assert_eq(ev["priority"], 7)
	assert_almost_eq(float(ev["db"]), -7.5, 1e-6)
	assert_almost_eq(float(ev["pitch"]), 0.5, 1e-6)
	assert_almost_eq(float(ev["at_s"]), 0.01, 1e-6)
	assert_almost_eq(float(ev["pos"]), 0.5, 1e-9)


func test_voice_sorts_a_block_by_at() -> void:
	var voice := CadenceVoice.new([{"at": [0.75, 0.25], "sound": "s"}])
	voice.plan(0.0, 60.0, 0.0, {}, true)
	var events := voice.plan(0.0, 60.0, 1.0, {}, true)
	assert_eq(events.size(), 2)
	assert_almost_eq(float(events[0]["pos"]), 0.25, 1e-9)
	assert_almost_eq(float(events[1]["pos"]), 0.75, 1e-9)


func test_voice_round_robin_per_sound_and_pitch_table_cycle() -> void:
	var voice := (
		CadenceVoice
		. new(
			[
				{"at": [0.0, 0.25], "sound": "a", "pitch_table": [0.0, 0.1]},
				{"at": [0.5], "sound": "b"},
			]
		)
	)
	voice.plan(-0.5, 60.0, 0.0, {}, true)
	var events := voice.plan(-0.5, 60.0, 2.0, {}, true)
	var a_variants: Array[int] = []
	var b_variants: Array[int] = []
	var pitches: Array[float] = []
	for ev: Dictionary in events:
		if ev["sound"] == "a":
			a_variants.append(ev["variant"])
			pitches.append(snappedf(float(ev["pitch"]), 0.001))
		else:
			b_variants.append(ev["variant"])
	assert_eq(a_variants, [0, 1, 2, 3] as Array[int], "each sound has its own count")
	assert_eq(b_variants, [0, 1] as Array[int])
	assert_eq(pitches, [1.0, 1.1, 1.0, 1.1] as Array[float], "no RNG: the table cycles by firing")


func test_voice_gates_when_and_lead_only_and_counts_them() -> void:
	var voice := (
		CadenceVoice
		. new(
			[
				{"at": [0.25], "sound": "gated", "when": {"param": "power", "min": 0.5}},
				{"at": [0.5], "sound": "own", "lead_only": true},
				{"at": [0.75], "sound": "all"},
			]
		)
	)
	voice.plan(0.0, 60.0, 0.0, {}, false)
	var events := voice.plan(0.0, 60.0, 0.9, {"power": 0.1}, false)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["sound"], "all")
	assert_eq(voice.fired, 1)
	assert_eq(voice.gated, 2, "S2: fired + dropped + gated covers the walk")


func test_curve_points_clamp_and_interpolate() -> void:
	var c := {"param": "x", "points": [[0, -10], [1, 0], [2, 4]]}
	assert_almost_eq(AudioCurve.eval(c, {"x": -1.0}), -10.0, 1e-6)
	assert_almost_eq(AudioCurve.eval(c, {"x": 0.5}), -5.0, 1e-6)
	assert_almost_eq(AudioCurve.eval(c, {"x": 1.5}), 2.0, 1e-6)
	assert_almost_eq(AudioCurve.eval(c, {"x": 9.0}), 4.0, 1e-6)
	assert_almost_eq(AudioCurve.eval(c, {}), -10.0, 1e-6, "a missing param reads 0")


func test_curve_ratio() -> void:
	assert_almost_eq(AudioCurve.eval({"param": "rpm", "ratio": 110}, {"rpm": 55.0}), 0.5, 1e-6)
	assert_eq(AudioCurve.eval({"param": "rpm", "ratio": 110}, {}), 0.0)


func test_curve_sum_and_product() -> void:
	var a := {"param": "x", "ratio": 1}
	var b := {"param": "y", "ratio": 1}
	var params := {"x": 2.0, "y": 3.0}
	assert_almost_eq(AudioCurve.sum_db([a, b], params), 5.0, 1e-6)
	assert_eq(AudioCurve.sum_db([], params), 0.0)
	assert_almost_eq(AudioCurve.product([a, b], params), 6.0, 1e-6)
	assert_eq(AudioCurve.product([], params), 1.0)


func test_curve_passes() -> void:
	assert_true(AudioCurve.passes({}, {}))
	var band := {"param": "x", "min": 1.0, "max": 2.0}
	assert_false(AudioCurve.passes(band, {"x": 0.5}))
	assert_true(AudioCurve.passes(band, {"x": 1.0}))
	assert_true(AudioCurve.passes(band, {"x": 2.0}))
	assert_false(AudioCurve.passes(band, {"x": 2.5}))
	assert_false(AudioCurve.passes({"param": "x", "min": 0.1}, {}), "a missing param reads 0")


func _loop(extra: Dictionary = {}) -> LayeredLoop:
	var layer := {"sound": "b", "db": -6.0, "pitch_by": [{"param": "rpm", "ratio": 100}]}
	layer.merge(extra, true)
	return LayeredLoop.new([layer])


func test_loop_opens_and_a_new_layer_takes_its_pitch_at_once() -> void:
	var loop := _loop()
	assert_eq(loop.count, 1)
	assert_eq(loop.on[0], 0)
	loop.update({"rpm": 150.0}, 0.0, true, DT)
	assert_eq(loop.on[0], 1)
	assert_almost_eq(loop.pitch[0], 1.5, 1e-5, "no slew from off")
	for i in 60:
		loop.update({"rpm": 150.0}, 0.0, true, DT)
	assert_almost_eq(loop.db[0], -6.0, 0.01)


func test_loop_pitch_slews_with_tau() -> void:
	var loop := _loop({"slew_s": 0.25})
	loop.update({"rpm": 100.0}, 0.0, true, DT)
	for i in 15:
		loop.update({"rpm": 200.0}, 0.0, true, DT)
	assert_almost_eq(loop.pitch[0], 2.0 - exp(-1.0), 0.01, "one tau: 63 % of the way")


func test_loop_min_rpm_and_when_close_it_in_time() -> void:
	var loop := _loop({"min_rpm": 8.0})
	for i in 30:
		loop.update({"rpm": 90.0}, 0.0, true, DT)
	var t := 0.0
	while loop.on[0] != 0:
		loop.update({"rpm": 0.0}, 0.0, true, DT)
		t += DT
		assert_lt(t, 1.0, "it closes")
		if t >= 1.0:
			break
	assert_lte(t, 0.12, "closing is linear in dB")
	assert_eq(loop.db[0], LayeredLoop.OFF_DB)
	var gated := _loop({"when": {"param": "power", "min": 0.5}})
	gated.update({"rpm": 90.0, "power": 0.1}, 0.0, true, DT)
	assert_eq(gated.on[0], 0)


func test_loop_non_lead_needs_other() -> void:
	var own := _loop()
	own.update({"rpm": 90.0}, 0.0, false, DT)
	assert_eq(own.on[0], 0, "lead false and other false is off")
	var shared := _loop({"other": true})
	shared.update({"rpm": 90.0}, -10.0, false, DT)
	assert_eq(shared.on[0], 1)
	for i in 60:
		shared.update({"rpm": 90.0}, -10.0, false, DT)
	assert_almost_eq(shared.db[0], -16.0, 0.01, "trim applies")


func test_loop_close_overrides_params() -> void:
	var loop := _loop()
	for i in 10:
		loop.update({"rpm": 90.0}, 0.0, true, DT)
	assert_false(loop.all_off())
	for i in 10:
		loop.close(DT)
	assert_true(loop.all_off())


func _bed_spec() -> Dictionary:
	return {
		"layers": [{"sound": "wind", "db": -20.0}],
		"spots":
		[
			{
				"sound": "c",
				"gap_s": [0.5, 1.0],
				"db": [-30.0, -24.0],
				"pitch": [0.9, 1.1],
				"burst": [2, 3],
				"burst_gap_s": 0.09,
			}
		],
	}


func _bed_run(bed: AmbienceBed, seconds: float, params: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in int(seconds / DT):
		out.append_array(bed.update(params, DT))
	return out


func test_bed_is_seeded() -> void:
	var a := _bed_run(AmbienceBed.new(_bed_spec(), 5), 20.0)
	var b := _bed_run(AmbienceBed.new(_bed_spec(), 5), 20.0)
	var c := _bed_run(AmbienceBed.new(_bed_spec(), 6), 20.0)
	assert_gt(a.size(), 0)
	assert_eq(a, b, "the same seed, the same spots")
	assert_ne(a, c, "another seed, others")


func test_bed_spots_stay_in_range_and_bursts_expand() -> void:
	var spots := _bed_run(AmbienceBed.new(_bed_spec(), 5), 20.0)
	var offset := false
	for s: Dictionary in spots:
		assert_between(float(s["db"]), -30.0, -24.0)
		assert_between(float(s["pitch"]), 0.9, 1.1)
		assert_lte(float(s["at_s"]), AmbienceBed.BURST_MAX_S)
		offset = offset or float(s["at_s"]) > 0.0
	assert_true(offset, "a burst has offsets")


func test_bed_spot_when_gates_and_loops_run() -> void:
	var spec := _bed_spec()
	(spec["spots"][0] as Dictionary)["when"] = {"param": "night", "min": 0.5}
	var bed := AmbienceBed.new(spec, 5)
	assert_eq(_bed_run(bed, 10.0, {"night": 0.0}).size(), 0)
	assert_eq(bed.loops.on[0], 1, "the layers run on")
	assert_gt(_bed_run(bed, 10.0, {"night": 1.0}).size(), 0)


## Split in two by a `when`, one sound keeps one round: no variant twice running at the switch.
func test_bed_sound_split_by_when_keeps_its_round_robin() -> void:
	var spec := {
		"spots":
		[
			{"sound": "a", "gap_s": 1.0, "when": {"param": "x", "max": 0.5}},
			{"sound": "a", "gap_s": 1.0, "when": {"param": "x", "min": 0.5}},
		]
	}
	var bed := AmbienceBed.new(spec, 3)
	var out := _bed_run(bed, 5.0, {"x": 0.0})
	out.append_array(_bed_run(bed, 5.0, {"x": 1.0}))
	assert_gte(out.size(), 8)
	for i in out.size():
		assert_eq(int(out[i]["variant"]), i)


## The bank has no gap_by: a gap that follows speed is one spot per band (hull_slap, SPEC_AUDIO 4.2).
func test_bed_gap_by_speed_is_one_spot_per_band() -> void:
	var spec := {
		"spots":
		[
			{"sound": "slap", "gap_s": 4.0, "when": {"param": "speed", "max": 3.0}},
			{"sound": "slap", "gap_s": 1.0, "when": {"param": "speed", "min": 3.0}},
		]
	}
	var slow := _bed_run(AmbienceBed.new(spec, 5), 40.0, {"speed": 1.0})
	var fast := _bed_run(AmbienceBed.new(spec, 5), 40.0, {"speed": 6.0})
	assert_between(slow.size(), 9, 10, "every 4 s below the band's edge")
	assert_between(fast.size(), 39, 40, "every second above it")


func test_bed_spot_min_gap_keeps_details_apart_and_leaves_a_texture_alone() -> void:
	var spec := {
		"layers": [],
		"spot_min_gap_s": 2.0,
		"spots":
		[
			{"sound": "a", "gap_s": [3.0, 5.0], "burst": 2, "burst_gap_s": 0.7},
			{"sound": "b", "gap_s": [3.0, 5.0]},
			{"sound": "c", "gap_s": [3.0, 5.0]},
			{"sound": "tex", "gap_s": [0.5, 1.0]},
		],
	}
	var bed := AmbienceBed.new(spec, 5)
	var details: Array[Dictionary] = []
	var textures := 0
	for f in 60 * 300:
		for s: Dictionary in bed.update({}, 1.0 / 60.0):
			if s["sound"] == "tex":
				textures += 1
			else:
				details.append({"sound": s["sound"], "t": float(f) / 60.0 + float(s["at_s"])})
	assert_gt(details.size(), 45)
	assert_gt(textures, 300, "a texture keeps its pace")
	details.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["t"] < y["t"])
	for i in range(1, details.size()):
		if details[i]["sound"] != details[i - 1]["sound"]:
			var gap: float = details[i]["t"] - details[i - 1]["t"]
			assert_gte(gap, 2.0 - 1.0 / 60.0, "two details apart at %.2f" % details[i]["t"])


func test_bed_trim_reaches_layers_and_spots() -> void:
	var bed := AmbienceBed.new(_bed_spec(), 5)
	bed.trim_db = -9.0
	var spots := _bed_run(bed, 10.0)
	assert_almost_eq(bed.loops.db[0], -29.0, 0.01)
	for s: Dictionary in spots:
		assert_between(float(s["db"]), -39.0, -33.0)


func test_lift_off_fires_on_a_drop_and_fades() -> void:
	var d := LiftOffDetector.new()
	for i in 120:
		assert_eq(d.update(1.0, DT), 0.0, "steady power")
	assert_eq(d.update(0.7, DT), 1.0, "a fall of 0.25 or more within the window")
	var v := d.update(0.7, 0.4)
	assert_almost_eq(v, 0.5, 1e-6, "linear over HOLD_S")
	assert_eq(d.update(0.7, 0.4), 0.0)
	assert_eq(d.update(0.7, 1.0), 0.0)


func test_lift_off_ignores_a_slow_fall() -> void:
	var d := LiftOffDetector.new()
	var p := 1.2
	for i in 600:
		p -= 0.1 * DT
		assert_eq(d.update(p, DT), 0.0, "0.1 a second is no lift-off")
