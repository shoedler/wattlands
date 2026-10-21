extends GutTest
## WlSfx and SfxSynth (BRIEF 3.9 audio; docs/OWNERSHIP.md AU1-AU2): every built-in effect is
## synthesized and plays headless without errors, games register and synthesize their own
## clips (looping ones included), bad input is rejected, and the cadence metronome clicks
## once per pedal stroke.

var _sfx: WlSfx = null


func before_each() -> void:
	_sfx = WlSfx.new()
	add_child_autofree(_sfx)
	_sfx.set_process(false)


func test_runs_always() -> void:
	assert_eq(_sfx.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_every_builtin_exists_and_is_not_silent() -> void:
	assert_eq(WlSfx.BUILTIN_NAMES.size(), 15)
	for sound: String in WlSfx.BUILTIN_NAMES:
		assert_true(_sfx.has_sound(sound), sound)
		var s := _sfx.get_stream(sound) as AudioStreamWAV
		assert_not_null(s, sound)
		if s == null:
			continue
		assert_eq(s.format, AudioStreamWAV.FORMAT_16_BITS, sound)
		assert_eq(s.mix_rate, SfxSynth.MIX_RATE, sound)
		assert_false(s.stereo, sound)
		assert_between(SfxSynth.length_s(s), 0.005, 1.5, sound + " length")
		assert_gt(SfxSynth.peak(s), 0.05, sound + " is audible")
		assert_lte(SfxSynth.peak(s), 1.0, sound + " doesn't clip")


func test_builtins_are_cached() -> void:
	assert_same(_sfx.get_stream("coin"), _sfx.get_stream("coin"))


func test_play_every_builtin_headless() -> void:
	for sound: String in WlSfx.BUILTIN_NAMES:
		_sfx.play(sound, -6.0, 1.1)
	assert_eq(_sfx.play_count, WlSfx.BUILTIN_NAMES.size())
	assert_eq(_sfx.last_played, "click")
	assert_lte(_sfx.get_child_count(), WlSfx.POOL_SIZE, "a bounded player pool")


func test_play_unknown_warns_once() -> void:
	_sfx.play("does_not_exist")
	_sfx.play("does_not_exist")
	assert_push_warning("unknown sound")
	assert_eq(_sfx.play_count, 0)
	assert_false(_sfx.has_sound("does_not_exist"))


func test_register_and_replace() -> void:
	var s := _sfx.synth("saw", 220.0, 0.2)
	_sfx.register("reel_click", s)
	assert_true(_sfx.has_sound("reel_click"))
	assert_same(_sfx.get_stream("reel_click"), s)
	_sfx.play("reel_click")
	assert_eq(_sfx.last_played, "reel_click")
	var mine := _sfx.synth("sine", 100.0, 0.1)
	_sfx.register("boom", mine)
	assert_same(_sfx.get_stream("boom"), mine, "a game may replace a built-in")


func test_register_rejects_bad_input() -> void:
	_sfx.register("", AudioStreamWAV.new())
	assert_push_error("register needs")
	_sfx.register("x", null)
	assert_push_error("register needs")
	assert_false(_sfx.has_sound("x"))


func test_synth_kinds_and_lengths() -> void:
	for kind: String in ["sine", "square", "saw", "noise", "triangle"]:
		var s := _sfx.synth(kind, 440.0, 0.25, 0.01, 0.05) as AudioStreamWAV
		assert_not_null(s, kind)
		assert_almost_eq(SfxSynth.length_s(s), 0.25, 0.001, kind)
		assert_gt(SfxSynth.peak(s), 0.1, kind)
		assert_eq(s.loop_mode, AudioStreamWAV.LOOP_DISABLED, kind)


func test_synth_loop() -> void:
	var s := _sfx.synth("square", 55.0, 0.5, 0.0, 0.0, true) as AudioStreamWAV
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(s.loop_begin, 0)
	assert_eq(s.loop_end, s.data.size() / 2)


func test_synth_rejects_bad_input() -> void:
	assert_null(_sfx.synth("kazoo", 440.0, 0.2))
	assert_push_error("unknown synth kind")
	assert_null(_sfx.synth("sine", 440.0, 0.0))
	assert_push_error("out of range")


func test_synth_is_deterministic() -> void:
	var a := SfxSynth.tone("noise", 0.0, 0.1)
	var b := SfxSynth.tone("noise", 0.0, 0.1)
	assert_eq(a.data, b.data)


func test_envelope_starts_and_ends_quietly() -> void:
	var samples := SfxSynth.render("square", 440.0, 0.2, 0.01, 0.05, 0.6)
	assert_almost_eq(samples[0], 0.0, 0.001, "attack starts at 0")
	assert_almost_eq(samples[samples.size() - 1], 0.0, 0.001, "release ends at 0")
	var mid := absf(samples[samples.size() / 2])
	assert_almost_eq(mid, 0.6, 0.001, "full gain in the middle")


func test_sweep_changes_pitch() -> void:
	var flat := SfxSynth.render("sine", 400.0, 0.2, 0.0, 0.0)
	var swept := SfxSynth.render("sine", 400.0, 0.2, 0.0, 0.0, 0.6, 800.0)
	assert_ne(flat, swept)


func test_metronome_clicks_once_per_stroke() -> void:
	_sfx.set_metronome(90.0, true)
	assert_true(_sfx.metronome_on())
	assert_eq(_sfx.metronome_rpm(), 90.0)
	for _i in 200:
		_sfx.tick(0.05)
	assert_eq(_sfx.metronome_clicks(), 15, "90 rpm for 10 s")
	assert_eq(_sfx.last_played, WlSfx.METRONOME_SOUND)


func test_metronome_rate_change_and_off() -> void:
	_sfx.set_metronome(60.0, true)
	_sfx.tick(2.0)
	assert_eq(_sfx.metronome_clicks(), 2)
	_sfx.set_metronome(120.0, true)
	_sfx.tick(1.0)
	assert_eq(_sfx.metronome_clicks(), 4)
	_sfx.set_metronome(120.0, false)
	_sfx.tick(5.0)
	assert_eq(_sfx.metronome_clicks(), 4, "off")
	_sfx.set_metronome(0.0, true)
	assert_false(_sfx.metronome_on(), "rpm <= 0 stops it")
	_sfx.tick(5.0)
	assert_eq(_sfx.metronome_clicks(), 4)


## The session screen and the GameHost both call it (OWNERSHIP AU2): a repeated call is a no-op.
func test_set_metronome_is_idempotent() -> void:
	_sfx.set_metronome(60.0, true)
	_sfx.tick(0.6)
	for _i in 5:
		_sfx.set_metronome(60.0, true)
	assert_eq(_sfx.metronome_clicks(), 0, "no click from repeated calls")
	_sfx.tick(0.4)
	assert_eq(
		_sfx.metronome_clicks(), 1, "the stroke phase kept running: a click 1 s after the start"
	)
	_sfx.set_metronome(0.0, false)
	_sfx.set_metronome(0.0, false)
	assert_false(_sfx.metronome_on())
	_sfx.tick(3.0)
	assert_eq(_sfx.metronome_clicks(), 1)


func test_muted_counts_without_players() -> void:
	_sfx.muted = true
	_sfx.play("toast")
	assert_eq(_sfx.play_count, 1)
	assert_eq(_sfx.get_child_count(), 0)


func test_stop_all() -> void:
	_sfx.play("results")
	_sfx.stop_all()
	for c in _sfx.get_children():
		assert_false((c as AudioStreamPlayer).playing)


func test_autoload_is_wlsfx() -> void:
	var autoload := get_tree().root.get_node_or_null("Sfx")
	assert_true(autoload is WlSfx)
