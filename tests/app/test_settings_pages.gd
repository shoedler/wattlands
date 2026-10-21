extends "res://tests/app/app_test_base.gd"
## Settings pages (W3 SAF-8, ZIH-3, ZIH-4; W4r2 R6, R7, R28):
## - BRIEF 4.6.9 "on disconnect: try SIM flat, then Stop": Disconnect, switching trainers and
##   "use the mock trainer" go through WlTrainerService (the real one here, with a real
##   FtmsConnectionManager, FtmsClient and FtmsTrainer over an emulated KICKR CORE whose lock is
##   off), which makes the trainer safe and drops the link only once the control point sent SIM
##   flat and Stop, however slowly it answers (R6). Picking the trainer that is already linked
##   changes nothing (R7). Leaving the page never cuts the wait short.
## - BRIEF 3.5/3.9: the Controls rows fit the 640 px menu column; a capture ends when the page is
##   left (coast or back) and the controller's B button cancels it like Esc; the content column's
##   list of every binding follows a rebind (R28).
## - BRIEF 3.5 (W4fin): the Controls page says Esc or B cancels, and its Reset to defaults row
##   (after a Keep / Reset confirm) puts every default back, Esc and B on back included, and
##   writes input.cfg; it works with pedal-scan alone, through the real InputRouter.
## - BRIEF 3.9 (W4fin): the Settings menu column scrolls. At 1920 x 1080 every row the scan,
##   the keyboard or a controller highlights is fully on screen (Controls, Strava), Back is
##   reached and picked, and the pages that fit never scroll.

const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const DT := Wl.SIM_DT
const ADDR := "C4:9D:A1:00:2B:7E"
const OTHER := "11:22:33:44:55:66"
const FLAT := "write 2ad9 11000000002833"
const STOP := "write 2ad9 0801"


## The emulated KICKR plus what FtmsConnectionManager needs from a backend (as in
## tests/core/integration/test_safe_unlink.gd).
class KickrLink:
	extends "res://tests/trainer/fake_kickr_transport.gd"
	var linked: String = ""

	func initialize() -> void:
		adapter_ready.emit(true, "")

	func start_scan(_seconds: float) -> void:
		pass

	func stop_scan() -> void:
		pass

	func connect_device(address: String) -> void:
		ops.append("connect " + address)
		linked = address
		_queue("device_connected", [address])

	func disconnect_device() -> void:
		ops.append("disconnect " + linked)
		_queue("device_disconnected", [linked, "local"])


var _link: KickrLink = null
var _client: FtmsClient = null
var _manager: FtmsConnectionManager = null
var _svc: WlTrainerService = null
## The root window's size before a test set 1920 x 1080 (zero when it didn't).
var _old_root_size: Vector2i = Vector2i.ZERO


func after_each() -> void:
	super.after_each()
	if _old_root_size != Vector2i.ZERO:
		get_tree().root.size = _old_root_size
		_old_root_size = Vector2i.ZERO
	InputBindings.reset_to_defaults()
	if _svc != null and is_instance_valid(_svc):
		remove_child(_svc)
		_svc.free()
	_svc = null
	_manager = null
	await wait_process_frames(1)


## The real TrainerService, in control of the emulated KICKR at ADDR, as the services' trainer.
func _real_trainer() -> WlTrainerService:
	var p := fx.give_profile(200.0)
	p.skip_warmup = true
	_link = KickrLink.new()
	_client = UnlockedClient.new()
	_client.process_self = false
	_svc = WlTrainerService.new()
	_svc.settings = fx.settings
	_svc.bus = fx.bus
	_svc.connection_factory = func() -> FtmsConnectionManager:
		var m := FtmsConnectionManager.new()
		m.manual_clock = true
		m.make_gdble = func() -> BleTransport: return _link
		m.make_client = func() -> FtmsClient: return _client
		_manager = m
		return m
	_svc.rider_options_factory = func() -> Dictionary: return {"bus": fx.bus}
	add_child(_svc)
	_svc.start()
	_svc.connect_trainer(ADDR)
	_pump(3.0)
	assert_true(_client.is_ready(), "precondition: in control of the emulated trainer")
	assert_true(
		_svc.device() is FtmsTrainer, "precondition: the FTMS trainer is the service's device"
	)
	assert_true(_link.ops.has(FLAT), "precondition: the menus ride SIM flat")
	fx.services.trainer = _svc
	return _svc


## Wall and platform time: the link's answers (unless `answer` is false: a control point that
## answers late), the manager, the client, the service and the screen.
func _pump(
	seconds: float, s: AppScreen = null, answer: bool = true, manager: FtmsConnectionManager = null
) -> void:
	var m := manager if manager != null else _manager
	for i in roundi(seconds / DT):
		if answer:
			_link.flush()
		if m != null and is_instance_valid(m):
			m.tick(DT)
		_client.tick(DT)
		if answer:
			_link.flush()
		_svc._process(DT)
		if s != null and is_instance_valid(s):
			s.tick(DT)


## The control-point writes and link calls from index `from` on.
func _since(from: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(from, _link.ops.size()):
		var op := _link.ops[i]
		if (
			op.begins_with("write 2ad9")
			or op.begins_with("disconnect")
			or op.begins_with("connect")
		):
			out.append(op)
	return out


func test_disconnect_sends_sim_flat_then_stop_before_the_link_drops() -> void:
	_real_trainer()
	var rider := _svc.local_rider()
	var n := _link.ops.size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "trainer")
	confirm_pick(s, "disconnect")
	assert_true(rider.is_shut_down(), "the governor went safe first")
	assert_false(
		_since(n).has("disconnect " + ADDR), "the link stays up while SIM flat and Stop go out"
	)
	assert_true(s.is_making_trainer_safe())
	assert_true(
		s.status_label.text.contains(AppScreen.t("APP_SET_TRAINER_SAFE")), "the page says so"
	)
	_pump(1.0, s)
	assert_eq(
		_since(n), [FLAT, STOP, "disconnect " + ADDR], "SIM flat, then Stop, then the link drops"
	)
	assert_false(s.is_making_trainer_safe())
	assert_false(
		s.status_label.text.contains(AppScreen.t("APP_SET_TRAINER_SAFE")), "and the note goes"
	)
	# The next connect has a live governor on the trainer again, which App.quit shuts down.
	s.connect_trainer(ADDR)
	_pump(3.0, s)
	var again := _svc.local_rider()
	assert_true(
		again != null and not again.is_shut_down(), "a live menu rider on the trainer again"
	)
	assert_true(LocalRider.live_riders().has(again), "so App.quit shuts it down again")


## W4r2 R6: a control point that answers SIM flat later than the old fixed 0.5 s still gets the
## Stop before the link drops.
func test_disconnect_waits_for_a_slow_control_point() -> void:
	_real_trainer()
	var n := _link.ops.size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.disconnect_trainer()
	_pump(0.8, s, false)
	assert_false(
		_since(n).has("disconnect " + ADDR), "no answer yet: the link waits (%s)" % str(_since(n))
	)
	assert_true(s.is_making_trainer_safe())
	_pump(1.0, s)
	assert_eq(
		_since(n), [FLAT, STOP, "disconnect " + ADDR], "Stop reached the trainer before the drop"
	)


## W4r2 R7: the trainer that is already linked (a KICKR keeps advertising) connects at once:
## no SIM flat or Stop, and the menu rider stays live.
func test_connecting_the_linked_trainer_again_keeps_the_menu_rider_alive() -> void:
	_real_trainer()
	var rider := _svc.local_rider()
	var n := _link.ops.size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.connect_trainer(ADDR)
	assert_false(s.is_making_trainer_safe())
	_pump(0.6, s)
	assert_false(_since(n).has(STOP), "no Stop: %s" % str(_since(n)))
	assert_false(_since(n).has("disconnect " + ADDR))
	assert_eq(_svc.local_rider(), rider)
	assert_false(rider.is_shut_down(), "the menu rider keeps riding")
	assert_true(LocalRider.live_riders().has(rider))


func test_switching_trainers_makes_the_old_one_safe_first() -> void:
	_real_trainer()
	var n := _link.ops.size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.connect_trainer(OTHER)
	assert_false(_since(n).has("connect " + OTHER), "no switch before the old trainer is safe")
	assert_true(s.is_making_trainer_safe())
	_pump(3.0, s)
	var ops := _since(n)
	var at_connect := ops.find("connect " + OTHER)
	assert_gt(at_connect, -1, "connected to the other trainer: %s" % str(ops))
	assert_eq(
		ops.slice(0, 3), [FLAT, STOP, "disconnect " + ADDR], "SIM flat, then Stop before the switch"
	)
	assert_false(ops.slice(at_connect).has(STOP), "no Stop reaches the new trainer")


func test_use_mock_makes_the_real_trainer_safe_first() -> void:
	_real_trainer()
	var m := _manager
	var n := _link.ops.size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.use_mock()
	assert_true(_svc.is_mock(), "the mock takes over")
	assert_true(s.is_making_trainer_safe(), "while the real trainer's link waits")
	_pump(1.0, s, true, m)
	assert_eq(
		_since(n),
		[FLAT, STOP, "disconnect " + ADDR],
		"SIM flat, then Stop before the real trainer's link dropped"
	)


## W4r2 R6: leaving the page mid-wait no longer drops the link at once; the service's wait goes on.
func test_leaving_the_page_keeps_the_safe_unlink() -> void:
	_real_trainer()
	var n := _link.ops.size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.disconnect_trainer()
	s.leave()
	assert_false(_since(n).has("disconnect " + ADDR), "still waiting for the safe commands")
	_pump(1.0)
	assert_eq(_since(n), [FLAT, STOP, "disconnect " + ADDR])


func test_a_mock_trainer_disconnects_at_once() -> void:
	fx.give_profile()
	var conn: FtmsConnectionManager = preload("res://tests/app/fakes/fake_connection.gd").new()
	fx.trainer.add_child(conn)
	fx.fake_trainer().conn = conn
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.disconnect_trainer()
	assert_eq(fx.fake_trainer().disconnect_calls, 1, "through TrainerService.disconnect_trainer()")
	assert_eq(conn.get("disconnects"), 1, "no real control point to drain")
	assert_false(s.is_making_trainer_safe())
	s.connect_trainer("AA:BB")
	assert_eq(
		fx.fake_trainer().connect_calls,
		["AA:BB"] as Array[String],
		"through TrainerService.connect_trainer()"
	)
	s.use_mock()
	assert_eq(
		fx.fake_trainer().mock_specs, ["erg"] as Array[String], "through TrainerService.use_mock()"
	)


# --- controls ----------------------------------------------------------------------------------


## FakeInput whose rebind also changes the InputMap, as the real WlInputRouter.rebind does.
class RealRebindInput:
	extends "res://tests/app/fakes/fake_input.gd"

	func rebind(action_name: StringName, event: InputEvent) -> void:
		super(action_name, event)
		InputBindings.rebind(action_name, event)


## W4r2 R28: the content column's list of every binding follows a rebind, including the action
## that lost the input (InputBindings.rebind takes it away from any other action).
func test_controls_content_column_follows_a_rebind() -> void:
	fx.give_profile()
	var inp := RealRebindInput.new()
	add_child_autofree(inp)
	fx.services.input = inp
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "controls")
	assert_eq(s.status_label.text, s.all_bindings_text(), "precondition: the list is current")
	var holder := &""
	var ls := InputEventJoypadButton.new()
	ls.button_index = JOY_BUTTON_LEFT_STICK
	ls.pressed = true
	for a: StringName in Wl.ACTIONS:
		for e: InputEvent in InputMap.action_get_events(a) if InputMap.has_action(a) else []:
			if e.is_match(ls):
				holder = a
	var before := s.status_label.text
	s.start_capture(&"item")
	assert_true(s.capture_event(ls), "LS is captured for item")
	assert_true(menu(s).text_of("bind:item").contains("LS"), "the row shows the new binding")
	assert_eq(
		s.status_label.text, s.all_bindings_text(), "the content column lists the new binding too"
	)
	assert_ne(s.status_label.text, before, "and it changed")
	if holder != &"" and holder != &"item":
		assert_false(
			s.status_label.text.contains(
				"%s: LS" % AppScreen.t("APP_ACTION_" + String(holder).to_upper())
			),
			"%s no longer lists LS" % holder
		)


func test_controls_page_rows_fit_the_menu_column() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "controls")
	await wait_process_frames(2)
	var m := s.active_menu()
	var w := m.get_combined_minimum_size().x
	var col := s.find_child("MenuColumn", true, false) as Control
	var vp_w := s.get_viewport_rect().size.x
	assert_true(w <= 640.0, "Controls rows need %.0f px (menu column 640 px)" % w)
	assert_true(
		col.get_global_rect().end.x <= vp_w + 0.5,
		(
			"menu column x=%.0f..%.0f on a %.0f px screen"
			% [col.get_global_rect().position.x, col.get_global_rect().end.x, vp_w]
		)
	)
	# Every binding is still on the page: the content column lists them all.
	var all := s.all_bindings_text()
	for a: StringName in Wl.ACTIONS:
		for label in s.binding_labels(a):
			assert_true(all.contains(label), "%s's binding %s is listed" % [a, label])
	assert_eq(s.status_label.text, all)


## At 1080p (the project's base size; the headless test viewport may be taller) the Controls
## page's one-line help, its list of every binding and the Reset to defaults row are on screen
## when the page opens.
func test_controls_help_list_and_reset_row_are_on_a_1080p_screen() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "controls")
	await wait_process_frames(2)
	var base_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	var bottom := base_h - AppStyle.MARGIN
	assert_true(s.controls_help_label.visible)
	assert_eq(s.controls_help_label.get_line_count(), 1, "the help is one line")
	var help_rect := s.controls_help_label.get_global_rect()
	var list_rect := s.status_label.get_global_rect()
	assert_true(help_rect.end.y <= list_rect.position.y + 0.5, "the help sits above the list")
	assert_true(
		list_rect.end.y <= bottom + 0.5,
		"the bindings list ends at y=%.0f (bottom margin at %.0f)" % [list_rect.end.y, bottom]
	)
	var reset_rect := menu(s).row(menu(s).index_of_id("reset_controls")).get_global_rect()
	assert_true(
		reset_rect.end.y <= bottom + 0.5,
		"Reset to defaults ends at y=%.0f (bottom margin at %.0f)" % [reset_rect.end.y, bottom]
	)


# --- controls: the page scrolls on a 1080p screen (BRIEF 3.9, W4fin) ---------------------------


## The Settings screen on a 1920 x 1080 root window (restored in after_each).
func _settings_at_1080p() -> AppSettingsScreen:
	_old_root_size = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	await wait_process_frames(2)
	assert_eq(s.get_viewport_rect(), Rect2(0, 0, 1920, 1080), "precondition: a 1080p screen")
	return s


## "" when `c` is fully inside the 1080p screen and the menu column's scroll view, else why not.
func _off_screen(s: AppScreen, c: Control, what: String) -> String:
	var r := c.get_global_rect()
	var view := s.menu_scroll.get_global_rect()
	var screen := s.get_viewport_rect()
	if (
		r.position.y >= view.position.y - 0.5
		and r.end.y <= view.end.y + 0.5
		and r.position.x >= screen.position.x - 0.5
		and r.end.x <= screen.end.x + 0.5
		and view.position.y >= screen.position.y - 0.5
		and view.end.y <= screen.end.y + 0.5
	):
		return ""
	return (
		"%s at y=%.0f..%.0f (view y=%.0f..%.0f, screen %.0f x %.0f)"
		% [what, r.position.y, r.end.y, view.position.y, view.end.y, screen.size.x, screen.size.y]
	)


## Highlight every enabled row of the active menu in turn: why each row (and on the last row the
## scan hint under it) is not fully on screen; empty when all are.
func _highlight_each_row(s: AppScreen, page: String) -> Array[String]:
	var m := menu(s)
	var off: Array[String] = []
	for i in m.item_count():
		if not m.is_item_enabled(i):
			continue
		m.set_highlight(i)
		await wait_process_frames(2)
		var why := _off_screen(s, m.row(i), "'%s' row %d (%s)" % [page, i, str(m.ids()[i])])
		if why != "":
			off.append(why)
		if i == m.item_count() - 1:
			why = _off_screen(s, m.get_node("Hint") as Control, "'%s' scan hint" % page)
			if why != "":
				off.append(why)
	return off


## BRIEF 3.9: the Controls page is taller than a 1080p screen, so its menu scrolls: whichever row
## is highlighted is fully on screen, Back and the scan hint under it included.
func test_every_controls_row_is_on_a_1080p_screen_when_highlighted() -> void:
	var s: AppSettingsScreen = await _settings_at_1080p()
	confirm_pick(s, "controls")
	await wait_process_frames(2)
	var m := menu(s)
	var back := m.index_of_id("back")
	assert_eq(back, Wl.ACTIONS.size() + 1, "Reset, a row per action, then Back")
	var holder := m.get_parent() as Control
	assert_gt(
		holder.size.y,
		s.menu_scroll.size.y,
		"precondition: the page (%.0f px) is taller than its view" % holder.size.y
	)
	assert_eq(s.menu_scroll.scroll_vertical, 0, "the page opens at its top")
	var off: Array[String] = await _highlight_each_row(s, "controls")
	assert_eq(off, [] as Array[String], "every highlighted row is on screen")
	assert_eq(m.highlighted(), back)
	assert_gt(s.menu_scroll.scroll_vertical, 0, "Back scrolled the page")
	m.set_highlight(0)
	await wait_process_frames(2)
	assert_eq(s.menu_scroll.scroll_vertical, 0, "Reset to defaults scrolls the page back up")
	assert_eq(_off_screen(s, m.row(0), "Reset to defaults"), "")


## Pedal-scan alone: every row the scan highlights is on screen, and Back is reached and picked.
func test_pedal_scan_reaches_back_on_the_controls_page_at_1080p() -> void:
	var s: AppSettingsScreen = await _settings_at_1080p()
	confirm_pick(s, "controls")
	await wait_process_frames(2)
	var m := menu(s)
	assert_true(m.scanning, "precondition: the page scans")
	assert_eq(m.highlighted(), 0)
	var off: Array[String] = []
	var seen: Array[int] = [m.highlighted()]
	while m.highlighted() != m.index_of_id("back") and seen.size() <= m.item_count():
		s.tick(m.scan_interval_s)
		await wait_process_frames(2)
		seen.append(m.highlighted())
		var why := _off_screen(s, m.row(m.highlighted()), "row %d" % m.highlighted())
		if why != "":
			off.append(why)
	assert_eq(seen.size(), m.item_count(), "the scan went through every row to Back: %s" % [seen])
	assert_eq(off, [] as Array[String], "every scanned row is on screen")
	assert_eq(m.highlighted_id(), "back")
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(menu(s).ids()[0], "trainer", "the surge on Back left the Controls page")
	await wait_process_frames(2)
	assert_eq(s.menu_scroll.scroll_vertical, 0, "the Settings menu fits again, unscrolled")
	assert_eq(_off_screen(s, menu(s).row(0), "the Settings root's first row"), "")


## Keyboard and controller focus moves keep the highlighted row on screen too, wrapping from the
## first row up to Back and from Back down to the first row.
func test_focus_moves_keep_the_controls_row_on_a_1080p_screen() -> void:
	var s: AppSettingsScreen = await _settings_at_1080p()
	confirm_pick(s, "controls")
	await wait_process_frames(2)
	var m := menu(s)
	s.feed_action(&"up")
	await wait_process_frames(2)
	assert_eq(m.highlighted_id(), "back", "up from the first row wraps to Back")
	assert_eq(_off_screen(s, m.row(m.highlighted()), "Back"), "")
	assert_eq(_off_screen(s, m.get_node("Hint") as Control, "the scan hint"), "")
	s.feed_action(&"down")
	await wait_process_frames(2)
	assert_eq(m.highlighted(), 0, "down from Back wraps to the first row")
	assert_eq(s.menu_scroll.scroll_vertical, 0)
	var off: Array[String] = []
	for _k in m.item_count() - 1:
		s.feed_action(&"down")
		await wait_process_frames(2)
		var why := _off_screen(s, m.row(m.highlighted()), "row %d" % m.highlighted())
		if why != "":
			off.append(why)
	assert_eq(m.highlighted_id(), "back", "down through every row reaches Back")
	assert_eq(off, [] as Array[String], "every focused row is on screen")
	s.feed_action(&"confirm")
	assert_eq(menu(s).ids()[0], "trainer", "Back by keyboard leaves the Controls page")


## Every other Settings page: whichever row is highlighted is fully on screen. Strava's 11 rows
## run past the bottom margin too (its scan hint was below the screen), so it scrolls a little
## when Back is highlighted.
func test_every_settings_row_is_on_a_1080p_screen_when_highlighted() -> void:
	var s: AppSettingsScreen = await _settings_at_1080p()
	var off: Array[String] = []
	for page: String in ["", "trainer", "strava", "haptics", "audio", "network", "pedal_ui"]:
		if page != "":
			s.open_section(page)
		await wait_process_frames(2)
		off.append_array(await _highlight_each_row(s, page))
		if page != "":
			s._pop_section()
	assert_eq(off, [] as Array[String], "every highlighted row is on screen")


## The Settings pages that fit a 1080p screen look as they did: no scroll bar and never scrolled,
## every row and the scan hint on screen, whichever row is highlighted.
func test_settings_pages_that_fit_do_not_scroll() -> void:
	var s: AppSettingsScreen = await _settings_at_1080p()
	for page: String in ["", "trainer", "haptics", "audio", "network", "pedal_ui"]:
		if page != "":
			s.open_section(page)
		await wait_process_frames(2)
		var m := menu(s)
		var off: Array[String] = []
		for i in m.item_count():
			var why := _off_screen(s, m.row(i), "'%s' row %d" % [page, i])
			if why != "":
				off.append(why)
		var hint := _off_screen(s, m.get_node("Hint") as Control, "'%s' scan hint" % page)
		if hint != "":
			off.append(hint)
		assert_eq(off, [] as Array[String], "every row of '%s' is on screen" % page)
		m.set_highlight(m.index_of_id("back"))
		await wait_process_frames(2)
		assert_false(s.menu_scroll.get_v_scroll_bar().visible, "'%s' needs no scroll bar" % page)
		assert_eq(s.menu_scroll.scroll_vertical, 0, "'%s' is not scrolled" % page)
		if page != "":
			s._pop_section()


func test_compact_binding_text_takes_one_key_and_one_pad_binding() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	var text := s.compact_binding_text(&"right")
	assert_false(text.contains("Physical"), "short labels, not InputEvent.as_text(): %s" % text)
	assert_lte(text.split(", ").size(), 2, text)


func test_backing_out_of_controls_ends_the_capture() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	surge_pick(s, "controls")
	surge_pick(s, "bind:ability_1")
	assert_eq(s.capturing, &"ability_1")
	s.feed_gesture(Wl.G_COAST)
	assert_eq(menu(s).ids()[0], "trainer", "the coast left the Controls page")
	assert_eq(s.capturing, &"", "leaving the Controls page ends the capture")
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.keycode = KEY_ENTER
	enter.pressed = true
	assert_false(s.capture_event(enter), "Enter on the Settings root menu is not captured")
	var rebinds: Array = (fx.input as Object).get("rebinds")
	assert_eq(rebinds.size(), 0, "no binding changed (got %s)" % str(rebinds))


func test_the_back_item_ends_the_capture_too() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "controls")
	s.start_capture(&"swap")
	s._pop_section()
	assert_eq(s.capturing, &"")


func test_controller_b_cancels_a_capture() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "controls")
	s.start_capture(&"item")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	assert_true(s.capture_event(b), "B is taken by the capture")
	assert_eq(s.capturing, &"", "and cancels it")
	var rebinds: Array = (fx.input as Object).get("rebinds")
	assert_eq(rebinds.size(), 0, "B was not bound to item")
	s.start_capture(&"item")
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_X
	a.pressed = true
	assert_true(s.capture_event(a))
	assert_eq(rebinds.size(), 1, "another button still binds")


# --- controls: Reset to defaults (BRIEF 3.5, W4fin) --------------------------------------------


## FakeInput that counts reset_bindings() (the real reset of the InputMap runs too).
class ResetCountingInput:
	extends "res://tests/app/fakes/fake_input.gd"
	var resets: int = 0

	func reset_bindings() -> void:
		resets += 1
		super()


## The real InputRouter as the services' router: no input.cfg loaded at start, the fixture's
## profile and bus, and no device used yet, so the menus run on pedal-scan with zero input.
func _real_router() -> WlInputRouter:
	var r := WlInputRouter.new()
	r.load_on_ready = false
	r.bus = fx.bus
	r.profile = fx.settings.profile
	add_child_autofree(r)
	r.set_process(false)
	r.set_process_input(false)
	fx.services.input = r
	return r


static func _key_event(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e


static func _pad_event(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


## True when `action` is bound to `event`'s input now.
static func _bound(action: StringName, event: InputEvent) -> bool:
	for e: InputEvent in InputBindings.events_of(action):
		if InputBindings.same_input(e, event):
			return true
	return false


## Every action's bindings now, as plain data.
static func _all_bindings() -> Dictionary:
	var out := {}
	for a: StringName in Wl.ACTIONS:
		var list: Array = []
		for e: InputEvent in InputBindings.events_of(a):
			list.append(InputBindings.event_to_dict(e))
		out[a] = list
	return out


## Every action's project.godot defaults, as plain data.
static func _default_bindings() -> Dictionary:
	var out := {}
	for a: StringName in Wl.ACTIONS:
		var list: Array = []
		for e: InputEvent in InputBindings.default_events(a):
			list.append(InputBindings.event_to_dict(e))
		out[a] = list
	return out


func test_controls_page_has_a_reset_row_and_says_how_to_cancel() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	assert_false(s.controls_help_label.visible, "the help shows only on the Controls page")
	confirm_pick(s, "controls")
	var ids := menu(s).ids()
	assert_eq(ids.size(), Wl.ACTIONS.size() + 2, "Reset to defaults, a row per action, Back")
	assert_eq(ids[0], "reset_controls", "Reset to defaults comes first")
	assert_eq(ids[1], "bind:" + String(Wl.ACTIONS[0]), "then the action rows")
	assert_eq(ids[ids.size() - 1], "back")
	assert_eq(menu(s).text_of("reset_controls"), AppScreen.t("APP_SET_CONTROLS_RESET"))
	assert_false(menu(s).is_disabled_id("reset_controls"))
	assert_true(s.controls_help_label.visible, "the Controls page says how to cancel")
	assert_eq(s.controls_help_label.text, AppScreen.t("APP_SET_CONTROLS_HELP"))
	assert_string_contains(s.controls_help_label.text, "Esc or B cancels")
	assert_string_contains(s.controls_help_label.text, AppScreen.t("APP_SET_CONTROLS_RESET"))
	s.start_capture(&"item")
	assert_eq(
		s.value_label.text,
		AppScreen.t("APP_SET_CAPTURE").format([AppScreen.t("APP_ACTION_ITEM")]),
		"the capture prompt"
	)
	assert_string_contains(s.value_label.text, "Esc or B cancels")
	s._pop_section()
	assert_false(s.controls_help_label.visible, "the help hides when the page is left")


## BRIEF 3.5 puts Esc and B on back, and both cancel a capture, so once back moved to other
## inputs only Reset to defaults brings them back. With pedal-scan alone (no device used yet) it
## restores every default and writes input.cfg.
func test_reset_to_defaults_by_pedal_scan_restores_esc_and_b_and_saves() -> void:
	fx.give_profile()
	var router := _real_router()
	router.rebind(&"back", _key_event(KEY_K))
	router.rebind(&"back", _pad_event(JOY_BUTTON_PADDLE1))
	assert_true(router.save_bindings(), "precondition: a custom input.cfg")
	assert_false(_bound(&"back", _key_event(KEY_ESCAPE)), "precondition: Esc left back")
	assert_false(_bound(&"back", _pad_event(JOY_BUTTON_B)), "precondition: B left back")
	assert_ne(_all_bindings(), _default_bindings(), "precondition: custom bindings")
	assert_true(router.pedal_ui_active(), "precondition: no device used, the menus scan")
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	assert_true(menu(s).scanning)
	assert_true(scan_to(s, "controls"), "the scan reaches Controls")
	router.inject_gesture(Wl.G_SURGE)
	assert_true(menu(s).scanning, "the Controls page scans")
	assert_true(scan_to(s, "reset_controls"), "the scan reaches Reset to defaults")
	router.inject_gesture(Wl.G_SURGE)
	assert_eq(menu(s).ids(), ["keep", "reset"], "a confirm: Keep, then Reset")
	assert_eq(menu(s).text_of("keep"), AppScreen.t("APP_SET_CONTROLS_RESET_KEEP"))
	assert_eq(menu(s).text_of("reset"), AppScreen.t("APP_SET_CONTROLS_RESET_YES"))
	assert_eq(menu(s).highlighted(), 0, "Keep is highlighted first")
	assert_true(menu(s).scanning, "the confirm scans")
	assert_eq(s.status_label.text, AppScreen.t("APP_SET_CONTROLS_RESET_ASK"))
	assert_true(scan_to(s, "reset"), "the scan reaches Reset")
	router.inject_gesture(Wl.G_SURGE)
	assert_eq(_all_bindings(), _default_bindings(), "every action has its default bindings")
	assert_true(_bound(&"back", _key_event(KEY_ESCAPE)), "Esc is on back again")
	assert_true(_bound(&"back", _pad_event(JOY_BUTTON_B)), "B is on back again")
	assert_false(_bound(&"back", _key_event(KEY_K)), "K left back")
	assert_false(_bound(&"back", _pad_event(JOY_BUTTON_PADDLE1)), "the paddle left back")
	assert_eq(menu(s).ids()[1], "bind:confirm", "back on the Controls page")
	assert_eq(
		menu(s).text_of("bind:back"),
		"%s: %s, B" % [AppScreen.t("APP_ACTION_BACK"), OS.get_keycode_string(KEY_ESCAPE)],
		"the back row shows Esc and B"
	)
	assert_eq(s.status_label.text, s.all_bindings_text(), "the list shows the defaults")
	assert_true(s.controls_help_label.visible)
	# input.cfg holds the defaults: loading it undoes an unsaved change.
	assert_true(FileAccess.file_exists(Paths.input_cfg_path()), "input.cfg written")
	router.rebind(&"back", _key_event(KEY_K))
	router.load_bindings()
	assert_eq(_all_bindings(), _default_bindings(), "input.cfg was saved with the defaults")


func test_keep_back_or_a_coast_leave_the_bindings_alone() -> void:
	fx.give_profile()
	var inp := ResetCountingInput.new()
	add_child_autofree(inp)
	fx.services.input = inp
	InputBindings.rebind(&"back", _key_event(KEY_K))
	var custom := _all_bindings()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "controls")
	surge_pick(s, "reset_controls")
	s.feed_gesture(Wl.G_SURGE)
	assert_eq(menu(s).ids()[1], "bind:confirm", "a stray surge picks Keep")
	confirm_pick(s, "reset_controls")
	s.feed_gesture(Wl.G_COAST)
	assert_eq(menu(s).ids()[1], "bind:confirm", "a coast backs out to Controls")
	confirm_pick(s, "reset_controls")
	s.feed_action(&"back")
	assert_eq(menu(s).ids()[1], "bind:confirm", "back backs out to Controls")
	confirm_pick(s, "reset_controls")
	confirm_pick(s, "keep")
	assert_eq(menu(s).ids()[1], "bind:confirm", "Keep returns to Controls")
	assert_eq(inp.resets, 0, "nothing was reset")
	assert_eq(inp.saves, 0, "nothing was saved")
	assert_eq(_all_bindings(), custom, "the rider's bindings stay")
	assert_eq(s.status_label.text, s.all_bindings_text(), "the Controls list is back")
	confirm_pick(s, "reset_controls")
	confirm_pick(s, "reset")
	assert_eq(inp.resets, 1, "Reset resets")
	assert_eq(inp.saves, 1, "and saves input.cfg")
	assert_eq(_all_bindings(), _default_bindings())
	assert_eq(menu(s).ids()[1], "bind:confirm")
