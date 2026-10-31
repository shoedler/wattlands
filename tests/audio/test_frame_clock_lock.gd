extends GutTest
## The sawtooth of Godot's delta smoothing against the strokes (tools/audio/jitter_bench.gd measures the same on a real
## driver). Pure time: a headless kit has no real frames, so commit_timed() gives it the frame clock of the bench
## machine's 59.94 Hz display. Each hard constraint of the lock is one test here.

const Bench := preload("res://tools/audio/jitter_bench.gd")
const BANK := "res://tests/audio/fixtures/bank_min.json"
const NTSC_HZ := 60000.0 / 1001.0
const PATTERN: Array = [0.25, 0.75]  # "main", with power under its tick's gate
const RPMS: Array[float] = [60.0, 90.0, 110.0, 140.0]
## A frame's distance from the strokes' clock: the sawtooth's height and a little.
const LEAD_MAX_S := 0.017
## What the driver's own spread (stddev about 3.2 ms, p99 about 6 ms) leaves of the bench's 4 and 12 ms. The p99 is the
## lock finding its mean in the first 40 s after setup, when it starts on the sawtooth's edge.
const CLOCK_SD_MAX_MS := 1.5
const CLOCK_P99_MAX_MS := 4.0
const POWER := {"power": 0.2}


## The frame clock: every frame takes real_s, the view is handed nominal_s, and the debt is paid back in one frame when
## it reaches payback_s (as measured: 1 ms/s behind and 16 ms back, every 16.4 s). With an rng, each frame's timestamp
## is up to 0.5 ms off its vsync.
class Frames:
	var real_s: float
	var nominal_s: float
	var payback_s: float = 0.016
	var debt_s: float = 0.0
	var dt: float = 0.0
	var real_dt: float = 0.0
	var real_t: float = 0.0
	var rng: RandomNumberGenerator = null
	var _stamp_off_s: float = 0.0

	func _init(p_real_hz: float = NTSC_HZ, p_nominal_hz: float = 60.0) -> void:
		real_s = 1.0 / p_real_hz
		nominal_s = 1.0 / p_nominal_hz

	func next() -> void:
		real_dt = real_s
		debt_s += real_dt - nominal_s
		if rng != null:
			var off := rng.randf_range(-0.0005, 0.0005)
			real_dt += off - _stamp_off_s
			_stamp_off_s = off
		dt = nominal_s
		if debt_s >= payback_s:
			dt += debt_s
			debt_s = 0.0
		real_t += real_dt


## One machine on a silent kit, on a frame clock, with what its strokes did.
class Rider:
	var kit: GameAudioKit
	var frames: Frames
	var clock: CrankClock = CrankClock.new()
	var due: PackedFloat64Array = PackedFloat64Array()  ## real time each attack is due
	var machine: String = "main"
	var instance: String = "a"
	var first_revs: float = -1.0
	var locked: bool = true

	func _init(p_kit: GameAudioKit, p_frames: Frames) -> void:
		kit = p_kit
		frames = p_frames

	## One frame at `rpm`. Returns the strokes it started.
	func step(rpm: float) -> int:
		frames.next()
		clock.advance(rpm, frames.dt)
		return show_frame(rpm)

	## The rest of a frame, once the view has moved. Not `locked`: the view's delta passes for real time, so strokes
	## read the view's sawtooth, as they did before the lock.
	func show_frame(rpm: float) -> int:
		kit.drive(instance, machine, clock.revs, rpm, POWER, true)
		kit.commit_timed(frames.dt, frames.real_dt if locked else frames.dt)
		if first_revs < 0.0:
			first_revs = clock.revs
		var n := 0
		for k in kit.played.size():
			if kit.played[k] == "stroke":
				due.append(frames.real_t + kit.played_t[k] - kit._t)
				n += 1
		kit.clear_played()
		return n

	## The most strokes any frame started.
	func ride(rpm: float, seconds: float) -> int:
		var most := 0
		var until := frames.real_t + seconds
		while frames.real_t < until:
			most = maxi(most, step(rpm))
		return most

	func voice() -> CadenceVoice:
		return kit.machine_voice(instance)


func _kit() -> GameAudioKit:
	var kit := GameAudioKit.new()
	add_child_autofree(kit)
	assert_true(kit.setup(BANK, 7))
	assert_true(kit.silent, "headless: the kit keeps its records and starts no player")
	return kit


func _rider(frames: Frames = Frames.new()) -> Rider:
	return Rider.new(_kit(), frames)


## How many k + f of PATTERN fall in (from, to].
func _count(from: float, to: float) -> int:
	var n := 0
	for f: float in PATTERN:
		n += floori(to - f) - floori(from - f)
	return n


## The tick at 0.5 of each revolution: gated out at this power, but a hitch drops it like a stroke.
func _ticks(rider: Rider) -> int:
	return floori(rider.voice().planned_to() - 0.5) - floori(rider.first_revs - 0.5)


## The strokes from `from_i` on against the bench's own arithmetic.
func _judge(rider: Rider, rpm: float, from_i: int = 0) -> Dictionary:
	var positions := PackedFloat64Array()
	positions.resize(rider.due.size() - from_i)
	for i in positions.size():
		positions[i] = float(i) * 0.5
	var line := Bench.fit_line(positions, rider.due.slice(from_i))
	var residual := PackedFloat64Array()
	var magnitudes := PackedFloat64Array()
	for i in positions.size():
		var r := rider.due[from_i + i] - (float(line["a"]) + float(line["b"]) * positions[i])
		residual.append(r)
		magnitudes.append(absf(r))
	return {
		"p99_ms": Bench.percentile(magnitudes, 0.99) * 1000.0,
		"sd_ms": Bench.stddev(residual) * 1000.0,
		"slope_error": absf(float(line["b"]) - 60.0 / rpm) / (60.0 / rpm),
	}


func _assert_on_the_line(got: Dictionary, what: String) -> void:
	assert_lt(float(got["sd_ms"]), CLOCK_SD_MAX_MS, what + ": sd %.2f ms" % float(got["sd_ms"]))
	assert_lt(float(got["p99_ms"]), CLOCK_P99_MAX_MS, what + ": p99 %.2f ms" % float(got["p99_ms"]))
	assert_lt(float(got["slope_error"]), Bench.SLOPE_TOLERANCE, what + ": slope")


func test_a_frame_clock_on_real_time_gives_no_lead() -> void:
	var lock := FrameClockLock.new()
	for i in 1000:
		assert_eq(lock.update(1.0 / 60.0, 1.0 / 60.0), 0.0)


func test_the_lead_is_bounded_on_every_display() -> void:
	for hz: Array in [[NTSC_HZ, 60.0], [143.86, 144.0], [120000.0 / 1001.0, 120.0], [59.99, 60.0]]:
		var frames := Frames.new(hz[0], hz[1])
		var lock := FrameClockLock.new()
		var worst := 0.0
		for i in int(1800.0 * float(hz[0])):
			frames.next()
			worst = maxf(worst, absf(lock.update(frames.dt, frames.real_dt)))
		assert_lt(worst, LEAD_MAX_S, "%.2f Hz: half an hour, under one vsync" % float(hz[0]))


func test_strokes_lose_the_sawtooth_and_keep_the_view_rate() -> void:
	for rpm: float in RPMS:
		var rider := _rider()
		rider.ride(rpm, 120.0)
		var what := "%d rpm" % int(rpm)
		_assert_on_the_line(_judge(rider, rpm), what)
		var bare := _rider()
		bare.locked = false
		bare.ride(rpm, 120.0)
		assert_gt(
			float(_judge(bare, rpm)["sd_ms"]),
			Bench.STDDEV_MAX_MS,
			(
				what
				+ ": with no lock the sawtooth alone is over the limit, or this test proves nothing"
			)
		)


func test_an_hour_with_no_drift_and_no_stroke_gained_or_lost() -> void:
	const RPM := 110.0
	var rider := _rider()
	rider.frames.rng = SeededRng.make(5)
	var rate := RPM / 60.0
	var worst := 0.0
	while rider.frames.real_t < 3600.0:
		rider.step(RPM)
		var slot: GameAudioKit.MachineSlot = rider.kit._machines["a"]
		worst = maxf(worst, absf(slot.lead_revs) / rate)
		rider.due.clear()
	assert_lt(worst, LEAD_MAX_S, "the crank on screen and its stroke, in time, after an hour")
	var voice := rider.voice()
	assert_eq(voice.fired, _count(rider.first_revs, voice.planned_to()), "every stroke, once")
	assert_eq(voice.dropped, 0)
	assert_lt(absf(voice.planned_to() - rider.clock.revs), rate * (0.05 + LEAD_MAX_S), "still here")


## Anywhere in the cycle, with the view on either side of the strokes.
func test_a_dead_stop_stops_the_strokes_and_the_loops() -> void:
	var rider := _rider()
	var rng := SeededRng.make(9)
	var seen_ahead := false
	var seen_behind := false
	for stop in 40:
		rider.ride(90.0, rng.randf_range(1.0, 2.2))
		var lead := rider.kit.frame_lead_s()
		seen_ahead = seen_ahead or lead > 0.002
		seen_behind = seen_behind or lead < -0.002
		var loop := rider.kit.machine_loop("a")
		var what := "stop %d, lead %.1f ms" % [stop, lead * 1000.0]
		assert_eq(loop.on[0], 1, what + ": precondition: the body loop runs")
		var stop_t := rider.frames.real_t
		for k in rider.due.size():
			assert_lte(rider.due[k], stop_t + GameAudioKit.HORIZON_MAX_S, what + ": by the horizon")
		rider.due.clear()
		var off_after := -1.0
		while rider.frames.real_t < stop_t + 0.4:
			assert_eq(rider.step(0.0), 0, what + ": no stroke starts once the crank stands")
			if off_after < 0.0 and loop.all_off():
				off_after = rider.frames.real_t - stop_t
		assert_between(off_after, 0.0, 0.12, what + ": loops off")
	assert_true(seen_ahead and seen_behind, "precondition: stops on both sides of the lock")
	var voice := rider.voice()
	assert_eq(voice.fired, _count(rider.first_revs, voice.planned_to()), "none lost at a stop")
	assert_eq(voice.dropped, 0)


func test_coasting_and_a_resume_are_no_burst() -> void:
	var rider := _rider()
	rider.ride(90.0, 20.0)
	for i in 180:
		assert_lte(rider.step(lerpf(90.0, 0.0, float(i) / 179.0)), 1, "coasting down")
	assert_eq(rider.ride(0.0, 2.0), 0, "standing")
	for i in 60:
		assert_lte(rider.step(90.0), 1, "no burst on the first frames back")
	var voice := rider.voice()
	assert_eq(voice.dropped, 0)
	assert_eq(voice.fired, _count(rider.first_revs, voice.planned_to()))


func test_a_pause_is_silent_and_its_resume_is_no_burst() -> void:
	var rider := _rider()
	rider.ride(90.0, 20.0)
	var dropped := rider.voice().dropped
	rider.due.clear()
	rider.kit._on_paused_changed(true, "test")
	assert_eq(rider.ride(90.0, 6.0), 0, "the view runs on under a pause, the strokes do not")
	assert_eq(rider.due.size(), 0)
	assert_true(rider.kit.machine_loop("a").all_off())
	rider.kit._on_paused_changed(false, "test")
	var strokes := 0
	for i in 60:
		var n := rider.step(90.0)
		assert_lte(n, 1, "no burst on resume")
		strokes += n
	assert_between(strokes, 2, 4, "one second, three strokes a second")
	assert_eq(rider.voice().dropped, dropped, "nothing saved up, so nothing dropped")


## A jump lands at once: the strokes' place is the view's next frame, with nothing fired for the revs it crossed and no
## slew afterwards, so what follows is a straight line from the first stroke on.
func test_a_jump_ahead_snaps() -> void:
	for jump: float in [0.4, 3.0, 500.0]:
		var rider := _rider()
		rider.ride(90.0, 20.0)
		rider.due.clear()
		rider.clock.revs += jump
		var what := "%.1f revs ahead" % jump
		assert_lte(rider.step(90.0), 1, what + ": no rush")
		assert_lt(
			absf(rider.voice().planned_to() - rider.clock.revs), 1.5 * 0.06, what + ": at once"
		)
		rider.due.clear()
		rider.ride(90.0, 20.0)
		_assert_on_the_line(_judge(rider, 90.0), what + ": no slew")


func test_a_jump_back_repeats_nothing_and_a_long_one_snaps() -> void:
	var small := _rider()
	small.ride(90.0, 20.0)
	var reached := small.voice().planned_to()
	var fired := small.voice().fired
	small.clock.revs -= 0.4
	assert_eq(small.step(90.0), 0, "under a revolution back: nothing twice")
	assert_eq(small.voice().fired, fired)
	while small.clock.revs < reached - 1.5 * 0.05:
		assert_eq(small.step(90.0), 0, "until the view is back where the strokes were")
	small.due.clear()
	small.ride(90.0, 2.0)
	assert_between(small.due.size(), 5, 7, "then on as before")
	var long := _rider()
	long.ride(90.0, 20.0)
	long.clock.revs -= 300.0
	long.due.clear()
	assert_lte(long.step(90.0), 1, "a rejoin far back: no rush")
	assert_lt(absf(long.voice().planned_to() - long.clock.revs), 1.5 * 0.06, "at once")


func test_a_seat_change_and_a_rejoin_start_clean() -> void:
	var rider := _rider()
	rider.ride(90.0, 20.0)
	var was := rider.voice()
	rider.kit.drive("a", "other", 7000.0, 90.0, {}, true)
	rider.kit.commit_timed(rider.frames.dt, rider.frames.real_dt)
	assert_ne(rider.kit.machine_voice("a"), was, "another machine on the seat: another voice")
	assert_lte(rider.kit.played.size(), 1, "no rush")
	rider.kit.clear_played()
	rider.instance = "b"
	rider.clock.revs = 123456.0
	assert_lte(rider.step(90.0), 1, "a new instance far along: no rush")
	assert_lt(absf(rider.voice().planned_to() - rider.clock.revs), 1.5 * 0.06, "and it is there")


func test_a_sprint_keeps_every_stroke_and_holds_once_settled() -> void:
	var rider := _rider()
	rider.frames.rng = SeededRng.make(3)
	rider.ride(70.0, 10.0)
	var ramp_frames := int(2.0 * NTSC_HZ)
	for i in ramp_frames:
		assert_lte(rider.step(lerpf(70.0, 130.0, float(i + 1) / float(ramp_frames))), 1, "ramp")
	rider.ride(130.0, 1.0)
	var settled := rider.due.size()
	rider.ride(130.0, 20.0)
	var voice := rider.voice()
	assert_eq(voice.fired, _count(rider.first_revs, voice.planned_to()), "every stroke")
	assert_eq(voice.dropped, 0)
	assert_eq(voice.late, 0)
	_assert_on_the_line(_judge(rider, 130.0, settled), "settled")


func test_a_step_in_cadence_keeps_every_stroke() -> void:
	var rider := _rider()
	rider.ride(70.0, 12.0)
	assert_lte(rider.ride(130.0, 12.0), 1, "no burst")
	assert_lte(rider.ride(70.0, 12.0), 1, "either way")
	var voice := rider.voice()
	assert_eq(voice.fired, _count(rider.first_revs, voice.planned_to()))
	assert_eq(voice.dropped, 0)


func test_a_hitch_drops_what_is_too_old_and_fires_no_burst() -> void:
	var rider := _rider()
	rider.ride(140.0, 20.0)
	rider.frames.next()
	rider.frames.dt += 0.75
	rider.frames.real_dt += 0.75
	rider.frames.real_t += 0.75
	rider.clock.advance(140.0, rider.frames.dt)
	assert_lte(rider.show_frame(140.0), 1, "no burst")
	assert_gt(rider.voice().dropped, 0, "what the hitch passed is gone")
	assert_eq(
		rider.voice().fired + rider.voice().dropped + rider.voice().gated,
		_count(rider.first_revs, rider.voice().planned_to()) + _ticks(rider),
		"fired + dropped + gated exact"
	)


## A gap between commits: the lock follows the frames at once.
func test_a_gap_between_commits_snaps_the_lock() -> void:
	var lock := FrameClockLock.new()
	for i in 600:
		lock.update(1.0 / 60.0, 1.0 / 59.94)
	assert_lt(absf(lock.lead_s), LEAD_MAX_S)
	assert_eq(lock.update(1.0 / 60.0, 5.0), 0.0, "five seconds with no commit")
	assert_lt(absf(lock.update(1.0 / 60.0, 1.0 / 59.94)), 0.001, "and on from there")
	lock.reset()
	assert_eq(lock.lead_s, 0.0)


func test_the_lead_settles_on_frames_that_drift_for_good() -> void:
	var lock := FrameClockLock.new()
	var worst := 0.0
	for i in 60 * 600:
		worst = maxf(worst, absf(lock.update(1.0 / 60.0, (1.0 / 60.0) * 1.001)))
	assert_lt(worst, FrameClockLock.SNAP_S, "0.1 % for ten minutes needs no snap")
	assert_almost_eq(lock.lead_s, -0.001 * FrameClockLock.TAU_S, 0.001, "the lag TAU_S gives")


func test_headless_reads_no_clock_and_stays_deterministic() -> void:
	var a := _kit()
	var b := _kit()
	for kit: GameAudioKit in [a, b]:
		var clock := CrankClock.new()
		for i in 600:
			clock.advance(90.0, 1.0 / 60.0)
			kit.drive("a", "main", clock.revs, 90.0, POWER, true)
			if kit == b and i % 60 == 0:
				OS.delay_msec(5)
			kit.commit(1.0 / 60.0)
			assert_eq(kit.frame_lead_s(), 0.0, "silent: real time is the delta")
	assert_gt(a.played.size(), 0)
	assert_eq(a.played, b.played)
	assert_eq(a.played_t, b.played_t, "a slower machine changes nothing")


func test_setup_starts_the_lock_again() -> void:
	var rider := _rider()
	rider.ride(90.0, 12.0)
	assert_gt(absf(rider.kit.frame_lead_s()), 0.001, "precondition: the lock has a lead")
	assert_true(rider.kit.setup(BANK, 7))
	assert_eq(rider.kit.frame_lead_s(), 0.0)


func test_audio_stays_away_from_the_trainer_and_the_sim() -> void:
	for path: String in [
		"res://addons/wattlands/audio/frame_clock_lock.gd",
		"res://addons/wattlands/audio/game_audio_kit.gd",
		"res://addons/wattlands/audio/cadence_voice.gd",
	]:
		var text := FileAccess.get_file_as_string(path)
		assert_gt(text.length(), 0, path)
		for word: String in ["directives", "Trainer", "SafetyGovernor", "GameContext", "ctx."]:
			assert_false(text.contains(word), "%s reads no %s" % [path, word])


## D10 is 0.5 ms for a whole commit, which the bench times; this is what the lock adds to it.
func test_the_lock_costs_a_small_share_of_d10() -> void:
	var lock := FrameClockLock.new()
	var t0 := Time.get_ticks_usec()
	for i in 20000:
		lock.update(1.0 / 60.0, 1.0 / 59.94)
	assert_lt(float(Time.get_ticks_usec() - t0) / 20000.0, 50.0, "microseconds a frame")
