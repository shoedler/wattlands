class_name FishingRiderInput
extends RefCounted
## One rider's inputs for one FishingRules.step (contract v2). FishingGame fills one per slot, in
## slot order, from the InputFrame's Telemetry and PhaseState, so the rules never touch platform
## objects and tests build inputs directly.

var peer: int = 0
var slot: int = 0
var has_phase: bool = false

# --- Telemetry -----------------------------------------------------------------------------
var power_w: float = 0.0
## Effective power in the session's scaling mode (the boat's thrust).
var p_eff_w: float = 0.0
var cadence_rpm: float = 0.0
## Seconds since the last fresh cadence value, and since the rider's latest telemetry arrived
## (0 for local riders and bots).
var cadence_age_s: float = 0.0
var age_s: float = 0.0
var connected: bool = true
var applied_target_w: float = 0.0
## "ERG", "SIM" or "OFF" as the rider's governor applied it.
var mode: String = "ERG"
var rescue: bool = false
var afk: bool = false
var paused: bool = false

# --- Phase (frame.phase_of(peer)) ---------------------------------------------------------
var phase_index: int = -1
var phase_kind: String = ""
var phase_mode: String = ""
var phase_elapsed_s: float = 0.0
var phase_duration_s: float = 0.0
var phase_open_ended: bool = false
var phase_min_s: float = 0.0
var phase_max_s: float = 0.0
var phase_remaining_s: float = 0.0
## Game seconds since this rider's plan started ("the first 300 s": plan_elapsed_s < 300).
var plan_elapsed_s: float = 0.0
var is_cooldown: bool = false

# --- Intents -------------------------------------------------------------------------------
## This tick's intents, each FishingIntents.normalize()d, the rider's own first.
var intents: Array = []
