class_name WorkoutHudCtl
extends HudArtControl
## Base of Workout's own HUD Controls. Each sits alone in a Rect2i of the HudSpec (`art_rect`, art px
## of the 960 x 540 base, WorkoutHud.LAYOUT); the HudLayer anchors that rect on the current art canvas
## and sizes the Control to it on screen. It draws in art px under a scale transform (u() screen px
## per art px, 2 at 1080p) with nearest filtering, so everything lands on the art grid. It ignores the
## mouse, refreshes every frame, gets the local rider's telemetry from the HudLayer (set_telemetry)
## and reads everything else from WorkoutGame.state. It only reads the state.

const D := preload("res://src/games/workout/hud/workout_hud_draw.gd")

var game: WorkoutGame = null
## What paint() shows, from the model (subclasses).
var m: Dictionary = {}


## Sets the game and the rect the spec places the Control in, names it after its class.
func setup(p_game: WorkoutGame, rect: Rect2i) -> WorkoutHudCtl:
	game = p_game
	place_at(rect)
	return self


func has_state() -> bool:
	return game != null and game.state != null


func st() -> WorkoutState:
	return game.state


## The rider this HUD shows (the local one, the first for a spectator); null with no riders.
func rider() -> WorkoutRiderState:
	return st().rider(game.view_peer())


## `key` translated, `{0}`.. filled from `args`.
func tx(key: String, args: Variant = []) -> String:
	return WorkoutHudModel.tx(game, key, args)
