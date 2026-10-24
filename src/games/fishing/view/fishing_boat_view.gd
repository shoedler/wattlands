class_name FishingBoatView
extends Node2D
## One rider's boat (FishingRig's points, boat-local art px): the hull with its brass long-tail
## (stripe in the slot colour by PaletteSwap), the gear train, flywheel, winch drum and screw prop
## as frame-animated sprites, the chain (ScrollingChain), legs solved hip to pedal, the rider (cap
## and jersey in the slot colour), arms to the tiller or the winch brake, the clutch lever, the
## rod (stowed or raised, bending toward the line) and the slot-coloured pennant. The view sets
## position (the stern's waterline point on the surface), the shown values and calls advance().
## Driving vs fishing (`fishing` eased 0..1): the clutch flips aft, the prop spins down while the
## winch drum turns, the rod tips up, the hands move from the tiller to the winch brake.

## The boat pivots (bob and pitch) round the hull's waterline midpoint.
const PIVOT := Vector2(58, FishingRig.WATERLINE)
const FISHING_EASE_S := 0.6
## Prop and flywheel frame rates at full cadence (frames per second at 90 rpm).
const PROP_FPS_FULL := 14.0
const FLY_FPS_PER_RPM := 0.12
const WINCH_FPS_PER_MPS := 6.0
const FAR_SHADER := "res://src/games/fishing/view/fishing_far_boat.gdshader"
## How far toward the sky a boat on the farther row is tinted.
const FAR_HAZE := 0.22

static var _far_shader: Shader = null

var slot: int = 0
var look: Dictionary = {}
var line_color: Color = FishingPalette.LINE
## Shown values (the view writes them every frame).
var heading: int = 1
var pitch_deg: float = 0.0
var bob_px: float = 0.0
var cadence: float = 0.0
## 0 driving .. 1 fishing (eased toward `fishing_target`).
var fishing: float = 0.0
var fishing_target: float = 0.0
## Prop drive 0..1 (throttle while the clutch drives the prop) and the winch's line speed (m/s).
var prop_drive: float = 0.0
var winch_mps: float = 0.0
## Rod tension 0..1 and the unit direction toward the line (boat-local, before the flip).
var tension: float = 0.0
var pull_dir: Vector2 = Vector2.DOWN

## True on the farther row (another rider's boat): see set_far().
var far: bool = false
var body: Node2D = null
var hull: Sprite2D = null
var gears: Sprite2D = null
var flywheel: Sprite2D = null
var winch: Sprite2D = null
var prop: Sprite2D = null
var rider: Sprite2D = null
var chain: ScrollingChain = null
var _far: FishingDrawLayer = null
var _near: FishingDrawLayer = null
var _crank: float = 0.0
var _prop_t: float = 0.0
var _fly_t: float = 0.0
var _winch_t: float = 0.0
var _far_mats: Array[ShaderMaterial] = []


func _init() -> void:
	name = "Boat"
	body = Node2D.new()
	body.name = "Body"
	body.position = -PIVOT
	add_child(body)
	_far = FishingDrawLayer.make("FarLeg", _paint_far)
	body.add_child(_far)
	hull = _sprite("boat_hull", Vector2.ZERO)
	gears = _sprite("boat_gears", FishingRig.GEARS_AT)
	flywheel = _sprite("boat_flywheel", FishingRig.FLYWHEEL_AT)
	winch = _sprite("boat_winch", FishingRig.WINCH_AT)
	prop = _sprite("boat_prop", FishingRig.PROP_AT)
	chain = ScrollingChain.new()
	chain.name = "Chain"
	chain.auto_process = false
	chain.max_px_s = TAU * FishingRig.CHAINRING_R * 2.0
	chain.pitch_px = 2.0
	chain.link_px = 1.0
	chain.color_a = FishingPalette.STEEL
	chain.color_b = FishingPalette.WOOD_3
	chain.set_loop(
		FishingRig.SPROCKET, FishingRig.SPROCKET_R, FishingRig.BB, FishingRig.CHAINRING_R, 8
	)
	body.add_child(chain)
	rider = _sprite("rider", FishingRig.RIDER_AT)
	_near = FishingDrawLayer.make("Near", _paint_near)
	body.add_child(_near)


## The slot's look: the hull stripe and the rider's cap and jersey take the slot colour.
func set_look(p_slot: int, p_look: Dictionary, p_line: Color) -> void:
	slot = p_slot
	look = p_look
	line_color = p_line
	for s: Sprite2D in [hull, rider]:
		PaletteSwap.apply_slot(s, FishingPalette.keys(), slot)


## Another rider's boat on the farther row: every part gets the far-boat material (the slot
## colour on the key reds, a touch of haze, nothing drawn below the boat's own waterline).
func set_far(on: bool) -> void:
	far = on
	_far_mats.clear()
	if not on:
		set_look(slot, look, line_color)
		return
	var ramp := PaletteSwap.slot_ramp(slot, 2)
	var items: Array[CanvasItem] = [hull, gears, flywheel, winch, prop, chain, rider, _far, _near]
	for item in items:
		var m := ShaderMaterial.new()
		m.shader = far_shader()
		m.set_shader_parameter("key0", FishingPalette.KEY_LIGHT)
		m.set_shader_parameter("key1", FishingPalette.KEY_DARK)
		m.set_shader_parameter("swap0", ramp[0])
		m.set_shader_parameter("swap1", ramp[1])
		m.set_shader_parameter("swap_keys", item == hull or item == rider)
		m.set_shader_parameter("haze", FishingPalette.SKY_1)
		m.set_shader_parameter("haze_amount", FAR_HAZE)
		item.material = m
		_far_mats.append(m)


static func far_shader() -> Shader:
	if _far_shader == null:
		_far_shader = load(FAR_SHADER) as Shader
	return _far_shader


## One frame of `dt` seconds: eases the clutch, turns the parts, places the pivot.
func advance(dt: float) -> void:
	fishing = move_toward(fishing, fishing_target, dt / FISHING_EASE_S)
	_crank = fmod(_crank + cadence / 60.0 * TAU * dt, TAU)
	chain.drive(cadence, 120.0)
	chain.tick(dt)
	_fly_t += cadence * FLY_FPS_PER_RPM * dt
	_prop_t += PROP_FPS_FULL * prop_drive * (1.0 - fishing) * dt
	_winch_t += absf(winch_mps) * WINCH_FPS_PER_MPS * fishing * dt
	flywheel.texture = FishingSprites.frame("boat_flywheel", floori(_fly_t))
	gears.texture = FishingSprites.frame("boat_gears", floori(_fly_t * 0.5))
	prop.texture = FishingSprites.frame("boat_prop", floori(_prop_t))
	winch.texture = FishingSprites.frame("boat_winch", floori(_winch_t))
	scale.x = float(heading) if heading != 0 else 1.0
	rotation = -deg_to_rad(pitch_deg) * scale.x
	body.position = -PIVOT + Vector2(0, roundf(bob_px))
	for m in _far_mats:
		m.set_shader_parameter("clip_y", position.y + 1.0)
	_far.queue_redraw()
	_near.queue_redraw()


## The rod's points (boat-local, unflipped).
func rod_points() -> PackedVector2Array:
	return FishingRig.rod(fishing, tension, pull_dir)


## The rod tip in the parent's (the view's) coordinates.
func rod_tip() -> Vector2:
	return transform * (body.transform * rod_points()[-1])


## A boat-local point in the parent's coordinates.
func to_view(p: Vector2) -> Vector2:
	return transform * (body.transform * p)


## The two legs [near, far], each [hip, knee, foot], at the crank's angle.
func legs() -> Array[PackedVector2Array]:
	var p := FishingRig.pedals(_crank)
	return [FishingRig.leg(FishingRig.HIP, p[0]), FishingRig.leg(FishingRig.HIP, p[1])]


## The hand's grip: the tiller while driving, the winch brake while fishing.
func hand() -> Vector2:
	return FishingRig.BRAKE_KNOB if fishing >= 0.5 else FishingRig.TILLER_GRIP


func _sprite(id: String, at: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = id
	s.centered = false
	s.position = at
	s.texture = FishingSprites.frame(id)
	body.add_child(s)
	return s


func _paint_far(c: CanvasItem) -> void:
	var l := legs()[1]
	_seg(c, l[0], l[1], FishingPalette.WOOD_2)
	_seg(c, l[1], l[2], FishingPalette.SKIN_2)
	var pd := FishingRig.pedals(_crank)
	_seg(c, FishingRig.BB, pd[1], FishingPalette.STEEL)


func _paint_near(c: CanvasItem) -> void:
	var pd := FishingRig.pedals(_crank)
	_seg(c, FishingRig.BB, pd[0], FishingPalette.STEEL)
	c.draw_rect(Rect2(FishingRig.BB, Vector2.ONE), FishingPalette.BRASS_1)
	var l := legs()[0]
	_seg(c, l[0], l[1], FishingPalette.WOOD_3)
	_seg(c, l[1], l[2], FishingPalette.SKIN_1)
	c.draw_rect(Rect2(l[2].floor() + Vector2(1, 0), Vector2.ONE), FishingPalette.WOOD_3)
	var a := FishingRig.arm(hand())
	_seg(c, a[0], a[1], FishingPalette.SKIN_1)
	_seg(c, a[1], a[2], FishingPalette.SKIN_1)
	_seg(c, FishingRig.CLUTCH_PIVOT, FishingRig.clutch_tip(fishing), FishingPalette.WOOD_3)
	c.draw_rect(
		Rect2(FishingRig.clutch_tip(fishing).floor(), Vector2.ONE), FishingPalette.KEY_LIGHT
	)
	var rod := FishingRig.snapped(rod_points())
	c.draw_polyline(rod.slice(0, 3), FishingPalette.WOOD_3, 1.0)
	c.draw_polyline(rod.slice(2), FishingPalette.WOOD_2, 1.0)
	if fishing > 0.5:
		c.draw_line(FishingRig.WINCH_HUB + Vector2(0.5, -1.5), rod[1], Color(line_color, 0.9), 1.0)
	var col: Color = look.get("color", Wl.slot_look(slot)["color"])
	_seg(c, FishingRig.MAST_FOOT, FishingRig.MAST_TOP, FishingPalette.WOOD_3)
	var m := FishingRig.MAST_TOP
	var flag := PackedVector2Array([m + Vector2(0, 0), m + Vector2(-6, 1.5), m + Vector2(0, 3)])
	c.draw_colored_polygon(flag, col)


func _seg(c: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	c.draw_line(a.floor() + Vector2(0.5, 0.5), b.floor() + Vector2(0.5, 0.5), col, 1.0)
