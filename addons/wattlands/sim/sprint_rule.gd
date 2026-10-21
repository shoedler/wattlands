class_name SprintRule
extends RefCounted
## The stricter sprint rule games use where they score a sprint (BRIEF 3.5): power
## >= 1.2 x FTP. Owned by sim; public API frozen after W0.
## Feed power each sim step (or each sample); holds() is true while the rule held over the
## trailing `window_s` (default 0: instantaneous), held_s() counts the current streak.

const FTP_FACTOR := 1.2

var ftp_w: float = 200.0
## Trailing window the average must exceed 1.2 x FTP over (e.g. 3.0 for Tank's Ram).
var window_s: float = 0.0


static func create(p_ftp_w: float, p_window_s: float = 0.0) -> SprintRule:
	var r := SprintRule.new()
	r.ftp_w = p_ftp_w
	r.window_s = p_window_s
	return r


func threshold_w() -> float:
	return FTP_FACTOR * ftp_w


## Feed power at time t (seconds, any monotonic clock the caller uses consistently).
func update(_t: float, _power_w: float) -> void:
	pass


## True while the rule holds (over window_s if set).
func holds() -> bool:
	return false


## Seconds the current streak has held (0 when not holding).
func held_s() -> float:
	return 0.0


## Longest streak so far, seconds.
func best_s() -> float:
	return 0.0


func reset() -> void:
	pass
