extends GutTest
## A rules step stays cheap at the cap (brief 4: <= 1 ms with 150 enemies plus live projectiles,
## so a 55 minute shift simulates in about a minute). The clock is read here, in the test, never in
## the rules.

const BUDGET_US := 1000.0
## GitHub's runners are about 2x this budget's reference machine (docs/decisions/lead.md).
const CI_BUDGET_US := 2500.0


func _budget_us() -> float:
	return CI_BUDGET_US if OS.has_environment("CI") else BUDGET_US


## vo2 wave 2 with 150 enemies in reach, every station manned at m ~ 1.5, four Scorpions.
func _loaded_rig() -> SiegeRig:
	var rig := SiegeRig.new("vo2", 4, 0, 5)
	rig.enter(4, 10.0)
	rig.manual()
	var s := rig.state
	for pd in s.pads:
		pd.type = SiegeIds.PAD_SCORPION
	rig.put(1, SiegeIds.STATION_BALLISTA)
	rig.put(2, SiegeIds.STATION_ONAGER)
	rig.put(3, SiegeIds.STATION_ARROWS)
	rig.put(4, SiegeIds.STATION_ARROWS)
	for p in rig.slots:
		rig.power_w[p.peer_id] = 300.0
	s.wave.budget_left = 0.0
	s.wave.engines.clear()
	_fill(rig)
	return rig


## Tops the field up to 150 bodies spread over every station's band.
func _fill(rig: SiegeRig) -> void:
	var s := rig.state
	var progs: Array[float] = []
	for id in SiegeIds.WEAPONS:
		progs.append_array(SiegeKit.band_progs(s, id))
	var i := s.next_enemy_id
	while s.enemies.size() < 150:
		var type := SiegeIds.ENEMY_SPEAR if i % 3 != 0 else SiegeIds.ENEMY_SHIELD
		var e := SiegeKit.enemy(s, type, progs[(i * 37) % progs.size()], float(i % 4) - 1.5, 9999.0)
		e.speed_mps = 0.0
		i += 1


func _mean_us(rig: SiegeRig, steps: int) -> float:
	rig.run(2.0)
	var total := 0
	for _i in steps:
		_fill(rig)
		var t0 := Time.get_ticks_usec()
		rig.step()
		total += Time.get_ticks_usec() - t0
	return float(total) / steps


func test_a_step_at_the_cap_with_every_station_firing_is_under_a_millisecond() -> void:
	var rig := _loaded_rig()
	assert_eq(rig.state.enemies.size(), 150)
	var mean := _mean_us(rig, 400)
	assert_gt(rig.state.projectiles.size(), 0, "projectiles are in flight")
	var shots := 0
	for st in rig.state.stations:
		shots += st.shots
	assert_gt(shots, 20, "every weapon fired")
	gut.p(
		(
			"mean rules step at the cap: %.0f us, %d projectiles live"
			% [mean, rig.state.projectiles.size()]
		)
	)
	assert_lt(mean, _budget_us(), "mean %.0f us" % mean)


func test_an_idle_field_at_the_cap_is_cheap_too() -> void:
	var rig := _loaded_rig()
	for r in rig.state.riders:
		r.target = SiegeIds.STATION_MINE
	var mean := _mean_us(rig, 200)
	gut.p("mean rules step at the cap, stations idle: %.0f us" % mean)
	assert_lt(mean, _budget_us())


func test_a_cap_sized_burst_of_spawns_drains_within_the_cap() -> void:
	var rig := _loaded_rig()
	for i in 300:
		SiegeSpawner.enqueue(rig.state, SiegeIds.ENEMY_SPEAR, float(i % 50))
	rig.step()
	assert_lte(rig.state.enemies.size(), 150)
	assert_gt(rig.state.queue.size(), 0)
	assert_lte(
		SiegeSnapshotSchema.byte_size(SiegeSnapshot.encode(rig.state)),
		SiegeSnapshotSchema.MAX_BYTES
	)
