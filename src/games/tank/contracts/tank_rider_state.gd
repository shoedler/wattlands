class_name TankRiderState
extends TankRecord
## One crew member (G0 contract). Host bookkeeping plus the [snap] part every peer needs for the
## teammate strip, the station card and results. Results stats are host-only and reach clients
## in GameResults.

## Indexes of engine_s (engine code - 1; 3 was the retired Bulwark's and stays unused).
const ENGINE_INDEX := {
	TankIds.ENGINE_DIESEL: 0,
	TankIds.ENGINE_DYNAMO: 1,
	TankIds.ENGINE_STEAM: 2,
	TankIds.ENGINE_ARC: 4,
	TankIds.ENGINE_FEED: 5
}
## Indexes of shells_by_type.
const SHELL_INDEX := {
	TankIds.SHELL_LIGHT: 0, TankIds.SHELL_HEAVY: 1, TankIds.SHELL_OVER: 2, TankIds.SHELL_BOW: 3
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
## v3: the rider's seat; at most one rider per seat (TankStationState.slot points back).
var engine: String = ""
## [snap] (0.3.1) While the rider's trainer has not yet switched to its seat's mode (Wl.ERG or
## Wl.SIM, `mode_to`; "" when it follows the seat): seconds until it switches (BRIEF 4.5 keeps a
## rider's ERG <-> SIM switches 30 s apart), or -1 when it waits for the segment's end. The HUD shows
## "ERG in 12 s". A seat move itself lands at once (there is no seat lock since 0.3.1).
var mode_wait_s: float = 0.0
var mode_to: String = ""
## [snap] Raw watts, cadence and %FTP of the latest tick (for the strip and the station card).
var raw_w: float = 0.0
var cadence_rpm: float = 0.0
var ftp_pct: float = 0.0
## [snap] (v2) The rider's current effort target in % FTP, for the HUD's and the view's power ratio:
## power = raw W / (target_pct / 100 x FTP). The host sets it each tick (TankRules.target_pct): the
## applied ERG target, else the phase's planned ERG target, else in SIM the engine's band centre
## (diesel and Bulwark: the middle of tanks.json in_band.sim_ftp_pct; steam building 90, loaded or
## cycling tanks.json power_ratio.steam_loaded_pct; WARMUP-kind SIM power_ratio.warmup_sim_pct).
## 0 when there is none (no phase).
var target_pct: float = 0.0
## [snap]
var in_band: bool = false
## [snap] (v2) This rider can "Surge to evade" now (brief 2.4): in a SIM WORK phase of its own plan,
## past its first 300 s, present and not in rescue. Each peer raises its own rider's prompt from it.
var can_evade: bool = false
## [snap] (v2) The rider's sprint rule holds now (>= 1.2 x FTP raw over the trailing 3 s).
var sprinting: bool = false
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
var engine_s: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## (v2) Telegraphed shots that resolved while this rider could evade, and those this rider's own
## surge made miss (brief 2.8: evades tried and successful).
var evades_tried: int = 0
var evades_ok: int = 0
## (v2) Bow-gun bursts credited to this rider (its station powered them) that hit.
var bow_hits: int = 0
## Berm HP that absorbed damage while this rider dug in.
var berm_absorbed: float = 0.0
## Main-gun shots fired from this rider's station and hits, plus every shell by type.
var shots: int = 0
var hits: int = 0
var shells_by_type: Array[int] = [0, 0, 0, 0]

# --- Host-only helpers (never serialized: "_" names and Objects are skipped by TankRecord) -----------
## The sprint rule for evade and Overpressure: SprintRule.create(ftp, evade.sprint_window_s), the
## trailing 3 s average >= 1.2 x FTP (BRIEF 3.5, brief 2.4). The rules feed it every tick with
## (state.t, raw watts) through sprint_rule(); `sprinting` mirrors holds(). Reset it when the rider
## changes station.
var _sprint: SprintRule = null


## This rider's sprint rule, created on first use with a `window_s` trailing window.
func sprint_rule(window_s: float) -> SprintRule:
	if _sprint == null:
		_sprint = SprintRule.create(ftp, window_s)
	return _sprint
