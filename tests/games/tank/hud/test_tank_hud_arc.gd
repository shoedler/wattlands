extends GutTest
## The gun's elevation arc (brief 3.6) against the tank as the view draws it: for every variant
## (crews 1-4), every facing (forward and traversed to the rear), the mission frame and free roam in
## both travel directions (driving west the world is mirrored) and every elevation, the arc is
## centred on the barrel's live pivot on the side the barrel points, beyond the muzzle, and none of
## its pixels or its label lie on the turret or the hull. Mid-traverse there is no arc.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const LABEL := Vector2(30, 9)


func _view(s: TankState) -> TankView:
	var g: TankGame = autofree(U.roam_game(s) if s.roam.active else U.make_game(s))
	return U.make_view(self, g)


## Every pixel the arc paints (arc_reach filtered as the painter filters it) and its label rect.
func _drawn(b: Dictionary, lay: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in TankHudGeom.arc_reach(b["pivot"], float(lay["radius"]), bool(b["left"])):
		if TankHudGeom.arc_px_ok(p, lay["keep_out"]):
			out.append(p)
	var lr: Rect2 = lay["label"]
	for y in range(int(lr.position.y), int(lr.end.y)):
		for x in range(int(lr.position.x), int(lr.end.x)):
			out.append(Vector2i(x, y))
	return out


func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crew in [1, 2, 3, 4]:
		out.append({"crew": crew, "mode": "mission", "s": U.fixture("state", crew)})
		for dir in [TankIds.DIR_RIGHT, TankIds.DIR_LEFT]:
			out.append({"crew": crew, "mode": "roam %d" % dir, "s": U.roam_state(crew, dir)})
	return out


func test_the_arc_never_lies_on_the_tank_for_any_variant_facing_or_elevation() -> void:
	for c: Dictionary in _cases():
		var s: TankState = c["s"]
		var v := _view(s)
		for facing in [TankIds.FACE_RIGHT, TankIds.FACE_LEFT]:
			s.hull.facing = facing
			s.hull.traverse_s = 0.0
			v.advance(1.0 / 60.0)
			var deg := TankHudGeom.ELEV_MIN
			while deg <= TankHudGeom.ELEV_MAX:
				s.hull.elev_deg = deg
				var what := "crew %d %s facing %d at %.0f deg" % [c["crew"], c["mode"], facing, deg]
				var g := TankHudGeom.make(s, v)
				var b := g.barrel()
				assert_false(bool(b["turning"]), what)
				var body := g.tank_rects()
				assert_eq(body.size(), 2, "turret and hull")
				var lay := TankHudGeom.arc_layout(b, LABEL, body)
				var drawn := _drawn(b, lay)
				var on_tank := 0
				for p in drawn:
					for r in body:
						if r.has_point(Vector2(p) + Vector2(0.5, 0.5)):
							on_tank += 1
				assert_eq(on_tank, 0, what)
				var arc := TankHudGeom.arc_pixels(b["pivot"], float(lay["radius"]), bool(b["left"]))
				assert_gt(drawn.size(), arc.size(), "%s: the arc is drawn" % what)
				# Anchored on the live barrel: its pivot, its side, past its muzzle.
				var piv: Vector2 = b["pivot"]
				var muz := v.hud_tank_point("muzzle")
				assert_eq(piv, v.hud_tank_point("barrel_pivot"), what)
				assert_eq(bool(b["left"]), muz.x < piv.x, "%s: the side the barrel points" % what)
				assert_lt(piv.distance_to(muz), float(lay["radius"]) - 2.0, what)
				deg += 3.0


func test_the_turret_mirrors_with_a_rear_facing_gun() -> void:
	for crew in [1, 2, 3, 4]:
		var s := U.fixture("state", crew)
		var v := _view(s)
		s.hull.facing = TankIds.FACE_RIGHT
		v.advance(1.0 / 60.0)
		assert_eq(v.turret_sx(), 1.0)
		var front := v.hud_tank_rects()[0]
		var tp := v.hud_tank_point("turret_pivot").x
		s.hull.facing = TankIds.FACE_LEFT
		v.advance(1.0 / 60.0)
		assert_eq(v.turret_sx(), -1.0, "crew %d: the whole turret mirrored" % crew)
		var back := v.hud_tank_rects()[0]
		assert_almost_eq(back.position.x, 2.0 * tp - front.end.x, 1.0, "mirrored about its pivot")
		var piv := v.hud_tank_point("barrel_pivot")
		var muz := v.hud_tank_point("muzzle")
		assert_lt(muz.x, piv.x, "crew %d: the barrel points back" % crew)
		assert_almost_eq(piv.x, back.position.x + 3.0, 1.5, "crew %d: from the mantlet" % crew)
		var tv := v.kit.variant(v.variant)
		assert_true(tv.has("turret") and tv.has("hull_open"), "the turret block is cut out")


func test_a_traverse_squeezes_the_turret_and_hides_the_arc_until_it_is_round() -> void:
	var s := U.fixture("state", 3)
	var v := _view(s)
	s.hull.facing = TankIds.FACE_RIGHT
	s.hull.elev_deg = 8.0
	s.hull.traverse_s = 2.0
	v.advance(1.0 / 60.0)
	assert_almost_eq(v.turret_sx(), 1.0, 0.01, "the traverse starts facing forward")
	s.hull.traverse_s = 1.0
	v.advance(1.0 / 60.0)
	assert_almost_eq(absf(v.turret_sx()), TankView.TURRET_MIN_W, 0.01, "end on half way round")
	var g := TankHudGeom.make(s, v)
	assert_true(bool(g.barrel()["turning"]), "no arc mid-traverse")
	s.hull.traverse_s = 0.0
	s.hull.facing = TankIds.FACE_LEFT
	v.advance(1.0 / 60.0)
	var b := TankHudGeom.make(s, v).barrel()
	assert_false(bool(b["turning"]))
	assert_true(bool(b["left"]), "the arc follows the barrel round")
