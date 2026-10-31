extends "res://tests/net/net_session_test_base.gd"
## WlNetSession.leave_when_flushed(): leave() drops the frames the send budget holds back, so a
## host that leaves right after its last messages waits for the queue. A host discarding its ride
## leaves this way, and the other riders still get their results.


func _event(seq: int) -> Dictionary:
	return Protocol.game_msg("event", {"seq": seq, "events": []})


func _seqs(label: String) -> Array:
	var out: Array = []
	for e: Array in logs[label]:
		if e[0] == "msg" and str((e[2] as Dictionary).get("type", "")) == "event":
			out.append(int((e[2] as Dictionary)["seq"]))
	return out


## Index of the first entry of `what` in the session's log, -1 when none.
func _at(label: String, what: String) -> int:
	var log: Array = logs[label]
	for i in log.size():
		if (log[i] as Array)[0] == what:
			return i
	return -1


func _held_back_room() -> WlNetSession:
	var r := room(["1"])
	var h := r[0]
	h.send_budget_per_s = 5.0
	h.send_burst = 1.0
	clear_logs()
	for i in 4:
		h.broadcast(_event(i))
	assert_gt(h.queued_frames(), 0, "the budget holds frames back")
	return h


func test_a_plain_leave_drops_what_the_budget_holds_back() -> void:
	var h := _held_back_room()
	h.leave()
	pump(20)
	assert_lt(_seqs("c1").size(), 4, "why leave_when_flushed exists")


func test_the_held_back_frames_go_out_before_the_leave() -> void:
	var h := _held_back_room()
	h.leave_when_flushed()
	assert_eq(h.role, Wl.HOST, "still in the room")
	var n := 0
	while h.role != "" and n < 400:
		hub.advance(Wl.SIM_DT)
		h.tick(Wl.SIM_DT)
		pump(1)
		n += 1
	assert_eq(h.role, "", "left after %d steps" % n)
	assert_eq(h.queued_frames(), 0)
	pump(4)
	assert_eq(_seqs("c1"), [0, 1, 2, 3], "every frame, in order")
	var refused := _at("c1", "refused")
	assert_gt(refused, 0, "the client hears the host left")
	var last_msg := -1
	for i in (logs["c1"] as Array).size():
		if (logs["c1"] as Array)[i][0] == "msg":
			last_msg = i
	assert_gt(refused, last_msg, "after the frames")


func test_with_nothing_queued_it_leaves_at_once() -> void:
	var r := room(["1"])
	var h := r[0]
	assert_eq(h.queued_frames(), 0)
	h.leave_when_flushed()
	assert_eq(h.role, "")
	assert_eq(h.state, WlNetSession.STATE_OFFLINE)


func test_outside_a_room_it_leaves_at_once() -> void:
	var s := make_session("alone", rider("Solo"))
	s.start_offline()
	s.leave_when_flushed()
	assert_false(s.offline)
	assert_eq(s.state, WlNetSession.STATE_OFFLINE)


func test_a_new_room_leaves_the_old_one_first() -> void:
	var h := _held_back_room()
	var old := h.room_code
	h.leave_when_flushed()
	h.host_room(8)
	pump()
	assert_eq(h.role, Wl.HOST)
	assert_ne(h.room_code, old, "a new room")
	assert_gte(_at("c1", "refused"), 0, "the old room's rider heard the host left")
	for _i in 40:
		hub.advance(Wl.SIM_DT)
		h.tick(Wl.SIM_DT)
		pump(1)
	assert_eq(h.role, Wl.HOST, "no leave stays pending for the new room")


func test_an_offline_start_settles_it_too() -> void:
	var h := _held_back_room()
	h.leave_when_flushed()
	h.start_offline()
	assert_true(h.offline)
	for _i in 40:
		pump(1)
	assert_true(h.offline, "no leave stays pending")
