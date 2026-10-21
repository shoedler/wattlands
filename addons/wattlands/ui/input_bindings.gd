class_name InputBindings
extends RefCounted
## Rebindable input bindings (BRIEF 3.5): the defaults come from project.godot's input map,
## changes are applied to InputMap and saved as plain data in input.cfg
## (Paths.input_cfg_path(), a ConfigFile). Owned by ui-hud; WlInputRouter uses it.
##
## input.cfg layout:
##   [input]    version = 1
##   [bindings] <action> = [{"type": "key", "physical_keycode": 4194309}, ...]
## Event dictionaries: {"type": "key", "physical_keycode": int, "keycode": int},
## {"type": "joy_button", "button": int}, {"type": "joy_motion", "axis": int, "value": float},
## {"type": "mouse_button", "button": int}. Only actions in Wl.ACTIONS are saved and loaded.

const VERSION := 1
const SECTION_META := "input"
const SECTION_BINDINGS := "bindings"


## The project.godot default events of `action` (fresh copies).
static func default_events(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var setting: Variant = ProjectSettings.get_setting("input/" + String(action), null)
	if setting is Dictionary:
		var events: Variant = (setting as Dictionary).get("events", [])
		if events is Array:
			for e: Variant in events:
				if e is InputEvent:
					out.append((e as InputEvent).duplicate() as InputEvent)
	return out


## The project.godot deadzone of `action` (0.5 if unset).
static func default_deadzone(action: StringName) -> float:
	var setting: Variant = ProjectSettings.get_setting("input/" + String(action), null)
	if setting is Dictionary:
		return float((setting as Dictionary).get("deadzone", 0.5))
	return 0.5


## Make sure every Wl.ACTIONS action exists in InputMap (headless tools, tests).
static func ensure_actions() -> void:
	for action: StringName in Wl.ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, default_deadzone(action))
			for e in default_events(action):
				InputMap.action_add_event(action, e)


## Reset every Wl.ACTIONS action to its project.godot events.
static func reset_to_defaults() -> void:
	for action: StringName in Wl.ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, default_deadzone(action))
		for e in default_events(action):
			InputMap.action_add_event(action, e)


## The events currently bound to `action`.
static func events_of(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if InputMap.has_action(action):
		for e: InputEvent in InputMap.action_get_events(action):
			out.append(e)
	return out


## "keyboard" (keys and mouse buttons), "joypad" (buttons and axes) or "" for other events.
static func family(event: InputEvent) -> String:
	if event is InputEventKey or event is InputEventMouseButton:
		return "keyboard"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "joypad"
	return ""


## True when two events stand for the same physical input (key, button or axis direction).
static func same_input(a: InputEvent, b: InputEvent) -> bool:
	var da := event_to_dict(a)
	var db := event_to_dict(b)
	if da.is_empty() or db.is_empty():
		return false
	if da["type"] != db["type"]:
		return false
	match str(da["type"]):
		"key":
			return _key_code(da) == _key_code(db)
		"joy_button", "mouse_button":
			return int(da["button"]) == int(db["button"])
		"joy_motion":
			return int(da["axis"]) == int(db["axis"]) and signf(float(da["value"])) == signf(float(db["value"]))
	return false


## Bind `event` to `action`: it replaces the action's events of the same family (keyboard or
## joypad) and is removed from every other action, so one input never does two things.
## Returns false (push_error) for an unknown action or an unsupported event.
static func rebind(action: StringName, event: InputEvent) -> bool:
	if not Wl.ACTIONS.has(action) or not InputMap.has_action(action):
		push_error("InputBindings: unknown action %s" % action)
		return false
	var d := event_to_dict(event)
	if d.is_empty():
		push_error("InputBindings: unsupported event for %s: %s" % [action, event])
		return false
	var clean := dict_to_event(d)
	var fam := family(clean)
	for other: StringName in Wl.ACTIONS:
		if not InputMap.has_action(other):
			continue
		for e: InputEvent in InputMap.action_get_events(other):
			if same_input(e, clean) or (other == action and family(e) == fam):
				InputMap.action_erase_event(other, e)
	InputMap.action_add_event(action, clean)
	return true


## Add `event` to `action` without removing anything (a second key for the same action).
static func add_binding(action: StringName, event: InputEvent) -> bool:
	if not Wl.ACTIONS.has(action) or not InputMap.has_action(action):
		push_error("InputBindings: unknown action %s" % action)
		return false
	var d := event_to_dict(event)
	if d.is_empty():
		push_error("InputBindings: unsupported event for %s: %s" % [action, event])
		return false
	var clean := dict_to_event(d)
	for e: InputEvent in InputMap.action_get_events(action):
		if same_input(e, clean):
			return true
	InputMap.action_add_event(action, clean)
	return true


## Save the current bindings of every Wl.ACTIONS action to `path`.
static func save(path: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_META, "version", VERSION)
	for action: StringName in Wl.ACTIONS:
		var arr: Array = []
		for e in events_of(action):
			var d := event_to_dict(e)
			if not d.is_empty():
				arr.append(d)
		cfg.set_value(SECTION_BINDINGS, String(action), arr)
	var err := cfg.save(path)
	if err != OK:
		push_warning("InputBindings: could not save %s (error %d)" % [path, err])
		return false
	return true


## Load bindings from `path` into InputMap. Actions missing from the file keep their
## project.godot defaults; a missing file means defaults only. Returns true if a file was
## applied.
static func load_from(path: String) -> bool:
	reset_to_defaults()
	if not FileAccess.file_exists(path):
		return false
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		push_warning("InputBindings: unreadable %s (error %d), using defaults" % [path, err])
		return false
	var version := int(cfg.get_value(SECTION_META, "version", 0))
	if version != VERSION:
		push_warning("InputBindings: %s has version %d (want %d), using defaults" % [path, version, VERSION])
		return false
	if not cfg.has_section(SECTION_BINDINGS):
		return true
	for key: String in cfg.get_section_keys(SECTION_BINDINGS):
		var action := StringName(key)
		if not Wl.ACTIONS.has(action):
			push_warning("InputBindings: ignoring unknown action %s in %s" % [key, path])
			continue
		var arr: Variant = cfg.get_value(SECTION_BINDINGS, key, [])
		if not (arr is Array):
			continue
		InputMap.action_erase_events(action)
		for d: Variant in arr:
			if d is Dictionary:
				var e := dict_to_event(d)
				if e != null:
					InputMap.action_add_event(action, e)
	return true


## A plain-data description of `event` ({} for unsupported events).
static func event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k := event as InputEventKey
		return {"type": "key", "physical_keycode": int(k.physical_keycode), "keycode": int(k.keycode)}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return {"type": "joy_motion", "axis": int(m.axis), "value": -1.0 if m.axis_value < 0.0 else 1.0}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button": int((event as InputEventMouseButton).button_index)}
	return {}


## The event described by `d` (null for an unknown type).
static func dict_to_event(d: Dictionary) -> InputEvent:
	match str(d.get("type", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("physical_keycode", 0)) as Key
			k.keycode = int(d.get("keycode", 0)) as Key
			return k
		"joy_button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(d.get("button", 0)) as JoyButton
			b.device = -1
			return b
		"joy_motion":
			var m := InputEventJoypadMotion.new()
			m.axis = int(d.get("axis", 0)) as JoyAxis
			m.axis_value = -1.0 if float(d.get("value", 1.0)) < 0.0 else 1.0
			m.device = -1
			return m
		"mouse_button":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("button", 1)) as MouseButton
			return mb
	return null


static func _key_code(d: Dictionary) -> int:
	var p := int(d.get("physical_keycode", 0))
	return p if p != 0 else int(d.get("keycode", 0))
