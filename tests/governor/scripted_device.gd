extends TrainerDevice
## Test trainer for the governor and controller suites: scripted rider values, a sample
## every `sample_period_s` (the first at `first_sample_s`), and a log of every setter call.
## Deterministic: no randomness, time only from tick(dt).

var t: float = 0.0
## Rider values reported in samples. cadence_rpm or speed_kmh < 0 means "absent".
var power_w: float = 200.0
var cadence_rpm: float = 90.0
var speed_kmh: float = 30.0
## In ERG, power = commanded target x erg_follow (instantly). < 0: always power_w.
var erg_follow: float = -1.0
var sample_period_s: float = 1.0
var first_sample_s: float = 1.0
var max_power_w: int = 1800
## Every setter call: {t, op ("erg", "sim", "resistance", "stop"), ...values}.
var writes: Array[Dictionary] = []
var mode: String = Wl.OFF
var target_w: int = 0
var grade_pct: float = 0.0
var wind_mps: float = 0.0
var crr: float = 0.004
var cw: float = 0.51
var level: float = 0.0
var stops: int = 0
var samples_sent: int = 0
var sample_times: Array[float] = []
var last_sample: TrainerSample = null
var _next_sample_t: float = -1.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func device_name() -> String:
	return "Scripted test trainer"


func is_ready() -> bool:
	return true


func status() -> String:
	return STATUS_READY


func power_range() -> Dictionary:
	return {"min_w": 0, "max_w": max_power_w, "step_w": 1}


func set_target_power(watts: int) -> void:
	mode = Wl.ERG
	target_w = watts
	writes.append({"t": t, "op": "erg", "w": watts})


func set_simulation(p_wind_mps: float, p_grade_pct: float, p_crr: float, p_cw: float) -> void:
	mode = Wl.SIM
	wind_mps = p_wind_mps
	grade_pct = p_grade_pct
	crr = p_crr
	cw = p_cw
	writes.append(
		{
			"t": t,
			"op": "sim",
			"wind_mps": p_wind_mps,
			"grade_pct": p_grade_pct,
			"crr": p_crr,
			"cw": p_cw
		}
	)


func set_resistance(p_level: float) -> void:
	mode = Wl.RESISTANCE
	level = p_level
	writes.append({"t": t, "op": "resistance", "level": p_level})


func request_stop() -> void:
	mode = Wl.OFF
	stops += 1
	writes.append({"t": t, "op": "stop"})


## The power the rider produces right now.
func current_power_w() -> float:
	if erg_follow >= 0.0 and mode == Wl.ERG:
		return float(target_w) * erg_follow
	return power_w


func tick(dt: float) -> void:
	if _next_sample_t < 0.0:
		_next_sample_t = first_sample_s
	t += dt
	if t >= _next_sample_t - 1e-6:
		_emit()
		_next_sample_t += sample_period_s


## Writes of one op ("erg", "sim", ...), optionally since time `since`.
func writes_of(op: String, since: float = -1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in writes:
		if w["op"] == op and float(w["t"]) >= since - 1e-9:
			out.append(w)
	return out


## The most writes inside any half-open window [t, t + window_s).
func max_writes_in_window(window_s: float = 1.0) -> int:
	var best := 0
	for i in writes.size():
		var start := float(writes[i]["t"])
		var n := 0
		for j in range(i, writes.size()):
			if float(writes[j]["t"]) < start + window_s - 1e-9:
				n += 1
		best = maxi(best, n)
	return best


func _emit() -> void:
	var s := TrainerSample.make(t, roundf(current_power_w()), cadence_rpm, speed_kmh)
	last_sample = s
	samples_sent += 1
	sample_times.append(t)
	sample_received.emit(s)
