class_name FishingDepthTint
extends RefCounted
## The depth tint (fishing_depth_tint.gdshader): mixes a sprite toward the water colour at its
## depth, so everything under the surface reads as seen through the water.

const SHADER_PATH := "res://src/games/fishing/view/fishing_depth_tint.gdshader"

static var _shader: Shader = null


static func shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


## A fresh tint material on `item` (returned so the caller can set it every frame).
static func apply(item: CanvasItem) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	item.material = m
	return m


static func set_tint(m: ShaderMaterial, fog: Color, amount: float) -> void:
	m.set_shader_parameter("fog", fog)
	m.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))


static func amount_of(m: ShaderMaterial) -> float:
	return float(m.get_shader_parameter("amount"))
