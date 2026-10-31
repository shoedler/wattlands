extends GutTest
## What v4 asks of the sound beyond the seats: a near threat you hear before you look, a far one that stays far, the
## tread under a tow, and a banner that is not a safety prompt. Levels are read_over.mjs's; this holds the wiring.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const DT := 1.0 / 60.0

var _state: TankState = null
var _audio: TankAudio = null


func before_each() -> void:
	AudioBuses.clear_ducks()
	_state = TankFixtures.state(3)
	_audio = _make(_state)


func after_each() -> void:
	AudioBuses.clear_ducks()


func _make(state: TankState) -> TankAudio:
	var g := U.make_game(state, Wl.SOLO, 1)
	autofree(g)
	var a := TankAudio.new()
	a.game = g
	add_child_autofree(a)
	return a


func _idle(seconds: float, far_fight: bool = false) -> void:
	for _i in roundi(seconds / DT):
		_audio.update(_state, DT, 1, {}, 0.0, far_fight)


func _near_state() -> TankState:
	_state = TankFixturesV4.make("near_ambush")
	_audio = _make(_state)
	return _state


func _near_of(s: TankState, type: String) -> TankEnemyState:
	for e: TankEnemyState in s.enemies:
		if e.is_near() and TankIds.enemy_of(e.code) == type:
			return e
	return null


## Only this enemy left on the field.
func _alone(s: TankState, e: TankEnemyState) -> void:
	s.enemies.clear()
	s.enemies.append(e)


func _front(s: TankState) -> float:
	return s.hull.x_px + float(s.hull.hull_w)


# --- The near engines -------------------------------------------------------------------------------------


func test_a_near_engine_is_as_near_as_the_rules_place_it() -> void:
	var s := _near_state()
	var e := _near_of(s, TankIds.ENEMY_RECON)
	_alone(s, e)
	e.mode = TankIds.EM_MOVE
	e.x_px = _front(s) + 30.0
	_idle(0.5)
	var recon := _audio.kit.entry_loop("recon_engine")
	var close: float = recon.db[0]
	assert_almost_eq(close, -4.5, 0.3, "the bank's level, undimmed at the bush")
	e.x_px = _front(s) + 185.0
	_idle(0.5)
	assert_almost_eq(recon.db[0], close - 4.0, 0.3, "at the edge of its dash")


func test_it_revs_as_it_drives_and_idles_down_to_fire() -> void:
	var s := _near_state()
	var e := _near_of(s, TankIds.ENEMY_TANKETTE)
	_alone(s, e)
	e.x_px = _front(s) + 80.0
	e.mode = TankIds.EM_MOVE
	_idle(1.0)
	var loop := _audio.kit.entry_loop("tankette_engine")
	var driving_pitch: float = loop.pitch[0]
	var driving_db: float = loop.db[0]
	e.mode = TankIds.EM_PAUSE
	_idle(1.0)
	assert_lt(loop.pitch[0], driving_pitch, "idles down")
	assert_lt(loop.db[0], driving_db)


func test_one_that_escapes_drives_on_and_fades_out() -> void:
	var s := _near_state()
	var e := _near_of(s, TankIds.ENEMY_RECON)
	_alone(s, e)
	e.mode = TankIds.EM_LEAVE
	e.x_px = _front(s) + TankConst.NEAR_SPAN_PX
	_idle(0.3)
	var loop := _audio.kit.entry_loop("recon_engine")
	var was: float = loop.db[0]
	s.enemies.clear()
	_audio.on_cue(TankEvents.ESCAPED, TankEvents.escaped(e.id, e.code))
	_idle(0.5)
	assert_gt(loop.db[0], LayeredLoop.OFF_DB, "still there after the event")
	assert_lt(loop.db[0], was, "further off")
	assert_gt(loop.db[0], was - 12.0, "a fade, not a cut")
	var left := (TankAudio.NEAR_GONE_PX - TankConst.NEAR_SPAN_PX) / TankAudio.NEAR_FLEE_PX_S
	_idle(left + 0.5)
	assert_true(loop.all_off(), "gone")


func test_a_kill_ends_the_engine_at_once() -> void:
	var s := _near_state()
	var e := _near_of(s, TankIds.ENEMY_RECON)
	_alone(s, e)
	e.x_px = _front(s) + 60.0
	_idle(0.3)
	var loop := _audio.kit.entry_loop("recon_engine")
	s.enemies.clear()
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(e.id, e.code, TankEvents.BY_BOW, 0))
	_idle(0.2)
	assert_true(loop.all_off(), "no ghost of a dead car")


func test_an_escape_nobody_heard_starts_nothing() -> void:
	var recon := TankIds.enemy_code(TankIds.ENEMY_RECON)
	_audio.on_cue(TankEvents.ESCAPED, TankEvents.escaped(41, recon))
	_idle(0.2)
	assert_does_not_have(_audio.played, "recon_engine")


func test_a_tow_clears_the_road_of_engines_too() -> void:
	var s := _near_state()
	var e := _near_of(s, TankIds.ENEMY_RECON)
	_alone(s, e)
	e.x_px = _front(s) + TankConst.NEAR_SPAN_PX
	_idle(0.3)
	var loop := _audio.kit.entry_loop("recon_engine")
	s.enemies.clear()
	_audio.on_cue(TankEvents.ESCAPED, TankEvents.escaped(e.id, e.code))
	s.hull.tow_s = 8.0
	_idle(0.3)
	assert_true(loop.all_off())


# --- Its fire ---------------------------------------------------------------------------------------------


func test_a_near_gun_cracks_at_once_with_no_thump_or_whistle() -> void:
	var recon := TankIds.enemy_code(TankIds.ENEMY_RECON)
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 9, 41, recon))
	_idle(4.0)
	assert_has(_audio.played, "small_mg")
	assert_does_not_have(_audio.played, "enemy_thump")
	assert_does_not_have(_audio.played, "incoming_whistle")


func test_its_round_rings_on_the_plate_and_is_no_shell() -> void:
	_audio.on_cue(
		TankEvents.HIT, TankEvents.hit(TankEvents.ON_TANK, 0, 1.0, TankIds.SHELL_ENEMY, 0.0, 300.0)
	)
	assert_has(_audio.played, "hull_hit")
	assert_does_not_have(_audio.played, "incoming_impact_near")
	_audio.kit.clear_played()
	_audio.on_cue(
		TankEvents.HIT, TankEvents.hit(TankEvents.ON_TANK, 0, 3.0, TankIds.SHELL_ENEMY, 0.0, 300.0)
	)
	assert_has(_audio.played, "incoming_impact_near", "a far tank's lightest shell lands")


func test_a_shell_on_a_broken_down_hull_still_lands() -> void:
	_state.hull.breakdown = true
	_audio.on_cue(
		TankEvents.HIT, TankEvents.hit(TankEvents.ON_TANK, 0, 0.0, TankIds.SHELL_ENEMY, 0.0, 300.0)
	)
	assert_has(_audio.played, "incoming_impact_near", "the rules report 0 damage then")


func test_the_ambush_ducks_the_room_so_the_bush_is_heard() -> void:
	var recon := TankIds.enemy_code(TankIds.ENEMY_RECON)
	_audio.on_cue(TankEvents.AMBUSH, TankEvents.ambush(41, recon))
	assert_has(_audio.played, "near_burst")
	AudioBuses.tick(0.02)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -4.0, 0.01)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.AMBIENCE), -6.0, 0.01)


# --- Far stays far ----------------------------------------------------------------------------------------


func test_every_flight_ends_its_whistle_at_impact() -> void:
	for range_m: float in [800.0, 1100.0, 1400.0, 1900.0, 2200.0, 2500.0]:
		var elev := TankBallistics.far_elevation(range_m, 560.0, 70.0)
		var flight := TankBallistics.far_flight(elev, 560.0, 70.0)
		var heard := (
			TankAudio.whistle_delay(flight)
			+ TankAudio.WHISTLE_FILE_S / TankAudio.whistle_rate(flight)
		)
		assert_almost_eq(heard, flight, 0.01, "%d m" % int(range_m))


func test_a_long_flight_waits_before_its_whistle() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_audio.on_cue(
		TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 9, 11, medium, 4.67, 2500.0)
	)
	assert_does_not_have(_audio.played, "incoming_whistle", "the shell is still far")
	var waits := TankAudio.whistle_delay(4.67)
	assert_gt(waits, 0.5)
	_idle(waits - 0.1)
	assert_does_not_have(_audio.played, "incoming_whistle")
	_idle(0.2)
	assert_has(_audio.played, "incoming_whistle")


func test_the_behemoths_main_gun_is_deeper_and_louder_than_a_tank() -> void:
	var shot := TankEvents.shot(-1, TankIds.SHELL_BOSS_MAIN, 9, 11, TankIds.BOSS_CODE, 2.5, 1400.0)
	_audio.on_cue(TankEvents.SHOT, shot)
	_idle(TankAudio.boom_delay(1400.0) + 0.1)
	var at := _audio.played.find("enemy_thump")
	assert_gt(at, -1)
	var level := 3.0 + TankAudio.range_db(1400.0) + TankAudio.BOSS_THUMP_DB
	assert_almost_eq(_audio.played_db[at], level, 0.001)


func test_no_far_battle_while_a_real_one_stands_in_the_far_panel() -> void:
	_state.seg.seg = TankIds.SEG_ADVANCE
	_idle(0.1)
	assert_eq(_audio.bed_now["combat"], 1.0)
	_idle(0.1, true)
	assert_eq(_audio.bed_now["combat"], 0.0, "a thump there is a shot at this tank")


func test_the_view_says_what_its_far_panel_shows() -> void:
	var near := TankFixturesV4.make("near_ambush")
	for e: TankEnemyState in near.enemies.duplicate():
		if not e.is_near():
			near.enemies.erase(e)
	near.seg.seg = TankIds.SEG_ADVANCE
	var v := U.view_of(self, near)
	U.run(v, 3, DT)
	assert_eq(v.audio.bed_now["combat"], 1.0, "near threats are not a far fight")
	var far := TankEnemyState.new()
	far.id = 900
	far.code = TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	far.hp = 50.0
	far.hp_max = 50.0
	far.range_m = 1400.0
	near.enemies.append(far)
	U.run(v, 3, DT)
	assert_eq(v.audio.bed_now["combat"], 0.0)


# --- The tread under a tow --------------------------------------------------------------------------------


func test_the_links_follow_the_reversed_tread_under_a_tow() -> void:
	var state := TankFixtures.state(3)
	state.hull.speed_mps = 0.0
	var v := U.view_of(self, state)
	U.run(v, 2, DT)
	v.audio.kit.clear_played()
	state.hull.tow_s = 8.0
	var from := v.travel
	U.run(v, 240, DT)
	assert_lt(v.travel, from, "the tread runs backwards on screen")
	assert_has(v.audio.played, "track_link")
	var voice := v.audio.kit.machine_voice(TankAudio.TRACK)
	var turned := (from - v.travel) / (TankConst.PX_PER_M * TankView.S) / TankAudio.TRACK_M_PER_REV
	assert_almost_eq(voice.planned_to(), turned, 0.1, "as far as the tread went, always forward")
	state.hull.tow_s = 0.0
	v.audio.kit.clear_played()
	U.run(v, 30, DT)
	assert_does_not_have(v.audio.played, "track_link", "a standing tank after it")


# --- The sixth seat ---------------------------------------------------------------------------------------


func test_the_hammer_you_see_is_the_hammer_you_hear() -> void:
	var s := TankFixturesV4.make("repair")
	var rep := s.station(TankIds.ENGINE_REPAIR) as TankRepairState
	rep.working = true
	var hand := s.riders[3]
	var v := U.view_of(self, s, Wl.SOLO, hand.peer)
	hand.cadence_rpm = 90
	hand.raw_w = 150.0
	var a := v.audio
	U.run(v, 10, DT)
	a.kit.clear_played()
	var from := v.machine_phase("repair")
	U.run(v, 300, DT)
	var to := v.machine_phase("repair")
	assert_gt(to - from, 5.0, "its crank turned")
	var feed := v.audio_feed(s)["repair"] as Dictionary
	var drawn := v.paint_input(s)["repair"] as Dictionary
	assert_eq(float(feed["revs"]), float(drawn["revs"]), "one number for the picture and the sound")
	var due := a.played.count("rivet_hit")
	assert_between(due, floori(to - from) - 1, ceili(to - from) + 1, "one strike a revolution")


# --- The banner -------------------------------------------------------------------------------------------


func test_a_banner_is_not_a_safety_prompt() -> void:
	var g := U.make_game(TankFixtures.state(3), Wl.SOLO, 1)
	autofree(g)
	assert_eq(TankHud.spec(g).banner_sound, "", "the warning means a real safety prompt")
	# Segment and boss banners have sounds of their own.
	assert_true(TankAudio.EVENT_CUES.has(TankEvents.SEGMENT))
	assert_true(TankAudio.EVENT_CUES.has(TankEvents.BOSS_PHASE))
