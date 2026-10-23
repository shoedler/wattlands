class_name TankRunningGear
extends Node2D
## The running gear under the hull skirt (brief 3 "Cutaway"): road wheels, the drive sprocket and the
## idler as SpinningParts, and a code-drawn track belt round them (ScrollingChain.set_belt) whose
## links move at the ground speed. Everything is in the hull frame; the hull sprite is drawn over the
## top of the wheels so the skirt hides them. Wheel speed is the rolling speed: v / (2 pi r).

const TRACK_PITCH_PX := 4.0
const BELT_MAX_PX_S := 120.0
const ROAD_R := 9.0
const SPROCKET_R := 11.0
const IDLER_R := 10.0

var wheels: Array[SpinningPart] = []
var radii: Array[float] = []
var belt: ScrollingChain = null
var ground_y: float = 82.0


## Builds the gear from rigs.json `tanks.<id>`.
func assemble(def: Dictionary) -> void:
	name = "RunningGear"
	var line_y := float(def.get("wheel_line_y", 73))
	var centers := PackedVector2Array()
	var rs := PackedFloat32Array()
	var sp := TankRigs.vec(def.get("drive_sprocket"))
	var idl := TankRigs.vec(def.get("idler"))
	ground_y = line_y + ROAD_R
	_add_wheel(sp, SPROCKET_R, "drive_sprocket", centers, rs)
	_add_wheel(idl, IDLER_R, "idler_wheel", centers, rs)
	for x: Variant in def.get("road_wheels_x", []):
		_add_wheel(Vector2(float(x), line_y), ROAD_R, "road_wheel", centers, rs)
	belt = ScrollingChain.new()
	belt.name = "TrackBelt"
	belt.pitch_px = TRACK_PITCH_PX
	belt.link_px = 3.0
	belt.width_px = 2.0
	belt.color_a = TankPalette.STEEL_DARK
	belt.color_b = TankPalette.IRON
	belt.max_px_s = BELT_MAX_PX_S
	belt.inertia_s = 0.15
	belt.auto_process = false
	var belt_r := PackedFloat32Array()
	for r in rs:
		belt_r.append(r + 0.5)
	belt.set_belt(centers, belt_r)
	add_child(belt)


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
	add_child(w)
	wheels.append(w)
	radii.append(r)
	centers.append(c)
	rs.append(r)


## Ground speed in art px per second (positive drives right).
func update(speed_px_s: float, dt: float) -> void:
	for i in wheels.size():
		wheels[i].speed = clampf(speed_px_s / (4.0 * PI * radii[i]), -1.0, 1.0)
		wheels[i].tick(dt)
	belt.speed = clampf(speed_px_s / BELT_MAX_PX_S, -1.0, 1.0)
	belt.tick(dt)
