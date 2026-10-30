class_name SiegeStationState
extends SiegeRecord
## One of the five stations in SiegeState.stations (index = id, STATE_V2.md). The rules write it
## on the host; fields marked [snap] come back on clients from the snapshot's st rows.

## [snap] Station id 0..4 (SiegeIds.STATION_*).
var id: int = 0
## [snap] Upgrades bought, 0..3, team-wide (the mine: the mine level).
var level: int = 0
## [snap] Output multiplier now (0 idle): sum(P_eff x od) / 250 W, x1.4 after upgrade 1, capped
## at 4.0; the Reserve flywheel holds the last m for 10 s, the Aqueduct drive gives idle weapons
## 0.25.
var m: float = 0.0
## Reserve flywheel: the m it holds and the seconds left of the hold.
var hold_m: float = 0.0
var hold_s: float = 0.0
## [snap] 0..1: the winding of the next shot (ballista, onager); the arrow organ: the reload of
## the next rack. It rises by dt x m / wind time, holds when unpowered, and fires at 1.
var wind: float = 0.0
## [snap] Current aim, degrees, atan2(dy, dx) from the pivot.
var yaw_deg: float = 0.0
## [snap] 0..1 animation phase: 0 just fired, rising to 1 at fully wound (it follows `wind`).
var arm: float = 0.0
## Arrow organ: the next rack to fire, 0..2 (0..3 with upgrade 3).
var rack: int = 0
## The enemy it aims at (0: none) and the seconds until it looks again.
var target_id: int = 0
var retarget_s: float = 0.0
## An enemy its last solve could not reach (left out of the next pick; 0: none).
var skip_id: int = 0
## The last flight time solved for (the lead's first guess, s).
var flight_s: float = 2.0
## Damage this wave (kept through the break that follows: Autopilot's upgrade pick), over the
## session, projectiles fired and projectiles that hit at least one enemy, kills.
var damage_wave: float = 0.0
var damage_total: float = 0.0
var shots: int = 0
var hits: int = 0
var kills: int = 0
