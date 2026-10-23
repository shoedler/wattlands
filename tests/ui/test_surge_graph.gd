extends GutTest
## The surge feedback graph (BRIEF 3.5): the last 5 s of power and the surge threshold line,
## shown only with pedal navigation on, a rider attached and the trainer outside ERG.

const FakeRider := preload("res://tests/ui/fake_local_rider.gd")

var _graph: WlSurgeGraph = null


func before_each() -> void:
	_graph = WlSurgeGraph.new()
	_graph.real_time = false
	add_child_autofree(_graph)


func _rider(mode: String, power_w: float) -> FakeRider:
	var r: FakeRider = autofree(FakeRider.new())
	r.fake_mode = mode
	r.fake_power_w = power_w
	r.gestures = GestureRecognizer.new()
	r.gestures.configure(200.0, true)
	return r


func test_keeps_the_last_five_seconds_at_10_hz_or_better() -> void:
	for i in 120:
		_graph.push_sample(float(i), 150.0)
	assert_eq(_graph.samples().size(), roundi(WlSurgeGraph.WINDOW_S / WlSurgeGraph.SAMPLE_S))
	assert_eq(_graph.samples()[_graph.samples().size() - 1], 119.0, "newest last")
	assert_lte(WlSurgeGraph.SAMPLE_S, 1.0, "at least 1 Hz")
	assert_eq(_graph.threshold_w, 150.0)


func test_scale_leaves_room_for_the_threshold_and_the_peak() -> void:
	_graph.push_sample(100.0, 120.0)
	assert_almost_eq(_graph.scale_max_w(), WlSurgeGraph.MIN_SCALE_W, 1e-6)
	_graph.push_sample(100.0, 260.0)
	assert_almost_eq(_graph.scale_max_w(), 260.0 * 1.15, 1e-6)
	_graph.push_sample(400.0, 260.0)
	assert_almost_eq(_graph.scale_max_w(), 440.0, 1e-6)


func test_shows_only_with_a_rider_outside_erg() -> void:
	assert_false(_graph.visible, "no rider")
	var r := _rider(Wl.SIM, 180.0)
	_graph.rider = r
	_graph.tick(0.1)
	assert_true(_graph.visible)
	assert_eq(_graph.power_w, 180.0)
	r.fake_mode = Wl.ERG
	_graph.tick(0.1)
	assert_false(_graph.visible, "inside ERG power is held and the surge reads speed")
	r.fake_mode = Wl.SIM
	_graph.enabled = false
	_graph.tick(0.1)
	assert_false(_graph.visible, "pedal navigation off")
	_graph.enabled = true
	_graph.tick(0.1)
	assert_true(_graph.visible)


func test_reads_the_routers_attached_rider() -> void:
	var router: WlInputRouter = autofree(WlInputRouter.new())
	router.load_on_ready = false
	_graph.router = router
	router.attach_rider(_rider(Wl.SIM, 220.0))
	_graph.tick(0.5)
	assert_eq(_graph.power_w, 220.0)
	assert_eq(_graph.samples().size(), 5, "10 Hz: five samples in half a second")
	router.detach_rider()
	_graph.tick(0.1)
	assert_false(_graph.visible)


func test_threshold_comes_from_the_recognizer() -> void:
	var r := _rider(Wl.SIM, 200.0)
	for i in 12:
		r.gestures.on_sample(TrainerSample.make(float(i), 200.0, 90.0, -1.0))
	_graph.rider = r
	_graph.tick(0.1)
	assert_almost_eq(_graph.threshold_w, 260.0, 1e-6)
