extends GutTest
## Wl (BRIEF 3.6, 3.9, 4.6): slot looks, phase kinds and the string constants games and
## reports rely on.


func test_slot_look_first_four() -> void:
	var names := ["red", "blue", "yellow", "green"]
	var shapes := ["circle", "triangle", "square", "diamond"]
	var patterns := ["solid", "dashed", "dotted", "double"]
	for i in 4:
		var look := Wl.slot_look(i)
		assert_eq(look["color"], Wl.SLOT_COLORS[i], "slot %d" % i)
		assert_eq(look["color_name"], names[i])
		assert_eq(look["shape"], shapes[i])
		assert_eq(look["pattern"], patterns[i])
		assert_false(look["hollow"], "slot %d is filled" % i)


func test_slot_look_4_to_7_repeat_hollow() -> void:
	for i in range(4, 8):
		var look := Wl.slot_look(i)
		var base := Wl.slot_look(i - 4)
		assert_eq(look["color"], base["color"])
		assert_eq(look["shape"], base["shape"])
		assert_eq(look["pattern"], base["pattern"])
		assert_true(look["hollow"], "slot %d is hollow" % i)


func test_slot_looks_are_distinct() -> void:
	var seen := {}
	for i in Wl.MAX_SLOTS:
		var look := Wl.slot_look(i)
		var key := "%s/%s/%s/%s" % [look["color_name"], look["shape"], look["pattern"], look["hollow"]]
		assert_false(seen.has(key), "slot %d duplicates %s" % [i, key])
		seen[key] = true
	assert_eq(seen.size(), 8)


func test_okabe_ito_colors() -> void:
	assert_eq(Wl.SLOT_COLORS[0], Color("#D55E00"))
	assert_eq(Wl.SLOT_COLORS[1], Color("#0072B2"))
	assert_eq(Wl.SLOT_COLORS[2], Color("#F0E442"))
	assert_eq(Wl.SLOT_COLORS[3], Color("#009E73"))


func test_slot_look_wraps() -> void:
	assert_eq(Wl.slot_look(8), Wl.slot_look(0))
	assert_eq(Wl.slot_look(-1)["shape"], "diamond")


func test_phase_kinds() -> void:
	for k in [Wl.WARMUP, Wl.WORK, Wl.RECOVERY, Wl.FREE, Wl.COOLDOWN]:
		assert_true(Wl.is_phase_kind(k), k)
	assert_false(Wl.is_phase_kind("SPRINT"))
	assert_false(Wl.is_phase_kind("work"))


func test_timing_constants() -> void:
	assert_eq(Wl.SIM_DT, 0.05)
	assert_eq(Wl.SIM_HZ, 20)
	assert_almost_eq(1.0 / Wl.SIM_DT, float(Wl.SIM_HZ), 1e-9)
	assert_eq(Wl.SNAPSHOT_HZ, 10)
	assert_eq(Wl.TELEMETRY_HZ, 5)
	assert_eq(Wl.ROSTER_HZ, 2)
	assert_eq(Wl.MAX_SLOTS, 8)
	assert_eq(Wl.ALL_PEERS, 0)
	assert_eq(Wl.HOST_PEER, 1)


func test_string_constants_survive_json() -> void:
	var d := {"kind": Wl.WARMUP, "mode": Wl.SIM, "role": Wl.HOST, "scaling": Wl.WKG}
	var back: Variant = JSON.parse_string(JSON.stringify(d))
	assert_eq(back, d)


func test_rule_names() -> void:
	assert_eq(Wl.CLAMP_HAPTIC_INTENSITY, "haptic_intensity")
	assert_eq(Wl.REFUSE_ERG_IN_SIM, "erg_in_sim_phase")
	assert_eq(Wl.REFUSE_NOT_GAME_GRADE, "grade_source_not_game")
	assert_eq(Wl.REFUSE_SIM_BLOCK_UNSAFE, "sim_block_unsafe")
	var clamps := [Wl.CLAMP_UNVERIFIED, Wl.CLAMP_CEILING, Wl.CLAMP_LONG_PHASE, Wl.CLAMP_LIMIT_105,
		Wl.CLAMP_LIMIT_120, Wl.CLAMP_WARMUP, Wl.CLAMP_FLOOR, Wl.CLAMP_RESCUE, Wl.CLAMP_COASTING,
		Wl.CLAMP_SLEW, Wl.CLAMP_SWITCH, Wl.CLAMP_PANIC, Wl.CLAMP_GRADE_RANGE, Wl.CLAMP_GRADE_LIMIT,
		Wl.CLAMP_HAPTIC, Wl.CLAMP_HAPTIC_INTENSITY, Wl.CLAMP_FACTOR, Wl.CLAMP_PAUSE]
	var refusals := [Wl.REFUSE_NO_PHASE, Wl.REFUSE_COOLDOWN, Wl.REFUSE_RANGE,
		Wl.REFUSE_SIM_BLOCK_LENGTH, Wl.REFUSE_SWITCH_SPACING, Wl.REFUSE_MODE_GRADE,
		Wl.REFUSE_HAPTIC_ERG, Wl.REFUSE_HAPTIC_OFF, Wl.REFUSE_HAPTIC_WARMUP,
		Wl.REFUSE_HAPTIC_COOLDOWN, Wl.REFUSE_BAD_FIELDS, Wl.REFUSE_UNKNOWN_PEER,
		Wl.REFUSE_NOT_OPEN_ENDED, Wl.REFUSE_MIN_S, Wl.REFUSE_PLAN_INVALID, Wl.REFUSE_NOT_AUTHORITY,
		Wl.REFUSE_ERG_IN_SIM, Wl.REFUSE_NOT_GAME_GRADE, Wl.REFUSE_SIM_BLOCK_UNSAFE]
	_assert_unique(clamps, "clamp rule names")
	_assert_unique(refusals, "refusal reasons")


func _assert_unique(names: Array, what: String) -> void:
	var seen := {}
	for n in names:
		assert_false(seen.has(n), "%s: %s repeats" % [what, n])
		seen[n] = true


func test_actions_and_gestures() -> void:
	assert_eq(Wl.ACTIONS.size(), 14)
	assert_has(Wl.ACTIONS, &"panic")
	assert_eq(Wl.GESTURES, [&"pedal_start", &"surge", &"coast", &"stop_5s"])
