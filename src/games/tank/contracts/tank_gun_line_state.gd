class_name TankGunLineState
extends TankRecord
## The current gun line (G0 contract; brief 2.4 Dig in): dug-in guns, a heavy duel, tank traps.
## The objective is done when every gun-line enemy has fallen; an overrun at max_s calls a
## support barrage that clears them (no kill credit).

## [snap] A gun line is the current segment.
var active: bool = false
## [snap] Gun-line enemies at the start (after enemy_scale) and still standing.
var guns_total: int = 0
var guns_left: int = 0
## [snap] The support barrage fell (overrun).
var barrage: bool = false
