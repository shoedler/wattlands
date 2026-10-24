class_name FishingRig
extends RefCounted
## The boat's geometry in boat-local art pixels (origin = the boat_hull sprite's top-left, bow
## right, sea surface on WATERLINE), the rod's fixed pixel frames (stowed, raised, bent, hard
## bent: run lengths that change steadily along the curve) and the pixel rasteriser every line
## uses: uniform runs along the major axis with one diagonal step between runs (no corner
## pixels; a 1:1 run is one pixel per step), Bresenham only for slopes no uniform run fits. Pure
## functions, so tests check the shapes. The sprites in FishingArtGrids are drawn to these points.

const HULL_SIZE := Vector2i(96, 40)
## The sea surface (boat-local y): rows from here down are seen through the water.
const WATERLINE := 28
## Hull extent along the deck (stern transom .. bow stem).
const STERN_X := 24
const BOW_X := 90
## The crew sprite (clutch lever, seat, rider, leg, flywheel; four crank frames per pose).
const CREW_AT := Vector2(30, 3)
const CREW_SIZE := Vector2i(30, 18)
## Winch drum and outboard prop sprites (top-left) and the prop's hub.
const WINCH_AT := Vector2(26, 13)
const PROP_AT := Vector2(20, 30)
const PROP_HUB := Vector2(21, 32)
## The rider's cap (player colour) on the head, and the pennant on the bow mast.
const CAP := Rect2i(40, 7, 3, 1)
const FLAG := Rect2i(83, 11, 4, 2)
## The planing hull frame raises the bow section (the mast, pennant and bow wave with it).
const PLANE_BOW_PX := 2
## The rod in its holder on the winch, as runs from the base toward the tip: a positive run
## climbs that many pixels, then steps one aft and up; a negative run goes that many pixels aft,
## then steps one aft and down (stowed, with no climb, it steps up instead). Raised the rod
## stands at 1:2; under tension the runs shorten as it climbs and lengthen as it bends back.
const ROD_BASE := Vector2i(27, 12)
const ROD_STOWED: Array[int] = [-2, -2, -2, -2]
const ROD_RAISED: Array[int] = [2, 2, 2, 2, 2]
const ROD_BENT: Array[int] = [3, 3, 2, 2, -2, -3]
const ROD_HARD: Array[int] = [3, 3, 2, 2, -2, -2, -3, -4]
## Tension from which the raised rod shows the bent and the hard-bent frame.
const ROD_BENT_AT := 0.35
const ROD_HARD_AT := 0.7
## Even slopes for a run (|dx| per |dy|): a line snaps its end to the nearest one.
const SLOPES: Array[float] = [0.0, 0.125, 0.25, 1.0 / 3.0, 0.5, 1.0, 2.0, 3.0, 4.0, 8.0]
## How far (px) a snapped line may move its end.
const SNAP_MAX_PX := 24
## Where the wake starts (behind the outboard, on the waterline) and the bow's waterline.
const WAKE_AT := Vector2i(19, WATERLINE)
const SPRAY_AT := Vector2i(87, WATERLINE)


## The rod frame for `raise` (0 stowed .. 1 raised, shown from 0.5) and `tension`.
static func rod_runs(raise: float, tension: float) -> Array[int]:
	if raise < 0.5:
		return ROD_STOWED
	if tension >= ROD_HARD_AT:
		return ROD_HARD
	return ROD_BENT if tension >= ROD_BENT_AT else ROD_RAISED


## The rod's pixels from the base to the tip (the last one).
static func rod(raise: float, tension: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var runs := rod_runs(raise, tension)
	var climbs := runs[0] > 0
	var p := ROD_BASE
	for i in runs.size():
		var run := runs[i]
		var along := Vector2i(0, -1) if run > 0 else Vector2i(-1, 0)
		for k in absi(run):
			out.append(p + along * k)
		if i + 1 == runs.size():
			break
		var last := out[-1]
		if run > 0:
			p = last + (Vector2i(-1, 0) if runs[i + 1] < 0 else Vector2i(-1, -1))
		else:
			p = last + Vector2i(-1, 1 if climbs else -1)
	return out


## The x the line's end (a fish's lip, a wobbler) should take so the line from `tip` to `end`
## runs in uniform runs of an even slope (SLOPES); end.x itself when that would move it more
## than SNAP_MAX_PX.
static func even_end(tip: Vector2i, end: Vector2i) -> int:
	var dy := absi(end.y - tip.y)
	if dy == 0:
		return end.x
	var dx := end.x - tip.x
	var want := absf(float(dx)) / float(dy)
	var best := SLOPES[0]
	for s in SLOPES:
		if absf(atan(s) - atan(want)) < absf(atan(best) - atan(want)):
			best = s
	var w := 0
	if best >= 1.0:
		w = (dy + 1) * roundi(best) - 1
	elif best > 0.0:
		w = dy / roundi(1.0 / best)
	var x := tip.x + int(signf(float(dx))) * w
	return x if absi(x - end.x) <= SNAP_MAX_PX else end.x


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


## Every pixel of the straight run from `a` to `b`, both ends included: runs of one length along
## the major axis, a diagonal step between runs, the last run what is left; Bresenham where no
## uniform run fits the slope.
static func raster(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var d := b - a
	var x_major := absi(d.x) >= absi(d.y)
	var big := absi(d.x) if x_major else absi(d.y)
	var small := absi(d.y) if x_major else absi(d.x)
	var major := Vector2i(signi(d.x), 0) if x_major else Vector2i(0, signi(d.y))
	var minor := Vector2i(0, signi(d.y)) if x_major else Vector2i(signi(d.x), 0)
	var out: Array[Vector2i] = []
	if small == 0:
		for k in big + 1:
			out.append(a + major * k)
		return out
	var run_len := ceili(float(big + 1) / float(small + 1))
	if run_len * small > big:
		return _bresenham(a, b)
	var p := a
	var run := 0
	var steps := 0
	while true:
		out.append(p)
		if p == b:
			break
		run += 1
		if run == run_len and steps < small:
			p += major + minor
			steps += 1
			run = 0
		else:
			p += major
	return out


static func _bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
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


## Every pixel of the runs through `points` (each joint once).
static func raster_path(points: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in points.size() - 1:
		var run := raster(points[i], points[i + 1])
		if i > 0:
			run.pop_front()
		out.append_array(run)
	return out
