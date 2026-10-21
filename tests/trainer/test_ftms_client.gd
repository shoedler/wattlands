extends GutTest
## FtmsClient (BRIEF 1, 4.3, 4.4) against the fake KICKR CORE: the connection flow and its
## order, the serialized control-point queue (one in flight, 2 s timeout, two retries),
## response matching, coalescing, control lost (0x05 and Machine Status 0xFF), failures, the
## Cycling Power fallback, Device Information, bike data, and the hardware lock.
##
## Control-flow tests use unlocked_ftms_client.gd, a test-only subclass whose lock is off for
## that instance and which only ever talks to the fake transport; the process keeps
## WATTLANDS_NO_HW_CONTROL=1. The lock tests use the real FtmsClient with the variable set
## explicitly (and restored afterwards).

const FakeKickr := preload("res://tests/trainer/fake_kickr_transport.gd")
const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const DT := 0.05
const HW_ENV := "WATTLANDS_NO_HW_CONTROL"
const FLAT := "11000000002833"

var _fake: FakeKickr = null
var _client: FtmsClient = null
var _ready_count: int = 0
var _states: Array[String] = []
var _responses: Array[Vector2i] = []
var _statuses: Array = []
var _lost: Array[String] = []
var _failed: Array[String] = []
var _records: Array[Dictionary] = []
var _env_saved: bool = false
var _env_had: bool = false
var _env_prev: String = ""


func before_each() -> void:
	_ready_count = 0
	_states = []
	_responses = []
	_statuses = []
	_lost = []
	_failed = []
	_records = []


func after_each() -> void:
	if _env_saved:
		if _env_had:
			OS.set_environment(HW_ENV, _env_prev)
		else:
			OS.unset_environment(HW_ENV)
		_env_saved = false


func _set_lock_env(value: String) -> void:
	if not _env_saved:
		_env_saved = true
		_env_had = OS.has_environment(HW_ENV)
		_env_prev = OS.get_environment(HW_ENV)
	OS.set_environment(HW_ENV, value)


func _make(unlocked: bool = true) -> void:
	_fake = autofree(FakeKickr.new())
	if unlocked:
		_client = autofree(UnlockedClient.new())
	else:
		_client = autofree(FtmsClient.new())
	_client.attach(_fake)
	_client.client_ready.connect(func() -> void: _ready_count += 1)
	_client.state_changed.connect(func(s: String, _d: String) -> void: _states.append(s))
	_client.control_response.connect(func(op: int, res: int) -> void: _responses.append(Vector2i(op, res)))
	_client.machine_status.connect(func(code: int, data: PackedByteArray) -> void: _statuses.append([code, FtmsCodec.to_hex(data)]))
	_client.control_lost.connect(func(d: String) -> void: _lost.append(d))
	_client.failed.connect(func(r: String) -> void: _failed.append(r))
	_client.bike_data.connect(func(rec: Dictionary) -> void: _records.append(rec))


func _pump(seconds: float) -> void:
	for i in roundi(seconds / DT):
		_fake.flush()
		_client.tick(DT)
		_fake.flush()


func _connect_ready() -> void:
	_make()
	_client.begin()
	_pump(1.0)
	assert_true(_client.is_ready(), "connected and in control")


func _writes() -> Array[String]:
	var out: Array[String] = []
	for op in _fake.ops:
		if op.begins_with("write "):
			out.append(op)
	return out


# --- connection flow ------------------------------------------------------------------

func test_flow_order_and_ready() -> void:
	_make()
	_client.begin()
	_pump(1.0)
	assert_eq(_fake.ops, [
		"discover",
		"read 2acc", "read 2ad8", "read 2ad6", "read 2a29", "read 2a24", "read 2a26",
		"subscribe 2ad2", "subscribe 2ada", "subscribe 2ad9",
		"write 2ad9 00",
		"write 2ad9 " + FLAT,
	] as Array[String])
	assert_eq(_states, [
		FtmsClient.STATE_DISCOVERING, FtmsClient.STATE_READING, FtmsClient.STATE_SUBSCRIBING,
		FtmsClient.STATE_REQUESTING_CONTROL, FtmsClient.STATE_SETTING_SIM, FtmsClient.STATE_READY,
	] as Array[String])
	assert_eq(_ready_count, 1)
	assert_true(_client.is_ready())
	assert_false(_client.is_read_only())
	assert_eq(_responses, [Vector2i(0x00, 0x01), Vector2i(0x11, 0x01)] as Array[Vector2i])
	assert_eq(_client.features(), {"machine": 16518, "target": 57356})
	assert_eq(_client.power_range(), {"min_w": 0, "max_w": 1800, "step_w": 1})
	var rr := _client.resistance_range()
	assert_almost_eq(float(rr["max"]), 100.0, 1e-9)
	assert_almost_eq(float(rr["step"]), 0.1, 1e-9)
	assert_eq(_client.device_info(), {"manufacturer": "Wahoo Fitness", "model": "KICKR CORE", "firmware_revision": "4.2.1"})
	assert_false(_client.cps_fallback_active(), "the KICKR reports power itself")
	assert_eq(_failed.size(), 0)


func test_indications_enabled_before_the_first_control_point_write() -> void:
	_make()
	_client.begin()
	_pump(1.0)
	var sub := _fake.ops.find("subscribe 2ad9")
	var first_write := _fake.ops.find("write 2ad9 00")
	assert_gt(sub, -1)
	assert_gt(first_write, sub, "indications on 0x2AD9 come first")
	assert_gt(sub, _fake.ops.find("subscribe 2ad2"))
	assert_gt(sub, _fake.ops.find("subscribe 2ada"))


func test_request_control_waits_for_the_subscribe_settle() -> void:
	_make()
	_client.begin()
	_fake.flush()
	for i in 20:
		_fake.flush()
	assert_eq(_client.state(), FtmsClient.STATE_SUBSCRIBING)
	assert_eq(_writes().size(), 0, "no write before the settle delay")
	_client.tick(FtmsClient.SUBSCRIBE_SETTLE_S - DT)
	assert_eq(_writes().size(), 0)
	_client.tick(DT)
	assert_eq(_writes(), ["write 2ad9 00"] as Array[String])


func test_begin_without_transport_fails() -> void:
	_client = autofree(UnlockedClient.new())
	_client.failed.connect(func(r: String) -> void: _failed.append(r))
	_client.begin()
	assert_eq(_failed, ["no transport attached"] as Array[String])
	assert_eq(_client.state(), FtmsClient.STATE_FAILED)
	assert_push_warning("no transport attached")


func test_no_ftms_service_fails() -> void:
	_make()
	_fake.services = [{"uuid": BleTransport.expand_uuid("180a"), "characteristics": []}]
	_client.begin()
	_pump(0.5)
	assert_eq(_failed.size(), 1)
	assert_string_contains(_failed[0], "no Fitness Machine service")
	assert_eq(_client.state(), FtmsClient.STATE_FAILED)
	assert_eq(_writes().size(), 0)
	assert_push_warning("no Fitness Machine service")


func test_unanswered_discovery_fails_after_the_timeout() -> void:
	_make()
	_fake.answer_discover = false
	_client.begin()
	_pump(FtmsClient.DISCOVER_TIMEOUT_S - 0.1)
	assert_eq(_client.state(), FtmsClient.STATE_DISCOVERING, "still waiting")
	assert_eq(_failed.size(), 0)
	_pump(0.2)
	assert_eq(_client.state(), FtmsClient.STATE_FAILED)
	assert_eq(_failed.size(), 1)
	assert_string_contains(_failed[0], "service discovery timed out")
	assert_push_warning("service discovery timed out")
	_fake.answer_discover = true
	_client.begin()
	_pump(1.0)
	assert_true(_client.is_ready(), "begin() after a failure runs the flow again")
	_pump(FtmsClient.DISCOVER_TIMEOUT_S + 1.0)
	assert_true(_client.is_ready(), "the old discovery timer is gone")
	assert_eq(_failed.size(), 1)


func test_services_without_characteristic_lists_read_everything_standard() -> void:
	_make()
	_fake.services = [{"uuid": "1826"}]
	_client.begin()
	_pump(1.0)
	assert_true(_client.is_ready())
	assert_has(_fake.ops, "read 2ad8")
	assert_has(_fake.ops, "read 2ad6")
	assert_does_not_have(_fake.ops, "read 2a29", "no Device Information service offered")


func test_feature_read_timeout_fails_after_two_retries() -> void:
	_make()
	_fake.unreadable = ["2acc"] as Array[String]
	_client.begin()
	_pump(5.9)
	assert_eq(_failed.size(), 0, "still retrying")
	_pump(0.2)
	assert_eq(_fake.ops.count("read 2acc"), 3, "first read plus two retries")
	assert_eq(_failed.size(), 1)
	assert_string_contains(_failed[0], "feature")
	assert_push_warning("feature")


func test_optional_read_failure_keeps_defaults() -> void:
	_make()
	_fake.unreadable = ["2ad8"] as Array[String]
	_client.begin()
	_pump(7.0)
	assert_true(_client.is_ready())
	assert_eq(_client.power_range(), {"min_w": 0, "max_w": 1800, "step_w": 1}, "KICKR default")
	assert_eq(_fake.ops.count("read 2ad8"), 3)
	assert_push_warning("power_range")


func test_malformed_optional_read_keeps_defaults() -> void:
	_make()
	_fake.read_values["2ad8"] = PackedByteArray([0, 0, 8])
	_client.begin()
	_pump(1.0)
	assert_true(_client.is_ready())
	assert_eq(_client.power_range()["max_w"], 1800)
	assert_push_error("malformed power range")
	assert_push_warning("power_range unreadable")


func test_read_power_range_is_used() -> void:
	_make()
	_fake.read_values["2ad8"] = FtmsCodec.from_hex("9cffd0070500")
	_client.begin()
	_pump(1.0)
	assert_eq(_client.power_range(), {"min_w": -100, "max_w": 2000, "step_w": 5})


# --- control-point queue --------------------------------------------------------------

func test_one_write_in_flight_and_coalescing() -> void:
	_connect_ready()
	_fake.auto_respond = false
	var before := _writes().size()
	_client.write_control(FtmsCodec.encode_target_power(150))
	_client.write_control(FtmsCodec.encode_target_power(200))
	_client.write_control(FtmsCodec.encode_target_power(250))
	_client.write_control(FtmsCodec.encode_indoor_bike_simulation(0.0, 2.0, 0.004, 0.51))
	assert_eq(_writes().size(), before + 1, "one write in flight")
	assert_eq(_client.in_flight_opcode(), 0x05)
	assert_eq(_client.queued_count(), 2, "the queued 200 W was replaced by 250 W")
	_fake.notify("2ad9", PackedByteArray([0x80, 0x05, 0x01]))
	_fake.flush()
	assert_eq(_writes().size(), before + 2)
	assert_eq(_client.in_flight_opcode(), 0x05)
	_fake.notify("2ad9", PackedByteArray([0x80, 0x05, 0x01]))
	_fake.flush()
	assert_eq(_client.in_flight_opcode(), 0x11)
	_fake.notify("2ad9", PackedByteArray([0x80, 0x11, 0x01]))
	_fake.flush()
	var w := _writes()
	assert_eq(w.slice(before), ["write 2ad9 059600", "write 2ad9 05fa00", "write 2ad9 110000c8002833"])
	assert_eq(_responses.slice(2), [Vector2i(0x05, 1), Vector2i(0x05, 1), Vector2i(0x11, 1)])
	assert_eq(_client.in_flight_opcode(), -1)
	assert_eq(_client.queued_count(), 0)


func test_coalescing_never_reorders_commands() -> void:
	_connect_ready()
	_fake.auto_respond = false
	_client.write_control(FtmsCodec.encode_stop_pause(2))
	_client.write_control(FtmsCodec.encode_target_power(200))
	_client.write_control(FtmsCodec.encode_indoor_bike_simulation(0.0, 0.0, 0.004, 0.51))
	_client.write_control(FtmsCodec.encode_target_power(180))
	_answer_until_idle()
	var w := _writes()
	assert_eq(w.back(), "write 2ad9 05b400", "the newest command (ERG 180 W) is applied last")
	assert_eq(_fake.writes_with_op(0x11), 2, "the flow's SIM flat and the SIM entry before ERG 180 W")


func test_coalescing_keeps_the_first_command_of_a_mode() -> void:
	_connect_ready()
	_fake.auto_respond = false
	var before := _writes().size()
	_client.write_control(FtmsCodec.encode_target_power(150))
	_client.write_control(FtmsCodec.encode_indoor_bike_simulation(0.0, 0.0, 0.004, 0.51))
	_client.write_control(FtmsCodec.encode_indoor_bike_simulation(0.0, 2.0, 0.004, 0.51))
	_client.write_control(FtmsCodec.encode_indoor_bike_simulation(0.0, 3.0, 0.004, 0.51))
	assert_eq(_client.queued_count(), 2, "SIM grade 0 (the mode switch's entry) stays; 2 % gave way to 3 %")
	_client.write_control(FtmsCodec.encode_target_power(120))
	_client.write_control(FtmsCodec.encode_target_power(140))
	assert_eq(_client.queued_count(), 4, "ERG 120 W (the switch back) is an entry, so 140 W queues behind it")
	_client.write_control(FtmsCodec.encode_target_power(160))
	assert_eq(_client.queued_count(), 4, "ERG 160 W replaced 140 W, not the entry at 120 W")
	_answer_until_idle()
	assert_eq(_writes().slice(before), [
		"write 2ad9 059600", "write 2ad9 11000000002833", "write 2ad9 1100002c012833",
		"write 2ad9 057800", "write 2ad9 05a000",
	] as Array[String], "every mode switch keeps its entry command and the newest command goes last (BRIEF 4.5)")


## Answers the write in flight until nothing is left (auto_respond off).
func _answer_until_idle() -> void:
	for i in 20:
		var op := _client.in_flight_opcode()
		if op < 0:
			return
		_fake.notify("2ad9", PackedByteArray([0x80, op, 0x01]))
		_fake.flush()


func test_non_setting_commands_are_never_coalesced() -> void:
	_connect_ready()
	_fake.auto_respond = false
	_client.write_control(FtmsCodec.encode_target_power(150))
	_client.write_control(FtmsCodec.encode_stop_pause(2))
	_client.write_control(FtmsCodec.encode_stop_pause(2))
	_client.write_control(FtmsCodec.encode_start_resume())
	assert_eq(_client.queued_count(), 3)


func test_timeout_and_two_retries_then_success() -> void:
	_connect_ready()
	_fake.drop_writes = 2
	_client.write_control(FtmsCodec.encode_target_power(200))
	_fake.flush()
	assert_eq(_fake.writes_with_op(0x05), 1)
	_pump(1.95)
	assert_eq(_fake.writes_with_op(0x05), 1, "no retry before 2 s")
	_pump(0.05)
	assert_eq(_fake.writes_with_op(0x05), 2, "first retry at 2 s")
	_pump(2.0)
	assert_eq(_fake.writes_with_op(0x05), 3, "second retry at 4 s")
	_pump(0.5)
	assert_eq(_responses.back(), Vector2i(0x05, 0x01))
	assert_true(_client.is_ready())
	assert_eq(_failed.size(), 0)
	assert_eq(int(_client.stats()["cp_retries"]), 2)


func test_gives_up_after_two_retries() -> void:
	_connect_ready()
	_fake.drop_writes = 3
	_client.write_control(FtmsCodec.encode_target_power(200))
	_client.write_control(FtmsCodec.encode_target_power(220))
	_pump(5.9)
	assert_eq(_failed.size(), 0)
	_pump(0.2)
	assert_eq(_fake.writes_with_op(0x05), 3, "one write plus two retries")
	assert_eq(_failed.size(), 1)
	assert_string_contains(_failed[0], "Set Target Power unanswered after 3 attempts")
	assert_eq(_client.state(), FtmsClient.STATE_FAILED)
	assert_eq(_client.queued_count(), 0, "the queue is dropped")
	assert_eq(int(_client.stats()["cp_timeouts"]), 1)
	assert_push_warning("unanswered")


func test_write_failure_is_retried_at_once() -> void:
	_connect_ready()
	_fake.fail_writes = 1
	_client.write_control(FtmsCodec.encode_target_power(180))
	_pump(0.1)
	assert_eq(_fake.writes_with_op(0x05), 2)
	assert_eq(_responses.back(), Vector2i(0x05, 0x01))
	assert_eq(_failed.size(), 0)


func test_unexpected_response_is_ignored() -> void:
	_connect_ready()
	_fake.auto_respond = false
	_client.write_control(FtmsCodec.encode_target_power(150))
	_fake.notify("2ad9", PackedByteArray([0x80, 0x11, 0x01]))
	_fake.flush()
	assert_eq(_client.in_flight_opcode(), 0x05, "still waiting for its own response")
	assert_push_warning("unexpected response")
	_fake.notify("2ad9", PackedByteArray([0x80, 0x05, 0x03]))
	_fake.flush()
	assert_eq(_responses.back(), Vector2i(0x05, 0x03))
	assert_eq(_client.in_flight_opcode(), -1)
	assert_true(_client.is_ready(), "invalid parameter is reported, not fatal")
	assert_push_warning("invalid parameter")


func test_write_before_ready_is_dropped() -> void:
	_make()
	_client.write_control(FtmsCodec.encode_target_power(150))
	assert_eq(_writes().size(), 0)
	assert_push_warning("not in control")
	_client.write_control(PackedByteArray())
	assert_push_error("empty payload")


func test_sim_flat_refusal_still_ends_ready() -> void:
	_make()
	_fake.result_override[0x11] = 0x02
	_client.begin()
	_pump(1.0)
	assert_true(_client.is_ready())
	assert_eq(_ready_count, 1)
	assert_push_warning("SIM flat refused")


func test_machine_status_passthrough() -> void:
	_connect_ready()
	_client.write_control(FtmsCodec.encode_target_power(150))
	_pump(0.1)
	assert_has(_statuses, [0x08, "9600"])
	assert_has(_statuses, [0x12, "000000002833"], "SIM flat during the flow")


# --- control lost and failures --------------------------------------------------------

func test_request_control_not_permitted_means_control_lost() -> void:
	_make()
	_fake.other_app_has_control = true
	_client.begin()
	_pump(1.0)
	assert_eq(_lost, [FtmsClient.DETAIL_ANOTHER_APP] as Array[String])
	assert_eq(FtmsClient.DETAIL_ANOTHER_APP, "another app may hold control")
	assert_eq(_client.state(), FtmsClient.STATE_CONTROL_LOST)
	assert_false(_client.is_ready())
	assert_eq(_ready_count, 0)
	assert_eq(_writes(), ["write 2ad9 00"] as Array[String], "no SIM flat without control")
	assert_eq(_responses, [Vector2i(0x00, 0x05)] as Array[Vector2i])
	assert_push_warning("another app may hold control")


func test_machine_status_ff_means_control_lost_and_request_control_restores() -> void:
	_connect_ready()
	_fake.revoke_control()
	_fake.flush()
	assert_eq(_lost, [FtmsClient.DETAIL_ANOTHER_APP] as Array[String])
	assert_eq(_client.state(), FtmsClient.STATE_CONTROL_LOST)
	assert_has(_statuses, [0xFF, ""])
	assert_push_warning("control lost")
	var before := _writes().size()
	_client.write_control(FtmsCodec.encode_target_power(150))
	assert_eq(_writes().size(), before, "no writes without control")
	assert_push_warning("not in control")
	_client.request_control()
	_pump(0.5)
	assert_true(_client.is_ready())
	assert_eq(_ready_count, 2)
	assert_eq(_writes().slice(before), ["write 2ad9 00", "write 2ad9 " + FLAT])


func test_command_answered_0x05_means_control_lost() -> void:
	_connect_ready()
	_fake.result_override[0x05] = 0x05
	_client.write_control(FtmsCodec.encode_target_power(150))
	_client.write_control(FtmsCodec.encode_indoor_bike_simulation(0.0, 1.0, 0.004, 0.51))
	_pump(0.2)
	assert_eq(_lost.size(), 1)
	assert_eq(_client.queued_count(), 0, "queued writes are dropped")
	assert_eq(_fake.writes_with_op(0x11), 1, "only the flow's SIM flat")
	assert_push_warning("control lost")


func test_request_control_other_failure_fails() -> void:
	_make()
	_fake.result_override[0x00] = 0x04
	_client.begin()
	_pump(1.0)
	assert_eq(_failed, ["Request Control failed: operation failed"] as Array[String])
	assert_eq(_lost.size(), 0)
	assert_push_warning("Request Control failed")


func test_disconnect_resets_the_link() -> void:
	_connect_ready()
	_fake.auto_respond = false
	_client.write_control(FtmsCodec.encode_target_power(150))
	_fake.drop_link("gone")
	_fake.flush()
	assert_eq(_client.state(), FtmsClient.STATE_DISCONNECTED)
	assert_eq(_client.state_detail(), "gone")
	assert_eq(_client.in_flight_opcode(), -1)
	_pump(3.0)
	assert_eq(_failed.size(), 0, "no timeout after the link is gone")


func test_reattach_moves_to_the_new_transport() -> void:
	_make()
	var old := _fake
	var other: FakeKickr = autofree(FakeKickr.new())
	_client.attach(other)
	_client.begin()
	assert_eq(old.ops.size(), 0)
	assert_eq(other.ops, ["discover"] as Array[String])
	old.notify("2ad2", FtmsCodec.from_hex("4400ea0bb400c800"))
	old.flush()
	assert_eq(_records.size(), 0, "the old transport is disconnected")


# --- telemetry ------------------------------------------------------------------------

func test_bike_data_records_and_multi_notification_records() -> void:
	_connect_ready()
	_fake.send_bike_data({"speed_kmh": 30.5, "cadence_rpm": 90.0, "power_w": 200})
	_fake.notify("2ad2", FtmsCodec.from_hex("4500b400c800"))
	_fake.flush()
	assert_eq(_records.size(), 1, "the second record is still pending")
	_fake.notify("2ad2", FtmsCodec.from_hex("0000ea0b"))
	_fake.flush()
	assert_eq(_records.size(), 2)
	assert_almost_eq(float(_records[0]["speed_kmh"]), 30.5, 1e-9)
	assert_eq(int(_records[0]["power_w"]), 200)
	assert_eq(int(_records[1]["parts"]), 2)
	assert_almost_eq(float(_records[1]["cadence_rpm"]), 90.0, 1e-9)
	_fake.notify("2ad2", FtmsCodec.from_hex("4400ea"))
	_fake.flush()
	assert_eq(_records.size(), 2, "a truncated notification is dropped")
	assert_push_error("truncated speed_kmh")
	assert_eq(int(_client.stats()["records"]), 2)


func test_cycling_power_fallback() -> void:
	_make()
	_fake.read_values["2acc"] = FtmsCodec.from_hex("860000000ce00000")
	_client.begin()
	_pump(1.0)
	assert_true(_client.is_ready())
	assert_true(_client.cps_fallback_active())
	assert_has(_fake.ops, "subscribe 2a63")
	assert_lt(_fake.ops.find("subscribe 2a63"), _fake.ops.find("subscribe 2ad9"))
	_fake.send_bike_data({"speed_kmh": 30.5, "cadence_rpm": 90.0})
	_fake.flush()
	assert_false(_records[0].has("power_w"), "no CPS reading yet")
	_fake.notify("2a63", FtmsCodec.from_hex("0000fa00"))
	_fake.send_bike_data({"speed_kmh": 30.5, "cadence_rpm": 90.0})
	_fake.flush()
	assert_eq(int(_records[1]["power_w"]), 250)
	assert_eq(_records[1]["power_source"], "cps")
	_fake.send_bike_data({"speed_kmh": 30.0, "cadence_rpm": 88.0, "power_w": 240})
	_fake.flush()
	assert_eq(int(_records[2]["power_w"]), 240, "FTMS power wins when present")
	assert_false(_records[2].has("power_source"))


func test_no_cycling_power_fallback_without_the_service() -> void:
	_make()
	_fake.read_values["2acc"] = FtmsCodec.from_hex("860000000ce00000")
	_fake.services = [_fake.services[0], _fake.services[2]]
	_client.begin()
	_pump(1.0)
	assert_true(_client.is_ready())
	assert_false(_client.cps_fallback_active())
	assert_does_not_have(_fake.ops, "subscribe 2a63")


func test_runs_while_paused_and_ticks_itself_in_the_tree() -> void:
	_make()
	assert_eq(_client.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(_client.process_self)


# --- hardware lock (BRIEF 1) ----------------------------------------------------------

func test_hardware_lock_refuses_request_control_and_every_write() -> void:
	_set_lock_env("1")
	assert_true(FtmsClient.hardware_locked())
	assert_true(Locks.hw_locked())
	_make(false)
	_client.begin()
	_pump(1.0)
	assert_push_warning("hardware control locked")
	assert_eq(_writes().size(), 0, "no control-point write reached the transport")
	assert_true(_fake.ops.has("discover"), "scan/discovery still works")
	assert_true(_fake.ops.has("read 2acc"), "reads still work")
	for s: String in ["subscribe 2ad2", "subscribe 2ada", "subscribe 2ad9"]:
		assert_has(_fake.ops, s, "subscribing still works")
	assert_eq(_client.state(), FtmsClient.STATE_READ_ONLY)
	assert_eq(_client.state_detail(), Locks.HW_MESSAGE)
	assert_true(_client.is_read_only())
	assert_false(_client.is_ready())
	assert_eq(_ready_count, 1, "telemetry-only client is ready to stream")
	for payload: PackedByteArray in [
		FtmsCodec.encode_request_control(), FtmsCodec.encode_target_power(200),
		FtmsCodec.encode_indoor_bike_simulation(0.0, 5.0, 0.004, 0.51), FtmsCodec.encode_target_resistance(10.0),
		FtmsCodec.encode_stop_pause(1), FtmsCodec.encode_reset(), FtmsCodec.encode_start_resume(),
	]:
		_client.write_control(payload)
		assert_push_warning("hardware control locked")
	_client.request_control()
	assert_push_warning("hardware control locked")
	_pump(3.0)
	assert_eq(_writes().size(), 0, "still nothing written")
	assert_eq(_fake.cp_writes.size(), 0)
	assert_eq(int(_client.stats()["refused_locked"]), 9)
	_fake.send_bike_data({"speed_kmh": 30.5, "cadence_rpm": 90.0, "power_w": 200})
	_fake.flush()
	assert_eq(_records.size(), 1, "bike data still flows")


func test_hardware_lock_reads_the_environment() -> void:
	_set_lock_env("1")
	var c: FtmsClient = autofree(FtmsClient.new())
	assert_true(c._is_hw_locked(), "the production client follows WATTLANDS_NO_HW_CONTROL=1")
	assert_eq(FtmsClient.hardware_locked(), Locks.hw_locked())


func test_lock_is_checked_again_when_a_queued_write_is_sent() -> void:
	_connect_ready()
	_fake.auto_respond = false
	_client.write_control(FtmsCodec.encode_target_power(150))
	_client.write_control(FtmsCodec.encode_indoor_bike_simulation(0.0, 2.0, 0.004, 0.51))
	var before := _fake.cp_writes.size()
	_client.set("lock_on", true)
	_fake.notify("2ad9", PackedByteArray([0x80, 0x05, 0x01]))
	_fake.flush()
	assert_eq(_fake.cp_writes.size(), before, "the queued write is refused at send time")
	assert_eq(_client.queued_count(), 0)
	assert_push_warning("hardware control locked")
