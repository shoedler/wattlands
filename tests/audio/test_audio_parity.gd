extends GutTest
## The closed-form parity table of SPEC_AUDIO 2.6, asserted identically by tools/audio/test/pattern.test.mjs, so the
## offline preview (tools/audio/lib/pattern.mjs) and the game plan the same strokes. Each frame: advance `revs` by dt,
## then plan. dt 0.05, horizon 0.05, 1e-6 tolerance, times of the attacks. The stroke at `revs` 0 itself never fires:
## intervals are (from, to].

const DT := 0.05
const HORIZON := 0.05
const TOLERANCE := 1e-6


## schedule: [[rpm, until_t], ...]
func _attacks(schedule: Array, pattern: Array, end_t: float) -> Array[float]:
	var voice := CadenceVoice.new([{"at": pattern, "sound": "s"}])
	var clock := CrankClock.new()
	var out: Array[float] = []
	var frames := roundi(end_t / DT)
	for i in frames:
		var t := float(i) * DT
		var rpm := 0.0
		for row: Array in schedule:
			if t < float(row[1]) - 1e-9:
				rpm = row[0]
				break
		clock.advance(rpm, DT)
		for ev: Dictionary in voice.plan(clock.revs, rpm, HORIZON, {}, true):
			out.append(float(i + 1) * DT + float(ev["at_s"]))
	return out


func _assert_times(got: Array[float], want: Array[float], what: String) -> void:
	assert_eq(got.size(), want.size(), what + ": %s" % str(got))
	for i in mini(got.size(), want.size()):
		assert_almost_eq(got[i], want[i], TOLERANCE, "%s attack %d" % [what, i])


func test_scenario_a_steady() -> void:
	var want: Array[float] = [1.0 / 6.0, 0.5, 5.0 / 6.0, 7.0 / 6.0, 1.5, 11.0 / 6.0]
	_assert_times(_attacks([[90.0, 2.0]], [0.25, 0.75], 2.0), want, "A")


func test_scenario_b_a_step_up() -> void:
	var want: Array[float] = [0.5, 1.0, 1.25, 1.5, 1.75, 2.0]
	_assert_times(_attacks([[60.0, 1.0], [120.0, 2.0]], [0.0, 0.5], 2.0), want, "B")


func test_scenario_c_stop_and_restart() -> void:
	var want: Array[float] = [1.0 / 6.0, 0.5, 5.0 / 6.0, 13.0 / 6.0, 2.5, 17.0 / 6.0]
	var schedule := [[90.0, 1.0], [0.0, 2.0], [90.0, 3.0]]
	_assert_times(_attacks(schedule, [0.25, 0.75], 3.0), want, "C")
