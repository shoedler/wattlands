class_name SpinningPart
extends Node2D
## A part that turns with a signed speed signal: gears, flywheels, cranks, reels, wheels
## (BRIEF 3.9; "animate by parts", BRIEF 3.10).
##
## `speed` runs from -1 to 1 (clamped). Positive speed turns clockwise on screen, negative
## turns the other way (Fishing's reel on a run). At |speed| = 1 the part makes `max_rpm`
## revolutions per minute; `ratio` scales that for gear trains (2.0 twice as fast, -1.0 a
## meshing gear that turns the other way). The part rotates itself, so a Sprite2D child turns
## with it, or set `texture` to draw one centred on the pivot.
##
## Time: tick(dt) advances the angle; with `auto_process` (default) _process(delta) calls it.
## A view that drives everything from sim time sets auto_process = false and calls tick().
## [codeblock]
## var crank := SpinningPart.new()
## crank.texture = preload("res://assets/fishing/sprites/rig_crank.png")
## crank.max_rpm = 120.0            # speed = cadence / 120 turns it at the cadence
## crank.speed = cadence_rpm / 120.0
## [/codeblock]

## Drive signal, clamped to -1..1 (NaN counts as 0).
var speed: float = 0.0:
	set(value):
		speed = 0.0 if is_nan(value) else clampf(value, -1.0, 1.0)

## Revolutions per minute at |speed| = 1.
var max_rpm: float = 60.0:
	set(value):
		max_rpm = maxf(value, 0.0)

## Gear ratio relative to the drive signal; negative reverses (meshing gears).
var ratio: float = 1.0

## Angle offset in degrees, added to the turned angle.
var phase_deg: float = 0.0:
	set(value):
		phase_deg = value
		_apply()

## Seconds for the turning speed to follow `speed` (0 = at once). Gives flywheels inertia.
var inertia_s: float = 0.0:
	set(value):
		inertia_s = maxf(value, 0.0)

## Show the angle in steps of 360 / snap_steps degrees (0 = smooth). A gear with n teeth
## looks crisp at n * 2 steps; small sprites read better with 8 or 16.
var snap_steps: int = 0:
	set(value):
		snap_steps = maxi(value, 0)
		_apply()

## Optional texture drawn centred on the pivot (children turn as well).
var texture: Texture2D = null:
	set(value):
		texture = value
		queue_redraw()

## Call tick(delta) from _process.
var auto_process: bool = true

var _revolutions: float = 0.0
var _current: float = 0.0


func _ready() -> void:
	_apply()


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
	_revolutions += _current * ratio * max_rpm / 60.0 * dt
	_apply()


## Set speed from a value and the value that means full speed (e.g. cadence and 120 rpm).
func drive(value: float, full_scale: float) -> void:
	speed = value / full_scale if full_scale != 0.0 else 0.0


## The turning speed after inertia, -1..1 (before ratio).
func current_speed() -> float:
	return _current


## Revolutions turned so far, signed (clockwise positive), without phase.
func revolutions() -> float:
	return _revolutions


## The shown angle in radians, 0..TAU (with phase and snapping).
func angle() -> float:
	var a := fposmod(TAU * _revolutions + deg_to_rad(phase_deg), TAU)
	if snap_steps > 0:
		var step := TAU / float(snap_steps)
		a = fposmod(roundf(a / step) * step, TAU)
	return a


## Reset the turned angle (and the inertia state) to zero.
func reset() -> void:
	_revolutions = 0.0
	_current = 0.0
	_apply()


func _apply() -> void:
	rotation = angle()


func _draw() -> void:
	if texture != null:
		draw_texture(texture, -(texture.get_size() * 0.5).floor())
