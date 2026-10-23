class_name SiegeRiderInput
extends RefCounted
## One slot's part of SiegeInputs (G0 contract): the telemetry subset the rules use, the safety
## flags, the plan numbers the budget B and par need, and this tick's validated intents.

var peer: int = 0
var slot: int = 0
## Raw watts (Overdrive's od = 2 needs >= slot.ftp; the sprint rule needs >= 1.2 x FTP).
var power_w: float = 0.0
## Effective power (BRIEF 3.3): what towers and the generator are paid in.
var p_eff_w: float = 0.0
var cadence_rpm: float = 0.0
## The governor's applied mode (Wl.ERG / Wl.SIM / Wl.OFF).
var mode: String = Wl.OFF
var connected: bool = true
## From on_rescue / on_afk (afk is also true while disconnected).
var rescue: bool = false
var afk: bool = false
## frame.phase_of(peer).planned_pct: this slot's planned ERG target now (% FTP, ramp included;
## the wave offset included in waves).
var planned_pct: float = 0.0
## The phase's mean planned target (% FTP; a ramp's mean): the budget B's "planned P_eff".
var phase_mean_pct: float = 0.0
## Normalized intents (SiegeIntents.normalize), rate-limited, in arrival order.
var intents: Array[Dictionary] = []
