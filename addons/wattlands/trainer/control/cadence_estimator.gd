class_name CadenceEstimator
extends RefCounted
## Cadence when the trainer doesn't report it (BRIEF 4.5): use FTMS cadence when present;
## estimate it from flywheel speed when absent or stale (older than `stale_s`), learning the
## speed-to-cadence ratio while both are valid, or from a 10 s calibration at 90 rpm.
## Owned by trainer-control; public API frozen after W0. LocalRider passes every sample
## through process() before gestures, the governor and telemetry use it.
##
## Rules (W1):
##   - Present and fresh: the sample is returned unchanged, and while cadence >= MIN_LEARN_RPM
##     and speed >= MIN_LEARN_KMH the km/h-per-rpm ratio is learned (exponential average).
##     A reported value that repeats while the speed moved by more than FROZEN_SPEED_CHANGE
##     since it last changed teaches nothing (it may be a frozen trainer estimate).
##   - Absent: estimated as speed / ratio, with HAS_CADENCE and CADENCE_ESTIMATED set.
##   - Stale: a reported cadence that has not changed for more than `stale_s` while the speed
##     moved by more than STALE_SPEED_CHANGE (a frozen trainer estimate, for example after a
##     sprint) is replaced by the estimate too.
##   - No ratio yet (or no speed): the sample is returned unchanged.
##   - A sample that arrives already marked CADENCE_ESTIMATED is passed through untouched.
##   - Coasting (W2r2): with a reported power below COAST_POWER_W (BRIEF 3.5 not_pedaling:
##     15 W) the flywheel's speed is momentum, not pedaling, so nothing is estimated from it:
##     a reported cadence is kept even when unchanged while the flywheel spins down (a crank
##     at rest reads 0 and stays 0), and an absent one stays absent. Otherwise a coasting
##     rider's spinning flywheel would read as pedaling, hiding the governor's coasting,
##     pause and AFK rules (4.6.4), stop_5s and the warm-up's 20-minute reset (4.6.8).
## Time comes from sample.t only (platform time); nothing reads the wall clock.

var stale_s: float = 3.0

const MIN_LEARN_RPM := 40.0
const MIN_LEARN_KMH := 5.0
const LEARN_ALPHA := 0.1
const CALIBRATION_S := 10.0
## Relative speed change that marks an unchanged cadence as stale.
const STALE_SPEED_CHANGE := 0.15
## Relative speed change that stops learning from a repeated cadence value.
const FROZEN_SPEED_CHANGE := 0.05
## Reported power below this means the rider isn't pedaling (BRIEF 3.5 not_pedaling), so no
## cadence is estimated from the flywheel's speed (W2r2). The shared detector's power threshold.
const COAST_POWER_W := GestureRecognizer.NOT_PEDALING_W

var _ratio: float = 0.0
var _calibrating: bool = false
var _cal_target_rpm: float = 90.0
var _cal_start_t: float = -1.0
var _cal_sum_kmh: float = 0.0
var _cal_n: int = 0
var _last_reported_rpm: float = -1.0
var _reported_changed_t: float = -1.0
var _speed_at_change_kmh: float = -1.0
var _last_fresh_t: float = -1.0


## Returns `sample` (or a copy) with cadence filled in and TrainerSample.CADENCE_ESTIMATED
## set when it had to be estimated; unchanged when cadence is present and fresh or no ratio
## is known yet.
func process(sample: TrainerSample) -> TrainerSample:
	if sample == null:
		return null
	if (sample.flags & TrainerSample.CADENCE_ESTIMATED) != 0:
		_last_fresh_t = sample.t
		return sample
	var was_calibrating := _calibrating
	if _calibrating:
		_calibrate(sample)
	var present := sample.has_cadence()
	var stale := false
	var repeated_while_moving := false
	if present:
		if _last_reported_rpm < 0.0 or absf(sample.cadence_rpm - _last_reported_rpm) > 1e-6:
			_last_reported_rpm = sample.cadence_rpm
			_reported_changed_t = sample.t
			_speed_at_change_kmh = sample.speed_kmh if sample.has_speed() else -1.0
		elif sample.has_speed() and _speed_at_change_kmh >= 0.0:
			var moved := absf(sample.speed_kmh - _speed_at_change_kmh)
			var ref := maxf(_speed_at_change_kmh, MIN_LEARN_KMH)
			repeated_while_moving = moved > FROZEN_SPEED_CHANGE * ref
			stale = sample.t - _reported_changed_t > stale_s and moved > STALE_SPEED_CHANGE * ref
	var coasting := (sample.flags & TrainerSample.HAS_POWER) != 0 and sample.power_w < COAST_POWER_W
	if stale and coasting:
		# A spinning-down flywheel under a resting crank: the reading is right, not frozen.
		stale = false
	if present and not stale:
		if not was_calibrating and not repeated_while_moving:
			_learn(sample)
		_last_fresh_t = sample.t
		return sample
	if _ratio <= 0.0 or not sample.has_speed() or coasting:
		return sample
	var est := TrainerSample.new()
	est.t = sample.t
	est.power_w = sample.power_w
	est.speed_kmh = sample.speed_kmh
	est.distance_m = sample.distance_m
	est.cadence_rpm = maxf(0.0, sample.speed_kmh / _ratio)
	est.flags = sample.flags | TrainerSample.HAS_CADENCE | TrainerSample.CADENCE_ESTIMATED
	_last_fresh_t = sample.t
	return est


## Start a 10 s calibration: the rider holds 90 rpm; samples during it set the ratio.
func start_calibration(_target_rpm: float = 90.0) -> void:
	if _target_rpm <= 0.0:
		push_error("CadenceEstimator: calibration target must be > 0 rpm")
		return
	_calibrating = true
	_cal_target_rpm = _target_rpm
	_cal_start_t = -1.0
	_cal_sum_kmh = 0.0
	_cal_n = 0


func is_calibrating() -> bool:
	return _calibrating


## Learned km/h per rpm (0 when unknown).
func ratio() -> float:
	return _ratio


## Seconds from the last fresh cadence (measured or estimated) to `now_t`; INF before any.
## Added in W1 for Telemetry.cadence_age_s.
func cadence_age_s(now_t: float) -> float:
	if _last_fresh_t < 0.0:
		return INF
	return maxf(0.0, now_t - _last_fresh_t)


## Forget the learned ratio and any calibration (a new trainer or a gear change on a
## cassette that makes the old ratio wrong). Added in W1.
func reset() -> void:
	_ratio = 0.0
	_calibrating = false
	_cal_start_t = -1.0
	_cal_sum_kmh = 0.0
	_cal_n = 0
	_last_reported_rpm = -1.0
	_reported_changed_t = -1.0
	_speed_at_change_kmh = -1.0
	_last_fresh_t = -1.0


func _learn(sample: TrainerSample) -> void:
	if not sample.has_speed():
		return
	if sample.cadence_rpm < MIN_LEARN_RPM or sample.speed_kmh < MIN_LEARN_KMH:
		return
	var r := sample.speed_kmh / sample.cadence_rpm
	_ratio = r if _ratio <= 0.0 else lerpf(_ratio, r, LEARN_ALPHA)


func _calibrate(sample: TrainerSample) -> void:
	if not sample.has_speed() or sample.speed_kmh <= 0.0:
		return
	if _cal_start_t < 0.0:
		_cal_start_t = sample.t
	_cal_sum_kmh += sample.speed_kmh
	_cal_n += 1
	if sample.t - _cal_start_t >= CALIBRATION_S - 1e-6 and _cal_n > 0:
		_ratio = (_cal_sum_kmh / float(_cal_n)) / _cal_target_rpm
		_calibrating = false
