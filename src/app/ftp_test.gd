class_name AppFtpTest
extends RefCounted
## The FTP test protocol (BRIEF 3.2, P1), as pure logic fed with samples:
##   - a 5-minute ramp-in from 50% to 65% FTP;
##   - then one-minute ERG steps: 65% of the current FTP, rising by 6% of that FTP per step, each
##     its own 60 s ERG phase, up to min(1000 W, the trainer's max);
##   - the test ends when power < 90% of the applied target for 10 s, cadence < 50 rpm for 5 s,
##     a coast, or a rescue trigger (rescue's 50% FTP then stands; the best 1-minute power so far
##     is used); a 3-minute cool-down at 50% FTP follows (appended by the PlanValidator);
##   - new FTP = 0.75 x the best 1-minute power, saved after a 10 s countdown unless `back`.
## The governor runs the plan under its ramp_test profile (duration limits, the 105% long-phase
## cap, the 150% cap and the unverified factor suspended; slew, floor, rescue, coasting, panic
## and min(1000 W, trainer max) still apply). Time comes from the samples (platform seconds).

const RAMP_S := 300.0
const RAMP_FROM_PCT := 50.0
const RAMP_TO_PCT := 65.0
const STEP_S := 60.0
const STEP_START_PCT := 65.0
const STEP_INC_PCT := 6.0
const END_POWER_FRACTION := 0.90
const END_POWER_S := 10.0
const END_CADENCE_RPM := 50.0
const END_CADENCE_S := 5.0
const RESULT_FACTOR := 0.75
const SAVE_COUNTDOWN_S := 10.0
const MAX_TARGET_W := 1000.0
const WINDOW_S := 60.0

const END_POWER := "power"
const END_CADENCE := "cadence"
const END_COAST := "coast"
const END_RESCUE := "rescue"
const END_PLAN := "plan_end"

var ftp_w: float = 200.0
var max_w: float = MAX_TARGET_W
## "" while running, else why the test ended (END_*).
var end_reason: String = ""
var end_t: float = -1.0
var best_1m_w: float = 0.0
var _window: Array[Vector2] = []
var _window_sum: float = 0.0
var _low_power_since: float = -1.0
var _low_cadence_since: float = -1.0


static func create(p_ftp_w: float, trainer_max_w: float = MAX_TARGET_W) -> AppFtpTest:
	var t := AppFtpTest.new()
	t.ftp_w = maxf(p_ftp_w, 1.0)
	t.max_w = minf(MAX_TARGET_W, maxf(trainer_max_w, 1.0))
	return t


## Number of one-minute steps whose target stays within min(1000 W, trainer max).
func step_count() -> int:
	var n := 0
	while step_target_w(n) <= max_w and n < 200:
		n += 1
	return n


func step_target_pct(k: int) -> float:
	return STEP_START_PCT + STEP_INC_PCT * float(k)


func step_target_w(k: int) -> float:
	return ftp_w * step_target_pct(k) / 100.0


## The test plan without the cool-down (PlanValidator.finalize(plan, {"ramp_test": true}) appends
## it): the ramp-in, then one 60 s ERG phase per step.
func build_plan() -> EffortPlan:
	var plan := EffortPlan.new()
	plan.add(PlanPhase.erg(Wl.WARMUP, RAMP_FROM_PCT, RAMP_S, "Ramp-in").with_ramp(RAMP_TO_PCT).with_lap())
	for k in step_count():
		plan.add(PlanPhase.erg(Wl.WORK, step_target_pct(k), STEP_S, "Step %d" % (k + 1)).with_lap())
	return plan


func is_running() -> bool:
	return end_reason == ""


## Feed one sample (platform time t). Returns the end reason when this sample ends the test.
func feed(t: float, power_w: float, cadence_rpm: float, applied_target_w: float, rescue: bool) -> String:
	if not is_running():
		return ""
	_track_best(t, power_w)
	if rescue:
		return _end(END_RESCUE, t)
	if applied_target_w > 0.0 and power_w < END_POWER_FRACTION * applied_target_w:
		if _low_power_since < 0.0:
			_low_power_since = t
		if t - _low_power_since >= END_POWER_S - 1e-6:
			return _end(END_POWER, t)
	else:
		_low_power_since = -1.0
	if cadence_rpm < END_CADENCE_RPM:
		if _low_cadence_since < 0.0:
			_low_cadence_since = t
		if t - _low_cadence_since >= END_CADENCE_S - 1e-6:
			return _end(END_CADENCE, t)
	else:
		_low_cadence_since = -1.0
	return ""


## The rider coasted (the coast gesture): the test ends.
func on_coast(t: float) -> String:
	return _end(END_COAST, t) if is_running() else ""


## The plan ran out of steps (a very strong rider): the test ends.
func on_plan_end(t: float) -> String:
	return _end(END_PLAN, t) if is_running() else ""


## New FTP = 0.75 x the best 1-minute power (whole watts); 0 before a full minute was ridden.
func result_ftp_w() -> float:
	return round(RESULT_FACTOR * best_1m_w)


func _end(reason: String, t: float) -> String:
	end_reason = reason
	end_t = t
	return reason


## Best rolling 60 s average power (sample mean over a full 60 s window).
func _track_best(t: float, power_w: float) -> void:
	_window.append(Vector2(t, power_w))
	_window_sum += power_w
	while not _window.is_empty() and _window[0].x <= t - WINDOW_S:
		_window_sum -= _window[0].y
		_window.pop_front()
	if _window.is_empty():
		return
	if t - _window[0].x >= WINDOW_S - 1.5:
		best_1m_w = maxf(best_1m_w, _window_sum / float(_window.size()))
