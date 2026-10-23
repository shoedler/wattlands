class_name TankRiderInput
extends RefCounted
## One slot's part of TankInputs (G0 contract): the rider input digest, everything the rules
## read from a frame for one rider. Built by TankInputs.from_frame (the module) or directly
## (tests, the rules-level balance harness).

var peer: int = 0
var slot: int = 0
## TankIds.ENGINE_* this rider works in its current phase (its plan meta; "" in the cool-down).
var engine: String = ""
## This rider's own phase index (normally the group's; it can lag one tick at a boundary).
var phase_index: int = -1
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
