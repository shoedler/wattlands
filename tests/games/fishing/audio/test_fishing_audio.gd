extends GutTest
## Turbo Reel's adapter over GameAudioKit, on the real bank: the cue map, the 1:1 lock of the strokes
## to the crank each boat draws, and what the fight, the sea and the other boats do to the sound.

const FX := preload("res://tests/games/fishing/view/fishing_view_fixtures.gd")
const BANK := "res://assets/fishing/audio/audio.json"
const MANIFEST := "res://assets/fishing/audio/audio_manifest.json"
const DT := 1.0 / 60.0


func _audio(p_seed: int = 1) -> FishingAudio:
	var a := FishingAudio.new()
	a.rng_seed = p_seed
	add_child_autofree(a)
	return a


func _boat(cadence: float = 90.0) -> FishingBoatView:
	var b := FishingBoatView.new()
	add_child_autofree(b)
	b.cadence = cadence
	return b


## A state of `n` riders, the local one at x_m 5000 (no harbour, no gulls).
func _state(n: int = 1) -> FishingState:
	var st := FishingState.new()
	for i in n:
		var r := FishingRiderState.new()
		r.slot = i
		r.x_m = 5000.0
		st.riders.append(r)
	return st


func _run(
	a: FishingAudio, boats: Dictionary, st: FishingState, seconds: float, local: int = 0
) -> void:
	for i in roundi(seconds / DT):
		for slot: int in boats:
			(boats[slot] as FishingBoatView).advance(DT)
		a.update(DT, boats, st, local)


func _count(a: FishingAudio, id: String) -> int:
	return a.played.count(id)


func _fishing(b: FishingBoatView, tension: float, winch: float = 0.0) -> void:
	b.fishing = 1.0
	b.fishing_target = 1.0
	b.tension = tension
	b.winch_mps = winch


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(BANK))


# --- Moved from the view's suites -------------------------------------------------------------


func test_cues_play_their_sounds_and_other_riders_are_quieter() -> void:
	var a := _audio()
	a.cue({"k": FishingCues.CUE_CAST, "l": 0}, true)
	assert_true(a.played.has("reel_clunk") and a.played.has("cast_whip"))
	a.cue({"k": FishingCues.CUE_SNAP, "l": 1}, false)
	assert_eq(a.played[-1], "snap_twang")
	var other_db := a.kit.played_db[-1]
	a.cue({"k": FishingCues.CUE_SNAP, "l": 0}, true)
	assert_almost_eq(a.kit.played_db[-1] - other_db, -FishingAudio.OTHER_DB, 0.01)
	a.cue({"k": FishingCues.CUE_TRIP_OVER, "l": -1}, false)
	assert_eq(a.played[-1], "horn_long")
	assert_lt(FishingAudio.OTHER_DB, 0.0)
	assert_eq(float(_doc()["mix"]["other_db"]), FishingAudio.OTHER_DB, "the adapter names the bank")


func test_gulls_call_only_near_the_harbour() -> void:
	var a := _audio()
	var st := _state()
	st.riders[0].x_m = 50.0
	var b := _boat(0.0)
	_run(a, {0: b}, st, 60.0)
	assert_has(a.played, "gull", "they gather over the harbour")
	assert_gt(_count(a, "gull"), 2)
	assert_almost_eq(FishingAudio.near_dock(50.0), 0.8, 0.001)
	var far := _audio()
	var out := _state()
	_run(far, {0: _boat(0.0)}, out, 60.0)
	assert_does_not_have(far.played, "gull", "out at sea only the rare far one, its own sound")
	assert_eq(FishingAudio.near_dock(FishingAudio.GULL_RANGE_M), 0.0)


func test_audio_hums_with_cadence_screams_on_a_run_and_plays_the_fanfare() -> void:
	var a := _audio()
	var st := _state()
	var r: FishingRiderState = st.riders[0]
	var b := _boat(90.0)
	b.prop_drive = 1.0
	r.p_eff_w = 200.0
	_run(a, {0: b}, st, 0.5)
	var body := _layer_of(a.kit.machine_loop("boat0"), "outboard_body")
	assert_true(a.kit.machine_loop("boat0").on[body] != 0, "the body runs with the cadence")
	assert_almost_eq(a.kit.machine_loop("boat0").pitch[body], 1.0, 0.01, "pitch rpm / 90")
	_fishing(b, 1.0)
	r.action = FishingConst.A_FIGHT
	r.fish.run_active = true
	_run(a, {0: b}, st, 0.2)
	assert_true(a.kit.entry_loop("drag_scream").on[0] != 0, "the drag screams on a run")
	r.fish.run_active = false
	b.cadence = 0.0
	_run(a, {0: b}, st, 0.2)
	assert_true(a.kit.machine_loop("boat0").all_off(), "no cadence, no machine")
	assert_true(a.kit.entry_loop("drag_scream").all_off(), "the run is over")
	a.cue({"k": FishingCues.CUE_LANDED, "l": 0}, true)
	_run(a, {0: b}, st, 0.5)
	assert_has(a.played, "fanfare_3")
	assert_does_not_have(a.played, "fanfare_4", "the top note is a trophy's")


func test_audio_clicks_while_the_winch_brings_line_in() -> void:
	var a := _audio()
	var st := _state()
	var b := _boat(90.0)
	_fishing(b, 0.4, 3.0)
	_run(a, {0: b}, st, 1.0)
	assert_has(a.played, "reel_ratchet")
	assert_does_not_have(a.played, "gull", "no gulls out at sea")


# --- The bank ---------------------------------------------------------------------------------


func test_the_bank_validates_and_every_sound_loads_as_its_manifest_says() -> void:
	var bank := AudioBank.load_bank(BANK)
	assert_not_null(bank)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_gt(manifest.size(), 40)
	for stem: String in manifest:
		var m: Dictionary = manifest[stem]
		var s := load("res://assets/fishing/audio/%s.wav" % stem) as AudioStreamWAV
		assert_not_null(s, stem)
		assert_eq(s.mix_rate, int(m["rate"]), stem)
		assert_eq(s.stereo, int(m["ch"]) == 2, stem)
		var want := AudioStreamWAV.LOOP_FORWARD if bool(m["loop"]) else AudioStreamWAV.LOOP_DISABLED
		assert_eq(s.loop_mode, want, stem)
		var fmt := (
			AudioStreamWAV.FORMAT_QOA if m["compress"] == "qoa" else AudioStreamWAV.FORMAT_16_BITS
		)
		assert_eq(s.format, fmt, stem)


func test_every_event_maps_to_a_cue_or_is_silent() -> void:
	var cues: Dictionary = _doc()["cues"]
	var seen := 0
	for key: String in FishingEvents.INT_FIELDS:
		seen += 1
		var made := FishingCues.from_event({"type": key, "l": 0})
		if key in FishingAudio.SILENT_EVENTS:
			assert_eq(made.size(), 0, "%s has no cue, so it stays silent" % key)
			continue
		assert_eq(made.size(), 1, key)
		assert_true(cues.has(FishingAudio.cue_name(made[0])), "%s has its cue in the bank" % key)
	assert_eq(seen, 14, "every event of the contract")


func test_a_leap_is_a_splash_each_and_a_trophy_gets_its_top_note() -> void:
	var cues: Dictionary = _doc()["cues"]
	for n in [1, 2, 3]:
		var cue_id := FishingAudio.cue_name({"k": FishingCues.CUE_JUMP, "leaps": n})
		assert_eq((cues[cue_id]["hits"] as Array).size(), n + 1, "out of the water, then each fall")
		var last: Dictionary = (cues[cue_id]["hits"] as Array)[-1]
		assert_almost_eq(float(last["delay_s"]), FishingView.LEAP_S, 0.001, "the view's leap time")
	var a := _audio()
	var st := _state()
	a.cue({"k": FishingCues.CUE_LANDED, "l": 0, "grade": FishingConst.GRADE_TROPHY}, true)
	_run(a, {0: _boat(0.0)}, st, 0.8)
	assert_has(a.played, "fanfare_4")


# --- 1:1 with the crank -----------------------------------------------------------------------


## The drawn crank foot: colour 1 (crank and leg), its lowest pixel row.
func _foot_y(angle: float) -> int:
	var y := -1
	for p in FishingRig.drivetrain(angle):
		if p.z == 1:
			y = maxi(y, p.y)
	return y


func test_the_stroke_fractions_come_from_the_art() -> void:
	var low := _foot_y(0.25 * TAU)
	assert_gt(low, _foot_y(0.0), "at .25 the pedal is at the bottom of the stroke")
	assert_gt(low, _foot_y(0.5 * TAU))
	assert_gt(_foot_y(0.0), _foot_y(0.75 * TAU) - 1, "at .75 at the top")
	var pedal_0 := sin(0.0)
	var pedal_half := sin(0.5 * TAU)
	assert_almost_eq(pedal_0, pedal_half, 1e-6, "0 and .5: level, a foot starts down")
	var machine: Dictionary = _doc()["machines"]["drivetrain"]
	var at := {}
	for ev: Dictionary in machine["events"]:
		at[str(ev["sound"])] = ev["at"]
	assert_eq(at["gear_tick"], [0.0])
	assert_eq(at["crank_knock"], [0.5])
	assert_eq(at["outboard_chug"], [0.0, 0.5], "one putt for each foot's down stroke")
	assert_eq(at["line_creak"], [0.25, 0.75], "the line takes up at the dead centres")
	assert_eq((at["reel_ratchet"] as Array).size(), 6)


func test_the_strokes_read_the_number_the_crank_is_drawn_from() -> void:
	for rpm in [30.0, 60.0, 90.0, 110.0, 140.0]:
		var a := _audio()
		var st := _state()
		var b := _boat(rpm)
		b.prop_drive = 1.0
		st.riders[0].p_eff_w = 200.0
		_run(a, {0: b}, st, 20.0)
		var revs := b.crank_clock.revs
		assert_almost_eq(revs, rpm / 60.0 * 20.0, 1e-6, "%d rpm" % rpm)
		assert_almost_eq(b.crank(), fposmod(revs, 1.0) * TAU, 1e-6, "%d rpm" % rpm)
		var voice := a.kit.machine_voice("boat0")
		var to := voice.planned_to()
		assert_gte(to, revs, "the plan runs ahead of the crank by one horizon")
		assert_lt(to - revs, rpm / 60.0 * GameAudioKit.HORIZON_MAX_S + 1e-9)
		assert_eq(_count(a, "gear_tick"), floori(to), "one tick per revolution at %d rpm" % rpm)
		assert_eq(_count(a, "crank_knock"), floori(to + 0.5), "%d rpm" % rpm)
		assert_eq(
			_count(a, "outboard_chug"), floori(to) + floori(to + 0.5), "two putts at %d rpm" % rpm
		)
		assert_eq(voice.dropped, 0, "%d rpm" % rpm)


func test_a_stopped_crank_stops_the_strokes_and_closes_the_loops_at_once() -> void:
	var a := _audio()
	var st := _state()
	var b := _boat(90.0)
	b.prop_drive = 1.0
	st.riders[0].p_eff_w = 200.0
	_run(a, {0: b}, st, 3.0)
	assert_gt(_count(a, "outboard_chug"), 5)
	b.cadence = 0.0
	_run(a, {0: b}, st, GameAudioKit.HORIZON_MAX_S)
	a.kit.clear_played()
	_run(a, {0: b}, st, 0.12 - GameAudioKit.HORIZON_MAX_S)
	assert_true(a.kit.machine_loop("boat0").all_off(), "the loops within 120 ms")
	_run(a, {0: b}, st, 5.0)
	for id in ["gear_tick", "crank_knock", "outboard_chug", "outboard_body", "prop_churn"]:
		assert_does_not_have(a.played, id, "no %s after the stop" % id)
	var at := b.crank_clock.revs
	b.cadence = 90.0
	_run(a, {0: b}, st, 1.0)
	assert_almost_eq(b.crank_clock.revs - at, 1.5, 0.05, "it picks up where it stood")
	assert_lte(_count(a, "gear_tick"), 2, "with no burst")


# --- The fight --------------------------------------------------------------------------------


func test_the_clutch_swaps_the_putt_for_the_ratchet_and_a_run_silences_the_ratchet() -> void:
	var a := _audio()
	var st := _state()
	var r: FishingRiderState = st.riders[0]
	var b := _boat(90.0)
	b.prop_drive = 1.5
	_fishing(b, 0.5, 3.0)
	r.action = FishingConst.A_FIGHT
	_run(a, {0: b}, st, 4.0)
	assert_does_not_have(a.played, "outboard_chug", "the prop is off while fishing")
	assert_gt(_count(a, "reel_ratchet"), 25, "six clicks a revolution")
	assert_true(_on(a, "winch_gear"), "the winch's gears")
	assert_false(_on(a, "outboard_body"))
	r.fish.run_active = true
	_run(a, {0: b}, st, 1.0)
	a.kit.clear_played()
	_run(a, {0: b}, st, 2.0)
	assert_does_not_have(a.played, "reel_ratchet", "line going out: the drag, no clicks")


func test_the_line_creaks_and_sings_harder_as_the_tension_rises() -> void:
	var a := _audio()
	var st := _state()
	var b := _boat(90.0)
	_fishing(b, 0.2)
	_run(a, {0: b}, st, 3.0)
	assert_does_not_have(a.played, "line_creak", "a slack line is silent")
	assert_false(_on(a, "line_tension"))
	_fishing(b, 0.45)
	a.kit.clear_played()
	_run(a, {0: b}, st, 3.0)
	assert_has(a.played, "line_creak")
	var low := _loudest(a, "line_creak")
	assert_true(_on(a, "line_tension"), "the wire begins to sing")
	assert_false(_on(a, "rod_groan"))
	var wire := _layer_of(a.kit.machine_loop("boat0"), "line_tension")
	var low_pitch := a.kit.machine_loop("boat0").pitch[wire]
	var low_db := a.kit.machine_loop("boat0").db[wire]
	_fishing(b, 0.85)
	a.kit.clear_played()
	_run(a, {0: b}, st, 3.0)
	assert_gt(_loudest(a, "line_creak"), low, "the creak rises with the pull")
	assert_gt(a.kit.machine_loop("boat0").pitch[wire], low_pitch, "and the wire climbs")
	assert_gt(a.kit.machine_loop("boat0").db[wire], low_db)
	assert_true(_on(a, "rod_groan"), "the rod groans under a hard pull")


func test_another_boat_is_quieter_has_no_detail_and_fades_out_with_distance() -> void:
	var a := _audio()
	var st := _state(2)
	st.riders[1].x_m = st.riders[0].x_m + 20.0
	var me := _boat(90.0)
	var other := _boat(90.0)
	for b: FishingBoatView in [me, other]:
		_fishing(b, 0.9)
	st.riders[0].p_eff_w = 200.0
	st.riders[1].p_eff_w = 200.0
	var boats := {0: me, 1: other}
	_run(a, boats, st, 3.0)
	var mine := _layer_of(a.kit.machine_loop("boat0"), "winch_gear")
	assert_gt(
		a.kit.machine_loop("boat0").db[mine],
		a.kit.machine_loop("boat1").db[mine] - FishingAudio.OTHER_DB - 0.5,
		"another boat sits -10 dB under yours"
	)
	var wire := _layer_of(a.kit.machine_loop("boat1"), "line_tension")
	assert_eq(a.kit.machine_loop("boat1").on[wire], 0, "their line's song is yours to hear only")
	var db_near := a.kit.machine_loop("boat1").db[mine]
	st.riders[1].x_m = st.riders[0].x_m + (FishingAudio.EAR_FULL_M + FishingAudio.EAR_ZERO_M) * 0.5
	_run(a, boats, st, 1.0)
	assert_lt(a.kit.machine_loop("boat1").db[mine], db_near - 3.0, "it falls away with distance")
	st.riders[1].x_m = st.riders[0].x_m + FishingAudio.EAR_ZERO_M
	_run(a, boats, st, 0.5)
	assert_true(a.kit.machine_loop("boat1").all_off(), "out of earshot")
	var fired := a.kit.machine_voice("boat1").fired
	_run(a, boats, st, 2.0)
	assert_eq(a.kit.machine_voice("boat1").fired, fired, "no strokes either")
	st.riders[1].x_m = st.riders[0].x_m
	_run(a, boats, st, DT)
	assert_lte(a.kit.machine_voice("boat1").fired - fired, 2, "back in earshot with no burst")


# --- The sea ----------------------------------------------------------------------------------


func test_the_bed_follows_the_seed_and_the_speed_brings_the_slaps_faster() -> void:
	var one := _spots(7, 2.0)
	assert_eq(one, _spots(7, 2.0), "same seed, same sea")
	assert_ne(one, _spots(8, 2.0), "another seed, another sea")
	var slow := one.count("hull_slap")
	var fast := _spots(7, 14.0).count("hull_slap")
	assert_gt(fast, slow, "the hull hits the water more often at speed")


func _spots(p_seed: int, speed: float) -> Array[String]:
	var a := _audio(p_seed)
	var st := _state()
	st.riders[0].v_mps = speed
	_run(a, {0: _boat(0.0)}, st, 90.0)
	var out: Array[String] = []
	out.assign(a.played)
	return out


func test_the_hull_slaps_when_it_falls_once_per_fall() -> void:
	var a := _audio()
	var st := _state()
	var r: FishingRiderState = st.riders[0]
	r.v_mps = 8.0
	var b := _boat(0.0)
	a.update(DT, {0: b}, st, 0)
	a.kit.clear_played()
	for i in 30:
		r.heave_m -= 0.2 * DT
		a.update(DT, {0: b}, st, 0)
	assert_eq(_slaps(a), 1, "one slap on the edge of a 20 cm/s fall")
	for i in 60:
		a.update(DT, {0: b}, st, 0)
	a.kit.clear_played()
	r.heave_m -= 0.01
	for i in 12:
		a.update(DT, {0: b}, st, 0)
	assert_eq(_slaps(a), 0, "one 1 cm snapshot step is not a fall")
	r.v_mps = 0.5
	for i in 30:
		r.heave_m -= 0.2 * DT
		a.update(DT, {0: b}, st, 0)
	assert_eq(_slaps(a), 0, "not at rest")


## Slaps from the cue, not the bed's spots (those come at their own kit level).
func _slaps(a: FishingAudio) -> int:
	var n := 0
	var cue_db := float(_doc()["cues"]["hull_slap"]["hits"][0]["db"])
	for i in a.played.size():
		if a.played[i] == "hull_slap" and is_equal_approx(a.kit.played_db[i], cue_db):
			n += 1
	return n


func test_lifting_off_the_power_burbles_only_while_driving() -> void:
	var a := _audio()
	var st := _state()
	var r: FishingRiderState = st.riders[0]
	var b := _boat(90.0)
	b.prop_drive = 1.0
	r.p_eff_w = 250.0
	_run(a, {0: b}, st, 1.5)
	assert_does_not_have(a.played, "exhaust_burble")
	r.p_eff_w = 100.0
	_run(a, {0: b}, st, 0.1)
	assert_has(a.played, "exhaust_burble", "a 60 % lift")
	var c := _audio()
	_fishing(b, 0.3)
	r.p_eff_w = 250.0
	_run(c, {0: b}, st, 1.5)
	r.p_eff_w = 100.0
	_run(c, {0: b}, st, 0.1)
	assert_does_not_have(c.played, "exhaust_burble", "the clutch is in the winch")


# --- In the view ------------------------------------------------------------------------------


func test_the_view_drives_each_boat_with_the_local_one_leading() -> void:
	var g := FX.make_game(2)
	add_child_autofree(g)
	var v := FishingView.new()
	v.game = g
	add_child_autofree(v)
	v.advance(DT)
	assert_eq(v.audio.rng_seed, SeededRng.derive(g.ctx.seed, "fishing:audio"))
	assert_not_null(v.audio.kit.machine_voice("boat0"))
	assert_not_null(v.audio.kit.machine_voice("boat1"))
	assert_true(v.audio.kit.silent, "headless: no player, no stream, and no error")
	assert_eq(v.audio.kit.loops_in_use() > 0, true, "the bed's layers are running")


func _layer_of(loop: LayeredLoop, sound: String) -> int:
	for i in loop.count:
		if str(loop.layer(i).get("sound", "")) == sound:
			return i
	return -1


func _on(a: FishingAudio, sound: String) -> bool:
	var loop := a.kit.machine_loop("boat0")
	return loop.on[_layer_of(loop, sound)] != 0


func _loudest(a: FishingAudio, id: String) -> float:
	var top := -INF
	for i in a.played.size():
		if a.played[i] == id:
			top = maxf(top, a.kit.played_db[i])
	return top
