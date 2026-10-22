class_name SiegeSpawn
extends SiegeRecord
## A queued spawn in SiegeState.queue: spawns past the 150-enemy cap wait here (snapshot q is
## the queue's length); the queue is dropped at wave end. G0 contract.

var type: int = SiegeIds.ENEMY_RAIDERS
var road: int = 0
## Metres along the road it enters at (0 = the off-screen spawn; a ram push: length - 40).
var prog_m: float = 0.0
## Fraction of the type's HP (the warm-up ram: 0.5).
var hp_frac: float = 1.0
var escort: bool = false
var crew: bool = false
var rush: bool = false
