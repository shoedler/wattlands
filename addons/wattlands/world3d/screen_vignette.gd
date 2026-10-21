class_name ScreenVignette
extends CanvasLayer
## A full-screen vignette over the 3D view and under the HUD (Siege S3: "A vignette under
## the HUD darkens the corners by at most 12%"). It sits on CanvasLayer -1: above the 3D
## world, below layer-0 2D content and every HUD layer. It ignores the mouse.
## [codeblock]
## var vignette := ScreenVignette.new()   # strength 0.12
## add_child(vignette)
## [/codeblock]

const SHADER_PATH := "res://addons/wattlands/world3d/screen_vignette.gdshader"

## The darkening at the corners (0..1); Siege caps it at 0.12.
var strength: float = 0.12:
	set(value):
		strength = clampf(value, 0.0, 1.0)
		_apply()

## Where darkening starts, as a fraction of the centre-to-corner distance.
var inner: float = 0.55:
	set(value):
		inner = clampf(value, 0.0, 0.99)
		_apply()

var rect: ColorRect = null
var vignette_material: ShaderMaterial = null


func _init() -> void:
	layer = -1
	rect = ColorRect.new()
	rect.name = "Vignette"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette_material = ShaderMaterial.new()
	vignette_material.shader = load(SHADER_PATH) as Shader
	rect.material = vignette_material
	add_child(rect, false, Node.INTERNAL_MODE_FRONT)
	_apply()


## The darkening (0..strength) at a screen UV (0..1), as the shader computes it.
static func darkening_at(uv: Vector2, p_strength: float, p_inner: float) -> float:
	var d := (uv - Vector2(0.5, 0.5)) * 2.0
	var r := d.length() / sqrt(2.0)
	var t := clampf((r - p_inner) / maxf(1.0 - p_inner, 0.0001), 0.0, 1.0)
	return clampf(p_strength, 0.0, 1.0) * t * t * (3.0 - 2.0 * t)


func _apply() -> void:
	if vignette_material == null:
		return
	vignette_material.set_shader_parameter("strength", strength)
	vignette_material.set_shader_parameter("inner", inner)
