class_name TankBossState
extends TankRecord
## The Behemoth (G0 contract; brief 2.4 Boss and Foundry Gate). Phase 1: while a bogie stands it
## creeps toward the tank at 2 px/s until 120 px away; each broken bogie pushes it back 24 px.
## Phase 2: immobile; shoot the turret. Main gun after a 6 s telegraph ("Surge to dodge").

## Auto-aim target ids of the parts: PART_ID_BASE + 0..2 bogies (rear to front), + 3 the turret.
const PART_ID_BASE := 1000
const TURRET_PART := 3

## [snap] TankIds.BOSS_*.
var phase: int = TankIds.BOSS_NONE
## [snap] World x of the hull's left edge in art px.
var x_px: float = 0.0
## [snap] HP per bogie (rear to front).
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
## The current telegraph's shot will miss (a dodge: the sprint rule held >= 3 s inside it).
var dodged: bool = false


func bogies_left() -> int:
	var n := 0
	for hp in bogie_hp:
		if hp > 0.0:
			n += 1
	return n
