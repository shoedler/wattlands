extends GutTest
## FtmsTrainer (BRIEF 4.1, 4.6.11): setters become FtmsCodec control-point payloads through
## FtmsClient.write_control (its only caller), bike data becomes TrainerSamples, statuses and
## responses pass through, and the hardware lock holds at the device level too.

const FakeKickr := preload("res://tests/trainer/fake_kickr_transport.gd")
const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const DT := 0.05
const HW_ENV := "WATTLANDS_NO_HW_CONTROL"
const TRAINER_DIR := "res://addons/wattlands/trainer/"

var _fake: FakeKickr = null
var _client: FtmsClient = null
var _trainer: FtmsTrainer = null
var _samples: Array[TrainerSample] = []
var _statuses: Array[String] = []
var _env_saved: bool = false
var _env_had: bool = false
var _env_prev: String = ""


func before_each() -> void:
	_samples = []
	_statuses = []


func after_each() -> void:
	if _env_saved:
		if _env_had:
			OS.set_environment(HW_ENV, _env_prev)
		else:
			OS.unset_environment(HW_ENV)
		_env_saved = false


func _make(unlocked: bool = true, p_name: String = "KICKR CORE 1234") -> void:
	_fake = autofree(FakeKickr.new())
	_client = autofree(UnlockedClient.new()) if unlocked else autofree(FtmsClient.new())
	_client.attach(_fake)
	_trainer = autofree(FtmsTrainer.create(_client, p_name))
	_trainer.sample_received.connect(func(s: TrainerSample) -> void: _samples.append(s))
	_trainer.status_changed.connect(func(s: String, _d: String) -> void: _statuses.append(s))


func _pump(seconds: float) -> void:
	for i in roundi(seconds / DT):
		_fake.flush()
		_trainer.tick(DT)
		_fake.flush()


func _ready_trainer() -> void:
	_make()
	_client.begin()
	_pump(1.0)
	assert_true(_trainer.is_ready())


func _last_write() -> String:
	var w := _fake.cp_writes
	return FtmsCodec.to_hex(w[w.size() - 1]) if not w.is_empty() else ""


func test_setters_become_control_point_payloads() -> void:
	_ready_trainer()
	_trainer.set_target_power(200)
	_pump(0.1)
	assert_eq(_last_write(), "05c800")
	_trainer.set_simulation(0.0, 5.5, 0.004, 0.51)
	_pump(0.1)
	assert_eq(_last_write(), "11000026022833")
	_trainer.set_simulation(2.5, 3.25, 0.005, 0.45)
	_pump(0.1)
	assert_eq(_last_write(), "11c4094501322d")
	_trainer.set_resistance(12.5)
	_pump(0.1)
	assert_eq(_last_write(), "047d")
	_trainer.resistance_encoding = FtmsCodec.RESISTANCE_SINT16
	_trainer.set_resistance(12.5)
	_pump(0.1)
	assert_eq(_last_write(), "047d00")
	_trainer.request_stop()
	_pump(0.1)
	assert_eq(_last_write(), "0801")


## BRIEF 4.6.9: on exit, crash paths and disconnect the controller tries SIM flat, then Stop.
## Queued behind a write in flight, both still go out in that order, after the ERG target.
func test_exit_sequence_sim_flat_then_stop_keeps_its_order() -> void:
	_ready_trainer()
	_fake.auto_respond = false
	var before := _fake.cp_writes.size()
	_trainer.set_target_power(220)
	_trainer.set_simulation(0.0, 0.0, 0.004, 0.51)
	_trainer.request_stop()
	for i in 5:
		var op := _client.in_flight_opcode()
		if op < 0:
			break
		_fake.notify("2ad9", PackedByteArray([0x80, op, 0x01]))
		_fake.flush()
	var sent: Array[String] = []
	for w in _fake.cp_writes.slice(before):
		sent.append(FtmsCodec.to_hex(w))
	assert_eq(sent, ["05dc00", "11000000002833", "0801"] as Array[String])


func test_responses_and_machine_status_pass_through() -> void:
	_ready_trainer()
	watch_signals(_trainer)
	_trainer.set_target_power(150)
	_pump(0.1)
	assert_signal_emitted_with_parameters(
		_trainer, "control_response", [FtmsCodec.OP_SET_TARGET_POWER, FtmsCodec.RESULT_SUCCESS]
	)
	assert_signal_emitted_with_parameters(
		_trainer,
		"machine_status",
		[FtmsCodec.STATUS_TARGET_POWER_CHANGED, PackedByteArray([0x96, 0x00])]
	)


func test_bike_data_becomes_samples() -> void:
	_ready_trainer()
	_pump(0.5)
	var t := _trainer.platform_time_s()
	_fake.send_bike_data(
		{"speed_kmh": 30.5, "cadence_rpm": 85.5, "power_w": 200, "distance_m": 1234}
	)
	_fake.flush()
	assert_eq(_samples.size(), 1)
	var s := _samples[0]
	assert_almost_eq(s.t, t, 1e-9, "stamped with the device's platform time")
	assert_eq(s.power_w, 200.0)
	assert_eq(s.cadence_rpm, 85.5, "0.5 rpm units")
	assert_eq(s.speed_kmh, 30.5, "0.01 km/h units")
	assert_eq(s.distance_m, 1234.0)
	assert_eq(
		s.flags,
		(
			TrainerSample.HAS_POWER
			| TrainerSample.HAS_CADENCE
			| TrainerSample.HAS_SPEED
			| TrainerSample.HAS_DISTANCE
		)
	)
	assert_same(_trainer.last_sample(), s)


func test_missing_fields_stay_absent() -> void:
	_ready_trainer()
	_fake.send_bike_data({"speed_kmh": 25.0, "power_w": 180})
	_fake.flush()
	var s := _samples[0]
	assert_false(s.has_cadence(), "CadenceEstimator fills it later, not the device")
	assert_eq(s.cadence_rpm, -1.0)
	assert_true(s.has_speed())
	assert_eq(s.distance_m, -1.0)
	var none := FtmsTrainer.sample_from_record({"cadence_rpm": 80.0}, 3.0)
	assert_eq(none.flags & TrainerSample.HAS_POWER, 0, "no power field, no HAS_POWER")


func test_negative_power_becomes_zero() -> void:
	_ready_trainer()
	_fake.notify("2ad2", FtmsCodec.from_hex("60000000fbfff6ff"))
	_fake.flush()
	var s := _samples[0]
	assert_eq(s.power_w, 0.0, "the vector's -10 W (back-pedalling) is 0 W")
	assert_true((s.flags & TrainerSample.HAS_POWER) != 0)
	assert_eq(s.speed_kmh, 0.0)


func test_cycling_power_samples_are_flagged() -> void:
	var s := FtmsTrainer.sample_from_record(
		{"power_w": 250, "power_source": "cps", "speed_kmh": 30.0}, 1.0
	)
	assert_eq(s.power_w, 250.0)
	assert_true((s.flags & TrainerSample.POWER_FROM_CPS) != 0)
	assert_true((s.flags & TrainerSample.HAS_POWER) != 0)


func test_status_follows_the_client() -> void:
	_make()
	assert_eq(_trainer.status(), TrainerDevice.STATUS_DISCONNECTED)
	_client.begin()
	_pump(1.0)
	assert_eq(_statuses.back(), TrainerDevice.STATUS_READY)
	assert_true(_statuses.has(TrainerDevice.STATUS_CONNECTED), "connected while the flow runs")
	assert_eq(_trainer.status(), TrainerDevice.STATUS_READY)
	assert_eq(_trainer.power_range(), {"min_w": 0, "max_w": 1800, "step_w": 1})
	assert_eq(_trainer.features(), {"machine": 16518, "target": 57356})
	_fake.revoke_control()
	_fake.flush()
	assert_eq(_trainer.status(), TrainerDevice.STATUS_CONTROL_LOST)
	assert_eq(_statuses.back(), TrainerDevice.STATUS_CONTROL_LOST)
	assert_false(_trainer.is_ready())
	assert_push_warning("control lost")
	_fake.drop_link()
	_fake.flush()
	assert_eq(_trainer.status(), TrainerDevice.STATUS_DISCONNECTED)
	assert_eq(FtmsTrainer._map_state(FtmsClient.STATE_FAILED), TrainerDevice.STATUS_ERROR)
	assert_eq(FtmsTrainer._map_state(FtmsClient.STATE_READ_ONLY), TrainerDevice.STATUS_CONNECTED)


func test_device_name() -> void:
	_make(true, "")
	assert_eq(_trainer.device_name(), "FTMS trainer")
	_client.begin()
	_pump(1.0)
	assert_eq(_trainer.device_name(), "KICKR CORE", "from Device Information")
	var named: FtmsTrainer = autofree(FtmsTrainer.create(_client, "My trainer"))
	assert_eq(named.device_name(), "My trainer")
	assert_same(named.client(), _client)


func test_tick_drives_a_client_outside_the_tree() -> void:
	_ready_trainer()
	_fake.auto_respond = false
	_trainer.set_target_power(150)
	assert_eq(_fake.writes_with_op(0x05), 1)
	_trainer.tick(FtmsClient.CP_TIMEOUT_S)
	assert_eq(_fake.writes_with_op(0x05), 2, "the client's timeout ran on the trainer's tick")
	assert_almost_eq(_trainer.platform_time_s(), 1.0 + FtmsClient.CP_TIMEOUT_S, 1e-6)
	assert_eq(_trainer.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_tick_drives_a_client_in_the_tree_that_does_not_tick_itself() -> void:
	_ready_trainer()
	_client.process_self = false
	add_child(_client)
	_fake.auto_respond = false
	_trainer.set_target_power(150)
	_trainer.tick(FtmsClient.CP_TIMEOUT_S)
	assert_eq(_fake.writes_with_op(0x05), 2)
	remove_child(_client)


func test_hardware_lock_blocks_every_setter() -> void:
	_env_saved = true
	_env_had = OS.has_environment(HW_ENV)
	_env_prev = OS.get_environment(HW_ENV)
	OS.set_environment(HW_ENV, "1")
	_make(false)
	_client.begin()
	_pump(1.0)
	assert_push_warning("hardware control locked")
	assert_false(_trainer.is_ready())
	assert_eq(_trainer.status(), TrainerDevice.STATUS_CONNECTED)
	_trainer.set_target_power(200)
	_trainer.set_simulation(0.0, 8.0, 0.004, 0.51)
	_trainer.set_resistance(20.0)
	_trainer.request_stop()
	for i in 4:
		assert_push_warning("hardware control locked")
	_pump(3.0)
	assert_eq(_fake.cp_writes.size(), 0, "nothing reached the control point")
	_fake.send_bike_data({"speed_kmh": 30.5, "cadence_rpm": 90.0, "power_w": 200})
	_fake.flush()
	assert_eq(_samples.size(), 1, "telemetry still arrives")


func test_without_a_client() -> void:
	var t: FtmsTrainer = autofree(FtmsTrainer.create(null))
	assert_eq(t.status(), TrainerDevice.STATUS_DISCONNECTED)
	assert_false(t.is_ready())
	assert_eq(t.power_range()["max_w"], 1800)
	t.set_target_power(100)
	assert_push_warning("no client")
	t.tick(1.0)
	assert_null(t.last_sample())


## Module-local guard for BRIEF 4.6.11 (trainer-control's tests/arch scan covers the tree):
## inside addons/wattlands/trainer/*.gd, write_control is called only by ftms_trainer.gd,
## write_characteristic only by ftms_client.gd, and no file calls a TrainerDevice setter.
func test_only_ftms_trainer_calls_write_control() -> void:
	var calls := {
		"write_control": [],
		"write_characteristic": [],
		"set_target_power": [],
		"set_simulation": [],
		"set_resistance": []
	}
	for file: String in DirAccess.get_files_at(TRAINER_DIR):
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(TRAINER_DIR + file)
		for line: String in text.split("\n"):
			var code := line.strip_edges()
			if (
				code.begins_with("#")
				or code.begins_with("func ")
				or code.begins_with("static func ")
			):
				continue
			for fn: String in calls.keys():
				var re := RegEx.create_from_string("(^|[^A-Za-z0-9_])%s\\s*\\(" % fn)
				if re.search(code) != null and not (calls[fn] as Array).has(file):
					(calls[fn] as Array).append(file)
	assert_eq(calls["write_control"], ["ftms_trainer.gd"])
	assert_eq(calls["write_characteristic"], ["ftms_client.gd"])
	assert_eq(calls["set_target_power"], [])
	assert_eq(calls["set_simulation"], [])
	assert_eq(calls["set_resistance"], [])
