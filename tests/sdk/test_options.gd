extends GutTest
## Game options and player_options reach ctx on the host and on clients (BRIEF 3.6, 7.1;
## docs/OWNERSHIP.md CTX8, PS14, REG5).

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")

var _root: Node = null
var _tmp: Array[String] = []


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)


func after_each() -> void:
	for d in _tmp:
		Kit.remove_tree(d)
	_tmp.clear()


func test_options_and_player_options_on_host_and_clients() -> void:
	var slots: Array[PlayerSlot] = []
	for i in 3:
		slots.append(Kit.human(i + 1, i))
	slots[0].options = {"offset": -10}
	slots[1].options = {"reel_pct": 70, "relaxed": true}
	slots.append(Bots.make_slot(1, 3, 200.0))
	var b := Kit.multi(
		_root, 3, "tiny", {"players": slots, "options": {"speed": 5, "mode": "b"}}, 1
	)
	_tmp.append(str(b["tmp"]))
	assert_eq(b["err"], "")
	Kit.start(b)
	Kit.step(b, 1)
	var expected_opts := {"speed": 5, "mirror": false, "mode": "b"}
	var expected_players := [
		{"offset": -10, "reel_pct": 60, "relaxed": false},
		{"offset": 0, "reel_pct": 70, "relaxed": true},
		{"offset": 0, "reel_pct": 60, "relaxed": false},
		{"offset": 0, "reel_pct": 60, "relaxed": false},
	]
	var peers: Array[GameHost] = [b["host"]]
	for c: GameHost in b["clients"]:
		peers.append(c)
	for gh in peers:
		assert_eq(gh.ctx.options, expected_opts, "ctx.options on peer %d" % gh.local_peer())
		for i in 4:
			assert_eq(
				gh.ctx.players[i].options,
				expected_players[i],
				"slot %d options on peer %d" % [i, gh.local_peer()]
			)
			assert_typeof(gh.ctx.players[i].options["offset"], TYPE_INT)


func test_invalid_and_unknown_values_fall_back_with_warnings() -> void:
	var b := Kit.solo(_root, "tiny", {"options": {"speed": 99, "colour": "red"}})
	_tmp.append(str(b["tmp"]))
	assert_eq(b["err"], "")
	var host: GameHost = b["host"]
	assert_eq(host.ctx.options, {"speed": 2, "mirror": false, "mode": "a"})
	assert_push_warning("using the default")
	assert_push_warning("unknown option")
