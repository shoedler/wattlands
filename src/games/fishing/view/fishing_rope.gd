class_name FishingRope
extends RefCounted
## The fishing line as a small verlet rope in view pixels (visual only, never game state):
## SEGMENTS links between the rod end and the fish or wobbler, pinned at both ends, stepped at
## STEP_S. Gravity sags it, much more drag and buoyancy under the surface than in the air (so the
## surface kink comes out of the drag difference), and its length follows the fight: strain
## pulls it to the straight distance, slack lets it bow (length()). The links only resist
## stretching. pixels() draws it as one clean 1 px curve: the joints rounded with hysteresis (a
## joint moves only once it is HOLD_PX off its pixel, so the line does not flicker), the runs
## between them rastered and every L-corner taken out.

const SEGMENTS := 16
const ITERATIONS := 40
const STEP_S := 1.0 / 60.0
## Gravity (px/s^2) and the share of velocity kept per step, in the air and in the water.
const GRAVITY_AIR := 260.0
const GRAVITY_WATER := 120.0
const KEEP_AIR := 0.985
const KEEP_WATER := 0.86
## A line under strain (strain over slack) is also pulled this share toward its chord per step,
## so a fight's strain draws it straight.
const TAUT_PULL := 0.25
## The most extra length (a share of the straight distance) a fully slack line has.
const SLACK_MAX := 0.32
## An anchor that jumps further than this (a cast, a rejoin) restarts the rope straight.
const RESET_PX := 90.0
## A joint's drawn pixel moves once its point is this far off it.
const HOLD_PX := 0.75
## Each frame the drawn anchors close this share of the gap to the true ones.
const ANCHOR_EASE := 0.5

var points: PackedVector2Array = PackedVector2Array()
var _prev: PackedVector2Array = PackedVector2Array()
var _held: Array[Vector2i] = []
var _a: Vector2 = Vector2.INF
var _b: Vector2 = Vector2.INF
var _acc: float = 0.0


## The rope's length for a straight distance `dist` with the fight's `slack` and `strain`
## (0..1 each).
static func length(dist: float, slack: float, strain: float) -> float:
	var loose := clampf(0.15 + 0.9 * slack - 0.9 * strain, 0.0, 1.0)
	return dist * (1.0 + SLACK_MAX * loose)


## Restarts the rope straight between `a` and `b`.
func reset(a: Vector2, b: Vector2) -> void:
	_a = a
	_b = b
	points.resize(SEGMENTS + 1)
	for i in SEGMENTS + 1:
		points[i] = a.lerp(b, float(i) / float(SEGMENTS))
	_prev = points.duplicate()
	_held.clear()
	_acc = 0.0


## Advances `dt` seconds with the ends at `a` (the rod end) and `b`, the water's surface on row
## `surf_y`.
func step(a: Vector2, b: Vector2, slack: float, strain: float, dt: float, surf_y: float) -> void:
	if (
		points.size() != SEGMENTS + 1
		or _a.distance_to(a) > RESET_PX
		or _b.distance_to(b) > RESET_PX
	):
		reset(a, b)
		return
	_a = _a.lerp(a, ANCHOR_EASE)
	_b = _b.lerp(b, ANCHOR_EASE)
	var rest := length(_a.distance_to(_b), slack, strain) / float(SEGMENTS)
	var taut := clampf(strain - slack, 0.0, 1.0) * TAUT_PULL
	_acc = minf(_acc + maxf(dt, 0.0), 0.25)
	while _acc >= STEP_S:
		_acc -= STEP_S
		_integrate(surf_y)
		_constrain(rest)
		if taut > 0.0:
			for i in range(1, SEGMENTS):
				var on_chord := _a.lerp(_b, float(i) / float(SEGMENTS))
				points[i] = points[i].lerp(on_chord, taut)


func _integrate(surf_y: float) -> void:
	for i in range(1, SEGMENTS):
		var p := points[i]
		var wet := p.y > surf_y
		var keep := KEEP_WATER if wet else KEEP_AIR
		var g := GRAVITY_WATER if wet else GRAVITY_AIR
		var v := (p - _prev[i]) * keep
		_prev[i] = p
		points[i] = p + v + Vector2(0.0, g * STEP_S * STEP_S)


func _constrain(rest: float) -> void:
	for _k in ITERATIONS:
		points[0] = _a
		points[SEGMENTS] = _b
		for i in SEGMENTS:
			var d := points[i + 1] - points[i]
			var len := d.length()
			if len <= rest or len < 1e-6:
				continue
			var fix := d * ((len - rest) / len)
			if i == 0:
				points[1] -= fix
			elif i + 1 == SEGMENTS:
				points[i] += fix
			else:
				points[i] += fix * 0.5
				points[i + 1] -= fix * 0.5
	points[0] = _a
	points[SEGMENTS] = _b


## The line's pixels from the rod end to the far end: whole-pixel joints held against jitter,
## rastered runs between them, no L-corners.
func pixels() -> Array[Vector2i]:
	if points.size() != SEGMENTS + 1:
		return []
	if _held.size() != points.size():
		_held.clear()
		for p in points:
			_held.append(Vector2i(p.round()))
	for i in points.size():
		var p := points[i]
		if i == 0 or i == points.size() - 1 or Vector2(_held[i]).distance_to(p) > HOLD_PX:
			_held[i] = Vector2i(p.round())
	var joints: Array[Vector2i] = []
	for q in _held:
		if joints.is_empty() or joints[-1] != q:
			joints.append(q)
	return pixel_perfect(FishingRig.raster_path(joints))


## `path` without its L-corners (a pixel whose neighbours before and after touch diagonally
## goes) and without one-pixel spikes (a pixel off the row or column its two neighbours share
## moves onto it, so an apex is flat instead of a checker).
static func pixel_perfect(path: Array[Vector2i]) -> Array[Vector2i]:
	if path.size() < 3:
		return path
	var out: Array[Vector2i] = [path[0]]
	var i := 1
	while i < path.size() - 1:
		var a := out[-1]
		var c := path[i + 1]
		if absi(c.x - a.x) == 1 and absi(c.y - a.y) == 1:
			i += 1
			continue
		if a.y == c.y and absi(c.x - a.x) == 2 and path[i].y != a.y:
			out.append(Vector2i((a.x + c.x) / 2, a.y))
		elif a.x == c.x and absi(c.y - a.y) == 2 and path[i].x != a.x:
			out.append(Vector2i(a.x, (a.y + c.y) / 2))
		else:
			out.append(path[i])
		i += 1
	out.append(path[-1])
	return out
