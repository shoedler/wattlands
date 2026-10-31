class_name SiegeV2TiltShift
extends ColorRect
## The tilt-shift, haze and vignette screen pass over the art-resolution view
## (siege_tilt_shift.gdshader). Add it last in the game view; `enabled` is the local rider's
## tilt_shift option (off keeps the picture sharp, with the haze and vignette). It covers the
## art canvas (set_canvas); focus_rows() keeps as many blurred rows on a tall canvas as on the base,
## and on a short one keeps the design frame's focus band in focus.

const SHADER_PATH := "res://src/games/siege/view/v2/siege_tilt_shift.gdshader"

var enabled: bool = true:
	set(v):
		enabled = v
		if _mat != null:
			_mat.set_shader_parameter("blur_enabled", v)

var _mat: ShaderMaterial = null
var _focus_top: float = 95.0
var _focus_bottom: float = 500.0


func _init(art_size: Vector2i = SiegeBakeBank.ART_SIZE, focus: Dictionary = {}) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(art_size)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	_focus_top = float(focus.get("top", _focus_top))
	_focus_bottom = float(focus.get("bottom", _focus_bottom))
	_mat.set_shader_parameter("focus_top", _focus_top)
	_mat.set_shader_parameter("focus_bottom", _focus_bottom)
	for k: String in ["rampTop", "rampBottom", "blurTop", "blurBottom"]:
		if focus.has(k):
			_mat.set_shader_parameter(k.to_snake_case(), float(focus[k]))
	_mat.set_shader_parameter("blur_enabled", enabled)
	material = _mat


## Covers `art_size`, with the design frame's top-left at `offset` on it (this node sits in the
## view, whose origin is that top-left).
func set_canvas(art_size: Vector2i, offset: Vector2i) -> void:
	position = Vector2(-offset)
	size = Vector2(art_size)
	var rows := focus_rows(art_size.y, offset.y, _focus_top, _focus_bottom)
	_mat.set_shader_parameter("focus_top", rows.x)
	_mat.set_shader_parameter("focus_bottom", rows.y)


## The focus band on the canvas (top row, bottom row), from the band's rows on the design frame.
static func focus_rows(art_h: int, offset_y: int, top: float, bottom: float) -> Vector2:
	var below := float(SiegeBakeBank.ART_SIZE.y) - bottom
	return Vector2(minf(top, top + offset_y), maxf(art_h - below, bottom + offset_y))
