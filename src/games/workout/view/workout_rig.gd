class_name WorkoutRig
extends RefCounted
## The rider rig's numbers the view and the HUD share with the art (src/games/workout/art/rig.mjs),
## and the pure rules for what each rider shows: frames from revolutions and distance, the pose from
## what the rider is doing, and the group's formation and spread (view only: SpeedModel has no draft).

## Baked rider frames per crank revolution; frame 0 has the near pedal on top.
const CRANK_FRAMES := 24
const WHEEL_FRAMES := 16
const WHEEL_RADIUS_PX := 13.0
const POSE_SEAT := 0
const POSE_STAND := 1
const POSE_SITUP := 2
const POSE_STOP := 3
## kit.rider.pose_rows' key per pose.
const POSE_NAMES: Array[String] = ["seat", "stand", "situp", "stop"]
## Road lane per ordinal (art px). Next to each other on the road, two ordinals never share a lane.
const LANES: Array[int] = [0, 9, -9, 0, 9, -9, 0, 9]
## The group's spots around the viewer. A wheel sits 20 px either side of the rider's x, so at 60 px
## a rider's front wheel stands 20 px behind the rear wheel of the rider in front, in the next lane:
## the wheels stagger, the tyres never make one dark mass.
const GROUP_STEP_PX := 60
## What the group's spread keeps between two riders whatever their real gaps say: the sprite is 88
## px wide in one lane, and across lanes the wheels stagger as above.
const MIN_SAME_LANE_PX := 96
const MIN_CROSS_LANE_PX := 60
## Standing: a sprint at this share of FTP, a climb of GRADE_STAND_PCT at this share, and below the
## _HOLD shares a rider already standing sits down.
const SPRINT_STAND := 1.2
const SPRINT_HOLD := 0.95
const CLIMB_STAND := 0.95
const CLIMB_HOLD := 0.85
const GRADE_STAND_PCT := 4.0
## Under this speed a rider who has gone is stopped, a foot on the ground.
const STOPPED_MPS := 0.5


## The rider sheet's frame for `revs` crank revolutions.
static func crank_frame(revs: float) -> int:
	return floori(fposmod(revs, 1.0) * CRANK_FRAMES)


## Wheel turns after `distance_m` metres: no slip against the road surface, which scrolls at
## VISUAL_PX_PER_M.
static func wheel_revs(distance_m: float) -> float:
	return distance_m * WorkoutRideView.VISUAL_PX_PER_M / (TAU * WHEEL_RADIUS_PX)


static func wheel_frame(distance_m: float) -> int:
	return floori(fposmod(wheel_revs(distance_m), 1.0) * WHEEL_FRAMES)


## The pose a rider shows. `f`: {rescue, afk, disconnected, v_mps, cadence_rpm, power_w, ftp,
## sprint_phase: bool, grade_pct}. It shows what the rider is doing, so a warm-up sprint is not
## excluded here.
static func pose_of(prev: int, f: Dictionary) -> int:
	var gone := bool(f["afk"]) or bool(f["disconnected"])
	if gone and float(f["v_mps"]) < STOPPED_MPS:
		return POSE_STOP
	if bool(f["rescue"]) or gone:
		return POSE_SITUP
	var share := float(f["power_w"]) / maxf(float(f["ftp"]), 1.0)
	var sprint := bool(f["sprint_phase"])
	var climb := float(f["grade_pct"]) >= GRADE_STAND_PCT and float(f["cadence_rpm"]) > 0.0
	if (sprint and share >= SPRINT_STAND) or (climb and share >= CLIMB_STAND):
		return POSE_STAND
	if prev == POSE_STAND:
		if (sprint and share >= SPRINT_HOLD) or (climb and share >= CLIMB_HOLD):
			return POSE_STAND
	return POSE_SEAT


## How far rider `ordinal` is drawn from where its distance alone would put it, with rider
## `local_ordinal` on its own spot: the next ordinals ride in front of the viewer, the last ones
## behind, so the viewer is in the middle of the group and every spot stays on screen.
static func formation_dx(ordinal: int, local_ordinal: int, count: int = 8) -> int:
	var n := clampi(count, 1, LANES.size())
	var k := posmod(ordinal - local_ordinal, n)
	return (k if k <= n / 2 else k - n) * GROUP_STEP_PX


static func lane_dy(ordinal: int) -> int:
	return LANES[posmod(ordinal, LANES.size())]


## View-only collision resolution: where each rider is drawn so that nobody stands on anybody, however
## the real gaps cancel the formation. `spots`: Vector2(wanted x, lane) per rider. Rider `pinned` (the
## viewer) never moves, and riders only move away from it, each keeping the order its wanted x gave. A
## group too long for the room between it and the edge `lo` or `hi` closes up evenly instead of
## piling up against the edge.
static func spread(spots: Array[Vector2], pinned: int, lo: float, hi: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(spots.size())
	var keys: Array[Vector2] = []
	for i in spots.size():
		out[i] = spots[i].x
		keys.append(Vector2(spots[i].x, float(i)))
	keys.sort()
	var ahead: Array[int] = []
	var behind: Array[int] = []
	var seen_pin := false
	for k in keys:
		var i := int(k.y)
		if i == pinned:
			seen_pin = true
		elif seen_pin:
			ahead.append(i)
		else:
			behind.push_front(i)
	_sweep(out, spots, pinned, ahead, 1.0, hi)
	_sweep(out, spots, pinned, behind, -1.0, lo)
	return out


## Lays `list` out from the pinned rider in direction `dir`, nearest first, then closes it up to `limit`.
static func _sweep(
	out: PackedFloat64Array,
	spots: Array[Vector2],
	pinned: int,
	list: Array[int],
	dir: float,
	limit: float
) -> void:
	var placed: Array[int] = [pinned]
	for i in list:
		var x := out[i] * dir
		for j in placed:
			var same := is_equal_approx(spots[i].y, spots[j].y)
			x = maxf(x, out[j] * dir + float(MIN_SAME_LANE_PX if same else MIN_CROSS_LANE_PX))
		out[i] = x * dir
		placed.append(i)
	if list.is_empty():
		return
	var pin := out[pinned]
	var far: float = out[list.back()]
	if (far - limit) * dir > 0.0:
		var k := (limit - pin) / (far - pin)
		for i in list:
			out[i] = pin + (out[i] - pin) * k


## Rider sheet source cell for a pose and frame: the one addressing rule the art shares
## (kit.rider.pose_rows; the stop pose ignores the frame).
static func cell_of(pose: int, frame: int, pose_rows: Dictionary) -> Vector2i:
	var row := int(pose_rows[POSE_NAMES[pose]])
	if pose == POSE_STOP:
		return Vector2i(0, row)
	return Vector2i(frame % 6, row + floori(float(frame) / 6.0))


## The rider frame's column shear for a pitch: (first column, end column, y offset), one entry per
## whole pixel of offset, so the frame stays on the art grid. The rear hub's column has offset 0 and
## the front hub's has `pitch`, so the frame meets both wheels.
static func shear_slices(pitch: int, cell_w: int, rear_x: int, front_x: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if pitch == 0:
		out.append(Vector3i(0, cell_w, 0))
		return out
	var span := float(front_x - rear_x)
	var start := 0
	var off := _shear_at(0, pitch, rear_x, span)
	for x in range(1, cell_w):
		var here := _shear_at(x, pitch, rear_x, span)
		if here != off:
			out.append(Vector3i(start, x, off))
			start = x
			off = here
	out.append(Vector3i(start, cell_w, off))
	return out


## How far column `x` of a frame with this pitch is offset, so what is drawn over a rider stays on it.
static func shear_at(x: int, pitch: int, rear_x: int, front_x: int) -> int:
	if pitch == 0:
		return 0
	return _shear_at(x, pitch, rear_x, float(front_x - rear_x))


static func _shear_at(x: int, pitch: int, rear_x: int, span: float) -> int:
	return clampi(roundi(float(pitch) * float(x - rear_x) / span), mini(pitch, 0), maxi(pitch, 0))
