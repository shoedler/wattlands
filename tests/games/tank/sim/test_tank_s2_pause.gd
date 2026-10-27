extends "res://tests/scenarios/lib/scenario_test.gd"
## S2's timing (brief 4, BRIEF 3.5 and 7.4) measured where it can be measured exactly: a 0 W
## rider on ashfall_road is paused 10 s (within one 0.05 s tick) after the first trainer sample
## that meets not_pedaling, the anchor the platform's own check uses
## (tests/scenarios/workout/test_workout_coasting.gd: MockTrainer.sample_received, the sample's
## `t`, platform time after the step). The run_game_sim report cannot show that sample: its 1 Hz
## trace rows before the first notification (0.9-1.1 s in) carry the default 0 W telemetry, so
## check_sims.mjs bounds the pause from the latest moment that notification can arrive.
## Crew 3 (HOST): every rider ride-pauses on that rule; the shared game clock pauses once the host
## knows every rider is paused, never before (the lag behind the last rider's own pause is printed:
## a client's pause reaches the host in its telemetry).

const TICK := 0.05
const SECONDS := 20.0


## {first: {peer: s.t}, ride: {peer: t}, shared: t} on platform time after each step.
func _run_zero(players: int) -> Dictionary:
	var extra: Array = [
		"--game=tank",
		"--players=%d" % players,
		"--bots=0",
		"--rider=zero",
		"--seed=1",
		"--max-sim-seconds=60",
		"--sim-speed=200",
	]
	var runner := start_runner(S.flags("ashfall_road", report_path("s2"), extra))
	if runner == null:
		return {}
	var hosts: Array[GameHost] = [runner.host]
	hosts.append_array(runner.clients)
	assert_eq(hosts.size(), players, "one GameHost per rider")
	var obs := {"first": {}, "ride": {}, "shared": -1.0}
	for h in hosts:
		var peer := h.local_peer()
		var mock := S.mock_of(h.local_rider(peer))
		assert_not_null(mock, "rider %d rides a MockTrainer" % peer)
		if mock == null:
			return {}
		mock.sample_received.connect(_on_sample.bind(obs["first"], peer))
	for i in int(SECONDS / TICK):
		runner.step()
		var t := runner.host.clock.platform_time()
		for h in hosts:
			var peer := h.local_peer()
			if not (obs["ride"] as Dictionary).has(peer) and h.local_rider(peer).is_ride_paused():
				obs["ride"][peer] = t
		if float(obs["shared"]) < 0.0 and runner.host.is_paused():
			obs["shared"] = t
	return obs


func _on_sample(s: TrainerSample, first: Dictionary, peer: int) -> void:
	if not first.has(peer) and S.is_not_pedaling(s):
		first[peer] = s.t


func _assert_ten_s(label: String, first_t: float, t: float) -> void:
	var lag := t - first_t
	assert_lte(
		lag, RidePause.ENTER_S + TICK + S.EPS, "%s %.3f s after its first sample" % [label, lag]
	)
	assert_gte(lag, RidePause.ENTER_S - TICK - S.EPS, "%s not before 10 s (%.3f s)" % [label, lag])


func test_the_mock_first_notification_window_check_sims_relies_on() -> void:
	assert_almost_eq(MockTrainer.SAMPLE_MAX_S, 1.1, S.EPS, "check_sims FIRST_SAMPLE_MAX_S")
	assert_eq(RidePause.ENTER_S, 10.0)


func test_a_solo_zero_rider_pauses_10_s_after_the_first_not_pedaling_sample() -> void:
	var obs := _run_zero(1)
	if obs.is_empty():
		return
	var first: Dictionary = obs["first"]
	assert_true(first.has(1), "a sample met not_pedaling")
	if not first.has(1):
		return
	assert_between(float(first[1]), 0.9 - S.EPS, MockTrainer.SAMPLE_MAX_S + S.EPS)
	assert_gte(float(obs["shared"]), 0.0, "the session paused")
	_assert_ten_s("the solo pause", float(first[1]), float(obs["shared"]))
	gut.p("S2 solo: first sample %.2f s, paused %.2f s" % [first[1], obs["shared"]])


func test_crew_3_riders_each_pause_10_s_after_their_first_sample_then_the_shared_clock() -> void:
	var obs := _run_zero(3)
	if obs.is_empty():
		return
	var first: Dictionary = obs["first"]
	var ride: Dictionary = obs["ride"]
	var last_ride := -1.0
	for peer: int in [1, 2, 3]:
		assert_true(first.has(peer) and ride.has(peer), "rider %d: sample and ride pause" % peer)
		if not (first.has(peer) and ride.has(peer)):
			return
		_assert_ten_s("rider %d's ride pause" % peer, float(first[peer]), float(ride[peer]))
		last_ride = maxf(last_ride, float(ride[peer]))
	var shared := float(obs["shared"])
	assert_gte(shared, 0.0, "the shared clock paused")
	assert_gte(shared, last_ride - S.EPS, "not before every rider is paused")
	(
		gut
		. p(
			(
				"S2 crew 3: first samples %s, ride pauses %s, shared pause %.2f s (%.2f s after the last)"
				% [first, ride, shared, shared - last_ride]
			)
		)
	)
