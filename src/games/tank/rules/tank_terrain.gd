class_name TankTerrain
extends RefCounted
## The terrain grade under the tank (brief 2.3 pattern 4): a mission segment's [distance_m,
## grade_pct] points, interpolated linearly by the distance driven into the segment and held past
## the last point (the `course_profile` format). Grades are before difficulty. Owner: rules.


## The grade in % at `distance_m` into the segment: the first grade before the first point, the
## last past the last one, 0 for a segment with no terrain.
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
