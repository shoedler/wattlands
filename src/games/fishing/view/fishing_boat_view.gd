class_name FishingBoatView
extends Node2D
## One rider's boat (FishingRig's points, boat-local art px): the slate hull (level, or planing
## with the bow section raised) with its outboard leg, the crew sprite (clutch lever, a seated
## cyclist, the flywheel with its brass hub and the bar; four crank frames per pose), the winch
## drum and the prop as frame-animated sprites, the rod (stowed, raised, bent back under
## tension), the rider's cap and the bow pennant in the player's colour. The view sets position
## (the stern's waterline point on the surface), the shown values and calls advance(). Nothing
## is ever rotated: pitch lifts the boat by whole pixels and switches to the planing hull.
## Driving vs fishing (`fishing` eased 0..1, shown as a pose from 0.5): the rider sits up from
## the bar with a hand on the clutch, which leans aft; the prop stops while the winch drum turns;
## the rod tips up. Every part carries a palette map (FishingPaletteMap): rows under the boat's
## waterline take one flat water tone (the shadow slab); a farther boat is a step lighter.

## The boat's waterline midpoint: its position is this point of the hull.
const PIVOT := Vector2(58, FishingRig.WATERLINE)
const FISHING_EASE_S := 0.6
## Prop frame rate at full drive and the winch's frames per metre of line.
const PROP_FPS_FULL := 14.0
const WINCH_FPS_PER_MPS := 6.0
## Bow pitch (degrees) per pixel the boat lifts, and the most it lifts.
const LIFT_DEG_PER_PX := 3.0
const LIFT_MAX_PX := 3
## Lift (px) from which the planing hull frame shows.
const PLANE_LIFT_PX := 2
## A farther boat: each slate one step lighter.
const FAR_FROM: Array[Color] = [FishingPalette.SLATE, FishingPalette.WOOD]
const FAR_TO: Array[Color] = [FishingPalette.WOOD, FishingPalette.UPPER]

var slot: int = 0
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
## Rod tension 0..1.
var tension: float = 0.0

## True on the farther row (another rider's boat): see set_far().
var far: bool = false
var body: Node2D = null
var hull: Sprite2D = null
var crew: Sprite2D = null
var winch: Sprite2D = null
var prop: Sprite2D = null
var _near: FishingDrawLayer = null
var _crank: float = 0.0
var _prop_t: float = 0.0
var _winch_t: float = 0.0
var _mats: Array[ShaderMaterial] = []


func _init() -> void:
	name = "Boat"
	body = Node2D.new()
	body.name = "Body"
	body.position = -PIVOT
	add_child(body)
	hull = _sprite("boat_hull", Vector2.ZERO)
	winch = _sprite("boat_winch", FishingRig.WINCH_AT)
	prop = _sprite("boat_prop", FishingRig.PROP_AT)
	crew = _sprite("boat_crew", FishingRig.CREW_AT)
	_near = FishingDrawLayer.make("Near", _paint_near)
	body.add_child(_near)
	for item: CanvasItem in [hull, winch, prop, crew, _near]:
		_mats.append(FishingPaletteMap.apply(item))


## The rider's slot (the cap and pennant take its player colour) and the line colour.
func set_slot(p_slot: int, p_line: Color) -> void:
	slot = p_slot
	line_color = p_line


## Another rider's boat on the farther row: a step lighter.
func set_far(on: bool) -> void:
	far = on
	var none: Array[Color] = []
	for m in _mats:
		FishingPaletteMap.set_pairs(m, FAR_FROM if on else none, FAR_TO if on else none)


## The player colour of this boat's cap and pennant.
func player_color() -> Color:
	return FishingPalette.player(slot)


## Whole pixels the boat rises for the bow pitch shown (0 .. LIFT_MAX_PX).
func lift_px() -> int:
	return clampi(floori(maxf(pitch_deg, 0.0) / LIFT_DEG_PER_PX), 0, LIFT_MAX_PX)


## The crew frame shown: the pose's block, then the crank's quarter turn.
func crew_frame() -> int:
	var pose := 1 if fishing >= 0.5 else 0
	var k := posmod(floori(_crank / (TAU / float(FishingArtGrids.CREW_FRAMES))), 4)
	return pose * FishingArtGrids.CREW_FRAMES + k


## One frame of `dt` seconds: eases the clutch, turns the parts, places the body.
func advance(dt: float) -> void:
	fishing = move_toward(fishing, fishing_target, dt / FISHING_EASE_S)
	_crank = fmod(_crank + cadence / 60.0 * TAU * dt, TAU)
	_prop_t += PROP_FPS_FULL * prop_drive * (1.0 - fishing) * dt
	_winch_t += absf(winch_mps) * WINCH_FPS_PER_MPS * fishing * dt
	crew.texture = FishingSprites.frame("boat_crew", crew_frame())
	hull.texture = FishingSprites.frame("boat_hull", 1 if planing() else 0)
	prop.texture = FishingSprites.frame("boat_prop", floori(_prop_t))
	winch.texture = FishingSprites.frame("boat_winch", floori(_winch_t))
	scale.x = float(heading) if heading != 0 else 1.0
	body.position = -PIVOT + Vector2(0, roundf(bob_px) - float(lift_px()))
	for m in _mats:
		FishingPaletteMap.set_under(m, position.y, FishingPalette.UPPER)
	_near.queue_redraw()


## True while the planing hull shows (the bow section raised).
func planing() -> bool:
	return lift_px() >= PLANE_LIFT_PX


## The rod's points (boat-local, unflipped): [base, butt, tip].
func rod_points() -> PackedVector2Array:
	return FishingRig.rod(fishing, tension)


## The rod tip's pixel in the parent's (the view's) coordinates.
func rod_tip() -> Vector2:
	return pixel_of(Vector2i(rod_points()[-1]))


## The view pixel (top-left corner) of boat-local pixel `p`.
func pixel_of(p: Vector2i) -> Vector2:
	return to_view(Vector2(p) + Vector2(0.5, 0.5)).floor()


## A boat-local point in the parent's coordinates.
func to_view(p: Vector2) -> Vector2:
	return transform * (body.transform * p)


func _sprite(id: String, at: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = id
	s.centered = false
	s.position = at
	s.texture = FishingSprites.frame(id)
	body.add_child(s)
	return s


## The line's colour above the water: the cosmetic, else the rod's slate (wood on a farther
## boat, like its rod).
func line_above() -> Color:
	if far and line_color == FishingPalette.LINE:
		return FAR_TO[0]
	return line_color


func _paint_near(c: CanvasItem) -> void:
	for p in FishingRig.rod_pixels(rod_points()):
		c.draw_rect(Rect2(Vector2(p), Vector2.ONE), FishingPalette.SLATE)
	var col := player_color()
	c.draw_rect(Rect2(FishingRig.cap(fishing)), col)
	var bow := Vector2(0, -FishingRig.PLANE_BOW_PX if planing() else 0)
	c.draw_rect(Rect2(Vector2(FishingRig.FLAG.position) + bow, FishingRig.FLAG.size), col)
