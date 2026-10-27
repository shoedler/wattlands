class_name TankRiderState
extends TankRecord
## One crew member (G0 contract). Host bookkeeping plus the [snap] part every peer needs for the
## teammate strip, the station card and results. Results stats are host-only and reach clients
## in GameResults.

## Indexes of engine_s (engine code - 1).
const ENGINE_INDEX := {
	TankIds.ENGINE_DIESEL: 0,
	TankIds.ENGINE_DYNAMO: 1,
	TankIds.ENGINE_STEAM: 2,
	TankIds.ENGINE_BULWARK: 3
}
## Indexes of shells_by_type.
const SHELL_INDEX := {
	TankIds.SHELL_LIGHT: 0,
	TankIds.SHELL_HEAVY: 1,
	TankIds.SHELL_OVER: 2,
	TankIds.SHELL_BOW: 3
}

## [snap]
var slot: int = 0
var peer: int = 0
var is_bot: bool = false
## PlayerSlot.autopilot (the platform calls autopilot_intents for it).
var autopilot: bool = false
## A human counts as Autopilot until their first deliberate intent (TankIds.DELIBERATE_KINDS;
## ram and over never end it, brief 2.5). True while the fallback plays this rider's choices.
var fallback: bool = true
var ftp: float = 200.0
var ftp_verified: bool = true
var haptics_on: bool = true
## Host only: PlayerSlot.rider_mass_kg (the drive's mass while this rider drives).
var rider_mass_kg: float = 75.0

## [snap] (engine code) TankIds.ENGINE_* this rider works in the current segment (plan meta).
var engine: String = ""
## [snap] Raw watts, cadence and %FTP of the latest tick (for the strip and the station card).
var raw_w: float = 0.0
var cadence_rpm: float = 0.0
var ftp_pct: float = 0.0
## [snap]
var in_band: bool = false
## [snap]
var rescue: bool = false
## [snap] AFK or dropped: the station runs on reserve.
var afk: bool = false
## [snap]
var connected: bool = true

# --- Results (brief 2.8), host only -------------------------------------------------------------------
## Game seconds of WORK phases, and of those in band (score "band" is the crew mean of their ratio).
var work_s: float = 0.0
var band_s: float = 0.0
## Game seconds per engine (ENGINE_INDEX).
var engine_s: Array[float] = [0.0, 0.0, 0.0, 0.0]
var rams: int = 0
var dodges: int = 0
## Berm HP that absorbed damage while this rider dug in.
var berm_absorbed: float = 0.0
## Main-gun shots fired from this rider's station and hits, plus every shell by type.
var shots: int = 0
var hits: int = 0
var shells_by_type: Array[int] = [0, 0, 0, 0]

# --- Host-only helpers (never serialized: "_" names and Objects are skipped by TankRecord) -----------
## The sprint rule for Ram, dodge and Overpressure: SprintRule.create(ftp, ram.sprint_window_s),
## the trailing 3 s average >= 1.2 x FTP (BRIEF 3.5, brief 2.4). The rules feed it every tick with
## (state.t, raw watts) through sprint_rule(); the station's `sprinting` mirrors holds() and
## `sprint_s` / `dodge_s` count held_s(). Reset it when the rider changes station.
var _sprint: SprintRule = null


## This rider's sprint rule, created on first use with a `window_s` trailing window.
func sprint_rule(window_s: float) -> SprintRule:
	if _sprint == null:
		_sprint = SprintRule.create(ftp, window_s)
	return _sprint
