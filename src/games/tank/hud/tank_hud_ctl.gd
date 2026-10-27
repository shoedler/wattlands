class_name TankHudCtl
extends Control
## Base of Diesel Domestiques' own HUD Controls (brief 3.6; the way Turbo Reel's FishingHudControl
## works). Each sits alone in a Rect2i of the HudSpec (`art_rect`, art px of the 960 x 540 base,
## TankHud.LAYOUT); the HudLayer anchors that rect on the current art canvas
## (PixelViewport.anchor_art_rect) and sizes the Control to it on screen. It draws in art px under
## a scale transform (u() screen px per art px, 2 at 1080p) with nearest filtering, so everything
## lands on the art grid. It ignores the mouse, refreshes every frame, gets the local rider's
## telemetry from the HudLayer (set_telemetry) and reads everything else from TankGame.state. It
## only reads the state.

const D := preload("res://src/games/tank/hud/tank_hud_draw.gd")

var game: TankGame = null
## The rect the spec places it in (art px of the 960 x 540 base).
var art_rect: Rect2i = Rect2i(0, 0, TankHud.BASE.x, TankHud.BASE.y)
## The local rider's latest telemetry (null until the HUD sends one; the rider state stands in).
var tm: Telemetry = null
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
func setup(p_game: TankGame, rect: Rect2i) -> TankHudCtl:
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
	tick(delta)
	if has_state():
		refresh()
	queue_redraw()


## Wall-clock animation (the crew row's engines); tests call it directly.
func tick(_delta: float) -> void:
	pass


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


func st() -> TankState:
	return game.state


func local_peer() -> int:
	return game.ctx.local_peer if game != null and game.ctx != null else 0


## The local rider (the first rider when the local peer has none, e.g. a spectator).
func local_rider() -> TankRiderState:
	var r := st().rider(local_peer())
	if r == null and not st().riders.is_empty():
		r = st().riders[0]
	return r


## The HudLayer this Control sits in (null without one).
func hud_layer() -> HudLayer:
	if _layer == null or not is_instance_valid(_layer):
		_layer = null
		var p := get_parent()
		while p != null and not p is HudLayer:
			p = p.get_parent()
		_layer = p as HudLayer
	return _layer


## The art canvas the HUD lays out on (the HudLayer's flex size; the 960 x 540 base without one).
func canvas() -> Vector2i:
	var hl := hud_layer()
	if hl != null:
		var a := hl.art_size()
		if a.x > 0 and a.y > 0:
			return a
	return TankHud.BASE


## Where this Control's rect sits on the canvas (anchored like the HUD does).
func canvas_rect() -> Rect2i:
	return TankHud.anchored(art_rect, canvas())


## `key` translated, `{0}`.. filled from `args`.
func tx(key: String, args: Array = []) -> String:
	return TankHud.tx(game, key, args)


func rider_name(r: TankRiderState) -> String:
	if game != null and game.ctx != null:
		var p := game.ctx.player(r.peer)
		if p != null and p.name != "":
			return p.name
	return "Rider %d" % (r.slot + 1)


static func slot_color(slot: int) -> Color:
	return Wl.SLOT_COLORS[posmod(slot, Wl.SLOT_COLORS.size())]
