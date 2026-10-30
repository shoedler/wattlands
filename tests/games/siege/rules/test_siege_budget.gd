extends GutTest
## The threat budget B and par (brief 2.4 "Waves", 2.8; 4 "B and par in FAIR_FTP, WKG and RAW,
## verified or not, without reading any weight").

const F := preload("res://tests/games/siege/siege_fakes.gd")


func _state(mode: String, ftp: float = 200.0, verified: bool = true) -> SiegeState:
	var slots := F.make_slots(1)
	slots[0].ftp = ftp
	slots[0].ftp_verified = verified
	slots[0].rider_mass_kg = 999.0
	return SiegeState.create(F.content("short"), slots, mode, null)


## The shift's budget factor times the slot count's.
func _factor(rig: SiegeRig) -> float:
	return (
		SiegeRules.budget_factor(rig.content)
		* SiegeRules.slot_factor(rig.content, rig.state.riders.size())
	)


func test_fair_ftp_planned_p_eff_is_the_target_share_of_250_w() -> void:
	for ftp in [80.0, 200.0, 400.0]:
		var s := _state(Wl.FAIR_FTP, ftp)
		assert_almost_eq(SiegeRules.planned_p_eff_w(s, s.riders[0], 95.0), 0.95 * 250.0, 1e-6)


func test_raw_planned_p_eff_is_the_planned_watts() -> void:
	for ftp in [80.0, 200.0, 400.0]:
		var s := _state(Wl.RAW, ftp)
		assert_almost_eq(SiegeRules.planned_p_eff_w(s, s.riders[0], 95.0), 0.95 * ftp, 1e-6)


func test_wkg_uses_the_latest_p_eff_over_power_ratio() -> void:
	var s := _state(Wl.WKG, 200.0)
	s.riders[0].r_wkg = 1.3
	assert_almost_eq(SiegeRules.planned_p_eff_w(s, s.riders[0], 100.0), 200.0 * 1.3, 1e-6)


func test_an_unverified_ftp_counts_85_percent() -> void:
	for mode: String in [Wl.FAIR_FTP, Wl.RAW, Wl.WKG]:
		var v := _state(mode, 200.0, true)
		var u := _state(mode, 200.0, false)
		var a := SiegeRules.planned_p_eff_w(v, v.riders[0], 90.0)
		var b := SiegeRules.planned_p_eff_w(u, u.riders[0], 90.0)
		assert_almost_eq(b, a * 0.85, 1e-6, mode)


func test_no_weight_is_ever_read() -> void:
	var a := _state(Wl.WKG, 200.0)
	var slots := F.make_slots(1)
	slots[0].rider_mass_kg = 50.0
	var b := SiegeState.create(F.content("short"), slots, Wl.WKG, null)
	assert_eq(
		SiegeRules.planned_p_eff_w(a, a.riders[0], 90.0),
		SiegeRules.planned_p_eff_w(b, b.riders[0], 90.0)
	)


func test_wkg_ratio_comes_from_telemetry_with_at_least_50_w() -> void:
	var rig := SiegeRig.new("short", 1, 0, 7, Wl.WKG)
	rig.power_w[1] = 40.0
	rig.p_eff[1] = 80.0
	rig.step()
	assert_eq(rig.rider().r_wkg, 1.0, "below 50 W: unchanged")
	rig.power_w[1] = 200.0
	rig.p_eff[1] = 260.0
	rig.step()
	assert_almost_eq(rig.rider().r_wkg, 1.3, 1e-6)


func test_b_is_c_budget_times_the_sum_of_planned_shares_times_the_spawn_minutes() -> void:
	var rig := SiegeRig.new("short", 3)
	rig.enter(2, 0.0)
	var want := 0.0
	for r in rig.state.riders:
		want += SiegeRules.planned_p_eff_w(rig.state, r, 95.0) / 250.0
	want *= rig.content.num("c_budget") * _factor(rig) * (300.0 - 60.0) / 60.0
	assert_almost_eq(rig.state.wave.budget, want, 1e-3)
	assert_eq(int(rig.of_type(SiegeIds.EV_WAVE_START).back()["b"]), roundi(want))


func test_b_grows_with_the_slot_count() -> void:
	var b: Array[float] = []
	for n in [1, 2, 4]:
		var rig := SiegeRig.new("short", n)
		rig.enter(2, 0.0)
		b.append(rig.state.wave.budget)
	var c := F.content("short")
	var f: Array[float] = []
	for n in [1, 2, 4]:
		f.append(SiegeRules.slot_factor(c, n))
	assert_almost_eq(b[1], 2.0 * b[0] * f[1] / f[0], 1e-3)
	assert_almost_eq(b[2], 4.0 * b[0] * f[2] / f[0], 1e-3)


func test_b_uses_the_wave_offset_through_the_plan() -> void:
	var rig := SiegeRig.new("short", 1)
	rig.slots[0].options["wave_offset"] = 5
	rig.plans[1] = F.with_cooldown(SiegePlanBuilder.build(rig.content.shift, rig.slots[0], "short"))
	rig.enter(2, 0.0)
	var want := SiegeRules.planned_p_eff_w(rig.state, rig.rider(), 100.0) / 250.0
	want *= rig.content.num("c_budget") * _factor(rig) * 4.0
	assert_almost_eq(rig.state.wave.budget, want, 1e-3)


func test_b_is_the_same_for_every_ftp_in_fair_ftp() -> void:
	var b: Array[float] = []
	for ftp in [80.0, 200.0, 400.0]:
		var rig := SiegeRig.new("short", 1)
		rig.slots[0].ftp = ftp
		rig.state.rider(1).ftp = ftp
		rig.enter(2, 0.0)
		b.append(rig.state.wave.budget)
	assert_almost_eq(b[0], b[1], 1e-3)
	assert_almost_eq(b[1], b[2], 1e-3)


func test_par_is_three_quarters_of_the_planned_kj() -> void:
	var rig := SiegeRig.new("drill", 1)
	rig.run(120.0)
	var sc := SiegeScore.compute(rig.state)
	assert_almost_eq(float(sc["par"]), 0.75 * rig.state.planned_kj, 1e-6)
	assert_gt(rig.state.planned_kj, 0.0)


func test_par_in_raw_follows_the_ftp() -> void:
	var lo := SiegeRig.new("drill", 1, 0, 7, Wl.RAW)
	lo.slots[0].ftp = 100.0
	lo.state.rider(1).ftp = 100.0
	lo.run(120.0)
	var hi := SiegeRig.new("drill", 1, 0, 7, Wl.RAW)
	hi.slots[0].ftp = 300.0
	hi.state.rider(1).ftp = 300.0
	hi.run(120.0)
	assert_almost_eq(hi.state.planned_kj, 3.0 * lo.state.planned_kj, 0.01)


func test_par_unverified_is_85_percent() -> void:
	var v := SiegeRig.new("drill", 1)
	v.run(120.0)
	var u := SiegeRig.new("drill", 1)
	u.state.rider(1).ftp_verified = false
	u.run(120.0)
	assert_almost_eq(u.state.planned_kj, 0.85 * v.state.planned_kj, 0.01)


func test_a_shift_s_budget_factor_scales_b() -> void:
	var rig := SiegeRig.new("endurance", 2)
	rig.enter(2, 0.0)
	var f := SiegeRules.budget_factor(rig.content)
	assert_eq(f, float(rig.content.waves["budget_factor"]["endurance"]))
	assert_lt(f, 1.0, "endurance's one long wave gets less")
	var want := 0.0
	for r in rig.state.riders:
		want += SiegeRules.planned_p_eff_w(rig.state, r, 70.0) / 250.0
	want *= rig.content.num("c_budget") * _factor(rig) * (2700.0 - 60.0) / 60.0
	assert_almost_eq(rig.state.wave.budget, want, 1e-2)


func test_shifts_without_a_factor_use_1() -> void:
	assert_eq(SiegeRules.budget_factor(F.content("drill")), 1.0, "the drill has none")
	var files := SiegeContent.read_files()
	files["waves"].erase("budget_factor")
	files["waves"].erase("slot_factor")
	var c := SiegeContent.from_dicts(files, "short")
	assert_true(c.ok(), str(c.errors))
	assert_eq(SiegeRules.budget_factor(c), 1.0)
	assert_eq(SiegeRules.slot_factor(c, 2), 1.0)


func test_each_shift_reads_its_own_factor() -> void:
	var bf: Dictionary = F.content("short").waves["budget_factor"]
	for id: String in ["short", "vo2", "sweetspot", "endurance"]:
		assert_eq(SiegeRules.budget_factor(F.content(id)), float(bf.get(id, 1.0)), id)


func test_a_bad_budget_factor_is_rejected() -> void:
	var files := SiegeContent.read_files()
	files["waves"]["budget_factor"] = {"endurance": 0}
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("budget_factor"))
	files["waves"]["budget_factor"] = 3
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("budget_factor"))


func test_the_slot_factor_scales_b_by_the_team_size() -> void:
	var c := F.content("short")
	var sf: Array = c.waves["slot_factor"]
	assert_eq(sf.size(), 4)
	for n in range(1, 5):
		assert_eq(SiegeRules.slot_factor(c, n), float(sf[n - 1]), "%d slots" % n)
	assert_eq(SiegeRules.slot_factor(c, 4), 1.0, "a full team is the reference")
	assert_eq(SiegeRules.slot_factor(c, 0), 1.0)
	assert_eq(SiegeRules.slot_factor(c, 9), 1.0)


func test_bots_count_as_slots() -> void:
	var a := SiegeRig.new("short", 1, 3)
	var b := SiegeRig.new("short", 4)
	a.enter(2, 0.0)
	b.enter(2, 0.0)
	assert_almost_eq(a.state.wave.budget, b.state.wave.budget, 1e-3)


func test_total_b_still_grows_with_every_slot() -> void:
	var c := F.content("short")
	var last := 0.0
	for n in range(1, 5):
		var total := SiegeRules.slot_factor(c, n) * n
		assert_gt(total, last, "%d slots bring more threat than %d" % [n, n - 1])
		last = total


func test_a_bad_slot_factor_is_rejected() -> void:
	var files := SiegeContent.read_files()
	files["waves"]["slot_factor"] = [1, 1, 1]
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("slot_factor"))
	files["waves"]["slot_factor"] = [1, 0, 1, 1]
	assert_true(str(SiegeContent.from_dicts(files, "short").errors).contains("slot_factor"))
