class_name TankGame
extends GameModule
## Diesel Domestiques' GameModule (docs/games/tank.md; GAME_SDK 4). Owner: module.
##
## Host / SOLO, every tick (sim_step): intents are normalized, ownership-filtered and rate-limited
## (TankIntentLimiter, 5 a second per peer, only peers in ctx.players) -> TankInputs.from_frame ->
## TankRules.step (the events) -> TankDirector.step (every ctx.directives call and the power band)
## -> send_event for each event -> phase_changed with the group's phase (v3: the lowest segment
## any rider is in; a seat switch splits a rider's phase, TankSeatPlan) -> finished(outcome) once
## every rider is in the cool-down. `plans` is shared with the director, which splices every
## accepted seat replan into it. Clients: apply_snapshot
## and apply_event rebuild the state; client_predict moves the local rider's own room.
##
## Autopilot: the platform merges autopilot_intents() into the telemetry of bots and Autopilot
## riders; a human who is not flagged Autopilot but is still on the fallback (no deliberate
## intent yet) or on reserve (AFK, dropped) gets TankAutopilot's intents added in
## _collect_intents(), through the same ownership and 5-a-second filter. The first aim, target,
## fire, latch, turn or seat intent of a human ends their fallback (over never does, nor does
## anything tagged "auto"); while on the fallback the Autopilot also seats them (v3 automatic
## seating, TankAutopilot.seat_intents). v4: bots seat themselves through TankBots.
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

## Session ids kept in the progress file (a restarted client sees the same results twice).
const PROGRESS_SESSIONS_KEPT := 32

## The kill counts on the results, in the order TANK_TEAM_KILLS and TANK_TEAM_ROAM_KILLS name them.
const TEAM_KILL_CODES: Array[int] = [1, 2, 3, 5, TankIds.BOSS_CODE, 7, 8]

var content: TankContent = null
var state: TankState = null
## peer -> EffortPlan built here (host / SOLO).
var plans: Dictionary = {}
var director: TankDirector = null
## v3: the local rider's seat picker (TankHudSeatPicker; the seat panel draws its highlight).
var seat_picker := TankHudSeatPicker.new()

var _limiter := TankIntentLimiter.new()
var _cues: TankCues = null
var _rescue: Dictionary = {}
var _afk: Dictionary = {}
var _group_phase: int = -1
var _finished: bool = false


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
	var rng: RandomNumberGenerator = ctx.rng if ctx.is_authority() else null
	state = TankRules.new_state(content, ctx.players, ctx.content_id, rng)
	state.difficulty = TankDifficulty.resolve(
		ctx.options.get("difficulty", TankIds.DIFF_AUTO), content
	)


func build_effort_plans() -> Dictionary:
	if state == null:
		return {}
	plans = TankPlanBuilder.build_all(content, ctx.players)
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


## A human who sends a deliberate intent (aim, target, fire, latch, turn, seat; not over or anything
## tagged auto) plays that station themselves from now on.
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


# --- Every peer: input ------------------------------------------------------------------------


## The local rider's actions and gestures as intents for its current seat (brief 2.5, 2.6): a
## surge becomes only over (the Loader overpressures; "Surge to evade" needs no intent, the sprint
## itself is the input), never fire or latch. Keys: up and down nudge the elevation, swap (R / LB)
## cycles targets, confirm fires (the Gun); ability_1 overpressures, confirm latches (the Loader).
## In free roam the Drive rider turns the tank round: ability_1 or confirm.
## 0.3.1: the seat picker (TankHudSeatPicker) takes its keys first: left / right on every seat pick
## an empty seat, confirm sits there (at once, no seat lock), back closes it.
func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	if state == null:
		return []
	var r := state.rider(ctx.local_peer)
	if r == null:
		return []
	var seat := seat_picker.feed(state, r, actions)
	actions = TankHudSeatPicker.without(actions, seat["taken"])
	var out: Array = seat["intents"]
	var engine := r.engine
	var surge := gestures.has(Wl.G_SURGE)
	if (surge or actions.has(&"ability_1")) and engine == TankIds.ENGINE_STEAM:
		var via := TankIds.VIA_SURGE if surge else TankIds.VIA_ACTION
		out.append(TankIntents.make(TankIds.INTENT_OVER, via))
	if engine == TankIds.ENGINE_DYNAMO:
		out.append_array(_gunner_intents(actions))
		if actions.has(&"swap"):
			out.append(TankIntents.target(TankIds.TARGET_NEXT))
	if state.roam.active and not surge:
		var drives := engine == TankIds.ENGINE_DIESEL
		var key := actions.has(&"ability_1") or actions.has(&"confirm")
		if drives and key:
			out.append(TankIntents.make(TankIds.INTENT_TURN))
	if actions.has(&"confirm") and not surge:
		match engine:
			TankIds.ENGINE_DYNAMO:
				out.append(TankIntents.make(TankIds.INTENT_FIRE))
			TankIds.ENGINE_STEAM:
				out.append(TankIntents.make(TankIds.INTENT_LATCH))
	return out


func _gunner_intents(actions: Array[StringName]) -> Array:
	var out: Array = []
	if actions.has(&"up"):
		out.append(TankIntents.aim(TankIds.AIM_UP))
	if actions.has(&"down"):
		out.append(TankIntents.aim(TankIds.AIM_DOWN))
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
## %FTP, its effort target (TankRules.target_pct on its own telemetry, when it has one), its room's
## power and its glow (the in-band rule on its own telemetry). Everything else renders from
## snapshots.
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
	var ri := _local_input(r, local, st)
	var band := TankRules.in_band(state, ri, st)
	r.in_band = band
	st.in_band = band
	var target := TankRules.target_pct(state, ri, st)
	if target > 0.0:
		r.target_pct = target


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
	ri.phase_mode = local.mode
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
	if state.roam.active:
		return _roam_results(res)
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
			# A ride cut short (paused, timed out, left early) has no outcome yet.
			res.summary_key = "TANK_RESULT_ABANDONED"
	res.ride_tag = _ride_tag()
	res.ride_lines = _team_ride_lines(res)
	for row in res.rows:
		var r := state.rider(int(row["peer_id"]))
		if r != null:
			var own := res.ride_lines.duplicate()
			own.append_array(_rider_ride_lines(r))
			row["ride_lines"] = own
	return res


## The Strava title tag (GameResults.ride_tag): the mission and how it ended.
func _ride_tag() -> String:
	var tx := ctx.strings
	var key := "TANK_MISSION_" + ctx.content_id.to_upper()
	var mission := tx.t(key) if tx.has(key) else ctx.content_id
	var tag_key: String
	match state.outcome:
		TankIds.OUTCOME_VICTORY:
			tag_key = "TANK_RIDE_WON"
		TankIds.OUTCOME_WITHDRAWN:
			tag_key = "TANK_RIDE_LOST"
		TankIds.OUTCOME_COMPLETE:
			tag_key = "TANK_RIDE_DRILL"
		_:
			tag_key = "TANK_RIDE_EARLY"
	return tx.t(tag_key, [mission])


## The crew's Strava description lines (GameResults.ride_lines): score and grade, kills,
## breakdowns, evades and (v4) the tanks lost, when any was.
func _team_ride_lines(res: GameResults) -> Array[String]:
	var sc := state.score
	var kills := 0
	for code in range(1, sc.kills.size()):
		kills += int(sc.kills[code])
	var tx := ctx.strings
	var lines: Array[String] = [
		tx.t("TANK_RIDE_SCORE", [roundi(res.score), res.grade]),
		tx.t("TANK_RIDE_KILLS", [kills]),
		tx.t("TANK_RIDE_BREAKDOWNS", [sc.breakdowns]),
		tx.t("TANK_RIDE_EVADES", [sc.evades_ok, sc.evades_tried]),
	]
	if sc.losses > 0:
		lines.append(tx.t("TANK_RIDE_LOSSES", [sc.losses]))
	return lines


## One rider's own Strava lines (row["ride_lines"] after the crew's): gunnery and bow-gun hits.
func _rider_ride_lines(r: TankRiderState) -> Array[String]:
	var tx := ctx.strings
	return [
		tx.t("TANK_RIDE_GUNNERY", [r.shots, r.hits]),
		tx.t("TANK_RIDE_BOW", [r.bow_hits]),
	]


## The difficulty's name for the results screen.
func _difficulty_label() -> String:
	return ctx.strings.t("TANK_DIFF_" + state.difficulty.to_upper())


## The crew's values in the results screen's order: the mission, (v4) the difficulty and tanks lost,
## hull HP at the end of each segment, breakdowns, overruns, kills by kind (TEAM_KILL_CODES), evades
## (successful/tried) and bow-gun hits.
func _team_stats() -> Dictionary:
	var sc := state.score
	var outcome_key: String
	match state.outcome:
		TankIds.OUTCOME_VICTORY:
			outcome_key = "TANK_OUTCOME_VICTORY"
		TankIds.OUTCOME_WITHDRAWN:
			outcome_key = "TANK_OUTCOME_WITHDRAWN"
		TankIds.OUTCOME_COMPLETE:
			outcome_key = "TANK_RESULT_DRILL"
		_:
			outcome_key = "TANK_RESULT_ABANDONED"
	var hp: PackedStringArray = []
	for v in sc.hp_by_segment:
		hp.append(str(v))
	var kills: PackedStringArray = []
	for code: int in TEAM_KILL_CODES:
		kills.append(str(sc.kills[code]))
	return {
		"TANK_TEAM_OUTCOME": ctx.strings.t(outcome_key),
		"TANK_TEAM_DIFFICULTY": _difficulty_label(),
		"TANK_TEAM_LOSSES": sc.losses,
		"TANK_TEAM_HP": "/".join(hp),
		"TANK_TEAM_BREAKDOWNS": sc.breakdowns,
		"TANK_TEAM_OVERRUNS": sc.overruns,
		"TANK_TEAM_KILLS": "/".join(kills),
		"TANK_TEAM_EVADES": "%d/%d" % [sc.evades_ok, sc.evades_tried],
		"TANK_TEAM_BOW_HITS": sc.bow_hits,
	}


## Free roam's results (brief 2.8): the crew's points and the grade by points per WORK minute
## (TankRoam.grade_of), kills by type, distance, evades and breakdowns; XP as for missions; unlocks
## as for missions (the Behemoth's never comes in a roam); ride_tag "Free Roam N min".
func _roam_results(res: GameResults) -> GameResults:
	var per_min := TankRoam.points_per_min(state)
	var grade := TankRoam.grade_of(content, per_min)
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
	res.score = float(state.roam.points)
	res.team = _roam_team_stats(per_min)
	var timed_out := state.outcome == TankIds.OUTCOME_TIME_UP
	res.summary_key = "TANK_RESULT_TIME_UP" if timed_out else "TANK_RESULT_ABANDONED"
	var tx := ctx.strings
	res.ride_tag = tx.t("TANK_RIDE_ROAM", [content.roam_minutes()])
	var sc := state.score
	var lines: Array[String] = [
		tx.t("TANK_RIDE_POINTS", [state.roam.points, grade]),
		tx.t("TANK_RIDE_KILLS", [_kill_total()]),
		tx.t("TANK_RIDE_DISTANCE", ["%.1f" % (state.roam.odo_m / 1000.0)]),
		tx.t("TANK_RIDE_EVADES", [sc.evades_ok, sc.evades_tried]),
		tx.t("TANK_RIDE_BREAKDOWNS", [sc.breakdowns]),
	]
	if sc.losses > 0:
		lines.append(tx.t("TANK_RIDE_LOSSES", [sc.losses]))
	res.ride_lines = lines
	for row in res.rows:
		var r2 := state.rider(int(row["peer_id"]))
		if r2 != null:
			var own := res.ride_lines.duplicate()
			own.append_array(_rider_ride_lines(r2))
			row["ride_lines"] = own
	return res


func _kill_total() -> int:
	var n := 0
	for code in range(1, state.score.kills.size()):
		n += int(state.score.kills[code])
	return n


## The crew's free-roam values in the results screen's order: the outcome, (v4) the difficulty and tanks
## lost, points, points per WORK minute, kills by code without the Behemoth's (light, medium, destroyer,
## heavy, recon, tankette), distance, evades, breakdowns, patrols.
func _roam_team_stats(per_min: float) -> Dictionary:
	var sc := state.score
	var kills: PackedStringArray = []
	for code: int in TEAM_KILL_CODES:
		if code != TankIds.BOSS_CODE:
			kills.append(str(sc.kills[code]))
	var timed_out := state.outcome == TankIds.OUTCOME_TIME_UP
	return {
		"TANK_TEAM_OUTCOME":
		ctx.strings.t("TANK_OUTCOME_TIME_UP" if timed_out else "TANK_RESULT_ABANDONED"),
		"TANK_TEAM_DIFFICULTY": _difficulty_label(),
		"TANK_TEAM_LOSSES": sc.losses,
		"TANK_TEAM_POINTS": state.roam.points,
		"TANK_TEAM_POINTS_PER_MIN": "%.1f" % per_min,
		"TANK_TEAM_ROAM_KILLS": "/".join(kills),
		"TANK_TEAM_DISTANCE": "%.1f" % (state.roam.odo_m / 1000.0),
		"TANK_TEAM_EVADES": "%d/%d" % [sc.evades_ok, sc.evades_tried],
		"TANK_TEAM_BREAKDOWNS": sc.breakdowns,
		"TANK_TEAM_PATROLS": state.roam.patrols,
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
		"TANK_STAT_ARC_S": roundi(r.engine_s[4]),
		"TANK_STAT_FEED_S": roundi(r.engine_s[5]),
		"TANK_STAT_REPAIR_S": roundi(r.engine_s[6]),
		"TANK_STAT_REPAIRED": roundi(r.repaired_hp),
		"TANK_STAT_EVADES": "%d/%d" % [r.evades_ok, r.evades_tried],
		"TANK_STAT_BOW_HITS": r.bow_hits,
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
