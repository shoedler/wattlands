extends GutTest
## Art polish round 6 (effects): hit sparks stay on the outside of the armour, fires burn as a mass of
## seeded tongues (never a mirrored pair), the tank's silhouette shadows the scenery's and wrecks'
## halos and flames behind it, the deck vent's plume is an unbroken stream of wisps, the smoke ring
## pulls ahead of the powder smoke, and a casing glints while the gun's flash lasts.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const DT := 1.0 / 60.0


func after_each() -> void:
	var none: Array[Rect2] = []
	TankLights.set_tank_shadow(none)


func _fx() -> TankFx:
	var fx := TankFx.new()
	fx.seed_rng(61)
	add_child_autofree(fx)
	return fx


func _of(fx: TankFx, k: int) -> Array[int]:
	var out: Array[int] = []
	for i in fx.particles.count:
		if fx.particles.kind[i] == k:
			out.append(i)
	return out


func test_a_floor_removes_a_particle_that_falls_past_it() -> void:
	var p := TankParticles.new()
	p.spawn(TankParticles.Kind.SPARK, Vector2(10, 100), Vector2(0, 60), 2.0, 1.0, 1.0, Color.WHITE)
	p.set_floor(101.0)
	p.spawn(TankParticles.Kind.SPARK, Vector2(20, 100), Vector2(0, 60), 2.0, 1.0, 1.0, Color.WHITE)
	assert_eq(p.floor_y[1], INF, "no floor unless one is set")
	p.step(0.05, 500.0)
	assert_eq(p.count, 1, "the floored spark is gone once below its floor")
	assert_eq(p.pos[0].x, 20.0)


func test_hit_sparks_spray_up_and_never_fall_into_the_rooms() -> void:
	var fx := _fx()
	var at := Vector2(300, 200)
	for away: Vector2 in [Vector2.UP, Vector2(1.0, -0.6).normalized()]:
		fx.particles.clear()
		fx.impact_sparks(at, away)
		for i in _of(fx, TankParticles.Kind.SPARK) + _of(fx, TankParticles.Kind.EMBER):
			assert_lt(fx.particles.vel[i].y, 0.0, "every spark leaves upward off the face")
		var seen := 0
		for _f in 90:
			fx.step(DT)
			for i in fx.particles.count:
				var k := fx.particles.kind[i]
				if k == TankParticles.Kind.SPARK or k == TankParticles.Kind.EMBER:
					seen += 1
					assert_lte(
						fx.particles.pos[i].y, at.y + TankFx.IMPACT_FLOOR, "never below the armour"
					)
		assert_gt(seen, 30, "the spray is still visible for a while")


func test_a_hit_on_the_tank_keeps_its_sparks_above_the_rooms() -> void:
	var v := U.view_of(self, TankFixtures.state(3))
	var rig := v.rig
	var rooms_top := INF
	for room in rig.rooms:
		rooms_top = minf(rooms_top, room.rect.position.y + rig.base_pos.y)
	v.fx.particles.clear()
	var x := v.cam_x + rig.base_pos.x + float(rig.hull_w) * 0.5
	v.apply_cue(
		v.game.state,
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_TANK, 0, 20.0, TankIds.SHELL_ENEMY, 0.0, x)
	)
	for _f in 60:
		v.fx.step(DT)
		for i in v.fx.particles.count:
			if v.fx.particles.kind[i] == TankParticles.Kind.SPARK:
				assert_lt(v.fx.particles.pos[i].y, rooms_top, "no spark streaks into a room")


func test_a_fire_is_a_mass_of_seeded_tongues_leaning_one_way() -> void:
	var fx := _fx()
	var seat := Vector2(400, 220)
	var most := 0
	for _f in 120:
		fx.fire_and_smoke("w1", seat, 0.6, 1.0, DT)
		fx.step(DT)
		most = maxi(most, fx.particles.count_kind(TankParticles.Kind.FIRE))
	assert_gte(most, 5, "a mass of tongues, never a pair")
	var seeds := {}
	for i in _of(fx, TankParticles.Kind.FIRE):
		assert_ne(fx.particles.rot[i], 0.0, "each tongue carries its own seed")
		seeds[fx.particles.rot[i]] = true
		assert_gt(fx.particles.vel[i].x, -1.0, "all lean the same way, downwind")
		assert_lt(absf(fx.particles.pos[i].x - seat.x), TankFx.FIRE_SPREAD + 6.0, "on its seat")
	assert_eq(seeds.size(), _of(fx, TankParticles.Kind.FIRE).size(), "no two tongues alike")
	assert_gt(fx.particles.count_kind(TankParticles.Kind.FLASH), 0, "a glowing bed under them")


func test_seeded_tongues_differ_and_are_not_mirrored_in_turn() -> void:
	# Neighbouring slots used to alternate their mirroring, which paired tongues into a V; now the
	# seed decides, so a run of tongues does not alternate strictly.
	var flips: Array[bool] = []
	for n in 12:
		flips.append(TankFxLayer._hash(1.0 + float(n) * 7.3, 4) < 0.5)
	var alternating := true
	for n in range(1, flips.size()):
		if flips[n] == flips[n - 1]:
			alternating = false
	assert_false(alternating, "the mirroring follows the seed, not the slot")
	assert_lte(TankFxLayer.FLAME_LEAN, 0.45, "tongues stand mostly upright, never fanned out")


func test_fires_behind_the_tank_only_smoke_but_its_own_fire_burns() -> void:
	var fx := _fx()
	var behind: Array[Rect2] = [Rect2(16, 170, 240, 120)]
	fx.shadow = behind
	for _f in 60:
		fx.fire_and_smoke("house", Vector2(70, 213), 0.6, 0.5, DT, TankParticles.PLANE_BACK)
		fx.fire_and_smoke("wreck", Vector2(120, 230), 0.6, 0.5, DT)
	assert_eq(fx.particles.count_kind(TankParticles.Kind.FIRE), 0, "no flames over the deck")
	assert_gt(fx.particles.count_kind(TankParticles.Kind.SMOKE), 0, "the smoke still rises")
	for _f in 30:
		fx.fire_and_smoke("hull_down", Vector2(110, 210), 0.5, 1.0, DT, 0, true)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.FIRE), 0, "the tank's own fire burns")


func test_the_tank_shadows_halos_behind_it_but_not_its_own() -> void:
	var l := TankLights.new()
	add_child_autofree(l)
	var tank: Array[Rect2] = [Rect2(16, 210, 240, 76), Rect2(100, 174, 100, 36)]
	TankLights.set_tank_shadow(tank)
	l.begin()
	l.add(Vector2(72, 213), 37.0, TankPalette.FIRE, 0.5)
	assert_eq(l.count, 0, "a fire's halo behind the deck is dropped")
	l.add(Vector2(400, 213), 37.0, TankPalette.FIRE, 0.5)
	assert_eq(l.count, 1, "one clear of the tank stays")
	l.own = true
	l.add(Vector2(72, 230), 20.0, TankPalette.AMBER, 0.5)
	assert_eq(l.count, 2, "the tank's own room lights stay")
	l.own = false
	var near := TankLights.shadow_keep(Vector2(150, 168), 37.0)
	assert_gt(near, 0.0, "a halo just above the turret is dimmed")
	assert_lt(near, 1.0)
	var none: Array[Rect2] = []
	TankLights.set_tank_shadow(none)
	assert_eq(TankLights.shadow_keep(Vector2(72, 213), 37.0), 1.0, "no shadow, no dimming")


func test_the_rig_casts_its_silhouette_every_frame() -> void:
	var v := U.view_of(self, TankFixtures.state(3))
	var rig := v.rig
	rig.update(v.game.state, {}, DT)
	var s := rig.silhouette()
	var deck := rig.hull_point(Vector2(float(rig.hull_w) * 0.2, rig.deck_y(rig.hull_w * 0.2) + 1.0))
	assert_true(v.fx.in_shadow(deck), "covers the rear deck")
	assert_eq(v.fx.shadow, s, "the effects know it")
	assert_eq(TankLights.tank_shadow, s, "so do the light layers")
	assert_eq(TankLights.shadow_keep(deck, 30.0), 0.0, "a halo there is dropped")
	assert_false(v.lights.own, "the bracket for the tank's own lights is closed")
	var muzzle := rig.muzzle_layer()
	assert_false(v.fx.in_shadow(muzzle), "the gun's own flash and tracer stay clear of it")
	assert_eq(TankLights.shadow_keep(muzzle, 20.0), 1.0)


func test_the_vent_plume_is_an_unbroken_stream_of_wisps() -> void:
	var fx := _fx()
	var mouth := Vector2(250, 190)
	var gaps := 0
	for f in 180:
		# A stroke about every 0.9 s (a steady riding cadence).
		if f % 54 == 0:
			fx.steam_plume(mouth)
		fx.step(DT)
		if f > 10 and fx.particles.count_kind(TankParticles.Kind.STEAM) < 3:
			gaps += 1
	assert_eq(gaps, 0, "the strokes overlap into one plume")
	for i in _of(fx, TankParticles.Kind.STEAM):
		assert_ne(fx.particles.rot[i], 0.0, "seeded: drawn as a wisp, not a round disc")
		assert_eq(fx.particles.plane[i], 0, "on the world plane")


func test_the_smoke_ring_pulls_ahead_of_the_powder_smoke_and_holds() -> void:
	var fx := _fx()
	var mz := Vector2(300, 150)
	fx.muzzle_blast(mz, Vector2.RIGHT, 0.6, false)
	for _f in 12:
		fx.step(DT)
	var ring := _of(fx, TankParticles.Kind.RING)
	assert_eq(ring.size(), 1)
	var rx := fx.particles.pos[ring[0]].x
	for i in _of(fx, TankParticles.Kind.SMOKE):
		assert_lt(fx.particles.pos[i].x, rx, "the ring is ahead of the powder smoke")
	assert_gt(rx - mz.x, 15.0, "it has left the muzzle")
	assert_gte(TankFx.RING_TTL * TankFxLayer.RING_HOLD, 0.35, "a ring through a burst's frames")


func test_a_fresh_casing_glints_in_the_flash() -> void:
	var fx := _fx()
	fx.brass(Vector2(125, 185), Vector2(-0.8, -1.0).normalized())
	var ids := _of(fx, TankParticles.Kind.BRASS)
	assert_eq(ids.size(), 1)
	assert_gte(fx.particles.ttl[ids[0]], 0.35, "still in the air 0.3 s after the shot")
	assert_gte(TankFxLayer.BRASS_FLASH_S, 0.12, "it glints from the first frames of the burst")
	var glints := 0
	for n in 64:
		glints += 1 if TankFxLayer.glints(TAU * float(n) / 64.0) else 0
	assert_gt(glints, 6, "a glint each half turn while it tumbles")
	assert_lt(glints, 32, "a glint, not a steady shine")
