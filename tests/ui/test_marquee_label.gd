extends GutTest
## WlMarqueeLabel: text that fits stays still; wider text rests at its start, scrolls to its
## end, rests and scrolls back, and never widens its container.

const DT := Wl.SIM_DT
## Each _run rounds to whole fixed steps (half a step off at most); five runs stay within three.
const TOLERANCE_PX := WlMarqueeLabel.SPEED_PX_S * DT * 3.0

var _m: WlMarqueeLabel = null


func before_each() -> void:
	_m = WlMarqueeLabel.new()
	_m.real_time = false
	_m.label.label_settings = WlTheme.label_settings(WlTheme.MENU_PX)
	add_child_autofree(_m)


func _run(seconds: float) -> void:
	for _i in roundi(seconds / DT):
		_m.step(DT)


func _set_width(px: float) -> void:
	_m.size = Vector2(px, _m.get_combined_minimum_size().y)


func test_text_that_fits_stays_still() -> void:
	_m.text = "Back"
	_set_width(2000.0)
	assert_eq(_m.overflow_px(), 0.0)
	_run(10.0)
	assert_eq(_m.offset_px(), 0.0)
	assert_eq(_m.label.position.x, 0.0)


func test_minimum_width_is_zero_so_long_text_never_widens_its_row() -> void:
	_m.text = "2026-10-23T20:04:28Z  fishing  20:08  Upload failed: Forbidden (403)"
	assert_eq(_m.get_combined_minimum_size().x, 0.0)
	assert_gt(_m.get_combined_minimum_size().y, 0.0, "one line tall")
	assert_true(_m.clip_contents)


func test_long_text_scrolls_to_its_end_and_back() -> void:
	_m.text = "2026-10-23T20:04:28Z  fishing  20:08  Upload failed: Forbidden (403)"
	_set_width(400.0)
	var over := _m.overflow_px()
	assert_gt(over, 0.0)
	var travel := over / WlMarqueeLabel.SPEED_PX_S
	_run(WlMarqueeLabel.REST_S * 0.5)
	assert_eq(_m.offset_px(), 0.0, "rests at its start first")
	_run(WlMarqueeLabel.REST_S * 0.5 + travel * 0.5)
	assert_almost_eq(_m.offset_px(), over * 0.5, TOLERANCE_PX, "half way to the end")
	assert_almost_eq(_m.label.position.x, -_m.offset_px(), 0.01, "the label moves left")
	_run(travel * 0.5 + WlMarqueeLabel.REST_S * 0.5)
	assert_almost_eq(_m.offset_px(), over, TOLERANCE_PX, "rests at its end")
	_run(WlMarqueeLabel.REST_S * 0.5 + travel * 0.5)
	assert_almost_eq(_m.offset_px(), over * 0.5, TOLERANCE_PX, "on its way back")
	_run(travel * 0.5 + WlMarqueeLabel.REST_S * 0.5)
	assert_almost_eq(_m.offset_px(), 0.0, TOLERANCE_PX, "back at its start")


func test_new_text_starts_again_at_its_start() -> void:
	_m.text = "A long line of text that cannot fit in a narrow row at all"
	_set_width(200.0)
	_run(WlMarqueeLabel.REST_S + 1.0)
	assert_gt(_m.offset_px(), 0.0)
	_m.text = "Another long line of text that cannot fit in a narrow row either"
	assert_eq(_m.offset_px(), 0.0)
