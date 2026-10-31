class_name TankFarMap
extends RefCounted
## v4: the split screen's geometry (canvas art px) and the far panel's range mapping. Pure.

const SEAM_W := 8.0
const FAR_W_MIN := 286.0
const FAR_W_BASE := 330.0
const FAR_W_MAX := 420.0
## Below the banner rect (tank_hud.gd LAYOUT banners y 112..148), above every far sprite's top (244).
const PIP_Y := 150.0
const PIP_H := 60.0
const PIP_INSET := 6.0
const RANGE_NEAR_M := 700.0
const RANGE_FAR_M := 2600.0
const EDGE_PAD := 30.0
## Stage y of a far sprite's foot at lane 0 and RANGE_NEAR_M.
const FOOT_Y := 392.0
const LANE_LIFT := 12.0
const RANGE_LIFT := 18.0


static func far_w(canvas_x: float) -> float:
	return clampf(
		roundf(FAR_W_MIN + (canvas_x - 852.0) * (FAR_W_BASE - FAR_W_MIN) / 108.0),
		FAR_W_MIN,
		FAR_W_MAX
	)


## {near, seam, far, pip: Rect2} on the canvas. Mirrored (free roam, west): far on the left.
static func panels(canvas: Vector2, mirrored: bool) -> Dictionary:
	var fw := far_w(canvas.x)
	var nw := canvas.x - fw - SEAM_W
	var h := canvas.y
	var near := Rect2(0, 0, nw, h)
	var seam := Rect2(nw, 0, SEAM_W, h)
	var far := Rect2(nw + SEAM_W, 0, fw, h)
	if mirrored:
		far = Rect2(0, 0, fw, h)
		seam = Rect2(fw, 0, SEAM_W, h)
		near = Rect2(fw + SEAM_W, 0, nw, h)
	var pip := Rect2(far.position.x + PIP_INSET, PIP_Y, fw - 2.0 * PIP_INSET, PIP_H)
	return {"near": near, "seam": seam, "far": far, "pip": pip}


## The near panel's edge in the travel frame (the mirrored layers' x), whatever the mirror.
static func near_end_x(canvas_x: float) -> float:
	return canvas_x - far_w(canvas_x) - SEAM_W


## A range's x inside the far panel, from its near-side edge (the panel's own travel frame).
static func range_x(range_m: float, fw: float) -> float:
	var k := clampf((range_m - RANGE_NEAR_M) / (RANGE_FAR_M - RANGE_NEAR_M), 0.0, 1.0)
	return EDGE_PAD + k * (fw - 2.0 * EDGE_PAD)


## A far sprite's foot (stage y) at `range_m` in depth lane `lane`.
static func foot_y(range_m: float, lane: int) -> float:
	var k := clampf((range_m - RANGE_NEAR_M) / (RANGE_FAR_M - RANGE_NEAR_M), 0.0, 1.0)
	return roundf(FOOT_Y - LANE_LIFT * float(clampi(lane, 0, 3)) - RANGE_LIFT * k)
