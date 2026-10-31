extends GutTest
## The tank's bank against the game: every sound imported as its manifest says, every event mapped, and every stroke's
## fraction against the formula that draws its machine (SPEC_AUDIO 2.3, 2.6). If an art formula moves, this says so.

const BANK := "res://assets/tank/audio/audio.json"
const MANIFEST := "res://assets/tank/audio/audio_manifest.json"
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


func test_the_bank_loads_and_every_seat_has_its_machine() -> void:
	assert_not_null(_bank)
	assert_eq(AudioBank.validate(JSON.parse_string(FileAccess.get_file_as_string(BANK))).size(), 0)
	for seat: String in TankRig.SEATS:
		assert_true(TankKitAudio.MACHINE_OF_SEAT.has(seat), seat)
		assert_true(_bank.machines.has(TankKitAudio.MACHINE_OF_SEAT[seat]), seat)
	assert_true(_bank.machines.has(TankKitAudio.TRACK))
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
		var mapped := TankKitAudio.EVENT_CUES.has(kind)
		var silent := kind in TankKitAudio.SILENT_EVENTS
		assert_true(mapped != silent, "%s: one of a cue or SILENT_EVENTS" % kind)


func test_every_mapped_cue_exists_and_no_cue_is_an_orphan() -> void:
	var reached: Array[String] = TankKitAudio.STATE_CUES.duplicate()
	for kind: String in TankKitAudio.EVENT_CUES:
		for id: String in TankKitAudio.EVENT_CUES[kind]:
			assert_true(_bank.cues.has(id), id)
			reached.append(id)
	for id: String in TankKitAudio.STATE_CUES:
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
	assert_eq(_fractions("dynamo", "cap_dump"), [0.8])
	assert_almost_eq(float(_event("dynamo", "cap_dump")["when"]["min"]), 1.15 * 0.4, 0.001)
	# The ring's teeth: fposmod(ph * 3, 1).
	var teeth := func(ph: float) -> float: return fposmod(ph * 3.0, 1.0)
	_assert_wraps_at(teeth, _fractions("dynamo", "brush_tick"), "brush")


func test_the_steam_engine_chuffs_at_each_end_of_its_stroke() -> void:
	# tank_mech.gd: stroke = fposmod(ph * 2, 1).
	var stroke := func(ph: float) -> float: return fposmod(ph * 2.0, 1.0)
	var chuffs: Array = []
	chuffs.append_array(_fractions("steam", "chuff_a"))
	chuffs.append_array(_fractions("steam", "chuff_b"))
	chuffs.sort()
	_assert_wraps_at(stroke, chuffs, "chuff")


func test_the_arc_zaps_as_it_starts_up_the_ladder() -> void:
	# tank_mech.gd: climb = fposmod(ph * 2 + ai * 0.5, 1), a second arc over 0.3; the belt: fposmod(ph * 12, 3).
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
	assert_eq(_fractions("feed", "bolt_clack"), [0.0, 0.5])
	assert_eq(_fractions("feed", "bow_shot"), [0.0, 0.5])
	assert_eq(_fractions("feed", "link_clink"), [0.25, 0.75])
	assert_eq(_fractions("feed", "casing_tink"), [0.2, 0.7])


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
