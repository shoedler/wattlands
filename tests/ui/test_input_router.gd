extends GutTest
## WlInputRouter (BRIEF 3.5): defaults from project.godot, rebinding with save and load to
## input.cfg, Backspace held 1 s and View+Menu panic, the action and gesture queues, gesture
## forwarding from the attached LocalRider and the pedal-UI menu mapping.

const FakeRider := preload("res://tests/ui/fake_local_rider.gd")

var _router: WlInputRouter = null
var _bus: WlEventBus = null
var _dir: String = ""


func before_each() -> void:
	_dir = Paths.make_temp_dir("wl_ui_router")
	Paths.set_override(_dir)
	_bus = autofree(WlEventBus.new())
	_router = WlInputRouter.new()
	_router.bus = _bus
	_router.profile = RiderProfile.new()
	_router.profile.pedal_nav = true
	add_child_autofree(_router)
	_router.set_process(false)
	_router.set_process_input(false)
	watch_signals(_bus)
	watch_signals(_router)


func after_each() -> void:
	InputBindings.reset_to_defaults()
	Paths.set_override("")
	_remove_dir(_dir)


# --- helpers -------------------------------------------------------------------------------


func _key(code: Key, pressed: bool, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	e.echo = echo
	return e


func _joy(button: JoyButton, pressed: bool, device: int = 0) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	e.device = device
	return e


func _axis(axis: JoyAxis, value: float, device: int = 0) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = device
	return e


func _tap(code: Key) -> void:
	_router.handle_event(_key(code, true))
	_router.handle_event(_key(code, false))


func _count(obj: Object, sig: String) -> int:
	return maxi(0, get_signal_emit_count(obj, sig))


func _remove_dir(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func _has_key(events: Array[InputEvent], code: Key) -> bool:
	for e in events:
		if e is InputEventKey and (e as InputEventKey).physical_keycode == code:
			return true
	return false


func _has_button(events: Array[InputEvent], button: JoyButton) -> bool:
	for e in events:
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button:
			return true
	return false


# --- defaults -------------------------------------------------------------------------------


func test_runs_always() -> void:
	assert_eq(_router.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_every_action_exists_with_project_defaults() -> void:
	for a: StringName in Wl.ACTIONS:
		assert_true(InputMap.has_action(a), String(a))
		assert_eq(_router.bindings(a).size(), InputBindings.default_events(a).size(), String(a))
		assert_gt(_router.bindings(a).size(), 0, "%s has a default binding" % a)


func test_default_keys_and_buttons() -> void:
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_ENTER))
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_SPACE))
	assert_true(_has_button(_router.bindings(&"confirm"), JOY_BUTTON_A))
	assert_true(_has_key(_router.bindings(&"back"), KEY_ESCAPE))
	assert_true(_has_button(_router.bindings(&"back"), JOY_BUTTON_B))
	assert_true(_has_key(_router.bindings(&"up"), KEY_UP))
	assert_true(_has_key(_router.bindings(&"up"), KEY_W))
	assert_true(_has_key(_router.bindings(&"ability_1"), KEY_1))
	assert_true(_has_key(_router.bindings(&"item"), KEY_F))
	assert_true(_has_key(_router.bindings(&"swap"), KEY_R))
	assert_true(_has_key(_router.bindings(&"shift_down"), KEY_Q))
	assert_true(_has_key(_router.bindings(&"shift_up"), KEY_E))
	assert_true(_has_key(_router.bindings(&"pause"), KEY_P))
	assert_true(_has_button(_router.bindings(&"pause"), JOY_BUTTON_START))
	assert_true(_has_key(_router.bindings(&"panic"), KEY_BACKSPACE))
	assert_true(_has_button(_router.bindings(&"panic"), JOY_BUTTON_BACK))


# --- actions --------------------------------------------------------------------------------


func test_key_press_fires_action_once() -> void:
	_router.handle_event(_key(KEY_ENTER, true))
	_router.handle_event(_key(KEY_ENTER, true, true))
	_router.handle_event(_key(KEY_ENTER, true))
	assert_eq(_router.take_actions(), [&"confirm"])
	assert_eq(_router.take_actions(), [], "drained")
	assert_signal_emit_count(_bus, "action_pressed", 1)
	assert_eq(get_signal_parameters(_bus, "action_pressed"), [&"confirm"])
	assert_eq(get_signal_parameters(_router, "menu_input"), [&"confirm", "action"])
	_router.handle_event(_key(KEY_ENTER, false))
	_router.handle_event(_key(KEY_ENTER, true))
	assert_eq(_router.take_actions(), [&"confirm"], "a new press fires again")


func test_each_default_key_maps_to_its_action() -> void:
	var cases := {
		KEY_SPACE: &"confirm",
		KEY_ESCAPE: &"back",
		KEY_W: &"up",
		KEY_DOWN: &"down",
		KEY_A: &"left",
		KEY_RIGHT: &"right",
		KEY_1: &"ability_1",
		KEY_2: &"ability_2",
		KEY_F: &"item",
		KEY_R: &"swap",
		KEY_E: &"shift_up",
		KEY_Q: &"shift_down",
		KEY_P: &"pause",
	}
	for code: int in cases.keys():
		_tap(code as Key)
		assert_eq(_router.take_actions(), [cases[code]], str(cases[code]))


func test_controller_buttons() -> void:
	var cases := {
		JOY_BUTTON_A: &"confirm",
		JOY_BUTTON_B: &"back",
		JOY_BUTTON_X: &"ability_1",
		JOY_BUTTON_Y: &"ability_2",
		JOY_BUTTON_RIGHT_SHOULDER: &"item",
		JOY_BUTTON_LEFT_SHOULDER: &"swap",
		JOY_BUTTON_DPAD_UP: &"up",
		JOY_BUTTON_START: &"pause",
	}
	for b: int in cases.keys():
		_router.handle_event(_joy(b as JoyButton, true))
		_router.handle_event(_joy(b as JoyButton, false))
		assert_eq(_router.take_actions(), [cases[b]], str(cases[b]))


func test_stick_and_triggers_are_edge_detected() -> void:
	_router.handle_event(_axis(JOY_AXIS_LEFT_Y, -0.8))
	_router.handle_event(_axis(JOY_AXIS_LEFT_Y, -0.95))
	assert_eq(_router.take_actions(), [&"up"], "one press while held")
	_router.handle_event(_axis(JOY_AXIS_LEFT_Y, 0.1))
	_router.handle_event(_axis(JOY_AXIS_LEFT_Y, -0.7))
	assert_eq(_router.take_actions(), [&"up"], "released inside the deadzone")
	_router.handle_event(_axis(JOY_AXIS_LEFT_Y, 0.9))
	assert_eq(_router.take_actions(), [&"down"], "the other direction")
	_router.handle_event(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	_router.handle_event(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0))
	_router.handle_event(_axis(JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_eq(_router.take_actions(), [&"shift_up", &"shift_down"])


func test_inject_action() -> void:
	_router.inject_action(&"swap")
	assert_eq(_router.take_actions(), [&"swap"])
	assert_signal_emitted(_bus, "action_pressed")


func test_inject_unknown_action_is_rejected() -> void:
	_router.inject_action(&"jump")
	assert_push_error("unknown action")
	assert_eq(_router.take_actions(), [])


func test_queue_is_bounded() -> void:
	for i in WlInputRouter.QUEUE_LIMIT + 10:
		_router.inject_action(&"item")
	assert_eq(_router.take_actions().size(), WlInputRouter.QUEUE_LIMIT)


func test_clear_queues() -> void:
	_router.inject_action(&"item")
	_router.inject_gesture(Wl.G_SURGE)
	_router.clear_queues()
	assert_eq(_router.take_actions().size(), 0)
	assert_eq(_router.take_gestures().size(), 0)


# --- panic ----------------------------------------------------------------------------------


func test_backspace_held_one_second_panics() -> void:
	_router.handle_event(_key(KEY_BACKSPACE, true))
	assert_eq(_router.take_actions(), [], "no panic on press")
	_router.tick(0.5)
	_router.tick(0.45)
	assert_signal_not_emitted(_bus, "panic_requested")
	_router.tick(0.05)
	assert_signal_emit_count(_bus, "panic_requested", 1)
	assert_eq(_router.take_actions(), [&"panic"])
	_router.tick(3.0)
	assert_signal_emit_count(_bus, "panic_requested", 1, "once per hold")


func test_backspace_tap_or_short_hold_never_panics() -> void:
	_router.handle_event(_key(KEY_BACKSPACE, true))
	_router.tick(0.9)
	_router.handle_event(_key(KEY_BACKSPACE, false))
	_router.tick(2.0)
	_router.handle_event(_key(KEY_BACKSPACE, true))
	_router.tick(0.5)
	assert_signal_not_emitted(_bus, "panic_requested")
	_router.tick(0.5)
	assert_signal_emit_count(
		_bus, "panic_requested", 1, "a fresh 1 s hold counts from its own press"
	)


func test_key_repeat_does_not_restart_the_hold() -> void:
	_router.handle_event(_key(KEY_BACKSPACE, true))
	_router.tick(0.6)
	_router.handle_event(_key(KEY_BACKSPACE, true, true))
	_router.tick(0.4)
	assert_signal_emit_count(_bus, "panic_requested", 1)


func test_view_and_menu_together_panic_at_once() -> void:
	_router.handle_event(_joy(JOY_BUTTON_BACK, true))
	assert_signal_not_emitted(_bus, "panic_requested")
	_router.handle_event(_joy(JOY_BUTTON_START, true))
	assert_signal_emit_count(_bus, "panic_requested", 1)
	assert_eq(_router.take_actions(), [&"panic"], "no pause from the chord")


func test_menu_then_view_panics() -> void:
	_router.handle_event(_joy(JOY_BUTTON_START, true))
	assert_eq(_router.take_actions(), [&"pause"], "Menu alone pauses")
	_router.handle_event(_joy(JOY_BUTTON_BACK, true))
	assert_signal_emit_count(_bus, "panic_requested", 1)
	assert_eq(_router.take_actions(), [&"panic"])


func test_view_alone_never_panics() -> void:
	_router.handle_event(_joy(JOY_BUTTON_BACK, true))
	_router.tick(5.0)
	assert_signal_not_emitted(_bus, "panic_requested")
	assert_eq(_router.take_actions(), [])


func test_inject_panic_is_immediate() -> void:
	_router.inject_action(&"panic")
	assert_signal_emit_count(_bus, "panic_requested", 1)
	assert_eq(get_signal_parameters(_bus, "action_pressed"), [&"panic"])


# --- gestures -------------------------------------------------------------------------------


func test_gestures_queue_apart_from_actions() -> void:
	_router.inject_gesture(Wl.G_SURGE)
	_router.inject_gesture(Wl.G_PEDAL_START)
	assert_eq(_router.take_gestures(), [Wl.G_SURGE, Wl.G_PEDAL_START])
	assert_eq(_router.take_actions(), [], "a surge is never an action")
	assert_signal_emit_count(_bus, "gesture", 2)
	assert_signal_emit_count(_router, "gesture", 2)
	assert_signal_not_emitted(_bus, "action_pressed")


## The app shell feeds the `action` and `gesture` signals to one PedalScanList: a gesture that
## also arrived as an action would pick (or back out) twice. Only `menu_input` maps them.
func test_the_action_signal_never_carries_a_gesture() -> void:
	var rider: FakeRider = autofree(FakeRider.new())
	rider.fake_mode = Wl.SIM
	_router.attach_rider(rider)
	for g: StringName in [Wl.G_SURGE, Wl.G_COAST, Wl.G_STOP_5S, Wl.G_PEDAL_START]:
		rider.gesture_detected.emit(g)
	_router.inject_gesture(Wl.G_SURGE)
	assert_signal_not_emitted(
		_router, "action", "surge is never confirm, coast never back, stop_5s never pause"
	)
	assert_signal_not_emitted(_bus, "action_pressed")
	assert_eq(_router.take_actions(), [], "nor in the action queue")
	assert_signal_emit_count(_router, "gesture", 5)
	assert_signal_emit_count(
		_router, "menu_input", 4, "the pedal-UI mapping goes only to menu_input"
	)
	_tap(KEY_ENTER)
	assert_signal_emit_count(_router, "action", 1, "a device confirm is an action")
	assert_eq(get_signal_parameters(_router, "action"), [&"confirm"])
	assert_signal_emit_count(_router, "gesture", 5, "and never a gesture")


func test_attached_rider_gestures_are_forwarded() -> void:
	var rider: LocalRider = autofree(FakeRider.new())
	_router.attach_rider(rider)
	assert_same(_router.attached_rider(), rider)
	rider.gesture_detected.emit(Wl.G_COAST)
	assert_eq(_router.take_gestures(), [Wl.G_COAST])
	assert_eq(get_signal_parameters(_bus, "gesture"), [Wl.G_COAST])
	_router.detach_rider()
	rider.gesture_detected.emit(Wl.G_SURGE)
	assert_eq(_router.take_gestures(), [], "detached")
	assert_null(_router.attached_rider())


## Menu presses pile up (nobody drains the queue in menus); a session attaching its rider
## starts with empty queues. Re-attaching the same rider keeps what is queued.
func test_attaching_a_new_rider_clears_stale_menu_input() -> void:
	for i in 40:
		_tap(KEY_DOWN)
	_router.inject_gesture(Wl.G_SURGE)
	var rider: LocalRider = autofree(FakeRider.new())
	_router.attach_rider(rider)
	assert_eq(_router.take_actions(), [], "stale menu actions dropped")
	assert_eq(_router.take_gestures(), [], "stale gestures dropped")
	_tap(KEY_1)
	_router.attach_rider(rider)
	assert_eq(_router.take_actions(), [&"ability_1"], "same rider: nothing dropped")


func test_menu_mapping_outside_erg() -> void:
	var rider: FakeRider = autofree(FakeRider.new())
	rider.fake_mode = Wl.SIM
	_router.attach_rider(rider)
	_router.inject_gesture(Wl.G_SURGE)
	assert_eq(get_signal_parameters(_router, "menu_input"), [&"confirm", "surge"])
	_router.inject_gesture(Wl.G_COAST)
	assert_eq(get_signal_parameters(_router, "menu_input"), [&"back", "coast"])
	_router.inject_gesture(Wl.G_STOP_5S)
	assert_eq(get_signal_parameters(_router, "menu_input"), [&"pause", "stop_5s"])
	_router.inject_gesture(Wl.G_PEDAL_START)
	assert_signal_emit_count(_router, "menu_input", 3, "pedal_start maps to nothing")


func test_menu_mapping_in_erg() -> void:
	var rider: FakeRider = autofree(FakeRider.new())
	rider.fake_mode = Wl.ERG
	_router.attach_rider(rider)
	assert_eq(_router.local_mode(), Wl.ERG)
	_router.inject_gesture(Wl.G_COAST)
	_router.inject_gesture(Wl.G_STOP_5S)
	assert_signal_not_emitted(_router, "menu_input", "coast is never back in ERG; no pause in ERG")
	_router.inject_gesture(Wl.G_SURGE)
	assert_eq(
		get_signal_parameters(_router, "menu_input"), [&"confirm", "surge"], "surge confirms in ERG"
	)
	assert_eq(_router.take_gestures().size(), 3, "every gesture still reaches sessions")


func test_stop_5s_pauses_only_in_solo() -> void:
	_router.solo = false
	_router.inject_gesture(Wl.G_STOP_5S)
	assert_signal_not_emitted(_router, "menu_input")
	_router.solo = true
	_router.inject_gesture(Wl.G_STOP_5S)
	assert_eq(get_signal_parameters(_router, "menu_input"), [&"pause", "stop_5s"])


func test_device_actions_reach_menu_input() -> void:
	_tap(KEY_ESCAPE)
	assert_eq(get_signal_parameters(_router, "menu_input"), [&"back", "action"])


# --- pedal UI ---------------------------------------------------------------------------------


func test_pedal_nav_active_follows_profile() -> void:
	_router.profile.pedal_nav = false
	_router.profile.autopilot_default = false
	assert_false(_router.pedal_nav_active(), "off by default, whatever device is used")
	_router.profile.pedal_nav = true
	assert_true(_router.pedal_nav_active())
	_router.profile.pedal_nav = false
	_router.profile.autopilot_default = true
	assert_true(_router.pedal_nav_active(), "Autopilot keeps pedal navigation on")


func test_surge_and_coast_pick_and_back_only_with_pedal_navigation() -> void:
	var got: Array = []
	_router.menu_input.connect(func(a: StringName, via: String) -> void: got.append([a, via]))
	_router.profile.pedal_nav = false
	_router.profile.autopilot_default = false
	_router.inject_gesture(Wl.G_SURGE)
	_router.inject_gesture(Wl.G_COAST)
	assert_eq(got, [], "no menu input from pedal gestures while pedal navigation is off")
	assert_eq(_router.take_gestures().size(), 2, "the gestures still reach sessions")
	_router.profile.pedal_nav = true
	_router.inject_gesture(Wl.G_SURGE)
	_router.inject_gesture(Wl.G_COAST)
	assert_eq(got, [[&"confirm", "surge"], [&"back", "coast"]])


# --- rebinding ------------------------------------------------------------------------------


func test_rebind_replaces_same_family_only() -> void:
	_router.rebind(&"confirm", _key(KEY_K, true))
	var ev := _router.bindings(&"confirm")
	assert_true(_has_key(ev, KEY_K))
	assert_false(_has_key(ev, KEY_ENTER), "keyboard bindings replaced")
	assert_true(_has_button(ev, JOY_BUTTON_A), "controller binding kept")
	_tap(KEY_ENTER)
	assert_eq(_router.take_actions(), [])
	_tap(KEY_K)
	assert_eq(_router.take_actions(), [&"confirm"])


func test_rebind_removes_the_input_from_other_actions() -> void:
	_router.rebind(&"item", _key(KEY_ESCAPE, true))
	assert_false(_has_key(_router.bindings(&"back"), KEY_ESCAPE))
	_tap(KEY_ESCAPE)
	assert_eq(_router.take_actions(), [&"item"])


## A captured key carries both codes; the binding keeps the physical key (like the defaults),
## so it fires for that key under any layout and same_input() agrees with matching.
func test_rebind_binds_the_physical_key() -> void:
	var captured := InputEventKey.new()
	captured.physical_keycode = KEY_Y
	captured.keycode = KEY_Z
	captured.pressed = true
	_router.rebind(&"item", captured)
	var bound := _router.bindings(&"item")
	var key_events := bound.filter(func(e: InputEvent) -> bool: return e is InputEventKey)
	assert_eq(key_events.size(), 1)
	assert_eq((key_events[0] as InputEventKey).physical_keycode, KEY_Y)
	assert_eq((key_events[0] as InputEventKey).keycode, KEY_NONE, "matched by physical key")
	var other_layout := InputEventKey.new()
	other_layout.physical_keycode = KEY_Y
	other_layout.keycode = KEY_A
	other_layout.pressed = true
	_router.handle_event(other_layout)
	assert_eq(_router.take_actions(), [&"item"], "same physical key, other layout")
	var only_logical := InputEventKey.new()
	only_logical.keycode = KEY_J
	only_logical.pressed = true
	_router.rebind(&"swap", only_logical)
	_router.handle_event(only_logical)
	assert_eq(
		_router.take_actions(), [&"swap"], "an event without a physical code binds by keycode"
	)


func test_rebind_unknown_action_is_rejected() -> void:
	_router.rebind(&"jump", _key(KEY_J, true))
	assert_push_error("unknown action")


func test_add_binding_keeps_existing() -> void:
	assert_true(_router.add_binding(&"confirm", _key(KEY_C, true)))
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_C))
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_ENTER))


func test_save_and_load_bindings() -> void:
	_router.rebind(&"confirm", _key(KEY_K, true))
	_router.rebind(&"pause", _joy(JOY_BUTTON_Y, true))
	assert_true(_router.save_bindings())
	assert_true(FileAccess.file_exists(Paths.input_cfg_path()))
	assert_eq(Paths.input_cfg_path(), _dir.path_join("input.cfg"))
	_router.reset_bindings()
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_ENTER), "defaults back")
	_router.load_bindings()
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_K))
	assert_false(_has_key(_router.bindings(&"confirm"), KEY_ENTER))
	assert_true(_has_button(_router.bindings(&"pause"), JOY_BUTTON_Y))
	assert_false(_has_button(_router.bindings(&"pause"), JOY_BUTTON_START))
	assert_false(_has_button(_router.bindings(&"ability_2"), JOY_BUTTON_Y), "moved off ability_2")


func test_new_router_loads_saved_bindings() -> void:
	_router.rebind(&"swap", _key(KEY_T, true))
	_router.save_bindings()
	InputBindings.reset_to_defaults()
	var other := WlInputRouter.new()
	other.bus = _bus
	add_child_autofree(other)
	assert_true(_has_key(other.bindings(&"swap"), KEY_T))


func test_load_without_file_gives_defaults() -> void:
	_router.rebind(&"confirm", _key(KEY_K, true))
	_router.load_bindings()
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_ENTER))


func test_load_bad_version_keeps_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "version", 99)
	cfg.set_value(
		"bindings", "confirm", [{"type": "key", "physical_keycode": int(KEY_K), "keycode": 0}]
	)
	cfg.save(Paths.input_cfg_path())
	_router.load_bindings()
	assert_push_warning("version")
	assert_true(_has_key(_router.bindings(&"confirm"), KEY_ENTER))
	assert_false(_has_key(_router.bindings(&"confirm"), KEY_K))


func test_load_ignores_unknown_actions() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "version", 1)
	cfg.set_value(
		"bindings", "jump", [{"type": "key", "physical_keycode": int(KEY_J), "keycode": 0}]
	)
	cfg.set_value(
		"bindings", "back", [{"type": "key", "physical_keycode": int(KEY_B), "keycode": 0}]
	)
	cfg.save(Paths.input_cfg_path())
	_router.load_bindings()
	assert_push_warning("unknown action")
	assert_true(_has_key(_router.bindings(&"back"), KEY_B))
	assert_false(InputMap.has_action(&"jump"))


func test_event_dict_round_trip() -> void:
	var events: Array[InputEvent] = [
		_key(KEY_ENTER, true),
		_joy(JOY_BUTTON_A, true),
		_axis(JOY_AXIS_LEFT_X, -0.6),
	]
	for e in events:
		var d := InputBindings.event_to_dict(e)
		assert_false(d.is_empty())
		var back := InputBindings.dict_to_event(d)
		assert_true(InputBindings.same_input(e, back), str(d))
	assert_eq(InputBindings.event_to_dict(InputEventMouseMotion.new()), {})
	assert_null(InputBindings.dict_to_event({"type": "nope"}))


func test_typing_in_a_text_field_fires_no_actions_or_panic() -> void:
	var field := LineEdit.new()
	add_child_autofree(field)
	field.grab_focus()
	assert_true(_router.text_input_focused())
	_tap(KEY_R)
	_tap(KEY_P)
	_router.handle_event(_key(KEY_BACKSPACE, true))
	_router.tick(3.0)
	assert_eq(_router.take_actions(), [], "letters belong to the field")
	assert_signal_not_emitted(_bus, "panic_requested", "holding Backspace to delete is not panic")
	_router.handle_event(_key(KEY_BACKSPACE, false))
	_router.handle_event(_joy(JOY_BUTTON_BACK, true))
	_router.handle_event(_joy(JOY_BUTTON_START, true))
	assert_signal_emit_count(_bus, "panic_requested", 1, "the controller chord still works")
	field.release_focus()
	assert_false(_router.text_input_focused())
	_tap(KEY_R)
	assert_eq(_router.take_actions(), [&"panic", &"swap"])


# --- controls screen helpers ------------------------------------------------------------------


func test_binding_labels() -> void:
	var labels := _router.binding_labels(&"confirm")
	assert_has(labels, "Enter")
	assert_has(labels, "Space")
	assert_has(labels, "A")
	assert_has(_router.binding_labels(&"panic"), "View")
	assert_has(_router.binding_labels(&"pause"), "Menu")
	assert_has(_router.binding_labels(&"up"), "Left stick up")
	assert_has(_router.binding_labels(&"shift_up"), "RT")
	assert_has(_router.binding_labels(&"swap"), "LB")


func test_capture_binds_the_next_press() -> void:
	watch_signals(_router)
	_router.start_capture(&"item")
	assert_eq(_router.capturing(), &"item")
	_router.handle_event(_key(KEY_K, true))
	assert_eq(_router.capturing(), &"")
	assert_signal_emit_count(_router, "binding_captured", 1)
	var params: Array = get_signal_parameters(_router, "binding_captured")
	assert_eq(params[0], &"item")
	assert_true(InputBindings.same_input(params[1], _key(KEY_K, true)))
	assert_eq(_router.take_actions(), [], "the captured press fires nothing")
	_router.handle_event(_key(KEY_K, false))
	_tap(KEY_K)
	assert_eq(_router.take_actions(), [&"item"])
	_tap(KEY_F)
	assert_eq(_router.take_actions(), [], "F was replaced")


func test_capture_a_trigger_moves_it() -> void:
	_router.start_capture(&"swap")
	_router.handle_event(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.3))
	assert_eq(_router.capturing(), &"swap", "a light touch is not a press")
	_router.handle_event(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	assert_has(_router.binding_labels(&"swap"), "RT")
	assert_does_not_have(_router.binding_labels(&"shift_up"), "RT", "removed from shift_up")


func test_capture_unknown_and_cancel() -> void:
	_router.start_capture(&"jump")
	assert_push_error("unknown action")
	assert_eq(_router.capturing(), &"")
	_router.start_capture(&"item")
	_router.cancel_capture()
	_tap(KEY_F)
	assert_eq(_router.take_actions(), [&"item"])


## F11 and Alt+Enter toggle fullscreen (WlWindowMode, the app shell): no action fires for them,
## though plain Enter is `confirm`, and no default binding uses F11.
func test_fullscreen_keys_are_never_actions() -> void:
	var f11 := _key(KEY_F11, true)
	for a: StringName in Wl.ACTIONS:
		assert_false(InputMap.has_action(a) and f11.is_action(a), "F11 is not bound to %s" % a)
	_router.handle_event(f11)
	var alt_enter := _key(KEY_ENTER, true)
	alt_enter.alt_pressed = true
	_router.handle_event(alt_enter)
	assert_eq(_router.take_actions(), [], "neither is an action")
	_router.handle_event(_key(KEY_ENTER, false))
	_router.handle_event(_key(KEY_ENTER, true))
	assert_eq(_router.take_actions(), [&"confirm"], "plain Enter still confirms")
