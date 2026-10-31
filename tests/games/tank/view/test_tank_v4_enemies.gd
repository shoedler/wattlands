extends GutTest
## TankEnemyDraw (SPEC_TANK 5.4): the live parts follow the tank's pure functions (TankSuspension, the belt,
## the turret's squeeze), the gun aims, recoils and mirrors, the casemate gun stops at its mount, and every
## kind draws in every pose without error.

const FOOT := Vector2(300, 400)


## A canvas that draws what it was asked to.
class Sketch:
	extends Node2D
	var kit := TankEnemyKit.shared()
	var calls: Array = []

	func _draw() -> void:
		for c: Array in calls:
			TankEnemyDraw.draw(self, kit, str(c[0]), c[1], c[2])
			TankEnemyDraw.draw_light(self, kit, str(c[0]), c[1], c[2])


func _kit() -> TankEnemyKit:
	return TankEnemyKit.shared()


func test_every_kind_draws_in_every_pose() -> void:
	var sk: Sketch = add_child_autofree(Sketch.new())
	var bump := func(x: float) -> float: return 400.0 + 4.0 * sin(x * 0.11)
	for k: String in TankEnemyKit.SIZES:
		sk.calls.append([k, FOOT, {}])
		sk.calls.append(
			[k, FOOT, {"travel": 7.3, "elev_deg": 9.0, "recoil": 3.0, "turret_sx": 0.3}]
		)
		sk.calls.append(
			[k, FOOT, {"haze": 0.4, "dim": 0.2, "flash": 0.5, "flip": true, "time": 2.0}]
		)
		sk.calls.append([k, FOOT, {"ground": bump, "travel": 12.0, "turret_sx": -1.0}])
		sk.calls.append([k, FOOT, {"ground": bump, "flip": true}])
		sk.calls.append([k, FOOT, {"wrecked": true, "time": 1.0}])
		sk.calls.append([k, FOOT, {"wrecked": true, "flip": true}])
	sk.calls.append(["behemoth", FOOT, {"bogies_wrecked": [true, false, true]}])
	sk.queue_redraw()
	await wait_physics_frames(2)
	assert_true(true, "drew without error")


func test_the_foot_is_the_ground_centre_of_the_sprite() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit().kind(k)
		var xf: Transform2D = TankEnemyDraw.hull_pose(row, FOOT, {})["stage"]
		var size: Vector2 = row["size"]
		var p: Vector2 = xf * Vector2(floorf(size.x * 0.5), float(row["ground"]))
		assert_almost_eq(p.distance_to(FOOT), 0.0, 1.0, k)


func test_the_gun_faces_the_kinds_front_and_traverses_back() -> void:
	var kit := _kit()
	for k: String in TankEnemyKit.SIZES:
		var f := float(kit.kind(k)["faces"])
		var m := TankEnemyDraw.muzzle(kit, k, FOOT, {"turret_sx": 1.0})
		var gun: Dictionary = kit.kind(k)["gun"]
		var tr: Vector2 = (
			(TankEnemyDraw.hull_pose(kit.kind(k), FOOT, {})["stage"] as Transform2D)
			* (gun["trunnion"] as Vector2)
		)
		assert_almost_eq((m.x - tr.x) * f, float(gun["len"]), 0.01, "%s: along its front" % k)
	var near_back := TankEnemyDraw.muzzle(kit, "recon", FOOT, {"turret_sx": -1.0})
	var pivot := float((kit.kind("recon")["turret"]["pivot"] as Vector2).x)
	assert_lt(near_back.x, FOOT.x, "the recon's turret traversed back at us")
	assert_gt(pivot, 0.0)


func test_a_flip_mirrors_about_the_foot() -> void:
	var kit := _kit()
	var a := TankEnemyDraw.muzzle(kit, "medium", FOOT, {})
	var b := TankEnemyDraw.muzzle(kit, "medium", FOOT, {"flip": true})
	assert_almost_eq(a.x + b.x, FOOT.x * 2.0, 0.01)
	assert_almost_eq(a.y, b.y, 0.01)


func test_recoil_runs_back_along_the_bore() -> void:
	var kit := _kit()
	var a := TankEnemyDraw.muzzle(kit, "heavy", FOOT, {"elev_deg": 8.0})
	var b := TankEnemyDraw.muzzle(kit, "heavy", FOOT, {"elev_deg": 8.0, "recoil": 5.0})
	assert_almost_eq(a.distance_to(b), 5.0, 0.01)
	assert_gt(b.x, a.x, "towards the left-facing heavy's rear")
	assert_gt(b.y, a.y, "down the elevated bore")


func test_elevation_lifts_the_muzzle_and_the_casemate_stops_at_its_mount() -> void:
	var kit := _kit()
	var flat := TankEnemyDraw.muzzle(kit, "medium", FOOT, {})
	assert_lt(TankEnemyDraw.muzzle(kit, "medium", FOOT, {"elev_deg": 12.0}).y, flat.y)
	var row := kit.kind("destroyer")
	assert_eq(
		TankEnemyDraw.clamp_elev(row, 30.0),
		16.0,
		"its top stop still reaches 2200 m's 14.7 degrees"
	)
	assert_eq(TankEnemyDraw.clamp_elev(row, -9.0), -2.0)
	assert_eq(TankEnemyDraw.clamp_elev(kit.kind("medium"), 30.0), 30.0, "a turret has no such stop")


func test_turret_squeezes_about_its_pivot() -> void:
	var row := _kit().kind("light")
	var piv: Vector2 = row["turret"]["pivot"]
	var xf := TankEnemyDraw.turret_xf(row, {"turret_sx": -1.0})
	assert_almost_eq((xf * piv).x, piv.x, 0.001, "the pivot stays")
	assert_almost_eq((xf * (piv + Vector2(10, 0))).x, piv.x - 10.0, 0.001, "mirrored")
	var half := TankEnemyDraw.turret_xf(row, {"turret_sx": 0.5})
	assert_almost_eq((half * (piv + Vector2(10, 0))).x, piv.x + 5.0, 0.001, "squeezed")
	assert_eq(
		TankEnemyDraw.turret_xf(_kit().kind("destroyer"), {}), Transform2D.IDENTITY, "no turret"
	)


func test_each_wheel_lifts_with_the_ground_under_it() -> void:
	var row := _kit().kind("medium")
	var rest: Array[Vector3] = row["gear"]["wheels"]
	var flat := func(_x: float) -> float: return 400.0
	var on_flat: Dictionary = TankEnemyDraw.hull_pose(row, FOOT, {"ground": flat})
	for i in rest.size():
		assert_almost_eq((on_flat["wheels"][i] as Vector2).y, rest[i].y, 1.0, "flat: at rest")
	# a short bump under one end only
	var left_x := FOOT.x - 64.0 + rest[0].x
	var bump := func(x: float) -> float: return 397.0 if absf(x - left_x) < 5.0 else 400.0
	var on_bump: Dictionary = TankEnemyDraw.hull_pose(row, FOOT, {"ground": bump})
	var rise := (on_bump["wheels"][0] as Vector2).y - (on_bump["wheels"][5] as Vector2).y
	assert_lt(rise, 0.0, "the wheel on the bump rides higher than the far one")


func test_wheels_stay_within_their_travel() -> void:
	var row := _kit().kind("heavy")
	var g: Dictionary = row["gear"]
	var rest: Array[Vector3] = g["wheels"]
	var pit := func(_x: float) -> float: return 460.0
	var r: Dictionary = TankEnemyDraw.hull_pose(row, FOOT, {"ground": pit})
	for i in rest.size():
		var dy := (r["wheels"][i] as Vector2).y - rest[i].y
		assert_between(dy, -float(g["up"]) - 1.0, float(g["droop"]) + 1.0, "wheel %d" % i)


func test_the_hull_tilts_on_a_slope_and_stays_flat_on_a_hair_of_one() -> void:
	var row := _kit().kind("medium")
	var slope := func(x: float) -> float: return 400.0 + (x - FOOT.x) * 0.1
	var tilted: Transform2D = TankEnemyDraw.hull_pose(row, FOOT, {"ground": slope})["stage"]
	assert_almost_eq(tilted.get_rotation(), atan(0.1), 0.01)
	var hair := func(x: float) -> float: return 400.0 + (x - FOOT.x) * 0.002
	var flat: Transform2D = TankEnemyDraw.hull_pose(row, FOOT, {"ground": hair})["stage"]
	assert_eq(flat.get_rotation(), 0.0, "no jaggy half-pixel lean")


func test_the_belt_runs_clockwise_round_the_right_circles() -> void:
	var row := _kit().kind("light")
	var g: Dictionary = row["gear"]
	var rest: Array[Vector3] = g["wheels"]
	var wheels: Array = []
	for w in rest:
		wheels.append(Vector2(w.x, w.y))
	var circles := TankEnemyDraw.belt_circles(g, wheels)
	assert_eq(circles.size(), rest.size() + (g["rollers"] as Array).size() + 2)
	assert_lt(
		circles[0].x, circles[(g["rollers"] as Array).size() + 1].x, "left end, then right end"
	)
	var belt := TankBody.belt_of(circles, TankBody.ARC_DS)
	var top := 1e9
	var low := -1e9
	for e: Array in belt["pts"]:
		top = minf(top, (e[0] as Vector2).y)
		low = maxf(low, (e[0] as Vector2).y)
	assert_almost_eq(low, rest[0].y + rest[0].z + 0.5, 0.01, "the lower run under the wheels")
	var sp: Vector3 = g["sprocket"]
	assert_lte(top, sp.y - sp.z, "the upper run over the sprocket")
	var pitch := float(row["track"]["pitch"])
	assert_gt(float(belt["len"]) / pitch, 30.0, "a long run of separate shoes")


func test_a_shoe_moves_with_travel_and_loops_each_pitch() -> void:
	var row := _kit().kind("medium")
	var g: Dictionary = row["gear"]
	var rest: Array[Vector3] = g["wheels"]
	var wheels: Array = []
	for w in rest:
		wheels.append(Vector2(w.x, w.y))
	var belt := TankBody.belt_of(TankEnemyDraw.belt_circles(g, wheels), TankBody.ARC_DS)
	var a := TankEnemyDraw.along(belt["pts"], float(belt["len"]), 10.0, 0)
	var b := TankEnemyDraw.along(belt["pts"], float(belt["len"]), 12.0, 0)
	var wrap := TankEnemyDraw.along(belt["pts"], float(belt["len"]), 10.0 + float(belt["len"]), 0)
	assert_gt((a[0] as Vector2).distance_to(b[0]), 1.5, "along the belt")
	assert_almost_eq((a[0] as Vector2).distance_to(wrap[0]), 0.0, 0.01, "the loop closes")


func test_wheel_frames_turn_with_travel() -> void:
	for k: String in ["medium", "recon", "behemoth"]:
		var s: Dictionary = _kit().kind(k)["sheets"]["road"]
		assert_gte(int(s["frames"]), 6, k)
		assert_eq((s["rect"] as Rect2).size.x, float(s["size"]) * int(s["frames"]), k)
		assert_eq(TankEnemyDraw.frame_of(s, 0.0), 0, k)
		assert_eq(
			TankEnemyDraw.frame_of(s, float(s["period"])), 0, "%s: a period is the same frame" % k
		)
		assert_gt(TankEnemyDraw.frame_of(s, float(s["period"]) * 0.5), 0, k)


func test_a_point_of_the_hull_follows_the_pose() -> void:
	var kit := _kit()
	var ex: Vector2 = kit.kind("heavy")["exhaust"]
	var a := TankEnemyDraw.point(kit, "heavy", FOOT, {}, ex)
	var b := TankEnemyDraw.point(kit, "heavy", FOOT, {"flip": true}, ex)
	assert_gt(a.x, FOOT.x, "the heavy's stack is at its stern, on the right")
	assert_lt(b.x, FOOT.x, "mirrored")
	assert_lt(a.y, FOOT.y, "above the road")


func test_near_kinds_and_far_kinds_face_their_way() -> void:
	var kit := _kit()
	for k: String in TankIds.NEAR_KINDS:
		assert_eq(int(kit.kind(k)["faces"]), 1, "%s flees to the right" % k)
	for k2: String in ["light", "medium", "heavy", "destroyer", "behemoth"]:
		assert_eq(int(kit.kind(k2)["faces"]), -1, "%s faces us" % k2)
