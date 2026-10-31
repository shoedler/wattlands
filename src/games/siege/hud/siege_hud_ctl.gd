class_name SiegeHudCtl
extends HudArtControl
## Base of Castellum Rotae's own HUD Controls (docs/games/siege.md 3 "HUD"; the way TankHudCtl
## works). Each sits alone in a Rect2i of the HudSpec (`art_rect`, art px of the 960 x 540 base);
## the HudLayer sizes it on screen and it draws in art px under a scale transform (u() screen px
## per art px, 2 at 1080p) with nearest filtering, so everything lands on the art grid.
##
## It reads the state REFRESH_S apart, builds its `model` (a Dictionary, pure data the tests read)
## and redraws only when the model changed, so a plate costs nothing between its changes.
## It ignores the mouse, gets the local rider's telemetry from the HudLayer (set_telemetry), and
## only reads the state.

const REFRESH_S := 0.1
const D := preload("res://src/games/siege/hud/siege_hud_draw.gd")

var game: SiegeGame = null
## What it shows as of the last refresh ({} draws nothing).
var model: Dictionary = {}
var _since: float = REFRESH_S
var _signature: int = 0


## Sets the game and the rect the spec places the Control in, names it after its class.
func setup(p_game: SiegeGame, rect: Rect2i) -> SiegeHudCtl:
	game = p_game
	place_at(rect)
	return self


func _process(delta: float) -> void:
	_since += delta
	if _since >= REFRESH_S:
		_since = 0.0
		refresh()


## Rebuilds the model from the state and redraws if it changed. Tests call it directly.
func refresh() -> void:
	model = build() if has_state() else {}
	var sig := model.hash()
	if sig != _signature:
		_signature = sig
		queue_redraw()


## What the Control shows now (subclasses). Called only with a state.
func build() -> Dictionary:
	return {}


func _draw() -> void:
	draws += 1
	if model.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(u(), u()))
	paint()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func has_state() -> bool:
	return game != null and game.state != null


func st() -> SiegeState:
	return game.state


func own() -> SiegeRiderState:
	return SiegeHudModel.own_rider(game)
