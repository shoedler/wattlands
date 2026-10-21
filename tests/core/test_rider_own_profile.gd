extends GutTest
## W4 (SAF-1): the local human rider's governor takes FTP, ftp_verified, haptics_on and
## haptic_intensity from the rider's own RiderProfile, never from a slot someone else built.
## On a CLIENT the slot comes from the host's session_start (AppSessionLauncher.build_config);
## BRIEF 3.3 "ERG targets always come from each rider's own FTP" and 4.6.7 "each client
## validates and clamps them locally". SafetyGovernor.configure also rejects an FTP outside the
## 30-2000 W Settings allows. (The W3 proof drove this through the app's session launcher,
## build/w3/safety/test_w3_safety_client_slot.gd; the launcher itself is the app's, so this
## test drives LocalRider.setup with the same hostile slot.)

const DT := Wl.SIM_DT


func _own_profile() -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = "Guest"
	p.ftp_w = 200.0
	p.cp_w = 200.0
	p.ftp_verified = false
	p.haptics_on = false
	p.haptic_intensity_pct = 40.0
	p.skip_warmup = false
	return p


## What a modified or buggy host's session_start says about this rider.
func _hostile_slot(peer: int) -> PlayerSlot:
	return PlayerSlot.from_dict({
		"peer_id": peer, "name": "Guest", "slot_index": 1, "ftp": 5000, "ftp_verified": true,
		"haptics_on": true, "haptic_intensity": 1.0,
	})


func _rider(profile: RiderProfile, slot: PlayerSlot, device: TrainerDevice) -> LocalRider:
	var r := LocalRider.new()
	add_child_autofree(r)
	r.setup(slot.peer_id if slot != null else 2, profile, slot, device, {"multiplayer": true, "record": false})
	return r


func _mock(ftp: float = 200.0) -> MockTrainer:
	var m := MockTrainer.from_spec("erg", ftp, {"seed": 5})
	autofree(m)
	return m


func test_a_hosts_slot_cannot_set_the_clients_safety_values() -> void:
	var slot := _hostile_slot(2)
	var r := _rider(_own_profile(), slot, _mock())
	assert_push_warning("using the rider's own profile")
	var params := r.governor_params()
	assert_eq(float(params["ftp_w"]), 200.0, "the rider's own FTP")
	assert_false(bool(params["ftp_verified"]), "unverified: the 0.85 factor stays")
	assert_false(bool(params["haptics_on"]), "the rider opted out of haptics")
	assert_almost_eq(float(params["haptic_intensity"]), 0.4, 1e-9)
	assert_eq(slot.ftp, 200.0, "the local slot now says what the governor uses")
	assert_false(slot.ftp_verified)
	assert_false(slot.haptics_on)
	assert_eq(r.ftp_w(), 200.0)
	var st := r.governor.status()
	assert_eq(float(st["ftp_w"]), 200.0)
	assert_false(bool(st["ftp_verified"]))


## The W3 repro's effect: a PlanValidator-finalized 50% warm-up phase wrote 1500 W ERG.
func test_the_trainer_gets_the_riders_own_watts() -> void:
	var r := _rider(_own_profile(), _hostile_slot(2), _mock())
	var plan := PlanValidator.finalize(EffortPlan.of([PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up")]))
	assert_not_null(plan)
	r.set_plan(plan)
	r.start_phase(0)
	for i in 40:
		r.tick(DT)
	var st := r.governor.status()
	var w := int(st["applied_target_w"])
	assert_lte(w, 300, "150%% of the rider's 200 W FTP is the most any ERG target may be; applied %d W" % w)
	assert_eq(int(st["governed_target_w"]), 85, "50% x 200 W x 0.85 (unverified)")


func test_an_honest_slot_changes_nothing_and_logs_nothing() -> void:
	var p := _own_profile()
	var slot := p.to_slot(2, Wl.FAIR_FTP)
	var r := _rider(p, slot, _mock())
	for e: Variant in get_errors():
		assert_false((e as Object).call("contains_text", "using the rider's own profile"), "no warning for an honest slot")
	assert_eq(float(r.governor_params()["ftp_w"]), 200.0)


func test_bots_keep_their_slot() -> void:
	var bslot := Bots.make_slot(1, 3, 230.0)
	var r := _rider(Bots.make_profile(1, 180.0), bslot, _mock(230.0))
	assert_eq(float(r.governor_params()["ftp_w"]), 230.0, "a bot rides the lobby's bot FTP")
	assert_eq(bslot.ftp, 230.0)


func test_without_a_profile_the_slot_is_used_but_the_governor_rejects_an_absurd_ftp() -> void:
	var r := _rider(null, _hostile_slot(2), _mock())
	assert_push_error("ftp_w must be within 30-2000 W")
	assert_eq(float(r.governor.status()["ftp_w"]), 200.0, "the governor keeps its previous (default) FTP")
	var plan := PlanValidator.finalize(EffortPlan.of([PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up")]))
	r.set_plan(plan)
	r.start_phase(0)
	for i in 40:
		r.tick(DT)
	assert_lte(int(r.governor.status()["applied_target_w"]), 300)


func test_configure_rejects_an_ftp_outside_30_to_2000() -> void:
	var g := SafetyGovernor.new()
	autofree(g)
	g.configure({"ftp_w": 250.0})
	for bad: float in [5000.0, 29.9, 2000.5, 0.0, -10.0, INF, NAN]:
		g.configure({"ftp_w": bad})
		assert_push_error("ftp_w must be within 30-2000 W")
		assert_eq(float(g.status()["ftp_w"]), 250.0, "rejected %s; the previous value stays" % str(bad))
	for ok: float in [30.0, 2000.0, 77.0]:
		g.configure({"ftp_w": ok})
		assert_eq(float(g.status()["ftp_w"]), ok)
	assert_true(GovernorClamps.ftp_in_range(30.0))
	assert_true(GovernorClamps.ftp_in_range(2000.0))
	assert_false(GovernorClamps.ftp_in_range(2000.01))
	assert_false(GovernorClamps.ftp_in_range(NAN))
