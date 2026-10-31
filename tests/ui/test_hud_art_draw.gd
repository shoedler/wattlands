extends GutTest
## HudArtDraw: the frame's geometry from frame_rects, and both helpers running inside a real _draw
## (a draw outside one is an engine error, and headless rendering has no pixels to read back).


class Painter:
	extends Control
	var drawn: int = 0

	func _draw() -> void:
		HudArtDraw.frame(self, Rect2(0, 0, 8, 8), Color.RED)
		HudArtDraw.frame(self, Rect2(0, 0, 8, 8), Color.RED, 3.0)
		HudArtDraw.pixels(self, [".#.", "###"], Vector2(1, 1), Color.BLUE)
		HudArtDraw.pixels(self, ["#"], Vector2(1, 1), Color.BLUE, 3.0)
		HudArtDraw.pixels(self, [], Vector2.ZERO, Color.BLUE)
		drawn += 1


func _area(rects: Array[Rect2]) -> float:
	var total := 0.0
	for r in rects:
		total += r.get_area()
	return total


func test_a_one_pixel_frame_has_the_sides_between_top_and_bottom() -> void:
	assert_eq(
		HudArtDraw.frame_rects(Rect2(10, 20, 30, 40)),
		(
			[
				Rect2(10, 20, 30, 1),
				Rect2(10, 59, 30, 1),
				Rect2(10, 21, 1, 38),
				Rect2(39, 21, 1, 38),
			]
			as Array[Rect2]
		)
	)


func test_a_thick_frame_scales_every_side() -> void:
	assert_eq(
		HudArtDraw.frame_rects(Rect2(0, 0, 30, 24), 3.0),
		(
			[
				Rect2(0, 0, 30, 3),
				Rect2(0, 21, 30, 3),
				Rect2(0, 3, 3, 18),
				Rect2(27, 3, 3, 18),
			]
			as Array[Rect2]
		)
	)


func test_no_two_sides_overlap_so_alpha_never_doubles_in_a_corner() -> void:
	for m: float in [1.0, 2.0, 3.0]:
		var r := Rect2(5, 7, 41, 23)
		var sides := HudArtDraw.frame_rects(r, m)
		var hole := r.grow(-m)
		assert_eq(_area(sides), r.get_area() - hole.get_area(), "the ring exactly, m %s" % m)
		for i in sides.size():
			assert_false(sides[i].intersects(hole), "side %d stays out of the hole" % i)
			for j in range(i + 1, sides.size()):
				assert_false(sides[i].intersects(sides[j]), "sides %d and %d" % [i, j])


func test_frame_and_pixels_draw_inside_a_draw() -> void:
	var p: Painter = add_child_autofree(Painter.new())
	p.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(p.drawn, 0)
