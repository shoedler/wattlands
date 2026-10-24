class_name TankEnemyState
extends TankRecord
## One enemy tank (G0 contract; brief 2.4 Enemies). The Behemoth is TankBossState, not this.

## [snap] Unique per session, never reused (TankState.next_id).
var id: int = 0
## [snap] TankIds.ENEMY_CODES value.
var code: int = 0
## [snap] World x of the enemy's left edge in art px.
var x_px: float = 0.0
## Sprite size (enemies.json size_px).
var w: int = 0
var h: int = 0
## [snap] Hit points left (after the tank's enemy_scale).
var hp: float = 0.0
var hp_max: float = 0.0
## [snap] TankIds.EM_*.
var mode: int = TankIds.EM_ENTER
## [snap] +1 ahead of the tank, -1 behind it.
var side: int = 1
## The held distance in art px from the hull's nearer end to the enemy's near edge.
var hold_px: float = 0.0
## Fixed in world space (gun lines) instead of keeping station with the tank.
var fixed: bool = false
## Part of the current gun line (its fall counts toward the gun line's objective).
var gun_line: bool = false
## Seconds to the next shot (a telegraph runs inside it for destroyers and heavies).
var gun_s: float = 0.0
## [snap] Seconds of a telegraph left (destroyer glint, heavy muzzle glow); 0 none.
var telegraph_s: float = 0.0
## Heavy: damage taken since the last back-off.
var dmg_since_backoff: float = 0.0
## Light: weave phase in radians (an offset around hold_px).
var weave: float = 0.0
## The encounter index that spawned it (-1 for a gun line or the boss).
var encounter: int = -1
