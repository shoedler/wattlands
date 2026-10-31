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
		assert_eq(_count(v, "wheel_creak"), _pattern([0.25], to), "creak at %d rpm" % rpm)
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
	assert_true(loop.db[0] <= LayeredLoop.OFF_DB, "the groan is shut within 120 ms")
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


func test_load_raises_the_strokes_and_the_groan() -> void:
	var low := _solo(90.0, 60.0)
	var high := _solo(90.0, 340.0)
	_run(low, 1.0)
	_run(high, 1.0)
	assert_gt(_db_of(high, "pawl_click")[0], _db_of(low, "pawl_click")[0])
	var low_loop: LayeredLoop = low.audio.kit.machine_loop("wheel0")
	var high_loop: LayeredLoop = high.audio.kit.machine_loop("wheel0")
	assert_gt(high_loop.db[0], low_loop.db[0])


func test_a_hard_effort_opens_two_strains_a_pitch_apart_and_recovery_none() -> void:
	var easy := _solo(90.0, 80.0)
	var hard := _solo(90.0, 300.0)
	_run(easy, 1.0)
	_run(hard, 1.0)
	var soft_loop: LayeredLoop = easy.audio.kit.machine_loop("wheel0")
	var hard_loop: LayeredLoop = hard.audio.kit.machine_loop("wheel0")
	assert_eq(hard_loop.layer(1).get("sound"), "timber_strain")
	assert_eq(hard_loop.layer(2).get("sound"), "timber_strain")
	for i in [1, 2]:
		assert_eq(soft_loop.on[i], 0, "no strain player in recovery")
		assert_eq(hard_loop.on[i], 1)
	assert_almost_eq(hard_loop.pitch[2] / hard_loop.pitch[1], 1.13, 0.001)


func test_the_groan_follows_cadence_in_pitch() -> void:
	var slow := _solo(60.0)
	var fast := _solo(120.0)
	_run(slow, 1.5)
	_run(fast, 1.5)
	var a: LayeredLoop = slow.audio.kit.machine_loop("wheel0")
	var b: LayeredLoop = fast.audio.kit.machine_loop("wheel0")
	assert_gt(b.pitch[0], a.pitch[0])


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


func test_a_bolt_twangs_then_whooshes() -> void:
	var v := _solo(0.0)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_BOLT))
	assert_true(v.audio.played.has("ballista_twang"))
	assert_false(v.audio.played.has("bolt_whoosh"), "the whoosh leaves after the string")
	_run(v, 0.1)
	assert_true(v.audio.played.has("bolt_whoosh"))


func test_a_stone_lands_when_its_flight_is_over() -> void:
	var v := _solo(0.0)
	var ev := _shot(SiegeIds.SHOT_STONE)
	var flight := SiegeAudio.flight_s(ev)
	assert_gt(flight, SiegeAudio.FLIGHT_MIN_S)
	v.audio.on_cue(SiegeIds.EV_SHOT, ev)
	assert_true(v.audio.played.has("onager_release"))
	_run(v, flight - 0.1)
	assert_true(v.audio.played.has("stone_whoosh"))
	assert_false(v.audio.played.has("stone_impact"))
	_run(v, 0.2)
	assert_true(v.audio.played.has("stone_impact"))


func test_a_rack_within_the_gap_is_a_release_and_a_patter_with_no_whistle() -> void:
	var v := _solo(0.0)
	var ev := _shot(SiegeIds.SHOT_ARROW, 1)
	v.audio.on_cue(SiegeIds.EV_SHOT, ev)
	_run(v, 0.2)
	assert_eq(_count(v, "arrow_whistle"), 3)
	_run(v, 1.3)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_ARROW, 2))
	_run(v, 0.2)
	assert_eq(_count(v, "arrow_whistle"), 3, "1.5 s later: no whistle")
	assert_eq(_count(v, "arrow_release"), 2)
	_run(v, SiegeAudio.flight_s(ev) + 0.1)
	assert_eq(_count(v, "arrow_patter"), 2, "the second rack still lands")
	_run(v, SiegeAudio.WHISTLE_GAPS_S[0])
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_ARROW, 3))
	_run(v, 0.2)
	assert_eq(_count(v, "arrow_whistle"), 6, "the gap over: three more")


func test_an_organ_at_full_rate_whistles_one_volley_in_three() -> void:
	var v := _solo(0.0)
	for k in 12:
		v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_ARROW, k + 1))
		_run(v, 1.5)
	assert_eq(_count(v, "arrow_release"), 12)
	assert_eq(_count(v, "arrow_whistle"), 12, "4 whistling volleys of 12, 3 whistles each")


func test_the_whistling_volleys_keep_no_steady_beat() -> void:
	var v := _solo(0.0)
	for k in 30:
		v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_ARROW, k + 1))
		_run(v, 1.5)
	var kit := v.audio.kit
	var at: Array[float] = []
	for i in kit.played.size():
		# Each whistling volley's first arrow: the other two come 0.07 and 0.15 s after it.
		if kit.played[i] == "arrow_whistle" and (at.is_empty() or kit.played_t[i] - at[-1] > 1.0):
			at.append(kit.played_t[i])
	var gaps: Array[float] = []
	for i in range(1, at.size()):
		gaps.append(snappedf(at[i] - at[i - 1], 0.5))
	assert_eq(
		gaps.slice(0, 4), [4.5, 6.0, 4.5, 9.0] as Array[float], "the organ's rate through the cycle"
	)


func test_shots_of_a_single_file_sound_carry_a_pitch_from_their_spread_seed() -> void:
	var bank := AudioBank.load_bank(SiegeAudio.BANK_PATH)
	for cue_name: String in ["shot_bolt", "shot_stone", "shot_arrow", "shot_arrow_rack"]:
		var vars: Array[String] = []
		for hit: Dictionary in bank.cues[cue_name]["hits"]:
			vars.append(str(hit.get("pitch_var", "")))
		assert_true(vars.has("p"), cue_name)
	var v := _solo(0.0)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_BOLT))
	assert_true(v.audio.played.has("ballista_twang"))


func test_a_volley_whistles_three_times_then_patters() -> void:
	var v := _solo(0.0)
	var ev := _shot(SiegeIds.SHOT_ARROW)
	v.audio.on_cue(SiegeIds.EV_SHOT, ev)
	assert_true(v.audio.played.has("arrow_release"))
	_run(v, 0.2)
	assert_eq(_count(v, "arrow_whistle"), 3)
	_run(v, SiegeAudio.flight_s(ev))
	assert_eq(_count(v, "arrow_patter"), 1)


func test_shot_sounds_are_capped_per_tick_and_the_next_tick_starts_over() -> void:
	var v := _solo(0.0)
	for _i in 5:
		v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_SCORPION, 7))
	assert_eq(_count(v, "scorpion_snap"), SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK)
	v.audio.on_cue(SiegeIds.EV_SHOT, _shot(SiegeIds.SHOT_SCORPION, 8))
	assert_eq(_count(v, "scorpion_snap"), SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK + 1)


func test_kills_are_capped_per_frame() -> void:
	var v := _solo(0.0)
	for i in 6:
		v.audio.on_cue(SiegeIds.EV_KILL, SiegeEvents.kill(i, SiegeIds.ENEMY_SPEAR, 1, false))
	assert_eq(_count(v, "kill_thud"), SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK)
	v.update(FRAME)
	v.audio.on_cue(SiegeIds.EV_KILL, SiegeEvents.kill(9, SiegeIds.ENEMY_SPEAR, 1, false))
	assert_eq(_count(v, "kill_thud"), SiegeAudio.MAX_SHOT_SOUNDS_PER_TICK + 1)


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
	SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, 100.0)
	var v := _view(st)
	_run(v, 2.0, 0.05)
	assert_almost_eq(_count(v, "hooves"), 5, 1, "one gallop per 0.4 s")
	var one := _db_of(v, "hooves")[0]
	for k in 5:
		SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, 110.0 + k)
	_run(v, 0.5, 0.05)
	assert_gt(_db_of(v, "hooves").max(), one)


func _bus() -> Node:
	return get_node("/root/EventBus")


func test_a_pause_stops_the_ram_and_the_hooves_over_a_frozen_picture() -> void:
	var st := SiegeKit.state("short", 1, 0)
	var ram := SiegeKit.enemy(st, SiegeIds.ENEMY_RAM, 100.0)
	ram.st = SiegeIds.EN_BATTER
	SiegeKit.enemy(st, SiegeIds.ENEMY_CHARIOT, 110.0)
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


func test_the_junction_rises_with_the_team() -> void:
	var st := SiegeKit.state("short", 1, 0)
	st.team_w = 200.0
	st.rider_at(0).cadence_rpm = 90.0
	var v := _view(st)
	_run(v, 1.0)
	var low: float = v.audio.kit.entry_loop("junction_clatter").pitch[0]
	st.team_w = 1400.0
	_run(v, 2.0)
	assert_gt(v.audio.kit.entry_loop("junction_clatter").pitch[0], low)


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
