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
