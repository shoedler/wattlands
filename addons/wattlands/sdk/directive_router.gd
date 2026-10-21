class_name DirectiveRouter
extends DirectiveSink
## `ctx.directives` on the authority (HOST and SOLO; BRIEF 3.6, 4.5, 4.6.6, 4.6.7;
## docs/OWNERSHIP.md DS1-DS13, PL20; 3.1 C4, C25, C26). On a CLIENT every call is ignored
## with push_warning (only the authority simulates).
##
## request(peer, directive) checks, in order, refusing with:
##   unknown_peer, no_phase (before the session started), cooldown (the cool-down or a
##   finished plan), bad_fields (nothing set, non-finite values, negative duration_s, an
##   unknown mode), erg_in_sim_phase (mode "ERG" in a SIM phase), outside_range_pct (an ERG
##   target outside the phase's effective range; target_w / target_wkg are converted to
##   % FTP first; a SIM phase has no ERG range), sim_block_length (a SIM block, i.e. mode
##   "SIM" in an ERG phase while no block runs, needs 10 s <= duration_s <= 30 s),
##   sim_block_unsafe (a SIM block during rescue, coasting, AFK or pause), switch_spacing (a
##   SIM block must start >= 30 s after the rider's previous ERG<->SIM switch: plan phase
##   changes and directive blocks; the block's own exit is exempt), mode_grade_outside_sim
##   (mode_grade outside a SIM phase or block), haptic_in_erg (a haptic for a rider in ERG),
##   haptics_off (the rider opted out). Mode "SIM" in a SIM phase (C4), and mode "SIM" in an
##   ERG phase while a SIM block runs, is a no-op confirmation: no block opens, the running
##   one is neither extended nor re-checked (length, safety, spacing), and the request's
##   other channels (a haptic, mode_grade, factors) apply as inside the block, as the
##   governor does (DirectiveSink contract). A refusal refuses the whole request.
## Every request gets an id (refused ones too). An accepted request goes to a rider
## simulated here through LocalRider.apply_directive() (its record is emitted as
## EventBus.directive_applied at once; a SIM block its governor refused is taken back, so
## the host's spacing and mode_grade bookkeeping never count a block that never ran) or to a
## remote rider as a 5.5 `directive`
## {kind: "request", id, peer, directive: {...}}; the client's governor acks it in
## Telemetry.acks and the GameHost emits the ack as directive_applied.
## Every refusal is logged with push_warning, emitted as directive_applied {refused: true,
## reason} and kept in the report.
##
## course_grade: only in a SIM phase with grade_source "game" (else grade_source_not_game);
## coalesced to 2 Hz (the newest value goes out at most every 0.5 s of game time; a value
## pending at a phase change is dropped). end_phase: open-ended phases after min_s; the phase
## ends at the end of the current tick. cadence_band: holds across phases, (0, 0) clears,
## refused in the cool-down (the GameHost clears every band there). replan: validated as the
## whole resulting plan (phases up to the current one + the new ones), applied at the next
## phase change.

const COURSE_GRADE_INTERVAL_TICKS := 10
const SIM_BLOCK_MIN_S := 10.0
const SIM_BLOCK_MAX_S := 30.0
const SWITCH_SPACING_S := 30.0
const EPS := 1e-6

var role: String = Wl.SOLO
var tracker: PhaseTracker = null
var clock: SimClock = null
## Every rider in the session: peer -> PlayerSlot.
var slots: Dictionary = {}
## Riders simulated on this peer: peer -> LocalRider. Private (W3 SAF-4): `ctx.directives` is
## this object, so a public map would hand a game every LocalRider (set_plan, start_phase,
## resume, the governor) past the DirectiveSink's checks. The GameHost sets it with
## bind_riders(); nothing reads it from outside.
var _riders: Dictionary = {}
var bus: WlEventBus = null
var report: ReportCollector = null
## (peer: int, payload: Dictionary) -> void: sends a 5.5 `directive` to a remote rider.
var remote_send: Callable = Callable()
## (peer: int) -> Telemetry or null: the rider's latest telemetry (sim_block_unsafe).
var telemetry_of: Callable = Callable()
## (peer: int, warnings: Array) -> void: a replan was accepted (report plan warnings).
var on_replan: Callable = Callable()

var _next_id: int = 1
## peer -> [lo, hi]
var _cadence_bands: Dictionary = {}
## peer -> {grade, phase}
var _grade_pending: Dictionary = {}
## peer -> game tick of the last delivered course grade
var _grade_last_tick: Dictionary = {}
## peer -> {id, prev_switch, prev_mode}: a remote rider's SIM block awaiting its ack.
var _open_blocks: Dictionary = {}


func is_authority() -> bool:
	return role == Wl.SOLO or role == Wl.HOST


## The riders simulated on this peer (peer -> LocalRider); the GameHost calls this once at
## setup. There is deliberately no getter.
func bind_riders(p_riders: Dictionary) -> void:
	_riders = p_riders


func request(peer: int, directive: EffortDirective) -> DirectiveResult:
	if not is_authority():
		push_warning("DirectiveRouter: request ignored on a client (only the host simulates)")
		return DirectiveResult.refused(Wl.REFUSE_NOT_AUTHORITY)
	var d := directive.duplicate_directive() if directive != null else EffortDirective.new()
	var id := _take_id()
	d.id = id
	var why := _check_request(peer, d) if directive != null else Wl.REFUSE_BAD_FIELDS
	if why != "":
		return _refuse(peer, NetMessages.DIRECTIVE_REQUEST, d.to_dict(), why, id)
	var tick := _tick()
	var phase := tracker.phase_of(peer)
	var opened := false
	var prev_switch := tracker.last_switch_tick(peer)
	var prev_mode := tracker.mode_now(peer)
	if _opens_block(peer, d, tick):
		tracker.open_block(peer, tick, PhaseTracker.ticks(d.duration_s))
		opened = true
	elif phase.mode == Wl.ERG and d.mode == Wl.ERG and tracker.block_active(peer, tick):
		tracker.close_block(peer, tick)
	_log(peer, id, NetMessages.DIRECTIVE_REQUEST, d.to_dict(), true, "")
	if _riders.has(peer):
		var rec := _normalize((_riders[peer] as LocalRider).apply_directive(d), id, NetMessages.DIRECTIVE_REQUEST, d.to_dict())
		if opened and bool(rec.get("refused", false)):
			# The rider's governor refused the block: no switch happened.
			tracker.cancel_block(peer, prev_switch, prev_mode)
		_applied(peer, rec)
	else:
		if opened:
			_open_blocks[peer] = {"id": id, "prev_switch": prev_switch, "prev_mode": prev_mode}
		_remote(peer, {"kind": NetMessages.DIRECTIVE_REQUEST, "id": id, "peer": peer, "directive": d.to_dict()})
	return DirectiveResult.ok(id)


## A remote rider's ack arrived (the GameHost calls this for every Telemetry.acks record): a
## SIM block its governor refused is taken back while it is still the running block.
func on_ack(peer: int, rec: Dictionary) -> void:
	var pending: Dictionary = _open_blocks.get(peer, {})
	if pending.is_empty() or int(rec.get("id", 0)) != int(pending["id"]):
		return
	_open_blocks.erase(peer)
	var refused: Variant = rec.get("refused", false)
	if refused is bool and refused and tracker != null and tracker.block_active(peer, _tick()):
		tracker.cancel_block(peer, int(pending["prev_switch"]), str(pending["prev_mode"]))


func course_grade(peer: int, grade_pct: float) -> void:
	if not is_authority():
		push_warning("DirectiveRouter: course_grade ignored on a client")
		return
	var kind := NetMessages.DIRECTIVE_COURSE_GRADE
	var why := _check_phase(peer)
	if why == "":
		var phase := tracker.phase_of(peer)
		if phase.mode != Wl.SIM or phase.grade_source != Wl.GRADE_GAME:
			why = Wl.REFUSE_NOT_GAME_GRADE
		elif is_nan(grade_pct) or is_inf(grade_pct):
			why = Wl.REFUSE_BAD_FIELDS
	if why != "":
		_refuse(peer, kind, {"grade_pct": grade_pct}, why, _take_id())
		return
	var tick := _tick()
	var last := int(_grade_last_tick.get(peer, -COURSE_GRADE_INTERVAL_TICKS))
	if tick - last >= COURSE_GRADE_INTERVAL_TICKS:
		_deliver_grade(peer, grade_pct, tick)
	else:
		_grade_pending[peer] = {"grade": grade_pct, "phase": tracker.index_of(peer)}


func end_phase(peer: int) -> bool:
	if not is_authority():
		push_warning("DirectiveRouter: end_phase ignored on a client")
		return false
	var id := _take_id()
	var why := Wl.REFUSE_UNKNOWN_PEER if not slots.has(peer) else (tracker.request_end(peer) if tracker != null else Wl.REFUSE_NO_PHASE)
	if why != "":
		_refuse(peer, "end_phase", {}, why, id)
		return false
	_log(peer, id, "end_phase", {"index": tracker.index_of(peer)}, true, "")
	return true


func cadence_band(peer: int, lo_rpm: float, hi_rpm: float) -> void:
	if not is_authority():
		push_warning("DirectiveRouter: cadence_band ignored on a client")
		return
	var kind := NetMessages.DIRECTIVE_CADENCE_BAND
	var req := {"lo_rpm": lo_rpm, "hi_rpm": hi_rpm}
	var id := _take_id()
	var why := ""
	if not slots.has(peer):
		why = Wl.REFUSE_UNKNOWN_PEER
	elif tracker != null and (tracker.is_cooldown(peer) or tracker.is_done(peer)):
		why = Wl.REFUSE_COOLDOWN
	elif is_nan(lo_rpm) or is_nan(hi_rpm) or is_inf(lo_rpm) or is_inf(hi_rpm) or lo_rpm < 0.0 or hi_rpm < lo_rpm:
		why = Wl.REFUSE_BAD_FIELDS
	if why != "":
		_refuse(peer, kind, req, why, id)
		return
	_log(peer, id, kind, req, true, "")
	_apply_band(peer, lo_rpm, hi_rpm, id)


func replan(peer: int, plan: EffortPlan) -> bool:
	if not is_authority():
		push_warning("DirectiveRouter: replan ignored on a client")
		return false
	var id := _take_id()
	var why := _check_phase(peer)
	if why == "" and plan == null:
		why = Wl.REFUSE_BAD_FIELDS
	if why != "":
		_refuse(peer, "replan", {}, why, id)
		return false
	var whole := PlanValidator.spliced(tracker.plan_of(peer), tracker.index_of(peer), plan)
	var res := PlanValidator.validate(whole)
	if not bool(res["ok"]):
		_refuse(peer, "replan", {"plan": plan.to_dict(), "errors": res["errors"]}, Wl.REFUSE_PLAN_INVALID, id)
		return false
	var fin := PlanValidator.finalize(whole)
	tracker.set_pending_plan(peer, fin)
	_log(peer, id, "replan", {"plan": plan.to_dict(), "warnings": res["warnings"]}, true, "")
	if on_replan.is_valid():
		on_replan.call(peer, res["warnings"])
	return true


# --- GameHost hooks -----------------------------------------------------------------


## Deliver coalesced course grades that are due (call once per tick, after phase changes).
func flush(game_tick: int) -> void:
	for peer: int in _grade_pending.keys():
		var pending: Dictionary = _grade_pending[peer]
		if int(pending["phase"]) != tracker.index_of(peer) or tracker.is_cooldown(peer):
			_grade_pending.erase(peer)
			continue
		var last := int(_grade_last_tick.get(peer, -COURSE_GRADE_INTERVAL_TICKS))
		if game_tick - last >= COURSE_GRADE_INTERVAL_TICKS:
			_grade_pending.erase(peer)
			_deliver_grade(peer, float(pending["grade"]), game_tick)


## The rider entered its cool-down: its cadence band is cleared (BRIEF 3.6).
func clear_bands(peer: int) -> void:
	_grade_pending.erase(peer)
	if not _cadence_bands.has(peer):
		return
	_cadence_bands.erase(peer)
	if _riders.has(peer):
		(_riders[peer] as LocalRider).set_cadence_band(0.0, 0.0)
	if bus != null:
		bus.cadence_band_changed.emit(peer, 0.0, 0.0)


## The published cadence band for `peer` ([0, 0] when none).
func cadence_band_of(peer: int) -> Array:
	return _cadence_bands.get(peer, [0.0, 0.0])


# --- internals --------------------------------------------------------------------------


func _take_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _tick() -> int:
	return clock.game_tick if clock != null else 0


func _t() -> float:
	return _tick() * Wl.SIM_DT


func _check_phase(peer: int) -> String:
	if not slots.has(peer):
		return Wl.REFUSE_UNKNOWN_PEER
	if tracker == null or not tracker.has(peer) or tracker.index_of(peer) < 0:
		return Wl.REFUSE_NO_PHASE
	if tracker.is_cooldown(peer) or tracker.is_done(peer):
		return Wl.REFUSE_COOLDOWN
	return ""


func _check_request(peer: int, d: EffortDirective) -> String:
	var why := _check_phase(peer)
	if why != "":
		return why
	if not _fields_ok(d):
		return Wl.REFUSE_BAD_FIELDS
	var tick := _tick()
	var phase := tracker.phase_of(peer)
	var block := tracker.block_active(peer, tick)
	var opens_block := _opens_block(peer, d, tick)
	if phase.mode == Wl.SIM and d.mode == Wl.ERG:
		return Wl.REFUSE_ERG_IN_SIM
	if d.sets_erg_target():
		if phase.mode != Wl.ERG:
			return Wl.REFUSE_RANGE
		var pct := target_pct_of(peer, d)
		var rng := phase.effective_range()
		if pct < float(rng[0]) - EPS or pct > float(rng[1]) + EPS:
			return Wl.REFUSE_RANGE
	if opens_block:
		if d.duration_s < SIM_BLOCK_MIN_S - EPS or d.duration_s > SIM_BLOCK_MAX_S + EPS:
			return Wl.REFUSE_SIM_BLOCK_LENGTH
		if _unsafe(peer):
			return Wl.REFUSE_SIM_BLOCK_UNSAFE
		if tracker.seconds_since_switch(peer, tick) < SWITCH_SPACING_S - EPS:
			return Wl.REFUSE_SWITCH_SPACING
	var ends_block := phase.mode == Wl.ERG and d.mode == Wl.ERG
	var sim_now := phase.mode == Wl.SIM or opens_block or (block and not ends_block)
	if d.is_set("mode_grade") and not sim_now:
		return Wl.REFUSE_MODE_GRADE
	if d.sets_haptic():
		if not sim_now:
			return Wl.REFUSE_HAPTIC_ERG
		var slot: PlayerSlot = slots[peer]
		if not slot.haptics_on:
			return Wl.REFUSE_HAPTIC_OFF
	return ""


## True when `d` opens a SIM block: mode "SIM" in an ERG phase while no block runs. The same
## request during a running block only confirms it (never extends it), like the governor.
func _opens_block(peer: int, d: EffortDirective, tick: int) -> bool:
	return d.mode == Wl.SIM and tracker.phase_of(peer).mode == Wl.ERG and not tracker.block_active(peer, tick)


func _fields_ok(d: EffortDirective) -> bool:
	if d.mode != "" and d.mode != Wl.ERG and d.mode != Wl.SIM:
		return false
	if is_nan(d.duration_s) or is_inf(d.duration_s) or d.duration_s < 0.0:
		return false
	var any := d.mode != ""
	for f in EffortDirective.FLOAT_FIELDS:
		var v: float = d.get(f)
		if is_nan(v):
			continue
		if is_inf(v):
			return false
		any = true
	return any


## The request's ERG target in % of the rider's FTP (target_w and target_wkg converted).
## W/kg uses the rider's weight where the host knows it (WKG: 75 / p_eff_per_w; RAW with a
## shared weight: rider_mass_kg), else the 75 kg reference; the rider's own governor
## converts again with its real weight.
func target_pct_of(peer: int, d: EffortDirective) -> float:
	var slot: PlayerSlot = slots.get(peer)
	var ftp := maxf(slot.ftp if slot != null else 200.0, 1.0)
	if d.is_set("target_pct"):
		return d.target_pct
	if d.is_set("target_w"):
		return d.target_w / ftp * 100.0
	if d.is_set("target_wkg"):
		return d.target_wkg * weight_of(slot) / ftp * 100.0
	return NAN


static func weight_of(slot: PlayerSlot) -> float:
	if slot == null:
		return EffortScaling.REFERENCE_KG
	if slot.scaling_mode == Wl.WKG and slot.p_eff_per_w > 0.0:
		return EffortScaling.REFERENCE_KG / slot.p_eff_per_w
	if slot.scaling_mode == Wl.RAW:
		return slot.rider_mass_kg
	return EffortScaling.REFERENCE_KG


func _unsafe(peer: int) -> bool:
	if not telemetry_of.is_valid():
		return false
	var tm: Variant = telemetry_of.call(peer)
	if not (tm is Telemetry):
		return false
	var t: Telemetry = tm
	return t.rescue or t.coasting or t.afk or t.paused


func _deliver_grade(peer: int, grade: float, tick: int) -> void:
	_grade_last_tick[peer] = tick
	var id := _take_id()
	var kind := NetMessages.DIRECTIVE_COURSE_GRADE
	_log(peer, id, kind, {"grade_pct": grade}, true, "")
	if _riders.has(peer):
		(_riders[peer] as LocalRider).apply_course_grade(grade)
	else:
		_remote(peer, {"kind": kind, "id": id, "peer": peer, "grade_pct": grade})


func _apply_band(peer: int, lo: float, hi: float, id: int) -> void:
	if lo == 0.0 and hi == 0.0:
		_cadence_bands.erase(peer)
	else:
		_cadence_bands[peer] = [lo, hi]
	if _riders.has(peer):
		(_riders[peer] as LocalRider).set_cadence_band(lo, hi)
	else:
		_remote(peer, {"kind": NetMessages.DIRECTIVE_CADENCE_BAND, "id": id, "peer": peer, "lo_rpm": lo, "hi_rpm": hi})
	if bus != null:
		bus.cadence_band_changed.emit(peer, lo, hi)


func _remote(peer: int, payload: Dictionary) -> void:
	if remote_send.is_valid():
		remote_send.call(peer, payload)
	else:
		push_warning("DirectiveRouter: no route to remote rider %d" % peer)


func _refuse(peer: int, kind: String, requested: Dictionary, reason: String, id: int) -> DirectiveResult:
	push_warning("DirectiveRouter: %s for peer %d refused: %s" % [kind, peer, reason])
	var rec := {
		"id": id, "kind": kind, "requested": requested, "applied": {}, "clamped_by": [],
		"refused": true, "reason": reason, "t": _t(), "by": "host",
	}
	_log(peer, id, kind, requested, false, reason)
	if bus != null:
		bus.directive_applied.emit(peer, rec)
	if report != null:
		report.directive_applied(peer, rec)
	return DirectiveResult.refused(reason, id)


func _log(peer: int, id: int, kind: String, requested: Dictionary, accepted: bool, reason: String) -> void:
	if report != null:
		report.directive_requested(peer, id, kind, requested, _t(), accepted, reason)


func _applied(peer: int, rec: Dictionary) -> void:
	if bus != null:
		bus.directive_applied.emit(peer, rec)
	if report != null:
		report.directive_applied(peer, rec)


## A governor record with the contract's keys filled in (the W0 LocalRider stub returns {}).
func _normalize(rec: Dictionary, id: int, kind: String, requested: Dictionary) -> Dictionary:
	var out := rec.duplicate(true)
	if int(out.get("id", 0)) == 0:
		out["id"] = id
	if not out.has("kind"):
		out["kind"] = kind
	if not out.has("requested"):
		out["requested"] = requested
	if not out.has("applied"):
		out["applied"] = {}
	if not out.has("clamped_by"):
		out["clamped_by"] = []
	if not out.has("refused"):
		out["refused"] = false
	elif not (out["refused"] is bool):
		# Telemetry.acks documents refused as a String ("" or the reason); records carry a bool.
		var rv: Variant = out["refused"]
		out["refused"] = (rv is String and str(rv) != "") or ((rv is int or rv is float) and float(rv) != 0.0)
	if not out.has("reason"):
		out["reason"] = ""
	if not out.has("t"):
		out["t"] = _t()
	return out
