class_name SiegeTowerState
extends SiegeRecord
## One pad in SiegeState.pads (index pad - 1), empty while type is SiegeIds.TOWER_NONE.
## Written by the rules/combat (B1); [snap] fields come back on clients. G0 contract.

## [snap] Pad 1..8.
var pad: int = 1
## [snap] SiegeIds.TOWER_* (0 = empty marble plinth).
var type: int = SiegeIds.TOWER_NONE
## [snap] Upgrades bought, 0..3 (1: +40% output, 2: +25% range, 3: the special).
var level: int = 0
## [snap] Output multiplier m now (0 = idle): sum(P_eff x od) / 250 W, x1.4 after upgrade 1,
## capped at 4.0; Reserve flywheel holds the last m for 10 s, Aqueduct drive gives 0.25.
var m: float = 0.0
## Reserve flywheel: the m it holds and the seconds left of the hold.
var hold_m: float = 0.0
var hold_s: float = 0.0
## [snap] Seconds at m = 1 until the next shot (decreases by dt x m; fires at <= 0).
var cd_s: float = 0.0
## Seconds since it was built (the view scales a new tower up over 1 s; large = long ago).
var age_s: float = 1000.0
## Slot that built it (-1: a starting tower).
var built_by: int = -1
var kills: int = 0
var damage: float = 0.0


func built() -> bool:
	return type != SiegeIds.TOWER_NONE
