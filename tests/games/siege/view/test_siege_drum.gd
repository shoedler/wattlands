extends GutTest
## The rolling-drum counter (brief 3 "Generator"): four digit drums showing the team's raw
## watts, clamped at 9999, rolling over 0.4 s.


func test_display_value_rounds_and_clamps() -> void:
	assert_eq(SiegeDrum.display_value(0.0), 0)
	assert_eq(SiegeDrum.display_value(6.6), 7)
	assert_eq(SiegeDrum.display_value(1249.6), 1250)
	assert_eq(SiegeDrum.display_value(12000.0), 9999)
	assert_eq(SiegeDrum.display_value(-30.0), 0)


func test_text_shows_0_7_1250_and_9999_for_12000() -> void:
	assert_eq(SiegeDrum.text_for(SiegeDrum.display_value(0.0)), "0")
	assert_eq(SiegeDrum.text_for(SiegeDrum.display_value(7.0)), "7")
	assert_eq(SiegeDrum.text_for(SiegeDrum.display_value(1250.0)), "1250")
	assert_eq(SiegeDrum.text_for(SiegeDrum.display_value(12000.0)), "9999")


func test_digits_leave_leading_drums_blank_but_never_the_ones() -> void:
	assert_eq(SiegeDrum.digits_for(0), [-1, -1, -1, 0] as Array[int])
	assert_eq(SiegeDrum.digits_for(7), [-1, -1, -1, 7] as Array[int])
	assert_eq(SiegeDrum.digits_for(1250), [1, 2, 5, 0] as Array[int])
	assert_eq(SiegeDrum.digits_for(9999), [9, 9, 9, 9] as Array[int])
	assert_eq(SiegeDrum.digits_for(40), [-1, -1, 4, 0] as Array[int])


func test_set_target_starts_a_roll_that_takes_0_4_s() -> void:
	var d := SiegeDrum.new()
	d.snap_to(0.0)
	d.set_target_w(1000.0)
	assert_true(d.rolling())
	d.step(0.2)
	assert_gt(d.shown, 0.0)
	assert_lt(d.shown, 1000.0)
	assert_almost_eq(d.shown, 500.0, 1.0, "a smoothstep is at half way at half time")
	d.step(0.2)
	assert_almost_eq(d.shown, 1000.0, 0.001)
	assert_false(d.rolling())


func test_a_new_target_mid_roll_starts_from_where_the_drums_are() -> void:
	var d := SiegeDrum.new()
	d.snap_to(0.0)
	d.set_target_w(1000.0)
	d.step(0.2)
	var mid := d.shown
	d.set_target_w(0.0)
	d.step(0.0)
	assert_almost_eq(d.shown, mid, 0.001)
	d.step(0.4)
	assert_almost_eq(d.shown, 0.0, 0.001)


func test_the_target_clamps_at_9999() -> void:
	var d := SiegeDrum.new()
	d.snap_to(0.0)
	d.set_target_w(12000.0)
	d.step(1.0)
	assert_eq(d.target, 9999)
	assert_almost_eq(d.shown, 9999.0, 0.001)
	assert_eq(int(d.drum_at(0)["digit"]), 9)
	assert_eq(float(d.drum_at(0)["roll"]), 0.0, "never rolls past 9999")


func test_the_ones_drum_rolls_and_higher_drums_carry_like_an_odometer() -> void:
	var d := SiegeDrum.new()
	d.shown = 1249.5
	var ones := d.drum_at(0)
	assert_eq(int(ones["digit"]), 9)
	assert_eq(int(ones["next"]), 0)
	assert_almost_eq(float(ones["roll"]), 0.5, 0.001)
	var tens := d.drum_at(1)
	assert_eq(int(tens["digit"]), 4)
	assert_eq(int(tens["next"]), 5)
	assert_almost_eq(float(tens["roll"]), 0.5, 0.001, "the tens carry while the ones wrap")
	var hundreds := d.drum_at(2)
	assert_eq(float(hundreds["roll"]), 0.0, "the hundreds wait for the tens to wrap")
	d.shown = 1240.0
	assert_eq(float(d.drum_at(1)["roll"]), 0.0)


func test_a_leading_drum_is_blank_until_the_value_reaches_it() -> void:
	var d := SiegeDrum.new()
	d.snap_to(7.0)
	assert_eq(int(d.drum_at(3)["digit"]), -1)
	assert_eq(int(d.drum_at(1)["digit"]), -1)
	assert_eq(int(d.drum_at(0)["digit"]), 7)
	d.snap_to(1250.0)
	assert_eq(int(d.drum_at(3)["digit"]), 1)
