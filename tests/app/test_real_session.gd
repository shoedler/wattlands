extends "res://tests/app/app_test_base.gd"
## The app shell on the real session path (W2 integration): the real GameHost, the GameRegistry
## autoload's Workout, a real LocalRider on a MockTrainer, the real RideRecorder and, for the
## two-peer case, two real WlNetSessions over a LoopbackTransport hub. Only the App, Settings,
## Rides, InputRouter and TrainerService shells stay doubles (no boot side effects).
## Runs Workout's e2e content (120 s plus the 180 s cool-down) to the results, stepping time by
## hand (screens and scripted peers with auto_process off, GameHosts with realtime off).

const DT := Wl.SIM_DT
## Platform steps a 300 s session needs, with room for the start and the results.
const MAX_STEPS := 7000

var _extra: Array[AppFixture] = []


func after_each() -> void:
	super()
	for f in _extra:
		f.free_all()
	_extra.clear()


## Swap the fixture's session path for the real modules: a real LocalRider around the fixture's
## MockTrainer, the GameRegistry autoload and real GameHosts.
func _go_real(f: AppFixture) -> LocalRider:
	var t := f.fake_trainer()
	var old: LocalRider = t.rider
	t.remove_child(old)
	old.free()
	var r := LocalRider.new()
	r.name = "LocalRider"
	t.add_child(r)
	t.rider = r
	f.services.registry = get_tree().root.get_node("GameRegistry") as WlGameRegistry
	f.services.game_host_factory = func() -> GameHost: return GameHost.new()
	return r


func test_a_solo_session_on_the_real_game_host_reaches_the_results() -> void:
	fx.give_profile(200.0)
	var rider := _go_real(fx)
	var s := open_screen(AppSessionScreen.new(), {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"}) as AppSessionScreen
	assert_eq(s.error, "", "the session set up")
	assert_true(s.host is GameHost and not (s.host is FakeHost), "the real GameHost")
	if s.host == null:
		return
	assert_eq(s.host.state, "running")
	assert_true(fx.trainer.is_external_tick(), "the GameHost ticks the rider, TrainerService does not")
	assert_same(s.local_rider(), rider)
	assert_true(rider.recorder != null and rider.recorder.is_recording(), "the ride records from the start")
	var states: Array[String] = []
	s.host.state_changed.connect(func(st: String) -> void: states.append(st))
	var n := 0
	while not s.finished and n < MAX_STEPS:
		s.host.step()
		n += 1
	assert_true(s.finished, "results after %d steps" % n)
	assert_true(states.has("cooldown") and states.has("results"), "cool-down, then results: %s" % str(states))
	assert_eq(fx.app.state, "results")
	var p: Dictionary = fx.app.params
	assert_not_null(p.get("results"), "GameResults reach the results screen")
	var fit := str(p.get("fit_path", ""))
	assert_true(fit != "" and FileAccess.file_exists(fit), "the FIT was saved: %s" % fit)
	var laps: Array = (p.get("summary", {}) as Dictionary).get("laps", [])
	assert_eq(laps.size(), 4, "three e2e phases and the cool-down")
	assert_almost_eq(float((p["summary"] as Dictionary).get("duration_s", 0.0)), 300.0, 1.0,
		"the whole session recorded, nothing from menu time")


## The scripted-peer flow of docs/ARCHITECTURE.md in one process: a host and a client hosting and
## joining through NetSession, readying up, the client's GameHost opened by the host's
## session_start, Autopilot through the session, results on both, then exit 0.
func test_scripted_host_and_client_play_a_session_over_loopback() -> void:
	var hub: RefCounted = LoopbackTransport.create_hub()
	var host_fx := fx
	var client_fx := AppFixture.new()
	_extra.append(client_fx)
	var peers: Array[AppScriptedPeer] = []
	var lines := {"host": [], "client": []}
	for i in 2:
		var f: AppFixture = host_fx if i == 0 else client_fx
		f.give_profile(220.0 if i == 0 else 180.0, "Host" if i == 0 else "Guest")
		f.services.utc_override = 1800000000 + i
		_go_real(f)
		var t := LoopbackTransport.hub_transport(hub)
		var net := WlNetSession.new()
		net.name = "Net%d" % i
		add_child_autofree(net)
		net.use_transport(t)
		if t.get_parent() == null:
			net.add_child(t)
		f.services.net = net
		var c := AppScriptedConfig.new()
		c.enabled = true
		c.role = Wl.HOST if i == 0 else Wl.CLIENT
		c.game_id = "workout"
		c.e2e = true
		c.wait_peers = 2
		c.mock_trainer = "erg"
		c.autopilot = true
		var peer := AppScriptedPeer.new()
		peer.name = "Scripted%d" % i
		peer.services = f.services
		peer.config = c
		peer.install_logger = false
		peer.auto_process = false
		var key := "host" if i == 0 else "client"
		peer.out = func(line: String) -> void: (lines[key] as Array).append(line)
		add_child(peer)
		_opened.append(peer)
		peers.append(peer)
	peers[0].start()
	var code := ""
	for _k in 50:
		(peers[0].services.net as WlNetSession).poll()
		if peers[0].room != "":
			break
	code = peers[0].room
	assert_ne(code, "", "the host has a room")
	peers[1].config.join_code = code
	peers[1].start()
	var n := 0
	while n < MAX_STEPS and not (peers[0].phase == "done" and peers[1].phase == "done"):
		for p in peers:
			if p.phase == "done":
				continue
			if p.host == null or not is_instance_valid(p.host):
				(p.services.net as WlNetSession).poll()
			else:
				p.host.step()
			p.step(DT)
		n += 1
	for i in 2:
		var p := peers[i]
		var who := "host" if i == 0 else "client"
		assert_eq(p.exit_reason, "complete", "%s: %s after %d steps; out %s" % [who, p.exit_reason, n, str(lines[who])])
		assert_eq(p.exit_code, AppScriptedPeer.EXIT_OK, who)
		assert_true((lines[who] as Array).has("WATTLANDS_STATE running"), "%s ran the session" % who)
		assert_true((lines[who] as Array).has("WATTLANDS_STATE cooldown"), "%s saw the cool-down" % who)
		assert_true((lines[who] as Array).has("WATTLANDS_DONE complete"), who)
		assert_not_null(p.results, "%s got the results" % who)
		assert_true(p.fit_path != "" and FileAccess.file_exists(p.fit_path), "%s saved its FIT" % who)
	assert_true((lines["host"] as Array).has("WATTLANDS_ROOM %s" % code))
	assert_ne(peers[0].fit_path, peers[1].fit_path, "each peer its own ride")
	var client_states: Array = (peers[1].host.players() if peers[1].host != null else []).map(func(s: PlayerSlot) -> int: return s.peer_id)
	assert_eq(client_states.size(), 2, "the client's GameHost got both players from session_start")
	assert_eq(host_fx.quits, [0])
	assert_eq(client_fx.quits, [0])


func _real_router() -> WlInputRouter:
	var router := WlInputRouter.new()
	router.load_on_ready = false
	router.bus = fx.bus
	router.profile = fx.settings.profile
	add_child_autofree(router)
	router.set_process(false)
	router.set_process_input(false)
	return router


## The session screen owns pause and its overlay menu; the GameHost reads input through
## AppSessionInput, so it neither undoes the screen's pause on its next tick nor resumes on the
## confirm that picks an overlay item.
func test_the_screen_owns_pause_and_the_overlay_menu() -> void:
	fx.give_profile(200.0)
	_go_real(fx)
	var router := _real_router()
	fx.services.input = router
	var s := open_screen(AppSessionScreen.new(), {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"}) as AppSessionScreen
	assert_not_null(s.session_input, "the GameHost reads input through the screen")
	if s.host == null:
		return
	for _i in 20:
		s.host.step()
	router.inject_action(&"pause")
	assert_eq(s.host.state, "paused", "P pauses at once")
	assert_true(s.overlay.visible)
	for _i in 40:
		s.host.step()
	assert_eq(s.host.state, "paused", "the GameHost does not toggle it back")
	assert_eq(menu(s).highlighted_id(), "resume")
	router.inject_action(&"confirm")
	assert_eq(s.host.state, "running", "Resume picked from the overlay")
	assert_false(s.overlay.visible)
	for _i in 20:
		s.host.step()
	assert_eq(s.host.state, "running", "the confirm did not reach the GameHost as a second toggle")


func test_session_input_filters_for_the_game_host() -> void:
	var router := _real_router()
	var owned := [false]
	var menu_rider: LocalRider = autofree(FakeRider.new())
	var si := AppSessionInput.create(router, func() -> bool: return owned[0], func() -> LocalRider: return menu_rider)
	add_child_autofree(si)
	router.inject_action(&"pause")
	router.inject_action(&"ability_1")
	router.inject_action(&"confirm")
	assert_eq(si.take_actions(), [&"ability_1", &"confirm"] as Array[StringName], "pause is the screen's")
	owned[0] = true
	router.inject_action(&"confirm")
	router.inject_action(&"panic")
	router.inject_action(&"down")
	assert_eq(si.take_actions(), [&"panic"] as Array[StringName], "the overlay owns input; panic always passes")
	router.inject_gesture(Wl.G_SURGE)
	assert_eq(si.take_gestures(), [Wl.G_SURGE] as Array[StringName])
	var session_rider: LocalRider = autofree(FakeRider.new())
	si.attach_rider(session_rider)
	assert_same(router.attached_rider(), session_rider)
	si.detach_rider()
	assert_same(router.attached_rider(), menu_rider, "menus after the session get pedal gestures again")
