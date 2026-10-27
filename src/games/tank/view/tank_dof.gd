class_name TankDof
extends Node2D
## The per-frame depth-of-field pass (docs/games/tank.md 3.1, the strong tilt-shift): a light blur
## of the composed art-resolution frame that grows with the distance from the road band, so smoke,
## shells and far enemies above it and the foreground below it go soft while the tank, the road and
## its enemies stay sharp. The planes carry their own baked blur; this pass only adds to moving
## things. It is the rider's `miniature` option (on by default) and switches itself off for the
## session once the frame time stays above SLOW_FRAME_S for SLOW_FOR_S (frames of a fast-forward,
## where the sim moved more than the frame, never count).

const SLOW_FRAME_S := 0.0167
const SLOW_FOR_S := 5.0
## Frame-time smoothing (s): one long frame never trips it.
const SMOOTH_TAU_S := 0.5
## Blur radius in art px far from the band, and the ramp (art px) over which it grows.
const MAX_RADIUS_PX := 2.2
const RAMP_PX := 70.0

const SHADER := """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 canvas_px = vec2(960.0, 540.0);
uniform vec2 band = vec2(150.0, 360.0);
uniform float ramp_px = 70.0;
uniform float max_radius = 2.2;

void fragment() {
	float y = UV.y * canvas_px.y;
	float d = max(band.x - y, y - band.y);
	float k = clamp(d / ramp_px, 0.0, 1.0);
	float r = k * k * max_radius;
	vec2 px = 1.0 / canvas_px;
	vec4 c = texture(screen_tex, SCREEN_UV);
	if (r > 0.15) {
		vec4 acc = c;
		float n = 1.0;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			vec2 o = vec2(cos(a), sin(a)) * r * px;
			acc += texture(screen_tex, SCREEN_UV + o);
			acc += texture(screen_tex, SCREEN_UV + o * 0.5);
			n += 2.0;
		}
		c = acc / n;
	}
	COLOR = vec4(c.rgb, 1.0);
}
"""

## The rider's option (player_options `miniature`).
var enabled: bool = true
## True once the frame time switched it off (for the rest of the session).
var auto_off: bool = false
## The canvas size (art px) and the sharp band (art y, top and bottom) on it.
var canvas: Vector2 = Vector2(960, 540)
var band: Vector2 = Vector2(150, 360)

var _mat: ShaderMaterial = null
var _smooth_dt: float = 0.0
var _slow_s: float = 0.0


func _init() -> void:
	name = "Dof"
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat


## Whether the pass draws this frame.
func active() -> bool:
	return enabled and not auto_off


## One frame of `delta` seconds in which the sim advanced `sim_advance` seconds.
func note_frame(delta: float, sim_advance: float) -> void:
	if auto_off or not enabled:
		return
	if sim_advance > delta + 0.1:
		_slow_s = 0.0
		return
	if _smooth_dt <= 0.0:
		_smooth_dt = delta
	_smooth_dt = lerpf(_smooth_dt, delta, clampf(delta / SMOOTH_TAU_S, 0.0, 1.0))
	if _smooth_dt > SLOW_FRAME_S:
		_slow_s += delta
		if _slow_s >= SLOW_FOR_S:
			auto_off = true
			push_warning(
				"TankDof: the frame time stayed above 16.7 ms for 5 s; the miniature pass is off"
			)
	else:
		_slow_s = 0.0


func update(p_canvas: Vector2, p_band: Vector2) -> void:
	canvas = p_canvas
	band = p_band
	visible = active()
	if _mat != null:
		_mat.set_shader_parameter("canvas_px", canvas)
		_mat.set_shader_parameter("band", band)
		_mat.set_shader_parameter("ramp_px", RAMP_PX)
		_mat.set_shader_parameter("max_radius", MAX_RADIUS_PX)
	queue_redraw()


func _draw() -> void:
	if active():
		draw_texture_rect(TankDraw.white_tex(), Rect2(Vector2.ZERO, canvas), false)
