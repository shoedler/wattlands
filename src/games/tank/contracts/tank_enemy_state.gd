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
## [snap] Always +1 (v4: nothing comes from behind); kept for the snapshot's E_SIDE column.
var side: int = 1
## The held distance in art px from the hull's nearer end to the enemy's near edge.
var hold_px: float = 0.0
## Fixed in world space (gun lines) instead of keeping station with the tank.
var fixed: bool = false
## Part of the current gun line (its fall counts toward the gun line's objective).
var gun_line: bool = false
## Seconds to the next shot (a telegraph runs inside it for destroyers and heavies).
var gun_s: float = 0.0
## [snap] Seconds of a telegraph left (destroyer glint 4 s, heavy muzzle glow 3 s, a light tank's
## 2.5 s flank shot); 0 none. "Surge to evade" can make that shot miss (brief 2.4).
var telegraph_s: float = 0.0
## [snap] (v2) The depth lane it holds in (brief 2.4 Spacing; the view draws lanes): 0 the near
## lane on the road, 1 the far one behind it. Within a lane and side no two held positions overlap.
var lane: int = 0
## Heavy: damage taken since the last back-off.
var dmg_since_backoff: float = 0.0
## Light: weave phase in radians (an offset around hold_px).
var weave: float = 0.0
## The encounter index that spawned it (-1 for a gun line or the boss).
var encounter: int = -1
## [snap] v4: far kinds: range in metres from the hull's front to the enemy; 0 for a near kind.
var range_m: float = 0.0
## v4: far kinds: the range it is heading for or holds (host only).
var hold_m: float = 0.0
## v4: far kinds: d(range)/dt in m/s this tick (host only; the lead solver reads it).
var rate_mps: float = 0.0


## v4: a near kind (recon, tankette): x_px and the near frame; a far kind has range_m instead.
func is_near() -> bool:
	return TankIds.is_near_code(code)
