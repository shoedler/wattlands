class_name MockTrainer
extends TrainerDevice
## A simulated trainer plus rider (BRIEF 4.2). Owned by trainer-core; public API frozen
## after W0 (additive changes only). Used by tests, headless simulations, demos, bots
## (Bots.RIDER_SPEC, profile "erg:compliance=1.0+band") and `--mock-trainer=<profile>`.
##
## Profiles are parsed as "name:key=value,...", combined with "+" (BRIEF 4.2); names and keys
## are case-insensitive, values are numbers, and a profile may appear more than once:
##   erg (ERG follower; compliance 0..1, default 1.0; in SIM rides compliance x the centre
##     of the power band published with ctx.hud.power_band, else 90% FTP),
##   zero (0 W, 0 rpm), const (w, rpm), ramp (from_w, to_w, over_s, rpm),
##   intervals (on_w, off_w, on_s default 60, off_s default 60, rpm; starts "on" at t = 0),
##   noise (sd_w default 5, sd_rpm default 2: seeded Gaussian noise on each sample's power
##     and cadence while pedaling),
##   band (cadence follows the published cadence band's centre plus offset_rpm, default 0,
##     with a 2 s first-order lag and seeded noise bounded to +-1.5 rpm; no band: the
##     profile's rpm or the preferred cadence). offset_rpm is measured from the published
##     band's centre, so +-(half the band's width + n) holds the rider n rpm outside it.
##   cadence_drop (rpm; at_s | at_phase [+ after_s] | at_target_pct [+ at_phase, after_s];
##     for_s default rest of run): at_s counts profile seconds (profile_time_s(): platform
##     seconds since the mock was created or restart_profile() was last called);
##     at_phase is the plan phase index from set_phase() and after_s counts from entering it
##     (leaving the phase before the drop starts re-arms it); at_target_pct waits, inside
##     at_phase if given, until the commanded ERG target (the governor's applied target, after
##     the unverified factor) is >= n% of FTP, then counts after_s. While a drop is active the
##     cadence is its rpm (several active drops: the lowest); rpm 0 means the rider stops
##     (0 W). Every instance is independent and fires once.
##   surge (every_s 60, for_s 2, lift 0.2, sim_pct): every every_s (first at profile time
##     every_s) it
##     multiplies cadence and reported speed by 1 + lift for for_s, extended until at least
##     SURGE_MIN_SAMPLES notifications carried it, so the ERG surge gesture (flywheel speed
##     >= 1.12 x its 10 s average for two consecutive ~1 Hz samples) fires on every surge;
##     with sim_pct it rides sim_pct% FTP whenever the trainer is in SIM.
##   hr (rest_bpm 60, max_bpm 185): a mock heart rate sensor; heart_rate_bpm() follows the
##     rider's power (rest_bpm when stopped, 20% of the reserve plus up to 80% more at 120%
##     FTP) with a 20 s first-order lag. Without `hr`, heart_rate_bpm() is 0 (no sensor).
## Precedence (docs/OWNERSHIP.md MR1, C31). Power: the first scripted profile (zero, const,
## ramp, intervals) > surge sim_pct in SIM > the erg follower (ERG: compliance x the commanded
## target, limited to max_power_w; otherwise compliance x the power band's centre, or 90% FTP).
## A spec without erg uses the follower at compliance 1.0. Cadence: an active cadence_drop >
## surge's lift (multiplies) > band > the profile's rpm > the preferred cadence.
##
## Rider model: the follower is a second-order response (63% of a step after ERG_TAU_S,
## ~2.5% overshoot, within 2% after ~6 s). Fatigue: a W' balance (Skiba, CP = cp_w or FTP,
## W' = wprime_j or 20 kJ) on the rider's power; when it is used up the follower can give only
## EXHAUSTED_CP_FRACTION x CP until RECOVERED_WPRIME_FRACTION of W' has come back, so targets
## far above CP eventually fail (150% FTP within about 3 minutes at the defaults) while targets
## below CP hold. Scripted profiles ignore fatigue. The rider pedals while its goal power is
## above 0 and stops at once (0 W, 0 rpm) at 0. Outside ERG at >= 120% FTP the follower
## sprints: its cadence rises 10% (unless `band` steers it) and the reported cadence lags its
## fall for 5 s afterwards (tau 1.5 s), like a trainer's cadence estimate. Speed: in ERG,
## RESISTANCE and OFF the flywheel speed is cadence x KMH_PER_RPM (a fixed virtual gear); in
## SIM a SpeedModel integrates the rider's power at the commanded grade and wind with
## weight_kg + 8 kg, starting from the flywheel speed.
## Notifications every 0.9-1.1 s (seeded jitter), rounded like FTMS data (1 W, 0.5 rpm,
## 0.01 km/h); with options.dropouts some are skipped (seeded gaps of 1.5-4 s that never
## chain and never touch a surge or the 10 s before it). Control responses arrive on the next
## tick with response_result (success by default).
## Keyboard control when enabled (Input is read only then, only while the app window has
## focus; the app enables it with --mock-keyboard or Settings > Trainer, and the keys avoid
## every InputRouter binding): T/G power and Y/H cadence step +-10 W / +-5 rpm on a tap and,
## held past KEY_HOLD_DELAY_S, ramp (20 W/s growing to 200 W/s over KEY_RAMP_UP_S; 5 rpm/s to
## 50 rpm/s). The presets (KEYBOARD_PRESET_KEYS, a numpad block on the right hand, M , . /
## J K L / U I O or the numpad itself) set the power at 50% .. 250% of FTP in steps of 25%
## FTP (50, 75, 100, 125, 150, 175, 200, 225, 250) and the cadence at 85 .. 105 rpm; N (numpad
## 0) stops pedaling (0 W, 0 rpm). Shift held sprints (300% FTP at 110 rpm) and its release
## returns to the setting before. A preset or the sprint puts the power on its value at once
## (no follower lag, no fatigue cap, no sprint cadence lift); T/G and Y/H then move that
## value. Turning the keyboard off clears it all. The mock only produces telemetry: the
## governor still applies its rules to it.
## Everything time-based advances only in tick(dt) (platform time, fixed steps of at most
## Wl.SIM_DT); every random stream derives from options.seed, so a run is reproducible.
## Profile time (at_s, surges, ramp, intervals) starts at creation; restart_profile() restarts
## it, for a mock that rode through menus before its session started.

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
## Result code the control responses carry while the mock holds control (tests set it to
## simulate refusals); after simulate_control_lost() every response is 0x05.
var response_result: int = RESULT_SUCCESS

## Profile used when a spec is invalid.
const DEFAULT_SPEC := "erg"
## Allowed keys per profile name.
const PROFILE_KEYS: Dictionary = {
	"erg": ["compliance"],
	"zero": [],
	"const": ["w", "rpm"],
	"ramp": ["from_w", "to_w", "over_s", "rpm"],
	"intervals": ["on_w", "off_w", "on_s", "off_s", "rpm"],
	"noise": ["sd_w", "sd_rpm"],
	"band": ["offset_rpm"],
	"cadence_drop": ["rpm", "at_s", "at_phase", "after_s", "at_target_pct", "for_s"],
	"surge": ["every_s", "for_s", "lift", "sim_pct"],
	"hr": ["rest_bpm", "max_bpm"],
}
const REQUIRED_KEYS: Dictionary = {
	"const": ["w"],
	"ramp": ["from_w", "to_w", "over_s"],
	"intervals": ["on_w", "off_w"],
	"cadence_drop": ["rpm"],
}
## Profiles that script power directly; the first one in the spec wins over `erg`.
const SCRIPTED_POWER: Array[String] = ["zero", "const", "ramp", "intervals"]
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
## Result code while another app "holds control" (simulate_control_lost).
const RESULT_CONTROL_NOT_PERMITTED := 0x05

## Rider defaults (options cp_w, wprime_j, weight_kg override them).
const DEFAULT_WPRIME_J := 20000.0
const DEFAULT_WEIGHT_KG := 75.0
## Profile parameter defaults.
const INTERVALS_DEFAULT_S := 60.0
const NOISE_SD_W := 5.0
const NOISE_SD_RPM := 2.0
const SURGE_EVERY_S := 60.0
const SURGE_FOR_S := 2.0
const SURGE_LIFT := 0.2
## A surge lasts at least until this many notifications carried it (docs/OWNERSHIP.md C30).
const SURGE_MIN_SAMPLES := 2
## No dropout gap starts this long before a surge (the surge gesture's averaging window).
const SURGE_GUARD_S := 10.0
## Band cadence policy: first-order lag and Ornstein-Uhlenbeck noise, clamped.
const BAND_LAG_S := 2.0
const BAND_NOISE_SD_RPM := 0.6
const BAND_NOISE_TAU_S := 4.0
const BAND_NOISE_MAX_RPM := 1.5
## Fatigue: power available while W' is used up, and the W' fraction that ends exhaustion.
const EXHAUSTED_CP_FRACTION := 0.95
const RECOVERED_WPRIME_FRACTION := 0.1
## Sprints (follower outside ERG at >= 120% FTP): cadence lift and the reported lag after.
const SPRINT_FTP_FRACTION := 1.2
const SPRINT_CADENCE_LIFT := 0.1
const SPRINT_LAG_WINDOW_S := 5.0
const CADENCE_LAG_TAU_S := 1.5
## options.dropouts = true: per-notification chance of a gap, and the gap length.
const DROPOUT_CHANCE := 0.03
const DROPOUT_MIN_S := 1.5
const DROPOUT_MAX_S := 4.0
## `hr` profile defaults and its lag.
const HR_REST_BPM := 60.0
const HR_MAX_BPM := 185.0
const HR_TAU_S := 20.0
## Keyboard steps.
const KEY_POWER_STEP_W := 10.0
const KEY_CADENCE_STEP_RPM := 5.0
## A key held longer than this starts to ramp; a shorter press is a tap (one step).
const KEY_HOLD_DELAY_S := 0.3
## The ramp speed grows exponentially from the first to the second value over KEY_RAMP_UP_S.
const KEY_RAMP_UP_S := 3.0
const KEY_POWER_RAMP_W_PER_S: Vector2 = Vector2(20.0, 200.0)
const KEY_CADENCE_RAMP_RPM_PER_S: Vector2 = Vector2(5.0, 50.0)
## Presets 1..9: % of FTP = 25 x (index + 1), cadence KEY_PRESET_RPM_MIN + step x (index - 1).
const KEY_PRESET_FTP_PCT_MIN := 50.0
const KEY_PRESET_FTP_PCT_STEP := 25.0
const KEY_PRESET_RPM_MIN := 85.0
const KEY_PRESET_RPM_STEP := 2.5
const KEY_SPRINT_FTP_FRACTION := 3.0
const KEY_SPRINT_RPM := 110.0
const KEY_CADENCE_MAX_RPM := 220.0
## The keyboard-control keys (physical): power up/down, cadence up/down, the sprint (Shift),
## stop (N). None is bound in the input map (W/A/S/D, 1 and 2, Space are).
const KEY_POWER_UP := KEY_T
const KEY_POWER_DOWN := KEY_G
const KEY_CADENCE_UP := KEY_Y
const KEY_CADENCE_DOWN := KEY_H
const KEY_SPRINT := KEY_SHIFT
const KEY_STOP := KEY_N
## Key -> preset 1..9 (like a numpad: 1 bottom left, 9 top right); the numpad keys too.
const KEYBOARD_PRESET_KEYS: Dictionary = {
	KEY_M: 1,
	KEY_COMMA: 2,
	KEY_PERIOD: 3,
	KEY_J: 4,
	KEY_K: 5,
	KEY_L: 6,
	KEY_U: 7,
	KEY_I: 8,
	KEY_O: 9,
	KEY_KP_1: 1,
	KEY_KP_2: 2,
	KEY_KP_3: 3,
	KEY_KP_4: 4,
	KEY_KP_5: 5,
	KEY_KP_6: 6,
	KEY_KP_7: 7,
	KEY_KP_8: 8,
	KEY_KP_9: 9,
}

const _DROP_WAITING := 0
const _DROP_COUNTING := 1
const _DROP_ACTIVE := 2
const _DROP_DONE := 3


## One cadence_drop instance.
class DropState:
	extends RefCounted
	var rpm: float = 0.0
	var at_s: float = -1.0
	var at_phase: int = -1
	var after_s: float = 0.0
	var at_target_pct: float = -1.0
	var for_s: float = INF
	var state: int = 0
	var trigger_t: float = 0.0
	var start_t: float = 0.0


## One surge instance.
class SurgeState:
	extends RefCounted
	var every_s: float = 60.0
	var for_s: float = 2.0
	var lift: float = 0.2
	var next_t: float = 60.0
	var active: bool = false
	var start_t: float = 0.0
	var samples: int = 0


## Keyboard control seams (W2r2), for tests: (key: Key) -> bool reads a physical key
## (default Input.is_physical_key_pressed) and () -> bool says whether the app window has
## focus (default: this node's Window.has_focus(); false outside the tree). Read only while
## keyboard control is enabled.
var key_reader: Callable = Callable()
var focus_reader: Callable = Callable()

var _components: Array = []
## The scripted power component (zero, const, ramp, intervals) or {} for the erg follower.
var _scripted_power: Dictionary = {}
var _erg_compliance: float = 1.0
var _ftp_w: float = 200.0
var _preferred_cadence_rpm: float = DEFAULT_CADENCE_RPM
var _max_power_w: int = DEFAULT_MAX_POWER_W
var _seed: int = 0
var _keyboard: bool = false
var _power_band_lo: float = 0.0
var _power_band_hi: float = 0.0
var _cadence_band_lo: float = 0.0
var _cadence_band_hi: float = 0.0
var _phase_index: int = -1
var _phase_start_t: float = 0.0
## Rider model: platform seconds since creation, power, its rate (follower), cadence, speed.
var _t: float = 0.0
## Platform time at which profile time is 0 (creation, or the last restart_profile()).
var _run_start_t: float = 0.0
var _power_w: float = 0.0
var _power_rate: float = 0.0
var _cadence_rpm: float = 0.0
var _speed_kmh: float = 0.0
var _sample_rng: RandomNumberGenerator = null
var _next_sample_t: float = 0.0
var _last_sample: TrainerSample = null
## [opcode, result] responses queued by the setters, emitted on the next tick.
var _pending_responses: Array[Vector2i] = []
var _status: String = STATUS_READY

# Profiles parsed for the rider model.
var _has_band: bool = false
var _band_offset_rpm: float = 0.0
var _band_cadence: float = 0.0
var _band_noise: float = 0.0
var _band_valid: bool = false
var _band_rng: RandomNumberGenerator = null
var _has_noise: bool = false
var _noise_sd_w: float = NOISE_SD_W
var _noise_sd_rpm: float = NOISE_SD_RPM
var _noise_rng: RandomNumberGenerator = null
var _drops: Array[DropState] = []
var _surges: Array[SurgeState] = []
var _sim_pct: float = -1.0
var _has_hr: bool = false
var _hr_rest: float = HR_REST_BPM
var _hr_max: float = HR_MAX_BPM
var _hr: float = HR_REST_BPM
# Fatigue, sprints, speed, dropouts, keyboard.
var _wbal: WBalance = null
var _exhausted: bool = false
var _sprinting: bool = false
var _since_sprint_s: float = INF
var _reported_cadence_rpm: float = 0.0
var _speed_model: SpeedModel = null
var _speed_mode: String = Wl.OFF
var _dropout_chance: float = 0.0
var _dropout_until_t: float = -1.0
var _in_dropout: bool = false
var _dropout_rng: RandomNumberGenerator = null
var _dropouts: int = 0
var _samples_emitted: int = 0
var _kb_power_offset_w: float = 0.0
var _kb_cadence_offset_rpm: float = 0.0
var _kb_down: Dictionary = {}
## key -> true from the press (seen going down) until the release: only such keys ramp.
var _kb_armed: Dictionary = {}
## key -> seconds held since the press.
var _kb_held_s: Dictionary = {}
## A preset's power and cadence (-1: none); T/G and Y/H move them while set.
var _kb_override_w: float = -1.0
var _kb_override_rpm: float = -1.0
var _kb_sprint: bool = false
## The next focused poll only notes the held keys (after enabling or regaining focus).
var _kb_baseline: bool = true


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure(DEFAULT_SPEC, parse_spec(DEFAULT_SPEC), 200.0, {})


## Build a mock from a profile spec for a rider with `ftp_w` (and CP = FTP unless given).
## options: {cp_w, wprime_j, preferred_cadence_rpm, weight_kg, max_power_w, seed,
## dropouts (bool, or a per-notification chance 0..1), keyboard (bool)}. An invalid spec
## push_errors and falls back to "erg".
static func from_spec(
	p_spec: String, p_ftp_w: float = 200.0, p_options: Dictionary = {}
) -> MockTrainer:
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
					return _spec_error(p_spec, '"%s" is not key=value' % pair.strip_edges())
				var key := pair.substr(0, eq).strip_edges().to_lower()
				var raw := pair.substr(eq + 1).strip_edges()
				if key == "" or not raw.is_valid_float():
					return _spec_error(p_spec, 'bad value in "%s"' % pair.strip_edges())
				if params.has(key):
					return _spec_error(p_spec, 'key "%s" given twice' % key)
				params[key] = float(raw)
		pname = pname.to_lower()
		if pname == "":
			return _spec_error(p_spec, "empty profile name")
		if not PROFILE_KEYS.has(pname):
			return _spec_error(p_spec, 'unknown profile "%s"' % pname)
		var allowed: Array = PROFILE_KEYS[pname]
		for key: String in params.keys():
			if not allowed.has(key):
				return _spec_error(p_spec, 'unknown key "%s" for %s' % [key, pname])
			var why := _check_param(key, float(params[key]))
			if why != "":
				return _spec_error(p_spec, why)
		for key: String in REQUIRED_KEYS.get(pname, []):
			if not params.has(key):
				return _spec_error(p_spec, "%s needs %s" % [pname, key])
		var bad := _check_component(pname, params)
		if bad != "":
			return _spec_error(p_spec, bad)
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
	if index != _phase_index:
		_phase_start_t = _t
	_phase_index = index


func set_keyboard_enabled(on: bool) -> void:
	if on and not _keyboard:
		_kb_baseline = true
	if not on and _keyboard:
		_kb_clear()
	_keyboard = on


## True while keyboard control reads its keys (options.keyboard or set_keyboard_enabled).
func is_keyboard_enabled() -> bool:
	return _keyboard


## The latest sample emitted (null before the first).
func last_sample() -> TrainerSample:
	return _last_sample


## The rider's true instantaneous power right now (between notifications).
func instantaneous_power_w() -> float:
	return _power_w


## The rider's true instantaneous cadence right now (between notifications).
func instantaneous_cadence_rpm() -> float:
	return _cadence_rpm


## The parsed profile components in use ([{"name", "params"}], a copy).
func components() -> Array:
	return _components.duplicate(true)


## Platform seconds this mock has been ticked.
func platform_time_s() -> float:
	return _t


func device_name() -> String:
	return "Mock trainer (%s)" % spec


func is_ready() -> bool:
	return _status == STATUS_READY


func status() -> String:
	return _status


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
	if _keyboard and dt > 0.0:
		_poll_keyboard(dt)
	var remaining := maxf(dt, 0.0)
	while remaining > 1e-9:
		var h := minf(remaining, Wl.SIM_DT)
		_step(h)
		remaining -= h


# --- Added in W1 ----------------------------------------------------------------------


## Every profile for docs and tool help: {name: {"keys": [...], "required": [...],
## "defaults": {key: value}, "summary": String}}, in PROFILE_KEYS order.
static func describe_profiles() -> Dictionary:
	var summaries := {
		"erg":
		"ERG follower: compliance x the applied target (tau ~2 s); in SIM compliance x the power band's centre, else 90% FTP",
		"zero": "0 W and 0 rpm from t = 0",
		"const": "constant power w at rpm (default: the preferred cadence)",
		"ramp": "power from from_w to to_w over over_s, then to_w",
		"intervals": "on_w for on_s, then off_w for off_s, repeating from t = 0",
		"noise": "seeded Gaussian noise (sd_w, sd_rpm) on each sample while pedaling",
		"band":
		(
			"cadence follows the published cadence band's centre + offset_rpm (2 s lag, noise "
			+ "within +-1.5 rpm); no band: the preferred cadence"
		),
		"cadence_drop":
		(
			"cadence held at rpm from at_s, or after_s into phase at_phase, or once the applied "
			+ "ERG target reaches at_target_pct % FTP; for for_s (default: the rest of the run); "
			+ "rpm 0 stops the rider"
		),
		"surge":
		(
			"every every_s, cadence and speed x (1 + lift) for for_s and at least two "
			+ "notifications (fires the ERG surge gesture); sim_pct: rides that % FTP in SIM"
		),
		"hr": "a mock heart rate sensor following power (rest_bpm .. max_bpm, 20 s lag)",
	}
	var defaults := {
		"erg": {"compliance": 1.0},
		"const": {},
		"ramp": {},
		"intervals": {"on_s": INTERVALS_DEFAULT_S, "off_s": INTERVALS_DEFAULT_S},
		"noise": {"sd_w": NOISE_SD_W, "sd_rpm": NOISE_SD_RPM},
		"band": {"offset_rpm": 0.0},
		"cadence_drop": {"after_s": 0.0, "for_s": INF},
		"surge": {"every_s": SURGE_EVERY_S, "for_s": SURGE_FOR_S, "lift": SURGE_LIFT},
		"hr": {"rest_bpm": HR_REST_BPM, "max_bpm": HR_MAX_BPM},
	}
	var out := {}
	for pname: String in PROFILE_KEYS.keys():
		out[pname] = {
			"keys": (PROFILE_KEYS[pname] as Array).duplicate(),
			"required": (REQUIRED_KEYS.get(pname, []) as Array).duplicate(),
			"defaults": (defaults.get(pname, {}) as Dictionary).duplicate(),
			"summary": str(summaries.get(pname, "")),
		}
	return out


## Keyboard control without the keyboard: add delta_w to the rider's power goal (to the
## preset's power while one is set).
func nudge_power(delta_w: float) -> void:
	if _kb_override_w >= 0.0:
		_kb_override_w = clampf(_kb_override_w + delta_w, 0.0, float(_max_power_w))
	else:
		_kb_power_offset_w += delta_w


## Keyboard control without the keyboard: add delta_rpm to the rider's cadence (to the
## preset's cadence while one is set).
func nudge_cadence(delta_rpm: float) -> void:
	if _kb_override_rpm >= 0.0:
		_kb_override_rpm = clampf(_kb_override_rpm + delta_rpm, 0.0, KEY_CADENCE_MAX_RPM)
	else:
		_kb_cadence_offset_rpm += delta_rpm


## Keyboard preset 1..9 without the keyboard: power at 25 x (index + 1)% of FTP, cadence at
## KEY_PRESET_RPM_MIN + KEY_PRESET_RPM_STEP x (index - 1). Out-of-range indexes are ignored.
func keyboard_preset(index: int) -> void:
	if index < 1 or index > 9:
		return
	var pct := KEY_PRESET_FTP_PCT_MIN + KEY_PRESET_FTP_PCT_STEP * float(index - 1)
	_kb_override_w = clampf(pct * _ftp_w / 100.0, 0.0, float(_max_power_w))
	_kb_override_rpm = KEY_PRESET_RPM_MIN + KEY_PRESET_RPM_STEP * float(index - 1)
	_kb_power_offset_w = 0.0
	_kb_cadence_offset_rpm = 0.0


## Keyboard stop without the keyboard: the rider stops pedaling (0 W, 0 rpm) until the power
## is raised again.
func keyboard_stop() -> void:
	_kb_override_w = 0.0
	_kb_override_rpm = -1.0
	_kb_power_offset_w = 0.0
	_kb_cadence_offset_rpm = 0.0


## Keyboard sprint without the keyboard: on while true, the previous setting returns after.
func keyboard_sprint(on: bool) -> void:
	_kb_sprint = on


## {"power_w", "cadence_rpm"}: the keyboard offsets in use.
func keyboard_offsets() -> Dictionary:
	return {"power_w": _kb_power_offset_w, "cadence_rpm": _kb_cadence_offset_rpm}


## {"power_w", "cadence_rpm" (-1: none), "sprint"}: the preset or stop and the sprint in use.
func keyboard_override() -> Dictionary:
	return {"power_w": _kb_override_w, "cadence_rpm": _kb_override_rpm, "sprint": _kb_sprint}


## The rider's W' balance in joules (fatigue model).
func wbal_j() -> float:
	return _wbal.wbal_j


## True while W' is used up and the follower can give only EXHAUSTED_CP_FRACTION x CP.
func is_exhausted() -> bool:
	return _exhausted


## The rider's true cadence right now (the samples carry the trainer's estimate of it).
func cadence_rpm() -> float:
	return _cadence_rpm


## The cadence the next sample will report (lags after sprints).
func reported_cadence_rpm() -> float:
	return _reported_cadence_rpm


## The speed the next sample will report (km/h).
func speed_kmh() -> float:
	return _speed_kmh


## True while a surge lifts cadence and speed.
func surging() -> bool:
	for s in _surges:
		if s.active:
			return true
	return false


## True while a cadence_drop holds the cadence.
func cadence_drop_active() -> bool:
	return _active_drop_rpm() >= 0.0


func phase_index() -> int:
	return _phase_index


## Samples emitted and notifications skipped by dropouts so far.
func samples_emitted() -> int:
	return _samples_emitted


func dropout_count() -> int:
	return _dropouts


## Another app takes control: status control_lost, Machine Status 0xFF, and every later
## command is answered 0x05 until restore_control().
func simulate_control_lost() -> void:
	_status = STATUS_CONTROL_LOST
	status_changed.emit(STATUS_CONTROL_LOST, FtmsClient.DETAIL_ANOTHER_APP)
	machine_status.emit(0xFF, PackedByteArray())


func restore_control() -> void:
	_status = STATUS_READY
	status_changed.emit(STATUS_READY, "")


## Seconds of profile time: at_s drops, surges, ramp and intervals count from here.
func profile_time_s() -> float:
	return _t - _run_start_t


## The `hr` profile's heart rate in whole bpm (0 without `hr`: no sensor).
func heart_rate_bpm() -> int:
	return roundi(_hr) if _has_hr else 0


func _update_heart_rate(h: float) -> void:
	if not _has_hr:
		return
	var target := _hr_rest
	if _power_w > 0.0:
		var frac := clampf(_power_w / (SPRINT_FTP_FRACTION * _ftp_w), 0.0, 1.0)
		target = _hr_rest + (_hr_max - _hr_rest) * (0.2 + 0.8 * frac)
	_hr += (target - _hr) * minf(h / HR_TAU_S, 1.0)


## Restart the profile from now (for example at session start, after the mock rode through
## menus): profile time returns to 0, every cadence_drop re-arms and every surge is next due
## every_s from now. The rider (power, W' balance, cadence, speed), the commanded state, the
## published bands and phase, and the notification schedule carry on unchanged.
func restart_profile() -> void:
	_run_start_t = _t
	for d in _drops:
		d.state = _DROP_WAITING
		d.trigger_t = 0.0
		d.start_t = 0.0
	for s in _surges:
		s.active = false
		s.samples = 0
		s.next_t = _t + s.every_s


# --- Configuration --------------------------------------------------------------------


func _configure(p_spec: String, comps: Array, p_ftp_w: float, options: Dictionary) -> void:
	spec = p_spec
	_components = comps
	_ftp_w = maxf(p_ftp_w, 1.0)
	_preferred_cadence_rpm = float(options.get("preferred_cadence_rpm", DEFAULT_CADENCE_RPM))
	_max_power_w = int(options.get("max_power_w", DEFAULT_MAX_POWER_W))
	_seed = int(options.get("seed", 0))
	_keyboard = bool(options.get("keyboard", false))
	_kb_baseline = true
	_scripted_power = {}
	_erg_compliance = 1.0
	_has_band = false
	_band_offset_rpm = 0.0
	_has_noise = false
	_drops = []
	_surges = []
	_sim_pct = -1.0
	_has_hr = false
	var found_erg := false
	for c: Dictionary in _components:
		var cname := str(c["name"])
		var p: Dictionary = c["params"]
		if _scripted_power.is_empty() and SCRIPTED_POWER.has(cname):
			_scripted_power = c
		match cname:
			"erg":
				if not found_erg:
					found_erg = true
					_erg_compliance = float(p.get("compliance", 1.0))
			"band":
				if not _has_band:
					_has_band = true
					_band_offset_rpm = float(p.get("offset_rpm", 0.0))
			"noise":
				if not _has_noise:
					_has_noise = true
					_noise_sd_w = float(p.get("sd_w", NOISE_SD_W))
					_noise_sd_rpm = float(p.get("sd_rpm", NOISE_SD_RPM))
			"cadence_drop":
				var d := DropState.new()
				d.rpm = float(p["rpm"])
				d.at_s = float(p.get("at_s", -1.0))
				d.at_phase = int(p.get("at_phase", -1.0))
				d.after_s = float(p.get("after_s", 0.0))
				d.at_target_pct = float(p.get("at_target_pct", -1.0))
				d.for_s = float(p.get("for_s", INF))
				_drops.append(d)
			"surge":
				var s := SurgeState.new()
				s.every_s = float(p.get("every_s", SURGE_EVERY_S))
				s.for_s = float(p.get("for_s", SURGE_FOR_S))
				s.lift = float(p.get("lift", SURGE_LIFT))
				s.next_t = s.every_s
				_surges.append(s)
				if _sim_pct < 0.0 and p.has("sim_pct"):
					_sim_pct = float(p["sim_pct"])
			"hr":
				if not _has_hr:
					_has_hr = true
					_hr_rest = float(p.get("rest_bpm", HR_REST_BPM))
					_hr_max = maxf(float(p.get("max_bpm", HR_MAX_BPM)), _hr_rest)
	_hr = _hr_rest
	var cp := float(options.get("cp_w", _ftp_w))
	_wbal = WBalance.create(
		maxf(cp, 1.0), maxf(float(options.get("wprime_j", DEFAULT_WPRIME_J)), 1.0)
	)
	_exhausted = false
	_speed_model = SpeedModel.create(float(options.get("weight_kg", DEFAULT_WEIGHT_KG)))
	var dropouts: Variant = options.get("dropouts", false)
	if dropouts is bool:
		_dropout_chance = DROPOUT_CHANCE if dropouts else 0.0
	else:
		_dropout_chance = clampf(float(dropouts), 0.0, 1.0)
	# Each randomness source gets its own stream, so noise, band noise and dropouts never
	# shift the notification times.
	_sample_rng = SeededRng.make(SeededRng.derive(_seed, "mock_trainer:samples"))
	_noise_rng = SeededRng.make(SeededRng.derive(_seed, "mock_trainer:noise"))
	_band_rng = SeededRng.make(SeededRng.derive(_seed, "mock_trainer:band"))
	_dropout_rng = SeededRng.make(SeededRng.derive(_seed, "mock_trainer:dropouts"))
	_t = 0.0
	_run_start_t = 0.0
	_next_sample_t = _sample_interval()


# --- Rider model ----------------------------------------------------------------------


## One fixed step of the rider model (h <= Wl.SIM_DT platform seconds).
func _step(h: float) -> void:
	_t += h
	_update_drops()
	_update_surges()
	var drop_rpm := _active_drop_rpm()
	var follower := _scripted_power.is_empty()
	var goal := (
		_follower_goal_w() if follower else _scripted_power_w(_scripted_power, profile_time_s())
	)
	goal = _keyboard_goal_w(goal)
	if drop_rpm >= 0.0 and drop_rpm < 1.0:
		goal = 0.0
	if goal <= 0.0:
		goal = 0.0
		_power_w = 0.0
		_power_rate = 0.0
	elif follower and not _kb_direct():
		var g := minf(goal, _fatigue_cap_w())
		var accel := (
			ERG_OMEGA * ERG_OMEGA * (g - _power_w) - 2.0 * ERG_DAMPING * ERG_OMEGA * _power_rate
		)
		_power_rate += h * accel
		_power_w = maxf(_power_w + h * _power_rate, 0.0)
	else:
		_power_w = goal
		_power_rate = 0.0
	_update_fatigue(h)
	_update_heart_rate(h)
	_sprinting = follower and commanded_mode != Wl.ERG and _power_w >= SPRINT_FTP_FRACTION * _ftp_w
	_since_sprint_s = 0.0 if _sprinting else _since_sprint_s + h
	var pedaling := goal > 0.0
	_cadence_rpm = _cadence_now(pedaling, drop_rpm, h)
	_update_reported_cadence(pedaling, h)
	_update_speed(h)
	if _t + 1e-9 >= _next_sample_t:
		if not _dropout_now():
			_emit_sample()
		_next_sample_t += _sample_interval()


## The follower's goal: sim_pct in SIM; compliance x the commanded target in ERG; otherwise
## compliance x the power band's centre, or FREE_RIDE_PCT of FTP without a band.
func _follower_goal_w() -> float:
	if commanded_mode == Wl.SIM and _sim_pct > 0.0:
		return _sim_pct * _ftp_w / 100.0
	return _erg_goal_w()


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
		"intervals":
			var on_s := float(p.get("on_s", INTERVALS_DEFAULT_S))
			var off_s := float(p.get("off_s", INTERVALS_DEFAULT_S))
			var into := fmod(t, on_s + off_s)
			return float(p["on_w"]) if into < on_s else float(p["off_w"])
	return 0.0


func _fatigue_cap_w() -> float:
	return EXHAUSTED_CP_FRACTION * _wbal.cp_w if _exhausted else INF


func _update_fatigue(h: float) -> void:
	_wbal.step(_power_w, h)
	if not _exhausted and _wbal.wbal_j <= 0.0:
		_exhausted = true
	elif _exhausted and _wbal.wbal_j >= RECOVERED_WPRIME_FRACTION * _wbal.wprime_j:
		_exhausted = false


## The profile's own rpm (const, ramp, intervals) or the preferred cadence.
func _base_cadence_rpm() -> float:
	if not _scripted_power.is_empty():
		return float((_scripted_power["params"] as Dictionary).get("rpm", _preferred_cadence_rpm))
	return _preferred_cadence_rpm


func _cadence_band_published() -> bool:
	return _cadence_band_lo > 0.0 or _cadence_band_hi > 0.0


func _band_target_rpm() -> float:
	if _cadence_band_published():
		return 0.5 * (_cadence_band_lo + _cadence_band_hi) + _band_offset_rpm
	return _base_cadence_rpm()


## True cadence this step (precedence in the class doc).
func _cadence_now(pedaling: bool, drop_rpm: float, h: float) -> float:
	if not pedaling:
		_band_valid = false
		return 0.0
	var c := 0.0
	if _has_band:
		var target := _band_target_rpm()
		if not _band_valid:
			_band_cadence = target
			_band_noise = 0.0
			_band_valid = true
		else:
			_band_cadence += (target - _band_cadence) * (1.0 - exp(-h / BAND_LAG_S))
		var decay := exp(-h / BAND_NOISE_TAU_S)
		var kick := (
			BAND_NOISE_SD_RPM * sqrt(1.0 - decay * decay) * SeededRng.normal(_band_rng, 0.0, 1.0)
		)
		_band_noise = clampf(_band_noise * decay + kick, -BAND_NOISE_MAX_RPM, BAND_NOISE_MAX_RPM)
		c = _band_cadence + _band_noise
	else:
		c = _base_cadence_rpm()
	var kb_rpm := _keyboard_cadence_rpm()
	if kb_rpm >= 0.0:
		c = kb_rpm
	else:
		c = _clamped_cadence_offset(c)
		if _sprinting and not _has_band:
			c *= 1.0 + SPRINT_CADENCE_LIFT
	var lift := _surge_lift()
	if lift > 0.0:
		c *= 1.0 + lift
	if drop_rpm >= 0.0:
		c = drop_rpm
	return maxf(c, 0.0)


func _update_reported_cadence(pedaling: bool, h: float) -> void:
	if not pedaling:
		_reported_cadence_rpm = 0.0
	elif (
		not _sprinting
		and _since_sprint_s < SPRINT_LAG_WINDOW_S
		and _cadence_rpm < _reported_cadence_rpm
	):
		_reported_cadence_rpm += (
			(_cadence_rpm - _reported_cadence_rpm) * (1.0 - exp(-h / CADENCE_LAG_TAU_S))
		)
	else:
		_reported_cadence_rpm = _cadence_rpm


func _update_speed(h: float) -> void:
	if commanded_mode == Wl.SIM:
		if _speed_mode != Wl.SIM:
			_speed_model.reset(_speed_kmh / 3.6)
		_speed_model.step(h, _power_w, commanded_grade_pct, commanded_wind_mps)
		_speed_kmh = _speed_model.speed_kmh() * (1.0 + _surge_lift())
	else:
		_speed_kmh = _cadence_rpm * KMH_PER_RPM
	_speed_mode = commanded_mode


func _update_drops() -> void:
	for d in _drops:
		if d.state == _DROP_WAITING:
			if d.at_s >= 0.0:
				if profile_time_s() + 1e-9 >= d.at_s:
					d.state = _DROP_ACTIVE
					d.start_t = _t
			elif d.at_phase < 0 or _phase_index == d.at_phase:
				if d.at_target_pct > 0.0:
					var reached := (
						float(commanded_target_w) + 1e-6 >= d.at_target_pct * _ftp_w / 100.0
					)
					if commanded_mode == Wl.ERG and reached:
						d.state = _DROP_COUNTING
						d.trigger_t = _t
				else:
					d.state = _DROP_COUNTING
					d.trigger_t = _phase_start_t
		if d.state == _DROP_COUNTING:
			if d.at_phase >= 0 and _phase_index != d.at_phase:
				d.state = _DROP_WAITING
			elif _t + 1e-9 >= d.trigger_t + d.after_s:
				d.state = _DROP_ACTIVE
				d.start_t = _t
		if d.state == _DROP_ACTIVE and _t + 1e-9 >= d.start_t + d.for_s:
			d.state = _DROP_DONE


## The lowest rpm among active drops, or -1.
func _active_drop_rpm() -> float:
	var rpm := -1.0
	for d in _drops:
		if d.state == _DROP_ACTIVE and (rpm < 0.0 or d.rpm < rpm):
			rpm = d.rpm
	return rpm


func _update_surges() -> void:
	for s in _surges:
		if s.active and _t + 1e-9 >= s.start_t + s.for_s and s.samples >= SURGE_MIN_SAMPLES:
			s.active = false
		if _t + 1e-9 >= s.next_t:
			if not s.active:
				s.active = true
				s.start_t = _t
				s.samples = 0
			s.next_t += s.every_s


func _surge_lift() -> float:
	var lift := 0.0
	for s in _surges:
		if s.active:
			lift = maxf(lift, s.lift)
	return lift


## True when this notification is lost. A surge's notifications are never lost, and no gap
## starts in the SURGE_GUARD_S before a surge, so the surge gesture's 10 s average always has
## data (docs/OWNERSHIP.md C30); a surge also ends an ongoing gap. The first notification
## after a gap always arrives, so gaps never chain.
func _dropout_now() -> bool:
	if _dropout_chance <= 0.0 or surging():
		_in_dropout = false
		_dropout_until_t = -1.0
		return false
	if _t < _dropout_until_t:
		_in_dropout = true
		return true
	if _in_dropout:
		_in_dropout = false
		return false
	for sg in _surges:
		if sg.next_t - _t < SURGE_GUARD_S:
			return false
	if SeededRng.chance(_dropout_rng, _dropout_chance):
		_in_dropout = true
		_dropout_until_t = _t + SeededRng.range_f(_dropout_rng, DROPOUT_MIN_S, DROPOUT_MAX_S)
		_dropouts += 1
		return true
	return false


func _emit_sample() -> void:
	var p := _power_w
	var c := _reported_cadence_rpm
	if _has_noise and _power_w > 0.0:
		p = maxf(p + SeededRng.normal(_noise_rng, 0.0, _noise_sd_w), 0.0)
		c = maxf(c + SeededRng.normal(_noise_rng, 0.0, _noise_sd_rpm), 0.0)
	var s := TrainerSample.make(
		_t, roundf(p), roundf(c * 2.0) / 2.0, roundf(_speed_kmh * 100.0) / 100.0
	)
	_last_sample = s
	_samples_emitted += 1
	for sg in _surges:
		if sg.active:
			sg.samples += 1
	sample_received.emit(s)


func _sample_interval() -> float:
	return SeededRng.range_f(_sample_rng, SAMPLE_MIN_S, SAMPLE_MAX_S)


## Keyboard control (BRIEF 4.2), only while enabled and while the app window has focus: a
## key counts when it goes down. Keys are read only while focused, and the first poll after
## enabling or after the window regains focus only notes which keys are held, so a key pressed
## in another window never nudges the rider and a key held through a focus change never ramps.
## Held ramp keys integrate over the polled dt (platform time).
func _poll_keyboard(dt: float) -> void:
	var focused: bool = bool(focus_reader.call()) if focus_reader.is_valid() else _window_focused()
	if not focused:
		_kb_baseline = true
		_kb_sprint = false
		_kb_armed.clear()
		_kb_held_s.clear()
		return
	var baseline := _kb_baseline
	_kb_baseline = false
	for k: Key in _keyboard_keys():
		var down := _key_down(k)
		var was := bool(_kb_down.get(k, false))
		_kb_down[k] = down
		if not down:
			_kb_armed.erase(k)
			_kb_held_s.erase(k)
			continue
		if not baseline and not was:
			_kb_armed[k] = true
			_kb_held_s[k] = 0.0
			_on_key_pressed(k)
		elif bool(_kb_armed.get(k, false)):
			_kb_held_s[k] = float(_kb_held_s.get(k, 0.0)) + dt
			_ramp_key(k, dt)
	_kb_sprint = bool(_kb_armed.get(KEY_SPRINT, false))


func _keyboard_keys() -> Array:
	var keys: Array = [
		KEY_POWER_UP,
		KEY_POWER_DOWN,
		KEY_CADENCE_UP,
		KEY_CADENCE_DOWN,
		KEY_SPRINT,
		KEY_STOP,
		KEY_KP_0
	]
	keys.append_array(KEYBOARD_PRESET_KEYS.keys())
	return keys


func _key_down(k: Key) -> bool:
	return bool(key_reader.call(k)) if key_reader.is_valid() else Input.is_physical_key_pressed(k)


## A key went down (the sprint key only arms: _poll_keyboard reads its hold).
func _on_key_pressed(k: Key) -> void:
	if KEYBOARD_PRESET_KEYS.has(k):
		keyboard_preset(int(KEYBOARD_PRESET_KEYS[k]))
		return
	match k:
		KEY_POWER_UP:
			nudge_power(KEY_POWER_STEP_W)
		KEY_POWER_DOWN:
			nudge_power(-KEY_POWER_STEP_W)
		KEY_CADENCE_UP:
			nudge_cadence(KEY_CADENCE_STEP_RPM)
		KEY_CADENCE_DOWN:
			nudge_cadence(-KEY_CADENCE_STEP_RPM)
		KEY_STOP, KEY_KP_0:
			keyboard_stop()


## A held T/G/Y/H key past KEY_HOLD_DELAY_S ramps: the speed grows exponentially from the first
## to the second value of its range over KEY_RAMP_UP_S.
func _ramp_key(k: Key, dt: float) -> void:
	var held := float(_kb_held_s.get(k, 0.0))
	var active := clampf(held - KEY_HOLD_DELAY_S, 0.0, dt)
	if active <= 0.0:
		return
	var u := clampf((held - KEY_HOLD_DELAY_S) / KEY_RAMP_UP_S, 0.0, 1.0)
	match k:
		KEY_POWER_UP, KEY_POWER_DOWN:
			var w := _ramp_speed(KEY_POWER_RAMP_W_PER_S, u) * active
			nudge_power(w if k == KEY_POWER_UP else -w)
		KEY_CADENCE_UP, KEY_CADENCE_DOWN:
			var rpm := _ramp_speed(KEY_CADENCE_RAMP_RPM_PER_S, u) * active
			nudge_cadence(rpm if k == KEY_CADENCE_UP else -rpm)


static func _ramp_speed(speeds: Vector2, u: float) -> float:
	return speeds.x * pow(speeds.y / speeds.x, u)


## True while a preset, a stop or the sprint holds the power: it then follows at once.
func _kb_direct() -> bool:
	return _kb_sprint or _kb_override_w >= 0.0


## The power goal with the keyboard applied: the sprint, else the preset, else `goal` plus the
## offset (kept inside 0 .. max_power_w by moving the offset back).
func _keyboard_goal_w(goal: float) -> float:
	var max_w := float(_max_power_w)
	if _kb_sprint:
		return minf(KEY_SPRINT_FTP_FRACTION * _ftp_w, max_w)
	if _kb_override_w >= 0.0:
		return minf(_kb_override_w, max_w)
	if _kb_power_offset_w == 0.0:
		return goal
	var g := clampf(goal + _kb_power_offset_w, 0.0, max_w)
	_kb_power_offset_w = g - goal
	return g


## The cadence the sprint or a preset sets, -1 without either.
func _keyboard_cadence_rpm() -> float:
	if _kb_sprint:
		return KEY_SPRINT_RPM
	return _kb_override_rpm


## `base` plus the cadence offset, kept inside 0 .. KEY_CADENCE_MAX_RPM by moving the offset.
func _clamped_cadence_offset(base: float) -> float:
	if _kb_cadence_offset_rpm == 0.0:
		return base
	var c := clampf(base + _kb_cadence_offset_rpm, 0.0, KEY_CADENCE_MAX_RPM)
	_kb_cadence_offset_rpm = c - base
	return c


## Back to the rider's own power and cadence (the keyboard was switched off).
func _kb_clear() -> void:
	_kb_override_w = -1.0
	_kb_override_rpm = -1.0
	_kb_sprint = false
	_kb_power_offset_w = 0.0
	_kb_cadence_offset_rpm = 0.0
	_kb_down.clear()
	_kb_armed.clear()
	_kb_held_s.clear()


## True while this mock's window (the app's) has focus; false outside the tree.
func _window_focused() -> bool:
	if not is_inside_tree():
		return false
	var w := get_window()
	return w != null and w.has_focus()


func _record(opcode: int) -> void:
	command_count += 1
	var result := response_result if _status == STATUS_READY else RESULT_CONTROL_NOT_PERMITTED
	_pending_responses.append(Vector2i(opcode, result))


func _flush_responses() -> void:
	if _pending_responses.is_empty():
		return
	var pending := _pending_responses
	_pending_responses = []
	for r in pending:
		control_response.emit(r.x, r.y)


## "" if `value` is allowed for `key`, else why not.
static func _check_param(key: String, value: float) -> String:
	if key == "compliance" and (value < 0.0 or value > 1.0):
		return "compliance must be within 0..1"
	if key == "offset_rpm":
		return ""
	if value < 0.0:
		return "%s must not be negative" % key
	if key == "at_phase" and value != floorf(value):
		return "at_phase must be a whole phase index"
	if (key == "every_s" or key == "for_s" or key == "on_s" or key == "off_s") and value <= 0.0:
		return "%s must be positive" % key
	if key == "lift" and value > 2.0:
		return "lift must be within 0..2"
	if (key == "sim_pct" or key == "at_target_pct") and (value <= 0.0 or value > 300.0):
		return "%s must be within 0..300" % key
	return ""


## "" if a whole component is consistent, else why not.
static func _check_component(pname: String, params: Dictionary) -> String:
	if pname == "cadence_drop":
		var by_time := params.has("at_s")
		if not by_time and not params.has("at_phase") and not params.has("at_target_pct"):
			return "cadence_drop needs at_s, at_phase or at_target_pct"
		if (
			by_time
			and (params.has("at_phase") or params.has("at_target_pct") or params.has("after_s"))
		):
			return "cadence_drop: at_s excludes at_phase, at_target_pct and after_s"
	if pname == "surge":
		if float(params.get("for_s", SURGE_FOR_S)) >= float(params.get("every_s", SURGE_EVERY_S)):
			return "surge for_s must be shorter than every_s"
	return ""


static func _spec_error(p_spec: String, why: String) -> Array:
	push_error('MockTrainer: invalid profile spec "%s": %s' % [p_spec, why])
	return []
