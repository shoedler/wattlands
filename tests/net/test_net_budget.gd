extends "res://tests/net/net_session_test_base.gd"
## WlNetSession's send budget (W3 NET-4; BRIEF 5.3 "60 messages/s per peer (burst 120)"):
## tests/net/test_net_session.gd's NET5 load with 8 riders instead of 4 (snapshot 10 Hz, events
## 10 Hz, roster 2 Hz, per client 2 Hz request + 2 Hz course_grade + 2 Hz cadence_band + 1 Hz
## power_band, and a phase change every 2 s), about 71 frames a second, against the relay's
## rate limit. The relay rate-limits nothing, every request, phase and event batch arrives in
## order, and only snapshots, rosters and coalesced directives give way (the latest wins).


func test_eight_riders_stay_under_the_relay_rate_limit_without_losing_requests() -> void:
	hub.enforce_limits(true)
	var r := room(["1", "1", "1", "1", "1", "1", "1"])
	var h := r[0]
	assert_eq(r.size(), 8)
	var state := {"lanes": []}
	clear_logs()
	var seq := 0
	var requests_sent := 0
	var phases_sent := 0
	for step in 600:
		hub.advance(Wl.SIM_DT)
		if step % 2 == 0:
			seq += 1
			h.broadcast(Protocol.game_msg("event", {"seq": seq, "events": [{"type": "tick", "n": step}]}))
			h.broadcast(Protocol.game_msg("snapshot", {"game_id": "workout", "seq": seq, "tick": seq * 2, "state": state}))
		if step % 10 == 0:
			h.broadcast(Protocol.game_msg("roster", {"riders": {1: {"raw_w": 200.0}}}))
			for peer in range(2, 9):
				h.send_to(peer, Protocol.game_msg("directive", {"kind": "request", "id": step * 10 + peer, "directive": {"target_pct": 70.0, "duration_s": 1.0}}))
				requests_sent += 1
				h.send_to(peer, Protocol.game_msg("directive", {"kind": "course_grade", "grade_pct": 2.0}))
				h.send_to(peer, Protocol.game_msg("directive", {"kind": "cadence_band", "lo_rpm": 80.0, "hi_rpm": 95.0}))
		if step % 20 == 0:
			for peer in range(2, 9):
				h.send_to(peer, Protocol.game_msg("directive", {"kind": "power_band", "lo_w": 150.0, "hi_w": 210.0}))
		if step % 40 == 0:
			for peer in range(2, 9):
				h.send_to(peer, Protocol.game_msg("phase", {"peer": peer, "index": phases_sent, "start_tick": step, "ended_by": "duration"}))
			phases_sent += 1
		for s in r:
			s.tick(Wl.SIM_DT)
	# Let the queue drain (the load stops; the budget refills).
	for k in 200:
		hub.advance(Wl.SIM_DT)
		for s in r:
			s.tick(Wl.SIM_DT)
	pump()
	assert_eq(int(hub.error_counts.get("rate_limited", 0)), 0, "8 riders never hit the relay's rate limit")
	assert_eq(h.queued_frames(), 0, "the queue drained")
	var got_requests := 0
	for i in range(1, 8):
		var label := "c%d" % i
		var ids: Array[int] = []
		var phase_idx: Array[int] = []
		var event_seqs: Array[int] = []
		var snap_seqs: Array[int] = []
		for m: Array in messages(label):
			var d: Dictionary = m[2]
			match str(d.get("type", "")):
				"directive":
					if str(d.get("kind", "")) == "request":
						ids.append(int(d["id"]))
				"phase":
					phase_idx.append(int(d["index"]))
				"event":
					event_seqs.append(int(d["seq"]))
				"snapshot":
					snap_seqs.append(int(d["seq"]))
		got_requests += ids.size()
		var sorted_ids := ids.duplicate()
		sorted_ids.sort()
		assert_eq(ids, sorted_ids, "%s: requests in order" % label)
		assert_eq(phase_idx.size(), phases_sent, "%s: every phase message" % label)
		for k in phase_idx.size():
			assert_eq(phase_idx[k], k, "%s: phases in order" % label)
		assert_eq(event_seqs.size(), seq, "%s: every event batch" % label)
		for k in event_seqs.size():
			if event_seqs[k] != k + 1:
				fail_test("%s: event batch %d arrived as %d" % [label, k + 1, event_seqs[k]])
				break
		assert_gt(snap_seqs.size(), 0, "%s: snapshots arrive" % label)
		assert_eq(snap_seqs.back(), seq, "%s: the newest snapshot arrives" % label)
	assert_eq(got_requests, requests_sent, "every request reaches its client")
	assert_gt(int(h.stats["superseded"]), 0, "snapshots, rosters and coalesced directives gave way")


## Under the budget nothing waits: frames go out at once, as before the budget existed.
func test_a_light_load_sends_at_once() -> void:
	var r := room(["1"])
	var h := r[0]
	clear_logs()
	h.send_to(2, Protocol.game_msg("phase", {"peer": 2, "index": 0, "start_tick": 0, "ended_by": "start"}))
	assert_eq(h.queued_frames(), 0)
	pump()
	assert_eq(messages("c1", "phase").size(), 1)


## A replaceable frame that waits is replaced by a newer one, which goes behind everything
## queued before it (a snapshot never overtakes the events sent before it).
func test_a_newer_snapshot_replaces_the_queued_one_and_keeps_order() -> void:
	var r := room(["1"])
	var h := r[0]
	h.send_budget_per_s = 1.0
	h.send_burst = 1.0
	h.set("_tokens", 0.0)
	h.set("_tokens_t", h.local_time())
	clear_logs()
	h.broadcast(Protocol.game_msg("snapshot", {"game_id": "x", "seq": 1, "tick": 1, "state": {}}))
	h.broadcast(Protocol.game_msg("event", {"seq": 1, "events": []}))
	h.broadcast(Protocol.game_msg("snapshot", {"game_id": "x", "seq": 2, "tick": 2, "state": {}}))
	assert_eq(h.queued_frames(), 2, "the first snapshot was replaced")
	assert_eq(int(h.stats["superseded"]), 1)
	for k in 60:
		h.tick(Wl.SIM_DT)
	pump()
	var got: Array = []
	for m: Array in messages("c1"):
		var d: Dictionary = m[2]
		if str(d.get("type", "")) in ["snapshot", "event"]:
			got.append([d["type"], int(d["seq"])])
	assert_eq(got, [["event", 1], ["snapshot", 2]])
