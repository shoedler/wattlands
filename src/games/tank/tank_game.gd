class_name TankGame
extends GameModule
## Diesel Domestiques' GameModule (docs/games/tank.md; GAME_SDK 4). Owner: module.
##
## Host / SOLO, every tick (sim_step): intents are normalized, ownership-filtered and rate-limited
## (TankIntentLimiter, 5 a second per peer, only peers in ctx.players) -> TankInputs.from_frame ->
## TankRules.step (the events) -> TankDirector.step (every ctx.directives call and the power band)
## -> send_event for each event -> phase_changed with the group's phase (the lowest index any
## rider is in) -> finished(outcome) once every rider is in the cool-down. Clients: apply_snapshot
## and apply_event rebuild the state; client_predict moves the local rider's own room.
##
## G0 wrote this working skeleton; G1 (module) adds the Autopilot, prompts per peer, toasts and
## e2e_check.mjs, keeping the flow above. Not the module's (contracts/README.md "Module and
## view"): snapshot interpolation (TankView keeps a WorkoutSnapHistory-style buffer keyed by
## state.tick, fed from snapshot_applied), Tank Controls (they send their own intents through
## game.ctx.intents.send(TankIntents.*)) and TankAudio (TankView creates it and connects it to cue).

## Every event, raised like its effects: the host where it sends the event, clients in
## apply_event. The view and audio listen here.
signal cue(kind: String, data: Dictionary)
## A client applied a snapshot (state now holds the host's tick `tick`): the view records it in
## its interpolation history. Clients only; the host's view reads the live state.
signal snapshot_applied(tick: int)

## The host refreshes the teammate strip this often (ticks; 2 Hz).
const STATUS_EVERY_TICKS := 10
## Session ids kept in the progress file (a restarted client sees the same results twice).
const PROGRESS_SESSIONS_KEPT := 32

var content: TankContent = null
var state: TankState = null
## peer -> EffortPlan built here (host / SOLO).
var plans: Dictionary = {}
var director: TankDirector = null

var _limiter := TankIntentLimiter.new()
var _rescue: Dictionary = {}
var _afk: Dictionary = {}
var _group_phase: int = -1
var _finished: bool = false


func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	content = TankContent.load_for(ctx)
	if not content.ok():
		var msg := "tank: content %s: %s" % [ctx.content_id, "; ".join(content.errors)]
		if ctx.is_authority():
			push_error(msg)
		else:
			push_warning(msg)
		return
	var rotation := bool(ctx.options.get("rotation", true)) and content.mission_rotates()
	var rng: RandomNumberGenerator = ctx.rng if ctx.is_authority() else null
	state = TankRules.new_state(content, ctx.players, ctx.content_id, rotation, rng)


func build_effort_plans() -> Dictionary:
	if state == null:
		return {}
	plans = TankPlanBuilder.build_all(content, ctx.players, state.rotation)
	director = TankDirector.new(ctx, content, plans)
	return plans


# --- Host / SOLO ----------------------------------------------------------------------------


func sim_step(dt: float, frame: InputFrame) -> void:
	if state == null:
		return
	var inp := TankInputs.from_frame(
		frame, ctx.players, plans, _collect_intents(frame), _rescue, _afk
	)
	var events := TankRules.step(state, inp, dt)
	if director != null:
		director.step(state, inp, events)
	for e in events:
		send_event(e)
		cue.emit(str(e["type"]), e)
	if inp.phase.index >= 0 and inp.phase.index != _group_phase:
		_group_phase = inp.phase.index
		phase_changed.emit(_group_phase)
	if not _finished and _all_in_cooldown(frame):
		_finished = true
		finished.emit(state.outcome if state.outcome != "" else TankIds.OUTCOME_COMPLETE)
	if frame.tick % STATUS_EVERY_TICKS == 0:
		_feed_status()


func autopilot_intents(peer_id: int) -> Array:
	return TankAutopilot.intents(state, peer_id) if state != null else []


func on_rescue(peer_id: int, active: bool) -> void:
	_rescue[peer_id] = active


func on_afk(peer_id: int, afk: bool) -> void:
	_afk[peer_id] = afk


## Every rider's intents this tick, normalized, filtered to its engine's and rate-limited.
func _collect_intents(frame: InputFrame) -> Dictionary:
	var out := {}
	for p in ctx.players:
		var tm := frame.telemetry(p.peer_id)
		var ps := frame.phase_of(p.peer_id)
		if tm == null or ps == null or tm.intents.is_empty():
			continue
		var engine := str(TankInputs.meta_of(plans.get(p.peer_id), ps.index).get("engine", ""))
		out[p.peer_id] = _limiter.filter(p.peer_id, frame.tick, tm.intents, engine)
	return out


func _all_in_cooldown(frame: InputFrame) -> bool:
	for p in ctx.players:
		var ps := frame.phase_of(p.peer_id)
		if ps == null or not ps.is_cooldown():
			return false
	return not ctx.players.is_empty()


## The teammate strip (engine icon, engine name, in band) and the hull readout, 2 Hz.
func _feed_status() -> void:
	for r in state.riders:
		if r.engine == "":
			continue
		var status := {
			"in_band": r.in_band,
			"icon": str(TankIds.ENGINE_ICONS.get(r.engine, "")),
			"text": ctx.strings.t(str(TankIds.ENGINE_LABELS.get(r.engine, "")))
		}
		ctx.hud.teammate_status(r.peer, status)
	ctx.hud.readout(TankHud.READOUT_HULL, str(ceili(state.hull.hp)))


# --- Every peer: input ------------------------------------------------------------------------


## The local rider's actions and gestures as intents for its current engine (brief 2.5, 2.6): a
## surge becomes only ram or over, never fire or latch.
func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	if state == null:
		return []
	var r := state.rider(ctx.local_peer)
	if r == null:
		return []
	var out: Array = []
	var engine := r.engine
	var surge := gestures.has(Wl.G_SURGE)
	if surge or actions.has(&"ability_1"):
		var via := TankIds.VIA_SURGE if surge else TankIds.VIA_ACTION
		if engine == TankIds.ENGINE_STEAM:
			out.append(TankIntents.make(TankIds.INTENT_OVER, via))
		elif engine == TankIds.ENGINE_DIESEL or engine == TankIds.ENGINE_BULWARK:
			out.append(TankIntents.make(TankIds.INTENT_RAM, via))
	if engine == TankIds.ENGINE_DYNAMO or engine == TankIds.ENGINE_BULWARK:
		out.append_array(_gunner_intents(actions))
	if engine == TankIds.ENGINE_DYNAMO:
		if actions.has(&"left"):
			out.append(TankIntents.target(TankIds.TARGET_PREV))
		if actions.has(&"right"):
			out.append(TankIntents.target(TankIds.TARGET_NEXT))
	if engine == TankIds.ENGINE_BULWARK:
		out.append_array(_lever_intents(actions))
	if actions.has(&"confirm") and not surge:
		match engine:
			TankIds.ENGINE_DYNAMO:
				out.append(TankIntents.make(TankIds.INTENT_FIRE))
			TankIds.ENGINE_STEAM:
				out.append(TankIntents.make(TankIds.INTENT_LATCH))
			TankIds.ENGINE_BULWARK:
				var loaded := state.hull.loaded != TankIds.SHELL_NONE
				var kind := TankIds.INTENT_FIRE if loaded else TankIds.INTENT_LATCH
				out.append(TankIntents.make(kind))
	return out


func _gunner_intents(actions: Array[StringName]) -> Array:
	var out: Array = []
	if actions.has(&"up"):
		out.append(TankIntents.aim(TankIds.AIM_UP))
	if actions.has(&"down"):
		out.append(TankIntents.aim(TankIds.AIM_DOWN))
	if actions.has(&"ability_2"):
		out.append(TankIntents.make(TankIds.INTENT_TRAVERSE))
	return out


func _lever_intents(actions: Array[StringName]) -> Array:
	var out: Array = []
	if actions.has(&"item"):
		out.append(TankIntents.target(TankIds.TARGET_NEXT))
	if actions.has(&"swap"):
		out.append(TankIntents.lever(TankIds.LEVER_TO_NEXT))
	if actions.has(&"left"):
		out.append(TankIntents.lever(TankIds.LEVER_TO_LEFT))
	if actions.has(&"right"):
		out.append(TankIntents.lever(TankIds.LEVER_TO_RIGHT))
	return out


# --- Net ---------------------------------------------------------------------------------------


func snapshot() -> Dictionary:
	return TankSnapshot.encode(state) if state != null else {}


func apply_snapshot(snap: Dictionary) -> void:
	if state == null:
		return
	TankSnapshot.apply(state, snap)
	ctx.hud.readout(TankHud.READOUT_HULL, str(ceili(state.hull.hp)))
	snapshot_applied.emit(state.tick)


func apply_event(event: Dictionary) -> void:
	cue.emit(str(event.get("type", "")), event)


func client_predict(_dt: float, local: Telemetry) -> void:
	if state == null or local == null:
		return
	var r := state.rider(ctx.local_peer)
	if r != null:
		r.raw_w = local.power_w
		r.cadence_rpm = local.cadence_rpm
		r.ftp_pct = local.ftp_pct


func int_fields() -> Dictionary:
	var out := {"snapshot": TankSnapshotSchema.INT_PATHS.duplicate()}
	for k: String in TankEvents.INT_FIELDS:
		out[k] = (TankEvents.INT_FIELDS[k] as Array).duplicate()
	return out


# --- Presentation --------------------------------------------------------------------------------


func make_view() -> Node:
	var view := TankView.new()
	view.game = self
	return view


func hud_spec() -> HudSpec:
	return TankHud.spec(self)


# --- Results and progress ---------------------------------------------------------------------------


## Grade, score, per-rider stats, XP and unlocks (brief 2.8).
func results() -> GameResults:
	var res := GameResults.from_stats(ctx.stats, ctx.players)
	if state == null:
		res.grade = "D"
		return res
	var sum := TankScore.summary(state)
	var grade := str(sum["grade"])
	var done := state.in_cooldown()
	for row in res.rows:
		var r := state.rider(int(row["peer_id"]))
		if r == null:
			continue
		row["time_in_band_s"] = r.band_s
		row["time_in_band_pct"] = 100.0 * r.band_s / r.work_s if r.work_s > 0.0 else 0.0
		row["stats"].merge(_rider_stats(r), true)
		row["xp"] = TankScore.xp(content, float(row.get("kj", 0.0)), grade)
		row["unlocks"] = TankScore.unlocks(state, grade, done)
	res.grade = grade
	res.score = float(sum["score"])
	res.team = {
		"TANK_TEAM_OUTCOME": state.outcome,
		"TANK_TEAM_HP": state.score.hp_by_segment.duplicate(),
		"TANK_TEAM_BREAKDOWNS": state.score.breakdowns,
		"TANK_TEAM_OVERRUNS": state.score.overruns,
		"TANK_TEAM_KILLS": state.score.kills.duplicate(),
	}
	match state.outcome:
		TankIds.OUTCOME_VICTORY:
			res.summary_key = "TANK_RESULT_VICTORY"
		TankIds.OUTCOME_WITHDRAWN:
			res.summary_key = "TANK_RESULT_WITHDRAWN"
		_:
			res.summary_key = "TANK_RESULT_DRILL"
	return res


## One rider's results stats, keyed by their strings (the results screen's order).
static func _rider_stats(r: TankRiderState) -> Dictionary:
	return {
		"TANK_STAT_DIESEL_S": roundi(r.engine_s[0]),
		"TANK_STAT_DYNAMO_S": roundi(r.engine_s[1]),
		"TANK_STAT_STEAM_S": roundi(r.engine_s[2]),
		"TANK_STAT_BULWARK_S": roundi(r.engine_s[3]),
		"TANK_STAT_RAMS": r.rams,
		"TANK_STAT_BERM": roundi(r.berm_absorbed),
		"TANK_STAT_SHOTS": r.shots,
		"TANK_STAT_HITS": r.hits,
		"TANK_STAT_ACCURACY": roundi(100.0 * r.hits / r.shots) if r.shots > 0 else 0,
		"TANK_STAT_SHELLS": r.shells_by_type.duplicate(),
	}


## Every peer, once per session: the local rider's XP and new unlocks into `progress`.
func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	var row := res.row(ctx.local_peer)
	if row.is_empty():
		return []
	var seen: Array = progress.get_value("sessions", [])
	if res.session_id != "" and seen.has(res.session_id):
		return []
	if res.session_id != "":
		seen.append(res.session_id)
		progress.set_value("sessions", seen.slice(maxi(0, seen.size() - PROGRESS_SESSIONS_KEPT)))
	progress.add("xp", float(row.get("xp", 0)))
	var held: Array = progress.get_value("unlocks", [])
	var fresh: Array = []
	for u: Variant in row.get("unlocks", []):
		if not held.has(u) and not fresh.has(u):
			fresh.append(u)
	progress.set_value("unlocks", held + fresh)
	return fresh
