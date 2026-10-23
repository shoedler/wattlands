class_name TankAudio
extends Node
## Synthesized sound (brief 3 Audio; Sfx.synth, no downloads): diesel rumble by cadence, dynamo
## whine, steam chuff and latch hiss, cannon boom, shell whistle, brass casings, explosions, track
## clank, lever clunk, hoist ratchet; the local station loudest. Owner: view. It only reads state
## and the module's events; silent and error-free headless.
##
## G0 stub: plays nothing. G1 (view) fills it, keeping these entry points.

var game: TankGame = null


## Called by the module for every event (host where it sends it, clients in apply_event).
func on_event(_event: Dictionary) -> void:
	pass
