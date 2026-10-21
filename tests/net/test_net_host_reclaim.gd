extends "res://tests/net/net_session_test_base.gd"
## The host reclaims peer 1 after a drop (W3 NET-1; BRIEF 5.3 holds its room 120 s): the
## relay's joined.peers tells it who left or came meanwhile, connected session peers get
## resync_requested, and a client re-sends its player_info when the host comes back.
## Lobby privacy in WKG and RAW (W3 PROF-2; BRIEF 3.2).


func _lt(s: WlNetSession) -> LoopbackTransport:
	return s.transport as LoopbackTransport


func test_joined_lists_the_other_connected_peers() -> void:
	var r := room()
	var h := r[0]
	var rt := _lt(r[2])
	assert_true(rt.joined_peers_known)
	assert_eq(rt.joined_peers, [1, 2] as Array[int], "c2 joined after the host and c1")
	assert_false(rt.rejoined)
	h.auto_reconnect = false
	_lt(h).simulate_drop()
	pump()
	h.rejoin()
	pump()
	assert_eq(h.state, "hosting")
	assert_true(_lt(h).rejoined, "the host reclaimed its id")
	assert_eq(_lt(h).joined_peers, [2, 3] as Array[int])


func test_a_reclaiming_host_resyncs_who_stayed_and_drops_who_left() -> void:
	var r := room(["1", "1", "1"])
	var h := r[0]
	h.mark_started()
	pump()
	h.auto_reconnect = false
	_lt(h).simulate_drop()
	pump()
	r[3].leave()  # c3 leaves for good while the host is away
	pump()
	clear_logs()
	var resynced: Array = []
	h.resync_requested.connect(func(p: int) -> void: resynced.append(p))
	h.rejoin()
	pump()
	assert_eq(h.state, "hosting")
	assert_true(
		U.same(events("host", "peer_left"), [["peer_left", 4, "dropped"]]),
		str(events("host", "peer_left"))
	)
	resynced.sort()
	assert_eq(resynced, [2, 3], "every session peer still connected is resynced")
	assert_eq(events("host", "rejoin_requested").size(), 0, "nobody new came back")
	assert_false(h.peers().has(4), "the one that left is not listed as connected")


func test_a_client_that_joined_while_the_host_was_away_reaches_the_lobby() -> void:
	var r := room(["1"])
	var h := r[0]
	h.auto_reconnect = false
	_lt(h).simulate_drop()
	pump()
	var late := make_session("late", rider("Lou", "1", 230))
	late.join_room(h.room_code)
	pump()
	assert_eq(late.state, "joined", "the relay let it in while the host was away")
	assert_false(
		h.lobby_slots().any(func(s: PlayerSlot) -> bool: return s.name == "Lou"), "precondition"
	)
	h.rejoin()
	pump(8)
	var names: Array = []
	for s in h.lobby_slots():
		names.append(s.name)
	assert_true(
		names.has("Lou"), "its player_info is re-sent when the host comes back: %s" % str(names)
	)
	assert_true(
		late.lobby_slots().any(func(s: PlayerSlot) -> bool: return s.name == "Lou"),
		"and it sees itself in lobby_state"
	)


## PROF-2: in WKG, p_eff_per_w is 75 / weight. Another client never learns a rider's
## unshared weight from lobby_state; the rider sees its own value and the host keeps them all.
func test_wkg_lobby_state_hides_every_riders_weight_from_the_others() -> void:
	var h := make_session("host", rider("Hana", "1", 250))
	h.set_game("workout", "1", "easy30")
	h.host_room(8)
	pump()
	var c := make_session("c1")
	var p := RiderProfile.new()
	p.display_name = "Cy"
	p.ftp_w = 250.0
	p.weight_kg = 82.5
	p.share_weight = false
	c.set_local_profile(p, {"workout": "1"})
	c.join_room(h.room_code)
	pump()
	var d := make_session("c2", rider("Dee", "1", 220))
	d.join_room(h.room_code)
	pump()
	h.set_scaling(Wl.WKG)
	pump(8)
	var cy_on_d := player(d, c.local_peer)
	assert_false(cy_on_d.is_empty())
	assert_eq(
		float(cy_on_d["p_eff_per_w"]), 1.0, "another client sees the 75 kg reference, not 75 / 82.5"
	)
	assert_eq(float(player(d, h.local_peer)["p_eff_per_w"]), 1.0, "the host's own entry too")
	assert_almost_eq(
		float(player(h, c.local_peer)["p_eff_per_w"]),
		75.0 / 82.5,
		1e-9,
		"the host keeps the real value"
	)
	var own: PlayerSlot = null
	for s in c.lobby_slots():
		if s.peer_id == c.local_peer:
			own = s
	assert_almost_eq(own.p_eff_per_w, 75.0 / 82.5, 1e-9, "the rider sees its own value")
	h.set_scaling(Wl.FAIR_FTP)
	pump(8)
	assert_almost_eq(
		float(player(d, c.local_peer)["p_eff_per_w"]),
		1.0,
		1e-9,
		"FAIR_FTP: 250 / FTP, which reveals nothing"
	)


## BRIEF 3.2: in RAW the speed model uses the weight a rider shared with the host. Another
## client never learns it from lobby_state (every human's rider_mass_kg goes out as the 75 kg
## reference), the rider sees its own, the host computes with every real weight, and
## player_info carries the weight only while the lobby is RAW.
func test_raw_lobby_state_hides_every_shared_weight_from_the_others() -> void:
	var h := make_session("host")
	h.set_local_profile(_sharing("Hana", 64.0), {"workout": "1"})
	h.set_game("workout", "1", "easy30")
	h.host_room(8)
	pump()
	var c := make_session("c1")
	c.set_local_profile(_sharing("Cy", 82.5), {"workout": "1"})
	c.join_room(h.room_code)
	pump()
	# A player_info built outside NetSession (as the app's lobby does), with the weight in it
	# and an FTP of 250, so P_eff (1.0) is the same in FAIR_FTP and RAW.
	var d := make_session("c2", rider("Dee", "1", 250, {"weight_kg": 58.0}))
	d.join_room(h.room_code)
	pump()
	h.add_bot()
	pump()
	var weights := {h.local_peer: 64.0, c.local_peer: 82.5, d.local_peer: 58.0}
	var c_sent := _infos_from(c.local_peer).size()
	var d_sent := _infos_from(d.local_peer).size()
	assert_gt(d_sent, 0, "precondition: c2 sent its player_info")
	_assert_no_weight_in_player_info("FAIR_FTP")
	h.set_scaling(Wl.RAW)
	pump(8)
	assert_eq(_infos_from(c.local_peer).size(), c_sent + 1, "c1 re-sent its player_info for RAW")
	assert_eq(
		_infos_from(d.local_peer).size(), d_sent + 1, "c2 too, once, though its info is unchanged"
	)
	assert_eq(float(_infos_from(c.local_peer).back()["weight_kg"]), 82.5)
	assert_eq(float(_infos_from(d.local_peer).back()["weight_kg"]), 58.0)
	for peer: int in weights:
		assert_eq(
			float(player(h, peer)["rider_mass_kg"]),
			float(weights[peer]),
			"the host computes RAW with peer %d's real weight" % peer
		)
	for s in h.lobby_slots():
		assert_eq(s.rider_mass_kg, 75.0 if s.is_bot else float(weights[s.peer_id]))
	for viewer: WlNetSession in [c, d]:
		for peer: int in weights:
			assert_eq(
				float(player(viewer, peer)["rider_mass_kg"]),
				75.0,
				"peer %d's lobby_state carries 75 kg for peer %d" % [viewer.local_peer, peer]
			)
		for e: Array in messages(str(viewer.name), "lobby_state"):
			for p: Dictionary in (e[2] as Dictionary)["players"]:
				assert_eq(float(p["rider_mass_kg"]), 75.0, "no lobby_state ever names a weight")
		var own: PlayerSlot = null
		for s in viewer.lobby_slots():
			if s.peer_id == viewer.local_peer:
				own = s
		assert_eq(
			own.rider_mass_kg,
			float(weights[viewer.local_peer]),
			"peer %d rides at its own weight" % viewer.local_peer
		)
	h.set_scaling(Wl.WKG)
	pump(8)
	assert_eq(_infos_from(d.local_peer).size(), d_sent + 2, "re-sent without the weight")
	assert_false(_infos_from(c.local_peer).back().has("weight_kg"), "WKG: no weight")
	assert_false(_infos_from(d.local_peer).back().has("weight_kg"), "WKG: no weight")
	h.set_scaling(Wl.FAIR_FTP)
	pump(8)
	assert_false(_infos_from(c.local_peer).back().has("weight_kg"), "FAIR_FTP: no weight")
	assert_false(_infos_from(d.local_peer).back().has("weight_kg"), "FAIR_FTP: no weight")
	var settled := _infos_from(d.local_peer).size()
	pump(8)
	assert_eq(_infos_from(d.local_peer).size(), settled, "no re-send loop on lobby_state echoes")


func _sharing(display_name: String, weight: float) -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = display_name
	p.ftp_w = 250.0
	p.weight_kg = weight
	p.share_weight = true
	return p


## The player_info messages the host got from `peer`, in order.
func _infos_from(peer: int) -> Array:
	var out: Array = []
	for e: Array in messages("host", "player_info"):
		if int(e[1]) == peer:
			out.append(e[2])
	return out


func _assert_no_weight_in_player_info(mode: String) -> void:
	for e: Array in messages("host", "player_info"):
		assert_false((e[2] as Dictionary).has("weight_kg"), "%s: no weight leaves a client" % mode)
