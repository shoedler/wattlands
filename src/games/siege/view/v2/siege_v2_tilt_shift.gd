class_name SiegeV2TiltShift
extends ColorRect
## The tilt-shift, haze and vignette screen pass over the art-resolution view
## (siege_tilt_shift.gdshader). Add it last in the game view; `enabled` is the local rider's
## tilt_shift option (off keeps the picture sharp, with the haze and vignette).

const SHADER_PATH := "res://src/games/siege/view/v2/siege_tilt_shift.gdshader"

var enabled: bool = true:
	set(v):
		enabled = v
		if _mat != null:
			_mat.set_shader_parameter("blur_enabled", v)

var _mat: ShaderMaterial = null


func _init(art_size: Vector2i = SiegeBakeBank.ART_SIZE, focus: Dictionary = {}) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(art_size)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	for k: String in ["top", "bottom"]:
		if focus.has(k):
			_mat.set_shader_parameter("focus_" + k, float(focus[k]))
	for k: String in ["rampTop", "rampBottom", "blurTop", "blurBottom"]:
		if focus.has(k):
			_mat.set_shader_parameter(k.to_snake_case(), float(focus[k]))
	_mat.set_shader_parameter("blur_enabled", enabled)
	material = _mat
