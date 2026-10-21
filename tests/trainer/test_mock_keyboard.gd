extends GutTest
## MockTrainer keyboard control (BRIEF 4.2: W and S +-10 W, A and D cadence), W2r2: off unless
## enabled (the app's --mock-keyboard), keys read only while the app window has focus, a key
## counts when it goes down, and a key already held when polling starts (after enabling or
## after the window regains focus) never counts. No real key is read: the tests inject the
## key and focus readers.

const DT := Wl.SIM_DT

var _held: Dictionary = {}
var _focused: bool = true
var _key_reads: int = 0
var _focus_reads: int = 0


func before_each() -> void:
	_held = {}
	_focused = true
	_key_reads = 0
	_focus_reads = 0


func _mock(options: Dictionary = {}) -> MockTrainer:
	var m := MockTrainer.from_spec("erg", 200.0, options)
	autofree(m)
	m.key_reader = func(k: Key) -> bool:
		_key_reads += 1
		return bool(_held.get(k, false))
	m.focus_reader = func() -> bool:
		_focus_reads += 1
		return _focused
	return m


func test_off_by_default_reads_nothing() -> void:
	var m := _mock()
	assert_false(m.is_keyboard_enabled())
	_held[KEY_W] = true
	m.tick(DT)
	m.tick(DT)
	assert_eq(_key_reads, 0, "no key is read")
	assert_eq(_focus_reads, 0)
	assert_eq(m.keyboard_offsets(), {"power_w": 0.0, "cadence_rpm": 0.0})


func test_options_keyboard_turns_it_on() -> void:
	var m := _mock({"keyboard": true})
	assert_true(m.is_keyboard_enabled())
	m.tick(DT)
	_held[KEY_W] = true
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0, "W: +10 W")
	m.tick(DT)
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0, "held: counted once")
	_held[KEY_W] = false
	m.tick(DT)
	_held[KEY_W] = true
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["power_w"], 20.0, "pressed again")
	_held = {KEY_S: true}
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0, "S: -10 W")
	_held = {KEY_A: true}
	m.tick(DT)
	_held = {KEY_D: true}
	m.tick(DT)
	m.tick(DT)
	_held = {}
	m.tick(DT)
	_held = {KEY_D: true}
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["cadence_rpm"], 5.0, "A -5, D +5 twice")


func test_keys_are_read_only_while_the_window_has_focus() -> void:
	var m := _mock({"keyboard": true})
	m.tick(DT)
	_focused = false
	var reads := _key_reads
	_held[KEY_W] = true
	for _i in 10:
		m.tick(DT)
	assert_eq(_key_reads, reads, "unfocused: no key is read")
	assert_eq(m.keyboard_offsets()["power_w"], 0.0)
	_focused = true
	m.tick(DT)
	assert_gt(_key_reads, reads)
	assert_eq(m.keyboard_offsets()["power_w"], 0.0, "a key held while switching in doesn't count")
	_held[KEY_W] = false
	m.tick(DT)
	_held[KEY_W] = true
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0)


func test_a_key_held_when_enabled_does_not_count() -> void:
	var m := _mock()
	_held[KEY_S] = true
	m.set_keyboard_enabled(true)
	assert_true(m.is_keyboard_enabled())
	m.tick(DT)
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["power_w"], 0.0)
	m.set_keyboard_enabled(false)
	_held[KEY_S] = false
	var reads := _key_reads
	m.tick(DT)
	assert_eq(_key_reads, reads, "disabled again: nothing read")


func test_the_default_focus_reader_is_false_outside_the_tree() -> void:
	var m := MockTrainer.from_spec("erg", 200.0, {"keyboard": true})
	autofree(m)
	var reads := [0]
	m.key_reader = func(_k: Key) -> bool:
		reads[0] += 1
		return true
	m.tick(DT)
	assert_eq(reads[0], 0, "not in a window: no focus, no key read")
