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
## Autopilot: the platform merges autopilot_intents() into the telemetry of bots and Autopilot
## riders; a human who is not flagged Autopilot but is still on the fallback (no deliberate
## intent yet) or on reserve (AFK, dropped) gets TankAutopilot's intents added in
## _collect_intents(), through the same ownership and 5-a-second filter. The first lever, aim,
## target, traverse, fire or latch intent of a human ends their fallback (ram and over never do,
## nor does anything tagged "auto").
##
## Prompts and toasts are per peer (TankCues): each peer raises only its own rider's, the host with
## ctx.local_peer, a client from apply_event / apply_snapshot, so none is ever broadcast.
##
## Not the module's (contracts/README.md "Module and view"): snapshot interpolation (TankView
## keeps a WorkoutSnapHistory-style buffer keyed by state.tick, fed from snapshot_applied), Tank
## Controls (they send their own intents through game.ctx.intents.send(TankIntents.*)) and
## TankAudio (TankView creates it and connects it to cue).

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
var _cues: TankCues = null
var _rescue: Dictionary = {}
var _afk: Dictionary = {}
var _group_phase: int = -1
var _finished: bool = false
var _hull_shown: int = -1


func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	_cues = TankCues.new(ctx)
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
		_cues.on_event(state, e)
	if inp.phase.index >= 0 and inp.phase.index != _group_phase:
		_group_phase = inp.phase.index
		phase_changed.emit(_group_phase)
	if not _finished and _all_in_cooldown(frame):
		_finished = true
		finished.emit(state.outcome if state.outcome != "" else TankIds.OUTCOME_COMPLETE)
	_cues.on_state(state)
	_feed_hull()
	if frame.tick % STATUS_EVERY_TICKS == 0:
		_feed_status()


## Called by the platform for bots and Autopilot riders only (its result is appended to their own
## intents). Bots always play it; a human only while on the fallback or on reserve.
func autopilot_intents(peer_id: int) -> Array:
	if state == null or not _autopilot_plays(peer_id):
		return []
	return TankAutopilot.intents(state, peer_id)


## True when the Autopilot plays this rider's choices now: a bot, a human who has not yet sent a
## deliberate intent (brief 2.5), or a station on reserve (AFK, dropped).
func _autopilot_plays(peer_id: int) -> bool:
	var r := state.rider(peer_id)
	if r == null:
		return false
	return r.is_bot or r.fallback or r.afk or bool(_afk.get(peer_id, false))


func on_rescue(peer_id: int, active: bool) -> void:
	_rescue[peer_id] = active


func on_afk(peer_id: int, afk: bool) -> void:
	_afk[peer_id] = afk


## Every rider's intents this tick, normalized, filtered to its engine's and rate-limited (5 a
## second per peer; the rules apply what passes in this same step, the platform having delivered
## it in this frame, the tick after it was sent). Only the peers of ctx.players are read. A
## human's first deliberate intent ends their Autopilot fallback.
func _collect_intents(frame: InputFrame) -> Dictionary:
	var out := {}
	for p in ctx.players:
		var tm := frame.telemetry(p.peer_id)
		var ps := frame.phase_of(p.peer_id)
		if tm == null or ps == null:
			continue
		var list: Array = tm.intents
		if not (p.autopilot or p.is_bot) and _autopilot_plays(p.peer_id):
			list = list + TankAutopilot.intents(state, p.peer_id)
		if list.is_empty():
			continue
		var engine := str(TankInputs.meta_of(plans.get(p.peer_id), ps.index).get("engine", ""))
		var accepted := _limiter.filter(p.peer_id, frame.tick, list, engine)
		out[p.peer_id] = accepted
		_end_fallback(p, accepted)
	return out


## A human who sends a deliberate intent (lever, aim, target, traverse, fire, latch; not ram, over
## or anything tagged auto) plays that station themselves from now on.
func _end_fallback(p: PlayerSlot, accepted: Array[Dictionary]) -> void:
	var r := state.rider(p.peer_id)
	if r == null or r.is_bot:
		return
	for n in accepted:
		if TankIntents.is_deliberate(n):
			r.fallback = false


func _all_in_cooldown(frame: InputFrame) -> bool:
	for p in ctx.players:
		var ps := frame.phase_of(p.peer_id)
		if ps == null or not ps.is_cooldown():
			return false
	return not ctx.players.is_empty()


## The teammate strip (engine icon, engine name, in band), 2 Hz (host).
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


## The hull HP readout, whenever the shown number changes.
func _feed_hull() -> void:
	var hp := ceili(state.hull.hp)
	if hp != _hull_shown:
		_hull_shown = hp
		ctx.hud.readout(TankHud.READOUT_HULL, str(hp))


# --- Every peer: input ------------------------------------------------------------------------


## The local rider's actions and gestures as intents for its current engine (brief 2.5, 2.6): a
## surge becomes only ram or over (the diesel and the Bulwark ram, which is also the boss dodge;
## the steam engine overpressures; the dynamo has no sprint), never fire or latch. Keys: up and
## down nudge the elevation, left and right cycle targets (the dynamo; on the Bulwark they step
## the lever and `item` cycles targets, `swap` steps it too), ability_1 rams or overpressures,
## ability_2 traverses, confirm fires, or latches (the steam engine; the Bulwark with an empty
## gun).
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


## Overwrites the replicated state (full snapshots, so a rejoin needs no special path), then raises
## this peer's own prompts from it.
func apply_snapshot(snap: Dictionary) -> void:
	if state == null:
		return
	var problem := TankSnapshotSchema.check(snap)
	if problem != "":
		push_warning("tank: snapshot: %s" % problem)
		# A broken layout would index past a row: skip it. Rows over the caps are well formed.
		if not problem.contains("more than"):
			return
	TankSnapshot.apply(state, snap)
	_feed_hull()
	_cues.on_state(state)
	snapshot_applied.emit(state.tick)


## Clients only: each event once, in the host's order, before that tick's snapshot. It raises this
## peer's own toasts and banners and tells the view and audio through `cue`; the snapshot that
## follows carries the state itself.
func apply_event(event: Dictionary) -> void:
	if state == null:
		return
	var e := TankEventCast.cast(event)
	_cues.on_event(state, e)
	cue.emit(str(e.get("type", "")), e)


## Moves only what the local rider controls ahead of the next snapshot: its watts, cadence and
## %FTP, its room's power and its glow (the in-band rule on its own telemetry). Everything else
## renders from snapshots.
func client_predict(_dt: float, local: Telemetry) -> void:
	if state == null or local == null:
		return
	var r := state.rider(ctx.local_peer)
	if r == null:
		return
	r.raw_w = local.power_w
	r.cadence_rpm = local.cadence_rpm
	r.ftp_pct = local.ftp_pct
	var st := state.station_of(r.slot)
	if st == null:
		return
	if not st.reserve and not st.unpowered:
		st.p_eff_w = local.p_eff_w
	var band := TankRules.in_band(state, _local_input(r, local, st), st)
	r.in_band = band
	st.in_band = band


## The in-band rule's input for the local rider from its own telemetry and the replicated state.
func _local_input(r: TankRiderState, local: Telemetry, st: TankStationState) -> TankRiderInput:
	var ri := TankRiderInput.new()
	ri.peer = r.peer
	ri.slot = r.slot
	ri.engine = r.engine
	ri.phase_kind = state.seg.kind
	ri.ftp = r.ftp
	ri.ftp_verified = r.ftp_verified
	ri.power_w = local.power_w
	ri.p_eff_w = local.p_eff_w
	ri.cadence_rpm = local.cadence_rpm
	ri.ftp_pct = local.ftp_pct
	ri.mode = local.mode
	ri.applied_target_w = float(local.applied_target_w)
	ri.rescue = local.rescue or r.rescue
	ri.afk = r.afk or st.reserve
	ri.connected = r.connected
	return ri


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


## Grade, score, per-rider stats, XP and unlocks (brief 2.8). Values under `stats` and `team` are
## numbers or strings (the results screen prints them as they are).
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
		var unlocks: Array = []
		unlocks.append_array(TankScore.unlocks(state, grade, done))
		row["unlocks"] = unlocks
	res.grade = grade
	res.score = float(sum["score"])
	res.team = _team_stats()
	match state.outcome:
		TankIds.OUTCOME_VICTORY:
			res.summary_key = "TANK_RESULT_VICTORY"
		TankIds.OUTCOME_WITHDRAWN:
			res.summary_key = "TANK_RESULT_WITHDRAWN"
		TankIds.OUTCOME_COMPLETE:
			res.summary_key = "TANK_RESULT_DRILL"
		_:
			# A ride cut short (paused, timed out, left early) has no outcome yet: no title.
			res.summary_key = ""
	return res


## The crew's values in the results screen's order: the mission, hull HP at the end of each
## segment, breakdowns, overruns and kills (light/medium/destroyer/dug-in/heavy/Behemoth).
func _team_stats() -> Dictionary:
	var sc := state.score
	var outcome_key := ""
	match state.outcome:
		TankIds.OUTCOME_VICTORY:
			outcome_key = "TANK_OUTCOME_VICTORY"
		TankIds.OUTCOME_WITHDRAWN:
			outcome_key = "TANK_OUTCOME_WITHDRAWN"
		TankIds.OUTCOME_COMPLETE:
			outcome_key = "TANK_RESULT_DRILL"
	var hp: PackedStringArray = []
	for v in sc.hp_by_segment:
		hp.append(str(v))
	var kills: PackedStringArray = []
	for code in range(1, sc.kills.size()):
		kills.append(str(sc.kills[code]))
	return {
		"TANK_TEAM_OUTCOME": ctx.strings.t(outcome_key) if outcome_key != "" else "-",
		"TANK_TEAM_HP": "/".join(hp),
		"TANK_TEAM_BREAKDOWNS": sc.breakdowns,
		"TANK_TEAM_OVERRUNS": sc.overruns,
		"TANK_TEAM_KILLS": "/".join(kills),
	}


## One rider's results stats, keyed by their strings (the results screen's order).
static func _rider_stats(r: TankRiderState) -> Dictionary:
	var shells: PackedStringArray = []
	for n in r.shells_by_type:
		shells.append(str(n))
	return {
		"TANK_STAT_DIESEL_S": roundi(r.engine_s[0]),
		"TANK_STAT_DYNAMO_S": roundi(r.engine_s[1]),
		"TANK_STAT_STEAM_S": roundi(r.engine_s[2]),
		"TANK_STAT_BULWARK_S": roundi(r.engine_s[3]),
		"TANK_STAT_RAMS": r.rams,
		"TANK_STAT_DODGES": r.dodges,
		"TANK_STAT_BERM": roundi(r.berm_absorbed),
		"TANK_STAT_SHOTS": r.shots,
		"TANK_STAT_HITS": r.hits,
		"TANK_STAT_ACCURACY": roundi(100.0 * r.hits / r.shots) if r.shots > 0 else 0,
		"TANK_STAT_SHELLS": "/".join(shells),
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
