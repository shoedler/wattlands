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
