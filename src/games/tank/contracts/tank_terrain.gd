class_name TankTerrain
extends RefCounted
## The one terrain sampler (brief 2.3 pattern 4; G2 contract change). A mission segment's
## [distance_m, grade_pct] points (the `course_profile` format), interpolated linearly by the
## distance driven into the segment and held past either end. The rules call `for_segment` for the
## grade the speed model rolls on (TankHullState.grade_pct) and the director calls it for the
## course_grade it pushes, so the tank speeds up and slows down on exactly the hill the rider's
## trainer feels. Grades are before difficulty.


## The raw grade in % at `distance_m`: the first grade before the first point, the last past the
## last one, 0 for a segment with no terrain.
static func grade_at(points: Array, distance_m: float) -> float:
	if points.is_empty():
		return 0.0
	var first: Array = points[0]
	if distance_m <= float(first[0]):
		return float(first[1])
	for i in range(1, points.size()):
		var a: Array = points[i - 1]
		var b: Array = points[i]
		if distance_m <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			if span <= 0.0:
				return float(b[1])
			return lerpf(float(a[1]), float(b[1]), (distance_m - float(a[0])) / span)
	return float((points[points.size() - 1] as Array)[1])


## v3 (brief "Terrain relief"): the road's height in game metres at `distance_m`, relative to
## distance 0: the integral of grade_at / 100 over the distance (the same points, so the height
## profile and the grade the trainer feels never disagree). Exact for the piecewise-linear grade:
## trapezoids between points, the held end grades outside them; negative distances run back from 0.
## Raw grades (before any clamp); pure. The view scales it into its relief (TankConst.m_to_px for
## world px) and may add seeded cosmetic bumps; the rules may use it for the aim solver.
static func height_at(points: Array, distance_m: float) -> float:
	if points.is_empty() or is_zero_approx(distance_m):
		return 0.0
	if distance_m < 0.0:
		return -_rise(points, distance_m, 0.0)
	return _rise(points, 0.0, distance_m)


## The height gained from `x0` to `x1` (x0 <= x1) over the grade profile, in metres.
static func _rise(points: Array, x0: float, x1: float) -> float:
	var xs: Array[float] = [x0]
	for p: Variant in points:
		var x := float((p as Array)[0])
		if x > x0 and x < x1:
			xs.append(x)
	xs.append(x1)
	var h := 0.0
	for i in range(1, xs.size()):
		var a := xs[i - 1]
		var b := xs[i]
		h += (grade_at(points, a) + grade_at(points, b)) * 0.5 * (b - a) / 100.0
	return h


## The grade the tank rolls on and the director pushes: `grade_at` clamped to the warm-up terrain
## range (stations.json terrain.warmup_grade_pct, 0..+2%) in WARMUP kinds and to -3..+6%
## otherwise (BRIEF 4.6.6, 4.6.8).
static func for_segment(c: TankContent, segment: int, distance_m: float, warmup: bool) -> float:
	var pts: Variant = c.segment(segment).get("terrain", [])
	var g := grade_at(pts if pts is Array else [], distance_m)
	if warmup:
		var w: Array = c.value("stations", "terrain.warmup_grade_pct", [0, 2])
		return clampf(g, float(w[0]), float(w[1]))
	return clampf(g, TankContentSchema.TERRAIN_MIN_PCT, TankContentSchema.TERRAIN_MAX_PCT)


## Free roam (brief 2.10): the grade under the hull's centre at `map_m` on `map` travelling `dir`
## (the valley's terrain negated westward), clamped to valley.json terrain_pct (-3..+5%) in WORK
## and to the warm-up terrain range in WARMUP kinds (the drive-out), like for_segment.
static func for_roam(
	c: TankContent, map: TankRoamMap, map_m: float, dir: int, warmup: bool
) -> float:
	if map == null:
		return 0.0
	var g := map.grade_at(map_m, dir)
	if warmup:
		var w: Array = c.value("stations", "terrain.warmup_grade_pct", [0, 2])
		return clampf(g, float(w[0]), float(w[1]))
	var r: Array = c.value("valley", "terrain_pct", [-3, 5])
	var lo := maxf(float(r[0]), TankContentSchema.TERRAIN_MIN_PCT)
	var hi := minf(float(r[1]), TankContentSchema.TERRAIN_MAX_PCT)
	return clampf(g, lo, hi)
