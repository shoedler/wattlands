extends GutTest
## Bots (BRIEF 3.6, 4.2): negative peer ids, "Bot n" names, verified lobby FTP, Autopilot,
## the slot's session look and MockTrainer's erg profile at compliance 1.0.


func test_peer_ids_are_negative() -> void:
	assert_eq(Bots.peer_id(1), -1)
	assert_eq(Bots.peer_id(3), -3)
	assert_eq(Bots.peer_id(-2), -2, "already negative stays negative")
	for n in range(1, 8):
		assert_lt(Bots.peer_id(n), 0)


func test_make_slot() -> void:
	var s := Bots.make_slot(2, 5, 230.0)
	assert_eq(s.peer_id, -2)
	assert_eq(s.name, "Bot 2")
	assert_eq(s.slot_index, 5)
	assert_true(s.is_bot)
	assert_true(s.autopilot)
	assert_eq(s.ftp, 230.0)
	assert_true(s.ftp_verified)
	assert_eq(s.scaling_mode, Wl.FAIR_FTP)
	assert_almost_eq(s.p_eff_per_w, 250.0 / 230.0, 1e-9)
	assert_eq(s.rider_mass_kg, 75.0)
	assert_eq(s.preferred_cadence_rpm, 90.0)
	assert_true(s.haptics_on)


func test_make_slot_look_matches_the_slot() -> void:
	for i in Wl.MAX_SLOTS:
		var s := Bots.make_slot(i + 1, i, 200.0)
		var look := Wl.slot_look(i)
		assert_eq(s.color, look["color"], "slot %d color" % i)
		assert_eq(s.shape, look["shape"], "slot %d shape" % i)
		assert_eq(s.pattern, look["pattern"], "slot %d pattern" % i)
		assert_eq(s.hollow, look["hollow"], "slot %d hollow" % i)
		assert_eq(s.hollow, i >= 4)


func test_make_slot_scaling_modes() -> void:
	assert_almost_eq(Bots.make_slot(1, 0, 200.0, Wl.WKG).p_eff_per_w, 1.0, 1e-9, "75 / 75 kg")
	assert_eq(Bots.make_slot(1, 0, 200.0, Wl.RAW).p_eff_per_w, 1.0)
	assert_eq(Bots.make_slot(1, 0, 200.0, Wl.RAW).scaling_mode, Wl.RAW)
	assert_eq(Bots.make_slot(1, 0, 200.0, Wl.RAW).rider_mass_kg, 75.0)


func test_make_profile() -> void:
	var p := Bots.make_profile(3, 180.0)
	assert_eq(p.display_name, "Bot 3")
	assert_eq(p.ftp_w, 180.0)
	assert_true(p.ftp_verified)
	assert_eq(p.cp_w, 180.0)
	assert_eq(p.wprime_j, 20000.0)
	assert_true(p.created)


func test_rider_spec_is_a_valid_mock_profile() -> void:
	assert_eq(Bots.RIDER_SPEC, "erg:compliance=1.0")
	var comps := MockTrainer.parse_spec(Bots.RIDER_SPEC)
	assert_eq(comps.size(), 1)
	assert_eq(comps[0]["name"], "erg")
	assert_eq(float(comps[0]["params"]["compliance"]), 1.0)
	assert_push_error_count(0)
