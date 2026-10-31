class_name TankBossState
extends TankRecord
## The Behemoth (G0 contract; brief 2.4 Boss and Foundry Gate). Phase 1: while a bogie stands it
## creeps toward the tank at 2 px/s until 120 px away; each broken bogie pushes it back 24 px.
## Phase 2: immobile; shoot the turret. Main gun after a 6 s telegraph ("Surge to evade": a rider
## who can evade holds the sprint rule 3 s inside it, brief 2.4).
##
## Maximum HP: enemies.json boss.bogie_hp and boss.turret_hp x the tank's enemy_scale (brief 2.4:
## "HP and counts x 0.6 / 0.8 / 1.0" covers the Behemoth). bogie_max and turret_max are not in the
## snapshot: clients compute them the same way from content (TankContent.boss_def, enemy_scale).

## Auto-aim target ids of the parts are negative, so they never collide with TankState.take_id()
## (always > 0): bogies -1..-3 (rigs.json order: index 0 is the bogie nearest the tank, the lowest x in the
## boss_hull frame, as the Behemoth faces left; index 2 the farthest), the turret -4.
const PART_COUNT := 4
const TURRET_PART := 3

## [snap] TankIds.BOSS_*.
var phase: int = TankIds.BOSS_NONE
## [snap] World x of the hull's left edge in art px.
var x_px: float = 0.0
## [snap] HP per bogie (rigs.json order: index 0 nearest the tank, the first one the auto-aim takes).
var bogie_hp: Array[float] = [100.0, 100.0, 100.0]
## [snap]
var turret_hp: float = 300.0
var bogie_max: float = 100.0
var turret_max: float = 300.0
## Seconds to the next main-gun shot (the telegraph is its last 6 s).
var main_s: float = 0.0
## [snap] Seconds of the main-gun telegraph left; 0 none.
var telegraph_s: float = 0.0
## Seconds to the next secondary shot.
var secondary_s: float = 0.0
## The current telegraph's shot will miss (evaded: a rider held the sprint rule >= 3 s inside it).
var evaded: bool = false
## [snap] v4: range in metres to bogie 0.
var range_m: float = 0.0


## The target id of part `index` (0..2 bogies, index 0 nearest the tank, 3 the turret).
static func part_id(index: int) -> int:
	return -(index + 1)


## The part index of target id `id`, or -1 when `id` is not a boss part.
static func part_of(id: int) -> int:
	return -id - 1 if id < 0 and id >= -PART_COUNT else -1


static func is_part_id(id: int) -> bool:
	return part_of(id) >= 0


func bogies_left() -> int:
	var n := 0
	for hp in bogie_hp:
		if hp > 0.0:
			n += 1
	return n
