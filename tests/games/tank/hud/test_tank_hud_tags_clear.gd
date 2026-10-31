extends GutTest
## The world tags in v4's split screen: for every crew, the mission frame and free roam in both travel
## directions, the speed plate, the posts and every SURGE tag keep TankHudTags.TAG_CLEAR px outside the
## tank's drawn rects, no pointer pixel lies on the tank, a far shooter's tag stands in the far panel
## clear of the PiP, the post pins to the near panel's edge and the shell's tag sits beside the seam's
## range plate. Far rects are TankFarMap's until the view places far kinds on the far panel.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const X := preload("res://tests/games/tank/hud/tank_hud_fixtures.gd")
const CANVASES: Array[Vector2] = [Vector2(960, 540), Vector2(852, 480), Vector2(1280, 680)]


class FakeView:
	extends RefCounted
	var enemy := Rect2()
	var boss := Rect2()

	func hud_world_x(x: float) -> float:
		return x

	func hud_enemy_rect(_id: int) -> Rect2:
		return enemy

	func hud_boss_rect() -> Rect2:
		return boss

	func hud_mirrored() -> bool:
		return false


func _far(s: TankState, id: int, type: String, range_m: float, lane: int) -> TankEnemyState:
	var e := TankEnemyState.new()
	e.id = id
	e.code = TankIds.enemy_code(type)
	e.hp_max = 50.0
	e.hp = 40.0
	e.side = 1
	e.lane = lane
	e.range_m = range_m
	e.hold_m = range_m
	e.mode = TankIds.EM_TELEGRAPH
	e.telegraph_s = 2.0
	s.enemies.append(e)
	return e


## Far shooters across the field, every one telegraphing.
func _crowd(s: TankState) -> void:
	s.enemies.clear()
	_far(s, 901, TankIds.ENEMY_LIGHT, 800.0, 0)
	_far(s, 902, TankIds.ENEMY_HEAVY, 1640.0, 1)
	_far(s, 903, TankIds.ENEMY_DESTROYER, 2200.0, 2)


func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crew in [1, 2, 3, 4]:
		out.append({"what": "crew %d mission" % crew, "s": U.fixture("state", crew)})
		for dir in [TankIds.DIR_RIGHT, TankIds.DIR_LEFT]:
			var what := "crew %d roam dir %d" % [crew, dir]
			out.append({"what": what, "s": U.roam_state(crew, dir)})
	return out


func _tags(g: TankGame) -> TankHudTags:
	var tags := TankHudTags.new().setup(g, TankHud.LAYOUT["tags"]) as TankHudTags
	add_child_autofree(tags)
	return tags


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
	return n


func test_no_world_tag_lies_on_the_tank_for_any_crew_or_direction() -> void:
	for c: Dictionary in _cases():
		var s: TankState = c["s"]
		_crowd(s)
		var g: TankGame = autofree(U.roam_game(s) if s.roam.active else U.make_game(s))
		var v := U.make_view(self, g)
		var tags := _tags(g)
		v.advance(1.0 / 60.0)
		tags.refresh()
		var body: Array[Rect2] = v.hud_tank_rects()
		assert_gte(_check(tags, body, str(c["what"])), 3, "%s: the crowd's tags" % c["what"])


func test_a_far_shooters_tag_stands_in_the_far_panel_clear_of_the_pip() -> void:
	for dir in [TankIds.DIR_RIGHT, TankIds.DIR_LEFT]:
		var s := U.roam_state(3, dir)
		_crowd(s)
		var g: TankGame = autofree(U.roam_game(s))
		U.make_view(self, g)
		var tags := _tags(g)
		tags.refresh()
		var panels: Dictionary = tags.m["panels"]
		var far: Rect2 = panels["far"]
		var pip: Rect2 = panels["pip"]
		var rects: Array = tags.m["layout"]["warn"]
		for i in rects.size():
			var ri: Rect2 = rects[i]["rect"]
			assert_true(far.encloses(ri), "dir %d: %s inside %s" % [dir, ri, far])
			assert_false(ri.intersects(pip), "dir %d: clear of the PiP" % dir)
			for j in range(i + 1, rects.size()):
				var rj: Rect2 = rects[j]["rect"]
				assert_false(ri.intersects(rj), "dir %d: tags %d and %d overlap" % [dir, i, j])


func test_without_a_view_a_far_enemy_stands_where_the_map_says() -> void:
	var s := TankFixturesV4.make("far_duel", 3)
	var e := s.enemy(21)
	var g := TankHudGeom.make(s, null)
	var at := g.far_sprite_rect(TankIds.ENEMY_HEAVY, e.range_m, e.lane)
	assert_eq(g.enemy_rect(e), at, "no view: TankFarMap")
	var far: Rect2 = g.panels()["far"]
	assert_true(far.has_point(at.get_center()), "on the far panel")
	var x := TankFarMap.range_x(e.range_m, far.size.x) + far.position.x
	assert_almost_eq(at.get_center().x, x, 0.01, "the foot's x from the near-side edge")
	var foot := TankFarMap.foot_y(e.range_m, e.lane)
	assert_almost_eq(at.end.y, foot, 0.01, "standing on the foot's line")


func test_a_view_that_places_far_kinds_wins_over_the_map() -> void:
	var s := TankFixturesV4.make("far_duel", 3)
	var e := s.enemy(21)
	var v := FakeView.new()
	var g := TankHudGeom.make(s, v)
	var mapped := g.far_sprite_rect(TankIds.ENEMY_HEAVY, e.range_m, e.lane)
	v.enemy = Rect2(700, 300, 100, 50)
	assert_eq(g.enemy_rect(e), v.enemy, "the view's rect on the far panel")
	v.enemy = Rect2(-3000, 300, 100, 50)
	assert_eq(g.enemy_rect(e), mapped, "off the panel: the map (before the view moves far kinds)")
	v.enemy = Rect2()
	assert_eq(g.enemy_rect(e), mapped, "not drawn: the map")
	var b := TankFixturesV4.make("boss_far", 3)
	var gb := TankHudGeom.make(b, v)
	var mb := gb.far_sprite_rect(TankHudGeom.BOSS_KIND, b.boss.range_m, 0)
	assert_eq(gb.boss_rect(), mb, "the Behemoth on the map")
	v.boss = Rect2(650, 200, 300, 148)
	assert_eq(gb.boss_rect(), v.boss, "and on the view's far rect")


func test_a_far_kind_in_the_old_frame_keeps_its_rules_px() -> void:
	var s := U.fixture("state", 1)
	var old := s.enemies[0]
	assert_eq(old.range_m, 0.0, "TankFixtures' states are in the old frame")
	assert_false(TankHudGeom.in_far_frame(old))
	var near := TankFixturesV4.make("near_ambush", 1)
	assert_false(TankHudGeom.in_far_frame(near.enemy(41)), "a near kind has no range")
	assert_true(TankHudGeom.in_far_frame(TankFixturesV4.make("far_duel", 1).enemy(21)))


func test_the_far_rects_hold_on_every_canvas_and_mirror_with_the_world() -> void:
	for cv in CANVASES:
		var s := TankFixturesV4.make("far_duel", 3)
		var g := TankHudGeom.make(s, null, cv)
		var far: Rect2 = g.panels()["far"]
		for e in s.enemies:
			var r := g.enemy_rect(e)
			assert_true(far.has_point(r.get_center()), "%s: enemy %d's middle" % [cv, e.id])
			var pip_end := TankFarMap.PIP_Y + TankFarMap.PIP_H
			assert_gt(r.position.y, pip_end, "%s: enemy %d under the PiP" % [cv, e.id])
	var west := TankFixturesV4.make("roam_west", 3)
	var gw := TankHudGeom.make(west, null)
	var fw: Rect2 = gw.panels()["far"]
	assert_eq(fw.position.x, 0.0, "west: the far panel on the left")
	var nearer := gw.enemy_rect(west.enemy(302))
	var farther := gw.enemy_rect(west.enemy(301))
	assert_gt(nearer.get_center().x, farther.get_center().x, "west: range runs left from the seam")
	assert_true(fw.has_point(farther.get_center()))


func test_the_post_pins_to_the_near_panels_edge_not_the_canvas() -> void:
	var s := U.fixture("state", 3)
	var g: TankGame = autofree(U.make_game(s))
	var v := U.make_view(self, g)
	var body: Array[Rect2] = v.hud_tank_rects()
	var gy := v.hud_ground_y()
	var size := TankHudTags.post_size("HALT LINE", "400 m")
	var near: Rect2 = TankFarMap.panels(Vector2(960, 540), false)["near"]
	var pl := TankHudTags.post_layout(5000.0, size, gy, near, body)
	assert_true(bool(pl["pinned"]), "a far line is pinned")
	assert_lte(float(pl["x"]), near.end.x - TankHudTags.PIN_MARGIN, "at the near panel's edge")
	assert_lte((pl["plate"] as Rect2).end.x, near.end.x, "its plate inside the near panel")
	assert_true(TankHudTags.clear_of(pl["plate"], body), "and clear of the tank")


func test_on_the_narrowest_canvas_the_post_stays_off_the_far_panel() -> void:
	var s := U.fixture("state", 3)
	var g: TankGame = autofree(U.make_game(s))
	var v := U.make_view(self, g, Vector2(852, 480))
	var body: Array[Rect2] = v.hud_tank_rects()
	var panels := TankFarMap.panels(Vector2(852, 480), false)
	var near: Rect2 = panels["near"]
	var seam: Rect2 = panels["seam"]
	var size := TankHudTags.post_size("HALT LINE", "400 m")
	var pl := TankHudTags.post_layout(5000.0, size, v.hud_ground_y(), near, body)
	assert_true(
		TankHudTags.clear_of(TankHudTags.post_rect(pl["x"], v.hud_ground_y()), body), "the post"
	)
	assert_true(TankHudTags.clear_of(pl["plate"], body), "the plate")
	assert_lte((pl["plate"] as Rect2).end.x, seam.end.x, "at worst its plate overlaps the seam")


func test_posts_and_the_speed_plate_step_off_the_tank_wherever_they_stand() -> void:
	var s := U.fixture("state", 3)
	var g: TankGame = autofree(U.make_game(s))
	var v := U.make_view(self, g)
	var body: Array[Rect2] = v.hud_tank_rects()
	var gy := v.hud_ground_y()
	var near: Rect2 = TankFarMap.panels(v.canvas, false)["near"]
	var size := TankHudTags.post_size("HALT LINE", "12 m")
	var x := 0.0
	while x <= v.canvas.x:
		var pl := TankHudTags.post_layout(x, size, gy, near, body)
		assert_true(
			TankHudTags.clear_of(TankHudTags.post_rect(pl["x"], gy), body), "post at %d" % x
		)
		assert_true(TankHudTags.clear_of(pl["plate"], body), "its plate at %d" % x)
		x += 12.0
	var rear := v.hud_tank_point("rear")
	for mirrored in [false, true]:
		var sr := TankHudTags.speed_rect(rear, 60.0, mirrored, body, near)
		assert_true(TankHudTags.clear_of(sr, body), "the speed plate under the tracks")
		assert_true(near.encloses(sr), "the speed plate in the near panel")


func test_the_speed_plate_stays_in_a_mirrored_near_panel() -> void:
	var near: Rect2 = TankFarMap.panels(Vector2(960, 540), true)["near"]
	var body: Array[Rect2] = []
	var sr := TankHudTags.speed_rect(Vector2(340, 385), 60.0, true, body, near)
	assert_gte(sr.position.x, near.position.x, "not over the seam")


func test_the_tags_have_no_edge_arrows_or_bent_pointers() -> void:
	var s := U.fixture("state", 1)
	s.enemies.clear()
	_far(s, 901, TankIds.ENEMY_LIGHT, 900.0, 0)
	var g: TankGame = autofree(U.make_game(s))
	U.make_view(self, g)
	var tags := _tags(g)
	tags.refresh()
	var lay: Dictionary = tags.m["layout"]
	assert_false(lay.has("edge"), "v4: nothing comes from behind")
	var wl: Dictionary = lay["warn"][0]
	assert_false(wl.has("up"), "the tag never sits on the road under the tank")
	var pts: Array = wl["pointer"]
	var first: Vector2i = pts[0]
	var last: Vector2i = pts[-1]
	for p: Vector2i in pts:
		if p != first:
			var along := Vector2(last - first).normalized().dot(Vector2(p - first).normalized())
			assert_gt(along, 0.95, "a straight pointer")


func test_an_evadable_shell_gets_a_tag_beside_the_seam_plate() -> void:
	var s := TankFixturesV4.make("far_duel", 3)
	var g: TankGame = autofree(X.game(s))
	var tags := _tags(g)
	tags.refresh()
	var shell: Rect2 = tags.m["layout"]["shell"]
	var panels: Dictionary = tags.m["panels"]
	assert_ne(shell.size, Vector2.ZERO, "the shell's tag")
	assert_eq(shell.position.y, TankHudTags.SEAM_PLATE_Y, "at the seam plate's height")
	assert_true((panels["far"] as Rect2).encloses(shell), "in the far panel")
	var seam_x := (panels["seam"] as Rect2).get_center().x
	assert_gte(shell.position.x, seam_x + TankHudTags.SEAM_PLATE_W * 0.5, "clear of the plate")
	assert_false(shell.intersects(panels["pip"]), "clear of the PiP")
	for wl: Dictionary in tags.m["layout"]["warn"]:
		assert_false((wl["rect"] as Rect2).intersects(shell), "a shooter's tag steps aside")
	tags.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(tags.draws, 0)


func test_the_shells_tag_mirrors_with_the_panels() -> void:
	var panels := TankFarMap.panels(Vector2(960, 540), true)
	var r := TankHudTags.shell_rect(panels["seam"], panels["far"], Vector2(100, 26))
	assert_true((panels["far"] as Rect2).encloses(r), "west: still in the far panel")
	var seam_x := (panels["seam"] as Rect2).get_center().x
	assert_lte(r.end.x, seam_x - TankHudTags.SEAM_PLATE_W * 0.5, "left of the plate")


func test_no_shell_tag_without_an_evadable_incoming_shell() -> void:
	var s := TankFixturesV4.make("advance_far", 3)
	var g: TankGame = autofree(X.game(s))
	var tags := _tags(g)
	tags.refresh()
	assert_eq((tags.m["layout"]["shell"] as Rect2).size, Vector2.ZERO, "only our own shell flies")
	assert_true(TankHudModel.evadable_shell(s).is_empty())


func test_the_secondaries_dial_shows_only_with_a_near_threat() -> void:
	var s := TankFixturesV4.make("bow_duel", 3)
	var g: TankGame = autofree(X.game(s))
	var tags := _tags(g)
	tags.refresh()
	assert_true(tags.m.has("sec"), "manned, firing, a near threat alive")
	assert_true(TankHudTags.near_threat(s))
	for e in s.enemies:
		e.mode = TankIds.EM_DEAD
	tags.refresh()
	assert_false(tags.m.has("sec"), "the guns may run on, but nothing near: no dial")
	assert_false(TankHudTags.near_threat(s))
	_far(s, 950, TankIds.ENEMY_MEDIUM, 1200.0, 0)
	tags.refresh()
	assert_false(tags.m.has("sec"), "a far enemy is not their business")
