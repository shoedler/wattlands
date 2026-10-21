extends GutTest
## W4 (SAF-8; BRIEF 4.6.9 "On exit, crash paths and disconnect: try SIM flat, then Stop"):
## WlTrainerService.disconnect_trainer(), connect_trainer() (a switch) and use_mock() make the
## trainer safe before its link drops. Real WlTrainerService + LocalRider + SafetyGovernor +
## FtmsConnectionManager + FtmsClient + FtmsTrainer over a fake KICKR (no Bluetooth). W3 found
## that Settings Disconnect never sent SIM flat or Stop, use_mock() dropped the link with the
## Stop still queued, and a switch sent the old rider's SIM flat and Stop to the NEW trainer
## (build/w3/verify_safety_1/test_saf8_stop_before_unlink.gd).

const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const Util := preload("res://tests/core/helpers/core_test_util.gd")

const DT := Wl.SIM_DT
const ADDR := "C4:9D:A1:00:2B:7E"
const OTHER := "11:22:33:44:55:66"
const FLAT := "write 2ad9 11000000002833"
const STOP := "write 2ad9 0801"


## The fake KICKR plus what FtmsConnectionManager needs from a backend.
class KickrLink:
	extends "res://tests/trainer/fake_kickr_transport.gd"
	var linked: String = ""

	func initialize() -> void:
		adapter_ready.emit(true, "")

	func start_scan(_seconds: float) -> void:
		pass

	func stop_scan() -> void:
		pass

	func connect_device(address: String) -> void:
		ops.append("connect " + address)
		linked = address
		_queue("device_connected", [address])

	func disconnect_device() -> void:
		ops.append("disconnect " + linked)
		_queue("device_disconnected", [linked, "local"])


var _dir: String = ""
var _bus: WlEventBus = null
var _settings: WlSettings = null
var _link: KickrLink = null
var _client: FtmsClient = null
var _manager: FtmsConnectionManager = null


func before_each() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	_dir = Paths.make_temp_dir("wattlands_safe_unlink_test")
	Paths.set_override(_dir)
	_bus = WlEventBus.new()
	autofree(_bus)
	_settings = WlSettings.new()
	_settings.bus = _bus
	autofree(_settings)
	_settings.load_all()
	_settings.profile.skip_warmup = true
	# The manager adopts both as children (and frees them with itself), so the trainer's
	# shutdown at teardown still finds its transport.
	_link = KickrLink.new()
	_client = UnlockedClient.new()
	_client.process_self = false
	_manager = null


func after_each() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	Util.remove_tree(_dir)
	await wait_process_frames(1)


func _service() -> WlTrainerService:
	var svc := WlTrainerService.new()
	svc.settings = _settings
	svc.bus = _bus
	svc.connection_factory = func() -> FtmsConnectionManager:
		var m := FtmsConnectionManager.new()
		m.manual_clock = true
		m.make_gdble = func() -> BleTransport: return _link
		m.make_client = func() -> FtmsClient: return _client
		_manager = m
		return m
	svc.rider_options_factory = func() -> Dictionary: return {"bus": _bus}
	add_child_autofree(svc)
	return svc


func _pump(svc: WlTrainerService, seconds: float, manager: FtmsConnectionManager = null) -> void:
	var m := manager if manager != null else _manager
	for i in roundi(seconds / DT):
		_link.flush()
		if m != null and is_instance_valid(m):
			m.tick(DT)
		_client.tick(DT)
		_link.flush()
		svc._process(DT)


func _ready_service() -> WlTrainerService:
	var svc := _service()
	svc.start()
	svc.connect_trainer(ADDR)
	_pump(svc, 3.0)
	assert_true(_client.is_ready(), "precondition: in control")
	assert_true(
		svc.device() is FtmsTrainer, "precondition: the FTMS trainer is the service's device"
	)
	assert_not_null(svc.local_rider())
	assert_true(_link.ops.has(FLAT), "precondition: the menus ride SIM flat")
	return svc


## The control-point writes and link calls from index `from` on.
func _since(from: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(from, _link.ops.size()):
		var op := _link.ops[i]
		if (
			op.begins_with("write 2ad9")
			or op.begins_with("disconnect")
			or op.begins_with("connect")
		):
			out.append(op)
	return out


func test_disconnect_sends_sim_flat_then_stop_before_the_link_drops() -> void:
	var svc := _ready_service()
	var rider := svc.local_rider()
	var n := _link.ops.size()
	svc.disconnect_trainer()
	assert_true(rider.is_shut_down(), "the rider (and its governor) is shut down")
	assert_null(svc.device(), "no device until a trainer is ready again")
	assert_true(svc.is_unlinking(), "the link waits for the control point")
	assert_false(_since(n).has("disconnect " + ADDR), "not yet dropped")
	_pump(svc, 1.0)
	assert_false(svc.is_unlinking())
	assert_eq(
		_since(n), [FLAT, STOP, "disconnect " + ADDR], "SIM flat, then Stop, then the link drops"
	)
	assert_eq(_manager.status(), TrainerDevice.STATUS_DISCONNECTED)


func test_a_reconnect_after_disconnect_sets_a_new_rider_up() -> void:
	var svc := _ready_service()
	svc.disconnect_trainer()
	_pump(svc, 1.0)
	svc.connect_trainer(ADDR)
	_pump(svc, 3.0)
	assert_true(_client.is_ready())
	assert_not_null(svc.device())
	var r := svc.local_rider()
	assert_not_null(r)
	assert_false(r.is_shut_down(), "a live rider on the trainer again")


func test_switching_trainers_makes_the_old_one_safe_and_never_stops_the_new_one() -> void:
	var svc := _ready_service()
	var old_device := svc.device()
	var n := _link.ops.size()
	svc.connect_trainer(OTHER)
	assert_true(svc.is_unlinking())
	_pump(svc, 3.0)
	var ops := _since(n)
	var at_connect := ops.find("connect " + OTHER)
	assert_gt(at_connect, -1, "connected to the other trainer: %s" % str(ops))
	assert_eq(
		ops.slice(0, 3),
		[FLAT, STOP, "disconnect " + ADDR],
		"the old trainer: SIM flat, Stop, then the link drops"
	)
	assert_false(
		ops.slice(at_connect).has(STOP),
		"no Stop reaches the new trainer: %s" % str(ops.slice(at_connect))
	)
	assert_true(_client.is_ready(), "in control of the other trainer")
	assert_ne(svc.device(), old_device)
	assert_not_null(svc.local_rider())
	assert_false(svc.local_rider().is_shut_down())


func test_use_mock_sends_stop_before_dropping_the_real_trainer() -> void:
	var svc := _ready_service()
	var m := _manager
	var n := _link.ops.size()
	svc.use_mock("erg")
	assert_true(svc.is_mock(), "the mock takes over at once")
	assert_null(svc.connection())
	assert_true(svc.is_unlinking())
	assert_false(m.is_queued_for_deletion(), "the old manager waits for the Stop")
	_pump(svc, 1.0, m)
	assert_eq(
		_since(n),
		[FLAT, STOP, "disconnect " + ADDR],
		"W3: only SIM flat went out before the link dropped"
	)
	assert_true(m.is_queued_for_deletion())


func test_an_unanswering_trainer_is_dropped_after_the_timeout() -> void:
	var svc := _ready_service()
	_link.drop_writes = 100
	var n := _link.ops.size()
	svc.disconnect_trainer()
	_pump(svc, WlTrainerService.SAFE_UNLINK_TIMEOUT_S - 0.1)
	assert_false(_since(n).has("disconnect " + ADDR), "still waiting")
	_pump(svc, 0.2)
	assert_true(
		_since(n).has("disconnect " + ADDR),
		"dropped after %.1f s" % WlTrainerService.SAFE_UNLINK_TIMEOUT_S
	)
	assert_push_warning("did not all go out")


func test_under_the_hardware_lock_the_link_drops_at_once() -> void:
	_client.lock_on = true
	var svc := _service()
	svc.start()
	svc.connect_trainer(ADDR)
	_pump(svc, 3.0)
	assert_true(_client.is_read_only(), "precondition: read-only under the lock")
	var n := _link.ops.size()
	svc.disconnect_trainer()
	assert_false(svc.is_unlinking(), "nothing can go out: no wait")
	assert_eq(_since(n), ["disconnect " + ADDR])
	assert_push_warning("hardware control locked")


func test_disconnect_is_refused_during_a_session() -> void:
	var svc := _ready_service()
	svc.set_external_tick(true)
	svc.disconnect_trainer()
	assert_push_warning("during a session")
	assert_not_null(svc.device())
	assert_false(svc.local_rider().is_shut_down())
