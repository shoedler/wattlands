extends GutTest
## The free-roam HUD (brief 2.10, 3.6; 4 "the HUD's controls for crews 1-4 in mission and roam"): the
## map strip across the top instead of the mission plate, the board (time left, points, kills) with
## the hull plate under it without its kills, toasts under the strip, the roam help, each Control fed
## from the state; the board's clock through the drive-out, time up and overtime; the strip's map,
## tank, patrols and strongpoints; the turn marker at the turning place ahead.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const STRINGS := "res://content/tank/strings.csv"


func _game(crew: int, dir: int = TankIds.DIR_RIGHT, content: String = "roam_30") -> TankGame:
	var s := U.roam_state(crew, dir, -1.0, 7, content)
	return autofree(U.roam_game(s, content))


func _controls(g: TankGame) -> Dictionary:
	var hs := TankHud.spec(g)
	var out := {}
	for c: Dictionary in hs.controls:
		var ctl := c["control"] as TankHudCtl
		autofree(ctl)
		out[ctl.get_script().get_global_name()] = {"ctl": ctl, "at": c["at"]}
	out["_spec"] = hs
	return out


static func _keys() -> Dictionary:
	var out := {}
	var f := FileAccess.open(STRINGS, FileAccess.READ)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2:
			out[row[0]] = row[1]
	return out


func test_every_crew_gets_the_roam_layout() -> void:
	for crew in [1, 2, 3, 4]:
		var g := _game(crew)
		var got := _controls(g)
		var hs: HudSpec = got["_spec"]
		for k: String in ["TankHudRoamStrip", "TankHudBoard", "TankHudHull", "TankHudMine"]:
			assert_true(got.has(k), "crew %d: %s" % [crew, k])
		for k2: String in ["TankHudCrew", "TankHudTags"]:
			assert_true(got.has(k2), "crew %d: %s" % [crew, k2])
		assert_false(got.has("TankHudMission"), "no mission plate in free roam")
		assert_false(got.has("TankHudBoss"), "no Behemoth in free roam")
		assert_eq(got["TankHudRoamStrip"]["at"], TankHud.LAYOUT["roam_strip"])
		assert_eq(got["TankHudBoard"]["at"], TankHud.LAYOUT["roam_board"])
		assert_eq(got["TankHudHull"]["at"], TankHud.LAYOUT["roam_hull"])
		assert_false((got["TankHudHull"]["ctl"] as TankHudHull).show_kills, "the board shows kills")
		assert_eq(hs.toast_area, TankHud.LAYOUT["roam_toasts"])
		assert_eq(hs.widgets.size(), 0, "no kit widgets")
		assert_true(hs.shows_power)
	var mission := _controls(autofree(U.make_game(U.fixture("state", 3))))
	assert_true(mission.has("TankHudMission"), "missions keep their plate")
	assert_false(mission.has("TankHudRoamStrip"))


func test_the_roam_help_points_at_its_plates_with_keys_in_the_strings() -> void:
	var got := _controls(_game(3))
	var hs: HudSpec = got["_spec"]
	var k := _keys()
	assert_between(hs.help.size(), 3, 6)
	for e: Dictionary in hs.help:
		var key := str(e["text"])
		assert_true(k.has(key), key + " in strings.csv")
		var inside := false
		for c: Dictionary in hs.controls:
			if c["control"] is TankHudTags:
				continue
			inside = inside or Rect2(c["at"] as Rect2i).has_point(e["arrow_to"])
		assert_true(inside, key + " points at a plate")


func test_the_strip_is_fed_the_map_the_tank_and_the_contacts() -> void:
	var g := _game(3, TankIds.DIR_LEFT)
	var strip: TankHudRoamStrip = _controls(g)["TankHudRoamStrip"]["ctl"]
	strip.refresh()
	var s := g.state
	assert_eq(strip.length_m, s.roam_map.length_m)
	assert_eq(strip.zones.size(), s.roam_map.zones.size())
	assert_eq(strip.profile.size(), 96)
	assert_almost_eq(strip.tank_m, s.roam.map_m, 0.01)
	assert_eq(strip.tank_dir, -1)
	assert_eq(strip.patrols.size(), 3, "the light, the medium and the destroyer")
	assert_eq(strip.strongpoints.size(), s.roam_map.strongpoints.size())
	assert_eq(strip.title, "ROAM")
	assert_eq(strip.subtitle, "30 MIN")
	s.roam.engaging = true
	strip.refresh()
	assert_eq(strip.subtitle, "ENGAGE")
	s.roam.strong_back_s[0] = 100.0
	strip.refresh()
	assert_false(bool(strip.strongpoints[0]["alive"]), "a fallen strongpoint is crossed out")
	var behind := strip.patrols[2]
	assert_gt(behind, s.roam.map_m, "going west, the destroyer behind is east of the tank")


func test_the_strips_contacts_sit_under_the_zone_names_on_the_line_row() -> void:
	var g := _game(3, TankIds.DIR_RIGHT)
	var strip: TankHudRoamStrip = _controls(g)["TankHudRoamStrip"]["ctl"]
	strip.refresh()
	var names := strip.label_rows()
	var top := strip.marker_y() - 1.0
	assert_gte(top, names.y, "the markers' backing starts below the names")
	assert_lte(strip.marker_y() + 6.0, strip.map_rect().end.y, "and stays inside the map")


func test_the_strips_screen_bracket_never_crosses_the_zone_names() -> void:
	for dir in [TankIds.DIR_RIGHT, TankIds.DIR_LEFT]:
		var g := _game(3, dir)
		var strip: TankHudRoamStrip = _controls(g)["TankHudRoamStrip"]["ctl"]
		strip.refresh()
		var box := strip.view_box()
		assert_gte(box.position.y, strip.label_rows().y, "dir %d: under the names" % dir)
		assert_lte(box.end.y, strip.map_rect().end.y, "dir %d: inside the map" % dir)
		assert_gt(box.size.x, 0.0)


func test_the_board_counts_down_to_time_up_and_shows_overtime() -> void:
	var g := _game(3, TankIds.DIR_RIGHT, "roam_20")
	var board: TankHudBoard = _controls(g)["TankHudBoard"]["ctl"]
	var s := g.state
	s.score.kills = [0, 2, 1, 0, 1, 0, 0]
	board.refresh()
	assert_almost_eq(board.left_s, 900.0 - 400.0, 0.01, "the roam's min_s less its elapsed")
	assert_eq(board.points, 120)
	assert_eq(board.kills, 4)
	assert_false(board.overtime)
	s.seg.seg = TankIds.SEG_DEPOT
	s.seg.elapsed_s = 100.0
	board.refresh()
	assert_almost_eq(board.left_s, 200.0 + 900.0, 0.01, "the drive-out counts toward the ride")
	s.seg.seg = TankIds.SEG_ROAM
	s.roam.time_up = true
	s.roam.overtime = true
	board.refresh()
	assert_eq(board.left_s, 0.0)
	assert_true(board.overtime, "OVERTIME while a fight finishes")


func test_the_turn_marker_stands_at_the_turning_place_ahead() -> void:
	var g := _game(3)
	var tags: TankHudTags = _controls(g)["TankHudTags"]["ctl"]
	var s := g.state
	tags.refresh()
	assert_eq(tags.turn_dir, 0, "none in the middle of the road")
	s.roam.map_m = s.roam_map.hi_m - 40.0
	tags.refresh()
	assert_eq(tags.turn_dir, -1, "the arrow points back the way the tank will go")
	var want := TankRoam.travel_x(s, s.roam_map.length_m - TankWorldDraw.TURN_BARRIER_M)
	assert_almost_eq(tags.turn_x, want, 0.01)
	s.roam.turn_s = 5.0
	tags.refresh()
	assert_eq(tags.turn_dir, 0, "cleared while turning")


func test_the_roam_hud_paints_on_every_canvas() -> void:
	for crew in [1, 4]:
		for dir in [TankIds.DIR_RIGHT, TankIds.DIR_LEFT]:
			var g := _game(crew, dir)
			var got := _controls(g)
			for k: String in got:
				if k == "_spec":
					continue
				var ctl: TankHudCtl = got[k]["ctl"]
				add_child_autofree(ctl)
				ctl.size = Vector2((got[k]["at"] as Rect2i).size) * 2.0
				ctl.refresh()
				ctl.queue_redraw()
	await wait_frames(2)
	pass_test("painted without errors")
