class_name TankShellState
extends TankRecord
## One projectile in flight (G0 contract; brief 2.4 Gun). Friendly shells fly from the muzzle
## anchor in assets/tank/rigs.json; enemy shells roll their hit with the session RNG at fire time
## and land on the tank or 20-40 px off. Positions in world art px, y down, GROUND_Y the ground.

## [snap]
var id: int = 0
## [snap] TankIds.SHELL_*.
var type: int = TankIds.SHELL_NONE
## [snap] World position and velocity (art px, art px/s).
var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
## [snap] True for the crew's shells.
var friendly: bool = true
## The aimed target's id (0 none).
var target_id: int = 0
## Damage on a direct hit (after the shell type; target multipliers apply on impact).
var damage: float = 0.0
## Enemy shells: the roll at fire time (true hits the tank).
var will_hit: bool = false
## The firing enemy's id (enemy shells) or the slot whose station fired (friendly).
var source: int = 0
