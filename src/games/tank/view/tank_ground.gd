class_name TankGround
extends RefCounted
## The road's relief (docs/games/tank.md v3 "Terrain relief"), cosmetic: the height of the road
## surface on the canvas, which the road band, the tank's wheels and the enemies follow. Two parts:
##   terrain  the rules' terrain points (a segment's [distance_m, grade_pct], the valley's terrain in
##            free roam) integrated into a height profile (once per segment, in STEP_M steps: the
##            trapezoids TankTerrain.height_at sums), taken relative to the hull and scaled
##            (TERRAIN_K) and saturated (TERRAIN_MAX px), so a climb tilts the tank and the road
##            ahead rises while the planes stay level
##   bumps    small seeded bumps: three waves (BUMPS: wavelength px, amplitude px) with phases from
##            the session seed, anchored to the road (they scroll with it)
## Canvas x is the Back layer's x (never mirrored): world art px = plane_x x 1.5 + canvas x.

## Art px per game metre (rules px per metre x 1.5).
const PX_PER_M_ART := TankConst.PX_PER_M * 1.5
const TERRAIN_K := 0.6
const TERRAIN_MAX := 10.0
## [wavelength art px, amplitude art px].
const BUMPS: Array[Vector2] = [Vector2(700, 2.4), Vector2(150, 1.6), Vector2(64, 0.8)]
## Height samples per metre of the integrated profile.
const STEP_M := 1.0

## The road line on the stage at the flat (the v3 layout: 385).
var base_y: float = 385.0
## Seeded phases of the bumps.
var phases: Array[float] = []
## This frame: the Back layer's world art x at canvas 0, the hull's canvas x and its metre, and the
## height profile (metres up per STEP_M from metre `prof_from`).
var world0: float = 0.0
var hull_cx: float = 0.0
var hull_m: float = 0.0
var prof: PackedFloat32Array = PackedFloat32Array()
var prof_from: float = 0.0
var _hull_h: float = 0.0
var _prof_key: String = ""


func _init(seed_value: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value) ^ 0x7e11
	for b in BUMPS:
		phases.append(rng.randf() * TAU)


## Sets the frame: `world0` the world art x at canvas 0, the hull at canvas x `p_hull_cx` and metre
## `p_hull_m`, and `points` the terrain ([metre, grade %]) over metres `from_m` .. `to_m` (a
## profile is integrated once per key: segment or map).
func frame(p_world0: float, p_hull_cx: float, p_hull_m: float, key: String, points: Array) -> void:
	world0 = p_world0
	hull_cx = p_hull_cx
	hull_m = p_hull_m
	if key != _prof_key:
		_prof_key = key
		_integrate(points)
	_hull_h = height_m(hull_m)


func _integrate(points: Array) -> void:
	prof = PackedFloat32Array()
	prof_from = 0.0
	if points.is_empty():
		return
	var first: Array = points[0]
	var last: Array = points[points.size() - 1]
	prof_from = float(first[0])
	var span := maxf(float(last[0]) - prof_from, 0.0)
	var n := int(span / STEP_M) + 1
	prof.resize(n + 1)
	var h := 0.0
	prof[0] = 0.0
	for i in n:
		var m := prof_from + (float(i) + 0.5) * STEP_M
		h += TankTerrain.grade_at(points, m) / 100.0 * STEP_M
		prof[i + 1] = h
	_hull_h = 0.0


## The integrated height (metres) at metre `m` (the grades held past either end).
func height_m(m: float) -> float:
	if prof.size() < 2:
		return 0.0
	var f := (m - prof_from) / STEP_M
	var n := prof.size() - 1
	if f <= 0.0:
		return prof[0] + f * (prof[1] - prof[0])
	if f >= float(n):
		return prof[n] + (f - float(n)) * (prof[n] - prof[n - 1])
	var i := floori(f)
	return lerpf(prof[i], prof[i + 1], f - float(i))


## The bumps' height (art px, up positive) at world art x `wx`.
func bumps(wx: float) -> float:
	var h := 0.0
	for i in BUMPS.size():
		h += BUMPS[i].y * sin(wx * TAU / BUMPS[i].x + phases[i])
	return h


## The terrain's height (art px, up positive) at canvas x relative to the hull, saturated.
func terrain(canvas_x: float) -> float:
	if prof.size() < 2:
		return 0.0
	var m := hull_m + (canvas_x - hull_cx) / PX_PER_M_ART
	var dh := (height_m(m) - _hull_h) * PX_PER_M_ART * TERRAIN_K
	return TERRAIN_MAX * tanh(dh / TERRAIN_MAX)


## How high the road stands at canvas x (art px above the flat road line).
func lift(canvas_x: float) -> float:
	return bumps(world0 + canvas_x) + terrain(canvas_x)


## The road surface's stage y at canvas x.
func y_at(canvas_x: float) -> float:
	return base_y - lift(canvas_x)
