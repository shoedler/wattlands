class_name SiegeZoneState
extends SiegeRecord
## A Caltrop zone in SiegeState.zones: thrown at the lead enemy's predicted spot, it lands after
## 1.0 s and lasts 4 s: 40% slower, no damage, no stacking (+25% damage taken with upgrade 3).
## G0 contract. Snapshot z: [road, prog_dm, ttl_ms] with ttl_ms = (delay_s + ttl_s) x 1000, so
## a zone is landed while ttl_ms <= zone_s x 1000.

## [snap] Road and metres along it of the zone's centre.
var road: int = 0
var prog_m: float = 0.0
## Seconds until it lands (> 0: in flight, no effect yet).
var delay_s: float = 0.0
## Seconds it lasts once landed.
var ttl_s: float = 0.0
var radius_m: float = 6.0
## Speed factor inside (0.6) and damage factor inside (1.0, or 1.25 from upgrade 3).
var slow: float = 0.6
var amp: float = 1.0
## The pad that threw it.
var pad: int = 0
## Centre on the ground plane.
var pos: Vector2 = Vector2.ZERO


func landed() -> bool:
	return delay_s <= 0.0 and ttl_s > 0.0
