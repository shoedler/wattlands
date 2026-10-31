extends "res://tests/app/app_test_base.gd"
## Discard the ride on the real stack: the real WlTrainerService with a MockTrainer, LocalRider,
## governor and GameHost. Pedals through the real GestureRecognizer and PedalScanList never pick
## Yes; a discard leaves the trainer exactly as End/Leave does; the title never starts a new ride
## from a stretch that was already running.

const DT := Wl.SIM_DT
## Steps for a rescue to begin: the plan reaches the mock's cadence drop within two minutes.
const MAX_RESCUE_STEPS := 2400

var _extra: Array[AppFixture] = []


func after_each() -> void:
	super()
	for f in _extra:
		f.free_all()
	_extra.clear()


## The fixture's trainer double becomes the real service on a mock, as the app builds it.
func _real(f: AppFixture, spec: String) -> WlTrainerService:
	f.trainer.free()
	var svc := WlTrainerService.new()
	svc.settings = f.settings
	svc.bus = f.bus
	svc.input_router = f.input
	svc.rider_options_factory = func() -> Dictionary: return {"bus": f.bus}
	add_child(svc)
	f.trainer = svc
	f.services.trainer = svc
	f.services.registry = get_tree().root.get_node("GameRegistry") as WlGameRegistry
	f.services.game_host_factory = func() -> GameHost: return GameHost.new()
	svc.use_mock(spec)
	return svc


func _new_fixture(ftp: float, rider_name: String) -> AppFixture:
	var f := AppFixture.new()
	_extra.append(f)
	f.give_profile(ftp, rider_name)
	return f


func _enter(f: AppFixture, params: Dictionary) -> AppSessionScreen:
	var s := AppSessionScreen.new()
	s.services = f.services
	s.auto_process = false
	add_child(s)
	s.enter(params)
	return s


## What the trainer and the rider's stack hold now; End and a discard must match on all of it.
func _trainer_state(svc: WlTrainerService, f: AppFixture) -> Dictionary:
	var r := svc.local_rider()
	var d := svc.device() as MockTrainer
	return {
		"external_tick": svc.is_external_tick(),
		"reset_due": svc.is_menu_reset_pending(),
		"plan_null": r.plan() == null,
		"multiplayer": r.is_multiplayer,
		"peer": r.peer_id,
		"panic": r.governor.is_panic(),
		"rescue": r.governor.is_rescue(),
		"mode": d.commanded_mode,
		"target_w": d.commanded_target_w,
		"grade": d.commanded_grade_pct,
		"wind": d.commanded_wind_mps,
		"governor_mode": str(r.governor.status().get("mode", "")),
		"attached": f.input.attached_rider() == r,
	}


func _assert_handed_back(state: Dictionary, what: String) -> void:
	assert_true(state["plan_null"], "%s: no plan" % what)
	assert_eq(state["mode"], Wl.SIM, "%s: SIM" % what)
	assert_eq(state["grade"], 0.0, "%s: flat" % what)
	assert_eq(state["wind"], 0.0, "%s: no wind" % what)
	assert_false(state["external_tick"], "%s: menu time ticks the rider" % what)
	assert_false(state["reset_due"], "%s: the reset is done" % what)


const STOPS_AT_20_S := "erg+cadence_drop:rpm=0,at_s=20"
const STEPS_TO_PAUSE := 1200
const STEPS_TO_SURGE := 800


func _spec_for(state: String) -> String:
	match state:
		"rescue":
			return "erg+cadence_drop:rpm=35,at_target_pct=60,for_s=30"
		"surge":
			return "erg+surge:every_s=30,for_s=4,lift=0.3"
		"auto_pause", "shared_pause":
			return STOPS_AT_20_S
	return "erg"


func _speed(s: AppSessionScreen) -> float:
	return float((s.local_rider().device as MockTrainer).last_sample().speed_kmh)


## Puts `s` in `state`, the rider's way there, and fails the row unless it is in it when the way out
## is picked. `step` advances the whole session one step.
func _reach(s: AppSessionScreen, state: String, step: Callable) -> void:
	for _i in 300:
		step.call()
	var r := s.local_rider()
	var base := _speed(s)
	match state:
		"pause":
			s.feed_action(&"pause")
		"panic":
			s.panic()
		"auto_pause", "shared_pause":
			_step_until(step, STEPS_TO_PAUSE, func() -> bool: return s.host.is_paused())
		"rescue":
			_step_until(step, MAX_RESCUE_STEPS, func() -> bool: return r.governor.is_rescue())
		"surge":
			_step_until(step, STEPS_TO_SURGE, func() -> bool: return _speed(s) > base * 1.1)
	for _i in 5:
		step.call()
	match state:
		"riding":
			assert_eq(s.host.state, "running", "the row is riding")
			assert_false(s.overlay.visible, "the row is riding")
		"pause":
			assert_true(s.host.is_paused(), "the row is paused")
			assert_false(s.auto_paused(), "by the rider")
		"auto_pause":
			assert_true(s.host.is_paused(), "the row is paused")
			assert_true(s.auto_paused(), "on not pedaling")
		"shared_pause":
			assert_true(s.host.is_paused(), "the shared pause: role %s" % s.role)
			assert_true(r.is_ride_paused(), "this rider stopped")
		"panic":
			assert_true(r.governor.is_panic(), "the row is in a panic")
		"rescue":
			assert_true(r.governor.is_rescue(), "the row is in a rescue")
		"surge":
			assert_gt(_speed(s), base * 1.1, "the row is in a surge")


func _step_until(step: Callable, max_steps: int, done: Callable) -> void:
	var n := 0
	while not done.call() and n < max_steps:
		step.call()
		n += 1


func _way_out(s: AppSessionScreen, way: String) -> void:
	if not s.overlay.visible:
		s.open_menu()
	if way == "end":
		assert_true(s.pick_id("end"), "End is on the menu")
	else:
		assert_true(s.pick_id("discard"), "Discard is on the menu")
		assert_true(s.pick_id("yes"), "the confirm opened")


## The state just after the screen leaves, and 10 s of menu time later.
func _after_leaving(s: AppSessionScreen, svc: WlTrainerService, f: AppFixture) -> Dictionary:
	s.leave()
	var out := {"app": f.app.state, "at_once": _trainer_state(svc, f)}
	for _i in 200:
		svc.step()
	out["later"] = _trainer_state(svc, f)
	return out


func _solo_run(way: String, state: String) -> Dictionary:
	var f := _new_fixture(200.0, "Rider")
	var svc := _real(f, _spec_for(state))
	for _i in 20:
		svc.step()
	var s := _enter(f, {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"})
	_reach(
		s,
		state,
		func() -> void:
			s.host.step()
			s.tick(DT)
	)
	_way_out(s, way)
	var out := _after_leaving(s, svc, f)
	remove_child(s)
	s.free()
	return out


func test_solo_a_discard_leaves_the_trainer_as_end_does() -> void:
	for state: String in ["riding", "pause", "auto_pause", "panic", "rescue", "surge"]:
		var ended := _solo_run("end", state)
		var discarded := _solo_run("discard", state)
		assert_eq(ended["app"], "results", state)
		assert_eq(discarded["app"], "title", state)
		assert_eq(discarded["at_once"], ended["at_once"], "identical at once from %s" % state)
		assert_eq(discarded["later"], ended["later"], "identical 10 s later from %s" % state)
		_assert_handed_back(discarded["later"], state)


func _loop_net(hub: RefCounted, net_name: String) -> WlNetSession:
	var net := WlNetSession.new()
	net.name = net_name
	add_child_autofree(net)
	var t := LoopbackTransport.hub_transport(hub)
	net.use_transport(t)
	if t.get_parent() == null:
		net.add_child(t)
	return net


static func _pump(nets: Array, done: Callable, max_iter: int = 400) -> bool:
	for _k in max_iter:
		for n: Variant in nets:
			(n as WlNetSession).poll()
		if done.call():
			return true
	return false


func _player_info(f: AppFixture, net: WlNetSession, games: Dictionary) -> void:
	net.set_local_player_info(
		AppLobbyModel.player_info(f.settings.profile, Wl.FAIR_FTP, {}, games, "ready")
	)


## The shared pause needs every human rider stopped; the other states are the acting rider's own.
func _room_spec(state: String, acting: bool) -> String:
	return _spec_for(state) if acting or state == "shared_pause" else "erg"


## One rider of a two-rider room ends or discards from `state`; {} if the room did not start.
func _room_run(who: String, way: String, state: String) -> Dictionary:
	var registry := get_tree().root.get_node("GameRegistry") as WlGameRegistry
	var games := AppLobbyModel.installed_games(registry)
	var hub: RefCounted = LoopbackTransport.create_hub()
	var hf := _new_fixture(220.0, "Host")
	var hsvc := _real(hf, _room_spec(state, who == "host"))
	var hnet := _loop_net(hub, "HostNet")
	hf.services.net = hnet
	_player_info(hf, hnet, games)
	hnet.host_room(8)
	if not _pump([hnet], func() -> bool: return hnet.room_code != "" and hnet.local_peer != 0):
		fail_test("no room")
		return {}
	hnet.set_game("workout", str(registry.manifest("workout").get("version", "")), "e2e")
	hnet.set_ready(true)
	var cf := _new_fixture(200.0, "Guest")
	var csvc := _real(cf, _room_spec(state, who == "client"))
	var cnet := _loop_net(hub, "ClientNet")
	cf.services.net = cnet
	_player_info(cf, cnet, games)
	cnet.join_room(hnet.room_code)
	var joined := func() -> bool: return cnet.local_peer != 0 and hnet.peers().size() == 2
	if not _pump([hnet, cnet], joined):
		fail_test("no join")
		return {}
	cnet.set_ready(true)
	if not _pump([hnet, cnet], func() -> bool: return hnet.all_ready()):
		fail_test("not ready")
		return {}
	var cs := AppSessionScreen.new()
	cs.services = cf.services
	cs.auto_process = false
	add_child(cs)
	var opened := [false]
	cnet.game_message.connect(
		func(_from: int, d: Dictionary) -> void:
			if str(d.get("type", "")) == "session_start" and not opened[0]:
				opened[0] = true
				cs.enter({"role": Wl.CLIENT, "session_start": d.duplicate(true)})
	)
	var hs := _enter(hf, {"role": Wl.HOST, "game_id": "workout", "content_id": "e2e"})
	if not _pump([hnet, cnet], func() -> bool: return opened[0]):
		fail_test("no session_start")
		remove_child(cs)
		cs.free()
		remove_child(hs)
		hs.leave()
		hs.free()
		return {}
	var me := hs if who == "host" else cs
	var f := hf if who == "host" else cf
	var svc := hsvc if who == "host" else csvc
	_reach(
		me,
		state,
		func() -> void:
			hs.host.step()
			cs.host.step()
	)
	_way_out(me, way)
	var out := _after_leaving(me, svc, f)
	if who == "host":
		var n := 0
		while not cs.finished and n < 400:
			cs.host.step()
			n += 1
		out["client_finished"] = cs.finished
		out["client_app"] = cf.app.state
		cs.leave()
		for _i in 200:
			csvc.step()
		out["client_later"] = _trainer_state(csvc, cf)
	else:
		out["host_finished"] = hs.finished
	for scr: AppSessionScreen in [hs, cs]:
		if not scr._left:
			scr.leave()
		remove_child(scr)
		scr.free()
	return out


func _room_case(who: String, state: String) -> void:
	var what := "%s from %s" % [who, state]
	var ended := _room_run(who, "end", state)
	var discarded := _room_run(who, "discard", state)
	if ended.is_empty() or discarded.is_empty():
		return
	assert_eq(discarded["app"], "title", what)
	assert_eq(discarded["at_once"], ended["at_once"], "identical at once: %s" % what)
	assert_eq(discarded["later"], ended["later"], "identical 10 s later: %s" % what)
	_assert_handed_back(discarded["later"], what)
	if who == "host":
		assert_true(discarded["client_finished"], "the session ended for the client: %s" % what)
		assert_eq(discarded["client_app"], "results", what)
		_assert_handed_back(discarded["client_later"], "the client: %s" % what)
	else:
		assert_false(discarded["host_finished"], "the host rides on: %s" % what)


func test_host_a_discard_leaves_the_trainers_as_end_does() -> void:
	for state: String in ["riding", "shared_pause", "panic", "rescue", "surge"]:
		_room_case("host", state)


## In a room no rider pauses by choice (GameHost.pause() is SOLO only). The session pauses when
## every human rider has stopped (_update_shared_pause), and a client follows it from the roster.
func test_client_a_discard_leaves_the_trainer_as_leave_does() -> void:
	for state: String in ["riding", "shared_pause", "panic", "rescue", "surge"]:
		_room_case("client", state)


# --- pedals, through the real recognizer and the real list ---------------------------------------


func _real_list_solo() -> AppSessionScreen:
	fx.give_profile()
	fx.services.scan_list_factory = func() -> PedalScanList: return PedalScanList.new()
	return (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)


## The rider holds 200 W at 85 rpm; `samples` are [seconds after the confirm opened, watts]. `arm`
## runs on the open confirm. A surge the recognizer fires goes where the router sends it.
func _feed_recognizer(samples: Array, arm: Callable = Callable()) -> Dictionary:
	var s := _real_list_solo()
	s.open_menu()
	s.pick_id("discard")
	if arm.is_valid():
		arm.call(s)
	var gr := GestureRecognizer.new()
	gr.configure(250.0, true)
	var t0 := 30.0
	for i in int(t0):
		gr.on_sample(TrainerSample.make(float(i), 200.0, 85.0))
	var out := {"surges": 0, "screen": s}
	var t := 0.0
	var next := 0
	while t < 12.0 and not s.finished:
		s.tick(DT)
		t += DT
		while next < samples.size() and float(samples[next][0]) <= t + 1e-6:
			var at := t0 + float(samples[next][0])
			var fired := gr.on_sample(TrainerSample.make(at, float(samples[next][1]), 85.0))
			next += 1
			for g: StringName in fired:
				if g == Wl.G_SURGE:
					out["surges"] = int(out["surges"]) + 1
				s.feed_gesture(g)
	return out


func _assert_nothing_picked(run: Dictionary, what: String) -> void:
	var s: AppSessionScreen = run["screen"]
	assert_gt(int(run["surges"]), 0, "%s: the recognizer did fire a surge" % what)
	assert_eq((s.host as FakeHost).discards, 0, what)
	assert_false(s.finished, what)
	assert_eq(s.active_menu().item_count(), 2, "%s: the confirm stays" % what)
	assert_eq(str(s.active_menu().highlighted_id()), "keep", "%s: on Keep riding" % what)


## The review's cases, which the first version's dwell on Yes got wrong.
func test_a_surge_with_sample_jitter_picks_nothing() -> void:
	var run := _feed_recognizer(
		[[0.85, 200.0], [1.85, 200.0], [2.85, 200.0], [3.85, 200.0], [4.95, 300.0], [6.05, 300.0]]
	)
	_assert_nothing_picked(run, "jitter")


func test_a_slow_ramp_into_a_surge_picks_nothing() -> void:
	var run := _feed_recognizer(
		[[1.05, 200.0], [2.05, 200.0], [3.05, 200.0], [4.05, 215.0], [5.05, 300.0], [6.05, 300.0]]
	)
	_assert_nothing_picked(run, "ramp")


func test_a_surge_across_a_ble_gap_picks_nothing() -> void:
	var run := _feed_recognizer([[1.0, 200.0], [2.5, 300.0], [6.5, 300.0]])
	_assert_nothing_picked(run, "BLE gap")


func test_a_surge_with_the_highlight_on_yes_picks_nothing() -> void:
	var run := _feed_recognizer(
		[[1.0, 200.0], [2.0, 300.0], [3.0, 300.0]],
		func(s: AppSessionScreen) -> void: s.feed_action(&"down")
	)
	var s: AppSessionScreen = run["screen"]
	assert_gt(int(run["surges"]), 0, "the recognizer did fire a surge")
	assert_eq(str(s.active_menu().highlighted_id()), "yes", "the keyboard put it there")
	assert_eq((s.host as FakeHost).discards, 0)
	assert_false(s.finished)


func test_the_real_list_takes_the_keyboards_yes() -> void:
	var s := _real_list_solo()
	s.open_menu()
	s.pick_id("discard")
	s.feed_action(&"down")
	s.feed_action(&"confirm")
	assert_eq((s.host as FakeHost).discards, 1)
	assert_eq(fx.app.state, "title")


## The whole chain through the main scene: the rider sits in the open confirm, the governor rescues
## them, and recovering fires a real surge from the real rider. The ride goes on, and the keys
## still work afterwards.
func test_a_rescue_recovery_surge_in_the_confirm_discards_nothing() -> void:
	fx.give_profile(200.0)
	var svc := _real(fx, "erg+cadence_drop:rpm=35,at_target_pct=60,for_s=6")
	var main := open_main()
	fx.services.goto("session", {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"})
	var s := current_screen(main) as AppSessionScreen
	var r := svc.local_rider()
	var surges := [0]
	r.gesture_detected.connect(
		func(g: StringName) -> void:
			if g == Wl.G_SURGE and s.discard_confirm_showing():
				surges[0] += 1
	)
	var rescued := false
	var opened := false
	for _i in MAX_RESCUE_STEPS:
		s.host.step()
		s.tick(DT)
		rescued = rescued or r.governor.is_rescue()
		if not opened and r.platform_time() >= 60.3:
			opened = true
			s.open_menu()
			s.pick_id("discard")
	assert_true(rescued, "the rescue happened")
	assert_gt(surges[0], 0, "its recovery fired a surge in the confirm")
	assert_false(s.discarded, "which discards nothing")
	assert_true(current_screen(main) == s, "the session goes on")
	assert_true(r.recorder != null and r.recorder.is_recording(), "the ride records")
	s.feed_action(&"down")
	s.feed_action(&"confirm")
	assert_true(s.discarded, "the keyboard does")
	assert_true(current_screen(main) is AppTitleScreen)


# --- the title after a discard --------------------------------------------------------------------


## The rider stays on the pedals from the discard on: the mock spins on and the title reads its
## real samples. `no_visit_count` drops the visit rule, leaving only what the discard asks for.
func _spin_on_after_discard(has_profile: bool, no_visit_count: bool = false) -> AppTitleScreen:
	if has_profile:
		fx.give_profile(200.0)
	else:
		fx.settings.profile = RiderProfile.new()
	var svc := _real(fx, "erg")
	var main := open_main()
	fx.services.goto("session", {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"})
	var s := current_screen(main) as AppSessionScreen
	for _i in 200:
		s.host.step()
		s.tick(DT)
	if no_visit_count:
		fx.services.title_visits = 0
	s.open_menu()
	s.pick_id("discard")
	s.pick_id("yes")
	var title := current_screen(main) as AppTitleScreen
	assert_not_null(title, "the title")
	if title == null:
		return null
	assert_eq(title.has_profile, has_profile)
	assert_true(title.zero.need_fresh, "a stretch already running does not count")
	# Far past both holds, on the pedals the whole time.
	for _i in 40 * 20:
		svc.step()
		title.tick(DT)
	assert_true(current_screen(main) == title, "still on the title after 40 s of spinning")
	assert_false(title.started, "no new ride")
	assert_false(title.zero.fired)
	assert_eq(title.zero.held_s, 0.0)
	assert_true(title.zero.armed, "still armed for a fresh start")
	assert_eq(fx.app.state, "title")
	return title


func _stop_then_pedal(title: AppTitleScreen, seconds: float) -> void:
	var t := 1000.0
	title.feed_sample(sample(t, 0.0, 0.0))
	assert_false(title.zero.need_fresh, "a stop clears the wait")
	var left := seconds
	while left >= -1.0 and not title.started:
		t += 1.0
		left -= 1.0
		title.feed_sample(sample(t, 150.0, 85.0))


func test_no_profile_spinning_after_a_discard_starts_no_ride() -> void:
	var title := _spin_on_after_discard(false)
	if title != null:
		assert_eq(title.zero.hold_s, AppZeroTouch.FIRST_RUN_S)
		_stop_then_pedal(title, AppZeroTouch.FIRST_RUN_S)
		assert_true(title.started, "after a stop the first-run rule works again")


func test_a_profile_spinning_after_a_discard_starts_no_ride() -> void:
	var title := _spin_on_after_discard(true)
	if title != null:
		_stop_then_pedal(title, AppZeroTouch.HOLD_START_S)
		assert_true(title.started, "after a stop the 5 s rule works again")


func test_a_profile_on_its_first_title_visit_too() -> void:
	_spin_on_after_discard(true, true)


## The launch visit is unchanged: a first-run rider already pedaling still gets the ride.
func test_a_title_with_no_discard_still_counts_the_stretch() -> void:
	fx.settings.profile = RiderProfile.new()
	var main := open_main()
	var title := current_screen(main) as AppTitleScreen
	assert_false(title.zero.need_fresh)
	assert_eq(title.zero.hold_s, AppZeroTouch.FIRST_RUN_S)
