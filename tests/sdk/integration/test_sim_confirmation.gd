extends GutTest
## W2 round 2 (docs/TRAINER.md known difference 7), end to end with the real LocalRider,
## SafetyGovernor, MockTrainer, WlNetSession and LoopbackTransport: a game sends
## {mode: SIM, haptic, duration_s <= 8} while a SIM block runs. The host's DirectiveRouter
## accepts it as a confirmation plus the haptic, and the rider's governor (the host's own rider
## directly, the client's through its telemetry ack) applies it the same way; the block keeps
## its own end. The riders skip the governor's warm-up (a profile setting), so the haptic is
## not dropped by BRIEF 4.6.8.

const FIXTURES := "res://tests/fixtures/games"
## Game ticks (0.05 s) of the requests: the block opens at 40 s (past the 30 s switch spacing
## from the session start) for 20 s, the haptic follows at 45 s.
const OPEN_TICK := 800
const HAPTIC_TICK := 900

var _reg: WlGameRegistry = null
var _runner: GameSimRunner = null
var _tmp: String = ""


func before_each() -> void:
	_tmp = Paths.make_temp_dir("wattlands_sim_confirm")
	Paths.set_override(_tmp)
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_reg.content_root = FIXTURES.path_join("_content")
	_reg.scan(FIXTURES.path_join("conform"))


func after_each() -> void:
	if _runner != null and is_instance_valid(_runner):
		_runner.cleanup()
		_runner.free()
	_runner = null
	_reg.clear()
	_reg.free()
	Paths.set_override("")
	_remove_tree(_tmp)


static func _rider(
	slot: PlayerSlot, profile: RiderProfile, spec: String, options: Dictionary
) -> LocalRider:
	var opts := options.duplicate()
	opts["skip_warmup"] = true
	opts["record"] = false
	var device := MockTrainer.from_spec(
		spec,
		slot.ftp,
		{"seed": 3 + slot.slot_index, "preferred_cadence_rpm": slot.preferred_cadence_rpm}
	)
	var r := LocalRider.new()
	r.setup(slot.peer_id, profile, slot, device, opts)
	if device.get_parent() == null:
		r.add_child(device)
	return r


func test_a_mode_sim_haptic_inside_a_running_block_is_confirmed_by_host_and_governor() -> void:
	_runner = GameSimRunner.new()
	assert_eq(
		(
			_runner
			. setup(
				{
					"game": "fx_conform",
					"content": "short",
					"players": 2,
					"seed": 5,
					"registry": _reg,
					"max_sim_seconds": 70.0,
					"rider_factory": _rider,
				}
			)
		),
		""
	)
	var results: Dictionary = {}
	_runner.host.game.set(
		"on_step",
		func(g: GameModule, frame: InputFrame) -> void:
			for peer: int in [1, 2]:
				if frame.tick == OPEN_TICK:
					results["open%d" % peer] = g.ctx.directives.request(
						peer,
						EffortDirective.from_dict(
							{
								"mode": "SIM",
								"duration_s": 20,
								"reason": "overdrive",
								"source": "test"
							}
						)
					)
				elif frame.tick == HAPTIC_TICK:
					results["hit%d" % peer] = g.ctx.directives.request(
						peer,
						EffortDirective.from_dict(
							{
								"mode": "SIM",
								"haptic": 2.0,
								"duration_s": 1.5,
								"reason": "hit",
								"source": "test"
							}
						)
					)
	)
	assert_eq(_runner.run_to_end(), "timeout")
	var rep := _runner.build_report()
	for peer: int in [1, 2]:
		var open: DirectiveResult = results["open%d" % peer]
		var hit: DirectiveResult = results["hit%d" % peer]
		assert_true(open.accepted, "peer %d: the block opens" % peer)
		assert_true(
			hit.accepted, "peer %d: the host accepts the confirmation (was sim_block_length)" % peer
		)
		var entry := _directive(rep, hit.id)
		assert_false(entry.is_empty(), "peer %d: the haptic is in the report" % peer)
		var applied: Variant = entry.get("applied")
		assert_true(applied is Dictionary, "peer %d: the governor reported it" % peer)
		if not (applied is Dictionary):
			continue
		var rec: Dictionary = applied
		assert_false(
			bool(rec["refused"]),
			"peer %d: the governor confirms too: %s" % [peer, str(rec.get("reason", ""))]
		)
		assert_eq(
			str(rec["applied"].get("mode", "")), Wl.SIM, "peer %d: applied as a confirmation" % peer
		)
		assert_almost_eq(
			float(rec["applied"].get("haptic_s", 0.0)), 1.5, 1e-6, "peer %d: with its haptic" % peer
		)
		assert_false(rec["applied"].has("sim_block"), "peer %d: no new block" % peer)
		var trace: Array = _trace(rep, peer)
		assert_eq(_mode_at(trace, 58.0), Wl.SIM, "peer %d: the block runs to its end" % peer)
		assert_eq(
			_mode_at(trace, 63.0),
			Wl.ERG,
			"peer %d: and ends on time (40 s + 20 s), never extended" % peer
		)
		assert_gt(
			_max_haptic(trace, 45.0, 47.0),
			0.0,
			"peer %d: the haptic reached the trainer grade" % peer
		)


func _directive(rep: Dictionary, id: int) -> Dictionary:
	for d: Dictionary in rep["directives"]:
		if int(d["id"]) == id:
			return d
	return {}


## The rider's 1 Hz trace: the host's own rider from the host report, a client's from its
## client report.
func _trace(rep: Dictionary, peer: int) -> Array:
	if peer == 1:
		return rep["trace"]["1"]
	for c: Dictionary in rep["clients"]:
		if int(c["peer"]) == peer:
			return c["trace"][str(peer)]
	return []


func _mode_at(trace: Array, t: float) -> String:
	var mode := ""
	for row: Dictionary in trace:
		if float(row["t"]) <= t + 1e-6:
			mode = str(row["mode"])
	return mode


func _max_haptic(trace: Array, from_t: float, to_t: float) -> float:
	var m := 0.0
	for row: Dictionary in trace:
		if float(row["t"]) >= from_t and float(row["t"]) <= to_t:
			m = maxf(m, absf(float(row["haptic"])))
	return m


static func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
