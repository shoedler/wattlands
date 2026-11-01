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
	"flesh": ["arrow_flesh", "hit_flesh"],
	"wood": ["arrow_wood", "hit_wood", "bolt_wood", "stone_wood"],
}
const ARROW_BODY := ["arrow_flesh", "arrow_wood"]
const ARROW_OTHER := ["arrow_shield", "arrow_dirt", "arrow_water"]
const ARROW_FILES := ["arrow_flesh", "arrow_wood", "arrow_shield", "arrow_dirt", "arrow_water"]

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


func _sum(seen: Dictionary, ids: Array) -> int:
	var n := 0
	for id: String in ids:
		n += int(seen.get(id, 0))
	return n


## The owner: "arrow hits still make no sound. they should individually make a sound."
func test_every_arrow_that_lands_in_a_real_wave_makes_one_sound() -> void:
	var seen := {}
	_ride(FIX_SECONDS, seen)
	var sounds: SiegeShotSounds = _view.audio._shots
	var landed := int(sounds.landed_count.get("arrow", 0))
	var struck := int(sounds.struck_count.get("arrow", 0))
	assert_gt(landed, 500, "a real wave lands hundreds of arrows")
	assert_gt(struck, 20, "and strikes bodies")
	assert_eq(_sum(seen, ARROW_FILES), landed, "one sound per arrow: %s" % [seen])
	assert_eq(_sum(seen, ARROW_BODY), struck, "one body sound per arrow that struck")
	assert_eq(_sum(seen, ARROW_OTHER), landed - struck, "and the rest by what they fell on")
	var hits := _game.state.station(SiegeIds.STATION_ARROWS).hits
	assert_lte(absi(struck - hits), maxi(5, roundi(hits * 0.25)), "%d, host %d" % [struck, hits])


func test_a_shot_past_the_cap_of_a_tick_has_no_flight_and_still_lands() -> void:
	var seen := {}
	_ride(0.05, seen)
	seen.clear()
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	var tick := _game.state.tick
	var volleys := SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK + 2
	var was: int = _view.audio.kit.flight_starts
	for k in volleys:
		var ev := SiegeEvents.shot(
			tick, SiegeIds.STATION_ARROWS, SiegeIds.SHOT_ARROW, o, v, 12, 70 + k
		)
		_view.audio.on_cue(SiegeIds.EV_SHOT, ev)
	_view.audio.kit.commit(0.2)
	assert_eq(_view.audio.kit.flight_starts - was, SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK)
	var t := _view.clock_s
	for i in 200:
		t += Wl.SIM_DT
		for imp: Dictionary in _view.audio._shots.step(t, _game.state.enemies):
			seen[imp["weapon"]] = int(seen.get(imp["weapon"], 0)) + 1
	assert_eq(int(seen.get("arrow", 0)), 12 * volleys)


func test_every_arrow_lands_at_its_own_moment_and_place() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var sounds := SiegeShotSounds.new()
	sounds.content = st.content
	sounds.path = st.path
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	var ev := SiegeEvents.shot(0, SiegeIds.STATION_ARROWS, SiegeIds.SHOT_ARROW, o, v, 12, 77)
	sounds.add(ev, 0.0)
	var r := sounds.flying[0].replay
	var heard: Array[Vector3] = []
	var t := 0.0
	while heard.size() < 12 and t < 12.0:
		t += 1.0 / 60.0
		var due := 0
		for j in r.n:
			if r.land_t[j] <= t:
				due += 1
		for imp: Dictionary in sounds.step(t, st.enemies):
			heard.append(imp["at"])
		assert_eq(heard.size(), due, "at %.3f s" % t)
	for j in r.n:
		assert_true(heard.has(r.landing(j)), "arrow %d where it comes down" % j)


## Real players on the Dummy driver. A full crowd pool or a flight losing its voice to an arrow would show here.
func test_arrows_play_on_their_own_pool_and_take_nothing_from_the_rest() -> void:
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
	var on_sfx := 0
	for tick in roundi(150.0 / Wl.SIM_DT):
		_game.sim_step(Wl.SIM_DT, F.frame(ctx, final, tick))
		_view.update(Wl.SIM_DT)
		for v: GameAudioKit.Voice in kit._pools[AudioBuses.SFX]:
			if v.player.stream != null and v.player.playing:
				var file := str(v.player.stream.resource_path).get_file()
				on_sfx += 1 if file.begins_with("arrow_") and _landing_file(file) else 0
	var crowd: Array = kit._pools[GameAudioKit.CROWD]
	assert_gt(crowd.size(), 1, "arrows landed on the crowd's players")
	assert_lte(crowd.size(), int(kit._bank.mix["crowd_voices"]))
	assert_eq(on_sfx, 0, "no arrow's landing on a player of the flights")
	assert_eq(kit.crowd_voiceless, 0, "no arrow dropped")
	kit.stop_all()


## A volley over one body and nothing else, stepped as a view does. {t, accent, surface} per arrow, in landing order.
func _landings_of(enemy_type: int, at_landing: bool) -> Array[Dictionary]:
	var st := SiegeKit.state("short", 1, 0)
	var sounds := SiegeShotSounds.new()
	sounds.content = st.content
	sounds.path = st.path
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	var ev := SiegeEvents.shot(0, SiegeIds.STATION_ARROWS, SiegeIds.SHOT_ARROW, o, v, 12, 77)
	sounds.add(ev, 0.0)
	var r := sounds.flying[0].replay
	var e := SiegeKit.enemy(st, enemy_type, 100.0)
	e.pos = r.landing(sounds.flying[0].order[6]) if at_landing else Vector3(-500.0, -500.0, 0.0)
	var out: Array[Dictionary] = []
	var t := 0.0
	while out.size() < 12 and t < 12.0:
		t += 1.0 / 60.0
		for imp: Dictionary in sounds.step(t, st.enemies):
			out.append({"t": t, "accent": bool(imp["accent"]), "surface": imp["surface"]})
	return out


func test_accents_are_at_most_one_a_gap_and_the_first_of_a_volley_of_misses_is_one() -> void:
	var list := _landings_of(SiegeIds.ENEMY_SPEAR, false)
	assert_eq(list.size(), 12)
	assert_true(list[0]["accent"], "the earliest landing")
	var last := -INF
	var n := 0
	for imp: Dictionary in list:
		if imp["accent"]:
			n += 1
			assert_gte(imp["t"] - last, SiegeShotSounds.ACCENT_GAP_S - 1.0 / 60.0, "apart")
			last = imp["t"]
	assert_gt(n, 1, "a volley has several")
	assert_lt(n, 12, "and they stand out from the rest")


func test_every_body_is_an_accent_whatever_the_gap() -> void:
	var list := _landings_of(SiegeIds.ENEMY_SPEAR, true)
	var bodies := 0
	for k in list.size():
		if list[k]["surface"] != "flesh":
			continue
		bodies += 1
		assert_true(list[k]["accent"], "arrow %d struck a body" % k)
	assert_gt(bodies, 0, "the volley struck it")


func test_a_miss_is_no_accent_inside_the_gap_of_a_body() -> void:
	var list := _landings_of(SiegeIds.ENEMY_SPEAR, true)
	var body_t: Array[float] = []
	for imp: Dictionary in list:
		if imp["surface"] == "flesh":
			body_t.append(imp["t"])
	for imp: Dictionary in list:
		if imp["surface"] == "flesh" or not imp["accent"]:
			continue
		for t: float in body_t:
			# A miss landing ahead of a body waits for it; one after it waits out the gap.
			assert_false(
				absf(imp["t"] - t) < SiegeShotSounds.ACCENT_GAP_S - 1.0 / 30.0,
				"a miss at %.3f, a body at %.3f" % [imp["t"], t]
			)


func test_accents_keep_their_gap_across_volleys() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var sounds := SiegeShotSounds.new()
	sounds.content = st.content
	sounds.path = st.path
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	for k in 2:
		var ev := SiegeEvents.shot(
			0, SiegeIds.STATION_ARROWS, SiegeIds.SHOT_ARROW, o, v, 12, 70 + k
		)
		sounds.add(ev, 0.02 * k)
	var last := -INF
	var t := 0.0
	while t < 12.0:
		t += 1.0 / 60.0
		for imp: Dictionary in sounds.step(t, st.enemies):
			if imp["accent"]:
				assert_gte(t - last, SiegeShotSounds.ACCENT_GAP_S - 1.0 / 60.0)
				last = t


func test_bodies_landing_together_step_back_by_how_many() -> void:
	assert_almost_eq(SiegeAudio.pile_db(1), 0.0, 0.001, "one body is all there")
	assert_almost_eq(SiegeAudio.pile_db(2), SiegeAudio.ARROW_PILE_DB, 0.001)
	assert_almost_eq(SiegeAudio.pile_db(12), SiegeAudio.ARROW_PILE_DB * 3.585, 0.01)


func test_no_file_twice_running_and_the_order_is_not_a_rotation() -> void:
	var was := 0
	var steps := {}
	for n in 2000:
		var file := SiegeAudio.next_file(was, n, 4)
		assert_ne(file, was, "arrow %d" % n)
		assert_between(file, 0, 3)
		steps[posmod(file - was, 4)] = true
		was = file
	assert_eq(steps.size(), 3, "every other file can follow")
	assert_eq(SiegeAudio.next_file(0, 7, 1), 0, "one file is that file")


static func _landing_file(file: String) -> bool:
	for id: String in ARROW_FILES:
		if file.begins_with(id):
			return true
	return false


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


func test_a_volley_on_a_body_is_twelve_sounds_by_where_each_arrow_fell() -> void:
	var got := _surfaces(_sounds_of(SiegeIds.SHOT_ARROW, SiegeIds.ENEMY_RAM, true))
	assert_eq(got.size(), 12, "%s" % [got])
	assert_gt(got.count("wood"), 0, "%s" % [got])
	assert_eq(got.count("wood") + got.count("dirt") + got.count("water"), 12, "%s" % [got])


func test_a_volley_of_misses_is_twelve_small_sounds() -> void:
	var got := _surfaces(_sounds_of(SiegeIds.SHOT_ARROW, SiegeIds.ENEMY_SPEAR, false))
	assert_eq(got.count("dirt") + got.count("water"), 12, "%s" % [got])


func test_the_moat_is_water_and_the_bridge_and_the_field_are_not() -> void:
	assert_eq(SiegeShotSounds.ground_at(Vector3(20.0, 68.0, 0.0)), "water", "before the south wall")
	assert_eq(SiegeShotSounds.ground_at(Vector3(44.0, 68.0, 0.0)), "dirt", "on the bridge")
	assert_eq(SiegeShotSounds.ground_at(Vector3(-8.0, 30.0, 0.0)), "water", "beside the west wall")
	assert_eq(SiegeShotSounds.ground_at(Vector3(-60.0, 45.0, 0.0)), "dirt", "the road")
	assert_eq(SiegeShotSounds.ground_at(Vector3(20.0, 30.0, 8.0)), "dirt", "inside the fort")


func test_each_arrow_has_a_small_pitch_and_level_of_its_own() -> void:
	var low := 9.0
	var high := -9.0
	var quiet := 0.0
	for n in 2000:
		var s := SiegeAudio.arrow_spread(n)
		low = minf(low, s.x)
		high = maxf(high, s.x)
		quiet = minf(quiet, s.y)
		assert_lte(s.y, 0.0)
	assert_almost_eq(low, 1.0 - SiegeAudio.ARROW_PITCH_SPREAD, 0.002)
	assert_almost_eq(high, 1.0 + SiegeAudio.ARROW_PITCH_SPREAD, 0.002)
	assert_almost_eq(quiet, -SiegeAudio.ARROW_DB_SPREAD, 0.01)


## An hour of arrows at about 14 a second, on one surface's four variants: the same file at the same pitch and level,
## to within what an ear could tell, must not come back soon. The closest pair is its figure in docs/decisions.
func test_an_hour_of_arrows_does_not_repeat_itself() -> void:
	var last := {}
	var closest := 1 << 30
	var file := 0
	for n in 14 * 3600:
		var s := SiegeAudio.arrow_spread(n)
		file = SiegeAudio.next_file(file, n, 4)
		var key := Vector3i(file, roundi(s.x / 0.002), roundi(s.y / 0.25))
		if last.has(key):
			closest = mini(closest, n - int(last[key]))
		last[key] = n
	assert_gte(closest, 100, "the same arrow again after %d arrows" % closest)
