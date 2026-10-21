class_name ScrollingChain
extends Node2D
## A code-drawn chain, belt or track that scrolls along a path with a signed speed signal
## (BRIEF 3.10 "chains scroll"; Fishing's dotted chain loop, Tank's drive chains and track
## links). Links are short dashes `link_px` long, every `pitch_px` along the path,
## alternating `color_a` and `color_b`; they move along the path at `max_px_s` per second at
## |speed| = 1 (negative runs backwards). Pixel-snapped, drawn with draw_line (no texture).
##
## [codeblock]
## var chain := ScrollingChain.new()
## chain.set_loop(Vector2(10, 20), 4.0, Vector2(40, 20), 6.0)   # two sprockets
## chain.max_px_s = 30.0
## chain.speed = cadence_rpm / 120.0
## [/codeblock]

## Drive signal, clamped to -1..1 (NaN counts as 0).
var speed: float = 0.0:
	set(value):
		speed = 0.0 if is_nan(value) else clampf(value, -1.0, 1.0)

## Art pixels per second along the path at |speed| = 1.
var max_px_s: float = 24.0:
	set(value):
		max_px_s = maxf(value, 0.0)

## Seconds for the motion to follow `speed` (0 = at once).
var inertia_s: float = 0.0:
	set(value):
		inertia_s = maxf(value, 0.0)

## The path in local art pixels.
var points: PackedVector2Array = PackedVector2Array():
	set(value):
		points = value
		_rebuild()

## The path closes back to its first point (a loop).
var closed: bool = true:
	set(value):
		closed = value
		_rebuild()

## Spacing between link starts, art pixels.
var pitch_px: float = 4.0:
	set(value):
		pitch_px = maxf(value, 0.5)
		queue_redraw()

## Drawn length of each link (<= pitch_px for gaps; 1 for a dotted chain).
var link_px: float = 2.0:
	set(value):
		link_px = maxf(value, 0.0)
		queue_redraw()

## Line width in art pixels.
var width_px: float = 1.0:
	set(value):
		width_px = maxf(value, 1.0)
		queue_redraw()

var color_a: Color = Color("#c9c3b8"):
	set(value):
		color_a = value
		queue_redraw()

## Every second link (use color_a again for a uniform chain).
var color_b: Color = Color("#6b6660"):
	set(value):
		color_b = value
		queue_redraw()

## Round link positions to whole art pixels.
var pixel_snap: bool = true

## Call tick(delta) from _process.
var auto_process: bool = true

var _travel: float = 0.0
var _current: float = 0.0
var _cum: PackedFloat32Array = PackedFloat32Array()
var _path: PackedVector2Array = PackedVector2Array()


func _process(delta: float) -> void:
	if auto_process:
		tick(delta)


## Advance by dt seconds.
func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	if inertia_s > 0.0:
		_current += (speed - _current) * (1.0 - exp(-dt / inertia_s))
	else:
		_current = speed
	var before := _travel
	_travel = fposmod(_travel + _current * max_px_s * dt, effective_pitch() * 2.0)
	if not is_equal_approx(before, _travel):
		queue_redraw()


## Set speed from a value and the value that means full speed.
func drive(value: float, full_scale: float) -> void:
	speed = value / full_scale if full_scale != 0.0 else 0.0


## The scroll position, 0..2 * effective_pitch() (the pattern repeats after two links).
func travel() -> float:
	return _travel


## The link spacing actually used: pitch_px on open paths; on closed paths the nearest
## spacing that fits an even number of links exactly into the loop, so it has no seam.
func effective_pitch() -> float:
	var length := path_length()
	if not closed or length <= 0.0:
		return pitch_px
	var pairs := maxi(int(roundf(length / (2.0 * pitch_px))), 1)
	return length / float(pairs * 2)


## A belt around two pulleys: the convex hull of both circles (sprocket centres and radii in
## art pixels). `segments` points per circle.
func set_loop(
	center_a: Vector2, radius_a: float, center_b: Vector2, radius_b: float, segments: int = 16
) -> void:
	set_belt(
		PackedVector2Array([center_a, center_b]), PackedFloat32Array([radius_a, radius_b]), segments
	)


## A belt around any number of pulleys, such as a tank track round its drive sprocket, idler
## and road wheels: the convex hull of all circles (centres and radii in art pixels, one radius
## per centre), clockwise on screen. `segments` points per circle.
func set_belt(centers: PackedVector2Array, radii: PackedFloat32Array, segments: int = 16) -> void:
	if centers.is_empty() or centers.size() != radii.size():
		push_error(
			(
				"ScrollingChain: set_belt needs one radius per centre (%d centres, %d radii)"
				% [centers.size(), radii.size()]
			)
		)
		return
	var pts := PackedVector2Array()
	var n := maxi(segments, 4)
	for i in n:
		var a := TAU * float(i) / float(n)
		for k in centers.size():
			pts.append(centers[k] + Vector2(cos(a), sin(a)) * maxf(radii[k], 0.0))
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	# Clockwise on screen (y down), so positive speed moves the links the way a SpinningPart
	# with positive speed turns.
	if screen_area(hull) < 0.0:
		hull.reverse()
	closed = true
	points = hull


## Twice the signed area of a polygon in screen coordinates (y down): positive when its
## points run clockwise on screen.
static func screen_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a


## Total path length in art pixels.
func path_length() -> float:
	return _cum[_cum.size() - 1] if _cum.size() > 0 else 0.0


## The point at distance d along the path (wrapped on closed paths, clamped on open ones).
func point_at(d: float) -> Vector2:
	if _path.is_empty():
		return Vector2.ZERO
	if _path.size() == 1:
		return _path[0]
	var length := path_length()
	if length <= 0.0:
		return _path[0]
	d = fposmod(d, length) if closed else clampf(d, 0.0, length)
	var i := _segment_index(d)
	var seg_len := _cum[i + 1] - _cum[i]
	var t := (d - _cum[i]) / seg_len if seg_len > 0.0 else 0.0
	return _path[i].lerp(_path[i + 1], t)


## Link starts for the current scroll: [{"d": float (distance along the path), "pos":
## Vector2, "color_index": 0 or 1}].
func links() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var length := path_length()
	if length <= 0.0:
		return out
	var pitch := effective_pitch()
	var count := int(roundf(length / pitch)) if closed else int(floor(length / pitch)) + 1
	if count <= 0:
		return out
	var start := _travel
	if not closed:
		start = fposmod(_travel, pitch * 2.0) - pitch * 2.0
	for k in count + (0 if closed else 2):
		var d := start + float(k) * pitch
		if not closed and d < 0.0:
			continue
		if not closed and d > length:
			break
		# The color pattern moves with the links: two links make one period of 2 * pitch.
		out.append({"d": d, "pos": point_at(d), "color_index": k % 2})
	return out


func _draw() -> void:
	if path_length() <= 0.0:
		return
	for link: Dictionary in links():
		var d0: float = link["d"]
		var col := color_a if int(link["color_index"]) == 0 else color_b
		if link_px <= 1.0:
			var p := _snap(point_at(d0))
			draw_rect(Rect2(p, Vector2(width_px, width_px)), col)
			continue
		var pts := _sub_path(d0, d0 + link_px - 1.0)
		for j in pts.size() - 1:
			draw_line(
				_snap(pts[j]) + Vector2(0.5, 0.5),
				_snap(pts[j + 1]) + Vector2(0.5, 0.5),
				col,
				width_px
			)


func _snap(p: Vector2) -> Vector2:
	return p.floor() if pixel_snap else p


func _sub_path(d0: float, d1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(point_at(d0))
	var length := path_length()
	# Corner points strictly between d0 and d1 (unwrapped on closed paths).
	var last := _cum.size() - 1 if closed else _cum.size() - 2
	for lap: float in [0.0, length] if closed else [0.0]:
		for i in range(1, last + 1):
			var c: float = _cum[i] + lap
			if c > d0 and c < d1:
				out.append(_path[i])
	out.append(point_at(d1))
	return out


func _segment_index(d: float) -> int:
	var lo := 0
	var hi := _cum.size() - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _cum[mid] <= d:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _rebuild() -> void:
	_path = points.duplicate()
	if closed and _path.size() > 2:
		_path.append(_path[0])
	_cum = PackedFloat32Array()
	var total := 0.0
	for i in _path.size():
		if i > 0:
			total += _path[i - 1].distance_to(_path[i])
		_cum.append(total)
	queue_redraw()
