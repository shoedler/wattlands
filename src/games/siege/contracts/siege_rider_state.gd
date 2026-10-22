class_name SiegeRiderState
extends SiegeRecord
## One rider's wheel in SiegeState.riders (slot order). The rules (B1) write it on the host;
## SiegeSnapshot rebuilds the snapshot part on clients (fields marked [snap]); the view and HUD
## (B3) read it. Units: s, W (raw), P_eff W, denarii (float; the snapshot floors it). G0 contract.

## [snap] (slot) Slot index 0..3; owns the NW, NE, SW, SE wheel.
var slot: int = 0
var peer: int = 0
var is_bot: bool = false
## Bots and Autopilot-on humans (PlayerSlot.autopilot).
var autopilot: bool = false
## PlayerSlot.ftp (W): CP for Overdrive's od = 2 (ADR "slot.ftp as CP"), %FTP on the strip.
var ftp: float = 200.0
var ftp_verified: bool = true

## [snap] Routing target: SiegeIds.TARGET_GEN (0) or a pad 1..8. During a reconnect it is
## already the new target.
var target: int = SiegeIds.TARGET_GEN
## [snap] Seconds left of the 2 s reconnect after a change (no output while > 0).
var reconnect_s: float = 0.0
## Game time of the last target change (Autopilot's 8 s switch limit).
var routed_t: float = -1000.0

## [snap] Latest telemetry: P_eff W (wheel speed, chains), raw W (strip), cadence (workers).
var p_eff_w: float = 0.0
var raw_w: float = 0.0
var cadence_rpm: float = 0.0
## WKG's r = p_eff_w / power_w from the latest telemetry with power >= 50 W (1 before).
var r_wkg: float = 1.0
## [snap] Safety states from on_rescue / on_afk (a dropped client is AFK).
var rescue: bool = false
var afk: bool = false
var connected: bool = true

## [snap] Personal denarii (start 40; float on the host, floored in the snapshot).
var denarii: float = 0.0

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
var gen_denarii: float = 0.0
var bounty_denarii: float = 0.0
var kills: int = 0
var damage: float = 0.0
var od_count: int = 0
var od_scored: int = 0
## Wave seconds routed to the generator vs. towers (connected, not reconnecting).
var wave_gen_s: float = 0.0
var wave_tower_s: float = 0.0
var towers_built: int = 0


## True while the rider's output reaches its target: connected, not AFK, not reconnecting.
func delivering() -> bool:
	return connected and not afk and reconnect_s <= 0.0
