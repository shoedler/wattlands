extends GutTest
## W3 WO-4 (BRIEF 3.7 "a 76-105% FTP target band on the power gauge"; 3.6: a band holds until
## replaced): a client restarted in Rolling road gets its band back from the host's rejoin
## resync. Real Workout game (rolling_road) on the sdk-runtime FakeNet session kit.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")
const FakeNetHub := preload("res://tests/sdk/helpers/fake_net_hub.gd")

var _root: Node = null
var _tmp: String = ""


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)


func after_each() -> void:
	if _tmp != "":
		Kit.remove_tree(_tmp)


func test_rolling_road_band_reaches_a_restarted_client() -> void:
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	_root.add_child(reg)
	reg.scan()
	assert_true(reg.has_game("workout"))
	_tmp = Paths.make_temp_dir("workout_rejoin_band")
	var hub: RefCounted = FakeNetHub.new()
	var nets: Array[WlNetSession] = []
	for i in 2:
		var s: WlNetSession = hub.call("add", i + 1)
		_root.add_child(s)
		nets.append(s)
	var players: Array[PlayerSlot] = [Kit.human(1, 0, 200.0), Kit.human(2, 1, 200.0)]
	var riders := {}
	for p in players:
		riders[p.peer_id] = Kit.rider(_root, p)
	var host := GameHost.new()
	_root.add_child(host)
	var err := (
		host
		. setup(
			{
				"game_id": "workout",
				"content_id": "rolling_road",
				"seed": 7,
				"role": Wl.HOST,
				"players": players,
				"local_riders": {1: riders[1]},
				"local_peer": 1,
				"net": nets[0],
				"bus": Kit.new_bus(_root, "HB"),
				"registry": reg,
				"headless": true,
				"realtime": false,
				"progress_path": _tmp.path_join("p1/progress.json"),
			}
		)
	)
	assert_eq(err, "")
	var client := GameHost.new()
	_root.add_child(client)
	assert_eq(
		(
			client
			. setup(
				{
					"role": Wl.CLIENT,
					"local_peer": 2,
					"local_riders": {2: riders[2]},
					"net": nets[1],
					"bus": Kit.new_bus(_root, "CB"),
					"registry": reg,
					"headless": true,
					"realtime": false,
					"progress_path": _tmp.path_join("p2/progress.json"),
				}
			)
		),
		""
	)
	var b := {"host": host, "clients": [client]}
	Kit.start(b)
	var steps := Kit.step_until(b, func() -> bool: return host.tracker.index_of(2) == 1, 7000)
	assert_lt(steps, 7001, "peer 2 reached the Rolling road phase")
	Kit.step(b, 20)
	var before: Array = riders[2].get("band_power")
	assert_almost_eq(float(before[0]), 152.0, 0.5, "76% of 200 W")
	assert_almost_eq(float(before[1]), 210.0, 0.5, "105% of 200 W")
	# Peer 2's app restarts mid-phase: a fresh process has a fresh LocalRider and GameHost.
	hub.call("drop", 2)
	Kit.step(b, 2)
	client.end_session("restart")
	var fresh := Kit.rider(_root, players[1])
	var c2 := GameHost.new()
	_root.add_child(c2)
	assert_eq(
		(
			c2
			. setup(
				{
					"role": Wl.CLIENT,
					"local_peer": 2,
					"local_riders": {2: fresh},
					"net": nets[1],
					"bus": Kit.new_bus(_root, "CB2"),
					"registry": reg,
					"headless": true,
					"realtime": false,
					"progress_path": _tmp.path_join("p2r/progress.json"),
				}
			)
		),
		""
	)
	hub.call("rejoin", 2)
	b["clients"] = [c2]
	Kit.step(b, 200)
	assert_eq(c2.local_phase_state().index, 1, "the restarted client is back in Rolling road")
	var after: Array = fresh.get("band_power")
	assert_almost_eq(
		float(after[0]), 152.0, 0.5, "the restarted client's gauge shows the 76-105% band again"
	)
	assert_almost_eq(float(after[1]), 210.0, 0.5)
	assert_eq(c2.hud_router.band_of(2), [152.0, 210.0], "and its HUD")
