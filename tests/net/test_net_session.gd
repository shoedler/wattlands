extends "res://tests/net/net_session_test_base.gd"
## WlNetSession lobby over LoopbackTransport (BRIEF 3.6, 5.4, 5.5; OWNERSHIP NET7, NET8,
## PS10, CTX1): a host with two client NetSessions, join with slot looks, player_info
## fields, ready-up, version and missing-game refusals, bots and bot FTP, options and
## player_options in lobby_state, the offline SOLO lobby and per-session buses; NET2 (nothing
## over 16 384 bytes), NET5 (a 4-rider session under the relay's rate limit) and NET7
## (session_in_progress).


func test_host_and_two_clients_join_with_slot_looks() -> void:
	var r := room()
	var h := r[0]
	assert_eq(h.state, "hosting")
	assert_eq(h.role, Wl.HOST)
	assert_true(RoomCode.is_valid(h.room_code))
	for c in [r[1], r[2]]:
		assert_eq(c.state, "joined")
		assert_eq(c.role, Wl.CLIENT)
		assert_eq(c.room_code, h.room_code)
		assert_true(U.same(c.lobby, h.lobby), U.diff(c.lobby, h.lobby))
	assert_eq(r[1].local_peer, 2)
	assert_eq(r[2].local_peer, 3)
	var names := ["Hana", "Rider 1", "Rider 2"]
	for s: WlNetSession in r:
		var slots := s.lobby_slots()
		assert_eq(slots.size(), 3)
		for i in 3:
			var look := Wl.slot_look(i)
			assert_eq(slots[i].peer_id, i + 1, "join order")
			assert_eq(slots[i].slot_index, i)
			assert_eq(slots[i].name, names[i])
			assert_eq(slots[i].color, look["color"])
			assert_eq(slots[i].shape, look["shape"])
			assert_eq(slots[i].pattern, look["pattern"])
			assert_false(slots[i].is_bot)
	assert_eq(h.lobby_slots()[0].ftp, 250.0)
	assert_eq(r[2].lobby_slots()[2].ftp, 220.0)
	assert_eq(h.peers(), [1, 2, 3] as Array[int])
	assert_eq(r[1].peers(), [1, 2, 3] as Array[int])
	assert_eq(r[1].remote_peers(), [1, 3] as Array[int])
	assert_eq(events("host", "peer_joined").size(), 2)
	assert_eq(events("host", "bus_peer_joined").size(), 2, "the host's own bus")
	assert_eq(events("c2", "bus_peer_joined").size(), 0, "no cross-talk between buses")


func test_player_info_fields_reach_player_slots() -> void:
	var h := make_session("host", rider("Hana", "1", 250))
	h.host_room(8)
	pump()
	var c := make_session(
		"c1",
		rider(
			"Bo",
			"1",
			300,
			{
				"ftp_verified": true,
				"preferred_cadence_rpm": 95.0,
				"haptics_on": false,
				"haptic_intensity": 0.4,
				"autopilot": true,
				"weight_kg": 80.0,
				"trainer": "mock",
				"color": Color("#0072B2")
			}
		)
	)
	c.join_room(h.room_code)
	pump()
	var s := c.lobby_slots()[1]
	assert_eq(s.peer_id, 2)
	assert_eq(s.ftp, 300.0)
	assert_true(s.ftp_verified)
	assert_eq(s.preferred_cadence_rpm, 95.0)
	assert_false(s.haptics_on)
	assert_almost_eq(s.haptic_intensity, 0.4, 1e-9)
	assert_true(s.autopilot)
	assert_eq(s.scaling_mode, Wl.FAIR_FTP)
	assert_almost_eq(s.p_eff_per_w, 250.0 / 300.0, 1e-9)
	assert_eq(s.rider_mass_kg, 75.0, "75 kg unless RAW with the weight shared")
	assert_eq(player(h, 2)["trainer"], "mock")
	assert_eq(player(h, 2)["profile_color"], "0072b2")
	assert_eq(h.lobby["trainers"][2], "mock")
	h.set_scaling(Wl.RAW)
	pump()
	s = c.lobby_slots()[1]
	assert_eq(s.scaling_mode, Wl.RAW)
	assert_eq(s.p_eff_per_w, 1.0)
	assert_eq(s.rider_mass_kg, 80.0, "RAW with the weight shared")
	h.set_scaling(Wl.WKG)
	pump()
	assert_almost_eq(c.lobby_slots()[1].p_eff_per_w, 75.0 / 80.0, 1e-9)
	h.set_scaling("FAST")
	assert_push_error("unknown scaling mode")


func test_local_profile_follows_the_lobby_scaling() -> void:
	var h := make_session("host", rider("Hana", "1", 250))
	h.host_room(8)
	pump()
	var c := make_session("c1")
	var p := RiderProfile.new()
	p.display_name = "Cy"
	p.ftp_w = 250.0
	p.weight_kg = 80.0
	p.share_weight = false
	p.preferred_cadence_rpm = 88.0
	c.set_local_profile(p, {"workout": "1"}, {"wave_offset": 2})
	c.join_room(h.room_code)
	pump()
	assert_eq(player(h, 2)["name"], "Cy")
	assert_almost_eq(float(player(h, 2)["p_eff_per_w"]), 1.0, 1e-9)
	assert_eq(float(player(h, 2)["rider_mass_kg"]), 75.0)
	h.set_scaling(Wl.WKG)
	pump()
	assert_almost_eq(
		float(player(h, 2)["p_eff_per_w"]),
		75.0 / 80.0,
		1e-9,
		"the client recomputed P_eff for WKG and re-sent player_info"
	)
	assert_false(h.lobby_slots()[1].options.is_empty())
	var info := WlNetSession.player_info_from_profile(p, Wl.FAIR_FTP)
	assert_false(info.has("weight_kg"), "weight only if shared")
	assert_false((info["p_eff_by_mode"] as Dictionary).has(Wl.WKG))
	info = WlNetSession.player_info_from_profile(p, Wl.RAW)
	assert_false(info.has("weight_kg"), "RAW without the opt-in: no weight either")


## BRIEF 3.2: a shared weight goes into player_info only when the lobby's scaling needs it
## (RAW, the speed model's mass); 75 / weight (p_eff_by_mode's WKG entry) only in WKG.
func test_player_info_carries_the_weight_only_in_raw() -> void:
	var p := RiderProfile.new()
	p.ftp_w = 250.0
	p.weight_kg = 80.0
	p.share_weight = true
	var fair := WlNetSession.player_info_from_profile(p, Wl.FAIR_FTP)
	assert_false(fair.has("weight_kg"), "FAIR_FTP never uses the weight")
	assert_eq(fair["p_eff_by_mode"], {Wl.FAIR_FTP: 1.0, Wl.RAW: 1.0}, "no 75 / weight entry")
	var wkg := WlNetSession.player_info_from_profile(p, Wl.WKG)
	assert_false(wkg.has("weight_kg"), "WKG sends 75 / weight, never the weight")
	assert_almost_eq(float(wkg["p_eff_per_w"]), 75.0 / 80.0, 1e-9)
	assert_almost_eq(float((wkg["p_eff_by_mode"] as Dictionary)[Wl.WKG]), 75.0 / 80.0, 1e-9)
	var raw := WlNetSession.player_info_from_profile(p, Wl.RAW)
	assert_eq(raw["weight_kg"], 80.0, "RAW: the shared weight, for the speed model")
	assert_false((raw["p_eff_by_mode"] as Dictionary).has(Wl.WKG))
	# Info built elsewhere (the app's lobby) goes out the same way.
	var app := rider("Bo", "1", 300, {"weight_kg": 68.0, "p_eff_by_mode": {Wl.WKG: 75.0 / 68.0}})
	for mode: String in [Wl.FAIR_FTP, Wl.WKG]:
		assert_false(WlNetSession.wire_player_info(app, mode).has("weight_kg"), mode)
	assert_eq(WlNetSession.wire_player_info(app, Wl.RAW)["weight_kg"], 68.0)
	assert_eq(WlNetSession.wire_player_info(app, Wl.FAIR_FTP)["p_eff_by_mode"], {})
	assert_eq(WlNetSession.wire_player_info(app, Wl.RAW)["p_eff_by_mode"], {})
	assert_almost_eq(
		float((WlNetSession.wire_player_info(app, Wl.WKG)["p_eff_by_mode"] as Dictionary)[Wl.WKG]),
		75.0 / 68.0,
		1e-9
	)
	assert_eq(app["weight_kg"], 68.0, "the local copy keeps the weight")
	assert_true((app["p_eff_by_mode"] as Dictionary).has(Wl.WKG))


func test_ready_up_and_all_ready() -> void:
	var r := room()
	for s: WlNetSession in r:
		assert_false(s.all_ready())
	r[1].set_ready(true)
	r[2].set_ready(true)
	pump()
	assert_false(r[0].all_ready(), "the host has not readied")
	r[0].set_ready(true)
	pump()
	for s: WlNetSession in r:
		assert_true(s.all_ready(), s.name)
	assert_true(bool(r[0].lobby["ready_flags"][2]))
	r[2].set_ready(false)
	pump()
	assert_false(r[0].all_ready())
	assert_false(r[1].all_ready())


func test_other_version_cannot_ready_up() -> void:
	var r := room(["1", "2"])
	var h := r[0]
	var c2 := r[2]
	assert_eq(player(h, 3)["game_issue"], "version_mismatch")
	assert_false(bool(player(h, 3)["game_ok"]))
	assert_eq(c2.ready_block_reason(), "version_mismatch")
	c2.set_ready(true)
	var rr := events("c2", "ready_refused")
	assert_eq(rr.size(), 1, "refused locally, nothing sent")
	assert_eq(rr[0][1], "version_mismatch")
	assert_string_contains(str(rr[0][2]), "2")
	assert_string_contains(str(rr[0][2]), "workout")
	# A client that sends ready anyway is refused by the host.
	c2.send_to_host(Protocol.game_msg("ready", {"ready": true}))
	pump()
	rr = events("c2", "ready_refused")
	assert_eq(rr.size(), 2)
	assert_eq(rr[1][1], "version_mismatch")
	assert_false(bool(player(h, 3)["ready"]))
	assert_eq(c2.state, "joined", "a ready refusal does not end the session")
	assert_eq(events("c2", "refused").size(), 0)
	r[0].set_ready(true)
	r[1].set_ready(true)
	pump()
	assert_false(h.all_ready(), "the mismatched client blocks the start")
	c2.leave()
	pump()
	assert_true(h.all_ready(), "without it everyone is ready")


func test_missing_game_cannot_ready_up() -> void:
	var h := make_session("host", rider("Hana"))
	h.set_game("workout", "1", "easy30")
	h.host_room()
	pump()
	var c := make_session("c1", rider("Nogame", "1", 200, {"games": {"siege": "1"}}))
	c.join_room(h.room_code)
	pump()
	assert_eq(player(h, 2)["game_issue"], "missing_game")
	c.set_ready(true)
	var rr := events("c1", "ready_refused")
	assert_eq(rr[0][1], "missing_game")
	assert_string_contains(str(rr[0][2]), "workout")


func test_changing_the_game_resets_ready() -> void:
	var r := room()
	for s: WlNetSession in r:
		s.set_ready(true)
	pump()
	assert_true(r[0].all_ready())
	r[0].set_game("siege", "1", "shift_1")
	pump()
	assert_false(bool(player(r[0], 2)["ready"]))
	assert_eq(player(r[0], 2)["game_issue"], "missing_game")
	assert_true(bool(player(r[0], 1)["ready"]), "the host keeps its own flag")
	assert_eq(r[1].lobby["game_id"], "siege")
	assert_eq(r[1].lobby["content_id"], "shift_1")
	r[0].set_game("siege", "1", "shift_2")
	pump()
	assert_eq(r[2].lobby["content_id"], "shift_2")


func test_bots_add_remove_and_bot_ftp() -> void:
	var r := room()
	var h := r[0]
	assert_false(r[1].add_bot(), "clients can't add bots")
	assert_true(h.add_bot())
	assert_true(h.add_bot())
	pump()
	var slots := r[1].lobby_slots()
	assert_eq(slots.size(), 5)
	var b1 := slots[3]
	assert_eq(b1.peer_id, -1)
	assert_eq(b1.name, "Bot 1")
	assert_eq(b1.slot_index, 3)
	assert_true(b1.is_bot)
	assert_true(b1.autopilot)
	assert_true(b1.ftp_verified)
	assert_eq(b1.ftp, 250.0, "bot FTP defaults to the host's FTP")
	assert_eq(b1.preferred_cadence_rpm, 90.0, "bots ride at 90 rpm (PS10)")
	assert_eq(slots[4].peer_id, -2)
	assert_eq(slots[4].shape, Wl.slot_look(4)["shape"])
	assert_true(slots[4].hollow, "slots 4-7 are hollow")
	assert_eq(h.bot_ftp(), 250)
	h.set_setting("bot_ftp", 180.4)
	pump()
	assert_eq(r[2].lobby["settings"]["bot_ftp"], 180)
	assert_typeof(r[2].lobby["settings"]["bot_ftp"], TYPE_INT)
	for s in r[2].lobby_slots():
		if s.is_bot:
			assert_eq(s.ftp, 180.0)
	assert_true(h.remove_bot())
	pump()
	assert_eq(r[1].lobby_slots().size(), 4)
	assert_eq(r[1].lobby_slots()[3].peer_id, -1)
	assert_true(h.remove_bot())
	assert_false(h.remove_bot())
	h.set_setting("bot_ftp", "fast")
	assert_push_error("bot_ftp must be a number")


func test_manifest_limits_bots_and_players() -> void:
	var r := room()
	var h := r[0]
	h.set_game_manifest(
		{"id": "duo", "version": "1", "min_players": 1, "max_players": 4, "bots": true}
	)
	h.set_game("duo", "1", "a")
	assert_true(h.add_bot())
	assert_false(h.add_bot(), "3 humans + 1 bot = max_players 4")
	pump()
	assert_eq(r[1].lobby["settings"]["max_players"], 4)
	h.set_game_manifest(
		{"id": "nobots", "version": "1", "min_players": 1, "max_players": 8, "bots": false}
	)
	h.set_game("nobots", "1", "a")
	assert_eq(h.bot_count(), 0, "bots leave when the game allows none")
	assert_false(h.add_bot())
	h.set_game_manifest(
		{"id": "big", "version": "1", "min_players": 5, "max_players": 8, "bots": true}
	)
	h.set_game("big", "1", "a")
	for s in r:
		s.set_ready(true)
	pump()
	assert_false(h.all_ready(), "3 riders < min_players 5")
	assert_true(h.add_bot())
	assert_true(h.add_bot())
	pump()
	assert_false(r[1].all_ready(), "clients lack 'big'")


func test_options_and_player_options_in_lobby_state() -> void:
	var r := room()
	var h := r[0]
	var c1 := r[1]
	h.set_game_manifest(
		{
			"id": "siege",
			"version": "1",
			"min_players": 1,
			"max_players": 4,
			"bots": true,
			"options": [{"id": "rotation", "type": "toggle", "default": true}],
			"player_options":
			[{"id": "wave_offset", "type": "int", "default": 0, "min": -10, "max": 5}]
		}
	)
	h.set_game("siege", "1", "shift_1")
	h.add_bot()
	pump()
	assert_eq(c1.lobby["settings"]["options"], {"rotation": true})
	h.set_option("rotation", false)
	pump()
	assert_eq(c1.lobby["settings"]["options"]["rotation"], false)
	c1.set_player_option(c1.local_peer, "wave_offset", -5)
	c1.set_player_option(c1.local_peer, "not_an_option", 1)
	pump()
	var popts: Dictionary = h.lobby["player_options"]
	assert_eq(float(popts[2]["wave_offset"]), -5.0)
	assert_false((popts[2] as Dictionary).has("not_an_option"), "unknown ids are dropped")
	assert_eq(popts[3], {"wave_offset": 0.0}, "defaults filled")
	assert_eq(popts[-1], {"wave_offset": 0.0}, "bots get the defaults")
	h.set_player_option(-1, "wave_offset", 3)
	h.set_player_option(1, "wave_offset", -2)
	pump()
	var slots := r[2].lobby_slots()
	assert_eq(float(slots[0].options["wave_offset"]), -2.0)
	assert_eq(float(slots[1].options["wave_offset"]), -5.0)
	assert_eq(float(slots[3].options["wave_offset"]), 3.0)
	h.set_player_option(2, "wave_offset", 1)
	assert_push_warning("sets its own options")
	c1.set_player_option(3, "wave_offset", 1)
	assert_push_warning("a client sets only its own options")
	h.set_setting("options", {"rotation": true, "bogus": 1})
	pump()
	assert_eq(c1.lobby["settings"]["options"], {"rotation": true})
	h.set_setting("difficulty", 0.5)
	pump()
	assert_eq(c1.lobby["settings"]["difficulty"], 0.5)


func test_clients_cannot_change_the_lobby() -> void:
	var r := room()
	var before: Dictionary = r[0].lobby.duplicate(true)
	r[1].set_game("siege", "1", "x")
	assert_push_warning("only the host changes the lobby")
	r[1].set_setting("bot_ftp", 100)
	assert_push_warning("only the host changes the lobby")
	r[1].set_scaling(Wl.RAW)
	assert_push_warning("only the host changes the lobby")
	pump()
	assert_true(U.same(r[0].lobby, before))


func test_settings_made_before_hosting_carry_over() -> void:
	var h := make_session("host", rider("Hana", "1", 250))
	# An empty registry: the installed games' manifests (the GameRegistry autoload) would drop
	# the unknown player option "x"; this test is about carrying settings over.
	var reg := WlGameRegistry.new()
	reg.scan_on_ready = false
	add_child_autofree(reg)
	h.registry = reg
	h.set_game("workout", "1", "e2e")
	h.set_scaling(Wl.RAW)
	h.set_player_option(1, "x", 1)
	h.host_room(4)
	pump()
	assert_eq(h.lobby["game_id"], "workout")
	assert_eq(h.lobby["content_id"], "e2e")
	assert_eq(h.lobby["scaling"], Wl.RAW)
	assert_eq(float(h.lobby["player_options"][1]["x"]), 1.0)


func test_offline_lobby_for_solo() -> void:
	var s := make_session("solo", rider("Sol", "1", 230))
	s.start_offline()
	assert_eq(s.state, "offline")
	assert_true(s.offline)
	assert_true(s.is_authority())
	assert_eq(s.local_peer, 1)
	s.set_game("workout", "1", "easy30")
	assert_true(s.add_bot())
	var slots := s.lobby_slots()
	assert_eq(slots.size(), 2)
	assert_eq(slots[0].name, "Sol")
	assert_eq(slots[1].ftp, 230.0)
	assert_false(s.all_ready())
	s.set_ready(true)
	assert_true(s.all_ready())
	s.send_to_host(Protocol.game_msg("ready", {"ready": true}))
	assert_eq(messages("solo").size(), 0, "local delivery happens in poll()")
	s.poll()
	assert_eq(messages("solo", "ready").size(), 1)
	assert_eq(messages("solo")[0][1], 1)
	s.broadcast(Protocol.game_msg("roster", {"riders": {}}))
	s.poll()
	assert_eq(messages("solo", "roster").size(), 0, "nobody to broadcast to")


func test_lobby_changed_on_session_and_bus() -> void:
	var h := make_session("host", rider("Hana"))
	var seen: Array = []
	h.lobby_changed.connect(func(l: Dictionary) -> void: seen.append(l["seq"]))
	var bus_seen: Array = []
	h.bus.lobby_changed.connect(func(l: Dictionary) -> void: bus_seen.append(l["seq"]))
	var states: Array = []
	h.bus.net_state_changed.connect(func(st: String, _d: String) -> void: states.append(st))
	h.host_room()
	pump()
	h.set_game("workout", "1", "a")
	assert_gt(seen.size(), 1)
	assert_eq(seen, bus_seen)
	assert_eq(states, ["connecting", "hosting"])
	assert_typeof(seen[0], TYPE_INT)


# --- NET2, NET5, NET7 (OWNERSHIP names this file) -----------------------------------------


func _directive(kind: String, fields: Dictionary) -> Dictionary:
	var d := fields.duplicate()
	d["kind"] = kind
	return Protocol.game_msg("directive", d)


func _snapshot(seq: int, t: float, state: Dictionary) -> Dictionary:
	return Protocol.game_msg(
		"snapshot", {"game_id": "workout", "seq": seq, "t": t, "tick": seq * 2, "state": state}
	)


func test_oversize_messages_are_dropped() -> void:
	var r := room()
	clear_logs()
	var blob := "x".repeat(NetMessages.MAX_MESSAGE_BYTES)
	r[0].broadcast(_snapshot(1, 0.1, {"blob": blob}))
	assert_push_warning("over the 16384-byte limit")
	r[0].broadcast(_snapshot(2, 0.2, {"blob": "x".repeat(NetMessages.MAX_MESSAGE_BYTES - 200)}))
	pump()
	assert_eq(int(r[0].stats["oversize_snapshots"]), 1)
	assert_eq(int(r[0].stats["oversize_dropped"]), 1)
	var got := messages("c1", "snapshot")
	assert_eq(got.size(), 1, "a message just under the limit still goes")
	assert_eq((got[0][2] as Dictionary)["seq"], 2)


func test_four_rider_session_stays_under_the_relay_rate_limit() -> void:
	# OWNERSHIP NET5 / 3.1 C11: snapshot 10 Hz + roster 2 Hz + events 10 Hz + per-client
	# Fishing-like directives (2 Hz requests, 2 Hz grade, 2 Hz cadence band, 1 Hz power
	# band), clients' telemetry 5 Hz, for 30 s with the relay's limits on.
	hub.enforce_limits(true)
	var r := room(["1", "1", "1"])
	var h := r[0]
	var state := {"lanes": []}
	for i in 4:
		(state["lanes"] as Array).append(
			{"fish": i, "x": 12.5, "tension": 0.75, "run": false, "marks": [1, 2, 3, 4, 5, 6, 7, 8]}
		)
	clear_logs()
	var seq := 0
	for step in 600:
		hub.advance(Wl.SIM_DT)
		if step % 2 == 0:
			seq += 1
			h.broadcast(
				Protocol.game_msg("event", {"seq": seq, "events": [{"type": "tick", "n": step}]})
			)
			h.broadcast(_snapshot(seq, step * Wl.SIM_DT, state))
		if step % 10 == 0:
			h.broadcast(
				Protocol.game_msg("roster", {"riders": {1: {"raw_w": 200.0}, 2: {"raw_w": 180.0}}})
			)
			for peer in [2, 3, 4]:
				h.send_to(
					peer,
					_directive(
						"request", {"id": step + peer, "target_pct": 70.0, "duration_s": 1.0}
					)
				)
				h.send_to(peer, _directive("course_grade", {"grade_pct": 2.0}))
				h.send_to(peer, _directive("cadence_band", {"lo_rpm": 80.0, "hi_rpm": 95.0}))
		if step % 20 == 0:
			for peer in [2, 3, 4]:
				h.send_to(peer, _directive("power_band", {"lo_w": 150.0, "hi_w": 210.0}))
		for i in range(1, 4):
			if step % 4 == i:
				r[i].send_to_host(
					Protocol.game_msg(
						"telemetry",
						{
							"tm":
							{"peer": r[i].local_peer, "power_w": 190.0, "intents": [{"k": "reel"}]}
						}
					)
				)
		for s in r:
			s.tick(Wl.SIM_DT)
	pump()
	assert_eq(int(hub.error_counts.get("rate_limited", 0)), 0, str(hub.error_counts))
	for label in ["c1", "c2", "c3"]:
		assert_eq(messages(label, "snapshot").size(), 300, label)
		assert_eq(messages(label, "event").size(), 300, label)
		assert_eq(messages(label, "roster").size(), 60, label)
		assert_eq(events(label, "refused").size(), 0)
	assert_eq(messages("host", "telemetry").size(), 450)


func test_joins_after_the_start_are_refused_with_session_in_progress() -> void:
	var r := room()
	var h := r[0]
	# A peer that joined but never sent player_info is refused at the start.
	var raw := LoopbackTransport.hub_transport(hub)
	add_child_autofree(raw)
	var raw_msgs: Array = []
	raw.message.connect(func(_f: int, d: Dictionary) -> void: raw_msgs.append(d))
	raw.join(h.room_code)
	raw.poll()
	pump()
	raw.poll()
	h.mark_started()
	pump()
	raw.poll()
	var in_progress := func(d: Dictionary) -> bool:
		return d["type"] == "refused" and d["reason"] == "session_in_progress"
	assert_true(raw_msgs.any(in_progress))
	clear_logs()
	var late := make_session("late", rider("Late"))
	late.join_room(h.room_code)
	pump()
	assert_true(U.same(events("late", "refused"), [["refused", "session_in_progress"]]))
	assert_true(U.same(events("late", "bus_refused"), [["bus_refused", "session_in_progress"]]))
	assert_eq(late.state, "error")
	assert_eq(late.refusal_reason, "session_in_progress")
	assert_false(late.transport.is_open(), "the refused client leaves the room")
	assert_ne(
		WlNetSession.reason_text("session_in_progress"), "session_in_progress", "a readable message"
	)
	assert_eq(events("host", "peer_joined").size(), 0, "the host never lists it")
	assert_eq(events("host", "peer_left").size(), 0)
	assert_eq(h.lobby_slots().size(), 3)


func test_peers_lists_lobby_riders_only() -> void:
	var r := room()
	var raw := LoopbackTransport.hub_transport(hub)
	add_child_autofree(raw)
	raw.join(r[0].room_code)
	raw.poll()
	pump()
	assert_eq(raw.local_peer, 4)
	assert_eq(
		r[0].peers(), [1, 2, 3] as Array[int], "a peer without player_info is not a rider yet"
	)
	assert_eq(r[2].peers(), [1, 2, 3] as Array[int])
	r[0].add_bot()
	pump()
	assert_eq(r[1].peers(), [1, 2, 3] as Array[int], "bots are not peers")


func test_limits_reset_for_a_game_without_manifest() -> void:
	var h := make_session("host", rider("Hana"))
	h.set_game_manifest(
		{"id": "duo", "version": "1", "min_players": 2, "max_players": 2, "bots": false}
	)
	h.set_game("duo", "1", "a")
	assert_eq(h.max_players, 2)
	assert_false(h.bots_allowed)
	h.set_game("workout", "1", "a")
	assert_eq(h.max_players, NetMessages.MAX_PEERS)
	assert_eq(h.min_players, 1)
	assert_true(h.bots_allowed)
