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
## The crew sprite (clutch lever, seat, rider; one frame per pose).
const CREW_AT := Vector2(30, 3)
const CREW_SIZE := Vector2i(30, 18)
## The drivetrain, crew-local, drawn at the exact crank angle (drivetrain()): the flywheel ring
## (a 2 px slate ring, WHEEL_RING's rows from WHEEL_AT), its brass hub (2 x 2 on the centre),
## the crank (CRANK_R px to the pedal) and the leg from the hip to the pedal through a knee
## (THIGH_PX and SHIN_PX long, bent up), crank and leg 2 px thick in the rider's abyss.
const WHEEL_AT := Vector2i(15, 8)
const WHEEL_RING: Array[String] = [
	"...####...",
	".########.",
	".##....##.",
	"##......##",
	"##......##",
	"##......##",
	"##......##",
	".##....##.",
	".########.",
	"...####...",
]
const WHEEL_C := Vector2(20.0, 13.0)
const CRANK_R := 3.5
const HIP := Vector2(12.0, 12.0)
const THIGH_PX := 5.5
const SHIN_PX := 5.5
## drivetrain()'s colour indices: ring, crank and leg, hub.
const DRIVE_COLOURS: Array[Color] = [
	FishingPalette.SLATE, FishingPalette.ABYSS, FishingPalette.ACCENT
]
## Winch drum and outboard prop sprites (top-left) and the prop's hub.
const WINCH_AT := Vector2(26, 13)
const PROP_AT := Vector2(20, 30)
const PROP_HUB := Vector2(21, 32)
## The rider's cap (player colour) on the head, and the pennant on the bow mast.
const CAP := Rect2i(40, 7, 3, 1)
const FLAG := Rect2i(83, 11, 4, 2)
## The hull's poses (nothing is ever rotated): the boat is cut into bands along x between
## POSE_X0 and POSE_X1 and each band moves by whole pixels in 1 px steps of equal length, from
## the stern's offset to the bow's. Per pose, [stern dy, bow dy] (y grows down): the bow-up
## poses 1..5 squat the stern up to 2 px and lift the bow up to 8 px; the braking poses -1 and
## -2 dig the bow in 2 and 4 px and lift the stern 1 and 2 px. The hull frames and every part
## follow tilt_dy().
const POSE_LEVELS := {
	-2: [-2, 4],
	-1: [-1, 2],
	0: [0, 0],
	1: [1, -2],
	2: [1, -3],
	3: [1, -5],
	4: [2, -6],
	5: [2, -8],
}
const POSE_MIN := -2
const POSE_MAX := 5
const POSE_X0 := 30
const POSE_X1 := 86
## The rod in its holder on the winch, as runs from the base toward the tip: a positive run
## climbs that many pixels, then steps one aft and up; a negative run goes that many pixels aft,
## then steps one aft and down (stowed, with no climb, it steps up instead). Raised the rod
## leans back at 1:1, its tip behind the outboard; bent it is two clean straight parts, the 1:1
## butt and a 2:1 tip falling toward the line, longer under more tension.
const ROD_BASE := Vector2i(27, 12)
const ROD_STOWED: Array[int] = [-2, -2, -2, -2]
const ROD_RAISED: Array[int] = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
const ROD_BENT: Array[int] = [1, 1, 1, 1, 1, 1, 1, -2, -2, -2]
const ROD_HARD: Array[int] = [1, 1, 1, 1, 1, -2, -2, -2, -2, -2]
## Tension from which the raised rod shows the bent and the hard-bent frame.
const ROD_BENT_AT := 0.35
const ROD_HARD_AT := 0.7
## Where the wake starts (behind the outboard, on the waterline) and the bow's waterline.
const WAKE_AT := Vector2i(19, WATERLINE)
const SPRAY_AT := Vector2i(87, WATERLINE)


## The drivetrain's pixels at crank angle `angle` (radians, clockwise on screen), crew-local,
## back to front: Vector3i(x, y, DRIVE_COLOURS index).
static func drivetrain(angle: float) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y in WHEEL_RING.size():
		for x in WHEEL_RING[y].length():
			if WHEEL_RING[y][x] == "#":
				out.append(Vector3i(WHEEL_AT.x + x, WHEEL_AT.y + y, 0))
	var pedal := WHEEL_C + Vector2(cos(angle), sin(angle)) * CRANK_R
	var d := pedal - HIP
	var reach := clampf(d.length(), 0.5, THIGH_PX + SHIN_PX - 0.01)
	var along := (THIGH_PX * THIGH_PX - SHIN_PX * SHIN_PX + reach * reach) / (2.0 * reach)
	var lift := sqrt(maxf(THIGH_PX * THIGH_PX - along * along, 0.0))
	var dir := d.normalized() if d.length() > 0.01 else Vector2.RIGHT
	var side := Vector2(dir.y, -dir.x) * lift
	var knee := HIP + dir * along + side
	var other := HIP + dir * along - side
	if other.y < knee.y:
		knee = other
	var hub := Vector2i(WHEEL_C.floor()) - Vector2i.ONE
	var foot := Vector2i(pedal.floor()) - Vector2i.ONE
	var hip := Vector2i(HIP.floor())
	var k := Vector2i(knee.floor())
	var block: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i.ONE]
	for seg: Array in [[hip, k], [k, foot], [hub, foot]]:
		for p in raster(seg[0], seg[1]):
			for q in block:
				out.append(Vector3i(p.x + q.x, p.y + q.y, 1))
	for q in block:
		out.append(Vector3i(hub.x + q.x, hub.y + q.y, 2))
	return out


## How far boat-local column `x` moves in pose `pose` (POSE_LEVELS).
static func tilt_dy(pose: int, x: int) -> int:
	var lv: Array = POSE_LEVELS[clampi(pose, POSE_MIN, POSE_MAX)]
	var stern := int(lv[0])
	var bow := int(lv[1])
	var steps := absi(bow - stern)
	if steps == 0:
		return stern
	var u := clampi(x - POSE_X0, 0, POSE_X1 - POSE_X0)
	var k := mini(u * (steps + 1) / (POSE_X1 - POSE_X0 + 1), steps)
	return stern + k * signi(bow - stern)


## The boat_hull frame of pose `pose`: the level hull first, then the bow-up poses 1..5, then
## the braking poses -1 and -2.
static func hull_frame(pose: int) -> int:
	var p := clampi(pose, POSE_MIN, POSE_MAX)
	return p if p >= 0 else POSE_MAX - p


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
		return bresenham(a, b)
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


## Every pixel of the Bresenham line from `a` to `b`, both ends included.
static func bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
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
