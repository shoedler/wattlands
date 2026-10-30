extends GutTest
## Review fixes in the view: retreating bodies keep walking, rescue makes the walkers stumble,
## AFK paths go dark, and the arrow organ's fourth rack (upgrade 3) is counted.

const F := preload("res://tests/games/siege/siege_fakes.gd")


func _view(st: SiegeState, humans: int = 1) -> SiegeView:
	var g := F.make_game(F.make_ctx(humans, 0, "short", Wl.SOLO, 1))
	g.state = st
	g.content = st.content
	var v := g.make_view() as SiegeView
	add_child_autofree(v)
	autofree_game(g)
	return v


var _games: Array[SiegeGame] = []


func autofree_game(g: SiegeGame) -> void:
	_games.append(g)


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()


func test_retreating_bodies_are_drawn() -> void:
	var st := SiegeKit.state("short")
	var e := SiegeKit.enemy(st, SiegeIds.ENEMY_SPEAR, 200.0, 0.0, -1.0)
	e.st = SiegeIds.EN_RETREAT
	var v := _view(st)
	v.update(0.05)
	assert_eq(v.crowd.drawn, 1, "a retreating spearman walks back")


func test_rescue_makes_the_walkers_stumble() -> void:
	var st := SiegeKit.state("short", 2, 0)
	for r in st.riders:
		r.p_eff_w = 200.0
	st.rider_at(1).rescue = true
	var v := _view(st, 2)
	for _i in 12:
		v.update(0.05)
	assert_eq(v.stumbling[0], 0)
	assert_eq(v.stumbling[1], 1, "a rider in rescue stumbles")
	assert_true(v.machines.stumble[1])
	assert_false(v.machines.stumble[0])


func test_afk_paths_go_dark() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var r := st.rider_at(0)
	r.target = SiegeIds.STATION_ONAGER
	r.afk = true
	assert_eq(SiegeViewMath.lit_station(st, r), -1)
	var v := _view(st)
	v.update(0.05)
	assert_eq(v.machines.route[0], -1)


func test_the_fourth_rack_counts() -> void:
	var st := SiegeKit.state("short")
	var arrows := st.station(SiegeIds.STATION_ARROWS)
	arrows.level = 3
	# rack 0 is next, so the fourth rack (not drawn) fired last: the three drawn are loaded
	arrows.rack = 0
	arrows.arm = 0.2
	var v := _view(st)
	v.update(0.05)
	assert_eq(v.machines.racks, 7)
	arrows.rack = 3
	v.update(0.05)
	assert_eq(v.machines.racks, 7 & ~4, "rack 2 fired last")
	arrows.level = 0
	arrows.rack = 0
	v.update(0.05)
	assert_eq(v.machines.racks, 7 & ~4, "three racks: rack 2 fired last")
