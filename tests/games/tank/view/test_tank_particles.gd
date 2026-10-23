extends GutTest
## Particles (brief 3): pooled, capped at about 400 live, fewer emitters when the frame time rises,
## cosmetic randomness from the view's own seeded RNG, and no effect on the rules.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _fx(seed_value: int = 7) -> TankFx:
	var fx := TankFx.new()
	fx.seed_rng(seed_value)
	add_child_autofree(fx)
	return fx


func test_the_pool_never_exceeds_the_cap() -> void:
	var p := TankParticles.new()
	for i in 1000:
		p.spawn(TankParticles.Kind.SMOKE, Vector2(i, 0), Vector2.ZERO, 5.0, 4.0, 8.0, Color.WHITE)
	assert_eq(p.count, TankParticles.CAP)
	assert_gt(p.dropped, 0, "smoke is dropped when the pool is full")
	for i in 100:
		assert_true(
			p.spawn(
				TankParticles.Kind.EXPLOSION,
				Vector2(i, 0),
				Vector2.ZERO,
				1.0,
				4.0,
				8.0,
				Color.WHITE
			)
		)
	assert_eq(p.count, TankParticles.CAP, "explosions replace the oldest instead")
	assert_gte(p.count_kind(TankParticles.Kind.EXPLOSION), 100)
	assert_eq(TankParticles.CAP, 400, "about 400 live")


func test_a_lowered_cap_is_respected() -> void:
	var p := TankParticles.new()
	p.cap = 100
	for i in 300:
		p.spawn(TankParticles.Kind.DUST, Vector2.ZERO, Vector2.ZERO, 5.0, 4.0, 8.0, Color.WHITE)
	assert_eq(p.count, 100)


func test_particles_die_and_the_pool_compacts() -> void:
	var p := TankParticles.new()
	for i in 50:
		p.spawn(
			TankParticles.Kind.SMOKE,
			Vector2.ZERO,
			Vector2.ZERO,
			0.5 + float(i) * 0.1,
			4.0,
			8.0,
			Color.WHITE
		)
	for _i in 12:
		p.step(0.1, 296.0)
	assert_lt(p.count, 50)
	assert_gt(p.count, 0)
	for _i in 100:
		p.step(0.1, 296.0)
	assert_eq(p.count, 0)


func test_gravity_drag_and_the_ground_bounce() -> void:
	var p := TankParticles.new()
	p.spawn(
		TankParticles.Kind.BRASS,
		Vector2(10, 280),
		Vector2(20, 0),
		3.0,
		2.0,
		2.0,
		Color.WHITE,
		400.0
	)
	for _i in 30:
		p.step(0.05, 296.0)
	assert_lte(p.pos[0].y, 296.0 + 1e-3, "casings land on the ground line")
	assert_gt(p.pos[0].x, 10.0)
	var q := TankParticles.new()
	q.spawn(
		TankParticles.Kind.SMOKE,
		Vector2.ZERO,
		Vector2(100, 0),
		3.0,
		4.0,
		8.0,
		Color.WHITE,
		0.0,
		2.0
	)
	q.step(0.5, 296.0)
	assert_lt(q.pos[0].x, 50.0, "drag slows it")


func test_far_planes_scroll_slower_than_the_world_and_the_front_faster() -> void:
	var p := TankParticles.new()
	for pl in [0, 1, -1]:
		p.spawn(
			TankParticles.Kind.SMOKE,
			Vector2(100, 100),
			Vector2.ZERO,
			3.0,
			4.0,
			8.0,
			Color.WHITE,
			0.0,
			0.0,
			pl
		)
	p.step(0.05, 296.0, 10.0)
	assert_almost_eq(p.pos[0].x, 90.0, 1e-4)
	assert_almost_eq(p.pos[1].x, 95.0, 1e-4)
	assert_almost_eq(p.pos[2].x, 87.0, 1e-4)


func test_quality_falls_as_the_frame_time_rises() -> void:
	assert_eq(TankFx.quality_for(0.0167), 1.0)
	assert_eq(TankFx.quality_for(TankFx.SLOW_FRAME_S), 1.0)
	var mid := TankFx.quality_for(0.025)
	assert_lt(mid, 1.0)
	assert_gt(mid, TankFx.MIN_QUALITY)
	assert_almost_eq(TankFx.quality_for(0.2), TankFx.MIN_QUALITY, 1e-6)
	assert_gt(TankFx.quality_for(0.02), TankFx.quality_for(0.03), "monotonic")


func test_slow_frames_thin_the_emitters_and_lower_the_cap() -> void:
	var fx := _fx()
	for _i in 60:
		fx.note_frame_time(0.0167)
	assert_eq(fx.quality, 1.0)
	assert_eq(fx.particles.cap, TankParticles.CAP)
	var steady := 0
	for _i in 60:
		steady += fx.rate("a", 20.0, 1.0 / 60.0)
	for _i in 120:
		fx.note_frame_time(0.04)
	assert_almost_eq(fx.quality, TankFx.MIN_QUALITY, 0.02)
	assert_lt(fx.particles.cap, TankParticles.CAP)
	var slow := 0
	for _i in 60:
		slow += fx.rate("b", 20.0, 1.0 / 60.0)
	assert_lt(slow, steady, "fewer emissions when frames are slow")


func test_rate_carries_the_fraction_between_frames() -> void:
	var fx := _fx()
	var n := 0
	for _i in 120:
		n += fx.rate("x", 10.0, 1.0 / 60.0)
	assert_almost_eq(float(n), 20.0, 1.0, "10 per second for 2 s")


func test_the_same_seed_gives_the_same_effects() -> void:
	var a := _fx(42)
	var b := _fx(42)
	var c := _fx(43)
	for fx in [a, b, c]:
		fx.muzzle_blast(Vector2(200, 180), Vector2.RIGHT, 0.8)
		fx.explosion(Vector2(400, 250), true)
	assert_eq(a.live(), b.live())
	for i in a.live():
		assert_eq(a.particles.pos[i], b.particles.pos[i])
		assert_eq(a.particles.vel[i], b.particles.vel[i])
	var differs := false
	for i in mini(a.live(), c.live()):
		differs = differs or a.particles.vel[i] != c.particles.vel[i]
	assert_true(differs, "another seed, another spray")


func test_a_muzzle_blast_makes_flash_ring_smoke_sparks_and_dust() -> void:
	var fx := _fx()
	fx.muzzle_blast(Vector2(200, 180), Vector2.RIGHT, 0.8)
	assert_eq(fx.flash, 1.0, "the muzzle flash lights the scene")
	for k in [
		TankParticles.Kind.FLASH,
		TankParticles.Kind.FIRE,
		TankParticles.Kind.RING,
		TankParticles.Kind.SMOKE,
		TankParticles.Kind.SPARK,
		TankParticles.Kind.DUST
	]:
		assert_gt(fx.particles.count_kind(k), 0, "kind %d" % k)
	fx.step(TankFx.FLASH_S)
	assert_eq(fx.flash, 0.0, "a few frames only")


func test_brass_casings_are_ejected_and_tumble() -> void:
	var fx := _fx()
	fx.brass(Vector2(100, 200), Vector2(-1, -1))
	assert_eq(fx.particles.count_kind(TankParticles.Kind.BRASS), 1)
	assert_ne(fx.particles.spin[0], 0.0)


func test_impacts_throw_sparks_and_fragments_and_dirt_sprays() -> void:
	var fx := _fx()
	fx.impact_sparks(Vector2(300, 220), Vector2.UP)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.SPARK), 3)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.EMBER), 0, "hot fragments")
	fx.dirt_spray(Vector2(400, 296))
	assert_gt(fx.particles.count_kind(TankParticles.Kind.DIRT), 3)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.DUST), 0)


func _smoke_after(fx: TankFx, frac: float) -> Array:
	for _i in 120:
		fx.exhaust("s", Vector2(100, 200), frac, 1.0 / 60.0)
	var alpha := 0.0
	var n := 0
	for i in fx.particles.count:
		if fx.particles.kind[i] == TankParticles.Kind.SMOKE:
			alpha += fx.particles.color[i].a
			n += 1
	return [n, alpha / maxf(float(n), 1.0)]


func test_exhaust_follows_watts_and_a_sprint_is_a_black_plume() -> void:
	var idle := _smoke_after(_fx(), 0.1)
	var tempo := _smoke_after(_fx(), 0.9)
	var sprint := _smoke_after(_fx(), 1.35)
	assert_gt(tempo[0], idle[0], "more smoke at tempo")
	assert_gt(sprint[0], tempo[0], "and more in a sprint")
	assert_gt(tempo[1], idle[1], "thicker smoke with watts")
	var fx := _fx()
	for _i in 30:
		fx.exhaust("p", Vector2(100, 200), 1.35, 1.0 / 60.0)
	var darkest := 1.0
	for i in fx.particles.count:
		if fx.particles.kind[i] == TankParticles.Kind.SMOKE:
			darkest = minf(darkest, fx.particles.color[i].r)
	assert_lt(darkest, 0.1, "black, not grey")
	assert_gt(fx.particles.count_kind(TankParticles.Kind.HEAT), 0, "a faint heat shimmer")


func test_steam_puffs_and_the_latch_hiss() -> void:
	var fx := _fx()
	fx.steam_puff(Vector2(200, 180))
	var puff := fx.particles.count_kind(TankParticles.Kind.STEAM)
	fx.steam_burst(Vector2(200, 180))
	assert_gt(fx.particles.count_kind(TankParticles.Kind.STEAM), puff + 5, "a hiss cloud")


func test_dynamo_sparks_follow_watts() -> void:
	var low := _fx()
	var high := _fx()
	for _i in 60:
		low.dynamo_sparks("a", Vector2(100, 200), 0.1, 1.0 / 60.0)
		high.dynamo_sparks("a", Vector2(100, 200), 1.0, 1.0 / 60.0)
	assert_gt(
		high.particles.count_kind(TankParticles.Kind.SPARK),
		low.particles.count_kind(TankParticles.Kind.SPARK)
	)
	for i in high.particles.count:
		var c: Color = high.particles.color[i]
		assert_gt(c.b, c.r, "blue sparks")


func test_track_dust_follows_speed() -> void:
	var slow := _fx()
	var fast := _fx()
	for _i in 60:
		slow.track_dust("t", Vector2(20, 290), 0.5, 1.0 / 60.0)
		fast.track_dust("t", Vector2(20, 290), 9.0, 1.0 / 60.0)
	assert_eq(slow.live(), 0, "nothing when crawling")
	assert_gt(fast.live(), 10)


func test_wrecks_smoke_and_burn() -> void:
	var fx := _fx()
	for _i in 120:
		fx.fire_and_smoke("w", Vector2(300, 260), 1.0, 1.0, 1.0 / 60.0)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.SMOKE), 0)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.FIRE), 0)
	var out := _fx()
	for _i in 120:
		out.fire_and_smoke("w", Vector2(300, 260), 0.0, 1.0, 1.0 / 60.0)
	assert_eq(out.particles.count_kind(TankParticles.Kind.FIRE), 0, "a burnt-out wreck only smokes")


func test_forgetting_a_source_drops_its_carry() -> void:
	var fx := _fx()
	fx.rate("e5", 1.0, 0.5)
	fx.rate("e5_heat", 1.0, 0.5)
	fx.rate("e50", 1.0, 0.5)
	fx.forget("e5")
	assert_eq(fx.rate("e5", 1.0, 0.5), 0)
	assert_false(fx._acc.has("e5_heat"))
	assert_true(fx._acc.has("e50"), "another source with the same prefix stays")


func test_a_storm_of_effects_stays_inside_the_cap() -> void:
	var fx := _fx()
	for i in 80:
		fx.explosion(Vector2(300 + i, 240), true)
		fx.muzzle_blast(Vector2(200, 180), Vector2.RIGHT, 1.0)
		fx.impact_sparks(Vector2(300, 220))
		fx.step(0.016)
		assert_lte(fx.live(), TankParticles.CAP)


func test_the_view_stays_inside_the_cap_under_a_cue_storm() -> void:
	var s := TankFixtures.boss(3)
	var v := U.view_of(self, s)
	for i in 200:
		v.game.cue.emit(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 1))
		v.game.cue.emit(
			TankEvents.HIT,
			TankEvents.hit(TankEvents.ON_TANK, 0, 12.0, TankIds.SHELL_ENEMY, 0.0, 3300.0)
		)
		v.advance(1.0 / 60.0)
		assert_lte(v.fx.live(), TankParticles.CAP)
	assert_lte(v._cues.size(), TankView.CUE_QUEUE_MAX)
