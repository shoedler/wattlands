extends GutTest
## RiderProfile (BRIEF 3.2): defaults, JSON round trip and the PlayerSlot it produces.


func _json_round_trip(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(parsed is Dictionary, "JSON round trip gives a Dictionary")
	return parsed if parsed is Dictionary else {}


func test_defaults_match_brief_3_2() -> void:
	var p := RiderProfile.new()
	assert_eq(p.ftp_w, 200.0, "FTP 200")
	assert_false(p.ftp_verified, "FTP unverified")
	assert_eq(p.cp_w, 200.0, "CP = FTP")
	assert_eq(p.weight_kg, 75.0, "weight 75 kg")
	assert_false(p.share_weight, "weight stays local")
	assert_false(p.show_wkg, "W/kg only on opt-in (BRIEF 3.3)")
	assert_eq(p.wprime_j, 20000.0, "W' 20000 J")
	assert_eq(p.preferred_cadence_rpm, 90.0, "cadence 90")
	assert_eq(p.difficulty_pct, 50.0, "difficulty 50%")
	assert_true(p.haptics_on, "haptics on")
	assert_eq(p.haptic_intensity_pct, 70.0, "haptics at 70%")
	assert_eq(p.units, "metric")
	assert_false(p.autopilot_default, "Autopilot off")
	assert_false(p.pedal_nav, "pedal navigation is opt-in")
	assert_false(p.strava_auto_upload, "auto-upload off")
	assert_eq(p.drivetrain, "cassette")
	assert_eq(p.grade_min_pct, -5.0, "user grade range -5%")
	assert_eq(p.grade_max_pct, 10.0, "user grade range +10%")
	assert_false(p.skip_warmup)
	assert_false(p.created)


func _custom() -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = "Simon"
	p.color = Color("#0072B2")
	p.units = "imperial"
	p.weight_kg = 68.5
	p.share_weight = true
	p.show_wkg = true
	p.ftp_w = 265.0
	p.ftp_verified = true
	p.cp_w = 270.0
	p.wprime_j = 18500.0
	p.preferred_cadence_rpm = 85.0
	p.drivetrain = "single_speed"
	p.difficulty_pct = 75.0
	p.haptics_on = false
	p.haptic_intensity_pct = 40.0
	p.grade_min_pct = -3.0
	p.grade_max_pct = 8.0
	p.skip_warmup = true
	p.autopilot_default = true
	p.pedal_nav = true
	p.scan_interval_s = 2.0
	p.strava_auto_upload = true
	p.metronome = true
	p.created = true
	return p


func test_round_trip_through_json() -> void:
	var p := _custom()
	var q := RiderProfile.from_dict(_json_round_trip(p.to_dict()))
	assert_eq(q.to_dict(), p.to_dict())
	assert_eq(q.display_name, "Simon")
	assert_eq(q.color, Color("#0072B2"))
	assert_eq(q.weight_kg, 68.5)
	assert_true(q.share_weight)
	assert_true(q.show_wkg)
	assert_eq(q.ftp_w, 265.0)
	assert_true(q.ftp_verified)
	assert_eq(q.cp_w, 270.0)
	assert_eq(q.wprime_j, 18500.0)
	assert_eq(q.drivetrain, "single_speed")
	assert_true(q.metronome)
	assert_true(q.created)


func test_default_round_trip() -> void:
	var p := RiderProfile.new()
	assert_eq(RiderProfile.from_dict(_json_round_trip(p.to_dict())).to_dict(), p.to_dict())


func test_from_empty_dict_gives_defaults() -> void:
	assert_eq(RiderProfile.from_dict({}).to_dict(), RiderProfile.new().to_dict())


func test_color_parsing() -> void:
	assert_eq(RiderProfile.from_dict({"color": "009e73"}).color, Color("#009E73"))
	assert_eq(RiderProfile.from_dict({"color": "#0072B2"}).color, Color("#0072B2"))
	assert_eq(
		RiderProfile.from_dict({"color": "not a color"}).color,
		RiderProfile.new().color,
		"an invalid color keeps the default"
	)
	assert_engine_error_count(0)


## W2 (ui-hud): show_wkg is independent of share_weight, and an older profile.json without
## it loads with the opt-in off.
func test_show_wkg_is_its_own_opt_in() -> void:
	var p := RiderProfile.from_dict({"share_weight": true})
	assert_true(p.share_weight)
	assert_false(p.show_wkg, "missing in an older file: off")
	var q := RiderProfile.from_dict({"show_wkg": true})
	assert_true(q.show_wkg)
	assert_false(q.share_weight, "showing W/kg never shares the weight")
	assert_eq(q.to_dict()["show_wkg"], true)


func test_missing_cp_defaults_to_ftp() -> void:
	var p := RiderProfile.from_dict({"ftp_w": 310.0})
	assert_eq(p.ftp_w, 310.0)
	assert_eq(p.cp_w, 310.0)


func test_to_dict_has_every_field() -> void:
	var keys := RiderProfile.new().to_dict().keys()
	for k: String in [
		"display_name",
		"color",
		"units",
		"weight_kg",
		"share_weight",
		"show_wkg",
		"ftp_w",
		"ftp_verified",
		"cp_w",
		"wprime_j",
		"preferred_cadence_rpm",
		"drivetrain",
		"difficulty_pct",
		"haptics_on",
		"haptic_intensity_pct",
		"grade_min_pct",
		"grade_max_pct",
		"skip_warmup",
		"autopilot_default",
		"pedal_nav",
		"scan_interval_s",
		"strava_auto_upload",
		"metronome",
		"created"
	]:
		assert_has(keys, k)


func test_to_slot_fields() -> void:
	var p := _custom()
	var s := p.to_slot(7, Wl.FAIR_FTP)
	assert_eq(s.peer_id, 7)
	assert_eq(s.name, "Simon")
	assert_eq(s.ftp, 265.0)
	assert_true(s.ftp_verified)
	assert_eq(s.scaling_mode, Wl.FAIR_FTP)
	assert_almost_eq(s.p_eff_per_w, 250.0 / 265.0, 1e-9)
	assert_eq(s.rider_mass_kg, 75.0, "FAIR_FTP always uses the 75 kg reference")
	assert_eq(s.preferred_cadence_rpm, 85.0)
	assert_false(s.haptics_on)
	assert_almost_eq(s.haptic_intensity, 0.4, 1e-9)
	assert_true(s.autopilot)
	assert_false(s.is_bot)


func test_to_slot_scaling_modes() -> void:
	var p := _custom()
	var wkg := p.to_slot(2, Wl.WKG)
	assert_almost_eq(wkg.p_eff_per_w, 75.0 / 68.5, 1e-9)
	assert_eq(wkg.rider_mass_kg, 75.0)
	var raw := p.to_slot(2, Wl.RAW)
	assert_eq(raw.p_eff_per_w, 1.0)
	assert_eq(raw.rider_mass_kg, 68.5, "RAW with the weight shared")
	p.share_weight = false
	assert_eq(p.to_slot(2, Wl.RAW).rider_mass_kg, 75.0, "RAW without the weight")


func test_default_slot_haptics() -> void:
	var s := RiderProfile.new().to_slot(1, Wl.FAIR_FTP)
	assert_true(s.haptics_on)
	assert_almost_eq(s.haptic_intensity, 0.7, 1e-9)
	assert_false(s.autopilot)
	assert_false(s.ftp_verified)
	assert_almost_eq(s.p_eff_per_w, 1.25, 1e-9)
