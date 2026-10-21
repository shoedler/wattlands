extends GutTest
## W3 NET-3: an imported .zwo with hundreds of blocks makes a `plan` message far over the relay's
## 16 KB limit (BRIEF 5.3). The host splits it into parts of whole phases and every client joins
## them and re-validates the whole plan, over the real WlNetSession and LoopbackTransport.

var _tmp: String = ""
var _runners: Array[GameSimRunner] = []


func before_each() -> void:
	_tmp = Paths.make_temp_dir("workout_big_zwo")


func after_each() -> void:
	for r in _runners:
		if is_instance_valid(r):
			r.cleanup()
	_runners.clear()
	GameSimRunner._remove_tree(_tmp)


func _zwo(repeat: int) -> String:
	var path := _tmp.path_join("many_%d.zwo" % repeat)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("""<workout_file><name>Many intervals</name><sportType>bike</sportType><workout>
<Warmup Duration="600" PowerLow="0.45" PowerHigh="0.65"/>
<IntervalsT Repeat="%d" OnDuration="30" OffDuration="30" OnPower="1.00" OffPower="0.50"/>
<Cooldown Duration="300" PowerLow="0.60" PowerHigh="0.45"/>
</workout></workout_file>""" % repeat)
	f.close()
	return path


func test_a_long_imported_zwo_reaches_every_client() -> void:
	var path := _zwo(200)
	var args := GameSimRunner.parse_args(PackedStringArray([
		"--game=workout", "--content=zwo:" + path, "--players=3", "--bots=1", "--seed=2",
		"--max-sim-seconds=40", "--report=" + _tmp.path_join("big.json"),
	]))
	assert_false(args.has("error"), str(args.get("error", "")))
	args["headless"] = true
	var runner := GameSimRunner.new()
	add_child_autofree(runner)
	_runners.append(runner)
	assert_eq(runner.setup(args), "")
	assert_eq(runner.run_to_end(), "timeout")
	var host := runner.host
	for gh in runner.clients:
		var peer := gh.local_peer()
		var plan: EffortPlan = host.plans[peer]
		var bytes := Protocol.encoded_size(Protocol.game_msg("plan", {"peer": peer, "plan": plan.to_dict()}))
		assert_gt(plan.phases.size(), 400, "precondition: a 400-block workout")
		assert_gt(bytes, NetMessages.MAX_MESSAGE_BYTES, "precondition: its plan is %d bytes" % bytes)
		assert_true(gh.plans.has(peer), "peer %d got its plan" % peer)
		if gh.plans.has(peer):
			# Through JSON both sides, as the wire has it (ints in `meta` come back as floats).
			assert_eq(JSON.parse_string(JSON.stringify((gh.plans[peer] as EffortPlan).to_dict())),
				JSON.parse_string(JSON.stringify(plan.to_dict())), "peer %d's plan is the host's, whole" % peer)
		var wg := gh.game as WorkoutGame
		assert_eq(wg.state.phases.size(), plan.phases.size(), "peer %d's view has the whole timeline" % peer)
		var rider: LocalRider = gh.local_riders[peer]
		assert_eq(rider.plan().phases.size(), plan.phases.size(), "and its governor rides it")
		assert_eq(gh.local_phase_state().index, host.tracker.index_of(peer), "in the host's phase")
	assert_eq(int(host.net.stats.get("oversize_dropped", 0)), 0, "nothing was dropped for size (plan parts, timeline parts)")
