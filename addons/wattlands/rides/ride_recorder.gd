class_name RideRecorder
extends RideRecorderApi
## Records the local rider's ride (BRIEF 3.8, RideRecorderApi). Pure: time is the caller's
## platform time, never the wall clock; only the UTC start stamp passed to start() is wall
## time.
##
## Records: one per second of platform time since start(), stamped at whole seconds
## (utc_start + k). Each record holds the latest values fed at or before its second
## (sample and hold), so a 1 Hz trainer feed and a 20 Hz tick feed both give one record per
## second. A value is held for at most hold_limit_s without a fresh record() call (a trainer
## dropout): after that power counts as 0 W and cadence and speed as absent (no distance)
## until the next record(), so a dropout never credits work the rider may not have done.
## Non-finite inputs count as 0 W (power) or absent (cadence, speed).
## Heart rate (additive): set_heart_rate(bpm) before record() hands in the rider's heart rate
## (0 = none); it is held and expires like the other values, recorded per second, and averaged
## (time-weighted over the time it was known) and maxed per lap and ride. The FIT gets the
## record, lap and session heart rate fields only when the ride has a heart rate.
## Totals: work, distance (from the reported speed), time-weighted cadence and speed are
## integrated over platform time between record() calls with the held values, so they don't
## depend on the feed rate. Averages are time-weighted over the elapsed time; maxima are the
## largest values fed. Paused time (set_timer_running(false)) counts in elapsed time and
## not in timer time, and records continue while paused (the trainer still runs).
## Laps: start() opens the first lap; every lap(label, t) closes the current lap at t and
## opens a new one named `label`, except that a lap() at the instant the current lap
## started (no time in it yet) only renames it, so a lap-true first phase doesn't leave a
## zero-length lap. stop() closes the last lap. Expected laps = lap() calls after the start
## instant + 1.
## save() writes <UTC start yyyymmddThhmmssZ>_<game>.fit and a .json summary with the same
## stem; the FIT's laps and session totals are the summary's.

## Seconds of tolerance for "the same instant" (platform time accumulates 0.05 s steps).
const EPS := 1e-4
## Summary format version.
const SUMMARY_VERSION := 1
## The normalized-power rolling window in seconds (the platform's SessionStatsTracker uses 30 too).
const NP_WINDOW_S := 30
## Default hold_limit_s.
const DEFAULT_HOLD_LIMIT_S := 3.0

## The ride's UUID (Strava external_id). start() generates one if empty; set it before
## start() to choose it.
var ride_id: String = ""
## The local time zone's offset from UTC in seconds (FIT activity.local_timestamp), or null
## to leave it out. WlRides.new_recorder() sets it from the system time zone.
var utc_offset_s: Variant = null
## Seconds a fed value stays valid without a fresh record() call (default 3 s, the
## platform's telemetry staleness, OWNERSHIP C20); 0 or less holds values forever.
var hold_limit_s: float = DEFAULT_HOLD_LIMIT_S

var _started_id: String = ""
var _game_id: String = ""
var _content_id: String = ""
var _utc_start: int = 0
var _t0: float = 0.0
var _started: bool = false
var _recording: bool = false
var _last_t: float = 0.0
var _end_rel: float = 0.0
var _timer_running: bool = true

# Held (latest) values; cadence and speed are -1 until a valid value arrives.
var _p: float = 0.0
var _c: float = -1.0
var _s: float = -1.0
var _dist: float = 0.0
## Held heart rate (bpm, 0 = none) and the value set_heart_rate() handed in for the next
## record() call.
var _hr: int = 0
var _hr_in: int = 0
var _next_k: int = 0
## Platform time of the last record() call (the held values' age).
var _fresh_t: float = 0.0

# Records (parallel arrays): second index, power W, cadence rpm (-1 absent),
# speed km/h (-1 absent), distance m.
var _rk: PackedInt32Array = PackedInt32Array()
var _rp: PackedFloat32Array = PackedFloat32Array()
var _rc: PackedFloat32Array = PackedFloat32Array()
var _rs: PackedFloat32Array = PackedFloat32Array()
var _rd: PackedFloat64Array = PackedFloat64Array()
var _rh: PackedInt32Array = PackedInt32Array()

## Timer events: [{rel, running}].
var _events: Array[Dictionary] = []
## Laps: accumulators, see _new_lap().
var _laps: Array[Dictionary] = []
## Whole-ride accumulators (same keys as a lap).
var _total: Dictionary = {}
var _saved_fit_path: String = ""


func _init() -> void:
	_laps = [_new_lap("", 0.0)]
	_total = _new_lap("", 0.0)


func start(game_id: String, content_id: String, utc_start_unix: int, t: float) -> void:
	_game_id = game_id
	_content_id = content_id
	_utc_start = utc_start_unix
	_t0 = t
	_last_t = t
	_end_rel = 0.0
	_started = true
	_recording = true
	_timer_running = true
	_p = 0.0
	_c = -1.0
	_s = -1.0
	_dist = 0.0
	_hr = 0
	_hr_in = 0
	_next_k = 0
	_fresh_t = t
	_rk = PackedInt32Array()
	_rp = PackedFloat32Array()
	_rc = PackedFloat32Array()
	_rs = PackedFloat32Array()
	_rd = PackedFloat64Array()
	_rh = PackedInt32Array()
	_events = [{"rel": 0.0, "running": true}]
	_laps = [_new_lap("", 0.0)]
	_total = _new_lap("", 0.0)
	_saved_fit_path = ""
	# A new ride gets a new id unless the caller set one since the last start().
	if ride_id == "" or ride_id == _started_id:
		ride_id = new_uuid()
	_started_id = ride_id


func record(t: float, power_w: float, cadence_rpm: float, speed_kmh: float) -> void:
	if not _recording:
		return
	if t < _last_t - EPS:
		push_warning(
			"RideRecorder: time went backwards (%.3f < %.3f); sample ignored" % [t, _last_t]
		)
		return
	_advance_to(t)
	_p = maxf(power_w, 0.0) if is_finite(power_w) else 0.0
	_c = cadence_rpm if is_finite(cadence_rpm) and cadence_rpm >= 0.0 else -1.0
	_s = speed_kmh if is_finite(speed_kmh) and speed_kmh >= 0.0 else -1.0
	_hr = _hr_in
	_fresh_t = maxf(t, _last_t)
	_note_max(_laps[_laps.size() - 1])
	_note_max(_total)
	_emit_record_at(t)


func lap(label: String, t: float) -> void:
	if not _recording:
		return
	_advance_to(maxf(t, _last_t))
	var rel := _last_t - _t0
	var cur: Dictionary = _laps[_laps.size() - 1]
	if rel - float(cur["start_rel"]) <= EPS:
		cur["label"] = label
		return
	cur["end_rel"] = rel
	cur["trigger"] = FitEncoder.LAP_TRIGGER_MANUAL
	var nxt := _new_lap(label, rel)
	_note_max(nxt)
	_laps.append(nxt)


func set_timer_running(running: bool, t: float) -> void:
	if not _recording or running == _timer_running:
		return
	_advance_to(maxf(t, _last_t))
	_timer_running = running
	_events.append({"rel": _last_t - _t0, "running": running})


func stop(t: float) -> void:
	if not _recording:
		return
	_advance_to(maxf(t, _last_t))
	_emit_record_at(_last_t)
	_end_rel = _last_t - _t0
	if _timer_running:
		_events.append({"rel": _end_rel, "running": false})
	_timer_running = false
	var cur: Dictionary = _laps[_laps.size() - 1]
	cur["end_rel"] = _end_rel
	cur["trigger"] = FitEncoder.LAP_TRIGGER_SESSION_END
	_total["end_rel"] = _end_rel
	_recording = false


func is_recording() -> bool:
	return _recording


## The rider's heart rate (bpm, 0 = none) for the next record() call.
func set_heart_rate(bpm: int) -> void:
	_hr_in = maxi(bpm, 0)


func save(dir: String = "") -> String:
	if not _ready_to_save():
		return ""
	var d := dir if dir != "" else Paths.rides_dir()
	d = d.replace("\\", "/").trim_suffix("/")
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	var stem := file_stem()
	var path := d.path_join(stem + ".fit")
	var n := 2
	while FileAccess.file_exists(path) or FileAccess.file_exists(path.get_basename() + ".json"):
		path = d.path_join("%s_%d.fit" % [stem, n])
		n += 1
	return save_as(path)


## Writes the FIT file at exactly `fit_path` (overwriting) and the JSON summary next to it
## (same stem, .json). Returns the FIT path, or "" on failure. Used by GameSimRunner for
## <report dir>/fit/<report stem>_slot<n>.fit.
func save_as(fit_path: String) -> String:
	if not _ready_to_save():
		return ""
	var path := fit_path.replace("\\", "/")
	var base_dir := path.get_base_dir()
	if base_dir != "" and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning(
			"RideRecorder: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		)
		return ""
	f.store_buffer(fit_bytes())
	f.close()
	_saved_fit_path = path
	var json_path := path.get_basename() + ".json"
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		push_warning("RideRecorder: can't write %s" % json_path)
		return ""
	jf.store_string(JSON.stringify(summary(), "  "))
	jf.close()
	return path


func summary() -> Dictionary:
	var laps: Array = []
	for i in _laps.size():
		laps.append(_lap_summary(_laps[i], i))
	var tot := _lap_summary(_total, -1)
	var out := {
		"version": SUMMARY_VERSION,
		"ride_id": ride_id,
		"game_id": _game_id,
		"content_id": _content_id,
		"utc_start": utc_iso(_utc_start),
		"utc_start_unix": _utc_start,
		"duration_s": tot["duration_s"],
		"timer_s": tot["timer_s"],
		"distance_m": tot["distance_m"],
		"records": _rk.size(),
		"laps": laps,
		"kj": tot["kj"],
		"avg_power_w": tot["avg_power_w"],
		"np_w": _r1(_normalized_power(tot["avg_power_w"])),
		"max_power_w": tot["max_power_w"],
		"avg_cadence_rpm": tot["avg_cadence_rpm"],
		"max_cadence_rpm": tot["max_cadence_rpm"],
		"avg_heart_rate_bpm": tot["avg_heart_rate_bpm"],
		"max_heart_rate_bpm": tot["max_heart_rate_bpm"],
		"avg_speed_kmh": tot["avg_speed_kmh"],
		"max_speed_kmh": tot["max_speed_kmh"],
		"fit_path": _saved_fit_path,
		"sport": "cycling",
		"sub_sport": "virtual_activity",
		"app_build": Wl.BUILD,
	}
	return out


# --- Extra API (additive) ---------------------------------------------------------


## "<UTC start yyyymmddThhmmssZ>_<game>" (the game id reduced to [a-z0-9_-]).
func file_stem() -> String:
	return "%s_%s" % [utc_stamp(_utc_start), _safe_id(_game_id)]


## The encoded FIT file (the ride must have been started).
func fit_bytes() -> PackedByteArray:
	return FitEncoder.encode_ride(fit_data())


## Records so far: [{t_rel (s), power_w, cadence_rpm, speed_kmh, distance_m, heart_rate_bpm}].
func records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _rk.size():
		(
			out
			. append(
				{
					"t_rel": _rk[i],
					"power_w": _rp[i],
					"cadence_rpm": _rc[i],
					"speed_kmh": _rs[i],
					"distance_m": _rd[i],
					"heart_rate_bpm": _rh[i],
				}
			)
		)
	return out


func record_count() -> int:
	return _rk.size()


func lap_count() -> int:
	return _laps.size()


func game_id() -> String:
	return _game_id


func utc_start_unix() -> int:
	return _utc_start


## The data FitEncoder.encode_ride() takes (absolute Unix times).
func fit_data() -> Dictionary:
	var end_rel := _end_rel if not _recording else _last_t - _t0
	var recs: Array = []
	for i in _rk.size():
		(
			recs
			. append(
				{
					"t": _utc_start + _rk[i],
					"power_w": _rp[i],
					"cadence_rpm": _rc[i],
					"speed_mps": _rs[i] / 3.6 if _rs[i] >= 0.0 else -1.0,
					"distance_m": _rd[i],
					"heart_rate_bpm": _rh[i],
				}
			)
		)
	var evs: Array = []
	for e in _events:
		evs.append({"t": _utc_start + roundi(float(e["rel"])), "running": bool(e["running"])})
	var laps: Array = []
	for i in _laps.size():
		laps.append(_lap_fit(_laps[i], i, end_rel))
	var sess := _lap_fit(_total, 0, end_rel)
	sess["first_lap_index"] = 0
	sess["num_laps"] = _laps.size()
	return {
		"utc_start_unix": _utc_start,
		"serial": _serial_from_id(),
		"software_version_x100": _software_version_x100(),
		"local_offset_s": utc_offset_s,
		"records": recs,
		"events": evs,
		"laps": laps,
		"session": sess,
		"end_unix": _utc_start + roundi(end_rel),
		"timer_s": float(sess["timer_s"]),
		"heart_rate": float(_total["max_hr"]) > 0.0,
	}


## A random RFC 4122 version 4 UUID (an identifier, from the OS's secure random source).
static func new_uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var h := b.hex_encode()
	return (
		"%s-%s-%s-%s-%s"
		% [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
	)


## "yyyymmddThhmmssZ" for a Unix time.
static func utc_stamp(unix_s: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_s)
	return (
		"%04d%02d%02dT%02d%02d%02dZ"
		% [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	)


## ISO 8601 UTC ("2026-10-21T13:26:00Z").
static func utc_iso(unix_s: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_s, false) + "Z"


# --- Internals -------------------------------------------------------------------


func _ready_to_save() -> bool:
	if not _started:
		push_warning("RideRecorder: save() before start(); nothing to write")
		return false
	if _recording:
		stop(_last_t)
	return true


func _new_lap(label: String, start_rel: float) -> Dictionary:
	return {
		"label": label,
		"start_rel": start_rel,
		"end_rel": -1.0,
		"elapsed": 0.0,
		"timer": 0.0,
		"work": 0.0,
		"dist": 0.0,
		"cad_sum": 0.0,
		"cad_time": 0.0,
		"spd_sum": 0.0,
		"spd_time": 0.0,
		"max_p": 0.0,
		"max_c": -1.0,
		"max_s": -1.0,
		"hr_sum": 0.0,
		"hr_time": 0.0,
		"max_hr": 0.0,
		"records": 0,
		"trigger": FitEncoder.LAP_TRIGGER_MANUAL,
	}


## Integrates the held values from _last_t to t and emits the records whose second lies
## strictly before t.
func _advance_to(t: float) -> void:
	if t <= _last_t:
		return
	# Records at whole seconds strictly inside (_last_t, t) use the held values; emit each
	# one at its own instant so the integration up to it is exact.
	while _t0 + float(_next_k) < t - EPS:
		var b := _t0 + float(_next_k)
		if b > _last_t:
			_integrate_to(b)
		_emit_record()
	_integrate_to(t)


## Integrates the held values from _last_t to b; values older than hold_limit_s expire on
## the way (power 0, cadence and speed absent).
func _integrate_to(b: float) -> void:
	if hold_limit_s > 0.0 and (_p > 0.0 or _c >= 0.0 or _s >= 0.0 or _hr > 0):
		var stale_at := _fresh_t + hold_limit_s
		if stale_at < b:
			if stale_at > _last_t:
				_integrate(stale_at - _last_t)
				_last_t = stale_at
			_p = 0.0
			_c = -1.0
			_s = -1.0
			_hr = 0
	_integrate(b - _last_t)
	_last_t = maxf(b, _last_t)


func _integrate(dt: float) -> void:
	if dt <= 0.0:
		return
	var speed_mps := maxf(_s, 0.0) / 3.6
	_dist += speed_mps * dt
	for acc: Dictionary in [_laps[_laps.size() - 1], _total]:
		acc["elapsed"] = float(acc["elapsed"]) + dt
		if _timer_running:
			acc["timer"] = float(acc["timer"]) + dt
		acc["work"] = float(acc["work"]) + _p * dt
		acc["dist"] = float(acc["dist"]) + speed_mps * dt
		if _c >= 0.0:
			acc["cad_sum"] = float(acc["cad_sum"]) + _c * dt
			acc["cad_time"] = float(acc["cad_time"]) + dt
		if _s >= 0.0:
			acc["spd_sum"] = float(acc["spd_sum"]) + _s * dt
			acc["spd_time"] = float(acc["spd_time"]) + dt
		if _hr > 0:
			acc["hr_sum"] = float(acc["hr_sum"]) + float(_hr) * dt
			acc["hr_time"] = float(acc["hr_time"]) + dt


func _note_max(acc: Dictionary) -> void:
	acc["max_p"] = maxf(float(acc["max_p"]), _p)
	if _c >= 0.0:
		acc["max_c"] = maxf(float(acc["max_c"]), _c)
	if _s >= 0.0:
		acc["max_s"] = maxf(float(acc["max_s"]), _s)
	acc["max_hr"] = maxf(float(acc["max_hr"]), float(_hr))


## Emits the record due at `t` if t is (within EPS) its whole second.
func _emit_record_at(t: float) -> void:
	if absf(t - (_t0 + float(_next_k))) <= EPS:
		_emit_record()


func _emit_record() -> void:
	_rk.append(_next_k)
	_rp.append(roundf(_p))
	_rc.append(roundf(_c) if _c >= 0.0 else -1.0)
	_rs.append(_s)
	_rd.append(_dist)
	_rh.append(_hr)
	_laps[_laps.size() - 1]["records"] = int(_laps[_laps.size() - 1]["records"]) + 1
	_total["records"] = int(_total["records"]) + 1
	_next_k += 1


## Normalized power of the 1 Hz records: the 30 s rolling mean, to the 4th power, averaged, and
## the 4th root; `fallback_w` (the average) for a ride under 30 s.
func _normalized_power(fallback_w: float) -> float:
	var n := _rp.size()
	if n < NP_WINDOW_S:
		return fallback_w
	var sum := 0.0
	for i in NP_WINDOW_S:
		sum += _rp[i]
	var acc := pow(sum / NP_WINDOW_S, 4.0)
	var count := 1
	for i in range(NP_WINDOW_S, n):
		sum += _rp[i] - _rp[i - NP_WINDOW_S]
		acc += pow(sum / NP_WINDOW_S, 4.0)
		count += 1
	return pow(acc / count, 0.25)


func _lap_summary(acc: Dictionary, index: int) -> Dictionary:
	var elapsed := float(acc["elapsed"])
	var d := {
		"start_s": _r3(float(acc["start_rel"])),
		"duration_s": _r3(elapsed),
		"timer_s": _r3(float(acc["timer"])),
		"distance_m": _r2(float(acc["dist"])),
		"kj": float(roundi(float(acc["work"]))) / 1000.0,
		"avg_power_w": _r1(float(acc["work"]) / elapsed) if elapsed > 0.0 else 0.0,
		"max_power_w": _r1(float(acc["max_p"])),
		"avg_cadence_rpm":
		(
			_r1(float(acc["cad_sum"]) / float(acc["cad_time"]))
			if float(acc["cad_time"]) > 0.0
			else -1.0
		),
		"max_cadence_rpm": _r1(float(acc["max_c"])),
		"avg_speed_kmh":
		(
			_r2(float(acc["spd_sum"]) / float(acc["spd_time"]))
			if float(acc["spd_time"]) > 0.0
			else -1.0
		),
		"max_speed_kmh": _r2(float(acc["max_s"])),
		"avg_heart_rate_bpm":
		_r1(float(acc["hr_sum"]) / float(acc["hr_time"])) if float(acc["hr_time"]) > 0.0 else -1.0,
		"max_heart_rate_bpm": float(acc["max_hr"]) if float(acc["max_hr"]) > 0.0 else -1.0,
		"records": int(acc["records"]),
	}
	if index >= 0:
		d["index"] = index
		d["label"] = str(acc["label"])
	return d


func _lap_fit(acc: Dictionary, index: int, end_rel: float) -> Dictionary:
	var s := _lap_summary(acc, index)
	var start_rel := float(acc["start_rel"])
	var lap_end := float(acc["end_rel"]) if float(acc["end_rel"]) >= 0.0 else end_rel
	return {
		"index": index,
		"name": str(acc["label"]),
		"start_unix": _utc_start + roundi(start_rel),
		"end_unix": _utc_start + roundi(lap_end),
		"elapsed_s": float(s["duration_s"]),
		"timer_s": float(s["timer_s"]),
		"distance_m": float(s["distance_m"]),
		"avg_speed_mps":
		float(s["avg_speed_kmh"]) / 3.6 if float(s["avg_speed_kmh"]) >= 0.0 else -1.0,
		"max_speed_mps":
		float(s["max_speed_kmh"]) / 3.6 if float(s["max_speed_kmh"]) >= 0.0 else -1.0,
		"avg_power_w": float(s["avg_power_w"]),
		"max_power_w": float(s["max_power_w"]),
		"avg_cadence_rpm": float(s["avg_cadence_rpm"]),
		"max_cadence_rpm": float(s["max_cadence_rpm"]),
		"avg_heart_rate_bpm": float(s["avg_heart_rate_bpm"]),
		"max_heart_rate_bpm": float(s["max_heart_rate_bpm"]),
		"work_j": float(roundi(float(acc["work"]))),
		"trigger": int(acc["trigger"]),
	}


func _serial_from_id() -> int:
	var hex := ride_id.replace("-", "").substr(0, 8)
	var v := hex.hex_to_int() if hex.is_valid_hex_number() else 1
	return v if v != 0 else 1


static func _software_version_x100() -> int:
	var parts := Wl.BUILD.split(".")
	var major := int(parts[0]) if parts.size() > 0 else 0
	var minor := int(parts[1]) if parts.size() > 1 else 0
	return major * 100 + minor * 10


static func _safe_id(id: String) -> String:
	var out := ""
	for ch in id.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	return out if out != "" else "ride"


static func _r1(v: float) -> float:
	return roundf(v * 10.0) / 10.0


static func _r2(v: float) -> float:
	return roundf(v * 100.0) / 100.0


static func _r3(v: float) -> float:
	return roundf(v * 1000.0) / 1000.0
