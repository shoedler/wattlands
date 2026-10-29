class_name SiegeRiderState
extends SiegeRecord
## One rider's wheel in SiegeState.riders (slot order). The rules write it on the host;
## SiegeSnapshot rebuilds the snapshot part on clients (fields marked [snap]); the view and HUD
## read it (STATE_V2.md). Units: s, W (raw), P_eff W, gold (float; the snapshot floors it).

## [snap] (slot) Slot index 0..3; owns wheel 0..3, west to east.
var slot: int = 0
var peer: int = 0
var is_bot: bool = false
## Bots and Autopilot-on humans (PlayerSlot.autopilot).
var autopilot: bool = false
## PlayerSlot.ftp (W): CP for Overdrive's od = 2 (ADR "slot.ftp as CP"), %FTP on the strip.
var ftp: float = 200.0
var ftp_verified: bool = true

## [snap] Routing target: a station 0..4 (SiegeIds.STATION_*). During a reconnect it is already
## the new target.
var target: int = SiegeIds.STATION_MINE
## [snap] Seconds left of the 2 s reconnect after a change (no output while > 0).
var reconnect_s: float = 0.0
## Game time of the last target change (Autopilot's 8 s switch limit).
var routed_t: float = -1000.0

## [snap] Latest telemetry: P_eff W (wheel speed, the powered path), raw W (strip), cadence.
var p_eff_w: float = 0.0
var raw_w: float = 0.0
var cadence_rpm: float = 0.0
## WKG's r = p_eff_w / power_w from the latest telemetry with power >= 50 W (1 before).
var r_wkg: float = 1.0
## [snap] Safety states from on_rescue / on_afk (a dropped client is AFK).
var rescue: bool = false
var afk: bool = false
var connected: bool = true

## [snap] Personal gold (start 40; float on the host, floored in the snapshot).
var gold: float = 0.0

## Zero-input fallbacks (brief 2.5): Autopilot routes for this rider while route_fallback, and
## shops for it while shop_fallback. A deliberate route intent clears the first, a buy that is
## not auto-confirmed the second; Overdrive intents and auto-confirms clear neither. Bots never
## clear them.
var route_fallback: bool = true
var shop_fallback: bool = true
## Purchases Autopilot made for this rider in the current break (at most 2).
var ap_buys: int = 0

## [snap] Overdrive state machine (SiegeOverdrive): SiegeIds.OD_READY / PENDING / ACTIVE /
## COOLDOWN, seconds left of it (od_s) and of the cooldown (od_cd_s).
var od_state: int = SiegeIds.OD_READY
var od_s: float = 0.0
var od_cd_s: float = 0.0
## The accepted directive's id while ACTIVE (0 otherwise): matches the applied record.
var od_id: int = 0
## Current and best streak of raw power >= 1.2 x FTP inside this Overdrive (scored at >= 10 s).
var od_hold_s: float = 0.0
var od_best_s: float = 0.0
## The prompt is showing (host: computed each tick; clients: recomputed from the snapshot).
var od_prompt: bool = false

# --- Results stats (brief 2.8) -------------------------------------------------------------------
var mine_gold: float = 0.0
var bounty_gold: float = 0.0
var kills: int = 0
var damage: float = 0.0
var od_count: int = 0
var od_scored: int = 0
## Wave seconds delivering to the mine vs. a weapon or the tar works.
var wave_mine_s: float = 0.0
var wave_weapon_s: float = 0.0
## Wave seconds delivering to each station 0..4 (the station spent most time on).
var station_s: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]


## True while the rider's output reaches its target: connected, not AFK, not reconnecting.
func delivering() -> bool:
	return connected and not afk and reconnect_s <= 0.0


## The station this rider delivered to longest in waves (the mine when none).
func top_station() -> int:
	var best := SiegeIds.STATION_MINE
	for i in station_s.size():
		if station_s[i] > station_s[best] + 1e-9:
			best = i
	return best
