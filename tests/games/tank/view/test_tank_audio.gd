extends GutTest
## Tank's synthesized sound (brief 3 Audio): every sound registered with Sfx, loops that follow
## cadence with the local station loudest, a chuff per steam stroke, shots, impacts, explosions, the
## lever and the hoist; silent and error-free headless.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")

var _audio: TankAudio = null
var _state: TankState = null


func before_each() -> void:
	_state = TankFixtures.state(3)
	var g := U.make_game(_state)
	autofree(g)
	_audio = TankAudio.new()
	_audio.game = g
	add_child_autofree(_audio)


func _feed(cadence: float) -> Dictionary:
	return U.feed_of(_state, 200.0, cadence)


func _step(dt: float = 0.05, cadence: float = 90.0, peer: int = 1) -> void:
	_audio.update(_state, dt, peer, _feed(cadence))


func test_every_sound_is_registered_with_sfx() -> void:
	var sfx := get_node("/root/Sfx") as WlSfx
	for key in TankAudio.SOUND_NAMES:
		assert_true(sfx.has_sound(key), key)
		assert_not_null(sfx.get_stream(key), key)
	for key: String in TankAudio.DEFS:
		assert_has(TankAudio.SOUND_NAMES, key)


func test_headless_makes_no_players_and_stays_silent() -> void:
	assert_true(_audio.silent)
	assert_eq(_audio.loop_players.size(), 0)
	_step()
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 1))
	assert_gt(_audio.played.size(), 0, "it still records what it would play")


func test_a_friendly_shot_booms_cracks_and_drops_brass() -> void:
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 1))
	assert_has(_audio.played, "tank_boom_low")
	assert_has(_audio.played, "tank_boom_crack")
	assert_does_not_have(_audio.played, "tank_brass")
	for _i in 10:
		_step()
	assert_has(_audio.played, "tank_brass", "the casing clinks a moment later")


func test_a_heavy_shot_is_louder_than_a_light_one_and_the_gunner_hears_it_loudest() -> void:
	_step(0.05, 90.0, 1)
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_LIGHT, 1))
	var light := _audio.played_db[0]
	_audio.played_db.clear()
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 2))
	var heavy := _audio.played_db[0]
	assert_gt(heavy, light)
	var other := _audio_for(3)
	other.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 3))
	assert_gt(heavy, other.played_db[0], "peer 1 works the dynamo, the gunner's station")


func _audio_for(peer: int) -> TankAudio:
	var a := TankAudio.new()
	a.game = _audio.game
	add_child_autofree(a)
	a.update(_state, 0.05, peer, _feed(90.0))
	return a


func test_bow_guns_rattle_and_enemy_guns_whistle_in() -> void:
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_BOW, 1))
	for _i in 6:
		_step()
	assert_gte(_audio.played.count("tank_bow_rattle"), 4, "a burst rattles")
	assert_does_not_have(_audio.played, "tank_boom_low", "not the cannon")
	_audio.played.clear()
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 2, 11, 2))
	assert_eq(_audio.played[0], "tank_boom_small")
	for _i in 8:
		_step()
	assert_has(_audio.played, "tank_whistle", "the shell whistles on its way")
	_audio.played.clear()
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_BOSS_MAIN, 3))
	assert_has(_audio.played, "tank_boom_low", "the Behemoth's main gun is a boom")


func test_impacts_explosions_ram_breakdown_lever_and_latch() -> void:
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_TANK, 0, 20.0, TankIds.SHELL_ENEMY, 0.0, 3300.0)
	)
	assert_has(_audio.played, "tank_hit")
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(11, 2, TankEvents.BY_SHELL, 0))
	assert_has(_audio.played, "tank_boom_big")
	_audio.on_cue(TankEvents.RAM, TankEvents.ram(2, true, 12))
	assert_has(_audio.played, "tank_ram")
	_audio.on_cue(TankEvents.BREAKDOWN, TankEvents.breakdown())
	assert_has(_audio.played, "tank_breakdown")
	_audio.on_cue(TankEvents.LEVER, TankEvents.lever(0, TankIds.LEVER_HOIST))
	assert_has(_audio.played, "tank_clunk")
	_audio.played.clear()
	_audio.on_cue(TankEvents.LATCH, TankEvents.latch(1, TankIds.SHELL_HEAVY))
	assert_has(_audio.played, "tank_hiss", "the steam latch hisses")


func test_a_bulwark_latch_ratchets_instead_of_hissing() -> void:
	var s := TankFixtures.state(1)
	var g := U.make_game(s)
	autofree(g)
	var a := TankAudio.new()
	a.game = g
	add_child_autofree(a)
	a.on_cue(TankEvents.LATCH, TankEvents.latch(0, TankIds.SHELL_HEAVY))
	assert_eq(a.played[0], "tank_ratchet")


func test_the_boss_dying_is_a_long_roll_of_booms() -> void:
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(-4, TankIds.BOSS_CODE, TankEvents.BY_SHELL, 0))
	for _i in 30:
		_step()
	var booms := _audio.played.count("tank_boom_big")
	assert_gte(booms, 3)


func test_loops_follow_cadence_and_the_local_station_is_loudest() -> void:
	_step(0.05, 90.0, 1)
	assert_eq(_audio.own_engine, TankIds.ENGINE_DYNAMO, "peer 1 works the dynamo in Stage 2")
	assert_eq(_audio.loop_db[TankIds.ENGINE_DYNAMO], TankAudio.OWN_DB[TankIds.ENGINE_DYNAMO])
	assert_eq(_audio.loop_db[TankIds.ENGINE_DIESEL], TankAudio.OTHER_DB[TankIds.ENGINE_DIESEL])
	assert_gt(
		_audio.loop_db[TankIds.ENGINE_DYNAMO] - TankAudio.OTHER_DB[TankIds.ENGINE_DYNAMO],
		5.0,
		"your own room is clearly louder than it would be as a teammate's"
	)
	_step(0.05, 90.0, 3)
	assert_eq(_audio.own_engine, TankIds.ENGINE_DIESEL)
	assert_eq(_audio.loop_db[TankIds.ENGINE_DIESEL], TankAudio.OWN_DB[TankIds.ENGINE_DIESEL])
	assert_eq(_audio.loop_db[TankIds.ENGINE_DYNAMO], TankAudio.OTHER_DB[TankIds.ENGINE_DYNAMO])


func test_pitch_rises_with_cadence_and_the_whine_climbs_faster() -> void:
	_step(0.05, 30.0)
	var rumble_low: float = _audio.loop_pitch[TankIds.ENGINE_DIESEL]
	var whine_low: float = _audio.loop_pitch[TankIds.ENGINE_DYNAMO]
	_step(0.05, 110.0)
	assert_gt(_audio.loop_pitch[TankIds.ENGINE_DIESEL], rumble_low)
	assert_gt(_audio.loop_pitch[TankIds.ENGINE_DYNAMO], whine_low)
	assert_almost_eq(TankAudio.pitch_for(0.0, 120.0, TankAudio.RUMBLE_PITCH), 0.7, 1e-6)
	assert_almost_eq(TankAudio.pitch_for(120.0, 120.0, TankAudio.RUMBLE_PITCH), 1.7, 1e-6)
	assert_almost_eq(TankAudio.pitch_for(240.0, 120.0, TankAudio.WHINE_PITCH), 2.0, 1e-6, "clamped")


func test_loops_stop_without_cadence_power_or_a_room() -> void:
	_step(0.05, 90.0)
	assert_true(_audio.loop_on[TankIds.ENGINE_DIESEL])
	_step(0.05, 3.0)
	assert_false(_audio.loop_on[TankIds.ENGINE_DIESEL], "a coasting engine falls silent")
	_state.station(TankIds.ENGINE_DIESEL).unpowered = true
	_step(0.05, 90.0)
	assert_false(_audio.loop_on[TankIds.ENGINE_DIESEL])
	assert_false(_audio.loop_on[TankIds.ENGINE_BULWARK], "the Citadel has no gearbox room")
	_state.all_afk = true
	_step(0.05, 90.0)
	assert_false(_audio.loop_on[TankIds.ENGINE_DYNAMO])


func test_a_reserve_room_hums_at_a_steady_slow_pitch() -> void:
	_state.station(TankIds.ENGINE_DIESEL).reserve = true
	_step(0.05, 120.0)
	assert_true(_audio.loop_on[TankIds.ENGINE_DIESEL])
	assert_lt(_audio.loop_pitch[TankIds.ENGINE_DIESEL], 1.2)


func test_steam_chuffs_once_per_stroke_and_the_loader_hears_it_loudest() -> void:
	var chuffs := 0
	for _i in 60:
		_step(0.05, 60.0, 2)
	chuffs = _audio.played.count("tank_chuff")
	assert_almost_eq(float(chuffs), 3.0, 1.0, "60 rpm for 3 s: three strokes")
	var own_db := _audio.played_db[_audio.played.find("tank_chuff")]
	var other := _audio_for(1)
	for _i in 22:
		other.update(_state, 0.05, 1, _feed(60.0))
	assert_gt(own_db, other.played_db[other.played.find("tank_chuff")], "peer 2 is on steam")


func test_the_chuff_pitch_follows_pressure() -> void:
	var steam := _state.station(TankIds.ENGINE_STEAM) as TankSteamState
	steam.pressure_pct = 10.0
	for _i in 30:
		_step(0.05, 70.0, 2)
	var low := _audio.played_db.size()
	assert_gt(low, 0)
	steam.pressure_pct = 140.0
	_audio.played.clear()
	for _i in 30:
		_step(0.05, 70.0, 2)
	assert_has(_audio.played, "tank_chuff")


func test_the_tracks_clank_faster_the_faster_the_tank_goes() -> void:
	_state.hull.speed_mps = 0.0
	for _i in 20:
		_step()
	assert_false(_audio.played.has("tank_clank"), "silent when stopped")
	_state.hull.speed_mps = 3.0
	for _i in 40:
		_step()
	var slow := _audio.played.count("tank_clank")
	_audio.played.clear()
	_state.hull.speed_mps = 9.0
	for _i in 40:
		_step()
	assert_gt(_audio.played.count("tank_clank"), slow)


func test_the_hoist_ratchets_while_a_shell_is_lifted() -> void:
	var s := TankFixtures.state(1)
	var g := U.make_game(s)
	autofree(g)
	var a := TankAudio.new()
	a.game = g
	add_child_autofree(a)
	var gb := s.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	gb.lever = TankIds.LEVER_HOIST
	gb.lever_to = TankIds.LEVER_HOIST
	gb.move_s = 0.0
	for i in 30:
		gb.hoist_j += 60.0
		a.update(s, 0.05, 1, U.feed_of(s, 200.0, 90.0))
	assert_gt(a.played.count("tank_ratchet"), 3)
	a.played.clear()
	gb.lever = TankIds.LEVER_DRIVE
	for i in 30:
		gb.hoist_j += 60.0
		a.update(s, 0.05, 1, U.feed_of(s, 200.0, 90.0))
	assert_eq(a.played.count("tank_ratchet"), 0, "only on Hoist")


func test_the_recorded_sounds_stay_bounded() -> void:
	for _i in TankAudio.PLAYED_MAX * 2:
		_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_LIGHT, 1))
	assert_lte(_audio.played.size(), TankAudio.PLAYED_MAX)
	assert_eq(_audio.played.size(), _audio.played_db.size())


func test_the_view_feeds_the_audio_every_frame() -> void:
	var v := U.view_of(self, TankFixtures.state(3))
	assert_not_null(v.audio)
	v.game.cue.emit(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 1))
	v.advance(0.016)
	assert_has(v.audio.played, "tank_boom_low")
	assert_eq(v.audio.local_peer, 1)
	assert_true(v.audio.loop_on[TankIds.ENGINE_DYNAMO])


func test_the_arc_generator_hums_and_crackles_on_its_riders_cadence() -> void:
	var s := U.fixture("state", 4)
	var g := U.make_game(s)
	autofree(g)
	var a := TankAudio.new()
	a.game = g
	add_child_autofree(a)
	var me := s.rider_at(s.station(TankIds.ENGINE_ARC).slot).peer
	for _i in 40:
		a.update(s, 0.05, me, U.feed_of(s, 180.0, 90.0))
	assert_true(a.loop_on[TankIds.ENGINE_ARC], "the hum runs")
	assert_eq(
		a.loop_db[TankIds.ENGINE_ARC], TankAudio.OWN_DB[TankIds.ENGINE_ARC], "its rider's own"
	)
	# 90 rpm, two climbs a revolution: about 6 crackles in 2 s.
	assert_between(a.played.count("tank_arc_crackle"), 4, 7)
	a.played.clear()
	for _i in 40:
		a.update(s, 0.05, me, U.feed_of(s, 0.0, 0.0))
	assert_false(a.loop_on[TankIds.ENGINE_ARC], "stopped at 0 rpm")
	assert_eq(a.played.count("tank_arc_crackle"), 0)


func test_the_night_ambience_and_its_crickets() -> void:
	for _i in 120:
		_step()
	assert_true(_audio.ambience_on)
	assert_gt(_audio.played.count("tank_cricket"), 2, "crickets in 6 s")
