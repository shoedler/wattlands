class_name SiegeFraming
extends RefCounted
## The Siege camera's framing math (brief 3 "Camera"): pure pinhole projection onto a 16:9
## picture, so the distance can be chosen from what must be on screen instead of from a width
## at the target. The fort including its corner towers fills FORT_WIDTH_SHARE of the picture
## width, so the Valley road shows as far below the gate as the pitch allows.

const SCREEN := Vector2(1920.0, 1080.0)
## A corner tower is an 8.4 m wide cap on an 8 m block, centred on the wall corner.
const TOWER_HALF_M := 4.2


## The fort's box in world space (walls and corner towers; the gate faces +Z).
static func fort_box(map: SiegeMap) -> AABB:
	var half := map.fort_size * 0.5 + Vector2.ONE * TOWER_HALF_M
	var fort: Dictionary = map.data.get("fort", {})
	var h := float(fort.get("wall_h_m", 6.0)) + SiegeFortBuilder.CORNER_EXTRA_H
	return AABB(Vector3(-half.x, 0.0, -half.y), Vector3(half.x * 2.0, h, half.y * 2.0))


## The screen position (px of a 1920 x 1080 picture) of the world point `p` seen by a camera that
## orbits `target` at `distance`, `pitch_deg` above the horizon, looking toward -Z.
static func project(
	p: Vector3, target: Vector3, distance: float, pitch_deg: float, fov_deg: float
) -> Vector2:
	var pitch := deg_to_rad(pitch_deg)
	var cam := target + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	var rel := p - cam
	var fwd := Vector3(0.0, -sin(pitch), -cos(pitch))
	var up := Vector3(0.0, cos(pitch), -sin(pitch))
	var depth := rel.dot(fwd)
	var t := tan(deg_to_rad(fov_deg) * 0.5)
	var aspect := SCREEN.x / SCREEN.y
	return Vector2(
		SCREEN.x * 0.5 + rel.x / depth / (t * aspect) * SCREEN.x * 0.5,
		SCREEN.y * 0.5 - rel.dot(up) / depth / t * SCREEN.y * 0.5
	)


## The share of the picture width the box spans on screen (all eight corners projected).
static func width_share(
	box: AABB, target: Vector3, distance: float, pitch_deg: float, fov_deg: float
) -> float:
	var lo := INF
	var hi := -INF
	for i in 8:
		var q := project(box.get_endpoint(i), target, distance, pitch_deg, fov_deg)
		lo = minf(lo, q.x)
		hi = maxf(hi, q.x)
	return (hi - lo) / SCREEN.x


## The distance at which `box` spans `share` of the picture width (the share falls as the camera
## moves away, so the answer is found by bisection).
static func fit_distance(
	box: AABB, target: Vector3, pitch_deg: float, fov_deg: float, share: float
) -> float:
	var near := 20.0
	var far := 800.0
	for i in 48:
		var mid := (near + far) * 0.5
		if width_share(box, target, mid, pitch_deg, fov_deg) > share:
			near = mid
		else:
			far = mid
	return (near + far) * 0.5
