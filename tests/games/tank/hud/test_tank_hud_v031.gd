extends GutTest
## Tank 0.3.1 (Simon's feedback on v3): the two angle meters (the gun's arc, the Secondaries' dial)
## fade in and out with a hold so they no longer flash, and my numbers show the local rider's heart
## rate (Telemetry.heart_rate_bpm) only while a sensor sends one, fitted into the header.

const X := preload("res://tests/games/tank/hud/tank_hud_fixtures.gd")
const D := preload("res://src/games/tank/hud/tank_hud_draw.gd")


func _place(c: TankHudCtl) -> TankHudCtl:
	add_child_autofree(c)
	c.size = Vector2(c.art_rect.size * 2)
	return c


# --- the angle meters -----------------------------------------------------------------------------


func test_an_angle_meter_fades_in_holds_and_fades_out() -> void:
	var dt := 0.05
	var f := TankHudTags.dial_fade(0.0, 0.0, true, 0.125)
	assert_almost_eq(f.x, 0.5, 1e-4, "half in after 0.125 s")
	f = TankHudTags.dial_fade(f.x, f.y, true, 0.125)
	assert_eq(f.x, 1.0, "in after about 0.25 s")
	var t := 0.0
	while t < 1.45:
		f = TankHudTags.dial_fade(f.x, f.y, false, dt)
		t += dt
	assert_eq(f.x, 1.0, "held about 1.5 s after its condition ends")
	while t < 1.5 + 0.3 - 1e-6:
		f = TankHudTags.dial_fade(f.x, f.y, false, dt)
		t += dt
	assert_almost_eq(f.x, 0.5, 0.06, "half out 0.3 s into its 0.6 s fade")
	while t < 2.15:
		f = TankHudTags.dial_fade(f.x, f.y, false, dt)
		t += dt
	assert_eq(f.x, 0.0, "gone")
	f = Vector2(1.0, TankHudTags.DIAL_HOLD_S)
	for i in 60:
		f = TankHudTags.dial_fade(f.x, f.y, (i / 8) % 2 == 0, dt)
		assert_eq(f.x, 1.0, "a condition toggling every 0.4 s never flashes it")


func test_the_gun_arc_and_the_dial_follow_their_conditions_through_tick() -> void:
	var s := X.state(3)
	var g: TankGame = autofree(X.game(s))
	var tags := _place(TankHudTags.new().setup(g, TankHud.LAYOUT["tags"])) as TankHudTags
	tags.refresh()
	assert_true(bool(tags.m["aim"]), "the gunner lays the gun")
	assert_eq(tags.aim_fade.x, 0.0, "not shown before its first tick")
	tags.tick(0.3)
	assert_eq(tags.aim_fade.x, 1.0, "faded in")
	s.hull.target_id = 0
	s.hull.elev_target_deg = s.hull.elev_deg
	tags.refresh()
	assert_false(bool(tags.m["aim"]), "the gunner stops laying")
	tags.tick(1.0)
	assert_eq(tags.aim_fade.x, 1.0, "the arc holds")
	assert_true(tags.m.has("barrel"), "and keeps its geometry while it shows")
	tags.refresh()
	tags.tick(1.0)
	assert_lt(tags.aim_fade.x, 1.0, "then fades")
	tags.refresh()
	tags.tick(1.0)
	assert_eq(tags.aim_fade.x, 0.0, "and is gone")
	tags.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(tags.draws, 0)
	tags.m["sec"] = {
		"pivot": Vector2(400, 300), "length": 20.0, "left": false, "deg": 4.0, "rpm": 180
	}
	tags.sec_shown = tags.m["sec"]
	tags.tick(0.3)
	assert_eq(tags.sec_fade.x, 1.0, "the dial fades in")
	tags.m.erase("sec")
	tags.tick(1.4)
	assert_eq(tags.sec_fade.x, 1.0, "and holds")
	tags.tick(0.7)
	assert_eq(tags.sec_fade.x, 0.0, "then fades out")


# --- the heart rate -------------------------------------------------------------------------------


func test_my_numbers_show_the_heart_rate_only_with_a_sensor() -> void:
	assert_eq(TankHudModel.heart_bpm(null), 0, "no telemetry")
	var s := X.state(4)
	var g: TankGame = autofree(X.game(s))
	var mine := _place(TankHudMine.new().setup(g, TankHud.LAYOUT["mine"])) as TankHudMine
	var t := X.tm(200.0, 90.0)
	t.heart_rate_bpm = 0
	mine.set_telemetry(t)
	mine.refresh()
	assert_eq(int(mine.m["hr"]), 0, "no sensor: no heart rate")
	t.heart_rate_bpm = 142
	mine.refresh()
	assert_eq(int(mine.m["hr"]), 142, "the local rider's own heart rate")
	mine.queue_redraw()
	await wait_physics_frames(2)
	assert_gt(mine.draws, 0)


func test_the_heart_rate_fits_the_header_beside_every_seat_and_machine() -> void:
	var g: TankGame = autofree(X.game(X.state(4)))
	for bpm: String in ["58", "142", "199"]:
		var r := TankHudMine.hr_rect(bpm)
		assert_gte(r.position.x, 0.0)
		assert_lte(r.end.x, float(TankHudMine.W) - 14.0, "%s: clear of the in-band lamp" % bpm)
		assert_lte(r.end.y, 16.0, "%s: in the header, above watts, FTP and rpm" % bpm)
		for e: String in TankIds.SEATS:
			var seat := TankHud.tx(g, str(TankIds.SEAT_LABELS[e])).to_upper()
			var x := 16.0 + D.tall_w(seat)
			assert_lt(x + 5.0, r.position.x - 4.0, "%s, %s: the seat's name stays clear" % [e, bpm])
	for art: Vector2i in [Vector2i(852, 480), Vector2i(960, 540), Vector2i(1146, 480)]:
		var pr := TankHud.anchored(TankHud.LAYOUT["mine"], art)
		assert_true(Rect2(Vector2.ZERO, Vector2(art)).encloses(Rect2(pr)), "the panel on %s" % art)
