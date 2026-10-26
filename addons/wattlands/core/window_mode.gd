class_name WlWindowMode
extends RefCounted
## Fullscreen (the Settings key `fullscreen`): applied at boot (the app shell's main scene),
## switched from Settings > Audio and display, and toggled anywhere with F11 or Alt+Enter.
## Fullscreen is DisplayServer.WINDOW_MODE_FULLSCREEN, off is WINDOW_MODE_WINDOWED. The two
## shortcuts are platform keys: WlInputRouter never turns them into actions (Alt+Enter is not
## `confirm`) and a key capture never binds them. A headless display server ignores the mode.


## True for a press of F11 (any modifiers) or Alt+Enter (either Enter key); key repeats are not.
static func is_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return false
	var key := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if key == KEY_F11:
		return true
	return k.alt_pressed and (key == KEY_ENTER or key == KEY_KP_ENTER)


## Switch the window to fullscreen or windowed (nothing on a headless display server).
static func apply(fullscreen: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := (
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## The stored setting (false without settings).
static func stored(settings: WlSettings) -> bool:
	return settings != null and bool(settings.get_value("fullscreen", false))


## Store `fullscreen` (WlSettings saves it and emits EventBus.settings_changed) and apply it.
static func set_fullscreen(settings: WlSettings, fullscreen: bool) -> void:
	if settings != null:
		settings.set_value("fullscreen", fullscreen)
	apply(fullscreen)


## Flip the stored setting (F11 / Alt+Enter); returns the new value.
static func toggle(settings: WlSettings) -> bool:
	var on := not stored(settings)
	set_fullscreen(settings, on)
	return on
