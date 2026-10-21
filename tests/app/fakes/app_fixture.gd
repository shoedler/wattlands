extends RefCounted
## Builds AppServices from test doubles for the app-shell tests: fake App, Settings,
## TrainerService (a MockTrainer device and a fake local rider), NetSession, GameRegistry (the
## fixture games), Rides, InputRouter, a private EventBus, a scripted PedalScanList and a fake
## GameHost. Persisted files go to a fresh temp dir (Paths.set_override). Call free_all() in
## after_each.

const FakeApp := preload("res://tests/app/fakes/fake_app.gd")
const FakeSettings := preload("res://tests/app/fakes/fake_settings.gd")
const FakeTrainer := preload("res://tests/app/fakes/fake_trainer.gd")
const FakeNet := preload("res://tests/app/fakes/fake_net.gd")
const FakeRegistry := preload("res://tests/app/fakes/fake_registry.gd")
const FakeRides := preload("res://tests/app/fakes/fake_rides.gd")
const FakeInput := preload("res://tests/app/fakes/fake_input.gd")
const FakeScanList := preload("res://tests/app/fakes/fake_scan_list.gd")
const FakeHost := preload("res://tests/app/fakes/fake_game_host.gd")
const FakeRider := preload("res://tests/app/fakes/fake_rider.gd")
const FakeSfx := preload("res://tests/app/fakes/fake_sfx.gd")

var services: AppServices = null
var app: WlApp = null
var settings: WlSettings = null
var trainer: WlTrainerService = null
var net: WlNetSession = null
var registry: WlGameRegistry = null
var rides: WlRides = null
var input: WlInputRouter = null
var bus: WlEventBus = null
var sfx: WlSfx = null
var lists: Array[PedalScanList] = []
var hosts: Array[GameHost] = []
var riders: Array[LocalRider] = []
var quits: Array[int] = []
var tmp_dir: String = ""


func _init() -> void:
	tmp_dir = Paths.make_temp_dir("wattlands_app_test")
	Paths.set_override(tmp_dir)
	app = FakeApp.new()
	settings = FakeSettings.new()
	trainer = FakeTrainer.new()
	net = FakeNet.new()
	registry = FakeRegistry.new()
	rides = FakeRides.new()
	input = FakeInput.new()
	bus = WlEventBus.new()
	sfx = FakeSfx.new()
	services = AppServices.new()
	services.app = app
	services.settings = settings
	services.trainer = trainer
	services.net = net
	services.registry = registry
	services.rides = rides
	services.input = input
	services.bus = bus
	services.sfx = sfx
	services.utc_override = 1800000000
	services.scan_list_factory = _make_list
	services.game_host_factory = _make_host
	services.rider_factory = _make_rider
	services.quit_hook = func(code: int) -> void: quits.append(code)
	(registry as FakeRegistry).add_fixture(FakeRegistry.workout())
	(registry as FakeRegistry).add_fixture(FakeRegistry.siege())
	(registry as FakeRegistry).add_fixture(FakeRegistry.tank())
	var t := trainer as FakeTrainer
	t.dev = MockTrainer.from_spec("erg", 200.0)
	t.add_child(t.dev)
	var r := FakeRider.new()
	t.rider = r
	t.add_child(r)
	t.st = TrainerDevice.STATUS_READY


func _make_list() -> PedalScanList:
	var l := FakeScanList.new()
	lists.append(l)
	return l


func _make_host() -> GameHost:
	var h := FakeHost.new()
	hosts.append(h)
	return h


func _make_rider() -> LocalRider:
	var r := FakeRider.new()
	riders.append(r)
	return r


## A saved profile (created = true) with this FTP.
func give_profile(ftp: float = 250.0, name: String = "Ada") -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = name
	p.ftp_w = ftp
	p.cp_w = ftp
	p.ftp_verified = true
	p.created = true
	settings.profile = p
	return p


func fake_net() -> FakeNet:
	return net as FakeNet


func fake_registry() -> FakeRegistry:
	return registry as FakeRegistry


func fake_rides() -> FakeRides:
	return rides as FakeRides


func fake_trainer() -> FakeTrainer:
	return trainer as FakeTrainer


func fake_app() -> FakeApp:
	return app as FakeApp


func fake_sfx() -> FakeSfx:
	return sfx as FakeSfx


func last_host() -> FakeHost:
	return hosts[hosts.size() - 1] as FakeHost if not hosts.is_empty() else null


func free_all() -> void:
	# Break the services <-> fixture reference cycle (the quit hook lambda captures self).
	services.quit_hook = Callable()
	services.scan_list_factory = Callable()
	services.game_host_factory = Callable()
	services.rider_factory = Callable()
	for r in riders:
		if is_instance_valid(r) and r.get_parent() == null:
			r.free()
	for n: Node in [app, settings, trainer, net, registry, rides, input, bus, sfx]:
		if is_instance_valid(n):
			n.free()
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	_remove_tree(tmp_dir)


static func _remove_tree(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
