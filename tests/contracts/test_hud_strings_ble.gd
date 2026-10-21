extends GutTest
## HudSpec (BRIEF 3.9), GameStrings (BRIEF 3.6, 6) and BleTransport's UUID helpers
## (BRIEF 4.2, 4.3).

const KEY := "W0_CONTRACT_TEST_GREETING"
const KEY_NAMED := "W0_CONTRACT_TEST_NAMED"

var _translation: Translation = null


func after_each() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null


# --- HudSpec --------------------------------------------------------------------------

func test_fluent_add() -> void:
	var card: Control = autofree(Control.new())
	var spec := HudSpec.new()
	var same := spec \
		.add(HudSpec.TIMELINE, HudSpec.TOP_LEFT) \
		.add(HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT) \
		.add(HudSpec.READOUT, HudSpec.TOP_RIGHT, {"source": "power_w"}) \
		.add_control(card, Rect2i(427, 24, 212, 80)) \
		.toasts_at(HudSpec.BOTTOM).banners_at(Rect2i(0, 0, 100, 20))
	assert_same(same, spec)
	assert_eq(spec.widgets.size(), 3)
	assert_eq(spec.widgets[0], {"widget": HudSpec.TIMELINE, "at": HudSpec.TOP_LEFT, "options": {}})
	assert_eq(spec.widgets[2]["options"], {"source": "power_w"})
	assert_eq(spec.controls.size(), 1)
	assert_same(spec.controls[0]["control"], card)
	assert_eq(spec.controls[0]["at"], Rect2i(427, 24, 212, 80))
	assert_eq(spec.toast_area, HudSpec.BOTTOM)
	assert_eq(spec.banner_area, Rect2i(0, 0, 100, 20))
	assert_true(spec.show_safety_banners)


func test_has_widget() -> void:
	var spec := HudSpec.new().add(HudSpec.WBAL, HudSpec.TOP).add(HudSpec.GEAR, HudSpec.BOTTOM)
	assert_true(spec.has_widget(HudSpec.WBAL))
	assert_true(spec.has_widget(HudSpec.GEAR))
	assert_false(spec.has_widget(HudSpec.CADENCE))


func test_defaults() -> void:
	var spec := HudSpec.new()
	assert_eq(spec.toast_area, HudSpec.TOP)
	assert_eq(spec.banner_area, HudSpec.TOP)
	assert_eq(spec.widgets.size(), 0)
	assert_eq(HudSpec.KIT_WIDGETS.size(), 7)
	assert_eq(HudSpec.ANCHORS.size(), 6)


func test_is_valid_position() -> void:
	for a in HudSpec.ANCHORS:
		assert_true(HudSpec.is_valid_position(a), a)
	assert_true(HudSpec.is_valid_position(&"top_left"), "StringName anchors")
	assert_true(HudSpec.is_valid_position(Rect2i(0, 0, 10, 10)))
	assert_false(HudSpec.is_valid_position("middle"))
	assert_false(HudSpec.is_valid_position("TOP"), "anchor names are lower case")
	assert_false(HudSpec.is_valid_position(Rect2(0, 0, 10, 10)), "art pixels are integers")
	assert_false(HudSpec.is_valid_position(3))
	assert_false(HudSpec.is_valid_position(null))
	assert_false(HudSpec.is_valid_position(Vector2i(1, 2)))


# --- GameStrings ----------------------------------------------------------------------

func _add_translation() -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	_translation.add_message(KEY, "Hello {0}, wave {1}")
	_translation.add_message(KEY_NAMED, "{name} caught a {fish}")
	TranslationServer.add_translation(_translation)


func test_missing_key_returns_the_key() -> void:
	var s := GameStrings.new()
	assert_eq(s.t("W0_CONTRACT_TEST_MISSING"), "W0_CONTRACT_TEST_MISSING")
	assert_false(s.has("W0_CONTRACT_TEST_MISSING"))


func test_t_with_args() -> void:
	_add_translation()
	var s := GameStrings.new()
	assert_true(s.has(KEY))
	assert_eq(s.t(KEY), "Hello {0}, wave {1}", "no args: the raw text")
	assert_eq(s.t(KEY, ["Ada", 3]), "Hello Ada, wave 3")
	assert_eq(s.t(KEY_NAMED, {"name": "Ada", "fish": "marlin"}), "Ada caught a marlin")
	assert_eq(s.t(KEY, []), "Hello {0}, wave {1}")
	assert_eq(s.t(KEY, {}), "Hello {0}, wave {1}")


# --- BleTransport UUIDs ---------------------------------------------------------------

func test_expand_uuid() -> void:
	var full := "00002ad2-0000-1000-8000-00805f9b34fb"
	assert_eq(BleTransport.expand_uuid("2AD2"), full)
	assert_eq(BleTransport.expand_uuid("2ad2"), full)
	assert_eq(BleTransport.expand_uuid("0x2ad2"), full)
	assert_eq(BleTransport.expand_uuid("0X2AD2"), full)
	assert_eq(BleTransport.expand_uuid(" 2AD2 "), full)
	assert_eq(BleTransport.expand_uuid("00002AD2-0000-1000-8000-00805F9B34FB"), full)
	assert_eq(BleTransport.expand_uuid("00001826"), "00001826-0000-1000-8000-00805f9b34fb", "32-bit form")


func test_same_uuid() -> void:
	assert_true(BleTransport.same_uuid("2AD2", "00002AD2-0000-1000-8000-00805F9B34FB"))
	assert_true(BleTransport.same_uuid("0x1826", "1826"))
	assert_false(BleTransport.same_uuid("2AD2", "2AD9"))
	assert_false(BleTransport.same_uuid("1826", "00001826-0000-1000-8000-00805f9b34fc"))
