extends GutTest
## AudioBuses and the kit's platform edges (SPEC_AUDIO 1.4): buses in code, the Master limiter, ducks, the user's
## levels, WlSfx's routing of a safety prompt to Master, and the Settings rows.

const AppFixture := preload("res://tests/app/fakes/app_fixture.gd")
const MainScene := preload("res://src/app/main.gd")


func before_each() -> void:
	AudioBuses.ensure()
	AudioBuses.clear_ducks()
	for bus: String in AudioBuses.ALL:
		AudioBuses.set_user_db(bus, 0.0)


func after_each() -> void:
	AudioBuses.clear_ducks()
	for bus: String in AudioBuses.ALL:
		AudioBuses.set_user_db(bus, 0.0)


func _limiters() -> int:
	var master := AudioServer.get_bus_index(AudioBuses.MASTER)
	var n := 0
	for e in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, e) is AudioEffectHardLimiter:
			n += 1
	return n


func test_ensure_is_idempotent() -> void:
	var count := AudioServer.bus_count
	AudioBuses.ensure()
	AudioBuses.ensure()
	assert_eq(AudioServer.bus_count, count)
	assert_eq(_limiters(), 1)
	for bus: String in AudioBuses.ALL:
		var i := AudioServer.get_bus_index(bus)
		assert_gt(i, 0, bus)
		assert_eq(AudioServer.get_bus_send(i), StringName(AudioBuses.MASTER), bus)


func test_limiter_ceiling() -> void:
	var master := AudioServer.get_bus_index(AudioBuses.MASTER)
	for e in AudioServer.get_bus_effect_count(master):
		var fx := AudioServer.get_bus_effect(master, e) as AudioEffectHardLimiter
		if fx != null:
			assert_eq(fx.ceiling_db, AudioBuses.LIMITER_CEILING_DB)


func test_the_master_bus_stays_bus_zero() -> void:
	assert_eq(AudioServer.get_bus_index(AudioBuses.MASTER), 0, "AppSettingsScreen writes bus 0")


func test_user_db_sets_the_bus() -> void:
	AudioBuses.set_user_db(AudioBuses.SFX, -9.0)
	assert_eq(AudioBuses.user_db(AudioBuses.SFX), -9.0)
	var i := AudioServer.get_bus_index(AudioBuses.SFX)
	assert_almost_eq(AudioServer.get_bus_volume_db(i), -9.0, 0.001)


func test_duck_envelope_attack_and_release() -> void:
	AudioBuses.duck(AudioBuses.MACHINES, -6.0, 0.1, 1.0)
	AudioBuses.tick(0.05)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -3.0, 0.001, "half way down")
	AudioBuses.tick(0.05)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -6.0, 0.001, "full depth")
	AudioBuses.tick(0.5)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -3.0, 0.001, "half way back")
	AudioBuses.tick(0.6)
	assert_eq(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0, "over")


func test_deepest_duck_wins_and_user_level_stays_apart() -> void:
	AudioBuses.set_user_db(AudioBuses.AMBIENCE, -3.0)
	AudioBuses.duck(AudioBuses.AMBIENCE, -4.0, 0.0, 10.0)
	AudioBuses.duck(AudioBuses.AMBIENCE, -9.0, 0.0, 10.0)
	AudioBuses.tick(0.0001)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.AMBIENCE), -9.0, 0.01)
	var i := AudioServer.get_bus_index(AudioBuses.AMBIENCE)
	assert_almost_eq(AudioServer.get_bus_volume_db(i), -12.0, 0.01)
	assert_eq(AudioBuses.user_db(AudioBuses.AMBIENCE), -3.0)


func test_master_and_ui_are_never_ducked() -> void:
	AudioBuses.duck(AudioBuses.MASTER, -6.0, 0.0, 1.0)
	assert_push_warning("never ducked")
	AudioBuses.duck(AudioBuses.UI, -6.0, 0.0, 1.0)
	assert_push_warning("never ducked")
	AudioBuses.tick(0.1)
	assert_eq(AudioBuses.duck_db(AudioBuses.MASTER), 0.0)
	assert_eq(AudioBuses.duck_db(AudioBuses.UI), 0.0)


func _sfx() -> WlSfx:
	var sfx := WlSfx.new()
	add_child_autofree(sfx)
	sfx.set_process(false)
	return sfx


func _last_bus(sfx: WlSfx) -> String:
	var p := sfx.get_child(sfx.get_child_count() - 1) as AudioStreamPlayer
	return str(p.bus)


func test_sfx_routes_a_safety_prompt_to_master() -> void:
	for sound: String in ["warning", "rescue"]:
		var sfx := _sfx()
		sfx.play(sound)
		assert_eq(sfx.bus_of(sound), AudioBuses.MASTER, sound)
		assert_eq(_last_bus(sfx), AudioBuses.MASTER, sound)


func test_sfx_routes_the_rest() -> void:
	var sfx := _sfx()
	for sound: String in ["coin", "hit", "boom", "whoosh"]:
		assert_eq(sfx.bus_of(sound), AudioBuses.SFX, sound)
	for sound: String in ["ui_move", "ui_confirm", "ui_back", "toast", "phase", "countdown"]:
		assert_eq(sfx.bus_of(sound), AudioBuses.UI, sound)
	for sound: String in ["lap", "results", "click"]:
		assert_eq(sfx.bus_of(sound), AudioBuses.UI, sound)
	sfx.register("reel", sfx.synth("sine", 200.0, 0.1))
	assert_eq(sfx.bus_of("reel"), AudioBuses.SFX, "a registered sound")
	sfx.play("reel")
	assert_eq(_last_bus(sfx), AudioBuses.SFX)
	sfx.register("warning", sfx.synth("sine", 200.0, 0.1))
	assert_eq(sfx.bus_of("warning"), AudioBuses.MASTER, "a game's own warning stays on Master")
	sfx.register("click", sfx.synth("sine", 200.0, 0.1))
	assert_eq(sfx.bus_of("click"), AudioBuses.UI, "the metronome stays on UI")


func test_sfx_warning_ducks_the_rest_not_ui() -> void:
	var sfx := _sfx()
	sfx.play("warning")
	AudioBuses.tick(0.02)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.MACHINES), -14.0, 0.01)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.AMBIENCE), -14.0, 0.01)
	assert_almost_eq(AudioBuses.duck_db(AudioBuses.SFX), -20.0, 0.01)
	assert_eq(AudioBuses.duck_db(AudioBuses.UI), 0.0)
	assert_eq(AudioBuses.duck_db(AudioBuses.MASTER), 0.0)


func test_sfx_muted_warning_does_not_duck() -> void:
	var sfx := _sfx()
	sfx.muted = true
	sfx.play("rescue")
	AudioBuses.tick(0.02)
	assert_eq(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0)


func test_sfx_other_sounds_do_not_duck() -> void:
	var sfx := _sfx()
	sfx.play("boom")
	AudioBuses.tick(0.02)
	assert_eq(AudioBuses.duck_db(AudioBuses.MACHINES), 0.0)


func test_setting_defaults_exist() -> void:
	for bus: String in AudioBuses.ALL:
		assert_eq(WlSettings.DEFAULTS[AudioBuses.SETTING_KEYS[bus]], 0.0, bus)


func test_settings_page_has_a_row_per_bus_that_applies_at_once() -> void:
	var fx := AppFixture.new()
	var s := AppSettingsScreen.new()
	s.services = fx.services
	add_child_autofree(s)
	var ids: Array[String] = []
	var fields := s.audio_fields()
	for f: Dictionary in fields:
		ids.append(str(f["id"]))
	assert_eq(ids.slice(0, 5), ["volume", "vol_machines", "vol_ambience", "vol_sfx", "vol_ui"])
	var row: Dictionary = fields[1]
	assert_eq(row["min"], -30.0)
	assert_eq(row["max"], 0.0)
	assert_eq(row["step"], 3.0)
	assert_eq(row["unit"], "dB")
	assert_ne(str(row["label"]), "APP_SET_VOL_MACHINES", "the string exists")
	(row["set"] as Callable).call(-12.0)
	assert_eq((row["get"] as Callable).call(), -12.0)
	assert_eq(float(fx.settings.get_value("bus_machines_db", 0.0)), -12.0, "saved")
	var i := AudioServer.get_bus_index(AudioBuses.MACHINES)
	assert_almost_eq(AudioServer.get_bus_volume_db(i), -12.0, 0.001, "applied")
	s.leave()
	remove_child(s)
	s.queue_free()
	fx.free_all()


func test_boot_applies_the_saved_levels() -> void:
	var fx := AppFixture.new()
	fx.give_profile()
	fx.settings.set_value("bus_sfx_db", -6.0)
	var before := AudioServer.get_bus_volume_db(0)
	var m: Control = MainScene.new()
	m.set("services", fx.services)
	m.set("screens_auto_process", false)
	m.set("scripted_config", AppScriptedConfig.new())
	add_child(m)
	assert_eq(AudioBuses.user_db(AudioBuses.SFX), -6.0)
	AudioServer.set_bus_volume_db(0, before)
	remove_child(m)
	m.free()
	fx.free_all()
