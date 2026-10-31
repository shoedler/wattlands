extends GutTest
## PixelPainter.line_pixels: the Bresenham line HudHelp and Fishing's rig both draw.


func test_a_shallow_line_steps_on_the_grid_both_ends_included() -> void:
	assert_eq(
		PixelPainter.line_pixels(Vector2i(0, 0), Vector2i(3, 1)),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i]
	)


func test_a_line_upward_walks_back_along_the_axis() -> void:
	assert_eq(
		PixelPainter.line_pixels(Vector2i(2, 2), Vector2i(2, 0)),
		[Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)] as Array[Vector2i]
	)


func test_a_single_point_is_one_pixel() -> void:
	assert_eq(
		PixelPainter.line_pixels(Vector2i(5, 5), Vector2i(5, 5)),
		[Vector2i(5, 5)] as Array[Vector2i]
	)


func test_every_octant_stays_unbroken_and_lands_on_its_end() -> void:
	var a := Vector2i(10, 10)
	for b: Vector2i in [
		Vector2i(17, 13),
		Vector2i(13, 17),
		Vector2i(7, 17),
		Vector2i(3, 13),
		Vector2i(3, 7),
		Vector2i(7, 3),
		Vector2i(13, 3),
		Vector2i(17, 7),
	]:
		var line := PixelPainter.line_pixels(a, b)
		assert_eq(line[0], a, "starts at a, to %s" % b)
		assert_eq(line[-1], b, "ends at b, to %s" % b)
		assert_eq(line.size(), maxi(absi(b.x - a.x), absi(b.y - a.y)) + 1, "no gap, to %s" % b)
		for i in range(1, line.size()):
			var d := line[i] - line[i - 1]
			assert_true(absi(d.x) <= 1 and absi(d.y) <= 1, "one pixel at a time, to %s" % b)


func test_the_help_overlay_draws_the_same_line() -> void:
	var a := Vector2i(-4, 9)
	var b := Vector2i(21, -6)
	assert_eq(HudHelp.line_pixels(a, b), PixelPainter.line_pixels(a, b))
