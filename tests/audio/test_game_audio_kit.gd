extends GutTest
## GameAudioKit (SPEC_AUDIO 1.3, 2.5, 5): the Node a game talks to. Headless it stays silent and error-free, with every
## record kept; force_audio builds real players on the Dummy driver, for the voice pools.

const BANK := "res://tests/audio/fixtures/bank_min.json"
const DT := 1.0 / 60.0


func before_each() -> void:
	AudioBuses.clear_ducks()


func after_each() -> void:
	AudioBuses.clear_ducks()


func _kit(seed_value: int = 7) -> GameAudioKit:
	var kit := GameAudioKit.new()
	add_child_autofree(kit)
	assert_true(kit.setup(BANK, seed_value))
	return kit


## A kit with real players, every sound of the bank a short code-built stream.
func _loud_kit(mix: Dictionary = {}) -> GameAudioKit:
	var kit := GameAudioKit.new()
	kit.force_audio = true
	add_child_autofree(kit)
	var bank := AudioBank.load_bank(BANK)
	bank.mix.merge(mix, true)
	for id: String in bank.sounds:
		for v in bank.variants(id):
			bank.set_stream(id, v, SfxSynth.tone("sine", 200.0, 1.0))
	assert_true(kit.setup_bank(bank, 1))
	assert_false(kit.silent)
	return kit


func _count(kit: GameAudioKit, id: String) -> int:
	return kit.played.count(id)


func _players(kit: GameAudioKit) -> int:
	var n := 0
	for c in kit.get_children():
		if c is AudioStreamPlayer:
			n += 1
	return n


func _run_machine(kit: GameAudioKit, seconds: float, rpm: float, params: Dictionary) -> CrankClock:
	var clock := CrankClock.new()
	for i in int(seconds / DT):
		clock.advance(rpm, DT)
		kit.drive("a", "main", clock.revs, rpm, params, true)
		kit.commit(DT)
	return clock


func test_headless_is_silent_with_no_players() -> void:
	var kit := _kit()
	assert_true(kit.silent)
	_run_machine(kit, 2.0, 90.0, {"power": 1.0})
	kit.cue("shot")
	kit.set_bed("night")
	kit.commit(DT)
	assert_eq(_players(kit), 0)
	assert_gt(kit.played.size(), 0, "records kept")


func test_sim_speed_is_silent() -> void:
	CmdLine.set_args(PackedStringArray(["--sim-speed=4"]))
	var kit := GameAudioKit.new()
	kit.force_audio = false
	add_child_autofree(kit)
	kit.setup(BANK, 1)
	CmdLine.set_args(PackedStringArray(), false)
	assert_true(kit.silent)


func test_no_bank_is_silent_and_no_errors() -> void:
	var kit := GameAudioKit.new()
	add_child_autofree(kit)
	assert_false(kit.setup("res://tests/audio/fixtures/does_not_exist.json", 1))
	assert_push_error("does_not_exist.json")
	assert_true(kit.silent)
	kit.drive("a", "main", 1.0, 90.0, {}, true)
	kit.cue("shot")
	kit.sound("bang")
	kit.set_bed("night")
	kit.set_loop("drag_scream", {})
	kit.commit(DT)
	assert_eq(kit.played.size(), 0)


func test_constants_keep_their_bound() -> void:
	var worst := (
		(GameAudioKit.HORIZON_MAX_S + GameAudioKit.ATTACK_GUARD_S) * GameAudioKit.LOCKED_PITCH_MAX
	)
	assert_gte(GameAudioKit.PREROLL_S, worst, "a seek never needs to start before the file")


func test_strokes_are_recorded_with_base_ids_levels_and_due_times() -> void:
	var kit := _kit()
	_run_machine(kit, 4.0, 90.0, {"power": 1.0})
	assert_eq(_count(kit, "stroke"), 12 - 1 + 1, "two a revolution, 6 revolutions")
	assert_false(kit.played.has("stroke_1"), "never the variant file")
	assert_eq(kit.played.size(), kit.played_db.size())
	assert_eq(kit.played.size(), kit.played_t.size())
	var i := kit.played.find("stroke")
	assert_almost_eq(kit.played_db[i], -2.0, 0.01, "db + db_by at power 1")
	assert_almost_eq(kit.played_t[i], 0.25 / 1.5, 1e-3, "due when revs reach the fraction")
	var t := kit.played.find("tick")
	assert_gte(t, 0, "tick: lead_only, power above its gate")


func test_when_gates_a_stroke() -> void:
	var kit := _kit()
	_run_machine(kit, 2.0, 90.0, {"power": 0.1})
	assert_eq(_count(kit, "tick"), 0)
	assert_gt(_count(kit, "stroke"), 0)


func test_lead_only_and_other_gain() -> void:
	var kit := _kit()
	var lead := CrankClock.new()
	var other := CrankClock.new()
	for i in 120:
		lead.advance(90.0, DT)
		other.advance(60.0, DT)
		kit.drive("o", "main", other.revs, 60.0, {"power": 1.0}, false)
		kit.commit(DT)
	# Nobody leads here: others rise 4 dB (spectator).
	var i := kit.played.find("stroke")
	assert_almost_eq(kit.played_db[i], -2.0 - 10.0 + 4.0, 0.01, "no seat: others at -6 dB")
	assert_eq(_count(kit, "tick"), 0, "lead_only stays with the lead")
	kit.clear_played()
	for f in 120:
		lead.advance(90.0, DT)
		other.advance(60.0, DT)
		kit.drive("l", "main", lead.revs, 90.0, {"power": 1.0}, true)
		kit.drive("o", "main", other.revs, 60.0, {"power": 1.0}, false)
		kit.commit(DT)
	var low := 0.0
	var high := -100.0
	for k in kit.played.size():
		if kit.played[k] == "stroke":
			low = minf(low, kit.played_db[k])
			high = maxf(high, kit.played_db[k])
	assert_almost_eq(high, -2.0, 0.01, "lead at table level")
	assert_almost_eq(low, -12.0, 0.01, "other at mix.other_db")


func test_other_doubling() -> void:
	var kit := _kit()
	for i in 4:
		kit.drive("o%d" % i, "main", 0.0, 90.0, {"power": 1.0}, false)
	kit.drive("l", "main", 0.0, 90.0, {"power": 1.0}, true)
	assert_almost_eq(kit._other_trim(4, true), -10.0 - 3.0, 0.001, "log2(4 / 2) doublings")
	assert_almost_eq(kit._other_trim(2, true), -10.0, 0.001)
	assert_almost_eq(kit._other_trim(2, false), -6.0, 0.001)


func test_undriven_instance_closes_its_loops() -> void:
	var kit := _kit()
	_run_machine(kit, 1.0, 90.0, {"power": 1.0})
	var loop := kit.machine_loop("a")
	assert_false(loop.all_off())
	for i in 10:
		kit.commit(DT)
	assert_true(loop.all_off(), "no drive this frame: it stops")
	assert_eq(kit.loops_in_use(), 0)


func test_stop_machine_frees_the_instance_once_closed() -> void:
	var kit := _kit()
	_run_machine(kit, 1.0, 90.0, {"power": 1.0})
	kit.stop_machine("a")
	for i in 10:
		kit.commit(DT)
	assert_null(kit.machine_voice("a"))
	assert_eq(kit.loops_in_use(), 0)


func test_a_loop_is_recorded_once_on_each_off_to_on() -> void:
	var kit := _kit()
	_run_machine(kit, 1.0, 90.0, {"power": 1.0})
	assert_eq(_count(kit, "body"), 1)
	assert_eq(_count(kit, "whine"), 1)
	_run_machine(kit, 0.5, 0.0, {"power": 0.0})
	_run_machine(kit, 0.5, 90.0, {"power": 1.0})
	assert_eq(_count(kit, "body"), 2)


func test_unknown_names_warn_once() -> void:
	var kit := _kit()
	kit.cue("nope")
	kit.cue("nope")
	assert_push_warning("unknown cue 'nope'")
	kit.drive("a", "nope", 0.0, 90.0, {}, true)
	kit.drive("a", "nope", 0.0, 90.0, {}, true)
	assert_push_warning("unknown machine 'nope'")
	kit.sound("nope")
	assert_push_warning("unknown sound 'nope'")
	kit.set_loop("nope", {})
	assert_push_warning("unknown loop 'nope'")
	kit.set_bed("nope")
	assert_push_warning("unknown bed 'nope'")
	kit.commit(DT)
	assert_eq(kit.played.size(), 0)


func test_cue_fires_at_once_and_after_its_delay() -> void:
	var kit := _kit()
	kit.cue("shot", {"flight": 0.5, "scale": 2.0, "gain": 3.0})
	assert_eq(kit.played, ["bang"] as Array[String])
	assert_eq(kit.played_db, [-4.0] as Array[float])
	for i in 59:
		kit.commit(DT)
	assert_eq(_count(kit, "boom"), 0, "delay_s + delay_var")
	for i in 3:
		kit.commit(DT)
	assert_eq(_count(kit, "boom"), 1)
	assert_almost_eq(kit.played_db[kit.played.find("boom")], -6.0 + 3.0, 0.01, "db_var adds")


func test_cue_other_db_and_duck_on_the_lead_only() -> void:
	var kit := _kit()
	kit.cue("shot", {}, false)
	assert_eq(kit.played_db[0], -4.0 - 8.0, "the cue's other_db")
	AudioBuses.tick(0.005)
	assert_eq(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0, "someone else's shot ducks nothing")
	kit.cue("quiet", {}, false)
	assert_eq(kit.played_db[kit.played_db.size() - 1], -10.0, "else mix.other_db")
	kit.cue("shot")
	AudioBuses.tick(0.01)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -4.0, 0.01, "own gun ducks")


## The preview applies the same defaults (offline_mix.mjs duckEnvelope), so critics hear the duck the game plays.
func test_cue_duck_without_times_takes_the_mix_defaults() -> void:
	var kit := _kit()
	kit.cue("plain_duck")
	AudioBuses.tick(GameAudioKit.DUCK_ATTACK_S)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -4.0, 0.01, "10 ms attack")
	AudioBuses.tick(GameAudioKit.DUCK_RELEASE_S / 2.0)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -2.0, 0.01, "350 ms release")
	AudioBuses.tick(GameAudioKit.DUCK_RELEASE_S)
	assert_eq(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0, "and it is over")


func test_sound_records_and_clear_played() -> void:
	var kit := _kit()
	kit.sound("bang", -3.0, 1.2)
	assert_eq(kit.played, ["bang"] as Array[String])
	assert_eq(kit.played_db, [-3.0] as Array[float])
	kit.clear_played()
	assert_eq(kit.played.size(), 0)
	assert_eq(kit.played_db.size(), 0)
	assert_eq(kit.played_t.size(), 0)


func test_played_is_bounded() -> void:
	var kit := _kit()
	for i in GameAudioKit.PLAYED_MAX + 10:
		kit.sound("bang", float(i))
	assert_eq(kit.played.size(), GameAudioKit.PLAYED_MAX)
	assert_eq(kit.played_db.size(), GameAudioKit.PLAYED_MAX)
	assert_eq(kit.played_t.size(), GameAudioKit.PLAYED_MAX)
	assert_eq(
		kit.played_db[GameAudioKit.PLAYED_MAX - 1],
		float(GameAudioKit.PLAYED_MAX + 9),
		"newest last"
	)


func test_set_loop_wants_a_call_each_frame() -> void:
	var kit := _kit()
	for i in 10:
		kit.set_loop("drag_scream", {"tension": 1.0})
		kit.commit(DT)
	var loop := kit.entry_loop("drag_scream")
	assert_eq(loop.on[0], 1)
	assert_eq(_count(kit, "scream"), 1)
	for i in 10:
		kit.commit(DT)
	assert_true(loop.all_off(), "no call, it closes")
	assert_eq(kit.loops_in_use(), 0)


func test_set_loop_params_gate_it() -> void:
	var kit := _kit()
	for i in 10:
		kit.set_loop("drag_scream", {"tension": 0.1})
		kit.commit(DT)
	assert_eq(kit.entry_loop("drag_scream").on[0], 0)


func test_bed_spots_are_seeded_by_the_kit() -> void:
	var a := _kit(11)
	var b := _kit(11)
	var c := _kit(12)
	for k: GameAudioKit in [a, b, c]:
		k.set_bed("night")
		for i in 900:
			k.commit(DT)
	assert_gt(_count(a, "cricket"), 0)
	assert_eq(a.played, b.played)
	assert_eq(a.played_t, b.played_t)
	assert_ne(a.played_t, c.played_t)


func test_bed_params_reach_the_layers() -> void:
	var kit := _kit()
	kit.set_bed("night")
	kit.bed_params({"gust": 0.0})
	for i in 120:
		kit.commit(DT)
	var quiet := kit.current_bed().loops.db[0]
	kit.bed_params({"gust": 1.0})
	for i in 120:
		kit.commit(DT)
	assert_almost_eq(quiet, -26.0, 0.1)
	assert_almost_eq(kit.current_bed().loops.db[0], -20.0, 0.1)


func test_set_bed_crossfades_and_frees_the_old_one() -> void:
	var kit := _kit()
	kit.set_bed("night")
	for i in 120:
		kit.commit(DT)
	assert_eq(kit.loops_in_use(), 1)
	kit.set_bed("day")
	for i in 3:
		kit.commit(DT)
	assert_eq(kit.loops_in_use(), 2, "both run through the crossfade")
	for i in 180:
		kit.commit(DT)
	assert_eq(kit.loops_in_use(), 1, "the old bed is gone")
	kit.set_bed("")
	for i in 180:
		kit.commit(DT)
	assert_eq(kit.loops_in_use(), 0, '"" fades out')
	assert_null(kit.current_bed())


func test_pause_drops_the_bed_and_holds_delayed_cues() -> void:
	var kit := _kit()
	kit.set_bed("day")
	kit.bed_params({})
	for i in 180:
		kit.commit(DT)
	assert_almost_eq(kit.current_bed().loops.db[0], -26.0, 0.1)
	kit.cue("shot")
	kit._on_paused_changed(true, "test")
	for i in 180:
		kit.commit(DT)
	assert_almost_eq(kit.current_bed().loops.db[0], -35.0, 0.1, "beds drop 9 dB")
	assert_eq(_count(kit, "boom"), 0, "held")
	kit._on_paused_changed(false, "test")
	for i in 60:
		kit.commit(DT)
	assert_almost_eq(kit.current_bed().loops.db[0], -26.0, 0.1, "and come back")
	assert_eq(_count(kit, "boom"), 1, "and it plays")


## A routine stop-and-go: the bed's timers run on under the pause, so its bursts play out there, 9 dB down. Saved up,
## they would all start in the first second of the resume, on a silent road.
func test_a_long_pause_saves_up_no_bed_spots_for_the_resume() -> void:
	var kit := _kit()
	kit.set_bed("night")
	kit.bed_params({})
	kit._on_paused_changed(true, "test")
	for i in 120 * 60:
		kit.commit(DT)
	assert_gt(_count(kit, "cricket"), 40, "the bed's details go on under the pause")
	var before := _count(kit, "cricket")
	kit._on_paused_changed(false, "test")
	for i in 60:
		kit.commit(DT)
	assert_lte(_count(kit, "cricket") - before, 9, "one second of the bed's own rate, no more")


func test_the_event_bus_pauses_it() -> void:
	var kit := _kit()
	var bus := get_tree().root.get_node("EventBus")
	assert_true(bus.is_connected("paused_changed", kit._on_paused_changed))


func test_stop_all_clears_state_keeps_records() -> void:
	var kit := _kit()
	_run_machine(kit, 1.0, 90.0, {"power": 1.0})
	kit.set_bed("night")
	kit.cue("shot")
	kit.stop_all()
	assert_eq(kit.loops_in_use(), 0)
	assert_null(kit.machine_voice("a"))
	assert_null(kit.current_bed())
	var n := kit.played.size()
	assert_gt(n, 0)
	for i in 120:
		kit.commit(DT)
	assert_eq(kit.played.size(), n, "the delayed boom went with it")


func test_loud_kit_starts_voices_on_the_right_bus() -> void:
	var kit := _loud_kit()
	_run_machine(kit, 1.0, 90.0, {"power": 1.0})
	var machines := 0
	for c in kit.get_children():
		var p := c as AudioStreamPlayer
		if p != null and str(p.bus) == AudioBuses.MACHINES:
			machines += 1
	assert_gt(machines, 0)
	kit.stop_all()


func test_loud_kit_clamps_pitch() -> void:
	var kit := _loud_kit()
	kit.set_loop("drag_scream", {"tension": 0.5})
	kit.commit(DT)
	var loop_player := kit.get_child(kit.get_child_count() - 1) as AudioStreamPlayer
	assert_almost_eq(loop_player.pitch_scale, 0.5, 0.001)
	for i in 240:
		kit.set_loop("drag_scream", {"tension": 100.0})
		kit.commit(DT)
	assert_eq(loop_player.pitch_scale, GameAudioKit.PITCH_MAX, "Godot errors on a wild pitch")
	kit.sound("tick", 0.0, 3.0, AudioBuses.MACHINES)
	var stroke := kit.get_child(kit.get_child_count() - 1) as AudioStreamPlayer
	assert_almost_eq(
		stroke.pitch_scale, GameAudioKit.LOCKED_PITCH_MAX, 1e-5, "locked strokes keep the bound"
	)
	kit.stop_all()


func test_loud_kit_pools_are_capped_and_lead_is_not_stolen() -> void:
	var kit := _loud_kit({"sfx_voices": 2, "machine_voices": 2, "spot_voices": 1})
	kit.sound("bang", 0.0, 1.0, AudioBuses.SFX)
	kit.sound("boom", 0.0, 1.0, AudioBuses.SFX)
	kit.sound("bang", 0.0, 1.0, AudioBuses.SFX)
	assert_eq(_players(kit), 2, "Sfx stays in its pool: the oldest was stolen")
	assert_eq(kit.voiceless, 0)
	kit._start_locked(AudioStreamWAV.new(), 0.0, 0.0, 1.0, AudioBuses.MACHINES, 5, true)
	kit._start_locked(AudioStreamWAV.new(), 0.0, 0.0, 1.0, AudioBuses.MACHINES, 5, true)
	assert_eq(_players(kit), 4)
	kit._start_locked(AudioStreamWAV.new(), 0.0, 0.0, 1.0, AudioBuses.MACHINES, 3, false)
	# A stream with no data ends at once on some drivers: only count a refusal if the voices still play.
	var voices: Array = kit._pools[AudioBuses.MACHINES]
	assert_eq(voices.size(), 2, "no third machine voice")
	kit.stop_all()


func test_steal_prefers_lowest_priority_then_oldest_and_never_lead_for_other() -> void:
	var kit := _kit()
	var make := func(priority: int, lead: bool, started: float) -> GameAudioKit.Voice:
		var v := GameAudioKit.Voice.new()
		v.priority = priority
		v.lead = lead
		v.started = started
		return v
	var a: GameAudioKit.Voice = make.call(5, true, 1.0)
	var b: GameAudioKit.Voice = make.call(3, false, 2.0)
	var c: GameAudioKit.Voice = make.call(3, false, 1.5)
	var pool: Array[GameAudioKit.Voice] = [a, b, c]
	assert_same(kit._steal_voice(pool, 5, true), c, "lowest priority, then oldest")
	assert_same(kit._steal_voice(pool, 3, false), c, "others take others")
	var leads: Array[GameAudioKit.Voice] = [a]
	assert_null(
		kit._steal_voice(leads, 3, false), "a lead stroke is never stolen by a non-lead one"
	)
	assert_null(kit._steal_voice(leads, 3, true), "nor a higher priority for a lower one")


func test_loop_pool_cap_lead_takes_a_non_lead_player() -> void:
	var kit := _kit()
	kit._bank.mix["max_loop_players"] = 2
	kit.drive("o1", "main", 0.0, 90.0, {"power": 1.0}, false)
	kit.drive("o2", "main", 0.0, 90.0, {"power": 1.0}, false)
	kit.drive("o3", "main", 0.0, 90.0, {"power": 1.0}, false)
	kit.commit(DT)
	assert_eq(kit.loops_in_use(), 2)
	assert_eq(kit.thinned, 1, "the non-lead layer that found the pool full stays off")
	kit.drive("o1", "main", 0.0, 90.0, {"power": 1.0}, false)
	kit.drive("o2", "main", 0.0, 90.0, {"power": 1.0}, false)
	kit.drive("o3", "main", 0.0, 90.0, {"power": 1.0}, false)
	kit.drive("l", "main", 0.0, 90.0, {"power": 1.0}, true)
	kit.commit(DT)
	assert_eq(kit.loops_in_use(), 2)
	var slot: GameAudioKit.MachineSlot = kit._machines["l"]
	assert_eq(slot.loops.granted[0], 1, "the lead took a non-lead's player")
	assert_eq(slot.loops.granted[1], 1, "for each of its layers")
	var other: GameAudioKit.MachineSlot = kit._machines["o1"]
	assert_eq(other.loops.granted[0], 0, "the non-lead's layer is off")


func test_exit_tree_stops_all() -> void:
	var kit := GameAudioKit.new()
	add_child(kit)
	kit.setup(BANK, 1)
	kit.set_bed("night")
	kit.commit(DT)
	remove_child(kit)
	assert_eq(kit.loops_in_use(), 0)
	kit.free()


# --- Flights and sides ---------------------------------------------------------------------------


## A bank with one flight cue: a looping `wind`, over `flight_s`, from pan0 to pan1.
func _flight_kit(loud: bool) -> GameAudioKit:
	var kit := GameAudioKit.new()
	kit.force_audio = loud
	add_child_autofree(kit)
	var bank := AudioBank.load_bank(BANK)
	bank.cues["fly"] = {
		"hits":
		[
			{
				"sound": "wind",
				"db": -10.0,
				"pan_var": "pan0",
				"flight":
				{
					"dur_var": "flight_s",
					"pan_to_var": "pan1",
					"gain": [[0.0, -20.0], [0.5, 0.0], [1.0, -6.0]],
					"pitch": [[0.0, 1.2], [1.0, 0.8]],
				}
			}
		]
	}
	if loud:
		for id: String in bank.sounds:
			for v in bank.variants(id):
				var s := SfxSynth.tone("sine", 200.0, 1.0)
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_end = 1000
				bank.set_stream(id, v, s)
	assert_true(kit.setup_bank(bank, 1))
	return kit


func _commit_for(kit: GameAudioKit, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		kit.commit(DT)


func test_a_flight_runs_for_the_time_it_was_given_silent_or_not() -> void:
	var kit := _flight_kit(false)
	kit.cue("fly", {"flight_s": 2.0, "pan0": -0.5, "pan1": 0.5})
	assert_eq(kit.flight_starts, 1)
	assert_eq(kit.flights_live(), 1)
	_commit_for(kit, 1.9)
	assert_eq(kit.flights_live(), 1, "still in the air")
	_commit_for(kit, 0.2)
	assert_eq(kit.flights_live(), 0, "landed")


func test_a_flights_level_pitch_and_side_follow_it_and_its_player_stops_at_the_end() -> void:
	var kit := _flight_kit(true)
	kit.cue("fly", {"flight_s": 1.0, "pan0": -0.5, "pan1": 0.5})
	var f: GameAudioKit.Flight = kit._flights[0]
	var player: AudioStreamPlayer = f.voice.player
	assert_true(player.playing)
	assert_eq(
		str(player.bus), AudioBuses.pan_bus(AudioBuses.SFX, -0.5), "starts on the launch's side"
	)
	assert_almost_eq(player.volume_db, -30.0, 0.5, "from the start of its curve")
	assert_almost_eq(player.pitch_scale, 1.2, 0.01)
	_commit_for(kit, 0.5)
	assert_almost_eq(player.volume_db, -10.0, 1.0, "the top of the curve")
	assert_eq(str(player.bus), AudioBuses.SFX, "over the middle of the screen")
	assert_almost_eq(player.pitch_scale, 1.0, 0.02)
	_commit_for(kit, 0.4)
	assert_eq(
		str(player.bus), AudioBuses.pan_bus(AudioBuses.SFX, 0.5), "and comes down on the other side"
	)
	_commit_for(kit, 0.2)
	assert_eq(kit.flights_live(), 0)
	assert_false(player.playing, "a looping voice ends with its flight")


func test_a_pause_holds_a_flight_and_a_resume_runs_it_on() -> void:
	var kit := _flight_kit(true)
	kit.cue("fly", {"flight_s": 1.0})
	var player: AudioStreamPlayer = kit._flights[0].voice.player
	_commit_for(kit, 0.2)
	kit._on_paused_changed(true, "test")
	_commit_for(kit, 5.0)
	assert_eq(kit.flights_live(), 1)
	assert_true(player.stream_paused)
	kit._on_paused_changed(false, "")
	_commit_for(kit, 0.1)
	assert_false(player.stream_paused)
	_commit_for(kit, 1.0)
	assert_eq(kit.flights_live(), 0)


func test_a_stolen_flight_lets_go_of_its_player() -> void:
	var kit := _flight_kit(true)
	kit._bank.mix["sfx_voices"] = 1
	kit.cue("fly", {"flight_s": 5.0})
	assert_eq(kit.flights_live(), 1)
	kit.sound("bang")
	kit.commit(DT)
	assert_eq(kit.flights_live(), 0, "the newer voice of its priority took it")
	assert_eq(kit.voiceless, 0)


func test_a_flight_with_a_high_priority_keeps_its_voice() -> void:
	var kit := _flight_kit(true)
	kit._bank.mix["sfx_voices"] = 1
	var c: Dictionary = kit._bank.cues["fly"]
	(c["hits"][0] as Dictionary)["priority"] = 8
	kit.cue("fly", {"flight_s": 5.0})
	kit.sound("bang")
	kit.commit(DT)
	assert_eq(kit.flights_live(), 1, "a lower priority cannot take it")
	assert_eq(kit.voiceless, 1, "and finds no voice")


## A kit with a one-player Sfx pool, a flight on it, and a crowd cue.
func _crowd_kit(crowd_voices: int) -> GameAudioKit:
	var kit := _flight_kit(true)
	kit._bank.mix["sfx_voices"] = 1
	kit._bank.mix["crowd_voices"] = crowd_voices
	kit._bank.cues["tick_crowd"] = {
		"hits": [{"sound": "bang", "priority": 3, "crowd": true, "pan_var": "pan"}]
	}
	return kit


func test_a_crowd_hit_takes_no_player_from_a_flight() -> void:
	var kit := _crowd_kit(2)
	kit.cue("fly", {"flight_s": 5.0})
	var serial: int = kit._pools[AudioBuses.SFX][0].serial
	kit.cue("tick_crowd", {"pan": -0.5})
	kit.cue("tick_crowd", {"pan": 0.5})
	kit.commit(DT)
	assert_eq(kit.flights_live(), 1, "the flight still flies")
	assert_eq(kit._pools[AudioBuses.SFX][0].serial, serial, "on its own player")
	assert_eq(kit._pools[GameAudioKit.CROWD].size(), 2)
	assert_eq(kit.voiceless, 0)
	assert_true(kit.stolen.is_empty(), "%s" % [kit.stolen])
	var player: AudioStreamPlayer = kit._pools[GameAudioKit.CROWD][0].player
	assert_eq(str(player.bus), AudioBuses.pan_bus(AudioBuses.SFX, -0.5), "and it pans")


func test_a_full_crowd_pool_steals_only_inside_itself_and_says_so() -> void:
	var kit := _crowd_kit(2)
	kit.cue("fly", {"flight_s": 5.0})
	for _i in 3:
		kit.cue("tick_crowd")
	assert_eq(kit._pools[GameAudioKit.CROWD].size(), 2, "the pool stays at its cap")
	assert_eq(kit.stolen, {"Crowd:3": 1}, "one of the crowd was cut short")
	assert_eq(kit.crowd_voiceless, 0)
	kit.commit(DT)
	assert_eq(kit.flights_live(), 1, "and no flight was touched")


func test_an_other_riders_crowd_hit_is_dropped_before_it_cuts_your_own() -> void:
	var kit := _crowd_kit(1)
	kit.cue("tick_crowd", {}, true)
	kit.cue("tick_crowd", {}, false)
	assert_eq(kit.crowd_voiceless, 1)
	assert_eq(kit.voiceless, 1)
	assert_true(kit.stolen.is_empty())


func test_without_crowd_voices_a_crowd_hit_is_any_other_hit_of_its_bus() -> void:
	var kit := _crowd_kit(0)
	kit.cue("tick_crowd")
	assert_eq(kit._pools[GameAudioKit.CROWD].size(), 0)
	assert_eq(kit._pools[AudioBuses.SFX].size(), 1)


func test_a_stolen_voice_is_counted_by_the_pool_and_priority_it_was_taken_from() -> void:
	var kit := _loud_kit({"sfx_voices": 1})
	kit.sound("bang", 0.0, 1.0, AudioBuses.SFX)
	kit.sound("boom", 0.0, 1.0, AudioBuses.SFX)
	assert_eq(kit.stolen, {"Sfx:%d" % GameAudioKit.CUE_PRIORITY: 1})


func test_a_hit_may_name_its_file_and_otherwise_takes_the_round_robin() -> void:
	var kit := _flight_kit(false)
	kit._bank.cues["pick"] = {"hits": [{"sound": "bang", "variant_var": "vr"}]}
	var before: int = kit._variant.get("bang", 0)
	kit.cue("pick", {"vr": 1})
	assert_eq(int(kit._variant.get("bang", 0)), before, "the round robin stays where it was")
	kit.cue("pick")
	assert_eq(int(kit._variant.get("bang", 0)), before + 1, "no var: the round robin")
	assert_eq(kit.variants_of("bang"), kit._bank.variants("bang"))
	assert_eq(kit.variants_of("no such sound"), 1)


func test_a_delayed_flight_starts_when_its_delay_is_over() -> void:
	var kit := _flight_kit(false)
	var c: Dictionary = kit._bank.cues["fly"]
	(c["hits"][0] as Dictionary)["delay_s"] = 0.2
	kit.cue("fly", {"flight_s": 1.0})
	assert_eq(kit.flight_starts, 0)
	_commit_for(kit, 0.25)
	assert_eq(kit.flight_starts, 1)


func test_a_bank_may_not_fly_a_sound_that_is_no_loop() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BANK))
	doc["cues"]["bad"] = {"hits": [{"sound": "bang", "flight": {"dur_s": 1.0}}]}
	var errors := AudioBank.validate(doc)
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "flight")


func test_a_panned_voice_plays_through_a_send_of_sfx() -> void:
	var kit := _loud_kit()
	kit._fire("bang", 0, -10.0, 1.0, AudioBuses.SFX, 6, true, -0.5)
	var bus := AudioBuses.pan_bus(AudioBuses.SFX, -0.5)
	var found := false
	for c in kit.get_children():
		if c is AudioStreamPlayer and str(c.bus) == bus:
			found = true
	assert_true(found, "on the left send")
