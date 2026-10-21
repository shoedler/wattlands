class_name MiniatureCameraRig
extends Node3D
## A tabletop-miniature camera (BRIEF 3.9; Siege S3 "Camera": a fixed high three-quarter
## view, pitch about 42 degrees, FOV 30-35 degrees, a 4 s push-in at the start, a shake of up
## to 0.15 m on big hits). The narrow FOV from far away flattens perspective the way a
## tilt-shift photo of a model does; there is no depth-of-field blur (Compatibility has none).
##
## The rig orbits `target` at `distance`, `pitch_deg` above the horizon and `yaw_deg` around
## Y (0 = looking toward -Z from the +Z side). Every value is clamped to its limits: pitch
## to min/max_pitch_deg, yaw to base_yaw_deg +- orbit_limit_deg, FOV to min/max_fov_deg,
## distance to min/max_distance, shake to max_shake_m. push_in() eases from farther out to
## `distance`; shake() adds a decaying, deterministic jitter in the camera's screen plane.
##
## Positions (target, camera) are in the rig's local space: leave the rig at the origin to
## work in world coordinates. Time: tick(dt), called from _process while `auto_process` is on.
## [codeblock]
## var rig := MiniatureCameraRig.new()
## rig.target = Vector3(0, 0, -10)
## rig.pitch_deg = 42.0
## rig.fov_deg = 32.0
## rig.fit_width(110.0)        # fort plus roads fill the frame
## add_child(rig)
## rig.push_in(1.5, 4.0)
## # on a gate hit of 8 HP or more:
## rig.shake(0.15, 0.5)
## [/codeblock]

## The push-in reached its end distance.
signal push_in_finished

var target: Vector3 = Vector3.ZERO:
	set(value):
		target = value
		update_camera()

var distance: float = 120.0:
	set(value):
		distance = clampf(value, min_distance, max_distance)
		update_camera()

var pitch_deg: float = 42.0:
	set(value):
		pitch_deg = clampf(value, min_pitch_deg, max_pitch_deg)
		update_camera()

## Yaw around Y in degrees, clamped to base_yaw_deg +- orbit_limit_deg.
var yaw_deg: float = 0.0:
	set(value):
		yaw_deg = clampf(value, base_yaw_deg - orbit_limit_deg, base_yaw_deg + orbit_limit_deg)
		update_camera()

## The centre of the allowed orbit.
var base_yaw_deg: float = 0.0:
	set(value):
		base_yaw_deg = value
		yaw_deg = yaw_deg

## How far the view may orbit either side of base_yaw_deg (limited orbit).
var orbit_limit_deg: float = 20.0:
	set(value):
		orbit_limit_deg = maxf(value, 0.0)
		yaw_deg = yaw_deg

var min_pitch_deg: float = 25.0
var max_pitch_deg: float = 65.0

## Vertical field of view in degrees.
var fov_deg: float = 32.0:
	set(value):
		fov_deg = clampf(value, min_fov_deg, max_fov_deg)
		if camera != null:
			camera.fov = fov_deg

var min_fov_deg: float = 15.0
var max_fov_deg: float = 60.0
var min_distance: float = 5.0
var max_distance: float = 2000.0

## The largest shake offset in meters.
var max_shake_m: float = 0.15

## Call tick(delta) from _process.
var auto_process: bool = true

## The camera this rig drives (a child, current by default).
var camera: Camera3D = null

var _push_from: float = 1.0
var _push_t: float = 0.0
var _push_duration: float = 0.0
var _shake_amp: float = 0.0
var _shake_left: float = 0.0
var _shake_duration: float = 0.0
var _shake_t: float = 0.0


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = fov_deg
	camera.near = 0.5
	camera.far = 2500.0
	add_child(camera, false, Node.INTERNAL_MODE_FRONT)
	update_camera()


func _ready() -> void:
	camera.current = true
	update_camera()


func _process(delta: float) -> void:
	if auto_process:
		tick(delta)


## Advance the push-in and the shake by dt seconds.
func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	if _push_duration > 0.0:
		_push_t += dt
		if _push_t >= _push_duration:
			_push_duration = 0.0
			_push_t = 0.0
			push_in_finished.emit()
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - dt, 0.0)
		_shake_t += dt
	update_camera()


## Orbit by the given degrees (clamped to the limits).
func orbit(delta_yaw_deg: float, delta_pitch_deg: float = 0.0) -> void:
	yaw_deg += delta_yaw_deg
	pitch_deg += delta_pitch_deg


## Start a push-in: the camera starts `from_factor` times farther out and eases (cubic out)
## to `distance` over `duration_s`. A duration of 0 or less places the camera at `distance`
## and emits push_in_finished at once, so code awaiting the signal never hangs.
func push_in(from_factor: float = 1.5, duration_s: float = 4.0) -> void:
	_push_from = maxf(from_factor, 1.0)
	_push_t = 0.0
	_push_duration = maxf(duration_s, 0.0)
	update_camera()
	if _push_duration <= 0.0:
		push_in_finished.emit()


func is_pushing_in() -> bool:
	return _push_duration > 0.0


## Start a decaying shake of `amplitude_m` (clamped to max_shake_m) lasting `duration_s`. A
## stronger shake replaces a weaker one in progress; a weaker one is ignored.
func shake(amplitude_m: float = 0.15, duration_s: float = 0.4) -> void:
	var amp := clampf(amplitude_m, 0.0, max_shake_m)
	if amp < current_shake_amplitude():
		return
	_shake_amp = amp
	_shake_duration = maxf(duration_s, 0.001)
	_shake_left = _shake_duration
	_shake_t = 0.0


## The shake's current envelope amplitude (meters), decaying to 0.
func current_shake_amplitude() -> float:
	if _shake_left <= 0.0:
		return 0.0
	var e := _shake_left / _shake_duration
	return _shake_amp * e * e


## The shake offset now (in world space, within the camera's screen plane), length <=
## current_shake_amplitude().
func shake_offset() -> Vector3:
	var amp := current_shake_amplitude()
	if amp <= 0.0:
		return Vector3.ZERO
	var t := _shake_t
	var v := Vector2(sin(t * 47.0 + 0.7) + 0.5 * sin(t * 83.0 + 2.1), sin(t * 53.0 + 1.9) + 0.5 * sin(t * 71.0 + 0.3))
	v = v / 1.5 * amp
	if v.length() > amp:
		v = v.normalized() * amp
	var b := _view_basis()
	return b.x * v.x + b.y * v.y


## The distance right now, including the push-in.
func effective_distance() -> float:
	if _push_duration <= 0.0:
		return distance
	var u := clampf(_push_t / _push_duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - u, 3.0)
	return distance * lerpf(_push_from, 1.0, eased)


## The camera position without shake.
func camera_position() -> Vector3:
	return target + _view_basis() * Vector3(0.0, 0.0, effective_distance())


## Set `distance` so a span `width_m` wide at the target fills the view horizontally at the
## given aspect ratio (16:9 by default).
func fit_width(width_m: float, aspect: float = 16.0 / 9.0) -> void:
	var vfov := deg_to_rad(fov_deg)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * maxf(aspect, 0.01))
	distance = (width_m * 0.5) / tan(hfov * 0.5)


## Place the camera now (setters and tick() call it).
func update_camera() -> void:
	if camera == null:
		return
	camera.transform = Transform3D(_view_basis(), camera_position() + shake_offset())
	camera.fov = fov_deg


## The camera's orientation: yaw about Y, then pitch down by pitch_deg.
func _view_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, -deg_to_rad(pitch_deg))
