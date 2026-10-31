extends GutTest
## The tank's bank against the game: every sound imported as its manifest says, every event mapped, and every stroke's
## fraction against the formula that draws its machine (SPEC_AUDIO 2.3, 2.6). The art's formulas sit inside its draw
## calls, so these tests restate each one and pin its line in tank_mech.gd: if an art formula moves, this says so.

const BANK := "res://assets/tank/audio/audio.json"
const MANIFEST := "res://assets/tank/audio/audio_manifest.json"
const MECH := "res://src/games/tank/view/tank_mech.gd"
const EPS := 0.0005

var _bank: AudioBank = null


func before_all() -> void:
	_bank = AudioBank.load_bank(BANK)


func _fractions(machine: String, sound: String) -> Array:
	var out: Array = []
	for ev: Dictionary in _bank.machines[machine]["events"]:
		if str(ev["sound"]) == sound:
			out.append_array(ev["at"])
	out.sort()
	return out


func _event(machine: String, sound: String) -> Dictionary:
	for ev: Dictionary in _bank.machines[machine]["events"]:
		if str(ev["sound"]) == sound:
			return ev
	return {}


## `formula` is a sawtooth of the crank phase: at each fraction it must fall back, and only there.
func _assert_wraps_at(formula: Callable, expected: Array, text: String) -> void:
	for at: Variant in expected:
		var f := float(at)
		var before: float = formula.call(f - EPS)
		var after: float = formula.call(f + EPS)
		assert_lt(after, before, "%s: wraps at %s" % [text, str(f)])
	var wraps := 0
	var steps := 7200
	var last: float = formula.call(0.0)
	for i in range(1, steps + 1):
		var now: float = formula.call(float(i) / float(steps))
		if now < last:
			wraps += 1
		last = now
	assert_eq(wraps, expected.size(), "%s: wraps per revolution" % text)


## The art's formula, as tank_mech.gd spells it: the fractions below are only true while this line stands.
func _assert_art_says(line: String) -> void:
	var source := FileAccess.get_file_as_string(MECH)
	assert_true(source.contains(line), "tank_mech.gd still says: %s" % line)


func test_the_bank_loads_and_every_seat_has_its_machine() -> void:
	assert_not_null(_bank)
	assert_eq(AudioBank.validate(JSON.parse_string(FileAccess.get_file_as_string(BANK))).size(), 0)
	for seat: String in TankRig.SEATS:
		assert_true(TankAudio.MACHINE_OF_SEAT.has(seat), seat)
		assert_true(_bank.machines.has(TankAudio.MACHINE_OF_SEAT[seat]), seat)
	assert_true(_bank.machines.has(TankAudio.TRACK))
	assert_true(_bank.beds.has("night_forest"))


func test_every_sound_is_imported_as_the_manifest_says() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_gt(manifest.size(), 100)
	for stem: String in manifest:
		var m: Dictionary = manifest[stem]
		var s := _bank.stream(str(m["sound"]), int(m["variant"])) as AudioStreamWAV
		assert_not_null(s, stem)
		if s == null:
			continue
		assert_eq(s.mix_rate, int(m["rate"]), stem)
		assert_eq(s.stereo, int(m["ch"]) == 2, stem)
		var qoa := str(m["compress"]) == "qoa"
		assert_eq(
			s.format, AudioStreamWAV.FORMAT_QOA if qoa else AudioStreamWAV.FORMAT_16_BITS, stem
		)
		var looped := bool(m["loop"])
		assert_eq(
			s.loop_mode,
			AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED,
			stem
		)
		if looped:
			assert_eq(s.loop_end, int(m["loop_frames"]), stem + ": the guard frame's period")


func test_every_event_maps_to_a_cue_or_is_silent() -> void:
	for kind: String in TankEvents.TYPES:
		var mapped := TankAudio.EVENT_CUES.has(kind)
		var silent := kind in TankAudio.SILENT_EVENTS
		assert_true(mapped != silent, "%s: one of a cue or SILENT_EVENTS" % kind)


func test_every_mapped_cue_exists_and_no_cue_is_an_orphan() -> void:
	var reached: Array[String] = TankAudio.STATE_CUES.duplicate()
	for kind: String in TankAudio.EVENT_CUES:
		for id: String in TankAudio.EVENT_CUES[kind]:
			assert_true(_bank.cues.has(id), id)
			reached.append(id)
	for id: String in TankAudio.STATE_CUES:
		assert_true(_bank.cues.has(id), id)
	for id: String in _bank.cues:
		assert_has(reached, id, "cue %s has a trigger" % id)


func test_every_sound_is_used() -> void:
	var used := {}
	for id: String in _bank.machines:
		for ev: Dictionary in _bank.machines[id]["events"]:
			used[ev["sound"]] = true
		for layer: Dictionary in _bank.machines[id]["loops"]:
			used[layer["sound"]] = true
	for id: String in _bank.loops:
		for layer: Dictionary in _bank.loops[id]["layers"]:
			used[layer["sound"]] = true
	for id: String in _bank.beds:
		for layer: Dictionary in _bank.beds[id]["layers"]:
			used[layer["sound"]] = true
		for spot: Dictionary in _bank.beds[id]["spots"]:
			used[spot["sound"]] = true
	for id: String in _bank.cues:
		for hit: Dictionary in _bank.cues[id]["hits"]:
			used[hit["sound"]] = true
	for id: String in _bank.sounds:
		assert_true(used.has(id), "sound %s plays somewhere" % id)


func test_the_diesel_fires_when_its_flapper_lifts() -> void:
	# tank_mech.gd _diesel: e = ph * RATIO["diesel"], since = fposmod(e * 360 - 200, 240).
	_assert_art_says('var e := ph * float(RATIO["diesel"])')
	_assert_art_says("var since := fposmod(e * 360.0 - 200.0, 240.0)")
	var ratio := float(TankMech.RATIO["diesel"])
	var since := func(ph: float) -> float: return fposmod(ph * ratio * 360.0 - 200.0, 240.0)
	var fires: Array = []
	fires.append_array(_fractions("diesel", "diesel_fire_a"))
	fires.append_array(_fractions("diesel", "diesel_fire_b"))
	fires.append_array(_fractions("diesel", "diesel_fire_c"))
	fires.sort()
	_assert_wraps_at(since, fires, "fire")
	assert_eq(_fractions("diesel", "diesel_fire_hard"), fires, "the overlay lands on the fires")


func test_the_valves_stand_a_fixed_turn_from_the_fires() -> void:
	var ex := _fractions("diesel", "diesel_valve_ex")
	var inlet := _fractions("diesel", "diesel_valve_in")
	assert_eq(ex.size(), 3)
	assert_eq(inlet.size(), 3)
	var fires := [0.2778, 0.6111, 0.9444]
	for i in 3:
		assert_almost_eq(
			float(ex[i]) - float(fires[i]), 0.0222, 0.0005, "exhaust opens on the fall"
		)
		assert_almost_eq(fposmod(float(inlet[i]) - float(fires[i]), 1.0), 0.8333, 0.0005, "inlet")


func test_the_dynamo_dumps_where_its_jars_empty() -> void:
	# tank_mech.gd: cyc < 0.8 charges, then dumps; `max_fill = pw / 1.15`, the dump shows when max_fill > 0.4.
	_assert_art_says("if cyc < 0.8:")
	_assert_art_says("var max_fill := clampf(pw / 1.15, 0.0, 1.0)")
	_assert_art_says("if dump > 0.0 and max_fill > 0.4:")
	_assert_art_says("var rshift := fposmod(ph * 3.0, 1.0) * 3.0")
	assert_eq(_fractions("dynamo", "cap_dump"), [0.8])
	assert_almost_eq(float(_event("dynamo", "cap_dump")["when"]["min"]), 1.15 * 0.4, 0.001)
	# The ring's teeth: fposmod(ph * 3, 1).
	var teeth := func(ph: float) -> float: return fposmod(ph * 3.0, 1.0)
	_assert_wraps_at(teeth, _fractions("dynamo", "brush_tick"), "brush")


func test_the_steam_engine_chuffs_at_each_end_of_its_stroke() -> void:
	# tank_mech.gd: stroke = fposmod(ph * 2, 1).
	_assert_art_says("var stroke := fposmod(ph * 2.0, 1.0)")
	var stroke := func(ph: float) -> float: return fposmod(ph * 2.0, 1.0)
	var chuffs: Array = []
	chuffs.append_array(_fractions("steam", "chuff_a"))
	chuffs.append_array(_fractions("steam", "chuff_b"))
	chuffs.sort()
	_assert_wraps_at(stroke, chuffs, "chuff")


func test_the_arc_zaps_as_it_starts_up_the_ladder() -> void:
	# tank_mech.gd: climb = fposmod(ph * 2 + ai * 0.5, 1), a second arc over 0.3; the belt: fposmod(ph * 12, 3).
	_assert_art_says("fposmod(ph * 2.0 + ")
	_assert_art_says("fposmod(ph * 12.0, 3.0)")
	var first := func(ph: float) -> float: return fposmod(ph * 2.0, 1.0)
	var second := func(ph: float) -> float: return fposmod(ph * 2.0 + 0.5, 1.0)
	var belt := func(ph: float) -> float: return fposmod(ph * 12.0, 3.0)
	_assert_wraps_at(first, _fractions("arc", "arc_zap"), "first arc")
	_assert_wraps_at(second, _fractions("arc", "arc_zap_over"), "second arc")
	_assert_wraps_at(belt, _fractions("arc", "belt_tick"), "belt")
	assert_almost_eq(float(_event("arc", "arc_zap_over")["when"]["min"]), 0.3, 0.001)
	assert_almost_eq(float(_event("arc", "arc_zap")["when"]["min"]), 0.12, 0.001)


func test_the_feed_fires_when_its_bolts_come_home() -> void:
	# tank_mech.gd: u = fposmod(ph - 0.5 * k, 1), the shot at u = 0, for k 0 and 1.
	_assert_art_says("fposmod(ph - 0.5 * ")
	assert_eq(_fractions("feed", "bolt_clack"), [0.0, 0.5])
	assert_eq(_fractions("feed", "bow_shot"), [0.0, 0.5])
	assert_eq(_fractions("feed", "link_clink"), [0.25, 0.75])
	assert_eq(_fractions("feed", "casing_tink"), [0.2, 0.7])


func test_the_rivet_hammer_strikes_where_it_comes_down_on_the_plate() -> void:
	# The fraction read from the art itself: TankMech.hammer_lift is 0 on the plate, at the top just before the fall.
	assert_eq(_fractions("repair", "rivet_hit"), [0.0])
	assert_almost_eq(TankMech.hammer_lift(0.0), 0.0, 1e-6, "down at the strike")
	assert_almost_eq(TankMech.hammer_lift(1.0), 0.0, 1e-6, "every whole revolution")
	assert_almost_eq(TankMech.hammer_lift(0.9999), 0.0, 0.01, "the fall ends just there")
	assert_gt(TankMech.hammer_lift(0.8), 0.9, "up before the fall")
	var lowest := INF
	var lowest_at := -1.0
	for i in 720:
		var f := float(i) / 720.0
		if TankMech.hammer_lift(f) < lowest:
			lowest = TankMech.hammer_lift(f)
			lowest_at = f
	assert_almost_eq(lowest_at, float(_fractions("repair", "rivet_hit")[0]), 1.0 / 720.0)
	assert_lt(
		float(_fractions("repair", "rivet_ring")[0]), TankMech.R_SPARK, "rings under the sparks"
	)


func _variants(sound: String) -> int:
	return int(_bank.sounds[sound].get("variants", 1))


func test_every_pitch_table_is_coprime_with_its_variants_and_small() -> void:
	var tables := 0
	for id: String in _bank.machines:
		for ev: Dictionary in _bank.machines[id]["events"]:
			var table: Array = ev.get("pitch_table", [])
			if table.is_empty():
				continue
			tables += 1
			var a := table.size()
			var b := _variants(str(ev["sound"]))
			while b != 0:
				var r := a % b
				a = b
				b = r
			assert_eq(a, 1, "%s: the table and the variants never fall in step" % str(ev["sound"]))
			for v: Variant in table:
				assert_lte(absf(float(v)), 0.015, str(ev["sound"]))
	assert_gte(tables, 12, "each seat's strokes vary")


func test_the_diesel_has_no_short_bar_to_repeat() -> void:
	# 5 takes against 4 and 7 table entries: 20 and 35 revolutions before any one cylinder repeats.
	for sound: String in ["diesel_fire_a", "diesel_fire_b", "diesel_fire_c"]:
		assert_eq(_variants(sound), 5, sound)
	assert_eq((_event("diesel", "diesel_fire_a")["pitch_table"] as Array).size(), 4)
	assert_eq((_event("diesel", "diesel_fire_b")["pitch_table"] as Array).size(), 7)
	assert_eq((_event("diesel", "diesel_fire_c")["pitch_table"] as Array).size(), 7)
	assert_eq(_variants("diesel_fire_hard"), 4, "the overlay never falls in step with 3 cylinders")


func test_a_loops_slow_movement_runs_with_the_machines_own_rhythm() -> void:
	# Rates are at pitch 1. diesel_rasp plays at rpm / 90: three firings a revolution at 90 rpm is 4.5 Hz.
	var rasp: Dictionary = _bank.sounds["diesel_rasp"]
	var dur := float(rasp["dur"])
	var trems: Array[float] = []
	for layer: Dictionary in rasp["layers"]:
		for fx: Dictionary in layer.get("fx", []):
			if fx.has("trem"):
				trems.append(float(fx["trem"]["hz"]))
	assert_eq(trems, [4.5, 9.0] as Array[float])
	for hz in trems:
		assert_almost_eq(fposmod(hz * dur + 0.01, 1.0), 0.01, 0.02, "whole cycles in the loop")
	# dynamo_whine plays at rpm / 90 too: 27 Hz is 18 ripples per revolution, 0.75 Hz one swell per 2 revolutions.
	var whine: Dictionary = _bank.sounds["dynamo_whine"]
	assert_almost_eq(fposmod(27.0 * float(whine["dur"]), 1.0), 0.0, 0.001)
	assert_almost_eq(fposmod(0.75 * float(whine["dur"]), 1.0), 0.0, 0.001)


func test_what_a_full_crew_thins_first_is_only_the_leads_anyway() -> void:
	# Thinning is first come, not by priority, so the bank cuts the ask: these never go through it.
	for pair: Array in [["diesel", "diesel_fire_hard"], ["feed", "bolt_clack"]]:
		assert_true(bool(_event(pair[0], pair[1]).get("lead_only", false)), str(pair[1]))


func test_a_cricket_train_holds_its_pitch_and_place() -> void:
	# The kit re-rolls pitch and walks the variants per burst entry, so a train is baked into one file.
	var cricket: Dictionary = {}
	for spot: Dictionary in _bank.beds["night_forest"]["spots"]:
		if str(spot["sound"]) == "cricket":
			cricket = spot
	assert_false(cricket.has("burst"), "no burst: that would hop across the stereo field")
	assert_eq((_bank.sounds["cricket"]["layers"] as Array).size(), 3, "three chirps a file")
	assert_eq(_variants("cricket"), 5)


func test_the_bed_has_three_layers_that_do_not_share_a_period() -> void:
	var lengths: Array[float] = []
	for layer: Dictionary in _bank.beds["night_forest"]["layers"]:
		lengths.append(float(_bank.sounds[layer["sound"]]["dur"]))
	lengths.sort()
	assert_eq(lengths, [5.0, 11.0, 13.0] as Array[float], "they meet again after 715 s")


func test_a_small_explosion_takes_the_adapters_counter() -> void:
	var hit: Dictionary = _bank.cues["kill_near"]["hits"][0]
	assert_eq(str(hit["pitch_var"]), "small_pitch")
	assert_eq(TankAudio.SMALL_PITCHES.size(), 5)


func test_every_stroke_is_locked_pcm_and_mono() -> void:
	for id: String in _bank.machines:
		for ev: Dictionary in _bank.machines[id]["events"]:
			var sound: Dictionary = _bank.sounds[ev["sound"]]
			assert_true(bool(sound.get("locked", false)), str(ev["sound"]))
			assert_eq(int(sound["ch"]), 1, str(ev["sound"]))


func test_nothing_locked_above_two_kilohertz_outshouts_its_machine() -> void:
	# SPEC_AUDIO 5, fatigue: an hour of a 110 rpm tick must stay a texture.
	var ticks := {
		"dynamo": ["brush_tick"],
		"arc": ["belt_tick"],
		"feed": ["link_clink", "casing_tink"],
	}
	for machine: String in ticks:
		var top := -INF
		for ev: Dictionary in _bank.machines[machine]["events"]:
			top = maxf(top, float(ev["db"]))
		for id: String in ticks[machine]:
			assert_lte(float(_event(machine, id)["db"]), top - 16.0, id)


func test_the_bed_has_no_battle_in_the_depot_by_its_gate() -> void:
	var gated := false
	for spot: Dictionary in _bank.beds["night_forest"]["spots"]:
		if str(spot["sound"]) == "far_battle":
			gated = str(spot["when"]["param"]) == "combat"
	assert_true(gated)
