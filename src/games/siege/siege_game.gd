class_name SiegeGame
extends GameModule
## Generator Siege's GameModule (docs/games/siege.md; GAME_SDK 4). Owner: B2 "module".
##
## Host / SOLO: sim_step validates and rate-limits intents (SiegeIntentLimiter, 5 a second per
## peer, only peers in ctx.players), runs SiegeRules.step, sends the Overdrive directive round
## trip and every event (send_event), emits phase_changed and finished("complete"), and feeds
## the HUD. Clients: apply_snapshot / apply_event rebuild the state, client_predict moves the
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
## apply_event. `kind` is the event "type", `data` the event (ints cast). The view and audio
## listen here for horns, coins and the like.
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
## The host refreshes the teammate chips this often (ticks; 2 Hz).
const STATUS_EVERY_TICKS := 10
## Session ids kept in the progress file (a restarted client sees the same results twice).
const PROGRESS_SESSIONS_KEPT := 32

var content: SiegeContent = null
var state: SiegeState = null
## peer -> EffortPlan built here (host/SOLO).
var plans: Dictionary = {}
## Phase metas in plan order (every peer; from shifts.json).
var metas: Array[Dictionary] = []
## Client: enemy road positions of the last snapshots for the view's interpolation.
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
	history = SiegeSnapHistory.new(content.map)
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
	if frame.tick % STATUS_EVERY_TICKS == 0:
		_feed_status(inp)
	if frame.tick % Wl.SIM_HZ == 0:
		_feed_hud()


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


## The local rider's controls: ability_1 or a surge -> Overdrive; swap / right, left, up, down ->
## routing (outside breaks; in breaks the shop panel takes the directions and the surge). A
## surge never also counts as confirm (nothing here reads confirm).
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
		to = "gen"
	elif actions.has(&"down"):
		to = "hot"
	if to != null:
		var route := SiegeIntents.route(to)
		out.append(route)
		if ctx.role == Wl.CLIENT:
			_predict_route(int(SiegeIntents.normalize(route)["to"]))
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
	_feed_hud()


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
		SiegeIds.EV_WAVE_START:
			state.wave.active_roads.clear()
			for r: Variant in e.get("roads", []):
				state.wave.active_roads.append(int(r))
		SiegeIds.EV_ROADS:
			state.wave.next_roads.clear()
			for r: Variant in e.get("roads", []):
				state.wave.next_roads.append(int(r))
			state.wave.horn_s = int(e.get("in_ms", 0)) / 1000.0
		SiegeIds.EV_PUSH:
			state.wave.push_done = true
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
				var to := int(e.get("to", rd.target))
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
	var w := state.wave
	w.rush_s = maxf(w.rush_s - dt, 0.0)
	if w.horn_s > 0.0:
		w.horn_s -= dt
		if w.horn_s <= 0.0 and not w.next_roads.is_empty():
			w.active_roads = w.next_roads.duplicate()
			w.next_roads.clear()
	if _pred_target >= 0 and rd != null:
		_pred_age_s += dt
		if _pred_age_s > PREDICT_HOLD_S:
			_pred_target = -1
		elif rd.target != _pred_target:
			rd.target = _pred_target
			rd.reconnect_s = maxf(content.num("reconnect_s", 2.0) - _pred_age_s, 0.0)


## Clients: a route intent the local rider just made, shown at once.
func _predict_route(to: int) -> void:
	var rd := state.rider(ctx.local_peer) if state != null else null
	if rd == null:
		return
	var want := SiegeRoutePredict.resolve(state, rd, to)
	if want < 0:
		return
	_pred_target = want
	_pred_age_s = 0.0
	rd.target = want
	rd.reconnect_s = content.num("reconnect_s", 2.0)


func int_fields() -> Dictionary:
	return SiegeEvents.int_fields()


# --- Presentation ---------------------------------------------------------------------------


func make_view() -> Node:
	var view := SiegeView.new()
	view.game = self
	view.bind(state, content.map if content != null else null)
	return view


func hud_spec() -> HudSpec:
	return SiegeHud.spec(self)


## The teammate strip's rows from the replicated state, so a client's numbers come from the
## snapshot (raw W, %FTP of the slot's FTP, target, Overdrive): [{slot, peer, name, color,
## pattern, is_bot, raw_w, p_eff_w, ftp_pct, target, target_text, marker, od, rescue, afk}] in
## slot order. The HUD's own Control beside the kit strip reads it.
func teammate_strip() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	for rd in state.riders:
		var p := ctx.player(rd.peer)
		var od := rd.od_state == SiegeIds.OD_ACTIVE
		(
			out
			. append(
				{
					"slot": rd.slot,
					"peer": rd.peer,
					"name": p.name if p != null else "",
					"color": p.color if p != null else Color.WHITE,
					"pattern": p.pattern if p != null else "solid",
					"is_bot": rd.is_bot,
					"raw_w": roundi(rd.raw_w),
					"p_eff_w": roundi(rd.p_eff_w),
					"ftp_pct": roundi(rd.raw_w / maxf(rd.ftp, 1.0) * 100.0),
					"target": rd.target,
					"target_text": _target_name(rd.target),
					"marker": ctx.strings.t("SIEGE_STATUS_OD") if od else "",
					"od": od,
					"rescue": rd.rescue,
					"afk": rd.afk,
				}
			)
		)
	return out


func _target_name(target: int) -> String:
	if SiegeIds.is_pad(target):
		return ctx.strings.t("SIEGE_STATUS_TOWER", [target])
	return ctx.strings.t("SIEGE_STATUS_GEN")


## The host's teammate chips (2 Hz, reach every peer through the roster): the target and the
## Overdrive marker; in band = delivering power at its plan (±5%) or inside the sprint band.
func _feed_status(inp: SiegeInputs) -> void:
	if ctx.hud == null:
		return
	for rd in state.riders:
		var ri := inp.rider(rd.peer)
		if ri == null:
			continue
		var text := _target_name(rd.target)
		if rd.od_state == SiegeIds.OD_ACTIVE:
			text += " · " + ctx.strings.t("SIEGE_STATUS_OD")
		var planned_w := ri.planned_pct / 100.0 * rd.ftp
		var in_band := (
			rd.connected
			and not rd.afk
			and not rd.rescue
			and planned_w > 0.0
			and absf(ri.power_w - planned_w) <= 0.05 * planned_w
		)
		if rd.od_state == SiegeIds.OD_ACTIVE:
			var band := SiegeOverdrive.band_w(content, rd.ftp)
			in_band = ri.power_w >= band.x and ri.power_w <= band.y
		ctx.hud.teammate_status(rd.peer, {"in_band": in_band, "icon": "", "text": text})


func _feed_hud() -> void:
	if state == null or ctx.hud == null:
		return
	ctx.hud.readout(
		SiegeHud.READOUT_GATE, "%d / %d" % [ceili(state.gate_hp), roundi(state.gate_max)]
	)
	var me := state.rider(ctx.local_peer)
	if me != null:
		ctx.hud.readout(SiegeHud.READOUT_DENARII, str(floori(me.denarii)))


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
		SiegeIds.EV_ROADS:
			_toast("SIEGE_TOAST_ROADS")
		SiegeIds.EV_PUSH:
			_toast("SIEGE_TOAST_PUSH")
		SiegeIds.EV_RUSH:
			_toast("SIEGE_TOAST_RUSH_START" if int(e["on"]) != 0 else "SIEGE_TOAST_RUSH_END")
		SiegeIds.EV_KILL:
			if int(e["et"]) == SiegeIds.ENEMY_RAM:
				_toast("SIEGE_TOAST_RAM_DOWN")
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
	if SiegeIds.is_pad(to):
		return ctx.strings.t("SIEGE_HUD_ROUTE_PAD", [to])
	return ctx.strings.t("SIEGE_GENERATOR")


func _refusal(why: String) -> String:
	return ctx.strings.t("SIEGE_SHOP_REFUSED_" + why.to_upper())


## The bought item's name for the buyer's toast (upgrades and generator by their new level).
func _item_name(e: Dictionary) -> String:
	var item := str(e.get("item", ""))
	var lvl := int(e.get("lvl", 0))
	if item == SiegeIds.ITEM_UPGRADE:
		return ctx.strings.t("SIEGE_ITEM_UPGRADE_%d" % clampi(lvl, 1, 3))
	if item == SiegeIds.ITEM_GENERATOR:
		return ctx.strings.t("SIEGE_ITEM_GENERATOR_%d" % clampi(lvl, 1, 3))
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
		st["SIEGE_STAT_GEN_DENARII"] = floori(rd.gen_denarii)
		st["SIEGE_STAT_BOUNTY_DENARII"] = floori(rd.bounty_denarii)
		st["SIEGE_STAT_KILLS"] = rd.kills
		st["SIEGE_STAT_DAMAGE"] = roundi(rd.damage)
		st["SIEGE_STAT_OVERDRIVES"] = rd.od_scored
		st["SIEGE_STAT_GEN_TIME"] = roundi(rd.wave_gen_s)
		st["SIEGE_STAT_TOWER_TIME"] = roundi(rd.wave_tower_s)
		st["SIEGE_STAT_TOWERS_BUILT"] = rd.towers_built
	# The results screen prints team values with str(): lists become readable text first.
	var gate_hp := PackedStringArray()
	for hp in state.wave_gate_hp:
		gate_hp.append(str(hp))
	var leaks := state.leaks_by_road
	res.team = {
		"SIEGE_STAT_SCORE": roundi(res.score),
		"SIEGE_STAT_GATE_PER_WAVE": " / ".join(gate_hp) if not gate_hp.is_empty() else "-",
		"SIEGE_STAT_BREACHES": state.breaches,
		"SIEGE_STAT_LEAKS_BY_ROAD": "%d / %d / %d" % [leaks[0], leaks[1], leaks[2]],
		"SIEGE_STAT_RAMS_STOPPED": "%d / %d" % [state.rams_stopped, state.rams_total],
	}
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
