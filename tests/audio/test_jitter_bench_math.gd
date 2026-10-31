extends GutTest
## The jitter bench's arithmetic (tools/audio/jitter_bench.gd; SPEC_AUDIO 2.4). The bench itself needs a real audio
## driver and runs by hand; what decides pass or miss is tested here.

const Bench := preload("res://tools/audio/jitter_bench.gd")
const FRACTIONS: Array[float] = [0.2778, 0.6111, 0.9444]


## Onset times of every stroke of `revolutions` revolutions at `rpm`, plus `wobble(i)`.
func _onsets(rpm: float, revolutions: int, wobble: Callable) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var i := 0
	for rev in revolutions:
		for f: float in FRACTIONS:
			out.append(10.0 + (float(rev) + f) * 60.0 / rpm + float(wobble.call(i)))
			i += 1
	return out


func _none(_i: int) -> float:
	return 0.0


func _ms_alternating(i: int) -> float:
	return 0.002 if i % 2 == 0 else -0.002


func _large(i: int) -> float:
	return 0.02 if i % 2 == 0 else -0.02


func test_fit_line() -> void:
	var line := Bench.fit_line(
		PackedFloat64Array([0.0, 1.0, 2.0, 3.0]), PackedFloat64Array([1.0, 3.0, 5.0, 7.0])
	)
	assert_almost_eq(float(line["a"]), 1.0, 1e-9)
	assert_almost_eq(float(line["b"]), 2.0, 1e-9)


func test_percentile_and_stddev() -> void:
	var v := PackedFloat64Array()
	for i in 100:
		v.append(float(i + 1))
	assert_eq(Bench.percentile(v, 0.99), 99.0)
	assert_eq(Bench.percentile(v, 1.0), 100.0)
	assert_eq(Bench.percentile(PackedFloat64Array(), 0.99), 0.0)
	assert_almost_eq(
		Bench.stddev(PackedFloat64Array([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0])), 2.138, 0.001
	)
	assert_eq(Bench.stddev(PackedFloat64Array([1.0])), 0.0)


func test_perfect_clicks_pass() -> void:
	var run := Bench.analyse(90.0, _onsets(90.0, 30, _none), 90)
	assert_true(run["pass"])
	assert_almost_eq(float(run["residual_ms_p99"]), 0.0, 1e-6)
	assert_almost_eq(float(run["slope_s_per_rev"]), 60.0 / 90.0, 1e-6)
	assert_eq(run["onsets"], 90)
	assert_eq(run["fired"], 90)


func test_small_jitter_passes_with_its_numbers() -> void:
	var run := Bench.analyse(90.0, _onsets(90.0, 30, _ms_alternating), 90)
	assert_true(run["pass"])
	assert_almost_eq(float(run["residual_ms_p99"]), 2.0, 0.1)


func test_large_jitter_misses() -> void:
	var run := Bench.analyse(90.0, _onsets(90.0, 30, _large), 90)
	assert_false(run["pass"], "20 ms is over both limits")
	assert_gt(float(run["residual_ms_p99"]), Bench.P99_MAX_MS)
	assert_gt(float(run["residual_ms_stddev"]), Bench.STDDEV_MAX_MS)


func test_a_wrong_rate_misses() -> void:
	var run := Bench.analyse(90.0, _onsets(89.5, 30, _none), 90)
	assert_false(run["pass"], "half an rpm is 0.56 %, over the 0.1 % limit")
	assert_gt(float(run["slope_error_pct"]), 0.1)


func test_a_missing_onset_costs_one_point() -> void:
	var onsets := _onsets(90.0, 30, _none)
	onsets.remove_at(40)
	var positions := Bench.match_positions(onsets, 90.0, FRACTIONS)
	assert_almost_eq(positions[39], 13.2778, 1e-9)
	assert_almost_eq(positions[40], 13.9444, 1e-9, "the next stroke keeps its own position")
	var run := Bench.analyse(90.0, onsets, 90)
	assert_true(run["pass"])
	assert_eq(run["onsets"], 89)
	assert_eq(run["fired"], 90, "the report shows the gap")


func test_too_few_onsets_miss() -> void:
	assert_false(Bench.analyse(90.0, PackedFloat64Array([1.0, 2.0]), 90)["pass"])


func test_the_click_is_a_locked_file() -> void:
	var s := Bench.click_stream()
	assert_eq(s.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_false(s.stereo)
	assert_eq(s.mix_rate, Bench.CLICK_RATE)
	var silence := int(GameAudioKit.PREROLL_S * Bench.CLICK_RATE)
	assert_eq(s.data.decode_s16((silence - 1) * 2), 0, "silent up to the attack")
	assert_gt(s.data.decode_s16(silence * 2), 10000, "then the click")


func test_the_bank_validates_on_an_existing_bus() -> void:
	assert_eq(AudioBank.validate(Bench.bank_doc(AudioBuses.MACHINES)), [] as Array[String])
	assert_ne(AudioBank.validate(Bench.bank_doc("NotABus")), [] as Array[String])
