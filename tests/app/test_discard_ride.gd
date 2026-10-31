extends "res://tests/app/app_test_base.gd"
## Discard the ride (session screen, GameHost.discard_own_ride): the menu item and its confirm, on
## test doubles, then real sessions (real GameHost, Workout, LocalRider and RideRecorder on a
## MockTrainer; host and client over a LoopbackTransport hub) proving what stays on disk.

const DT := Wl.SIM_DT
## Enough steps to reach the results after a host ended the session.
const MAX_STEPS := 400

var _extra: Array[AppFixture] = []


func after_each() -> void:
	super()
	for f in _extra:
		f.free_all()
	_extra.clear()


func _solo() -> AppSessionScreen:
	fx.give_profile()
	return (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)


func _host() -> AppSessionScreen:
	fx.give_profile()
	var net := fx.fake_net()
	net.local_peer = 1
	net.add_human(1, "Ada", 250.0)
	net.lobby = {
		"game_id": "workout",
		"game_version": "1.0.0",
		"content_id": "easy_30",
		"scaling": Wl.FAIR_FTP,
		"settings": {"options": {}},
		"player_options": {}
	}
	return (
		open_screen(
			AppSessionScreen.new(), {"role": Wl.HOST, "game_id": "workout", "content_id": "easy_30"}
		)
		as AppSessionScreen
	)


func _client() -> AppSessionScreen:
	fx.give_profile()
	fx.fake_net().local_peer = 2
	var a := PlayerSlot.new()
	a.peer_id = 1
	a.apply_look(0)
	var b := PlayerSlot.new()
	b.peer_id = 2
	b.apply_look(1)
	var start := {
		"type": "session_start",
		"game_id": "workout",
		"content_id": "e2e",
		"seed": 1,
		"players": [a.to_dict(), b.to_dict()],
		"options": {},
		"scaling": Wl.FAIR_FTP
	}
	return (
		open_screen(AppSessionScreen.new(), {"role": Wl.CLIENT, "session_start": start})
		as AppSessionScreen
	)


func _open(role: String) -> AppSessionScreen:
	match role:
		Wl.HOST:
			return _host()
		Wl.CLIENT:
			return _client()
	return _solo()


## The confirm, from the ride menu.
func _open_confirm(s: AppSessionScreen) -> void:
	s.open_menu()
	confirm_pick(s, "discard")


func _tick_for(s: AppSessionScreen, seconds: float) -> void:
	var left := seconds
	while left > 1e-6:
		s.tick(DT)
		left -= DT


func _fake(s: AppSessionScreen) -> FakeHost:
	return s.host as FakeHost


# --- the ride menu -------------------------------------------------------------------------------


func test_the_item_sits_under_end_or_leave_for_every_role() -> void:
	for role: String in [Wl.SOLO, Wl.HOST, Wl.CLIENT]:
		var s := _open(role)
		s.open_menu()
		assert_eq(menu(s).ids(), ["resume", "panic", "end", "discard"], role)
		assert_eq(menu(s).text_of("discard"), AppScreen.t("APP_SESSION_DISCARD"), role)


func test_the_panic_menu_has_it_too() -> void:
	var s := _solo()
	s.panic()
	assert_eq(menu(s).ids(), ["resume_trainer", "end", "discard"])


func test_the_error_menu_does_not() -> void:
	fx.give_profile()
	fx.services.game_host_factory = func() -> GameHost:
		var h := FakeHost.new()
		h.setup_error = "broken"
		fx.hosts.append(h)
		return h
	var s := (
		open_screen(
			AppSessionScreen.new(),
			{"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30", "quick": true}
		)
		as AppSessionScreen
	)
	assert_ne(s.error, "")
	assert_eq(menu(s).ids(), ["leave"])


# --- the confirm ---------------------------------------------------------------------------------


func test_the_confirm_has_keep_riding_first_and_says_what_happens() -> void:
	var details := {
		Wl.SOLO: "APP_SESSION_DISCARD_DETAIL",
		Wl.HOST: "APP_SESSION_DISCARD_DETAIL_HOST",
		Wl.CLIENT: "APP_SESSION_DISCARD_DETAIL_CLIENT"
	}
	for role: String in details.keys():
		var s := _open(role)
		_open_confirm(s)
		assert_eq(menu(s).ids(), ["keep", "yes"], role)
		assert_eq(menu(s).highlighted_id(), "keep", role)
		assert_eq(menu(s).text_of("keep"), AppScreen.t("APP_SESSION_DISCARD_KEEP"), role)
		assert_eq(menu(s).text_of("yes"), AppScreen.t("APP_SESSION_DISCARD_YES"), role)
		assert_eq(s.overlay_title.text, AppScreen.t("APP_SESSION_DISCARD_TITLE"), role)
		assert_string_starts_with(s.overlay_detail.text, AppScreen.t(details[role]), role)
		assert_string_ends_with(s.overlay_detail.text, AppScreen.t("APP_SESSION_DISCARD_HOW"), role)
		assert_true(s.overlay_detail.visible, role)
		assert_eq(_fake(s).discards, 0, "opening it discards nothing")
		assert_false(s.finished, role)
	assert_string_contains(AppScreen.t("APP_SESSION_DISCARD_DETAIL_HOST"), "everyone")


func test_back_returns_to_the_ride_menu() -> void:
	var s := _solo()
	_open_confirm(s)
	s.feed_action(&"back")
	assert_eq(menu(s).ids(), ["resume", "panic", "end", "discard"])
	assert_eq(s.overlay_title.text, AppScreen.t("APP_SESSION_MENU"))
	assert_false(s.overlay_detail.visible, "the ride menu has no detail line")
	assert_true(s.overlay.visible)
	assert_eq(_fake(s).discards, 0)
	assert_eq(_fake(s).ended_reasons, [] as Array[String])


func test_a_coast_backs_out_like_back() -> void:
	var s := _solo()
	_open_confirm(s)
	s.feed_gesture(Wl.G_COAST)
	assert_eq(menu(s).ids(), ["resume", "panic", "end", "discard"])
	assert_eq(_fake(s).discards, 0)


func test_keep_riding_closes_the_overlay_and_rides_on() -> void:
	var s := _solo()
	s.feed_action(&"pause")
	assert_eq(_fake(s).pause_reasons, ["user"] as Array[String])
	confirm_pick(s, "discard")
	confirm_pick(s, "keep")
	assert_false(s.overlay.visible)
	assert_eq(_fake(s).resumes, 1, "like the menu's Resume")
	assert_eq(_fake(s).discards, 0)
	assert_eq(_fake(s).ended_reasons, [] as Array[String])


func test_keep_riding_in_a_panic_stays_safe() -> void:
	var s := _solo()
	s.panic()
	confirm_pick(s, "discard")
	assert_eq(s.overlay_title.text, AppScreen.t("APP_SESSION_DISCARD_TITLE"))
	confirm_pick(s, "keep")
	assert_true(s.panicked, "only Resume the trainer leaves a panic")
	assert_eq(menu(s).ids(), ["resume_trainer", "end", "discard"])
	assert_eq(s.overlay_title.text, AppScreen.t("APP_SESSION_PANIC_TITLE"))
	assert_eq(_fake(s).discards, 0)


func test_a_panic_closes_the_confirm() -> void:
	var s := _solo()
	_open_confirm(s)
	s.feed_action(&"panic")
	assert_true(s.panicked)
	assert_eq(
		menu(s).ids(), ["resume_trainer", "end", "discard"], "the panic menu, not the confirm"
	)
	assert_eq(s.overlay_title.text, AppScreen.t("APP_SESSION_PANIC_TITLE"))
	assert_eq((fx.trainer.local_rider() as FakeRider).panics, 1)


func test_the_session_ending_while_the_confirm_shows_opens_the_results() -> void:
	var s := _solo()
	_open_confirm(s)
	_fake(s).finish_with(GameResults.new())
	assert_eq(fx.app.state, "results", "the ride finished: it is kept")
	assert_eq(_fake(s).discards, 0)


# --- pedals and timers never discard --------------------------------------------------------------


## The pick handler refuses an auto pick even if the list were set to make one.
func test_an_automatic_pick_never_discards() -> void:
	var s := _solo()
	_open_confirm(s)
	var m := menu(s)
	m.pedal_nav = true
	m.erg_auto_confirm = true
	m.set_highlight(m.index_of_id("yes"))
	_tick_for(s, m.auto_confirm_after_s() + 1.0)
	assert_true(m.picks.size() > 0, "the list did pick by itself")
	assert_eq((m.picks[0] as Array)[1], "yes")
	assert_eq((m.picks[0] as Array)[2], "auto")
	assert_eq(_fake(s).discards, 0)
	assert_eq(_fake(s).ended_reasons, [] as Array[String])
	assert_false(s.finished)
	assert_eq(menu(s).ids(), ["keep", "yes"], "the confirm stays")


func test_a_confirm_left_open_for_ten_minutes_sits_on_keep_riding() -> void:
	for mode: String in [Wl.ERG, Wl.SIM]:
		var s := _solo()
		(fx.trainer.local_rider() as FakeRider).tm.mode = mode
		assert_true(menu_scans_before_confirm(s), "the ride menu scans")
		_open_confirm(s)
		var m := menu(s)
		assert_false(m.pedal_nav, "no pedal navigation on the confirm")
		assert_false(m.scanning)
		assert_false(m.erg_auto_confirm)
		assert_false(m.follow_local_mode)
		var moved := false
		for _i in 600 * 20:
			s.tick(DT)
			moved = moved or m.highlighted_id() != "keep"
		assert_false(moved, "the highlight stays on Keep riding in %s" % mode)
		assert_eq(m.picks, [], "nothing picked")
		assert_eq(_fake(s).discards, 0)
		assert_false(s.finished)


func menu_scans_before_confirm(s: AppSessionScreen) -> bool:
	s.open_menu()
	return menu(s).scanning


func test_a_surge_does_nothing_on_the_confirm() -> void:
	var s := _solo()
	_open_confirm(s)
	var m := menu(s)
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(m.picks, [], "not on Keep riding")
	assert_true(s.overlay.visible)
	s.feed_action(&"down")
	assert_eq(m.highlighted_id(), "yes", "the keyboard moves")
	_tick_for(s, 30.0)
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(m.picks, [], "not on Yes, however long it rested there")
	assert_eq(_fake(s).discards, 0)
	s.feed_action(&"confirm")
	assert_eq(_fake(s).discards, 1, "the keyboard picks it")
	assert_eq(fx.app.state, "title")


func test_a_coast_never_backs_out_in_erg() -> void:
	var s := _solo()
	(fx.trainer.local_rider() as FakeRider).tm.mode = Wl.ERG
	_open_confirm(s)
	s.feed_gesture(Wl.G_COAST)
	assert_eq(menu(s).ids(), ["keep", "yes"], "BRIEF 3.5")


func test_a_pause_does_not_change_the_confirm() -> void:
	var s := _solo()
	_open_confirm(s)
	var m := menu(s)
	_fake(s).pause("coasting")
	fx.bus.paused_changed.emit(true, "coasting")
	assert_true(s.auto_paused())
	assert_eq(menu(s), m, "the confirm stays")
	assert_eq(s.overlay_title.text, AppScreen.t("APP_SESSION_DISCARD_TITLE"))
	assert_false(m.scanning)
	assert_eq(m.highlighted_id(), "keep")
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(_fake(s).discards, 0)
	assert_eq(_fake(s).resumes, 0, "a surge does not pick Keep riding either")
	assert_eq(menu(s), m)


func test_pedaling_out_of_an_auto_pause_closes_the_confirm() -> void:
	var s := _solo()
	_open_confirm(s)
	_fake(s).pause("coasting")
	fx.bus.paused_changed.emit(true, "coasting")
	fx.bus.paused_changed.emit(false, "pedaling")
	assert_false(s.overlay.visible)
	assert_eq(_fake(s).discards, 0)
	s.open_menu()
	assert_eq(menu(s).ids(), ["resume", "panic", "end", "discard"], "a fresh ride menu")


# --- yes, discard (doubles) ----------------------------------------------------------------------


func test_solo_discard_ends_like_end_the_ride_and_goes_to_the_title() -> void:
	var s := _solo()
	_open_confirm(s)
	confirm_pick(s, "yes")
	assert_eq(_fake(s).discards, 1)
	assert_eq(_fake(s).ended_reasons, ["ended_by_rider"] as Array[String], "End's path")
	assert_eq(fx.app.state, "title", "no results screen")
	assert_true(s.finished)
	assert_eq(fx.fake_net().calls_named("leave_when_flushed").size(), 1)


func test_client_discard_leaves_like_leave_the_ride() -> void:
	var s := _client()
	_open_confirm(s)
	confirm_pick(s, "yes")
	assert_eq(_fake(s).discards, 1)
	assert_eq(_fake(s).ended_reasons, ["left"] as Array[String], "Leave's path")
	assert_eq(fx.fake_net().calls_named("leave").size(), 1)
	assert_eq(fx.app.state, "title", "no results screen")


func test_host_discard_ends_for_everyone_then_leaves_once_flushed() -> void:
	var s := _host()
	_open_confirm(s)
	confirm_pick(s, "yes")
	assert_eq(_fake(s).discards, 1)
	assert_eq(_fake(s).ended_reasons, ["ended_by_rider"] as Array[String], "End's path")
	assert_eq(fx.fake_net().calls_named("leave").size(), 0, "a plain leave drops queued frames")
	assert_eq(fx.fake_net().calls_named("leave_when_flushed").size(), 1)
	assert_eq(fx.app.state, "title", "no results screen")


## A pedal-only rider on the main scene: the ride menu still scans and End is still in reach, the
## confirm takes no surge, and a coast leaves it. The keys then discard, and the screen swap hands
## the rider back to menu time as End's way through the results does.
func test_pedals_reach_the_confirm_and_only_the_keys_get_past_it() -> void:
	fx.give_profile()
	var m := open_main()
	fx.services.goto("session", {"role": Wl.SOLO, "game_id": "workout", "content_id": "easy_30"})
	var s := current_screen(m) as AppSessionScreen
	assert_not_null(s, "the session opened")
	if s == null:
		return
	assert_true(fx.trainer.is_external_tick(), "the session ticks the rider")
	s.open_menu()
	assert_true(scan_to(s, "end"), "the scan reaches End the ride")
	assert_true(scan_to(s, "discard"), "and the item")
	fx.input.inject_gesture(Wl.G_SURGE)
	assert_eq(menu(s).ids(), ["keep", "yes"])
	for _i in 10:
		_tick_for(s, 1.0)
		fx.input.inject_gesture(Wl.G_SURGE)
	assert_eq(menu(s).ids(), ["keep", "yes"], "surges change nothing")
	assert_eq(menu(s).highlighted_id(), "keep")
	assert_true(current_screen(m) == s, "still riding")
	fx.input.inject_gesture(Wl.G_COAST)
	assert_eq(menu(s).ids(), ["resume", "panic", "end", "discard"], "a coast leaves it")
	assert_true(menu(s).scanning, "the ride menu scans again")
	fx.input.inject_gesture(Wl.G_SURGE)
	assert_eq(menu(s).ids(), ["keep", "yes"], "reopened")
	fx.input.inject_action(&"down")
	fx.input.inject_action(&"confirm")
	assert_true(current_screen(m) is AppTitleScreen, "the title")
	assert_false(fx.trainer.is_external_tick(), "menu time ticks the rider again")


# --- real sessions -------------------------------------------------------------------------------


## Swap the fixture's session path for the real modules (see test_real_session.gd).
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


func _open_real_solo() -> AppSessionScreen:
	fx.give_profile(200.0)
	_go_real(fx)
	return (
		open_screen(
			AppSessionScreen.new(), {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"}
		)
		as AppSessionScreen
	)


func _progress_file() -> String:
	return Paths.progress_path("workout")


func _ride_files() -> PackedStringArray:
	return DirAccess.get_files_at(Paths.rides_dir())


func _files_ending(ext: String) -> Array:
	return Array(_ride_files()).filter(func(f: String) -> bool: return f.get_extension() == ext)


## The confirm's Yes, by keyboard.
func _discard(s: AppSessionScreen) -> void:
	_open_confirm(s)
	assert_eq(menu(s).ids(), ["keep", "yes"])
	confirm_pick(s, "yes")


func _bus_autoload() -> WlEventBus:
	return AutoloadLookup.bus()


## The control: on the same session, End the ride writes everything the discard must not.
func test_end_the_ride_writes_the_fit_summary_and_progress() -> void:
	var s := _open_real_solo()
	for _i in 200:
		s.host.step()
	assert_eq(_ride_files().size(), 0, "nothing on disk during the ride")
	assert_false(FileAccess.file_exists(_progress_file()))
	s.open_menu()
	confirm_pick(s, "end")
	assert_eq(fx.app.state, "results")
	assert_eq(_files_ending("fit").size(), 1)
	assert_eq(_files_ending("json").size(), 1)
	assert_true(FileAccess.file_exists(_progress_file()))


func test_a_real_solo_discard_keeps_nothing() -> void:
	var s := _open_real_solo()
	var rider := s.local_rider()
	for _i in 200:
		s.host.step()
	assert_true(rider.recorder != null and rider.recorder.is_recording(), "the ride records")
	assert_eq(_ride_files().size(), 0, "the ride is in memory only: no partial file")
	var global_bus := _bus_autoload()
	watch_signals(global_bus)
	watch_signals(fx.bus)
	_discard(s)
	assert_eq(fx.app.state, "title", "no results screen")
	assert_false(fx.app.params.has("results"))
	assert_eq(s.host.state, "ended", "the session ended as End does")
	assert_eq(s.host.end_reason, "ended_by_rider")
	assert_eq(_ride_files().size(), 0, "no FIT, no summary (the summaries are the ride history)")
	assert_false(FileAccess.file_exists(Paths.upload_queue_path()), "no upload queued")
	assert_false(FileAccess.file_exists(_progress_file()), "no progress")
	assert_null(s.host.ctx.progress.get_value("rides"), "not applied in memory either")
	assert_eq(s.host.fit_paths(), {})
	assert_signal_not_emitted(global_bus, "ride_saved", "so no auto-upload and no stale ride text")
	assert_signal_not_emitted(fx.bus, "ride_saved")
	assert_signal_not_emitted(fx.bus, "results_ready")
	assert_signal_not_emitted(fx.bus, "unlocks_ready")
	# The paths that save a ride still recording: an app quit, a trainer switch, a new setup.
	assert_null(rider.recorder)
	assert_eq(rider.finish_ride(), "")
	assert_eq(_ride_files().size(), 0, "no later path saves it")


## The trainer after it: tests/app/test_discard_ride_stack.gd, on the real WlTrainerService.
func test_a_discard_from_the_panic_menu_keeps_nothing() -> void:
	var s := _open_real_solo()
	for _i in 200:
		s.host.step()
	s.panic()
	confirm_pick(s, "discard")
	confirm_pick(s, "yes")
	assert_eq(fx.app.state, "title")
	assert_eq(_ride_files().size(), 0)
	assert_false(FileAccess.file_exists(_progress_file()))


func test_a_ride_already_over_can_not_be_discarded() -> void:
	var s := _open_real_solo()
	for _i in 200:
		s.host.step()
	s.host.end_session("ended_by_rider")
	assert_false(s.host.discard_own_ride())
	assert_eq(_files_ending("fit").size(), 1, "its FIT stays")


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


func _open_on(f: AppFixture, s: AppSessionScreen, params: Dictionary) -> AppSessionScreen:
	s.services = f.services
	s.auto_process = false
	add_child(s)
	_opened.append(s)
	s.enter(params)
	return s


func _give_info(f: AppFixture, net: WlNetSession, games: Dictionary) -> void:
	net.set_local_player_info(
		AppLobbyModel.player_info(f.settings.profile, Wl.FAIR_FTP, {}, games, "ready")
	)


## A real host screen (on fx) and client screen (on the returned fixture) in a running session:
## {"host": screen, "client": screen, "cfx": fixture, "hnet": net, "cnet": net}; {} on a failure.
func _real_room() -> Dictionary:
	var registry := get_tree().root.get_node("GameRegistry") as WlGameRegistry
	var games := AppLobbyModel.installed_games(registry)
	var hub: RefCounted = LoopbackTransport.create_hub()
	fx.give_profile(220.0, "Host")
	_go_real(fx)
	var hnet := _loop_net(hub, "HostNet")
	fx.services.net = hnet
	_give_info(fx, hnet, games)
	hnet.host_room(8)
	if not _pump([hnet], func() -> bool: return hnet.room_code != "" and hnet.local_peer != 0):
		fail_test("the host has no room")
		return {}
	hnet.set_game("workout", str(registry.manifest("workout").get("version", "")), "e2e")
	hnet.set_ready(true)
	var cfx := AppFixture.new()
	_extra.append(cfx)
	cfx.give_profile(200.0, "Guest")
	_go_real(cfx)
	var cnet := _loop_net(hub, "ClientNet")
	cfx.services.net = cnet
	_give_info(cfx, cnet, games)
	cnet.join_room(hnet.room_code)
	if not _pump(
		[hnet, cnet], func() -> bool: return cnet.local_peer != 0 and hnet.peers().size() == 2
	):
		fail_test("the client did not join")
		return {}
	cnet.set_ready(true)
	if not _pump([hnet, cnet], func() -> bool: return hnet.all_ready()):
		fail_test("not everyone is ready")
		return {}
	var cs := AppSessionScreen.new()
	var opened := [false]
	cnet.game_message.connect(
		func(_from: int, d: Dictionary) -> void:
			if str(d.get("type", "")) == "session_start" and not opened[0]:
				opened[0] = true
				_open_on(cfx, cs, {"role": Wl.CLIENT, "session_start": d.duplicate(true)})
	)
	var hs := (
		open_screen(
			AppSessionScreen.new(), {"role": Wl.HOST, "game_id": "workout", "content_id": "e2e"}
		)
		as AppSessionScreen
	)
	if hs.error != "" or not _pump([hnet, cnet], func() -> bool: return opened[0]):
		fail_test("the session did not start: %s" % hs.error)
		if not opened[0]:
			cs.free()
		return {}
	if cs.error != "":
		fail_test("the client session did not start: %s" % cs.error)
		return {}
	for _i in 100:
		hs.host.step()
		cs.host.step()
	return {"host": hs, "client": cs, "cfx": cfx, "hnet": hnet, "cnet": cnet}


## The host discards: its session ends for everyone. It leaves at once here (nothing queued), so
## the results, session_end and host_left reach the client in one poll, the hardest case.
func test_a_real_host_discard_ends_for_all_and_the_client_keeps_its_ride() -> void:
	var room := _real_room()
	if room.is_empty():
		return
	var hs: AppSessionScreen = room["host"]
	var cs: AppSessionScreen = room["client"]
	var cfx: AppFixture = room["cfx"]
	var hnet: WlNetSession = room["hnet"]
	var host_rider := hs.local_rider()
	var client_rider := cs.local_rider()
	var client_ride_id: String = (client_rider.recorder as RideRecorder).ride_id
	assert_true(client_rider.recorder.is_recording())
	watch_signals(fx.bus)
	_discard(hs)
	assert_eq(fx.app.state, "title", "the host: no results screen")
	assert_eq(hs.host.state, "ended")
	assert_eq(hnet.role, "", "the host left the room")
	assert_null(host_rider.recorder)
	assert_eq(_ride_files().size(), 0, "the host wrote no FIT and no summary")
	assert_false(FileAccess.file_exists(_progress_file()), "the host saved no progress")
	assert_null(hs.host.ctx.progress.get_value("rides"))
	assert_signal_not_emitted(fx.bus, "results_ready")
	var n := 0
	while not cs.finished and n < MAX_STEPS:
		cs.host.step()
		n += 1
	assert_true(cs.finished, "the session ended for the client")
	assert_eq(cfx.app.state, "results", "the client gets its results screen")
	var p: Dictionary = cfx.app.params
	var r: GameResults = p.get("results") as GameResults
	assert_not_null(r, "with the host's results, not an empty page")
	if r != null:
		assert_false(r.row(cs.local_peer()).is_empty(), "the client's row")
	assert_true(bool(p.get("host_left", false)), "and the note that the host left")
	var fit := str(p.get("fit_path", ""))
	assert_true(fit != "" and FileAccess.file_exists(fit), "the client's FIT: %s" % fit)
	assert_eq(_files_ending("fit").size(), 1, "the client's FIT only")
	assert_eq(str((p["summary"] as Dictionary).get("ride_id", "")), client_ride_id)
	assert_true(FileAccess.file_exists(_progress_file()), "the client's progress")
	assert_eq(cs.host.ctx.progress.get_value("rides"), 1.0)


func test_a_real_client_discard_leaves_and_the_host_rides_on() -> void:
	var room := _real_room()
	if room.is_empty():
		return
	var hs: AppSessionScreen = room["host"]
	var cs: AppSessionScreen = room["client"]
	var cfx: AppFixture = room["cfx"]
	var cnet: WlNetSession = room["cnet"]
	var client_rider := cs.local_rider()
	var cbus: WlEventBus = cfx.bus
	watch_signals(cbus)
	_discard_on(cfx, cs)
	assert_eq(cfx.app.state, "title", "the client: no results screen")
	assert_eq(cs.host.state, "ended")
	assert_eq(cs.host.end_reason, "left", "Leave's path")
	assert_eq(cnet.role, "", "the client left the room")
	assert_null(client_rider.recorder)
	assert_eq(_ride_files().size(), 0, "the client wrote no FIT and no summary")
	assert_false(FileAccess.file_exists(_progress_file()), "the client saved no progress")
	assert_signal_not_emitted(cbus, "results_ready")
	for _i in 100:
		hs.host.step()
	assert_false(hs.finished, "the host's session goes on")
	assert_true(hs.host.state == "running" or hs.host.state == "cooldown", hs.host.state)
	assert_true(hs.local_rider().recorder.is_recording(), "the host's ride records")
	hs.open_menu()
	confirm_pick(hs, "end")
	assert_eq(fx.app.state, "results", "End still gives the host its results")
	assert_eq(_files_ending("fit").size(), 1, "the host's FIT only")
	assert_eq(hs.host.ctx.progress.get_value("rides"), 1.0)
	assert_null(cs.host.ctx.progress.get_value("rides"), "the client's store stays untouched")


func _discard_on(f: AppFixture, s: AppSessionScreen) -> void:
	s.open_menu()
	var m := s.active_menu() as FakeScanList
	m.set_highlight(m.index_of_id("discard"))
	s.feed_action(&"confirm")
	m = s.active_menu() as FakeScanList
	assert_eq(m.ids(), ["keep", "yes"])
	m.set_highlight(m.index_of_id("yes"))
	s.feed_action(&"confirm")
	assert_eq(f.app.state, "title")
