extends GutTest
## lead W2 round 2, GameHost config.platform_pause with the real LocalRider, SafetyGovernor and
## MockTrainer: a SOLO rider who stops pedalling in ERG is paused by the governor's coasting
## rule (BRIEF 4.6.4: not_pedaling for 3 s drops ERG to its floor, after 10 s the session
## pauses; stop_5s is outside ERG only) whoever owns pausing. Pedalling again ends that pause
## only while the GameHost owns it (platform_pause on, the default); with platform_pause off
## the app resumes it. The stop falls in the ERG cool-down of "tiny" (from ~41 s), where the
## flywheel stops with the rider (in SIM the coasting flywheel feeds the cadence estimate; see
## the sdk round-2 report).

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


func test_the_coasting_pause_works_with_either_owner_and_only_the_platform_resumes_on_pedalling(
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
			host.is_paused(),
			"platform_pause %s: the coasting rider pauses (4.6.4)" % platform_pause
		)
		assert_eq(host.tracker.phase_of(1).kind, Wl.COOLDOWN, "in the ERG cool-down")
		assert_between(t, 55.0, 57.0, "10 s after the first not_pedaling sample at ~45.5 s")
		assert_eq(log[0].slice(0, 2), [true, "coasting"])
		# The rider rides again from 70 s: pedal_start fires a few seconds later.
		while host.clock.platform_time() < 85.0:
			host.step()
		assert_gt(rider.telemetry().power_w, 50.0, "the rider pedals again")
		if platform_pause:
			assert_false(host.is_paused(), "the GameHost resumes on pedal_start")
			assert_eq(log[1].slice(0, 2), [false, "resume"])
		else:
			assert_true(host.is_paused(), "platform_pause off: still paused until the app resumes")
			assert_eq(log.size(), 1)
			host.resume()
			assert_false(host.is_paused())
		host.end_session("timeout")
		rider.shutdown()
