class_name TankRoomInput
extends RefCounted
## What one engine room is fed each frame: the rider's watts and cadence (live for the local rider,
## interpolated for the others), the in-band and reserve flags and the rider's look. The room turns
## these into machinery speed (cadence / 120), brightness (%FTP), glow and exhaust.

## Raw watts and cadence of the rider on this station (a reserve room: 60 W, 45 rpm).
var watts: float = 0.0
var cadence: float = 0.0
## Watts as a fraction of the rider's FTP (1.0 = FTP).
var frac: float = 0.0
var in_band: bool = false
var reserve: bool = false
var unpowered: bool = false
var slot: int = -1
## The local rider works this station.
var own: bool = false
## {"color", "shape", "pattern", "hollow"}
var look: Dictionary = {}


## The machinery drive signal 0 .. 1 (cadence / 120), 0 when the room has no power.
func speed() -> float:
	return 0.0 if unpowered else clampf(cadence / 120.0, 0.0, 1.0)


## Room brightness 0.4 .. 1: dark when idle, brighter with %FTP, full in band.
func brightness() -> float:
	var b := 0.42 + 0.4 * clampf(frac / 1.1, 0.0, 1.0)
	if in_band:
		b += 0.18
	if reserve or unpowered:
		b = minf(b, 0.5)
	return clampf(b, 0.3, 1.0)
