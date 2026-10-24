extends GutTest
## WlTrainerService's heart rate sensor: the FTMS path starts one HrSensorManager whose
## transport rides the trainer's backend (a GdbleTransport sharing the trainer transport's
## BluetoothManager, or a second BridgeTransport on the same URL), a mock trainer has none, and
## the app's rider reads the sensor's bpm. Nothing here touches Bluetooth.

const FakeManager := preload("res://tests/ble/fake_bluetooth_manager.gd")
const Util := preload("res://tests/core/helpers/core_test_util.gd")


## A bridge transport whose socket is never opened: initialize() answers at once.
class ReadyBridge:
	extends BridgeTransport

	func initialize() -> void:
		adapter_ready.emit(true, "")


var _dir: String = ""
var _bus: WlEventBus = null
var _settings: WlSettings = null
var _mgr: FakeManager = null


func before_each() -> void:
	CmdLine.set_args(PackedStringArray(), true)
	_dir = Paths.make_temp_dir("wattlands_trainer_service_hr_test")
	Paths.set_override(_dir)
	_bus = WlEventBus.new()
	autofree(_bus)
	_settings = WlSettings.new()
	_settings.bus = _bus
	autofree(_settings)
	_settings.load_all()
	_mgr = FakeManager.new()


func after_each() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	Util.remove_tree(_dir)
	if is_instance_valid(_mgr) and _mgr.get_parent() == null:
		_mgr.free()
	await wait_process_frames(1)


func _make(backend: String) -> WlTrainerService:
	var svc := WlTrainerService.new()
	svc.settings = _settings
	svc.bus = _bus
	svc.connection_factory = func() -> FtmsConnectionManager:
		var m := FtmsConnectionManager.new()
		m.manual_clock = true
		m.make_gdble = func() -> BleTransport:
			if backend != "gdble":
				return null
			var g := GdbleTransport.new()
			g.manager_factory = func() -> Node: return _mgr
			return g
		m.make_bridge = func() -> BleTransport:
			var b := ReadyBridge.new()
			b.url = "ws://127.0.0.1:8799"
			return b
		return m
	add_child_autofree(svc)
	return svc


func test_gdble_backend_gives_a_sharing_transport() -> void:
	var svc := _make("gdble")
	svc.start()
	assert_eq(svc.connection().backend_name(), FtmsConnectionManager.BACKEND_GDBLE)
	assert_not_null(svc.hr_manager(), "the FTMS path starts the heart rate sensor manager")
	var t := svc._make_hr_transport() as GdbleTransport
	assert_not_null(t)
	assert_eq(t.primary(), svc.connection().transport(), "shares the trainer's manager")
	t.free()
	assert_eq(_mgr.count("initialize"), 1, "the adapter is initialized once")


func test_bridge_backend_gives_a_second_bridge_transport() -> void:
	var svc := _make("bridge")
	svc.start()
	assert_eq(svc.connection().backend_name(), FtmsConnectionManager.BACKEND_BRIDGE)
	var t := svc._make_hr_transport() as BridgeTransport
	assert_not_null(t)
	assert_ne(t, svc.connection().transport())
	assert_eq(t.url, "ws://127.0.0.1:8799")
	t.free()


func test_a_mock_trainer_has_no_sensor_manager() -> void:
	CmdLine.set_args(PackedStringArray(["--mock-trainer=erg"]), true)
	var svc := _make("gdble")
	svc.start()
	assert_null(svc.hr_manager())
	assert_eq(svc.heart_rate_bpm(), 0)
	assert_eq(svc.hr_status(), TrainerDevice.STATUS_DISCONNECTED)
	assert_eq(svc._make_hr_transport(), null)
	assert_true(svc.local_rider().heart_rate_source.is_valid(), "the rider asks the service")
	assert_eq(svc.local_rider().heart_rate_source.call(), 0)
