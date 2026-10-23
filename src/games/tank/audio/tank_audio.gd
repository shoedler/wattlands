class_name TankAudio
extends Node
## Synthesized sound (brief 3 Audio; Sfx.synth, no downloads): diesel rumble by cadence, dynamo
## whine, steam chuff and latch hiss, cannon boom, shell whistle, brass casings, explosions, track
## clank, lever clunk, hoist ratchet; the local station loudest. Owner: view. It only reads state
## and the module's events; silent and error-free headless.
##
## TankView creates it as a child and connects TankGame.cue to on_cue (the module never creates
## it). G0 stub: plays nothing. G1 (view) fills it, keeping these entry points.

var game: TankGame = null


## Every game event (TankGame.cue: the host where it sends it, clients in apply_event).
func on_cue(_kind: String, _data: Dictionary) -> void:
	pass
