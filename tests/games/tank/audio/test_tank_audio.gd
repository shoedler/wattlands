extends GutTest
## The tank's adapter on the audio kit: events to cues, state to parameters, strokes 1:1 with the view's crank, the far
## sounds' delays, lead over the others, and silence at 0 rpm. No audio device: the kit keeps its records when
## headless.

const U := preload("res://tests/games/tank/view/tank_view_util.gd")
const DT := 1.0 / 60.0

var _state: TankState = null
var _audio: TankAudio = null
var _revs: Dictionary = {}
var _travel: float = 0.0


func before_each() -> void:
	AudioBuses.clear_ducks()
	_state = TankFixtures.state(3)
	_audio = _make(_state)
	_revs = {}
	_travel = 0.0


func after_each() -> void:
	AudioBuses.clear_ducks()


func _make(state: TankState, peer: int = 1) -> TankAudio:
	var g := U.make_game(state, Wl.SOLO, peer)
	autofree(g)
	var a := TankAudio.new()
	a.game = g
	add_child_autofree(a)
	return a


## One seat turning, `lead` or not; the rest of the room stands still.
func _feed(seat: String, rpm: float, power: float, lead: bool = true) -> Dictionary:
	_revs[seat] = float(_revs.get(seat, 0.0)) + rpm / 60.0 * DT
	return {seat: {"revs": _revs[seat], "rpm": rpm, "power": power, "lead": lead}}


func _run(seat: String, rpm: float, power: float, seconds: float, lead: bool = true) -> void:
	for _i in roundi(seconds / DT):
		_audio.update(_state, DT, 1, _feed(seat, rpm, power, lead), _travel)


func _idle(seconds: float) -> void:
	for _i in roundi(seconds / DT):
		_audio.update(_state, DT, 1, {}, _travel)


## How many k + f lie in (0, to].
func _pattern_count(f: float, to: float) -> int:
	return floori(to - f) + (1 if f > 0.0 else 0)


func _level(id: String) -> float:
	assert_has(_audio.played, id)
	return _audio.played_db[maxi(_audio.played.find(id), 0)]


func _due(id: String) -> float:
	assert_has(_audio.played, id)
	return _audio.played_t[maxi(_audio.played.find(id), 0)]


func _layer_db(instance: String, sound: String) -> float:
	var loop := _audio.kit.machine_loop(instance)
	for i in loop.count:
		if str(loop.layer(i)["sound"]) == sound:
			return loop.db[i]
	return -INF


# --- Strokes ----------------------------------------------------------------------------------------------


func test_the_diesel_fires_three_cylinders_per_revolution_exactly() -> void:
	for rpm: float in [30.0, 60.0, 90.0, 110.0, 140.0]:
		_audio.kit.clear_played()
		_revs = {}
		_audio.kit.stop_all()
		_run("drive", rpm, 1.0, 10.0)
		var to := _audio.kit.machine_voice("drive").planned_to()
		var first: float = float(_revs["drive"]) - rpm / 60.0 * 10.0
		assert_eq(
			_audio.played.count("diesel_fire_a"),
			_pattern_count(0.2778, to) - _pattern_count(0.2778, first),
			"cylinder a at %d rpm" % int(rpm)
		)
		assert_eq(
			_audio.played.count("diesel_fire_b"),
			_pattern_count(0.6111, to) - _pattern_count(0.6111, first),
			"cylinder b at %d rpm" % int(rpm)
		)


func test_the_strokes_read_the_revs_they_are_given_and_integrate_nothing() -> void:
	# Revs that stand still at a nonzero rpm plan nothing past one horizon: the audio has no clock of its own.
	for _i in 120:
		_audio.update(
			_state, DT, 1, {"drive": {"revs": 5.0, "rpm": 90.0, "power": 1.0, "lead": true}}, 0.0
		)
	var fired := _audio.played.count("diesel_fire_a")
	assert_lte(fired, 1, "at most the stroke inside the first horizon")


func test_at_zero_rpm_the_strokes_stop_dead_and_the_loops_close() -> void:
	_run("drive", 90.0, 1.0, 2.0)
	assert_gt(_audio.played.count("diesel_fire_a"), 0)
	_audio.kit.clear_played()
	_run("drive", 0.0, 0.0, 0.12)
	var loop := _audio.kit.machine_loop("drive")
	if loop != null:
		assert_true(loop.all_off(), "closed within 0.12 s")
	_audio.kit.clear_played()
	_run("drive", 0.0, 0.0, 3.0)
	for id: String in _audio.played:
		assert_false(id.begins_with("diesel_"), "nothing more, however long it stands: " + id)


func test_a_restart_goes_on_with_no_burst() -> void:
	_run("drive", 90.0, 1.0, 2.0)
	_run("drive", 0.0, 0.0, 5.0)
	_audio.kit.clear_played()
	_run("drive", 90.0, 1.0, 0.1)
	assert_lte(_audio.played.count("diesel_fire_a"), 1, "no pile of strokes")


func test_the_lead_hears_details_the_others_do_not() -> void:
	_run("drive", 90.0, 1.0, 2.0)
	assert_has(_audio.played, "diesel_valve_ex")
	assert_has(_audio.played, "diesel_valve_in")
	_audio.kit.stop_all()
	_audio.kit.clear_played()
	_run("drive", 90.0, 1.0, 2.0, false)
	assert_has(_audio.played, "diesel_fire_a")
	assert_does_not_have(_audio.played, "diesel_valve_ex", "lead_only")
	assert_does_not_have(_audio.played, "turbo_whistle", "not an `other` layer")


func test_the_lead_is_louder_than_any_other_on_every_machine() -> void:
	(_state.station(TankIds.ENGINE_FEED) as TankFeedState).rpm = 120.0
	var main := {
		"drive": "diesel_fire_a",
		"gun": "cap_dump",
		"loader": "chuff_a",
		"lights": "arc_zap",
		"sec": "bow_shot",
		"repair": "repair_idle",
	}
	for seat: String in main:
		_audio.kit.stop_all()
		_audio.kit.clear_played()
		_run(seat, 90.0, 1.0, 2.0)
		var lead := _level(main[seat])
		_audio.kit.stop_all()
		_audio.kit.clear_played()
		var other := {"revs": 0.0, "rpm": 90.0, "power": 1.0, "lead": true}
		for _i in 120:
			var f := _feed(seat, 90.0, 1.0, false)
			# A lead elsewhere: the +4 dB of a room with no lead stays out of this.
			f["drive" if seat != "drive" else "gun"] = other
			_audio.update(_state, DT, 1, f, 0.0)
		assert_lte(_level(main[seat]), lead - 8.0, seat)


func test_with_no_seat_every_machine_plays_as_another_riders() -> void:
	_run("gun", 90.0, 1.0, 2.0)
	var lead := _level("cap_dump")
	_audio.kit.stop_all()
	_audio.kit.clear_played()
	_run("gun", 90.0, 1.0, 2.0, false)
	assert_has(_audio.played, "cap_dump")
	assert_almost_eq(
		_level("cap_dump"), lead - 10.0 + 4.0, 0.001, "other_db, and the +4 dB with no lead"
	)


func _two_seats(lead_rpm: float, other_rpm: float, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		var feed := _feed("drive", lead_rpm, 1.0, true)
		feed.merge(_feed("gun", other_rpm, 1.0, false))
		_audio.update(_state, DT, 1, feed, 0.0)


func test_a_rider_who_stops_pedalling_stays_the_lead_and_the_room_does_not_rise() -> void:
	_two_seats(90.0, 90.0, 2.0)
	var other := _level("cap_dump")
	_audio.kit.clear_played()
	_two_seats(0.0, 90.0, 2.0)
	assert_has(_audio.played, "cap_dump", "the other rider's machine goes on")
	assert_almost_eq(_level("cap_dump"), other, 0.001, "no +4 dB: this rider still has a seat")


func test_a_lead_seat_that_stands_still_closes_its_loops_and_plans_nothing() -> void:
	_two_seats(90.0, 90.0, 2.0)
	var voice := _audio.kit.machine_voice("drive")
	assert_false(_audio.kit.machine_loop("drive").all_off(), "its body runs")
	_audio.kit.clear_played()
	_two_seats(0.0, 90.0, 1.0)
	assert_does_not_have(_audio.played, "diesel_fire_a", "dead stop")
	assert_true(_audio.kit.machine_loop("drive").all_off(), "the loops close")
	assert_eq(_audio.kit.machine_voice("drive"), voice, "the seat keeps its machine")
	_audio.kit.clear_played()
	_two_seats(90.0, 90.0, 0.1)
	assert_lte(_audio.played.count("diesel_fire_a"), 1, "and starts again with no burst")


func test_another_riders_seat_that_stops_is_let_go() -> void:
	_two_seats(90.0, 90.0, 1.0)
	assert_not_null(_audio.kit.machine_voice("gun"))
	_two_seats(90.0, 0.0, 1.0)
	assert_null(_audio.kit.machine_voice("gun"), "released once its loops closed")
	assert_not_null(_audio.kit.machine_voice("drive"))


func test_a_breakdown_keeps_the_lead_too() -> void:
	# audio_feed reports rpm 0 for every seat in a breakdown, and the seated rider is still seated.
	_audio.update(
		_state, DT, 1, {"drive": {"revs": 0.0, "rpm": 0.0, "power": 0.0, "lead": true}}, 0.0
	)
	assert_not_null(_audio.kit.machine_voice("drive"))


# --- Machine parameters -----------------------------------------------------------------------------------


func test_hard_power_adds_the_overlay_and_soft_power_quiets_the_strokes() -> void:
	_run("drive", 90.0, 0.8, 2.0)
	assert_does_not_have(_audio.played, "diesel_fire_hard", "only over 1.0")
	var soft := _level("diesel_fire_a")
	_audio.kit.stop_all()
	_audio.kit.clear_played()
	_run("drive", 90.0, 1.2, 2.0)
	assert_has(_audio.played, "diesel_fire_hard")
	assert_gt(_level("diesel_fire_a"), soft)


func test_the_turbo_climbs_with_watts_not_with_cadence() -> void:
	_run("drive", 90.0, 0.6, 3.0)
	var low_db := _layer_db("drive", "turbo_whistle")
	var low_pitch: float = _audio.kit.machine_loop("drive").pitch[3]
	_run("drive", 90.0, 1.3, 4.0)
	assert_gt(_layer_db("drive", "turbo_whistle"), low_db + 6.0)
	assert_gt(_audio.kit.machine_loop("drive").pitch[3], low_pitch)
	assert_eq(str(_audio.kit.machine_loop("drive").layer(3)["sound"]), "turbo_whistle")
	var same_watts := _audio.kit.machine_loop("drive").pitch[3]
	_run("drive", 50.0, 1.3, 4.0)
	assert_almost_eq(_audio.kit.machine_loop("drive").pitch[3], same_watts, 0.01, "cadence: none")


func test_a_lift_off_blows_off_once_and_crackles_on_the_exhaust() -> void:
	_run("drive", 90.0, 1.1, 2.0)
	assert_does_not_have(_audio.played, "exhaust_crackle", "steady in band: no crackle")
	assert_does_not_have(_audio.played, "turbo_blowoff")
	_run("drive", 90.0, 0.4, 1.0)
	assert_eq(_audio.played.count("turbo_blowoff"), 1, "once per lift-off")
	assert_gte(_audio.played.count("exhaust_crackle"), 2)
	_audio.kit.clear_played()
	_run("drive", 90.0, 0.4, 3.0)
	assert_does_not_have(_audio.played, "exhaust_crackle", "it dies away")


func test_well_over_band_the_exhaust_spits() -> void:
	assert_eq(TankAudio.crackle_level(0.0, 1.0), 0.0)
	assert_eq(TankAudio.crackle_level(0.8, 1.0), 0.8)
	assert_almost_eq(TankAudio.crackle_level(0.0, 1.4), TankAudio.SPIT_LEVEL, 1e-6)
	_run("drive", 90.0, 1.4, 2.0)
	assert_has(_audio.played, "exhaust_crackle")


func test_the_body_crossfades_at_the_same_pitch() -> void:
	# Between 50 and 75 rpm both bodies sound: rpm/50 of 46.67 Hz and rpm/110 of 102.67 Hz are one note.
	var doc: Dictionary = _audio.kit._bank.machines["diesel"]
	var lo: Dictionary = doc["loops"][0]
	var hi: Dictionary = doc["loops"][1]
	assert_almost_eq(
		46.6667 / float(lo["pitch_by"][0]["ratio"]),
		102.6667 / float(hi["pitch_by"][0]["ratio"]),
		0.001
	)
	_run("drive", 60.0, 1.0, 1.0)
	assert_gt(_layer_db("drive", "diesel_body_lo"), -30.0)
	assert_gt(_layer_db("drive", "diesel_body_hi"), -30.0)
	_run("drive", 110.0, 1.0, 1.0)
	assert_eq(_layer_db("drive", "diesel_body_lo"), LayeredLoop.OFF_DB)


func test_the_dynamo_dumps_its_charge_only_when_the_jars_fill() -> void:
	_run("gun", 90.0, 0.4, 2.0)
	assert_does_not_have(_audio.played, "cap_dump", "max_fill <= 0.4 in the art")
	_run("gun", 90.0, 0.8, 2.0)
	assert_has(_audio.played, "cap_dump")
	assert_has(_audio.played, "brush_tick")


func test_the_hoist_ratchets_four_times_a_turn_while_it_lifts() -> void:
	_run("gun", 60.0, 1.0, 2.0)
	assert_does_not_have(_audio.played, "hoist_ratchet")
	(_state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).hoist_s = 8.0
	_run("gun", 60.0, 1.0, 2.0)
	assert_between(_audio.played.count("hoist_ratchet"), 7, 9)


func test_steam_chuffs_on_both_strokes_and_the_pawl_stops_when_loaded() -> void:
	var steam := _state.station(TankIds.ENGINE_STEAM) as TankSteamState
	steam.loaded = false
	_run("loader", 60.0, 1.0, 4.0)
	assert_between(_audio.played.count("chuff_a"), 3, 5)
	assert_between(_audio.played.count("chuff_b"), 3, 5)
	assert_has(_audio.played, "hoist_pawl")
	assert_gt(_level("chuff_a"), _level("chuff_b"), "a is the louder")
	_audio.kit.clear_played()
	steam.loaded = true
	_run("loader", 60.0, 1.0, 2.0)
	assert_does_not_have(_audio.played, "hoist_pawl")


func test_the_safety_valve_lifts_when_over() -> void:
	var steam := _state.station(TankIds.ENGINE_STEAM) as TankSteamState
	_run("loader", 90.0, 1.0, 1.0)
	assert_eq(_layer_db("loader", "safety_valve"), LayeredLoop.OFF_DB)
	steam.over = true
	_run("loader", 90.0, 1.0, 1.0)
	assert_gt(_layer_db("loader", "safety_valve"), -30.0, "overpressure")
	steam.over = false
	_run("loader", 90.0, 1.5, 1.0)
	assert_gt(_layer_db("loader", "safety_valve"), -30.0, "over power, as the art")


func test_the_arc_zaps_twice_a_turn_and_doubles_when_over() -> void:
	_run("lights", 60.0, 1.0, 4.0)
	assert_between(_audio.played.count("arc_zap"), 7, 9)
	assert_does_not_have(_audio.played, "arc_zap_over")
	assert_between(_audio.played.count("belt_tick"), 15, 17)
	_audio.kit.clear_played()
	_run("lights", 60.0, 1.5, 4.0)
	assert_between(_audio.played.count("arc_zap_over"), 7, 9)
	assert_almost_eq(TankAudio.ladder_reach(0.9), 1.0, 1e-6, "the art's reach")
	assert_almost_eq(TankAudio.ladder_reach(0.3), 0.25, 1e-6)


func test_the_arc_is_silent_under_its_threshold() -> void:
	_run("lights", 60.0, 0.1, 3.0)
	assert_does_not_have(_audio.played, "arc_zap", "strength 0 in the art")


func test_the_feed_clacks_fires_and_ejects_with_its_rounds() -> void:
	var feed := _state.station(TankIds.ENGINE_FEED) as TankFeedState
	if feed == null:
		_state = TankFixtures.state(4)
		_audio = _make(_state)
		feed = _state.station(TankIds.ENGINE_FEED) as TankFeedState
	feed.rpm = 0.0
	feed.rounds = 0
	_run("sec", 60.0, 1.0, 4.0)
	assert_between(_audio.played.count("bolt_clack"), 7, 9, "two per revolution")
	assert_does_not_have(_audio.played, "bow_shot", "the guns are silent")
	assert_does_not_have(_audio.played, "casing_tink", "no rounds yet")
	_audio.kit.clear_played()
	feed.rpm = 120.0
	feed.rounds = 8
	_run("sec", 60.0, 1.0, 4.0)
	assert_between(_audio.played.count("bow_shot"), 7, 9)
	assert_between(_audio.played.count("casing_tink"), 7, 9)
	assert_between(_audio.played.count("link_clink"), 7, 9)


func test_the_rivet_hammer_works_only_while_the_hull_needs_it() -> void:
	var s := TankFixturesV4.make("repair")
	_state = s
	_audio = _make(s)
	var rep := s.station(TankIds.ENGINE_REPAIR) as TankRepairState
	rep.working = true
	_run("repair", 60.0, 1.0, 4.0)
	assert_between(_audio.played.count("rivet_hit"), 3, 5, "one stroke a revolution")
	assert_has(_audio.played, "rivet_ring")
	assert_does_not_have(_audio.played, "repair_idle")
	_audio.kit.clear_played()
	rep.working = false
	_run("repair", 60.0, 1.0, 4.0)
	assert_does_not_have(_audio.played, "rivet_hit")
	assert_between(_audio.played.count("repair_idle"), 3, 5, "quiet: hull full")


func test_a_patch_presses_once_each_time_the_count_rises() -> void:
	var s := TankFixturesV4.make("repair")
	_state = s
	_audio = _make(s)
	var rep := s.station(TankIds.ENGINE_REPAIR) as TankRepairState
	_run("repair", 60.0, 1.0, 0.5)
	assert_does_not_have(_audio.played, "plate_press", "the first look only learns the count")
	rep.patches += 1
	_run("repair", 60.0, 1.0, 0.5)
	assert_eq(_audio.played.count("plate_press"), 1)
	rep.patches = 0
	_run("repair", 60.0, 1.0, 0.5)
	assert_eq(_audio.played.count("plate_press"), 1, "a restart's reset is no patch")


# --- The track --------------------------------------------------------------------------------------------


## A rider on the Gun, or a spectator: a spectator's track thins like any other machine.
func _drive_track(speed: float, seconds: float, rider: bool = true) -> void:
	_state.hull.speed_mps = speed
	for _i in roundi(seconds / DT):
		_travel += speed * DT
		_audio.update(_state, DT, 1, _feed("gun", 90.0, 1.0) if rider else {}, _travel)


func test_the_track_is_locked_to_the_distance_drawn() -> void:
	_drive_track(4.8, 5.0)
	# 24 m is ten track turns: thirty links, ten squeaks.
	assert_between(_audio.played.count("track_link"), 29, 31)
	assert_between(_audio.played.count("track_squeak"), 9, 11)
	assert_has(_audio.played, "track_rumble")


func test_every_rider_hears_the_track_full_and_a_spectator_with_the_machines() -> void:
	_drive_track(4.8, 2.0)
	var rider := _level("track_link")
	_audio.kit.stop_all()
	_audio.kit.clear_played()
	_drive_track(4.8, 2.0, false)
	assert_almost_eq(_level("track_link"), rider - 10.0 + 4.0, 0.001, "no seat: the room's level")


func test_the_track_squeaks_louder_at_speed_and_stops_with_the_hull() -> void:
	_drive_track(1.0, 8.0)
	var slow := _level("track_squeak")
	_audio.kit.clear_played()
	_drive_track(8.0, 2.0)
	assert_gt(_level("track_squeak"), slow)
	_audio.kit.clear_played()
	_drive_track(0.0, 2.0)
	assert_does_not_have(_audio.played, "track_link")
	assert_does_not_have(_audio.played, "track_squeak")


# --- The main gun -----------------------------------------------------------------------------------------


func test_a_shot_booms_cracks_rings_and_ejects_in_order() -> void:
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_LIGHT, 1))
	for id: String in ["gun_low", "gun_crack", "gun_tail"]:
		assert_has(_audio.played, id)
	assert_does_not_have(_audio.played, "shell_eject", "a moment later")
	_idle(0.3)
	assert_has(_audio.played, "shell_outgoing")
	assert_does_not_have(_audio.played, "shell_eject")
	_idle(0.1)
	assert_has(_audio.played, "shell_eject")
	assert_does_not_have(_audio.played, "shell_clang")
	_idle(0.3)
	assert_has(_audio.played, "shell_clang", "the casing lands")


func test_a_heavy_is_louder_an_overpressure_lower_and_the_gunner_hears_it_most() -> void:
	assert_eq(TankAudio.shot_vars(TankIds.SHELL_LIGHT)["boost"], 0.0)
	assert_eq(TankAudio.shot_vars(TankIds.SHELL_HEAVY)["boost"], 3.0)
	assert_eq(TankAudio.shot_vars(TankIds.SHELL_OVER)["gun_pitch"], 0.8)
	assert_eq(TankAudio.shot_vars(TankIds.SHELL_HEAVY)["gun_pitch"], 1.0)
	var own_slot := _state.rider(1).slot
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(own_slot, TankIds.SHELL_LIGHT, 1))
	var light := _level("gun_low")
	# A fresh adapter for each: round for round, only the shell and the seat differ.
	_audio = _make(_state)
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(own_slot, TankIds.SHELL_HEAVY, 2))
	assert_almost_eq(_level("gun_low"), light + 3.0, 0.001)
	_audio = _make(_state)
	var other_slot := own_slot + 1
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(other_slot, TankIds.SHELL_LIGHT, 3))
	assert_almost_eq(_level("gun_low"), light - 4.0, 0.001, "another rider's gun")


func test_no_two_rounds_of_the_main_gun_run_the_same() -> void:
	var want_pitch: Array[float] = [1.0, 0.97, 1.025, 0.985, 1.01]
	var want_boost: Array[float] = [0.0, -0.8, 0.4]
	var seen := {}
	for n in 15:
		var v := TankAudio.shot_vars(TankIds.SHELL_LIGHT, n)
		assert_eq(v["gun_pitch"], want_pitch[n % 5], "pitch of round %d" % n)
		assert_eq(v["boost"], want_boost[n % 3], "level of round %d" % n)
		seen["%s %s" % [v["gun_pitch"], v["boost"]]] = true
	assert_eq(seen.size(), 15, "the two cycles only meet again after 15 rounds")
	assert_almost_eq(TankAudio.shot_vars(TankIds.SHELL_OVER, 1)["gun_pitch"], 0.97 * 0.8, 1e-5)
	assert_almost_eq(TankAudio.shot_vars(TankIds.SHELL_HEAVY, 1)["boost"], 3.0 - 0.8, 1e-5)


func test_the_adapter_walks_the_guns_cycle_shot_by_shot() -> void:
	var slot := _state.rider(1).slot
	var levels: Array[float] = []
	for n in 3:
		_audio.kit.clear_played()
		_audio.on_cue(TankEvents.SHOT, TankEvents.shot(slot, TankIds.SHELL_LIGHT, n + 1))
		levels.append(_level("gun_low"))
	assert_almost_eq(levels[1] - levels[0], -0.8, 0.001)
	assert_almost_eq(levels[2] - levels[0], 0.4, 0.001)
	# A bow burst and an enemy's gun are not its rounds.
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(slot, TankIds.SHELL_BOW, 9))
	_audio.kit.clear_played()
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(slot, TankIds.SHELL_LIGHT, 10))
	assert_almost_eq(_level("gun_low"), levels[0], 0.001, "the fourth round starts the level again")


func _pending_pitch(sound: String) -> float:
	for p: Dictionary in _audio.kit._pending:
		if str(p["sound"]) == sound:
			return float(p["pitch"])
	return -1.0


func test_the_rounds_pitch_runs_through_the_shells_flight_and_its_ejection() -> void:
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_LIGHT, 1))
	_audio.kit._pending.clear()
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_LIGHT, 2))
	assert_almost_eq(_pending_pitch("shell_outgoing"), 0.97, 1e-5, "the second round's pitch")
	assert_almost_eq(_pending_pitch("shell_eject"), 0.97, 1e-5)
	_audio.kit._pending.clear()
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_OVER, 3))
	assert_almost_eq(_pending_pitch("shell_outgoing"), 1.025 * 0.8, 1e-5, "and the shell's own")


func test_no_two_reloads_in_a_row_run_the_same() -> void:
	var want: Array[float] = TankAudio.LOAD_PITCHES
	assert_gte(want.size(), 3)
	for n in want.size() * 2:
		_audio.kit._pending.clear()
		_audio.on_cue(TankEvents.LATCH, TankEvents.latch(1, TankIds.SHELL_HEAVY))
		assert_almost_eq(
			_pending_pitch("breech_close"), want[n % want.size()], 1e-5, "reload %d" % n
		)


func test_an_empty_loaders_click_does_not_spend_a_reloads_pitch() -> void:
	var s := TankFixtures.state(2)
	var a := _make(s)
	a.on_cue(TankEvents.LATCH, TankEvents.latch(0, TankIds.SHELL_HEAVY))
	assert_eq(a._loads, 0)


func test_each_impact_at_the_hull_takes_the_next_pitch() -> void:
	_audio.on_cue(TankEvents.SPLASH, TankEvents.splash(30.0, TankIds.SHELL_ENEMY, false))
	_audio.on_cue(
		TankEvents.HIT, TankEvents.hit(TankEvents.ON_TANK, 0, 8.0, TankIds.SHELL_ENEMY, 0.0, 0.0)
	)
	assert_eq(_audio._impacts, 2)
	assert_eq(TankAudio.IMPACT_PITCHES.size(), 4)


func test_only_the_gunners_own_shot_ducks_the_machines_and_the_wind() -> void:
	_audio.on_cue(
		TankEvents.SHOT, TankEvents.shot(_state.rider(1).slot + 1, TankIds.SHELL_LIGHT, 1)
	)
	AudioBuses.tick(0.01)
	assert_eq(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0)
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(_state.rider(1).slot, TankIds.SHELL_LIGHT, 2))
	AudioBuses.tick(0.01)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -4.0, 0.01)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.AMBIENCE), -6.0, 0.01)


func test_the_bow_guns_rattle_a_burst_not_the_cannon() -> void:
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_BOW, 1))
	_idle(0.3)
	assert_eq(_audio.played.count("bow_shot"), 5, "staggered")
	assert_does_not_have(_audio.played, "gun_low")


# --- Far shells -------------------------------------------------------------------------------------------


func test_the_curves_of_the_far_sounds() -> void:
	assert_almost_eq(TankAudio.boom_delay(1360.0), 2.0, 1e-6)
	assert_almost_eq(TankAudio.boom_delay(100.0), 0.6, 1e-5, "clamped")
	assert_almost_eq(TankAudio.boom_delay(9000.0), 3.5, 1e-5, "clamped")
	assert_eq(TankAudio.range_db(800.0), -5.0)
	assert_eq(TankAudio.range_db(2400.0), -12.0)
	assert_eq(TankAudio.range_db(5000.0), -12.0)
	assert_eq(TankAudio.whistle_rate(2.5), 1.0)
	assert_almost_eq(TankAudio.whistle_rate(1.5), 1.6667, 1e-3)
	assert_almost_eq(TankAudio.whistle_rate(0.2), 1.8, 1e-5, "clamped")
	assert_almost_eq(TankAudio.whistle_rate(4.0), 0.63, 1e-5, "clamped")


func test_an_enemy_shot_whistles_at_once_and_thumps_after_its_range() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	var shot := TankEvents.shot(-1, TankIds.SHELL_ENEMY, 9, 11, medium, 2.0, 1360.0)
	_audio.on_cue(TankEvents.SHOT, shot)
	assert_has(_audio.played, "incoming_whistle", "the telegraph starts now")
	assert_does_not_have(_audio.played, "enemy_thump")
	_idle(1.9)
	assert_does_not_have(_audio.played, "enemy_thump")
	_idle(0.2)
	assert_has(_audio.played, "enemy_thump", "1360 m: 2 s")
	assert_almost_eq(_level("enemy_thump"), 3.0 + TankAudio.range_db(1360.0), 0.001)


func test_the_incoming_whistle_is_prominent_and_ducks_the_wind_for_everyone() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_audio.on_cue(
		TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 9, 11, medium, 2.0, 1360.0)
	)
	assert_eq(_level("incoming_whistle"), -8.0)
	AudioBuses.tick(0.2)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.AMBIENCE), -6.0, 0.01)


func test_a_far_shot_with_no_numbers_falls_back_to_a_plain_flight() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 9, 11, medium))
	assert_has(_audio.played, "incoming_whistle")
	_idle(TankAudio.boom_delay(TankAudio.FALLBACK_RANGE_M) + 0.1)
	assert_has(_audio.played, "enemy_thump")


func test_a_near_threat_shoots_a_small_gun_and_no_whistle() -> void:
	var recon := TankIds.enemy_code(TankIds.ENEMY_RECON)
	_audio.on_cue(TankEvents.SHOT, TankEvents.shot(-1, TankIds.SHELL_ENEMY, 9, 41, recon))
	assert_has(_audio.played, "small_mg")
	assert_does_not_have(_audio.played, "incoming_whistle")


func test_our_far_hit_booms_after_its_range_with_metal_on_it() -> void:
	var hit := TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 2040.0)
	_audio.on_cue(TankEvents.HIT, hit)
	assert_does_not_have(_audio.played, "far_boom", "seen first, heard later")
	_idle(3.1)
	assert_has(_audio.played, "far_boom", "2040 m: 3 s")
	assert_has(_audio.played, "far_hit_metal")
	assert_almost_eq(_level("far_boom"), 3.0 + TankAudio.range_db(2040.0), 0.001)


func test_a_far_boom_is_quieter_the_further_it_lands() -> void:
	_audio.on_cue(TankEvents.SPLASH, TankEvents.splash(900.0, TankIds.SHELL_LIGHT, true))
	_idle(1.5)
	var near := _level("far_boom")
	_audio.kit.clear_played()
	_audio.on_cue(TankEvents.SPLASH, TankEvents.splash(2300.0, TankIds.SHELL_LIGHT, true))
	_idle(3.6)
	assert_lt(_level("far_boom"), near)


func test_their_miss_thuds_beside_the_hull_at_once() -> void:
	_audio.on_cue(TankEvents.SPLASH, TankEvents.splash(30.0, TankIds.SHELL_ENEMY, false))
	assert_has(_audio.played, "near_miss_thud")
	assert_does_not_have(_audio.played, "far_boom")


func test_a_hit_on_the_hull_rings_it_by_the_damage() -> void:
	_audio.on_cue(
		TankEvents.HIT, TankEvents.hit(TankEvents.ON_TANK, 0, 4.0, TankIds.SHELL_ENEMY, 0.0, 0.0)
	)
	assert_has(_audio.played, "incoming_impact_near")
	var small := _level("hull_hit")
	_audio.kit.clear_played()
	_audio.on_cue(
		TankEvents.HIT, TankEvents.hit(TankEvents.ON_TANK, 0, 24.0, TankIds.SHELL_ENEMY, 0.0, 0.0)
	)
	assert_gt(_level("hull_hit"), small)


func test_a_bow_round_on_a_near_threat_is_a_ping_with_no_delay() -> void:
	_audio.on_cue(
		TankEvents.HIT, TankEvents.hit(TankEvents.ON_ENEMY, 41, 2.0, TankIds.SHELL_BOW, 0.0, 3400.0)
	)
	assert_has(_audio.played, "far_hit_metal")
	assert_does_not_have(_audio.played, "far_boom")


func test_a_main_gun_round_on_a_living_near_threat_is_a_ping_with_no_delay() -> void:
	# A near shell's HIT sends world px in x: read as metres this was a far boom 3.5 s later.
	var e := TankEnemyState.new()
	e.id = 77
	e.code = TankIds.enemy_code(TankIds.ENEMY_RECON)
	_state.enemies.append(e)
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 77, 20.0, TankIds.SHELL_HEAVY, 0.0, 2600.0)
	)
	assert_has(_audio.played, "far_hit_metal")
	assert_eq(_pending_pitch("far_boom"), -1.0, "no boom on its way")


func test_the_round_that_kills_a_near_threat_is_near_too_though_the_rules_erased_it() -> void:
	var recon := TankIds.enemy_code(TankIds.ENEMY_RECON)
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(78, recon, TankEvents.BY_SHELL, 0))
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 78, 20.0, TankIds.SHELL_HEAVY, 0.0, 2600.0)
	)
	assert_has(_audio.played, "explode_small")
	assert_eq(_pending_pitch("far_boom"), -1.0, "no boom on its way")
	assert_eq(_pending_pitch("explode_big"), -1.0)
	_idle(0.1)
	assert_true(_audio._near_killed.is_empty(), "forgotten once the frame has run")


func test_a_far_hit_is_still_a_far_boom() -> void:
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 79, 20.0, TankIds.SHELL_HEAVY, 0.0, 1360.0)
	)
	assert_ne(_pending_pitch("far_boom"), -1.0)


# --- Other events -----------------------------------------------------------------------------------------


func test_kills_by_size_and_a_far_one_goes_up_with_its_boom() -> void:
	var recon := TankIds.enemy_code(TankIds.ENEMY_RECON)
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(41, recon, TankEvents.BY_BOW, 0))
	assert_has(_audio.played, "explode_small")
	_audio.kit.clear_played()
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	# The rules' order: TankShells._impact_far sends the kill before the hit that gives its range.
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(11, medium, TankEvents.BY_SHELL, 0))
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 1360.0)
	)
	assert_does_not_have(_audio.played, "explode_big")
	_idle(2.1)
	assert_has(_audio.played, "explode_big")
	assert_almost_eq(_due("explode_big"), _due("far_boom"), 0.02, "together")


func test_the_first_far_kill_at_long_range_goes_up_with_its_boom_not_before() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_idle(0.1)
	var t0 := _audio.kit._t
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(11, medium, TankEvents.BY_SHELL, 0))
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 2300.0)
	)
	_idle(3.6)
	assert_almost_eq(_due("far_boom") - t0, TankAudio.boom_delay(2300.0), 0.05, "3.38 s away")
	assert_almost_eq(_due("explode_big"), _due("far_boom"), 0.02, "the same frame's range")


func test_a_kill_by_splash_takes_the_splashs_range() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 900.0)
	)
	_idle(1.5)
	_audio.kit.clear_played()
	_audio.on_cue(TankEvents.SPLASH, TankEvents.splash(2200.0, TankIds.SHELL_HEAVY, true))
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(12, medium, TankEvents.BY_SHELL, 0))
	_idle(3.4)
	assert_has(_audio.played, "explode_big")
	assert_almost_eq(_due("explode_big"), _due("far_boom"), 0.02, "not the previous shot's range")


func test_a_barrage_rolls_in_one_explosion_after_another() -> void:
	# An overrun's barrage kills with no shell, so no HIT or SPLASH gives a range, and stacked they would just be loud.
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 2300.0)
	)
	_idle(3.6)
	_audio.kit.clear_played()
	for id in 3:
		_audio.on_cue(TankEvents.KILL, TankEvents.kill(20 + id, medium, TankEvents.BY_BARRAGE, -1))
	_idle(3.0)
	assert_eq(_audio.played.count("explode_big"), 3)
	assert_does_not_have(_audio.played, "far_boom", "no shell of ours landed")
	var dues: Array[float] = []
	for i in _audio.played.size():
		if _audio.played[i] == "explode_big":
			dues.append(_audio.played_t[i])
	assert_almost_eq(dues[1] - dues[0], TankAudio.BARRAGE_STEP_S, 0.02, "one after another")
	assert_almost_eq(dues[2] - dues[1], TankAudio.BARRAGE_STEP_S, 0.02)
	assert_almost_eq(dues[0] - (_audio.kit._t - 3.0), TankAudio.BARRAGE_DELAY_S, 0.05)


func test_two_far_kills_in_one_frame_both_go_up() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(11, medium, TankEvents.BY_SHELL, 0))
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 1000.0)
	)
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(12, medium, TankEvents.BY_SHELL, 0))
	_idle(2.0)
	assert_eq(_audio.played.count("explode_big"), 2)
	_idle(2.0)
	assert_eq(_audio.played.count("explode_big"), 2, "and only once each")


func test_the_boss_dying_is_a_long_roll_and_ducks_all_but_itself() -> void:
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(-4, TankIds.BOSS_CODE, TankEvents.BY_SHELL, 0))
	assert_has(_audio.played, "explode_boss")
	AudioBuses.tick(0.02)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -7.0, 0.01)
	_idle(1.0)
	assert_eq(_audio.played.count("explode_big"), 2, "at 0.4 and 0.9 s")


func test_losing_the_tank_ducks_everything_then_the_chain_comes() -> void:
	_audio.on_cue(TankEvents.TANK_LOST, TankEvents.tank_lost(1, TankIds.SEG_ADVANCE, 2))
	assert_has(_audio.played, "tank_lost")
	AudioBuses.tick(0.02)
	for bus: String in [AudioBuses.MACHINES, AudioBuses.AMBIENCE, AudioBuses.SFX]:
		assert_almost_eq(AudioBuses.duck_db(bus), -9.0, 0.01, bus)
	assert_eq(AudioBuses.duck_db(AudioBuses.UI), 0.0, "never UI")
	assert_does_not_have(_audio.played, "tow_chain")
	_idle(1.3)
	assert_has(_audio.played, "tow_chain")
	_audio.on_cue(TankEvents.STAGE_RESTART, TankEvents.stage_restart(TankIds.SEG_ADVANCE, 2, 90.0))
	assert_has(_audio.played, "repaired_start")


func test_a_latch_loads_when_the_rack_is_manned_and_only_clicks_when_not() -> void:
	_audio.on_cue(TankEvents.LATCH, TankEvents.latch(1, TankIds.SHELL_HEAVY))
	assert_has(_audio.played, "shell_load")
	_idle(0.7)
	assert_has(_audio.played, "breech_close")
	var s := TankFixtures.state(2)
	var a := _make(s)
	a.on_cue(TankEvents.LATCH, TankEvents.latch(0, TankIds.SHELL_HEAVY))
	assert_eq(a.played[0], "hoist_pawl", "an empty Loader's seat")


func test_a_seat_move_clunks_loudest_for_the_rider_who_moved() -> void:
	var own_slot := _state.rider(1).slot
	_audio.on_cue(
		TankEvents.SEAT, TankEvents.seat(own_slot, TankIds.ENGINE_ARC, TankIds.ENGINE_FEED)
	)
	var own := _level("lever_clunk")
	_audio.kit.clear_played()
	_audio.on_cue(
		TankEvents.SEAT, TankEvents.seat(own_slot + 1, TankIds.ENGINE_ARC, TankIds.ENGINE_FEED)
	)
	assert_almost_eq(_level("lever_clunk"), own - 8.0, 0.001)


func test_the_small_events() -> void:
	var cases := {
		"evade_lurch": [TankEvents.EVADE, TankEvents.evade(11, 2, true, 0)],
		"breakdown_stall": [TankEvents.BREAKDOWN, TankEvents.breakdown()],
		"repaired_start": [TankEvents.REPAIRED, TankEvents.repaired(40.0)],
		"boss_phase": [TankEvents.BOSS_PHASE, TankEvents.boss_phase(1)],
		"horn_segment": [TankEvents.SEGMENT, TankEvents.segment(1, TankIds.SEG_ADVANCE, 1)],
		"near_burst": [TankEvents.AMBUSH, TankEvents.ambush(41, 7)],
	}
	for id: String in cases:
		_audio.on_cue(cases[id][0], cases[id][1])
		assert_has(_audio.played, id)


func test_a_shot_not_evaded_makes_no_lurch() -> void:
	_audio.on_cue(TankEvents.EVADE, TankEvents.evade(11, 2, false))
	assert_does_not_have(_audio.played, "evade_lurch")


func test_silent_events_stay_silent() -> void:
	for kind: String in TankAudio.SILENT_EVENTS:
		_audio.on_cue(kind, {"type": kind})
	assert_eq(_audio.played.size(), 0)


# --- Near threats and the bed -----------------------------------------------------------------------------


func test_a_near_threats_engine_runs_while_it_lives_louder_when_closer() -> void:
	var s := TankFixturesV4.make("near_ambush")
	_state = s
	_audio = _make(s)
	_idle(0.5)
	var recon := _audio.kit.entry_loop("recon_engine")
	var tankette := _audio.kit.entry_loop("tankette_engine")
	assert_not_null(recon)
	assert_not_null(tankette)
	assert_gt(recon.db[0], LayeredLoop.OFF_DB)
	var close_db: float = recon.db[0]
	for e: TankEnemyState in s.enemies:
		if e.is_near():
			e.x_px += 500.0
	_idle(0.5)
	assert_lt(recon.db[0], close_db, "fleeing")
	s.enemies.clear()
	_idle(0.5)
	assert_true(recon.all_off(), "gone")
	assert_true(tankette.all_off())


func test_the_far_battle_keeps_out_of_the_depot() -> void:
	_idle(0.1)
	_state.seg.seg = TankIds.SEG_DEPOT
	_idle(0.1)
	assert_eq(_audio.bed_now["combat"], 0.0)
	_state.seg.seg = TankIds.SEG_ADVANCE
	_idle(0.1)
	assert_eq(_audio.bed_now["combat"], 1.0)
	_state.hull.speed_mps = 6.0
	_idle(0.1)
	assert_eq(_audio.bed_now["speed"], 6.0)


func test_the_night_runs_with_crickets_and_wind() -> void:
	_idle(16.0)
	assert_has(_audio.played, "wind_pine_lo")
	assert_has(_audio.played, "wind_pine_hi")
	assert_has(_audio.played, "cricket_chorus")
	assert_gt(_audio.played.count("cricket"), 2, "a train every 1.4 to 5.5 s")


func test_the_gust_stays_a_gust() -> void:
	for _i in 600:
		_audio.update(_state, 0.5, 1, {}, 0.0)
		assert_between(float(_audio.bed_now["gust"]), 0.0, 1.0)


# --- Every event through on_cue ---------------------------------------------------------------------------


func _every_event() -> Dictionary:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	var slot := _state.rider(1).slot
	return {
		TankEvents.SEGMENT: TankEvents.segment(1, TankIds.SEG_ADVANCE, 1),
		TankEvents.ROTATION: {"type": TankEvents.ROTATION, "s": slot},
		TankEvents.SHOT: TankEvents.shot(slot, TankIds.SHELL_LIGHT, 1),
		TankEvents.HIT: TankEvents.hit(TankEvents.ON_TANK, 0, 12.0, TankIds.SHELL_ENEMY, 0.0, 0.0),
		TankEvents.KILL: TankEvents.kill(11, medium, TankEvents.BY_SHELL, slot),
		TankEvents.RAM: {"type": TankEvents.RAM},
		TankEvents.DODGE: {"type": TankEvents.DODGE},
		TankEvents.BREAKDOWN: TankEvents.breakdown(),
		TankEvents.REPAIRED: TankEvents.repaired(40.0),
		TankEvents.OVERRUN: TankEvents.overrun(TankIds.SEG_ADVANCE, 1),
		TankEvents.BOSS_PHASE: TankEvents.boss_phase(1),
		TankEvents.LATCH: TankEvents.latch(slot, TankIds.SHELL_LIGHT),
		TankEvents.LEVER: {"type": TankEvents.LEVER, "s": slot, "lv": 1},
		TankEvents.EVADE: TankEvents.evade(11, medium, true, slot),
		TankEvents.TURN: TankEvents.turn(slot, TankIds.DIR_RIGHT),
		TankEvents.TIME_UP: TankEvents.time_up(2),
		TankEvents.SEAT: TankEvents.seat(slot, TankIds.ENGINE_DIESEL, TankIds.ENGINE_DYNAMO),
		TankEvents.TANK_LOST: TankEvents.tank_lost(1, TankIds.SEG_ADVANCE, 1),
		TankEvents.STAGE_RESTART: TankEvents.stage_restart(TankIds.SEG_ADVANCE, 1, 40.0),
		TankEvents.AMBUSH: TankEvents.ambush(41, TankIds.enemy_code(TankIds.ENEMY_RECON)),
		TankEvents.ESCAPED: TankEvents.escaped(41, TankIds.enemy_code(TankIds.ENEMY_RECON)),
		TankEvents.SPLASH: TankEvents.splash(1400.0, TankIds.SHELL_LIGHT, true),
	}


func test_the_table_of_events_is_every_event_there_is() -> void:
	var all := _every_event()
	for kind: String in TankEvents.TYPES:
		assert_true(all.has(kind), kind)
	assert_eq(all.size(), TankEvents.TYPES.size())


func test_every_event_makes_its_sound_through_on_cue_or_is_listed_silent() -> void:
	var all := _every_event()
	for kind: String in TankEvents.TYPES:
		_audio = _make(_state)
		_idle(0.0)
		_audio.kit.clear_played()
		var waiting := _audio.kit._pending.size()
		_audio.on_cue(kind, all[kind])
		_audio.update(_state, 0.0, 1, {}, 0.0)
		var heard := _audio.played.size() + _audio.kit._pending.size() - waiting
		if kind in TankAudio.SILENT_EVENTS:
			assert_eq(heard, 0, "%s is listed silent" % kind)
		else:
			assert_gt(heard, 0, "%s plays something" % kind)


func test_the_reserved_events_sound_like_their_neighbours() -> void:
	# Nothing emits these today, but their names stay taken on the wire: a client on a later version must not crash.
	for kind: String in [TankEvents.ROTATION, TankEvents.LEVER, TankEvents.TURN]:
		_audio.kit.clear_played()
		_audio.on_cue(kind, _every_event()[kind])
		assert_has(_audio.played, "lever_clunk", kind)
	_audio.kit.clear_played()
	_audio.on_cue(TankEvents.DODGE, _every_event()[TankEvents.DODGE])
	assert_has(_audio.played, "evade_lurch")
	_audio.kit.clear_played()
	_audio.on_cue(TankEvents.TIME_UP, _every_event()[TankEvents.TIME_UP])
	assert_has(_audio.played, "horn_segment")


func test_the_recorded_sounds_stay_bounded() -> void:
	for _i in GameAudioKit.PLAYED_MAX * 2:
		_audio.on_cue(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_LIGHT, 1))
	assert_lte(_audio.played.size(), GameAudioKit.PLAYED_MAX)
	assert_eq(_audio.played.size(), _audio.played_db.size())


# --- Under a pause ----------------------------------------------------------------------------------------


func _crew_feed(rpm: float) -> Dictionary:
	var feed := _feed("drive", rpm, 1.0, true)
	feed.merge(_feed("gun", rpm, 1.0, false))
	return feed


func test_a_pause_stops_the_strokes_the_track_and_their_loops() -> void:
	_state.hull.speed_mps = 6.0
	for _i in 120:
		_travel += 6.0 * DT
		_audio.update(_state, DT, 1, _crew_feed(90.0), _travel)
	assert_false(_audio.kit.machine_loop("drive").all_off())
	assert_has(_audio.played, "track_link")
	_audio.kit._on_paused_changed(true, "test")
	_audio.kit.clear_played()
	for _i in 120:
		_travel += 6.0 * DT
		_audio.update(_state, DT, 1, _crew_feed(90.0), _travel)
	for id: String in ["diesel_fire_a", "cap_dump", "track_link", "track_squeak"]:
		assert_does_not_have(_audio.played, id, "%s under a pause" % id)
	for instance: String in ["drive", "gun", TankAudio.TRACK]:
		assert_true(_audio.kit.machine_loop(instance).all_off(), "%s closed" % instance)
	_audio.kit._on_paused_changed(false, "test")


func test_nothing_bursts_when_a_pause_ends() -> void:
	_state.hull.speed_mps = 6.0
	for _i in 60:
		_travel += 6.0 * DT
		_audio.update(_state, DT, 1, _crew_feed(90.0), _travel)
	_audio.kit._on_paused_changed(true, "test")
	# The view goes on under the pause: a rider may still pedal, so the revs run on 8 revolutions.
	for _i in 300:
		_travel += 6.0 * DT
		_audio.update(_state, DT, 1, _crew_feed(90.0), _travel)
	_audio.kit._on_paused_changed(false, "test")
	_audio.kit.clear_played()
	_travel += 6.0 * DT
	_audio.update(_state, DT, 1, _crew_feed(90.0), _travel)
	assert_lte(_audio.played.count("diesel_fire_a"), 1, "no catching up")
	assert_lte(_audio.played.count("track_link"), 1, "nor on the track")
	_audio.kit.clear_played()
	for _i in 60:
		_travel += 6.0 * DT
		_audio.update(_state, DT, 1, _crew_feed(90.0), _travel)
	assert_between(
		_audio.played.count("diesel_fire_a"), 1, 2, "1.5 revolutions on, the normal rate"
	)


func test_a_pause_closes_the_near_engines_though_they_still_live() -> void:
	_state = TankFixturesV4.make("near_ambush")
	_audio = _make(_state)
	_idle(0.3)
	var recon := _audio.kit.entry_loop("recon_engine")
	assert_false(recon.all_off())
	_audio.kit._on_paused_changed(true, "test")
	_idle(0.3)
	assert_true(recon.all_off(), "closed under the pause")
	_audio.kit._on_paused_changed(false, "test")
	_idle(0.3)
	assert_false(recon.all_off(), "and open again")


func test_a_far_boom_waits_out_a_pause_with_its_remaining_delay() -> void:
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 1360.0)
	)
	_idle(1.0)
	assert_does_not_have(_audio.played, "far_boom", "still 1 s away")
	_audio.kit._on_paused_changed(true, "test")
	_idle(5.0)
	assert_does_not_have(_audio.played, "far_boom", "held")
	_audio.kit._on_paused_changed(false, "test")
	_idle(0.5)
	assert_does_not_have(_audio.played, "far_boom", "not yet: the pause did not spend its delay")
	_idle(0.6)
	assert_eq(_audio.played.count("far_boom"), 1, "once")


func test_a_far_kill_seen_before_a_pause_goes_up_after_it() -> void:
	var medium := TankIds.enemy_code(TankIds.ENEMY_MEDIUM)
	_audio.on_cue(TankEvents.KILL, TankEvents.kill(11, medium, TankEvents.BY_SHELL, 0))
	_audio.on_cue(
		TankEvents.HIT,
		TankEvents.hit(TankEvents.ON_ENEMY, 11, 20.0, TankIds.SHELL_HEAVY, 0.0, 1360.0)
	)
	_audio.kit._on_paused_changed(true, "test")
	_idle(3.0)
	assert_does_not_have(_audio.played, "explode_big")
	_audio.kit._on_paused_changed(false, "test")
	_idle(2.1)
	assert_eq(_audio.played.count("explode_big"), 1)


# --- A full crew ------------------------------------------------------------------------------------------


## Six seats and the track for `seconds`, `lead_seat` leading, the rest a little apart in cadence and phase as bots
## are, with a dense script of events. Returns {seat: its revs}.
func _crew_run(
	a: TankAudio, state: TankState, lead_seat: String, rpm: float, power: float, seconds: float
) -> Dictionary:
	var revs := {}
	var offset := 0.0
	for seat: String in TankRig.SEATS:
		revs[seat] = offset
		offset += 0.137
	var travel_m := 0.0
	var script := _every_event()
	var kinds: Array = script.keys()
	var frames := roundi(seconds / DT)
	state.hull.speed_mps = 8.0
	for i in frames:
		var feed := {}
		var k := 0
		for seat: String in TankRig.SEATS:
			var seat_rpm := rpm if seat == lead_seat else rpm * (0.97 + 0.012 * float(k))
			revs[seat] = float(revs[seat]) + seat_rpm / 60.0 * DT
			feed[seat] = {
				"revs": revs[seat], "rpm": seat_rpm, "power": power, "lead": seat == lead_seat
			}
			k += 1
		travel_m += state.hull.speed_mps * DT
		if i % 20 == 0:
			var kind: String = kinds[(i / 20) % kinds.size()]
			if kind != TankEvents.TANK_LOST:
				a.on_cue(kind, script[kind])
		a.update(state, DT, 1, feed, travel_m)
		assert_lte(a.kit.loops_in_use(), 24, "the kit's loop players")
	return revs


func _sounds_of(bank: AudioBank, machine: String) -> Dictionary:
	var out := {}
	for ev: Dictionary in bank.machines[machine]["events"]:
		out[ev["sound"]] = true
	return out


func test_a_full_crew_keeps_every_lead_stroke_and_thins_only_the_others() -> void:
	var bank := AudioBank.load_bank(TankAudio.BANK_PATH)
	for lead_seat: String in TankRig.SEATS:
		var state := TankFixtures.state(4)
		var a := _make(state)
		state.hull.speed_mps = 8.0
		var revs := _crew_run(a, state, lead_seat, 110.0, 1.3, 8.0)
		var lead_machine: String = TankAudio.MACHINE_OF_SEAT[lead_seat]
		var voice := a.kit.machine_voice(lead_seat)
		assert_not_null(voice, lead_seat)
		# The lead's strokes are never thinned: everything the voice planned reached the record.
		var lead_sounds := _sounds_of(bank, lead_machine)
		var heard := 0
		for id: String in a.played:
			if lead_sounds.has(id):
				heard += 1
		assert_gt(heard, 0, lead_seat)
		assert_eq(heard, voice.fired, "%s: every stroke it planned" % lead_seat)
		assert_eq(voice.dropped, 0, "%s: none dropped" % lead_seat)
		assert_almost_eq(voice.planned_to(), float(revs[lead_seat]), 0.3, lead_seat)
		if lead_seat == "drive":
			# And what it planned is the pattern, exactly: the first seat's revs start at 0.
			assert_eq(
				a.played.count("diesel_fire_a"),
				_pattern_count(0.2778, voice.planned_to()),
				"one per revolution of cylinder a"
			)
		assert_gt(a.kit.thinned, 0, "%s: a crew at 110 rpm asks more than the cap" % lead_seat)


func test_a_full_crews_other_strokes_keep_the_kits_gap() -> void:
	var bank := AudioBank.load_bank(TankAudio.BANK_PATH)
	for lead_seat: String in TankRig.SEATS:
		var state := TankFixtures.state(4)
		var a := _make(state)
		_crew_run(a, state, lead_seat, 110.0, 1.3, 8.0)
		var others := {}
		for seat: String in TankRig.SEATS:
			if seat != lead_seat:
				others.merge(_sounds_of(bank, TankAudio.MACHINE_OF_SEAT[seat]))
		var mine := _sounds_of(bank, TankAudio.MACHINE_OF_SEAT[lead_seat])
		mine.merge(_sounds_of(bank, TankAudio.TRACK))
		var times: Array[float] = []
		for i in a.played.size():
			if (
				others.has(a.played[i])
				and not mine.has(a.played[i])
				and not _is_cue_sound(a.played[i])
			):
				times.append(a.played_t[i])
		times.sort()
		var in_a_second := 0
		for i in times.size():
			var n := 0
			for j in range(i, times.size()):
				if times[j] - times[i] >= 1.0:
					break
				n += 1
			in_a_second = maxi(in_a_second, n)
		assert_gt(times.size(), 0, lead_seat)
		assert_lte(in_a_second, 17, "%s: 16.7 other strokes a second at most" % lead_seat)


## Sounds a cue also plays: the bow guns' burst and the pawl's latch would count as strokes.
func _is_cue_sound(id: String) -> bool:
	return id == "bow_shot" or id == "hoist_pawl"


func test_a_full_crew_finds_a_voice_for_everything_with_real_players() -> void:
	# force_audio: real players on the dummy driver, in real time, so a sound that ends gives its voice back. Their pools
	# are what the voiceless count measures.
	var state := TankFixtures.state(4)
	var g := U.make_game(state, Wl.SOLO, 1)
	autofree(g)
	var a := TankAudio.new()
	a.game = g
	a.kit.force_audio = true
	add_child_autofree(a)
	assert_false(a.kit.silent, "the kit has its players")
	state.hull.speed_mps = 8.0
	var revs := {}
	var script := _every_event()
	var kinds: Array = script.keys()
	var travel_m := 0.0
	for i in 240:
		var feed := {}
		for seat: String in TankRig.SEATS:
			revs[seat] = float(revs.get(seat, 0.137 * float(feed.size()))) + 110.0 / 60.0 * DT
			feed[seat] = {"revs": revs[seat], "rpm": 110.0, "power": 1.3, "lead": seat == "drive"}
		travel_m += state.hull.speed_mps * DT
		if i % 20 == 0 and kinds[(i / 20) % kinds.size()] != TankEvents.TANK_LOST:
			a.on_cue(kinds[(i / 20) % kinds.size()], script[kinds[(i / 20) % kinds.size()]])
		a.update(state, DT, 1, feed, travel_m)
		await wait_physics_frames(1)
	assert_eq(a.kit.voiceless, 0, "nothing was left without a voice")


# --- With the view ----------------------------------------------------------------------------------------


func test_the_views_feed_drives_it_stroke_for_crank() -> void:
	var state := TankFixtures.state(3)
	var v := U.view_of(self, state)
	var a := v.audio
	state.hull.speed_mps = 0.0
	for r: TankRiderState in state.riders:
		r.cadence_rpm = 90
		r.raw_w = 200.0
	for _i in 180:
		U.run(v, 1, DT)
	var phase := v.machine_phase("drive")
	assert_gt(phase, 0.0, "the view's crank turned")
	var planned := a.kit.machine_voice("drive").planned_to()
	assert_between(
		planned - phase, 0.0, 90.0 / 60.0 * 0.05 + 1e-3, "one horizon ahead of the crank"
	)
	assert_gte(a.played.count("diesel_fire_a"), floori(phase) - 1)
	state.hull.breakdown = true
	a.kit.clear_played()
	var count := 0
	for _i in 60:
		U.run(v, 1, DT)
		count += a.played.count("diesel_fire_a")
	assert_eq(count, 0, "a breakdown stops the picture and the sound together")


func test_the_view_makes_the_adapter_and_hands_it_game_events() -> void:
	var v := U.view_of(self, TankFixtures.state(3))
	assert_not_null(v.audio)
	assert_true(v.audio is TankAudio)
	v.game.cue.emit(TankEvents.SHOT, TankEvents.shot(0, TankIds.SHELL_HEAVY, 1))
	v.advance(DT)
	assert_has(v.audio.played, "gun_low")
	assert_eq(v.audio.local_peer, 1)


func test_the_track_follows_the_tread_the_view_draws() -> void:
	var state := TankFixtures.state(3)
	state.hull.speed_mps = 6.0
	var v := U.view_of(self, state)
	var from := v.travel
	U.run(v, 120, DT)
	var metres := (v.travel - from) / (TankConst.PX_PER_M * TankView.S)
	assert_gt(metres, 0.0, "the hull moved on screen")
	var voice := v.audio.kit.machine_voice(TankAudio.TRACK)
	assert_not_null(voice)
	assert_almost_eq(
		voice.planned_to(),
		v.travel / (TankConst.PX_PER_M * TankView.S) / TankAudio.TRACK_M_PER_REV,
		0.1,
		"the track machine reads the view's travel"
	)
	assert_has(v.audio.played, "track_link")


func test_a_reserve_room_is_silent_because_its_crank_stands_still() -> void:
	var state := TankFixtures.state(3)
	var v := U.view_of(self, state)
	var a := v.audio
	var empty := state.station(TankIds.ENGINE_DIESEL)
	empty.slot = -1
	a.kit.clear_played()
	for _i in 60:
		U.run(v, 1, DT)
	assert_does_not_have(a.played, "diesel_fire_a", "an empty seat")
