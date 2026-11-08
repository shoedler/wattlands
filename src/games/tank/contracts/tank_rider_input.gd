class_name TankRiderInput
extends RefCounted
## One slot's part of TankInputs (G0 contract): the rider input digest, everything the rules
## read from a frame for one rider. Built by TankInputs.from_frame (the module) or directly
## (tests, the rules-level balance harness).

var peer: int = 0
var slot: int = 0
## TankIds.ENGINE_* this rider works in its current phase (its plan meta; "" in the cool-down).
var engine: String = ""
## This rider's own phase (frame.phase_of(peer) and its PlanPhase): normally the group's, but it
## can lag one tick at a boundary. Every per-rider gate uses these, never the group's TankPhaseInfo:
## the SIM-only patterns (boiler, hoist, terrain), haptics (SIM phases only, never WARMUP kinds,
## never in this rider's first 300 s: TankConst.in_first_window(plan_elapsed_s)), the warm-up
## numbers (WARMUP kinds) and the in-band rule's kind.
var phase_index: int = -1
## Wl.WARMUP / WORK / RECOVERY / COOLDOWN ("" without a phase).
var phase_kind: String = ""
## The plan's mode for this phase (Wl.ERG / Wl.SIM; the cool-down is ERG). `mode` below is what
## the governor applies now (rescue can differ).
var phase_mode: String = ""
## PlanPhase.grade_source (Wl.GRADE_FLAT / GRADE_GAME) of a SIM phase; "" for ERG and the cool-down.
var grade_source: String = ""
## (v2) PhaseState.planned_pct: the plan's ERG target now in % FTP (its ramp included); 0 in SIM.
var planned_pct: float = 0.0
## Game seconds since this rider's plan started (PhaseState.plan_elapsed_s).
var plan_elapsed_s: float = 0.0
## (v3) The mission segment of this rider's phase (its meta "segment"; the segment count in the
## cool-down, -1 without a phase). A seat switch splits a phase (TankSeatPlan), so a rider's plan
## phase index can run ahead of the segment's: the group and end_phase key on the segment.
var segment: int = -1
## (v3) This rider's own phase clock and bounds (PhaseState elapsed_s, min_s, max_s, open_ended,
## remaining_s): a split phase's elapsed counts from the switch, and its min_s may hold the
## segment's end (TankDirector waits for every rider's min_s before it ends a segment).
var phase_elapsed_s: float = 0.0
var phase_min_s: float = 0.0
var phase_max_s: float = 0.0
var phase_open_ended: bool = false
var phase_remaining_s: float = 0.0
## (v3) Seconds into the segment this rider's phase starts (its meta "offset_s"; 0 unless the phase
## is the rest of a segment after a seat switch).
var seg_offset_s: float = 0.0
## (v3) Host only: this rider's plan as the module keeps it (no cool-down; spliced on every seat
## replan), so the seat rules can build and check a replan (TankSeatPlan). Null on clients and in
## tests that do not need it.
var plan: EffortPlan = null
## PlayerSlot.rider_mass_kg (scaling-mode mass; real on the host, 75 for others on a client). The
## drive (SpeedModel.create(mass, 0.5, 8.0), GAME_SDK) uses the mass of the rider whose station is
## diesel or bulwark this tick, so it changes with rotation.
var rider_mass_kg: float = 75.0
## Raw watts (the sprint rule, steam "building" >= 90% FTP and ERG in-band compare raw watts).
var power_w: float = 0.0
## Effective power (BRIEF 3.3): what drives the engines (energy, speed, berm, repair).
var p_eff_w: float = 0.0
var cadence_rpm: float = 0.0
## The rider's FTP in watts and its verified flag (PlayerSlot).
var ftp: float = 200.0
var ftp_verified: bool = true
## Raw power / FTP x 100.
var ftp_pct: float = 0.0
## The governor's applied mode (Wl.ERG / Wl.SIM / Wl.OFF) and ERG target in whole watts (0
## outside ERG; 50% FTP during rescue). In-band in ERG is power >= 95% of it and cadence >= 60.
var mode: String = Wl.OFF
var applied_target_w: float = 0.0
## W' balance in joules (HUD only; the rules never gate on it).
var wbal_j: float = 0.0
## From on_rescue / on_afk; afk is also true while disconnected (a dropped peer).
var rescue: bool = false
var afk: bool = false
var connected: bool = true
## PlayerSlot.autopilot (bots and Autopilot humans).
var autopilot: bool = false
## Normalized (TankIntents.normalize), rate-limited (TankIntentLimiter) intents this tick, in
## arrival order, already filtered by ownership (TankIntents.owned for `engine`), the rider's own
## first, then autopilot_intents().
var intents: Array[Dictionary] = []


## Applied ERG target in % FTP (0 outside ERG).
func applied_pct() -> float:
	return applied_target_w / ftp * 100.0 if ftp > 0.0 else 0.0


## On reserve: dropped or AFK (the station runs as if P_eff 60 W, never in band, brief 2.2).
func on_reserve() -> bool:
	return afk or not connected


## In this rider's own first 300 s (no evade, Overpressure, sprint prompt or haptic).
func in_first_window() -> bool:
	return TankConst.in_first_window(plan_elapsed_s)


## This rider's phase is a WARMUP kind (the hangar, the roll-out, the drill's skirmish): warm-up numbers apply.
func in_warmup() -> bool:
	return phase_kind == Wl.WARMUP
