class_name FishingRig
extends RefCounted
## The boat's geometry in boat-local art pixels (origin = the boat_hull sprite's top-left, bow
## right, sea surface on WATERLINE), the rod's pixel path (stowed or raised, its tip bending
## toward the line) and the pixel rasteriser every line uses: straight runs between whole-pixel
## points in the most even rhythm (Bresenham), one opaque colour, no gaps. Pure functions, so
## tests check the shapes. The sprites in FishingArtGrids are drawn to these points.

const HULL_SIZE := Vector2i(96, 40)
## The sea surface (boat-local y): rows from here down are seen through the water.
const WATERLINE := 30
## Hull extent along the deck (stern transom .. bow stem).
const STERN_X := 24
const BOW_X := 90
## The crew sprite (clutch lever, tiller, rider, legs, wheel and crank; four frames per pose).
const CREW_AT := Vector2(30, 3)
const CREW_SIZE := Vector2i(30, 18)
## Winch drum and screw prop sprites (top-left) and the prop's hub.
const WINCH_AT := Vector2(26, 13)
const PROP_AT := Vector2(8, 30)
const PROP_HUB := Vector2(9, 32)
## The rider's cap (player colour) and the pennant on the bow mast: top-left and size.
const CAP := Rect2i(43, 5, 4, 1)
const MAST_FOOT := Vector2i(87, 18)
const MAST_TOP := Vector2i(87, 11)
const FLAG := Rect2i(83, 11, 4, 2)
## The rod in its holder on the winch: three straight runs (butt, middle, tip), each a whole
## number of steps of a direction with an even ratio (1:0, 2:1, 1:1, 1:2). Unbent all three
## follow the butt's step (ROD_BUTT_STEPS + ROD_TIP_STEPS in all); under tension the middle
## turns half as far toward the line as the tip, so the rod bends in an arc.
const ROD_BASE := Vector2i(27, 12)
const ROD_STOW_STEP := Vector2i(-2, -1)
const ROD_FISH_STEP := Vector2i(-1, -2)
const ROD_BUTT_STEPS := 3
const ROD_TIP_STEPS := 4
## How far toward the pull the tip turns at full tension (0..1 of the way).
const ROD_BEND := 0.75
## The length (px) of the middle and the tip run.
const ROD_RUN_PX := 4.0
## Even slopes for a run (|dx| per |dy|): the line under water snaps to the nearest one.
const SLOPES: Array[float] = [0.0, 0.125, 0.25, 1.0 / 3.0, 0.5, 1.0, 2.0, 3.0, 4.0, 8.0]
## How far (px) a snapped line may move where it enters the water.
const SNAP_MAX_PX := 24
## Where the wake starts (behind the prop) and the bow's waterline (spray).
const WAKE_AT := Vector2i(7, 30)
const SPRAY_AT := Vector2i(86, 30)
## The rod tip's step directions (ratios 1:0, 2:1, 1:1, 1:2 in every quadrant).
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(2, 1),
	Vector2i(1, 1),
	Vector2i(1, 2),
	Vector2i(0, 1),
	Vector2i(-1, 2),
	Vector2i(-1, 1),
	Vector2i(-2, 1),
	Vector2i(-1, 0),
	Vector2i(-2, -1),
	Vector2i(-1, -1),
	Vector2i(-1, -2),
	Vector2i(0, -1),
	Vector2i(1, -2),
	Vector2i(1, -1),
	Vector2i(2, -1),
]


## The rod as [base, butt, middle, tip] (whole pixels): stowed low over the stern (`raise` <
## 0.5) or raised; a raised rod bends toward `pull_dir` (a unit vector toward the line) by
## `tension`.
static func rod(raise: float, tension: float, pull_dir: Vector2) -> PackedVector2Array:
	var step := ROD_STOW_STEP if raise < 0.5 else ROD_FISH_STEP
	var bend := clampf(tension, 0.0, 1.0) * ROD_BEND if raise >= 0.5 else 0.0
	var along := Vector2(step).normalized()
	var butt := ROD_BASE + step * ROD_BUTT_STEPS
	var mid_dir := quantize(along.lerp(pull_dir.normalized(), bend * 0.5))
	var mid := butt + mid_dir * _reps(mid_dir)
	var tip_dir := quantize(along.lerp(pull_dir.normalized(), bend))
	var tip := mid + tip_dir * _reps(tip_dir)
	return PackedVector2Array([Vector2(ROD_BASE), Vector2(butt), Vector2(mid), Vector2(tip)])


static func _reps(d: Vector2i) -> int:
	return maxi(roundi(ROD_RUN_PX / Vector2(d).length()), 1)


## Where a line should enter the water at row `surface` to reach `end` in an even slope
## (SLOPES), starting from the natural entry x `natural` (kept when snapping would move it more
## than SNAP_MAX_PX).
static func even_entry(natural: int, end: Vector2i, surface: int) -> int:
	var dy := end.y - surface
	if dy <= 0:
		return natural
	var dx := end.x - natural
	var want := absf(float(dx)) / float(dy)
	var best := SLOPES[0]
	for s in SLOPES:
		if absf(atan(s) - atan(want)) < absf(atan(best) - atan(want)):
			best = s
	var x := end.x - int(signf(float(dx))) * roundi(float(dy) * best)
	return x if absi(x - natural) <= SNAP_MAX_PX else natural


## The DIRS entry closest to `v` (straight up for a zero vector).
static func quantize(v: Vector2) -> Vector2i:
	if v.length() < 0.001:
		return Vector2i(0, -1)
	var best := DIRS[0]
	var best_dot := -2.0
	for d in DIRS:
		var dot := Vector2(d).normalized().dot(v.normalized())
		if dot > best_dot:
			best_dot = dot
			best = d
	return best


## Sag in art px of a line `length` long: deep with slack, none under strain.
static func line_sag(length: float, slack: float, strain: float) -> float:
	var k := clampf(slack - 0.4 - strain, 0.0, 1.0)
	return roundf(length * 0.15 * k)


## The line from `a` to `b` as one straight run, or two when it sags: [a, (low point), b], all
## whole pixels.
static func line(a: Vector2i, b: Vector2i, slack: float, strain: float) -> Array[Vector2i]:
	var sag := int(line_sag(Vector2(a).distance_to(Vector2(b)), slack, strain))
	if sag <= 0:
		return [a, b]
	var mid := Vector2i((a.x + b.x) / 2, (a.y + b.y) / 2 + sag)
	return [a, mid, b]


## Every pixel of the straight run from `a` to `b`, both ends included (Bresenham: each row or
## column advances in the most even rhythm).
static func raster(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	for _i in dx - dy + 1:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


## The rod's pixels through its joints `points` (rod()): each run walks its step direction,
## a 1:1 step as a two-pixel stair and the tip on a run of its own, so no rod pixel touches the
## next only at a corner.
static func rod_pixels(points: PackedVector2Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in points.size() - 1:
		var a := Vector2i(points[i])
		var d := Vector2i(points[i + 1]) - a
		if d == Vector2i.ZERO:
			continue
		var g := _gcd(absi(d.x), absi(d.y))
		var step := d / g
		for r in g:
			_walk(out, a + step * r, step)
	var tip := Vector2i(points[-1])
	var last := tip - Vector2i(points[-2]) if points.size() > 1 else Vector2i.ZERO
	if last.x != 0 and last.y != 0 and absi(last.x) != absi(last.y):
		var major := (
			Vector2i(signi(last.x), 0)
			if absi(last.x) > absi(last.y)
			else Vector2i(0, signi(last.y))
		)
		out.append(tip - major)
	out.append(tip)
	return out


static func _walk(out: Array[Vector2i], p: Vector2i, step: Vector2i) -> void:
	var sx := signi(step.x)
	var sy := signi(step.y)
	if absi(step.x) >= absi(step.y):
		for k in absi(step.x):
			out.append(p + Vector2i(sx * k, 0))
		if absi(step.x) == 1 and step.y != 0:
			out.append(p + Vector2i(sx, 0))
	else:
		for k in absi(step.y):
			out.append(p + Vector2i(0, sy * k))


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return maxi(a, 1)


## Every pixel of the runs through `points` (each joint once).
static func raster_path(points: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in points.size() - 1:
		var run := raster(points[i], points[i + 1])
		if i > 0:
			run.pop_front()
		out.append_array(run)
	return out
