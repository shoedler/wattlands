class_name WlInputRouter
extends Node
## Autoload `InputRouter` (BRIEF 3.5): keyboard and Xbox controller actions (rebindable,
## saved to Paths.input_cfg_path()), merged with the local rider's pedal gestures for menus
## and sessions. Owned by ui-hud; public API frozen after W0. Runs with
## PROCESS_MODE_ALWAYS.
## Defaults: arrows/WASD move, Enter/Space confirm, Esc back, 1/2 abilities, F item, R swap,
## Q/E shift down/up, P pause, Backspace held 1 s panic; controller: left stick/D-pad move,
## A confirm, B back, X/Y abilities, RB item, LB swap, LT/RT shift down/up, Start pause,
## View+Menu together panic. Panic emits EventBus.panic_requested immediately.
## Pedal UI: `surge` acts as confirm and `coast` as back for menus (pedal-scan), `stop_5s`
## as pause (solo, outside ERG).
##
## How the parts fit:
## - Keyboard presses are ignored while a LineEdit or TextEdit has focus (text_input_focused()).
## - Device actions fire once per press (edge-detected per key, button or stick direction;
##   key repeats are ignored). Each goes into the take_actions() queue, the `action` signal,
##   EventBus.action_pressed and `menu_input(action, "action")`.
## - Panic: a keyboard (or other non-chord) binding of `panic` fires after being held
##   PANIC_HOLD_S; a joypad binding of `panic` (View) fires at once together with a joypad
##   binding of `pause` (Menu). Pressing Menu while View is held fires panic instead of pause.
##   View alone does nothing. Panic emits `action(&"panic")`, EventBus.action_pressed,
##   EventBus.panic_requested and queues &"panic".
## - Gestures come from the attached LocalRider's gesture_detected signal (or
##   inject_gesture). Each goes into the take_gestures() queue, the `gesture` signal and
##   EventBus.gesture. Gestures never enter the action queue: sessions read them apart through
##   local_intents. The `action` signal (and EventBus.action_pressed, take_actions()) never
##   carries an action made from a gesture: a surge never also arrives as `confirm`, a coast
##   never as `back`, a stop_5s never as `pause`. Screens that feed both the `action` and the
##   `gesture` signal to one PedalScanList (the app shell) therefore get each pick once. Menus (PedalScanList, app screens) listen to `menu_input`, which maps
##   surge -> confirm (via "surge"), coast -> back (via "coast", never in ERG) and
##   stop_5s -> pause (via "stop_5s", solo and outside ERG only).
## - The GameHost drains take_actions() and take_gestures() each tick and must filter `pause`
##   and `panic` out before calling GameModule.local_intents (they are platform actions,
##   PLATFORM_ACTIONS).

signal action(action_name: StringName)
signal gesture(gesture_name: StringName)
## Menu-level input: device actions and the pedal-UI mappings. via: "action" (keyboard,
## controller or inject_action), "surge", "coast" or "stop_5s".
signal menu_input(action_name: StringName, via: String)
## start_capture() bound the next press to an action (not saved until save_bindings()).
signal binding_captured(action_name: StringName, event: InputEvent)

## Seconds a keyboard panic binding must be held.
const PANIC_HOLD_S := 1.0
## Queues drop their oldest entries beyond this (nobody drains them in menus).
const QUEUE_LIMIT := 256
## Actions the platform consumes; never passed to GameModule.local_intents.
const PLATFORM_ACTIONS: Array[StringName] = [&"pause", &"panic"]

## The bus to emit on; null means the EventBus autoload.
var bus: WlEventBus = null
## The profile for pedal_ui_active(); null means Settings.profile.
var profile: RiderProfile = null
## Solo session or menus (stop_5s maps to pause only when solo). The GameHost sets it.
var solo: bool = true
## Load input.cfg in _ready (private test instances may turn it off).
var load_on_ready: bool = true

var _rider: LocalRider = null
var _actions: Array[StringName] = []
var _gestures: Array[StringName] = []
## "<action>|<source>" -> true while that input is down.
var _held: Dictionary = {}
## Panic hold timers: source -> seconds held.
var _panic_holds: Dictionary = {}
## Sources whose panic hold already fired (until released).
var _panic_fired: Dictionary = {}
var _device_used: bool = false
var _capture_action: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputBindings.ensure_actions()
	if load_on_ready:
		load_bindings()


func _input(event: InputEvent) -> void:
	handle_event(event)


func _process(delta: float) -> void:
	tick(delta)


## Feed one input event (the _input callback; tests call it directly).
func handle_event(event: InputEvent) -> void:
	if event == null:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _capture_action != &"" and _is_capture_press(event):
		var a := _capture_action
		_capture_action = &""
		rebind(a, event)
		binding_captured.emit(a, InputBindings.dict_to_event(InputBindings.event_to_dict(event)))
		return
	if event is InputEventKey and (event as InputEventKey).pressed and text_input_focused():
		return
	var src := _source_id(event)
	if src.is_empty():
		return
	for a: StringName in Wl.ACTIONS:
		if not InputMap.has_action(a) or not event.is_action(a):
			continue
		var key := String(a) + "|" + src
		if event.is_action_pressed(a):
			if _held.has(key):
				continue
			_held[key] = true
			_device_used = true
			_on_press(a, src)
		elif _held.has(key):
			_held.erase(key)
			_on_release(a, src)


## Advance hold timers by dt seconds (_process calls it with the frame delta).
func tick(dt: float) -> void:
	for src: String in _panic_holds.keys():
		if _panic_fired.has(src):
			continue
		var held_s: float = float(_panic_holds[src]) + maxf(dt, 0.0)
		_panic_holds[src] = held_s
		if held_s >= PANIC_HOLD_S - 1e-6:
			_panic_fired[src] = true
			_fire_panic()


## Gestures from this rider feed menus and sessions (TrainerService/GameHost attach it).
## Attaching a different rider (a session starting) clears the action and gesture queues,
## so presses made in menus, which nobody drains, never reach the session's first tick.
func attach_rider(rider: LocalRider) -> void:
	var changed := rider != attached_rider()
	detach_rider()
	if changed:
		clear_queues()
	_rider = rider
	if rider != null and not rider.gesture_detected.is_connected(_on_rider_gesture):
		rider.gesture_detected.connect(_on_rider_gesture)


func detach_rider() -> void:
	if _rider != null and is_instance_valid(_rider):
		if _rider.gesture_detected.is_connected(_on_rider_gesture):
			_rider.gesture_detected.disconnect(_on_rider_gesture)
	_rider = null


## The attached rider (null if none).
func attached_rider() -> LocalRider:
	if _rider != null and not is_instance_valid(_rider):
		_rider = null
	return _rider


## The attached rider's current trainer mode ("ERG", "SIM", "OFF"), "" with no rider.
func local_mode() -> String:
	var r := attached_rider()
	if r == null:
		return ""
	var t := r.telemetry()
	return t.mode if t != null else ""


## Actions since the last call (the GameHost drains it every tick for local_intents).
func take_actions() -> Array[StringName]:
	var out: Array[StringName] = _actions.duplicate()
	_actions.clear()
	return out


## Gestures since the last call.
func take_gestures() -> Array[StringName]:
	var out: Array[StringName] = _gestures.duplicate()
	_gestures.clear()
	return out


## Drop queued actions and gestures (a session starts with empty queues).
func clear_queues() -> void:
	_actions.clear()
	_gestures.clear()


## True when menus run on pedal-scan (Autopilot or pedal UI on, or no input device used yet).
func pedal_ui_active() -> bool:
	var p := _profile()
	if p != null and (p.pedal_ui or p.autopilot_default):
		return true
	return not _device_used


## True once a keyboard or controller action was pressed.
func device_used() -> bool:
	return _device_used


## True while a text field (LineEdit, TextEdit) has keyboard focus: key presses then belong
## to the field (typing a room code, holding Backspace to delete) and fire no action and no
## panic hold. Key releases still pass so held actions end cleanly. Controller input is
## never filtered.
func text_input_focused() -> bool:
	if not is_inside_tree():
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	var owner_control := vp.gui_get_focus_owner()
	return owner_control is LineEdit or owner_control is TextEdit


## Inject an action (on-screen buttons, tests).
func inject_action(action_name: StringName) -> void:
	if not Wl.ACTIONS.has(action_name):
		push_error("InputRouter: unknown action %s" % action_name)
		return
	if action_name == &"panic":
		_fire_panic()
	else:
		_fire_action(action_name)


## Inject a gesture (tests).
func inject_gesture(gesture_name: StringName) -> void:
	_push(_gestures, gesture_name)
	gesture.emit(gesture_name)
	var b := _bus()
	if b != null:
		b.gesture.emit(gesture_name)
	var in_erg := local_mode() == Wl.ERG
	if gesture_name == Wl.G_SURGE:
		menu_input.emit(&"confirm", "surge")
	elif gesture_name == Wl.G_COAST:
		if not in_erg:
			menu_input.emit(&"back", "coast")
	elif gesture_name == Wl.G_STOP_5S:
		if solo and not in_erg:
			menu_input.emit(&"pause", "stop_5s")


## Bind `event` to `action_name`, replacing that action's binding of the same family
## (keyboard or controller) and removing the input from any other action.
func rebind(action_name: StringName, event: InputEvent) -> void:
	if InputBindings.rebind(action_name, event):
		_reset_held()


## Add a second binding to an action (nothing is replaced).
func add_binding(action_name: StringName, event: InputEvent) -> bool:
	var ok := InputBindings.add_binding(action_name, event)
	if ok:
		_reset_held()
	return ok


## Restore the project.godot defaults (not saved until save_bindings()).
func reset_bindings() -> void:
	InputBindings.reset_to_defaults()
	_reset_held()


## The events bound to `action_name` now.
func bindings(action_name: StringName) -> Array[InputEvent]:
	return InputBindings.events_of(action_name)


## Short labels of the bindings of `action_name` ("Enter", "Space", "A").
func binding_labels(action_name: StringName) -> Array[String]:
	var out: Array[String] = []
	for e in InputBindings.events_of(action_name):
		var s := InputBindings.describe(e)
		if not s.is_empty():
			out.append(s)
	return out


## Bind the next key, button, trigger or stick press to `action_name` (the controls screen).
## That press fires no action; binding_captured follows. Not saved until save_bindings().
func start_capture(action_name: StringName) -> void:
	if not Wl.ACTIONS.has(action_name):
		push_error("InputRouter: unknown action %s" % action_name)
		return
	_capture_action = action_name
	_reset_held()


func cancel_capture() -> void:
	_capture_action = &""


## The action waiting for a press (&"" when not capturing).
func capturing() -> StringName:
	return _capture_action


func save_bindings() -> bool:
	return InputBindings.save(Paths.input_cfg_path())


func load_bindings() -> void:
	InputBindings.load_from(Paths.input_cfg_path())
	_reset_held()


# --- internals ---------------------------------------------------------------------------

func _on_press(a: StringName, src: String) -> void:
	if a == &"panic":
		if _is_joy(src) and _has_joy_binding(&"pause"):
			if _joy_held(&"pause"):
				_fire_panic()
			return
		_panic_holds[src] = 0.0
		_panic_fired.erase(src)
		return
	if a == &"pause" and _is_joy(src) and _joy_held(&"panic"):
		_fire_panic()
		return
	_fire_action(a)


func _on_release(a: StringName, src: String) -> void:
	if a == &"panic":
		_panic_holds.erase(src)
		_panic_fired.erase(src)


func _fire_action(a: StringName) -> void:
	_push(_actions, a)
	action.emit(a)
	var b := _bus()
	if b != null:
		b.action_pressed.emit(a)
	menu_input.emit(a, "action")


func _fire_panic() -> void:
	_push(_actions, &"panic")
	action.emit(&"panic")
	var b := _bus()
	if b != null:
		b.action_pressed.emit(&"panic")
		b.panic_requested.emit()


func _on_rider_gesture(gesture_name: StringName) -> void:
	inject_gesture(gesture_name)


func _push(queue: Array[StringName], item: StringName) -> void:
	queue.append(item)
	while queue.size() > QUEUE_LIMIT:
		queue.remove_at(0)


func _reset_held() -> void:
	_held.clear()
	_panic_holds.clear()
	_panic_fired.clear()


func _joy_held(a: StringName) -> bool:
	var prefix := String(a) + "|j"
	for k: String in _held.keys():
		if k.begins_with(prefix):
			return true
	return false


func _has_joy_binding(a: StringName) -> bool:
	for e in InputBindings.events_of(a):
		if InputBindings.family(e) == "joypad":
			return true
	return false


static func _is_capture_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= 0.6
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	return false


static func _is_joy(src: String) -> bool:
	return src.begins_with("j")


static func _source_id(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		return "k:%d" % code
	if event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		return "jb:%d:%d" % [b.device, int(b.button_index)]
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return "ja:%d:%d" % [m.device, int(m.axis)]
	if event is InputEventMouseButton:
		return "mb:%d" % int((event as InputEventMouseButton).button_index)
	return ""


func _bus() -> WlEventBus:
	if bus != null:
		return bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus") as WlEventBus
	return null


func _profile() -> RiderProfile:
	if profile != null:
		return profile
	if is_inside_tree():
		var s := get_node_or_null("/root/Settings") as WlSettings
		if s != null:
			return s.profile
	return null
