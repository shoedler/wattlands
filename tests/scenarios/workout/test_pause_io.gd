extends "res://tests/scenarios/lib/scenario_test.gd"
## BRIEF 7.4 and 4.1: pausing the tree doesn't stop trainer I/O. During a running Workout session
## the test pauses the SceneTree and checks that every system node of the rider's stack (runner,
## GameHost, LocalRider, SafetyGovernor, MockTrainer) still processes (PROCESS_MODE_ALWAYS), and
## that mock samples and control-point responses keep arriving while the tree stays paused.
## Owned by qa; a W2 gate.


func after_each() -> void:
	get_tree().paused = false
	super()


func _always(n: Node) -> bool:
	if n.is_inside_tree():
		return n.can_process()
	return n.process_mode == Node.PROCESS_MODE_ALWAYS


func test_tree_pause_keeps_trainer_io() -> void:
	var runner := start_runner(S.flags("e2e", report_path("pause"), ["--bots=0"]))
	if runner == null:
		return
	var rider := human_rider(runner)
	if rider == null:
		return
	var mock := S.mock_of(rider)
	for i in 100:
		runner.step()
	var counts := {"samples": 0, "responses": 0}
	mock.sample_received.connect(func(_s: TrainerSample) -> void:
		counts["samples"] = int(counts["samples"]) + 1
	)
	mock.control_response.connect(func(_op: int, _result: int) -> void:
		counts["responses"] = int(counts["responses"]) + 1
	)
	var tree := get_tree()
	tree.paused = true
	var stopped: Array[String] = []
	var stack: Array = [runner, runner.host, rider, rider.governor, rider.device]
	for n: Variant in stack:
		if n is Node and not _always(n as Node):
			stopped.append((n as Node).get_class() + " " + str((n as Node).name))
	var t0 := S.platform_t(runner, rider)
	for i in 400:
		runner.step()
	var t1 := S.platform_t(runner, rider)
	tree.paused = false
	assert_eq(stopped, [] as Array[String], "system nodes run with PROCESS_MODE_ALWAYS")
	assert_almost_eq(t1 - t0, 20.0, 0.051, "platform time kept running while the tree was paused")
	assert_gte(int(counts["samples"]), 15, "about 1 Hz samples kept arriving (%d in 20 s)" % int(counts["samples"]))
	assert_gt(int(counts["responses"]), 0, "control-point responses kept arriving")
	assert_false(runner.host.is_paused(), "a tree pause is not a game pause")
