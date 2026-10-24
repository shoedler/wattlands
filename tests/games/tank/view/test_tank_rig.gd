extends GutTest
## The cutaway tank (brief 3): rooms at their rects with machinery that runs at cadence / 120 and
## brightens with %FTP, wall lamps in the rider's colour with their shape badge pulsing at cadence,
## the links between rooms, the running gear at tank speed, the turret and the dozer.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")


func _update(rig: TankRig, state: TankState, watts: float, cadence: float, frames: int = 6) -> void:
	for _i in frames:
		rig.update(state, U.feed_of(state, watts, cadence), 1.0 / 60.0)


func _room(rig: TankRig, engine: String) -> TankRoomView:
	for r in rig.rooms:
		if r.engine == engine:
			return r
	return null


func test_each_tank_has_one_room_per_engine_at_its_rigs_rect() -> void:
	var want := {
		"bulwark": ["bulwark"],
		"rampart": ["diesel", "dynamo"],
		"citadel": ["diesel", "dynamo", "steam"],
	}
	for tank: String in want:
		var rig := U.make_rig(self, tank)
		var engines: Array[String] = []
		for r in rig.rooms:
			engines.append(r.engine)
		assert_eq(engines, want[tank], tank)
		var rooms: Array = TankRigs.tank_def(tank)["rooms"]
		for i in rooms.size():
			var rr := TankRigs.rect(rooms[i]["rect"])
			assert_eq(rig.rooms[i].position, rr.position, "%s room %d" % [tank, i])
			assert_eq(rig.rooms[i].rect.size, rr.size)


func test_machinery_runs_at_cadence_over_120() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	_update(rig, s, 200.0, 60.0)
	var diesel := _room(rig, TankIds.ENGINE_DIESEL) as TankDieselRoom
	assert_almost_eq(diesel.flywheel.speed, 0.5, 1e-6, "60 rpm is half speed")
	for p in diesel.pistons:
		assert_almost_eq(p.speed, 0.5, 1e-6)
	var dynamo := _room(rig, TankIds.ENGINE_DYNAMO) as TankDynamoRoom
	assert_almost_eq(dynamo.armature.speed, 0.5, 1e-6)
	_update(rig, s, 200.0, 120.0)
	assert_almost_eq(diesel.flywheel.speed, 1.0, 1e-6)
	_update(rig, s, 200.0, 240.0)
	assert_almost_eq(diesel.flywheel.speed, 1.0, 1e-6, "clamped at full speed")


func test_a_flywheel_turns_a_whole_revolution_per_cadence_cycle() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	var room := _room(rig, TankIds.ENGINE_BULWARK) as TankBulwarkRoom
	room.flywheel.inertia_s = 0.0
	for _i in 60:
		rig.update(s, U.feed_of(s, 180.0, 90.0), 1.0 / 60.0)
	# 90 rpm for 1 s = 1.5 revolutions of the flywheel at max_rpm 120 x speed 0.75.
	assert_almost_eq(room.flywheel.revolutions(), 1.5, 0.05)


func test_pistons_are_staggered_and_stay_in_their_windows() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	_update(rig, s, 180.0, 90.0, 20)
	var room := _room(rig, TankIds.ENGINE_BULWARK) as TankBulwarkRoom
	var offsets: Array[float] = []
	for p in room.pistons:
		offsets.append(p.offset())
		assert_gte(p.offset(), 0.0)
		assert_lte(p.offset(), room.travel + 1e-6)
	var distinct := {}
	for o in offsets:
		distinct[o] = true
	assert_gt(distinct.size(), 1, "the pistons are not in step")


func test_the_room_brightens_with_ftp_and_in_band() -> void:
	var low := TankRoomInput.new()
	low.frac = 0.3
	var mid := TankRoomInput.new()
	mid.frac = 0.9
	var band := TankRoomInput.new()
	band.frac = 0.9
	band.in_band = true
	assert_lt(low.brightness(), mid.brightness())
	assert_lt(mid.brightness(), band.brightness())
	var reserve := TankRoomInput.new()
	reserve.frac = 1.0
	reserve.in_band = true
	reserve.reserve = true
	assert_lte(reserve.brightness(), 0.5, "a reserve room stays dim")
	assert_lte(band.brightness(), 1.0)
	assert_gte(low.brightness(), 0.3)


func test_the_room_node_is_dimmer_when_idle() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	for st in s.stations:
		st.in_band = false
	_update(rig, s, 40.0, 30.0)
	var dim := rig.rooms[0].modulate.r
	for st in s.stations:
		st.in_band = true
	_update(rig, s, 200.0, 90.0)
	assert_gt(rig.rooms[0].modulate.r, dim)


func test_the_wall_lamp_is_lit_in_band_in_the_riders_slot_colour_with_the_slot_shape() -> void:
	var rig := U.make_rig(self, "citadel")
	rig.hub.looks = {
		0: Wl.slot_look(0),
		1: Wl.slot_look(1),
		2: Wl.slot_look(2),
	}
	var s := TankFixtures.state(3)
	_update(rig, s, 200.0, 90.0)
	for r in rig.rooms:
		var st := s.station(r.engine)
		assert_true(r.lit(), "%s lit in band" % r.engine)
		assert_eq(r.input.look["color"], Wl.slot_look(st.slot)["color"], r.engine)
		assert_eq(r.input.look["shape"], Wl.slot_look(st.slot)["shape"])
	var diesel := _room(rig, TankIds.ENGINE_DIESEL)
	s.station(TankIds.ENGINE_DIESEL).in_band = false
	_update(rig, s, 200.0, 90.0)
	assert_false(diesel.lit(), "dark out of band")


func test_the_badge_pulses_once_per_pedal_stroke() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	var room := rig.rooms[0]
	var peaks := 0
	var prev := 0.0
	var rising := false
	for _i in 120:
		rig.update(s, U.feed_of(s, 180.0, 60.0), 1.0 / 60.0)
		var p := room.pulse()
		if rising and p < prev:
			peaks += 1
		rising = p > prev
		prev = p
	assert_almost_eq(float(peaks), 2.0, 1.0, "60 rpm for 2 s: two beats")


func test_a_reserve_room_runs_slow_and_dark() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	s.station(TankIds.ENGINE_DYNAMO).reserve = true
	s.station(TankIds.ENGINE_DYNAMO).in_band = false
	_update(rig, s, 300.0, 100.0)
	var dynamo := _room(rig, TankIds.ENGINE_DYNAMO)
	assert_false(dynamo.lit())
	assert_almost_eq(dynamo.input.watts, 60.0, 1e-6, "as if 60 W")
	assert_true(dynamo.input.reserve)
	assert_lt(dynamo.input.cadence, 60.0)


func test_an_unpowered_room_stops() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	s.all_afk = true
	_update(rig, s, 200.0, 90.0, 30)
	var room := _room(rig, TankIds.ENGINE_BULWARK) as TankBulwarkRoom
	assert_eq(room.flywheel.speed, 0.0)
	assert_eq(room.active_output(), -1)


func test_the_dynamo_jars_show_the_bank_in_order() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	var room := _room(rig, TankIds.ENGINE_DYNAMO) as TankDynamoRoom
	(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).bank = 64.0
	_update(rig, s, 200.0, 90.0)
	assert_eq(room.jars.size(), 3)
	assert_almost_eq(room.jar_level(0), 1.0, 1e-6)
	assert_almost_eq(room.jar_level(1), 0.92, 0.01)
	assert_almost_eq(room.jar_level(2), 0.0, 1e-6)
	(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).bank = 100.0
	_update(rig, s, 200.0, 90.0)
	assert_almost_eq(room.jar_level(2), 1.0, 1e-6)
	(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).bank = 0.0
	_update(rig, s, 200.0, 90.0)
	assert_almost_eq(room.jar_level(0), 0.0, 1e-6)


func test_the_dynamo_throws_cold_sparks_and_the_arc_is_the_cold_light() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	rig.hub.lights.begin()
	_update(rig, s, 220.0, 90.0, 40)
	assert_gt(rig.hub.fx.particles.count_kind(TankParticles.Kind.SPARK), 0)
	var cold := 0
	for i in rig.hub.fx.particles.count:
		if rig.hub.fx.particles.kind[i] == TankParticles.Kind.SPARK:
			var c: Color = rig.hub.fx.particles.color[i]
			cold += 1 if c.b > c.r else 0
	assert_gt(cold, 0)


func test_the_steam_gauge_marks_and_needle() -> void:
	assert_almost_eq(TankSteamRoom.gauge_angle(0.0), deg_to_rad(135.0), 1e-6)
	assert_almost_eq(TankSteamRoom.gauge_angle(150.0), deg_to_rad(405.0), 1e-6)
	assert_almost_eq(TankSteamRoom.gauge_angle(75.0), deg_to_rad(270.0), 1e-6)
	assert_almost_eq(TankSteamRoom.gauge_angle(999.0), deg_to_rad(405.0), 1e-6, "clamped")
	assert_eq(TankSteamRoom.GAUGE_MARKS, [40.0, 100.0, 150.0] as Array[float])


func test_the_shell_cradle_climbs_the_rail_with_pressure_and_reaches_the_breech_at_100() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	var steam := s.station(TankIds.ENGINE_STEAM) as TankSteamState
	var room := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	steam.pressure_pct = 50.0
	_update(rig, s, 200.0, 90.0, 120)
	assert_almost_eq(room.cradle_t, 0.5, 0.02)
	steam.pressure_pct = 100.0
	_update(rig, s, 200.0, 90.0, 120)
	assert_almost_eq(room.cradle_t, 1.0, 0.02, "the breech at 100%")
	steam.pressure_pct = 0.0
	steam.loaded = true
	_update(rig, s, 200.0, 90.0, 120)
	assert_almost_eq(room.cradle_t, 1.0, 0.02, "a latched shell waits at the breech")
	steam.loaded = false
	steam.cycling = true
	_update(rig, s, 200.0, 90.0, 120)
	assert_almost_eq(room.cradle_t, 0.0, 0.02, "and the cradle returns during the breech cycle")


func test_the_rampart_has_a_hoist_rail_and_a_chain_from_the_dynamo() -> void:
	var rig := U.make_rig(self, "rampart")
	assert_not_null(rig.rails, "a rail in the rear bay")
	assert_not_null(rig.hoist_chain, "a chain from the armature to its foot")
	var dynamo := _room(rig, TankIds.ENGINE_DYNAMO) as TankDynamoRoom
	assert_true(dynamo.has_hoist)
	var rail := rig._rail_points()
	assert_eq(rail.size(), 2)
	assert_gt(rail[0].x, dynamo.rect.end.x, "in the bay right of the dynamo room")
	assert_lt(rail[0].x, float(rig.hull_w))
	assert_lt(rail[1].y, rail[0].y, "the top is above the foot")
	assert_eq(rig.hoist_chain.points[0], dynamo.armature_hull_pos(), "from the armature")
	assert_eq(rig.hoist_chain.points[rig.hoist_chain.points.size() - 1], rail[0], "to the foot")
	for tank in ["bulwark", "citadel"]:
		var other := U.make_rig(self, tank)
		assert_null(other.hoist_chain, "%s has no dynamo hoist chain" % tank)


func test_the_rampart_cradle_rides_the_hoist_and_waits_at_the_breech() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	var dy := s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	var room := _room(rig, TankIds.ENGINE_DYNAMO) as TankDynamoRoom
	s.hull.loaded = TankIds.SHELL_NONE
	_update(rig, s, 200.0, 90.0, 10)
	assert_almost_eq(room.hoist_t, 0.0, 1e-6, "idle at the foot")
	dy.hoist_s = 10.0
	_update(rig, s, 200.0, 90.0, 2)
	assert_almost_eq(room.hoist_t, 0.0, 0.01, "just started")
	dy.hoist_s = 5.0
	_update(rig, s, 200.0, 90.0, 2)
	assert_almost_eq(room.hoist_t, 0.5, 0.01, "halfway after half the time")
	assert_true(room.hoisting())
	dy.hoist_s = 1.0
	_update(rig, s, 200.0, 90.0, 2)
	assert_almost_eq(room.hoist_t, 0.9, 0.01)
	dy.hoist_s = 0.0
	s.hull.loaded = TankIds.SHELL_HEAVY
	_update(rig, s, 200.0, 90.0, 120)
	assert_almost_eq(room.hoist_t, 1.0, 0.01, "the loaded shell waits at the breech")
	assert_false(room.hoisting())
	s.hull.loaded = TankIds.SHELL_NONE
	_update(rig, s, 200.0, 90.0, 120)
	assert_almost_eq(room.hoist_t, 0.0, 0.01, "and the cradle returns once the shot is gone")


func test_the_rampart_hoist_chain_turns_only_while_hoisting() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	var dy := s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState
	dy.hoist_s = 0.0
	_update(rig, s, 200.0, 90.0, 6)
	assert_eq(rig.hoist_chain.speed, 0.0)
	dy.hoist_s = 8.0
	_update(rig, s, 200.0, 90.0, 6)
	assert_eq(rig.hoist_chain.speed, 1.0)


func test_a_steam_puff_per_pedal_stroke() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	var room := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	room.feed(_input_at(60.0), 1.05)
	assert_eq(room.pending_strokes, 1, "60 rpm: one stroke in a second")
	assert_true(room.take_stroke())
	assert_false(room.take_stroke(), "taken once")
	for _i in 90:
		rig.update(s, U.feed_of(s, 200.0, 60.0), 1.0 / 60.0)
	assert_gt(
		rig.hub.fx.particles.count_kind(TankParticles.Kind.STEAM), 2, "puffs rise from the chimney"
	)


func _input_at(cadence: float) -> TankRoomInput:
	var inp := TankRoomInput.new()
	inp.cadence = cadence
	inp.watts = 200.0
	inp.frac = 0.9
	return inp


func test_the_flame_follows_watts() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	var room := _room(rig, TankIds.ENGINE_STEAM) as TankSteamRoom
	_update(rig, s, 60.0, 90.0, 30)
	var small := room.flame.scale.y
	_update(rig, s, 320.0, 90.0, 30)
	assert_gt(room.flame.scale.y, small)


func test_the_bulwark_lever_points_at_its_position_and_only_the_active_shaft_spins() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	var gb := s.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	var room := _room(rig, TankIds.ENGINE_BULWARK) as TankBulwarkRoom
	for pos in [TankIds.LEVER_DRIVE, TankIds.LEVER_TURRET, TankIds.LEVER_HOIST]:
		gb.lever = pos
		gb.lever_to = pos
		gb.move_s = 0.0
		_update(rig, s, 200.0, 90.0, 30)
		assert_eq(room.active_output(), pos)
		assert_eq(room.lever_tip(), room.outputs[pos], "the lever points at position %d" % pos)
		for i in 3:
			if i == pos:
				assert_gt(room.gears[i].speed, 0.0, "the active shaft spins")
			else:
				assert_eq(room.gears[i].speed, 0.0, "the others do not")


func test_the_lever_moves_across_during_a_shift_and_nothing_spins() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	var gb := s.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	var room := _room(rig, TankIds.ENGINE_BULWARK) as TankBulwarkRoom
	gb.lever = TankIds.LEVER_DRIVE
	gb.lever_to = TankIds.LEVER_HOIST
	gb.move_s = 0.5
	_update(rig, s, 200.0, 90.0)
	assert_eq(room.active_output(), -1, "no power through the lever during a move")
	var tip := room.lever_tip()
	assert_eq(tip, room.outputs[0].lerp(room.outputs[2], 0.5))
	gb.hoist_j = 2000.0
	assert_almost_eq(room.hoist_fill(), 0.5, 1e-6)


func test_chains_and_shafts_move_with_the_right_engine() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	var gb := s.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	gb.lever = TankIds.LEVER_DRIVE
	gb.lever_to = TankIds.LEVER_DRIVE
	_update(rig, s, 200.0, 90.0, 10)
	assert_gt(rig.drive_chain.speed, 0.0, "the drive chain runs on Drive")
	gb.lever = TankIds.LEVER_TURRET
	gb.lever_to = TankIds.LEVER_TURRET
	s.hull.traverse_s = 2.0
	_update(rig, s, 200.0, 90.0, 10)
	assert_eq(rig.drive_chain.speed, 0.0, "and stops on Turret")
	assert_true(rig.slewing)
	assert_gt(rig.slew_shaft.speed, 0.0, "the turret shaft turns while slewing")
	s.hull.traverse_s = 0.0
	_update(rig, s, 200.0, 90.0, 60)
	assert_false(rig.slewing)
	assert_eq(rig.slew_shaft.speed, 0.0)


func test_the_dynamo_shaft_turns_only_while_the_turret_slews() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	_update(rig, s, 200.0, 90.0, 60)
	assert_eq(rig.slew_shaft.speed, 0.0)
	s.hull.elev_deg += 0.0
	for i in 10:
		s.hull.elev_deg = 6.5 + float(i)
		rig.update(s, U.feed_of(s, 200.0, 90.0), 1.0 / 60.0)
	assert_gt(rig.slew_shaft.speed, 0.0, "the barrel is rising")


func test_the_diesel_chain_follows_the_diesel_cadence() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	_update(rig, s, 200.0, 60.0, 20)
	assert_almost_eq(rig.drive_chain.speed, 0.5, 1e-6)


func test_the_running_gear_turns_at_ground_speed() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	s.hull.speed_mps = 8.0
	_update(rig, s, 200.0, 90.0, 60)
	var v := 8.0 * TankConst.PX_PER_M
	for i in rig.gear.wheels.size():
		var rpm := rig.gear.wheels[i].current_speed() * rig.gear.wheels[i].max_rpm
		var rim := rpm / 60.0 * TAU * rig.gear.radii[i]
		assert_almost_eq(rim, v, v * 0.12, "wheel %d rolls at the ground speed" % i)
	assert_almost_eq(rig.gear.belt.speed, v / TankRunningGear.BELT_MAX_PX_S, 0.02)
	s.hull.speed_mps = 0.0
	_update(rig, s, 200.0, 90.0, 120)
	assert_almost_eq(rig.gear.belt.speed, 0.0, 1e-6)


func test_the_track_belt_wraps_every_wheel() -> void:
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		var def := TankRigs.tank_def(tank)
		var want := (def["road_wheels_x"] as Array).size() + 2
		assert_eq(rig.gear.wheels.size(), want, tank)
		assert_gt(
			rig.gear.belt.path_length(),
			float(TankRigs.vec(def["hull_px"]).x),
			"%s belt runs the hull's length" % tank
		)


func test_the_turret_faces_the_state_and_flips_through_a_traverse() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	s.hull.facing = TankIds.FACE_RIGHT
	_update(rig, s, 200.0, 90.0, 5)
	assert_almost_eq(rig.turret.scale.x, 1.0, 1e-6)
	var right_muzzle := rig.turret.muzzle_hull()
	s.hull.facing = TankIds.FACE_LEFT
	s.hull.traverse_s = 2.0
	var shown: Array[float] = []
	for _i in 130:
		s.hull.traverse_s = maxf(0.0, s.hull.traverse_s - 1.0 / 60.0)
		rig.update(s, U.feed_of(s, 200.0, 90.0), 1.0 / 60.0)
		shown.append(rig.turret.dir)
	assert_lt(shown[40], 0.6, "mid-turn the turret is edge on")
	assert_true(shown.any(func(d: float) -> bool: return absf(d) < 0.5))
	assert_almost_eq(rig.turret.scale.x, -1.0, 0.02)
	var left_muzzle := rig.turret.muzzle_hull()
	var ring := TankGeometry.load_default().ring("citadel")
	assert_almost_eq(
		left_muzzle.x - ring.x, -(right_muzzle.x - ring.x), 0.5, "mirrored about the ring"
	)


func test_the_muzzle_is_where_the_rules_put_it() -> void:
	var geo := TankGeometry.load_default()
	for tank in ["bulwark", "rampart", "citadel"]:
		var rig := U.make_rig(self, tank)
		rig.turret.elev = 12.0
		for facing in [TankIds.FACE_RIGHT, TankIds.FACE_LEFT]:
			rig.turret.scale.x = float(facing)
			var want := geo.muzzle(tank, 12.0, facing)
			assert_almost_eq(
				rig.turret.muzzle_hull().x, want.x, 0.01, "%s facing %d" % [tank, facing]
			)
			assert_almost_eq(rig.turret.muzzle_hull().y, want.y, 0.01)


func test_the_barrel_eases_to_the_elevation_and_the_gun_recoils() -> void:
	var rig := U.make_rig(self, "rampart")
	var s := TankFixtures.state(2)
	s.hull.elev_deg = 20.0
	_update(rig, s, 200.0, 90.0, 60)
	assert_almost_eq(rig.turret.elev, 20.0, 0.1)
	rig.fire_main(0.8)
	assert_gt(rig.turret.recoil, 3.0)
	_update(rig, s, 200.0, 90.0, 60)
	assert_eq(rig.turret.recoil, 0.0, "the barrel runs back out")
	assert_eq(rig.shake_offset, Vector2.ZERO, "and the shake settles")


func test_firing_shakes_the_hull_and_blasts() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	_update(rig, s, 200.0, 90.0, 2)
	rig.fire_main(1.0)
	assert_gt(rig.shake_amp, 2.0)
	assert_eq(rig.hub.fx.flash, 1.0)
	assert_gt(rig.hub.fx.particles.count_kind(TankParticles.Kind.BRASS), 0, "a casing is ejected")
	var moved := false
	for _i in 5:
		rig.update(s, U.feed_of(s, 200.0, 90.0), 1.0 / 60.0)
		moved = moved or rig.position != rig.base_pos
	assert_true(moved, "the hull shakes")
	assert_almost_eq(rig.muzzle_dir().length(), 1.0, 1e-4)


func test_the_citadel_has_two_secondaries_that_kick() -> void:
	var rig := U.make_rig(self, "citadel")
	assert_eq(rig.secondaries.size(), 2)
	assert_eq(rig.secondaries[0].facing, 1, "fore right")
	assert_eq(rig.secondaries[1].facing, -1, "aft left")
	rig.fire_secondary(1)
	assert_gt(rig.secondaries[1].recoil, 0.0)
	assert_eq(rig.secondaries[0].recoil, 0.0)
	assert_eq(U.make_rig(self, "bulwark").secondaries.size(), 0)


func test_exhaust_smoke_follows_the_diesels_watts() -> void:
	var low := U.make_rig(self, "bulwark")
	var high := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	for _i in 180:
		low.update(s, U.feed_of(s, 60.0, 60.0), 1.0 / 60.0)
		high.update(s, U.feed_of(s, 280.0, 100.0), 1.0 / 60.0)
	assert_gt(
		high.hub.fx.particles.count_kind(TankParticles.Kind.EXHAUST),
		low.hub.fx.particles.count_kind(TankParticles.Kind.EXHAUST)
	)


func test_the_dozer_blade_drops_and_the_berm_grows_at_a_gun_line() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.gun_line(3)
	s.hull.berm_hp = 0.0
	_update(rig, s, 200.0, 90.0, 90)
	assert_eq(rig.blade, 1.0, "lowered when dug in")
	assert_eq(rig.berm_hp, 0.0)
	s.hull.berm_hp = 30.0
	_update(rig, s, 200.0, 90.0, 2)
	assert_eq(rig.berm_hp, 30.0)
	var drive := TankFixtures.state(3)
	_update(rig, drive, 200.0, 90.0, 90)
	assert_eq(rig.blade, 0.0, "raised again while driving")


func test_a_low_or_broken_hull_smokes() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	s.hull.hp = 10.0
	s.hull.hp_max = 100.0
	_update(rig, s, 200.0, 90.0, 120)
	assert_gt(rig.hub.fx.particles.count_kind(TankParticles.Kind.SMOKE), 0)
	var down := U.make_rig(self, "bulwark")
	s.hull.breakdown = true
	for _i in 120:
		down.update(s, U.feed_of(s, 200.0, 90.0), 1.0 / 60.0)
	assert_gt(down.hub.fx.particles.count_kind(TankParticles.Kind.FIRE), 0, "a breakdown burns")


func test_room_lights_are_added_to_the_light_layer() -> void:
	var rig := U.make_rig(self, "citadel")
	var s := TankFixtures.state(3)
	rig.hub.lights.begin()
	_update(rig, s, 220.0, 90.0, 1)
	assert_gt(rig.hub.lights.count, 6, "lamps, room glows, cylinders, the arc, the firebox")
	assert_lte(rig.hub.lights.count, TankLights.MAX_LIGHTS)


func test_the_hit_flash_lights_the_hull_briefly() -> void:
	var rig := U.make_rig(self, "bulwark")
	var s := TankFixtures.state(1)
	rig.hit(1.0)
	_update(rig, s, 200.0, 90.0, 2)
	assert_gt(rig.hull_sprite.modulate.r, 1.0)
	_update(rig, s, 200.0, 90.0, 30)
	assert_eq(rig.hull_sprite.modulate.r, 1.0)
