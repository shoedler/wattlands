extends "res://tests/app/app_test_base.gd"
## Safety rules the session launcher applies on this machine (BRIEF 3.3, 4.5, 4.6):
## - W3 SAF-1: a CLIENT's governor works from the rider's own profile (FTP, ftp_verified,
##   haptics), never from the copy the host sent in session_start or lobby_state.
## - W3 SAF-3: --sim-speed only speeds up a MockTrainer session; with any other trainer the
##   session clock runs at 1, so no governor time rule is scaled in wall time.


## A real LocalRider in place of the fixture's fake one (the governor parameters are real).
func _go_real(f: AppFixture) -> LocalRider:
	var t := f.fake_trainer()
	var old: LocalRider = t.rider
	t.remove_child(old)
	old.free()
	var r := LocalRider.new()
	r.name = "LocalRider"
	t.add_child(r)
	t.rider = r
	return r


func _guest_profile() -> RiderProfile:
	var p := fx.give_profile(200.0, "Guest")
	p.ftp_verified = false
	p.haptics_on = false
	p.haptic_intensity_pct = 30.0
	return p


## A hostile session_start: the host claims the guest has FTP 5000 W, verified, haptics on.
func _hostile_session_start() -> Dictionary:
	return {
		"type": "session_start", "game_id": "workout", "content_id": "e2e", "seed": 1,
		"scaling": Wl.FAIR_FTP, "options": {}, "start_tick": 0,
		"players": [
			{"peer_id": 1, "name": "Host", "slot_index": 0, "ftp": 250, "ftp_verified": true},
			{"peer_id": 2, "name": "Guest", "slot_index": 1, "ftp": 5000, "ftp_verified": true,
				"haptics_on": true, "haptic_intensity": 1.0},
		],
	}


func _as_client(peer: int) -> void:
	var net := fx.fake_net()
	net.local_peer = peer
	net.host_peer = 1
	net.role = Wl.CLIENT


func test_client_governor_uses_the_riders_own_ftp_not_the_hosts_copy() -> void:
	_guest_profile()
	var rider := _go_real(fx)
	_as_client(2)
	var launcher := AppSessionLauncher.create(fx.services)
	var cfg := launcher.build_config(Wl.CLIENT, {"session_start": _hostile_session_start(), "realtime": false, "record_rides": false}, null, null, true)
	assert_eq(launcher.error, "", "the CLIENT config was built")
	assert_false(cfg.is_empty())
	var params := rider.governor_params()
	assert_eq(float(params.get("ftp_w", 0.0)), 200.0, "the governor's FTP is the rider's own (profile 200 W)")
	assert_false(bool(params.get("ftp_verified", true)), "the rider's own FTP is unverified (0.85 factor)")
	assert_false(bool(params.get("haptics_on", true)), "the rider opted out of haptics")
	assert_almost_eq(float(params.get("haptic_intensity", 0.0)), 0.3, 0.001, "the rider's own haptic intensity")
	var local: PlayerSlot = null
	for slot: PlayerSlot in cfg["players"]:
		if slot.peer_id == 2:
			local = slot
	assert_not_null(local)
	if local != null:
		assert_eq(local.ftp, 200.0, "the local slot the GameHost sees carries the rider's own FTP")
	# The effect on the trainer: a validated 50% FTP warm-up phase never asks for more than 150%
	# of the rider's own FTP.
	var plan := PlanValidator.finalize(EffortPlan.of([PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up")]))
	rider.set_plan(plan)
	rider.start_phase(0)
	for i in 40:
		rider.tick(Wl.SIM_DT)
	var st := rider.governor.status()
	assert_lte(int(st["applied_target_w"]), 300, "applied %d W, written %d W" % [int(st["applied_target_w"]), int(st["written_target_w"])])
	launcher.release()


## A restarted client rejoins without session_start: its slots come from the host's lobby_state.
func test_rejoining_client_ignores_the_hosts_ftp_and_haptics_too() -> void:
	_guest_profile()
	var rider := _go_real(fx)
	_as_client(2)
	var net := fx.fake_net()
	net.add_human(1, "Host", 250.0)
	var guest := net.add_human(2, "Guest", 5000.0)
	guest.ftp_verified = true
	guest.haptics_on = true
	guest.haptic_intensity = 1.0
	net.lobby = {"game_id": "workout", "game_version": "1.0.0", "content_id": "e2e", "scaling": Wl.FAIR_FTP,
		"settings": {"seed": 3}}
	var launcher := AppSessionLauncher.create(fx.services)
	var cfg := launcher.build_config(Wl.CLIENT, {"game_id": "workout", "content_id": "e2e", "realtime": false, "record_rides": false}, null, null, true)
	assert_eq(launcher.error, "")
	assert_false(cfg.is_empty())
	var params := rider.governor_params()
	assert_eq(float(params.get("ftp_w", 0.0)), 200.0)
	assert_false(bool(params.get("ftp_verified", true)))
	assert_false(bool(params.get("haptics_on", true)))
	launcher.release()


func test_host_keeps_its_lobby_slot() -> void:
	fx.give_profile(250.0)
	var net := fx.fake_net()
	net.local_peer = 1
	net.role = Wl.HOST
	net.add_human(1, "Ada", 250.0)
	net.lobby = {"game_id": "workout", "game_version": "1.0.0", "content_id": "e2e", "scaling": Wl.FAIR_FTP}
	var launcher := AppSessionLauncher.create(fx.services)
	var cfg := launcher.build_config(Wl.HOST, {"game_id": "workout", "content_id": "e2e", "seed": 1, "realtime": false}, null, null, true)
	assert_eq(launcher.error, "")
	var players: Array[PlayerSlot] = cfg["players"]
	assert_eq(players[0].ftp, 250.0)
	launcher.release()


func test_sim_speed_drives_only_a_mock_trainer() -> void:
	fx.give_profile(250.0)
	var launcher := AppSessionLauncher.create(fx.services)
	var cfg := launcher.build_config(Wl.SOLO, {"game_id": "workout", "content_id": "e2e", "seed": 1, "sim_speed": 4.0, "realtime": false}, null, null, true)
	assert_eq(launcher.error, "")
	assert_eq(float(cfg["sim_speed"]), 4.0, "a MockTrainer session may run fast")
	launcher.release()


func test_sim_speed_is_one_with_a_real_trainer() -> void:
	fx.give_profile(250.0)
	var t := fx.fake_trainer()
	var real := TrainerDevice.new()
	real.name = "RealTrainer"
	t.add_child(real)
	t.dev = real
	var launcher := AppSessionLauncher.create(fx.services)
	var cfg := launcher.build_config(Wl.SOLO, {"game_id": "workout", "content_id": "e2e", "seed": 1, "sim_speed": 4.0, "realtime": false}, null, null, true)
	assert_eq(launcher.error, "")
	assert_eq(float(cfg["sim_speed"]), 1.0, "a non-mock trainer never runs the governor's time rules faster")
	cfg = launcher.build_config(Wl.SOLO, {"game_id": "workout", "content_id": "e2e", "seed": 1, "sim_speed": 0.25, "realtime": false}, null, null, true)
	assert_eq(float(cfg["sim_speed"]), 1.0, "nor slower (rescue and coasting windows stay real seconds)")
	launcher.release()


func test_effective_sim_speed_rule() -> void:
	var mock := MockTrainer.from_spec("erg", 200.0)
	var real := TrainerDevice.new()
	assert_eq(AppSessionLauncher.effective_sim_speed(mock, 50.0), 50.0)
	assert_eq(AppSessionLauncher.effective_sim_speed(mock, 0.0), 0.01, "never 0")
	assert_eq(AppSessionLauncher.effective_sim_speed(real, 1.0), 1.0)
	assert_eq(AppSessionLauncher.effective_sim_speed(real, 8.0), 1.0)
	assert_eq(AppSessionLauncher.effective_sim_speed(null, 8.0), 1.0, "no device: no speed-up")
	mock.free()
	real.free()
