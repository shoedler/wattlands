class_name SiegePadState
extends SiegeRecord
## One of the four pads in SiegeState.pads (index pad - 1, STATE_V2.md): a crew-wound weapon
## that fires on its own (the Scorpion), or an empty plinth. [snap] fields come back on clients.

## [snap] Pad 1..4.
var pad: int = 1
## [snap] SiegeIds.PAD_* (0 = empty).
var type: int = SiegeIds.PAD_NONE
## [snap] Upgrades bought, 0..3 (1: +40% rate, 2: +25% range, 3: a second bolt per shot).
var level: int = 0
## [snap] Seconds until it may shoot again (fires at <= 0).
var cd_s: float = 0.0
## [snap] Current aim (deg, atan2(dy, dx)).
var yaw_deg: float = 90.0
## Slot that built it (-1: a starting pad).
var built_by: int = -1
var shots: int = 0
var hits: int = 0
var kills: int = 0
var damage: float = 0.0


func built() -> bool:
	return type != SiegeIds.PAD_NONE
