class_name HudRiderNumbers
extends RefCounted
## The rules every game's own rider numbers want (GAME_SDK 10.4), in one small class with no
## drawing: feed it the local rider's Telemetry every tick and read back what to show.
##  - Power: the displayed watts are a 3 s mean over Telemetry.t, not the latest 1 Hz sample.
##  - Stale power: a dropped stream shows `--`, not 0. LocalRider reads 0 W once a sample is older
##    than 3 s, so 0 W with a cadence just as old (or a dropped or silent peer) is "no data", while
##    0 W with a fresh cadence is a rider who stopped. The mean restarts when data comes back.
##  - In-band state with hysteresis: entering takes the mean inside the band; leaving takes it past
##    the band by a margin, so a 5% band does not flicker on 1 Hz data.
##  - Heart rate as three states: live, a dropout (a sensor was seen this session or is known, so
##    0 bpm must not claim "no sensor"), and none.
##  - Low cadence: true while rescue is armed (BRIEF 4.6.3: ERG, target >= 60% FTP) and the cadence
##    has stayed under the recover cadence (70) for LOW_CADENCE_DWELL_S, half of the 3 s rescue
##    needs under 45 rpm, so the warning comes first and one low 1 Hz sample raises nothing.
##  - W/kg opt-in and W' come from the rider's profile, the same way HudLayer reads them.
## Pure of the scene tree except for the two profile and sensor lookups, which fall back when no
## autoload is there. Kit widgets keep their own rules; nothing here changes a default.

const POWER_WINDOW_S := 3.0
const STALE_S := 3.0
const UNDER := -1
const IN_BAND := 0
const OVER := 1
## How far past the band the mean must go to leave it: this share of the band's width, at least
## BAND_MARGIN_MIN_W.
const BAND_MARGIN_FRAC := 0.25
const BAND_MARGIN_MIN_W := 3.0
const HR_NONE := 0
const HR_LIVE := 1
const HR_DROPOUT := 2
const LOW_CADENCE_RPM := SafetyGovernor.RESCUE_RECOVER_RPM
## The low-cadence warning clears at this cadence (a little above where it starts).
const LOW_CADENCE_CLEAR_RPM := LOW_CADENCE_RPM + 2.0
const LOW_CADENCE_DWELL_S := 1.5
const DEFAULT_WPRIME_J := 20000.0

## The rider's FTP in watts (for rescue's arming).
var ftp_w: float = 200.0
## Stands in for the TrainerService's hr_status() when set (tests; a game with its own sensor).
var sensor_status_override: String = ""

var _times := PackedFloat64Array()
var _watts := PackedFloat64Array()
var _mean: float = 0.0
var _stale: bool = false
var _band := Vector2.ZERO
var _state: int = IN_BAND
var _bpm: int = 0
var _hr_seen: bool = false
var _tm: Telemetry = null
var _low_since: float = -1.0
var _low: bool = false


## Reads one tick's telemetry (null is ignored).
func feed(t: Telemetry) -> void:
	if t == null:
		return
	_tm = t
	_bpm = t.heart_rate_bpm
	_hr_seen = _hr_seen or _bpm > 0
	_stale = telemetry_stale(t)
	if _stale:
		_clear()
	else:
		push_power(t.t, t.power_w)
	_track_cadence(t)


## One power sample at `time_s` (monotonic seconds; a clock that goes back restarts the mean).
func push_power(time_s: float, power_w: float) -> void:
	var n := _times.size()
	if n > 0 and time_s < _times[n - 1]:
		_clear()
		n = 0
	if n > 0 and is_equal_approx(time_s, _times[n - 1]):
		_watts[n - 1] = power_w
	else:
		_times.append(time_s)
		_watts.append(power_w)
	var start := time_s - POWER_WINDOW_S
	while _times.size() > 2 and _times[1] <= start:
		_times.remove_at(0)
		_watts.remove_at(0)
	_mean = _window_mean(start)
	_update_state()


## The band the mean is judged against (0, 0 clears it).
func set_band(lo_w: float, hi_w: float) -> void:
	var b := Vector2(lo_w, hi_w) if hi_w > 0.0 and hi_w >= lo_w else Vector2.ZERO
	if b == _band:
		return
	if _band == Vector2.ZERO or _times.is_empty():
		_state = IN_BAND
	_band = b
	_update_state()


func band() -> Vector2:
	return _band


## The 3 s mean in watts (0 while stale or before any sample).
func mean_power_w() -> float:
	return _mean


## True while the rider's power is not known: show `--`, not 0.
func is_stale() -> bool:
	return _stale


## UNDER, IN_BAND or OVER with hysteresis (IN_BAND without a band or while stale).
func band_state() -> int:
	return IN_BAND if _stale or _band == Vector2.ZERO else _state


func in_band() -> bool:
	return not _stale and _band != Vector2.ZERO and _state == IN_BAND


func heart_bpm() -> int:
	return _bpm


## HR_LIVE, HR_DROPOUT (show `--`) or HR_NONE (no sensor: no cell).
func heart_state() -> int:
	if _bpm > 0:
		return HR_LIVE
	if _hr_seen or sensor_known():
		return HR_DROPOUT
	return HR_NONE


## A heart rate sensor is at work or remembered, whatever it reads right now.
func sensor_known() -> bool:
	if sensor_status_override != "":
		return sensor_status_override != TrainerDevice.STATUS_DISCONNECTED
	var ts := AutoloadLookup.trainer_service()
	if ts == null:
		return false
	if ts.hr_status() != TrainerDevice.STATUS_DISCONNECTED:
		return true
	var hr := ts.hr_manager()
	return hr != null and not hr.last_sensor().is_empty()


## The cadence is older than STALE_S (dim it or dash it).
func cadence_stale() -> bool:
	return _tm != null and _tm.cadence_age_s > STALE_S


## BRIEF 4.6.3's arming as telemetry shows it: ERG at >= 60% FTP in whole watts, not paused.
func rescue_armed() -> bool:
	if _tm == null or _tm.mode != Wl.ERG or _tm.paused:
		return false
	return _tm.applied_target_w >= floori(ftp_w * SafetyGovernor.RESCUE_ARM_PCT / 100.0 + 1e-9)


## True while the low-cadence warning should show (see the class doc).
func low_cadence() -> bool:
	return _low


## True when `t` says this rider's numbers are not live (see the class doc).
static func telemetry_stale(t: Telemetry) -> bool:
	if not t.connected or t.age_s > STALE_S:
		return true
	return t.power_w <= 0.0 and t.cadence_age_s > STALE_S


## The weight for W/kg: above 0 only if the rider opted in (`override_kg` >= 0 wins, as
## HudLayer.wkg_weight_kg does).
static func opted_in_weight_kg(override_kg: float = -1.0) -> float:
	if override_kg >= 0.0:
		return override_kg
	var settings := AutoloadLookup.settings()
	if settings == null or settings.profile == null or not settings.profile.show_wkg:
		return 0.0
	return settings.profile.weight_kg


## The rider's W' in joules from the profile (20 kJ without one).
static func wprime_j() -> float:
	var settings := AutoloadLookup.settings()
	if settings == null or settings.profile == null or settings.profile.wprime_j <= 0.0:
		return DEFAULT_WPRIME_J
	return settings.profile.wprime_j


func _clear() -> void:
	_times.clear()
	_watts.clear()
	_mean = 0.0


func _window_mean(start: float) -> float:
	var n := _times.size()
	var total := 0.0
	var weight := 0.0
	for i in n - 1:
		var from := maxf(_times[i], start)
		var dt := _times[i + 1] - from
		if dt > 0.0:
			total += (_watts[i] + _watts[i + 1]) * 0.5 * dt
			weight += dt
	return total / weight if weight > 0.0 else _watts[n - 1]


func _update_state() -> void:
	if _band == Vector2.ZERO or _times.is_empty():
		return
	var margin := maxf((_band.y - _band.x) * BAND_MARGIN_FRAC, BAND_MARGIN_MIN_W)
	if _state == IN_BAND:
		if _mean < _band.x - margin:
			_state = UNDER
		elif _mean > _band.y + margin:
			_state = OVER
	elif _mean >= _band.x and _mean <= _band.y:
		_state = IN_BAND
	else:
		_state = UNDER if _mean < _band.x else OVER


func _track_cadence(t: Telemetry) -> void:
	var usable := rescue_armed() and not t.rescue and not t.coasting and not cadence_stale()
	if not usable or t.cadence_rpm >= LOW_CADENCE_CLEAR_RPM:
		_low_since = -1.0
		_low = false
		return
	if t.cadence_rpm >= LOW_CADENCE_RPM:
		return
	if _low_since < 0.0 or t.t < _low_since:
		_low_since = t.t
	_low = _low or t.t - _low_since >= LOW_CADENCE_DWELL_S - 1e-6
