extends GutTest
## Shot replay (SiegeV2ShotReplay) and the projectile drawer (SiegeV2Shots): identical arcs from
## the same seed, the spread rule of STATE_V2.md, landing on the ground, and drawing.

const MAP := "res://content/siege/maps/rotae.json"

var bank: SiegeBakeBank = null
var path: SiegePath = null


func before_all() -> void:
	bank = SiegeBakeBank.shared()
	path = SiegePath.load_file(MAP)


## A shot event as the rules send it, aimed from station `src`'s muzzle at the road.
func _event(
	src: int, kind: int, n: int, speed: float, k: float, sd: int, prog: float = 300.0
) -> Dictionary:
	var target := path.point_at(prog)
	var o := path.muzzle(src, SiegePath.yaw_to(path.station_pos[src], target))
	var v := SiegeBallistics.solve_angle(o, target, speed, k)
	return {
		"type": "shot",
		"tk": 40,
		"src": src,
		"kind": kind,
		"o": [roundi(o.x * 100.0), roundi(o.y * 100.0), roundi(o.z * 100.0)],
		"v": [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)],
		"n": n,
		"sd": sd,
	}


func test_replay_is_identical_twice_from_the_same_seed() -> void:
	var ev := _event(3, 2, 12, 45.0, 0.006, 987654, 340.0)
	var a := SiegeV2ShotReplay.from_event(ev, path)
	var b := SiegeV2ShotReplay.from_event(ev.duplicate(true), path)
	assert_eq(a.n, 12)
	assert_eq(a.flights.size(), 12)
	for j in a.n:
		assert_eq(a.flights[j], b.flights[j], "arrow %d" % j)
		assert_eq(a.land_t[j], b.land_t[j])
	# a JSON round trip (clients) changes nothing
	var c := SiegeV2ShotReplay.from_event(JSON.parse_string(JSON.stringify(ev)), path)
	for j in a.n:
		assert_eq(a.landing(j), c.landing(j))


func test_seed_spreads_the_volley() -> void:
	var a := SiegeV2ShotReplay.from_event(_event(3, 2, 12, 45.0, 0.006, 11, 340.0), path)
	var b := SiegeV2ShotReplay.from_event(_event(3, 2, 12, 45.0, 0.006, 12, 340.0), path)
	var differ := false
	var spread := 0.0
	for j in a.n:
		if a.landing(j).distance_to(b.landing(j)) > 0.01:
			differ = true
		spread = maxf(spread, a.landing(j).distance_to(a.landing(0)))
	assert_true(differ, "another seed, other arcs")
	assert_gt(spread, 0.5, "the arrows of one volley spread")
	assert_lt(spread, 25.0)


func test_spread_follows_state_v2_order() -> void:
	# arrow j's velocity is v0 turned by gauss yaw, gauss pitch and scaled by range_f, in order
	var ev := _event(3, 2, 3, 45.0, 0.006, 4242, 340.0)
	var r := SiegeV2ShotReplay.from_event(ev, path)
	var rng := SiegeHashRng.new(4242)
	var sp: Array = SiegeV2ShotReplay.SPREAD[2]
	for j in 3:
		var dyaw := rng.gauss(float(sp[0]))
		var dpitch := rng.gauss(float(sp[0]))
		var sf := 1.0 + rng.range_f(-float(sp[1]), float(sp[1]))
		var v := SiegeBallistics.spread(r.velocity, dyaw, dpitch, sf)
		var first := SiegeBallistics.step(r.origin, v, 0.006)
		assert_almost_eq(r.flights[j][1].distance_to(first[0]), 0.0, 1e-5, "arrow %d" % j)


func test_unspread_bolt_lands_on_its_aim_point() -> void:
	var ev := _event(1, 0, 1, 70.0, 0.0004, 5, 290.0)
	var r := SiegeV2ShotReplay.from_event(ev, path, [0.0, 0.0])
	var target := path.point_at(290.0)
	var land := r.landing(0)
	assert_lt(Vector2(land.x - target.x, land.y - target.y).length(), 1.5)
	assert_gt(r.land_t[0], 0.3)
	assert_eq(r.position(0, 100.0), land, "after landing it stays where it landed")
	assert_eq(r.position(0, 0.0), r.origin)


func test_drawer_replays_and_draws_shots() -> void:
	var shots := SiegeV2Shots.new(bank)
	shots.path = path
	add_child_autofree(shots)
	shots.add_event(_event(1, 0, 1, 70.0, 0.0004, 1))
	shots.add_event(_event(2, 1, 1, 34.0, 0.0016, 2, 320.0))
	shots.add_event(_event(3, 2, 12, 45.0, 0.006, 3, 340.0))
	shots.set_time(40 * 0.05 + 0.3)
	assert_eq(shots.in_flight(), 14)
	assert_gt(shots.entry_count(), 14 * 5, "streaks, trails, fletches and shadows")
	assert_eq(shots.dropped, 0)
	shots.set_time(40 * 0.05 + 30.0)
	assert_eq(shots.in_flight(), 0)
	assert_eq(shots.shots.size(), 0, "finished shots are dropped")
	assert_null(shots.add_event({"type": "shot"}), "a malformed event is ignored")
