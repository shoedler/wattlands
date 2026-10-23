class_name FishingBoatView
extends Node2D
## One lane's boat and rig (brief 3.3, 3.5 layer 7), in boat-local art pixels (FishingRig): the
## shared boat sprite recoloured to the slot's colour with PaletteSwap (the red key ramp on trim
## and canopy), the bike, the angler (cap and shirt recoloured too), the crank as a SpinningPart
## driven by cadence, the reel as a SpinningPart driven by line speed (reversed on runs), the
## chain as a ScrollingChain loop between them, code-drawn legs solved hip to pedal, the rod
## bending with tension, the cosmetics (canopy pattern, hull trim, pennant) and the wake. The lane
## view sets position (sprite top-left), `flipped` (motoring home, bow left) and calls advance().

const WAKE_SCROLL_PX_PER_PX := 1.0
const LEG_NEAR := Color("#c98e63")
const LEG_FAR := Color("#9a6236")
const SHORTS := Color("#23305c")

var slot: int = 0
var look: Dictionary = {}
## Cosmetic values: "canopy" pattern id ("" plain), "trim" colour, "pennant" ("" slot shape).
var canopy_pattern: String = ""
var trim_color: Color = Color(0, 0, 0, 0)
var trophy_pennant: bool = false
var flipped: bool = false
## Rod tension 0..1 and the unit direction toward the line (boat-local).
var tension: float = 0.0
var pull_dir: Vector2 = Vector2.DOWN
## Wake: shown while moving, scrolled by `wake_x` (art px travelled).
var wake_on: bool = false
var wake_x: float = 0.0

var hull: Sprite2D = null
var bike: Sprite2D = null
var angler: Sprite2D = null
var crank: SpinningPart = null
var reel: SpinningPart = null
var chain: ScrollingChain = null
var _wake_layer: FishingDrawLayer = null
var _deco_layer: FishingDrawLayer = null
var _far_leg_layer: FishingDrawLayer = null
var _near_leg_layer: FishingDrawLayer = null
var _rod_layer: FishingDrawLayer = null


func _init() -> void:
	name = "Boat"
	_wake_layer = FishingDrawLayer.make("Wake", _paint_wake)
	add_child(_wake_layer)
	hull = _sprite("boat", Vector2.ZERO)
	_deco_layer = FishingDrawLayer.make("Deco", _paint_deco)
	add_child(_deco_layer)
	bike = _sprite("rig_bike", FishingRig.BIKE_POS)
	_far_leg_layer = FishingDrawLayer.make("FarLeg", _paint_far_leg)
	add_child(_far_leg_layer)
	chain = ScrollingChain.new()
	chain.name = "Chain"
	chain.auto_process = false
	chain.max_px_s = TAU * FishingRig.CRANK_SPROCKET_R * 2.0
	chain.pitch_px = 2.0
	chain.link_px = 1.0
	chain.color_a = FishingPalette.GREY_1
	chain.color_b = FishingPalette.GREY_4
	chain.set_loop(
		FishingRig.CRANK_HUB, FishingRig.CRANK_SPROCKET_R, FishingRig.REEL_HUB, FishingRig.REEL_R, 8
	)
	add_child(chain)
	crank = SpinningPart.new()
	crank.name = "Crank"
	crank.auto_process = false
	crank.max_rpm = 120.0
	crank.snap_steps = 16
	crank.texture = FishingSprites.texture("rig_crank")
	crank.position = FishingRig.CRANK_HUB
	add_child(crank)
	_near_leg_layer = FishingDrawLayer.make("NearLeg", _paint_near_leg)
	add_child(_near_leg_layer)
	angler = _sprite("rig_angler", FishingRig.ANGLER_POS)
	reel = SpinningPart.new()
	reel.name = "Reel"
	reel.auto_process = false
	reel.max_rpm = 240.0
	reel.snap_steps = 8
	reel.inertia_s = 0.2
	reel.texture = FishingSprites.texture("rig_reel")
	reel.position = FishingRig.REEL_HUB
	add_child(reel)
	_rod_layer = FishingDrawLayer.make("Rod", _paint_rod)
	add_child(_rod_layer)


## The slot's look (colour ramp on the key colours) and the equipped cosmetics.
func set_look(p_slot: int, p_look: Dictionary, cosmetics: Dictionary) -> void:
	slot = p_slot
	look = p_look
	PaletteSwap.apply_slot(hull, FishingPalette.keys(), slot)
	PaletteSwap.apply_slot(angler, FishingPalette.keys(), slot)
	canopy_pattern = str(cosmetics.get("canopy", ""))
	var trim := str(cosmetics.get("trim", ""))
	trim_color = FishingPalette.color_of(trim, Color(0, 0, 0, 0))
	trophy_pennant = str(cosmetics.get("pennant", "")) == "trophy"
	_deco_layer.queue_redraw()


## One frame: crank at `cadence` rpm, reel by `line_mps` (positive retrieving, negative line
## going out on a run), chain with the crank.
func advance(dt: float, cadence: float, line_mps: float) -> void:
	crank.drive(cadence, 120.0)
	crank.tick(dt)
	chain.drive(cadence, 120.0)
	chain.tick(dt)
	reel.drive(line_mps, 2.0)
	reel.tick(dt)
	scale.x = -1.0 if flipped else 1.0
	_far_leg_layer.queue_redraw()
	_near_leg_layer.queue_redraw()
	_rod_layer.queue_redraw()
	_wake_layer.queue_redraw()


## The rod's points in boat-local px.
func rod_points() -> PackedVector2Array:
	return FishingRig.rod(FishingRig.ROD_BASE, FishingRig.ROD_TIP, tension, pull_dir)


## The two legs [near, far], each [hip, knee, foot], from the crank's current angle.
func legs() -> Array[PackedVector2Array]:
	var p := FishingRig.pedals(FishingRig.CRANK_HUB, FishingRig.CRANK_R, crank.angle())
	return [FishingRig.leg(FishingRig.HIP, p[0]), FishingRig.leg(FishingRig.HIP, p[1])]


func _sprite(id: String, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = id
	s.centered = false
	s.texture = FishingSprites.texture(id)
	s.position = pos
	add_child(s)
	return s


func _paint_wake(c: CanvasItem) -> void:
	if not wake_on:
		return
	var tex := FishingSprites.texture("wake")
	var w := float(tex.get_width())
	var off := fposmod(wake_x * WAKE_SCROLL_PX_PER_PX, w)
	var y := FishingRig.STERN.y
	var x := -off
	while x > -3.0 * w:
		c.draw_texture(tex, Vector2(roundf(x - w), y))
		x -= w
	c.draw_texture(tex, Vector2(roundf(-off), y))


func _paint_deco(c: CanvasItem) -> void:
	var r := FishingRig.CANOPY_RECT
	var light := Color(FishingPalette.WHITE, 0.55)
	match canopy_pattern:
		"stripes":
			for x in range(r.position.x, r.end.x, 4):
				c.draw_rect(Rect2(x, r.position.y, 2, r.size.y), light)
		"dots":
			for x in range(r.position.x + 1, r.end.x, 3):
				c.draw_rect(Rect2(x, r.position.y + (x % 2), 1, 1), light)
		"waves":
			for x in range(r.position.x, r.end.x):
				var yy := r.position.y + 1 + roundi(sin(float(x) * 0.8))
				c.draw_rect(Rect2(x, yy, 1, 1), light)
	if trim_color.a > 0.0:
		c.draw_rect(Rect2(8, FishingRig.TRIM_Y, 64, 1), trim_color)
	var m := FishingRig.PENNANT_AT
	c.draw_line(m, Vector2(m.x, FishingRig.CANOPY_RECT.position.y), FishingPalette.GREY_3, 1.0)
	var col: Color = look.get("color", Wl.slot_look(slot)["color"])
	if trophy_pennant:
		var fish := PackedVector2Array(
			[
				m + Vector2(1, 0),
				m + Vector2(6, 1),
				m + Vector2(4, 2),
				m + Vector2(6, 3),
				m + Vector2(1, 2)
			]
		)
		c.draw_colored_polygon(fish, FishingPalette.GOLD)
		c.draw_rect(Rect2(m + Vector2(2, 1), Vector2(1, 1)), FishingPalette.NAVY)
		return
	var flag := FishingView.shape_points(
		str(look.get("shape", "circle")), m + Vector2(3.5, 1.5), 2.5
	)
	c.draw_colored_polygon(flag, col)
	flag.append(flag[0])
	c.draw_polyline(flag, FishingPalette.NAVY, 1.0)


func _paint_far_leg(c: CanvasItem) -> void:
	_paint_leg(c, legs()[1], LEG_FAR)


func _paint_near_leg(c: CanvasItem) -> void:
	_paint_leg(c, legs()[0], LEG_NEAR)


func _paint_leg(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	c.draw_line(pts[0], pts[1], SHORTS, 2.0)
	c.draw_line(pts[1], pts[2], col, 2.0)
	c.draw_rect(Rect2(pts[2] - Vector2(1, 0), Vector2(2, 1)), FishingPalette.NAVY)


func _paint_rod(c: CanvasItem) -> void:
	var pts := FishingRig.snapped(rod_points())
	c.draw_polyline(pts.slice(0, 3), FishingPalette.NAVY, 2.0)
	c.draw_polyline(pts.slice(2), FishingPalette.GREY_4, 1.0)
	c.draw_rect(Rect2(pts[pts.size() - 1] - Vector2(0.5, 0.5), Vector2(1, 1)), FishingPalette.GOLD)
