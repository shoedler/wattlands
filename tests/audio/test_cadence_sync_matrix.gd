extends GutTest
## The cadence sync matrix (SPEC_AUDIO 2.6): pure, no audio device. Strokes 1:1 with the crank across 30-140 rpm at
## every frame rate, for an hour without drift, stopping dead at 0 rpm and resuming with no burst.

const RPMS: Array[float] = [30.0, 45.0, 60.0, 75.0, 90.0, 110.0, 125.0, 140.0]
const PATTERNS: Array = [[0.0], [0.0, 0.5], [0.2778, 0.6111, 0.9444]]
const FRAMES: Array[float] = [1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0, 0.05, 0.0]  # 0: seeded jitter 8-33 ms
const LONG_S := 120.0
const BANK := "res://tests/audio/fixtures/bank_min.json"


func _voice(pattern: Array) -> CadenceVoice:
	return CadenceVoice.new([{"at": pattern, "sound": "s"}])


func _horizon(frame_s: float) -> float:
	return clampf(1.5 * frame_s, GameAudioKit.HORIZON_MIN_S, GameAudioKit.HORIZON_MAX_S)


## How many k + f of `pattern` fall in (from, to].
func _count(pattern: Array, from: float, to: float) -> int:
	var n := 0
	for f: float in pattern:
		n += floori(to - f) - floori(from - f)
	return n


func _kit() -> GameAudioKit:
	var kit := GameAudioKit.new()
	add_child_autofree(kit)
	assert_true(kit.setup(BANK, 7))
	assert_true(kit.silent, "headless: the kit is silent and keeps its records")
	return kit


func test_count_and_times() -> void:
	var rng := SeededRng.make(42)
	for rpm: float in RPMS:
		for pattern: Array in PATTERNS:
			for frame: float in FRAMES:
				_one_count_and_times(rpm, pattern, frame, rng)


func _one_count_and_times(
	rpm: float, pattern: Array, frame: float, rng: RandomNumberGenerator
) -> void:
	var voice := _voice(pattern)
	var clock := CrankClock.new()
	var what := "%d rpm, %d strokes, frame %.4f" % [int(rpm), pattern.size(), frame]
	var rate := rpm / 60.0
	var t := 0.0
	var ema := 0.0
	var prev_h := 0.0
	var start := 0.0
	var last_pos := -1.0
	var emitted := 0
	var worst := 0.0
	var repeats := 0
	var first := true
	while t < LONG_S:
		var dt := frame if frame > 0.0 else rng.randf_range(0.008, 0.033)
		t += dt
		clock.advance(rpm, dt)
		ema = dt if ema <= 0.0 else lerpf(ema, dt, GameAudioKit.FRAME_ALPHA)
		var h := _horizon(ema)
		if first:
			start = clock.revs
			first = false
		var on_time := dt <= prev_h
		for ev: Dictionary in voice.plan(clock.revs, rpm, h, {}, true):
			var pos: float = ev["pos"]
			repeats += 1 if pos <= last_pos else 0
			last_pos = pos
			emitted += 1
			if on_time:
				worst = maxf(worst, absf(t + float(ev["at_s"]) - pos / rate))
		prev_h = h
	assert_eq(voice.fired, _count(pattern, start, voice.planned_to()), what + ": fired exact")
	assert_eq(voice.fired, emitted, what)
	assert_eq(voice.dropped, 0, what)
	assert_eq(repeats, 0, what + ": no stroke twice")
	assert_lt(worst, 1e-6, what + ": every time when dt <= horizon")


func test_hour_no_drift() -> void:
	const DT := 1.0 / 60.0
	const FRAMES_PER_CHECK := 36000
	for rpm: float in [30.0, 90.0, 140.0]:
		var voice := _voice([0.0])
		var clock := CrankClock.new()
		var rate := rpm / 60.0
		var last_error := 0.0
		for check in 6:
			for i in FRAMES_PER_CHECK:
				clock.advance(rpm, DT)
				var frame := check * FRAMES_PER_CHECK + i + 1
				for ev: Dictionary in voice.plan(clock.revs, rpm, 0.025, {}, true):
					var when := float(frame) * DT + float(ev["at_s"])
					last_error = absf(when - float(ev["pos"]) / rate)
			var t := float(check + 1) * 600.0
			assert_lt(absf(clock.revs - rate * t), 1e-6, "%d rpm at %d s" % [int(rpm), int(t)])
		assert_eq(voice.fired, _count([0.0], DT * rate, voice.planned_to()), "fired exact")
		assert_lt(last_error, 1e-4, "%d rpm: the last event's time" % int(rpm))


func test_ramp() -> void:
	const DT := 1.0 / 60.0
	const SECONDS := 60.0
	var pattern := [0.25, 0.75]
	var voice := _voice(pattern)
	var clock := CrankClock.new()
	var start := 0.0
	var sum := 0.0
	for i in int(SECONDS / DT):
		var t := float(i) * DT
		var u := t / (SECONDS / 2.0)
		var rpm := lerpf(30.0, 140.0, u) if u < 1.0 else lerpf(140.0, 30.0, u - 1.0)
		clock.advance(rpm, DT)
		sum += rpm / 60.0 * DT
		voice.plan(clock.revs, rpm, 0.025, {}, true)
		if i == 0:
			start = clock.revs
	assert_almost_eq(clock.revs, sum, 1e-9, "one integral")
	assert_eq(voice.fired, _count(pattern, start, voice.planned_to()))
	assert_eq(voice.dropped, 0)


func test_stop_dead() -> void:
	const DT := 1.0 / 60.0
	var kit := _kit()
	var clock := CrankClock.new()
	var t := 0.0
	for i in 300:
		clock.advance(90.0, DT)
		kit.drive("a", "main", clock.revs, 90.0, {"power": 1.0}, true)
		kit.drive("b", "bare", clock.revs, 90.0, {}, true)
		kit.commit(DT)
		t += DT
	var loop := kit.machine_loop("a")
	var bare := kit.machine_loop("b")
	assert_eq(loop.on[0], 1, "precondition: the body loop runs")
	assert_eq(bare.on[0], 1, "precondition: so does the layer with no min_rpm")
	var stop_t := t
	var count := kit.played.size()
	var off_after := -1.0
	var bare_off_after := -1.0
	for i in 60:
		kit.drive("a", "main", clock.revs, 0.0, {"power": 0.0}, true)
		kit.drive("b", "bare", clock.revs, 0.0, {}, true)
		kit.commit(DT)
		t += DT
		if off_after < 0.0 and loop.all_off():
			off_after = t - stop_t
		if bare_off_after < 0.0 and bare.all_off():
			bare_off_after = t - stop_t
	assert_eq(kit.played.size(), count, "no stroke starts once the crank stands")
	assert_true(off_after >= 0.0 and off_after <= 0.12, "loops off in %.3f s" % off_after)
	assert_true(
		bare_off_after >= 0.0 and bare_off_after <= 0.12,
		"whatever the layers say: off in %.3f s" % bare_off_after
	)
	assert_gt(count, 0, "precondition: strokes were played")
	for when: float in kit.played_t:
		assert_lte(when, stop_t + GameAudioKit.HORIZON_MAX_S, "due by the horizon")


func test_restart_is_no_burst_and_no_repeat() -> void:
	const DT := 1.0 / 60.0
	var voice := _voice([0.25, 0.75])
	var clock := CrankClock.new()
	var positions: Array[float] = []
	for phase: Array in [[90.0, 5.0], [0.0, 5.0], [90.0, 5.0]]:
		var rpm: float = phase[0]
		for i in int(float(phase[1]) / DT):
			clock.advance(rpm, DT)
			var events := voice.plan(clock.revs, rpm, 0.025, {}, true)
			assert_lte(events.size(), 1, "one stroke at a time")
			for ev: Dictionary in events:
				positions.append(ev["pos"])
	for i in range(1, positions.size()):
		assert_almost_eq(positions[i] - positions[i - 1], 0.5, 1e-9, "each stroke, once, in order")
	assert_eq(voice.dropped, 0)


func test_hitch_drops_what_is_too_old() -> void:
	var pattern := [0.0, 0.25, 0.5, 0.75]
	var voice := _voice(pattern)
	var clock := CrankClock.new()
	const RPM := 140.0
	var rate := RPM / 60.0
	clock.advance(RPM, 0.1)
	var start := clock.revs
	voice.plan(clock.revs, RPM, 0.025, {}, true)
	var before := voice.fired
	var was_to := voice.planned_to()
	clock.advance(RPM, 1.0)
	var events := voice.plan(clock.revs, RPM, 0.025, {}, true)
	var oldest := clock.revs - rate * CadenceVoice.LATE_MAX_S
	for ev: Dictionary in events:
		assert_gt(float(ev["pos"]), oldest, "only events inside the last LATE_MAX_S fire")
	assert_gt(voice.dropped, 0, "the rest are dropped")
	assert_eq(voice.dropped, _count(pattern, was_to, oldest), "and counted")
	assert_eq(voice.fired - before, events.size())
	assert_eq(
		voice.fired + voice.dropped,
		_count(pattern, start, voice.planned_to()),
		"fired + dropped exact"
	)
	assert_eq(voice.fired, before + events.size())


func test_late_counts_a_frame_past_the_horizon() -> void:
	var voice := _voice([0.5])
	voice.plan(0.0, 60.0, 0.012, {}, true)
	var events := voice.plan(0.51, 60.0, 0.012, {}, true)
	assert_eq(events.size(), 1)
	assert_eq(float(events[0]["at_s"]), 0.0)
	assert_eq(voice.late, 1)


func test_backwards_reprimes() -> void:
	var voice := _voice([0.5])
	voice.plan(100.0, 90.0, 0.025, {}, true)
	var fired := voice.fired
	assert_eq(voice.plan(0.0, 90.0, 0.025, {}, true).size(), 0, "no burst")
	assert_eq(voice.fired, fired)
	assert_eq(voice.plan(0.51, 90.0, 0.025, {}, true).size(), 1, "and it carries on from there")


## The Tank diesel's picture (tank_mech_diesel.gd: since = fposmod(ph*720 - 200, 240)) fires when `since` wraps.
func test_visual_alignment() -> void:
	const DT := 1.0 / 60.0
	const RPM := 90.0
	var voice := _voice([0.2778, 0.6111, 0.9444])
	var clock := CrankClock.new()
	var wraps: Array[float] = []
	var due: Array[float] = []
	var since := fposmod(-200.0, 240.0)
	for i in 3600:
		clock.advance(RPM, DT)
		var t := float(i + 1) * DT
		var now := fposmod(clock.frac() * 720.0 - 200.0, 240.0)
		if now < since:
			wraps.append(t)
		since = now
		for ev: Dictionary in voice.plan(clock.revs, RPM, 0.025, {}, true):
			due.append(t + float(ev["at_s"]))
	assert_gt(due.size(), 200)
	var worst := 0.0
	for when: float in due:
		var nearest := INF
		for wrap: float in wraps:
			nearest = minf(nearest, absf(wrap - when))
		worst = maxf(worst, nearest)
	assert_lte(worst, DT + 1e-6, "each planned event falls within one frame of `since` wrapping")


func test_remote_snapshot_rates() -> void:
	const DT := 1.0 / 60.0
	for hz: float in [10.0, 1.0]:
		var rng := SeededRng.make(int(hz))
		var pattern := [0.0]
		var voice := _voice(pattern)
		var clock := CrankClock.new()
		var integral := 0.0
		var rpm := 90.0
		var left := 0.0
		for i in 3600:
			left -= DT
			if left <= 0.0:
				left = 1.0 / hz
				rpm = float(90 + rng.randi_range(-2, 2))
			clock.advance(rpm, DT)
			integral += rpm / 60.0 * DT
			voice.plan(clock.revs, rpm, 0.025, {}, true)
		assert_lte(
			absi(voice.fired - floori(integral)), 1, "%d Hz: within 1 of the integral" % int(hz)
		)


func test_loop_pitch_moves_under_one_percent_a_frame_on_a_small_step() -> void:
	const DT := 1.0 / 60.0
	var loop := LayeredLoop.new([{"sound": "b", "pitch_by": [{"param": "rpm", "ratio": 110}]}])
	loop.update({"rpm": 90.0}, 0.0, true, DT)
	var was := loop.pitch[0]
	var worst := 0.0
	for i in 120:
		loop.update({"rpm": 93.0}, 0.0, true, DT)
		worst = maxf(worst, absf(loop.pitch[0] - was) / was)
		was = loop.pitch[0]
	assert_lt(worst, 0.01)


func test_thinning_caps_others_and_never_the_lead() -> void:
	const DT := 1.0 / 60.0
	const SECONDS := 60.0
	var kit := _kit()
	var lead := CrankClock.new()
	var others: Array[CrankClock] = []
	var rpms: Array[float] = []
	for i in 7:
		others.append(CrankClock.new())
		rpms.append(88.0 + 4.0 * float(i))
	var first := 0.0
	var other_times: Array[float] = []
	for frame in int(SECONDS / DT):
		lead.advance(90.0, DT)
		kit.drive("lead", "main", lead.revs, 90.0, {"power": 0.2}, true)
		for i in others.size():
			others[i].advance(rpms[i], DT)
			kit.drive("o%d" % i, "other", others[i].revs, rpms[i], {}, false)
		kit.commit(DT)
		if frame == 0:
			first = lead.revs
		for k in kit.played.size():
			if kit.played[k] == "other_stroke":
				other_times.append(kit.played_t[k])
		kit.clear_played()
	var voice := kit.machine_voice("lead")
	assert_eq(voice.fired, _count([0.25, 0.75], first, voice.planned_to()), "lead fired exact")
	assert_gt(kit.thinned, 0)
	assert_lte(float(other_times.size()) / SECONDS, 1.0 / 0.06, "others per second")
	for i in range(1, other_times.size()):
		assert_gte(other_times[i] - other_times[i - 1], 0.06 - 1e-9, "the gap holds")


func test_pause_is_silent_and_resumes_with_no_burst() -> void:
	const DT := 1.0 / 60.0
	var kit := _kit()
	var clock := CrankClock.new()
	for i in 120:
		clock.advance(90.0, DT)
		kit.drive("a", "main", clock.revs, 90.0, {"power": 0.2}, true)
		kit.set_loop("drag_scream", {"tension": 1.0})
		kit.commit(DT)
	var voice := kit.machine_voice("a")
	var dropped := voice.dropped
	var entry := kit.entry_loop("drag_scream")
	assert_eq(entry.on[0], 1, "precondition: the entry runs")
	kit.clear_played()
	kit._on_paused_changed(true, "test")
	for i in 300:
		clock.advance(90.0, DT)
		kit.drive("a", "main", clock.revs, 90.0, {"power": 0.2}, true)
		kit.set_loop("drag_scream", {"tension": 1.0})
		kit.commit(DT)
	assert_eq(kit.played.size(), 0, "no stroke while paused")
	assert_true(kit.machine_loop("a").all_off(), "machine loops closed")
	assert_true(entry.all_off(), "a loops entry closes too, though the adapter still asks for it")
	kit._on_paused_changed(false, "test")
	var strokes := 0
	for i in 30:
		clock.advance(90.0, DT)
		kit.drive("a", "main", clock.revs, 90.0, {"power": 0.2}, true)
		kit.set_loop("drag_scream", {"tension": 1.0})
		kit.commit(DT)
		var n := 0
		for id: String in kit.played:
			if id == "stroke":
				n += 1
		kit.clear_played()
		assert_lte(n, 1, "no burst on resume")
		strokes += n
	assert_between(strokes, 1, 2, "half a second at two strokes a revolution, 90 rpm")
	assert_eq(entry.on[0], 1, "the entry comes back with the resume")
	assert_eq(voice.dropped, dropped, "dropped unchanged")
