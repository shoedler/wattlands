extends GutTest
## W4 fixes in FtmsConnectionManager / FtmsClient / FtmsTrainer (adapted from the W3 proofs in
## build/w3/ftms-ble/test_ftms_ble_review.gd):
##   - ftms-ble-1 (BRIEF 4.4, 4.6.5, 4.6.9): a control-point write left unanswered after its two
##     retries while the trainer is ready ("the link is presumed dead") reconnects, so panic,
##     rescue and the exit writes reach the trainer again; a write the transport rejects
##     synchronously is retried on the next tick, not recursively inside the write call.
##   - ftms-ble-3 (BRIEF 3.5): each auto-scan window stops the previous scan before starting
##     the next (GDBLE refuses a duplicate start with BUSY).
##   - SAF-8: a switch to another trainer releases the old FtmsTrainer from the shared client,
##     so nothing its rider still writes reaches the next trainer.

const FakeKickr := preload("res://tests/trainer/fake_kickr_transport.gd")
const UnlockedClient := preload("res://tests/trainer/unlocked_ftms_client.gd")
const FakeTransport := preload("res://tests/ble/fake_transport.gd")
const FakeClient := preload("res://tests/ble/fake_ftms_client.gd")

const DT := 0.05
const ADDR := "C4:9D:A1:00:2B:7E"
const OTHER := "11:22:33:44:55:66"


## The fake KICKR plus what FtmsConnectionManager needs from a backend (adapter, connect).
class KickrLink:
	extends "res://tests/trainer/fake_kickr_transport.gd"
	var connects: int = 0
	var disconnects: int = 0
	var scans: Array = []
	var linked: String = ""
	## connect_device() to this address never answers (a trainer that is off).
	var hang_for: String = ""

	func initialize() -> void:
		adapter_ready.emit(true, "")

	func start_scan(seconds: float) -> void:
		scans.append(["start", seconds])

	func stop_scan() -> void:
		scans.append(["stop"])

	func connect_device(address: String) -> void:
		connects += 1
		ops.append("connect " + address)
		if address == hang_for:
			return
		linked = address
		_queue("device_connected", [address])

	func disconnect_device() -> void:
		disconnects += 1
		ops.append("disconnect")
		_queue("device_disconnected", [linked, "local"])


## A KICKR link whose control-point writes the backend rejects inside the write call itself
## (GDBLE's synchronous BUSY / QUEUE_FULL) while `reject_sync` > 0.
class BusyLink:
	extends KickrLink
	var reject_sync: int = 0
	var depth: int = 0
	var max_depth: int = 0

	func write_characteristic(
		service_uuid: String, char_uuid: String, data: PackedByteArray, with_response: bool
	) -> void:
		if reject_sync > 0 and short(char_uuid) == FtmsCodec.CHAR_CONTROL_POINT:
			reject_sync -= 1
			ops.append("rejected %s" % FtmsCodec.to_hex(data))
			depth += 1
			max_depth = maxi(max_depth, depth)
			operation_failed.emit("write", "BUSY")
			depth -= 1
			return
		super.write_characteristic(service_uuid, char_uuid, data, with_response)


var _dir: String = ""


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_w4_link_recovery")
	Paths.set_override(_dir)


func after_each() -> void:
	Paths.set_override("")
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _cp_writes(link: FakeKickr) -> Array[String]:
	var out: Array[String] = []
	for op in link.ops:
		if op.begins_with("write 2ad9"):
			out.append(op)
	return out


func _pump(m: FtmsConnectionManager, link: KickrLink, client: FtmsClient, seconds: float) -> void:
	for i in roundi(seconds / DT):
		link.flush()
		m.tick(DT)
		client.tick(DT)
		link.flush()


func _manager(link: KickrLink, client: FtmsClient) -> FtmsConnectionManager:
	var m := FtmsConnectionManager.new()
	m.manual_clock = true
	m.make_gdble = func() -> BleTransport: return link
	m.make_client = func() -> FtmsClient: return client
	add_child_autofree(m)
	return m


func _ready_stack(link: KickrLink) -> Dictionary:
	var client: FtmsClient = UnlockedClient.new()
	client.process_self = false
	var m := _manager(link, client)
	var reconnected: Array = []
	m.reconnected.connect(func(d: TrainerDevice) -> void: reconnected.append(d))
	m.start(false)
	m.connect_to(ADDR)
	_pump(m, link, client, 1.0)
	return {"m": m, "client": client, "reconnected": reconnected}


# --- ftms-ble-1 ---------------------------------------------------------------------------------


## Manager level: FtmsClient.failed while READY must lead to a reconnect (drop the link, back
## off, begin() again), as it does during setup. W3: the manager stayed READY.
func test_client_failure_while_ready_triggers_recovery() -> void:
	var gd := FakeTransport.new()
	var br := FakeTransport.new()
	br.init_error = "bridge not reachable"
	var client := FakeClient.new()
	var m := FtmsConnectionManager.new()
	m.manual_clock = true
	m.make_gdble = func() -> BleTransport: return gd
	m.make_bridge = func() -> BleTransport: return br
	m.make_client = func() -> FtmsClient: return client
	m.make_trainer = func(_c: FtmsClient, _n: String) -> TrainerDevice: return TrainerDevice.new()
	var reconnected: Array = []
	m.reconnected.connect(func(d: TrainerDevice) -> void: reconnected.append(d))
	add_child_autofree(m)
	m.start(false)
	gd.advertise(ADDR, "KICKR CORE")
	m.connect_to(ADDR)
	assert_true(m.is_ready(), "precondition: ready")
	client.failed.emit("control point Set Target Power unanswered after 3 attempts (timeout)")
	assert_push_warning("reconnecting")
	assert_false(m.is_ready(), "the manager does not stay READY after the client failed")
	assert_eq(gd.count("disconnect_device"), 1, "the dead link is dropped")
	assert_true(m.is_reconnecting())
	assert_eq(m.status(), TrainerDevice.STATUS_DISCONNECTED)
	for i in 60:
		m.tick(DT)
	assert_eq(gd.count("connect_device"), 2, "reconnects after the 1 s backoff")
	assert_eq(client.begin_count, 2, "the 4.4 flow runs again")
	assert_true(m.is_ready())
	assert_eq(reconnected.size(), 1, "reconnected: the governor restores its last safe mode")
	br.free()


func test_client_failure_after_a_control_loss_also_reconnects() -> void:
	var gd := FakeTransport.new()
	var client := FakeClient.new()
	var m := FtmsConnectionManager.new()
	m.manual_clock = true
	m.make_gdble = func() -> BleTransport: return gd
	m.make_client = func() -> FtmsClient: return client
	m.make_trainer = func(_c: FtmsClient, _n: String) -> TrainerDevice: return TrainerDevice.new()
	add_child_autofree(m)
	m.start(false)
	m.connect_to(ADDR)
	client.control_lost.emit("another app may hold control")
	assert_eq(m.status(), TrainerDevice.STATUS_CONTROL_LOST)
	client.failed.emit("control point Request Control unanswered after 3 attempts (timeout)")
	assert_push_warning("reconnecting")
	assert_eq(gd.count("disconnect_device"), 1)
	assert_true(m.is_reconnecting())


## Full stack (real manager + FtmsClient + FtmsTrainer over a fake KICKR): three lost
## indications for one ERG write, then the panic SIM flat must reach the trainer after the
## automatic reconnect. W3: "not in control (failed); dropped Set Indoor Bike Simulation".
func test_panic_write_after_an_unanswered_write_reaches_the_trainer() -> void:
	var link: KickrLink = autofree(KickrLink.new())
	var st := _ready_stack(link)
	var m: FtmsConnectionManager = st["m"]
	var client: FtmsClient = st["client"]
	assert_true(client.is_ready(), "precondition: in control")
	var dev: TrainerDevice = m.device()
	assert_not_null(dev)
	link.drop_writes = 3
	dev.set_target_power(250)
	_pump(m, link, client, 6.5)
	assert_push_warning("unanswered")
	assert_push_warning("reconnecting")
	assert_eq(link.disconnects, 1, "the dead link was dropped")
	_pump(m, link, client, 5.0)
	assert_true(
		client.is_ready(), "back in control after the reconnect (state %s)" % client.state()
	)
	assert_eq(link.connects, 2)
	assert_eq((st["reconnected"] as Array).size(), 1)
	assert_same(m.device(), dev, "the same trainer object")
	var before := _cp_writes(link).size()
	dev.set_simulation(0.0, 0.0, 0.004, 0.51)  # what emergency_safe() sends
	_pump(m, link, client, 1.0)
	var after := _cp_writes(link)
	assert_gt(after.size(), before, "the panic SIM flat reaches the trainer")
	assert_eq(after.back(), "write 2ad9 11000000002833")


## A synchronous rejection (the transport fails the write inside write_characteristic) is retried
## on the next tick: no recursion, one write per tick, then failed() and the reconnect.
func test_a_synchronous_write_rejection_is_retried_on_the_next_tick() -> void:
	var link: BusyLink = autofree(BusyLink.new())
	var st := _ready_stack(link)
	var m: FtmsConnectionManager = st["m"]
	var client: FtmsClient = st["client"]
	assert_true(client.is_ready())
	link.reject_sync = 3
	m.device().set_target_power(200)
	assert_eq(link.max_depth, 1, "no re-entrant write inside the rejection")
	assert_eq(client.state(), FtmsClient.STATE_READY, "one rejection is no failure")
	var rejected := func() -> int:
		return link.ops.filter(func(o: String) -> bool: return o.begins_with("rejected")).size()
	assert_eq(rejected.call(), 1)
	client.tick(DT)
	assert_eq(rejected.call(), 2, "the first retry on the next tick")
	client.tick(DT)
	assert_eq(rejected.call(), 3, "the second retry one tick later")
	assert_eq(client.state(), FtmsClient.STATE_READY, "the third rejection is still being handled")
	client.tick(DT)
	assert_eq(rejected.call(), 3, "no fourth send")
	assert_eq(client.state(), FtmsClient.STATE_FAILED, "three rejections: failed()")
	assert_push_warning("unanswered")
	assert_push_warning("reconnecting")
	assert_eq(link.max_depth, 1)
	_pump(m, link, client, 5.0)
	assert_true(client.is_ready(), "reconnected")


func test_a_single_synchronous_rejection_then_success() -> void:
	var link: BusyLink = autofree(BusyLink.new())
	var st := _ready_stack(link)
	var m: FtmsConnectionManager = st["m"]
	var client: FtmsClient = st["client"]
	link.reject_sync = 1
	m.device().set_target_power(180)
	_pump(m, link, client, 0.5)
	assert_eq(_cp_writes(link).back(), "write 2ad9 05b400", "sent on the retry")
	assert_true(client.is_ready())
	assert_eq(int(client.stats()["cp_retries"]), 1)


# --- ftms-ble-3 ---------------------------------------------------------------------------------


func test_auto_rescan_stops_the_previous_scan_first() -> void:
	FtmsConnectionManager.write_last_device("AA:AA:AA:AA:AA:AA", "KICKR CORE")
	var link: KickrLink = autofree(KickrLink.new())
	var client: FtmsClient = autofree(UnlockedClient.new())
	client.process_self = false
	var m := _manager(link, client)
	m.start(true)
	for i in roundi(61.0 / DT):
		m.tick(DT)
	assert_eq(
		link.scans.size(),
		5,
		"three windows: start, stop + start, stop + start: %s" % str(link.scans)
	)
	assert_eq(link.scans[0], ["start", FtmsConnectionManager.AUTO_SCAN_S])
	# GDBLE: "A duplicate start fails with BUSY without replacing the active scan."
	for i in range(1, link.scans.size()):
		if link.scans[i][0] == "start":
			assert_eq(link.scans[i - 1][0], "stop", "start_scan #%d follows a stop_scan" % i)


func test_a_manual_scan_during_a_scan_stops_it_first() -> void:
	var link: KickrLink = autofree(KickrLink.new())
	var client: FtmsClient = autofree(UnlockedClient.new())
	var m := _manager(link, client)
	m.start(false)
	m.scan(10.0)
	assert_eq(
		link.scans, [["start", FtmsConnectionManager.DEFAULT_SCAN_S], ["stop"], ["start", 10.0]]
	)
	m.stop_scan()
	m.scan(5.0)
	assert_eq(link.scans.slice(3), [["stop"], ["start", 5.0]], "after a stop: no second stop")


# --- SAF-8: switching trainers ------------------------------------------------------------------


func test_a_switch_releases_the_old_trainer_from_the_shared_client() -> void:
	var link: KickrLink = autofree(KickrLink.new())
	var st := _ready_stack(link)
	var m: FtmsConnectionManager = st["m"]
	var client: FtmsClient = st["client"]
	var old := m.device() as FtmsTrainer
	assert_not_null(old)
	assert_eq(m.linked_address(), ADDR)
	m.connect_to(OTHER)
	assert_null(old.client(), "the old trainer object is released at once")
	assert_eq(old.status(), TrainerDevice.STATUS_DISCONNECTED)
	_pump(m, link, client, 1.0)
	assert_true(client.is_ready(), "in control of the other trainer")
	assert_eq(m.linked_address(), OTHER)
	var fresh := m.device()
	assert_ne(fresh, old, "a new trainer object for the other trainer")
	var n := link.cp_writes.size()
	old.set_target_power(300)
	old.request_stop()
	assert_push_warning("no client")
	_pump(m, link, client, 1.0)
	assert_eq(
		link.cp_writes.size(), n, "nothing the old trainer's rider writes reaches the other trainer"
	)


func test_back_to_a_released_trainer_gets_a_fresh_object() -> void:
	var link: KickrLink = autofree(KickrLink.new())
	var st := _ready_stack(link)
	var m: FtmsConnectionManager = st["m"]
	var client: FtmsClient = st["client"]
	var first := m.device() as FtmsTrainer
	link.hang_for = OTHER
	m.connect_to(OTHER)
	_pump(m, link, client, 1.0)
	assert_null(first.client())
	m.connect_to(ADDR)
	_pump(m, link, client, 1.0)
	assert_true(client.is_ready())
	var again := m.device() as FtmsTrainer
	assert_not_null(again.client(), "a trainer object that can write")
	assert_ne(again, first)


func test_linked_address_is_empty_without_a_link() -> void:
	var link: KickrLink = autofree(KickrLink.new())
	var st := _ready_stack(link)
	var m: FtmsConnectionManager = st["m"]
	m.disconnect_trainer()
	assert_eq(m.linked_address(), "")
