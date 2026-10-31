extends GutTest
## SPEC_AUDIO 5, row 1: a `warning` or `rescue` that is playing is never stolen by a later Sfx.play, however busy the
## pool (a game's effects still go through it). Looping streams keep every player busy, also on the Dummy driver.

const BUSY := "busy_loop"

var _sfx: WlSfx = null
var _busy: AudioStream = null
var _prompt: AudioStream = null


func before_each() -> void:
	_sfx = WlSfx.new()
	add_child_autofree(_sfx)
	_sfx.set_process(false)
	_busy = _sfx.synth("sine", 200.0, 1.0, 0.005, 0.05, true)
	_prompt = _sfx.synth("sine", 900.0, 1.0, 0.005, 0.05, true)
	_sfx.register(BUSY, _busy)
	_sfx.register("warning", _prompt)
	_sfx.register("rescue", _prompt)


func after_each() -> void:
	_sfx.stop_all()


func _playing_prompts() -> int:
	var n := 0
	for c in _sfx.get_children():
		var p := c as AudioStreamPlayer
		if p.playing and p.stream == _prompt and str(p.bus) == AudioBuses.MASTER:
			n += 1
	return n


func test_a_playing_warning_survives_a_full_pool() -> void:
	_sfx.play("warning")
	for i in WlSfx.POOL_SIZE - 1:
		_sfx.play(BUSY)
	assert_eq(_sfx.get_child_count(), WlSfx.POOL_SIZE, "precondition: all eight are busy")
	for c in _sfx.get_children():
		assert_true((c as AudioStreamPlayer).playing, "precondition: all eight are busy")
	assert_eq(_playing_prompts(), 1)
	for i in WlSfx.POOL_SIZE * 3:
		_sfx.play(BUSY)
		assert_eq(_playing_prompts(), 1, "the next play takes another player, %d" % i)
	assert_eq(_sfx.get_child_count(), WlSfx.POOL_SIZE, "the pool stays bounded")


func test_a_playing_rescue_survives_a_full_pool() -> void:
	for i in WlSfx.POOL_SIZE - 1:
		_sfx.play(BUSY)
	_sfx.play("rescue")
	for i in WlSfx.POOL_SIZE * 3:
		_sfx.play(BUSY)
	assert_eq(_playing_prompts(), 1)


func test_a_new_prompt_takes_an_ordinary_player_in_a_full_pool() -> void:
	for i in WlSfx.POOL_SIZE:
		_sfx.play(BUSY)
	_sfx.play("warning")
	assert_eq(_playing_prompts(), 1)
	assert_eq(_sfx.get_child_count(), WlSfx.POOL_SIZE)


func test_when_all_eight_hold_prompts() -> void:
	for i in WlSfx.POOL_SIZE:
		_sfx.play("rescue")
	assert_eq(_playing_prompts(), WlSfx.POOL_SIZE)
	_sfx.play(BUSY)
	assert_eq(_playing_prompts(), WlSfx.POOL_SIZE, "an effect gets no player")
	assert_eq(_sfx.get_child_count(), WlSfx.POOL_SIZE)
	assert_eq(_sfx.last_played, BUSY, "the play still counts")
	_sfx.play("warning")
	assert_eq(_playing_prompts(), WlSfx.POOL_SIZE + 1, "a prompt always sounds")
	assert_eq(_sfx.get_child_count(), WlSfx.POOL_SIZE + 1)


# --- the UI cannot cover a prompt: its voices step back with the ducks, and come back ---


func _ui_sfx() -> WlSfx:
	var sfx := WlSfx.new()
	add_child_autofree(sfx)
	sfx.set_process(false)
	return sfx


func test_a_prompt_trims_the_ui_voices_playing_and_starting_and_they_come_back() -> void:
	var sfx := _ui_sfx()
	sfx.play("phase", -4.0)
	var before := sfx.get_child(0) as AudioStreamPlayer
	assert_eq(str(before.bus), AudioBuses.UI)
	assert_eq(before.volume_db, -4.0, "no prompt, no trim")
	sfx.play("warning", -4.0)
	var prompt := sfx.get_child(1) as AudioStreamPlayer
	sfx.tick(WlSfx.SAFETY_DUCK_ATTACK_S)
	assert_almost_eq(
		before.volume_db, -4.0 + WlSfx.SAFETY_UI_DB, 0.01, "one on the way out steps back"
	)
	assert_eq(prompt.volume_db, -4.0, "the prompt is not trimmed")
	sfx.play("toast", -4.0)
	var after := sfx.get_child(2) as AudioStreamPlayer
	assert_almost_eq(
		after.volume_db, -4.0 + WlSfx.SAFETY_UI_DB, 0.01, "so does one that starts under it"
	)
	sfx.tick(WlSfx.SAFETY_DUCK_RELEASE_S / 2.0)
	assert_almost_eq(
		after.volume_db, -4.0 + WlSfx.SAFETY_UI_DB / 2.0, 0.01, "on the ducks' release"
	)
	sfx.tick(WlSfx.SAFETY_DUCK_RELEASE_S)
	assert_eq(after.volume_db, -4.0, "and back")
	assert_eq(sfx.prompt_ui_db(), 0.0)
	sfx.stop_all()


func test_rescue_trims_them_too() -> void:
	var sfx := _ui_sfx()
	sfx.play("rescue")
	sfx.tick(WlSfx.SAFETY_DUCK_ATTACK_S)
	assert_almost_eq(sfx.prompt_ui_db(), WlSfx.SAFETY_UI_DB, 0.01)
	sfx.stop_all()


func test_the_start_count_and_the_metronome_keep_their_level_under_a_prompt() -> void:
	var sfx := _ui_sfx()
	sfx.play("countdown", -4.0)
	sfx.play("warning", -4.0)
	sfx.tick(WlSfx.SAFETY_DUCK_ATTACK_S)
	sfx.play("click", -8.0)
	assert_eq((sfx.get_child(0) as AudioStreamPlayer).volume_db, -4.0, "countdown")
	assert_eq((sfx.get_child(2) as AudioStreamPlayer).volume_db, -8.0, "metronome")
	sfx.stop_all()


func test_a_game_effect_is_left_to_the_bus_duck() -> void:
	var sfx := _ui_sfx()
	sfx.play("coin", -3.0)
	sfx.play("warning", -4.0)
	sfx.tick(WlSfx.SAFETY_DUCK_ATTACK_S)
	assert_eq((sfx.get_child(0) as AudioStreamPlayer).volume_db, -3.0, "Sfx: the bus takes it down")
	sfx.stop_all()


func test_a_player_reused_for_another_sound_holds_no_old_level() -> void:
	var sfx := _ui_sfx()
	sfx.play("phase", -4.0)
	var p := sfx.get_child(0) as AudioStreamPlayer
	p.stop()
	sfx.play("coin", -3.0)
	assert_eq(sfx.get_child(0), p, "the free player")
	sfx.play("warning", -4.0)
	sfx.tick(WlSfx.SAFETY_DUCK_ATTACK_S)
	assert_eq(p.volume_db, -3.0)
	sfx.stop_all()
