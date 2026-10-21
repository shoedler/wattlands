extends GutTest
## Protocol (BRIEF 5.5, OWNERSHIP PR1-PR3, NET8, GM13): exact round trips through
## JSON.stringify/JSON.parse_string for every message type, int conversion (top-level keys,
## "_id" keys at any depth, schema paths with [] and {}, peer-keyed dictionaries), schema
## and version rejection.

const U := preload("res://tests/net/net_test_util.gd")


# --- fixtures: one per message type, ints only where decode() makes ints -----------------

static func game_fixtures() -> Dictionary:
	var tm := Telemetry.new()
	tm.peer_id = 3
	tm.t = 12.5
	tm.power_w = 187.5
	tm.cadence_rpm = 91.25
	tm.speed_kmh = 31.5
	tm.effort = 0.9375
	tm.p_eff_w = 234.375
	tm.wbal_j = 18000.5
	tm.ftp_pct = 93.75
	tm.mode = Wl.ERG
	tm.applied_target_w = 188
	tm.applied_grade_pct = 0.0
	tm.gear = 14
	tm.clamped_by.assign([Wl.CLAMP_SLEW])
	tm.s_left_105 = 300.0
	tm.s_left_120 = 60.0
	tm.gestures.assign([Wl.G_SURGE])
	tm.intents = [{"k": "buy", "item": "ram", "auto": 1.0, "to": 2.0, "target_id": 7.0}]
	tm.distance_m = 1250.5
	tm.phase_index = 2
	tm.acks = [{"id": 12, "kind": "request", "applied": {"target_w": 210.0}, "clamped_by": ["slew"],
		"refused": "", "reason": ""}]
	tm.age_s = 0.25
	var slot := Bots.make_slot(1, 2, 200.0)
	slot.options = {"wave_offset": 0.0}
	var plan := EffortPlan.of([
		PlanPhase.erg(Wl.WARMUP, 50.0, 300.0, "Warm-up").with_ramp(65.0).with_lap(),
		PlanPhase.erg(Wl.WORK, 90.0, 240.0, "Wave 1").with_range(85.0, 100.0).with_lap(),
		PlanPhase.sim(Wl.FREE, Wl.GRADE_COURSE, 120.0, "Hill").with_course([[0.0, 1.5], [500.0, 4.5]]),
		PlanPhase.erg(Wl.WORK, 104.0, 0.0, "Reel 1").with_open(120.0, 540.0).with_meta({"fish": "marlin"}),
	])
	plan.add(PlanPhase.erg(Wl.COOLDOWN, 50.0, 180.0, "Cool-down").with_lap())
	plan.cooldown_appended = true
	var results := GameResults.new()
	results.grade = "A"
	results.score = 1234.5
	results.summary_key = "SIEGE_SUMMARY"
	results.rows = [{"peer_id": 1, "slot_index": 0, "name": "Ann", "is_bot": false, "kj": 300.5,
		"xp": 120, "unlocks": ["helmet"], "stats": {"kills": 4.0}}]
	results.team = {"gate_hp": 75.5}
	results.session_id = "abc"
	return {
		"player_info": {"name": "Ann", "color": "0072b2", "ftp": 250.0, "ftp_verified": true,
			"p_eff_per_w": 1.0, "preferred_cadence_rpm": 92.5, "haptics_on": false,
			"autopilot": true, "player_options": {"wave_offset": -5.0, "reel_pct": 60.0},
			"games": {"workout": "1", "siege": "1.2.0"}, "weight_kg": 72.5, "trainer": "mock"},
		"ready": {"ready": true},
		"telemetry": {"tm": tm.to_dict()},
		"clock_ping": {"t0": 12.25},
		"lobby_state": {"seq": 4, "host": 1, "started": false, "game_id": "siege",
			"game_version": "1.2.0", "content_id": "shift_1", "scaling": Wl.FAIR_FTP,
			"settings": {"options": {"rotation": true}, "bot_ftp": 180, "max_players": 4,
				"min_players": 1, "bots_allowed": true, "difficulty": 0.5},
			"players": [
				{"peer_id": 1, "name": "Ann", "slot_index": 0, "color": "d55e00", "ftp": 250,
					"ftp_verified": true, "p_eff_per_w": 1.0, "is_bot": false, "ready": true,
					"connected": true, "game_ok": true, "game_issue": "", "trainer": "mock"},
				{"peer_id": -1, "name": "Bot 1", "slot_index": 1, "color": "0072b2", "ftp": 180,
					"ftp_verified": true, "p_eff_per_w": 1.25, "is_bot": true, "ready": true,
					"connected": true, "game_ok": true, "game_issue": "", "trainer": "bot"},
			],
			"player_options": {1: {"wave_offset": -5.0}, -1: {"wave_offset": 0.0}},
			"ready_flags": {1: true, -1: true},
			"trainers": {1: "mock", -1: "bot"}},
		"session_start": {"game_id": "siege", "game_version": "1.2.0", "content_id": "shift_1",
			"seed": 987654321, "players": [slot.to_dict()], "options": {"rotation": true},
			"scaling": Wl.FAIR_FTP, "start_tick": 1200},
		"snapshot": {"game_id": "siege", "seq": 77, "tick": 1540, "t": 77.0,
			"state": {"w": 812.5, "r": [[0.0, 1.0, 2.5]], "riders": {"0": 1.5}}},
		"event": {"seq": 9, "events": [{"type": "kill", "id": 4.0, "slot": 1.0},
			{"type": "phase_started", "peer_id": 2, "index": 1.0}]},
		"roster": {"riders": {
			1: {"raw_w": 200.0, "cadence_rpm": 90.0, "ftp_pct": 80.0, "rescue": false, "afk": false,
				"connected": true, "status": {"in_band": true, "text": "Diesel"}, "name": "Ann",
				"slot_index": 0},
			-1: {"raw_w": 180.0, "cadence_rpm": 90.0, "ftp_pct": 100.0, "rescue": false,
				"afk": false, "connected": true, "status": {}, "name": "Bot 1", "slot_index": 1}}},
		"results": {"results": results.to_dict()},
		"session_end": {"reason": "complete"},
		"refused": {"reason": "session_in_progress"},
		"plan": {"plan": plan.to_dict()},
		"phase": {"index": 3, "start_tick": 4800, "ended_by": Wl.ENDED_END_PHASE},
		"directive": {"kind": NetMessages.DIRECTIVE_REQUEST, "id": 12, "mode": Wl.SIM,
			"duration_s": 30.0, "reason": "overdrive", "source": "siege"},
		"hud": {"kind": "toast", "key": "SIEGE_TOAST_BUY_REFUSED", "args": ["ram", 2.5]},
		"clock_pong": {"t0": 12.25, "th": 100.5},
	}


static func relay_fixtures() -> Array:
	return [
		{"t": "hello", "proto": 1, "game": "wattlands", "build": "0.1.0"},
		{"t": "create", "max": 8},
		{"t": "created", "code": "K7QX2M", "peer": 1, "token": "abc"},
		{"t": "join", "code": "K7QX2M", "token": null},
		{"t": "joined", "peer": 3, "host": 1, "token": "def"},
		{"t": "error", "code": "room_full"},
		{"t": "peer_joined", "peer": 3},
		{"t": "peer_left", "peer": 3, "reason": "dropped"},
		{"t": "host_left"},
		{"t": "leave"},
		{"t": "ping", "ts": 123.5},
		{"t": "pong", "ts": 123.5},
		{"t": "msg", "to": 0, "d": Protocol.game_msg("ready", {"ready": false})},
		{"t": "msg", "from": 3, "d": Protocol.game_msg("phase", {"index": 1, "start_tick": 20,
			"ended_by": "duration"})},
	]


# --- round trips --------------------------------------------------------------------------

func test_fixtures_cover_every_message_type() -> void:
	var fx := game_fixtures()
	for type: String in NetMessages.GAME.keys():
		assert_true(fx.has(type), "fixture for game message %s" % type)
	var relay_types := {}
	for e: Dictionary in relay_fixtures():
		relay_types[e["t"]] = true
	for t: String in NetMessages.RELAY.keys():
		assert_true(relay_types.has(t), "fixture for relay message %s" % t)


func test_game_messages_round_trip_exactly_through_json() -> void:
	var fx := game_fixtures()
	for type: String in fx.keys():
		var msg := Protocol.game_msg(type, fx[type])
		var back := Protocol.decode_game(U.json_round_trip(msg))
		assert_true(U.same(msg, back), "%s: %s" % [type, U.diff(msg, back)])


func test_game_messages_round_trip_through_encode_and_decode() -> void:
	var fx := game_fixtures()
	for type: String in fx.keys():
		var msg := Protocol.game_msg(type, fx[type])
		var back := Protocol.decode(Protocol.encode(msg))
		assert_true(U.same(msg, back), "%s: %s" % [type, U.diff(msg, back)])


func test_relay_envelopes_round_trip_exactly() -> void:
	for env: Dictionary in relay_fixtures():
		var back := Protocol.decode(JSON.stringify(env))
		assert_true(U.same(env, back), "%s: %s" % [env["t"], U.diff(env, back)])
		var back2 := Protocol.decode(Protocol.encode(env))
		assert_true(U.same(env, back2), "%s (encode): %s" % [env["t"], U.diff(env, back2)])


func test_typed_objects_survive_the_round_trip() -> void:
	var fx := game_fixtures()
	var tm_back := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("telemetry", fx["telemetry"])))
	var tm := Telemetry.from_dict(tm_back["tm"])
	assert_eq(tm.peer_id, 3)
	assert_eq(tm.applied_target_w, 188)
	assert_eq(tm.gestures.size(), 1)
	assert_eq(tm.gestures[0], Wl.G_SURGE)
	var plan_back := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("plan", fx["plan"])))
	var plan := EffortPlan.from_dict(plan_back["plan"])
	assert_eq(plan.size(), 5)
	assert_true(plan.cooldown_appended)
	assert_eq(plan.phase(3).max_s, 540.0)
	assert_true(U.same(plan.phase(3).meta, {"fish": "marlin"}))
	var ss := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("session_start", fx["session_start"])))
	var slot := PlayerSlot.from_dict((ss["players"] as Array)[0])
	assert_eq(slot.peer_id, -1)
	assert_eq(slot.slot_index, 2)
	assert_true(slot.is_bot)
	var res := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("results", fx["results"])))
	var gr := GameResults.from_dict(res["results"])
	assert_eq(gr.row(1)["xp"], 120)


func test_json_parse_returns_floats_and_decode_restores_ints() -> void:
	var msg := Protocol.game_msg("phase", {"index": 3, "start_tick": 4800, "ended_by": "duration"})
	var raw := U.json_round_trip(msg)
	assert_typeof(raw["index"], TYPE_FLOAT, "Godot's JSON parser returns floats")
	var back := Protocol.decode_game(raw)
	assert_typeof(back["index"], TYPE_INT)
	assert_typeof(back["start_tick"], TYPE_INT)
	assert_typeof(back["v"], TYPE_INT)
	assert_typeof(raw["index"], TYPE_FLOAT, "decode_game leaves its argument alone")


# --- int conversion ---------------------------------------------------------------------

func test_top_level_keys_become_ints() -> void:
	var env := Protocol.decode("{\"t\":\"joined\",\"peer\":3.0,\"host\":1,\"token\":\"x\"}")
	assert_typeof(env["peer"], TYPE_INT)
	assert_typeof(env["host"], TYPE_INT)
	var create := Protocol.decode("{\"t\":\"create\",\"max\":8}")
	assert_typeof(create["max"], TYPE_INT)
	var hello := Protocol.decode("{\"t\":\"hello\",\"proto\":1,\"game\":\"wattlands\",\"build\":\"0.1.0\"}")
	assert_typeof(hello["proto"], TYPE_INT)
	var m := Protocol.decode("{\"t\":\"msg\",\"from\":2,\"to\":1,\"d\":{\"type\":\"event\",\"v\":1,\"seq\":4,\"events\":[]}}")
	assert_typeof(m["from"], TYPE_INT)
	assert_typeof(m["to"], TYPE_INT)
	assert_typeof((m["d"] as Dictionary)["seq"], TYPE_INT)


func test_id_keys_at_any_depth_become_ints() -> void:
	var msg := Protocol.game_msg("snapshot", {"game_id": "siege", "seq": 1, "state": {
		"a": {"b": [{"target_id": 3.0, "x": 1.5}, [{"deep_id": -2.0}]]},
		"half_id": 2.5,
		"name_id": "text"}})
	var back := Protocol.decode_game(U.json_round_trip(msg))
	var st: Dictionary = back["state"]
	var b: Array = (st["a"] as Dictionary)["b"]
	assert_typeof((b[0] as Dictionary)["target_id"], TYPE_INT)
	assert_eq((b[0] as Dictionary)["target_id"], 3)
	assert_typeof((b[0] as Dictionary)["x"], TYPE_FLOAT)
	assert_eq(((b[1] as Array)[0] as Dictionary)["deep_id"], -2)
	assert_typeof(st["half_id"], TYPE_FLOAT, "a fractional value is not an id: left alone")
	assert_eq(st["name_id"], "text", "strings stay strings")
	assert_eq(back["game_id"], "siege", "game_id holds a string and stays one")


func test_telemetry_intents_are_never_converted() -> void:
	var msg := Protocol.game_msg("telemetry", {"tm": {"peer": 2, "intents": [
		{"k": "buy", "to": 2.0, "item_id": 7.0, "pad": 1.0}], "acks": [{"id": 5}]}})
	var back := Protocol.decode_game(U.json_round_trip(msg))
	var it: Dictionary = ((back["tm"] as Dictionary)["intents"] as Array)[0]
	assert_typeof(it["to"], TYPE_FLOAT)
	assert_typeof(it["item_id"], TYPE_FLOAT, "games cast intent values themselves (PR4)")
	assert_typeof(it["pad"], TYPE_FLOAT)
	assert_typeof((back["tm"] as Dictionary)["peer"], TYPE_INT)
	assert_typeof((((back["tm"] as Dictionary)["acks"] as Array)[0] as Dictionary)["id"], TYPE_INT)


func test_peer_keyed_dictionaries_get_int_keys() -> void:
	var fx := game_fixtures()
	var roster := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("roster", fx["roster"])))
	var riders: Dictionary = roster["riders"]
	var keys := riders.keys()
	keys.sort()
	assert_true(U.same(keys, [-1, 1]), str(keys))
	assert_typeof((riders[1] as Dictionary)["slot_index"], TYPE_INT)
	var lobby := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("lobby_state", fx["lobby_state"])))
	for field in ["player_options", "ready_flags", "trainers"]:
		for k: Variant in (lobby[field] as Dictionary).keys():
			assert_typeof(k, TYPE_INT, "%s key %s" % [field, str(k)])


func test_player_info_option_ids_stay_strings() -> void:
	var fx := game_fixtures()
	var pi := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("player_info", fx["player_info"])))
	assert_true((pi["player_options"] as Dictionary).has("wave_offset"))
	assert_true((pi["games"] as Dictionary).has("workout"))


func test_game_payloads_keep_their_own_keys() -> void:
	var msg := Protocol.game_msg("snapshot", {"game_id": "x", "seq": 1,
		"state": {"riders": {"0": 1.5, "1": 2.5}}})
	var back := Protocol.decode_game(U.json_round_trip(msg))
	var riders: Dictionary = (back["state"] as Dictionary)["riders"]
	assert_true(riders.has("0"), "keys inside a game's snapshot state stay as the game wrote them")


func test_schema_int_paths_with_wildcards() -> void:
	var fx := game_fixtures()
	var ls := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("lobby_state", fx["lobby_state"])))
	for p: Dictionary in ls["players"]:
		assert_typeof(p["slot_index"], TYPE_INT)
		assert_typeof(p["ftp"], TYPE_INT)
		assert_typeof(p["peer_id"], TYPE_INT)
		assert_typeof(p["p_eff_per_w"], TYPE_FLOAT)
	var settings: Dictionary = ls["settings"]
	assert_typeof(settings["bot_ftp"], TYPE_INT)
	assert_typeof(settings["max_players"], TYPE_INT)
	assert_typeof(settings["difficulty"], TYPE_FLOAT)
	var res := Protocol.decode_game(U.json_round_trip(Protocol.game_msg("results", fx["results"])))
	var row: Dictionary = ((res["results"] as Dictionary)["rows"] as Array)[0]
	assert_typeof(row["xp"], TYPE_INT)
	assert_typeof(row["kj"], TYPE_FLOAT)


func test_apply_int_fields_siege_fixture() -> void:
	# Siege S2.6: r: [[slot, target, ...]], f: [[pad, [target_ids]]] declares f[][] and f[][][].
	var parsed: Variant = JSON.parse_string(JSON.stringify({
		"tick": 140, "w": 812.5,
		"r": [[0, 120, 2000, 0, 0, 35, 250, 200, 90, 0, 1], [1, 95, 0, 0, 0, 12, 180, 150, 85, 1, 0]],
		"f": [[3, [10, 11]], [4, []]],
		"e": {"a": {"hp": 50, "x": 1.5}, "b": {"hp": 70, "x": 2.5}},
	}))
	var state: Dictionary = Protocol.apply_int_fields(parsed, ["tick", "r[][]", "f[][]", "f[][][]", "e{}.hp"])
	assert_typeof(state["tick"], TYPE_INT)
	assert_typeof(state["w"], TYPE_FLOAT, "undeclared fields stay floats")
	for row: Array in state["r"]:
		for v: Variant in row:
			assert_typeof(v, TYPE_INT)
	var f0: Array = (state["f"] as Array)[0]
	assert_typeof(f0[0], TYPE_INT, "f[][] converts the pad")
	assert_typeof(f0[1], TYPE_ARRAY, "an Array at a matched path is left unchanged")
	assert_true(U.same(f0[1], [10, 11]), "f[][][] converts the target ids")
	assert_true(U.same((state["f"] as Array)[1], [4, []]))
	var e: Dictionary = state["e"]
	assert_typeof((e["a"] as Dictionary)["hp"], TYPE_INT, "{} walks every dictionary value")
	assert_typeof((e["b"] as Dictionary)["x"], TYPE_FLOAT)


func test_apply_int_fields_edge_cases() -> void:
	var d: Dictionary = {"a": [1.6, "s", true, null, {"x": 2.0}], "b": {"c": 3.0}}
	Protocol.apply_int_fields(d, ["a[]", "b.c", "missing.path", "b.c.d", "a[].x", ""])
	assert_true(U.same(d["a"], [2, "s", true, null, {"x": 2}]), U.diff(d["a"], [2, "s", true, null, {"x": 2}]))
	assert_true(U.same(d["b"], {"c": 3}))
	assert_eq(Protocol.apply_int_fields(4.0, ["x"]), 4.0, "a scalar root without a matching path is unchanged")
	assert_true(U.same(Protocol.apply_int_fields([1.0, 2.0], ["[]"]), [1, 2]))


func test_apply_game_int_fields_on_snapshots_and_events() -> void:
	var fields := {"snapshot": ["r[][]"], "kill": ["id", "slot"]}
	var snap := Protocol.decode(Protocol.encode(Protocol.game_msg("snapshot", {"game_id": "g", "seq": 1,
		"state": {"r": [[1.0, 2.0]]}})))
	Protocol.apply_game_int_fields(snap, fields)
	assert_true(U.same((snap["state"] as Dictionary)["r"], [[1, 2]]))
	var ev := Protocol.decode(Protocol.encode(Protocol.game_msg("event", {"seq": 1, "events": [
		{"type": "kill", "id": 4.0, "slot": 1.0, "x": 0.5}, {"type": "other", "id": 4.0}]})))
	Protocol.apply_game_int_fields(ev, fields)
	var events: Array = ev["events"]
	assert_typeof((events[0] as Dictionary)["id"], TYPE_INT)
	assert_typeof((events[0] as Dictionary)["x"], TYPE_FLOAT)
	assert_typeof((events[1] as Dictionary)["id"], TYPE_FLOAT, "only the event's own type's paths apply")


# --- rejection ---------------------------------------------------------------------------

func test_rejects_unknown_types_and_bad_json() -> void:
	assert_true(Protocol.decode("{nope").is_empty())
	assert_eq(Protocol.last_error, "bad_json")
	assert_true(Protocol.decode("[1,2]").is_empty())
	assert_eq(Protocol.last_error, "not_object")
	assert_true(Protocol.decode("{\"x\":1}").is_empty())
	assert_eq(Protocol.last_error, "unknown_type")
	assert_true(Protocol.decode("{\"t\":\"teleport\"}").is_empty())
	assert_eq(Protocol.last_error, "unknown_type")
	assert_true(Protocol.decode_game({"type": "teleport", "v": 1}).is_empty())
	assert_eq(Protocol.last_error, "unknown_type")


func test_rejects_missing_and_mistyped_fields() -> void:
	assert_true(Protocol.decode_game({"type": "phase", "v": 1, "index": 1, "start_tick": 0}).is_empty())
	assert_eq(Protocol.last_error, "missing_field:ended_by")
	assert_true(Protocol.decode_game({"type": "lobby_state", "v": 1, "players": {}, "game_id": "",
		"game_version": "", "content_id": "", "scaling": "FAIR_FTP", "settings": {}}).is_empty())
	assert_eq(Protocol.last_error, "bad_type:players")
	assert_true(Protocol.decode_game({"type": "snapshot", "v": 1, "game_id": "g", "seq": "7", "state": {}}).is_empty())
	assert_eq(Protocol.last_error, "bad_type:seq")
	assert_true(Protocol.decode_game({"type": "directive", "v": 1, "kind": "teleport"}).is_empty())
	assert_eq(Protocol.last_error, "bad_kind")
	for kind in NetMessages.DIRECTIVE_KINDS:
		assert_false(Protocol.decode_game({"type": "directive", "v": 1, "kind": kind}).is_empty(), kind)
	assert_true(Protocol.decode("{\"t\":\"joined\",\"peer\":3,\"token\":\"x\"}").is_empty())
	assert_eq(Protocol.last_error, "missing_field:host")
	assert_true(Protocol.decode("{\"t\":\"msg\",\"to\":1,\"d\":[]}").is_empty())
	assert_eq(Protocol.last_error, "bad_type:d")


func test_every_required_field_is_checked() -> void:
	var fx := game_fixtures()
	for type: String in NetMessages.GAME.keys():
		for f: String in NetMessages.GAME[type]["req"]:
			var msg := Protocol.game_msg(type, fx[type])
			msg.erase(f)
			assert_true(Protocol.decode_game(msg).is_empty(), "%s without %s" % [type, f])
			assert_eq(Protocol.last_error, "missing_field:%s" % f)


func test_rejects_other_schema_versions() -> void:
	var msg := Protocol.game_msg("ready", {"ready": true})
	msg["v"] = NetMessages.VERSION + 1
	assert_true(Protocol.decode_game(msg).is_empty())
	assert_eq(Protocol.last_error, "version_mismatch")
	msg.erase("v")
	assert_true(Protocol.decode_game(msg).is_empty())
	assert_eq(Protocol.last_error, "version_mismatch")
	var env := {"t": "msg", "from": 1, "d": {"type": "ready", "v": 99, "ready": true}}
	assert_true(Protocol.decode(JSON.stringify(env)).is_empty(), "an envelope with a bad game message is rejected")
	assert_eq(Protocol.last_error, "version_mismatch")


func test_refused_is_readable_on_any_version() -> void:
	var back := Protocol.decode_game({"type": "refused", "v": 99.0, "reason": "version_mismatch"})
	assert_eq(back.get("reason"), "version_mismatch")
	assert_eq(Protocol.last_error, "")


func test_encode_keeps_order_and_precision() -> void:
	var text := Protocol.encode({"type": "x", "b": 1, "a": 0.30000000000000004})
	assert_true(text.begins_with("{\"type\":\"x\",\"b\":1,"), text)
	assert_true(text.contains("0.30000000000000004"), text)
	assert_eq(Protocol.encoded_size({"t": "leave"}), 13)
	assert_eq(Protocol.encoded_size({"s": "é"}), 10, "UTF-8 bytes, not characters")


func test_game_msg_sets_type_and_version() -> void:
	var payload := {"ready": true}
	var m := Protocol.game_msg("ready", payload)
	assert_eq(m["type"], "ready")
	assert_eq(m["v"], NetMessages.VERSION)
	assert_false(payload.has("type"), "payload is copied")
	assert_true(U.same(Protocol.schema_int_paths("phase"), ["index", "start_tick"]))
	assert_true(Protocol.schema_int_paths("nope").is_empty())
