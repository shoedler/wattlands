extends GutTest
## EffortScaling (BRIEF 3.3): FAIR_FTP, WKG and RAW effort, P_eff and the speed model's
## rider mass.


func test_effort_fair_ftp() -> void:
	assert_almost_eq(EffortScaling.effort(Wl.FAIR_FTP, 200.0, 250.0, 80.0), 0.8, 1e-9)
	assert_almost_eq(EffortScaling.effort(Wl.FAIR_FTP, 300.0, 300.0, 60.0), 1.0, 1e-9)


func test_effort_wkg() -> void:
	assert_almost_eq(EffortScaling.effort(Wl.WKG, 300.0, 250.0, 75.0), 4.0, 1e-9)
	assert_almost_eq(EffortScaling.effort(Wl.WKG, 180.0, 250.0, 60.0), 3.0, 1e-9)


func test_effort_raw() -> void:
	assert_eq(EffortScaling.effort(Wl.RAW, 300.0, 250.0, 75.0), 300.0)


func test_effort_unknown_mode_is_fair_ftp() -> void:
	assert_almost_eq(EffortScaling.effort("bogus", 200.0, 250.0, 80.0), 0.8, 1e-9)


func test_effort_guards_zero_divisors() -> void:
	assert_eq(EffortScaling.effort(Wl.FAIR_FTP, 100.0, 0.0, 0.0), 100.0, "FTP floored at 1")
	assert_eq(EffortScaling.effort(Wl.WKG, 100.0, 0.0, 0.0), 100.0, "weight floored at 1")


func test_p_eff_per_w() -> void:
	assert_almost_eq(EffortScaling.p_eff_per_w(Wl.FAIR_FTP, 200.0, 90.0), 1.25, 1e-9)
	assert_almost_eq(EffortScaling.p_eff_per_w(Wl.FAIR_FTP, 250.0, 90.0), 1.0, 1e-9)
	assert_almost_eq(EffortScaling.p_eff_per_w(Wl.WKG, 200.0, 60.0), 1.25, 1e-9)
	assert_almost_eq(EffortScaling.p_eff_per_w(Wl.WKG, 200.0, 75.0), 1.0, 1e-9)
	assert_eq(EffortScaling.p_eff_per_w(Wl.RAW, 200.0, 60.0), 1.0)


func test_p_eff_w() -> void:
	# FAIR_FTP: (P / FTP) * 250 W.
	assert_almost_eq(EffortScaling.p_eff_w(Wl.FAIR_FTP, 300.0, 300.0, 70.0), 250.0, 1e-9)
	assert_almost_eq(EffortScaling.p_eff_w(Wl.FAIR_FTP, 150.0, 200.0, 70.0), 187.5, 1e-9)
	# WKG: (P / weight) * 75.
	assert_almost_eq(EffortScaling.p_eff_w(Wl.WKG, 320.0, 250.0, 80.0), 300.0, 1e-9)
	# RAW: actual watts.
	assert_eq(EffortScaling.p_eff_w(Wl.RAW, 320.0, 250.0, 80.0), 320.0)
	# Riders at the same %FTP get the same P_eff in FAIR_FTP.
	assert_almost_eq(EffortScaling.p_eff_w(Wl.FAIR_FTP, 160.0, 200.0, 60.0),
		EffortScaling.p_eff_w(Wl.FAIR_FTP, 320.0, 400.0, 95.0), 1e-9)


func test_rider_mass_kg() -> void:
	assert_eq(EffortScaling.rider_mass_kg(Wl.FAIR_FTP, 82.0, true), 75.0)
	assert_eq(EffortScaling.rider_mass_kg(Wl.FAIR_FTP, 82.0, false), 75.0)
	assert_eq(EffortScaling.rider_mass_kg(Wl.WKG, 82.0, true), 75.0)
	assert_eq(EffortScaling.rider_mass_kg(Wl.WKG, 82.0, false), 75.0)
	assert_eq(EffortScaling.rider_mass_kg(Wl.RAW, 82.0, true), 82.0, "RAW with the weight shared")
	assert_eq(EffortScaling.rider_mass_kg(Wl.RAW, 82.0, false), 75.0, "RAW without the weight")
	assert_eq(EffortScaling.rider_mass_kg(Wl.RAW, 0.0, true), 75.0, "no weight to use")


func test_display_helpers() -> void:
	assert_almost_eq(EffortScaling.wkg(300.0, 75.0), 4.0, 1e-9)
	assert_almost_eq(EffortScaling.ftp_pct(150.0, 200.0), 75.0, 1e-9)
	assert_eq(EffortScaling.ftp_pct(100.0, 0.0), 10000.0, "FTP floored at 1")


func test_rider_profile_uses_scaling() -> void:
	var p := RiderProfile.new()
	p.ftp_w = 200.0
	p.weight_kg = 60.0
	p.share_weight = true
	assert_almost_eq(p.p_eff_per_w(Wl.FAIR_FTP), 1.25, 1e-9)
	assert_almost_eq(p.p_eff_per_w(Wl.WKG), 1.25, 1e-9)
	assert_eq(p.p_eff_per_w(Wl.RAW), 1.0)
	assert_eq(p.rider_mass_kg(Wl.RAW), 60.0)
	assert_eq(p.rider_mass_kg(Wl.FAIR_FTP), 75.0)
	p.share_weight = false
	assert_eq(p.rider_mass_kg(Wl.RAW), 75.0)
