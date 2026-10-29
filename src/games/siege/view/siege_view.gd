class_name SiegeView
extends Node2D
## Castellum Rotae's 2D view (docs/games/siege.md 3 "View"), drawn in the platform's
## PixelViewport at 960 x 540 art pixels. This is the rules builder's placeholder: the view
## builder replaces it with the baked world, the depth-tested sprites and the shot replay. It
## only reads the state (contracts/STATE_V2.md) and listens to SiegeGame.cue.

var game: SiegeGame = null
var state: SiegeState = null
var path: SiegePath = null


func bind(p_state: SiegeState, p_path: SiegePath) -> void:
	state = p_state
	path = p_path
