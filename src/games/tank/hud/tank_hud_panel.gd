class_name TankHudPanel
extends Control
## Base of the Tank Controls (station card, objective line, boss bars): a Control that reads
## TankGame.state each frame, recomputes its model (TankHudModel) and redraws only when the model
## changed. Layout is designed at 1080p pixels for the rect's own size (`design_size`) and scales
## with the control, so key numbers stay >= 48 px at 1080p (WlTheme.KEY_NUMBER_MIN_PX). Text uses
## the kit theme font with the kit's dark outline; colours come from WlTheme and always pair with
## a shape or text. Never changes state.

## The size the layout was designed for (1080p px); the control scales by size / design_size.
var design_size: Vector2 = Vector2(696, 168)
var game: TankGame = null
## The latest model and how many times it changed (a redraw each; tests read both).
var model: Dictionary = {}
var model_changes: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = WlTheme.get_theme()


func _process(_delta: float) -> void:
	refresh()


## Recomputes the model; redraws when it changed.
func refresh() -> void:
	if game == null or game.state == null:
		return
	var m := compute(game.state)
	if m != model:
		model = m
		model_changes += 1
		queue_redraw()


## The model for `state` (subclasses).
func compute(_state: TankState) -> Dictionary:
	return {}


## Layout scale: 1.0 at the design size.
func k() -> float:
	return (
		minf(size.x / design_size.x, size.y / design_size.y)
		if size.x > 8.0 and size.y > 8.0
		else 1.0
	)


## Local peer of the game (0 without one).
func local_peer() -> int:
	return game.ctx.local_peer if game != null and game.ctx != null else 0


# --- Drawing helpers ------------------------------------------------------------------------------


func _font() -> Font:
	return get_theme_default_font()


## Draws `s` with its top-left corner at `at` (design px), `px` design font px, in the kit style.
func text(
	at: Vector2,
	s: String,
	px: float,
	color: Color = WlTheme.TEXT,
	width: float = -1.0,
	align: int = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	var f := _font()
	var kk := k()
	var fs := maxi(8, roundi(px * kk))
	var base := Vector2(at.x * kk, at.y * kk + f.get_ascent(fs))
	var w := width * kk if width > 0.0 else -1.0
	var outline := maxi(2, roundi(float(WlTheme.OUTLINE_PX) * float(fs) / 64.0))
	draw_string_outline(f, base, s, align, w, fs, outline, WlTheme.OUTLINE)
	draw_string(f, base, s, align, w, fs, color)


## The width of `s` at design font px `px`, in design px.
func text_width(s: String, px: float) -> float:
	var kk := k()
	return (
		_font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, roundi(px * kk))).x / kk
	)


## A rect in design px.
func rect(r: Rect2, color: Color) -> void:
	draw_rect(_scaled(r), color)


func frame(r: Rect2, color: Color, width: float = 2.0) -> void:
	draw_rect(_scaled(r), color, false, maxf(1.0, width * k()))


## A bar: background, fill `frac` of the width, a border.
func bar(r: Rect2, frac: float, fill: Color) -> void:
	rect(r, WlTheme.BAR_BG)
	var w := r.size.x * clampf(frac, 0.0, 1.0)
	if w > 0.0:
		rect(Rect2(r.position, Vector2(w, r.size.y)), fill)
	frame(r, WlTheme.PANEL_BORDER, 2.0)


func line(a: Vector2, b: Vector2, color: Color, width: float = 3.0) -> void:
	draw_line(a * k(), b * k(), color, maxf(1.0, width * k()))


func polygon(points: PackedVector2Array, color: Color) -> void:
	var p := PackedVector2Array()
	for v in points:
		p.append(v * k())
	draw_colored_polygon(p, color)


## The dark panel behind a Tank Control, like the kit widgets'.
func panel() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.055, 0.067, 0.086, 0.74))
	draw_rect(r, Color(0.227, 0.271, 0.322, 0.9), false, 2.0)


## Translated text for a strings key with {0} style args.
static func tr_key(key: String, args: Array = []) -> String:
	var s := String(TranslationServer.translate(key))
	return s.format(args) if not args.is_empty() else s


func _scaled(r: Rect2) -> Rect2:
	var kk := k()
	return Rect2(r.position * kk, r.size * kk)
