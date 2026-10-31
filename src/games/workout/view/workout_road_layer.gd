class_name WorkoutRoadLayer
extends Node2D
## The road and its verges, following the road's height column by column. One node draws the far
## verge and the road, a second the near verge in front of the riders. Columns of equal height merge
## into runs, and each texture gets one whole pass: the Compatibility renderer batches consecutive
## draws of one texture, and alternating per run would break the batch at every rect.

## The far verge's first fully opaque row, under its fence.
const GROUND_ROW := 8

var kit: WorkoutKit = null
## Near-verge mode.
var near: bool = false
var _runs: PackedInt32Array = PackedInt32Array()
var _scroll: int = 0
var _frame: int = 0


func setup(p_kit: WorkoutKit, p_near: bool) -> WorkoutRoadLayer:
	kit = p_kit
	near = p_near
	return self


## Runs of equal rounded height: x0, x1, y triples (art px), left to right.
static func runs_of(road: PackedFloat64Array, column_w: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := 0
	while i < road.size():
		var y := roundi(road[i])
		var j := i + 1
		while j < road.size() and roundi(road[j]) == y:
			j += 1
		out.append(i * column_w)
		out.append(j * column_w)
		out.append(y)
		i = j
	return out


## `scroll`: the surface's world x in whole art px; `frame`: the verges' wind frame. Redraws only
## when something changed.
func set_view(runs: PackedInt32Array, scroll: int, frame: int) -> void:
	if scroll == _scroll and frame == _frame and runs == _runs:
		return
	_runs = runs
	_scroll = scroll
	_frame = frame
	queue_redraw()


func _draw() -> void:
	if kit == null:
		return
	if near:
		var vn: Dictionary = kit.road["verge_near"]
		_pass(_path_of(vn), vn, int(vn["below"]))
		return
	var vf: Dictionary = kit.road["verge_far"]
	_ground_under(vf)
	_pass(_path_of(vf), vf, -int(vf["above"]))
	_pass(str(kit.road["path"]), kit.road, -int(kit.road["contact_row"]))


## Where the road sinks below its flat line the verge sinks with it, and the sky would show between
## the trees' mist and the fence: the verge's ground runs on up behind it. One index stretched, so
## it stays in the LUT and goes through the shader like the rest.
func _ground_under(verge: Dictionary) -> void:
	var tex := kit.texture(_path_of(verge))
	if tex == null:
		return
	var h := int(verge["tile"][1])
	var above := int(verge["above"])
	var top := roundi(WorkoutRideView.ROAD_Y) - above + GROUND_ROW
	var source := Rect2(0, h - 1, 1, 1)
	for i in range(0, _runs.size(), 3):
		var bottom := _runs[i + 2] - above + h
		if _runs[i + 2] > roundi(WorkoutRideView.ROAD_Y):
			var x0 := _runs[i]
			draw_texture_rect_region(tex, Rect2(x0, top, _runs[i + 1] - x0, bottom - top), source)


func _path_of(verge: Dictionary) -> String:
	var paths: Array = verge["paths"]
	return str(paths[_frame % paths.size()])


func _pass(path: String, entry: Dictionary, dy: int) -> void:
	var tex := kit.texture(path)
	if tex == null:
		return
	var w := int(entry["tile"][0])
	var h := int(entry["tile"][1])
	for i in range(0, _runs.size(), 3):
		var x := _runs[i]
		var x1 := _runs[i + 1]
		var y := _runs[i + 2] + dy
		while x < x1:
			var u := posmod(x + _scroll, w)
			var n := mini(x1 - x, w - u)
			draw_texture_rect_region(tex, Rect2(x, y, n, h), Rect2(u, 0, n, h))
			x += n
