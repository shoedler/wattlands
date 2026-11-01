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
	var drawn := 0

	func _draw() -> void:
		for c: Array in calls:
			TankEnemyDraw.draw(self, kit, str(c[0]), c[1], c[2])
			TankEnemyDraw.draw_light(self, kit, str(c[0]), c[1], c[2])
			drawn += 1


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
	assert_eq(sk.drawn, sk.calls.size(), "every pose drew")


## The flame is hot: painted on black at its fullest it reaches near white at the core, on every kind, and it is
## taller on the Behemoth.
func test_a_wreck_burns_hot_and_to_its_size() -> void:
	var heights := {}
	for k: String in ["tankette", "behemoth"]:
		var vp := SubViewport.new()
		vp.size = Vector2i(420, 240)
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var sk := Sketch.new()
		sk.calls.append([k, Vector2(210, 200), {"wrecked": true, "time": 0.3}])
		vp.add_child(sk)
		add_child_autofree(vp)
		sk.queue_redraw()
		heights[k] = float((_kit().kind(k)["wreck_fires"] as Array)[0][2])
	assert_gt(float(heights["behemoth"]), float(heights["tankette"]) * 3.0)
	assert_eq(TankEnemyDraw.FIRE_CORE.a, 1.0, "the core's colour is not scaled by its strength")
	assert_gt(TankEnemyDraw.FIRE_CORE.g, 0.9, "white-hot at the core")


## The haze's veil: nothing up close, more with the range, opaque nowhere, a flash above all of it.
func test_the_haze_steps_widen_across_the_field() -> void:
	var near := TankEnemyDraw._veil({"haze": 0.12})
	var mid := TankEnemyDraw._veil({"haze": 0.31})
	var far := TankEnemyDraw._veil({"haze": 0.5})
	assert_lt(near.a, 0.1)
	assert_gt(mid.a - near.a, 0.2, "the steps are wide enough to part the lanes")
	assert_gt(far.a - mid.a, 0.2)
	assert_almost_eq(TankEnemyDraw._veil({"haze": 1.0}).a, TankEnemyDraw.HAZE_MAX, 0.001)
	assert_eq(TankEnemyDraw._veil({}).a, 0.0, "no veil without haze or a flash")
	assert_eq(TankEnemyDraw._veil({"flash": 1.0}).a, 1.0, "a full flash lights the whole shape")


## At full flash the whole shape is the flash: no slit or vent stays as a box on it.
func test_a_flash_takes_the_lights_with_it() -> void:
	assert_eq(TankEnemyDraw.light_k({"flash": 1.0}), 0.0)
	assert_eq(TankEnemyDraw.light_k({}), 1.0)
	assert_almost_eq(TankEnemyDraw.light_k({"haze": 1.0}), 0.5, 0.001)
	assert_lt(TankEnemyDraw.light_k({"dim": 0.5, "flash": 0.5}), 0.3)


## A small kind's fire is one tongue, a large kind's up to three of unequal height.
func test_a_fire_has_tongues_to_its_size() -> void:
	assert_eq(TankEnemyDraw.tongues_of(7.0), 1, "the tankette's")
	assert_eq(TankEnemyDraw.tongues_of(16.0), 2)
	assert_eq(TankEnemyDraw.tongues_of(32.0), 3, "the Behemoth's")


## A flame comes out of its mouth: its foot no wider than the mouth, an uneven lower edge, widening 2-4 rows up, and
## its tongues one body below 70 % of its height, so no dark counter opens there (no glyph, no 8).
func test_a_flame_comes_out_of_its_mouth() -> void:
	for height: float in [7.0, 11.0, 14.0, 16.0, 18.0, 24.0, 32.0]:
		var mouth := TankEnemyDraw.mouth_r(height)
		var uneven := false
		for i in 40:
			var t := float(i) * 0.083
			var seed := 13.0 + float(i) * 3.7
			var rows := TankEnemyDraw.flame_rows(height, t, seed)
			assert_gt(rows.size(), 3, "a fire of %d stands" % height)
			var foot: Array[Vector2] = rows[0][3]
			assert_eq(foot.size(), 1, "one foot")
			assert_lte(foot[0].y, mouth * 2.0 + 0.01, "the foot of %d fits its mouth" % height)
			assert_lte(absf(foot[0].x + foot[0].y * 0.5), mouth, "and stands in it")
			var belly := 0.0
			for k in rows.size():
				if k >= 1 and k <= 4:
					for sp: Vector2 in rows[k][3]:
						belly = maxf(belly, sp.y)
				if float(rows[k][2]) < TankEnemyDraw.FIRE_BODY:
					assert_eq((rows[k][3] as Array).size(), 1, "one body at %d of %d" % [k, height])
			if height >= 14.0:
				assert_gt(
					belly, foot[0].y, "a fire of %d widens within 4 rows of its foot" % height
				)
			var drops := {}
			for x in range(-int(foot[0].y * 0.5), int(foot[0].y * 0.5)):
				drops[TankEnemyDraw.flame_drop(x, floorf(t * 6.0), seed, height)] = true
			uneven = uneven or drops.size() > 1
		assert_true(uneven, "the lower edge of a fire of %d is uneven" % height)


## The far air: the haze is the hue of the game's own far sky and ridges (191-194), so far kinds fade into them; it
## stops at half, so the farthest keeps its seams.
func test_the_haze_is_the_far_airs_hue() -> void:
	assert_between(
		TankEnemyDraw.HAZE.h * 360.0, 186.0, 198.0, "hue of the sky #081519 and ridges #0e2429"
	)
	assert_lte(TankEnemyDraw.HAZE_MAX, 0.5)
	assert_lte(
		TankEnemyDraw._veil({"haze": 0.46}).a, 0.5, "the destroyer at 2200 m keeps its seams"
	)


## The furnace: lit between the louvre's bars and only there, its gaps at different heats.
func test_the_furnace_burns_between_its_bars() -> void:
	var fr := Rect2(100, 50, 22, 8)
	var gaps := TankEnemyDraw.furnace_gaps(fr)
	assert_gte(gaps.size(), 5)
	for g: Rect2 in gaps:
		for x in range(int(g.position.x), int(g.end.x)):
			assert_ne((x - int(fr.position.x)) % 4, 3, "x %d is a bar" % x)
		assert_true(fr.encloses(g), "inside the vent")
	for i in 5:
		assert_ne(TankEnemyDraw.furnace_heat(i), TankEnemyDraw.furnace_heat(i + 1), "no even heat")
	var cold := TankEnemyDraw.SLIT_CORE
	assert_gt(cold.b, cold.r, "one hue with the slits")


## Each tooth near the top of a sprocket stands in a gap of the belt, at rest and on the move: the sprocket turns
## with the belt, on its pitch circle.
func test_a_sprocket_tooth_sits_in_a_shoes_gap() -> void:
	for k: String in ["light", "medium", "heavy", "destroyer", "tankette"]:
		var row := _kit().kind(k)
		var g: Dictionary = row["gear"]
		var rest: Array[Vector3] = g["wheels"]
		var wheels: Array = []
		for w in rest:
			wheels.append(Vector2(w.x, w.y))
		var belt := TankBody.belt_of(TankEnemyDraw.belt_circles(g, wheels), TankBody.ARC_DS)
		var sp: Vector3 = g["sprocket"]
		var teeth := int(row["sheets"]["sprocket"]["teeth"])
		var total := float(belt["len"])
		var count := maxi(roundi(total / float(row["track"]["pitch"])), 3)
		var pitch := total / count
		for travel: float in [0.0, 3.3, 11.7, -5.2]:
			var a := TankEnemyDraw.sprocket_angle(belt, sp, travel)
			# the tooth nearest the top of the drum
			var arc := TAU / float(teeth)
			var near := a + roundf((-PI * 0.5 - a) / arc) * arc
			var q := Vector2(sp.x, sp.y) + Vector2.from_angle(near) * (sp.z + 0.5)
			var best := INF
			for n in count:
				var joint: Array = TankEnemyDraw.along(belt["pts"], total, travel + pitch * n, 0)
				best = minf(best, (joint[0] as Vector2).distance_to(q))
			assert_lt(best, 1.6, "%s at %.1f: tooth %.1f px from a gap" % [k, travel, best])


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


## On a slope the hull tilts and the turret and its gun stay level on the hull's pivot, so its digits keep their rows; a
## casemate's gun stays on its hull. Flat ground changes nothing.
func test_a_turret_rides_level_on_a_tilted_hull() -> void:
	var row := _kit().kind("light")
	var slope := func(x: float) -> float: return 400.0 + (x - FOOT.x) * 0.1
	var pose := {"ground": slope}
	var stage: Transform2D = TankEnemyDraw.hull_pose(row, FOOT, pose)["stage"]
	assert_ne(stage.get_rotation(), 0.0, "the hull tilts")
	var top := TankEnemyDraw.level_stage(row, stage)
	assert_eq(top.get_rotation(), 0.0, "the turret does not")
	var piv: Vector2 = row["turret"]["pivot"]
	assert_almost_eq((top * piv).distance_to(stage * piv), 0.0, 1.0, "it stays on the hull's pivot")
	var flipped: Transform2D = (
		TankEnemyDraw.hull_pose(row, FOOT, {"ground": slope, "flip": true})["stage"]
	)
	var mirror := TankEnemyDraw.level_stage(row, flipped)
	assert_lt(mirror.x.x, 0.0, "a flip still mirrors it")
	assert_eq(mirror.x.y, 0.0, "and level")
	var level := TankEnemyDraw.muzzle(_kit(), "light", FOOT, pose)
	var bore := TankEnemyDraw.bore(_kit(), "light", FOOT, pose)
	assert_almost_eq(level.y, bore[0].y, 0.01, "at 0 degrees the bore runs level on the slope")
	var flat: Transform2D = TankEnemyDraw.hull_pose(row, FOOT, {})["stage"]
	assert_eq(TankEnemyDraw.level_stage(row, flat), flat, "on the flat it is the hull's stage")
	var casemate := _kit().kind("destroyer")
	var tilted: Transform2D = TankEnemyDraw.hull_pose(casemate, FOOT, pose)["stage"]
	assert_eq(TankEnemyDraw.level_stage(casemate, tilted), tilted, "no turret, no level")


## Mid-traverse is no sliver: a slab never draws under half its width.
func test_a_turret_is_never_a_sliver() -> void:
	var row := _kit().kind("light")
	var piv: Vector2 = row["turret"]["pivot"]
	for sx: float in [0.0, 0.1, 0.34, -0.05, -0.32]:
		var xf := TankEnemyDraw.turret_xf(row, {"turret_sx": sx})
		var wide := absf((xf * (piv + Vector2(10, 0))).x - piv.x)
		assert_almost_eq(wide, 5.0, 0.001, "at %.2f" % sx)


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
