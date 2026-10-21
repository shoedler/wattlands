class_name FtpTest
extends RefCounted
## The FTP ramp test (BRIEF 3.2, P1, in Settings). Owned by platform.
##
## Protocol: a 5-minute ramp-in from 50% to 65% FTP, then one-minute ERG steps starting at
## 65% of the current FTP and rising by 6% of that FTP per step, each its own 60 s ERG
## phase, up to min(1000 W, the trainer's max). It runs under the governor's "ramp_test"
## profile (duration limits, the 150% cap, the long-phase cap and the unverified factor
## don't apply; slew, the floor, rescue, coasting and panic do).
## The test ends at once on a rescue or on coasting, after 10 s with power below 90% of the
## applied ERG target, after 5 s with a fresh cadence below 50 rpm, on back(), or after the
## last step ("complete"). A 3-minute cool-down at 50% FTP follows at once (rescue's 50%
## stands; nothing ramps back into a step). FTP = 0.75 x the best 1-minute power so far.
## A result counts only if the test reached the steps and wasn't ended with back(); it is
## saved after a 10 s countdown (shown at the start of the cool-down) unless back() cancels.
##
## The logic is pure: start() builds the plan and step(dt, telemetry) advances it, emitting
## phase_requested(index) for the driver. run_on(rider) drives a LocalRider: it sets the
## governor's ramp_test profile and the plan, follows the rider's telemetry, starts each
## phase, saves the FTP through WlSettings (ftp_w, cp_w = FTP, ftp_verified) and restores
## the "normal" profile when the cool-down ends or stop() is called. While it runs, the
## TrainerService holds its rider so the saved profile doesn't rebuild it mid-cool-down.

## The driver should start plan phase `index` now.
signal phase_requested(index: int)
## "idle", "ramp_in", "steps", "cooldown", "done".
signal state_changed(state: String)
## The test part ended: the result (see result()).
signal ended(result: Dictionary)
## Whole seconds left before the FTP is saved (10 .. 1).
signal countdown(seconds_left: int)
## The FTP was accepted (after the countdown).
signal saved(ftp_w: float)
## The cool-down ended: the final result.
signal finished(result: Dictionary)

const RAMP_IN_S := 300.0
const RAMP_FROM_PCT := 50.0
const RAMP_TO_PCT := 65.0
const STEP_S := 60.0
const STEP_START_PCT := 65.0
const STEP_INC_PCT := 6.0
const ABS_MAX_W := 1000.0
const MAX_STEPS := 120
const LOW_POWER_FRACTION := 0.9
const LOW_POWER_S := 10.0
const LOW_CADENCE_RPM := 50.0
const LOW_CADENCE_S := 5.0
## A cadence older than this (Telemetry.cadence_age_s) doesn't count for the cadence rule.
const CADENCE_FRESH_S := 3.0
const FTP_FACTOR := 0.75
const BEST_WINDOW_S := 60.0
const SAVE_COUNTDOWN_S := 10.0

const IDLE := "idle"
const RAMP_IN := "ramp_in"
const STEPS := "steps"
const COOLDOWN := "cooldown"
const DONE := "done"

const END_POWER := "power"
const END_CADENCE := "cadence"
const END_COASTING := "coasting"
const END_RESCUE := "rescue"
const END_BACK := "back"
const END_COMPLETE := "complete"

const EPS := 1e-9

var state: String = IDLE
var ftp_w: float = 200.0
var plan: EffortPlan = null
## The plan phase the test is in (0 ramp-in, 1.. steps, last the cool-down).
var phase_index: int = -1
var phase_elapsed_s: float = 0.0
## Seconds since start() (test and cool-down).
var elapsed_s: float = 0.0
var steps_completed: int = 0
var best_1min_w: float = 0.0
var end_reason: String = ""

var _step_count: int = 0
var _low_power_s: float = 0.0
var _low_cadence_s: float = 0.0
var _win: Array = []
var _win_t: float = 0.0
var _win_e: float = 0.0
var _countdown_left: float = -1.0
var _result: Dictionary = {}
var _rider: LocalRider = null
var _settings: WlSettings = null
var _service: WlTrainerService = null
var _last_t: float = -1.0


## Dropped while driving a rider (the screen let go of it without stop()): release the
## rider's ramp_test profile and the TrainerService hold, so menus never stay held. (Inline:
## a RefCounted can't call its own methods during PREDELETE; the rider's connection to this
## object goes away with it.)
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if _rider != null and is_instance_valid(_rider):
		_rider.configure_governor({"profile": "normal"})
	_rider = null
	if _service != null and is_instance_valid(_service):
		_service.hold_rider(false)
	_service = null


## Steps the plan holds for `p_ftp_w` on a trainer with `trainer_max_w`: every step whose
## target stays at or below min(1000 W, trainer max), at least 1, at most MAX_STEPS.
static func step_count(p_ftp_w: float, trainer_max_w: float = 1800.0) -> int:
	var ceiling := minf(ABS_MAX_W, trainer_max_w if trainer_max_w > 0.0 else ABS_MAX_W)
	var n := 0
	while n < MAX_STEPS and step_pct(n + 1) * p_ftp_w / 100.0 <= ceiling + EPS:
		n += 1
	return maxi(n, 1)


## Target of step `n` (1-based) in % of the current FTP: 65, 71, 77, ...
static func step_pct(n: int) -> float:
	return STEP_START_PCT + STEP_INC_PCT * float(n - 1)


## The ramp_test plan: ramp-in, the steps and the standard cool-down (cooldown_appended).
static func build_plan(p_ftp_w: float, trainer_max_w: float = 1800.0) -> EffortPlan:
	var p := EffortPlan.new()
	p.add(PlanPhase.erg(Wl.WARMUP, RAMP_FROM_PCT, RAMP_IN_S, TranslationServer.translate("CORE_FTP_RAMP_IN"))
		.with_ramp(RAMP_TO_PCT).with_lap())
	var step_label := TranslationServer.translate("CORE_FTP_STEP")
	for n in range(1, step_count(p_ftp_w, trainer_max_w) + 1):
		p.add(PlanPhase.erg(Wl.WORK, step_pct(n), STEP_S, step_label.replace("{n}", str(n))).with_lap())
	p.add(PlanValidator.cooldown_phase())
	p.cooldown_appended = true
	return p


## The strings key for an end reason (CORE_FTP_END_*).
static func end_reason_key(reason: String) -> String:
	return "CORE_FTP_END_" + reason.to_upper()


## Begin a test for `p_ftp_w`: builds the plan, enters the ramp-in and requests phase 0.
func start(p_ftp_w: float, trainer_max_w: float = 1800.0) -> EffortPlan:
	return _begin(build_plan(maxf(p_ftp_w, 1.0), trainer_max_w), p_ftp_w)


func _begin(p_plan: EffortPlan, p_ftp_w: float) -> EffortPlan:
	ftp_w = maxf(p_ftp_w, 1.0)
	plan = p_plan
	_step_count = plan.size() - 2
	phase_index = 0
	phase_elapsed_s = 0.0
	elapsed_s = 0.0
	steps_completed = 0
	best_1min_w = 0.0
	end_reason = ""
	_low_power_s = 0.0
	_low_cadence_s = 0.0
	_win.clear()
	_win_t = 0.0
	_win_e = 0.0
	_countdown_left = -1.0
	_result = {}
	_set_state(RAMP_IN)
	phase_requested.emit(0)
	return plan


## Advance by dt seconds with the rider's latest telemetry.
func step(dt: float, tel: Telemetry) -> void:
	if dt <= 0.0 or tel == null:
		return
	match state:
		RAMP_IN, STEPS:
			_step_test(dt, tel)
		COOLDOWN:
			_step_cooldown(dt)


## `back`: ends a running test (no result saved) or cancels the save countdown.
func back() -> void:
	match state:
		RAMP_IN, STEPS:
			_end_test(END_BACK)
		COOLDOWN:
			if _countdown_left > 0.0:
				_countdown_left = -1.0
				_result["cancelled"] = true


## {end_reason, ftp_w (whole watts), best_1min_w, steps_completed, last_step_pct, valid,
##  saved, cancelled, test_s}; empty until the test ended.
func result() -> Dictionary:
	return _result.duplicate(true)


## Seconds left before the save (-1 when no countdown runs).
func countdown_left() -> float:
	return _countdown_left


func is_running() -> bool:
	return state == RAMP_IN or state == STEPS or state == COOLDOWN


## Drive `rider` (normally TrainerService.local_rider()): ramp_test profile, the plan,
## phases, telemetry; saves through `p_settings` (default the Settings autoload). Returns
## the plan.
func run_on(rider: LocalRider, p_settings: WlSettings = null, p_service: WlTrainerService = null) -> EffortPlan:
	_detach()
	_rider = rider
	_settings = p_settings if p_settings != null else AutoloadLookup.settings()
	_service = p_service if p_service != null else AutoloadLookup.trainer_service()
	if _service != null:
		_service.hold_rider(true)
	rider.configure_governor({"profile": "ramp_test"})
	var max_w := float(rider.governor_params().get("trainer_max_w", 1800))
	phase_requested.connect(_on_phase_requested)
	saved.connect(_on_saved)
	finished.connect(_on_finished)
	rider.telemetry_updated.connect(_on_telemetry)
	_last_t = rider.platform_time()
	var p := build_plan(maxf(rider.ftp_w(), 1.0), max_w)
	rider.set_plan(p)
	return _begin(p, rider.ftp_w())


## Stop driving the rider (leaving Settings mid-test): back to the normal governor profile.
func stop() -> void:
	if state == RAMP_IN or state == STEPS:
		end_reason = END_BACK
		if _rider != null and is_instance_valid(_rider) and plan != null:
			_rider.start_phase(plan.cooldown_index())
	if state != IDLE:
		_set_state(DONE)
	_countdown_left = -1.0
	_detach()


# --- internals ------------------------------------------------------------------------------


func _step_test(dt: float, tel: Telemetry) -> void:
	elapsed_s += dt
	phase_elapsed_s += dt
	_track_best(dt, maxf(tel.power_w, 0.0))
	var reason := _end_condition(dt, tel)
	if reason != "":
		_end_test(reason)
		return
	var length := RAMP_IN_S if phase_index == 0 else STEP_S
	if phase_elapsed_s + EPS >= length:
		if phase_index > 0:
			steps_completed += 1
		if phase_index >= _step_count:
			_end_test(END_COMPLETE)
			return
		phase_index += 1
		phase_elapsed_s = maxf(phase_elapsed_s - length, 0.0)
		if state == RAMP_IN:
			_set_state(STEPS)
		phase_requested.emit(phase_index)


func _end_condition(dt: float, tel: Telemetry) -> String:
	if tel.rescue:
		return END_RESCUE
	if tel.coasting:
		return END_COASTING
	if tel.mode == Wl.ERG and tel.applied_target_w > 0 and tel.power_w < LOW_POWER_FRACTION * float(tel.applied_target_w):
		_low_power_s += dt
	else:
		_low_power_s = 0.0
	if _low_power_s + EPS >= LOW_POWER_S:
		return END_POWER
	if tel.cadence_age_s <= CADENCE_FRESH_S and tel.cadence_rpm < LOW_CADENCE_RPM:
		_low_cadence_s += dt
	else:
		_low_cadence_s = 0.0
	if _low_cadence_s + EPS >= LOW_CADENCE_S:
		return END_CADENCE
	return ""


## Sliding 60 s window of power x time; best_1min_w is its best full-window mean.
func _track_best(dt: float, power_w: float) -> void:
	_win.append([dt, power_w])
	_win_t += dt
	_win_e += dt * power_w
	while _win_t - BEST_WINDOW_S > EPS and not _win.is_empty():
		var excess := _win_t - BEST_WINDOW_S
		var front: Array = _win[0]
		var fdt: float = front[0]
		if fdt <= excess + EPS:
			_win.pop_front()
			_win_t -= fdt
			_win_e -= fdt * float(front[1])
		else:
			front[0] = fdt - excess
			_win_t -= excess
			_win_e -= excess * float(front[1])
	if _win_t + EPS >= BEST_WINDOW_S:
		best_1min_w = maxf(best_1min_w, _win_e / BEST_WINDOW_S)


func _end_test(reason: String) -> void:
	end_reason = reason
	var reached_steps := state == STEPS
	var valid := reached_steps and reason != END_BACK and best_1min_w > 0.0
	var last_pct := step_pct(phase_index) if phase_index > 0 else plan.phase(0).planned_pct_at(phase_elapsed_s)
	_result = {
		"end_reason": reason,
		"ftp_w": roundf(FTP_FACTOR * best_1min_w),
		"best_1min_w": best_1min_w,
		"steps_completed": steps_completed,
		"last_step_pct": last_pct,
		"valid": valid,
		"saved": false,
		"cancelled": false,
		"test_s": elapsed_s,
	}
	phase_index = plan.cooldown_index()
	phase_elapsed_s = 0.0
	_set_state(COOLDOWN)
	phase_requested.emit(phase_index)
	ended.emit(result())
	if valid:
		_countdown_left = SAVE_COUNTDOWN_S
		countdown.emit(int(SAVE_COUNTDOWN_S))


func _step_cooldown(dt: float) -> void:
	elapsed_s += dt
	phase_elapsed_s += dt
	if _countdown_left > 0.0:
		var before := ceili(_countdown_left - EPS)
		_countdown_left -= dt
		if _countdown_left <= EPS:
			_countdown_left = -1.0
			_result["saved"] = true
			saved.emit(float(_result["ftp_w"]))
		else:
			var now := ceili(_countdown_left - EPS)
			if now != before:
				countdown.emit(now)
	if phase_elapsed_s + EPS >= PlanValidator.COOLDOWN_S:
		_set_state(DONE)
		finished.emit(result())


func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


func _on_phase_requested(index: int) -> void:
	if _rider != null and is_instance_valid(_rider):
		_rider.start_phase(index)


func _on_telemetry(tel: Telemetry) -> void:
	var dt := tel.t - _last_t
	_last_t = tel.t
	step(dt, tel)


func _on_saved(p_ftp_w: float) -> void:
	if _settings == null or p_ftp_w <= 0.0:
		return
	_settings.profile.ftp_w = p_ftp_w
	_settings.profile.cp_w = p_ftp_w
	_settings.profile.ftp_verified = true
	_settings.save_profile()


func _on_finished(_r: Dictionary) -> void:
	_detach()


func _detach() -> void:
	if _rider != null and is_instance_valid(_rider):
		if _rider.telemetry_updated.is_connected(_on_telemetry):
			_rider.telemetry_updated.disconnect(_on_telemetry)
		_rider.configure_governor({"profile": "normal"})
	for pair: Array in [[phase_requested, _on_phase_requested], [saved, _on_saved], [finished, _on_finished]]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)
	if _service != null and is_instance_valid(_service):
		_service.hold_rider(false)
	_rider = null
	_service = null
