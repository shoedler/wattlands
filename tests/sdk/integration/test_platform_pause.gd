extends GutTest
## GameHost pausing with the real LocalRider, SafetyGovernor and MockTrainer: a SOLO rider who
## stops pedalling pauses after 10 s of not_pedaling in every mode, ERG included (BRIEF 3.5,
## RidePause), whoever owns pausing (config.platform_pause), and the session resumes after
## 1 s of pedalling at >= 30 rpm. The governor's own rules are unchanged (4.6.4: the coasting
## floor at 3 s, its 10 s solo pause request comes at the same moment and pauses once). The stop falls
## in the ERG cool-down of "tiny" (from ~41 s), where the flywheel stops with the rider.

const Kit := preload("res://tests/sdk/helpers/session_kit.gd")
## The rider stops at 45 s of profile time for 25 s, then rides again.
const SPEC := "erg+cadence_drop:rpm=0,at_s=45,for_s=25"

var _root: Node = null
var _tmp: String = ""


func before_each() -> void:
	_root = Node.new()
	add_child_autofree(_root)
	_tmp = Paths.make_temp_dir("wattlands_platform_pause")
	Paths.set_override(_tmp)


func after_each() -> void:
	Paths.set_override("")
	Kit.remove_tree(_tmp)


func _session(platform_pause: bool) -> Dictionary:
	var slot := Kit.human(1, 0)
	var prof := RiderProfile.new()
	prof.ftp_w = 200.0
	prof.cp_w = 200.0
	prof.ftp_verified = true
	var dev := MockTrainer.from_spec(SPEC, 200.0, {"seed": 11})
	var rider := LocalRider.new()
	rider.setup(1, prof, slot, dev, {"multiplayer": false, "record": false, "seed": 11})
	if dev.get_parent() == null:
		rider.add_child(dev)
	_root.add_child(rider)
	var bus := Kit.new_bus(_root, "PauseBus")
	var host := GameHost.new()
	_root.add_child(host)
	var err := (
		host
		. setup(
			{
				"game_id": "fx_solo",
				"content_id": "tiny",
				"seed": 7,
				"role": Wl.SOLO,
				"players": [slot] as Array[PlayerSlot],
				"local_riders": {1: rider},
				"local_peer": 1,
				"bus": bus,
				"registry": Kit.registry(_root),
				"headless": true,
				"realtime": false,
				"record_rides": false,
				"platform_pause": platform_pause,
				"progress_path": _tmp.path_join("progress.json"),
			}
		)
	)
	var log: Array = []
	bus.paused_changed.connect(
		func(p: bool, why: String) -> void: log.append([p, why, host.clock.platform_time()])
	)
	return {"host": host, "rider": rider, "err": err, "log": log}


## Steps until the session pauses (or `max_s` of platform time); returns the platform time.
func _step_until_paused(host: GameHost, max_s: float) -> float:
	while not host.is_paused() and host.clock.platform_time() < max_s:
		host.step()
	return host.clock.platform_time()


func test_the_rider_pauses_after_10_s_and_resumes_after_1_s_of_pedalling_with_either_owner(
) -> void:
	for platform_pause: bool in [true, false]:
		var s := _session(platform_pause)
		assert_eq(s["err"], "")
		var host: GameHost = s["host"]
		var rider: LocalRider = s["rider"]
		var log: Array = s["log"]
		host.start()
		var t := _step_until_paused(host, 65.0)
		assert_true(
			host.is_paused(), "platform_pause %s: the stopped rider pauses" % platform_pause
		)
		assert_eq(host.tracker.phase_of(1).kind, Wl.COOLDOWN, "in the ERG cool-down")
		assert_between(t, 55.0, 56.6, "10 s after the first not_pedaling sample at ~45.5 s")
		assert_true(log[0][0], "paused")
		assert_has(["stop_5s", "coasting"], log[0][1], "the pause on not pedaling or 4.6.4's")
		while not rider.is_ride_paused() and host.clock.platform_time() < 57.0:
			host.step()
		assert_true(rider.is_ride_paused())
		assert_true(rider.telemetry().paused)
		assert_true(rider.telemetry().coasting, "the 4.6.4 coasting floor since 3 s")
		# Both 10 s rules pause once: the second request lands in the pause already running.
		while host.clock.platform_time() < 69.5:
			host.step()
		assert_eq(log.size(), 1, "one pause")
		# The rider rides again from 70 s: 1 s at >= 30 rpm resumes, in either mode.
		while host.is_paused() and host.clock.platform_time() < 80.0:
			host.step()
		assert_false(host.is_paused(), "resumed")
		assert_between(host.clock.platform_time(), 71.0, 72.6, "1 s after the first pedal sample")
		assert_eq(log[1].slice(0, 2), [false, "resume"])
		assert_false(rider.is_ride_paused())
		host.end_session("timeout")
		rider.shutdown()


## A pause the rider asked for is not ended by pedalling.
func test_a_user_pause_stays_when_the_rider_pedals() -> void:
	var s := _session(true)
	var host: GameHost = s["host"]
	var rider: LocalRider = s["rider"]
	host.start()
	while host.clock.platform_time() < 10.0:
		host.step()
	host.pause("user")
	while host.clock.platform_time() < 20.0:
		host.step()
	assert_true(host.is_paused(), "still paused")
	assert_false(rider.is_ride_paused(), "the rider pedals")
	host.resume()
	host.end_session("timeout")
	rider.shutdown()
