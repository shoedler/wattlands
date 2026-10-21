extends GutTest
## Every PlayerSlot field reaches ctx.players on the host and on every client (BRIEF 3.6,
## 7.1 "every PlayerSlot field"; docs/OWNERSHIP.md PS1-PS14, CTX1).

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


func _custom_slots() -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for i in 3:
		var s := Kit.human(i + 1, i, 150.0 + 50.0 * i)
		s.name = ["Ann", "Bo", "Cy"][i]
		s.ftp_verified = i != 1
		s.scaling_mode = Wl.WKG
		s.p_eff_per_w = 75.0 / (60.0 + 10.0 * i)
		s.rider_mass_kg = 75.0
		s.preferred_cadence_rpm = 80.0 + 5.0 * i
		s.haptics_on = i != 2
		s.haptic_intensity = 0.3 + 0.2 * i
		s.autopilot = i == 0
		s.options = {"offset": -3 * i}
		out.append(s)
	for n in range(1, 3):
		var b := Bots.make_slot(n, 2 + n, 210.0, Wl.WKG)
		out.append(b)
	return out


func test_every_field_on_host_and_clients() -> void:
	var slots := _custom_slots()
	var b := Kit.multi(_root, 3, "tiny", {"players": slots}, 2)
	_tmp.append(str(b["tmp"]))
	assert_eq(b["err"], "")
	Kit.start(b)
	Kit.step(b, 2)
	var host: GameHost = b["host"]
	var reference: Array = []
	for p in host.ctx.players:
		reference.append(JSON.stringify(p.to_dict()))
	assert_eq(host.ctx.players.size(), 5)
	for c: GameHost in b["clients"]:
		assert_eq(c.ctx.players.size(), 5)
		for i in 5:
			var s := c.ctx.players[i]
			assert_eq(JSON.stringify(s.to_dict()), reference[i], "slot %d on peer %d" % [i, c.local_peer()])
			assert_typeof(s.peer_id, TYPE_INT)
			assert_typeof(s.slot_index, TYPE_INT)
			assert_eq(s.slot_index, i, "contiguous slot order")
		var ann := c.ctx.players[0]
		assert_eq(ann.peer_id, 1)
		assert_eq(ann.name, "Ann")
		assert_eq(ann.color, Wl.SLOT_COLORS[0])
		assert_eq(ann.shape, "circle")
		assert_eq(ann.pattern, "solid")
		assert_false(ann.hollow)
		assert_eq(ann.ftp, 150.0)
		assert_true(ann.ftp_verified)
		assert_eq(ann.scaling_mode, Wl.WKG)
		assert_almost_eq(ann.p_eff_per_w, 75.0 / 60.0, 1e-9)
		assert_eq(ann.rider_mass_kg, 75.0)
		assert_eq(ann.preferred_cadence_rpm, 80.0)
		assert_true(ann.haptics_on)
		assert_almost_eq(ann.haptic_intensity, 0.3, 1e-9)
		assert_true(ann.autopilot)
		assert_false(ann.is_bot)
		assert_eq(ann.options, {"offset": 0, "reel_pct": 60, "relaxed": false})
		var bo := c.ctx.players[1]
		assert_false(bo.ftp_verified)
		assert_eq(bo.shape, "triangle")
		assert_eq(bo.pattern, "dashed")
		assert_eq(bo.options["offset"], -3)
		var cy := c.ctx.players[2]
		assert_false(cy.haptics_on)
		var bot2 := c.ctx.players[4]
		assert_eq(bot2.peer_id, -2)
		assert_eq(bot2.name, "Bot 2")
		assert_true(bot2.is_bot)
		assert_true(bot2.hollow, "slots 4-7 are hollow")
		assert_eq(bot2.shape, "circle")
		assert_true(bot2.ftp_verified)
		assert_true(bot2.autopilot)
