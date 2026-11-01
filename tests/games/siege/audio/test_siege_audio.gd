extends GutTest
## SiegeAudio: every event reaches a cue, the wheels' strokes run 1:1 with the crank the walkers are
## drawn with, the loops follow the state, and all of it stays silent and error-free headless.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FIX := preload("res://tests/games/siege/fixtures/siege_fixtures.gd")
const FRAME := 1.0 / 60.0

var _games: Array[SiegeGame] = []


func after_each() -> void:
	for g in _games:
		F.free_game(g)
	_games.clear()


func _game(state: SiegeState, humans: int = 1, bots: int = 0) -> SiegeGame:
	var g := F.make_game(F.make_ctx(humans, bots, "short", Wl.SOLO, 1))
	g.state = state
	g.content = state.content
	_games.append(g)
	return g


func _view(state: SiegeState, humans: int = 1, bots: int = 0) -> SiegeView:
	var v := _game(state, humans, bots).make_view() as SiegeView
	add_child_autofree(v)
	return v


## One rider on a bare state, at `rpm`, nothing else moving.
func _solo(rpm: float, p_eff: float = 250.0) -> SiegeView:
	var st := SiegeKit.state("short", 1, 0)
	var r := st.rider_at(0)
	r.cadence_rpm = rpm
	r.p_eff_w = p_eff
	return _view(st)


func _run(v: SiegeView, seconds: float, dt: float = FRAME) -> void:
	for _i in roundi(seconds / dt):
		v.update(dt)


func _count(v: SiegeView, sound: String) -> int:
	return v.audio.played.count(sound)


func _db_of(v: SiegeView, sound: String) -> Array[float]:
	var out: Array[float] = []
	for i in v.audio.kit.played.size():
		if v.audio.kit.played[i] == sound:
			out.append(v.audio.kit.played_db[i])
	return out


## k + f in (0, to].
func _pattern(fractions: Array, to: float) -> int:
	var n := 0
	for f: float in fractions:
		n += floori(to - f) + (1 if f > 0.0 else 0)
	return n


func _shot(kind: int, tk: int = 1, sd: int = 77) -> Dictionary:
	var o: Array[int] = [8000, 12000, 1500]
	var v: Array[int] = [12000, 15000, 9000]
	return SiegeEvents.shot(tk, 1, kind, o, v, 12 if kind == SiegeIds.SHOT_ARROW else 1, sd)


# --- The bank ---------------------------------------------------------------------------------


func test_the_bank_loads_and_validates() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(SiegeAudio.BANK_PATH))
	assert_true(doc is Dictionary)
	assert_eq(AudioBank.validate(doc), [] as Array[String])
	assert_not_null(AudioBank.load_bank(SiegeAudio.BANK_PATH))


func test_every_file_is_imported_as_the_recipe_asks() -> void:
	var bank := AudioBank.load_bank(SiegeAudio.BANK_PATH)
	for id: String in bank.sounds:
		var recipe: Dictionary = bank.sounds[id]
		for k in bank.variants(id):
			var s := bank.stream(id, k) as AudioStreamWAV
			assert_not_null(s, "%s variant %d" % [id, k])
			if s == null:
				continue
			assert_eq(s.mix_rate, int(recipe["rate"]), id)
			assert_eq(s.stereo, int(recipe["ch"]) == 2, id)
			var looped := bool(recipe.get("loop", false))
			var mode := AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
			assert_eq(s.loop_mode, mode, id)
			if bool(recipe.get("locked", false)):
				assert_eq(s.format, AudioStreamWAV.FORMAT_16_BITS, "%s stays PCM for its seek" % id)


func test_every_event_maps_to_a_cue_of_the_bank() -> void:
	var bank := AudioBank.load_bank(SiegeAudio.BANK_PATH)
	for kind: String in SiegeIds.EVENT_TYPES:
		if SiegeAudio.SILENT_EVENTS.has(kind):
			continue
		var name := SiegeAudio.cue_for(kind, {"on": 1, "ok": 1, "st": SiegeIds.OD_EV_START})
		assert_true(bank.cues.has(name), "%s -> cue %s" % [kind, name])
	for shot in [
		SiegeIds.SHOT_BOLT, SiegeIds.SHOT_STONE, SiegeIds.SHOT_ARROW, SiegeIds.SHOT_SCORPION
	]:
		var name := SiegeAudio.cue_for(SiegeIds.EV_SHOT, {"kind": shot})
		assert_true(bank.cues.has(name), name)
	for st in [SiegeIds.OD_EV_START, SiegeIds.OD_EV_END, SiegeIds.OD_EV_REFUSED]:
		var name := SiegeAudio.cue_for(SiegeIds.EV_OVERDRIVE, {"st": st})
		assert_true(bank.cues.has(name), name)
	for name: String in [
		SiegeAudio.CUE_GATE_HIT,
		SiegeAudio.CUE_HOOVES,
		SiegeAudio.CUE_RAM,
		SiegeAudio.CUE_GOLD,
		SiegeAudio.CUE_TAR_HISS,
	]:
		assert_true(bank.cues.has(name), name)


func test_silent_variants_of_an_event_say_so() -> void:
	assert_eq(SiegeAudio.cue_for(SiegeIds.EV_RUSH, {"on": 0}), "")
	assert_eq(SiegeAudio.cue_for(SiegeIds.EV_BUY, {"ok": 0}), "")


func test_headless_makes_no_players_and_still_records() -> void:
	var v := _solo(90.0)
	assert_true(v.audio.silent)
	_run(v, 1.0)
	assert_gt(v.audio.played.size(), 0)
	var players := v.audio.find_children("*", "AudioStreamPlayer", true, false)
	assert_eq(players.size(), 0)


# --- 1:1 with cadence -------------------------------------------------------------------------


func test_strokes_are_exact_across_the_cadence_range() -> void:
	for rpm: float in [30.0, 60.0, 90.0, 110.0, 140.0]:
		var v := _solo(rpm)
		_run(v, 8.0)
		var voice: CadenceVoice = v.audio.kit.machine_voice("wheel0")
		var to := voice.planned_to()
		assert_almost_eq(v.cranks[0].revs, rpm / 60.0 * 8.0, 0.01, "%d rpm" % rpm)
		assert_eq(_count(v, "pawl_click"), _pattern([0.0, 0.5], to), "pawl at %d rpm" % rpm)
		assert_eq(_count(v, "tread_step"), _pattern([0.0, 0.5], to), "step at %d rpm" % rpm)
		assert_eq(_count(v, "axle_knock"), _pattern([0.75], to), "knock at %d rpm" % rpm)
		assert_eq(voice.dropped, 0, "%d rpm" % rpm)


func test_the_walkers_and_the_strokes_read_one_crank() -> void:
	var v := _solo(90.0)
	_run(v, 3.0)
	assert_almost_eq(float(v.walk_phase[0]), v.cranks[0].revs, 1e-3)
	assert_almost_eq(float(v.machines.walk_phase[0]), v.cranks[0].revs, 1e-3)
	assert_eq(_count(v, "tread_step"), _count(v, "pawl_click"))


func test_a_frame_rate_change_does_not_change_the_count() -> void:
	var a := _solo(100.0)
	var b := _solo(100.0)
	_run(a, 6.0, 1.0 / 144.0)
	_run(b, 6.0, 1.0 / 30.0)
	var to_a: float = a.audio.kit.machine_voice("wheel0").planned_to()
	var to_b: float = b.audio.kit.machine_voice("wheel0").planned_to()
	assert_eq(_count(a, "pawl_click"), _pattern([0.0, 0.5], to_a))
	assert_eq(_count(b, "pawl_click"), _pattern([0.0, 0.5], to_b))


func test_cadence_zero_stops_the_wheel_dead_and_restarts_with_no_burst() -> void:
	var v := _solo(90.0)
	_run(v, 2.0)
	v.state.rider_at(0).cadence_rpm = 0.0
	v.update(FRAME)
	var after_stop := _count(v, "pawl_click")
	var revs := v.cranks[0].revs
	_run(v, 0.12)
	var loop: LayeredLoop = v.audio.kit.machine_loop("wheel0")
	assert_true(loop.db[0] <= LayeredLoop.OFF_DB, "the rumble is shut within 120 ms")
	_run(v, 2.0)
	assert_eq(_count(v, "pawl_click"), after_stop, "no stroke after the stop")
	assert_eq(v.cranks[0].revs, revs, "the crank stands still")
	v.state.rider_at(0).cadence_rpm = 60.0
	v.update(FRAME)
	v.update(FRAME)
	assert_true(_count(v, "pawl_click") <= after_stop + 1, "no burst on the restart")


func test_the_wheel_still_turns_by_watts_while_the_legs_follow_cadence() -> void:
	var v := _solo(0.0, 300.0)
	var was := v.wheel_deg[0]
	_run(v, 1.0)
	assert_ne(v.wheel_deg[0], was, "the wheel is load")
	assert_eq(v.cranks[0].revs, 0.0, "the walkers are legs")


func test_an_empty_slot_has_no_crank_and_no_wheel_voice() -> void:
	var v := _solo(90.0)
	_run(v, 1.0)
	assert_eq(v.cranks[1].revs, 0.0)
	assert_null(v.audio.kit.machine_voice("wheel1"))


func test_load_raises_the_strokes_and_the_rumble() -> void:
	var low := _solo(90.0, 60.0)
	var high := _solo(90.0, 340.0)
	_run(low, 1.0)
	_run(high, 1.0)
	assert_gt(_db_of(high, "pawl_click")[0], _db_of(low, "pawl_click")[0])
	var low_loop: LayeredLoop = low.audio.kit.machine_loop("wheel0")
	var high_loop: LayeredLoop = high.audio.kit.machine_loop("wheel0")
	assert_gt(high_loop.db[0], low_loop.db[0])


func test_a_hard_effort_opens_the_timber_load_and_recovery_none() -> void:
	var easy := _solo(90.0, 60.0)
	var hard := _solo(90.0, 300.0)
	_run(easy, 1.0)
	_run(hard, 1.0)
	var soft_loop: LayeredLoop = easy.audio.kit.machine_loop("wheel0")
	var hard_loop: LayeredLoop = hard.audio.kit.machine_loop("wheel0")
	assert_eq(hard_loop.layer(2).get("sound"), "wheel_load")
	assert_gt(hard_loop.db[2], soft_loop.db[2] + 10.0)


func test_the_rumble_holds_one_pitch_at_every_cadence() -> void:
	var slow := _solo(60.0)
	var fast := _solo(120.0)
	_run(slow, 1.5)
	_run(fast, 1.5)
	var a: LayeredLoop = slow.audio.kit.machine_loop("wheel0")
	var b: LayeredLoop = fast.audio.kit.machine_loop("wheel0")
	assert_almost_eq(a.pitch[0], 1.0, 0.001, "two riders 2 rpm apart must not sweep a comb")
	assert_almost_eq(b.pitch[0], 1.0, 0.001)
	assert_gt(b.db[0], a.db[0], "the wheel is louder when it goes faster, never higher")


func test_the_local_rider_leads_and_others_sit_under_with_no_footsteps() -> void:
	var st := FIX.mid_wave()
	for slot in 4:
		st.rider_at(slot).cadence_rpm = 90.0
		st.rider_at(slot).p_eff_w = 250.0
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.SOLO, 1))
	g.state = st
	g.content = st.content
	_games.append(g)
	var v := g.make_view() as SiegeView
	add_child_autofree(v)
	_run(v, 4.0)
	var kit := v.audio.kit
	var lead_slot := st.rider(g.ctx.local_peer).slot
	var lead_voice: CadenceVoice = kit.machine_voice("wheel%d" % lead_slot)
	var other_voice: CadenceVoice = kit.machine_voice("wheel%d" % ((lead_slot + 1) % 4))
	assert_gt(other_voice.gated, 0, "footsteps and the axle are the lead's alone")
	assert_gt(lead_voice.fired, other_voice.fired)
	var pawls := _db_of(v, "pawl_click")
	assert_gt(pawls.max() - pawls.min(), 8.0, "others play under the lead")
	var other_loop: LayeredLoop = kit.machine_loop("wheel%d" % ((lead_slot + 1) % 4))
	var lead_loop: LayeredLoop = kit.machine_loop("wheel%d" % lead_slot)
	assert_eq(other_loop.on[0], 0, "another rider's wheel is not your rumble")
	assert_eq(other_loop.on[1], 1, "but its far one")
	assert_eq(lead_loop.on[1], 0)
	assert_gt(lead_loop.db[0], other_loop.db[1])


func test_the_mine_and_the_pump_lock_to_their_drawn_phase() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.station(SiegeIds.STATION_MINE).m = 1.0
	st.station(SiegeIds.STATION_TAR).m = 1.0
	st.tar.cauldron_l = 100.0
	var v := _view(st)
	_run(v, 10.0)
	var picks: CadenceVoice = v.audio.kit.machine_voice("mine")
	assert_eq(_count(v, "mine_pick"), _pattern([0.0, 0.5], picks.planned_to()))
	assert_almost_eq(picks.planned_to(), SiegeView.MINE_HZ * 10.0, 0.1)
	var pump: CadenceVoice = v.audio.kit.machine_voice("pump")
	assert_eq(_count(v, "pump_stroke"), _pattern([0.0], pump.planned_to()))
	assert_almost_eq(pump.planned_to(), SiegeView.PUMP_HZ * 10.0, 0.1)


func test_an_empty_cauldron_stops_the_pump_and_the_bubbling() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.station(SiegeIds.STATION_TAR).m = 1.0
	st.tar.cauldron_l = 0.0
	var v := _view(st)
	_run(v, 3.0)
	assert_eq(_count(v, "pump_stroke"), 0)
	assert_eq(_count(v, "tar_bubble"), 0)
	assert_eq(_count(v, "tar_pour"), 0)


# --- Events -----------------------------------------------------------------------------------


func test_a_bolt_twangs_then_its_flight_sounds() -> void:
	var v := _solo(0.0)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_BOLT))
	assert_true(v.audio.played.has("ballista_twang"))
	assert_false(v.audio.played.has("bolt_hiss"), "the hiss leaves after the string")
	_run(v, 0.1)
	assert_true(v.audio.played.has("bolt_hiss"))


func test_a_scorpion_snaps_then_its_flight_sounds() -> void:
	var v := _solo(0.0)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_SCORPION))
	assert_true(v.audio.played.has("scorpion_snap"))
	_run(v, 0.1)
	assert_true(v.audio.played.has("bolt_hiss"), "the Scorpion had no flight at all once")


func test_every_shot_kind_flies_for_as_long_as_it_does_and_then_lands() -> void:
	var table := [
		[SiegeIds.SHOT_STONE, "onager_release", "stone_tumble"],
		[SiegeIds.SHOT_ARROW, "arrow_release", "arrow_swarm"],
		[SiegeIds.SHOT_BOLT, "ballista_twang", "bolt_hiss"],
		[SiegeIds.SHOT_SCORPION, "scorpion_snap", "bolt_hiss"],
	]
	for row: Array in table:
		var v := _solo(0.0)
		var ev := _shot(row[0])
		ev["tk"] = v.state.tick
		v.audio.on_cue(SiegeIds.EV_SHOT, ev)
		assert_true(v.audio.played.has(row[1]), row[1])
		var flight: float = v.audio.last_flight_s
		assert_gt(flight, 0.1, "%s flies" % row[1])
		_run(v, 0.1)
		assert_true(v.audio.played.has(row[2]), row[2])
		assert_eq(v.audio.kit.flights_live(), 1, "%s is in the air" % row[2])
		_run(v, flight - 0.1 - 0.15)
		assert_eq(v.audio.kit.flights_live(), 1, "%s has not ended early" % row[2])
		_run(v, 0.5)
		assert_eq(v.audio.kit.flights_live(), 0, "%s ends with the flight" % row[2])


## Landings run on the clock the picture draws by: a host's clock is its ticks.
func _land(v: SiegeView, seconds: float) -> void:
	for _i in roundi(seconds / Wl.SIM_DT):
		v.state.tick += 1
		v.update(Wl.SIM_DT)


## The one rider on station `id`, its wheel lit there.
func _rider_on(st: SiegeState, id: int) -> void:
	var r := st.rider_at(0)
	r.target = id
	r.connected = true
	r.afk = false


func _db_of_shot(st: SiegeState, src: int, kind: int, sound: String) -> float:
	var v := _view(st)
	var ev := _shot(kind)
	ev["src"] = src
	ev["tk"] = st.tick
	v.audio.kit.clear_played()
	v.audio.on_cue(SiegeIds.EV_SHOT, ev)
	return float(_db_of(v, sound)[0])


func test_your_own_stations_shots_are_over_the_others_and_a_scorpion_is_nobodys() -> void:
	var st := SiegeKit.state("short", 1, 0)
	_rider_on(st, SiegeIds.STATION_ARROWS)
	var own := _db_of_shot(st, SiegeIds.STATION_ARROWS, SiegeIds.SHOT_ARROW, "arrow_release")
	var st2 := SiegeKit.state("short", 1, 0)
	_rider_on(st2, SiegeIds.STATION_BALLISTA)
	var other := _db_of_shot(st2, SiegeIds.STATION_ARROWS, SiegeIds.SHOT_ARROW, "arrow_release")
	assert_almost_eq(own - other, 5.0, 0.01, "another rider's rack, under yours and audible")
	var v := _view(SiegeKit.state("short", 1, 0))
	assert_false(v.audio.is_mine(SiegeIds.SRC_PAD + 1), "nobody drives a pad")


func test_a_landing_keeps_the_side_of_the_shot_it_came_from() -> void:
	var levels: Array[float] = []
	for station: int in [SiegeIds.STATION_ARROWS, SiegeIds.STATION_ONAGER]:
		var st := SiegeKit.state("short", 1, 0)
		_rider_on(st, station)
		var v := _view(st)
		var ev := _shot(SiegeIds.SHOT_STONE)
		ev["src"] = SiegeIds.STATION_ONAGER
		ev["tk"] = st.tick
		v.audio.on_cue(SiegeIds.EV_SHOT, ev)
		v.audio.kit.clear_played()
		_land(v, v.audio.last_flight_s + 1.5)
		levels.append(_db_of(v, "stone_impact")[0])
	assert_almost_eq(levels[1] - levels[0], 4.0, 0.01, "your own stone 4 dB over another's")


func test_only_your_own_stone_ducks_your_wheel() -> void:
	AudioBuses.clear_ducks()
	var st := SiegeKit.state("short", 1, 0)
	_rider_on(st, SiegeIds.STATION_ARROWS)
	_db_of_shot(st, SiegeIds.STATION_ONAGER, SiegeIds.SHOT_STONE, "onager_release")
	AudioBuses.tick(0.005)
	assert_eq(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0, "another rider's stone")
	var st2 := SiegeKit.state("short", 1, 0)
	_rider_on(st2, SiegeIds.STATION_ONAGER)
	_db_of_shot(st2, SiegeIds.STATION_ONAGER, SiegeIds.SHOT_STONE, "onager_release")
	AudioBuses.tick(0.005)
	assert_lt(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0, "your own")
	AudioBuses.clear_ducks()


func test_every_other_volley_passes_under_and_each_still_has_its_flight() -> void:
	var v := _solo(0.0)
	for k in 6:
		v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_ARROW, k + 1))
		_run(v, 0.1)
	var levels := _db_of(v, "arrow_swarm")
	assert_eq(levels.size(), 6, "one flight per volley, the quiet ones too")
	for k in 6:
		var under := SiegeAudio.VOLLEY_UNDER_DB if k % 2 == 1 else 0.0
		assert_almost_eq(levels[k] - levels[0], under, 0.01, "volley %d" % k)


func test_every_arrow_sounds_and_another_riders_are_quieter() -> void:
	var heard := {}
	for station: int in [SiegeIds.STATION_ARROWS, SiegeIds.STATION_BALLISTA]:
		var st := SiegeKit.state("short", 1, 0)
		_rider_on(st, station)
		var v := _view(st)
		var ev := _shot(SiegeIds.SHOT_ARROW)
		ev["src"] = SiegeIds.STATION_ARROWS
		ev["tk"] = st.tick
		v.audio.on_cue(SiegeIds.EV_SHOT, ev)
		_land(v, v.audio.last_flight_s + 1.5)
		var levels := _db_of(v, "arrow_dirt")
		assert_eq(
			levels.size(), 12, "twelve arrows, twelve sounds, the wheel on station %d" % station
		)
		heard[station] = levels[0]
	var bank := AudioBank.load_bank(SiegeAudio.BANK_PATH)
	assert_almost_eq(
		heard[SiegeIds.STATION_BALLISTA] - heard[SiegeIds.STATION_ARROWS],
		float(bank.cues["hit_arrow_dirt"]["other_db"]),
		0.01,
		"the same arrow of the same volley, another rider's"
	)


func test_an_arrow_near_the_camera_is_louder_and_a_volley_spreads_across_the_sends() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var v := _view(st)
	v.update(FRAME)
	var a: SiegeAudio = v.audio
	var mid_y := SiegeAudio.ARROW_DEPTH_MID_PX
	var at := func(y: float) -> Vector3:
		# A point of the ground at that art y, near the middle of the art's width.
		var t := (y - v.bank.to_art(Vector3.ZERO).y) / (v.bank.cam_k)
		return Vector3(t, t, 0.0)
	assert_almost_eq(a._arrow_depth_db(at.call(mid_y)), 0.0, 0.05, "where they land on average")
	var near: float = a._arrow_depth_db(at.call(mid_y + SiegeAudio.ARROW_DEPTH_PX))
	var far: float = a._arrow_depth_db(at.call(mid_y - SiegeAudio.ARROW_DEPTH_PX))
	assert_almost_eq(near, SiegeAudio.ARROW_DEPTH_DB, 0.05)
	assert_almost_eq(far, -SiegeAudio.ARROW_DEPTH_DB, 0.05)
	assert_almost_eq(
		a._arrow_depth_db(at.call(mid_y + 900.0)), SiegeAudio.ARROW_DEPTH_DB, 0.01, "no further"
	)
	var mid := Vector3(-30.0, 40.0, 0.0)
	var wide := absf(a._arrow_pan(mid + Vector3(2.0, -2.0, 0.0), mid) - a._arrow_pan(mid, mid))
	var drawn := absf(a._pan(mid + Vector3(2.0, -2.0, 0.0)) - a._pan(mid))
	assert_gt(wide, drawn * 2.0, "a few metres in a volley reach another pan step")


func test_an_arrows_level_over_its_cue_has_a_ceiling() -> void:
	var st := SiegeKit.state("short", 1, 0)
	_rider_on(st, SiegeIds.STATION_ARROWS)
	var v := _view(st)
	var ev := _shot(SiegeIds.SHOT_ARROW)
	ev["src"] = SiegeIds.STATION_ARROWS
	ev["tk"] = st.tick
	v.audio.on_cue(SiegeIds.EV_SHOT, ev)
	_land(v, v.audio.last_flight_s + 1.5)
	var bank := AudioBank.load_bank(SiegeAudio.BANK_PATH)
	var cue_db := float(bank.cues["hit_arrow_dirt"]["hits"][0]["db"])
	for db: float in _db_of(v, "arrow_dirt"):
		assert_lte(db - cue_db, SiegeAudio.ARROW_LVL_MAX_DB + 0.001)


func test_no_two_arrows_running_play_one_file_and_each_takes_its_own_pitch() -> void:
	var bank := AudioBank.load_bank(SiegeAudio.BANK_PATH)
	for surface: String in ["dirt", "water", "flesh", "wood", "shield"]:
		var hit: Dictionary = bank.cues["hit_arrow_%s" % surface]["hits"][0]
		assert_eq(hit["sound"], "arrow_%s" % surface)
		assert_true(bank.variants(hit["sound"]) >= 3, "%s: several variants" % surface)
		assert_eq(str(hit.get("pitch_var", "")), "pv", surface)
		assert_eq(str(hit.get("db_var", "")), "lvl", surface)
		assert_eq(str(hit.get("pan_var", "")), "pan", surface)
		assert_eq(str(hit.get("variant_var", "")), "vr", surface)
		assert_true(bool(hit.get("crowd", false)), "%s: on the crowd's pool" % surface)


func test_other_riders_impacts_are_thinned_and_your_own_are_not() -> void:
	var st := SiegeKit.state("short", 1, 0)
	_rider_on(st, SiegeIds.STATION_BALLISTA)
	var v := _view(st)
	var last := 0.0
	for k in SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK:
		var ev := _shot(SiegeIds.SHOT_SCORPION, k + 1)
		ev["src"] = SiegeIds.SRC_PAD + 1
		ev["tk"] = st.tick
		v.audio.on_cue(SiegeIds.EV_SHOT, ev)
		last = v.audio.last_flight_s
	_land(v, last + 1.0)
	assert_eq(_count(v, "bolt_dirt"), 1, "three Scorpion bolts down together, one impact heard")
	var landed: int = v.audio._shots.landed_count.get("scorpion", 0)
	assert_eq(landed, SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK, "and nothing else is touched")
	var st2 := SiegeKit.state("short", 1, 0)
	_rider_on(st2, SiegeIds.STATION_ONAGER)
	var w := _view(st2)
	for k in 2:
		var ev := _shot(SiegeIds.SHOT_STONE, k + 1)
		ev["src"] = SiegeIds.STATION_ONAGER
		ev["tk"] = st2.tick
		w.audio.on_cue(SiegeIds.EV_SHOT, ev)
	_land(w, 8.0)
	assert_eq(_count(w, "stone_impact"), 2, "your own stones all land")


func test_a_blow_on_timber_differs_in_pitch_each_time() -> void:
	assert_lte(SiegeAudio.WOOD_PITCH.min(), 0.94 + 0.001)
	assert_gte(SiegeAudio.WOOD_PITCH.max(), 1.06 - 0.001)
	var bank := AudioBank.load_bank(SiegeAudio.BANK_PATH)
	for cue_name: String in ["hit_arrow_wood", "hit_scorpion_wood"]:
		assert_eq(str(bank.cues[cue_name]["hits"][0].get("pitch_var", "")), "pv", cue_name)


func _shot_at(kind: int, st: SiegeState) -> Dictionary:
	var ev := _shot(kind)
	ev["tk"] = st.tick
	return ev


func test_a_shot_lands_on_the_ground_with_nothing_there() -> void:
	var table := [
		[SiegeIds.SHOT_ARROW, "arrow_dirt"],
		[SiegeIds.SHOT_STONE, "stone_impact"],
		[SiegeIds.SHOT_BOLT, "bolt_dirt"],
		[SiegeIds.SHOT_SCORPION, "bolt_dirt"],
	]
	for row: Array in table:
		var v := _solo(0.0)
		_rider_on(v.state, SiegeIds.STATION_ARROWS)
		var ev := _shot_at(row[0], v.state)
		ev["src"] = SiegeIds.STATION_ARROWS
		if row[0] == SiegeIds.SHOT_STONE:
			ev["src"] = SiegeIds.STATION_ONAGER
		v.audio.on_cue(SiegeIds.EV_SHOT, ev)
		assert_false(v.audio.played.has(row[1]), "still in the air")
		_land(v, v.audio.last_flight_s + 1.0)
		assert_true(v.audio.played.has(row[1]), "lands: %s" % row[1])


func test_a_kill_takes_its_side_from_where_the_body_was_last_seen() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var e := SiegeKit.enemy(st, SiegeIds.ENEMY_SPEAR, 100.0)
	var v := _view(st)
	v.update(FRAME)
	var want := v.audio._pan(e.pos)
	assert_ne(want, 0.0, "the road is off to one side")
	st.enemies.clear()
	assert_almost_eq(
		v.audio._enemy_pan(e.id), want, 0.001, "the rules took it off the list already"
	)
	assert_eq(v.audio._enemy_pan(99999), 0.0, "and one nobody saw is in the middle")


func test_a_stone_on_a_ram_is_timber_and_on_spearmen_a_body() -> void:
	var table := [[SiegeIds.ENEMY_RAM, "stone_wood"], [SiegeIds.ENEMY_SPEAR, "hit_flesh"]]
	for row: Array in table:
		var st := SiegeKit.state("short", 1, 0)
		var v := _view(st)
		var ev := _shot_at(SiegeIds.SHOT_STONE, st)
		var e := SiegeKit.enemy(st, row[0], 100.0)
		v.audio.on_cue(SiegeIds.EV_SHOT, ev)
		e.pos = SiegeV2ShotReplay.from_event(ev, st.path, st.content).landing(0)
		_land(v, v.audio.last_flight_s + 0.3)
		assert_true(v.audio.played.has(row[1]), "%d: %s" % [row[0], row[1]])


func test_a_paused_game_holds_its_shots_in_the_air() -> void:
	var v := _solo(0.0)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot_at(SiegeIds.SHOT_STONE, v.state))
	_land(v, 0.5)
	assert_eq(v.audio.kit.flights_live(), 1)
	_bus().paused_changed.emit(true, "test")
	_run(v, 20.0, 0.05)
	assert_eq(v.audio.kit.flights_live(), 1, "the flight waits with the picture")
	assert_false(v.audio.played.has("stone_impact"), "and the landing with it")
	_bus().paused_changed.emit(false, "resume")
	_land(v, v.audio.last_flight_s + 1.0)
	assert_eq(v.audio.kit.flights_live(), 0)
	assert_true(v.audio.played.has("stone_impact"))


func test_a_host_and_a_client_hear_one_shot_alike() -> void:
	var host := _solo(0.0)
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.CLIENT, 2))
	_games.append(g)
	g.apply_snapshot(Protocol.apply_int_fields(FIX.snapshot(), g.int_fields()["snapshot"]))
	var client := g.make_view() as SiegeView
	add_child_autofree(client)
	var ev := _shot(SiegeIds.SHOT_ARROW)
	host.audio.on_cue(SiegeIds.EV_SHOT, ev)
	g.apply_event(ev)
	assert_true(client.audio.played.has("arrow_release"), "the client's event reaches its kit")
	assert_true(host.audio.played.has("arrow_release"))
	_run(client, 0.2)
	assert_true(client.audio.played.has("arrow_swarm"))


func test_shot_sounds_are_capped_per_tick_and_the_next_tick_starts_over() -> void:
	var v := _solo(0.0)
	for _i in 5:
		v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_SCORPION, 7))
	assert_eq(_count(v, "scorpion_snap"), SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_SCORPION, 8))
	assert_eq(_count(v, "scorpion_snap"), SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK + 1)


func test_kills_are_thinned_but_a_siege_engine_always_falls_loud() -> void:
	var v := _solo(0.0)
	for i in 6:
		v.audio.on_cue(SiegeIds.EV_KILL, SiegeEvents.kill(i, SiegeIds.ENEMY_SPEAR, 1, false))
	assert_eq(_count(v, "kill_thud"), 1)
	_run(v, SiegeAudio.KILL_EVERY_S + 0.1)
	v.audio.on_cue(SiegeIds.EV_KILL, SiegeEvents.kill(9, SiegeIds.ENEMY_SPEAR, 1, false))
	assert_eq(_count(v, "kill_thud"), 2)
	v.audio.on_cue(SiegeIds.EV_KILL, SiegeEvents.kill(10, SiegeIds.ENEMY_RAM, 1, false))
	assert_true(v.audio.played.has("stone_wood"), "a ram going down does not wait its turn")


func test_each_event_plays_its_sound() -> void:
	var table := [
		[SiegeIds.EV_WAVE_START, {}, "horn_wave"],
		[SiegeIds.EV_PUSH, {}, "horn_push"],
		[SiegeIds.EV_RUSH, {"on": 1}, "horn_rush"],
		[SiegeIds.EV_WAVE_END, {}, "wave_end_bell"],
		[SiegeIds.EV_BREACH, {}, "gate_crash"],
		[SiegeIds.EV_GATE_RESTORED, {}, "gate_restored"],
		[SiegeIds.EV_DOCK, {}, "tower_dock"],
		[SiegeIds.EV_REACH, {}, "reach_alarm"],
		[SiegeIds.EV_LEAK, {}, "reach_alarm"],
		[SiegeIds.EV_ROUTE, {"slot": 0}, "lever_route"],
		[SiegeIds.EV_BUY, {"slot": 0, "ok": 1}, "hammer_buy"],
		[SiegeIds.EV_OVERDRIVE, {"slot": 0, "st": SiegeIds.OD_EV_START}, "overdrive_on"],
		[SiegeIds.EV_OVERDRIVE, {"slot": 0, "st": SiegeIds.OD_EV_END}, "overdrive_off"],
		[SiegeIds.EV_OVERDRIVE, {"slot": 0, "st": SiegeIds.OD_EV_REFUSED}, "overdrive_no"],
	]
	for row: Array in table:
		var v := _solo(0.0)
		v.audio.on_cue(row[0], row[1])
		assert_true(v.audio.played.has(row[2]), "%s plays %s" % [row[0], row[2]])


func test_a_rush_end_and_a_refused_buy_are_silent() -> void:
	var v := _solo(0.0)
	v.audio.kit.clear_played()
	v.audio.on_cue(SiegeIds.EV_RUSH, {"on": 0})
	v.audio.on_cue(SiegeIds.EV_BUY, {"slot": 0, "ok": 0})
	assert_eq(v.audio.played.size(), 0)


func test_another_riders_lever_is_quieter_than_your_own() -> void:
	var v := _solo(0.0)
	v.update(FRAME)
	v.audio.on_cue(SiegeIds.EV_ROUTE, {"slot": 0})
	v.audio.on_cue(SiegeIds.EV_ROUTE, {"slot": 3})
	var levers := _db_of(v, "lever_route")
	assert_gt(levers[0], levers[1] + 8.0)


func test_a_rams_leaks_ring_the_alarm_once_in_a_while() -> void:
	var v := _solo(0.0)
	for _i in 5:
		v.audio.on_cue(SiegeIds.EV_LEAK, {})
	assert_eq(_count(v, "reach_alarm"), 1)
	_run(v, SiegeAudio.LEAK_ALARM_EVERY_S + 0.1)
	v.audio.on_cue(SiegeIds.EV_LEAK, {})
	assert_eq(_count(v, "reach_alarm"), 2)


# --- What the state tells ---------------------------------------------------------------------


func test_a_gate_hit_grows_with_the_damage() -> void:
	var v := _solo(0.0)
	v.update(FRAME)
	v.state.gate_hp -= 1.0
	v.update(FRAME)
	_run(v, SiegeAudio.GATE_HIT_EVERY_S)
	v.state.gate_hp -= 9.0
	v.update(FRAME)
	var hits := _db_of(v, "gate_hit")
	assert_eq(hits.size(), 2)
	assert_gt(hits[1], hits[0])


## A gate losing `hp_per_s` for `seconds` at 20 ticks a second, as the rules (fractions) or a
## client's snapshot (ceili, whole HP) show it. Returns how many hits it made.
func _gate_hits(hp_per_s: float, seconds: float, whole: bool) -> int:
	var v := _solo(0.0)
	var hp: float = v.state.gate_hp
	v.update(0.05)
	for _i in roundi(seconds / 0.05):
		hp -= hp_per_s * 0.05
		v.state.gate_hp = ceilf(hp) if whole else hp
		v.update(0.05)
	return _count(v, "gate_hit")


func test_one_ram_is_heard_on_the_gate_at_fractional_damage() -> void:
	# 3.9 HP/s is 0.195 HP a tick: each tick alone is under the smallest drop that sounds.
	assert_almost_eq(_gate_hits(3.9, 6.0, false), 5, 1, "about one hit per ram stroke")


func test_many_rams_do_not_fire_a_hit_each_tick() -> void:
	assert_almost_eq(_gate_hits(11.7, 6.0, false), 5, 1, "three rams, the same rate")


func test_a_client_and_a_host_hear_the_gate_alike() -> void:
	for hp_per_s: float in [3.9, 7.8, 11.7]:
		assert_almost_eq(
			_gate_hits(hp_per_s, 6.0, true), _gate_hits(hp_per_s, 6.0, false), 1, "%f" % hp_per_s
		)


func test_a_hit_says_what_the_gate_lost_since_the_last_one() -> void:
	var v := _solo(0.0)
	v.update(FRAME)
	v.state.gate_hp -= 1.0
	v.update(FRAME)
	v.state.gate_hp -= 3.0
	v.update(FRAME)
	assert_eq(_count(v, "gate_hit"), 1, "the second drop waits its turn")
	_run(v, SiegeAudio.GATE_HIT_EVERY_S + 0.05)
	var hits := _db_of(v, "gate_hit")
	assert_eq(hits.size(), 2, "and is heard then, not lost")
	assert_gt(hits[1], hits[0])


func test_a_repaired_gate_does_not_sound_like_a_hit() -> void:
	var v := _solo(0.0)
	v.update(FRAME)
	v.state.gate_hp -= 20.0
	v.update(FRAME)
	assert_eq(_count(v, "gate_hit"), 1)
	v.state.gate_hp += 15.0
	_run(v, SiegeAudio.GATE_HIT_EVERY_S + 0.1)
	assert_eq(_count(v, "gate_hit"), 1, "a repair is no hit")
	var loud := _db_of(v, "gate_hit")[0]
	v.state.gate_hp -= 1.0
	v.update(FRAME)
	var hits := _db_of(v, "gate_hit")
	assert_eq(hits.size(), 2, "the next blow counts from the repaired gate")
	assert_lt(hits[1], loud)


func test_hooves_keep_their_timer_and_grow_with_the_horses() -> void:
	var st := SiegeKit.state("short", 1, 0)
	SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, st.path.length_m - 40.0)
	var v := _view(st)
	_run(v, 2.0, 0.05)
	assert_almost_eq(_count(v, "hooves"), 5, 1, "one gallop per 0.4 s")
	var one := _db_of(v, "hooves")[0]
	for k in 5:
		SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, st.path.length_m - 40.0 + k)
	_run(v, 0.5, 0.05)
	assert_gt(_db_of(v, "hooves").max(), one)


func _bus() -> Node:
	return get_node("/root/EventBus")


func test_a_pause_stops_the_ram_and_the_hooves_over_a_frozen_picture() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var ram := SiegeKit.enemy(st, SiegeIds.ENEMY_RAM, 100.0)
	ram.st = SiegeIds.EN_BATTER
	SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, st.path.length_m - 40.0)
	var v := _view(st)
	_run(v, 2.0, 0.05)
	assert_gt(_count(v, "ram_thud"), 0)
	assert_gt(_count(v, "hooves"), 0)
	_bus().paused_changed.emit(true, "test")
	var rams := _count(v, "ram_thud")
	var hooves := _count(v, "hooves")
	_run(v, 5.0, 0.05)
	assert_eq(_count(v, "ram_thud"), rams, "no ram under a pause")
	assert_eq(_count(v, "hooves"), hooves, "no hooves under a pause")
	_bus().paused_changed.emit(false, "resume")
	_run(v, 2.0, 0.05)
	assert_gt(_count(v, "ram_thud"), rams, "the ram goes on after the pause")
	assert_gt(_count(v, "hooves"), hooves, "and so do the hooves")


func test_a_pause_starts_no_war_drums_and_does_not_stack_them_for_the_resume() -> void:
	var st := SiegeKit.state("short", 1, 0)
	SiegeKit.enemy(st, SiegeIds.ENEMY_SPEAR, 100.0)
	var v := _view(st)
	_run(v, 30.0, 0.05)
	assert_gt(_count(v, "war_drum"), 0, "they beat before the pause")
	_bus().paused_changed.emit(true, "test")
	var drums := _count(v, "war_drum")
	_run(v, 60.0, 0.05)
	assert_eq(_count(v, "war_drum"), drums, "no drums over a frozen picture")
	_bus().paused_changed.emit(false, "resume")
	_run(v, 2.0, 0.05)
	assert_lte(_count(v, "war_drum") - drums, 3, "at most one burst's worth after the resume")


func test_a_pause_in_a_break_starts_no_anvil_and_no_lark() -> void:
	var v := _view(SiegeKit.state("short", 1, 0, 1, SiegeIds.ROLE_BREAK))
	_run(v, 2.0, 0.05)
	_bus().paused_changed.emit(true, "test")
	var anvils := _count(v, "far_anvil")
	var larks := _count(v, "lark")
	_run(v, 120.0, 0.05)
	assert_eq(_count(v, "far_anvil"), anvils, "no anvil over a frozen picture")
	assert_eq(_count(v, "lark"), larks)
	_bus().paused_changed.emit(false, "resume")


func test_each_ram_stroke_differs_a_little() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var ram := SiegeKit.enemy(st, SiegeIds.ENEMY_RAM, 100.0)
	ram.st = SiegeIds.EN_BATTER
	var v := _view(st)
	_run(v, 8.0, 0.05)
	var at: Array[float] = []
	for i in v.audio.kit.played.size():
		if v.audio.kit.played[i] == "ram_thud":
			at.append(v.audio.kit.played_t[i])
	assert_gt(at.size(), 4)
	assert_ne(snappedf(at[1] - at[0], 0.05), snappedf(at[2] - at[1], 0.05), "no metronome")


func test_a_ram_knocks_every_so_often() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var ram := SiegeKit.enemy(st, SiegeIds.ENEMY_RAM, 100.0)
	ram.st = SiegeIds.EN_BATTER
	var v := _view(st)
	_run(v, 3.7, 0.05)
	assert_almost_eq(_count(v, "ram_thud"), 4, 1)


func test_a_walking_tower_creaks_and_stops_when_it_docks() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var tower := SiegeKit.enemy(st, SiegeIds.ENEMY_TOWER, 100.0)
	var v := _view(st)
	_run(v, 0.3)
	assert_eq(_count(v, "tower_creak"), 1)
	var loop: LayeredLoop = v.audio.kit.entry_loop("tower_creak")
	assert_gt(loop.db[0], LayeredLoop.OFF_DB)
	tower.st = SiegeIds.EN_BATTER
	_run(v, 0.3)
	assert_true(loop.all_off())


func test_coins_for_your_own_gold_only_and_not_too_often() -> void:
	var v := _solo(0.0)
	v.update(FRAME)
	var me := v.state.rider_at(0)
	me.gold += 1.0
	v.update(FRAME)
	assert_eq(_count(v, "coin_clink"), 1)
	me.gold += 1.0
	v.update(FRAME)
	assert_eq(_count(v, "coin_clink"), 1, "at most one per COIN_EVERY_S")
	_run(v, SiegeAudio.COIN_EVERY_S + 0.05)
	me.gold += 1.0
	v.update(FRAME)
	assert_eq(_count(v, "coin_clink"), 2)


func test_tar_hisses_when_the_curtain_or_the_coat_changes_stage() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.tar.curtain_max = 100.0
	st.tar.curtain_hp = 100.0
	var v := _view(st)
	_run(v, 0.2)
	assert_eq(_count(v, "tar_hiss"), 0)
	st.tar.curtain_hp = 1.0
	_run(v, 0.1)
	assert_eq(_count(v, "tar_hiss"), 1)
	st.tar.coat = 1.0
	_run(v, 0.1)
	assert_eq(_count(v, "tar_hiss"), 2)


func test_the_junction_stops_dead_with_the_last_wheel_though_the_mean_still_reads_watts() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.team_w = 300.0
	st.rider_at(0).cadence_rpm = 90.0
	var v := _view(st)
	_run(v, 0.5)
	var loop: LayeredLoop = v.audio.kit.entry_loop("junction_clatter")
	assert_false(loop.all_off())
	st.rider_at(0).cadence_rpm = 0.0
	_run(v, 0.2)
	assert_gt(st.team_w, 5.0, "the rules' 1 s mean hasn't fallen yet")
	assert_true(loop.all_off(), "shut well inside D4's 400 ms")


func test_the_junction_and_the_pour_run_only_in_a_wave() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.team_w = 800.0
	st.rider_at(0).cadence_rpm = 90.0
	st.station(SiegeIds.STATION_TAR).m = 1.0
	st.tar.cauldron_l = 100.0
	var v := _view(st)
	_run(v, 0.5)
	assert_eq(_count(v, "junction_clatter"), 1)
	assert_eq(_count(v, "tar_pour"), 1)
	assert_eq(_count(v, "tar_bubble"), 1)
	st.role = SiegeIds.ROLE_BREAK
	_run(v, 0.5)
	assert_true(v.audio.kit.entry_loop("junction_clatter").all_off())
	assert_true(v.audio.kit.entry_loop("tar_pour").all_off())
	assert_false(v.audio.kit.entry_loop("tar_bubble").all_off(), "the cauldron still simmers")


func test_hooves_cannot_cover_the_battle() -> void:
	var st := SiegeKit.state("short", 1, 0)
	for k in 8:
		SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, st.path.length_m - 40.0 + k)
	var v := _view(st)
	_run(v, 1.0, 0.05)
	assert_lte(_db_of(v, "hooves").max(), -16.0, "soft, whatever comes")


func test_hooves_only_for_a_chariot_near_the_gate() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var far := SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, 100.0)
	var v := _view(st)
	_run(v, 2.0, 0.05)
	assert_eq(_count(v, "hooves"), 0, "they ran 75 % of a wave from the far end of the road")
	far.prog_m = st.path.length_m - 40.0
	_run(v, 2.0, 0.05)
	assert_gt(_count(v, "hooves"), 0)


func test_the_junction_rises_with_the_team() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.team_w = 200.0
	st.rider_at(0).cadence_rpm = 90.0
	var v := _view(st)
	_run(v, 1.0)
	var low: float = v.audio.kit.entry_loop("junction_clatter").db[0]
	st.team_w = 1400.0
	_run(v, 2.0)
	assert_gt(v.audio.kit.entry_loop("junction_clatter").db[0], low, "louder, not higher")
	assert_almost_eq(v.audio.kit.entry_loop("junction_clatter").pitch[0], 1.0, 0.001)


func test_the_hill_wind_plays_and_the_lark_only_sings_in_the_warm_up() -> void:
	var calm := SiegeKit.state("short", 1, 0)
	var a := _view(calm)
	assert_not_null(a.audio.kit.current_bed())
	_run(a, 90.0, 0.1)
	assert_gt(_count(a, "crow"), 0, "crows over the hill")
	assert_gt(_count(a, "banner_flap"), 0)
	assert_eq(_count(a, "lark"), 0)
	var warm := SiegeKit.state("short", 1, 0, 1, SiegeIds.ROLE_WARMUP_WAVE)
	var b := _view(warm)
	_run(b, 90.0, 0.1)
	assert_gt(_count(b, "lark"), 0)


func test_the_lark_and_the_anvil_keep_to_the_calm_between_waves() -> void:
	var wave := _view(SiegeKit.state("short", 1, 0))
	_run(wave, 120.0, 0.1)
	assert_eq(_count(wave, "far_anvil"), 0, "no repairs under attack")
	assert_eq(_count(wave, "lark"), 0)
	var calm := _view(SiegeKit.state("short", 1, 0, 1, SiegeIds.ROLE_BREAK))
	_run(calm, 120.0, 0.1)
	assert_gt(_count(calm, "far_anvil"), 0)
	assert_gt(_count(calm, "lark"), 0)


func test_the_war_drums_beat_only_while_enemies_are_on_the_field() -> void:
	var empty := _view(SiegeKit.state("short", 1, 0))
	_run(empty, 90.0, 0.1)
	assert_eq(_count(empty, "war_drum"), 0)
	var st := SiegeKit.state("short", 1, 0)
	SiegeKit.enemy(st, SiegeIds.ENEMY_SPEAR, 100.0)
	var v := _view(st)
	_run(v, 90.0, 0.1)
	assert_gt(_count(v, "war_drum"), 0)


func test_a_client_view_hears_the_rider_the_snapshot_carries() -> void:
	var g := F.make_game(F.make_ctx(3, 1, "vo2", Wl.CLIENT, 2))
	_games.append(g)
	g.apply_snapshot(Protocol.apply_int_fields(FIX.snapshot(), g.int_fields()["snapshot"]))
	var v := g.make_view() as SiegeView
	add_child_autofree(v)
	_run(v, 1.0)
	var moving := 0
	for slot in 4:
		var r := g.state.rider_at(slot)
		if r != null and r.cadence_rpm > 1.0:
			assert_gt(v.cranks[slot].revs, 0.0)
			moving += 1
	assert_gt(moving, 0)
