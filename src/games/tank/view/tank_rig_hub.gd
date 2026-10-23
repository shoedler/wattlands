class_name TankRigHub
extends RefCounted
## What a tank rig and its rooms need from the view: the effects, the lights, the cosmetic RNG and
## each slot's look. A small bag so the rig classes never reach into TankView (and tests can build
## a rig with a hub of their own).

var fx: TankFx = null
var lights: TankLights = null
## slot index -> {"color": Color, "shape": String, "pattern": String, "hollow": bool}
var looks: Dictionary = {}
## The local rider's peer (their own station is loudest and, on a client, runs from prediction).
var local_peer: int = 0
## Offset of the rig's hull frame on screen, set by the rig each frame (layer coordinates).
var origin: Vector2 = Vector2.ZERO


## The look of `slot` (the session's slot look when unknown).
func look(slot: int) -> Dictionary:
	if looks.has(slot):
		return looks[slot]
	return Wl.slot_look(maxi(slot, 0))


## A hull-frame point in layer coordinates.
func to_layer(p: Vector2) -> Vector2:
	return origin + p
