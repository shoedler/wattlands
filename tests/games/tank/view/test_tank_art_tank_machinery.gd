extends GutTest
## The cutaway machinery reads at a glance (the round 3 scene critic): the steam engine has a
## cylinder, a crosshead driven by a connecting rod from a crank turning once per stroke and a steam
## puff at its drain; the gauge sits on the boiler's boss; the hoist rails end at the main gun's
## breech under the main turret; the diesel chain runs below the rooms onto the drive sprocket; the
## Bulwark's lever leans to show its position on a quadrant.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _room(rig: TankRig, engine: String) -> TankRoomView:
	for r in rig.rooms:
		if r.engine == engine:
			return r
	return null


func _update(rig: TankRig, state: TankState, watts: float, cadence: float, frames: int) -> void:
	for _i in frames:
		rig.update(state, U.feed_of(state, watts, cadence), 1.0 / 60.0)


func test_the_gauge_sits_on_the_boilers_boss() -> void:
	var rig := U.make_rig(self, "citadel")
	var room := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	var gc: Array = (TankRigs.machinery().get("boiler", {}) as Dictionary).get("gauge_center")
	assert_eq(room.gauge_pos, room.boiler_pos + Vector2(float(gc[0]), float(gc[1])))


func test_the_crosshead_slides_on_its_guides_once_per_stroke() -> void:
	var rig := U.make_rig(self, "citadel")
	var room := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	var seen: Array[float] = []
	for k in 8:
		room.stroke = float(k) / 8.0
		seen.append(room.crosshead_x())
	var lo: float = seen.min()
	var hi: float = seen.max()
	assert_almost_eq(hi - lo, TankSteamRoom.CRANK_R * 2.0, 0.6, "the stroke is the crank's throw")
	assert_gt(lo, room.cyl_pos.x + TankSteamRoom.CYL_SIZE.x, "the crosshead stays off the cylinder")
	assert_lt(hi, room.wheel_pos.x, "and short of the flywheel")
	room.stroke = 0.0
	var a := room.crank_pin()
	room.stroke = 0.5
	assert_almost_eq(room.crank_pin().distance_to(a), TankSteamRoom.CRANK_R * 2.0, 1e-3)


func test_a_stroke_puffs_steam_at_the_drain_and_the_deck_vent() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	var room := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	_update(rig, s, 200.0, 90.0, 50)
	var fx := rig.hub.fx
	var drain := rig.hub.to_layer(room.drain_hull())
	assert_gt(rig._vent.x, room.rect.position.x, "the vent stands above the steam room")
	assert_lt(rig._vent.x, room.rect.end.x)
	assert_lt(rig._vent.y, room.rect.position.y, "on the deck")
	var vent := rig.hub.to_layer(rig._vent)
	var near_drain := 0
	var at_vent := 0
	for i in fx.particles.count:
		if fx.particles.kind[i] != TankParticles.Kind.STEAM:
			continue
		var p: Vector2 = fx.particles.pos[i]
		if p.distance_to(drain) < 3.0:
			near_drain += 1
		if p.distance_to(vent) < 3.0:
			at_vent += 1
	assert_gt(near_drain, 0, "wisps at the cylinder's drain")
	assert_gt(at_vent, 0, "a plume from the deck vent")


func test_every_hoist_ends_at_the_main_breech_under_the_main_turret() -> void:
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		var path := rig.rail_path()
		assert_gte(path.size(), 3, tank)
		var breech := path[path.size() - 1]
		var tr := TankRigs.rect((rig.def.get("turret", {}) as Dictionary).get("rect"))
		assert_between(breech.x, tr.position.x, tr.end.x, "%s: under the main turret" % tank)
		assert_lte(absf(breech.y - tr.end.y), 4.0, "%s: at the turret's base" % tank)
		for sd: Variant in rig.def.get("secondaries", []):
			var sr := TankRigs.rect((sd as Dictionary).get("rect"))
			var bb := rig.barbette_rect(sr, int((sd as Dictionary).get("facing", 1)))
			for p in path:
				assert_false(
					p.x >= bb.position.x - 2.0 and p.x <= bb.end.x + 2.0,
					"%s: the rail stays clear of the secondary's barbette" % tank
				)


func test_the_diesel_chain_runs_below_the_rooms_onto_the_drive_sprocket() -> void:
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		var pts := rig.drive_chain.points
		var sprocket := TankRigs.vec(rig.def.get("drive_sprocket"))
		var last := pts[pts.size() - 1]
		assert_almost_eq(
			last.distance_to(sprocket), TankRunningGear.SPROCKET_R, 1.0, "%s: on the teeth" % tank
		)
		var floor_y := 0.0
		for room in rig.rooms:
			floor_y = maxf(floor_y, room.rect.end.y)
		assert_gt(pts[1].y, floor_y + 3.0, "%s: the run is below the rooms and their band" % tank)
		assert_lt(pts[1].y, float(rig.hull_h), "%s: and on the skirt" % tank)


func test_the_bulwark_lever_leans_to_its_position_on_the_quadrant() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	var gb := s.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	var room := _room(rig, TankIds.ENGINE_BULWARK) as TankBulwarkRoom
	var knobs: Array[Vector2] = []
	for pos in [TankIds.LEVER_DRIVE, TankIds.LEVER_TURRET, TankIds.LEVER_HOIST]:
		gb.lever = pos
		gb.lever_to = pos
		gb.move_s = 0.0
		_update(rig, s, 200.0, 90.0, 3)
		var k := room.knob_pos()
		assert_almost_eq(k.distance_to(room.pivot), TankBulwarkRoom.LEVER_PX, 1e-3)
		assert_lt(k.y, room.pivot.y, "the lever stands up from its pivot")
		knobs.append(k)
	assert_lt(knobs[0].x, room.pivot.x - 3.0, "Drive leans left")
	assert_almost_eq(knobs[1].x, room.pivot.x, 0.5, "Turret stands upright")
	assert_gt(knobs[2].x, room.pivot.x + 3.0, "Hoist leans right")
	gb.lever = TankIds.LEVER_DRIVE
	gb.lever_to = TankIds.LEVER_HOIST
	gb.move_s = 0.5
	_update(rig, s, 200.0, 90.0, 1)
	assert_almost_eq(room.knob_pos().x, room.pivot.x, 0.5, "half way through a shift it is upright")


func test_the_shell_rack_and_engine_stay_inside_the_steam_room_clear_of_the_barbette() -> void:
	var rig := U.make_rig(self, "citadel")
	var room := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	var inside := Rect2(Vector2.ZERO, room.rect.size)
	var fore: Dictionary = (rig.def.get("secondaries", []) as Array)[0]
	var bb := rig.barbette_rect(TankRigs.rect(fore.get("rect")), int(fore.get("facing", 1)))
	bb.position -= room.rect.position
	assert_eq(room.rack_slots.size(), 3, "three shells")
	for r in room.rack_slots:
		assert_true(inside.encloses(r), "a shell inside the room")
		assert_false(r.intersects(bb), "no shell under the barbette")
	var engine := Rect2(room.cyl_pos, TankSteamRoom.CYL_SIZE).merge(
		Rect2(
			room.wheel_pos - Vector2.ONE * TankSteamRoom.WHEEL_R,
			Vector2.ONE * TankSteamRoom.WHEEL_R * 2.0
		)
	)
	assert_true(inside.encloses(engine), "the engine inside the room")
	assert_false(engine.intersects(bb), "and clear of the barbette")
