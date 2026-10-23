class_name SiegeShot
extends SiegeRecord
## One tower shot for visuals only (hits resolve on the fire tick; brief 2.4). The rules keep
## the shots of the last 0.1 s (two ticks) in SiegeState.shots, so every 10 Hz snapshot carries
## each shot exactly once (snapshot f: [[pad, [target ids]], ...]). G0 contract.

var pad: int = 0
## Enemy ids hit (a Caltrop throw: the lead enemy it aimed at).
var targets: Array[int] = []
## Seconds since it was fired (dropped once >= 0.1 s).
var age_s: float = 0.0
