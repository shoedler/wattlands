class_name WorkoutHudCtl
extends Control
## Base of Workout's own HUD Controls. Each sits alone in a Rect2i of the HudSpec (`art_rect`, art px
## of the 960 x 540 base, WorkoutHud.LAYOUT); the HudLayer anchors that rect on the current art canvas
## and sizes the Control to it on screen. It draws in art px under a scale transform (u() screen px
## per art px, 2 at 1080p) with nearest filtering, so everything lands on the art grid. It ignores the
## mouse, refreshes every frame, gets the local rider's telemetry from the HudLayer (set_telemetry)
## and reads everything else from WorkoutGame.state. It only reads the state.

const D := preload("res://src/games/workout/hud/workout_hud_draw.gd")

var game: WorkoutGame = null
## The rect the spec places it in (art px of the 960 x 540 base).
var art_rect: Rect2i = Rect2i(0, 0, 960, 540)
## The local rider's latest telemetry (null until the HUD sends one).
var tm: Telemetry = null
## What paint() shows, from the model (subclasses).
var m: Dictionary = {}
## How many times _draw ran (tests).
var draws: int = 0
var _layer: HudLayer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = false


## Sets the game and the rect the spec places the Control in, names it after its class.
func setup(p_game: WorkoutGame, rect: Rect2i) -> WorkoutHudCtl:
	game = p_game
	art_rect = rect
	var s: Variant = get_script()
	if s is Script:
		name = (s as Script).get_global_name()
	return self


## The HudLayer's per-tick local telemetry.
func set_telemetry(t: Telemetry) -> void:
	tm = t


func _process(_delta: float) -> void:
	if has_state():
		refresh()
	queue_redraw()


## Recomputes what the Control shows from the state (subclasses).
func refresh() -> void:
	pass


## Screen px per art px (2 at 1080p).
func u() -> float:
	if size.x <= 0.0 or art_rect.size.x <= 0:
		return 2.0
	return size.x / float(art_rect.size.x)


func _draw() -> void:
	draws += 1
	if not has_state():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(u(), u()))
	paint()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws in art px of art_rect (subclasses).
func paint() -> void:
	pass


func has_state() -> bool:
	return game != null and game.state != null


func st() -> WorkoutState:
	return game.state


## The rider this HUD shows (the local one, the first for a spectator); null with no riders.
func rider() -> WorkoutRiderState:
	return st().rider(game.view_peer())


## The HudLayer this Control sits in (null without one, as in unit tests and render_frames).
func hud_layer() -> HudLayer:
	if _layer == null or not is_instance_valid(_layer):
		_layer = null
		var p := get_parent()
		while p != null and not p is HudLayer:
			p = p.get_parent()
		_layer = p as HudLayer
	return _layer


## `key` translated, `{0}`.. filled from `args`.
func tx(key: String, args: Variant = []) -> String:
	return WorkoutHudModel.tx(game, key, args)
