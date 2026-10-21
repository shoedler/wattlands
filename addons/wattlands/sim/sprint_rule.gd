class_name SprintRule
extends RefCounted
## The stricter sprint rule games use where they score a sprint (BRIEF 3.5): power
## >= 1.2 x FTP. Owned by sim; public API frozen after W0.
## Feed power each sim step (or each sample); holds() is true while the rule held over the
## trailing `window_s` (default 0: instantaneous), held_s() counts the current streak.
##
## Each update(t, power) stands for the power since the previous update (sample and hold
## backwards), so a 1 Hz sample at t covers (t - 1, t] and a sim-step update covers its step.
## - window_s 0: holds() while the latest power >= threshold_w().
## - window_s > 0: holds() while the time-weighted average over (t - window_s, t] is
##   >= threshold_w(); it needs updates covering the whole window first (Tank's Ram: "over
##   the last 3 s").
## - held_s(): from the start of the interval of the first update that held (its previous
##   update's time; the first update ever covers no time) to the latest update. 0 when not
##   holding. best_s(): the longest streak so far, the current one included.
## Updates with an older t than the latest are ignored; one with the same t replaces it.
## The caller picks the clock (game time for scoring); nothing reads the wall clock.

const FTP_FACTOR := 1.2
const EPS := 1e-9

var ftp_w: float = 200.0
## Trailing window the average must exceed 1.2 x FTP over (e.g. 3.0 for Tank's Ram).
var window_s: float = 0.0

## Recent updates: [t, power_w], oldest first; the first one only marks a start time.
var _samples: Array[PackedFloat64Array] = []
var _holds: bool = false
var _streak_start: float = 0.0
var _held: float = 0.0
var _best: float = 0.0


static func create(p_ftp_w: float, p_window_s: float = 0.0) -> SprintRule:
	var r := SprintRule.new()
	r.ftp_w = p_ftp_w
	r.window_s = p_window_s
	return r


func threshold_w() -> float:
	return FTP_FACTOR * ftp_w


## Feed power at time t (seconds, any monotonic clock the caller uses consistently).
func update(t: float, power_w: float) -> void:
	if not _samples.is_empty():
		var last_t: float = _samples[-1][0]
		if t < last_t:
			return
		if t == last_t:
			_samples[-1] = PackedFloat64Array([t, power_w])
			_evaluate()
			return
	_samples.append(PackedFloat64Array([t, power_w]))
	_prune(t)
	_evaluate()


## True while the rule holds (over window_s if set).
func holds() -> bool:
	return _holds


## Seconds the current streak has held (0 when not holding).
func held_s() -> float:
	return _held if _holds else 0.0


## Longest streak so far, seconds.
func best_s() -> float:
	return _best


## The power the rule compares now: the latest power (window 0) or the trailing window's
## time-weighted average (-1 until the window is covered).
func current_w() -> float:
	if _samples.is_empty():
		return -1.0
	if window_s <= 0.0:
		return _samples[-1][1]
	var t_now: float = _samples[-1][0]
	var start := t_now - window_s
	if _samples[0][0] > start + EPS:
		return -1.0
	var energy := 0.0
	for i in range(1, _samples.size()):
		var a: float = maxf(_samples[i - 1][0], start)
		var b: float = _samples[i][0]
		if b > a:
			energy += _samples[i][1] * (b - a)
	return energy / window_s


func reset() -> void:
	_samples.clear()
	_holds = false
	_streak_start = 0.0
	_held = 0.0
	_best = 0.0


func _evaluate() -> void:
	var t_now: float = _samples[-1][0]
	var p := current_w()
	var now_holds := p >= 0.0 and p >= threshold_w() - EPS
	if now_holds and not _holds:
		# The streak starts where the first holding update's interval starts.
		_streak_start = _samples[-2][0] if _samples.size() >= 2 else t_now
	_holds = now_holds
	if _holds:
		_held = maxf(t_now - _streak_start, 0.0)
		_best = maxf(_best, _held)
	else:
		_held = 0.0


## Keeps the updates the window needs plus the one marking its start; with window 0 only
## the latest two.
func _prune(t_now: float) -> void:
	var start := t_now - maxf(window_s, 0.0)
	while _samples.size() > 2 and _samples[1][0] <= start + EPS:
		_samples.pop_front()
