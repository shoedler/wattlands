extends GutTest
## The audio generator's files through Godot's real importer (SPEC_AUDIO 3.4): the .wav.import skeleton
## it writes is honoured (format, loop mode, loop points), a locked file keeps its pre-roll, and every
## platform UI sound in assets/_shared/audio imports as 16-bit, mono, 22050 Hz. Each proof file is
## written by `node tools/audio/generate.mjs --bank=tests/audio/fixtures/import_proof_bank.json`.

const FIXTURES := "res://tests/audio/fixtures/"
const SHARED := "res://assets/_shared/audio/"
const PREROLL_S := 0.08
const MANIFEST := FIXTURES + "import_proof_bank_manifest.json"


func _wav(path: String) -> AudioStreamWAV:
	var s := load(path) as AudioStreamWAV
	assert_not_null(s, path)
	return s


func _sidecar(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(path + ".import"), OK, path + ".import")
	return cfg


func _manifest() -> Dictionary:
	var f := FileAccess.get_file_as_string(MANIFEST)
	var doc: Variant = JSON.parse_string(f)
	assert_true(doc is Dictionary, MANIFEST)
	return doc if doc is Dictionary else {}


func test_pcm_loop_keeps_format_and_loop_mode() -> void:
	var s := _wav(FIXTURES + "import_proof_loop.wav")
	if s == null:
		return
	assert_eq(s.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(s.mix_rate, 22050)
	assert_false(s.stereo)
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD)


func test_pcm_loop_period_is_exact_and_lands_on_the_guard_frame() -> void:
	var s := _wav(FIXTURES + "import_proof_loop.wav")
	if s == null:
		return
	var e: Dictionary = _manifest().get("import_proof_loop", {})
	var frames := s.data.size() / 2
	assert_eq(frames, int(e.get("frames", -1)), "the importer kept every frame")
	assert_eq(s.loop_begin, 0)
	assert_eq(
		s.loop_end, int(e.get("loop_frames", -1)), "edit/loop_end = -1 is frames - 1, the period"
	)
	assert_eq(
		s.data.decode_s16(s.loop_end * 2),
		s.data.decode_s16(0),
		"the frame after the loop is frame 0, so the resampler's read past the end is right"
	)


func test_qoa_loop_keeps_format_stereo_and_loop_mode() -> void:
	var s := _wav(FIXTURES + "import_proof_qoa.wav")
	if s == null:
		return
	assert_eq(s.format, AudioStreamWAV.FORMAT_QOA)
	assert_eq(s.mix_rate, 22050)
	assert_true(s.stereo)
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	var e: Dictionary = _manifest().get("import_proof_qoa", {})
	assert_eq(s.loop_end, int(e.get("loop_frames", -1)))
	assert_almost_eq(s.get_length(), float(e.get("frames", 0)) / 22050.0, 0.001)
	assert_lt(s.data.size(), int(e.get("bytes", 0)), "QOA is smaller than the WAV")


func test_locked_file_keeps_its_preroll() -> void:
	var s := _wav(FIXTURES + "import_proof_locked.wav")
	if s == null:
		return
	assert_eq(s.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	var e: Dictionary = _manifest().get("import_proof_locked", {})
	assert_eq(s.data.size() / 2, int(e.get("frames", -1)), "edit/trim did not cut the silence")
	var preroll := roundi(PREROLL_S * s.mix_rate)
	assert_eq(int(e.get("preroll", -1)), preroll)
	var loudest := 0
	for i in preroll:
		loudest = maxi(loudest, absi(s.data.decode_s16(i * 2)))
	assert_eq(loudest, 0, "80 ms of silence before the attack")
	var attack := 0
	for i in range(preroll, s.data.size() / 2):
		attack = maxi(attack, absi(s.data.decode_s16(i * 2)))
	assert_gt(attack, 3000, "the stroke itself is there")


func test_sidecars_hold_the_generator_params() -> void:
	var cases := {
		"import_proof_loop": [2, 0],
		"import_proof_qoa": [2, 2],
		"import_proof_locked": [1, 0],
	}
	for sound: String in cases:
		var want: Array = cases[sound]
		var cfg := _sidecar(FIXTURES + sound + ".wav")
		assert_eq(cfg.get_value("params", "edit/trim"), false, sound)
		assert_eq(cfg.get_value("params", "edit/normalize"), false, sound)
		assert_eq(cfg.get_value("params", "edit/loop_mode"), want[0], sound)
		assert_eq(cfg.get_value("params", "compress/mode"), want[1], sound)
		assert_eq(cfg.get_value("remap", "importer"), "wav", sound)
		assert_true(
			str(cfg.get_value("remap", "uid", "")).begins_with("uid://"), sound + " has a uid"
		)


func test_every_shared_ui_sound_imports_as_16_bit_mono_22050() -> void:
	assert_eq(WlSfx.BUILTIN_NAMES.size(), 15)
	for sound: String in WlSfx.BUILTIN_NAMES:
		var path := SHARED + sound + ".wav"
		assert_true(ResourceLoader.exists(path), path)
		var s := _wav(path)
		if s == null:
			continue
		assert_eq(s.format, AudioStreamWAV.FORMAT_16_BITS, sound)
		assert_eq(s.mix_rate, 22050, sound)
		assert_false(s.stereo, sound)
		assert_eq(s.loop_mode, AudioStreamWAV.LOOP_DISABLED, sound)
		assert_between(SfxSynth.length_s(s), 0.005, 1.5, sound + " length")
		assert_gt(SfxSynth.peak(s), 0.05, sound + " is audible")
		assert_lte(SfxSynth.peak(s), 1.0, sound + " doesn't clip")
		assert_eq(_sidecar(path).get_value("params", "edit/trim"), false, sound)
