extends GutTest
## HudMockKeys: the platform's one-line readout of the mock trainer's keyboard control, in the
## bottom-right corner of the session HUD, shown only while a MockTrainer has the keyboard on.

const SCREEN := Vector2(1920, 1080)

var _hud: HudLayer = null


func before_each() -> void:
	_hud = HudLayer.new()
	_hud.screen_size_override = SCREEN
	_hud.sounds = false
	add_child_autofree(_hud)
	_hud.set_process(false)


func _mock(keyboard: bool) -> MockTrainer:
	var m := MockTrainer.from_spec("erg", 250.0, {"keyboard": keyboard})
	autofree(m)
	m.key_reader = func(_k: Key) -> bool: return false
	m.focus_reader = func() -> bool: return true
	return m


func test_hidden_without_a_mock_with_keyboard_control() -> void:
	var line := _hud.mock_keys()
	line.refresh()
	assert_false(line.visible, "no MockTrainer device")
	line.source = _mock(false)
	line.refresh()
	assert_false(line.visible, "a mock whose keyboard is off")


func test_shows_power_cadence_and_keys_while_the_keyboard_is_on() -> void:
	var m := _mock(true)
	m.tick(Wl.SIM_DT)
	m.keyboard_preset(5)
	m.tick(Wl.SIM_DT)
	var line := _hud.mock_keys()
	line.source = m
	line.refresh()
	assert_true(line.visible)
	assert_eq(line.text, HudMockKeys.readout_text(375.0, 95.0))
	assert_true(line.text.begins_with("MOCK 375 W 95 rpm ["), line.text)
	m.keyboard_stop()
	m.tick(Wl.SIM_DT)
	line.refresh()
	assert_true(line.text.begins_with("MOCK 0 W 0 rpm"), line.text)
	m.set_keyboard_enabled(false)
	line.refresh()
	assert_false(line.visible, "gone with the keyboard control")


func test_sits_in_the_bottom_right_corner_and_stays_on_screen() -> void:
	var m := _mock(true)
	var line := _hud.mock_keys()
	line.source = m
	line.refresh()
	_hud.relayout()
	var r := Rect2(line.position, line.size)
	assert_true(Rect2(Vector2.ZERO, SCREEN).encloses(r), "inside the screen: %s" % r)
	assert_almost_eq(r.end.x, SCREEN.x - HudMockKeys.EDGE_PX, 1.0)
	assert_almost_eq(r.end.y, SCREEN.y - HudMockKeys.EDGE_PX, 1.0)
	assert_eq(line.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_lt(line.size.y, float(WlTheme.MARGIN_PX), "small enough for the HUD's own margin")
	m.keyboard_preset(9)
	m.tick(Wl.SIM_DT)
	m.tick(Wl.SIM_DT)
	line.refresh()
	assert_almost_eq(line.position.x + line.size.x, SCREEN.x - HudMockKeys.EDGE_PX, 1.0)


func test_uses_the_games_hud_palette() -> void:
	var spec := HudSpec.new()
	spec.palette = {"text_dim": Color("#ff8800")}
	_hud.build(spec, null)
	var line := _hud.mock_keys()
	assert_eq(line.label_settings.font_color, Color("#ff8800"))
	_hud.build(HudSpec.new(), null)
	assert_eq(line.label_settings.font_color, WlTheme.TEXT_DIM, "the kit default without a palette")
