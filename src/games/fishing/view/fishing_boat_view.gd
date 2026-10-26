class_name FishingBoatView
extends Node2D
## One rider's boat (FishingRig's points, boat-local art px): the slate hull in its pose with
## its outboard leg, the crew sprite (clutch lever, a seated cyclist; one frame per pose), the
## drivetrain drawn every frame at the exact crank angle (FishingRig.drivetrain: the flywheel
## ring, its brass hub, the crank and the leg; the angle integrates the raw cadence the view
## sets, no frames and no smoothing), the winch drum and the prop as frame-animated
## sprites, and in the player's colour the rod (thick at the butt; stowed, raised, bent back
## under tension), the rider's cap and the bow pennant. The view sets position
## (the stern's waterline point on the surface), the shown values and calls advance(). Nothing
## is ever rotated: the signed trim picks a pose (FishingRig.POSE_LEVELS: five bow up, two
## braking bow down), a hull frame cut in bands moved by whole pixels, every part moving with
## the band it sits on; the rider leans into a sprint and sits back to brake.
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
## The signed trim (degrees, bow up positive) from which each bow-up pose 1..5 shows, and the
## braking poses -1 and -2 (bow down); a pose changes only once the trim is POSE_HOLD_DEG past
## its edge, so the hull does not flicker between two.
const POSE_UP_DEG: Array[float] = [1.5, 3.5, 6.0, 9.0, 12.0]
const POSE_DOWN_DEG: Array[float] = [-1.0, -3.0]
const POSE_HOLD_DEG := 0.4
## The rod is solid in the player's colour (like the cap and pennant; the line stays slate above
## the water, so the two read as different things), 2 px thick for this many pixels at the
## butt, 1 px beyond.
const ROD_BUTT_PX := 3
## The crew sits on the deck where it is at this boat-local x (between seat and flywheel).
const CREW_SEAT_X := 44.0
## Braking water from this deceleration share, hard braking from the second.
const BRAKE_AT := 0.3
const BRAKE_HARD_AT := 0.65
## The crew leans into a sprint from this pose up and sits back in the braking poses.
const LEAN_POSE := 3
## A farther boat: each slate one step lighter.
const FAR_FROM: Array[Color] = [FishingPalette.SLATE, FishingPalette.WOOD]
const FAR_TO: Array[Color] = [FishingPalette.WOOD, FishingPalette.UPPER]

var slot: int = 0
var line_color: Color = FishingPalette.LINE
## Shown values (the view writes them every frame).
var heading: int = 1
var pitch_deg: float = 0.0
## Braking 0..1 (the boat's deceleration, FishingRiderState.brake).
var brake: float = 0.0
var bob_px: float = 0.0
## The hull's heave (whole px, up positive) from the boat physics.
var heave_px: int = 0
## Raw cadence (rpm): the crank turns at exactly this rate.
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
var _pose: int = 0


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


## The pose shown (FishingRig.POSE_LEVELS): 1..5 bow up, -1 and -2 braking, 0 level.
func pose() -> int:
	return _pose


## How hard the boat brakes, for its water effects: 0 none, 1 braking, 2 hard (a braking pose or
## the deceleration past BRAKE_AT / BRAKE_HARD_AT).
func braking() -> int:
	if _pose <= -2 or brake >= BRAKE_HARD_AT:
		return 2
	if _pose < 0 or brake >= BRAKE_AT:
		return 1
	return 0


## The pose the signed trim `deg` asks for, without hysteresis.
static func pose_for(deg: float) -> int:
	var k := 0
	for i in POSE_UP_DEG.size():
		if deg >= POSE_UP_DEG[i]:
			k = i + 1
	for i in POSE_DOWN_DEG.size():
		if deg <= POSE_DOWN_DEG[i]:
			k = -(i + 1)
	return k


func _update_pose() -> void:
	var want := pose_for(pitch_deg)
	if want == _pose:
		return
	var step := signi(want - _pose)
	var nudge := pose_for(pitch_deg - float(step) * POSE_HOLD_DEG)
	if nudge != _pose:
		_pose = nudge


## How far boat-local column `x` moves in the pose shown.
func tilt_at(x: float) -> float:
	return float(FishingRig.tilt_dy(pose(), floori(x)))


## The crew frame shown: driving, fishing, leaning into a sprint or sat back braking.
func crew_frame() -> int:
	if fishing >= 0.5:
		return 1
	if _pose >= LEAN_POSE:
		return 2
	if _pose < 0:
		return 3
	return 0


## The crank angle (radians, 0 .. TAU).
func crank() -> float:
	return _crank


## One frame of `dt` seconds: eases the clutch, turns the parts, places the body.
func advance(dt: float) -> void:
	fishing = move_toward(fishing, fishing_target, dt / FISHING_EASE_S)
	_crank = fmod(_crank + cadence / 60.0 * TAU * dt, TAU)
	_prop_t += PROP_FPS_FULL * prop_drive * (1.0 - fishing) * dt
	_winch_t += absf(winch_mps) * WINCH_FPS_PER_MPS * fishing * dt
	_update_pose()
	crew.texture = FishingSprites.frame("boat_crew", crew_frame())
	hull.texture = FishingSprites.frame("boat_hull", FishingRig.hull_frame(_pose))
	prop.texture = FishingSprites.frame("boat_prop", floori(_prop_t))
	winch.texture = FishingSprites.frame("boat_winch", floori(_winch_t))
	scale.x = float(heading) if heading != 0 else 1.0
	body.position = -PIVOT + Vector2(0, roundf(bob_px) - float(heave_px))
	winch.position = FishingRig.WINCH_AT + Vector2(0, tilt_at(FishingRig.WINCH_AT.x))
	prop.position = FishingRig.PROP_AT + Vector2(0, tilt_at(FishingRig.PROP_AT.x))
	crew.position = FishingRig.CREW_AT + Vector2(0, tilt_at(CREW_SEAT_X))
	for m in _mats:
		FishingPaletteMap.set_under(m, position.y, FishingPalette.UPPER)
	_near.queue_redraw()


## The rod's pixels (boat-local, unflipped, moved with the winch it stands on), the tip last.
func rod_points() -> Array[Vector2i]:
	var dy := FishingRig.tilt_dy(pose(), FishingRig.ROD_BASE.x)
	var out: Array[Vector2i] = []
	for p in FishingRig.rod(fishing, tension):
		out.append(p + Vector2i(0, dy))
	return out


## The rod tip's pixel in the parent's (the view's) coordinates.
func rod_tip() -> Vector2:
	return to_view(Vector2(rod_points()[-1]) + Vector2(0.5, 0.5)).floor()


## The view pixel (top-left corner) of boat-local pixel `p` (as posed: see tilt_at()).
func pixel_of(p: Vector2i) -> Vector2:
	return to_view(Vector2(p) + Vector2(0.5, 0.5 + tilt_at(p.x))).floor()


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
	var at := FishingRig.CREW_AT + Vector2(0, tilt_at(CREW_SEAT_X))
	for p in FishingRig.drivetrain(_crank):
		c.draw_rect(Rect2(at + Vector2(p.x, p.y), Vector2.ONE), FishingRig.DRIVE_COLOURS[p.z])
	var col := player_color()
	var rod := rod_points()
	for i in rod.size():
		c.draw_rect(Rect2(Vector2(rod[i]), Vector2.ONE), col)
		if i < ROD_BUTT_PX and i + 1 < rod.size():
			var d := rod[i + 1] - rod[i]
			var side := Vector2i(1, 0) if d.x == 0 or d.y != 0 else Vector2i(0, 1)
			c.draw_rect(Rect2(Vector2(rod[i] + side), Vector2.ONE), col)
	var cap := Vector2(FishingRig.CAP.position) + Vector2(0, tilt_at(CREW_SEAT_X))
	c.draw_rect(Rect2(cap, FishingRig.CAP.size), col)
	var bow := Vector2(0, tilt_at(FishingRig.FLAG.position.x))
	c.draw_rect(Rect2(Vector2(FishingRig.FLAG.position) + bow, FishingRig.FLAG.size), col)
