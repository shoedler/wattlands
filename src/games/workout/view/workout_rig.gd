class_name WorkoutRig
extends RefCounted
## The rider rig's numbers the view and the HUD share with the art (src/games/workout/art/rig.mjs).

## Baked rider frames per crank revolution; frame 0 has the near pedal on top.
const CRANK_FRAMES := 24


## The rider sheet's frame for `revs` crank revolutions.
static func crank_frame(revs: float) -> int:
	return floori(fposmod(revs, 1.0) * CRANK_FRAMES)
