extends GutTest
## Art polish round 5, the merge's cross-area fixes: hits and repairs strike the armour's top band
## (never the cutaway rooms, where their sparks read as a room's own), and fire burns as tapered
## flame tongues instead of round discs.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _flashes(v: TankView) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var p := v.fx.particles
	for i in p.count:
		if p.kind[i] == TankParticles.Kind.FLASH:
			out.append(p.pos[i])
	return out


## The top of the highest room (hull frame).
func _rooms_top(rig: TankRig) -> float:
	var top := INF
	for room in rig.rooms:
		top = minf(top, room.rect.position.y)
	return top


func test_a_hit_on_the_tank_strikes_the_deck_not_the_rooms() -> void:
	var v := U.view_of(self, TankFixtures.state(3))
	var rig := v.rig
	v.fx.particles.clear()
	var x := v.cam_x + rig.base_pos.x + float(rig.hull_w) * 0.5
	v.apply_cue(
		v.game.state,
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_TANK, 0, 20.0, TankIds.SHELL_ENEMY, 0.0, x)
	)
	var hits := _flashes(v)
	assert_eq(hits.size(), 1)
	var hy := hits[0].y - rig.base_pos.y
	assert_lt(hy, _rooms_top(rig), "above the rooms' band")
	assert_gte(hy, rig.deck_y(hits[0].x - rig.base_pos.x), "on the armour, not above it")


func test_a_repair_welds_on_the_deck() -> void:
	var v := U.view_of(self, TankFixtures.state(3))
	var rig := v.rig
	v.fx.particles.clear()
	v.apply_cue(v.game.state, TankEvents.REPAIRED, {})
	var welds := _flashes(v)
	assert_eq(welds.size(), 6)
	for w in welds:
		assert_lt(w.y - rig.base_pos.y, _rooms_top(rig), "above the rooms' band")


## The opaque width of row `y` of `img` (alpha above a quarter).
func _row_width(img: Image, y: int) -> int:
	var n := 0
	for x in img.get_width():
		if img.get_pixel(x, y).a > 0.25:
			n += 1
	return n


func test_fire_burns_as_tapered_tongues() -> void:
	var img := TankProcTex.flame().get_image()
	assert_gt(img.get_height(), img.get_width(), "taller than wide")
	var h := img.get_height()
	var base_w := _row_width(img, int(h * 0.75))
	assert_gt(base_w, _row_width(img, int(h * 0.3)), "wide at the base")
	assert_gt(_row_width(img, int(h * 0.3)), _row_width(img, int(h * 0.12)), "tapering to a tip")
	var heart := img.get_pixel(img.get_width() / 2, int(h * 0.8))
	var tip := img.get_pixel(img.get_width() / 2, int(h * 0.25))
	assert_gt(heart.g, tip.g, "an amber heart, an orange tip")
	assert_gt(heart.r, 0.85, "warm")
	assert_lt(heart.b, 0.5, "never white")


func test_fire_particles_draw_with_the_tongue() -> void:
	var fx := TankFx.new()
	fx.seed_rng(5)
	add_child_autofree(fx)
	fx.fire_and_smoke("wreck", Vector2(300, 260), 1.0, 1.0, 0.5)
	assert_gt(fx.particles.count_kind(TankParticles.Kind.FIRE), 0)
	assert_eq(fx.add_layer._flame, TankProcTex.flame(), "the additive layer draws tongues")
