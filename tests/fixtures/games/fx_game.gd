extends GameModule
## Fixture GameModule for the sdk-runtime tests (not a real game; lives outside src/games so
## the registry never lists it). Every manifest under tests/fixtures/games/ points its entry
## here. It exercises the SDK surface and records what the platform called, so tests can
## assert the GameHost's behaviour. Snapshots use floats and strings only, so their JSON
## round trip needs no int_fields (W1: Protocol is still a stub).
##
## Contents (plans per rider; every plan opens inside the warm-up limits):
##   "tiny":  WARMUP ERG 50% 2 s (lap), WORK ERG 60% 3 s range [55, 65],
##            FREE SIM game 30 s, WORK ERG 60% open-ended min 2 s max 6 s range [55, 65].
##   "short": WARMUP ERG 50 -> 65% 300 s (lap), WORK ERG 75% 120 s (lap).
##   "split": per rider: slot 0 gets "tiny"; other slots get WARMUP 50% 4 s, WORK 60% 3 s.
##   "bad":   WORK ERG 90% 60 s at the start (breaks the warm-up rule).

## Test hook: called at the end of every sim_step(dt, frame) with (self, frame).
var on_step: Callable = Callable()
## Test knobs: results() returns no rows ("empty") or only the first rider's ("partial");
## snapshot() carries a string of snapshot_pad characters.
var results_mode: String = ""
var snapshot_pad: int = 0
## Test knob: HudSpec.help entries.
var help_entries: Array[Dictionary] = []
## Recorded calls.
var configure_count: int = 0
var steps: int = 0
var dts: Array[float] = []
var frames_seen: Array[Dictionary] = []
var keep_frames: bool = false
var rescue_log: Array = []
var afk_log: Array = []
var intents_seen: Array = []
var local_intent_calls: Array = []
var events_applied: Array = []
var snapshots_applied: int = 0
var last_snapshot_applied: Dictionary = {}
var predicts: int = 0
var results_count: int = 0
var progress_calls: int = 0
var phases_seen: Dictionary = {}
var cooldown_steps: int = 0
var autopilot_calls: Dictionary = {}
## Game state (host).
var distance: Dictionary = {}
var events_sent: int = 0
var content: Variant = null


func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	configure_count += 1
	if FileAccess.file_exists(ctx.content_dir.path_join("levels.json")):
		content = ctx.load_content_json("levels.json")
	for p in ctx.players:
		distance[p.peer_id] = 0.0


func build_effort_plans() -> Dictionary:
	var out := {}
	for p in ctx.players:
		out[p.peer_id] = _plan_for(p)
	return out


func _plan_for(p: PlayerSlot) -> EffortPlan:
	match ctx.content_id:
		"short":
			return (
				EffortPlan
				. of(
					[
						PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up").with_ramp(65).with_lap(),
						PlanPhase.erg(Wl.WORK, 75, 120, "Push").with_lap(),
					]
				)
			)
		"split":
			if p.slot_index != 0:
				return (
					EffortPlan
					. of(
						[
							PlanPhase.erg(Wl.WARMUP, 50, 4, "Warm-up").with_lap(),
							PlanPhase.erg(Wl.WORK, 60, 3, "Push"),
						]
					)
				)
			return _tiny()
		"bad":
			return EffortPlan.of([PlanPhase.erg(Wl.WORK, 90, 60, "Too hard")])
	return _tiny()


func _tiny() -> EffortPlan:
	return (
		EffortPlan
		. of(
			[
				PlanPhase.erg(Wl.WARMUP, 50, 2, "Warm-up").with_lap(),
				PlanPhase.erg(Wl.WORK, 60, 3, "Push").with_range(55, 65),
				PlanPhase.sim(Wl.FREE, Wl.GRADE_GAME, 30, "Climb"),
				PlanPhase.erg(Wl.WORK, 60, 0, "Hold").with_range(55, 65).with_open(2, 6),
			]
		)
	)


func sim_step(dt: float, frame: InputFrame) -> void:
	steps += 1
	dts.append(dt)
	for peer: int in frame.players.keys():
		var tm: Telemetry = frame.players[peer]
		distance[peer] = float(distance.get(peer, 0.0)) + tm.p_eff_w * dt / 100.0
		for i: Variant in tm.intents:
			intents_seen.append({"tick": frame.tick, "peer": peer, "intent": i})
	for peer: int in frame.phase.keys():
		var ps: PhaseState = frame.phase[peer]
		if not phases_seen.has(peer):
			phases_seen[peer] = []
		var seen: Array = phases_seen[peer]
		if seen.is_empty() or int(seen[seen.size() - 1]) != ps.index:
			seen.append(ps.index)
	var any_ps: PhaseState = frame.phase.values()[0] if not frame.phase.is_empty() else null
	if any_ps != null and any_ps.is_cooldown():
		cooldown_steps += 1
	if steps % 20 == 0:
		events_sent += 1
		send_event({"type": "tick", "n": float(events_sent)})
	if keep_frames:
		frames_seen.append(
			{
				"tick": frame.tick,
				"t": frame.t,
				"players": frame.players.duplicate(),
				"phase": frame.phase.duplicate()
			}
		)
	if on_step.is_valid():
		on_step.call(self, frame)


func autopilot_intents(peer_id: int) -> Array:
	autopilot_calls[peer_id] = int(autopilot_calls.get(peer_id, 0)) + 1
	if steps > 0 and steps % 40 == 0:
		return [{"k": "auto", "peer": float(peer_id)}]
	return []


func on_rescue(peer_id: int, active: bool) -> void:
	rescue_log.append([peer_id, active])


func on_afk(peer_id: int, afk: bool) -> void:
	afk_log.append([peer_id, afk])


func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	var out: Array = []
	if not actions.is_empty() or not gestures.is_empty():
		local_intent_calls.append(
			{"actions": actions.duplicate(), "gestures": gestures.duplicate()}
		)
	for g in gestures:
		if g == Wl.G_SURGE:
			out.append({"k": "boost", "gesture": "surge"})
	for a in actions:
		if a == &"confirm":
			out.append({"k": "confirm"})
	return out


func snapshot() -> Dictionary:
	var d := {}
	for peer: Variant in distance.keys():
		d[str(peer)] = snappedf(float(distance[peer]), 0.001)
	var snap := {"steps": float(steps), "d": d, "ev": float(events_sent), "name": "fx"}
	if snapshot_pad > 0:
		snap["pad"] = "x".repeat(snapshot_pad)
	return snap


func apply_snapshot(snap: Dictionary) -> void:
	snapshots_applied += 1
	last_snapshot_applied = snap


func apply_event(event: Dictionary) -> void:
	events_applied.append(event)


func client_predict(_dt: float, _local: Telemetry) -> void:
	predicts += 1


func make_view() -> Node:
	if str(ctx.manifest.get("presentation", "2d")) == "3d":
		return Node3D.new()
	return Node2D.new()


func hud_spec() -> HudSpec:
	var spec := HudSpec.new().add(HudSpec.TIMELINE, HudSpec.TOP_LEFT).add(
		HudSpec.POWER_GAUGE, HudSpec.BOTTOM_LEFT
	)
	spec.help = help_entries.duplicate(true)
	return spec


func results() -> GameResults:
	results_count += 1
	if results_mode == "empty":
		var bare := GameResults.new()
		bare.grade = "C"
		return bare
	if results_mode == "partial":
		var part := GameResults.new()
		part.grade = "A"
		part.rows.append(
			{"peer_id": ctx.players[0].peer_id, "kj": 999.0, "stats": {"custom": "yes"}}
		)
		return part
	var r := GameResults.from_stats(ctx.stats, ctx.players)
	r.grade = "B"
	r.score = float(steps)
	for row in r.rows:
		row["xp"] = 10
		(row["stats"] as Dictionary)["distance"] = snappedf(
			float(distance.get(int(row["peer_id"]), 0.0)), 0.001
		)
	return r


func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	progress_calls += 1
	var row := res.row(ctx.local_peer)
	progress.add("xp", float(row.get("xp", 0)))
	if not progress.has("badge"):
		progress.set_value("badge", true)
		return ["fx_badge"]
	return []
