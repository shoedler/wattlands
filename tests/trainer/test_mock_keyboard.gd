extends GutTest
## MockTrainer keyboard control: off unless enabled (--mock-keyboard or Settings), keys read only
## while the app window has focus, a key counts when it goes down, and a key already held when
## polling starts (after enabling or after the window regains focus) never counts. T/G power and
## Y/H cadence step on a tap and ramp when held; the numpad block sets presets, N stops, Shift
## sprints. No real key is read: the tests inject the key and focus readers.

const DT := Wl.SIM_DT
const FTP := 200.0

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
	var m := MockTrainer.from_spec("erg", FTP, options)
	autofree(m)
	m.key_reader = func(k: Key) -> bool:
		_key_reads += 1
		return bool(_held.get(k, false))
	m.focus_reader = func() -> bool:
		_focus_reads += 1
		return _focused
	return m


## A mock with the keyboard on, past the first poll (which only notes held keys).
func _live() -> MockTrainer:
	var m := _mock({"keyboard": true})
	m.tick(DT)
	return m


func _hold(m: MockTrainer, key: Key, seconds: float) -> void:
	_held[key] = true
	for _i in roundi(seconds / DT):
		m.tick(DT)
	_held[key] = false
	m.tick(DT)


func _tap(m: MockTrainer, key: Key) -> void:
	_held[key] = true
	m.tick(DT)
	_held[key] = false
	m.tick(DT)


func test_off_by_default_reads_nothing() -> void:
	var m := _mock()
	assert_false(m.is_keyboard_enabled())
	_held[MockTrainer.KEY_POWER_UP] = true
	_held[KEY_O] = true
	_held[MockTrainer.KEY_SPRINT] = true
	m.tick(DT)
	m.tick(DT)
	assert_eq(_key_reads, 0, "no key is read")
	assert_eq(_focus_reads, 0)
	assert_eq(m.keyboard_offsets(), {"power_w": 0.0, "cadence_rpm": 0.0})
	assert_eq(m.keyboard_override()["power_w"], -1.0)


func test_no_key_is_bound_in_the_input_map() -> void:
	var keys: Array = [
		MockTrainer.KEY_POWER_UP,
		MockTrainer.KEY_POWER_DOWN,
		MockTrainer.KEY_CADENCE_UP,
		MockTrainer.KEY_CADENCE_DOWN,
		MockTrainer.KEY_SPRINT,
		MockTrainer.KEY_STOP,
		KEY_KP_0,
	]
	keys.append_array(MockTrainer.KEYBOARD_PRESET_KEYS.keys())
	InputBindings.ensure_actions()
	for action: StringName in Wl.ACTIONS:
		for e: InputEvent in InputBindings.events_of(action):
			if e is InputEventKey:
				var code := (e as InputEventKey).physical_keycode
				assert_false(keys.has(code), "%s is bound to the action %s" % [code, action])


func test_taps_step_power_and_cadence() -> void:
	var m := _live()
	_tap(m, MockTrainer.KEY_POWER_UP)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0, "T: +10 W")
	_hold(m, MockTrainer.KEY_POWER_UP, 0.15)
	assert_eq(m.keyboard_offsets()["power_w"], 20.0, "held a moment: one more step, not three")
	_tap(m, MockTrainer.KEY_POWER_DOWN)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0, "G: -10 W")
	_tap(m, MockTrainer.KEY_CADENCE_DOWN)
	_tap(m, MockTrainer.KEY_CADENCE_UP)
	_tap(m, MockTrainer.KEY_CADENCE_UP)
	assert_eq(m.keyboard_offsets()["cadence_rpm"], 5.0, "H -5, Y +5 twice")


func test_a_held_key_ramps_faster_the_longer_it_is_held() -> void:
	var m := _live()
	_hold(m, MockTrainer.KEY_POWER_UP, 1.0)
	var after_1s := float(m.keyboard_offsets()["power_w"])
	assert_gt(after_1s, 10.0 + 10.0, "more than the tap plus a second of 20 W/s")
	assert_lt(after_1s, 10.0 + 60.0)
	var m2 := _live()
	_hold(m2, MockTrainer.KEY_POWER_UP, 4.0)
	var after_4s := float(m2.keyboard_offsets()["power_w"])
	assert_gt(after_4s, 4.0 * after_1s, "accelerating, not linear")
	# Past the ramp-up the speed is 200 W/s: one more second of the same hold adds about 200 W.
	var m3 := _live()
	_held[MockTrainer.KEY_POWER_UP] = true
	for _i in roundi(4.0 / DT):
		m3.tick(DT)
	var at_4s := float(m3.keyboard_offsets()["power_w"])
	for _i in roundi(1.0 / DT):
		m3.tick(DT)
	assert_almost_eq(
		float(m3.keyboard_offsets()["power_w"]) - at_4s, 200.0, 20.0, "200 W/s at the top"
	)


func test_a_key_released_before_the_delay_is_only_a_tap() -> void:
	var m := _live()
	_hold(m, MockTrainer.KEY_POWER_UP, MockTrainer.KEY_HOLD_DELAY_S - 0.1)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0)


func test_ramping_down_stops_at_zero_watts_without_debt() -> void:
	var m := _live()
	_hold(m, MockTrainer.KEY_POWER_DOWN, 8.0)
	for _i in 60:
		m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 0.0, "never below zero")
	_tap(m, MockTrainer.KEY_POWER_UP)
	for _i in 60:
		m.tick(DT)
	assert_between(m.instantaneous_power_w(), 1.0, 15.0, "one tap above the floor")


func test_held_cadence_keys_ramp() -> void:
	var m := _live()
	_hold(m, MockTrainer.KEY_CADENCE_UP, 3.0)
	var up := float(m.keyboard_offsets()["cadence_rpm"])
	assert_gt(up, 5.0 + 15.0)
	_hold(m, MockTrainer.KEY_CADENCE_DOWN, 3.0)
	assert_lt(float(m.keyboard_offsets()["cadence_rpm"]), up)


func test_presets_set_power_from_the_riders_ftp() -> void:
	var m := _live()
	var pct := [50, 75, 100, 125, 150, 175, 200, 225, 250]
	var keys := [KEY_M, KEY_COMMA, KEY_PERIOD, KEY_J, KEY_K, KEY_L, KEY_U, KEY_I, KEY_O]
	for i in 9:
		_tap(m, keys[i] as Key)
		m.tick(DT)
		assert_almost_eq(
			m.instantaneous_power_w(), FTP * float(pct[i]) / 100.0, 1e-6, "preset %d" % (i + 1)
		)
		assert_almost_eq(m.instantaneous_cadence_rpm(), 85.0 + 2.5 * i, 1e-6, "cadence %d" % i)


func test_the_numpad_keys_are_presets_too() -> void:
	var m := _live()
	_tap(m, KEY_KP_9)
	m.tick(DT)
	assert_almost_eq(m.instantaneous_power_w(), 2.5 * FTP, 1e-6)
	_tap(m, KEY_KP_1)
	m.tick(DT)
	assert_almost_eq(m.instantaneous_power_w(), 0.5 * FTP, 1e-6)
	_tap(m, KEY_KP_0)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 0.0)


func test_a_preset_follows_at_once_and_t_g_move_it() -> void:
	var m := _live()
	_tap(m, KEY_PERIOD)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), FTP, "no follower lag")
	_tap(m, MockTrainer.KEY_POWER_UP)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), FTP + 10.0)
	_tap(m, MockTrainer.KEY_CADENCE_DOWN)
	m.tick(DT)
	assert_eq(m.instantaneous_cadence_rpm(), 90.0 - 5.0)
	_tap(m, KEY_J)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 1.25 * FTP, "the next preset replaces it")


func test_a_preset_is_exact_even_above_critical_power() -> void:
	var m := _live()
	_tap(m, KEY_O)
	for _i in roundi(240.0 / DT):
		m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 2.5 * FTP, "no fatigue cap")
	assert_eq(m.instantaneous_cadence_rpm(), 105.0, "no sprint cadence lift")


func test_the_stop_key_stops_pedaling_and_a_raise_starts_again() -> void:
	var m := _live()
	_tap(m, KEY_K)
	m.tick(DT)
	assert_gt(m.instantaneous_power_w(), 0.0)
	_tap(m, MockTrainer.KEY_STOP)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 0.0)
	assert_eq(m.instantaneous_cadence_rpm(), 0.0)
	for _i in 60:
		m.tick(DT)
	var s := m.last_sample()
	assert_eq(s.power_w, 0.0, "the telemetry shows no pedaling")
	assert_eq(s.cadence_rpm, 0.0)
	_tap(m, MockTrainer.KEY_POWER_UP)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 10.0)
	assert_gt(m.instantaneous_cadence_rpm(), 0.0, "pedaling again")


func test_the_sprint_key_sprints_while_held_and_restores_the_setting() -> void:
	var m := _live()
	_tap(m, KEY_K)
	m.tick(DT)
	var before := m.instantaneous_power_w()
	_held[MockTrainer.KEY_SPRINT] = true
	m.tick(DT)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 3.0 * FTP, "300% FTP")
	assert_eq(m.instantaneous_cadence_rpm(), 110.0)
	_held[MockTrainer.KEY_SPRINT] = false
	m.tick(DT)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), before, "back to the previous setting")
	assert_eq(m.instantaneous_cadence_rpm(), 95.0, "preset 5's cadence")


func test_the_sprint_returns_to_the_riders_own_power_without_a_preset() -> void:
	var m := _live()
	_held[MockTrainer.KEY_SPRINT] = true
	m.tick(DT)
	m.tick(DT)
	assert_eq(m.instantaneous_power_w(), 3.0 * FTP)
	_held[MockTrainer.KEY_SPRINT] = false
	for _i in roundi(30.0 / DT):
		m.tick(DT)
	assert_almost_eq(m.instantaneous_power_w(), 0.9 * FTP, 3.0, "the free-ride power again")


func test_keys_are_read_only_while_the_window_has_focus() -> void:
	var m := _live()
	_focused = false
	var reads := _key_reads
	_held[MockTrainer.KEY_POWER_UP] = true
	_held[KEY_O] = true
	_held[MockTrainer.KEY_SPRINT] = true
	for _i in 10:
		m.tick(DT)
	assert_eq(_key_reads, reads, "unfocused: no key is read")
	assert_eq(m.keyboard_offsets()["power_w"], 0.0)
	assert_eq(m.keyboard_override()["power_w"], -1.0)
	assert_false(m.keyboard_override()["sprint"])
	_focused = true
	m.tick(DT)
	m.tick(DT)
	assert_gt(_key_reads, reads)
	assert_eq(m.keyboard_offsets()["power_w"], 0.0, "a key held while switching in doesn't count")
	assert_eq(m.keyboard_override()["power_w"], -1.0)
	assert_false(m.keyboard_override()["sprint"], "nor does a held sprint")
	_held[MockTrainer.KEY_POWER_UP] = false
	m.tick(DT)
	_tap(m, MockTrainer.KEY_POWER_UP)
	assert_eq(m.keyboard_offsets()["power_w"], 10.0)


func test_losing_the_focus_drops_the_sprint() -> void:
	var m := _live()
	_held[MockTrainer.KEY_SPRINT] = true
	m.tick(DT)
	m.tick(DT)
	assert_true(m.keyboard_override()["sprint"])
	_focused = false
	m.tick(DT)
	assert_false(m.keyboard_override()["sprint"])


func test_a_key_held_when_enabled_does_not_count() -> void:
	var m := _mock()
	_held[MockTrainer.KEY_POWER_DOWN] = true
	_held[KEY_O] = true
	m.set_keyboard_enabled(true)
	assert_true(m.is_keyboard_enabled())
	m.tick(DT)
	m.tick(DT)
	assert_eq(m.keyboard_offsets()["power_w"], 0.0)
	assert_eq(m.keyboard_override()["power_w"], -1.0)
	m.set_keyboard_enabled(false)
	_held = {}
	var reads := _key_reads
	m.tick(DT)
	assert_eq(_key_reads, reads, "disabled again: nothing read")


func test_switching_the_keyboard_off_clears_every_setting() -> void:
	var m := _live()
	_tap(m, KEY_O)
	_tap(m, MockTrainer.KEY_CADENCE_UP)
	m.tick(DT)
	assert_gt(m.instantaneous_power_w(), 2.0 * FTP)
	m.set_keyboard_enabled(false)
	for _i in roundi(40.0 / DT):
		m.tick(DT)
	assert_almost_eq(m.instantaneous_power_w(), 0.9 * FTP, 3.0, "the rider's own power again")
	assert_eq(m.keyboard_override()["power_w"], -1.0)
	assert_eq(m.keyboard_offsets(), {"power_w": 0.0, "cadence_rpm": 0.0})


func test_keys_only_change_what_the_rider_pedals() -> void:
	# The mock is a rider, not a controller: a preset changes the telemetry, never a command.
	var m := _live()
	var commands := m.command_count
	_tap(m, KEY_O)
	_tap(m, MockTrainer.KEY_STOP)
	assert_eq(m.command_count, commands)
	assert_eq(m.commanded_mode, Wl.OFF)


func test_the_default_focus_reader_is_false_outside_the_tree() -> void:
	var m := MockTrainer.from_spec("erg", 200.0, {"keyboard": true})
	autofree(m)
	var reads := [0]
	m.key_reader = func(_k: Key) -> bool:
		reads[0] += 1
		return true
	m.tick(DT)
	assert_eq(reads[0], 0, "not in a window: no focus, no key read")
