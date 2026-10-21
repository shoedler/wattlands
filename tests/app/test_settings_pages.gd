extends "res://tests/app/app_test_base.gd"
## Settings pages (W3 SAF-8, ZIH-3, ZIH-4):
## - BRIEF 4.6.9 "on disconnect: try SIM flat, then Stop": Disconnect, switching trainers and
##   "use the mock trainer" make the trainer safe before the link drops, and both commands reach
##   the control point first (an emulated KICKR CORE on an FtmsClient whose lock is off).
## - BRIEF 3.5/3.9: the Controls rows fit the 640 px menu column; a capture ends when the page is
##   left (coast or back) and the controller's B button cancels it like Esc.

const FakeKickr := preload("res://tests/trainer/fake_kickr_transport.gd")
const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const DT := Wl.SIM_DT


## The trainer manager double: records what the control point had received when the link was
## dropped (connect_to to another trainer drops it, as FtmsConnectionManager does).
class RecordingConnection:
	extends "res://tests/app/fakes/fake_connection.gd"
	var kickr: Object = null
	var writes_at_unlink: Array = []

	func written() -> Array:
		var out: Array = []
		if kickr != null:
			for w: PackedByteArray in kickr.get("cp_writes"):
				out.append(FtmsCodec.to_hex(w))
		return out

	func connect_to(address: String) -> void:
		writes_at_unlink.append(written())
		super(address)

	func disconnect_trainer() -> void:
		writes_at_unlink.append(written())
		super()


var _kickr: Node = null
var _client: FtmsClient = null
var _ftms: FtmsTrainer = null
var _rider: LocalRider = null
var _conn: RecordingConnection = null


## A ready FtmsTrainer over the emulated KICKR, a real menu rider on it, and the recording
## connection manager.
func _real_trainer() -> void:
	var p := fx.give_profile(200.0)
	_kickr = autofree(FakeKickr.new())
	_client = autofree(UnlockedClient.new())
	_client.attach(_kickr as BleTransport)
	_ftms = FtmsTrainer.create(_client, "KICKR CORE 1234")
	var t := fx.fake_trainer()
	t.add_child(_ftms)
	t.dev = _ftms
	_client.begin()
	for i in 20:
		_kickr.call("flush")
		_ftms.tick(DT)
		_kickr.call("flush")
	assert_true(_ftms.is_ready(), "precondition: the emulated trainer is ready")
	var old: LocalRider = t.rider
	t.remove_child(old)
	old.free()
	_rider = LocalRider.new()
	_rider.name = "LocalRider"
	t.add_child(_rider)
	t.rider = _rider
	_rider.setup(1, p, p.to_slot(1, Wl.FAIR_FTP), _ftms, {"multiplayer": false})
	_run(40)
	_conn = RecordingConnection.new()
	_conn.kickr = _kickr
	t.add_child(_conn)
	t.conn = _conn


## Platform and wall time together: the rider (and through it the trainer), the emulated
## trainer's answers, and the screen.
func _run(steps: int, s: AppScreen = null) -> void:
	for i in steps:
		_kickr.call("flush")
		_rider.tick(DT)
		_kickr.call("flush")
		if s != null:
			s.tick(DT)


static func _stop_after_sim(writes: Array) -> bool:
	var sim := -1
	for i in writes.size():
		var h := str(writes[i])
		if h.begins_with("11") and sim < 0:
			sim = i
		if h.begins_with("08") and sim >= 0 and i > sim:
			return true
	return false


func test_disconnect_sends_sim_flat_then_stop_before_the_link_drops() -> void:
	_real_trainer()
	var before := _conn.written().size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "trainer")
	confirm_pick(s, "disconnect")
	assert_true(_rider.is_shut_down(), "the governor went safe first")
	assert_eq(_conn.disconnects, 0, "the link stays up while SIM flat and Stop go out")
	assert_true(s.is_making_trainer_safe())
	_run(12, s)
	assert_eq(_conn.disconnects, 1, "then the link drops")
	var at_drop: Array = (_conn.writes_at_unlink[0] as Array).slice(before)
	assert_true(_stop_after_sim(at_drop), "SIM flat, then Stop reached the trainer before the drop: %s" % str(at_drop))
	assert_false(_rider.is_shut_down(), "the menu rider is set up again for the next connect")
	assert_true(LocalRider.live_riders().has(_rider), "so App.quit shuts it down again")


func test_switching_trainers_makes_the_old_one_safe_first() -> void:
	_real_trainer()
	var before := _conn.written().size()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.connect_trainer("CC:DD:EE:FF:00:11")
	assert_eq(_conn.connects.size(), 0, "no switch before the old trainer is safe")
	_run(12, s)
	assert_eq(_conn.connects, ["CC:DD:EE:FF:00:11"] as Array[String])
	var at_drop: Array = (_conn.writes_at_unlink[0] as Array).slice(before)
	assert_true(_stop_after_sim(at_drop), "SIM flat, then Stop before the switch: %s" % str(at_drop))
	assert_true(_rider.is_shut_down(), "the old rider stays shut down (the new trainer gets a new rider)")


func test_use_mock_makes_the_real_trainer_safe_first() -> void:
	_real_trainer()
	var before := _conn.written().size()
	var at_switch: Array = []
	fx.trainer.device_changed.connect(func(_d: TrainerDevice) -> void: at_switch.append(_conn.written()))
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.use_mock()
	assert_eq(fx.fake_trainer().mock_specs.size(), 0, "the mock waits for the safe commands")
	_run(12, s)
	assert_eq(fx.fake_trainer().mock_specs, ["erg"] as Array[String])
	assert_eq(at_switch.size(), 1)
	if not at_switch.is_empty():
		var w: Array = (at_switch[0] as Array).slice(before)
		assert_true(_stop_after_sim(w), "SIM flat, then Stop before the mock took over: %s" % str(w))


func test_leaving_the_page_drops_the_link_at_once() -> void:
	_real_trainer()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.disconnect_trainer()
	assert_eq(_conn.disconnects, 0)
	s.leave()
	assert_eq(_conn.disconnects, 1, "a page left mid-wait still disconnects (the rider was already safe)")


func test_a_mock_trainer_disconnects_at_once() -> void:
	fx.give_profile()
	var conn: FtmsConnectionManager = preload("res://tests/app/fakes/fake_connection.gd").new()
	fx.trainer.add_child(conn)
	fx.fake_trainer().conn = conn
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	s.disconnect_trainer()
	assert_eq(conn.get("disconnects"), 1, "no real control point to drain")
	assert_false(s.is_making_trainer_safe())


# --- controls ----------------------------------------------------------------------------------

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
