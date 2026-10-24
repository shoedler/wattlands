class_name FishingRig
extends RefCounted
## The boat's geometry in boat-local art pixels (origin = the boat_hull sprite's top-left, bow
## right, sea surface on WATERLINE), the rod's pixel path (stowed or raised, its tip bending
## back under tension) and the pixel rasteriser every line uses: straight runs between whole-pixel
## points in the most even rhythm (Bresenham), one opaque colour, no gaps. Pure functions, so
## tests check the shapes. The sprites in FishingArtGrids are drawn to these points.

const HULL_SIZE := Vector2i(96, 40)
## The sea surface (boat-local y): rows from here down are seen through the water.
const WATERLINE := 28
## Hull extent along the deck (stern transom .. bow stem).
const STERN_X := 24
const BOW_X := 90
## The crew sprite (clutch lever, rider, leg, flywheel and bar; four crank frames per pose).
const CREW_AT := Vector2(30, 3)
const CREW_SIZE := Vector2i(30, 18)
## Winch drum and outboard prop sprites (top-left) and the prop's hub.
const WINCH_AT := Vector2(26, 13)
const PROP_AT := Vector2(20, 30)
const PROP_HUB := Vector2(21, 32)
## The rider's cap (player colour) driving (leaning to the bar) and fishing (upright), and the
## pennant on the bow mast: top-left and size.
const CAP_DRIVE := Rect2i(45, 7, 3, 1)
const CAP_FISH := Rect2i(41, 7, 3, 1)
const FLAG := Rect2i(83, 11, 4, 2)
## The planing hull frame raises the bow section (the mast, pennant and bow wave with it).
const PLANE_BOW_PX := 2
## The rod in its holder on the winch: a butt and a tip run, each a whole number of steps of an
## even ratio. Stowed both lie low over the stern (2:1); raised the butt stands steep (1:2) and
## under tension the tip bends back flatter (2:1).
const ROD_BASE := Vector2i(27, 12)
const ROD_STOW_STEP := Vector2i(-2, -1)
const ROD_FISH_STEP := Vector2i(-1, -2)
const ROD_BENT_STEP := Vector2i(-2, -1)
const ROD_BUTT_STEPS := 3
const ROD_TIP_STEPS := 2
## Tension from which the raised tip bends.
const ROD_BEND_AT := 0.35
## Even slopes for a run (|dx| per |dy|): the line under water snaps to the nearest one.
const SLOPES: Array[float] = [0.0, 0.125, 0.25, 1.0 / 3.0, 0.5, 1.0, 2.0, 3.0, 4.0, 8.0]
## How far (px) a snapped line may move where it enters the water.
const SNAP_MAX_PX := 24
## Where the wake starts (behind the outboard, on the waterline) and the bow's waterline.
const WAKE_AT := Vector2i(19, WATERLINE)
const SPRAY_AT := Vector2i(87, WATERLINE)


## The cap's rect for the pose (`fishing` from 0.5 the upright fishing pose).
static func cap(fishing: float) -> Rect2i:
	return CAP_FISH if fishing >= 0.5 else CAP_DRIVE


## The rod as [base, butt, tip] (whole pixels): stowed low over the stern (`raise` < 0.5) or
## raised; a raised tip bends back past ROD_BEND_AT `tension`.
static func rod(raise: float, tension: float) -> PackedVector2Array:
	var step := ROD_STOW_STEP if raise < 0.5 else ROD_FISH_STEP
	var butt := ROD_BASE + step * ROD_BUTT_STEPS
	var tip_step := ROD_BENT_STEP if raise >= 0.5 and tension >= ROD_BEND_AT else step
	var tip := butt + tip_step * ROD_TIP_STEPS
	return PackedVector2Array([Vector2(ROD_BASE), Vector2(butt), Vector2(tip)])


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
## column advances in the most even rhythm; a diagonal step also takes its corner pixel, so no
## pixel of a line touches the next only at a corner).
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
		var step_x := e2 >= dy
		var step_y := e2 <= dx
		if step_x:
			err += dy
			p.x += sx
		if step_x and step_y:
			out.append(p)
		if step_y:
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
