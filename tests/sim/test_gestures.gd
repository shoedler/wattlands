# gdlint: disable=max-public-methods
extends GutTest
## GestureRecognizer (BRIEF 3.5) on synthetic ~1 Hz streams: pedal_start (3 s), surge outside
## ERG (1.3 x and +40 W branches, two samples) and inside ERG (flywheel speed 1.12 x),
## not_pedaling, coast (3 s, never in ERG), stop_5s (solo, outside ERG), arbitration and
## re-arming. Times come only from TrainerSample.t.

const FTP := 200.0

var _g: GestureRecognizer = null


func before_each() -> void:
	_g = GestureRecognizer.new()
	_g.configure(FTP, true)


func _s(t: float, power: float, cadence: float = 90.0, speed: float = -1.0) -> TrainerSample:
	return TrainerSample.make(t, power, cadence, speed)


## Feeds one sample per second from t0 (t0, t0 + 1, ...) and returns every gesture with its t.
func _feed(
	g: GestureRecognizer,
	t0: float,
	seconds: int,
	power: float,
	cadence: float = 90.0,
	speed: float = -1.0
) -> Array:
	var out: Array = []
	for i in seconds:
		var t := t0 + i
		for name in g.on_sample(_s(t, power, cadence, speed)):
			out.append([t, name])
	return out


func _names(events: Array) -> Array:
	var out: Array = []
	for e: Array in events:
		out.append(e[1])
	return out


## A recognizer that has pedaled at `power` (and `speed`) from t = 0 to t = 11 (12 samples).
func _warmed(power: float, speed: float = -1.0, in_erg: bool = false) -> GestureRecognizer:
	var g := GestureRecognizer.new()
	g.configure(FTP, true)
	g.set_erg(in_erg)
	var ev := _feed(g, 0.0, 12, power, 90.0, speed)
	assert_eq(_names(ev), [Wl.G_PEDAL_START], "only pedal_start while warming up")
	assert_true(g.is_pedaling())
	return g


# ------------------------------------------------------------------------ not_pedaling


func test_not_pedaling_thresholds() -> void:
	assert_true(GestureRecognizer.is_not_pedaling(14.9, 19.9))
	assert_true(GestureRecognizer.is_not_pedaling(0.0, 0.0))
	assert_false(GestureRecognizer.is_not_pedaling(15.0, 0.0), "15 W is pedaling")
	assert_false(GestureRecognizer.is_not_pedaling(0.0, 20.0), "20 rpm is pedaling")
	assert_true(GestureRecognizer.is_not_pedaling(10.0, -1.0), "no cadence: power alone")
	var g := GestureRecognizer.new()
	g.on_sample(_s(0.0, 14.0, -1.0))
	assert_true(g.not_pedaling(), "a sample without cadence uses power only")


func test_not_pedaling_state_and_timing() -> void:
	watch_signals(_g)
	_feed(_g, 0.0, 5, 150.0)
	assert_false(_g.not_pedaling())
	assert_eq(_g.not_pedaling_s(), 0.0)
	assert_eq(_g.not_pedaling_since(), -1.0)
	_g.on_sample(_s(5.2, 10.0, 15.0))
	assert_true(_g.not_pedaling())
	assert_eq(_g.not_pedaling_since(), 5.2, "timed from the first sample that meets it")
	assert_eq(_g.not_pedaling_s(), 0.0)
	_g.on_sample(_s(6.3, 0.0, 0.0))
	assert_almost_eq(_g.not_pedaling_s(), 1.1, 1e-9)
	assert_almost_eq(_g.not_pedaling_s_at(7.0), 1.8, 1e-9, "between samples")
	assert_signal_emit_count(_g, "not_pedaling_changed", 1)
	assert_signal_emitted_with_parameters(_g, "not_pedaling_changed", [true])
	_g.on_sample(_s(7.3, 100.0, 80.0))
	assert_false(_g.not_pedaling())
	assert_eq(_g.not_pedaling_s(), 0.0)
	assert_eq(_g.not_pedaling_s_at(8.0), 0.0)
	assert_signal_emit_count(_g, "not_pedaling_changed", 2)
	assert_signal_emitted_with_parameters(_g, "not_pedaling_changed", [false])
	assert_eq(GestureRecognizer.NOT_PEDALING, &"not_pedaling")
	assert_false(Wl.GESTURES.has(GestureRecognizer.NOT_PEDALING), "a state, never a fired gesture")


# ------------------------------------------------------------------------- pedal_start


func test_pedal_start_by_cadence_after_3_s() -> void:
	var ev := _feed(_g, 0.0, 10, 0.0, 45.0)
	assert_eq(ev, [[3.0, Wl.G_PEDAL_START]], "cadence >= 40 for 3 s, once")


func test_pedal_start_by_power_30_pct() -> void:
	var ev := _feed(_g, 0.0, 6, 60.0, -1.0)
	assert_eq(ev, [[3.0, Wl.G_PEDAL_START]], "60 W is 30% of 200 W")
	var g := GestureRecognizer.new()
	g.configure(FTP, true)
	assert_eq(_feed(g, 0.0, 10, 59.0, 39.0), [], "below 30% FTP and below 40 rpm never starts")


func test_pedal_start_needs_3_continuous_seconds() -> void:
	var ev: Array = []
	ev.append_array(_feed(_g, 0.0, 3, 120.0, 85.0))
	# A soft-pedal dip: neither pedaling (< 40 rpm, < 60 W) nor stopped.
	ev.append_array(_feed(_g, 3.0, 1, 30.0, 30.0))
	assert_eq(ev, [], "broken at t = 3")
	ev.append_array(_feed(_g, 4.0, 4, 120.0, 85.0))
	assert_eq(ev, [[7.0, Wl.G_PEDAL_START]], "timed again from t = 4")


func test_pedal_start_with_jittered_samples() -> void:
	var times: Array[float] = [0.0, 1.05, 1.95, 2.9, 3.95, 5.0]
	var fired_at := -1.0
	for t in times:
		if _g.on_sample(_s(t, 150.0, 85.0)).has(Wl.G_PEDAL_START):
			fired_at = t
	assert_eq(fired_at, 3.95, "the first sample at least 3 s after the first one")


func test_pedal_start_rearms_only_after_not_pedaling() -> void:
	var ev: Array = []
	ev.append_array(_feed(_g, 0.0, 6, 150.0))
	ev.append_array(_feed(_g, 6.0, 2, 30.0, 30.0))  # soft-pedal dip: no re-arm
	ev.append_array(_feed(_g, 8.0, 6, 150.0))
	assert_eq(_names(ev), [Wl.G_PEDAL_START], "one start")
	ev.clear()
	ev.append_array(_feed(_g, 14.0, 1, 0.0, 0.0))  # one stopped sample re-arms
	ev.append_array(_feed(_g, 15.0, 5, 150.0))
	assert_eq(ev, [[18.0, Wl.G_PEDAL_START]], "a new start after a stop")


# ----------------------------------------------------------------------- surge outside ERG


func test_surge_ratio_branch_at_200_w() -> void:
	# Baseline 200 W: max(1.3 x 200, 200 + 40) = 260 W.
	var g := _warmed(200.0)
	assert_almost_eq(g.surge_baseline(), 200.0, 1e-9)
	assert_eq(_feed(g, 12.0, 2, 259.0), [], "259 W is below 1.3 x 200")
	var h := _warmed(200.0)
	assert_eq(_feed(h, 12.0, 2, 260.0), [[13.0, Wl.G_SURGE]], "260 W on the second sample")
	var k := _warmed(200.0)
	assert_eq(_feed(k, 12.0, 2, 250.0), [], "+40 W alone is not enough at 200 W")


func test_surge_plus_40_branch_at_100_w() -> void:
	# Baseline 100 W: max(130, 140) = 140 W.
	var g := _warmed(100.0)
	assert_eq(_feed(g, 12.0, 2, 135.0), [], "1.3 x alone is not enough at 100 W")
	var h := _warmed(100.0)
	assert_eq(_feed(h, 12.0, 2, 139.0), [])
	var k := _warmed(100.0)
	assert_eq(_feed(k, 12.0, 2, 140.0), [[13.0, Wl.G_SURGE]], "baseline + 40 W, inclusive")


func test_surge_needs_two_consecutive_samples() -> void:
	var g := _warmed(200.0)
	var ev: Array = []
	ev.append_array(_feed(g, 12.0, 1, 400.0))
	ev.append_array(_feed(g, 13.0, 1, 200.0))
	ev.append_array(_feed(g, 14.0, 1, 400.0))
	ev.append_array(_feed(g, 15.0, 1, 200.0))
	assert_eq(ev, [], "single-sample spikes never surge")


func test_surge_baseline_is_frozen_for_the_streak() -> void:
	# Against a rolling average the second 265 W sample would face 1.3 x 206.5 = 268.5 W.
	var g := _warmed(200.0)
	assert_eq(_feed(g, 12.0, 2, 265.0), [[13.0, Wl.G_SURGE]])


func test_surge_fires_once_per_streak_and_rearms() -> void:
	var g := _warmed(200.0)
	var ev := _feed(g, 12.0, 4, 300.0)
	assert_eq(ev, [[13.0, Wl.G_SURGE]], "a held surge fires once")
	ev = _feed(g, 16.0, 12, 200.0)
	assert_eq(ev, [], "back to the base")
	ev = _feed(g, 28.0, 2, 300.0)
	assert_eq(ev, [[29.0, Wl.G_SURGE]], "re-armed by the samples that did not qualify")


func test_surge_ignores_duplicate_notifications() -> void:
	var g := _warmed(200.0)
	assert_eq(g.on_sample(_s(12.0, 300.0)), [])
	assert_eq(g.on_sample(_s(12.1, 300.0)), [], "two samples 0.1 s apart are not 1.5 s")
	assert_eq(g.on_sample(_s(13.0, 300.0)), [Wl.G_SURGE])


func test_surge_outside_erg_ignores_speed() -> void:
	var g := _warmed(200.0, 36.0)
	assert_eq(_feed(g, 12.0, 3, 200.0, 90.0, 45.0), [], "a speed jump at constant power")


func test_surge_needs_established_pedaling() -> void:
	# Pedaling starts at 100 W; a jump to 250 W at t = 3 and 4 is part of starting, not a surge.
	var ev: Array = []
	ev.append_array(_feed(_g, 0.0, 3, 100.0))
	ev.append_array(_feed(_g, 3.0, 2, 250.0))
	assert_eq(_names(ev), [Wl.G_PEDAL_START])
	# Soft pedaling never establishes pedaling, so a jump from it is no surge either.
	var g := GestureRecognizer.new()
	g.configure(FTP, true)
	var ev2: Array = []
	ev2.append_array(_feed(g, 0.0, 12, 30.0, 30.0))
	ev2.append_array(_feed(g, 12.0, 2, 150.0, 85.0))
	assert_eq(ev2, [], "no surge before pedal_start")


func test_surge_baseline_needs_5_s_since_the_last_stop() -> void:
	var g := _warmed(200.0)
	_feed(g, 12.0, 1, 0.0, 0.0)
	assert_false(g.is_pedaling(), "a stop ends the start")
	var ev := _feed(g, 13.0, 4, 200.0)
	assert_eq(_names(ev), [Wl.G_PEDAL_START], "restart at t = 16")
	assert_eq(g.surge_baseline(), -1.0, "4 s of history since the stop")
	ev = _feed(g, 17.0, 2, 300.0)
	assert_eq(ev, [], "t = 17: only 4 s of history before the streak")
	ev = _feed(g, 19.0, 3, 200.0)
	ev.append_array(_feed(g, 22.0, 2, 300.0))
	assert_eq(ev, [[23.0, Wl.G_SURGE]], "enough history now")


func test_surge_never_while_not_pedaling() -> void:
	var g := _warmed(200.0)
	assert_eq(_feed(g, 12.0, 2, 10.0, 10.0), [], "stopping is no surge")
	assert_true(g.not_pedaling())


# ------------------------------------------------------------------------- surge in ERG


func test_surge_in_erg_uses_flywheel_speed() -> void:
	# Baseline 36 km/h: 1.12 x 36 = 40.32 km/h.
	var g := _warmed(200.0, 36.0, true)
	assert_almost_eq(g.surge_baseline(), 36.0, 1e-9)
	assert_eq(_feed(g, 12.0, 2, 200.0, 95.0, 40.3), [], "below 1.12 x")
	var h := _warmed(200.0, 36.0, true)
	assert_eq(_feed(h, 12.0, 2, 200.0, 95.0, 40.32), [[13.0, Wl.G_SURGE]], "1.12 x, inclusive")


func test_power_jump_in_erg_is_no_surge() -> void:
	var g := _warmed(200.0, 36.0, true)
	assert_eq(_feed(g, 12.0, 3, 400.0, 90.0, 36.0), [], "in ERG power is held; only speed counts")


func test_erg_surge_without_speed_never_fires() -> void:
	var g := _warmed(200.0, -1.0, true)
	assert_eq(g.surge_baseline(), -1.0)
	assert_eq(_feed(g, 12.0, 3, 400.0), [])


func test_mode_switch_drops_a_streak() -> void:
	var g := _warmed(200.0, 36.0)
	assert_eq(_feed(g, 12.0, 1, 300.0, 90.0, 36.0), [])
	g.set_erg(true)
	assert_eq(_feed(g, 13.0, 1, 300.0, 90.0, 36.0), [], "the power streak doesn't carry into ERG")


func test_ten_mock_like_surges_give_ten_gestures() -> void:
	# MockTrainer's surge profile (BRIEF 4.2, OWNERSHIP C30): every 60 s the reported speed
	# rises by 20% for 2 s; notifications every 0.9-1.1 s and each surge spans at least two.
	var g := GestureRecognizer.new()
	g.configure(FTP, true)
	g.set_erg(true)
	var rng := SeededRng.make(1234)
	var t := 0.0
	var surges := 0
	var windows: Array = []
	for k in 10:
		windows.append(30.0 + 60.0 * k)
	while t < 640.0:
		var lift := false
		for w: float in windows:
			if t >= w and t < w + 2.0:
				lift = true
		var speed := 36.0 * (1.2 if lift else 1.0)
		for name in g.on_sample(_s(t, 200.0, 90.0, speed)):
			if name == Wl.G_SURGE:
				surges += 1
		# Land at least two notifications inside each 2 s window.
		var step := SeededRng.range_f(rng, 0.9, 1.1)
		for w: float in windows:
			if t < w and t + step > w:
				step = w - t + 0.05
		t += step
	assert_eq(surges, 10)


# ------------------------------------------------------------------------ coast, stop_5s


func test_coast_at_3_s_outside_erg() -> void:
	_feed(_g, 0.0, 5, 150.0)
	var ev := _feed(_g, 5.0, 4, 0.0, 0.0)
	assert_eq(ev, [[8.0, Wl.G_COAST]], "3 s after the first stopped sample (t = 5)")


func test_coast_never_in_erg() -> void:
	_g.set_erg(true)
	_feed(_g, 0.0, 5, 150.0)
	var ev := _feed(_g, 5.0, 8, 0.0, 0.0)
	assert_eq(ev, [], "no coast and no stop_5s in ERG")
	_g.set_erg(false)
	ev = _feed(_g, 13.0, 5, 0.0, 0.0)
	assert_eq(ev, [], "leaving ERG later in the same stop fires nothing stale")
	ev = _feed(_g, 18.0, 2, 150.0)
	ev.append_array(_feed(_g, 20.0, 4, 0.0, 0.0))
	assert_eq(ev, [[23.0, Wl.G_COAST]], "the next stop outside ERG coasts")


func test_stop_5s_solo_only() -> void:
	_feed(_g, 0.0, 5, 150.0)
	var ev := _feed(_g, 5.0, 10, 0.0, 0.0)
	assert_eq(
		ev,
		[[8.0, Wl.G_COAST], [10.0, Wl.G_STOP_5S]],
		"solo: coast at 3 s, stop_5s at 5 s, once each"
	)
	var multi := GestureRecognizer.new()
	multi.configure(FTP, false)
	_feed(multi, 0.0, 5, 150.0)
	ev = _feed(multi, 5.0, 10, 0.0, 0.0)
	assert_eq(ev, [[8.0, Wl.G_COAST]], "multiplayer: coast only")


func test_coast_and_stop_rearm_per_stop() -> void:
	var ev: Array = []
	ev.append_array(_feed(_g, 0.0, 5, 150.0))
	ev.append_array(_feed(_g, 5.0, 6, 0.0, 0.0))
	ev.append_array(_feed(_g, 11.0, 2, 150.0))
	ev.append_array(_feed(_g, 13.0, 4, 0.0, 0.0))
	assert_eq(
		ev, [[3.0, Wl.G_PEDAL_START], [8.0, Wl.G_COAST], [10.0, Wl.G_STOP_5S], [16.0, Wl.G_COAST]]
	)


func test_short_stop_is_no_coast() -> void:
	_feed(_g, 0.0, 5, 150.0)
	var ev := _feed(_g, 5.0, 3, 0.0, 0.0)
	ev.append_array(_feed(_g, 8.0, 3, 150.0))
	assert_eq(ev, [], "2 s stopped")


func test_arbitration_over_a_whole_ride() -> void:
	var ev: Array = []
	ev.append_array(_feed(_g, 0.0, 15, 200.0))  # pedal_start at 3
	ev.append_array(_feed(_g, 15.0, 2, 300.0))  # surge at 16
	ev.append_array(_feed(_g, 17.0, 3, 200.0))
	ev.append_array(_feed(_g, 20.0, 7, 0.0, 0.0))  # coast at 23, stop_5s at 25
	ev.append_array(_feed(_g, 27.0, 6, 200.0))  # pedal_start at 30
	ev.append_array(_feed(_g, 33.0, 2, 300.0))  # 6 s since the stop: surge at 34
	assert_eq(
		ev,
		[
			[3.0, Wl.G_PEDAL_START],
			[16.0, Wl.G_SURGE],
			[23.0, Wl.G_COAST],
			[25.0, Wl.G_STOP_5S],
			[30.0, Wl.G_PEDAL_START],
			[34.0, Wl.G_SURGE]
		]
	)


func test_advance_fires_between_samples() -> void:
	_g.on_sample(_s(0.0, 0.0, 0.0))
	_g.on_sample(_s(1.0, 0.0, 0.0))
	_g.on_sample(_s(2.0, 0.0, 0.0))
	assert_eq(_g.advance(2.95), [])
	assert_eq(_g.advance(3.0), [Wl.G_COAST], "on time, not at the next sample")
	assert_eq(_g.advance(3.05), [], "once")
	assert_eq(_g.advance(4.6), [], "2.6 s after the last sample: too stale to hold")
	_g.on_sample(_s(4.4, 0.0, 0.0))
	assert_eq(_g.advance(5.0), [Wl.G_STOP_5S])
	assert_eq(_g.on_sample(_s(5.4, 0.0, 0.0)), [], "already fired by advance")
	var p := GestureRecognizer.new()
	p.configure(FTP, true)
	p.on_sample(_s(0.0, 150.0, 85.0))
	p.on_sample(_s(1.0, 150.0, 85.0))
	p.on_sample(_s(2.0, 150.0, 85.0))
	assert_eq(p.advance(3.0), [Wl.G_PEDAL_START])
	assert_eq(GestureRecognizer.new().advance(10.0), [], "nothing before the first sample")


func test_gesture_signal() -> void:
	watch_signals(_g)
	_feed(_g, 0.0, 5, 150.0)
	_feed(_g, 5.0, 6, 0.0, 0.0)
	assert_signal_emit_count(_g, "gesture", 3)
	var params: Array = get_signal_parameters(_g, "gesture", 0)
	assert_eq(params, [Wl.G_PEDAL_START])
	assert_eq(get_signal_parameters(_g, "gesture", 1), [Wl.G_COAST])
	assert_eq(get_signal_parameters(_g, "gesture", 2), [Wl.G_STOP_5S])


func test_older_samples_are_ignored() -> void:
	_g.on_sample(_s(5.0, 0.0, 0.0))
	assert_eq(_g.on_sample(_s(4.0, 150.0, 90.0)), [])
	assert_true(_g.not_pedaling(), "the older sample changed nothing")


func test_reset_clears_state_but_keeps_configuration() -> void:
	_g.configure(250.0, false)
	_g.set_erg(true)
	_feed(_g, 0.0, 12, 150.0, 90.0, 36.0)
	_feed(_g, 12.0, 2, 0.0, 0.0)
	_g.reset()
	assert_false(_g.not_pedaling())
	assert_false(_g.is_pedaling())
	assert_eq(_g.not_pedaling_s(), 0.0)
	assert_eq(_g.surge_baseline(), -1.0)
	assert_eq(_g.ftp_w, 250.0)
	assert_false(_g.solo)
	assert_true(_g.in_erg)
	assert_eq(_feed(_g, 0.0, 4, 150.0), [[3.0, Wl.G_PEDAL_START]], "time may restart after a reset")


func test_random_streams_keep_the_rules() -> void:
	# Seeded random rides (stops, soft pedaling, steady pedaling, surges, 0.8-1.2 s jitter) in
	# every ERG/solo combination. Checks every fired gesture against BRIEF 3.5 and that each
	# long enough stop fires exactly what it should.
	var rng := SeededRng.make(31337)
	var fired_total := {}
	for run in 120:
		var in_erg := run % 2 == 1
		var solo := run % 4 < 2
		var g := GestureRecognizer.new()
		g.configure(FTP, solo)
		g.set_erg(in_erg)
		var t := 0.0
		var stop_first := -1.0
		var stop_last := -1.0
		var stop_fired: Array = []
		var cond_since := -1.0
		var armed := true
		var surge_ok_since := -1.0
		for seg in 25:
			var kind := SeededRng.range_i(rng, 0, 3)
			var n := SeededRng.range_i(rng, 1, 12)
			var base := SeededRng.range_f(rng, 80.0, 300.0)
			for k in n:
				var power := 0.0
				var cadence := 0.0
				match kind:
					0:
						power = SeededRng.range_f(rng, 0.0, 14.0)
						cadence = SeededRng.range_f(rng, 0.0, 19.0)
					1:
						power = SeededRng.range_f(rng, 15.0, 55.0)
						cadence = SeededRng.range_f(rng, 20.0, 39.0)
					2:
						power = base
						cadence = 90.0
					_:
						power = base * (1.6 if k < 3 else 1.0)
						cadence = 90.0 * (1.2 if k < 3 else 1.0)
				var speed := cadence * 0.4
				var np := GestureRecognizer.is_not_pedaling(power, cadence)
				var cond := not np and (cadence >= 40.0 or power >= 0.3 * FTP)
				if np:
					if stop_first < 0.0:
						stop_first = t
						stop_fired = []
					stop_last = t
					armed = true
					cond_since = -1.0
					surge_ok_since = -1.0
				else:
					if stop_first >= 0.0:
						_check_stop(stop_first, stop_last, stop_fired, in_erg, solo, "run %d" % run)
						stop_first = -1.0
					if cond and cond_since < 0.0:
						cond_since = t
					elif not cond:
						cond_since = -1.0
				var out := g.on_sample(_s(t, power, cadence, speed))
				for name: StringName in out:
					fired_total[name] = true
					var tag := "run %d t %.2f %s" % [run, t, name]
					match name:
						Wl.G_PEDAL_START:
							assert_true(armed, tag + ": once per start")
							assert_true(
								cond and t - cond_since >= 3.0 - 1e-6, tag + ": 3 s of pedaling"
							)
							armed = false
							surge_ok_since = t
						Wl.G_SURGE:
							assert_false(np, tag + ": never while not pedaling")
							assert_true(surge_ok_since >= 0.0, tag + ": after pedal_start")
						Wl.G_COAST, Wl.G_STOP_5S:
							assert_true(np, tag + ": only while stopped")
							stop_fired.append(name)
				t += SeededRng.range_f(rng, 0.8, 1.2)
		if stop_first >= 0.0:
			_check_stop(stop_first, stop_last, stop_fired, in_erg, solo, "run %d (end)" % run)
	for name in Wl.GESTURES:
		assert_true(fired_total.has(name), "%s seen in the sweep" % name)


## What one stop (first and last stopped sample) must have fired.
func _check_stop(
	first: float, last: float, fired: Array, in_erg: bool, solo: bool, what: String
) -> void:
	var held := last - first
	var want: Array = []
	if not in_erg and held >= 3.0 - 1e-6:
		want.append(Wl.G_COAST)
	if not in_erg and solo and held >= 5.0 - 1e-6:
		want.append(Wl.G_STOP_5S)
	assert_eq(
		fired,
		want,
		"%s: stop from %.2f to %.2f (erg %s, solo %s)" % [what, first, last, in_erg, solo]
	)


func test_returned_and_emitted_gestures_are_wl_names() -> void:
	var seen := {}
	var g := GestureRecognizer.new()
	g.configure(FTP, true)
	var all: Array = []
	all.append_array(_feed(g, 0.0, 15, 200.0))
	all.append_array(_feed(g, 15.0, 2, 300.0))
	all.append_array(_feed(g, 17.0, 7, 0.0, 0.0))
	for e: Array in all:
		seen[e[1]] = true
		assert_true(Wl.GESTURES.has(e[1]), "%s is a Wl gesture" % e[1])
	assert_eq(seen.size(), 4, "pedal_start, surge, coast and stop_5s all seen")
