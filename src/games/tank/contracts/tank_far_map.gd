class_name TankFarMap
extends RefCounted
## v4: the split screen's geometry (canvas art px) and the far panel's range mapping. Pure.

const SEAM_W := 8.0
const FAR_W_MIN := 286.0
const FAR_W_BASE := 330.0
const FAR_W_MAX := 420.0
## The little shell screen, docked against the seam like an instrument on its bulkhead: below the banner rect
## (tank_hud.gd LAYOUT banners y 112..148), above every far sprite's top (244).
const PIP_Y := 150.0
const PIP_W := 176.0
const PIP_H := 52.0
const RANGE_NEAR_M := 700.0
const RANGE_FAR_M := 2600.0
const EDGE_PAD := 30.0
## Stage y of a far sprite's foot at lane 0 and RANGE_NEAR_M. Range lifts it: farther is always higher, behind and
## hazier. A lane only breaks a tie (it must never outrank 490 m, as it did at 12 px a lane).
const FOOT_Y := 408.0
const LANE_LIFT := 2.0
const RANGE_LIFT := 64.0
## place(): the rows between one sprite's foot and the next one back, the highest foot allowed, and how far apart two
## neighbours' middles stand as a share of their half widths added, so each turret and gun has its own silhouette.
const FOOT_STEP := 18.0
const FOOT_TOP := 344.0
const X_SEP := 0.62
const X_EDGE := 1.0
## place(): how far a muzzle stands clear of a nearer tank's turret.
const MUZZLE_CLEAR := 3.0


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
	var pip_x := far.end.x - PIP_W if mirrored else far.position.x
	var pip := Rect2(pip_x, PIP_Y, PIP_W, PIP_H)
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


## Where the far sprites stand together: `rows` are [{id, range_m, lane, half_w}], the result id -> Vector2 foot (panel
## x, stage y). Nearest first: each one back is higher by FOOT_STEP at least and stands X_SEP clear of the one before
## it; a field too full for that shares what room there is. A lone sprite stands where the map says. A row may also
## give "muzzle" (Vector2) and "turret" (Rect2), both from its foot: a shooter's muzzle never lands on a nearer turret,
## where its firing mark would read as the nearer tank's.
static func place(rows: Array, fw: float) -> Dictionary:
	var sorted := rows.duplicate()
	sorted.sort_custom(_nearer)
	var n := sorted.size()
	var out := {}
	if n == 0:
		return out
	var y0 := foot_y(float(sorted[0]["range_m"]), int(sorted[0]["lane"]))
	var step := minf(FOOT_STEP, (y0 - FOOT_TOP) / maxf(float(n - 1), 1.0))
	var xs := PackedFloat32Array()
	xs.resize(n)
	var ys := PackedFloat32Array()
	ys.resize(n)
	var want := 0.0
	for i in n:
		var half := float(sorted[i]["half_w"])
		var rm := float(sorted[i]["range_m"])
		ys[i] = minf(foot_y(rm, int(sorted[i]["lane"])), y0 - step * float(i))
		xs[i] = _inside(range_x(rm, fw), half, fw)
		if i > 0:
			want += (half + float(sorted[i - 1]["half_w"])) * X_SEP
	var last := float(sorted[n - 1]["half_w"])
	var room := _inside(fw, last, fw) - _inside(0.0, float(sorted[0]["half_w"]), fw)
	var k := minf(1.0, room / maxf(want, 1.0))
	for j in range(1, n):
		var sep := (float(sorted[j]["half_w"]) + float(sorted[j - 1]["half_w"])) * X_SEP * k
		xs[j] = _inside(maxf(xs[j], xs[j - 1] + sep), float(sorted[j]["half_w"]), fw)
		xs[j] = _inside(_past_turrets(sorted, xs, ys, j), float(sorted[j]["half_w"]), fw)
	for j2 in range(n - 2, -1, -1):
		var sep2 := (float(sorted[j2]["half_w"]) + float(sorted[j2 + 1]["half_w"])) * X_SEP * k
		xs[j2] = _inside(minf(xs[j2], xs[j2 + 1] - sep2), float(sorted[j2]["half_w"]), fw)
	for m in n:
		out[sorted[m]["id"]] = Vector2(roundf(xs[m]), roundf(ys[m]))
	return out


## Row `j`'s x with its muzzle past the turret of every nearer row it would land on.
static func _past_turrets(
	sorted: Array, xs: PackedFloat32Array, ys: PackedFloat32Array, j: int
) -> float:
	var x := xs[j]
	var mz: Variant = (sorted[j] as Dictionary).get("muzzle")
	if not mz is Vector2:
		return x
	var at: Vector2 = mz
	for i in j:
		var t: Variant = (sorted[i] as Dictionary).get("turret")
		if not t is Rect2:
			continue
		var box := (t as Rect2).grow(MUZZLE_CLEAR)
		box.position += Vector2(xs[i], ys[i])
		var p := Vector2(x, ys[j]) + at
		if box.has_point(p):
			x = box.end.x - at.x
	return x


static func _nearer(a: Dictionary, b: Dictionary) -> bool:
	if float(a["range_m"]) != float(b["range_m"]):
		return float(a["range_m"]) < float(b["range_m"])
	return int(a["lane"]) < int(b["lane"])


## `x` with a sprite of half width `half` whole in the panel.
static func _inside(x: float, half: float, fw: float) -> float:
	if half * 2.0 + X_EDGE * 2.0 >= fw:
		return fw * 0.5
	return clampf(x, half + X_EDGE, fw - half - X_EDGE)
