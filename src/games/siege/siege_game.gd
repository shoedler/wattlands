class_name SiegeGame
extends GameModule
## Castellum Rotae's GameModule (docs/games/siege.md; GAME_SDK 4).
##
## Host / SOLO: sim_step validates and rate-limits intents (SiegeIntentLimiter, 5 a second per
## peer, only peers in ctx.players), runs SiegeRules.step, sends the Overdrive directive round
## trip and every event (send_event), emits phase_changed and finished("complete"), and publishes
## the cadence band. Clients: apply_snapshot / apply_event rebuild the state, client_predict moves the
## local rider ahead of the next snapshot. Every toast and cue that follows a host-side rule is
## raised from the events: on the host right where it sends them (its own rider only, with
## ctx.local_peer), on each client in apply_event.
##
## Overdrive flow on the host (ADR "Overdrive refusal handling"):
##   rules: SiegeOverdrive.try_start -> state.od_requests
##   here, same tick: ctx.directives.request(peer, SiegeOverdrive.directive(content))
##     -> SiegeOverdrive.on_request_result(state, peer, accepted, id, reason)
##   ctx.events.directive_applied(peer, record) -> queued in _applied (a local rider's record
##     arrives inside request(), before its id is known; a remote rider's with its telemetry)
##     -> drained after each request and at the start of every sim_step into
##     SiegeOverdrive.on_applied(state, peer, record) (a refused record cancels it).
##   The rider's own peer shows the sprint band (1.2 to 1.4 x FTP) while its Overdrive is
##   ACTIVE (_sync_band, from the state on the host and from events and snapshots on clients).
## Never a bot, never an auto intent, never a lap_marker; the cool-down sends no directive.

## Every event type, raised like its toast: the host where it sends the event, clients in
## apply_event. `kind` is the event "type", `data` the event (ints cast). The view replays `shot`
## cues with SiegeBallistics and listens here for impacts, horns, coins and the like.
signal cue(kind: String, data: Dictionary)

## The warm-up wave's teaching toasts: one per minute, TEACH_AT_S into each minute.
const TEACH_KEYS: Array[String] = [
	"SIEGE_TEACH_1", "SIEGE_TEACH_2", "SIEGE_TEACH_3", "SIEGE_TEACH_4", "SIEGE_TEACH_5"
]
const TEACH_AT_S := 6.0
const TEACH_WINDOW_S := 10.0
## A client keeps its predicted route this long waiting for the host's route event or snapshot.
const PREDICT_HOLD_S := 2.5
## Leak toasts are rare: at most one per this many game seconds.
const LEAK_TOAST_GAP_S := 4.0
## The gate warning shows below this fraction and re-arms above REARM.
const GATE_LOW_FRAC := 0.3
const GATE_REARM_FRAC := 0.5
## Session ids kept in the progress file (a restarted client sees the same results twice).
const PROGRESS_SESSIONS_KEPT := 32

var content: SiegeContent = null
var state: SiegeState = null
## peer -> EffortPlan built here (host/SOLO).
var plans: Dictionary = {}
## Phase metas in plan order (every peer; from shifts.json).
var metas: Array[Dictionary] = []
## Client: enemy path positions of the last snapshots for the view's interpolation.
var history: SiegeSnapHistory = SiegeSnapHistory.new()

var _limiter := SiegeIntentLimiter.new()
var _rescue: Dictionary = {}
var _afk: Dictionary = {}
## [[peer, record], ...] from ctx.events.directive_applied, not yet handled.
var _applied: Array = []
var _last_phase: int = -1
var _finished: bool = false
var _band_on: bool = false
var _teach_done: int = -1
var _gate_low: bool = false
var _last_leak_tick: int = -100000
## Client: the route the local rider asked for and the game seconds since (-1: none).
var _pred_target: int = -1
var _pred_age_s: float = 0.0
var _progress_sessions: Array[String] = []
var _cadence_published: bool = false
## peer -> the rider's plan as the HUD reads it (hud_plan).
var _hud_plans: Dictionary = {}


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
	history = SiegeSnapHistory.new(content.path)
	if ctx.is_authority() and ctx.events != null:
		ctx.events.directive_applied.connect(_on_directive_applied)


func build_effort_plans() -> Dictionary:
	if state == null:
		return {}
	plans = SiegePlanBuilder.build_all(content.shift, ctx.players, ctx.content_id)
	return plans


# --- Host / SOLO ----------------------------------------------------------------------------


func sim_step(dt: float, frame: InputFrame) -> void:
	if state == null:
		return
	_publish_cadence_band()
	var events: Array[Dictionary] = _drain_applied()
	var inp := SiegeInputs.from_frame(
		frame, ctx.players, plans, _collect_intents(frame), _rescue, _afk
	)
	events.append_array(SiegeRules.step(state, inp, dt))
	events.append_array(_send_overdrive_requests())
	for e in events:
		send_event(e)
		_local_effects(e)
	_sync_band()
	_track_phase(inp)
	if state.done and not _finished:
		_finished = true
		finished.emit("complete")
	_teach_check()
	_gate_watch()


## The cadence Siege asks for, published once at the session's start: the rider's metronome, a
## MockTrainer `band` rider and every bot follow it. It never changes load (GAME_SDK 8).
func _publish_cadence_band() -> void:
	if _cadence_published or ctx.directives == null:
		return
	_cadence_published = true
	for p in ctx.players:
		ctx.directives.cadence_band(p.peer_id, SiegeHudModel.CADENCE_LO, SiegeHudModel.CADENCE_HI)


## Autopilot runs inside the host rules for every rider in a fallback (ADR "Autopilot runs
## inside the host rules"), so the platform's per-tick call adds nothing.
func autopilot_intents(_peer_id: int) -> Array:
	return []


func on_rescue(peer_id: int, active: bool) -> void:
	_rescue[peer_id] = active
	if active and peer_id == ctx.local_peer and ctx.is_authority():
		_toast("SIEGE_TOAST_STAGGER")


func on_afk(peer_id: int, afk: bool) -> void:
	_afk[peer_id] = afk
	if afk and peer_id == ctx.local_peer and ctx.is_authority():
		_toast("SIEGE_TOAST_AFK")


## Every peer's intents this tick, normalized and rate-limited, keyed by peer. Only the peers of
## ctx.players are read, so telemetry and intents from anyone else never reach the rules.
func _collect_intents(frame: InputFrame) -> Dictionary:
	var out := {}
	for p in ctx.players:
		var tm := frame.telemetry(p.peer_id)
		if tm != null and not tm.intents.is_empty():
			out[p.peer_id] = _limiter.filter(p.peer_id, frame.tick, tm.intents)
	return out


## Sends the directive of every Overdrive the rules started this tick and reports each result.
func _send_overdrive_requests() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for peer in state.take_od_requests():
		var r := state.rider(peer)
		if r == null:
			continue
		if r.is_bot:
			events.append_array(SiegeOverdrive.cancel(state, r, SiegeOverdrive.END_PHASE))
			continue
		var res := ctx.directives.request(peer, SiegeOverdrive.directive(content))
		events.append_array(
			SiegeOverdrive.on_request_result(state, peer, res.accepted, res.id, res.reason)
		)
		events.append_array(_drain_applied())
	return events


func _on_directive_applied(peer: int, record: Dictionary) -> void:
	_applied.append([peer, record])


func _drain_applied() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while not _applied.is_empty():
		var a: Array = _applied.pop_front()
		out.append_array(SiegeOverdrive.on_applied(state, int(a[0]), a[1]))
	return out


## phase_changed in the step where frame.phase first shows a new index (every slot shares it).
func _track_phase(inp: SiegeInputs) -> void:
	if inp.phase.index >= 0 and inp.phase.index != _last_phase:
		_last_phase = inp.phase.index
		phase_changed.emit(inp.phase.index)


## True from the end of the last wave through the platform's cool-down: the workers march home
## and the view shows the victory flag. (sim_step still runs; nothing spawns and enemies retreat.)
func victory_march() -> bool:
	return state != null and (state.in_cooldown() or state.done)


# --- Controls -------------------------------------------------------------------------------


## The local rider's controls: ability_1 or a surge -> Overdrive; swap / right (the next station),
## left (the previous), up (the mine), down (the hot station) -> routing (outside breaks; in breaks
## the shop panel takes the directions and the surge). A surge never also counts as confirm
## (nothing here reads confirm).
func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	var out: Array = []
	if state == null or state.shop_open() or state.in_cooldown():
		return out
	if gestures.has(Wl.G_SURGE):
		out.append(SiegeIntents.overdrive(SiegeIds.VIA_SURGE))
	elif actions.has(&"ability_1"):
		out.append(SiegeIntents.overdrive(SiegeIds.VIA_ACTION))
	var to: Variant = null
	if actions.has(&"swap") or actions.has(&"right"):
		to = "next"
	elif actions.has(&"left"):
		to = "prev"
	elif actions.has(&"up"):
		to = "mine"
	elif actions.has(&"down"):
		to = "hot"
	if to != null:
		var route := SiegeIntents.route(to)
		out.append(route)
		predict_route(route)
	return out


# --- Snapshots and events -------------------------------------------------------------------


func snapshot() -> Dictionary:
	return SiegeSnapshot.encode(state) if state != null else {}


func apply_snapshot(snap: Dictionary) -> void:
	if state == null:
		return
	var me := state.rider(ctx.local_peer)
	var was_rescue := me != null and me.rescue
	var was_afk := me != null and me.afk
	SiegeSnapshot.apply(state, snap)
	state.t = state.tick * Wl.SIM_DT
	_sync_phase()
	history.push(state.tick * Wl.SIM_DT, state.enemies)
	_refresh_prompts()
	if me != null:
		if me.rescue and not was_rescue:
			_toast("SIEGE_TOAST_STAGGER")
		if me.afk and not was_afk:
			_toast("SIEGE_TOAST_AFK")
		if _pred_target >= 0 and me.target == _pred_target:
			_pred_target = -1
	_sync_band()
	_teach_check()
	_gate_watch()


## Clients: the phase fields the snapshot leaves out, from the shift's phase list.
func _sync_phase() -> void:
	var ph := state.phase_index
	var phases: Array = content.shift.get("phases", [])
	if ph >= 0 and ph < metas.size() and ph < phases.size():
		state.role = str(metas[ph].get("role", ""))
		state.wave_no = int(metas[ph].get("number", 0))
		state.phase_kind = str(phases[ph].get("kind", ""))
		state.phase_duration_s = float(phases[ph].get("duration_s", 0.0))
		state.done = false
	elif ph >= metas.size() and ph >= 0:
		state.role = SiegeIds.ROLE_COOLDOWN
		state.wave_no = 0
		state.phase_kind = Wl.COOLDOWN
		state.phase_duration_s = PlanValidator.cooldown_phase().duration_s
		state.done = true
	state.phase_remaining_s = maxf(state.phase_duration_s - state.phase_elapsed_s, 0.0)


## Clients: every rider's Overdrive prompt from the replicated state (brief 2.4).
func _refresh_prompts() -> void:
	var info := SiegePhaseInfo.new()
	info.index = state.phase_index
	info.kind = state.phase_kind
	info.role = state.role
	info.number = state.wave_no
	info.waves = state.waves_total
	info.elapsed_s = state.phase_elapsed_s
	info.duration_s = state.phase_duration_s
	info.remaining_s = state.phase_remaining_s
	for rd in state.riders:
		rd.od_prompt = SiegeOverdrive.prompt(state, rd, info)


func apply_event(event: Dictionary) -> void:
	if state == null:
		return
	var e := SiegeEvents.cast(event)
	_client_state(e)
	_local_effects(e)
	_sync_band()


## Clients: what an event tells the state right away (the next snapshot confirms it).
func _client_state(e: Dictionary) -> void:
	var rd := state.rider_at(int(e.get("slot", -1)))
	match str(e.get("type", "")):
		SiegeIds.EV_DOCK:
			state.tar.boarded = true
		SiegeIds.EV_RUSH:
			var on := int(e.get("on", 0)) != 0
			state.wave.rush_s = content.num("rush.duration_s", 30.0) if on else 0.0
			state.wave.rush_next = int(e.get("i", 0)) + 1
		SiegeIds.EV_BREACH:
			state.breaches = int(e.get("n", state.breaches))
		SiegeIds.EV_GATE_RESTORED:
			state.gate_hp = float(int(e.get("hp", state.gate_hp)))
		SiegeIds.EV_ROUTE:
			if rd != null:
				var to := clampi(int(e.get("to", rd.target)), 0, SiegeIds.STATION_COUNT - 1)
				if to != rd.target:
					rd.reconnect_s = content.num("reconnect_s", 2.0)
				rd.target = to
				if rd.peer == ctx.local_peer:
					_pred_target = -1
		SiegeIds.EV_OVERDRIVE:
			if rd == null:
				return
			match int(e.get("st", 0)):
				SiegeIds.OD_EV_START:
					rd.od_state = SiegeIds.OD_ACTIVE
					rd.od_s = content.num("overdrive.duration_s", 30.0)
					rd.od_cd_s = 0.0
				SiegeIds.OD_EV_END:
					rd.od_state = SiegeIds.OD_COOLDOWN
					rd.od_s = 0.0
					rd.od_cd_s = content.num("overdrive.cooldown_s", 90.0)
				SiegeIds.OD_EV_REFUSED:
					rd.od_state = SiegeIds.OD_COOLDOWN
					rd.od_s = 0.0
					rd.od_cd_s = content.num("overdrive.refused_retry_s", 30.0)


## Moves the local rider ahead of the next snapshot: its own power, cadence and wheel (the view
## reads them), a route change shown at once, and the clocks the snapshot only refreshes.
func client_predict(dt: float, local: Telemetry) -> void:
	if state == null:
		return
	var rd := state.rider(ctx.local_peer)
	if rd != null and local != null:
		rd.p_eff_w = local.p_eff_w
		rd.raw_w = local.power_w
		rd.cadence_rpm = local.cadence_rpm
	for r in state.riders:
		r.reconnect_s = maxf(r.reconnect_s - dt, 0.0)
		r.od_s = maxf(r.od_s - dt, 0.0)
		r.od_cd_s = maxf(r.od_cd_s - dt, 0.0)
	state.breach_s = maxf(state.breach_s - dt, 0.0)
	state.phase_elapsed_s += dt
	state.phase_remaining_s = maxf(state.phase_remaining_s - dt, 0.0)
	state.wave.rush_s = maxf(state.wave.rush_s - dt, 0.0)
	if _pred_target >= 0 and rd != null:
		_pred_age_s += dt
		if _pred_age_s > PREDICT_HOLD_S:
			_pred_target = -1
		elif rd.target != _pred_target:
			rd.target = _pred_target
			rd.reconnect_s = maxf(content.num("reconnect_s", 2.0) - _pred_age_s, 0.0)


## Clients: shows a route the local rider just asked for at once, before the host's route event or
## the next snapshot. `to` is the route intent ({"k": "route", "to": ...}, as the controls send it)
## or just its target: "mine", "next", "prev", "hot", a station 0..4 or a normalized
## SiegeIds.ROUTE_*. local_intents() calls it for the control routes. Returns true when a prediction
## was set (never on the host or in SOLO, whose rules route at once, nor for a route that changes
## nothing).
func predict_route(to: Variant) -> bool:
	if state == null or ctx == null or ctx.role != Wl.CLIENT:
		return false
	var wire: Variant = to
	if to is int and int(to) < 0:
		# A normalized ROUTE_NEXT / PREV / HOT goes back to its wire word.
		for word: String in SiegeIds.ROUTE_WORDS:
			if int(SiegeIds.ROUTE_WORDS[word]) == to:
				wire = word
	var intent := SiegeIntents.normalize(wire if wire is Dictionary else SiegeIntents.route(wire))
	if intent.is_empty() or str(intent["k"]) != SiegeIds.INTENT_ROUTE:
		return false
	var rd := state.rider(ctx.local_peer)
	if rd == null:
		return false
	var want := SiegeRoutePredict.resolve(state, rd, int(intent["to"]))
	if want < 0:
		return false
	_pred_target = want
	_pred_age_s = 0.0
	rd.target = want
	rd.reconnect_s = content.num("reconnect_s", 2.0)
	return true


func int_fields() -> Dictionary:
	return SiegeEvents.int_fields()


# --- Presentation ---------------------------------------------------------------------------


func make_view() -> Node:
	var v := SiegeView.new()
	v.game = self
	v.bind(state, state.path if state != null else null)
	return v


func hud_spec() -> HudSpec:
	return SiegeHud.spec(self)


## The rider's whole plan as the HUD reads it, on every peer: this slot's targets (its wave offset)
## and the appended cool-down. Cached per peer: the shift never changes in a session.
func hud_plan(peer: int) -> EffortPlan:
	var plan: Variant = _hud_plans.get(peer, null)
	if plan is EffortPlan:
		return plan
	var built := EffortPlan.new()
	var slot := ctx.player(peer) if ctx != null else null
	if slot != null and state != null and state.content != null:
		built = SiegePlanBuilder.build(state.content.shift, slot, ctx.content_id)
		built.add(PlanValidator.cooldown_phase())
		built.cooldown_appended = true
		_hud_plans[peer] = built
	return built


func _target_name(target: int) -> String:
	return ctx.strings.t(station_key(target))


## The string key of station `id`'s name (SIEGE_STATION_MINE, ...).
static func station_key(id: int) -> String:
	return (
		"SIEGE_STATION_"
		+ SiegeIds.STATION_NAMES[clampi(id, 0, SiegeIds.STATION_COUNT - 1)].to_upper()
	)


## The sprint band on the rider's own peer while its Overdrive is ACTIVE, cleared after.
func _sync_band() -> void:
	var me := state.rider(ctx.local_peer)
	if me == null or ctx.hud == null:
		return
	var on := me.od_state == SiegeIds.OD_ACTIVE
	if on == _band_on:
		return
	_band_on = on
	if on:
		var band := SiegeOverdrive.band_w(content, me.ftp)
		ctx.hud.power_band(ctx.local_peer, band.x, band.y)
	else:
		ctx.hud.power_band(ctx.local_peer, 0.0, 0.0)


## One teaching toast a minute in the warm-up wave, from the phase clock (the same on every peer).
func _teach_check() -> void:
	if state.role != SiegeIds.ROLE_WARMUP_WAVE:
		return
	var since := state.phase_elapsed_s - TEACH_AT_S
	if since < 0.0:
		return
	var minute := int(since / 60.0)
	if minute >= TEACH_KEYS.size() or minute <= _teach_done:
		return
	if since - minute * 60.0 > TEACH_WINDOW_S:
		return
	_teach_done = minute
	_toast(TEACH_KEYS[minute])


## "The gate is failing!" once when it falls under 30%, re-armed above 50%.
func _gate_watch() -> void:
	var frac := state.gate_hp / maxf(state.gate_max, 1.0)
	if _gate_low and frac >= GATE_REARM_FRAC:
		_gate_low = false
	elif not _gate_low and frac < GATE_LOW_FRAC and state.in_wave():
		_gate_low = true
		_toast("SIEGE_WARN_GATE_LOW")


# --- Local effects --------------------------------------------------------------------------


## Toast for the local rider only: the host names its own peer (nothing is broadcast), a client's
## call is always local.
func _toast(key: String, args: Array = []) -> void:
	if ctx.hud != null:
		ctx.hud.toast(key, args, ctx.local_peer if ctx.is_authority() else Wl.ALL_PEERS)


## Effects of one event for the local rider: on the host right where it is sent, on clients in
## apply_event. Buy and Overdrive results speak to their own rider only.
func _local_effects(e: Dictionary) -> void:
	var type := str(e.get("type", ""))
	cue.emit(type, e)
	var me := state.rider(ctx.local_peer)
	if me == null:
		return
	var mine := int(e.get("slot", -1)) == me.slot
	match type:
		SiegeIds.EV_WAVE_START:
			if str(e.get("role", "")) == SiegeIds.ROLE_WARMUP_WAVE:
				_toast("SIEGE_TOAST_WARMUP_START")
			else:
				_toast("SIEGE_TOAST_WAVE_START", [int(e["n"]), int(e["waves"])])
		SiegeIds.EV_WAVE_END:
			if int(e.get("n", 0)) > 0:
				_toast("SIEGE_TOAST_WAVE_END", [int(e["n"]), int(e["hp"])])
			else:
				_toast("SIEGE_TOAST_BREAK")
		SiegeIds.EV_PUSH:
			if int(e.get("et", 0)) == SiegeIds.ENEMY_TOWER:
				_toast("SIEGE_TOAST_TOWER")
			else:
				_toast("SIEGE_TOAST_PUSH")
		SiegeIds.EV_DOCK:
			_toast("SIEGE_TOAST_DOCK")
		SiegeIds.EV_RUSH:
			_toast("SIEGE_TOAST_RUSH_START" if int(e["on"]) != 0 else "SIEGE_TOAST_RUSH_END")
		SiegeIds.EV_KILL:
			if int(e["et"]) == SiegeIds.ENEMY_RAM:
				_toast("SIEGE_TOAST_RAM_DOWN")
			elif int(e["et"]) == SiegeIds.ENEMY_TOWER:
				_toast("SIEGE_TOAST_TOWER_DOWN")
		SiegeIds.EV_LEAK:
			var tick := state.tick
			if (tick - _last_leak_tick) * Wl.SIM_DT >= LEAK_TOAST_GAP_S:
				_last_leak_tick = tick
				_toast("SIEGE_TOAST_LEAK", [_enemy_name(int(e["et"]))])
		SiegeIds.EV_BREACH:
			_toast("SIEGE_TOAST_BREACH")
		SiegeIds.EV_GATE_RESTORED:
			_toast("SIEGE_TOAST_GATE_RESTORED", [int(e["hp"])])
		SiegeIds.EV_BUY:
			if mine:
				if int(e["ok"]) != 0:
					_toast("SIEGE_TOAST_BUY_OK", [_item_name(e)])
				else:
					_toast("SIEGE_TOAST_BUY_REFUSED", [_refusal(str(e.get("why", "")))])
		SiegeIds.EV_ROUTE:
			if mine:
				_toast("SIEGE_TOAST_ROUTE", [_route_name(int(e["to"]))])
		SiegeIds.EV_OVERDRIVE:
			if not mine:
				return
			match int(e["st"]):
				SiegeIds.OD_EV_START:
					_toast("SIEGE_TOAST_OVERDRIVE_START")
				SiegeIds.OD_EV_END:
					if int(e.get("scored", 0)) != 0:
						_toast("SIEGE_TOAST_OVERDRIVE_SCORED")
					else:
						_toast("SIEGE_TOAST_OVERDRIVE_END")
				SiegeIds.OD_EV_REFUSED:
					_toast("SIEGE_TOAST_OVERDRIVE_REFUSED")


func _enemy_name(code: int) -> String:
	if code <= 0 or code >= SiegeIds.ENEMY_NAMES.size():
		return ""
	return ctx.strings.t("SIEGE_ENEMY_" + SiegeIds.ENEMY_NAMES[code].to_upper())


func _route_name(to: int) -> String:
	return ctx.strings.t(station_key(to))


func _refusal(why: String) -> String:
	return ctx.strings.t("SIEGE_SHOP_REFUSED_" + why.to_upper())


## The bought item's name for the buyer's toast (upgrades and mine levels by their new level).
func _item_name(e: Dictionary) -> String:
	var item := str(e.get("item", ""))
	var lvl := clampi(int(e.get("lvl", 0)), 1, 3)
	match item:
		SiegeIds.ITEM_UPGRADE:
			var st := ctx.strings.t(station_key(int(e.get("station", 1))))
			return ctx.strings.t("SIEGE_ITEM_UPGRADE_%d" % lvl, [st])
		SiegeIds.ITEM_PAD_UPGRADE:
			return ctx.strings.t("SIEGE_ITEM_PAD_UPGRADE_%d" % lvl, [int(e.get("pad", 1))])
		SiegeIds.ITEM_MINE:
			return ctx.strings.t("SIEGE_ITEM_MINE_%d" % lvl)
	return ctx.strings.t("SIEGE_ITEM_" + item.to_upper())


# --- Results and progression ------------------------------------------------------------------


func results() -> GameResults:
	var res := GameResults.from_stats(ctx.stats, ctx.players)
	if state == null:
		return res
	var sc := SiegeScore.compute(state)
	res.score = float(sc["score"])
	res.grade = str(sc["grade"])
	res.summary_key = "SIEGE_RESULTS_FALLEN" if state.breaches > 0 else "SIEGE_RESULTS"
	for row in res.rows:
		var rd := state.rider(int(row["peer_id"]))
		row["xp"] = SiegeScore.xp(content, float(row.get("kj", 0.0)), res.grade)
		if rd == null:
			continue
		var st: Dictionary = row["stats"]
		st["SIEGE_STAT_MINE_GOLD"] = floori(rd.mine_gold)
		st["SIEGE_STAT_BOUNTY_GOLD"] = floori(rd.bounty_gold)
		st["SIEGE_STAT_KILLS"] = rd.kills
		st["SIEGE_STAT_DAMAGE"] = roundi(rd.damage)
		st["SIEGE_STAT_OVERDRIVES"] = rd.od_scored
		st["SIEGE_STAT_MINE_TIME"] = roundi(rd.wave_mine_s)
		st["SIEGE_STAT_WEAPON_TIME"] = roundi(rd.wave_weapon_s)
		st["SIEGE_STAT_TOP_STATION"] = _target_name(rd.top_station())
	# The results screen prints team values with str(): lists become readable text first.
	var gate_hp := PackedStringArray()
	for hp in state.wave_gate_hp:
		gate_hp.append(str(hp))
	var shots := PackedStringArray()
	for id in SiegeIds.WEAPONS:
		var s := state.station(id)
		shots.append("%s %d / %d" % [_target_name(id), s.hits, s.shots])
	res.team = {
		"SIEGE_STAT_SCORE": roundi(res.score),
		"SIEGE_STAT_GATE_PER_WAVE": " / ".join(gate_hp) if not gate_hp.is_empty() else "-",
		"SIEGE_STAT_BREACHES": state.breaches,
		"SIEGE_STAT_LEAKS": state.leaks,
		"SIEGE_STAT_ENGINES_STOPPED": "%d / %d" % [state.engines_stopped, state.engines_total],
		"SIEGE_STAT_SHOTS": " · ".join(shots),
	}
	var tx := ctx.strings if ctx.strings != null else GameStrings.new()
	res.ride_tag = SiegeScore.ride_tag(state, ctx.content_id, tx)
	res.ride_lines = SiegeScore.ride_lines(state, res, tx)
	return res


## Adds the local rider's session XP once per results.session_id (remembered in the progress
## file too, so a client restarted in the cool-down that gets the results again counts it once)
## and returns the cosmetics whose thresholds the new cumulative total reaches for the first time
## (each unlock once).
func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	var row := res.row(ctx.local_peer)
	if row.is_empty():
		return []
	var sid := res.session_id
	var kept: Array = progress.get_value("sessions", [])
	if _progress_sessions.has(sid) or (sid != "" and kept.has(sid)):
		return []
	_progress_sessions.append(sid)
	if sid != "":
		kept.append(sid)
		while kept.size() > PROGRESS_SESSIONS_KEPT:
			kept.pop_front()
		progress.set_value("sessions", kept)
	var total := progress.add("xp", float(row.get("xp", 0)))
	var held: Array = progress.get_value("unlocks", [])
	var fresh: Array = []
	if content != null:
		for u: Variant in content.cosmetics.get("unlocks", []):
			var id := str(u["id"])
			if float(u["xp"]) <= total and not held.has(id) and not fresh.has(id):
				fresh.append(id)
	progress.set_value("unlocks", held + fresh)
	return fresh
