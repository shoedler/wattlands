class_name SafetyGovernor
extends Node
## The only path that can change trainer resistance (BRIEF 3.1 pillar 5, 4.6). One per
## rider (local riders, bots and every in-process MockTrainer rider). Owned by
## trainer-control; the public API below is frozen after W0 (additive changes only).
##
## Structure (4.6.11): only SafetyGovernor holds a TrainerController; only the
## controller calls TrainerDevice setters. Everything a game asks for arrives as an
## EffortPlan (set_plan + start_phase) plus EffortDirectives, course grades and gear shifts;
## the governor turns them into one applied ERG target or SIM state per tick, applying in
## order (4.6.12): panic > [plan/directive target x unverified factor, limited by the
## ceilings, the long-phase cap, duration limits and the warm-up cap] > rescue 50% >
## coasting floor > the floor (wins over every cap and over rescue) > slew (increases only).
## SIM grade follows 4.6.6 stacking. Mode switches are ramped (4.5).
##
## Time: tick(dt) advances every time-based rule on PLATFORM time (fixed 0.05 s steps);
## phase-relative values (ramps, directive expiry) count game time, which stops while
## set_game_paused(true). on_sample() feeds trainer samples (about 1 Hz). Never reads the
## wall clock, so headless runs at any sim speed are exact.
##
## Status dictionary (status(), status_changed, Telemetry fields):
##   mode ("ERG"/"SIM"/"OFF"), applied_target_w (int), applied_pct, applied_grade_pct,
##   wind_mps, crr, cw, haptic_active, clamped_by (Array[String], Wl.CLAMP_*), rescue,
##   coasting, afk, paused, panic, warmup_active, warmup_remaining_s, gear (1..24),
##   s_left_105, s_left_120, latched_105, latched_120, phase_index, phase_elapsed_s,
##   sim_block_active, last_switch_t, profile ("normal"/"ramp_test").
## Added in W1 (additive): t (platform s), game_t, desired_mode ("ERG"/"SIM"/"SAFE"/"OFF"),
##   governed_target_w (every rule but slew), planned_pct, haptic_pct, power_3s_w,
##   course_grade_pct, mode_grade_pct, base_grade_pct, rescue_ramp (bool), test_ended (bool),
##   shut_down (bool), ftp_w, ftp_verified, written_target_w, written_grade_pct.
## Added in W4 (additive): reset_run_s (seconds of ERG at <= 90% FTP toward the 4.6.1 120 s
##   reset), samples_stale (the trainer's sample stream went stale with the link up, SAF-7).
##
## Implementation notes (details in docs/decisions/trainer-control.md):
##   - on_sample() queues the sample; the next tick() processes it at that tick's platform
##     time, so LocalRider's order (device.tick, on_sample, governor.tick) times every rule
##     from the tick in which the sample arrived.
##   - not_pedaling is the one shared detector GestureRecognizer.is_not_pedaling (BRIEF 3.5:
##     power < 15 W and cadence < 20 rpm, strict; an absent cadence counts as low), the same
##     predicate coast and stop_5s use; the governor keeps no thresholds of its own.
##     Coasting (3 s), the 10 s pause/AFK and the rescue hold are timed from the first sample
##     that meets their condition; a sample that breaks it restarts it. The rescue triggers
##     need their condition for the whole 3 s / 5 s while rescue is armed (in ERG with a
##     governed target >= 60% FTP), so a low reading from an unarmed phase never fires at the
##     moment a harder phase arms it. Pause and AFK are raised only while a phase runs.
##     Edges (BRIEF 4.6.3): rescue arms at >= 60% FTP, triggers on cadence < 45 rpm or power
##     < 75% of the ERG target written to the trainer, and its hold ends on cadence >= 70 rpm.
##   - Directive channels per BRIEF 3.6. Structural problems refuse the whole request; a
##     haptic dropped for warm-up, opt-out or cooldown is reported in record.dropped and the
##     rest of the request still applies (refused only when nothing else was set). A haptic
##     to a rider in ERG refuses the whole request (never a mode switch).
##   - No phase (W2r2): with no plan, a plan before its first start_phase(), or after
##     clear_plan(), the governor commands SIM grade 0, wind 0 (menus ride free at SIM flat);
##     desired_mode stays "OFF". (W4, SAF-6) For the 30 s switch spacing (4.5) that SIM flat is
##     SIM: leaving ERG for it is a switch, and so is entering ERG from it once the controller
##     has the trainer at SIM (the menus, a session's first ERG phase). A governor whose
##     controller has written nothing yet knows no previous mode, so its first ERG is no switch.
##   - Warm-up (4.6.8) belongs to the trainer connection, not the session: its state is a
##     GovernorWarmup that adopt_connection() carries to the next governor on the same device.
##     (W4) So do the 4.6.1 duration limits (both counters, both latches and the 120 s reset
##     run, SAF-2) and the time of the last ERG/SIM switch (SAF-6): they reset only as 4.6.1
##     and 4.5 say, or with a new trainer connection (another device object).
##   - Stale samples (W4, SAF-7): while the trainer link is up (device status not
##     disconnected, scanning or connecting), a sample stream that stops for more than
##     STALE_SAMPLE_S counts as one not_pedaling sample (0 W, no cadence) at the moment it went
##     stale, so the coasting floor, pause/AFK and the rescue power trigger run as for a rider
##     who stopped. The watchdog counts from setup(device), a reconnect, or the latest sample.
##     It is a stricter governor-only rule layered on the shared detector: its synthetic sample
##     goes through the same predicate, but the GestureRecognizer never sees it, so coast and
##     stop_5s do not follow a dead stream (ADR in docs/decisions/trainer-control.md).
##   - Haptic pull (v0.3.0, BRIEF 4.6.6; ADR in docs/decisions/platform.md): `haptic_pull` % FTP
##     x the haptic intensity, at most +50% FTP (x0.85 while FTP is unverified), on top of the
##     governed ERG target for at most 3 s. The target with the pull never exceeds the absolute
##     ceiling or a latched duration-limit band, and its time above 105% / 120% counts toward
##     the budgets. Exempt from slew (on and off at once, TrainerController) and from the
##     long-phase 105% cap only. ERG only: dropped in SIM, warm-up, rescue (hold and ramp),
##     coasting, AFK, pause, panic, the ramp_test profile and for opted-out riders, and ended
##     at once when any of those begins. The 15 s cooldown is shared with SIM haptics: one
##     haptic per rider per 15 s, counted from the end of the previous one.
##   - Resume (W4r2, NET-2): resume_phase(index, elapsed_s) enters a phase at elapsed_s (a
##     client rejoining a running phase); only the phase clock and the course distance differ
##     from start_phase(), every 4.6 counter keeps its state.

## Any status field changed (at most once per tick).
signal status_changed(status: Dictionary)
signal rescue_changed(active: bool)
signal coasting_changed(active: bool)
## Coasting for 10 s (4.6.4): SOLO pauses, multiplayer marks AFK. `multiplayer` comes from
## configure(). Emitted once when the 10 s pass; cleared when pedaling resumes.
signal pause_requested(reason: String)
signal afk_changed(afk: bool)
## What happened to a directive, course grade or band: {id, kind, requested: {...},
## applied: {...}, clamped_by: [...], refused: bool, reason: String, t: float}.
## W1 adds: dropped: [{channel, reason}], game_t, phase_index. kind is "request" or
## "course_grade".
signal directive_applied(record: Dictionary)
signal warmup_changed(active: bool)
signal panic_changed(active: bool)
## The ramp_test profile's rescue ended the FTP test (BRIEF 3.2): rescue's 50% FTP stands
## until the next set_plan(). Added in W1.
signal ramp_test_ended(reason: String)

const PROFILE_NORMAL := "normal"
const PROFILE_RAMP_TEST := "ramp_test"

## desired_mode while panic holds the trainer at SIM flat.
const MODE_SAFE := "SAFE"

const LIMIT_105_PCT := 105.0
const LIMIT_120_PCT := 120.0
const LIMIT_105_S := 300.0
const LIMIT_120_S := 60.0
const RESET_PCT := 90.0
const RESET_S := 120.0
const LONG_PHASE_S := 300.0
const LONG_PHASE_PCT := 105.0
const RESCUE_ARM_PCT := 60.0
const RESCUE_PCT := 50.0
const RESCUE_CADENCE_LOW_RPM := 45.0
const RESCUE_CADENCE_LOW_S := 3.0
const RESCUE_POWER_FRACTION := 0.75
const RESCUE_POWER_LOW_S := 5.0
const RESCUE_RECOVER_RPM := 70.0
const RESCUE_RECOVER_S := 3.0
const RESCUE_RAMP_S := 10.0
## The shared not_pedaling thresholds (BRIEF 3.5), kept as aliases of GestureRecognizer's:
## the governor compares neither; _take_sample calls GestureRecognizer.is_not_pedaling.
const NOT_PEDALING_W := GestureRecognizer.NOT_PEDALING_W
const NOT_PEDALING_RPM := GestureRecognizer.NOT_PEDALING_RPM
const COAST_FLOOR_S := 3.0
const COAST_AFK_S := 10.0
const WARMUP_S := 300.0
const WARMUP_RESET_S := 1200.0
const WARMUP_ERG_PCT := 65.0
const WARMUP_GRADE_MIN := -2.0
const WARMUP_GRADE_MAX := 3.0
const GRADE_TOTAL_MIN := -10.0
const GRADE_TOTAL_MAX := 16.0
const HAPTIC_MAX_PCT := 3.0
const HAPTIC_MAX_S := 8.0
const HAPTIC_COOLDOWN_S := 15.0
## Haptic pull (4.6.6): at most +50% FTP after the intensity, for at most 3 s.
const PULL_MAX_PCT := 50.0
const PULL_MAX_S := 3.0
## In clamped_by (status, telemetry, the 1 Hz trace) while a haptic pull raises the applied
## ERG target.
const CLAMP_PULL := "haptic_pull"
## Refusal / drop reasons of a haptic pull besides Wl.REFUSE_HAPTIC_OFF, _WARMUP and _COOLDOWN.
const REFUSE_PULL_SIM := "haptic_pull_in_sim"
const REFUSE_PULL_UNSAFE := "haptic_pull_unsafe"
const FACTOR_MIN := 0.5
const FACTOR_MAX := 1.0
const SIM_BLOCK_MIN_S := 10.0
const SIM_BLOCK_MAX_S := 30.0
const SWITCH_SPACING_S := 30.0
const COURSE_GRADE_INTERVAL_S := 0.5
const POWER_WINDOW_S := 3.0
## A trainer sample older than this counts as gone (LocalRider.STALE_S): with the link up, the
## stream stopping counts as a not_pedaling sample (W4, SAF-7).
const STALE_SAMPLE_S := 3.0
## The distance record for resume_phase (W4r2): one entry per game second, six hours at most.
const DISTANCE_HIST_S := 1.0
const DISTANCE_HIST_MAX := 21600
## Speed assumed for the haptic wind bound when the trainer reports none (m/s). A higher
## speed allows less wind, so an unknown speed is the conservative case.
const UNKNOWN_SPEED_MPS := 20.0
const G := 9.80665

const _EPS := 1e-6
const _NEVER := -1e9

const _RESCUE_NONE := 0
const _RESCUE_HOLD := 1
const _RESCUE_RAMP := 2

## Keys configure() accepts.
const CONFIG_KEYS: Array[String] = [
	"ftp_w",
	"ftp_verified",
	"difficulty_pct",
	"grade_min_pct",
	"grade_max_pct",
	"haptics_on",
	"haptic_intensity",
	"skip_warmup",
	"multiplayer",
	"crr",
	"cw",
	"trainer_max_w",
	"profile",
	"weight_kg",
	"system_mass_kg",
]

# --- configuration -------------------------------------------------------------------
var _ftp_w: float = 200.0
var _ftp_verified: bool = false
var _difficulty_pct: float = 50.0
var _grade_min_pct: float = -5.0
var _grade_max_pct: float = 10.0
var _haptics_on: bool = true
var _haptic_intensity: float = 0.7
var _skip_warmup: bool = false
var _multiplayer: bool = false
var _crr: float = 0.004
var _cw: float = 0.51
var _trainer_max_w: float = float(GovernorClamps.KICKR_MAX_W)
var _trainer_max_configured: bool = false
var _profile: String = PROFILE_NORMAL
## Rider weight for target_wkg (BRIEF 4.6.6 conversion).
var _weight_kg: float = 75.0
## Rider plus bike mass for the haptic wind bound.
var _system_mass_kg: float = 83.0

# --- core state ----------------------------------------------------------------------
var _device: TrainerDevice = null
var _controller: TrainerController = null
var _gears: VirtualGears = VirtualGears.new()
var _t: float = 0.0
var _game_t: float = 0.0
var _game_paused: bool = false
var _plan: EffortPlan = null
var _phase_index: int = -1
var _phase: PlanPhase = null
var _phase_elapsed: float = 0.0
var _panic: bool = false
var _shut_down: bool = false
var _desired: String = Wl.OFF
var _last_switch_t: float = _NEVER

# --- samples -------------------------------------------------------------------------
var _pending: Array[TrainerSample] = []
## (platform t, power W) of recent samples, for the 3 s power.
var _power_hist: Array[Vector2] = []
var _speed_mps: float = -1.0
## Platform t of the latest trainer sample, or of the bind or reconnect when none came since
## (-1: no device, the stale-sample watchdog is off), and whether the stream has gone stale
## since then (W4, SAF-7).
var _last_sample_t: float = -1.0
var _stale: bool = false

# --- coasting --------------------------------------------------------------------------
var _np_since: float = -1.0
var _coasting: bool = false
var _afk: bool = false
var _pause_emitted: bool = false

# --- warm-up -----------------------------------------------------------------------------
## The trainer connection's warm-up state (start, done, last pedal stroke) on its own clock;
## adopt_connection() takes it over from the previous governor on the same device (W2r2).
var _wu: GovernorWarmup = GovernorWarmup.new()
var _warmup_active: bool = true

# --- rescue ------------------------------------------------------------------------------
var _rescue_state: int = _RESCUE_NONE
var _cad_low_since: float = -1.0
var _pow_low_since: float = -1.0
var _cad_high_since: float = -1.0
var _rescue_ramp_t: float = 0.0
var _rescue_armed: bool = false
var _rescue_armed_t: float = 0.0
var _test_ended: bool = false

# --- duration limits -----------------------------------------------------------------------
var _above_105_s: float = 0.0
var _above_120_s: float = 0.0
var _latched_105: bool = false
var _latched_120: bool = false
var _reset_run_s: float = 0.0

# --- directive channels (expiry in game time; -1 = until the phase ends) -------------------
var _ch_erg: Dictionary = {}
var _ch_block: Dictionary = {}
var _ch_mode_grade: Dictionary = {}
var _ch_haptic: Dictionary = {}
var _ch_factors: Dictionary = {}
## The haptic pull: {pct, id, expires (game t), end_t (platform t), duration_limited}.
var _ch_pull: Dictionary = {}
## End of the rider's previous haptic or haptic pull (the shared 15 s cooldown).
var _haptic_last_end_t: float = _NEVER

# --- course grade ----------------------------------------------------------------------------
var _course_source: float = 0.0
var _course_source_set: bool = false
var _course_applied: float = 0.0
var _course_applied_t: float = _NEVER
var _distance_m: float = -1.0
var _distance_origin: float = -1.0
## Metres of the current phase ridden before this governor entered it (resume_phase, W4r2):
## a "course" phase follows its profile from _distance_offset + the distance since the entry.
var _distance_offset: float = 0.0
## (game t, distance) about once per game second, so resume_phase can tell how far the rider
## rode since a phase began on the host (W4r2, NET-2). Bounded to DISTANCE_HIST_MAX entries.
var _distance_hist: PackedVector2Array = PackedVector2Array()

# --- outputs ---------------------------------------------------------------------------------
var _erg_out: Dictionary = {}
var _sim_out: Dictionary = {}
var _clamped_by: Array[String] = []
var _status: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_controller = TrainerController.new()
	_controller.name = "TrainerController"
	add_child(_controller)
	_erg_out = _empty_erg()
	_sim_out = _empty_sim()
	_update_status()


# =============================================================================================
# Public API (frozen W0 signatures)
# =============================================================================================


## Bind the device (the governor creates and owns its TrainerController around it).
## Calling it again (a reconnect with a new device object, LocalRider.rebind_device) rebinds
## the controller to that device; plan, phase, configuration and rider state (warm-up,
## limits, rescue, coasting, gears, channels) are kept, and the next command re-enters its
## mode through the ramped entry. A shut-down governor comes back to life here. The same
## device reconnecting uses on_trainer_reconnected() instead.
func setup(device: TrainerDevice) -> void:
	_device = device
	_controller.setup(device)
	_shut_down = false
	# The 3 s power and speed of a previous connection are stale: the next ERG entry starts
	# from the floor until fresh samples arrive.
	_power_hist.clear()
	_pending.clear()
	_speed_mps = -1.0
	# The stale-sample watchdog (SAF-7) counts from the bind: a bound trainer is expected to
	# notify about once per second.
	_last_sample_t = _t if device != null else -1.0
	_stale = false
	if _panic:
		# A trainer that connects during panic goes straight to SIM flat.
		_controller.emergency_safe(_crr, _cw)
	if device != null and not _trainer_max_configured:
		_trainer_max_w = _device_max_w(device)
	_update_status()


## Rider and safety parameters. Keys (all optional, defaults from BRIEF 3.2/4.6):
##   ftp_w (200), ftp_verified (false), difficulty_pct (50), grade_min_pct (-5),
##   grade_max_pct (10), haptics_on (true), haptic_intensity (0.7, 0..1),
##   skip_warmup (false), multiplayer (false: coasting pauses; true: marks AFK),
##   crr (0.004), cw (0.51), trainer_max_w (from the device's power range),
##   profile ("normal" or "ramp_test", BRIEF 3.2).
## W1 adds: weight_kg (75, for target_wkg), system_mass_kg (83, rider + bike for the haptic
## wind bound). Out-of-range values are clamped with push_warning; an unknown profile or an
## FTP outside 30-2000 W (GovernorClamps.FTP_MIN_W..FTP_MAX_W, the range Settings allows;
## W4) is a push_error. An FTP above the range (or NaN) is rejected and the previous value
## stays; one below it (zero, negative) gives 30 W (W4r2), so an invalid FTP never sets a
## higher watt basis than the rider's lowest possible one.
## Calling it again (LocalRider.configure_governor, the FTP test) replaces only the given
## parameters: the plan, the phase and its elapsed time, warm-up, duration limits, rescue,
## coasting and the directive channels are kept, and the next tick applies the new values.
func configure(params: Dictionary) -> void:
	for key: Variant in params.keys():
		if not CONFIG_KEYS.has(str(key)):
			push_warning('SafetyGovernor: unknown configure key "%s" ignored' % str(key))
	if params.has("ftp_w"):
		var f := float(params["ftp_w"])
		if GovernorClamps.ftp_in_range(f):
			_ftp_w = f
		elif f < GovernorClamps.FTP_MIN_W:
			# W4r2 (SAF-1 range): below the range (zero, negative, -inf) the rider gets the lowest
			# basis there is, never the previous or default one (200 W for a 25 W rider).
			push_error(
				(
					"SafetyGovernor: ftp_w must be within %d-%d W (got %s); using %d W"
					% [
						int(GovernorClamps.FTP_MIN_W),
						int(GovernorClamps.FTP_MAX_W),
						str(params["ftp_w"]),
						int(GovernorClamps.FTP_MIN_W)
					]
				)
			)
			_ftp_w = GovernorClamps.FTP_MIN_W
		else:
			push_error(
				(
					"SafetyGovernor: ftp_w must be within %d-%d W (got %s); keeping %s W"
					% [
						int(GovernorClamps.FTP_MIN_W),
						int(GovernorClamps.FTP_MAX_W),
						str(params["ftp_w"]),
						str(_ftp_w)
					]
				)
			)
	if params.has("ftp_verified"):
		_ftp_verified = bool(params["ftp_verified"])
	if params.has("difficulty_pct"):
		_difficulty_pct = _clamped_param(
			"difficulty_pct", float(params["difficulty_pct"]), 0.0, 100.0
		)
	if params.has("grade_min_pct"):
		_grade_min_pct = _clamped_param(
			"grade_min_pct", float(params["grade_min_pct"]), GRADE_TOTAL_MIN, GRADE_TOTAL_MAX
		)
	if params.has("grade_max_pct"):
		_grade_max_pct = _clamped_param(
			"grade_max_pct", float(params["grade_max_pct"]), GRADE_TOTAL_MIN, GRADE_TOTAL_MAX
		)
	if _grade_min_pct > _grade_max_pct:
		push_warning("SafetyGovernor: grade_min_pct > grade_max_pct, swapped")
		var tmp := _grade_min_pct
		_grade_min_pct = _grade_max_pct
		_grade_max_pct = tmp
	if params.has("haptics_on"):
		_haptics_on = bool(params["haptics_on"])
		if not _haptics_on:
			# Opting out ends a running haptic at once (4.6.6: haptics are off for opted-out riders).
			_end_haptic()
			_end_pull()
	if params.has("haptic_intensity"):
		_haptic_intensity = _clamped_param(
			"haptic_intensity", float(params["haptic_intensity"]), 0.0, 1.0
		)
	if params.has("skip_warmup"):
		_skip_warmup = bool(params["skip_warmup"])
	if params.has("multiplayer"):
		_multiplayer = bool(params["multiplayer"])
	if params.has("crr"):
		_crr = _clamped_param("crr", float(params["crr"]), 0.0, 0.0255)
	if params.has("cw"):
		_cw = _clamped_param("cw", float(params["cw"]), 0.0, 2.55)
	if params.has("trainer_max_w"):
		var m := float(params["trainer_max_w"])
		if m > 0.0 and is_finite(m):
			_trainer_max_w = m
			_trainer_max_configured = true
		else:
			_trainer_max_configured = false
			_trainer_max_w = _device_max_w(_device)
	if params.has("profile"):
		var p := str(params["profile"])
		if p == PROFILE_NORMAL or p == PROFILE_RAMP_TEST:
			if p != _profile:
				_test_ended = false
			_profile = p
			if p == PROFILE_RAMP_TEST:
				_end_pull()
		else:
			push_error('SafetyGovernor: unknown profile "%s" (normal or ramp_test)' % p)
	if params.has("weight_kg"):
		_weight_kg = _clamped_param("weight_kg", float(params["weight_kg"]), 20.0, 250.0)
	if params.has("system_mass_kg"):
		_system_mass_kg = _clamped_param(
			"system_mass_kg", float(params["system_mass_kg"]), 20.0, 300.0
		)
	if _skip_warmup and _warmup_active:
		_warmup_active = false
		warmup_changed.emit(false)
	_recompute_outputs()
	_update_status()


## The rider's validated plan (cool-down appended). Resets channel state.
## The current phase index is kept when it exists in the new plan (a replan between phases);
## otherwise the governor waits for start_phase().
func set_plan(plan: EffortPlan) -> void:
	if plan == null:
		push_error("SafetyGovernor: set_plan(null)")
		return
	_plan = plan
	_clear_channels()
	_test_ended = false
	if _phase_index >= 0 and _phase_index < plan.size():
		_phase = plan.phase(_phase_index)
	else:
		_phase_index = -1
		_phase = null
	_update_desired()
	_recompute_outputs()
	_update_status()


## Enter phase `index` (elapsed 0). The platform calls it on every phase change (duration,
## max_s, end_phase, finished, rejoin). Directive channels revert to the plan; the
## cool-down clears every directive.
func start_phase(index: int) -> void:
	if not _phase_index_ok(index, "start_phase(%d)" % index):
		return
	_enter_phase(index, 0.0, 0.0)


## Re-enter phase `index` `elapsed_s` game seconds after it began (W4r2, NET-2, additive): a
## client that rejoins a running phase, for example after the app restarted (GameHost on a
## `phase` message with elapsed_s). As start_phase(index) (directive channels revert to the
## plan, a "game" course grade waits for the game's next one, a SIM phase ends rescue), except:
##   - the phase clock starts at elapsed_s, so a ramp continues at the host's point of it;
##   - a "course" phase follows its profile from the distance already ridden in the phase:
##     `phase_distance_m` when the caller knows it (>= 0), else this governor's own record of
##     the distance since game time (now - elapsed_s) (the same governor across a socket
##     rejoin), else 0 (a new governor knows nothing older; LocalRider.resume_phase estimates
##     it first). See distance_ridden_since().
## Nothing 4.6 counts changes: the warm-up stays the trainer connection's (the skipped
## elapsed time never counts toward its 300 s), the 105% / 120% times, their latches and the
## 120 s reset run, the 30 s switch spacing, the haptic cooldown, coasting, rescue arming and
## panic all keep their state, and the long-phase cap and every ceiling apply as for any phase.
## elapsed_s must be finite and >= 0 (push_error otherwise; nothing changes); 0 is
## start_phase(index).
func resume_phase(index: int, elapsed_s: float, phase_distance_m: float = -1.0) -> void:
	if not is_finite(elapsed_s) or elapsed_s < 0.0:
		push_error(
			(
				"SafetyGovernor: resume_phase(%d) needs a finite elapsed_s >= 0 (got %s)"
				% [index, str(elapsed_s)]
			)
		)
		return
	if not _phase_index_ok(index, "resume_phase(%d)" % index):
		return
	var ridden := phase_distance_m
	if not is_finite(ridden) or ridden < 0.0:
		ridden = maxf(distance_ridden_since(_game_t - elapsed_s), 0.0)
	_enter_phase(index, elapsed_s, ridden)


## Metres ridden since game time `game_t` from this governor's own distance record
## (set_course_distance, about one entry per game second), or -1 when the record doesn't reach
## back that far (a new governor, more than DISTANCE_HIST_MAX seconds ago) or no distance came
## yet. Added in W4r2 for resume_phase.
func distance_ridden_since(game_t: float) -> float:
	if _distance_m < 0.0 or _distance_hist.is_empty() or not is_finite(game_t):
		return -1.0
	var first := _distance_hist[0]
	if game_t < float(first.x) - _EPS:
		return -1.0
	var lo := 0
	var hi := _distance_hist.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if float(_distance_hist[mid].x) <= game_t + _EPS:
			lo = mid
		else:
			hi = mid - 1
	var a := _distance_hist[lo]
	# After the last entry, interpolate toward now (the latest distance at the current game time).
	var b := (
		_distance_hist[lo + 1] if lo + 1 < _distance_hist.size() else Vector2(_game_t, _distance_m)
	)
	var at := float(a.y)
	var span := float(b.x) - float(a.x)
	if span > _EPS:
		at = lerpf(float(a.y), float(b.y), clampf((game_t - float(a.x)) / span, 0.0, 1.0))
	return maxf(_distance_m - at, 0.0)


## Metres of the current phase ridden so far, as its course profile is followed (0 without a
## phase or a distance). Added in W4r2 (diagnostics and tests).
func phase_distance_m() -> float:
	if _phase == null:
		return 0.0
	var d := _distance_offset
	if _distance_m >= 0.0 and _distance_origin >= 0.0:
		d += _distance_m - _distance_origin
	return d


## Pause (4.1): the game clock stops; the trainer goes to the ERG floor or SIM flat;
## telemetry, rescue, coasting and panic keep working.
func set_game_paused(paused: bool) -> void:
	_game_paused = paused
	if paused:
		_end_pull()
	_recompute_outputs()
	_update_status()


## Validate and clamp a directive for this rider; returns the applied record (also
## emitted as directive_applied). Refuses (record.refused = true, push_warning) anything
## BRIEF 3.6 disallows: outside range_pct, SIM block length or spacing, mode_grade outside
## SIM, haptics in ERG / warm-up / opted out / in cooldown, during the cool-down.
func apply_directive(directive: EffortDirective) -> Dictionary:
	var requested: Dictionary = {}
	var id := 0
	if directive != null:
		requested = directive.to_dict()
		id = directive.id
	var rec := _new_record("request", requested, id)
	if directive == null:
		return _refuse(rec, Wl.REFUSE_BAD_FIELDS, "null directive")
	if _plan == null or _phase == null:
		return _refuse(rec, Wl.REFUSE_NO_PHASE, "no active phase")
	if _is_cooldown_phase():
		return _refuse(rec, Wl.REFUSE_COOLDOWN, "the cool-down ignores directives")
	var bad := _bad_fields(directive)
	if bad != "":
		return _refuse(rec, Wl.REFUSE_BAD_FIELDS, bad)

	var phase_sim := _phase.mode == Wl.SIM
	var block_active := not _ch_block.is_empty()
	var sets_target := directive.sets_erg_target()
	var sets_haptic := directive.sets_haptic()
	var sets_mode_grade := directive.is_set("mode_grade")
	var sets_factors := directive.sets_factors()
	var sets_pull := directive.is_set("haptic_pull")
	var opens_block := false
	var ends_block := false
	var confirm_sim := false
	var confirm_erg := false
	var target_pct := NAN

	if phase_sim:
		if directive.mode == Wl.ERG:
			return _refuse(rec, Wl.REFUSE_ERG_IN_SIM, "mode ERG in a SIM phase")
		if sets_target:
			return _refuse(rec, Wl.REFUSE_ERG_IN_SIM, "ERG target in a SIM phase")
		confirm_sim = directive.mode == Wl.SIM
	else:
		if sets_haptic and not block_active:
			return _refuse(
				rec, Wl.REFUSE_HAPTIC_ERG, "haptic for a rider in ERG (never a mode switch)"
			)
		if sets_target:
			target_pct = _target_pct_of(directive)
			var rng := _phase.effective_range()
			var lo := float(rng[0])
			var hi := float(rng[1])
			if target_pct < lo - _EPS or target_pct > hi + _EPS:
				return _refuse(
					rec, Wl.REFUSE_RANGE, "%.3f%% FTP outside [%.3f, %.3f]" % [target_pct, lo, hi]
				)
		if directive.mode == Wl.SIM:
			if block_active:
				confirm_sim = true
			else:
				var d := directive.duration_s
				if d < SIM_BLOCK_MIN_S - _EPS or d > SIM_BLOCK_MAX_S + _EPS:
					return _refuse(
						rec,
						Wl.REFUSE_SIM_BLOCK_LENGTH,
						"SIM block duration_s %.2f outside [10, 30]" % d
					)
				var unsafe := _unsafe_reason()
				if unsafe != "":
					return _refuse(rec, Wl.REFUSE_SIM_BLOCK_UNSAFE, "SIM block during %s" % unsafe)
				if _t - _last_switch_t < SWITCH_SPACING_S - _EPS:
					return _refuse(
						rec,
						Wl.REFUSE_SWITCH_SPACING,
						"%.2f s since the last ERG/SIM switch (< 30 s)" % (_t - _last_switch_t)
					)
				opens_block = true
		elif directive.mode == Wl.ERG:
			ends_block = block_active
			confirm_erg = not block_active
		if sets_mode_grade and not (block_active or opens_block):
			return _refuse(rec, Wl.REFUSE_MODE_GRADE, "mode_grade outside a SIM phase or SIM block")

	var haptic_drop := ""
	if sets_haptic:
		if not _haptics_on:
			haptic_drop = Wl.REFUSE_HAPTIC_OFF
		elif _warmup_active:
			haptic_drop = Wl.REFUSE_HAPTIC_WARMUP
		elif _haptic_cooling():
			haptic_drop = Wl.REFUSE_HAPTIC_COOLDOWN
	var pull_drop := ""
	if sets_pull:
		pull_drop = _pull_drop_reason(phase_sim or block_active or opens_block or ends_block)
	var other := sets_target or sets_mode_grade or sets_factors or opens_block or ends_block
	var haptic_ok := sets_haptic and haptic_drop == ""
	var pull_ok := sets_pull and pull_drop == ""
	if not other and not haptic_ok and not pull_ok:
		if haptic_drop != "":
			return _refuse(rec, haptic_drop, "haptic dropped")
		if pull_drop != "":
			return _refuse(rec, pull_drop, "haptic pull dropped")

	# --- accepted: write the channels ------------------------------------------------
	var clamped: Array[String] = []
	var applied: Dictionary = {}
	var expiry := _expiry_for(directive.duration_s)
	if sets_target:
		_ch_erg = {"pct": target_pct, "id": directive.id, "expires": expiry}
	if opens_block:
		var block_s := snappedf(directive.duration_s, Wl.SIM_DT)
		_ch_block = {
			"id": directive.id, "expires": _game_t + block_s, "start_t": _t, "duration_s": block_s
		}
		applied["sim_block"] = true
		applied["duration_s"] = block_s
	if ends_block:
		_end_block()
		applied["sim_block"] = false
	if confirm_sim:
		applied["mode"] = Wl.SIM
	if confirm_erg:
		applied["mode"] = Wl.ERG
	if sets_mode_grade:
		_ch_mode_grade = {"grade": directive.mode_grade, "id": directive.id, "expires": expiry}
		applied["mode_grade"] = directive.mode_grade
	var haptic_applied := false
	if sets_haptic:
		if haptic_drop != "":
			(rec["dropped"] as Array).append({"channel": "haptic", "reason": haptic_drop})
			push_warning(
				"SafetyGovernor: haptic of directive %d dropped: %s" % [directive.id, haptic_drop]
			)
		else:
			haptic_applied = true
			var hap_s := directive.duration_s
			var limited := false
			if hap_s <= 0.0 or hap_s > HAPTIC_MAX_S + _EPS:
				hap_s = HAPTIC_MAX_S
				limited = true
			hap_s = snappedf(hap_s, Wl.SIM_DT)
			_ch_haptic = {
				"grade": directive.haptic if directive.is_set("haptic") else 0.0,
				"wind": directive.haptic_wind if directive.is_set("haptic_wind") else 0.0,
				"id": directive.id,
				"expires": _game_t + hap_s,
				"end_t": _t + HAPTIC_MAX_S,
				"duration_limited": limited,
			}
			applied["haptic_s"] = hap_s
	var pull_limited := false
	if sets_pull:
		if pull_drop != "":
			(rec["dropped"] as Array).append({"channel": "haptic_pull", "reason": pull_drop})
			push_warning(
				(
					"SafetyGovernor: haptic pull of directive %d dropped: %s"
					% [directive.id, pull_drop]
				)
			)
		else:
			var pull_s := directive.duration_s
			if pull_s <= 0.0 or pull_s > PULL_MAX_S + _EPS:
				pull_s = PULL_MAX_S
				pull_limited = true
			pull_s = snappedf(pull_s, Wl.SIM_DT)
			_ch_pull = {
				"pct": directive.haptic_pull,
				"id": directive.id,
				"expires": _game_t + pull_s,
				"end_t": _t + pull_s,
				"duration_limited": pull_limited,
			}
			applied["haptic_pull_s"] = pull_s
	if sets_factors:
		var crr_f := directive.crr if directive.is_set("crr") else 1.0
		var cw_f := directive.cw if directive.is_set("cw") else 1.0
		var fc := clampf(crr_f, FACTOR_MIN, FACTOR_MAX)
		var fw := clampf(cw_f, FACTOR_MIN, FACTOR_MAX)
		var factor_clamped := not is_equal_approx(fc, crr_f) or not is_equal_approx(fw, cw_f)
		_ch_factors = {
			"crr": fc, "cw": fw, "id": directive.id, "expires": expiry, "clamped": factor_clamped
		}
		applied["crr_factor"] = fc
		applied["cw_factor"] = fw
		if factor_clamped:
			clamped.append(Wl.CLAMP_FACTOR)

	_update_desired()
	_recompute_outputs()

	if sets_target:
		var e := _compute_erg()
		applied["target_pct"] = target_pct
		applied["target_w"] = int(e["w"])
		for c: String in e["clamped_by"]:
			_append_unique(clamped, c)
		if (
			_desired == Wl.ERG
			and _controller.mode() == Wl.ERG
			and _controller.applied_base_w() < int(e["w"])
		):
			if _controller.entry_active():
				_append_unique(clamped, Wl.CLAMP_SWITCH)
			_append_unique(clamped, Wl.CLAMP_SLEW)
		if _panic:
			_append_unique(clamped, Wl.CLAMP_PANIC)
	if pull_ok:
		var ep := _compute_erg()
		var pull_w := int(ep["pull_w"])
		applied["haptic_pull_w"] = pull_w
		applied["haptic_pull_pct"] = GovernorClamps.w_to_pct(float(pull_w), _ftp_w)
		applied["target_with_pull_w"] = int(ep["w"]) + pull_w
		for c: String in ep["pull_clamped_by"]:
			_append_unique(clamped, c)
		if pull_limited:
			_append_unique(clamped, Wl.CLAMP_HAPTIC)
	var sim_channels := (
		opens_block or confirm_sim or sets_mode_grade or haptic_applied or sets_factors
	)
	if sim_channels and (_desired == Wl.SIM or _desired == MODE_SAFE):
		var s := _compute_sim()
		applied["grade_pct"] = float(s["grade_pct"])
		if haptic_applied:
			applied["haptic_pct"] = float(s["haptic_pct"])
			applied["haptic_wind_mps"] = float(s["wind_mps"])
			if bool(_ch_haptic.get("duration_limited", false)):
				_append_unique(clamped, Wl.CLAMP_HAPTIC)
		for c: String in s["clamped_by"]:
			if c == Wl.CLAMP_FACTOR and not sets_factors:
				continue
			_append_unique(clamped, c)
	rec["applied"] = applied
	rec["clamped_by"] = clamped
	_update_clamped_by()
	_update_status()
	directive_applied.emit(rec)
	return rec


## Course grade for grade_source "game" phases (coalesced by the controller).
## Coalesced to 2 Hz (the newest value wins) and stacked by 4.6.6; holds until the next call
## or the phase end. Outside a "game" phase it is refused (grade_source_not_game). Every call
## is reported through directive_applied (kind "course_grade").
func set_course_grade(grade_pct: float) -> void:
	var rec := _new_record("course_grade", {"grade_pct": grade_pct}, 0)
	if not is_finite(grade_pct):
		_refuse(rec, Wl.REFUSE_BAD_FIELDS, "grade_pct is not finite")
		return
	if _plan == null or _phase == null:
		_refuse(rec, Wl.REFUSE_NO_PHASE, "no active phase")
		return
	if _is_cooldown_phase():
		_refuse(rec, Wl.REFUSE_COOLDOWN, "the cool-down ignores directives")
		return
	if _phase.mode != Wl.SIM or _phase.grade_source != Wl.GRADE_GAME:
		_refuse(rec, Wl.REFUSE_NOT_GAME_GRADE, 'course_grade outside a grade_source "game" phase')
		return
	_course_source = grade_pct
	_course_source_set = true
	rec["applied"] = {"course_grade_pct": grade_pct}
	directive_applied.emit(rec)


## The rider's distance from the speed model, for grade_source "course" phases.
## The phase's course_profile is followed by the distance ridden since the phase started
## (linear between points; the last grade holds after the last point).
func set_course_distance(distance_m: float) -> void:
	if not is_finite(distance_m):
		return
	_distance_m = distance_m
	if _distance_origin < 0.0:
		_distance_origin = distance_m
	var n := _distance_hist.size()
	if n == 0 or _game_t - float(_distance_hist[n - 1].x) >= DISTANCE_HIST_S - _EPS:
		_distance_hist.append(Vector2(_game_t, distance_m))
		if n + 1 > DISTANCE_HIST_MAX + 600:
			_distance_hist = _distance_hist.slice(n + 1 - DISTANCE_HIST_MAX)


## Virtual gears (4.5): +1 / -1 steps within 1..24. Returns the new gear.
## Shifts count only while the rider rides SIM (a SIM phase or a SIM block); otherwise the
## gear stays and is returned unchanged.
func shift(delta: int) -> int:
	if _desired == Wl.SIM or (_phase != null and _phase.mode == Wl.SIM):
		_gears.shift(delta)
		_recompute_outputs()
		_update_status()
	return _gears.gear


## Feed a trainer sample (power, cadence, speed): rescue, coasting, warm-up, 3 s power.
## The sample takes effect on the next tick() (see the class notes).
func on_sample(sample: TrainerSample) -> void:
	if sample == null:
		return
	_pending.append(sample)


## Advance every time-based rule by dt platform seconds and command the controller.
func tick(dt: float) -> void:
	if dt <= 0.0 or _shut_down:
		return
	_t += dt
	_wu.t += dt
	if not _game_paused:
		_game_t += dt
		if _phase != null:
			_phase_elapsed += dt
	_process_samples()
	_check_stale_samples()
	_update_coasting()
	_update_warmup()
	_expire_channels()
	_update_course_grade()
	_update_desired()
	if _desired == Wl.ERG:
		_erg_out = _compute_erg()
	_update_rescue()
	if not _ch_pull.is_empty() and _pull_drop_reason(_desired != Wl.ERG, false) != "":
		_end_pull()
	_recompute_outputs()
	_command_controller()
	_controller.tick(dt)
	_update_duration_limits(dt)
	_update_clamped_by()
	var before := _status
	_update_status()
	if not _status_equal(before, _status):
		status_changed.emit(_status.duplicate(true))


## Panic (4.6.5): ERG off, SIM grade 0 and wind 0 immediately; stays safe until resume().
func emergency_safe() -> void:
	if _shut_down:
		return
	if not _panic:
		_panic = true
		panic_changed.emit(true)
	_end_haptic()
	_end_pull()
	_controller.emergency_safe(_crr, _cw)
	_update_desired()
	_recompute_outputs()
	_update_clamped_by()
	_update_status()


## Leave the panic state (the player resumed). The plan resumes from the floor with slew.
func resume() -> void:
	if not _panic:
		return
	_panic = false
	panic_changed.emit(false)
	_controller.release_safe()
	_update_desired()
	_recompute_outputs()
	_update_clamped_by()
	_update_status()


## Exit, crash and disconnect paths (4.6.9): try SIM flat, then Stop (0x08 0x01).
func shutdown() -> void:
	_controller.shutdown(_crr, _cw)
	_shut_down = true
	_end_haptic()
	_end_pull()
	_update_status()


func status() -> Dictionary:
	return _status.duplicate(true)


## The trainer reconnected on the same device object (FtmsConnectionManager.reconnected; a
## new object goes through setup(device) instead). Added in W2 (BRIEF 4.4 "restore the last
## safe mode"). The connection flow left the trainer at SIM flat, so the controller forgets
## what it last wrote (TrainerController.resync) and the current mode and target come back
## through the normal ramped path on the next ticks: ERG through the SIM -> ERG entry and
## 30 W/s slew (4.5, 4.6.2), SIM by writing the stacked state, within the 2 writes per
## second. The 3 s power from before the outage is dropped (the rider's power is unknown), so
## an ERG re-entry starts at the floor until fresh samples arrive. Plan, phase, warm-up,
## duration limits, rescue, coasting, gears and directive channels are kept; the reconnect is
## no ERG/SIM switch for the 30 s spacing. Panic re-sends SIM flat at once; after shutdown()
## nothing is sent (setup() is the way back).
func on_trainer_reconnected() -> void:
	if _shut_down or _device == null:
		return
	_power_hist.clear()
	_speed_mps = -1.0
	_last_sample_t = _t
	_stale = false
	_controller.resync(_crr, _cw)
	_recompute_outputs()
	_update_clamped_by()
	_update_status()


## Take over from `previous`, the governor this one replaces on the same device object, what
## belongs to the trainer connection rather than to a session. Added in W2r2: LocalRider.setup()
## builds a new governor for every session (and for the menus after it) around the same
## device and calls this between setup(device) and configure().
##   - The warm-up state (BRIEF 4.6.8: counted from the first pedal stroke after the trainer
##     connects, reset after 20 minutes without pedaling), so a warm-up begun in the menus
##     continues into the session and back-to-back sessions share one. skip_warmup still
##     applies through configure().
##   - What the controller last wrote to the trainer and its write-slot timing
##     (TrainerController.adopt), so the next mode change is ramped from the trainer's real
##     state (4.5: from ERG the step-down first) and the 2 writes per second hold across the
##     hand-over.
##   - The rider's recent samples behind the 3 s power, and the latest speed: the same rider on
##     the same trainer, so the 4.5 step-down and SIM -> ERG entry use the rider's real power.
##   - (W4, SAF-2) The 4.6.1 duration limits: time above 105% and above 120% FTP, both latches
##     and the run of ERG at <= 90% FTP toward the 120 s reset. BRIEF 4.6.1 releases a latch
##     only after 120 consecutive seconds of ERG at <= 90% FTP; ending a session or setting the
##     rider up again is no such release.
##   - (W4, SAF-6) The time of the last ERG/SIM switch, so the 4.5 30 s spacing counts from
##     the rider's previous switch at the trainer, also when it happened under `previous`.
##   - (W4, SAF-7) When the latest trainer sample arrived (the stale-sample watchdog).
## Plan, phase, directive channels, rescue, coasting, gears and panic stay this governor's
## own. Does nothing with null, itself or a freed governor, or unless both are bound to the
## same device object (a new device is a new connection).
func adopt_connection(previous: SafetyGovernor) -> void:
	if previous == null or previous == self or not is_instance_valid(previous):
		return
	if _device == null or previous._device != _device:
		return
	_wu = previous._wu.copy()
	_controller.adopt(previous._controller)
	_power_hist.clear()
	for e: Vector2 in previous._power_hist:
		_power_hist.append(Vector2(e.x - previous._t + _t, e.y))
	_speed_mps = previous._speed_mps
	_above_105_s = previous._above_105_s
	_above_120_s = previous._above_120_s
	_latched_105 = previous._latched_105
	_latched_120 = previous._latched_120
	_reset_run_s = previous._reset_run_s
	if previous._last_switch_t > _NEVER * 0.5:
		_last_switch_t = maxf(_last_switch_t, previous._last_switch_t - previous._t + _t)
	if previous._last_sample_t >= 0.0:
		_last_sample_t = previous._last_sample_t - previous._t + _t
		_stale = previous._stale
	_update_warmup()
	_recompute_outputs()
	_update_clamped_by()
	_update_status()


## Drop the plan and the phase (W2r2): the session is over before the rider is set up again,
## for example while its ride still waits to be saved. From the next tick the governor rides
## free at SIM grade 0, wind 0, as with no plan; every directive channel is cleared and a
## rescue ends. Warm-up, duration limits, gears and panic are kept. Leaving ERG for that SIM
## flat counts as an ERG -> SIM switch for the 30 s spacing (W4, SAF-6).
func clear_plan() -> void:
	_plan = null
	_phase = null
	_phase_index = -1
	_phase_elapsed = 0.0
	_clear_channels()
	_test_ended = false
	_course_source = 0.0
	_course_source_set = false
	_course_applied = 0.0
	_course_applied_t = _NEVER
	_distance_offset = 0.0
	_update_desired()
	if _rescue_state != _RESCUE_NONE:
		_end_rescue(false)
	_recompute_outputs()
	_update_clamped_by()
	_update_status()


## The trainer connection's warm-up state (W2r2, diagnostics and tests): {t (its clock),
## started_t, done, last_pedal_t}; see GovernorWarmup.
func warmup_state() -> Dictionary:
	return _wu.to_dict()


func is_rescue() -> bool:
	return _rescue_state == _RESCUE_HOLD


func is_coasting() -> bool:
	return _coasting


func is_warmup_active() -> bool:
	return _warmup_active


# --- additive helpers (W1) ---------------------------------------------------------------


## True after the 10 s coasting rule marked a multiplayer rider AFK (until pedaling resumes).
func is_afk() -> bool:
	return _afk


func is_panic() -> bool:
	return _panic


func gear() -> int:
	return _gears.gear


## The rider's mean power over the last 3 s of platform time (each sample held until the next).
func power_3s_w() -> float:
	return _power_mean(POWER_WINDOW_S)


## Platform seconds this governor has ticked.
func platform_time_s() -> float:
	return _t


## Game seconds (stops while paused).
func game_time_s() -> float:
	return _game_t


## Grade in % at `distance_m` along a course profile [[distance_m, grade_pct], ...]:
## linear between points, the first grade before the first point, the last after the last.
static func profile_grade(profile: Array, distance_m: float) -> float:
	if profile.is_empty():
		return 0.0
	var first: Array = profile[0]
	if distance_m <= float(first[0]):
		return float(first[1])
	for i in range(1, profile.size()):
		var a: Array = profile[i - 1]
		var b: Array = profile[i]
		var da := float(a[0])
		var db := float(b[0])
		if distance_m <= db:
			if db - da <= 1e-9:
				return float(b[1])
			return lerpf(float(a[1]), float(b[1]), (distance_m - da) / (db - da))
	var last: Array = profile[profile.size() - 1]
	return float(last[1])


# =============================================================================================
# Rules
# =============================================================================================


func _process_samples() -> void:
	if _pending.is_empty():
		return
	var batch := _pending
	_pending = []
	for s in batch:
		_last_sample_t = _t
		_stale = false
		_take_sample(_t, s.power_w, s.has_cadence(), s.cadence_rpm)
		if s.has_speed():
			_speed_mps = s.speed_kmh / 3.6
	_trim_power_hist()


## One sample's effect on the 3 s power, coasting, warm-up and rescue timers, at platform time
## `at` (a real sample: the tick it arrived in; the stale-sample watchdog: when it went stale).
func _take_sample(at: float, power_w: float, has_cad: bool, cadence_rpm: float) -> void:
	_power_hist.append(Vector2(at, power_w))
	# The one shared not_pedaling detector (BRIEF 3.5); an absent cadence goes in as -1 (low).
	var np_cadence := cadence_rpm if has_cad else -1.0
	var not_pedaling := GestureRecognizer.is_not_pedaling(power_w, np_cadence)
	if not_pedaling:
		if _np_since < 0.0:
			_np_since = at
	else:
		_np_since = -1.0
		_wu.pedal()
	if has_cad:
		if cadence_rpm < RESCUE_CADENCE_LOW_RPM:
			if _cad_low_since < 0.0:
				_cad_low_since = at
		else:
			_cad_low_since = -1.0
		if cadence_rpm >= RESCUE_RECOVER_RPM:
			if _cad_high_since < 0.0:
				_cad_high_since = at
		else:
			_cad_high_since = -1.0
	var written := _controller.written_target_w()
	if written > 0 and power_w < RESCUE_POWER_FRACTION * float(written):
		if _pow_low_since < 0.0:
			_pow_low_since = at
	else:
		_pow_low_since = -1.0


## Keep the samples inside the 3 s window plus the one before it.
func _trim_power_hist() -> void:
	while _power_hist.size() > 2 and _power_hist[1].x <= _t - POWER_WINDOW_S:
		_power_hist.remove_at(0)


## The stale-sample watchdog (W4, SAF-7; ADR in docs/decisions/trainer-control.md). While the
## trainer link is up, no sample for more than STALE_SAMPLE_S counts as one not_pedaling sample
## (0 W, no cadence) at the moment the stream went stale: LocalRider already shows such a rider
## at 0 W, and the coasting floor, pause/AFK and the rescue power trigger now see the same.
## Once per stale stretch; the next real sample ends it.
func _check_stale_samples() -> void:
	if _stale or _last_sample_t < 0.0 or not _link_up():
		return
	if _t - _last_sample_t <= STALE_SAMPLE_S + _EPS:
		return
	_stale = true
	_cad_high_since = -1.0
	_take_sample(_last_sample_t + STALE_SAMPLE_S, 0.0, false, 0.0)
	_trim_power_hist()


## True while the device reports a link (connected, ready, control lost or error): only then
## is a silent sample stream a stopped rider rather than a dropped link (the reconnect flow
## handles that).
func _link_up() -> bool:
	if _device == null or not is_instance_valid(_device):
		return false
	var st := _device.status()
	return (
		st != TrainerDevice.STATUS_DISCONNECTED
		and st != TrainerDevice.STATUS_SCANNING
		and st != TrainerDevice.STATUS_CONNECTING
	)


func _power_mean(window_s: float) -> float:
	if _power_hist.is_empty():
		return 0.0
	var start := _t - window_s
	var area := 0.0
	var covered := 0.0
	var n := _power_hist.size()
	for i in n:
		var p := _power_hist[i]
		var seg_start := maxf(p.x, start)
		var seg_end := _t if i == n - 1 else _power_hist[i + 1].x
		if seg_end <= seg_start:
			continue
		area += p.y * (seg_end - seg_start)
		covered += seg_end - seg_start
	if covered <= _EPS:
		return _power_hist[n - 1].y
	return area / covered


func _update_coasting() -> void:
	if _np_since >= 0.0:
		var elapsed := _t - _np_since
		if not _coasting and elapsed >= COAST_FLOOR_S - _EPS:
			_coasting = true
			coasting_changed.emit(true)
		if elapsed >= COAST_AFK_S - _EPS and _phase != null:
			if _multiplayer:
				if not _afk:
					_afk = true
					afk_changed.emit(true)
			elif not _pause_emitted:
				_pause_emitted = true
				pause_requested.emit("coasting")
	else:
		if _coasting:
			_coasting = false
			coasting_changed.emit(false)
		if _afk:
			_afk = false
			afk_changed.emit(false)
		_pause_emitted = false


func _update_warmup() -> void:
	var active := true
	if _skip_warmup:
		active = false
	else:
		if _wu.started_t >= 0.0 and not _wu.done and _wu.t - _wu.started_t >= WARMUP_S - _EPS:
			_wu.done = true
		if (
			(_wu.done or _wu.started_t >= 0.0)
			and _wu.last_pedal_t >= 0.0
			and _wu.t - _wu.last_pedal_t >= WARMUP_RESET_S - _EPS
		):
			_wu.done = false
			_wu.started_t = -1.0
		active = not _wu.done
	if active != _warmup_active:
		_warmup_active = active
		if active:
			_end_haptic()
			_end_pull()
		warmup_changed.emit(active)


func _warmup_remaining_s() -> float:
	if not _warmup_active:
		return 0.0
	if _wu.started_t < 0.0:
		return WARMUP_S
	return maxf(0.0, WARMUP_S - (_wu.t - _wu.started_t))


func _update_rescue() -> void:
	var armed := false
	if _desired == Wl.ERG and not _game_paused and not _panic:
		# Whole watts on both sides (4.6.1): a target exactly at 60% FTP arms rescue even when
		# 60% FTP is not a whole number of watts (FTP 201: a 60% target is 120 W).
		armed = int(_erg_out.get("armed_w", 0)) >= _cap_w(RESCUE_ARM_PCT)
	if armed and not _rescue_armed:
		_rescue_armed_t = _t
	_rescue_armed = armed
	# Each trigger needs its condition for the whole window while armed: the window starts at
	# the later of the first sample that met it and the moment rescue armed.
	var triggered := false
	if armed:
		triggered = (
			(
				_cad_low_since >= 0.0
				and _t - maxf(_cad_low_since, _rescue_armed_t) >= RESCUE_CADENCE_LOW_S - _EPS
			)
			or (
				_pow_low_since >= 0.0
				and _t - maxf(_pow_low_since, _rescue_armed_t) >= RESCUE_POWER_LOW_S - _EPS
			)
		)
	match _rescue_state:
		_RESCUE_NONE, _RESCUE_RAMP:
			if armed and triggered:
				_rescue_state = _RESCUE_HOLD
				_cad_low_since = -1.0
				_pow_low_since = -1.0
				_cad_high_since = -1.0
				rescue_changed.emit(true)
				if _profile == PROFILE_RAMP_TEST and not _test_ended:
					_test_ended = true
					ramp_test_ended.emit("rescue")
			elif _rescue_state == _RESCUE_RAMP and _t - _rescue_ramp_t >= RESCUE_RAMP_S - _EPS:
				_rescue_state = _RESCUE_NONE
		_RESCUE_HOLD:
			if _desired == Wl.SIM or _desired == Wl.OFF:
				_end_rescue(false)
			elif _cad_high_since >= 0.0 and _t - _cad_high_since >= RESCUE_RECOVER_S - _EPS:
				_end_rescue(_profile != PROFILE_RAMP_TEST)


## Leave the rescue hold; with `ramp` the 10 s ramp-back starts now.
func _end_rescue(ramp: bool) -> void:
	var was_hold := _rescue_state == _RESCUE_HOLD
	if ramp and was_hold:
		_rescue_state = _RESCUE_RAMP
		_rescue_ramp_t = _t
	else:
		_rescue_state = _RESCUE_NONE
	_cad_high_since = -1.0
	if was_hold:
		rescue_changed.emit(false)


func _update_duration_limits(dt: float) -> void:
	if _profile == PROFILE_RAMP_TEST:
		_reset_run_s = 0.0
		return
	if _controller.mode() != Wl.ERG:
		# A switch to SIM restarts the reset count; SIM time adds nothing to either limit.
		_reset_run_s = 0.0
		return
	var w := _controller.applied_target_w()
	if w > _cap_w(LIMIT_105_PCT):
		_above_105_s += dt
	if w > _cap_w(LIMIT_120_PCT):
		_above_120_s += dt
	if float(w) <= GovernorClamps.pct_to_w(RESET_PCT, _ftp_w) + _EPS:
		_reset_run_s += dt
	else:
		_reset_run_s = 0.0
	if _reset_run_s >= RESET_S - _EPS:
		_above_105_s = 0.0
		_above_120_s = 0.0
		_latched_105 = false
		_latched_120 = false
	if _above_105_s >= LIMIT_105_S - _EPS:
		_latched_105 = true
	if _above_120_s >= LIMIT_120_S - _EPS:
		_latched_120 = true


## The whole-watt value of `pct` % FTP (rounded down).
func _cap_w(pct: float) -> int:
	return GovernorClamps.whole_w(GovernorClamps.pct_to_w(pct, _ftp_w))


func _floor_w() -> int:
	return GovernorClamps.floor_w(_ftp_w)


func _phase_is_long() -> bool:
	return _phase != null and _phase.worst_case_length_s() > LONG_PHASE_S + _EPS


func _is_cooldown_phase() -> bool:
	if _phase == null:
		return false
	return _phase.kind == Wl.COOLDOWN or (_plan != null and _phase_index == _plan.cooldown_index())


## The ERG target as % FTP right now: the directive channel, else the plan (with its ramp).
func _erg_pct_now() -> float:
	if not _ch_erg.is_empty():
		return float(_ch_erg["pct"])
	if _phase == null:
		return 0.0
	return _phase.planned_pct_at(_phase_elapsed)


func _planned_pct_now() -> float:
	if _phase == null or _phase.mode != Wl.ERG:
		return 0.0
	return _phase.planned_pct_at(_phase_elapsed)


## The governed ERG target (every rule but slew): {w, clamped_by, armed_w, pct}.
## armed_w is the value rescue arms on: after the unverified factor and the 4.6.1 caps.
func _compute_erg() -> Dictionary:
	var clamped: Array[String] = []
	var pct := _erg_pct_now()
	var w := GovernorClamps.pct_to_w(pct, _ftp_w)
	var ramp_test := _profile == PROFILE_RAMP_TEST
	if not ramp_test and not _ftp_verified and w > 0.0:
		w *= GovernorClamps.UNVERIFIED_FACTOR
		clamped.append(Wl.CLAMP_UNVERIFIED)
	var whole := GovernorClamps.whole_w(w)
	var ceiling := (
		GovernorClamps.ramp_test_ceiling_w(_trainer_max_w)
		if ramp_test
		else GovernorClamps.ceiling_w(_ftp_w, _trainer_max_w)
	)
	if whole > ceiling:
		whole = ceiling
		clamped.append(Wl.CLAMP_CEILING)
	if not ramp_test:
		var cap105 := _cap_w(LIMIT_105_PCT)
		if _phase_is_long() and whole > cap105:
			whole = cap105
			clamped.append(Wl.CLAMP_LONG_PHASE)
		var cap120 := _cap_w(LIMIT_120_PCT)
		if _latched_120 and whole > cap120:
			whole = cap120
			clamped.append(Wl.CLAMP_LIMIT_120)
		if _latched_105 and whole > cap105:
			whole = cap105
			clamped.append(Wl.CLAMP_LIMIT_105)
	var armed_w := whole
	if _warmup_active:
		var cap65 := _cap_w(WARMUP_ERG_PCT)
		if whole > cap65:
			whole = cap65
			clamped.append(Wl.CLAMP_WARMUP)
	var rescue_w := _cap_w(RESCUE_PCT)
	if _test_ended or _rescue_state == _RESCUE_HOLD:
		if whole > rescue_w:
			whole = rescue_w
			clamped.append(Wl.CLAMP_RESCUE)
	elif _rescue_state == _RESCUE_RAMP and whole > rescue_w:
		var frac := clampf((_t - _rescue_ramp_t) / RESCUE_RAMP_S, 0.0, 1.0)
		var ramped := GovernorClamps.whole_w(float(rescue_w) + float(whole - rescue_w) * frac)
		if ramped < whole:
			whole = ramped
			clamped.append(Wl.CLAMP_RESCUE)
	var fl := _floor_w()
	if _coasting and whole > fl:
		whole = fl
		clamped.append(Wl.CLAMP_COASTING)
	if _game_paused and whole > fl:
		whole = fl
		clamped.append(Wl.CLAMP_PAUSE)
	if whole < fl:
		whole = fl
		clamped.append(Wl.CLAMP_FLOOR)
	var pull := _compute_pull(whole, ceiling)
	return {
		"w": whole,
		"clamped_by": clamped,
		"armed_w": armed_w,
		"pct": pct,
		"pull_w": int(pull["w"]),
		"pull_clamped_by": pull["clamped_by"],
	}


## The haptic pull on top of the governed target `base_w` (4.6.6): {w (whole watts added),
## clamped_by}. pull % x intensity, at most +50% FTP, x0.85 while FTP is unverified; the sum
## never exceeds `ceiling_w` (min(150% FTP, 1000 W, trainer max)) nor a latched duration-limit
## band. The long-phase 105% cap does not apply (the one exemption besides slew).
func _compute_pull(base_w: int, ceiling_w: int) -> Dictionary:
	var clamped: Array[String] = []
	if _ch_pull.is_empty() or _pull_drop_reason(false, false) != "":
		return {"w": 0, "clamped_by": clamped}
	var pct := float(_ch_pull["pct"]) * _haptic_intensity
	if _haptic_intensity < 1.0:
		clamped.append(Wl.CLAMP_HAPTIC_INTENSITY)
	if pct > PULL_MAX_PCT:
		pct = PULL_MAX_PCT
		clamped.append(Wl.CLAMP_HAPTIC)
	var add := GovernorClamps.pct_to_w(pct, _ftp_w)
	if not _ftp_verified:
		add *= GovernorClamps.UNVERIFIED_FACTOR
		clamped.append(Wl.CLAMP_UNVERIFIED)
	var top := base_w + GovernorClamps.whole_w(add)
	if top > ceiling_w:
		top = ceiling_w
		clamped.append(Wl.CLAMP_CEILING)
	var cap120 := _cap_w(LIMIT_120_PCT)
	if _latched_120 and top > cap120:
		top = cap120
		clamped.append(Wl.CLAMP_LIMIT_120)
	var cap105 := _cap_w(LIMIT_105_PCT)
	if _latched_105 and top > cap105:
		top = cap105
		clamped.append(Wl.CLAMP_LIMIT_105)
	return {"w": maxi(top - base_w, 0), "clamped_by": clamped}


## Why a haptic pull can't run now ("" when it can). `sim` is true when the rider rides (or is
## switching to) SIM; `cooldown` checks the shared 15 s haptic cooldown (a new pull).
func _pull_drop_reason(sim: bool, cooldown: bool = true) -> String:
	if _panic:
		return REFUSE_PULL_UNSAFE
	if sim or _desired != Wl.ERG or _controller.mode() != Wl.ERG:
		return REFUSE_PULL_SIM
	if not _haptics_on:
		return Wl.REFUSE_HAPTIC_OFF
	if _warmup_active:
		return Wl.REFUSE_HAPTIC_WARMUP
	if (
		_profile == PROFILE_RAMP_TEST
		or _test_ended
		or _rescue_state != _RESCUE_NONE
		or _coasting
		or _afk
		or _game_paused
		or _shut_down
	):
		return REFUSE_PULL_UNSAFE
	if cooldown and _haptic_cooling():
		return Wl.REFUSE_HAPTIC_COOLDOWN
	return ""


## A haptic or haptic pull runs, or the previous one ended less than 15 s ago (4.6.6).
func _haptic_cooling() -> bool:
	return (
		not _ch_haptic.is_empty()
		or not _ch_pull.is_empty()
		or _t - _haptic_last_end_t < HAPTIC_COOLDOWN_S - _EPS
	)


## The stacked SIM state (4.6.6): {grade_pct, wind_mps, crr, cw, haptic_pct, base_grade_pct,
## course_grade_pct, mode_grade_pct, clamped_by}.
func _compute_sim() -> Dictionary:
	var clamped: Array[String] = []
	if _panic:
		var safe := _empty_sim()
		safe["clamped_by"] = [Wl.CLAMP_PANIC] as Array[String]
		return safe
	var course := 0.0
	if _phase != null and _phase.mode == Wl.SIM and _phase.grade_source != Wl.GRADE_FLAT:
		course = _course_applied
	var mode_grade := float(_ch_mode_grade.get("grade", 0.0))
	var scaled := (course + mode_grade) * _difficulty_pct / 100.0
	var base := scaled + _gears.offset_pct(scaled)
	var lo := maxf(_grade_min_pct, GRADE_TOTAL_MIN)
	var hi := minf(_grade_max_pct, GRADE_TOTAL_MAX)
	if base < lo or base > hi:
		base = clampf(base, lo, hi)
		clamped.append(Wl.CLAMP_GRADE_RANGE)
	var hap := 0.0
	var wind := 0.0
	if not _ch_haptic.is_empty() and not _game_paused:
		var raw_g := float(_ch_haptic["grade"])
		var raw_w := float(_ch_haptic["wind"])
		hap = raw_g * _haptic_intensity
		wind = raw_w * _haptic_intensity
		if _haptic_intensity < 1.0 and (absf(raw_g) > 0.0 or absf(raw_w) > 0.0):
			clamped.append(Wl.CLAMP_HAPTIC_INTENSITY)
		var limited := false
		if absf(hap) > HAPTIC_MAX_PCT:
			hap = clampf(hap, -HAPTIC_MAX_PCT, HAPTIC_MAX_PCT)
			limited = true
		if wind != 0.0:
			var w_max := _haptic_wind_max_mps(hap)
			if absf(wind) > w_max:
				wind = clampf(wind, -w_max, w_max)
				limited = true
		if limited:
			clamped.append(Wl.CLAMP_HAPTIC)
	var total := base + hap
	if total < GRADE_TOTAL_MIN or total > GRADE_TOTAL_MAX:
		total = clampf(total, GRADE_TOTAL_MIN, GRADE_TOTAL_MAX)
		clamped.append(Wl.CLAMP_GRADE_LIMIT)
	if _warmup_active and (total < WARMUP_GRADE_MIN or total > WARMUP_GRADE_MAX):
		total = clampf(total, WARMUP_GRADE_MIN, WARMUP_GRADE_MAX)
		clamped.append(Wl.CLAMP_WARMUP)
	if _game_paused:
		if absf(total) > 0.0 or absf(wind) > 0.0:
			clamped.append(Wl.CLAMP_PAUSE)
		total = 0.0
		wind = 0.0
		hap = 0.0
	var crr_f := float(_ch_factors.get("crr", 1.0))
	var cw_f := float(_ch_factors.get("cw", 1.0))
	if bool(_ch_factors.get("clamped", false)):
		clamped.append(Wl.CLAMP_FACTOR)
	return {
		"grade_pct": total,
		"wind_mps": wind,
		"crr": _crr * crr_f,
		"cw": _cw * cw_f,
		"haptic_pct": hap,
		"base_grade_pct": base,
		"course_grade_pct": course,
		"mode_grade_pct": mode_grade,
		"clamped_by": clamped,
	}


## The largest haptic wind (m/s) whose added force at the current speed, together with the
## applied haptic grade, stays within the force of +3% grade (BRIEF 4.6.6).
func _haptic_wind_max_mps(haptic_grade_pct: float) -> float:
	var mg := _system_mass_kg * G
	var budget := mg * sin(atan(HAPTIC_MAX_PCT / 100.0))
	var used := mg * sin(atan(maxf(haptic_grade_pct, 0.0) / 100.0))
	var left := maxf(0.0, budget - used)
	var cw := maxf(_cw * float(_ch_factors.get("cw", 1.0)), 1e-3)
	var v := _speed_mps if _speed_mps >= 0.0 else UNKNOWN_SPEED_MPS
	# cw * ((v + w)^2 - v^2) <= left  ->  w <= -v + sqrt(v^2 + left / cw)
	return maxf(0.0, -v + sqrt(v * v + left / cw))


func _empty_erg() -> Dictionary:
	return {
		"w": 0,
		"clamped_by": [] as Array[String],
		"armed_w": 0,
		"pct": 0.0,
		"pull_w": 0,
		"pull_clamped_by": [] as Array[String],
	}


func _empty_sim() -> Dictionary:
	return {
		"grade_pct": 0.0,
		"wind_mps": 0.0,
		"crr": _crr,
		"cw": _cw,
		"haptic_pct": 0.0,
		"base_grade_pct": 0.0,
		"course_grade_pct": 0.0,
		"mode_grade_pct": 0.0,
		"clamped_by": [] as Array[String],
	}


func _recompute_outputs() -> void:
	if _desired == Wl.ERG:
		_erg_out = _compute_erg()
	else:
		_erg_out = _empty_erg()
	if _desired == Wl.SIM or _desired == MODE_SAFE:
		_sim_out = _compute_sim()
	else:
		_sim_out = _empty_sim()


func _command_controller() -> void:
	var p3s := power_3s_w()
	match _desired:
		Wl.ERG:
			_controller.command_erg(
				int(_erg_out["w"]), _floor_w(), p3s, int(_erg_out["pull_w"]), _pull_left_s()
			)
		Wl.SIM:
			_controller.command_sim(
				float(_sim_out["wind_mps"]),
				float(_sim_out["grade_pct"]),
				float(_sim_out["crr"]),
				float(_sim_out["cw"]),
				_floor_w(),
				p3s
			)
		MODE_SAFE:
			pass
		_:
			# No phase (no plan yet, a plan before its first start_phase(), or after
			# clear_plan()): the rider rides free at SIM grade 0, wind 0 (W2r2). From ERG the
			# controller ramps there (the 4.5 step-down first).
			_controller.command_sim(0.0, 0.0, _crr, _cw, _floor_w(), p3s)


func _update_clamped_by() -> void:
	var out: Array[String] = []
	if _panic:
		out.append(Wl.CLAMP_PANIC)
	elif _desired == Wl.ERG:
		for c: String in _erg_out["clamped_by"]:
			out.append(c)
		var governed := int(_erg_out["w"])
		if _controller.mode() != Wl.ERG:
			_append_unique(out, Wl.CLAMP_SWITCH)
		elif _controller.applied_base_w() < governed:
			if _controller.entry_active():
				_append_unique(out, Wl.CLAMP_SWITCH)
			_append_unique(out, Wl.CLAMP_SLEW)
		if _controller.applied_pull_w() > 0:
			_append_unique(out, CLAMP_PULL)
			for c: String in _erg_out["pull_clamped_by"]:
				_append_unique(out, c)
	elif _desired == Wl.SIM:
		for c: String in _sim_out["clamped_by"]:
			out.append(c)
		if _controller.mode() != Wl.SIM:
			_append_unique(out, Wl.CLAMP_SWITCH)
	_clamped_by = out


# =============================================================================================
# Channels, phases and mode
# =============================================================================================


## True when `index` is a phase of the current plan; push_error (naming `what`) otherwise.
func _phase_index_ok(index: int, what: String) -> bool:
	if _plan == null:
		push_error("SafetyGovernor: %s before set_plan()" % what)
		return false
	if index < 0 or index >= _plan.size():
		push_error("SafetyGovernor: %s outside the plan (0..%d)" % [what, _plan.size() - 1])
		return false
	return true


## Enter phase `index` with its clock at `elapsed_s` and `ridden_m` metres of its course
## already behind the rider (start_phase: 0, 0; resume_phase).
func _enter_phase(index: int, elapsed_s: float, ridden_m: float) -> void:
	_clear_channels()
	_phase_index = index
	_phase = _plan.phase(index)
	_phase_elapsed = elapsed_s
	_course_source = 0.0
	_course_source_set = false
	_course_applied = 0.0
	_course_applied_t = _NEVER
	_distance_origin = _distance_m
	_distance_offset = ridden_m
	_update_desired()
	if _phase.mode == Wl.SIM and _rescue_state != _RESCUE_NONE:
		_end_rescue(false)
	_recompute_outputs()
	_update_status()


func _update_desired() -> void:
	var next := Wl.OFF
	if _panic:
		next = MODE_SAFE
	elif _phase != null:
		if _phase.mode == Wl.SIM or not _ch_block.is_empty():
			next = Wl.SIM
		else:
			next = Wl.ERG
	var was_erg := _desired == Wl.ERG
	var now_erg := next == Wl.ERG
	# No phase ("OFF") commands SIM grade 0 (W2r2), so for the 30 s spacing (BRIEF 4.5) it is
	# SIM (W4, SAF-6): ERG -> OFF is a switch, and OFF -> ERG is one when the controller has the
	# trainer at SIM (the menus, a cool-down that already stepped down). A fresh controller that
	# has written nothing knows no previous mode, so a first ERG is no switch.
	var was_sim := (
		_desired == Wl.SIM
		or _desired == MODE_SAFE
		or (_desired == Wl.OFF and _controller.mode() == Wl.SIM)
	)
	var now_sim := next == Wl.SIM or next == MODE_SAFE or (next == Wl.OFF and not _shut_down)
	if (was_erg and now_sim) or (was_sim and now_erg):
		_last_switch_t = _t
	if next != Wl.SIM and next != MODE_SAFE and not _ch_haptic.is_empty():
		_end_haptic()
	if next != Wl.ERG:
		_end_pull()
	_desired = next


func _expiry_for(duration_s: float) -> float:
	if duration_s <= 0.0:
		return -1.0
	return _game_t + snappedf(duration_s, Wl.SIM_DT)


func _expired(ch: Dictionary) -> bool:
	var e := float(ch.get("expires", -1.0))
	return e >= 0.0 and _game_t >= e - _EPS


func _expire_channels() -> void:
	if not _ch_erg.is_empty() and _expired(_ch_erg):
		_ch_erg = {}
	if not _ch_block.is_empty() and _expired(_ch_block):
		_end_block()
	if not _ch_mode_grade.is_empty() and _expired(_ch_mode_grade):
		_ch_mode_grade = {}
	if not _ch_factors.is_empty() and _expired(_ch_factors):
		_ch_factors = {}
	if (
		not _ch_haptic.is_empty()
		and (_expired(_ch_haptic) or _t >= float(_ch_haptic["end_t"]) - _EPS)
	):
		_end_haptic()
	if not _ch_pull.is_empty() and (_expired(_ch_pull) or _t >= float(_ch_pull["end_t"]) - _EPS):
		_end_pull()


## End the SIM block (expiry or a mode ERG request): its mode grade and haptic go with it.
func _end_block() -> void:
	_ch_block = {}
	_ch_mode_grade = {}
	_end_haptic()


func _end_haptic() -> void:
	if _ch_haptic.is_empty():
		return
	_ch_haptic = {}
	_haptic_last_end_t = _t


## End the haptic pull: the target drops back at once; the shared cooldown starts now.
func _end_pull() -> void:
	if _ch_pull.is_empty():
		return
	_ch_pull = {}
	_haptic_last_end_t = _t


## Platform seconds until the running pull ends (0 without one).
func _pull_left_s() -> float:
	if _ch_pull.is_empty():
		return 0.0
	var left := minf(float(_ch_pull["end_t"]) - _t, float(_ch_pull["expires"]) - _game_t)
	return maxf(0.0, left)


func _clear_channels() -> void:
	_ch_erg = {}
	_ch_block = {}
	_ch_mode_grade = {}
	_ch_factors = {}
	_end_haptic()
	_end_pull()


func _update_course_grade() -> void:
	if _phase == null or _phase.mode != Wl.SIM:
		return
	var src := NAN
	if _phase.grade_source == Wl.GRADE_GAME:
		if _course_source_set:
			src = _course_source
	elif _phase.grade_source == Wl.GRADE_COURSE:
		src = profile_grade(_phase.course_profile, phase_distance_m())
	if is_nan(src):
		return
	if (
		absf(src - _course_applied) > 1e-9
		and _t - _course_applied_t >= COURSE_GRADE_INTERVAL_S - _EPS
	):
		_course_applied = src
		_course_applied_t = _t


func _unsafe_reason() -> String:
	if _panic:
		return "panic"
	if _rescue_state == _RESCUE_HOLD:
		return "rescue"
	if _coasting:
		return "coasting"
	if _afk:
		return "afk"
	if _game_paused:
		return "pause"
	return ""


func _target_pct_of(d: EffortDirective) -> float:
	if d.is_set("target_pct"):
		return d.target_pct
	if d.is_set("target_w"):
		return GovernorClamps.w_to_pct(d.target_w, _ftp_w)
	return GovernorClamps.w_to_pct(d.target_wkg * _weight_kg, _ftp_w)


func _bad_fields(d: EffortDirective) -> String:
	if d.mode != "" and d.mode != Wl.ERG and d.mode != Wl.SIM:
		return 'mode "%s" is not ERG or SIM' % d.mode
	for f: String in EffortDirective.FLOAT_FIELDS:
		var v: float = d.get(f)
		if not is_nan(v) and not is_finite(v):
			return "%s is not finite" % f
	if not is_finite(d.duration_s) or d.duration_s < 0.0:
		return "duration_s must be finite and >= 0"
	var targets := 0
	for f: String in ["target_pct", "target_wkg", "target_w"]:
		if d.is_set(f):
			targets += 1
	if targets > 1:
		return "more than one of target_pct, target_wkg, target_w"
	if d.is_set("haptic_pull") and d.haptic_pull <= 0.0:
		return "haptic_pull must be > 0"
	if (
		d.mode == ""
		and not (
			d.sets_erg_target()
			or d.sets_haptic()
			or d.is_set("mode_grade")
			or d.sets_factors()
			or d.is_set("haptic_pull")
		)
	):
		return "no channel set"
	return ""


func _new_record(kind: String, requested: Dictionary, id: int) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"requested": requested,
		"applied": {},
		"clamped_by": [] as Array[String],
		"refused": false,
		"reason": "",
		"dropped": [],
		"t": _t,
		"game_t": _game_t,
		"phase_index": _phase_index,
	}


func _refuse(rec: Dictionary, reason: String, detail: String) -> Dictionary:
	rec["refused"] = true
	rec["reason"] = reason
	push_warning(
		(
			"SafetyGovernor: %s %d refused: %s (%s)"
			% [str(rec["kind"]), int(rec["id"]), reason, detail]
		)
	)
	directive_applied.emit(rec)
	return rec


# =============================================================================================
# Status
# =============================================================================================


func _update_status() -> void:
	var mode := Wl.OFF if _shut_down else _controller.mode()
	var applied_w := _controller.applied_target_w() if mode == Wl.ERG else 0
	var grade := 0.0
	var wind := 0.0
	var crr := _crr
	var cw := _cw
	var written_grade := 0.0
	if mode == Wl.SIM:
		var ws := _controller.written_sim()
		written_grade = float(ws["grade_pct"])
		if _desired == Wl.SIM:
			grade = float(_sim_out["grade_pct"])
			wind = float(_sim_out["wind_mps"])
			crr = float(_sim_out["crr"])
			cw = float(_sim_out["cw"])
		else:
			grade = written_grade
			wind = float(ws["wind_mps"])
			crr = float(ws["crr"])
			cw = float(ws["cw"])
	_status = {
		"mode": mode,
		"applied_target_w": applied_w,
		"applied_pct": GovernorClamps.w_to_pct(float(applied_w), _ftp_w) if applied_w > 0 else 0.0,
		"applied_grade_pct": grade,
		"wind_mps": wind,
		"crr": crr,
		"cw": cw,
		"haptic_active": not _ch_haptic.is_empty(),
		"haptic_pull_active": not _ch_pull.is_empty(),
		"haptic_pull_w": _controller.applied_pull_w() if mode == Wl.ERG else 0,
		"haptic_pct": float(_sim_out.get("haptic_pct", 0.0)) if mode == Wl.SIM else 0.0,
		"clamped_by": _clamped_by.duplicate(),
		"rescue": _rescue_state == _RESCUE_HOLD,
		"rescue_ramp": _rescue_state == _RESCUE_RAMP,
		"coasting": _coasting,
		"afk": _afk,
		"paused": _game_paused,
		"panic": _panic,
		"warmup_active": _warmup_active,
		"warmup_remaining_s": _warmup_remaining_s(),
		"gear": _gears.gear,
		"s_left_105": maxf(0.0, LIMIT_105_S - _above_105_s),
		"s_left_120": maxf(0.0, LIMIT_120_S - _above_120_s),
		"latched_105": _latched_105,
		"latched_120": _latched_120,
		"phase_index": _phase_index,
		"phase_elapsed_s": _phase_elapsed,
		"sim_block_active": not _ch_block.is_empty(),
		"last_switch_t": _last_switch_t,
		"profile": _profile,
		"t": _t,
		"game_t": _game_t,
		"desired_mode": _desired,
		"governed_target_w": int(_erg_out.get("w", 0)),
		"planned_pct": _planned_pct_now(),
		"power_3s_w": power_3s_w(),
		"course_grade_pct": _course_applied,
		"mode_grade_pct": float(_ch_mode_grade.get("grade", 0.0)),
		"base_grade_pct": float(_sim_out.get("base_grade_pct", 0.0)),
		"test_ended": _test_ended,
		"shut_down": _shut_down,
		"ftp_w": _ftp_w,
		"ftp_verified": _ftp_verified,
		"written_target_w": _controller.written_target_w(),
		"written_grade_pct": written_grade,
		"reset_run_s": _reset_run_s,
		"samples_stale": _stale,
	}


static func _status_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: Variant in a.keys():
		if not b.has(k):
			return false
		var va: Variant = a[k]
		var vb: Variant = b[k]
		if typeof(va) != typeof(vb):
			return false
		if va is Array:
			if (va as Array) != (vb as Array):
				return false
		elif va != vb:
			return false
	return true


# =============================================================================================
# Helpers
# =============================================================================================


static func _append_unique(arr: Array[String], value: String) -> void:
	if not arr.has(value):
		arr.append(value)


static func _device_max_w(device: TrainerDevice) -> float:
	if device == null:
		return float(GovernorClamps.KICKR_MAX_W)
	var r := device.power_range()
	var m := float(r.get("max_w", GovernorClamps.KICKR_MAX_W))
	return m if m > 0.0 else float(GovernorClamps.KICKR_MAX_W)


func _clamped_param(key: String, value: float, lo: float, hi: float) -> float:
	if not is_finite(value):
		push_warning("SafetyGovernor: %s is not finite; using %s" % [key, str(lo)])
		return lo
	if value < lo or value > hi:
		push_warning(
			"SafetyGovernor: %s = %s clamped to [%s, %s]" % [key, str(value), str(lo), str(hi)]
		)
	return clampf(value, lo, hi)
