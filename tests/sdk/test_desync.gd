extends GutTest
## Desync detection on clients (BRIEF 7.7 "no desync warnings"; W3 NET-5, QT-1). A lost event
## batch, or the roster showing another phase for this rider twice in a row, logs a
## push_warning with "desync" (AppLogWatch, the scripted peer's report and the e2e check count
## it) and asks the host for a resync, which puts the client back in step. The gap after a
## rejoin or the host's return is expected and is no desync.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")

var _root: Node = null
var _tmp: Array[String] = []
var _watch: AppLogWatch = null


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_watch = AppLogWatch.new()
	OS.add_logger(_watch)


func after_each() -> void:
	OS.remove_logger(_watch)
	for d in _tmp:
		Kit.remove_tree(d)
	_tmp.clear()


func _multi(humans: int = 2, content: String = "tiny") -> Dictionary:
	var b := Kit.multi(_root, humans, content)
	_tmp.append(str(b["tmp"]))
	assert_eq(b["err"], "", "session setup")
	Kit.start(b)
	Kit.step(b, 2)
	return b


func _desyncs() -> int:
	return int(_watch.counts()["desync_warnings"])


## The W3 QT-1 gate: batch 1001 lost between 1000 and 1002.
func test_a_lost_event_batch_is_reported_as_a_desync() -> void:
	var b := _multi()
	var client: GameHost = (b["clients"] as Array)[0]
	var before := _desyncs()
	var applied_before := (client.game.get("events_applied") as Array).size()
	# A first batch sets the baseline; any later jump is a gap.
	var gaps := 2 if int(client.get("_event_seq_applied")) > 0 else 1
	client.call("_client_message", 1, {"type": "event", "seq": 1000, "events": [{"type": "fx_a", "n": 1}]})
	client.call("_client_message", 1, {"type": "event", "seq": 1002, "events": [{"type": "fx_c", "n": 3}]})
	assert_eq((client.game.get("events_applied") as Array).size() - applied_before, 2, "both delivered batches were applied")
	assert_eq(_desyncs() - before, gaps, "a gap in the event sequence (1000 -> 1002) is reported as a desync warning")
	assert_eq(client.desync_count, gaps)
	assert_push_warning("desync: event batch 1002 after 1000: 1 batch(es) lost")
	assert_eq(int(client.report_data()["desync_warnings"]), gaps, "the report counts them")


## In-order batches and a repeat are no desync.
func test_in_order_events_are_no_desync() -> void:
	var b := _multi()
	Kit.step(b, 200)
	var client: GameHost = (b["clients"] as Array)[0]
	assert_gt((client.game.get("events_applied") as Array).size(), 2, "events arrived")
	assert_eq(client.desync_count, 0)
	assert_eq(_desyncs(), 0)


## A client's own rejoin and the host's return (peer_joined of the host) make the next gap
## expected: no warning, and the batch is applied.
func test_the_gap_after_a_rejoin_or_the_hosts_return_is_expected() -> void:
	var b := _multi()
	var client: GameHost = (b["clients"] as Array)[0]
	var net: WlNetSession = (b["nets"] as Array)[1]
	client.call("_client_message", 1, {"type": "event", "seq": 500, "events": []})
	var base := client.desync_count
	net.state_changed.emit(WlNetSession.STATE_JOINED, "rejoin")
	client.call("_client_message", 1, {"type": "event", "seq": 520, "events": []})
	assert_eq(client.desync_count, base, "after this client's rejoin")
	net.peer_joined.emit(Wl.HOST_PEER)
	Kit.step(b, 1)
	client.call("_client_message", 1, {"type": "event", "seq": 600, "events": []})
	assert_eq(client.desync_count, base, "after the host came back")
	client.call("_client_message", 1, {"type": "event", "seq": 610, "events": []})
	assert_eq(client.desync_count, base + 1, "only the first gap after it is expected")
	assert_push_warning("desync: event batch 610 after 600")


## A lost `phase` message: the roster shows the host's phase for this rider; two rosters in a
## row that disagree are a desync, the client asks for a resync in its telemetry, the host
## resends plan and phase, and the client rides the host's phase again.
func test_a_lost_phase_message_is_detected_and_resynced() -> void:
	var b := Kit.multi(_root, 2, "short")
	_tmp.append(str(b["tmp"]))
	assert_eq(b["err"], "")
	var hub: RefCounted = b["hub"]
	var host: GameHost = b["host"]
	var client: GameHost = (b["clients"] as Array)[0]
	Kit.start(b)
	# 300 s ramp: just before the WORK phase, cut the host -> client link for 1 s so the
	# client misses the `phase` message (and nothing else marks it: no peer_left).
	Kit.step(b, 5990)
	assert_eq(client.local_phase_state().index, 0)
	(hub.get("dropped") as Dictionary)[2] = true
	for k in 20:
		host.step()
		client.step()
	(hub.get("dropped") as Dictionary).erase(2)
	assert_eq(host.tracker.index_of(2), 1, "the host moved rider 2 to WORK")
	assert_eq(client.local_phase_state().index, 0, "precondition: the client missed it")
	var steps := Kit.step_until(b, func() -> bool: return client.local_phase_state().index == 1, 200)
	assert_lt(steps, 200, "the client is back in phase 1 within 10 s")
	assert_gte(client.desync_count, 1, "the mismatch was reported")
	assert_push_warning("desync: rider 2 rides phase 0 here but phase 1 on the host")
	assert_gte(host.resync_count, 1, "the host answered a resync")
	var rider: LocalRider = b["riders"][2]
	assert_eq((rider.get("phases_started") as Array).back(), 1, "the rider entered phase 1")
	assert_almost_eq(client.local_phase_state().elapsed_s, host.tracker.state(2).elapsed_s, 0.3, "at the host's elapsed time")
