class_name TankObstacleState
extends TankRecord
## An obstacle or prop fixed in world space (G0 contract): wire, a wreck barricade, the depot's
## drill wrecks, a gun line's tank traps. Wire and wrecks stop the tank until a heavy shell,
## three light shells or 4 s of bow-gun fire within range clears them (brief 2.4).

## [snap]
var id: int = 0
## [snap] TankIds.OBSTACLE_CODES value.
var code: int = 0
## [snap] World x of the left edge in art px.
var x_px: float = 0.0
var w: int = 64
## [snap] Light-shell hits taken (3 clear it).
var light_hits: int = 0
## (v2) Seconds of bow-gun fire it has taken (tanks.json bow.clear_s, 4 s, clears it).
var bow_s: float = 0.0
## [snap]
var cleared: bool = false
