extends GutTest
## WlWindowMode: F11 and Alt+Enter are the fullscreen toggles (presses only), and the Settings
## key `fullscreen` stores the choice (the window itself stays put on the headless test server).

const Util := preload("res://tests/core/helpers/core_test_util.gd")

var _dir: String = ""
var _settings: WlSettings = null


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_window_mode_test")
	Paths.set_override(_dir)
	_settings = WlSettings.new()
	_settings.bus = autofree(WlEventBus.new())
	autofree(_settings)
	_settings.load_all()


func after_each() -> void:
	Paths.set_override("")
	Util.remove_tree(_dir)


static func _key(code: Key, alt: bool = false, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.alt_pressed = alt
	e.pressed = pressed
	return e


func test_toggle_keys() -> void:
	assert_true(WlWindowMode.is_toggle_event(_key(KEY_F11)))
	assert_true(WlWindowMode.is_toggle_event(_key(KEY_ENTER, true)))
	assert_true(WlWindowMode.is_toggle_event(_key(KEY_KP_ENTER, true)))
	assert_false(WlWindowMode.is_toggle_event(_key(KEY_ENTER)), "Enter alone confirms")
	assert_false(WlWindowMode.is_toggle_event(_key(KEY_F11, false, false)), "a release")
	var echo := _key(KEY_F11)
	echo.echo = true
	assert_false(WlWindowMode.is_toggle_event(echo), "a key repeat")
	assert_false(WlWindowMode.is_toggle_event(InputEventMouseButton.new()))


func test_toggle_flips_and_saves_the_setting() -> void:
	assert_false(WlWindowMode.stored(_settings), "windowed by default")
	assert_true(WlWindowMode.toggle(_settings))
	assert_true(bool(_settings.get_value("fullscreen")))
	var again := WlSettings.new()
	autofree(again)
	again.load_all()
	assert_true(WlWindowMode.stored(again), "saved to settings.json")
	assert_false(WlWindowMode.toggle(_settings))
	assert_false(WlWindowMode.stored(_settings))
	assert_false(WlWindowMode.stored(null), "no settings: windowed")
