class_name WorkoutRiderLayer
extends Node2D
## The riders: wheels on the road at their own contact, the baked rider frame over them, sheared
## column by column on a slope (never rotated, so every pixel stays on the art grid), the whip
## pennant and the state bubble. Riders off screen are the pennant and an arrow only. It draws the
## model the WorkoutRideView computed and nothing else; the time of day's tint is this node's
## modulate.

const GREY_TINT := Color(0.55, 0.57, 0.62)
## Flag vertices past this x (art px from the pole) flutter.
const FLUTTER_X := 10.0

var kit: WorkoutKit = null
var _model: Dictionary = {}
var _slices: Dictionary = {}


func prepare(p_kit: WorkoutKit) -> WorkoutRiderLayer:
	kit = p_kit
	return self


func set_model(m: Dictionary) -> void:
	_model = m
	queue_redraw()


func _draw() -> void:
	if kit == null or _model.is_empty():
		return
	var markers: Array = _model.get("markers", [])
	for i: int in _model.get("draw_order", []):
		var m: Dictionary = markers[i]
		if int(m["edge"]) != 0:
			_edge_rider(m)
		else:
			_rider(m)
	for puff: Dictionary in _model.get("puffs", []):
		_fx(str(puff["fx"]), int(puff["frame"]), puff["at"])


func _rider(m: Dictionary) -> void:
	var r := kit.rider
	var origin := WorkoutKit.vec(r["origin"])
	var left := int(m["draw_x"]) - origin.x
	var top := int(m["rear_y"]) - origin.y
	var tint := Color.WHITE.lerp(GREY_TINT, float(m["grey"]))
	for dust: Dictionary in m.get("dust", []):
		_fx(str(dust["fx"]), int(dust["frame"]), dust["at"])
	_wheel(left + int(r["rear_hub"][0]), int(m["rear_y"]), int(m["wheel_frame"]), tint)
	_wheel(left + int(r["front_hub"][0]), int(m["front_y"]), int(m["wheel_frame"]), tint)
	_frame(m, left, top, tint)
	_pennant(m, Vector2(Vector2i(left, top) + WorkoutKit.vec(r["pennant_foot"])), int(m["flutter"]))
	var bubble := str(m["bubble"])
	if bubble != "":
		var at := WorkoutKit.vec(r["bubble"])
		var box: Array = kit.data["fx"][bubble]
		var half := floori(float(box[2]) * 0.5)
		_fx(bubble, int(m["blink"]), Vector2i(left + at.x - half, top + at.y - int(box[3]) + 2))


func _wheel(hub_x: int, contact_y: int, frame: int, tint: Color) -> void:
	var w: Dictionary = kit.data["wheel"]
	var cell := WorkoutKit.vec(w["cell"])
	var center := WorkoutKit.vec(w["center"])
	var pos := Vector2i(hub_x - center.x, contact_y - int(w["radius"]) - center.y)
	draw_texture_rect_region(
		kit.texture(w["path"]), Rect2(pos, cell), Rect2(Vector2i(frame * cell.x, 0), cell), tint
	)


## The rider frame as whole-pixel columns: a shear on the grid, never a rotation.
func _frame(m: Dictionary, left: int, top: int, tint: Color) -> void:
	var r := kit.rider
	var cell := WorkoutKit.vec(r["cell"])
	var slots: Array = r["slots"]
	var tex := kit.texture(slots[posmod(int(m["slot"]), slots.size())])
	var src := WorkoutRig.cell_of(int(m["pose"]), int(m["crank_frame"]), r["pose_rows"])
	for s: Vector3i in _slices_for(int(m["pitch"])):
		var w := s.y - s.x
		draw_texture_rect_region(
			tex,
			Rect2(left + s.x, top + s.z, w, cell.y),
			Rect2(src.x * cell.x + s.x, src.y * cell.y, w, cell.y),
			tint
		)


func _slices_for(pitch: int) -> Array:
	if not _slices.has(pitch):
		var r := kit.rider
		_slices[pitch] = WorkoutRig.shear_slices(
			pitch, int(r["cell"][0]), int(r["rear_hub"][0]), int(r["front_hub"][0])
		)
	return _slices[pitch]


## `trail`: a whip flag on a moving bike streams back, off the rider's own torso. The edge pennant
## keeps pointing right, its arrow past the flag.
func _pennant(m: Dictionary, foot: Vector2, flutter: int, trail: bool = true) -> void:
	for s: Dictionary in m["shapes"]:
		var moved := PackedVector2Array()
		for p: Vector2 in s["points"] as PackedVector2Array:
			var q := Vector2(foot.x - p.x if trail else foot.x + p.x, foot.y + p.y)
			if flutter != 0 and p.x > FLUTTER_X:
				q.y += float(flutter)
			moved.append(q)
		draw_colored_polygon(moved, s["color"])


## A rider off screen: its pennant at the edge and an arrow on the road pointing at it.
func _edge_rider(m: Dictionary) -> void:
	var foot := Vector2(float(m["x"]), float(m["y"]) - 2.0)
	_pennant(m, foot, 0, false)
	var edge := int(m["edge"])
	var ax := foot.x + (24.0 if edge > 0 else -5.0)
	var ay := foot.y - 5.0
	draw_colored_polygon(
		PackedVector2Array(
			[Vector2(ax, ay - 3.0), Vector2(ax + 4.0 * float(edge), ay), Vector2(ax, ay + 3.0)]
		),
		WorkoutArt.WHITE
	)


func _fx(fx_name: String, frame: int, at: Vector2i) -> void:
	var fx: Dictionary = kit.data["fx"]
	var box: Array = fx[fx_name]
	var size := Vector2i(int(box[2]), int(box[3]))
	var src := Vector2i(int(box[0]) + posmod(frame, int(box[4])) * size.x, int(box[1]))
	draw_texture_rect_region(kit.texture(fx["path"]), Rect2(at, size), Rect2(src, size))
