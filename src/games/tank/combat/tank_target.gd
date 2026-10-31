class_name TankTarget
extends RefCounted
## One thing the main gun can hit this tick (brief 2.4 Gun): an enemy tank (its hit box), a part
## of the Behemoth, or an obstacle. Built by TankTargets.build, read by the auto-aim and by the
## shell collisions. Owner: rules (combat).

const KIND_ENEMY := 0
const KIND_BOSS := 1
const KIND_OBSTACLE := 2

## Auto-aim tiers, lower first: a destroyer in its telegraph, a Behemoth's bogie, heavy, medium (or a
## destroyer not telegraphing), light, obstacle, the depot's drill wrecks.
const TIER_TELEGRAPH := 0
const TIER_BOGIE := 1
const TIER_HEAVY := 2
const TIER_MEDIUM := 3
const TIER_LIGHT := 4
const TIER_OBSTACLE := 5
const TIER_DRILL := 6

## The entity id (enemies and obstacles > 0, boss parts < 0; TankBossState.part_id).
var id: int = 0
var kind: int = KIND_ENEMY
var tier: int = TIER_LIGHT
## The hit box in world art px.
var rect: Rect2 = Rect2()
## World velocity in px/s (enemies keep station, so mostly the hull's own).
var vel: Vector2 = Vector2.ZERO
var enemy: TankEnemyState = null
var obstacle: TankObstacleState = null
## Boss part index (0..2 bogies, 3 the turret), -1 otherwise.
var part: int = -1
## Shells pass through it harmlessly and it never counts toward the score (a drill wreck).
var drill: bool = false
## v4: stands in the far frame (range_m, hit_half_m; its rect is empty).
var far: bool = false
## v4: a near threat (recon, tankette); the bow guns' target, never the main gun's.
var near: bool = false
## v4: far targets: metres from the hull's front, the rate it changes at, half its hit window.
var range_m: float = 0.0
var rate_mps: float = 0.0
var hit_half_m: float = 0.0


## The point the gun aims at: the box centre.
func center() -> Vector2:
	return rect.get_center()


## v4: what target lists sort on: range_m when far (its rect is empty), else the box centre's x.
func sort_key() -> float:
	return range_m if far else center().x
