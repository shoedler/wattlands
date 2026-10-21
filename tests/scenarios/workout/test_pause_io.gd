extends "res://tests/scenarios/lib/scenario_test.gd"
## BRIEF 7.4 and 4.1: pausing the tree doesn't stop trainer I/O. During a running Workout session
## the test pauses the SceneTree and checks that every system node of the rider's stack that
## BRIEF 4.1 names (GameHost, LocalRider, SafetyGovernor, MockTrainer) still processes
## (PROCESS_MODE_ALWAYS), while an ordinary node under the test does not (so the check means
## something), and that mock samples and control-point responses keep arriving while the tree
## stays paused. GameSimRunner itself is the test's driver, not a system node, and is not checked.
## Owned by qa; a W2 gate.


func after_each() -> void:
	get_tree().paused = false
	super()


func _always(n: Node) -> bool:
	if n.is_inside_tree():
		return n.can_process()
	return n.process_mode == Node.PROCESS_MODE_ALWAYS


static func _label(n: Node) -> String:
	var s: Script = n.get_script()
	var cls := s.get_global_name() if s != null else StringName()
	return "%s %s" % [str(cls) if cls != &"" else n.get_class(), str(n.name)]


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
	var ordinary := Node.new()
	ordinary.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(ordinary)
	var tree := get_tree()
	tree.paused = true
	assert_false(ordinary.can_process(), "an ordinary node stops while the tree is paused")
	var stopped: Array[String] = []
	var stack: Array = [runner.host, rider, rider.governor, rider.device]
	for n: Variant in stack:
		assert_true(n is Node, "a system node of the rider's stack")
		if n is Node and not _always(n as Node):
			stopped.append(_label(n as Node))
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
