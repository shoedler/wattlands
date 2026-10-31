class_name WorkoutHudTimeline
extends WorkoutHudCtl
## The timeline plate, top centre (480 x 66 art px; BRIEF 3.9): this phase's name and target, its time
## left in key digits, the whole session as a block profile with the current block outlined and past
## blocks darkened, and what comes next with the session's time left.

const W := 480
const H := 66
const STRIP := Rect2(6, 30, WorkoutHudModel.TIMELINE_COLUMNS, WorkoutHudModel.TIMELINE_H)
const PAST_DARKEN := 0.55

## Runs of the strip, cached until the timeline changes (a client's arrives after the first frame).
var runs: Array[Dictionary] = []
var _colors: Array[Color] = []
var _cached_n: int = -1
var _cached_total: float = -1.0


func _init() -> void:
	super()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func refresh() -> void:
	var total := st().total_s()
	if st().phases.size() != _cached_n or not is_equal_approx(total, _cached_total):
		_cached_n = st().phases.size()
		_cached_total = total
		runs = WorkoutHudModel.timeline_runs(st(), WorkoutHudModel.TIMELINE_COLUMNS)
		_colors.clear()
		for p in st().phases:
			_colors.append(WorkoutArt.phase_color(p))
	m = WorkoutHudModel.timeline(game, tm)


func paint() -> void:
	if m.is_empty():
		return
	D.plate(self, Rect2(0, 0, W, H))
	var left := D.clock(float(m["phase_left_s"]))
	var lw := D.big_r(self, W - 6, 4, left, D.NUM)
	var room := W - 6.0 - lw - 6.0 - 6.0
	D.tall(self, 6, 5, D.fit_tall(str(m["label"]), room), D.AMBER)
	D.tall(self, 6, 17, D.fit_tall(str(m["target"]), room), D.TEXT)
	_strip()
	var nx := 6.0 + D.tall(self, 6, 53, tx("WORKOUT_HUD_NEXT"), D.DIM) + 5.0
	var session := tx("WORKOUT_HUD_LEFT", [D.clock(float(m["session_left_s"]))])
	var sw := D.tall_r(self, W - 6, 53, session, D.TEXT)
	D.tall(self, nx, 53, D.fit_tall(str(m["next"]), W - 6.0 - sw - 8.0 - nx), D.TEXT)


func _strip() -> void:
	D.rect(self, STRIP, D.TRACK)
	var index := int(m["index"])
	var now_x := int(m["now_x"])
	var hatch := D.hatch()
	for run: Dictionary in runs:
		var phase := int(run["phase"])
		var col: Color = _colors[phase]
		var r := _run_rect(run)
		D.rect(self, r, col.darkened(PAST_DARKEN) if phase < index else col)
		if phase == index and now_x > int(run["x"]):
			# the part of the current block already ridden
			var done_w := minf(float(now_x - int(run["x"])), r.size.x)
			D.rect(self, Rect2(r.position, Vector2(done_w, r.size.y)), col.darkened(PAST_DARKEN))
		if bool(run["hatched"]):
			draw_texture_rect(hatch, r, true)
	_outline_current(index)
	D.rect(self, Rect2(STRIP.position.x + now_x, STRIP.position.y - 1, 1, STRIP.size.y + 2), D.TEXT)


func _run_rect(run: Dictionary) -> Rect2:
	var h := float(run["h"])
	return Rect2(STRIP.position.x + float(run["x"]), STRIP.end.y - h, float(run["w"]), h)


## A 1 px frame around the current block's columns, at the height of its tallest run.
func _outline_current(index: int) -> void:
	var x0 := -1
	var x1 := -1
	var h := 0
	for run: Dictionary in runs:
		if int(run["phase"]) != index:
			continue
		if x0 < 0:
			x0 = int(run["x"])
		x1 = int(run["x"]) + int(run["w"])
		h = maxi(h, int(run["h"]))
	if x0 < 0:
		return
	var r := Rect2(STRIP.position.x + x0, STRIP.end.y - h, x1 - x0, h)
	D.frame(self, r.grow(1).intersection(STRIP.grow(1)), D.FRAME_HI)
