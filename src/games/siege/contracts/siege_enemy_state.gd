class_name SiegeEnemyState
extends SiegeRecord
## One live enemy in SiegeState.enemies (spawn order). Enemies follow their road's polyline
## at a seeded lateral offset (+-1.5 m) and don't collide (brief 2.4). Combat (B1) moves it
## and keeps `pos` current; clients rebuild it from the snapshot (fields marked [snap]).
## G0 contract.

## [snap] Unique per session, ascending.
var id: int = 0
## [snap] SiegeIds.ENEMY_*.
var type: int = SiegeIds.ENEMY_RAIDERS
## [snap] SiegeIds.ROAD_* (0 West, 1 Valley, 2 East).
var road: int = 0
## [snap] Metres along the road from its spawn (snapshot: decimetres).
var prog_m: float = 0.0
## [snap] Lateral offset, metres left of travel (snapshot: decimetres).
var lat_m: float = 0.0
## [snap] Hit points now (snapshot: ceil).
var hp: float = 0.0
var max_hp: float = 0.0
## SiegeIds.EN_WALK, EN_BATTER (a ram at the gate) or EN_RETREAT (wave end).
var st: int = SiegeIds.EN_WALK
## EN_RETREAT: seconds left before it vanishes.
var retreat_s: float = 0.0
## Speed factor this tick from Caltrop zones (1 = free, 0.6 inside a zone).
var slow: float = 1.0
## Damage factor this tick from an upgraded Caltrop zone (1.25 inside, else 1).
var amp: float = 1.0
## Part of a ram push escort, a scattered ram crew, or a rush (rush kills pay double to riders
## in Overdrive).
var escort: bool = false
var crew: bool = false
var rush: bool = false
## World position on the ground plane (x, z): SiegeMap.point_at(road, prog_m, lat_m).
var pos: Vector2 = Vector2.ZERO


## Recomputes `pos` from road, prog_m and lat_m.
func place(map: SiegeMap) -> void:
	pos = map.point_at(road, prog_m, lat_m)
