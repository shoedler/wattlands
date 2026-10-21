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

const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const DT := Wl.SIM_DT
const ADDR := "C4:9D:A1:00:2B:7E"
const OTHER := "11:22:33:44:55:66"
const FLAT := "write 2ad9 11000000002833"
const STOP := "write 2ad9 0801"


## The emulated KICKR plus what FtmsConnectionManager needs from a backend (as in
## tests/core/integration/test_safe_unlink.gd).
class KickrLink extends "res://tests/trainer/fake_kickr_transport.gd":
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


func after_each() -> void:
	super.after_each()
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
	assert_true(_svc.device() is FtmsTrainer, "precondition: the FTMS trainer is the service's device")
	assert_true(_link.ops.has(FLAT), "precondition: the menus ride SIM flat")
	fx.services.trainer = _svc
	return _svc


## Wall and platform time: the link's answers (unless `answer` is false: a control point that
## answers late), the manager, the client, the service and the screen.
func _pump(seconds: float, s: AppScreen = null, answer: bool = true, manager: FtmsConnectionManager = null) -> void:
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
		if op.begins_with("write 2ad9") or op.begins_with("disconnect") or op.begins_with("connect"):
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
	assert_false(_since(n).has("disconnect " + ADDR), "the link stays up while SIM flat and Stop go out")
	assert_true(s.is_making_trainer_safe())
	assert_true(s.status_label.text.contains(AppScreen.t("APP_SET_TRAINER_SAFE")), "the page says so")
	_pump(1.0, s)
	assert_eq(_since(n), [FLAT, STOP, "disconnect " + ADDR], "SIM flat, then Stop, then the link drops")
	assert_false(s.is_making_trainer_safe())
	assert_false(s.status_label.text.contains(AppScreen.t("APP_SET_TRAINER_SAFE")), "and the note goes")
	# The next connect has a live governor on the trainer again, which App.quit shuts down.
	s.connect_trainer(ADDR)
	_pump(3.0, s)
	var again := _svc.local_rider()
	assert_true(again != null and not again.is_shut_down(), "a live menu rider on the trainer again")
	assert_true(LocalRider.live_riders().has(again), "so App.quit shuts it down again")


## W4r2 R6: a control point that answers SIM flat later than the old fixed 0.5 s still gets the
## Stop before the link drops.
func test_disconnect_waits_for_a_slow_control_point() -> void:
	_real_trainer()
	var n := _link.ops.size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.disconnect_trainer()
	_pump(0.8, s, false)
	assert_false(_since(n).has("disconnect " + ADDR), "no answer yet: the link waits (%s)" % str(_since(n)))
	assert_true(s.is_making_trainer_safe())
	_pump(1.0, s)
	assert_eq(_since(n), [FLAT, STOP, "disconnect " + ADDR], "Stop reached the trainer before the drop")


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
	assert_eq(ops.slice(0, 3), [FLAT, STOP, "disconnect " + ADDR], "SIM flat, then Stop before the switch")
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
	assert_eq(_since(n), [FLAT, STOP, "disconnect " + ADDR], "SIM flat, then Stop before the real trainer's link dropped")


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
	assert_eq(fx.fake_trainer().connect_calls, ["AA:BB"] as Array[String], "through TrainerService.connect_trainer()")
	s.use_mock()
	assert_eq(fx.fake_trainer().mock_specs, ["erg"] as Array[String], "through TrainerService.use_mock()")


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
	assert_eq(s.status_label.text, s.all_bindings_text(), "the content column lists the new binding too")
	assert_ne(s.status_label.text, before, "and it changed")
	if holder != &"" and holder != &"item":
		assert_false(s.status_label.text.contains("%s: LS" % AppScreen.t("APP_ACTION_" + String(holder).to_upper())),
			"%s no longer lists LS" % holder)

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
	assert_true(col.get_global_rect().end.x <= vp_w + 0.5, "menu column x=%.0f..%.0f on a %.0f px screen" % [col.get_global_rect().position.x, col.get_global_rect().end.x, vp_w])
	# Every binding is still on the page: the content column lists them all.
	var all := s.all_bindings_text()
	for a: StringName in Wl.ACTIONS:
		for label in s.binding_labels(a):
			assert_true(all.contains(label), "%s's binding %s is listed" % [a, label])
	assert_eq(s.status_label.text, all)


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
