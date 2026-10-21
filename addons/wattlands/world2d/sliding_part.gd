class_name SlidingPart
extends Node2D
## A part that slides along an axis with a signed speed signal: pistons, rods, shell
## cradles (RECIPROCATE) and chains, track links, belts (SCROLL) (BRIEF 3.9, 3.10).
##
## `speed` runs from -1 to 1 (clamped); negative runs the motion backwards. The part moves
## itself: position = rest_position + axis * offset(). rest_position is taken from
## `position` when the part enters the tree (or on the first tick outside the tree) unless
## you set it; set it again when you move the part's mount.
##
## - RECIPROCATE: offset swings between 0 and `travel_px` along `axis` (a smooth cosine
##   stroke, starting at 0), `max_cps` full out-and-back cycles per second at |speed| = 1.
## - SCROLL: offset grows by `max_px_s` per second at |speed| = 1 and wraps at `wrap_px`
##   (the link pitch or tile width), so a row of links drawn as children loops forever.
##
## Time: tick(dt), called from _process while `auto_process` is on.
## [codeblock]
## var piston := SlidingPart.new()
## piston.axis = Vector2.UP
## piston.travel_px = 6.0
## piston.max_cps = 2.0
## piston.speed = cadence_rpm / 120.0
## [/codeblock]

enum Mode { RECIPROCATE, SCROLL }

## RECIPROCATE (pistons) or SCROLL (chains, track links).
var mode: Mode = Mode.RECIPROCATE:
	set(value):
		mode = value
		_apply()

## Drive signal, clamped to -1..1 (NaN counts as 0).
var speed: float = 0.0:
	set(value):
		speed = 0.0 if is_nan(value) else clampf(value, -1.0, 1.0)

## Direction of travel (normalized; a zero vector means Vector2.RIGHT).
var axis: Vector2 = Vector2.RIGHT:
	set(value):
		axis = value.normalized() if value.length_squared() > 0.0 else Vector2.RIGHT
		_apply()

## RECIPROCATE: stroke length in art pixels (offset stays within 0..travel_px).
var travel_px: float = 8.0:
	set(value):
		travel_px = maxf(value, 0.0)
		_apply()

## RECIPROCATE: full cycles per second at |speed| = 1.
var max_cps: float = 2.0:
	set(value):
		max_cps = maxf(value, 0.0)

## SCROLL: art pixels per second at |speed| = 1.
var max_px_s: float = 32.0:
	set(value):
		max_px_s = maxf(value, 0.0)

## SCROLL: the offset wraps into 0..wrap_px (0 = never wraps).
var wrap_px: float = 8.0:
	set(value):
		wrap_px = maxf(value, 0.0)
		_apply()

## Phase offset as a fraction of a cycle (RECIPROCATE) or of wrap_px (SCROLL), 0..1.
## Two pistons with phases 0 and 0.5 move in opposition.
var phase: float = 0.0:
	set(value):
		phase = value
		_apply()

## Seconds for the motion to follow `speed` (0 = at once).
var inertia_s: float = 0.0:
	set(value):
		inertia_s = maxf(value, 0.0)

## Round the offset to whole art pixels.
var pixel_snap: bool = true:
	set(value):
		pixel_snap = value
		_apply()

## The mount position the offset is added to (see the class description).
var rest_position: Vector2 = Vector2.ZERO:
	set(value):
		rest_position = value
		_rest_set = true
		_apply()

## Call tick(delta) from _process.
var auto_process: bool = true

var _travel: float = 0.0
var _current: float = 0.0
var _rest_set: bool = false


func _enter_tree() -> void:
	_capture_rest()
	_apply()


func _process(delta: float) -> void:
	if auto_process:
		tick(delta)


## Advance by dt seconds.
func tick(dt: float) -> void:
	_capture_rest()
	if dt <= 0.0:
		return
	if inertia_s > 0.0:
		_current += (speed - _current) * (1.0 - exp(-dt / inertia_s))
	else:
		_current = speed
	if mode == Mode.RECIPROCATE:
		_travel += _current * max_cps * dt
	else:
		_travel += _current * max_px_s * dt
		if wrap_px > 0.0:
			# Keep the accumulator small; the wrapped offset is unchanged.
			_travel = fposmod(_travel, wrap_px)
	_apply()


## Set speed from a value and the value that means full speed.
func drive(value: float, full_scale: float) -> void:
	speed = value / full_scale if full_scale != 0.0 else 0.0


## The motion speed after inertia, -1..1.
func current_speed() -> float:
	return _current


## RECIPROCATE: cycles run so far (signed). SCROLL: pixels scrolled (wrapped when wrap_px > 0).
func travel() -> float:
	return _travel


## The current offset along `axis` in art pixels (snapped when pixel_snap).
func offset() -> float:
	var o := 0.0
	if mode == Mode.RECIPROCATE:
		o = travel_px * 0.5 * (1.0 - cos(TAU * (_travel + phase)))
	else:
		o = _travel + phase * wrap_px
		if wrap_px > 0.0:
			o = fposmod(o, wrap_px)
	if pixel_snap:
		o = roundf(o)
		if mode == Mode.SCROLL and wrap_px > 0.0 and o >= wrap_px:
			o = 0.0
	return o


## The offset as a vector (axis * offset()).
func offset_vector() -> Vector2:
	return axis * offset()


## Reset the motion to the start of its cycle.
func reset() -> void:
	_travel = 0.0
	_current = 0.0
	_apply()


func _capture_rest() -> void:
	if not _rest_set:
		rest_position = position


func _apply() -> void:
	if not _rest_set:
		return
	position = rest_position + offset_vector()
