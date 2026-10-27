extends GutTest
## TankMech (docs/games/tank.md 3.4): the four station machines paint at every phase and power
## without error, their picture moves with the phase (the crank) and changes with the power (heat,
## light, needles), and the coupling constants hold (integer ratios, the in-band window).

const KINDS: Array[String] = ["diesel", "dynamo", "steam", "arc"]


func _paint(kind: String, phase: float, power: float, t: float = 1.0) -> Image:
	var img := Image.create(TankMech.W, TankMech.H, false, Image.FORMAT_RGBA8)
	TankMech.paint_ex(img, kind, phase, power, t, Color(0.9, 0.6, 0.2), 90.0)
	return img


static func _diff(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				n += 1
	return n


func test_every_kind_paints_at_several_phases_and_powers() -> void:
	for kind in KINDS:
		for phase: float in [0.0, 0.13, 0.5, 1.7, 12.25]:
			for power: float in [0.0, 0.5, 1.0, 1.3, 1.6]:
				var img := _paint(kind, phase, power)
				assert_eq(img.get_size(), Vector2i(TankMech.W, TankMech.H))
				assert_false(img.is_invisible(), "%s %.2f %.1f" % [kind, phase, power])
		# Other sizes get the picture scaled.
		var small := Image.create(56, 32, false, Image.FORMAT_RGBA8)
		TankMech.paint(small, kind, 0.3, 1.0, 1.0, Color.WHITE)
		assert_eq(small.get_size(), Vector2i(56, 32), kind)


func test_the_picture_moves_with_the_phase() -> void:
	for kind in KINDS:
		var a := _paint(kind, 0.0, 1.0)
		var b := _paint(kind, 0.23, 1.0)
		assert_gt(_diff(a, b), 20, "%s moves with the crank" % kind)


func test_the_picture_changes_with_the_power() -> void:
	for kind in KINDS:
		var low := _paint(kind, 0.4, 0.3)
		var band := _paint(kind, 0.4, 1.0)
		var over := _paint(kind, 0.4, 1.45)
		assert_gt(_diff(low, band), 20, "%s under vs in band" % kind)
		assert_gt(_diff(band, over), 20, "%s in band vs over" % kind)


func test_one_crank_revolution_is_one_seamless_loop() -> void:
	for kind: String in TankMech.PARTS:
		for part: String in TankMech.PARTS[kind]:
			var n: Variant = TankMech.PARTS[kind][part]
			assert_eq(typeof(n), TYPE_INT, "%s %s turns an integer number of times" % [kind, part])
	assert_eq(TankMech.RATIO["diesel"], 2.0, "brief 3.4: diesel x2")
	assert_eq(TankMech.RATIO["dynamo"], 3.0, "dynamo armature x3")
	assert_eq(TankMech.PARTS["arc"]["ladder_arc_climbs"], 2, "two ladder climbs a revolution")
	assert_eq(TankMech.PARTS["steam"]["hoist_shells_raised"], 1, "one shell a revolution")


func test_the_in_band_window_and_the_rider_power() -> void:
	assert_true(TankMech.in_band(1.0))
	assert_true(TankMech.in_band(0.84))
	assert_true(TankMech.in_band(1.17))
	assert_false(TankMech.in_band(0.8))
	assert_false(TankMech.in_band(1.2))
	assert_almost_eq(TankMech.rider_power(90.5), 1.0, 0.001)
	assert_true(TankMech.in_band(TankMech.rider_power(77.0)), "77 % FTP is in the SIM band")
	assert_true(TankMech.in_band(TankMech.rider_power(105.0)), "105 % FTP is in the SIM band")


func test_the_room_machines_draw_their_parts_by_phase() -> void:
	# The in-world overlays share the coupling: the dynamo's jars charge once a revolution, the arc
	# climbs twice a revolution and dies under band.
	assert_almost_eq(TankRoomMachines.jar_fill(1.0, 0.0), 0.0, 0.001)
	assert_gt(TankRoomMachines.jar_fill(1.0, 0.7), 0.5)
	assert_almost_eq(TankRoomMachines.jar_fill(0.0, 0.7), 0.0, 0.001, "no power, no charge")
	var ra := Rect2(0, 0, 47, 33)
	var low := TankRoomMachines.arc_at(ra, 0.05, 1.0)
	var high := TankRoomMachines.arc_at(ra, 0.2, 1.0)
	assert_true(low.y > high.y, "the arc climbs with the phase")
	assert_eq(TankRoomMachines.arc_at(ra, 0.05, 0.0), Vector2(-1, -1), "no arc without power")
	assert_eq(TankRoomMachines.shake(1.0, 3.0, 1.0), Vector2.ZERO, "in band stands steady")
