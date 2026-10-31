extends GutTest
## Real rules events through the real module and view into the kit, never a hand-fed cue: the owner played the game
## and heard no arrows, while the bank passed its scorecard and every hand-fed test. A real wave's `shot` events must
## each start a flight sound that lasts the flight.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX_SECONDS := 150.0
## What may count as a projectile's flight sound, by shot kind. The old names are here on purpose: they ran for a
## fifth of the flight on a fifth of the volleys, and that is what these tests catch.
const FLIGHT_SOUNDS := {
	SiegeIds.SHOT_BOLT: ["bolt_whoosh", "bolt_hiss"],
	SiegeIds.SHOT_STONE: ["stone_whoosh", "stone_tumble"],
	SiegeIds.SHOT_ARROW: ["arrow_whistle", "arrow_swarm"],
	SiegeIds.SHOT_SCORPION: ["bolt_whoosh", "bolt_hiss"],
}
## The surfaces a real first wave lands on, by the sounds that say so. Shield bearers come in later waves: the unit
## test below puts one under an arrow.
const SURFACE_SOUNDS := {
	"dirt": ["arrow_dirt", "bolt_dirt", "stone_impact"],
	"flesh": ["hit_flesh"],
	"wood": ["hit_wood", "bolt_wood", "stone_wood"],
}

var _game: SiegeGame = null
var _view: SiegeView = null
var _shots: Array[Dictionary] = []


func after_each() -> void:
	if _game != null:
		F.free_game(_game)
	_game = null
	_view = null
	_shots.clear()


func _on_cue(kind: String, data: Dictionary) -> void:
	if kind == SiegeIds.EV_SHOT:
		_shots.append(data)


## A real session's first `seconds`: one rider and three bots on the real rules. `seen` gets each new start of the kit.
func _ride(seconds: float, seen: Dictionary) -> void:
	var ctx := F.make_ctx(1, 3, "short", Wl.SOLO, 1, 3)
	_game = F.make_game(ctx)
	var plans := _game.build_effort_plans()
	var final := {}
	for peer: int in plans:
		final[peer] = PlanValidator.finalize(plans[peer])
	_view = _game.make_view() as SiegeView
	add_child_autofree(_view)
	_game.cue.connect(_on_cue)
	for tick in roundi(seconds / Wl.SIM_DT):
		_game.sim_step(Wl.SIM_DT, F.frame(ctx, final, tick))
		_view.update(Wl.SIM_DT)
		_collect(seen)


func _collect(seen: Dictionary) -> void:
	var kit := _view.audio.kit
	for i in kit.played.size():
		var id := kit.played[i]
		seen[id] = int(seen.get(id, 0)) + 1
	kit.clear_played()


func _shots_of(kind: int) -> int:
	var n := 0
	for s in _shots:
		if int(s.get("kind", -1)) == kind:
			n += 1
	return n


func test_every_shot_of_a_real_wave_starts_a_flight_sound() -> void:
	var seen := {}
	_ride(FIX_SECONDS, seen)
	var bolts := _shots_of(SiegeIds.SHOT_BOLT) + _shots_of(SiegeIds.SHOT_SCORPION)
	var arrows := _shots_of(SiegeIds.SHOT_ARROW)
	var stones := _shots_of(SiegeIds.SHOT_STONE)
	assert_gt(arrows, 10, "the organ fires in the first %d s" % FIX_SECONDS)
	assert_gt(bolts, 5, "the bolt throwers fire")
	assert_gt(stones, 2, "the onager fires")
	var flying := func(kind: int) -> int:
		var n := 0
		for id: String in FLIGHT_SOUNDS[kind]:
			n += int(seen.get(id, 0))
		return n
	assert_eq(flying.call(SiegeIds.SHOT_ARROW), arrows, "one flight per volley")
	assert_eq(flying.call(SiegeIds.SHOT_STONE), stones, "one flight per stone")
	assert_eq(flying.call(SiegeIds.SHOT_BOLT), bolts, "one flight per bolt, the Scorpion's too")


func test_every_flight_is_given_the_real_time_the_shot_flies() -> void:
	var seen := {}
	_ride(60.0, seen)
	var bank: SiegeContent = _game.state.content
	var path: SiegePath = _game.state.path
	assert_gt(_shots.size(), 5)
	for ev in _shots:
		var r := SiegeV2ShotReplay.from_event(ev, path, bank)
		var want := 0.0
		for j in r.n:
			want += r.land_t[j] / float(r.n)
		var got: float = float(_view.audio.flight_of(ev))
		assert_almost_eq(got, want, 0.02, "kind %d" % int(ev["kind"]))


func test_a_real_wave_lands_on_the_ground_and_on_every_kind_of_target() -> void:
	var seen := {}
	_ride(FIX_SECONDS, seen)
	for surface: String in SURFACE_SOUNDS:
		var n := 0
		for id: String in SURFACE_SOUNDS[surface]:
			n += int(seen.get(id, 0))
		assert_gt(n, 0, "%s heard in %d s of a real wave: %s" % [surface, FIX_SECONDS, seen])


func test_a_volley_is_not_twelve_voices() -> void:
	var seen := {}
	_ride(FIX_SECONDS, seen)
	var volleys := _shots_of(SiegeIds.SHOT_ARROW)
	var impacts := int(seen.get("arrow_dirt", 0)) + int(seen.get("hit_flesh", 0))
	impacts += int(seen.get("hit_shield", 0)) + int(seen.get("hit_wood", 0))
	assert_lte(
		float(impacts) / float(volleys), 7.0, "%d impacts of %d volleys" % [impacts, volleys]
	)
	assert_gt(float(impacts) / float(volleys), 0.8, "and each volley lands")


func test_a_real_first_wave_gives_every_shot_a_real_player() -> void:
	var ctx := F.make_ctx(1, 3, "short", Wl.SOLO, 1, 3)
	_game = F.make_game(ctx)
	var plans := _game.build_effort_plans()
	var final := {}
	for peer: int in plans:
		final[peer] = PlanValidator.finalize(plans[peer])
	_view = _game.make_view() as SiegeView
	add_child_autofree(_view)
	var kit := _view.audio.kit
	kit.force_audio = true
	kit.setup(SiegeAudio.BANK_PATH, 3)
	assert_false(kit.silent, "real players, on the Dummy driver")
	_game.cue.connect(_on_cue)
	var voiced := 0
	var was := 0
	for tick in roundi(40.0 / Wl.SIM_DT):
		_game.sim_step(Wl.SIM_DT, F.frame(ctx, final, tick))
		if kit.flight_starts > was:
			was = kit.flight_starts
			var f: GameAudioKit.Flight = kit._flights[kit._flights.size() - 1]
			if f.voice != null and f.voice.player.playing:
				voiced += 1
		_view.update(Wl.SIM_DT)
	assert_gt(kit.flight_starts, 5, "flights started")
	assert_eq(voiced, kit.flight_starts, "each on a player that plays")
	kit.stop_all()


func _sounds_of(kind: int, enemy_type: int, enemy_at_landing: bool) -> Array[Dictionary]:
	var st := SiegeKit.state("short", 1, 0)
	var sounds := SiegeShotSounds.new()
	sounds.content = st.content
	sounds.path = st.path
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	var src := SiegeIds.SRC_PAD + 1 if kind == SiegeIds.SHOT_SCORPION else 1
	if kind == SiegeIds.SHOT_ARROW:
		src = SiegeIds.STATION_ARROWS
	elif kind == SiegeIds.SHOT_STONE:
		src = SiegeIds.STATION_ONAGER
	var n := 12 if kind == SiegeIds.SHOT_ARROW else 1
	var ev := SiegeEvents.shot(0, src, kind, o, v, n, 77)
	sounds.add(ev, 0.0)
	var r := sounds.flying[0].replay
	var e := SiegeKit.enemy(st, enemy_type, 100.0)
	e.pos = r.landing(0) if enemy_at_landing else Vector3(-500.0, -500.0, 0.0)
	var out: Array[Dictionary] = []
	for i in 300:
		out.append_array(sounds.step(i * Wl.SIM_DT, st.enemies))
	return out


func _surfaces(list: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for imp in list:
		out.append(str(imp["surface"]))
	return out


func test_each_weapon_lands_on_each_surface_by_what_stands_there() -> void:
	var table := [
		[SiegeIds.SHOT_STONE, SiegeIds.ENEMY_SPEAR, "flesh"],
		[SiegeIds.SHOT_STONE, SiegeIds.ENEMY_RAM, "wood"],
		[SiegeIds.SHOT_STONE, SiegeIds.ENEMY_TOWER, "wood"],
		[SiegeIds.SHOT_STONE, SiegeIds.ENEMY_SHIELD, "shield"],
		[SiegeIds.SHOT_ARROW, SiegeIds.ENEMY_SPEAR, "flesh"],
		[SiegeIds.SHOT_ARROW, SiegeIds.ENEMY_RAM, "wood"],
		[SiegeIds.SHOT_SCORPION, SiegeIds.ENEMY_SPEAR, "flesh"],
		[SiegeIds.SHOT_SCORPION, SiegeIds.ENEMY_CHARIOT, "wood"],
		[SiegeIds.SHOT_BOLT, SiegeIds.ENEMY_RAM, "wood"],
	]
	for row: Array in table:
		var got := _surfaces(_sounds_of(row[0], row[1], true))
		assert_true(got.has(row[2]), "shot %d on enemy %d: %s" % [row[0], row[1], got])


func test_nothing_there_is_the_ground() -> void:
	for kind in [
		SiegeIds.SHOT_ARROW, SiegeIds.SHOT_STONE, SiegeIds.SHOT_BOLT, SiegeIds.SHOT_SCORPION
	]:
		assert_eq(
			_surfaces(_sounds_of(kind, SiegeIds.ENEMY_SPEAR, false))[0], "dirt", "kind %d" % kind
		)


func test_a_real_wave_hears_what_the_host_hit() -> void:
	var seen := {}
	_ride(300.0, seen)
	var st := _game.state
	var sounds: SiegeShotSounds = _view.audio._shots
	var near := func(got: int, truth: int, label: String) -> void:
		var slack := maxi(2, roundi(truth * 0.1))
		assert_gt(truth, 0, "%s: the host hit something in %d s" % [label, 300])
		assert_lte(
			absi(got - truth), slack, "%s: %d struck by ear, %d by the host" % [label, got, truth]
		)
	near.call(
		int(sounds.struck_count.get("stone", 0)), st.station(SiegeIds.STATION_ONAGER).hits, "stones"
	)
	near.call(
		int(sounds.struck_count.get("bolt", 0)), st.station(SiegeIds.STATION_BALLISTA).hits, "bolts"
	)
	var pads := 0
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		pads += st.pad(n).hits
	near.call(int(sounds.struck_count.get("scorpion", 0)), pads, "Scorpion bolts")
	# Arrows within a quarter: a body killed by the volley's first arrow still counts for RECENT_S.
	var arrows := st.station(SiegeIds.STATION_ARROWS).hits
	var heard := int(sounds.struck_count.get("arrow", 0))
	assert_gt(arrows, 0)
	assert_lte(
		absi(heard - arrows),
		maxi(5, roundi(arrows * 0.25)),
		"%d by ear, %d by the host" % [heard, arrows]
	)


func test_a_killing_blow_is_a_hit_and_not_a_miss() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var sounds := SiegeShotSounds.new()
	sounds.content = st.content
	sounds.path = st.path
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	var ev := SiegeEvents.shot(0, SiegeIds.STATION_ONAGER, SiegeIds.SHOT_STONE, o, v, 1, 77)
	sounds.add(ev, 0.0)
	var r := sounds.flying[0].replay
	var e := SiegeKit.enemy(st, SiegeIds.ENEMY_SPEAR, 100.0)
	e.pos = r.landing(0)
	var land := r.land_t[0]
	assert_eq(sounds.step(land - 0.05, st.enemies), [] as Array[Dictionary], "still in the air")
	st.enemies.clear()
	assert_eq(
		_surfaces(sounds.step(land + 0.05, st.enemies)),
		["flesh"] as Array[String],
		"the rules already took it off"
	)


func test_a_body_long_gone_is_the_ground_again() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var sounds := SiegeShotSounds.new()
	sounds.content = st.content
	sounds.path = st.path
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	sounds.add(SiegeEvents.shot(0, SiegeIds.STATION_ONAGER, SiegeIds.SHOT_STONE, o, v, 1, 77), 0.0)
	var r := sounds.flying[0].replay
	var e := SiegeKit.enemy(st, SiegeIds.ENEMY_SPEAR, 100.0)
	e.pos = r.landing(0)
	sounds.track(r.land_t[0] - SiegeShotSounds.RECENT_S - 0.5, st.enemies)
	st.enemies.clear()
	assert_eq(_surfaces(sounds.step(r.land_t[0] + 0.05, st.enemies)), ["dirt"] as Array[String])


func test_an_upgraded_onager_reaches_further_with_its_splash() -> void:
	for row: Array in [[0, "dirt"], [3, "flesh"]]:
		var st := SiegeKit.state("short", 1, 0)
		var sounds := SiegeShotSounds.new()
		sounds.content = st.content
		sounds.path = st.path
		var o: Array[int] = [8000, 12000, 1500]
		var v: Array[int] = [12000, 15000, 9000]
		var ev := SiegeEvents.shot(0, SiegeIds.STATION_ONAGER, SiegeIds.SHOT_STONE, o, v, 1, 77)
		sounds.add(ev, 0.0, row[0])
		var r := sounds.flying[0].replay
		var e := SiegeKit.enemy(st, SiegeIds.ENEMY_SPEAR, 100.0)
		e.pos = r.landing(0) + Vector3(5.8, 0.0, 0.0)
		assert_eq(
			_surfaces(sounds.step(r.land_t[0] + 0.05, st.enemies)),
			[row[1]] as Array[String],
			"level %d" % row[0]
		)


func test_every_kill_of_a_real_wave_knows_its_side() -> void:
	var seen := {}
	var ctx := F.make_ctx(1, 3, "short", Wl.SOLO, 1, 3)
	_game = F.make_game(ctx)
	var plans := _game.build_effort_plans()
	var final := {}
	for peer: int in plans:
		final[peer] = PlanValidator.finalize(plans[peer])
	_view = _game.make_view() as SiegeView
	add_child_autofree(_view)
	var kills := [0, 0]
	var on_kill := func(kind: String, data: Dictionary) -> void:
		if kind != SiegeIds.EV_KILL:
			return
		kills[0] += 1
		if _view.audio._shots.last_seen(int(data["id"])) is Vector3:
			kills[1] += 1
	_game.cue.connect(on_kill)
	for tick in roundi(120.0 / Wl.SIM_DT):
		_game.sim_step(Wl.SIM_DT, F.frame(ctx, final, tick))
		_view.update(Wl.SIM_DT)
		_collect(seen)
	assert_gt(kills[0], 5, "the first wave kills")
	assert_gte(kills[1], kills[0] - 2, "the host's kills found their bodies: %s" % [kills])


func test_a_shield_bearer_blocks_by_the_hosts_own_stream() -> void:
	var got := _surfaces(_sounds_of(SiegeIds.SHOT_ARROW, SiegeIds.ENEMY_SHIELD, true))
	assert_true(got.has("shield") or got.has("flesh"), "%s" % [got])


func test_a_volleys_misses_are_one_patter_and_its_hits_are_capped() -> void:
	var got := _surfaces(_sounds_of(SiegeIds.SHOT_ARROW, SiegeIds.ENEMY_SPEAR, false))
	assert_eq(got.count("dirt"), 1, "twelve arrows, one patter")
	var on_ram := _surfaces(_sounds_of(SiegeIds.SHOT_ARROW, SiegeIds.ENEMY_RAM, true))
	assert_lte(on_ram.count("wood"), SiegeShotSounds.MAX_HITS_PER_VOLLEY)


func test_the_moat_is_water_and_the_bridge_and_the_field_are_not() -> void:
	assert_eq(SiegeShotSounds.ground_at(Vector3(20.0, 68.0, 0.0)), "water", "before the south wall")
	assert_eq(SiegeShotSounds.ground_at(Vector3(44.0, 68.0, 0.0)), "dirt", "on the bridge")
	assert_eq(SiegeShotSounds.ground_at(Vector3(-8.0, 30.0, 0.0)), "water", "beside the west wall")
	assert_eq(SiegeShotSounds.ground_at(Vector3(-60.0, 45.0, 0.0)), "dirt", "the road")
	assert_eq(SiegeShotSounds.ground_at(Vector3(20.0, 30.0, 8.0)), "dirt", "inside the fort")


func test_a_patter_is_quieter_for_few_arrows() -> void:
	assert_almost_eq(SiegeAudio.patter_db(12), 0.0, 0.01)
	assert_almost_eq(SiegeAudio.patter_db(6), SiegeAudio.PATTER_HALVING_DB, 0.01)
	assert_gte(SiegeAudio.patter_db(1), SiegeAudio.PATTER_MIN_DB)
