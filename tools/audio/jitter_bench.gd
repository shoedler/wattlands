extends SceneTree
## Measures the audio kit's stroke jitter on the real audio driver (SPEC_AUDIO 2.4). Windowed, not part of run_tests:
##   tools/godot.sh --path . --timeout=420 -s tools/audio/jitter_bench.gd -- --report=build/audio_jitter.json
## A temporary bus with an AudioEffectCapture (muted, so nothing reaches the speakers: the capture sits before the bus
## volume) records what the kit's voices mix. The bench drives a CrankClock at each rpm for 25 s, finds the click onsets
## by sample index, fits a line to them and takes the residual as the jitter, twice per rpm: with the pre-roll seek, and
## with every stroke started at PREROLL_S, the baseline. It needs no WAV: its stream is built in code.
## Exit 0 only if every pre-roll run holds p99 <= 12 ms, stddev <= 4 ms and a slope within 0.1 % of 60/rpm; 1 on a miss
## (the numbers go in the report, the thresholds do not move); 3 on the Dummy driver, where nothing was measured.

const RPMS: Array[float] = [60.0, 90.0, 110.0, 140.0]
const RUN_S := 25.0
const SETTLE_S := 0.4
const WARMUP_FRAMES := 60
const BUS := "JitterBench"
const FRACTIONS: Array[float] = [0.2778, 0.6111, 0.9444]
const P99_MAX_MS := 12.0
const STDDEV_MAX_MS := 4.0
const SLOPE_TOLERANCE := 0.001
const THRESHOLD := 0.1
const REFRACTORY_S := 0.03
const CLICK_S := 0.002
const CLICK_RATE := 22050
const CLICK_LEVEL := 0.6
const COMMIT_BENCH_S := 5.0
const COMMIT_MACHINES := 8

var _kit: GameAudioKit = null
var _capture: AudioEffectCapture = null
var _bus_index: int = -1
var _mix_rate: float = 44100.0
var _plan: Array[Dictionary] = []
var _plan_i: int = 0
var _frames_seen: int = 0
var _state: String = "warmup"
var _clock: CrankClock = CrankClock.new()
var _run_t: float = 0.0
var _rpm: float = 0.0
var _index: int = 0
var _last_onset: int = -1000000
var _onsets: PackedFloat64Array = PackedFloat64Array()
var _deltas: PackedFloat64Array = PackedFloat64Array()
var _runs: Array[Dictionary] = []
var _commit_clocks: Array[CrankClock] = []
var _commit_us: PackedFloat64Array = PackedFloat64Array()
var _report_path: String = ""


func _initialize() -> void:
	_report_path = CmdLine.get_str("report", "build/audio_jitter.json")
	if AudioServer.get_driver_name() == "Dummy":
		printerr(
			"jitter_bench: AudioServer is on the Dummy driver: no real device, nothing was measured"
		)
		quit(3)
		return
	_mix_rate = AudioServer.get_mix_rate()
	AudioServer.add_bus()
	_bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus_index, BUS)
	AudioServer.set_bus_send(_bus_index, AudioBuses.MASTER)
	AudioServer.set_bus_mute(_bus_index, true)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(_bus_index, _capture)
	for rpm: float in RPMS:
		_plan.append({"rpm": rpm, "preroll": true})
		_plan.append({"rpm": rpm, "preroll": false})
	_kit = GameAudioKit.new()
	_kit.force_audio = true
	root.add_child(_kit)
	var bank := AudioBank.from_dict(bank_doc(BUS), "res://tools/audio")
	if bank == null:
		quit(2)
		return
	bank.set_stream("click", 0, click_stream())
	_kit.setup_bank(bank, 1)


func _process(delta: float) -> bool:
	match _state:
		"warmup":
			_frames_seen += 1
			if _frames_seen >= WARMUP_FRAMES:
				_begin_run()
		"run":
			_deltas.append(delta)
			_clock.advance(_rpm, delta)
			_kit.drive("bench", "bench", _clock.revs, _rpm, {}, true)
			_kit.commit(delta)
			_pull()
			_run_t += delta
			if _run_t >= RUN_S:
				_run_t = 0.0
				_state = "settle"
		"settle":
			_kit.drive("bench", "bench", _clock.revs, 0.0, {}, true)
			_kit.commit(delta)
			_pull()
			_run_t += delta
			if _run_t >= SETTLE_S:
				_end_run()
		"commit":
			_step_commit_bench(delta)
	return false


func _begin_run() -> void:
	var run := _plan[_plan_i]
	_rpm = float(run["rpm"])
	_kit.preroll_on = bool(run["preroll"])
	_kit.stop_machine("bench")
	_clock.reset()
	_onsets.clear()
	_deltas.clear()
	_pull()
	_onsets.clear()
	_run_t = 0.0
	_state = "run"
	print("jitter_bench: %d rpm, pre-roll %s" % [int(_rpm), str(_kit.preroll_on)])


func _end_run() -> void:
	var voice := _kit.machine_voice("bench")
	var run := analyse(_rpm, _onsets, voice.fired)
	run["preroll"] = _kit.preroll_on
	run["late"] = voice.late
	run["dropped"] = voice.dropped
	run["voiceless"] = _kit.voiceless
	run["discarded_frames"] = _capture.get_discarded_frames()
	run["frame_ms_mean"] = mean(_deltas) * 1000.0
	run["frame_ms_p99"] = percentile(_deltas, 0.99) * 1000.0
	_runs.append(run)
	print("jitter_bench: %s" % JSON.stringify(run))
	_plan_i += 1
	if _plan_i < _plan.size():
		_begin_run()
	else:
		_kit.stop_machine("bench")
		_kit.preroll_on = true
		for i in COMMIT_MACHINES:
			_commit_clocks.append(CrankClock.new())
		_run_t = 0.0
		_state = "commit"


## D10 of the scorecard: a kit commit with 8 machines (a bench number, not a gate).
func _step_commit_bench(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	for i in COMMIT_MACHINES:
		var rpm := 85.0 + 4.0 * float(i)
		_commit_clocks[i].advance(rpm, delta)
		_kit.drive("m%d" % i, "bench", _commit_clocks[i].revs, rpm, {}, i == 0)
	_kit.commit(delta)
	_commit_us.append(float(Time.get_ticks_usec() - t0))
	_pull()
	_run_t += delta
	if _run_t >= COMMIT_BENCH_S:
		_finish()


func _finish() -> void:
	var ok := true
	for run: Dictionary in _runs:
		if bool(run["preroll"]) and not bool(run["pass"]):
			ok = false
	var report := {
		"driver": AudioServer.get_driver_name(),
		"mix_rate": _mix_rate,
		"display": DisplayServer.get_name(),
		"thresholds":
		{
			"p99_ms": P99_MAX_MS,
			"stddev_ms": STDDEV_MAX_MS,
			"slope_tolerance": SLOPE_TOLERANCE,
		},
		"commit_8_machines_mean_ms": mean(_commit_us) / 1000.0,
		"runs": _runs,
		"pass": ok,
	}
	var path := _report_path
	if path.is_relative_path():
		path = ProjectSettings.globalize_path("res://" + path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("jitter_bench: %s, report %s" % ["PASS" if ok else "MISS", path])
	_kit.stop_all()
	AudioServer.remove_bus(_bus_index)
	quit(0 if ok else 1)


func _pull() -> void:
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var buf := _capture.get_buffer(n)
	var refractory := int(REFRACTORY_S * _mix_rate)
	for i in n:
		var frame := buf[i]
		if maxf(absf(frame.x), absf(frame.y)) < THRESHOLD:
			continue
		var at := _index + i
		if at - _last_onset >= refractory:
			_onsets.append(float(at) / _mix_rate)
		_last_onset = at
	_index += n


## One machine, the diesel's three strokes a revolution (firings 143 ms apart at 140 rpm), on `bus`.
static func bank_doc(bus: String) -> Dictionary:
	return {
		"schema": 1,
		"game": "jitter_bench",
		"sounds": {"click": {"dur": 0.1, "rate": CLICK_RATE, "ch": 1, "locked": true}},
		"machines":
		{
			"bench":
			{
				"bus": bus,
				"priority": 5,
				"events": [{"at": Array(FRACTIONS), "sound": "click", "db": 0.0}],
			}
		},
	}


## 80 ms of silence, then a 2 ms click, in the format every locked file has.
static func click_stream() -> AudioStreamWAV:
	var silence := int(GameAudioKit.PREROLL_S * CLICK_RATE)
	var click := int(CLICK_S * CLICK_RATE)
	var tail := int(0.01 * CLICK_RATE)
	var data := PackedByteArray()
	data.resize((silence + click + tail) * 2)
	data.fill(0)
	for i in click:
		data.encode_s16((silence + i) * 2, int(CLICK_LEVEL * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = CLICK_RATE
	s.stereo = false
	s.data = data
	return s


## One run's numbers from its onset times (seconds on the mix's sample clock) and the strokes the voice fired.
static func analyse(rpm: float, onsets: PackedFloat64Array, fired: int) -> Dictionary:
	var positions := match_positions(onsets, rpm, FRACTIONS)
	var nominal := 60.0 / rpm
	var out := {
		"rpm": rpm,
		"fired": fired,
		"onsets": onsets.size(),
		"pass": false,
		"residual_ms_p99": -1.0,
		"residual_ms_stddev": -1.0,
		"slope_s_per_rev": 0.0,
		"slope_error_pct": 100.0,
	}
	if onsets.size() < 3:
		return out
	var line := fit_line(positions, onsets)
	var residual := PackedFloat64Array()
	residual.resize(onsets.size())
	for i in onsets.size():
		residual[i] = onsets[i] - (float(line["a"]) + float(line["b"]) * positions[i])
	var magnitudes := PackedFloat64Array()
	for r in residual:
		magnitudes.append(absf(r))
	var p99 := percentile(magnitudes, 0.99) * 1000.0
	var sd := stddev(residual) * 1000.0
	var slope_error := absf(float(line["b"]) - nominal) / nominal
	out["residual_ms_p99"] = p99
	out["residual_ms_stddev"] = sd
	out["slope_s_per_rev"] = line["b"]
	out["slope_error_pct"] = slope_error * 100.0
	out["pass"] = p99 <= P99_MAX_MS and sd <= STDDEV_MAX_MS and slope_error <= SLOPE_TOLERANCE
	return out


## Each onset's position on the revs axis: the pattern's position nearest the one its time implies from the onset
## before it, so a missing onset costs one point and does not shift the rest.
static func match_positions(
	onsets: PackedFloat64Array, rpm: float, fractions: Array[float]
) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if onsets.is_empty():
		return out
	var rate := rpm / 60.0
	var pos := float(fractions[0])
	out.append(pos)
	for i in range(1, onsets.size()):
		pos = nearest_position(pos + (onsets[i] - onsets[i - 1]) * rate, fractions)
		out.append(pos)
	return out


static func nearest_position(pos: float, fractions: Array[float]) -> float:
	var whole := floorf(pos)
	var best := whole + fractions[0]
	for k: float in [-1.0, 0.0, 1.0]:
		for f: float in fractions:
			var candidate := whole + k + f
			if absf(candidate - pos) < absf(best - pos):
				best = candidate
	return best


## Least squares y = a + b x.
static func fit_line(xs: PackedFloat64Array, ys: PackedFloat64Array) -> Dictionary:
	var mx := mean(xs)
	var my := mean(ys)
	var sxx := 0.0
	var sxy := 0.0
	for i in xs.size():
		sxx += (xs[i] - mx) * (xs[i] - mx)
		sxy += (xs[i] - mx) * (ys[i] - my)
	var b := sxy / sxx if sxx > 0.0 else 0.0
	return {"a": my - b * mx, "b": b}


static func mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


static func stddev(values: PackedFloat64Array) -> float:
	if values.size() < 2:
		return 0.0
	var m := mean(values)
	var total := 0.0
	for v in values:
		total += (v - m) * (v - m)
	return sqrt(total / float(values.size() - 1))


## Nearest-rank percentile, q in 0..1.
static func percentile(values: PackedFloat64Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(q * float(sorted.size())) - 1, 0, sorted.size() - 1)]
