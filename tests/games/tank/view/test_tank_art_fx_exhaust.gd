extends GutTest
## Art polish (effects): the diesel's exhaust reads at every load (a train of billowed puffs that
## leave with the hull and lose its motion to the air, a black column in a sprint, a heat shimmer
## over the mouth), steam stays in its room and is white, the smoke ring is a ragged roll, and a
## camera jump never flings smoke across the world.

const DT := 1.0 / 60.0


func _fx() -> TankFx:
	var fx := TankFx.new()
	fx.seed_rng(11)
	add_child_autofree(fx)
	return fx


func _exhaust_of(fx: TankFx) -> Array[int]:
	var out: Array[int] = []
	for i in fx.particles.count:
		if fx.particles.kind[i] == TankParticles.Kind.EXHAUST:
			out.append(i)
	return out


func test_tempo_exhaust_is_a_train_of_puffs_rising_off_the_stack() -> void:
	var fx := _fx()
	for _i in 120:
		fx.exhaust("stack", Vector2(100, 200), 0.9, DT)
		fx.step(DT)
	var ids := _exhaust_of(fx)
	assert_gt(ids.size(), 8, "a readable train of puffs")
	var highest := 200.0
	for i in ids:
		highest = minf(highest, fx.particles.pos[i].y)
		assert_gte(fx.particles.size1[i], 20.0, "puffs swell well past the stack's width")
		assert_gt(fx.particles.color[i].a, 0.7, "dense at tempo")
	assert_lt(highest, 140.0, "the column climbs well clear of the deck")


func test_a_sprint_is_a_thicker_black_column() -> void:
	var tempo := _fx()
	var sprint := _fx()
	for _i in 120:
		tempo.exhaust("stack", Vector2(100, 200), 0.9, DT)
		sprint.exhaust("stack", Vector2(100, 200), 1.35, DT)
		tempo.step(DT)
		sprint.step(DT)
	var t_ids := _exhaust_of(tempo)
	var s_ids := _exhaust_of(sprint)
	assert_gt(s_ids.size(), t_ids.size() + 10, "a continuous column")
	var t_size := 0.0
	for i in t_ids:
		t_size += tempo.particles.size1[i] / float(t_ids.size())
	var s_size := 0.0
	for i in s_ids:
		s_size += sprint.particles.size1[i] / float(s_ids.size())
		assert_lt(sprint.particles.color[i].r, 0.1, "black")
	assert_gt(s_size, t_size, "and fatter")


func test_the_exhaust_never_thins_with_the_frame_time() -> void:
	var fast := _fx()
	var slow := _fx()
	slow.note_frame_time(0.05)
	assert_almost_eq(slow.quality, TankFx.MIN_QUALITY, 1e-6)
	for _i in 120:
		fast.exhaust("stack", Vector2(100, 200), 0.9, DT)
		slow.exhaust("stack", Vector2(100, 200), 0.9, DT)
	assert_eq(
		_exhaust_of(slow).size(), _exhaust_of(fast).size(), "the riders' effort stays readable"
	)


func test_puffs_leave_with_the_hull_and_a_parked_stack_stands_still() -> void:
	var fx := _fx()
	# The camera follows the hull at 60 px/s: the hull's stack stays put on screen, a parked
	# enemy's slides left with the world.
	for f in 60:
		fx.exhaust("stack", Vector2(100, 200), 0.6, DT)
		fx.exhaust("e1", Vector2(500 - float(f), 220), 0.6, DT)
		fx.step(DT, 1.0)
	assert_almost_eq(fx.scroll_v, 60.0, 1.0)
	var hull := fx.source_velocity("stack", Vector2(100, 200), DT)
	var parked := fx.source_velocity("e1", Vector2(440, 220), DT)
	assert_almost_eq(hull.x, 60.0, 1.0, "the hull's stack moves with the hull")
	assert_almost_eq(parked.x, 0.0, 1.5, "a parked stack does not move")


func test_a_camera_jump_never_flings_smoke() -> void:
	var fx := _fx()
	for _i in 30:
		fx.exhaust("stack", Vector2(100, 200), 0.9, DT)
		fx.step(DT, 1.0)
	# A fast forward or a new stage moves the camera thousands of px in one frame.
	fx.step(DT, 9000.0)
	fx.step(DT, -12000.0)
	assert_lte(absf(fx.scroll_v), TankFx.MAX_SOURCE_V)
	for f in 30:
		fx.exhaust("stack", Vector2(100, 200), 0.9, DT)
		fx.exhaust("e2", Vector2(100.0 + float((f * 997) % 3000), 220), 0.9, DT)
		fx.step(DT, 1.0)
	for i in _exhaust_of(fx):
		assert_lte(fx.particles.vel[i].length(), TankFx.MAX_SOURCE_V + 80.0)


func test_the_stack_gets_a_heat_shimmer_and_it_goes_with_the_smoke() -> void:
	var fx := _fx()
	fx.step(DT)
	assert_eq(fx.shimmer_live, 0)
	for k in 5:
		fx.exhaust("s%d" % k, Vector2(100 + k * 50, 200), 0.2 + 0.2 * float(k), DT)
	fx.step(DT)
	assert_eq(fx.shimmer_live, TankFx.SHIMMER_MAX, "only the strongest few")
	fx.step(DT)
	assert_eq(fx.shimmer_live, 0, "gone when the stack stops")


func test_steam_puffs_are_white_and_ride_in_their_room() -> void:
	var fx := _fx()
	fx.steam_puff(Vector2(200, 250))
	var n := fx.particles.count
	assert_gte(n, 3)
	var before: Array[Vector2] = []
	for i in n:
		assert_eq(fx.particles.kind[i], TankParticles.Kind.STEAM)
		assert_eq(fx.particles.plane[i], TankParticles.PLANE_HULL, "carried with the hull")
		assert_gt(fx.particles.color[i].b, 0.9, "white")
		before.append(fx.particles.pos[i])
	fx.step(0.1, 6.0)
	for i in n:
		assert_lt(absf(fx.particles.pos[i].x - before[i].x), 3.0, "the scroll does not smear it")


func test_a_latch_hisses_a_jetting_cloud_and_a_deck_vent_plumes() -> void:
	var fx := _fx()
	fx.steam_burst(Vector2(200, 250))
	var wide := 0
	for i in fx.particles.count:
		if absf(fx.particles.vel[i].x) > 60.0:
			wide += 1
	assert_gt(fx.particles.count, 10)
	assert_gt(wide, 1, "jets sideways off the valve")
	var vent := _fx()
	vent.steam_plume(Vector2(200, 180))
	assert_gt(vent.particles.count_kind(TankParticles.Kind.STEAM), 1)
	for i in vent.particles.count:
		assert_lt(vent.particles.vel[i].y, -40.0, "rises well clear of the deck")


func test_dynamo_sparks_stay_in_the_room_while_the_hull_moves() -> void:
	var fx := _fx()
	var arc := Vector2(150, 250)
	for _i in 60:
		fx.dynamo_sparks("arc", arc, 1.0, DT)
		fx.step(DT, 1.5)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.SPARK), 0)
	for i in fx.particles.count:
		assert_lt(fx.particles.pos[i].distance_to(arc), 32.0, "local to the armature")


func test_the_smoke_ring_is_seeded_short_and_ragged() -> void:
	var fx := _fx()
	fx.muzzle_blast(Vector2(300, 150), Vector2.RIGHT, 0.6, false)
	var ring := -1
	for i in fx.particles.count:
		if fx.particles.kind[i] == TankParticles.Kind.RING:
			ring = i
	assert_gte(ring, 0)
	assert_ne(fx.particles.rot[ring], 0.0, "its seed jitters the puffs")
	assert_lte(fx.particles.ttl[ring], 0.8, "it breaks up quickly")
	# The jitter is repeatable per seed and spread over 0 .. 1.
	var lo := 1.0
	var hi := 0.0
	for n in TankFxLayer.RING_PUFFS:
		var h := TankFxLayer._hash(fx.particles.rot[ring], n)
		assert_eq(h, TankFxLayer._hash(fx.particles.rot[ring], n))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	assert_gt(hi - lo, 0.3, "the puffs differ")


func test_the_billow_is_a_soft_lump_lit_from_below_built_once() -> void:
	var tex := TankFxLayer.billow(0.5)
	assert_same(tex, TankFxLayer.billow(0.5), "cached")
	var img := tex.get_image()
	assert_gt(img.get_pixel(16, 16).a, 0.95, "a dense middle")
	assert_lt(img.get_pixel(0, 0).a, 0.05, "soft corners")
	assert_lt(img.get_pixel(0, 31).a, 0.05)
	assert_lt(img.get_pixel(16, 6).r, img.get_pixel(16, 24).r, "darker on top than underneath")
	var white := TankFxLayer.billow(0.82).get_image()
	assert_gt(white.get_pixel(16, 6).r, img.get_pixel(16, 6).r, "steam's billow stays white")


func test_a_storm_of_stacks_stays_inside_the_cap() -> void:
	var fx := _fx()
	for _i in 240:
		for k in 20:
			fx.exhaust("e%d" % k, Vector2(20 + k * 30, 220), 1.4, DT)
		fx.steam_puff(Vector2(200, 250))
		fx.step(DT, 1.0)
		assert_lte(fx.live(), TankParticles.CAP)
