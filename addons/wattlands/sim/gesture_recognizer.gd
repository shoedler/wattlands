class_name GestureRecognizer
extends RefCounted
## Pedal gestures from a rider's sample stream (BRIEF 3.5). Owned by sim; public API frozen
## after W0. Unit-tested on synthetic streams.
##   pedal_start: cadence >= 40 rpm or power >= 30% FTP for 3 s.
##   surge (confirm): outside ERG, power >= max(1.3 x its 10 s average, 10 s average + 40 W)
##     for 1.5 s (two consecutive ~1 Hz samples); inside ERG, flywheel speed >= 1.12 x its
##     10 s average for 1.5 s.
##   not_pedaling (shared detector): power < 15 W and cadence < 20 rpm. Drives coast,
##     stop_5s and the governor's coasting rule (4.6.4): is_not_pedaling() is the predicate
##     coast, stop_5s and SafetyGovernor share.
##   coast (back): not_pedaling for 3 s, never during ERG.
##   stop_5s (pause): not_pedaling for 5 s, solo and outside ERG only.
## Arbitration: within one stop, coast fires once at 3 s and stop_5s once at 5 s (each only
## where allowed); surge never fires while not_pedaling; pedal_start fires once per start
## (re-armed after not_pedaling).
## Time comes from the samples (TrainerSample.t, platform time); never the wall clock.
##
## How the rules read a ~1 Hz stream (samples arrive with jitter, BRIEF 4.5):
## - "for N s" (pedal_start, coast, stop_5s) is timed from the first sample of the stretch:
##   the gesture fires on the first sample (or advance() call) at least N s after it, so a
##   0 W rider coasts on the sample that arrives 3 s after the first stopped one.
## - surge "for 1.5 s" is two consecutive qualifying samples at least SURGE_MIN_SPAN_S apart
##   (a duplicate notification never counts twice). Both compare against the 10 s average
##   frozen when the streak's first sample arrived, so the surge never raises its own bar.
##   That baseline is the plain mean of the samples in the 10 s before the streak, counting
##   only samples from the moment pedal_start fired and since the pedal_start condition last
##   held without a break (W4, ZIH-2: never the spin-up before it, nor a soft-pedal dip), and
##   it needs at least SURGE_MIN_HISTORY_S of such history. A surge therefore needs pedaling
##   to be established (pedal_start fired since the last stop) and 5 s of steady riding after
##   that, so starting to pedal, or coming back from a dip, is never a surge: the low samples
##   of a spin-up from rest never pull the baseline under a rider who then just settles.
##   One surge per streak: a sample that doesn't qualify re-arms it.
## - Any not_pedaling sample ends the current start: it re-arms pedal_start and clears the
##   surge history. A stop that reaches 3 s (or 5 s) while in ERG (or, for stop_5s, in
##   multiplayer) uses up coast (or stop_5s) for that stop, so leaving ERG later in the same
##   stop never fires a stale "back".

## A gesture fired (Wl.G_*).
signal gesture(gesture_name: StringName)
## The shared not_pedaling detector changed (true on the first sample that meets it).
signal not_pedaling_changed(active: bool)

## Name of the shared detector (BRIEF 3.5); a state (not_pedaling()), never a fired gesture.
const NOT_PEDALING := &"not_pedaling"
const PEDAL_START_S := 3.0
const PEDAL_START_RPM := 40.0
const PEDAL_START_FTP_FRACTION := 0.30
## The shared not_pedaling thresholds (BRIEF 3.5), written only here. SafetyGovernor and
## CadenceEstimator use these constants, and GameHost's rejoin "shows pedaling" check calls
## is_not_pedaling(), so no other copy of 15 W and 20 rpm exists.
const NOT_PEDALING_W := 15.0
const NOT_PEDALING_RPM := 20.0
const COAST_S := 3.0
const STOP_S := 5.0
const SURGE_WINDOW_S := 10.0
const SURGE_POWER_FACTOR := 1.3
const SURGE_POWER_ADD_W := 40.0
const SURGE_SPEED_FACTOR := 1.12
## Consecutive qualifying samples a surge needs ("1.5 s at about 1 Hz").
const SURGE_SAMPLES := 2
## The qualifying samples must span at least this long (guards duplicate notifications).
const SURGE_MIN_SPAN_S := 0.5
## Pedaling history (since the last not_pedaling sample) the 10 s baseline needs.
const SURGE_MIN_HISTORY_S := 5.0
## advance() holds the latest sample's state at most this long after it arrived.
const HOLD_MAX_S := 2.5
const EPS := 1e-6

var ftp_w: float = 200.0
var solo: bool = true
var in_erg: bool = false

## Recent pedaling samples since the last stop: {t, power_w, speed_kmh (-1 if absent)}.
var _history: Array[Dictionary] = []
var _last_t: float = -INF
var _have_sample: bool = false
var _last_np: bool = false
var _last_pedal_cond: bool = false
## Not pedaling: t of the stretch's first sample (-1 while pedaling).
var _np_since: float = -1.0
var _coast_done: bool = false
var _stop_done: bool = false
## Pedaling condition: t of the streak's first sample (-1 while the condition fails).
var _pedal_since: float = -1.0
var _pedal_armed: bool = true
## True between pedal_start and the next not_pedaling sample.
var _pedaling: bool = false
## Platform time pedal_start fired for the current start (-1 before): the surge baseline counts
## only samples from then on (ZIH-2).
var _pedal_start_t: float = -1.0
## Surge streak: qualifying samples, the first one's t, the frozen baseline, fired.
var _surge_count: int = 0
var _surge_first_t: float = -1.0
var _surge_baseline: float = -1.0
var _surge_fired: bool = false


## ftp_w for the 30% rule; solo enables stop_5s.
func configure(p_ftp_w: float, p_solo: bool) -> void:
	ftp_w = maxf(p_ftp_w, 0.0)
	solo = p_solo


## Whether the rider's trainer is in ERG right now (switches surge to the speed rule and
## suppresses coast/stop_5s).
func set_erg(p_in_erg: bool) -> void:
	if p_in_erg != in_erg:
		_clear_surge_streak()
	in_erg = p_in_erg


## Feed one sample; returns the gestures fired by it (also emitted).
func on_sample(sample: TrainerSample) -> Array[StringName]:
	var fired: Array[StringName] = []
	if sample == null:
		return fired
	var t := sample.t
	if _have_sample and t < _last_t:
		push_warning(
			"GestureRecognizer: sample at t=%.3f is older than t=%.3f; ignored" % [t, _last_t]
		)
		return fired
	var cadence := sample.cadence_rpm if sample.has_cadence() else -1.0
	var power := sample.power_w
	var speed := sample.speed_kmh if sample.has_speed() else -1.0
	var np := is_not_pedaling(power, cadence)
	_have_sample = true
	_last_t = t

	# The shared not_pedaling detector. A stop ends the current start.
	if np:
		if not _last_np:
			_np_since = t
			_coast_done = false
			_stop_done = false
			_last_np = true
			not_pedaling_changed.emit(true)
		_pedal_armed = true
		_pedaling = false
		_pedal_start_t = -1.0
		_history.clear()
		_clear_surge_streak()
	elif _last_np:
		_np_since = -1.0
		_last_np = false
		not_pedaling_changed.emit(false)

	# pedal_start condition (timed in _fire_timed).
	var by_power := power > 0.0 and power >= PEDAL_START_FTP_FRACTION * ftp_w
	var cond := cadence >= PEDAL_START_RPM or by_power
	var was_cond := _last_pedal_cond
	_last_pedal_cond = cond and not np
	if not _last_pedal_cond:
		_pedal_since = -1.0
	elif not was_cond:
		_pedal_since = t

	# surge: checked before this sample joins the history (its baseline is the 10 s before).
	if not np:
		if _surge_check(t, power, speed):
			fired.append(Wl.G_SURGE)
		_history.append({"t": t, "power_w": power, "speed_kmh": speed})
		_prune_history(t)

	_fire_timed(t, fired)
	for g in fired:
		gesture.emit(g)
	return fired


## Fires the time-based gestures (pedal_start, coast, stop_5s) due at platform time `t`
## between samples, holding the latest sample's state for at most HOLD_MAX_S. Optional:
## on_sample alone fires them on the first sample at or after their time. Returns them
## (also emitted).
func advance(t: float) -> Array[StringName]:
	var fired: Array[StringName] = []
	if not _have_sample or t < _last_t or t - _last_t > HOLD_MAX_S + EPS:
		return fired
	_fire_timed(t, fired)
	for g in fired:
		gesture.emit(g)
	return fired


## The shared not_pedaling detector on a single sample (BRIEF 3.5): power < NOT_PEDALING_W and
## cadence < NOT_PEDALING_RPM, strict on both edges (15 W, or 20 rpm, is pedaling). Pass -1 for
## an absent cadence: it counts as low. on_sample() (coast, stop_5s) and SafetyGovernor
## (coasting 4.6.4, the warm-up's pedal strokes) both call it; GameHost's rejoin check still
## inverts its own copy inline (see NOT_PEDALING_W).
static func is_not_pedaling(power_w: float, cadence_rpm: float) -> bool:
	return power_w < NOT_PEDALING_W and cadence_rpm < NOT_PEDALING_RPM


## True while the latest sample meets not_pedaling.
func not_pedaling() -> bool:
	return _last_np


## Seconds the current not_pedaling stretch has lasted (from its first sample).
func not_pedaling_s() -> float:
	if not _last_np:
		return 0.0
	return maxf(_last_t - _np_since, 0.0)


## Seconds the current not_pedaling stretch has lasted at platform time `t` (for a rule that
## ticks between samples, like the governor's coasting). 0 while pedaling.
func not_pedaling_s_at(t: float) -> float:
	if not _last_np:
		return 0.0
	return maxf(t - _np_since, 0.0)


## Platform time of the current not_pedaling stretch's first sample, or -1 while pedaling.
func not_pedaling_since() -> float:
	return _np_since if _last_np else -1.0


## True between pedal_start and the next not_pedaling sample.
func is_pedaling() -> bool:
	return _pedaling


## The 10 s average a surge streak starting now would compare against (power outside ERG,
## flywheel speed in ERG), or -1 without enough pedaling history.
func surge_baseline() -> float:
	return _baseline(_last_t + EPS)


func reset() -> void:
	_history.clear()
	_last_t = -INF
	_have_sample = false
	_last_np = false
	_last_pedal_cond = false
	_np_since = -1.0
	_coast_done = false
	_stop_done = false
	_pedal_since = -1.0
	_pedal_armed = true
	_pedaling = false
	_pedal_start_t = -1.0
	_clear_surge_streak()


func _fire_timed(t: float, fired: Array[StringName]) -> void:
	if _last_pedal_cond and _pedal_armed and t - _pedal_since >= PEDAL_START_S - EPS:
		_pedal_armed = false
		_pedaling = true
		_pedal_start_t = t
		fired.append(Wl.G_PEDAL_START)
	if _last_np:
		var stopped := t - _np_since
		if not _coast_done and stopped >= COAST_S - EPS:
			_coast_done = true
			if not in_erg:
				fired.append(Wl.G_COAST)
		if not _stop_done and stopped >= STOP_S - EPS:
			_stop_done = true
			if solo and not in_erg:
				fired.append(Wl.G_STOP_5S)


## True when this sample completes a surge.
func _surge_check(t: float, power: float, speed: float) -> bool:
	var value := speed if in_erg else power
	if not _pedaling or value < 0.0:
		_clear_surge_streak()
		return false
	var baseline := _surge_baseline if _surge_count > 0 else _baseline(t)
	if baseline < 0.0 or not _qualifies(value, baseline):
		_clear_surge_streak()
		return false
	if _surge_count == 0:
		_surge_first_t = t
		_surge_baseline = baseline
	_surge_count += 1
	if _surge_fired:
		return false
	if _surge_count >= SURGE_SAMPLES and t - _surge_first_t >= SURGE_MIN_SPAN_S - EPS:
		_surge_fired = true
		return true
	return false


func _qualifies(value: float, baseline: float) -> bool:
	if in_erg:
		return baseline > 0.0 and value >= SURGE_SPEED_FACTOR * baseline - EPS
	var bar := maxf(SURGE_POWER_FACTOR * baseline, baseline + SURGE_POWER_ADD_W)
	return value >= bar - EPS


## Mean of the history in [t - 10 s, t) for the current mode's quantity, counting only samples
## from pedal_start and from the start of the current unbroken pedal_start-condition streak
## on, or -1 when that history is shorter than SURGE_MIN_HISTORY_S (or pedaling isn't
## established).
func _baseline(t: float) -> float:
	if _pedal_start_t < 0.0 or _pedal_since < 0.0:
		return -1.0
	# History counts from pedal_start, or from the end of a later soft-pedal dip (ZIH-2).
	var origin := maxf(_pedal_start_t, _pedal_since)
	var key := "speed_kmh" if in_erg else "power_w"
	var total := 0.0
	var n := 0
	var oldest := INF
	for h in _history:
		var ht: float = h["t"]
		if ht >= t - EPS or ht < t - SURGE_WINDOW_S - EPS or ht < origin - EPS:
			continue
		var v: float = h[key]
		if v < 0.0:
			continue
		total += v
		n += 1
		oldest = minf(oldest, ht)
	if n == 0 or t - oldest < SURGE_MIN_HISTORY_S - EPS:
		return -1.0
	return total / float(n)


func _prune_history(t: float) -> void:
	while not _history.is_empty() and float(_history[0]["t"]) < t - SURGE_WINDOW_S - 1.0:
		_history.pop_front()


func _clear_surge_streak() -> void:
	_surge_count = 0
	_surge_first_t = -1.0
	_surge_baseline = -1.0
	_surge_fired = false
