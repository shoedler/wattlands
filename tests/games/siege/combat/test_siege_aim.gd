extends GutTest
## SiegeAim (brief 2.4 "Aiming", 4): aim then fly lands within 0.5 m of a stationary aim point
## across each station's range; lead aim hits a constant-speed target on a straight stretch and
## on the path's hairpins; the prediction clamps where enemies stop.

var _s: SiegeState


func before_all() -> void:
	_s = SiegeKit.state()


func _spec(id: int) -> Dictionary:
	return SiegeStations.aim_spec(_s, id)


## The prog of the sharpest turn of the path inside station `id`'s band.
func _hairpin(id: int) -> float:
	var best := -1.0
	var best_turn := 0.0
	for p in SiegeKit.band_progs(_s, id):
		if p < 4.0 or p > _s.path.length_m - 4.0:
			continue
		var turn := absf(_s.path.dir_at(p - 3.0).angle_to(_s.path.dir_at(p + 3.0)))
		if turn > best_turn:
			best_turn = turn
			best = p
	return best


func _lands_on(id: int, aim: Vector3) -> float:
	var spec := _spec(id)
	var pivot := _s.path.station_pos[id]
	var a := deg_to_rad(SiegePath.yaw_to(pivot, aim))
	var o := pivot + Vector3(cos(a), sin(a), 0.0) * _s.path.station_muzzle_m[id]
	var sol := SiegeAim.solve(o, aim, spec)
	if sol.is_empty():
		return INF
	var l := SiegeBallistics.land(o, sol["v"], float(spec["k"]), aim.z)
	return Vector2(l["p"].x - aim.x, l["p"].y - aim.y).length()


func _check_band(id: int) -> void:
	var progs := SiegeKit.band_progs(_s, id)
	assert_gt(progs.size(), 20, "station %d covers road" % id)
	var dz := float(_spec(id).get("aim_dz_m", 0.0))
	var tried := 0
	for i in range(0, progs.size(), maxi(progs.size() / 12, 1)):
		var aim := _s.path.point_at(progs[i])
		aim.z += dz
		var err := _lands_on(id, aim)
		assert_lt(err, 0.5, "station %d at prog %.1f" % [id, progs[i]])
		tried += 1
	assert_gt(tried, 8)


func test_the_ballista_lands_on_a_still_point_across_its_band() -> void:
	_check_band(SiegeIds.STATION_BALLISTA)


func test_the_onager_lands_on_a_still_point_across_its_band() -> void:
	_check_band(SiegeIds.STATION_ONAGER)


func test_the_arrow_organ_lands_on_a_still_point_across_its_band() -> void:
	_check_band(SiegeIds.STATION_ARROWS)


func test_bolts_fly_flat_and_stones_arc() -> void:
	var b_aim := _s.path.point_at(SiegeKit.prog_in_band(_s, SiegeIds.STATION_BALLISTA))
	var bp := _s.path.station_pos[SiegeIds.STATION_BALLISTA]
	var bolt := SiegeAim.solve(bp, b_aim, _spec(SiegeIds.STATION_BALLISTA))
	var bv: Vector3 = bolt["v"]
	assert_lt(absf(rad_to_deg(atan2(bv.z, Vector2(bv.x, bv.y).length()))), 15.0, "a low arc")
	var o_aim := _s.path.point_at(SiegeKit.prog_in_band(_s, SiegeIds.STATION_ONAGER))
	var op := _s.path.station_pos[SiegeIds.STATION_ONAGER]
	var stone := SiegeAim.solve(op, o_aim, _spec(SiegeIds.STATION_ONAGER))
	var sv: Vector3 = stone["v"]
	assert_almost_eq(rad_to_deg(atan2(sv.z, Vector2(sv.x, sv.y).length())), 45.0, 0.01)
	assert_between(sv.length(), 10.0, 34.0)


func test_arrows_arc_at_40_degrees() -> void:
	var aim := _s.path.point_at(SiegeKit.prog_in_band(_s, SiegeIds.STATION_ARROWS, 0.3))
	var sol := SiegeAim.solve(
		_s.path.station_pos[SiegeIds.STATION_ARROWS], aim, _spec(SiegeIds.STATION_ARROWS)
	)
	var v: Vector3 = sol["v"]
	assert_almost_eq(rad_to_deg(atan2(v.z, Vector2(v.x, v.y).length())), 40.0, 0.01)
	assert_lte(v.length(), 45.0 + 1e-3)


func test_arrows_fall_back_to_the_low_arc_beyond_40_degree_reach() -> void:
	var spec := _spec(SiegeIds.STATION_ARROWS)
	var o := Vector3(0, 0, 17.5)
	var at_40 := SiegeBallistics.solve_speed(o, Vector3(140, 0, 0), 40.0, 0.006, 10.0, 45.0)
	assert_eq(at_40, Vector3.ZERO, "40 degrees can't reach 140 m")
	var sol := SiegeAim.solve(o, Vector3(115, 0, 0), spec)
	assert_false(sol.is_empty(), "115 m is in reach one way or the other")


func test_prediction_follows_the_current_speed() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 100.0)
	e.speed_mps = 2.0
	assert_almost_eq(SiegeAim.predict_prog(_s.path, e, 3.0), 106.0, 1e-5)
	_s.enemies.clear()


func test_prediction_stops_at_the_gate_and_the_moat() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, 385.0)
	assert_eq(SiegeAim.predict_prog(_s.path, e, 10.0), _s.path.length_m)
	var t := SiegeKit.enemy(_s, SiegeIds.ENEMY_TOWER, 374.0)
	assert_eq(SiegeAim.predict_prog(_s.path, t, 10.0), _s.path.moat_edge_m)
	var r := SiegeKit.enemy(_s, SiegeIds.ENEMY_RAM, 391.0)
	r.st = SiegeIds.EN_BATTER
	assert_eq(SiegeAim.predict_prog(_s.path, r, 10.0), 391.0, "a battering ram stands")
	_s.enemies.clear()


func test_the_aim_point_keeps_the_lateral_offset() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 50.0, 1.2)
	e.speed_mps = 0.0
	var p := SiegeAim.aim_point(_s.path, e, 2.0, 0.9)
	var want := _s.path.point_at(50.0, 1.2)
	assert_almost_eq(p.x, want.x, 1e-4)
	assert_almost_eq(p.z, want.z + 0.9, 1e-4)
	_s.enemies.clear()


## Lead-aims at `e` from station `id` and returns how far the landing is from where `e` is at
## the landing time (at its constant speed along the path).
func _lead_miss(id: int, e: SiegeEnemyState) -> float:
	var spec := _spec(id)
	var sol := SiegeAim.lead(
		_s.path, _s.path.station_pos[id], _s.path.station_muzzle_m[id], e, spec, 1.0, 3
	)
	assert_false(sol.is_empty(), "a solution")
	if sol.is_empty():
		return INF
	var aim: Vector3 = sol["aim"]
	var l := SiegeBallistics.land(sol["o"], sol["v"], float(spec["k"]), aim.z)
	var at := _s.path.point_at(e.prog_m + e.speed_mps * float(l["t"]), e.lat_m)
	return Vector2(l["p"].x - at.x, l["p"].y - at.y).length()


func test_lead_hits_a_walker_on_a_straight_stretch() -> void:
	for id in SiegeIds.WEAPONS:
		var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(_s, id, 0.4))
		assert_lt(_lead_miss(id, e), 0.6, "station %d" % id)
		_s.enemies.clear()


func test_lead_hits_a_chariot_on_a_straight_stretch() -> void:
	for id in [SiegeIds.STATION_BALLISTA, SiegeIds.STATION_ONAGER]:
		var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, SiegeKit.prog_in_band(_s, id, 0.3))
		e.speed_mps = 6.0
		assert_lt(_lead_miss(id, e), 1.0, "station %d (6 m/s, 3 rounds)" % id)
		_s.enemies.clear()


func test_lead_hits_through_a_hairpin() -> void:
	for id in SiegeIds.WEAPONS:
		var hp := _hairpin(id)
		assert_gt(hp, 0.0, "station %d sees a turn" % id)
		var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, maxf(hp - 3.0, 0.0))
		e.speed_mps = 1.8
		assert_lt(_lead_miss(id, e), 0.8, "station %d through the turn at %.0f" % [id, hp])
		_s.enemies.clear()


func test_three_lead_rounds_beat_one() -> void:
	var id := SiegeIds.STATION_ONAGER
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_CHARIOT, SiegeKit.prog_in_band(_s, id, 0.3))
	e.speed_mps = 6.0
	var spec := _spec(id)
	var pivot := _s.path.station_pos[id]
	var one := SiegeAim.lead(_s.path, pivot, _s.path.station_muzzle_m[id], e, spec, 0.0, 1)
	var three := SiegeAim.lead(_s.path, pivot, _s.path.station_muzzle_m[id], e, spec, 0.0, 3)
	var miss := func(sol: Dictionary) -> float:
		var l := SiegeBallistics.land(
			sol["o"], sol["v"], float(spec["k"]), (sol["aim"] as Vector3).z
		)
		var at := _s.path.point_at(e.prog_m + e.speed_mps * float(l["t"]), e.lat_m)
		return Vector2(l["p"].x - at.x, l["p"].y - at.y).length()
	assert_lt(float(miss.call(three)), float(miss.call(one)))
	_s.enemies.clear()


func test_out_of_reach_has_no_solution() -> void:
	var e := SiegeKit.enemy(_s, SiegeIds.ENEMY_SPEAR, 0.0)
	e.speed_mps = 0.0
	var id := SiegeIds.STATION_ONAGER
	if _s.path.ground_dist(_s.path.station_pos[id], 0.0) > 140.0:
		var sol := SiegeAim.lead(_s.path, _s.path.station_pos[id], 0.0, e, _spec(id), 1.0)
		assert_eq(sol, {})
	else:
		pass_test("the camp is within the onager's physical reach")
	_s.enemies.clear()
