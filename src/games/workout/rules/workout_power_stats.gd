class_name WorkoutPowerStats
extends RefCounted
## One rider's ride statistics from telemetry (BRIEF 3.7 results): kJ, average and
## normalized power and best 1-, 5- and 20-minute power. Fed every sim step; power is
## averaged into 1 Hz samples for the windowed numbers. Pure and deterministic.
##
## Workout uses these when the platform's ctx.stats has no value (and in tests).

const SAMPLE_S := 1.0
const NP_WINDOW := 30

var kj: float = 0.0
var ride_s: float = 0.0
## 1 Hz average power samples.
var samples: PackedFloat64Array = PackedFloat64Array()
var _acc_j: float = 0.0
var _acc_t: float = 0.0


func add(power_w: float, dt: float) -> void:
	var p := maxf(power_w, 0.0)
	kj += p * dt / 1000.0
	ride_s += dt
	_acc_j += p * dt
	_acc_t += dt
	if _acc_t >= SAMPLE_S - 1e-6:
		samples.append(_acc_j / _acc_t)
		_acc_j = 0.0
		_acc_t = 0.0


func avg_power_w() -> float:
	return kj * 1000.0 / ride_s if ride_s > 0.0 else 0.0


## Best average power over `window_s` whole seconds; 0 when the ride is shorter.
func best_w(window_s: int) -> float:
	var n := samples.size()
	if window_s <= 0 or n < window_s:
		return 0.0
	var sum := 0.0
	for i in window_s:
		sum += samples[i]
	var best := sum
	for i in range(window_s, n):
		sum += samples[i] - samples[i - window_s]
		best = maxf(best, sum)
	return best / float(window_s)


## Normalized power: the 4th-power mean of the 30 s rolling average, 4th root. Rides
## shorter than 30 s report their average power.
func np_w() -> float:
	var n := samples.size()
	if n < NP_WINDOW:
		return avg_power_w()
	var sum := 0.0
	for i in NP_WINDOW:
		sum += samples[i]
	var acc := pow(sum / NP_WINDOW, 4.0)
	var count := 1
	for i in range(NP_WINDOW, n):
		sum += samples[i] - samples[i - NP_WINDOW]
		acc += pow(sum / NP_WINDOW, 4.0)
		count += 1
	return pow(acc / count, 0.25)


## The GameResults row keys this class can fill.
func row_values(ftp_w: float) -> Dictionary:
	var avg := avg_power_w()
	return {
		"kj": kj,
		"avg_power_w": avg,
		"avg_ftp_pct": avg / ftp_w * 100.0 if ftp_w > 0.0 else 0.0,
		"np_w": np_w(),
		"best_1m_w": best_w(60),
		"best_5m_w": best_w(300),
		"best_20m_w": best_w(1200),
		"ride_s": ride_s,
	}
