class_name SiegeEnemyState
extends SiegeRecord
## One live enemy body in SiegeState.enemies (spawn order). Every body follows the one path at
## its own seeded lateral offset (+-1.8 m) and bodies don't collide (brief 2.4). Combat moves it
## and keeps `pos` current; clients rebuild it from the snapshot (fields marked [snap]).

## [snap] Unique per session, ascending.
var id: int = 0
## [snap] SiegeIds.ENEMY_*.
var type: int = SiegeIds.ENEMY_SPEAR
## [snap] Metres along the path from the camp (snapshot: decimetres).
var prog_m: float = 0.0
## [snap] Lateral offset, metres left of travel (snapshot: decimetres).
var lat_m: float = 0.0
## [snap] Hit points now (snapshot: ceil).
var hp: float = 0.0
var max_hp: float = 0.0
## [snap] SiegeIds.EN_WALK, EN_BATTER (a ram at the gate), EN_RETREAT (wave end) or EN_DOCKED
## (a siege tower at the moat edge).
var st: int = SiegeIds.EN_WALK
## Current speed along the path (m/s), the bridge coat included.
var speed_mps: float = 0.0
## Chariots: the drawn speed it accelerates toward (m/s, before the coat) and the seconds until
## the next draw.
var want_mps: float = 0.0
var redraw_s: float = 0.0
## EN_RETREAT: seconds left before it vanishes. EN_BATTER: battering damage not yet reported as
## a whole-HP leak event.
var retreat_s: float = 0.0
## Part of an engine's escort, a scattered ram crew, or a rush (rush kills pay double to riders
## in Overdrive).
var escort: bool = false
var crew: bool = false
var rush: bool = false
## A siege engine (ram or tower) that has reached the gate or docked (T4: not stopped in time).
var reached: bool = false
## World position (path.point_at(prog_m, lat_m)), kept current by the rules and place().
var pos: Vector3 = Vector3.ZERO
## The path segment pos was last placed on: a walker rarely leaves it, so place() looks there first.
var seg: int = 0


## Recomputes `pos` from prog_m and lat_m.
func place(path: SiegePath) -> void:
	var cum := path.cum
	var last := cum.size() - 2
	if last < 0:
		pos = path.point_at(prog_m, lat_m)
		return
	var p := clampf(prog_m, 0.0, path.length_m)
	var i := seg
	if i > last or cum[i] > p or (i < last and p >= cum[i + 1]):
		i = path.segment_at(p)
		seg = i
	var at := path.points[i].lerp(
		path.points[i + 1], (p - cum[i]) / maxf(cum[i + 1] - cum[i], 0.0001)
	)
	if lat_m != 0.0:
		var d := path.seg_dir[i]
		at += Vector3(d.y, -d.x, 0.0) * lat_m
	pos = at


func alive() -> bool:
	return hp > 0.0 and st != SiegeIds.EN_RETREAT
