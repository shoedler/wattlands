class_name WorkoutCourse
extends RefCounted
## Rolling road's procedural course (BRIEF 3.7): a [distance_m, grade_pct] profile seeded
## from the session content, so every rider and every peer gets the same road. Pure and
## deterministic: the same spec always gives the same profile.
##
## The grade of point i holds from its distance until the next point (a step profile).
## The profile is a sum of three seeded sine waves, normalized to exactly span
## [min_grade_pct, max_grade_pct] and rounded to 0.1 %.
## The optional "window_m" (a multiple of step_m, at most length_m; default length_m) is the
## stretch that spans the full range: the road is generated over [0, window_m] and then repeats
## it back and forth (mirrored, so the grade never jumps at a seam). A window shorter than the
## distance any rider covers in the phase puts both extremes on everyone's road (W3 WO-3: over
## 50 km, Rolling road's first -2 % point lay at 36 km, beyond every rider's 30 minutes).

const DEFAULT_SPEC := {
	"seed": 1, "length_m": 50000.0, "step_m": 250.0, "min_grade_pct": -2.0, "max_grade_pct": 6.0,
}
const SPEC_KEYS: Array[String] = ["seed", "length_m", "step_m", "min_grade_pct", "max_grade_pct"]
## Optional spec keys.
const OPTIONAL_KEYS: Array[String] = ["window_m"]
## Wavelength ranges (m) and weights of the three waves.
const WAVES := [[1500.0, 3000.0, 0.45], [3500.0, 7000.0, 0.35], [8000.0, 15000.0, 0.2]]

var seed: int = 1
var length_m: float = 50000.0
var step_m: float = 250.0
var min_grade_pct: float = -2.0
var max_grade_pct: float = 6.0
## The stretch normalized to [min_grade_pct, max_grade_pct], repeated back and forth.
var window_m: float = 50000.0
## [[distance_m, grade_pct], ...], distance ascending from 0.
var profile: Array = []
## Elevation (m) at each profile point, relative to the start.
var elevation: PackedFloat64Array = PackedFloat64Array()


## Problems with a course spec ([] when valid).
static func spec_errors(spec: Variant) -> Array[String]:
	var errs: Array[String] = []
	if not (spec is Dictionary):
		return ["course: must be an object"]
	var d: Dictionary = spec
	for key: Variant in d.keys():
		if not SPEC_KEYS.has(str(key)) and not OPTIONAL_KEYS.has(str(key)):
			errs.append("course.%s: unknown key" % key)
	for key in SPEC_KEYS:
		if not d.has(key) or not WorkoutCourse._is_number(d[key]):
			errs.append("course.%s: must be a number" % key)
	if d.has("window_m") and not WorkoutCourse._is_number(d["window_m"]):
		errs.append("course.window_m: must be a number")
	if not errs.is_empty():
		return errs
	if float(d["length_m"]) < 1000.0:
		errs.append("course.length_m: must be >= 1000")
	if float(d["step_m"]) < 50.0 or float(d["step_m"]) > 1000.0:
		errs.append("course.step_m: must be within 50..1000")
	if float(d["min_grade_pct"]) < -10.0 or float(d["max_grade_pct"]) > 16.0:
		errs.append("course: grades must stay within -10..+16 % (BRIEF 4.6.6)")
	if float(d["min_grade_pct"]) >= float(d["max_grade_pct"]):
		errs.append("course: min_grade_pct must be below max_grade_pct")
	if d.has("window_m") and errs.is_empty():
		var w := float(d["window_m"])
		var steps := w / float(d["step_m"])
		if w < 4.0 * float(d["step_m"]) or w > float(d["length_m"]) or absf(steps - roundf(steps)) > 1e-6:
			errs.append("course.window_m: must be a multiple of step_m, at least 4 steps and at most length_m")
	return errs


## A course from a validated spec (see spec_errors).
static func from_spec(spec: Dictionary) -> WorkoutCourse:
	var c := WorkoutCourse.new()
	c.seed = int(spec.get("seed", DEFAULT_SPEC["seed"]))
	c.length_m = float(spec.get("length_m", DEFAULT_SPEC["length_m"]))
	c.step_m = float(spec.get("step_m", DEFAULT_SPEC["step_m"]))
	c.min_grade_pct = float(spec.get("min_grade_pct", DEFAULT_SPEC["min_grade_pct"]))
	c.max_grade_pct = float(spec.get("max_grade_pct", DEFAULT_SPEC["max_grade_pct"]))
	c.window_m = float(spec.get("window_m", c.length_m))
	c._generate()
	return c


## A course rebuilt from an existing profile (for example a plan's course_profile).
static func from_profile(points: Array) -> WorkoutCourse:
	var c := WorkoutCourse.new()
	for pt: Variant in points:
		if pt is Array and (pt as Array).size() >= 2:
			c.profile.append([float(pt[0]), float(pt[1])])
	if c.profile.size() >= 2:
		c.step_m = float(c.profile[1][0]) - float(c.profile[0][0])
		c.length_m = float(c.profile[c.profile.size() - 1][0])
	c._integrate()
	return c


func _generate() -> void:
	var rng := SeededRng.make(seed)
	var waves: Array = []
	for w: Array in WAVES:
		var wavelength := SeededRng.range_f(rng, float(w[0]), float(w[1]))
		var phase := SeededRng.range_f(rng, 0.0, TAU)
		waves.append([wavelength, phase, float(w[2])])
	var n := int(floor(length_m / step_m)) + 1
	var window_steps := maxi(int(roundf(minf(window_m, length_m) / step_m)), 1)
	var raw := PackedFloat64Array()
	raw.resize(n)
	var lo := INF
	var hi := -INF
	for i in n:
		# Back and forth over the window: 0..W, then W-1..0, then 1..W, ...
		var k := posmod(i, 2 * window_steps)
		if k > window_steps:
			k = 2 * window_steps - k
		var d := float(k) * step_m
		var v := 0.0
		for w: Array in waves:
			v += float(w[2]) * sin(TAU * d / float(w[0]) + float(w[1]))
		raw[i] = v
		lo = minf(lo, v)
		hi = maxf(hi, v)
	profile.clear()
	var span := maxf(hi - lo, 1e-9)
	for i in n:
		var f := (raw[i] - lo) / span
		var g := snappedf(lerpf(min_grade_pct, max_grade_pct, f), 0.1)
		g = clampf(g, min_grade_pct, max_grade_pct)
		profile.append([float(i) * step_m, g])
	_integrate()


func _integrate() -> void:
	elevation = PackedFloat64Array()
	elevation.resize(profile.size())
	var e := 0.0
	for i in profile.size():
		elevation[i] = e
		if i + 1 < profile.size():
			var seg := float(profile[i + 1][0]) - float(profile[i][0])
			e += seg * float(profile[i][1]) / 100.0


func _index_at(d: float) -> int:
	if profile.is_empty() or d <= 0.0:
		return 0
	var i := int(floor(d / maxf(step_m, 1.0)))
	i = clampi(i, 0, profile.size() - 1)
	# Guard against uneven spacing (profiles from plans).
	while i + 1 < profile.size() and float(profile[i + 1][0]) <= d:
		i += 1
	while i > 0 and float(profile[i][0]) > d:
		i -= 1
	return i


## Grade (%) at distance d (step profile; the last grade holds past the end).
func grade_at(d: float) -> float:
	if profile.is_empty():
		return 0.0
	return float(profile[_index_at(d)][1])


## Elevation (m) at distance d, relative to the start.
func elevation_at(d: float) -> float:
	if profile.is_empty():
		return 0.0
	var dd := maxf(d, 0.0)
	var i := _index_at(dd)
	return elevation[i] + (dd - float(profile[i][0])) * float(profile[i][1]) / 100.0


func min_grade() -> float:
	var g := INF
	for pt: Array in profile:
		g = minf(g, float(pt[1]))
	return g


func max_grade() -> float:
	var g := -INF
	for pt: Array in profile:
		g = maxf(g, float(pt[1]))
	return g


## The profile in the plan's course_profile format (a deep copy).
func to_course_profile() -> Array:
	return profile.duplicate(true)


static func _is_number(v: Variant) -> bool:
	return v is float or v is int
