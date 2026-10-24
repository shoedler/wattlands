extends GutTest
## Art polish round 5 (effects): the deck vent's plume is a column of small puffs from the pipe's
## mouth, the dynamo's sparks stay blue-white and low in their room, the tracks throw dust and mud at
## speed, a shot kicks dust off the road, casings are two-tone brass that tumble on an arc and glint,
## and the heat shimmer wavers the young smoke at the stack's mouth.

const DT := 1.0 / 60.0
## The camera's step at about 23 km/h (art px per frame).
const SCROLL_23KMH := 51.0 / 60.0


func _fx() -> TankFx:
	var fx := TankFx.new()
	fx.seed_rng(23)
	add_child_autofree(fx)
	return fx


func _of(fx: TankFx, k: int) -> Array[int]:
	var out: Array[int] = []
	for i in fx.particles.count:
		if fx.particles.kind[i] == k:
			out.append(i)
	return out


func test_a_stroke_feeds_a_column_of_small_puffs_from_the_vent_mouth() -> void:
	var fx := _fx()
	var mouth := Vector2(250, 190)
	fx.steam_plume(mouth)
	for i in _of(fx, TankParticles.Kind.STEAM):
		assert_lt(fx.particles.pos[i].distance_to(mouth), 2.5, "it leaves the pipe's mouth")
	var first := fx.particles.count
	for _f in 24:
		fx.step(DT, SCROLL_23KMH)
	var ids := _of(fx, TankParticles.Kind.STEAM)
	assert_gt(ids.size(), first + 4, "the stroke keeps feeding the column for a moment")
	var top := mouth.y
	var bottom := 0.0
	for i in ids:
		var c: Color = fx.particles.color[i]
		assert_lte(fx.particles.size1[i], 20.0, "small puffs, never a big disc")
		assert_lte(maxf(c.r, maxf(c.g, c.b)), TankFx.PLUME_CORE.r + 1e-3, "below the lamps")
		assert_lt(c.a, 0.7, "translucent")
		top = minf(top, fx.particles.pos[i].y)
		bottom = maxf(bottom, fx.particles.pos[i].y)
	assert_gt(bottom - top, 10.0, "a column: puffs at every height, not one blob")
	# Long after the stroke the column has risen, drifted back and stopped growing.
	for _f in 90:
		fx.step(DT, SCROLL_23KMH)
	assert_eq(fx.particles.count_kind(TankParticles.Kind.STEAM), 0, "it fades within about 2 s")


func test_the_plume_leans_back_as_it_rises() -> void:
	var fx := _fx()
	var mouth := Vector2(250, 190)
	fx.steam_plume(mouth)
	for _f in 30:
		fx.step(DT, SCROLL_23KMH)
	var ids := _of(fx, TankParticles.Kind.STEAM)
	assert_gt(ids.size(), 0)
	for i in ids:
		var p: Vector2 = fx.particles.pos[i]
		if p.y < mouth.y - 12.0:
			assert_lt(p.x, mouth.x, "a risen puff has drifted back (left)")


func test_dynamo_sparks_are_cold_blended_and_stay_low_in_the_room() -> void:
	var fx := _fx()
	var arc := Vector2(180, 255)
	var highest := arc.y
	for _f in 120:
		fx.dynamo_sparks("arc", arc, 1.0, DT)
		fx.step(DT, SCROLL_23KMH)
		for i in _of(fx, TankParticles.Kind.SPARK):
			highest = minf(highest, fx.particles.pos[i].y)
	var ids := _of(fx, TankParticles.Kind.SPARK)
	assert_gt(ids.size(), 2, "a steady crackle at FTP")
	for i in ids:
		var c: Color = fx.particles.color[i]
		assert_gt(c.b, c.r, "blue-white")
		assert_false(fx.particles.is_additive(i), "blended, so a warm room can't turn them cream")
	# The brushes sit on the rim's upper half (rim radius about 9.5): the sparks climb only a few
	# px above them, far from the wall lamp by the ceiling.
	assert_gt(highest, arc.y - 9.5 - 6.0, "never climbing toward the lamp")
	var off := _fx()
	for _f in 60:
		off.dynamo_sparks("arc", arc, 0.0, DT)
	assert_eq(off.live(), 0, "a stopped dynamo throws nothing")


func test_warm_sparks_stay_additive() -> void:
	var fx := _fx()
	fx.impact_sparks(Vector2(300, 200), Vector2.UP)
	for i in _of(fx, TankParticles.Kind.SPARK):
		assert_true(fx.particles.is_additive(i), "impact sparks are light")
	assert_true(TankParticles.ADDITIVE.has(TankParticles.Kind.FLASH))


func test_tracks_throw_dust_along_the_run_and_mud_at_speed() -> void:
	var fx := _fx()
	var at := Vector2(10, 293)
	for _f in 60:
		fx.track_dust("tracks", at, 6.4, DT)
		fx.step(DT, SCROLL_23KMH)
	var dust := _of(fx, TankParticles.Kind.DUST)
	assert_gt(dust.size(), 10, "a cloud at 23 km/h")
	var reach := 0.0
	var lift := 0.0
	for i in dust:
		reach = maxf(reach, fx.particles.pos[i].x - at.x)
		lift = maxf(lift, at.y - fx.particles.pos[i].y)
		assert_gt(fx.particles.color[i].a, 0.5, "readable at speed")
	assert_gt(reach, 25.0, "dust rolls off the lower run under the hull, not only behind it")
	assert_gt(lift, 6.0, "and climbs off the road")
	assert_gt(fx.particles.count_kind(TankParticles.Kind.DIRT), 2, "mud flicked off the links")
	var walk := _fx()
	for _f in 60:
		walk.track_dust("tracks", at, 1.5, DT)
	assert_lt(walk.live(), dust.size(), "less at a walk")


func test_a_shot_kicks_dust_off_the_road_under_the_muzzle() -> void:
	var fx := _fx()
	var mz := Vector2(285, 183)
	fx.muzzle_blast(mz, Vector2.RIGHT, 0.6)
	var dust := _of(fx, TankParticles.Kind.DUST)
	assert_gte(dust.size(), 8)
	for i in dust:
		assert_gt(fx.particles.pos[i].y, float(TankConst.GROUND_Y) - 8.0, "off the road")
		assert_lt(absf(fx.particles.pos[i].x - mz.x - 14.0), 30.0, "under and ahead of the gun")
		assert_lt(fx.particles.vel[i].y, -15.0, "it climbs")
	var none := _fx()
	none.muzzle_blast(mz, Vector2.RIGHT, 0.6, false)
	assert_eq(none.particles.count_kind(TankParticles.Kind.DUST), 0)


func test_a_casing_tumbles_on_a_visible_arc_and_glints() -> void:
	var fx := _fx()
	var breech := Vector2(125, 185)
	fx.brass(breech, Vector2(-0.8, -1.0).normalized())
	var ids := _of(fx, TankParticles.Kind.BRASS)
	assert_eq(ids.size(), 1)
	assert_gte(absf(fx.particles.spin[ids[0]]), 16.0, "a fast tumble")
	var apex := breech.y
	var glints := 0
	for _f in 50:
		fx.step(DT)
		var i := _of(fx, TankParticles.Kind.BRASS)[0]
		apex = minf(apex, fx.particles.pos[i].y)
		glints += 1 if TankFxLayer.glints(fx.particles.rot[i]) else 0
	assert_gt(breech.y - apex, 6.0, "it pops up before it falls")
	assert_gt(fx.particles.pos[_of(fx, TankParticles.Kind.BRASS)[0]].y, breech.y, "then falls")
	assert_gt(glints, 3, "a glint now and then while it tumbles")
	assert_lt(glints, 25, "a glint, not a steady shine")


func test_brass_never_looks_like_a_spark() -> void:
	var lit := TankFxLayer.BRASS_LIT
	assert_ne(lit, TankPalette.AMBER.lerp(Color.BLACK, 0.5))
	assert_lt(TankFxLayer.BRASS_SHADE.get_luminance(), lit.get_luminance() * 0.6, "two-tone")
	assert_eq(TankParticles.Kind.BRASS in TankParticles.ADDITIVE, false, "a solid, not a light")


func test_the_shimmer_wavers_the_young_smoke_under_the_fire() -> void:
	var fx := _fx()
	var smoke := fx.alpha_layer.get_index()
	var fire := fx.add_layer.get_index()
	var copy := fx.get_node("ShimmerCopy").get_index()
	assert_gt(copy, smoke, "the copy is taken after the smoke is drawn")
	assert_lt(copy, fire)
	fx.exhaust("stack", Vector2(82, 184), 0.9, DT)
	fx.step(DT)
	var q := fx.get_node("Shimmer0") as ColorRect
	assert_true(q.visible)
	assert_gt(q.position.y + q.size.y, 184.0, "it starts at the mouth itself")
	assert_lt(q.position.y + q.size.y, 190.0)


func test_a_moving_tank_leans_its_exhaust_back() -> void:
	var fx := _fx()
	var mouth := Vector2(82, 184)
	for _f in 120:
		fx.exhaust("stack", mouth, 0.9, DT)
		fx.step(DT, SCROLL_23KMH)
	var risen := 0
	for i in _of(fx, TankParticles.Kind.EXHAUST):
		var p: Vector2 = fx.particles.pos[i]
		if p.y < mouth.y - 30.0:
			risen += 1
			assert_lt(p.x, mouth.x, "the column trails back at speed")
	assert_gt(risen, 3)


func test_the_plume_and_dust_stay_inside_the_cap() -> void:
	var fx := _fx()
	for f in 600:
		fx.exhaust("stack", Vector2(82, 184), 1.4, DT)
		fx.track_dust("tracks", Vector2(10, 293), 12.0, DT)
		fx.dynamo_sparks("arc", Vector2(180, 255), 1.2, DT)
		if f % 10 == 0:
			fx.steam_plume(Vector2(250, 190))
		if f % 90 == 0:
			fx.muzzle_blast(Vector2(285, 183), Vector2.RIGHT, 1.0)
			fx.brass(Vector2(125, 185), Vector2(-0.8, -1.0).normalized())
		fx.step(DT, SCROLL_23KMH)
		assert_lte(fx.live(), TankParticles.CAP)
