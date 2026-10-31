class_name SiegeHudCtl
extends Control
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
## The rect the spec places it in (art px of the base).
var art_rect: Rect2i = Rect2i(0, 0, 960, 540)
## The local rider's latest telemetry (null until the HUD sends one; the rider state stands in).
var tm: Telemetry = null
## What it shows as of the last refresh ({} draws nothing).
var model: Dictionary = {}
## How many times _draw ran (tests).
var draws: int = 0
var _since: float = REFRESH_S
var _signature: int = 0
var _layer: HudLayer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = false


## Sets the game and the rect the spec places the Control in, names it after its class.
func setup(p_game: SiegeGame, rect: Rect2i) -> SiegeHudCtl:
	game = p_game
	art_rect = rect
	var s: Variant = get_script()
	if s is Script:
		name = (s as Script).get_global_name()
	return self


## The HudLayer's per-tick local telemetry.
func set_telemetry(t: Telemetry) -> void:
	tm = t


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


## Screen px per art px (2 at 1080p).
func u() -> float:
	if size.x <= 0.0 or art_rect.size.x <= 0:
		return 2.0
	return size.x / float(art_rect.size.x)


func _draw() -> void:
	draws += 1
	if model.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(u(), u()))
	paint()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws in art px of art_rect (subclasses).
func paint() -> void:
	pass


func has_state() -> bool:
	return game != null and game.state != null


func st() -> SiegeState:
	return game.state


func own() -> SiegeRiderState:
	return SiegeHudModel.own_rider(game)


## The HudLayer this Control sits in (null without one).
func hud_layer() -> HudLayer:
	if _layer == null or not is_instance_valid(_layer):
		_layer = null
		var p := get_parent()
		while p != null and not p is HudLayer:
			p = p.get_parent()
		_layer = p as HudLayer
	return _layer
