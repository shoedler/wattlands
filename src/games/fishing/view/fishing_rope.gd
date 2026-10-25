class_name FishingRope
extends RefCounted
## The fishing line as a small verlet rope in view pixels (visual only, never game state):
## SEGMENTS links between the rod end and the fish or wobbler, pinned at both ends, stepped at
## STEP_S. Gravity sags it, with much more drag and buoyancy under the surface than in the air
## (the surface kink comes out of the difference) and the water flowing past a driving boat's
## line sweeping it back; its length follows the fight: strain pulls it to the straight
## distance, slack lets it bow (length()); in a fight no joint hangs below the lower end, and no
## joint turns more than BEND_MAX_DEG. The links only resist stretching. pixels() draws it as
## one clean 1 px curve (a smooth cubic through the rope's ends and its third points, held
## against sub-pixel jitter, thinned of L-corners and spikes), or one straight line when taut.

const SEGMENTS := 16
const ITERATIONS := 40
const STEP_S := 1.0 / 60.0
## Gravity (px/s^2) and the share of velocity kept per step, in the air and in the water.
const GRAVITY_AIR := 260.0
const GRAVITY_WATER := 120.0
const KEEP_AIR := 0.985
const KEEP_WATER := 0.86
## A line under strain (strain over slack) is also pulled this share toward its chord per step,
## so a fight's strain draws it straight; from TAUT_AT (strain over slack) it is drawn as one
## straight line.
const TAUT_PULL := 0.25
const TAUT_AT := 0.6
## The most extra length (a share of the straight distance) a fully slack line has.
const SLACK_MAX := 0.32
## The most a joint turns (degrees): sharper bends are eased toward the neighbours' midpoint.
const BEND_MAX_DEG := 20.0
## An anchor that jumps further than this (a cast, a rejoin) restarts the rope straight.
const RESET_PX := 90.0
## A joint's drawn position moves once its point is this far off it.
const HOLD_PX := 0.75
## Each frame the drawn anchors close this share of the gap to the true ones.
const ANCHOR_EASE := 0.5
## The drawn curve is sampled this finely (px along each link) before it is thinned.
const SAMPLE_PX := 0.25

var points: PackedVector2Array = PackedVector2Array()
## True while the line is drawn as one straight line (strain over slack past TAUT_AT).
var taut: bool = false
var _prev: PackedVector2Array = PackedVector2Array()
var _held: PackedVector2Array = PackedVector2Array()
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
	_held = points.duplicate()
	_acc = 0.0


## Advances `dt` seconds with the ends at `a` (the rod end) and `b` (pinned to the fish or the
## wobbler), the water's surface on row `surf_y`. `flow` (px/s^2, signed) is the water moving
## past the line (a driving boat's lines sweep back); with `no_sag` (a fight) no joint hangs
## below the lower end.
func step(
	a: Vector2,
	b: Vector2,
	slack: float,
	strain: float,
	dt: float,
	surf_y: float,
	flow: float = 0.0,
	no_sag: bool = false
) -> void:
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
	var pull := clampf(strain - slack, 0.0, 1.0)
	taut = pull >= TAUT_AT
	_acc = minf(_acc + maxf(dt, 0.0), 0.25)
	while _acc >= STEP_S:
		_acc -= STEP_S
		_integrate(surf_y, flow)
		_constrain(rest)
		if pull > 0.0:
			for i in range(1, SEGMENTS):
				var on_chord := _a.lerp(_b, float(i) / float(SEGMENTS))
				points[i] = points[i].lerp(on_chord, pull * TAUT_PULL)
		if no_sag:
			var low := maxf(_a.y, _b.y)
			for i in range(1, SEGMENTS):
				points[i].y = minf(points[i].y, low)
		_ease_bends()


func _integrate(surf_y: float, flow: float) -> void:
	for i in range(1, SEGMENTS):
		var p := points[i]
		var wet := p.y > surf_y
		var keep := KEEP_WATER if wet else KEEP_AIR
		var g := Vector2(flow, GRAVITY_WATER) if wet else Vector2(0.0, GRAVITY_AIR)
		var v := (p - _prev[i]) * keep
		_prev[i] = p
		points[i] = p + v + g * STEP_S * STEP_S


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


## Eases every joint that turns more than BEND_MAX_DEG halfway toward its neighbours' midpoint,
## so the line has no kinks or hooks.
func _ease_bends() -> void:
	var most := deg_to_rad(BEND_MAX_DEG)
	for _pass in 2:
		for i in range(1, SEGMENTS):
			var d0 := points[i] - points[i - 1]
			var d1 := points[i + 1] - points[i]
			if d0.length() < 1e-3 or d1.length() < 1e-3:
				continue
			if absf(d0.angle_to(d1)) > most:
				points[i] = points[i].lerp((points[i - 1] + points[i + 1]) * 0.5, 0.5)


## The line's pixels from the rod end to the far end: taut, one straight Bresenham line;
## otherwise one smooth cubic through both ends and the rope at a third and two thirds of its
## length (joints held against sub-pixel jitter), sampled finely, rounded and thinned to a clean
## 1 px curve whose step lengths change only gradually.
func pixels() -> Array[Vector2i]:
	if points.size() != SEGMENTS + 1:
		return []
	if _held.size() != points.size():
		_held = points.duplicate()
	for i in points.size():
		var last := i == 0 or i == points.size() - 1
		if last or _held[i].distance_to(points[i]) > HOLD_PX:
			_held[i] = points[i]
	var a := _held[0].round()
	var b := _held[_held.size() - 1].round()
	if taut:
		return FishingRig.bresenham(Vector2i(a.round()), Vector2i(b.round()))
	var q1 := along(_held, 1.0 / 3.0)
	var q2 := along(_held, 2.0 / 3.0)
	var c2 := (54.0 * q2 - 27.0 * q1 + 6.0 * a - 15.0 * b) / 18.0
	var c1 := (27.0 * q1 - 8.0 * a - b - 6.0 * c2) / 12.0
	var reach := a.distance_to(q1) + q1.distance_to(q2) + q2.distance_to(b)
	var steps := maxi(ceili(reach / SAMPLE_PX), 2)
	var out: Array[Vector2i] = [Vector2i(a.round())]
	for k in range(1, steps + 1):
		var u := float(k) / float(steps)
		var v := 1.0 - u
		var p := v * v * v * a + 3.0 * v * v * u * c1 + 3.0 * v * u * u * c2 + u * u * u * b
		var q := Vector2i(p.round())
		if q != out[-1]:
			_bridge(out, q)
	return pixel_perfect(out)


## The point a share `f` (0..1) along the joints `pts` by index.
static func along(pts: PackedVector2Array, f: float) -> Vector2:
	var at := f * float(pts.size() - 1)
	var i := mini(floori(at), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], at - float(i))


## Appends `q` to `out`, filling any gap from the last pixel with a straight run.
static func _bridge(out: Array[Vector2i], q: Vector2i) -> void:
	var last := out[-1]
	if absi(q.x - last.x) <= 1 and absi(q.y - last.y) <= 1:
		out.append(q)
		return
	var run := FishingRig.bresenham(last, q)
	run.pop_front()
	out.append_array(run)


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
