class_name SiegeSpawn
extends SiegeRecord
## A queued body in SiegeState.queue: spawns past the 150-enemy cap wait here (snapshot q is the
## queue's length); the queue is dropped at wave end.

var type: int = SiegeIds.ENEMY_SPEAR
## Metres along the path it enters at (a staging ground, less its place in the formation).
var prog_m: float = 0.0
## Lateral offset (m, left of travel): its file in the formation.
var lat_m: float = 0.0
## Fraction of the type's HP (the warm-up ram: 0.5).
var hp_frac: float = 1.0
var escort: bool = false
var crew: bool = false
var rush: bool = false
## A siege engine: its spawn raises the `push` event.
var push: bool = false
