extends GutTest
## Pause on not pedaling in multiplayer (BRIEF 3.5): a stopped rider pauses only their own ride
## timer; the shared game clock pauses only while every human rider is paused (bots ignored),
## clients follow through the roster's `paused`, and a rider who rides again resumes it. Heart
## rate never leaves the rider's machine.

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


func _session() -> Dictionary:
	var b := Kit.multi(_root, 3, "tiny", {}, 1)
	_tmp.append(str(b["tmp"]))
	assert_eq(b["err"], "", "session setup")
	Kit.start(b)
	Kit.step(b, 40)
	return b


func _rider(b: Dictionary, peer: int) -> LocalRider:
	return b["riders"][peer]


func test_the_shared_clock_pauses_only_while_every_human_is_paused() -> void:
	var b := _session()
	var host: GameHost = b["host"]
	var c2: GameHost = (b["clients"] as Array)[0]
	var c3: GameHost = (b["clients"] as Array)[1]
	assert_eq(host.state, "running")
	_rider(b, 1).set("ride_paused", true)
	_rider(b, 2).set("ride_paused", true)
	Kit.step(b, 40)
	assert_eq(host.state, "running", "one human still rides")
	var tick := host.clock.game_tick
	Kit.step(b, 10)
	assert_gt(host.clock.game_tick, tick, "the game clock runs")
	_rider(b, 3).set("ride_paused", true)
	Kit.step_until(b, func() -> bool: return host.is_paused(), 40)
	assert_true(host.is_paused(), "every human paused (the bot rides on)")
	tick = host.clock.game_tick
	Kit.step_until(b, func() -> bool: return c2.state == "paused" and c3.state == "paused", 40)
	assert_eq(c2.state, "paused", "clients follow the roster")
	assert_eq(c3.state, "paused")
	assert_true(_rider(b, 2).get("game_paused"), "the client rider's governor pauses (4.1)")
	var phase_ticks: int = c2.get("_client_phase_ticks")
	Kit.step(b, 30)
	assert_eq(host.clock.game_tick, tick, "the shared game clock stands")
	assert_eq(c2.get("_client_phase_ticks"), phase_ticks, "the client's phase clock stands")
	_rider(b, 3).set("ride_paused", false)
	Kit.step_until(b, func() -> bool: return not host.is_paused(), 40)
	assert_false(host.is_paused(), "one rider rides again: resumed")
	Kit.step_until(b, func() -> bool: return c2.state != "paused", 40)
	assert_eq(c2.state, "running")
	assert_false(_rider(b, 2).get("game_paused"))
	Kit.step(b, 10)
	assert_gt(host.clock.game_tick, tick, "the game clock runs again")


func test_a_resume_from_the_menu_holds_until_the_riders_stop_again() -> void:
	var b := _session()
	var host: GameHost = b["host"]
	for peer in [1, 2, 3]:
		_rider(b, peer).set("ride_paused", true)
	Kit.step_until(b, func() -> bool: return host.is_paused(), 40)
	assert_true(host.is_paused())
	host.resume()
	Kit.step(b, 40)
	assert_false(host.is_paused(), "edge-triggered: no re-pause while everyone stays stopped")


func test_heart_rate_never_leaves_the_rider() -> void:
	var b := _session()
	var host: GameHost = b["host"]
	_rider(b, 2).set("heart_rate", 150)
	_rider(b, 1).set("heart_rate", 140)
	Kit.step(b, 20)
	var remote: Dictionary = host.get("_remote")[2]
	var tm: Telemetry = remote["tm"]
	assert_not_null(tm)
	assert_eq(tm.heart_rate_bpm, 0, "a client's heart rate is not sent")
	var frame_tm: Dictionary = host.get("_frame_tm")
	assert_eq((frame_tm[1] as Telemetry).heart_rate_bpm, 0, "games never see it")
	assert_eq(_rider(b, 1).telemetry().heart_rate_bpm, 140, "the rider's own telemetry keeps it")
