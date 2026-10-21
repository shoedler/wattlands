extends "res://tests/governor/gov_test_base.gd"
## OWNERSHIP DS5, GOV10 and Siege S10: a SIM block in an ERG phase (Siege's Overdrive,
## {mode: SIM, duration_s: 30, reason: "overdrive", source: "siege"}) is accepted with no
## dropped channel; its grade is the gear offset clamped to the user range; after 30 s it
## returns to ERG through the ramped entry (min(3 s power, planned target), never below the
## floor, slewing up); it is refused during rescue, coasting, AFK or pause (C26).

const OVERDRIVE := {"mode": "SIM", "duration_s": 30.0, "reason": "overdrive", "source": "siege"}


func _siege_rig(params: Dictionary = {}) -> Rig:
	var dev := ScriptedDevice.new()
	dev.erg_follow = 1.0
	var rig := make_rig(params, dev)
	rig.keep_trace = true
	rig.start([erg(Wl.WORK, 65.0, 900.0, "Wave 1")])
	rig.run(420.0)
	return rig


func test_overdrive_accepted_and_returns_through_the_ramped_entry() -> void:
	var rig := _siege_rig()
	var dev: ScriptedDevice = rig.device
	var t0 := rig.t
	var rec := rig.directive(OVERDRIVE)
	assert_false(rec["refused"])
	assert_eq(rec["reason"], "")
	assert_eq(rec["dropped"], [], "no dropped channel")
	assert_eq(rec["applied"]["sim_block"], true)
	assert_almost_eq(float(rec["applied"]["duration_s"]), 30.0, 1e-9)
	assert_almost_eq(float(rec["applied"]["grade_pct"]), 0.0, 1e-9, "gear 12 adds nothing")
	assert_eq(rec["requested"], OVERDRIVE.merged({}), "exactly the game's keys")
	# The rider sprints at 400 W in SIM.
	dev.erg_follow = -1.0
	dev.power_w = 400.0
	rig.run(40.0)
	# SIM span on the trace: 30 +- 2 s (S10).
	var first_sim := first_where(rig, func(s: Dictionary) -> bool: return float(s["rig_t"]) > t0 and s["mode"] == Wl.SIM)
	var back := first_where(rig, func(s: Dictionary) -> bool:
		return float(s["rig_t"]) > float(first_sim["rig_t"]) and s["mode"] == Wl.ERG)
	var span := float(back["rig_t"]) - float(first_sim["rig_t"])
	assert_almost_eq(span, 30.0, 2.0, "SIM span %.2f s" % span)
	for w in dev.writes_of("erg", t0 + 1.0):
		assert_lte(int(w["w"]), 130, "ERG entered from a sprint never above the planned 130 W")
	assert_eq(rig.applied_w(), 130)


func test_overdrive_grade_is_the_gear_offset_clamped_to_the_user_range() -> void:
	var rig := _siege_rig({"grade_max_pct": 4.0})
	rig.directive(OVERDRIVE)
	for i in 12:
		rig.gov.shift(1)
	assert_eq(rig.gov.gear(), 24)
	rig.run(3.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 4.0, 1e-9, "gear 24 (~+6%) clamped to +4%")
	assert_has(rig.s()["clamped_by"], Wl.CLAMP_GRADE_RANGE)
	rig.gov.shift(-12)
	rig.run(1.0)
	assert_almost_eq(float(rig.s()["applied_grade_pct"]), 0.0, 1e-9)


func test_return_entry_at_3_s_power_when_lower() -> void:
	var rig := _siege_rig()
	var dev: ScriptedDevice = rig.device
	var t0 := rig.t
	rig.directive(OVERDRIVE)
	dev.erg_follow = -1.0
	dev.power_w = 90.0
	rig.run(31.0)
	var ergs := dev.writes_of("erg", t0 + 1.0)
	assert_gt(ergs.size(), 0)
	assert_eq(int(ergs[0]["w"]), 90, "min(3 s power 90 W, planned 130 W)")
	dev.erg_follow = 1.0
	rig.run(5.0)
	assert_eq(rig.applied_w(), 130, "then slews up")


func test_next_overdrive_needs_30_s_after_the_return() -> void:
	var rig := _siege_rig()
	rig.directive(OVERDRIVE)
	rig.run(30.0)
	assert_false(rig.s()["sim_block_active"])
	rig.run(25.0)
	assert_eq(rig.directive(OVERDRIVE)["reason"], Wl.REFUSE_SWITCH_SPACING)
	rig.run(65.0)
	assert_false(rig.directive(OVERDRIVE)["refused"], "Siege's 90 s cooldown is enough")


func test_refused_when_unsafe() -> void:
	var rig := _siege_rig()
	rig.gov.set_game_paused(true)
	assert_eq(rig.directive(OVERDRIVE)["reason"], Wl.REFUSE_SIM_BLOCK_UNSAFE, "paused")
	rig.gov.set_game_paused(false)
	var dev: ScriptedDevice = rig.device
	dev.cadence_rpm = 30.0
	rig.run(5.0)
	assert_true(rig.s()["rescue"])
	assert_eq(rig.directive(OVERDRIVE)["reason"], Wl.REFUSE_SIM_BLOCK_UNSAFE, "rescue")


func test_refused_when_coasting_or_afk() -> void:
	var rig := _siege_rig({"multiplayer": true})
	var dev: ScriptedDevice = rig.device
	dev.erg_follow = -1.0
	dev.power_w = 0.0
	dev.cadence_rpm = 0.0
	rig.run(5.0)
	assert_true(rig.s()["coasting"])
	assert_eq(rig.directive(OVERDRIVE)["reason"], Wl.REFUSE_SIM_BLOCK_UNSAFE, "coasting")
	rig.run(10.0)
	assert_true(rig.s()["afk"])
	assert_eq(rig.directive(OVERDRIVE)["reason"], Wl.REFUSE_SIM_BLOCK_UNSAFE, "AFK")


func test_block_ends_at_the_phase_change() -> void:
	var rig := make_rig({}, follower())
	rig.start([erg(Wl.WORK, 65.0, 60.0), erg(Wl.RECOVERY, 50.0, 60.0)])
	rig.run(40.0)
	rig.directive(OVERDRIVE)
	rig.run(5.0)
	rig.gov.start_phase(1)
	assert_false(rig.s()["sim_block_active"])
	rig.run(3.0)
	assert_eq(rig.s()["mode"], Wl.ERG)


func test_shift_ignored_outside_sim() -> void:
	var rig := _siege_rig()
	assert_eq(rig.gov.shift(1), 12, "ERG: the gear stays")
	rig.directive(OVERDRIVE)
	assert_eq(rig.gov.shift(1), 13, "in the block it shifts")
