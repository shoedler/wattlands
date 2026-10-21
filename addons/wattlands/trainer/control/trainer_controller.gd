class_name TrainerController
extends Node
## The trainer's command shaper (BRIEF 4.1, 4.5, 4.6.2): modes ERG / SIM / RESISTANCE (P1) /
## OFF, ERG slew, ramped mode switches and write coalescing. Owned by trainer-control.
##
## Safety structure (BRIEF 4.6.11): only SafetyGovernor holds a TrainerController, and only
## this class calls the TrainerDevice setters (set_target_power, set_simulation,
## set_resistance, request_stop). tests/arch/test_no_bypass.gd enforces it.
##
## The governor decides WHAT the trainer should do each tick (command_erg / command_sim /
## command_off, with every 4.6 rule already applied); the controller decides HOW and WHEN:
##   - Slew (4.6.2): the applied ERG target rises at most SLEW_UP_W_PER_S; decreases are
##     immediate. Slew is the last rule (4.6.12), so it lives here.
##   - ERG -> SIM (4.5): first ERG at max(floor, min(applied target, 3 s power)) (skipped when
##     that is not lower than the written target), then SIM at grade 0 and wind 0, then the
##     stacked SIM state.
##   - SIM -> ERG (4.5): first SIM grade 0 and wind 0 (skipped when already flat), then ERG at
##     max(floor, min(3 s power, the governed target)), so the entry is never above the planned
##     or directed target and never below the floor; then slew up. After a panic resume the
##     entry is the floor.
##   - Coalescing (4.5): at most one write per MIN_WRITE_INTERVAL_S (so at most 2 writes per
##     second). Each write is computed from the newest command when its slot opens, so
##     superseded commands are dropped and the newest is always sent.
##   - Panic and shutdown write at once (safety outranks coalescing; ADR in
##     docs/decisions/trainer-control.md): emergency_safe() sends SIM grade 0 and wind 0;
##     shutdown() sends SIM flat, then Stop (0x08 0x01).
## Time advances only through tick(dt) (platform time); nothing reads the wall clock.

## Minimum spacing between two control writes (2 writes per second).
const MIN_WRITE_INTERVAL_S := 0.5
## ERG increases at most this fast (BRIEF 4.6.2).
const SLEW_UP_W_PER_S := 30.0
## FTMS resolutions used to quantize SIM writes and to compare SIM states (BRIEF 4.3).
const GRADE_STEP := 0.01
const WIND_STEP := 0.001
const CRR_STEP := 0.0001
const CW_STEP := 0.01
## Write-log entries kept for tests and diagnostics.
const LOG_MAX := 256

const OP_ERG := "erg"
const OP_SIM := "sim"
const OP_RESISTANCE := "resistance"
const OP_STOP := "stop"

const _EPS := 1e-6

var _device: TrainerDevice = null
## Platform seconds advanced through tick().
var _t: float = 0.0
var _last_write_t: float = -1e9
var _write_count: int = 0
var _log: Array[Dictionary] = []

# What the trainer was last told (the written state).
var _mode: String = Wl.OFF
var _written_erg_w: int = 0
var _written_sim: Dictionary = {"wind_mps": 0.0, "grade_pct": 0.0, "crr": 0.004, "cw": 0.51}
var _written_level: float = 0.0

# The newest command from the governor.
var _want_mode: String = Wl.OFF
var _want_erg_w: int = 0
var _want_floor_w: int = 0
var _want_p3s_w: float = 0.0
var _want_sim: Dictionary = {"wind_mps": 0.0, "grade_pct": 0.0, "crr": 0.004, "cw": 0.51}
var _want_level: float = 0.0

# ERG shaping.
## The applied ERG target with slew (whole watts are taken by rounding down).
var _erg_w: float = 0.0
## The current ERG target started at a SIM -> ERG entry and is still slewing up to the command.
var _entry_active: bool = false
## The ERG -> SIM step-down has been decided for the current switch.
var _stepped_down: bool = false
## The next SIM -> ERG entry starts at the floor (after a panic resume).
var _resume_floor: bool = false
## Panic hold: SIM flat until release_safe().
var _safe: bool = false
## shutdown() ran: nothing more is written until setup().
var _stopped: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Bind the device. Resets the written state (the trainer's real state is unknown: the
## connection flow left it at SIM flat, BRIEF 4.4), so the next ERG command uses the entry rule.
func setup(device: TrainerDevice) -> void:
	_device = device
	_mode = Wl.OFF
	_written_erg_w = 0
	_written_level = 0.0
	_erg_w = 0.0
	_entry_active = false
	_stepped_down = false
	_safe = false
	_stopped = false
	_last_write_t = -1e9


func device() -> TrainerDevice:
	return _device


## ERG with the governed target (every 4.6 rule except slew already applied), the floor and
## the rider's 3 s power (for the SIM -> ERG entry).
func command_erg(governed_w: int, floor_w: int, power_3s_w: float) -> void:
	if _want_mode != Wl.ERG:
		_stepped_down = false
	_want_mode = Wl.ERG
	_want_floor_w = floor_w
	_want_erg_w = maxi(governed_w, floor_w)
	_want_p3s_w = maxf(power_3s_w, 0.0)


## SIM with the stacked state; floor and 3 s power shape the ERG -> SIM step-down.
func command_sim(wind_mps: float, grade_pct: float, crr: float, cw: float, floor_w: int, power_3s_w: float) -> void:
	_want_mode = Wl.SIM
	_want_sim = {"wind_mps": wind_mps, "grade_pct": grade_pct, "crr": crr, "cw": cw}
	_want_floor_w = floor_w
	_want_p3s_w = maxf(power_3s_w, 0.0)


## RESISTANCE (P1 fallback): level in device units.
func command_resistance(level: float) -> void:
	_want_mode = Wl.RESISTANCE
	_want_level = level


## No command: nothing new is written (the trainer keeps its last state).
func command_off() -> void:
	_want_mode = Wl.OFF


## Panic (BRIEF 4.6.5): SIM grade 0 and wind 0 at once, bypassing coalescing, then hold
## until release_safe().
func emergency_safe(crr: float, cw: float) -> void:
	_safe = true
	_stepped_down = false
	_entry_active = false
	if _device == null or _stopped:
		return
	_write_sim({"wind_mps": 0.0, "grade_pct": 0.0, "crr": crr, "cw": cw})


## Leave the panic hold; the next ERG entry starts at the floor and slews up.
func release_safe() -> void:
	if not _safe:
		return
	_safe = false
	_resume_floor = true


## Exit, crash and disconnect paths (BRIEF 4.6.9): SIM flat, then Stop, at once.
func shutdown(crr: float, cw: float) -> void:
	if _device == null or _stopped:
		_stopped = true
		return
	_write_sim({"wind_mps": 0.0, "grade_pct": 0.0, "crr": crr, "cw": cw})
	_device.request_stop()
	_note(OP_STOP, {})
	_mode = Wl.OFF
	_stopped = true
	_safe = false


## Advance by dt platform seconds: slew, then at most one write if its slot is open.
func tick(dt: float) -> void:
	if dt > 0.0:
		_t += dt
	if _device == null or _stopped:
		return
	_update_slew(maxf(dt, 0.0))
	if _safe:
		return
	_try_write()


## The mode the trainer was last put in: "ERG", "SIM", "RESISTANCE" or "OFF".
func mode() -> String:
	return _mode


## The applied ERG target in whole watts after slew (0 outside ERG). It may run up to one
## write slot ahead of the last written target.
func applied_target_w() -> int:
	if _mode != Wl.ERG:
		return 0
	return int(floor(_erg_w + 1e-9))


## The last ERG target written to the device (0 outside ERG).
func written_target_w() -> int:
	return _written_erg_w if _mode == Wl.ERG else 0


## The last SIM state written: {wind_mps, grade_pct, crr, cw}.
func written_sim() -> Dictionary:
	return _written_sim.duplicate()


## The newest commanded mode.
func wanted_mode() -> String:
	return _want_mode


## True while the written mode differs from the commanded one (a ramped switch in progress).
func in_transition() -> bool:
	if _want_mode == Wl.OFF:
		return false
	return _want_mode != _mode


## True while the ERG target is still rising from a SIM -> ERG entry toward the command.
func entry_active() -> bool:
	return _entry_active and _mode == Wl.ERG


func is_safe() -> bool:
	return _safe


func is_stopped() -> bool:
	return _stopped


func write_count() -> int:
	return _write_count


func last_write_t() -> float:
	return _last_write_t


## Platform time of this controller (seconds of tick()).
func time_s() -> float:
	return _t


## The most recent writes (at most LOG_MAX): {t, op, ...values}.
func write_log() -> Array[Dictionary]:
	return _log.duplicate(true)


func _update_slew(dt: float) -> void:
	if _mode != Wl.ERG or _want_mode != Wl.ERG or _safe:
		return
	var goal := float(_want_erg_w)
	if goal <= _erg_w + 1e-9:
		_erg_w = goal
		_entry_active = false
	else:
		_erg_w = minf(goal, _erg_w + SLEW_UP_W_PER_S * dt)
		if _erg_w >= goal - 1e-9:
			_entry_active = false


func _slot_open() -> bool:
	return _t - _last_write_t >= MIN_WRITE_INTERVAL_S - _EPS


func _try_write() -> void:
	if not _slot_open():
		return
	match _want_mode:
		Wl.ERG:
			_next_erg_write()
		Wl.SIM:
			_next_sim_write()
		Wl.RESISTANCE:
			if _mode != Wl.RESISTANCE or not is_equal_approx(_written_level, _want_level):
				_write_resistance(_want_level)
		_:
			pass


func _next_erg_write() -> void:
	if _mode == Wl.ERG:
		_stepped_down = false
		var w := int(floor(_erg_w + 1e-9))
		if w != _written_erg_w:
			_write_erg(w)
		return
	if _mode == Wl.SIM and not _is_flat(_written_sim):
		# SIM -> ERG, step 1: grade 0 and wind 0 first.
		_write_sim({"wind_mps": 0.0, "grade_pct": 0.0, "crr": _written_sim["crr"], "cw": _written_sim["cw"]})
		return
	# SIM -> ERG, step 2 (or a first ERG command): the entry target.
	var entry := _want_floor_w
	if not _resume_floor:
		entry = maxi(_want_floor_w, mini(int(floor(_want_p3s_w + 1e-9)), _want_erg_w))
	_resume_floor = false
	_erg_w = float(entry)
	_entry_active = entry < _want_erg_w
	_write_erg(entry)


func _next_sim_write() -> void:
	if _mode == Wl.ERG:
		if not _stepped_down:
			_stepped_down = true
			var applied := int(floor(_erg_w + 1e-9))
			var step := maxi(_want_floor_w, mini(applied, int(floor(_want_p3s_w + 1e-9))))
			if step < _written_erg_w:
				# ERG -> SIM, step 1: lower the ERG target to min(applied, 3 s power).
				_erg_w = float(step)
				_write_erg(step)
				return
		# ERG -> SIM, step 2: enter SIM at grade 0 and wind 0.
		_stepped_down = false
		_write_sim({"wind_mps": 0.0, "grade_pct": 0.0, "crr": _want_sim["crr"], "cw": _want_sim["cw"]})
		return
	_resume_floor = false
	if _mode != Wl.SIM or not _sim_equal(_written_sim, _want_sim):
		_write_sim(_want_sim)


func _write_erg(w: int) -> void:
	_device.set_target_power(w)
	_mode = Wl.ERG
	_written_erg_w = w
	_note(OP_ERG, {"w": w})


func _write_sim(state: Dictionary) -> void:
	var q := _quantize(state)
	_device.set_simulation(float(q["wind_mps"]), float(q["grade_pct"]), float(q["crr"]), float(q["cw"]))
	_mode = Wl.SIM
	_written_sim = q
	_entry_active = false
	_note(OP_SIM, q)


func _write_resistance(level: float) -> void:
	_device.set_resistance(level)
	_mode = Wl.RESISTANCE
	_written_level = level
	_note(OP_RESISTANCE, {"level": level})


func _note(op: String, values: Dictionary) -> void:
	_write_count += 1
	_last_write_t = _t
	var entry := {"t": _t, "op": op}
	entry.merge(values)
	_log.append(entry)
	if _log.size() > LOG_MAX:
		_log.remove_at(0)


static func _quantize(state: Dictionary) -> Dictionary:
	return {
		"wind_mps": snappedf(float(state.get("wind_mps", 0.0)), WIND_STEP),
		"grade_pct": snappedf(float(state.get("grade_pct", 0.0)), GRADE_STEP),
		"crr": snappedf(float(state.get("crr", 0.004)), CRR_STEP),
		"cw": snappedf(float(state.get("cw", 0.51)), CW_STEP),
	}


static func _sim_equal(a: Dictionary, b: Dictionary) -> bool:
	var qa := _quantize(a)
	var qb := _quantize(b)
	for k: String in ["wind_mps", "grade_pct", "crr", "cw"]:
		if absf(float(qa[k]) - float(qb[k])) > 1e-9:
			return false
	return true


static func _is_flat(state: Dictionary) -> bool:
	var q := _quantize(state)
	return absf(float(q["grade_pct"])) < 1e-9 and absf(float(q["wind_mps"])) < 1e-9
