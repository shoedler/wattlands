extends GutTest
## BRIEF 4.1: pausing never stops trainer I/O. The test pauses the SceneTree
## (get_tree().paused = true) and asserts that MockTrainer samples (ticked from a
## PROCESS_MODE_ALWAYS node's _process) and an FtmsClient control-point response from the
## fake transport still arrive, while an ordinary node really is paused.

const FakeKickr := preload("res://tests/trainer/fake_kickr_transport.gd")
const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const FRAMES := 30


## Ticks a device every frame, like LocalRider on platform time (a fixed step per frame keeps
## the test short and independent of the frame rate).
class Driver:
	extends Node
	var device: TrainerDevice = null
	var step_s: float = 0.25
	var ticks: int = 0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		device.tick(step_s)
		ticks += 1


## An ordinary node (inherits the pause).
class Pausable:
	extends Node
	var frames: int = 0

	func _process(_delta: float) -> void:
		frames += 1


var _samples: int = 0
var _mock_responses: Array[Vector2i] = []
var _client_responses: Array[Vector2i] = []


func before_each() -> void:
	_samples = 0
	_mock_responses = []
	_client_responses = []


func after_each() -> void:
	get_tree().paused = false


func _on_sample(_s: TrainerSample) -> void:
	_samples += 1


func test_mock_samples_and_control_responses_arrive_while_paused() -> void:
	var mock := MockTrainer.from_spec("erg", 200.0, {"seed": 1})
	mock.sample_received.connect(_on_sample)
	mock.control_response.connect(
		func(op: int, res: int) -> void: _mock_responses.append(Vector2i(op, res))
	)
	var driver := Driver.new()
	driver.device = mock
	add_child_autofree(driver)
	driver.add_child(mock)

	var fake: FakeKickr = FakeKickr.new()
	var client: FtmsClient = UnlockedClient.new()
	client.attach(fake)
	client.control_response.connect(
		func(op: int, res: int) -> void: _client_responses.append(Vector2i(op, res))
	)
	client.begin()
	for i in 40:
		fake.flush()
		client.tick(0.05)
	assert_true(client.is_ready(), "connected before the pause")
	fake.deliver_in_process = true
	add_child_autofree(fake)
	add_child_autofree(client)
	var pausable := Pausable.new()
	add_child_autofree(pausable)
	await get_tree().process_frame

	get_tree().paused = true
	var frames_before := pausable.frames
	var samples_before := _samples
	var responses_before := _client_responses.size()
	client.write_control(FtmsCodec.encode_target_power(160))
	mock.set_target_power(150)
	for i in FRAMES:
		await get_tree().process_frame
	assert_true(get_tree().paused)
	assert_eq(pausable.frames, frames_before, "the tree really is paused")
	assert_gt(driver.ticks, FRAMES - 2, "the PROCESS_MODE_ALWAYS driver kept ticking")
	assert_gt(_samples, samples_before + 3, "mock samples kept arriving")
	assert_eq(
		_mock_responses,
		[Vector2i(MockTrainer.OP_SET_TARGET_POWER, MockTrainer.RESULT_SUCCESS)] as Array[Vector2i]
	)
	assert_eq(_client_responses.size(), responses_before + 1, "the control-point response arrived")
	assert_eq(
		_client_responses.back(), Vector2i(FtmsCodec.OP_SET_TARGET_POWER, FtmsCodec.RESULT_SUCCESS)
	)
	assert_eq(fake.writes_with_op(FtmsCodec.OP_SET_TARGET_POWER), 1)
	get_tree().paused = false


## A reconnect while paused (BRIEF 4.1: telemetry, indications and reconnect keep working):
## the client runs the whole 4.4 flow from its own _process, including the subscribe settle it
## times itself, and its first control-point responses arrive with the tree paused.
func test_connection_flow_completes_while_paused() -> void:
	var fake: FakeKickr = FakeKickr.new()
	fake.deliver_in_process = true
	var client: FtmsClient = UnlockedClient.new()
	client.attach(fake)
	client.control_response.connect(
		func(op: int, res: int) -> void: _client_responses.append(Vector2i(op, res))
	)
	add_child_autofree(fake)
	add_child_autofree(client)
	var pausable := Pausable.new()
	add_child_autofree(pausable)
	await get_tree().process_frame
	get_tree().paused = true
	var frames_before := pausable.frames
	client.begin()
	for i in 30:
		if client.is_ready():
			break
		await get_tree().create_timer(0.1, true).timeout
	assert_true(get_tree().paused)
	assert_eq(pausable.frames, frames_before, "the tree really is paused")
	assert_true(client.is_ready(), "the flow finished while paused (state %s)" % client.state())
	assert_eq(
		_client_responses,
		(
			[
				Vector2i(FtmsCodec.OP_REQUEST_CONTROL, FtmsCodec.RESULT_SUCCESS),
				Vector2i(FtmsCodec.OP_SET_SIMULATION, FtmsCodec.RESULT_SUCCESS),
			]
			as Array[Vector2i]
		)
	)
	get_tree().paused = false


func test_trainer_nodes_run_with_process_mode_always() -> void:
	var mock: MockTrainer = autofree(MockTrainer.from_spec("erg"))
	var client: FtmsClient = autofree(FtmsClient.new())
	var trainer: FtmsTrainer = autofree(FtmsTrainer.create(client))
	assert_eq(mock.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(client.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(trainer.process_mode, Node.PROCESS_MODE_ALWAYS)
