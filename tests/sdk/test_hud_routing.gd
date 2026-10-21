extends GutTest
## HudRouter, ctx.hud (BRIEF 3.6, 7.1 "a host-side power_band reaching a client's power gauge
## and MockTrainer", "a toast with a peer reaching only that peer", "the roster reaching every
## client"; docs/OWNERSHIP.md HUD7-HUD9, CTX12; 3.1 C1, C27).

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")

var _root: Node = null
var _hud: HudRouter = null
var _bus: WlEventBus = null
var _sent: Array = []
var _toasts: Array = []
var _banners: Array = []
var _pbands: Array = []
var _local: LocalRider = null
var _bot: LocalRider = null


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_sent = []
	_toasts = []
	_banners = []
	_pbands = []
	_bus = Kit.new_bus(_root, "Bus")
	var s1 := Kit.human(1, 0)
	var s2 := Kit.human(2, 1)
	var sb := Bots.make_slot(1, 2, 200.0)
	_local = Kit.rider(_root, s1)
	_bot = Kit.rider(_root, sb)
	_hud = HudRouter.new()
	_hud.role = Wl.HOST
	_hud.local_peer = 1
	_hud.riders = {1: _local, -1: _bot}
	_hud.slots = {1: s1, 2: s2, -1: sb}
	_hud.bus = _bus
	_hud.send = func(peer: int, msg: Dictionary) -> void: _sent.append([peer, msg])
	_bus.toast_requested.connect(func(key: String, args: Variant) -> void: _toasts.append([key, args]))
	_bus.banner_requested.connect(func(key: String, args: Variant, seconds: float) -> void: _banners.append([key, args, seconds]))
	_bus.power_band_changed.connect(func(peer: int, lo: float, hi: float) -> void: _pbands.append([peer, lo, hi]))


func test_power_band_for_the_hosts_own_rider() -> void:
	_hud.power_band(1, 240, 280)
	assert_eq(_local.get("power_band"), [240.0, 280.0])
	assert_eq((_local.device as Object).call("last_power_band"), [240.0, 280.0], "MockTrainer's erg rides the band in SIM")
	assert_eq(_pbands, [[1, 240.0, 280.0]])
	assert_eq(_sent, [], "nothing is sent for a local rider")
	assert_eq(_hud.band_of(1), [240.0, 280.0])


func test_power_band_for_a_remote_rider_is_a_directive() -> void:
	_hud.power_band(2, 150, 210)
	assert_eq(_sent.size(), 1)
	assert_eq(_sent[0][0], 2)
	var msg: Dictionary = _sent[0][1]
	assert_eq(msg["type"], "directive")
	assert_eq(msg["kind"], NetMessages.DIRECTIVE_POWER_BAND)
	assert_eq(msg["lo_w"], 150.0)
	assert_eq(msg["hi_w"], 210.0)
	assert_eq(_pbands, [[2, 150.0, 210.0]], "the host's bus knows every band")


func test_power_band_for_a_bot_and_clearing() -> void:
	_hud.power_band(-1, 100, 120)
	assert_eq(_bot.get("power_band"), [100.0, 120.0])
	_hud.power_band(-1, 0, 0)
	assert_eq(_bot.get("power_band"), [0.0, 0.0])
	assert_eq(_hud.band_of(-1), [0.0, 0.0])
	_hud.power_band(1, 300, 200)
	assert_push_warning("power_band")


func test_cooldown_clears_a_power_band() -> void:
	_hud.power_band(1, 240, 280)
	_pbands.clear()
	_hud.clear_power_band(1)
	assert_eq(_local.get("power_band"), [0.0, 0.0])
	assert_eq(_pbands, [[1, 0.0, 0.0]])


func test_toast_routing_on_the_host() -> void:
	_hud.toast("FX_SOLO_HELLO", ["all"])
	assert_eq(_toasts, [["FX_SOLO_HELLO", ["all"]]], "ALL_PEERS draws on the host")
	assert_eq(_sent.size(), 1)
	assert_eq(_sent[0][0], Wl.ALL_PEERS)
	assert_eq(_sent[0][1]["type"], "hud")
	assert_eq(_sent[0][1]["kind"], "toast")
	_toasts.clear()
	_sent.clear()
	_hud.toast("FX_MINE", [], 1)
	assert_eq(_toasts.size(), 1, "the host's own peer draws here")
	assert_eq(_sent, [], "and sends nothing")
	_toasts.clear()
	_hud.toast("FX_YOURS", [], 2)
	assert_eq(_toasts, [], "another peer's toast never draws on the host")
	assert_eq(_sent.size(), 1)
	assert_eq(_sent[0][0], 2)
	_sent.clear()
	_hud.toast("FX_BOT", [], -1)
	assert_eq(_sent, [], "bots have no HUD")
	assert_eq(_toasts, [])


func test_banner_routing_on_the_host() -> void:
	_hud.banner("FX_BIG", [1], 5.0, 2)
	assert_eq(_banners, [])
	assert_eq(_sent[0][1]["kind"], "banner")
	assert_eq(_sent[0][1]["seconds"], 5.0)
	_hud.banner("FX_BIG", [], 2.0)
	assert_eq(_banners, [["FX_BIG", [], 2.0]])


func test_client_draws_everything_locally() -> void:
	_hud.role = Wl.CLIENT
	_hud.local_peer = 2
	var own := Kit.rider(_root, Kit.human(2, 1))
	_hud.riders = {2: own}
	_hud.toast("FX_X", [], 1)
	assert_eq(_toasts.size(), 1)
	_hud.banner("FX_Y")
	assert_eq(_banners.size(), 1)
	_hud.power_band(2, 200, 240)
	assert_eq(own.get("power_band"), [200.0, 240.0], "the client's own rider (C27)")
	_hud.power_band(1, 100, 140)
	assert_eq(_pbands.size(), 2, "another peer's band only draws")
	assert_eq(_sent, [], "a client sends nothing")


func test_teammate_status() -> void:
	_hud.teammate_status(2, {"in_band": true, "icon": "res://x.png", "text": "Diesel", "junk": 1})
	assert_eq(_hud.statuses[2], {"in_band": true, "icon": "res://x.png", "text": "Diesel"})
	var got: Array = []
	_hud.role = Wl.CLIENT
	_hud.local_status_changed.connect(func(peer: int, s: Dictionary) -> void: got.append([peer, s]))
	_hud.teammate_status(1, {"in_band": false})
	assert_eq(got.size(), 1)


func test_readout_is_local() -> void:
	var got: Array = []
	_bus.readout_changed.connect(func(id: String, text: String) -> void: got.append([id, text]))
	_hud.readout("gate_hp", "120")
	assert_eq(got, [["gate_hp", "120"]])
	assert_eq(_sent, [])


# --- through GameHost with a host and two FakeNet clients ---------------------------------


func test_host_power_band_reaches_a_clients_gauge_and_mock_trainer() -> void:
	var b := Kit.multi(_root, 3)
	assert_eq(b["err"], "")
	Kit.start(b)
	Kit.step(b, 2)
	var host: GameHost = b["host"]
	var got: Array = []
	(b["buses"][1] as WlEventBus).power_band_changed.connect(func(peer: int, lo: float, hi: float) -> void: got.append([peer, lo, hi]))
	host.ctx.hud.power_band(2, 210, 260)
	Kit.step(b, 1)
	assert_eq(got, [[2, 210.0, 260.0]], "the client's gauge")
	var r2: LocalRider = b["riders"][2]
	assert_eq(r2.get("power_band"), [210.0, 260.0])
	assert_eq((r2.device as Object).call("last_power_band"), [210.0, 260.0], "the client's MockTrainer")
	var r3: LocalRider = b["riders"][3]
	assert_eq(r3.get("power_band"), [0.0, 0.0], "nobody else")


func test_toast_with_a_peer_reaches_only_that_peer() -> void:
	var b := Kit.multi(_root, 3)
	Kit.start(b)
	Kit.step(b, 2)
	var counts := [0, 0, 0]
	for i in 3:
		var idx := i
		(b["buses"][i] as WlEventBus).toast_requested.connect(func(_k: String, _a: Variant) -> void: counts[idx] += 1)
	var host: GameHost = b["host"]
	host.ctx.hud.toast("FX_ONLY_YOU", [], 3)
	Kit.step(b, 2)
	assert_eq(counts, [0, 0, 1])
	host.ctx.hud.toast("FX_EVERYONE")
	Kit.step(b, 2)
	assert_eq(counts, [1, 1, 2])


func test_roster_reaches_every_client() -> void:
	var b := Kit.multi(_root, 3, "tiny", {}, 1)
	Kit.start(b)
	var host: GameHost = b["host"]
	host.ctx.hud.teammate_status(2, {"in_band": true, "text": "Diesel"})
	Kit.step(b, 25)
	for c: GameHost in b["clients"]:
		var roster: Dictionary = c.ctx.roster
		assert_eq(roster.keys().size(), 4, "every slot, the bot included")
		for peer: int in [1, 2, 3, -1]:
			assert_true(roster.has(peer), "int peer keys")
		assert_eq(roster[2]["status"]["text"], "Diesel")
		assert_eq(int(roster[3]["slot_index"]), 2)
		assert_almost_eq(float(roster[2]["raw_w"]), float(host.ctx.roster[2]["raw_w"]), 1e-6)
	assert_eq(host.ctx.roster.size(), 4, "the host's own ctx.roster too")
