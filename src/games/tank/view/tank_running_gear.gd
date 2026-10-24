class_name TankRunningGear
extends Node2D
## The running gear (brief 3 "Cutaway"): road wheels, the drive sprocket and the idler as
## SpinningParts, and a code-drawn track belt round them (ScrollingChain.set_belt) whose links move
## at the ground speed. Everything is in the hull frame. The rig draws the gear in front of the
## hull's lower band (round 5 scene critic: under the skirt it was invisible): the belt's upper run
## sits just under the cutaway band, the wheels show whole between the runs, and the lower run lies
## on the ground line. Each wheel is drawn crisp in code from its part's angle (a rubber tyre, a
## steel disc with a wet lit rim, turning lightening holes and a hub), since the generated 18 px
## wheel read as a black disc on the dark ground. Wheel speed is the rolling speed: v / (2 pi r).
## Radii come from rigs.json (`road_wheel_r`, `sprocket_r`, `idler_r`), so each tank's gear fits
## under its own rooms.

const TRACK_PITCH_PX := 4.0
const BELT_MAX_PX_S := 120.0
## Defaults when rigs.json gives no radius.
const ROAD_R := 9.0
const SPROCKET_R := 11.0
const IDLER_R := 10.0
## The belt's bed width (art px): the heavy dark band the link plates move on.
const BELT_W := 3.0

var wheels: Array[SpinningPart] = []
var radii: Array[float] = []
var belt: ScrollingChain = null
var ground_y: float = 82.0
var road_r: float = ROAD_R
var sprocket_r: float = SPROCKET_R
var idler_r: float = IDLER_R
## Which wheel is which: "drive_sprocket", "idler_wheel" or "road_wheel" per index of `wheels`.
var kinds: Array[String] = []

var _wheels_paint: TankPainter = null


## The road wheel, sprocket and idler radii of a rigs.json tank def.
static func radii_of(def: Dictionary) -> Vector3:
	var rr := float(def.get("road_wheel_r", ROAD_R))
	return Vector3(rr, float(def.get("sprocket_r", rr + 2.0)), float(def.get("idler_r", rr + 1.0)))


## Builds the gear from rigs.json `tanks.<id>`.
func assemble(def: Dictionary) -> void:
	name = "RunningGear"
	var r3 := radii_of(def)
	road_r = r3.x
	sprocket_r = r3.y
	idler_r = r3.z
	var line_y := float(def.get("wheel_line_y", 73))
	var centers := PackedVector2Array()
	var rs := PackedFloat32Array()
	var sp := TankRigs.vec(def.get("drive_sprocket"))
	var idl := TankRigs.vec(def.get("idler"))
	ground_y = line_y + road_r
	_add_wheel(sp, sprocket_r, "drive_sprocket", centers, rs)
	_add_wheel(idl, idler_r, "idler_wheel", centers, rs)
	for x: Variant in def.get("road_wheels_x", []):
		_add_wheel(Vector2(float(x), line_y), road_r, "road_wheel", centers, rs)
	_wheels_paint = TankPainter.new()
	_wheels_paint.name = "Wheels"
	_wheels_paint.painter = _paint_wheels
	add_child(_wheels_paint)
	# The belt: a solid coal-dark band of links (the bed) with one row of moving link plates on it,
	# so it reads as heavy track, not as dotted speckle; its upper run catches a wet lit edge.
	var bed := TankPainter.new()
	bed.name = "TrackBed"
	bed.painter = _paint_bed
	add_child(bed)
	belt = ScrollingChain.new()
	belt.name = "TrackBelt"
	belt.pitch_px = TRACK_PITCH_PX
	belt.link_px = 2.0
	belt.width_px = 1.0
	belt.color_a = TankPalette.STEEL
	belt.color_b = TankPalette.IRON_DARK
	belt.max_px_s = BELT_MAX_PX_S
	belt.inertia_s = 0.15
	belt.auto_process = false
	belt.points = belt_path(sp, sprocket_r, idl, idler_r, road_xs(def), line_y, road_r)
	add_child(belt)


## rigs.json `road_wheels_x` as floats, rear to front.
static func road_xs(def: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x: Variant in def.get("road_wheels_x", []):
		out.append(float(x))
	out.sort()
	return out


## The closed track belt (half a pixel outside every wheel): over the raised drive sprocket at the
## rear, sloping down onto the road wheels' tops so the upper run rests on them (not floating over
## them in a straight line), on round the front of the idler, then the lower run under the road
## wheels on the ground and back up round the sprocket.
static func belt_path(
	sp: Vector2,
	rs: float,
	idl: Vector2,
	ri: float,
	xs: PackedFloat32Array,
	line_y: float,
	rr: float
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var o := 0.5
	var top := line_y - rr - o
	var bottom := line_y + rr + o
	var segs := 8
	# The sprocket's upper rear quarter, then the top run.
	for k in range(segs + 1):
		var a := PI + PI * 0.5 * float(k) / float(segs)
		pts.append(sp + Vector2.from_angle(a) * (rs + o))
	if not xs.is_empty():
		pts.append(Vector2(xs[0], top))
		pts.append(Vector2(xs[xs.size() - 1], top))
	# Round the idler's front, top to bottom.
	for k in range(segs * 2 + 1):
		var a := -PI * 0.5 + PI * float(k) / float(segs * 2)
		pts.append(idl + Vector2.from_angle(a) * (ri + o))
	if not xs.is_empty():
		pts.append(Vector2(xs[xs.size() - 1], bottom))
		pts.append(Vector2(xs[0], bottom))
	# Up round the sprocket's lower rear quarter.
	for k in range(segs + 1):
		var a := PI * 0.5 + PI * 0.5 * float(k) / float(segs)
		pts.append(sp + Vector2.from_angle(a) * (rs + o))
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.25:
			out.append(p)
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.25:
		out.remove_at(out.size() - 1)
	return out


func _add_wheel(
	c: Vector2, r: float, sprite: String, centers: PackedVector2Array, rs: PackedFloat32Array
) -> void:
	var w := SpinningPart.new()
	w.name = "Wheel%d" % wheels.size()
	w.texture = TankSprites.tex(sprite)
	w.position = c
	w.max_rpm = 120.0
	w.inertia_s = 0.1
	w.snap_steps = 16
	w.auto_process = false
	# Drawn in code from this part's angle (_paint_wheels); the part keeps the rolling speed.
	w.self_modulate = Color(1, 1, 1, 0)
	add_child(w)
	wheels.append(w)
	radii.append(r)
	kinds.append(sprite)
	centers.append(c)
	rs.append(r)


func _paint_bed(item: Node2D) -> void:
	paint_bed(item, belt, BELT_W, TankPalette.COAL)
	if belt == null or belt.points.size() < 2:
		return
	# The upper run's top edge: a 1 px wet sheen where the moonlit haze and the room glow catch it.
	var pts := belt.points
	var mid := 0.0
	for p in pts:
		mid += p.y
	mid /= float(pts.size())
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if absf(a.y - b.y) < 0.6 and a.y < mid and absf(a.x - b.x) > 2.0:
			item.draw_line(
				Vector2(minf(a.x, b.x), a.y - 1.0),
				Vector2(maxf(a.x, b.x), a.y - 1.0),
				TankPalette.STEEL_LIGHT,
				1.0
			)


## Every wheel drawn crisp: a rubber tyre, a steel disc with a lit wet rim at its upper left and a
## dark lower right, lightening holes turning with the wheel, and a lit hub. The idler has spokes and
## no tyre; the sprocket a toothed ring (the rig draws it again over the hull where the chain ends).
func _paint_wheels(item: Node2D) -> void:
	for i in wheels.size():
		var c := wheels[i].position
		var r := radii[i]
		var ang := wheels[i].angle()
		match kinds[i]:
			"road_wheel":
				paint_road_wheel(item, c, r, ang)
			"idler_wheel":
				paint_idler(item, c, r, ang)
			_:
				paint_sprocket_ring(item, c, r, ang)


## A road wheel of radius `r` at `c`, turned `ang`.
static func paint_road_wheel(item: CanvasItem, c: Vector2, r: float, ang: float) -> void:
	item.draw_circle(c, r + 0.5, TankPalette.BLACK)
	item.draw_circle(c, r - 0.5, TankPalette.COAL)
	item.draw_circle(c, r - 1.5, TankPalette.IRON)
	item.draw_arc(c, r - 2.0, PI * 1.05, PI * 1.65, 8, TankPalette.STEEL_LIGHT, 1.0)
	item.draw_arc(c, r - 2.0, PI * 0.05, PI * 0.6, 8, TankPalette.IRON_DARK, 1.0)
	var hr := maxf((r - 1.5) * 0.55, 2.0)
	for k in 5:
		var d := Vector2.from_angle(ang + TAU * float(k) / 5.0)
		item.draw_rect(Rect2((c + d * hr).floor(), Vector2(1, 1)), TankPalette.SOOT)
	item.draw_circle(c, 1.8, TankPalette.STEEL)
	item.draw_rect(Rect2(c.round() - Vector2(1, 1), Vector2(1, 1)), TankPalette.STEEL_PALE)


## The idler of radius `r`: a steel rim and six spokes, no tyre.
static func paint_idler(item: CanvasItem, c: Vector2, r: float, ang: float) -> void:
	item.draw_circle(c, r + 0.5, TankPalette.BLACK)
	item.draw_circle(c, r - 0.5, TankPalette.IRON)
	item.draw_arc(c, r - 1.0, PI * 1.05, PI * 1.65, 8, TankPalette.STEEL_LIGHT, 1.0)
	item.draw_circle(c, r - 2.0, TankPalette.SOOT)
	for k in 6:
		var d := Vector2.from_angle(ang + TAU * float(k) / 6.0)
		item.draw_line(c + d * 1.5, c + d * (r - 1.5), TankPalette.STEEL_DARK, 1.0)
	item.draw_circle(c, 2.0, TankPalette.STEEL)
	item.draw_rect(Rect2(c.round() - Vector2(1, 1), Vector2(1, 1)), TankPalette.STEEL_PALE)


## A toothed sprocket ring of radius `r` with ten teeth cut by dark notches.
static func paint_sprocket_ring(item: CanvasItem, c: Vector2, r: float, ang: float) -> void:
	item.draw_circle(c, r + 0.5, TankPalette.BLACK)
	item.draw_circle(c, r - 0.5, TankPalette.STEEL)
	item.draw_arc(c, r - 0.5, PI * 1.1, PI * 1.8, 10, TankPalette.STEEL_PALE, 1.0)
	item.draw_circle(c, r - 3.0, TankPalette.IRON_DARK)
	for i in 10:
		var d := Vector2.from_angle(ang + TAU * float(i) / 10.0)
		item.draw_line(c + d * (r - 3.0), c + d * (r + 0.5), TankPalette.COAL, 1.0)
	item.draw_circle(c, 3.5, TankPalette.STEEL_DARK)
	item.draw_circle(c, 2.0, TankPalette.STEEL_LIGHT)


## The solid body under a ScrollingChain's moving links: its path as one polyline of `width` px.
static func paint_bed(item: CanvasItem, chain: ScrollingChain, width: float, col: Color) -> void:
	if chain == null or chain.points.size() < 2:
		return
	var pts := chain.points.duplicate()
	if chain.closed:
		pts.append(pts[0])
	item.draw_polyline(pts, col, width)


## Ground speed in art px per second (positive drives right).
func update(speed_px_s: float, dt: float) -> void:
	for i in wheels.size():
		wheels[i].speed = clampf(speed_px_s / (4.0 * PI * radii[i]), -1.0, 1.0)
		wheels[i].tick(dt)
	belt.speed = clampf(speed_px_s / BELT_MAX_PX_S, -1.0, 1.0)
	belt.tick(dt)
	_wheels_paint.queue_redraw()
