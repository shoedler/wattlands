extends GutTest
## The world tags never lie on the hero (brief 3.6, the critique's N1): for every variant (crews
## 1-4), both facings, the mission frame and free roam in both travel directions, every SURGE tag
## (shooters ahead, behind and pressed against the hull's front and rear), the speed plate, the
## halt line's and the turn marker's posts and the pursuers' edge arrows keep TankHudTags.TAG_CLEAR
## px outside the tank's drawn rects, and no pointer pixel is painted on the tank.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _enemy(s: TankState, id: int, type: String, x: float, side: int, lane: int) -> void:
	var def := s.content.enemy_def(type)
	var e := TankEnemyState.new()
	e.id = id
	e.code = TankIds.enemy_code(type)
	e.w = int(def["size_px"][0])
	e.h = int(def["size_px"][1])
	e.hp_max = 50.0
	e.hp = 40.0
	e.x_px = x
	e.side = side
	e.lane = lane
	e.mode = TankIds.EM_TELEGRAPH
	e.telegraph_s = 2.0
	s.enemies.append(e)


## Shooters pressed against the hull's rear (the rules' pursuer hold, -8 px) and its front (a held
## place re-reserved after a turn), plus whatever the fixture has, every one telegraphing.
func _crowd(s: TankState) -> void:
	var h := s.hull
	_enemy(s, 901, TankIds.ENEMY_LIGHT, h.x_px - 91.0 + 8.0, -1, 0)
	_enemy(s, 902, TankIds.ENEMY_LIGHT, h.x_px + float(h.hull_w) - 8.0, 1, 0)
	_enemy(s, 903, TankIds.ENEMY_MEDIUM, h.x_px - 110.0 + 8.0, -1, 1)
	for e in s.enemies:
		e.telegraph_s = 2.0


func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crew in [1, 2, 3, 4]:
		out.append({"what": "crew %d mission" % crew, "s": U.fixture("state", crew)})
		for dir in [TankIds.DIR_RIGHT, TankIds.DIR_LEFT]:
			var what := "crew %d roam dir %d" % [crew, dir]
			out.append({"what": what, "s": U.roam_state(crew, dir)})
	return out


func _check(tags: TankHudTags, body: Array[Rect2], what: String) -> int:
	var lay: Dictionary = tags.m["layout"]
	var n := 0
	var sr: Rect2 = lay["speed"]
	if sr.size != Vector2.ZERO:
		assert_true(TankHudTags.clear_of(sr, body), "%s: the speed plate" % what)
	for pl: Dictionary in lay["posts"]:
		var gy := float(tags.m["ground"])
		assert_true(
			TankHudTags.clear_of(TankHudTags.post_rect(pl["x"], gy), body), "%s: post" % what
		)
		assert_true(TankHudTags.clear_of(pl["plate"], body), "%s: post plate" % what)
	for wl: Dictionary in lay["warn"]:
		n += 1
		assert_true(TankHudTags.clear_of(wl["rect"], body), "%s: SURGE tag %s" % [what, wl["rect"]])
		var on := 0
		for p: Vector2i in wl["pointer"]:
			for b in body:
				if b.has_point(Vector2(p) + Vector2(0.5, 0.5)):
					on += 1
		assert_eq(on, 0, "%s: no pointer pixel on the tank" % what)
		assert_gt((wl["pointer"] as Array).size(), 0, "%s: a pointer to the shooter" % what)
	for p2: Vector2 in lay["edge"]:
		assert_true(TankHudTags.clear_of(Rect2(p2 - Vector2(1, 1), Vector2(6, 9)), body), what)
	return n


func test_no_world_tag_lies_on_the_tank_for_any_variant_facing_or_direction() -> void:
	for c: Dictionary in _cases():
		var s: TankState = c["s"]
		_crowd(s)
		var g: TankGame = autofree(U.roam_game(s) if s.roam.active else U.make_game(s))
		var v := U.make_view(self, g)
		var tags := TankHudTags.new().setup(g, TankHud.LAYOUT["tags"]) as TankHudTags
		add_child_autofree(tags)
		for facing in [TankIds.FACE_RIGHT, TankIds.FACE_LEFT]:
			s.hull.facing = facing
			v.advance(1.0 / 60.0)
			tags.refresh()
			var body: Array[Rect2] = v.hud_tank_rects()
			var what := "%s facing %d" % [c["what"], facing]
			var n := _check(tags, body, what)
			assert_gte(n, 3, "%s: the crowd's tags laid out" % what)


func test_posts_and_the_speed_plate_step_off_the_tank_wherever_they_stand() -> void:
	var s := U.fixture("state", 3)
	var g: TankGame = autofree(U.make_game(s))
	var v := U.make_view(self, g)
	var body: Array[Rect2] = v.hud_tank_rects()
	var gy := v.hud_ground_y()
	var cv := v.canvas
	var size := TankHudTags.post_size("HALT LINE", "12 m")
	var x := 0.0
	while x <= cv.x:
		var pl := TankHudTags.post_layout(x, size, gy, cv, body)
		assert_true(
			TankHudTags.clear_of(TankHudTags.post_rect(pl["x"], gy), body), "post at %d" % x
		)
		assert_true(TankHudTags.clear_of(pl["plate"], body), "its plate at %d" % x)
		x += 12.0
	var rear := v.hud_tank_point("rear")
	for mirrored in [false, true]:
		var sr := TankHudTags.speed_rect(rear, 60.0, mirrored, body)
		assert_true(TankHudTags.clear_of(sr, body), "the speed plate under the tracks")


func test_a_pursuer_showing_a_sliver_gets_an_edge_arrow() -> void:
	var s := U.fixture("state", 1)
	s.enemies.clear()
	_enemy(s, 901, TankIds.ENEMY_LIGHT, s.hull.x_px - 91.0 + 8.0, -1, 0)
	var g: TankGame = autofree(U.make_game(s))
	U.make_view(self, g)
	var tags := TankHudTags.new().setup(g, TankHud.LAYOUT["tags"]) as TankHudTags
	add_child_autofree(tags)
	tags.refresh()
	var edge: Array = tags.m["layout"]["edge"]
	assert_eq(edge.size(), 1, "one arrow for the pursuer at the tail")
	assert_lt((edge[0] as Vector2).x, 20.0, "on the left edge")
