extends GutTest
## TankMech (docs/games/tank.md 3.4): the station machines paint at every phase and power
## without error, their picture moves with the phase (the crank) and changes with the power (heat,
## light, needles), and the coupling constants hold (integer ratios, the in-band window).

const KINDS: Array[String] = ["diesel", "dynamo", "steam", "arc", "feed", "repair"]


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


# --- Repairs (SPEC_TANK 5.3) --------------------------------------------------------------------------------


func test_the_repair_machine_has_its_own_slight_colour() -> void:
	assert_eq(TankMech.KEYS["repair"], Color(1.0, 0.74, 0.5))
	assert_eq(TankMech.AMBS["repair"], Color(0.17, 0.13, 0.13))
	for k: String in TankMech.KEYS:
		if k != "repair":
			assert_ne(TankMech.KEYS[k], TankMech.KEYS["repair"], "no other seat's lamp: %s" % k)
	assert_true(TankMech.RATIO.has("repair"), "a machine of its own, not the diesel's fallback")
	var repair := _paint("repair", 0.5, 1.0)
	var diesel := _paint("diesel", 0.5, 1.0)
	assert_gt(_diff(repair, diesel), 2000, "its own picture")


func test_the_hammer_is_a_pure_function_of_the_crank() -> void:
	for revs: float in [0.0, 0.2, 0.5, 0.87, 0.99, 3.4, 117.72]:
		assert_eq(TankMech.hammer_lift(revs), TankMech.hammer_lift(revs), "pure")
		assert_almost_eq(
			TankMech.hammer_lift(revs), TankMech.hammer_lift(revs + 5.0), 0.0001, "periodic"
		)
		assert_between(TankMech.hammer_lift(revs), 0.0, 1.0)
	assert_eq(TankMech.hammer_lift(4.0), 0.0, "down on the plate at the whole revolution")
	assert_gt(TankMech.hammer_lift(4.85), 0.9, "at the top before the fall")


## One stroke per crank revolution, at every cadence: a strike is the head passing from high to low.
func test_one_stroke_per_revolution_across_the_cadences() -> void:
	for rpm: float in [30.0, 60.0, 90.0, 110.0, 140.0]:
		var revs := 0.0
		var dt := 1.0 / 240.0
		var strokes := 0
		var was := TankMech.hammer_lift(revs)
		var going_down := false
		for _i in int(20.0 / dt):
			revs += rpm / 60.0 * dt
			var now := TankMech.hammer_lift(revs)
			if now < was - 0.0001:
				going_down = true
			elif going_down and now > was:
				strokes += 1
				going_down = false
			was = now
		assert_almost_eq(
			float(strokes), floorf(revs), 1.0, "%.0f rpm: one stroke a revolution" % rpm
		)


func test_the_repair_card_strikes_with_sparks_and_rests_without() -> void:
	var strike := _paint("repair", 3.02, 1.0)
	var top := _paint("repair", 3.85, 1.0)
	assert_gt(_diff(strike, top), 100, "the head and the helve move")
	var same_a := _paint("repair", 3.6, 1.0)
	var same_b := _paint("repair", 4.6, 1.0)
	assert_eq(_diff(same_a, same_b), 0, "away from the sparks a revolution is a seamless loop")


## The card can be 64 px wide at 852: the middle 60 px of 112 must carry the action.
func test_the_action_is_in_the_cards_middle() -> void:
	var a := _paint("repair", 3.02, 1.0)
	var b := _paint("repair", 3.85, 1.0)
	var mid := 0
	for y in a.get_height():
		for x in range(26, 86):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				mid += 1
	assert_gt(float(mid) / float(_diff(a, b)), 0.6, "most of what moves is in the middle 60 px")


# --- The Repairs room (TankInterior.repair_bay) ---------------------------------------------------------------


func _room(revs: float, slot: int, on: bool, press_t: float = 0.3, patches: int = 2) -> Image:
	var it := TankInterior.new(TankRig.shared())
	var rp := {"slot": slot, "revs": revs, "on": on, "press_t": press_t, "patches": patches}
	it.paint_all({"t": 0.0, "repair": rp})
	return it.img.get_region(Rect2i(TankRig.shared().rooms["turret_drive"]))


func test_the_room_follows_the_crank_one_stroke_per_revolution() -> void:
	assert_gt(_diff(_room(5.02, 1, true), _room(5.85, 1, true)), 30, "the hammer moves")
	assert_eq(_diff(_room(5.6, 1, true), _room(6.6, 1, true)), 0, "a revolution loops")
	assert_eq(_diff(_room(5.3, 1, false), _room(9.8, 1, false)), 0, "stopped when the rider stops")


func test_the_room_shows_the_rider_the_press_and_the_plates() -> void:
	assert_gt(_diff(_room(5.6, 1, true), _room(5.6, -1, true)), 10, "a rider on the saddle")
	assert_gt(
		_diff(_room(5.6, 1, true, 0.1), _room(5.6, 1, true, 0.9)), 5, "the press closes at press_t"
	)
	assert_gt(
		_diff(_room(5.6, 1, true, 0.3, 1), _room(5.6, 1, true, 0.3, 4)),
		3,
		"plates stack by patches"
	)
	assert_eq(_diff(_room(5.6, 1, true, 0.3, 1), _room(5.6, 1, true, 0.3, 6)), 0, "patches mod 5")


func test_the_room_key_repaints_on_press_and_patches() -> void:
	var it := TankInterior.new(TankRig.shared())
	var rp := {"slot": 1, "revs": 2.0, "on": true, "press_t": 0.1, "patches": 0}
	var inp := {"t": 0.0, "repair": rp}
	it.paint_all(inp)
	assert_false(it.paint(inp, 10.0, 7), "nothing changed")
	rp["press_t"] = 0.5
	assert_true(it.paint(inp, 20.0, 7), "the press moved")
	rp["patches"] = 1
	assert_true(it.paint(inp, 30.0, 7), "a plate landed")
