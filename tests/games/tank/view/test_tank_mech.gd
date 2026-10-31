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
		assert_eq(TankMechRepair.hammer_lift(revs), TankMechRepair.hammer_lift(revs), "pure")
		assert_almost_eq(
			TankMechRepair.hammer_lift(revs),
			TankMechRepair.hammer_lift(revs + 5.0),
			0.0001,
			"periodic"
		)
		assert_between(TankMechRepair.hammer_lift(revs), 0.0, 1.0)
	assert_eq(TankMechRepair.hammer_lift(4.0), 0.0, "down on the plate at the whole revolution")
	assert_gt(TankMechRepair.hammer_lift(4.85), 0.9, "at the top before the fall")


## One stroke per crank revolution, at every cadence: a strike is the head passing from high to low.
func test_one_stroke_per_revolution_across_the_cadences() -> void:
	for rpm: float in [30.0, 60.0, 90.0, 110.0, 140.0]:
		var revs := 0.0
		var dt := 1.0 / 240.0
		var strokes := 0
		var was := TankMechRepair.hammer_lift(revs)
		var going_down := false
		for _i in int(20.0 / dt):
			revs += rpm / 60.0 * dt
			var now := TankMechRepair.hammer_lift(revs)
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


## The hammer is the hero: the head is the card's lit mass and the cam stays small beside it (the critic's
## "boulder" was a cam of 13 px radius).
func test_the_hammer_is_the_cards_hero_and_the_cam_stays_small() -> void:
	assert_lte(
		TankMechRepair.R_CAM_R + TankMechRepair.R_LIFT, 9.0, "a small drawn cam on its shaft"
	)
	assert_gte(TankMechRepair.R_HEAD_LIFT, 12.0, "a stroke you can see at 72 x 41")
	var top := _paint("repair", 3.85, 1.0)
	var low := _paint("repair", 3.3, 1.0)
	var head := Rect2i(
		int(TankMechRepair.R_HEAD_X) - 8,
		roundi(TankMechRepair.R_REST_Y - TankMechRepair.R_HEAD_LIFT),
		17,
		8
	)
	var cam := Rect2i(int(TankMechRepair.R_CAM.x) - 6, int(TankMechRepair.R_CAM.y) - 6, 12, 12)
	assert_gt(_mean_v(top, head), _mean_v(top, cam) + 0.1, "the head outshines the cam")
	assert_ne(_mean_v(top, head), _mean_v(low, head), "and it moves")


func _mean_v(img: Image, r: Rect2i) -> float:
	var total := 0.0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			total += img.get_pixel(x, y).v
	return total / float(r.size.x * r.size.y)


## The card's colour: its own, a pinker copper, not hotter than its neighbours.
func test_the_repair_card_is_a_pinker_copper_than_drive() -> void:
	var rep := _mean_colour(_paint("repair", 3.5, 1.0))
	var die := _mean_colour(_paint("diesel", 3.5, 1.0))
	assert_lt(rep.h, die.h, "hue %.3f is pinker than Drive's %.3f" % [rep.h, die.h])
	assert_lte(rep.s, 0.62, "sat %.2f: copper, not orange" % rep.s)


func _mean_colour(img: Image) -> Color:
	var c := Color(0, 0, 0)
	for y in img.get_height():
		for x in img.get_width():
			var q := img.get_pixel(x, y)
			c.r += q.r
			c.g += q.g
			c.b += q.b
	var n := float(img.get_width() * img.get_height())
	return Color(c.r / n, c.g / n, c.b / n)


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


## The room's edge is not a TV screen: its border rows keep the hull's art round it; the middle is the room's.
func test_the_room_dissolves_into_the_hull_at_its_edge() -> void:
	var rig := TankRig.shared()
	if rig.base_img == null:
		pass_test("no base picture headless")
		return
	var room := _room(5.6, 1, true)
	var r := Rect2i(rig.rooms["turret_drive"])
	var edge := 0.0
	var inner := 0.0
	for x in r.size.x:
		edge += _px_diff(
			room.get_pixel(x, 0), rig.base_img.get_pixel(r.position.x + x, r.position.y)
		)
		inner += _px_diff(
			room.get_pixel(x, 6), rig.base_img.get_pixel(r.position.x + x, r.position.y + 6)
		)
	assert_lt(edge, inner, "the top row stays nearer the base than a row inside")


static func _px_diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## The machine takes the lamp: no neutral grey line of a diagram on it.
func test_the_rooms_machine_takes_the_lamp() -> void:
	for ramp: Array[Color] in [TankInterior.RP_IRON, TankInterior.RP_HEAD]:
		for c in ramp:
			assert_gt(c.r, c.b, "%s leans to the lamp" % c.to_html(false))


## Form by the lamp's falloff, as the rooms round it: no black outline on the machine.
func test_the_room_has_no_black_outline() -> void:
	var room := _room(5.6, 1, true)
	var out := 0
	for y in room.get_height():
		for x in room.get_width():
			out += int(room.get_pixel(x, y).is_equal_approx(TankInterior.OUT))
	var share := float(out) / float(room.get_width() * room.get_height())
	assert_lt(share, 0.01, "outline colour on %.1f %% of the room" % (share * 100.0))


## The flywheel is open: round its web the spokes and the wall alternate, and a spoke moves with the crank.
func test_the_flywheel_has_open_spokes() -> void:
	var r := Rect2i(TankRig.shared().rooms["turret_drive"])
	var c := Vector2(0.0, float(r.size.y - 2)) + TankInterior.RP_FLYWHEEL
	var room := _room(5.6, 1, true)
	var cols: Array[Color] = []
	for k in 48:
		var q := c + Vector2.from_angle(TAU * k / 48.0) * (TankInterior.RP_FLY_R - 3.0)
		cols.append(room.get_pixelv(Vector2i(q)))
	var iron := 0
	for col in cols:
		for ramp: Color in TankInterior.RP_IRON:
			if col.is_equal_approx(ramp):
				iron += 1
				break
	assert_between(iron, 4, 34, "%d of 48 samples on a spoke: neither a disc nor nothing" % iron)


## The chain reads against the wall, and the helve has a lit top over a dark underside.
func test_the_chain_and_the_helve_stand_off_the_wall() -> void:
	var wall := TankInterior.REPAIR_WALL
	assert_gt(TankInterior.RP_CHAIN[0].get_luminance(), wall.get_luminance())
	assert_gt(TankInterior.RP_CHAIN[1].get_luminance(), wall.get_luminance() * 2.0)
	assert_gt(
		TankInterior.RP_HAFT[3].get_luminance(), TankInterior.RP_HAFT[0].get_luminance() * 3.0
	)


static func _luma(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0


## The room is a dark room with a lamp pool, as its neighbours on the deck (median L 27-38, p95 3.4-4.2 times that):
## no bright flat panel, its corners near their median.
func test_the_room_is_a_lamp_pool_not_a_panel() -> void:
	var room := _room(5.6, 1, true)
	var ls: Array[float] = []
	for y in room.get_height():
		for x in room.get_width():
			ls.append(_luma(room.get_pixel(x, y)))
	ls.sort()
	var med: float = ls[ls.size() / 2]
	var p95: float = ls[ls.size() * 95 / 100]
	assert_lte(med, 44.0, "median L")
	assert_gte(p95 / med, 3.2, "the pool stands out of the wall")
	var w := room.get_width()
	var corner := 0.0
	for q: Vector2i in [Vector2i(3, 4), Vector2i(w - 4, 4), Vector2i(w - 4, 20)]:
		for y2 in 3:
			for x2 in 3:
				corner += _luma(room.get_pixel(q.x + x2 - 1, q.y + y2 - 1))
	corner /= 27.0
	assert_lte(corner, 40.0, "the corners fall to the neighbours' median")


## No pale frame: no full-width pipe or post stands lit round the room. No column and no row of the wall holds a long
## straight run of bright iron.
func test_no_pale_frame_round_the_machine() -> void:
	var room := _room(5.6, 1, true)
	var w := room.get_width()
	var h := room.get_height()
	for y in 4:
		var bright := 0
		for x in w:
			bright += int(_luma(room.get_pixel(x, y)) > 70.0)
		assert_lt(bright, w / 3, "row %d of the ceiling: %d px bright" % [y, bright])
	for x2 in range(w - 10, w):
		var run := 0
		var best := 0
		for y2 in h:
			run = run + 1 if _luma(room.get_pixel(x2, y2)) > 60.0 else 0
			best = maxi(best, run)
		assert_lt(best, 10, "column %d: a straight lit run of %d" % [x2, best])


## What stands under the lamp is not the loudest shape after the hammer: no flat saturated square over the head.
func test_nothing_flat_and_loud_under_the_lamp() -> void:
	var it := TankInterior.new(TankRig.shared())
	var wall := it._repair_wall(Rect2i(TankRig.shared().rooms["turret_drive"]), true)
	var loud := 0
	for y in range(3, 14):
		for x in range(28, 52):
			var c := wall.get_pixel(x, y)
			loud += int(c.s > 0.45 and _luma(c) > 110.0)
	assert_lte(loud, 3, "%d px of loud colour on the wall under the lamp" % loud)


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
