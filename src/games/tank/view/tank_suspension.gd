class_name TankSuspension
extends RefCounted
## Per-wheel suspension on the ground (docs/games/tank.md v3 "Terrain relief"): every road wheel rides its own arm and
## spring and follows the ground under it within its travel (up `up` px, down `droop` px); the hull
## (everything above the suspension) rotates as a whole by the least-squares fit of the ground under
## the wheels and rides up by half the wheels' mean compression. Pure functions; the view keeps the
## springs' bob (Spring) itself. Sprite px for the vehicle, stage px for the world.


## The hull's pose for a vehicle whose ground centre (sprite (size.x / 2, ground_row)) stands at
## stage x `cx` on `ground` (Callable: stage x -> the road's stage y), wheels `wheels` (Vector3: rest
## centre x, y and radius, sprite px): {rot (radians, positive turns
## clockwise: nose down when facing right), at (Vector2, the ground centre on the fit)}.
static func fit(wheels: Array[Vector3], size: Vector2, cx: float, ground: Callable) -> Dictionary:
	var half := size.x * 0.5
	var n := float(maxi(wheels.size(), 1))
	var mx := 0.0
	var my := 0.0
	var xs: Array[float] = []
	var ys: Array[float] = []
	for w in wheels:
		var x := cx + (w.x - half)
		var y := float(ground.call(x))
		xs.append(x)
		ys.append(y)
		mx += x
		my += y
	mx /= n
	my /= n
	var sxx := 0.0
	var sxy := 0.0
	for i in xs.size():
		sxx += (xs[i] - mx) * (xs[i] - mx)
		sxy += (xs[i] - mx) * (ys[i] - my)
	var slope := sxy / maxf(sxx, 0.001)
	return {"rot": atan(slope), "at": Vector2(cx, my + slope * (cx - mx))}


## The sprite -> stage transform of a hull standing with its ground centre at `at`, turned `rot`
## about it, raised `lift` px along its own up.
static func xform(
	size: Vector2, ground_row: float, at: Vector2, rot: float, lift: float
) -> Transform2D:
	var piv := Vector2(size.x * 0.5, ground_row)
	var xf := Transform2D(rot, Vector2.ZERO)
	xf.origin = at + Vector2(0, -lift).rotated(rot) - xf.basis_xform(piv)
	return xf


## The road wheels' centres (sprite px) for the hull at `xf` on `ground`: each wheel's mount
## follows the ground under it (its rim plus the track `track_t` on the road), clamped to its
## travel (`up` px compressed, `droop` px hanging).
static func wheel_centres(
	wheels: Array[Vector3],
	xf: Transform2D,
	ground: Callable,
	track_t: float,
	up: float,
	droop: float
) -> Array[Vector2]:
	var inv := xf.affine_inverse()
	var down := xf.basis_xform(Vector2.DOWN).normalized()
	var out: Array[Vector2] = []
	for w in wheels:
		var mount := xf * Vector2(w.x, w.y)
		var want := float(ground.call(mount.x)) - w.z - track_t
		var s := clampf((want - mount.y) / maxf(down.y, 0.5), -up, droop)
		out.append(inv * (mount + down * s))
	return out


## Half the wheels' mean compression (px): how far the springs lift the hull.
static func lift_of(wheels: Array[Vector3], centres: Array[Vector2]) -> float:
	if centres.is_empty():
		return 0.0
	var comp := 0.0
	for i in centres.size():
		comp += wheels[i].y - centres[i].y
	return comp / float(centres.size()) * 0.5


## The least-squares angle (radians) of the points (stage px): the hull angle the contacts fit.
static func fit_angle(points: Array[Vector2]) -> float:
	var n := float(maxi(points.size(), 1))
	var m := Vector2.ZERO
	for q in points:
		m += q
	m /= n
	var sxx := 0.0
	var sxy := 0.0
	for q2 in points:
		sxx += (q2.x - m.x) * (q2.x - m.x)
		sxy += (q2.x - m.x) * (q2.y - m.y)
	return atan(sxy / maxf(sxx, 0.001))
