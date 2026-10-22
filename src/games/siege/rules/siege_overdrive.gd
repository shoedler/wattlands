class_name SiegeOverdrive
extends RefCounted
## Overdrive (brief 2.3, 2.4): a rider's 30 s SIM sprint block. Pure, static, deterministic.
## G0 architect's file (B1 owns the rest of rules/ and calls it from SiegeRules.step; B2's module
## sends the directive and feeds back the results). Numbers come from balance.json "overdrive".
##
## The one directive Siege ever sends (exactly these four keys; no mode_grade, haptic, target_*,
## crr or cw, so it opens no other channel, sets no ERG target and expires back to the planned
## target through the controller's ramped switch; Siege sends no restore directive):
##   {"mode": "SIM", "duration_s": 30, "reason": "overdrive", "source": "siege"}
##
## State machine per rider (SiegeRiderState.od_state):
##   READY --trigger (rules)--> PENDING (peer queued in state.od_requests)
##   PENDING --request accepted (module: on_request_result)--> ACTIVE (od_s = 30, od_id = id;
##       event overdrive st 1)
##   PENDING --request refused by the host (DirectiveResult.accepted false)--> COOLDOWN with
##       refused_retry_s (30 s; event st 2, why = the reason)
##   ACTIVE --the rider's governor refused it after all (applied record refused, same id;
##       module: on_applied)--> COOLDOWN with refused_retry_s (event st 2; od_count taken back)
##   ACTIVE --od_s runs out (step_rider)--> COOLDOWN with cooldown_s (90 s from the end; event
##       st 0 with scored)
##   ACTIVE --phase change, rescue or AFK (cancel)--> COOLDOWN with cooldown_s (event st 0)
##   COOLDOWN --od_cd_s runs out--> READY
## Triggers (try_start): an "overdrive" intent that is not auto (never Autopilot's, never a
## bot's) from a READY human in a WORK phase with >= 30 s left, not in rescue, not AFK;
## via "surge" also needs the prompt (target has an enemy in range, or a rush is on); via
## "action" (ability_1) or "button" doesn't (ADR "Overdrive triggers").
## While ACTIVE: od = 2 for that rider's routed output while raw power >= its FTP (CP, ADR
## "slot.ftp as CP"); the sprint rule (raw >= 1.2 x FTP) held >= 10 s in a row makes it a scored
## Overdrive. The rider's own peer publishes power_band(1.2 x FTP, 1.4 x FTP) while it is on.

const MODE := "SIM"
const REASON := "overdrive"
const SOURCE := "siege"
const DIRECTIVE_KEYS: Array[String] = ["duration_s", "mode", "reason", "source"]

## Why Overdrive can't start ("" = it can).
const WHY_BOT := "bot"
const WHY_AUTO := "auto"
const WHY_NOT_READY := "not_ready"
const WHY_NOT_WORK := "not_work"
const WHY_TOO_LATE := "too_late"
const WHY_RESCUE := "rescue"
const WHY_AFK := "afk"
const WHY_NO_PROMPT := "no_prompt"
const WHY_NOT_INTENT := "not_overdrive"
## cancel() reasons (END events carry them in "why").
const END_PHASE := "phase"
const END_RESCUE := "rescue"
const END_AFK := "afk"
const END_EXPIRED := ""
const EPS := 1e-6


## The directive as a Dictionary (duration from balance.json, 30).
static func directive_dict(content: SiegeContent = null) -> Dictionary:
	return {
		"mode": MODE,
		"duration_s": int(_num(content, "overdrive.duration_s", 30.0)),
		"reason": REASON,
		"source": SOURCE
	}


## The EffortDirective the module passes to ctx.directives.request(peer, ...).
static func directive(content: SiegeContent = null) -> EffortDirective:
	return EffortDirective.from_dict(directive_dict(content))


## The sprint band the rider's own peer publishes while Overdrive is on: [lo_w, hi_w].
static func band_w(content: SiegeContent, ftp: float) -> Vector2:
	return Vector2(
		_num(content, "overdrive.band_lo_ftp", 1.2) * ftp,
		_num(content, "overdrive.band_hi_ftp", 1.4) * ftp
	)


## The safety and readiness gate: "" when `rider` may start Overdrive in `phase` now (READY,
## a human, a WORK phase with >= min_left_s (30 s) left, not in rescue, delivering power).
static func blocked_reason(
	state: SiegeState, rider: SiegeRiderState, phase: SiegePhaseInfo
) -> String:
	if rider.is_bot:
		return WHY_BOT
	if rider.od_state != SiegeIds.OD_READY:
		return WHY_NOT_READY
	if phase == null or phase.kind != Wl.WORK or phase.is_cooldown():
		return WHY_NOT_WORK
	if phase.remaining_s < _num(state.content, "overdrive.min_left_s", 30.0) - EPS:
		return WHY_TOO_LATE
	if rider.rescue:
		return WHY_RESCUE
	if rider.afk or not rider.connected:
		return WHY_AFK
	return ""


## The prompt (brief 2.4): ready, WORK with >= 30 s left, no rescue, and the rider's target has
## an enemy in range or a rush is on.
static func prompt(state: SiegeState, rider: SiegeRiderState, phase: SiegePhaseInfo) -> bool:
	return (
		blocked_reason(state, rider, phase) == ""
		and (state.rush_on() or state.target_hot(rider.target))
	)


## "" when the normalized `intent` starts this rider's Overdrive now, else why not.
static func trigger_reason(
	state: SiegeState, rider: SiegeRiderState, phase: SiegePhaseInfo, intent: Dictionary
) -> String:
	if str(intent.get("k", "")) != SiegeIds.INTENT_OVERDRIVE:
		return WHY_NOT_INTENT
	if bool(intent.get("auto", false)) or str(intent.get("via", "")) == SiegeIds.VIA_AUTO:
		return WHY_AUTO
	var why := blocked_reason(state, rider, phase)
	if why != "":
		return why
	if str(intent.get("via", "")) == SiegeIds.VIA_SURGE and not prompt(state, rider, phase):
		return WHY_NO_PROMPT
	return ""


## Starts Overdrive when `intent` triggers it: READY -> PENDING and the peer queued in
## state.od_requests. Returns true when it did.
static func try_start(
	state: SiegeState, rider: SiegeRiderState, phase: SiegePhaseInfo, intent: Dictionary
) -> bool:
	if trigger_reason(state, rider, phase, intent) != "":
		return false
	rider.od_state = SiegeIds.OD_PENDING
	rider.od_s = 0.0
	rider.od_id = 0
	if not state.od_requests.has(rider.peer):
		state.od_requests.append(rider.peer)
	return true


## The module's report of ctx.directives.request() for `peer` (same tick as try_start).
## Returns the events to send.
static func on_request_result(
	state: SiegeState, peer: int, accepted: bool, id: int, reason: String
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := state.rider(peer)
	if r == null or r.od_state != SiegeIds.OD_PENDING:
		return out
	if accepted:
		r.od_state = SiegeIds.OD_ACTIVE
		r.od_s = _num(state.content, "overdrive.duration_s", 30.0)
		r.od_id = id
		r.od_hold_s = 0.0
		r.od_best_s = 0.0
		r.od_count += 1
		out.append(SiegeEvents.overdrive(r.slot, SiegeIds.OD_EV_START))
	else:
		_refused(state, r)
		out.append(SiegeEvents.overdrive(r.slot, SiegeIds.OD_EV_REFUSED, false, reason))
	return out


## An applied record from ctx.events.directive_applied(peer, record) on the host (local riders:
## emitted inside request(); remote riders: from Telemetry.acks, >= one telemetry later). A
## refused record for the running Overdrive's id cancels it. Anything else is ignored.
static func on_applied(state: SiegeState, peer: int, record: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := state.rider(peer)
	if r == null or r.od_state != SiegeIds.OD_ACTIVE or r.od_id == 0:
		return out
	if int(record.get("id", 0)) != r.od_id or not bool(record.get("refused", false)):
		return out
	r.od_count = maxi(r.od_count - 1, 0)
	_refused(state, r)
	out.append(
		SiegeEvents.overdrive(r.slot, SiegeIds.OD_EV_REFUSED, false, str(record.get("reason", "")))
	)
	return out


## Ends a running Overdrive early (phase change, rescue, AFK): the normal 90 s cooldown starts
## now. No directive is sent: the governor's SIM block expires on its own (every channel resets
## at a phase change anyway). A PENDING request is dropped without an event.
static func cancel(state: SiegeState, rider: SiegeRiderState, why: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if rider.od_state == SiegeIds.OD_PENDING:
		rider.od_state = SiegeIds.OD_READY
		state.od_requests.erase(rider.peer)
	elif rider.od_state == SiegeIds.OD_ACTIVE:
		out.append(_end(state, rider, why))
	return out


## One tick of the rider's Overdrive clocks, after intents were applied. `raw_w` is the rider's
## raw power. Returns the events (an END when it runs out).
static func step_rider(
	state: SiegeState, rider: SiegeRiderState, raw_w: float, dt: float
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match rider.od_state:
		SiegeIds.OD_ACTIVE:
			if raw_w >= SprintRule.FTP_FACTOR * rider.ftp:
				rider.od_hold_s = snappedf(rider.od_hold_s + dt, 0.001)
				rider.od_best_s = maxf(rider.od_best_s, rider.od_hold_s)
			else:
				rider.od_hold_s = 0.0
			rider.od_s = maxf(snappedf(rider.od_s - dt, 0.001), 0.0)
			if rider.od_s <= 0.0:
				out.append(_end(state, rider, END_EXPIRED))
		SiegeIds.OD_COOLDOWN:
			rider.od_cd_s = maxf(snappedf(rider.od_cd_s - dt, 0.001), 0.0)
			if rider.od_cd_s <= 0.0:
				rider.od_state = SiegeIds.OD_READY
	return out


## The od factor for the rider's routed output (2 while ACTIVE and raw power >= CP = FTP).
static func multiplier(state: SiegeState, rider: SiegeRiderState, raw_w: float) -> float:
	if rider.od_state == SiegeIds.OD_ACTIVE and raw_w >= rider.ftp:
		return _num(state.content, "overdrive.od_mult", 2.0)
	return 1.0


## True when the current Overdrive already counts as scored (held >= 10 s).
static func scored_now(state: SiegeState, rider: SiegeRiderState) -> bool:
	return rider.od_best_s >= _num(state.content, "overdrive.sprint_hold_s", 10.0) - EPS


static func _end(state: SiegeState, rider: SiegeRiderState, why: String) -> Dictionary:
	var scored := scored_now(state, rider)
	if scored:
		rider.od_scored += 1
	rider.od_state = SiegeIds.OD_COOLDOWN
	rider.od_s = 0.0
	rider.od_id = 0
	rider.od_hold_s = 0.0
	rider.od_cd_s = _num(state.content, "overdrive.cooldown_s", 90.0)
	return SiegeEvents.overdrive(rider.slot, SiegeIds.OD_EV_END, scored, why)


static func _refused(state: SiegeState, rider: SiegeRiderState) -> void:
	rider.od_state = SiegeIds.OD_COOLDOWN
	rider.od_s = 0.0
	rider.od_id = 0
	rider.od_hold_s = 0.0
	rider.od_best_s = 0.0
	rider.od_cd_s = _num(state.content, "overdrive.refused_retry_s", 30.0)
	state.od_requests.erase(rider.peer)


static func _num(content: SiegeContent, path: String, default: float) -> float:
	return content.num(path, default) if content != null else default
