extends "res://tests/governor/gov_test_base.gd"
## W4r2 (W3 SAF-1 range check): an FTP below the governor's 30-2000 W range must not be
## replaced by the governor's 200 W default. A profile FTP below 30 W was reachable in memory
## (the Strava import, the FTP test's result) while only a loaded profile.json was clamped; the
## governor then applied 200 W at "100 %" to a 25 W rider (W4r2 proof
## build/w4r2/safety/test_w4r2_saf1_ftp_range.gd). Now the governor uses 30 W below the range,
## and WlSettings.save_profile, the Strava import and the FTP test keep the profile in range.


func test_an_out_of_range_low_ftp_is_not_replaced_by_200_w() -> void:
	var dev: TrainerDevice = follower()
	autofree(dev)
	var r := LocalRider.new()
	add_child_autofree(r)
	var p := RiderProfile.new()
	p.ftp_w = 25.0
	p.cp_w = 25.0
	p.ftp_verified = true
	p.skip_warmup = true
	r.setup(1, p, p.to_slot(1, Wl.FAIR_FTP), dev, {"multiplayer": false, "skip_warmup": true})
	assert_push_error("ftp_w must be within")
	assert_eq(float(r.governor.status()["ftp_w"]), 30.0, "the lowest basis, not the 200 W default")
	r.set_plan(plan_with_cooldown([erg(Wl.WORK, 100.0, 600.0)]))
	r.start_phase(0)
	for i in roundi(30.0 / DT):
		r.tick(DT)
	var w := int(r.governor.status()["applied_target_w"])
	gut.p("profile FTP 25 W: rider ftp_w() %.0f, governor applied %d W at 100%% FTP" % [r.ftp_w(), w])
	assert_lte(w, 50, "100%% of the rider's 25 W FTP rides the 50 W floor at most; applied %d W" % w)


func test_a_high_out_of_range_ftp_still_keeps_the_previous_value() -> void:
	var rig := make_rig({"ftp_w": 180.0}, follower())
	rig.gov.configure({"ftp_w": 2500.0})
	assert_push_error("keeping 180")
	rig.start([erg(Wl.WORK, 100.0, 120.0)])
	rig.run(20.0)
	assert_eq(rig.applied_w(), 180, "never the 2000 W bound")
