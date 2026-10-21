extends GutTest
## TemplateRules: the template's pure rules (BRIEF 3.6, step(state, inputs, dt)).

const DT := Wl.SIM_DT


func _content() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/_template/default.json"))


func _state(peers: Array[int] = [1, 2]) -> Dictionary:
	return TemplateRules.new_state(_content(), peers, 400.0)


func _steps(state: Dictionary, inputs: Dictionary, n: int) -> Array:
	var events: Array = []
	for _i in n:
		events.append_array(TemplateRules.step(state, inputs, DT))
	return events


func test_new_state_has_one_rider_per_peer_in_slot_order() -> void:
	var s := _state([1, 2, -1])
	assert_eq(s["riders"].size(), 3)
	assert_eq(s["riders"][2]["peer"], -1)
	assert_eq(s["riders"][2]["slot"], 2)
	assert_eq(s["tick"], 0)
	assert_eq(s["track_m"], 400.0)


func test_speed_is_proportional_to_p_eff_and_boost_multiplies_it() -> void:
	var s := _state()
	var mps := float(_content()["mps_per_w"])
	assert_almost_eq(TemplateRules.speed(s, 250.0, false), 250.0 * mps, 1e-9)
	assert_almost_eq(TemplateRules.speed(s, 125.0, false), 125.0 * mps, 1e-9)
	assert_almost_eq(TemplateRules.speed(s, 250.0, true), 250.0 * mps * float(_content()["boost_mult"]), 1e-9)
	assert_eq(TemplateRules.speed(s, -50.0, false), 0.0, "negative P_eff never moves a marker backwards")


func test_step_integrates_distance_and_counts_ticks() -> void:
	var s := _state()
	_steps(s, {1: {"p_eff_w": 250.0}, 2: {"p_eff_w": 0.0}}, 20)
	assert_eq(s["tick"], 20)
	assert_almost_eq(float(s["riders"][0]["dist_m"]), 250.0 * float(_content()["mps_per_w"]), 1e-6, "1 s at 250 W")
	assert_eq(float(s["riders"][1]["dist_m"]), 0.0)


func test_boost_starts_once_lasts_boost_s_and_can_restart_after() -> void:
	var s := _state()
	var boost_ticks := roundi(float(_content()["boost_s"]) / DT)
	var events := _steps(s, {1: {"p_eff_w": 100.0, "boost": true}}, boost_ticks)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e["type"] == "boost").size(), 1)
	assert_eq(events[0], {"type": "boost", "slot": 0})
	assert_almost_eq(float(s["riders"][0]["boost_s"]), 0.0, 1e-6)
	var again := TemplateRules.step(s, {1: {"p_eff_w": 100.0, "boost": true}}, DT)
	assert_eq(again.size(), 1, "a new boost once the last one ran out")


func test_boost_moves_the_marker_faster() -> void:
	var a := _state()
	var b := _state()
	_steps(a, {1: {"p_eff_w": 200.0}}, 40)
	_steps(b, {1: {"p_eff_w": 200.0, "boost": true}}, 40)
	assert_gt(float(b["riders"][0]["dist_m"]), float(a["riders"][0]["dist_m"]))


func test_rescue_and_afk_stop_the_marker_without_losing_progress() -> void:
	var s := _state()
	_steps(s, {1: {"p_eff_w": 250.0}, 2: {"p_eff_w": 250.0}}, 20)
	var before0 := float(s["riders"][0]["dist_m"])
	var before1 := float(s["riders"][1]["dist_m"])
	s["riders"][0]["rescue"] = true
	s["riders"][1]["afk"] = true
	_steps(s, {1: {"p_eff_w": 250.0}, 2: {"p_eff_w": 250.0}}, 20)
	assert_eq(float(s["riders"][0]["dist_m"]), before0)
	assert_eq(float(s["riders"][1]["dist_m"]), before1)
	s["riders"][0]["rescue"] = false
	_steps(s, {1: {"p_eff_w": 250.0}}, 1)
	assert_gt(float(s["riders"][0]["dist_m"]), before0)


func test_a_lap_event_each_time_the_marker_passes_the_track_length() -> void:
	var s := _state([1])
	s["riders"][0]["dist_m"] = 399.9
	var events := TemplateRules.step(s, {1: {"p_eff_w": 250.0}}, DT)
	assert_eq(events, [{"type": "lap", "slot": 0, "laps": 1}])
	assert_eq(s["riders"][0]["laps"], 1)
	s["riders"][0]["dist_m"] = 799.95
	events = TemplateRules.step(s, {1: {"p_eff_w": 250.0}}, DT)
	assert_eq(events, [{"type": "lap", "slot": 0, "laps": 2}])


func test_same_inputs_give_the_same_state() -> void:
	var a := _state([1, 2, -1])
	var b := _state([1, 2, -1])
	var inputs := {1: {"p_eff_w": 210.0, "boost": true}, 2: {"p_eff_w": 180.0}, -1: {"p_eff_w": 250.0}}
	var ea := _steps(a, inputs, 600)
	var eb := _steps(b, inputs, 600)
	assert_eq(JSON.stringify(a), JSON.stringify(b))
	assert_eq(JSON.stringify(ea), JSON.stringify(eb))


func test_content_error_names_the_problem() -> void:
	assert_eq(TemplateRules.content_error(_content()), "")
	for bad: Variant in [[], null, "text", {}, {"phases": {}}]:
		assert_string_contains(TemplateRules.content_error(bad), "\"phases\"")
	var c := _content()
	c.erase("boost_s")
	assert_string_contains(TemplateRules.content_error(c), "boost_s")
	c = _content()
	c["phases"] = []
	assert_string_contains(TemplateRules.content_error(c), "phases")
	for k: String in ["nudge_pct", "mps_per_w"]:
		for v: Variant in ["fast", -1.0, [5], true]:
			c = _content()
			c[k] = v
			assert_string_contains(TemplateRules.content_error(c), "\"%s\" must be a number" % k)
	c = _content()
	c["boost_s"] = 5  # an int, as a GDScript-built dictionary has it
	assert_eq(TemplateRules.content_error(c), "")


func test_content_error_checks_every_phase() -> void:
	var good := {"kind": "WORK", "target_pct": 75.0, "duration_s": 180.0, "label": "_TEMPLATE_PHASE_WORK"}
	var breaks := {
		"kind": ["COOLDOWN", "SPRINT", null], "target_pct": [null, "high", [75]], "duration_s": [0.0, -5.0, null, "x"],
		"label": [null, 5], "ramp_to_pct": ["up", [65]],
	}
	for field: String in breaks:
		for v: Variant in breaks[field]:
			var broken := _content()
			var ph := good.duplicate()
			if v == null:
				ph.erase(field)
			else:
				ph[field] = v
			(broken["phases"] as Array).append(ph)
			var err := TemplateRules.content_error(broken)
			assert_true(err.begins_with("bad phase"), "%s = %s: %s" % [field, v, err])
	var c := _content()
	(c["phases"] as Array).append(good)
	(c["phases"] as Array).append("not a phase")
	assert_string_contains(TemplateRules.content_error(c), "bad phase \"not a phase\"")
	c = _content()
	(c["phases"] as Array).append(good.merged({"ramp_to_pct": 80.0}))
	assert_eq(TemplateRules.content_error(c), "", "a ramp is optional")


func test_rider_lookup_by_peer_and_by_slot() -> void:
	var s := _state([1, 2, -1])
	assert_eq(TemplateRules.rider(s, 2)["slot"], 1)
	assert_eq(TemplateRules.rider(s, -1)["slot"], 2)
	assert_eq(TemplateRules.rider(s, null, 0)["peer"], 1)
	assert_eq(TemplateRules.rider(s, 99), {})
	assert_eq(TemplateRules.rider(s, null, 7), {})
	assert_eq(TemplateRules.rider({}, 1), {})
