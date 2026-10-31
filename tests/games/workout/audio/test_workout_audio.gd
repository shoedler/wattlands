extends GutTest
## Workout's sound through its adapter, the real ride view and the real game: strokes 1:1 with the
## cranks the rider sheets draw, a dead stop, the local rider leading, what each clock drives, and no
## crowd in the warm-up (BRIEF 4.6.8). Headless: the kit records and plays nothing.

const U := preload("res://tests/games/workout/workout_test_util.gd")
const BANK := "res://assets/workout/audio/audio.json"
const MANIFEST := "res://assets/workout/audio/audio_manifest.json"


func _view(
	content: String = "easy_30",
	players: Array[PlayerSlot] = U.players(1),
	role: String = Wl.SOLO,
	local_peer: int = 1
) -> WorkoutRideView:
	var g := U.game(content, players, role, local_peer)
	autofree(g)
	var view := g.make_view() as WorkoutRideView
	add_child_autofree(view)
	view.set_process(false)
	return view


func _doc() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(BANK))
	return doc if doc is Dictionary else {}


## `seconds` of frames, with every rider at `rpm`: the view moves the cranks, the audio follows.
func _ride(view: WorkoutRideView, rpm: float, seconds: float, dt: float = 1.0 / 60.0) -> void:
	for peer: int in view.game.state.order:
		view.game.state.rider(peer).cadence_rpm = rpm
	_frames(view, seconds, dt)


func _frames(view: WorkoutRideView, seconds: float, dt: float = 1.0 / 60.0) -> void:
	for i in roundi(seconds / dt):
		view.game.sim_alive()
		view.advance(dt)


func _count(view: WorkoutRideView, sound: String) -> int:
	return view.audio.played.count(sound)


## How many k + f (k >= 0, f in `at`) lie in (0, to]: the strokes the plan has walked past.
func _in_range(at: Array, to: float) -> int:
	var n := 0
	for f: Variant in at:
		var first := 1 if float(f) <= 0.0 else 0
		for k in range(first, floori(to) + 1):
			if float(k) + float(f) <= to:
				n += 1
	return n


## A sprint after the warm-up, or -1.
func _scored_sprint(state: WorkoutState) -> int:
	for i in state.phases.size():
		if WorkoutCrowd.cheers_for(state, i):
			return i
	return -1


## Puts the ride inside phase `i` and walks the viewer until the crowd reaches it.
func _into_sprint(view: WorkoutRideView, i: int, rpm: float = 90.0) -> void:
	var g := view.game
	g.state.phase_index = i
	g.state.plan_t = g.state.phase_start_s(i) + 1.0
	var r := g.state.rider(1)
	r.power_w = r.ftp * 1.3
	r.cadence_rpm = rpm
	for f in 60 * 8:
		r.speed.v_mps = 12.0
		r.speed.distance_m += 12.0 / 60.0
		g.sim_alive()
		view.advance(1.0 / 60.0)


# --- the bank -------------------------------------------------------------------------


func test_the_bank_loads_and_validates() -> void:
	assert_eq(AudioBank.validate(_doc()), [] as Array[String])
	assert_not_null(AudioBank.load_bank(BANK))


func test_every_file_loads_with_its_manifests_format_and_loop_mode() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(manifest is Dictionary)
	var doc := _doc()
	var files := 0
	for id: String in doc["sounds"]:
		var sound: Dictionary = doc["sounds"][id]
		var n := int(sound.get("variants", 1))
		for v in n:
			var stem := "%s_%d" % [id, v + 1] if n > 1 else id
			var entry: Dictionary = manifest[stem]
			var wav := load("res://assets/workout/audio/%s.wav" % stem) as AudioStreamWAV
			assert_not_null(wav, stem)
			if wav == null:
				continue
			files += 1
			var format := (
				AudioStreamWAV.FORMAT_QOA
				if str(entry["compress"]) == "qoa"
				else AudioStreamWAV.FORMAT_16_BITS
			)
			assert_eq(wav.format, format, stem)
			var mode := (
				AudioStreamWAV.LOOP_FORWARD if bool(entry["loop"]) else AudioStreamWAV.LOOP_DISABLED
			)
			assert_eq(wav.loop_mode, mode, stem)
			assert_eq(wav.mix_rate, int(entry["rate"]), stem)
			assert_eq(wav.stereo, int(entry["ch"]) == 2, stem)
	assert_gt(files, 30, "the whole bank")


func test_every_event_constant_maps_to_a_cue_or_is_listed_silent() -> void:
	var cues: Dictionary = _doc()["cues"]
	var constants: Dictionary = WorkoutRules.new().get_script().get_script_constant_map()
	var seen := 0
	for key: String in constants:
		if not key.begins_with("EV_"):
			continue
		seen += 1
		var name_of := str(constants[key])
		assert_true(
			cues.has(name_of) or WorkoutAudio.SILENT_EVENTS.has(name_of), "%s has a sound" % name_of
		)
	assert_eq(seen, 3, "interval_start, interval_end, sprint")


func test_fractions_come_from_the_rider_sheet() -> void:
	var kit := WorkoutKit.shared()
	var pedal: Array = kit.rider["near_pedal"]
	var xs: Array[int] = []
	var ys: Array[int] = []
	for p: Array in pedal:
		xs.append(int(p[0]))
		ys.append(int(p[1]))
	var events: Array = _doc()["machines"]["bike"]["events"]
	var at_of := {}
	for e: Dictionary in events:
		at_of[e["sound"]] = e["at"]
	# The press sounds where the foot pushes hardest: the pedal furthest forward, near then far.
	assert_eq(xs[WorkoutRig.crank_frame(float(at_of["pedal_press"][0]))], xs.max())
	assert_eq(xs[WorkoutRig.crank_frame(float(at_of["pedal_press"][1]))], xs.min())
	# The chain ticks through the dead spot: the near pedal on top.
	assert_eq(ys[WorkoutRig.crank_frame(float(at_of["chain_tick"][0]))], ys.min())


# --- 1:1 with the cranks --------------------------------------------------------------


func test_one_stroke_per_revolution_across_cadence_and_frame_rates() -> void:
	for rpm: float in [30.0, 45.0, 60.0, 90.0, 110.0, 125.0, 140.0]:
		for dt: float in [1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0]:
			var view := _view()
			_ride(view, rpm, 20.0, dt)
			var to := view.audio.kit.machine_voice("bike1").planned_to()
			var label := "%d rpm at %d fps" % [rpm, roundi(1.0 / dt)]
			assert_eq(_count(view, "chain_tick"), _in_range([0.0], to), label)
			assert_eq(_count(view, "pedal_press"), _in_range([0.25, 0.75], to), label)
			view.free()


func test_the_audio_reads_the_one_number_the_legs_are_drawn_from() -> void:
	var view := _view()
	_ride(view, 90.0, 7.0)
	var revs := view.game.cranks.revs(1)
	var to := view.audio.kit.machine_voice("bike1").planned_to()
	assert_almost_eq(revs, 10.5, 1e-6)
	assert_almost_eq(view.audio.kit._t, 7.0, 1e-6, "commit once a frame")
	assert_between(to - revs, 0.0, 1.5 * 0.05, "the plan is at most one horizon ahead")
	var kit := view.audio.kit
	var tick := 0
	for i in kit.played.size():
		if kit.played[i] == "chain_tick":
			tick += 1
			assert_almost_eq(kit.played_t[i], float(tick) * 60.0 / 90.0, 1e-6, "on revolution k")
	assert_gt(tick, 9)


func test_a_ramp_stays_exact() -> void:
	var view := _view()
	for f in 60 * 40:
		var rpm := 30.0 + 110.0 * sin(float(f) / (60.0 * 40.0) * PI)
		view.game.state.rider(1).cadence_rpm = rpm
		view.game.sim_alive()
		view.advance(1.0 / 60.0)
	var to := view.audio.kit.machine_voice("bike1").planned_to()
	assert_eq(_count(view, "chain_tick"), _in_range([0.0], to))
	assert_eq(_count(view, "pedal_press"), _in_range([0.25, 0.75], to))


func test_a_dead_stop_ends_strokes_and_loops() -> void:
	var view := _view()
	_ride(view, 90.0, 5.0)
	var kit := view.audio.kit
	assert_eq(kit.machine_loop("bike1").on[0], 1, "the chain runs")
	var before := kit.played.size()
	_ride(view, 0.0, 0.12)
	assert_eq(kit.machine_loop("bike1").on[0], 0, "off within 120 ms")
	assert_eq(kit.machine_loop("bike1").on[1], 0)
	_ride(view, 0.0, 3.0)
	var strokes := 0
	for i in range(before, kit.played.size()):
		if kit.played[i] == "chain_tick" or kit.played[i] == "pedal_press":
			strokes += 1
	assert_eq(strokes, 0, "nothing starts: the horizon's stroke, if any, began before the stop")


func test_a_restart_has_no_burst_and_no_duplicate() -> void:
	var view := _view()
	_ride(view, 90.0, 5.0)
	_ride(view, 0.0, 5.0)
	_ride(view, 90.0, 5.0)
	var to := view.audio.kit.machine_voice("bike1").planned_to()
	assert_eq(_count(view, "chain_tick"), _in_range([0.0], to), "the whole axis, once")


func test_a_quiet_sim_stops_every_clock() -> void:
	var view := _view()
	view.game.state.rider(1).speed.v_mps = 9.0
	_ride(view, 90.0, 2.0)
	var kit := view.audio.kit
	assert_false(kit.entry_loop("tyre_hum").all_off(), "the tyres run")
	assert_false(kit.entry_loop("wind_rush").all_off(), "the wind blows")
	var ticks := _count(view, "chain_tick")
	for f in 60:
		view.advance(1.0 / 60.0)  # no sim_alive(): the session is paused or over
	assert_true(kit.entry_loop("tyre_hum").all_off(), "the state's last speed is not a road")
	assert_true(kit.entry_loop("wind_rush").all_off())
	assert_lte(_count(view, "chain_tick") - ticks, 1, "legs stopped with the sim")


func test_a_pause_makes_no_strokes_and_resumes_without_a_burst() -> void:
	var view := _view()
	var bus := get_node("/root/EventBus")
	_ride(view, 90.0, 2.0)
	bus.paused_changed.emit(true, "test")
	var ticks := _count(view, "chain_tick")
	_ride(view, 90.0, 5.0)
	assert_eq(_count(view, "chain_tick"), ticks, "a crank under the mute")
	bus.paused_changed.emit(false, "test")
	view.game.sim_alive()
	view.advance(1.0 / 60.0)
	assert_lte(_count(view, "chain_tick") - ticks, 1, "no burst")


# --- the group ------------------------------------------------------------------------


func test_others_get_the_tick_and_a_quiet_whirr_and_nothing_else() -> void:
	var view := _view("easy_30", U.players(2))
	var g := view.game
	g.state.rider(1).cadence_rpm = 0.0
	g.state.rider(2).cadence_rpm = 90.0
	g.state.rider(2).power_w = g.state.rider(2).ftp * 1.3
	g.state.rider(1).power_w = 0.0
	_frames(view, 6.0)
	assert_gt(_count(view, "chain_tick"), 6)
	assert_eq(_count(view, "pedal_press"), 0, "no press from another rider")
	assert_eq(_count(view, "bb_creak"), 0)
	var kit := view.audio.kit
	assert_eq(kit.machine_loop("bike2").on[0], 1, "the whirr")
	assert_eq(kit.machine_loop("bike2").on[1], 0, "the rattle is the rider's own")


func test_the_local_rider_leads() -> void:
	var dbs: Array[float] = []
	for moving: int in [1, 2]:
		var view := _view("easy_30", U.players(2))
		var g := view.game
		g.state.rider(1).cadence_rpm = 90.0 if moving == 1 else 0.0
		g.state.rider(2).cadence_rpm = 90.0 if moving == 2 else 0.0
		g.state.rider(1).power_w = 200.0
		g.state.rider(2).power_w = 200.0
		_frames(view, 3.0)
		var kit := view.audio.kit
		dbs.append(kit.played_db[kit.played.find("chain_tick")])
		var hum := kit.machine_loop("bike%d" % moving).db[0]
		dbs.append(hum)
		view.free()
	assert_gt(dbs[0], dbs[2] + 5.0, "lead's tick over another's, the same power")
	assert_gt(dbs[1], dbs[3] + 5.0, "lead's whirr over another's")


func test_eight_riders_stay_in_their_pools() -> void:
	var view := _view("easy_30", U.players(1, 7))
	var g := view.game
	var order := g.state.order
	for i in order.size():
		g.state.rider(order[i]).cadence_rpm = 88.0 + 24.0 * float(i) / 7.0
		g.state.rider(order[i]).power_w = 180.0
	var kit := view.audio.kit
	var peak := 0
	for f in 60 * 20:
		g.sim_alive()
		view.advance(1.0 / 60.0)
		peak = maxi(peak, kit.loops_in_use())
	assert_lte(peak, 24, "loop players")
	assert_gt(peak, 8, "the group's whirr does run")
	var to := kit.machine_voice("bike1").planned_to()
	var lead := _in_range([0.0, 0.25, 0.75], to)
	var others := kit.played.size() - lead
	assert_lte(
		float(others) / 20.0, 1.0 / 0.06 + 2.0, "other strokes per second, loops and bed added"
	)


func test_a_spectator_has_no_lead_and_no_rider_of_its_own() -> void:
	var view := _view("easy_30", U.players(2), Wl.CLIENT, 99)
	_ride(view, 90.0, 2.0)
	var kit := view.audio.kit
	assert_null(kit.machine_voice("wheel"))
	assert_null(kit.machine_voice("crowd"))
	assert_not_null(kit.machine_voice("bike1"))
	assert_gt(_count(view, "chain_tick"), 0)
	assert_eq(_count(view, "pedal_press"), 0)


func test_a_client_hears_its_own_cadence_not_a_snapshots() -> void:
	var view := _view("easy_30", U.players(2), Wl.CLIENT, 2)
	var g := view.game
	g.state.rider(2).cadence_rpm = 30.0
	g.local_rpm = 90.0
	_frames(view, 4.0)
	assert_almost_eq(g.cranks.revs(2), 6.0, 1e-6)
	var to := view.audio.kit.machine_voice("bike2").planned_to()
	assert_eq(_count(view, "pedal_press"), _in_range([0.25, 0.75], to))


# --- what the speed clock drives ------------------------------------------------------


func test_the_freewheel_ticks_only_on_a_real_coast() -> void:
	var view := _view()
	var g := view.game
	var r := g.state.rider(1)
	var run := func(rpm: float, mps: float, seconds: float) -> int:
		var before := _count(view, "freewheel_tick")
		r.cadence_rpm = rpm
		for f in roundi(seconds * 60.0):
			r.speed.v_mps = mps
			r.speed.distance_m += mps / 60.0
			g.sim_alive()
			view.advance(1.0 / 60.0)
		return _count(view, "freewheel_tick") - before
	assert_eq(run.call(90.0, 9.0, 3.0), 0, "pedalling")
	var coasting: int = run.call(0.0, 7.0, 3.5)
	assert_almost_eq(float(coasting), 7.0 * 3.5 / WorkoutAudio.TICK_M, 2.0, "by the metre")
	assert_eq(run.call(0.0, 1.0, 3.0), 0, "under walking pace")
	assert_eq(run.call(5.0, 0.0, 3.0), 0, "stopped")


func test_tyres_and_wind_follow_speed_and_stop_with_the_road() -> void:
	var view := _view()
	var g := view.game
	var r := g.state.rider(1)
	r.speed.v_mps = 5.0
	_ride(view, 90.0, 2.0)
	var kit := view.audio.kit
	var slow_hum := kit.entry_loop("tyre_hum").db[0]
	var slow_pitch := kit.entry_loop("tyre_hum").pitch[0]
	var slow_wind := kit.entry_loop("wind_rush").db[0]
	r.speed.v_mps = 13.0
	_ride(view, 90.0, 3.0)
	assert_gt(kit.entry_loop("tyre_hum").db[0], slow_hum + 2.0)
	assert_gt(kit.entry_loop("tyre_hum").pitch[0], slow_pitch * 1.8)
	assert_gt(kit.entry_loop("wind_rush").db[0], slow_wind + 5.0)
	r.speed.v_mps = 0.0
	_ride(view, 90.0, 0.2)
	assert_true(kit.entry_loop("tyre_hum").all_off(), "no road, no hum, legs or no legs")
	assert_true(kit.entry_loop("wind_rush").all_off())
	assert_eq(kit.machine_loop("bike1").on[0], 1, "the chain does not care")


# --- the gears ------------------------------------------------------------------------


func test_a_gear_change_clicks_by_direction_and_the_chain_crosses_a_quarter_rev_later() -> void:
	var view := _view()
	var g := view.game
	g.local_tm = Telemetry.new()
	g.local_tm.gear = 12
	_ride(view, 90.0, 0.5)
	assert_eq(_count(view, "gear_click_up") + _count(view, "gear_click_down"), 0, "first reading")
	g.local_tm.gear = 13
	_frames(view, 1.0 / 60.0)
	assert_eq(_count(view, "gear_click_up"), 1)
	assert_eq(_count(view, "chain_shift"), 0, "not yet")
	_frames(view, 0.25 * 60.0 / 90.0)
	assert_eq(_count(view, "chain_shift"), 1, "a quarter of a revolution on")
	g.local_tm.gear = 11
	_frames(view, 1.0 / 60.0)
	assert_eq(_count(view, "gear_click_down"), 1)


func test_a_shift_with_still_legs_clicks_and_the_chain_stays() -> void:
	var view := _view()
	var g := view.game
	g.local_tm = Telemetry.new()
	g.local_tm.gear = 12
	_ride(view, 5.0, 0.2)
	g.local_tm.gear = 14
	_ride(view, 5.0, 4.0)
	assert_eq(_count(view, "gear_click_up"), 1, "the lever moves")
	assert_eq(_count(view, "chain_shift"), 0, "the chain does not")


# --- the breath -----------------------------------------------------------------------


func test_breath_comes_every_second_revolution_on_a_hard_effort_only() -> void:
	var view := _view()
	var r := view.game.state.rider(1)
	r.power_w = r.ftp * 0.8
	_ride(view, 90.0, 6.0)
	assert_eq(_count(view, "breath"), 0, "not at 80 % FTP")
	r.power_w = r.ftp * 1.2
	_ride(view, 90.0, 12.0)
	var to := view.audio.kit.machine_voice("breath").planned_to()
	assert_eq(_count(view, "breath"), floori(to) - floori(9.0 / 2.0), "with the view's own rule")
	_ride(view, 0.0, 3.0)
	var after := _count(view, "breath")
	_ride(view, 0.0, 3.0)
	assert_eq(_count(view, "breath"), after, "stops dead with the legs")


# --- the crowd ------------------------------------------------------------------------


func test_the_crowd_beats_time_on_the_hands_the_view_draws() -> void:
	var view := _view()
	var g := view.game
	var r := g.state.rider(1)
	var machine: Dictionary = _doc()["machines"]["crowd"]
	var at_of := {}
	for e: Dictionary in machine["events"]:
		at_of[e["sound"]] = float(e["at"][0])
	var clap: float = at_of["crowd_clap"]
	var bell: float = at_of["cowbell"]
	# Hands drop on the clap and rise on the bell.
	for k in 4:
		g.cranks.clear()
		g.cranks.step(1, 60.0, float(k) + clap + 0.01)
		assert_false(view.hands_up(r), "down just after the clap")
		g.cranks.clear()
		g.cranks.step(1, 60.0, float(k) + 1.0 + clap - 0.01)
		assert_true(view.hands_up(r), "up just before the next clap")
		g.cranks.clear()
		g.cranks.step(1, 60.0, float(k) + bell + 0.01)
		assert_true(view.hands_up(r), "up just after the bell")


func test_a_scored_sprint_has_a_crowd_you_hear_as_far_as_you_see_it() -> void:
	var view := _view()
	var g := view.game
	var i := _scored_sprint(g.state)
	assert_gte(i, 0, "easy_30 has a scored sprint")
	assert_eq(view.audio.crowd_near(), 0.0, "no crowd yet")
	_into_sprint(view, i)
	assert_true(view.crowd_layer.active())
	assert_gt(view.audio.crowd_near(), 0.5, "among them")
	var kit := view.audio.kit
	assert_false(kit.entry_loop("crowd_loop").all_off())
	var claps := _count(view, "crowd_clap")
	assert_gt(claps, 3, "they clap")
	assert_gt(_count(view, "cowbell"), 0, "the bell")
	var rate := 90.0 / 60.0
	var before := _count(view, "crowd_clap")
	var r := g.state.rider(1)
	for f in 120:
		r.speed.distance_m += 12.0 / 60.0
		g.sim_alive()
		view.advance(1.0 / 60.0)
	assert_almost_eq(
		float(_count(view, "crowd_clap") - before), rate * 2.0, 1.0, "one per revolution"
	)
	before = _count(view, "crowd_clap")
	_ride(view, 0.0, 2.0)
	assert_lte(_count(view, "crowd_clap") - before, 1, "the rider stops, the hands stop")


func test_the_crowd_fades_with_the_screen_edge() -> void:
	var view := _view()
	var g := view.game
	g.state.plan_t = 0.0
	var at := func(w0: float, w1: float, distance: float) -> float:
		g.state.rider(1).speed.distance_m = distance
		view.crowd_layer.windows = [{"w0": w0, "w1": w1, "open": false, "i": 0}]
		return view.audio.crowd_near()
	var world := 100.0 * WorkoutRideView.VISUAL_PX_PER_M
	var me := world + WorkoutRideView.RIDER_X
	var ahead := float(WorkoutArt.W) - WorkoutRideView.RIDER_X
	assert_almost_eq(at.call(me + ahead, me + ahead + 500.0, 100.0), 0.0, 1e-6, "at the right edge")
	assert_almost_eq(at.call(me + ahead / 2.0, me + 2000.0, 100.0), 0.5, 1e-6, "halfway")
	assert_almost_eq(at.call(me - 100.0, me + 100.0, 100.0), 1.0, 1e-6, "among them")
	var behind := WorkoutRideView.RIDER_X
	assert_almost_eq(at.call(me - 900.0, me - behind, 100.0), 0.0, 1e-6, "at the left edge")
	view.crowd_layer.windows = []
	assert_eq(view.audio.crowd_near(), 0.0)


func test_a_warmup_sprint_gets_no_crowd_and_no_cheer() -> void:
	var view := _view("e2e")
	var g := view.game
	var i := g.state.phases.size() - 1
	for k in g.state.phases.size():
		if WorkoutSession.is_sprint(g.state.phase(k)):
			i = k
	assert_true(WorkoutSession.is_sprint(g.state.phase(i)), "e2e's sprint")
	assert_false(WorkoutCrowd.cheers_for(g.state, i), "it is in the warm-up")
	_into_sprint(view, i)
	assert_eq(view.audio.crowd_near(), 0.0)
	assert_eq(_count(view, "crowd_clap"), 0)
	assert_eq(_count(view, "crowd_loop"), 0)
	assert_eq(_count(view, "cowbell"), 0)
	g.cue.emit(
		WorkoutRules.EV_SPRINT, {"type": WorkoutRules.EV_SPRINT, "i": i, "r": [[1, 300, 50, 1]]}
	)
	_frames(view, 1.5)
	assert_eq(_count(view, "crowd_cheer"), 0, "BRIEF 4.6.8")


# --- events ---------------------------------------------------------------------------


func test_events_sound_in_order_the_chime_then_the_bell() -> void:
	var view := _view()
	var g := view.game
	g.cue.emit(WorkoutRules.EV_INTERVAL_END, {"i": 0, "r": []})
	g.cue.emit(WorkoutRules.EV_INTERVAL_START, {"i": 1})
	var kit := view.audio.kit
	assert_eq(_count(view, "interval_chime"), 1, "at once")
	assert_eq(_count(view, "interval_bell"), 0, "a beat later")
	_frames(view, 0.6)
	assert_eq(_count(view, "interval_bell"), 1)
	assert_gt(kit.played.find("interval_bell"), kit.played.find("interval_chime"))


func test_the_cheer_takes_the_riders_own_sprint() -> void:
	var dbs: Array[float] = []
	for hit: int in [1, 0]:
		var view := _view()
		var g := view.game
		var i := _scored_sprint(g.state)
		g.cue.emit(
			WorkoutRules.EV_SPRINT,
			{"type": WorkoutRules.EV_SPRINT, "i": i, "r": [[1, 300, 50, hit], [2, 900, 200, 1]]}
		)
		var kit := view.audio.kit
		dbs.append(kit.played_db[kit.played.find("crowd_cheer")])
		view.free()
	assert_almost_eq(dbs[0] - dbs[1], WorkoutAudio.HIT_DB - WorkoutAudio.MISS_DB, 1e-3)


func test_a_real_ride_sounds_through_the_games_cue_signal() -> void:
	var view := _view("e2e")
	U.ride(view.game, Callable(), 1300)
	_frames(view, 0.6)
	assert_gt(_count(view, "interval_chime"), 0, "phase ends")
	assert_gt(_count(view, "interval_bell"), 0, "phase starts")


func test_a_client_sounds_events_as_they_arrive() -> void:
	var view := _view("easy_30", U.players(2), Wl.CLIENT, 2)
	view.game.apply_event({"type": WorkoutRules.EV_INTERVAL_END, "i": 0, "r": []})
	assert_eq(_count(view, "interval_chime"), 1)


# --- the road side --------------------------------------------------------------------


func test_the_bed_runs_and_its_birds_follow_the_morning() -> void:
	var view := _view()
	var g := view.game
	var kit := view.audio.kit
	assert_not_null(kit.current_bed(), "dawn_road from the first frame")
	var layers: Array = _doc()["beds"]["dawn_road"]["layers"]
	var dawn := -1
	var day := -1
	for i in layers.size():
		if layers[i]["sound"] == "birds_dawn":
			dawn = i
		if layers[i]["sound"] == "birds_day":
			day = i
	g.state.plan_t = 0.0
	_frames(view, 1.0)
	var loops := kit.current_bed().loops
	assert_gt(loops.db[dawn], -40.0, "the dawn chorus")
	assert_eq(loops.on[day], 0, "no day birds at dawn")
	g.state.plan_t = g.state.total_s()
	_frames(view, 1.0)
	assert_eq(loops.on[dawn], 0, "the chorus is over")
	assert_gt(loops.db[day], -40.0)


func test_the_breeze_you_hear_is_the_breeze_that_moves_the_grass() -> void:
	var view := _view()
	for f in 40:
		var was := view._grass_frames
		view.game.sim_alive()
		view.advance(0.5)
		var rate := (view._grass_frames - was) / 0.5
		var gust := WorkoutAudio.gust_at(view.env_t)
		assert_almost_eq(rate, 2.0 + 4.0 * gust, 1e-6, "the view's own formula")


func test_a_tractor_is_heard_only_while_one_crosses_the_screen() -> void:
	var view := _view()
	var g := view.game
	var spots := WorkoutSpots.build(g.ctx.seed, g.state.total_s())
	var crossing := false
	for s: Dictionary in spots:
		if str(s["kind"]) == "tractor":
			g.state.plan_t = float(s["t0"]) + 1.0
			assert_true(view.audio._tractor_crossing(g), "while it crosses")
			crossing = true
			break
	assert_true(crossing, "this seed has a tractor")
	g.state.plan_t = 0.0
	assert_false(view.audio._tractor_crossing(g), "before any")


# --- platform rules -------------------------------------------------------------------


func test_headless_it_is_silent_and_keeps_its_records() -> void:
	var view := _view()
	_ride(view, 90.0, 1.0)
	var kit := view.audio.kit
	assert_true(kit.silent)
	assert_eq(kit.get_child_count(), 0, "no player was created")
	assert_gt(view.audio.played.size(), 0)
	assert_eq(view.audio.played, kit.played)


func test_with_real_players_every_voice_starts_and_none_goes_missing() -> void:
	var view := _view("easy_30", U.players(1, 3))
	var g := view.game
	var kit := view.audio.kit
	kit.force_audio = true
	assert_true(kit.setup(WorkoutAudio.BANK_PATH, 1))
	kit.set_bed(WorkoutAudio.BED)
	assert_false(kit.silent)
	g.local_tm = Telemetry.new()
	g.local_tm.gear = 12
	g.local_tm.power_w = g.state.rider(1).ftp * 1.3
	var me := g.state.rider(1)
	me.speed.v_mps = 12.0
	var x := WorkoutRideView.RIDER_X
	view.crowd_layer.windows = [{"w0": x - 500.0, "w1": x + 500.0, "open": false, "i": 99}]
	_ride(view, 90.0, 0.2)
	g.local_tm.gear = 13
	g.cue.emit(WorkoutRules.EV_INTERVAL_END, {"i": 0, "r": []})
	g.cue.emit(WorkoutRules.EV_INTERVAL_START, {"i": 1})
	# Frames outrun the clock here, so voices never end: a short ride stays inside the pools.
	view.crowd_layer.windows = [{"w0": x - 500.0, "w1": x + 500.0, "open": false, "i": 99}]
	_frames(view, 1.3)
	assert_gt(kit.get_child_count(), 5, "players ran")
	assert_true(kit.played.has("crowd_clap"), "the crowd machine played")
	assert_true(kit.played.has("interval_bell"), "the delayed hit started")
	assert_eq(kit.voiceless, 0, "every stroke and event found a voice")
	assert_gt(kit.loops_in_use(), 3)
	kit.stop_all()


func test_it_never_touches_the_games_rng_or_state() -> void:
	var view := _view()
	var g := view.game
	var rng_state := g.ctx.rng.state
	var snap_before := JSON.stringify(WorkoutSnapshot.encode(g.state, true, 0))
	view.audio.update(1.0 / 60.0)
	view.audio.update(1.0 / 60.0)
	assert_eq(g.ctx.rng.state, rng_state)
	assert_eq(JSON.stringify(WorkoutSnapshot.encode(g.state, true, 0)), snap_before)
	assert_eq(g.cranks.revs(1), 0.0, "only the view's advance moves the cranks")


func test_a_rider_leaving_the_session_closes_its_machine() -> void:
	var view := _view("easy_30", U.players(2))
	var g := view.game
	_ride(view, 90.0, 2.0)
	var kit := view.audio.kit
	assert_eq(kit.machine_loop("bike2").on[0], 1)
	g.state.rider(2).connected = false
	_ride(view, 90.0, 0.2)
	assert_eq(kit.machine_loop("bike2").on[0], 0, "a dropped rider's legs stop")
