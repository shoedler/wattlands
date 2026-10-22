class_name SiegeGame
extends GameModule
## Generator Siege's GameModule (docs/games/siege.md; GAME_SDK 4). Owner: B2 "module".
##
## G0 status: minimal but complete wiring, so the game is valid and plays end to end:
## content loaded and validated (SiegeContent), plans from SiegePlanBuilder, SiegeRules.step
## each tick with validated, rate-limited intents, the Overdrive directive round trip
## (SiegeOverdrive), phase_changed, finished("complete") when the last wave ends, results with
## the grade and XP, apply_progress once per session, snapshots (SiegeSnapshot) and int_fields
## (SiegeEvents). B2 completes events' local effects, prediction, interpolation and the HUD feed.
##
## Overdrive flow on the host (ADR "Overdrive refusal handling"):
##   rules: SiegeOverdrive.try_start -> state.od_requests
##   here, same tick: ctx.directives.request(peer, SiegeOverdrive.directive(content))
##     -> SiegeOverdrive.on_request_result(state, peer, accepted, id, reason)
##   ctx.events.directive_applied(peer, record) -> queued in _applied (a local rider's record
##     arrives inside request(), before its id is known; a remote rider's with its telemetry)
##     -> drained after each request and at the start of every sim_step into
##     SiegeOverdrive.on_applied(state, peer, record) (a refused record cancels it).
##   overdrive events: the host raises its own rider's band and toasts here; clients in
##     apply_event (power_band(local_peer, 1.2 x FTP, 1.4 x FTP) while on, (0, 0) after).

var content: SiegeContent = null
var state: SiegeState = null
## peer -> EffortPlan built here (host/SOLO).
var plans: Dictionary = {}
## Phase metas in plan order (every peer; from shifts.json).
var metas: Array[Dictionary] = []
var _limiter := SiegeIntentLimiter.new()
var _rescue: Dictionary = {}
var _afk: Dictionary = {}
## [[peer, record], ...] from ctx.events.directive_applied, not yet handled.
var _applied: Array = []
var _last_phase: int = -1
var _finished: bool = false


func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	content = SiegeContent.load_for(ctx)
	if not content.ok():
		var msg := "siege: content %s: %s" % [ctx.content_id, "; ".join(content.errors)]
		if ctx.is_authority():
			push_error(msg)
		else:
			push_warning(msg)
		return
	var rng: RandomNumberGenerator = ctx.rng if ctx.is_authority() else null
	state = SiegeRules.new_state(content, ctx.players, ctx.scaling_mode, rng)
	metas = SiegePlanBuilder.phase_metas(content.shift, ctx.content_id)
	if ctx.is_authority() and ctx.events != null:
		ctx.events.directive_applied.connect(_on_directive_applied)


func build_effort_plans() -> Dictionary:
	if state == null:
		return {}
	plans = SiegePlanBuilder.build_all(content.shift, ctx.players, ctx.content_id)
	return plans


func sim_step(dt: float, frame: InputFrame) -> void:
	if state == null:
		return
	var events: Array[Dictionary] = _drain_applied()
	var intents := {}
	for p in ctx.players:
		var tm := frame.telemetry(p.peer_id)
		if tm != null and not tm.intents.is_empty():
			intents[p.peer_id] = _limiter.filter(p.peer_id, frame.tick, tm.intents)
	var inp := SiegeInputs.from_frame(frame, ctx.players, plans, intents, _rescue, _afk)
	events.append_array(SiegeRules.step(state, inp, dt))
	for peer in state.take_od_requests():
		var res := ctx.directives.request(peer, SiegeOverdrive.directive(content))
		events.append_array(
			SiegeOverdrive.on_request_result(state, peer, res.accepted, res.id, res.reason)
		)
		events.append_array(_drain_applied())
	for e in events:
		send_event(e)
		_local_effects(e, true)
	if inp.phase.index >= 0 and inp.phase.index != _last_phase:
		_last_phase = inp.phase.index
		phase_changed.emit(inp.phase.index)
	if state.done and not _finished:
		_finished = true
		finished.emit("complete")
	if frame.tick % Wl.SIM_HZ == 0:
		_feed_hud()


## Autopilot runs inside the host rules for every rider in a fallback (ADR "Autopilot runs
## inside the host rules"), so the platform's per-tick call adds nothing.
func autopilot_intents(_peer_id: int) -> Array:
	return []


func on_rescue(peer_id: int, active: bool) -> void:
	_rescue[peer_id] = active


func on_afk(peer_id: int, afk: bool) -> void:
	_afk[peer_id] = afk


## The local rider's controls: ability_1 or a surge -> Overdrive; swap / right, left, up, down ->
## routing (outside breaks; in breaks the shop panel takes the directions and the surge).
func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	var out: Array = []
	if state == null or state.shop_open():
		return out
	if gestures.has(Wl.G_SURGE):
		out.append(SiegeIntents.overdrive(SiegeIds.VIA_SURGE))
	elif actions.has(&"ability_1"):
		out.append(SiegeIntents.overdrive(SiegeIds.VIA_ACTION))
	if actions.has(&"swap") or actions.has(&"right"):
		out.append(SiegeIntents.route("next"))
	elif actions.has(&"left"):
		out.append(SiegeIntents.route("prev"))
	elif actions.has(&"up"):
		out.append(SiegeIntents.route("gen"))
	elif actions.has(&"down"):
		out.append(SiegeIntents.route("hot"))
	return out


func snapshot() -> Dictionary:
	return SiegeSnapshot.encode(state) if state != null else {}


func apply_snapshot(snap: Dictionary) -> void:
	if state == null:
		return
	SiegeSnapshot.apply(state, snap)
	var ph := state.phase_index
	if ph >= 0 and ph < metas.size():
		state.role = str(metas[ph].get("role", ""))
		state.wave_no = int(metas[ph].get("number", 0))
	elif ph >= metas.size():
		state.role = SiegeIds.ROLE_COOLDOWN
	_feed_hud()


func apply_event(event: Dictionary) -> void:
	if state == null:
		return
	_local_effects(SiegeEvents.cast(event), false)


func client_predict(_dt: float, local: Telemetry) -> void:
	if state == null or local == null:
		return
	var rd := state.rider(ctx.local_peer)
	if rd != null:
		rd.p_eff_w = local.p_eff_w
		rd.raw_w = local.power_w
		rd.cadence_rpm = local.cadence_rpm


func int_fields() -> Dictionary:
	return SiegeEvents.int_fields()


func make_view() -> Node:
	var view := SiegeView.new()
	view.game = self
	view.bind(state, content.map if content != null else null)
	return view


func hud_spec() -> HudSpec:
	return SiegeHud.spec(self)


func results() -> GameResults:
	var res := GameResults.from_stats(ctx.stats, ctx.players)
	if state == null:
		return res
	var sc := SiegeScore.compute(state)
	res.score = float(sc["score"])
	res.grade = str(sc["grade"])
	res.summary_key = "SIEGE_RESULTS"
	for row in res.rows:
		var rd := state.rider(int(row["peer_id"]))
		row["xp"] = SiegeScore.xp(content, float(row.get("kj", 0.0)), res.grade)
		if rd == null:
			continue
		var st: Dictionary = row["stats"]
		st["SIEGE_STAT_GEN_DENARII"] = floori(rd.gen_denarii)
		st["SIEGE_STAT_BOUNTY_DENARII"] = floori(rd.bounty_denarii)
		st["SIEGE_STAT_KILLS"] = rd.kills
		st["SIEGE_STAT_DAMAGE"] = roundi(rd.damage)
		st["SIEGE_STAT_OVERDRIVES"] = rd.od_scored
		st["SIEGE_STAT_GEN_TIME"] = roundi(rd.wave_gen_s)
		st["SIEGE_STAT_TOWER_TIME"] = roundi(rd.wave_tower_s)
		st["SIEGE_STAT_TOWERS_BUILT"] = rd.towers_built
	res.team = {
		"SIEGE_STAT_SCORE": roundi(res.score),
		"SIEGE_STAT_GATE_PER_WAVE": state.wave_gate_hp.duplicate(),
		"SIEGE_STAT_BREACHES": state.breaches,
		"SIEGE_STAT_LEAKS_BY_ROAD": state.leaks_by_road.duplicate(),
		"SIEGE_STAT_RAMS_STOPPED": state.rams_stopped,
	}
	return res


## Adds the local rider's session XP once per session id and returns the cosmetics whose
## thresholds the new cumulative total reaches for the first time (each unlock once).
func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	var row := res.row(ctx.local_peer)
	if (
		row.is_empty()
		or (res.session_id != "" and progress.get_value("last_session", "") == res.session_id)
	):
		return []
	progress.set_value("last_session", res.session_id)
	var total := progress.add("xp", float(row.get("xp", 0)))
	var held: Array = progress.get_value("unlocks", [])
	var fresh: Array = []
	if content != null:
		for u: Variant in content.cosmetics.get("unlocks", []):
			var id := str(u["id"])
			if float(u["xp"]) <= total and not held.has(id):
				fresh.append(id)
	progress.set_value("unlocks", held + fresh)
	return fresh


func _on_directive_applied(peer: int, record: Dictionary) -> void:
	_applied.append([peer, record])


func _drain_applied() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while not _applied.is_empty():
		var a: Array = _applied.pop_front()
		out.append_array(SiegeOverdrive.on_applied(state, int(a[0]), a[1]))
	return out


## Effects of one event for the local rider: on the host right where it is sent (`host` true),
## on clients in apply_event. Every ctx.hud call here is for this peer only.
func _local_effects(e: Dictionary, host: bool) -> void:
	var me := state.rider(ctx.local_peer)
	var mine := me != null and int(e.get("slot", -1)) == me.slot
	var peer := ctx.local_peer if host else Wl.ALL_PEERS
	match str(e.get("type", "")):
		SiegeIds.EV_OVERDRIVE:
			if not mine:
				return
			match int(e["st"]):
				SiegeIds.OD_EV_START:
					var band := SiegeOverdrive.band_w(content, me.ftp)
					ctx.hud.power_band(ctx.local_peer, band.x, band.y)
				SiegeIds.OD_EV_END:
					ctx.hud.power_band(ctx.local_peer, 0.0, 0.0)
				SiegeIds.OD_EV_REFUSED:
					ctx.hud.power_band(ctx.local_peer, 0.0, 0.0)
					ctx.hud.toast("SIEGE_TOAST_OVERDRIVE_REFUSED", [], peer)
		SiegeIds.EV_BUY:
			if mine and int(e["ok"]) == 0:
				ctx.hud.toast("SIEGE_TOAST_BUY_REFUSED", [], peer)
		SiegeIds.EV_WAVE_START:
			if me == null:
				return
			if str(e.get("role", "")) == SiegeIds.ROLE_WARMUP_WAVE:
				ctx.hud.toast("SIEGE_TOAST_WARMUP_START", [], peer)
			else:
				ctx.hud.toast("SIEGE_TOAST_WAVE_START", [int(e["n"]), int(e["waves"])], peer)


func _feed_hud() -> void:
	if state == null or ctx.hud == null:
		return
	ctx.hud.readout(
		SiegeHud.READOUT_GATE, "%d / %d" % [ceili(state.gate_hp), roundi(state.gate_max)]
	)
	var me := state.rider(ctx.local_peer)
	if me != null:
		ctx.hud.readout(SiegeHud.READOUT_DENARII, str(floori(me.denarii)))
