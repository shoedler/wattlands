extends GutTest
## SiegeEvents (brief 2.6): every builder carries its declared fields, ints survive the wire,
## check() catches what is missing, the shot event's quantization.


func _all() -> Array[Dictionary]:
	return [
		SiegeEvents.wave_start(2, SiegeIds.ROLE_WAVE, 1, 3, 180.4),
		SiegeEvents.wave_end(2, 1, 72.2, 130.0, 4),
		SiegeEvents.rush(true, 0),
		SiegeEvents.push(17, SiegeIds.ENEMY_RAM, 183.42),
		SiegeEvents.dock(18),
		SiegeEvents.shot(
			100, 2, SiegeIds.SHOT_STONE, [100, 200, 1720], [5000, -3000, 16000], 1, 99
		),
		SiegeEvents.kill(5, SiegeIds.ENEMY_SPEAR, 3, false),
		SiegeEvents.leak(6, SiegeIds.ENEMY_SHIELD, 6),
		SiegeEvents.breach(1),
		SiegeEvents.gate_restored(30.0),
		SiegeEvents.buy(0, SiegeIds.ITEM_UPGRADE, 2, 0, true, "", 1),
		SiegeEvents.route(1, 3),
		SiegeEvents.overdrive(0, SiegeIds.OD_EV_START),
	]


func test_every_event_type_has_a_builder_that_checks() -> void:
	var types: Array[String] = []
	for e in _all():
		assert_eq(SiegeEvents.check(e), "", str(e))
		types.append(str(e["type"]))
	assert_eq(types, SiegeIds.EVENT_TYPES)


func test_int_fields_cover_every_type_and_the_snapshot() -> void:
	var f := SiegeEvents.int_fields()
	for t in SiegeIds.EVENT_TYPES:
		assert_true(f.has(t), t)
	assert_eq(f["snapshot"], SiegeSnapshotSchema.INT_PATHS)
	assert_eq(f[SiegeIds.EV_SHOT], ["tk", "src", "kind", "o[]", "v[]", "n", "sd"])


func test_cast_turns_json_floats_back_into_ints() -> void:
	for e in _all():
		var wire: Dictionary = JSON.parse_string(JSON.stringify(e))
		var back := SiegeEvents.cast(wire)
		for path: String in SiegeEvents.INT_FIELDS[str(e["type"])]:
			var key := path.trim_suffix("[]")
			if back[key] is Array:
				for v: Variant in back[key]:
					assert_typeof(v, TYPE_INT)
			else:
				assert_typeof(back[key], TYPE_INT)
		assert_eq(back, e, str(e["type"]))


func test_check_reports_missing_fields_and_unknown_types() -> void:
	assert_true(SiegeEvents.check({"type": "roads"}).begins_with("unknown"))
	assert_true(SiegeEvents.check({"type": "dock"}).contains("missing id"))
	var buy := SiegeEvents.buy(0, "mine", 0, 0, true, "", 1)
	buy["item"] = 3
	assert_ne(SiegeEvents.check(buy), "")
	var shot := SiegeEvents.shot(1, 1, 0, [1, 2, 3], [4, 5, 6], 1, 7)
	shot["o"] = [1, 2]
	assert_true(SiegeEvents.check(shot).contains("o needs 3"))


func test_wave_start_carries_no_roads() -> void:
	var e := SiegeEvents.wave_start(0, SiegeIds.ROLE_WARMUP_WAVE, 0, 3, 81.6)
	assert_false(e.has("roads"))
	assert_eq(e["b"], 82, "the budget rounded")


func test_wave_end_rounds_the_gate() -> void:
	var e := SiegeEvents.wave_end(4, 2, 71.2, 155.0, 3)
	assert_eq(e["hp"], 72, "ceil")
	assert_eq(e["max"], 155)


func test_push_carries_the_engine_and_its_entry() -> void:
	var e := SiegeEvents.push(9, SiegeIds.ENEMY_TOWER, 255.06)
	assert_eq(e, {"type": "push", "id": 9, "et": 5, "prog_dm": 2551})


func test_kill_carries_its_source_and_the_double() -> void:
	assert_eq(
		SiegeEvents.kill(1, 4, 12, true), {"type": "kill", "id": 1, "et": 4, "src": 12, "x2": 1}
	)


func test_buy_carries_station_and_pad_and_zeroes_a_refused_level() -> void:
	var ok := SiegeEvents.buy(1, SiegeIds.ITEM_PAD_UPGRADE, 0, 3, true, "", 2)
	assert_eq(ok["pad"], 3)
	assert_eq(ok["station"], 0)
	assert_eq(ok["lvl"], 2)
	var no := SiegeEvents.buy(1, SiegeIds.ITEM_UPGRADE, 4, 0, false, SiegeIds.BUY_FUNDS, 2)
	assert_eq(no["ok"], 0)
	assert_eq(no["lvl"], 0)
	assert_eq(no["why"], "funds")


func test_shot_quantizes_origin_in_cm_and_velocity_in_mm_per_s() -> void:
	assert_eq(SiegeEvents.quantize_o(Vector3(1.234, -0.006, 17.2)), [123, -1, 1720])
	assert_eq(SiegeEvents.quantize_v(Vector3(12.3456, 0.0004, -9.81)), [12346, 0, -9810])
	var e := SiegeEvents.shot(5, 1, 0, [123, -1, 1720], [12346, 0, -9810], 1, 42)
	assert_eq(SiegeEvents.shot_origin(e), Vector3(1.23, -0.01, 17.2))
	assert_true(SiegeEvents.shot_velocity(e).is_equal_approx(Vector3(12.346, 0.0, -9.81)))


func test_the_shot_event_survives_json_exactly() -> void:
	var e := SiegeEvents.shot(77, 13, SiegeIds.SHOT_SCORPION, [1, 2, 3], [-4, 5, -6], 2, 2147483000)
	var back := SiegeEvents.cast(JSON.parse_string(JSON.stringify(e)))
	assert_eq(back, e)
	assert_eq(SiegeEvents.shot_origin(back), SiegeEvents.shot_origin(e))
	assert_eq(SiegeEvents.shot_velocity(back), SiegeEvents.shot_velocity(e))


func test_overdrive_events_carry_why_as_a_string() -> void:
	var e := SiegeEvents.overdrive(2, SiegeIds.OD_EV_REFUSED, false, "switch_spacing")
	assert_eq(e["why"], "switch_spacing")
	assert_eq(SiegeEvents.check(e), "")
