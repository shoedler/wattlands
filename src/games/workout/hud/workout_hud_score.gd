class_name WorkoutHudScore
extends WorkoutHudCtl
## The score plate, bottom right (184 x 66 art px): session time in band as a key number with the live
## grade letter, this block's and the group's time in band, then speed and distance (with the grade on
## a course) or, in a sprint, this sprint's peak watts.

const W := 184
const H := 66

## The local rider's peak watts in the current phase, reset when the phase changes.
var peak_w: float = 0.0
var _peak_phase: int = -1


func refresh() -> void:
	var r := rider()
	if r == null:
		m = {}
		return
	var i := WorkoutHudModel.phase_index(st(), r)
	if i != _peak_phase:
		_peak_phase = i
		peak_w = 0.0
	if tm != null:
		peak_w = maxf(peak_w, tm.power_w)
	m = WorkoutHudModel.score(game, tm, peak_w)


func paint() -> void:
	if m.is_empty():
		return
	D.plate(self, Rect2(0, 0, W, H))
	var bw := D.big(self, 6, 5, str(m["tib"]), D.NUM)
	D.tall(self, 6 + bw + 3, 6, "%", D.DIM)
	D.tall(self, 6 + bw + 3, 18, tx("WORKOUT_HUD_IN_BAND").to_upper(), D.DIM)
	D.text_r(self, W - 7, 7, str(m["grade"]), D.AMBER, 3)
	D.rect(self, Rect2(4, 32, W - 8, 1), D.FRAME_IN)
	D.tall(self, 6, 36, str(m["block"]), D.TEXT)
	var group := str(m["group"])
	if group != "":
		D.tall_r(self, W - 6, 36, group, D.TEXT)
	var peak := str(m["peak"])
	if peak != "":
		D.tall(self, 6, 50, peak, D.AMBER)
		return
	var sw := D.tall(self, 6, 50, str(m["speed"]), D.TEXT)
	var grade := str(m["grade_pct"])
	if grade != "":
		D.tall(self, 6 + sw + 6, 50, grade, D.DIM)
	D.tall_r(self, W - 6, 50, str(m["km"]), D.TEXT)
