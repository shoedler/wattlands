extends GutTest
## Shot replay (SiegeV2ShotReplay) and the projectile drawer (SiegeV2Shots): the host's own
## landing for the same event (SiegeProjectiles.fire), identical arcs from the same seed, the
## spread from stations.json through SiegeBallistics.shot_velocities, and drawing.

var bank: SiegeBakeBank = null


func before_all() -> void:
	bank = SiegeBakeBank.shared()


## Fires station `id` on the host at an enemy at `prog`: [state, shot event, the host's
## projectiles].
func _host_shot(id: int, type: int, prog: float, rng_seed: int = 3) -> Array:
	var s := SiegeKit.state("short", 1, 0, rng_seed)
	var e := SiegeKit.enemy(s, type, prog, 0.6, -1.0)
	var spec := SiegeStations.aim_spec(s, id)
	var sol := SiegeAim.lead(
		s.path, s.path.station_pos[id], s.path.station_muzzle_m[id], e, spec, 2.0
	)
	assert_false(sol.is_empty(), "station %d reaches prog %f" % [id, prog])
	var events: Array[Dictionary] = []
	var n := 12 if id == SiegeIds.STATION_ARROWS else 1
	SiegeProjectiles.fire(s, SiegeKit.table(s), id, sol, n, e.id, events)
	return [s, SiegeKit.of_type(events, SiegeIds.EV_SHOT)[0], s.projectiles.duplicate()]


func test_replay_lands_where_the_host_lands_stones_and_arrows() -> void:
	for id in [SiegeIds.STATION_ONAGER, SiegeIds.STATION_ARROWS]:
		var s0 := SiegeKit.state("short")
		var prog := SiegeKit.prog_in_band(s0, id)
		var h := _host_shot(id, SiegeIds.ENEMY_SPEAR, prog)
		var s: SiegeState = h[0]
		var ev: Dictionary = JSON.parse_string(JSON.stringify(h[1]))
		var host: Array = h[2]
		var r := SiegeV2ShotReplay.from_event(ev, s.path, s.content)
		assert_eq(r.n, host.size())
		for j in r.n:
			var hp: SiegeProjectile = host[j]
			var d := r.landing(j).distance_to(hp.pos)
			assert_lt(d, 0.05, "station %d projectile %d lands %.3f m from the host's" % [id, j, d])
			assert_almost_eq(r.land_t[j], hp.ticks * SiegeBallistics.DT, SiegeBallistics.DT + 1e-4)
		assert_almost_eq(
			r.floor_z, (host[0] as SiegeProjectile).floor_z, 0.02, "the aim point's ground"
		)


func test_replay_follows_the_hosts_velocities() -> void:
	var s0 := SiegeKit.state("short")
	var h := _host_shot(SiegeIds.STATION_ARROWS, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(s0, 3))
	var s: SiegeState = h[0]
	var ev: Dictionary = h[1]
	var def := s.content.station_def(SiegeIds.STATION_ARROWS)
	var vs := SiegeBallistics.shot_velocities(
		SiegeEvents.shot_velocity(ev),
		int(ev["n"]),
		int(ev["sd"]),
		float(def["spread_deg"]),
		float(def["speed_spread"])
	)
	var r := SiegeV2ShotReplay.from_event(ev, s.path, s.content)
	for j in r.n:
		var first := SiegeBallistics.step(r.origin, vs[j], r.k)
		assert_almost_eq(r.flights[j][1].distance_to(first[0]), 0.0, 1e-5, "arrow %d" % j)


func test_replay_is_identical_twice_from_the_same_seed() -> void:
	var s0 := SiegeKit.state("short")
	var h := _host_shot(SiegeIds.STATION_ARROWS, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(s0, 3))
	var s: SiegeState = h[0]
	var ev: Dictionary = h[1]
	var a := SiegeV2ShotReplay.from_event(ev, s.path, s.content)
	var b := SiegeV2ShotReplay.from_event(ev.duplicate(true), s.path, s.content)
	for j in a.n:
		assert_eq(a.flights[j], b.flights[j], "arrow %d" % j)
	var other := ev.duplicate(true)
	other["sd"] = int(ev["sd"]) + 1
	var c := SiegeV2ShotReplay.from_event(other, s.path, s.content)
	var differ := false
	for j in a.n:
		differ = differ or a.landing(j).distance_to(c.landing(j)) > 0.01
	assert_true(differ, "another seed, other arcs")


func test_ballista_bolt_flies_to_the_ground() -> void:
	var s0 := SiegeKit.state("short")
	var prog := SiegeKit.prog_in_band(s0, SiegeIds.STATION_BALLISTA)
	var h := _host_shot(SiegeIds.STATION_BALLISTA, SiegeIds.ENEMY_RAM, prog)
	var s: SiegeState = h[0]
	var r := SiegeV2ShotReplay.from_event(h[1], s.path, s.content)
	var land := r.landing(0)
	assert_almost_eq(land.z, r.floor_z, 0.01)
	assert_gt(r.land_t[0], 0.2)
	assert_eq(r.position(0, 100.0), land, "after landing it stays where it landed")


func test_drawer_replays_draws_and_stops_scorpion_bolts() -> void:
	var s0 := SiegeKit.state("short")
	var shots := SiegeV2Shots.new(bank)
	shots.path = s0.path
	shots.content = s0.content
	add_child_autofree(shots)
	var arrows: Dictionary = _host_shot(SiegeIds.STATION_ARROWS, 1, SiegeKit.prog_in_band(s0, 3))[1]
	var stone: Dictionary = _host_shot(SiegeIds.STATION_ONAGER, 1, SiegeKit.prog_in_band(s0, 2))[1]
	shots.add_event(arrows)
	shots.add_event(stone)
	var t0 := int(arrows["tk"]) * SiegeBallistics.DT
	shots.set_time(t0 + 0.3)
	assert_eq(shots.in_flight(), 13)
	assert_gt(shots.entry_count(), 13 * 3, "streaks, trails, fletches and shadows")
	assert_eq(shots.dropped, 0)
	shots.set_time(t0 + 40.0)
	assert_eq(shots.in_flight(), 0)
	assert_eq(shots.shots.size(), 0, "finished shots are dropped")
	assert_null(shots.add_event({"type": "shot"}), "a malformed event is ignored")
	# a Scorpion bolt stops in the first body on its path
	var o := s0.path.pads[0] + Vector3(0, 0, 1.5)
	var target := s0.path.point_at(s0.path.length_m - 2.0)
	var v := SiegeBallistics.solve_angle(o, target, 50.0, 0.001)
	var ev := SiegeEvents.shot(
		roundi(t0 / SiegeBallistics.DT) + 1000,
		11,
		SiegeIds.SHOT_SCORPION,
		SiegeEvents.quantize_o(o),
		SiegeEvents.quantize_v(v),
		1,
		9
	)
	var r := shots.add_event(ev)
	var mid := r.position(0, r.land_t[0] * 0.5)
	shots.bodies = PackedVector3Array([mid - Vector3(0, 0, 1.0)])
	var t_ev := int(ev["tk"]) * SiegeBallistics.DT
	for k in 40:
		shots.set_time(t_ev + k * 0.05)
	assert_lt(r.end_t(0), r.land_t[0] - 0.05, "stopped short of the ground")
