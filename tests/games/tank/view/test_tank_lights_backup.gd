extends GutTest
## Tank 0.3.1 (Simon's feedback on v3): both searchlights burn only while the Lights seat is manned
## and powered (in band), with the 0.4 s fade, the 2 s hold and a standby glow on their lenses;
## unpowered, the rooms fall back to their dim backup lighting (a 0.5 s fade, the same hold); the
## headlight stays on.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


static func _searchlights(v: TankView) -> int:
	var n := 0
	for b in TankLightDraw.beams(v, v.game.state):
		if not bool(b["head"]):
			n += 1
	return n


static func _has_head(v: TankView) -> bool:
	for b in TankLightDraw.beams(v, v.game.state):
		if bool(b["head"]):
			return true
	return false


func test_an_empty_lights_seat_leaves_both_searchlights_off_and_the_backup_on() -> void:
	for crew in [1, 3]:
		var v := U.view_of(self, U.fixture("state", crew))
		U.run(v, 3)
		assert_null(v.rider_on("lights"), "crew %d: nobody on Lights" % crew)
		assert_eq(_searchlights(v), 0, "crew %d: neither searchlight, the rear one too" % crew)
		assert_true(_has_head(v), "crew %d: the headlight stays on" % crew)
		assert_false(v.body.search_lit or v.body.rear_lit, "their lenses dark")
		assert_eq(TankLightDraw.standby_lenses(v).size(), 2, "a standby glow on both lenses")
		assert_eq(v.backup_level, 1.0, "crew %d: the rooms on backup lighting" % crew)
		assert_eq(v.body.backup, 1.0)


func test_a_powered_lights_seat_lights_both_and_unpowered_puts_them_out_after_the_hold() -> void:
	var s := U.fixture("state", 4)
	var arc := s.station(TankIds.ENGINE_ARC) as TankArcState
	arc.lit = true
	var v := U.view_of(self, s)
	assert_eq(_searchlights(v), 2, "the turret and the rear searchlight")
	assert_true(v.body.search_lit and v.body.rear_lit, "both lenses lit")
	assert_eq(v.backup_level, 0.0, "the warm lamps")
	arc.lit = false
	U.run(v, 108)
	assert_eq(_searchlights(v), 2, "held 1.8 s after the rider drops out of band")
	assert_eq(v.backup_level, 0.0, "the rooms too")
	U.run(v, 24)
	assert_lt(v.search_level, 0.6, "the searchlights fading")
	assert_between(v.backup_level, 0.1, 0.9, "the backup lighting coming in")
	U.run(v, 30)
	assert_eq(_searchlights(v), 0, "both out")
	assert_false(v.body.rear_lit, "the rear lens dark")
	assert_eq(v.backup_level, 1.0, "the backup lighting on")
	arc.lit = true
	U.run(v, 33)
	assert_eq(v.search_level, 1.0, "back on")
	assert_eq(v.backup_level, 0.0, "the warm lamps back")


func test_a_breakdown_or_a_stalled_arc_puts_the_searchlights_out() -> void:
	var s := U.fixture("state", 4)
	var arc := s.station(TankIds.ENGINE_ARC) as TankArcState
	arc.lit = true
	var v := U.view_of(self, s)
	assert_true(v.lights_powered(s))
	arc.stalled = true
	assert_false(v.lights_powered(s), "a stalled generator: unpowered")
	arc.stalled = false
	s.hull.breakdown = true
	assert_false(v.lights_powered(s), "a breakdown: unpowered")
	U.run(v, 30)
	assert_eq(_searchlights(v), 0, "no hold in a breakdown")


func test_the_backup_lighting_dims_the_rooms_without_blacking_them_out() -> void:
	var c := TankBody.backup_tint(1.0)
	assert_eq(TankBody.backup_tint(0.0), Color.WHITE, "no backup: untouched")
	assert_lt(c.get_luminance(), 0.75, "dimmer")
	assert_gt(c.get_luminance(), 0.4, "still readable, not black")
	assert_gt(c.r, c.b, "a little red")
	var dt := 0.05
	var lh := Vector2(1.0, TankView.SEARCH_HOLD_S)
	var t := 0.0
	while t < 2.25 - 1e-6:
		lh = TankView.fade(lh.x, lh.y, false, dt, TankView.BACKUP_FADE_S, TankView.SEARCH_HOLD_S)
		t += dt
	assert_almost_eq(lh.x, 0.5, 0.06, "the backup fades over 0.5 s after the 2 s hold")
	var r := Rect2(100, 150, 40, 30)
	assert_true(r.has_point(TankLightDraw.emergency_lamp(r)), "the emergency lamp in its room")


func test_the_rear_lens_overlay_ships() -> void:
	var rig := TankRig.shared()
	assert_not_null(rig.lit_rear_tex, "the rear searchlight's lit lens")
	var rs := rig.detail("searchlight_rear")
	var at := TankRig.lens_of(rs)
	var box := Rect2(rig.lit_rear_at, Vector2(rig.lit_rear_tex.get_size())).grow(3.0)
	assert_true(box.has_point(at), "over the rear searchlight's lens")
	assert_lt(rig.lit_tex.get_width() * rig.lit_tex.get_height(), 64, "the turret's lens only")
