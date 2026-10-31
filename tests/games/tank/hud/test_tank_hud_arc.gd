extends GutTest
## The gun's elevation arc (brief 3.6) against the tank as the view draws it: for every variant
## (crews 1-4), the mission frame and free roam in both travel directions (driving west the world is
## mirrored) and every elevation, the arc is centred on the barrel's live pivot on the side the barrel
## points, beyond the muzzle, and none of its pixels or its label lie on the turret or the hull.

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


func test_the_arc_never_lies_on_the_tank_for_any_variant_or_elevation() -> void:
	for c: Dictionary in _cases():
		var s: TankState = c["s"]
		var v := _view(s)
		s.hull.facing = TankIds.FACE_RIGHT
		s.hull.traverse_s = 0.0
		v.advance(1.0 / 60.0)
		var deg := TankHudGeom.ELEV_MIN
		while deg <= TankHudGeom.ELEV_MAX:
			s.hull.elev_deg = deg
			var what := "crew %d %s at %.0f deg" % [c["crew"], c["mode"], deg]
			var g := TankHudGeom.make(s, v)
			var b := g.barrel()
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


func test_the_arc_stands_ahead_of_the_gun_wherever_the_order_says_it_faces() -> void:
	for crew in [1, 2, 3, 4]:
		var s := U.fixture("state", crew)
		s.hull.facing = TankIds.FACE_LEFT
		var b := TankHudGeom.make(s, null).barrel()
		assert_false(bool(b["left"]), "crew %d: v4 has no rear traverse" % crew)
		assert_false(b.has("turning"), "and no arc to hide mid-traverse")


func test_driving_west_mirrors_the_arc_with_the_world() -> void:
	var s := U.roam_state(3, TankIds.DIR_LEFT)
	assert_true(bool(TankHudGeom.make(s, null).barrel()["left"]), "the world is drawn mirrored")
	var e := U.roam_state(3, TankIds.DIR_RIGHT)
	assert_false(bool(TankHudGeom.make(e, null).barrel()["left"]))
