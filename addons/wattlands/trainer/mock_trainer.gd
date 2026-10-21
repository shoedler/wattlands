class_name MockTrainer
extends TrainerDevice
## A simulated trainer plus rider (BRIEF 4.2). Owned by trainer-core; public API frozen
## after W0 (additive changes only). Used by tests, headless simulations, demos, bots
## (profile "erg:compliance=1.0") and `--mock-trainer=<profile>`.
##
## Profiles are parsed as "name:key=value,...", combined with "+" (BRIEF 4.2):
##   erg (ERG follower; compliance 0..1, default 1.0; in SIM rides compliance x the centre
##     of the power band published with ctx.hud.power_band, else 90% FTP),
##   zero (0 W, 0 rpm), const (w, rpm), ramp (from_w, to_w, over_s, rpm),
##   intervals, noise, band (cadence follows the published cadence band's centre plus
##     offset_rpm, default 0, with 2 s lag and noise; no band: preferred cadence),
##   cadence_drop (rpm, at_s | at_phase [+ after_s] | at_target_pct [+ at_phase, after_s],
##     for_s default rest of run), surge (every_s 60, for_s 2, lift 0.2, sim_pct).
## Rider model: first-order ERG settling (tau ~ 2 s, slight overshoot), fatigue from W'
## that eventually fails high targets, ~1 Hz notifications with seeded jitter, cadence that
## lags after sprints, optional dropouts. Keyboard control when enabled: W/S +-10 W,
## A/D cadence.
## Everything time-based advances only in tick(dt) (platform time); randomness comes from
## the seed, so a run is reproducible.
##
## W0 implements erg, zero, const and ramp, the grammar, the jittered ~1 Hz samples and the
## recorded commands; trainer-core adds the rest in W1 (a PROFILE_KEYS row per profile, hooks
## at the "W1:" comments in _step()). W0 rules: the erg follower is a second-order response
## (63% of a step after ERG_TAU_S, ~2.5% overshoot, within 2% after ~6 s); outside ERG it
## rides compliance x the power band's centre, or FREE_RIDE_PCT of FTP without a band;
## scripted power (zero, const, ramp) wins over erg; the rider pedals (the profile's rpm, else
## the preferred cadence) while its goal power is above 0 and stops at once (0 W, 0 rpm) at 0;
## speed_kmh = cadence x KMH_PER_RPM (a fixed virtual gear); samples are rounded like FTMS
## data; control responses (success) arrive on the next tick.

## The profile string this mock was built from ("erg" after an invalid spec fell back).
var spec: String = ""
## Last commanded state from the controller (read-only for tests and reports).
var commanded_mode: String = Wl.OFF
var commanded_target_w: int = 0
var commanded_grade_pct: float = 0.0
var commanded_wind_mps: float = 0.0
var commanded_crr: float = 0.004
var commanded_cw: float = 0.51
## Last level sent with set_resistance (RESISTANCE mode, P1 fallback).
var commanded_resistance: float = 0.0
## Count of setter calls (tests assert coalescing and the hardware lock path).
var command_count: int = 0

## Profile used when a spec is invalid.
const DEFAULT_SPEC := "erg"
## Allowed keys per profile name. W1 adds band, cadence_drop, surge, intervals and noise.
const PROFILE_KEYS: Dictionary = {
	"erg": ["compliance"],
	"zero": [],
	"const": ["w", "rpm"],
	"ramp": ["from_w", "to_w", "over_s", "rpm"],
}
const REQUIRED_KEYS: Dictionary = {"const": ["w"], "ramp": ["from_w", "to_w", "over_s"]}
## Profiles that script power directly; the first one in the spec wins over `erg`.
const SCRIPTED_POWER: Array[String] = ["zero", "const", "ramp"]
## Outside ERG and without a published power band, `erg` rides this % of FTP.
const FREE_RIDE_PCT := 90.0
## ERG follower: 63% of a step after ERG_TAU_S seconds, with a slight overshoot.
const ERG_TAU_S := 2.0
const ERG_DAMPING := 0.75
## Natural frequency (rad/s): with ERG_DAMPING the step response crosses 63% at 1.8 / omega.
const ERG_OMEGA := 1.8 / ERG_TAU_S
## Notification interval bounds (seeded jitter).
const SAMPLE_MIN_S := 0.9
const SAMPLE_MAX_S := 1.1
## Fixed virtual gear: reported flywheel speed per rpm.
const KMH_PER_RPM := 0.4
const DEFAULT_CADENCE_RPM := 90.0
const DEFAULT_MAX_POWER_W := 1800
## FTMS feature bits (BRIEF 4.3): cadence, resistance level, power measurement; and
## resistance, power (ERG) and indoor bike simulation targets.
const FEATURES_MACHINE := (1 << 1) | (1 << 7) | (1 << 14)
const FEATURES_TARGET := (1 << 2) | (1 << 3) | (1 << 13)
## FTMS control point op codes and the success result code (BRIEF 4.3).
const OP_SET_RESISTANCE := 0x04
const OP_SET_TARGET_POWER := 0x05
const OP_STOP_PAUSE := 0x08
const OP_SET_SIMULATION := 0x11
const RESULT_SUCCESS := 0x01

var _components: Array = []
## The scripted power component (zero, const, ramp) or {} for the erg follower.
var _scripted_power: Dictionary = {}
var _erg_compliance: float = 1.0
var _ftp_w: float = 200.0
## from_spec's options as given (W1 reads cp_w, wprime_j, weight_kg and dropouts here).
var _options: Dictionary = {}
var _preferred_cadence_rpm: float = DEFAULT_CADENCE_RPM
var _max_power_w: int = DEFAULT_MAX_POWER_W
var _seed: int = 0
var _keyboard: bool = false
var _power_band_lo: float = 0.0
var _power_band_hi: float = 0.0
var _cadence_band_lo: float = 0.0
var _cadence_band_hi: float = 0.0
var _phase_index: int = -1
## Rider model: platform seconds since creation, power, its rate (follower), cadence, speed.
var _t: float = 0.0
var _power_w: float = 0.0
var _power_rate: float = 0.0
var _cadence_rpm: float = 0.0
var _speed_kmh: float = 0.0
var _sample_rng: RandomNumberGenerator = null
var _next_sample_t: float = 0.0
var _last_sample: TrainerSample = null
## [opcode, result] responses queued by the setters, emitted on the next tick.
var _pending_responses: Array[Vector2i] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure(DEFAULT_SPEC, parse_spec(DEFAULT_SPEC), 200.0, {})


## Build a mock from a profile spec for a rider with `ftp_w` (and CP = FTP unless given).
## options: {cp_w, wprime_j, preferred_cadence_rpm, weight_kg, max_power_w, seed,
## dropouts (bool), keyboard (bool)}. An invalid spec push_errors and falls back to "erg".
static func from_spec(p_spec: String, p_ftp_w: float = 200.0, p_options: Dictionary = {}) -> MockTrainer:
	var m := MockTrainer.new()
	var used := p_spec
	var comps := parse_spec(p_spec)
	if comps.is_empty():
		used = DEFAULT_SPEC
		comps = parse_spec(DEFAULT_SPEC)
	m._configure(used, comps, p_ftp_w, p_options)
	return m


## Parse a spec into [{"name": String, "params": Dictionary}] (empty + push_error if bad).
## Names and keys are case-insensitive; every value is a number (stored as float); a
## profile may appear more than once.
static func parse_spec(p_spec: String) -> Array:
	var out: Array = []
	if p_spec.strip_edges() == "":
		return _spec_error(p_spec, "empty spec")
	for part: String in p_spec.split("+"):
		var comp := part.strip_edges()
		var pname := comp
		var params: Dictionary = {}
		var colon := comp.find(":")
		if colon >= 0:
			pname = comp.substr(0, colon).strip_edges()
			for pair: String in comp.substr(colon + 1).split(","):
				var eq := pair.find("=")
				if eq < 0:
					return _spec_error(p_spec, "\"%s\" is not key=value" % pair.strip_edges())
				var key := pair.substr(0, eq).strip_edges().to_lower()
				var raw := pair.substr(eq + 1).strip_edges()
				if key == "" or not raw.is_valid_float():
					return _spec_error(p_spec, "bad value in \"%s\"" % pair.strip_edges())
				if params.has(key):
					return _spec_error(p_spec, "key \"%s\" given twice" % key)
				params[key] = float(raw)
		pname = pname.to_lower()
		if pname == "":
			return _spec_error(p_spec, "empty profile name")
		if not PROFILE_KEYS.has(pname):
			return _spec_error(p_spec, "unknown profile \"%s\"" % pname)
		var allowed: Array = PROFILE_KEYS[pname]
		for key: String in params.keys():
			if not allowed.has(key):
				return _spec_error(p_spec, "unknown key \"%s\" for %s" % [key, pname])
			var why := _check_param(key, float(params[key]))
			if why != "":
				return _spec_error(p_spec, why)
		for key: String in REQUIRED_KEYS.get(pname, []):
			if not params.has(key):
				return _spec_error(p_spec, "%s needs %s" % [pname, key])
		out.append({"name": pname, "params": params})
	return out


## The cadence band the game published for this rider (0, 0 clears): `band` follows it.
func set_cadence_band(lo_rpm: float, hi_rpm: float) -> void:
	_cadence_band_lo = lo_rpm
	_cadence_band_hi = hi_rpm


## The power band the game published (ctx.hud.power_band): `erg` rides its centre in SIM.
func set_power_band(lo_w: float, hi_w: float) -> void:
	_power_band_lo = lo_w
	_power_band_hi = hi_w


## The rider's current plan phase (for cadence_drop at_phase/after_s).
func set_phase(index: int) -> void:
	_phase_index = index


func set_keyboard_enabled(on: bool) -> void:
	_keyboard = on


## The latest sample emitted (null before the first).
func last_sample() -> TrainerSample:
	return _last_sample


## The rider's true instantaneous power right now (between notifications).
func instantaneous_power_w() -> float:
	return _power_w


## The parsed profile components in use ([{"name", "params"}], a copy).
func components() -> Array:
	return _components.duplicate(true)


## Platform seconds this mock has been ticked.
func platform_time_s() -> float:
	return _t


func device_name() -> String:
	return "Mock trainer (%s)" % spec


func is_ready() -> bool:
	return true


func status() -> String:
	return STATUS_READY


func power_range() -> Dictionary:
	return {"min_w": 0, "max_w": _max_power_w, "step_w": 1}


func features() -> Dictionary:
	return {"machine": FEATURES_MACHINE, "target": FEATURES_TARGET}


func set_target_power(watts: int) -> void:
	commanded_mode = Wl.ERG
	commanded_target_w = watts
	_record(OP_SET_TARGET_POWER)


func set_simulation(wind_mps: float, grade_pct: float, crr: float, cw: float) -> void:
	commanded_mode = Wl.SIM
	commanded_wind_mps = wind_mps
	commanded_grade_pct = grade_pct
	commanded_crr = crr
	commanded_cw = cw
	_record(OP_SET_SIMULATION)


func set_resistance(level: float) -> void:
	commanded_mode = Wl.RESISTANCE
	commanded_resistance = level
	_record(OP_SET_RESISTANCE)


func request_stop() -> void:
	commanded_mode = Wl.OFF
	_record(OP_STOP_PAUSE)


## Advances the rider model in steps of at most Wl.SIM_DT and emits due samples.
func tick(dt: float) -> void:
	_flush_responses()
	var remaining := maxf(dt, 0.0)
	while remaining > 1e-9:
		var h := minf(remaining, Wl.SIM_DT)
		_step(h)
		remaining -= h


func _configure(p_spec: String, comps: Array, p_ftp_w: float, options: Dictionary) -> void:
	spec = p_spec
	_components = comps
	_ftp_w = maxf(p_ftp_w, 1.0)
	_options = options.duplicate(true)
	_preferred_cadence_rpm = float(options.get("preferred_cadence_rpm", DEFAULT_CADENCE_RPM))
	_max_power_w = int(options.get("max_power_w", DEFAULT_MAX_POWER_W))
	_seed = int(options.get("seed", 0))
	_keyboard = bool(options.get("keyboard", false))
	_scripted_power = {}
	_erg_compliance = 1.0
	var found_erg := false
	for c: Dictionary in _components:
		if _scripted_power.is_empty() and SCRIPTED_POWER.has(str(c["name"])):
			_scripted_power = c
		if not found_erg and c["name"] == "erg":
			found_erg = true
			_erg_compliance = float((c["params"] as Dictionary).get("compliance", 1.0))
	# Each randomness source gets its own stream, so W1's noise and dropouts never shift
	# the notification times.
	_sample_rng = SeededRng.make(SeededRng.derive(_seed, "mock_trainer:samples"))
	_t = 0.0
	_next_sample_t = _sample_interval()


## One fixed step of the rider model (h <= Wl.SIM_DT platform seconds).
func _step(h: float) -> void:
	_t += h
	var goal := 0.0
	if _scripted_power.is_empty():
		goal = _erg_goal_w()
		if goal <= 0.0:
			_power_w = 0.0
			_power_rate = 0.0
		else:
			var accel := ERG_OMEGA * ERG_OMEGA * (goal - _power_w) - 2.0 * ERG_DAMPING * ERG_OMEGA * _power_rate
			_power_rate += h * accel
			_power_w = maxf(_power_w + h * _power_rate, 0.0)
	else:
		goal = _scripted_power_w(_scripted_power, _t)
		_power_w = maxf(goal, 0.0)
		_power_rate = 0.0
	# W1: fatigue from W', keyboard offsets, intervals, noise and surge sim_pct adjust power here.
	_cadence_rpm = _base_cadence_rpm() if goal > 0.0 else 0.0
	# W1: band, cadence_drop and surge adjust cadence here (precedence: docs/OWNERSHIP.md MR1).
	_speed_kmh = _cadence_rpm * KMH_PER_RPM
	if _t + 1e-9 >= _next_sample_t:
		# W1: dropouts skip the emission here (keep consuming the schedule).
		_emit_sample()
		_next_sample_t += _sample_interval()


## The `erg` follower's goal: compliance x the commanded target in ERG; otherwise
## compliance x the power band's centre, or FREE_RIDE_PCT of FTP without a band.
func _erg_goal_w() -> float:
	if commanded_mode == Wl.ERG:
		return _erg_compliance * clampf(float(commanded_target_w), 0.0, float(_max_power_w))
	if _power_band_lo > 0.0 or _power_band_hi > 0.0:
		return _erg_compliance * 0.5 * (_power_band_lo + _power_band_hi)
	return FREE_RIDE_PCT * _ftp_w / 100.0


func _scripted_power_w(c: Dictionary, t: float) -> float:
	var p: Dictionary = c["params"]
	match str(c["name"]):
		"const":
			return float(p["w"])
		"ramp":
			var over := float(p["over_s"])
			var f := 1.0 if over <= 0.0 else clampf(t / over, 0.0, 1.0)
			return lerpf(float(p["from_w"]), float(p["to_w"]), f)
	return 0.0


## The profile's own rpm (const, ramp) or the preferred cadence.
func _base_cadence_rpm() -> float:
	if not _scripted_power.is_empty():
		return float((_scripted_power["params"] as Dictionary).get("rpm", _preferred_cadence_rpm))
	return _preferred_cadence_rpm


func _emit_sample() -> void:
	var s := TrainerSample.make(_t, roundf(_power_w), roundf(_cadence_rpm * 2.0) / 2.0,
		roundf(_speed_kmh * 100.0) / 100.0)
	_last_sample = s
	sample_received.emit(s)


func _sample_interval() -> float:
	return SeededRng.range_f(_sample_rng, SAMPLE_MIN_S, SAMPLE_MAX_S)


func _record(opcode: int) -> void:
	command_count += 1
	_pending_responses.append(Vector2i(opcode, RESULT_SUCCESS))


func _flush_responses() -> void:
	if _pending_responses.is_empty():
		return
	var pending := _pending_responses
	_pending_responses = []
	for r in pending:
		control_response.emit(r.x, r.y)


## "" if `value` is allowed for `key`, else why not. W1 adds rules for its keys (for
## example a signed band offset_rpm).
static func _check_param(key: String, value: float) -> String:
	if key == "compliance" and (value < 0.0 or value > 1.0):
		return "compliance must be within 0..1"
	if value < 0.0:
		return "%s must not be negative" % key
	return ""


static func _spec_error(p_spec: String, why: String) -> Array:
	push_error("MockTrainer: invalid profile spec \"%s\": %s" % [p_spec, why])
	return []
