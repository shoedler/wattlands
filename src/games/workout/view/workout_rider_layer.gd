class_name WorkoutRiderLayer
extends Node2D
## The riders: wheels on the road at their own contact, the baked rider frame over them, sheared
## column by column on a slope (never rotated, so every pixel stays on the art grid), and the state
## bubble. Two cues say "you", and neither needs colour: a ring of light on the road under the local
## rider's wheels paints first, under everybody, and a caret paints last, over its own helmet. Every
## whip pennant paints before the bodies, so a pole or a flag never crosses anybody's body. Riders off
## screen are the pennant and an arrow only. It draws the model the WorkoutRideView computed and
## nothing else; the time of day's tint is this node's modulate.

const GREY_TINT := Color(0.55, 0.57, 0.62)
## Flag columns past this x (art px from the pole) flutter.
const FLUTTER_X := 3.5
## The caret's rows, top down: half-width of its white. Its tip stands CARET_GAP px over the helmet.
const CARET_HALF: Array[int] = [7, 6, 5, 4, 3, 2, 1, 0]
const CARET_GAP := 2
const CARET_DARK := Color("#1e1e24")
## The road ring: half its height (art px) by columns in from either end, then MARK_HALF along the
## bike; it stands MARK_PAST px past the tyres at both ends.
const MARK_ENDS: Array[int] = [1, 2, 2, 3, 3, 3, 3]
const MARK_HALF := 4
const MARK_PAST := 4
const MARK_FILL := Color(1.0, 1.0, 1.0, 0.55)
## From the mouth (kit.rider.mouth_by_pose) to the head's centre and from there to the helmet's top.
const HEAD_FROM_MOUTH := Vector2i(-4, -2)
const HELMET_ABOVE_HEAD := 6

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
	for step: Array in paint_steps(_model):
		var m: Dictionary = markers[int(step[1])]
		match str(step[0]):
			"mark":
				_mark(m)
			"edge":
				_edge_rider(m)
			"pennant":
				_rider_pennant(m)
			"rider":
				_rider(m)
			"caret":
				_caret(m)
	for puff: Dictionary in _model.get("puffs", []):
		_fx(str(puff["fx"]), int(puff["frame"]), puff["at"])


## What the layer paints, in order, [kind, marker index]: the local rider's road ring, then riders
## off screen and every pennant, then the bikes and bodies by the model's draw order, then its caret.
static func paint_steps(model: Dictionary) -> Array:
	var markers: Array = model.get("markers", [])
	var order: Array = model.get("draw_order", [])
	var out: Array = []
	for i: int in order:
		if _is_local_on_screen(markers[i]):
			out.append(["mark", i])
	for i: int in order:
		out.append(["edge" if int(markers[i]["edge"]) != 0 else "pennant", i])
	for i: int in order:
		if int(markers[i]["edge"]) == 0:
			out.append(["rider", i])
	for i: int in order:
		if _is_local_on_screen(markers[i]):
			out.append(["caret", i])
	return out


static func _is_local_on_screen(m: Dictionary) -> bool:
	return int(m["edge"]) == 0 and bool(m.get("local", false))


## The road ring's columns, left to right, each Vector3i(x, top, bottom) in art px: a flat ellipse on
## the road around both tyres' contact points, on the slope between them in whole-pixel steps.
static func mark_columns(m: Dictionary, rider: Dictionary, radius: int) -> Array[Vector3i]:
	var left := int(m["draw_x"]) - int(rider["origin"][0])
	var rear_x := left + int(rider["rear_hub"][0])
	var front_x := left + int(rider["front_hub"][0])
	var rear_y := int(m["rear_y"])
	var rise := float(int(m["front_y"]) - rear_y) / float(front_x - rear_x)
	var x0 := rear_x - radius - MARK_PAST
	var x1 := front_x + radius + MARK_PAST
	var out: Array[Vector3i] = []
	for x in range(x0, x1 + 1):
		var from_end := mini(x - x0, x1 - x)
		var half := MARK_ENDS[from_end] if from_end < MARK_ENDS.size() else MARK_HALF
		var y := rear_y + roundi(rise * float(x - rear_x))
		out.append(Vector3i(x, y - half, y + half))
	return out


## The point over this rider's helmet where the caret's tip goes (art px): over the head of the pose
## it is in, on its own column of a sheared frame, and over its state bubble if it has one.
static func caret_tip(m: Dictionary, rider: Dictionary) -> Vector2i:
	var origin := WorkoutKit.vec(rider["origin"])
	var pose: String = WorkoutRig.POSE_NAMES[int(m["pose"])]
	var head := WorkoutKit.vec(rider["mouth_by_pose"][pose]) + HEAD_FROM_MOUTH
	var shear := WorkoutRig.shear_at(
		head.x, int(m["pitch"]), int(rider["rear_hub"][0]), int(rider["front_hub"][0])
	)
	var top := int(m["rear_y"]) - origin.y + head.y - HELMET_ABOVE_HEAD + shear - CARET_GAP
	if str(m.get("bubble", "")) != "":
		top = mini(top, int(m["rear_y"]) - origin.y + int(rider["bubble"][1]) - 8)
	return Vector2i(int(m["draw_x"]) - origin.x + head.x, top)


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


## A whip pennant on its bike, from the rear axle.
func _rider_pennant(m: Dictionary) -> void:
	var origin := WorkoutKit.vec(kit.rider["origin"])
	var at := Vector2i(int(m["draw_x"]) - origin.x, int(m["rear_y"]) - origin.y)
	_pennant(m, at + WorkoutKit.vec(kit.rider["pennant_foot"]), int(m["flutter"]))


## `trail`: a whip flag on a moving bike streams back, off the rider's own torso. The edge pennant
## keeps pointing right, its arrow past the flag. Every shape is a whole-pixel rect.
func _pennant(m: Dictionary, foot: Vector2i, flutter: int, trail: bool = true) -> void:
	for s: Dictionary in m["shapes"]:
		var pts: PackedVector2Array = s["points"]
		var box := Rect2(pts[0], pts[2] - pts[0])
		if flutter != 0 and box.position.x > FLUTTER_X:
			box.position.y += float(flutter)
		if trail:
			box.position.x = 1.0 - box.position.x - box.size.x
		box.position += Vector2(foot)
		draw_rect(box, s["color"])


## A rider off screen: its pennant at the edge and an arrow on the road pointing at it.
func _edge_rider(m: Dictionary) -> void:
	var foot := Vector2i(roundi(float(m["x"])), roundi(float(m["y"])) - 2)
	_pennant(m, foot, 0, false)
	var edge := int(m["edge"])
	var ax := foot.x + (12 if edge > 0 else -5)
	for k in 3:
		var half := 2 - k
		draw_rect(Rect2(ax + k * edge, foot.y - 5 - half, 1, half * 2 + 1), WorkoutArt.WHITE)


## The ring on the road under the local rider, wheels over it: a white rim, doubled on the near side
## so that it still reads between the neighbours' tyres, and a pool of light inside, wide and solid
## enough never to read as one of the road's own dashes.
func _mark(m: Dictionary) -> void:
	var columns := mark_columns(m, kit.rider, int(kit.data["wheel"]["radius"]))
	for i in columns.size():
		var c := columns[i]
		if i == 0 or i == columns.size() - 1:
			draw_rect(Rect2(c.x, c.y, 1, c.z - c.y + 1), WorkoutArt.WHITE)
			continue
		draw_rect(Rect2(c.x, c.y + 1, 1, c.z - c.y - 2), MARK_FILL)
		draw_rect(Rect2(c.x, c.y, 1, 1), WorkoutArt.WHITE)
		draw_rect(Rect2(c.x, c.z - 1, 1, 2), WorkoutArt.WHITE)


## The caret over the local rider: white, a dark line around it so it holds on any sky.
func _caret(m: Dictionary) -> void:
	var tip := caret_tip(m, kit.rider)
	var rows := CARET_HALF.size()
	var top_half := CARET_HALF[0]
	draw_rect(Rect2(tip.x - top_half - 1, tip.y - rows - 1, top_half * 2 + 3, 1), CARET_DARK)
	for r in rows:
		var half := CARET_HALF[r]
		var y := tip.y - rows + r
		draw_rect(Rect2(tip.x - half - 1, y, half * 2 + 3, 1), CARET_DARK)
		draw_rect(Rect2(tip.x - half, y, half * 2 + 1, 1), WorkoutArt.WHITE)
	draw_rect(Rect2(tip.x, tip.y, 1, 1), CARET_DARK)


func _fx(fx_name: String, frame: int, at: Vector2i) -> void:
	var fx: Dictionary = kit.data["fx"]
	var box: Array = fx[fx_name]
	var size := Vector2i(int(box[2]), int(box[3]))
	var src := Vector2i(int(box[0]) + posmod(frame, int(box[4])) * size.x, int(box[1]))
	draw_texture_rect_region(kit.texture(fx["path"]), Rect2(at, size), Rect2(src, size))
