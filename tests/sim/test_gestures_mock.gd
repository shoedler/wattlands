extends GutTest
## GestureRecognizer fed by MockTrainer's own jittered ~1 Hz notifications (BRIEF 4.2):
## the way LocalRider wires it, with on_sample() per notification and advance(t) per tick.
## Timings are measured from the mock's first notification, so they hold whatever its
## notification schedule is.

const DT := Wl.SIM_DT


class Run:
	extends RefCounted
	var events: Array = []
	var g: GestureRecognizer = null
	var first_t: float = -1.0
	var first_np_t: float = -1.0
	var samples: int = 0

	func on_sample(s: TrainerSample) -> void:
		if first_t < 0.0:
			first_t = s.t
		samples += 1
		for name in g.on_sample(s):
			events.append([s.t, name])
		if g.not_pedaling() and first_np_t < 0.0:
			first_np_t = g.not_pedaling_since()


func _ride(spec: String, seconds: float, seed: int, solo: bool = true) -> Run:
	var m := MockTrainer.from_spec(spec, 200.0, {"seed": seed})
	autofree(m)
	var run := Run.new()
	run.g = GestureRecognizer.new()
	run.g.configure(200.0, solo)
	m.sample_received.connect(run.on_sample)
	for i in roundi(seconds / DT):
		m.tick(DT)
		for name in run.g.advance(m.platform_time_s()):
			run.events.append([m.platform_time_s(), name])
	return run


func _names(events: Array) -> Array:
	var out: Array = []
	for e: Array in events:
		out.append(e[1])
	return out


func test_const_rider_starts_once_on_time() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var run := _ride("const:w=150,rpm=90", 30.0, seed)
		assert_gt(run.samples, 20, "seed %d: about 1 Hz notifications" % seed)
		assert_eq(_names(run.events), [Wl.G_PEDAL_START], "seed %d" % seed)
		var after: float = float(run.events[0][0]) - run.first_t
		assert_between(
			after,
			3.0 - 1e-6,
			3.0 + DT + 1e-6,
			"seed %d: within one tick of 3 s after the first notification" % seed
		)


func test_zero_rider_coasts_and_stops_on_time() -> void:
	for seed in [1, 2, 3]:
		var run := _ride("zero", 12.0, seed)
		assert_eq(_names(run.events), [Wl.G_COAST, Wl.G_STOP_5S], "seed %d" % seed)
		var since := run.first_np_t
		assert_eq(since, run.first_t, "the first notification already meets not_pedaling")
		assert_between(
			float(run.events[0][0]) - since,
			3.0 - 1e-6,
			3.0 + DT + 1e-6,
			"coast within one tick of 3 s"
		)
		assert_between(
			float(run.events[1][0]) - since,
			5.0 - 1e-6,
			5.0 + DT + 1e-6,
			"stop_5s within one tick of 5 s"
		)


func test_zero_rider_in_multiplayer_only_coasts() -> void:
	var run := _ride("zero", 12.0, 9, false)
	assert_eq(_names(run.events), [Wl.G_COAST])


func test_rider_who_stops_after_a_ramp_down() -> void:
	# Pedals at 90 rpm while the ramp's power falls to 0 over 10 s, then stops (0 W, 0 rpm).
	var run := _ride("ramp:from_w=150,to_w=0,over_s=10,rpm=90", 25.0, 4)
	assert_eq(_names(run.events), [Wl.G_PEDAL_START, Wl.G_COAST, Wl.G_STOP_5S])
	assert_gt(run.first_np_t, run.first_t + 8.0, "stops once the ramp reaches 0 W")
	assert_almost_eq(float(run.events[1][0]) - run.first_np_t, 3.0, DT + 1e-6)
	assert_almost_eq(float(run.events[2][0]) - run.first_np_t, 5.0, DT + 1e-6)
