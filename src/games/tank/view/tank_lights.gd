class_name TankLights
extends Node2D
## One additive layer of soft halos (brief 3, "Light"): lamps, cylinder windows, the dynamo's arc,
## fires, muzzle flashes and tracers all add a glow each frame; the layer draws them in one canvas
## item with a procedural radial falloff, so a light costs one quad. Cold lights are blue-white
## (TankPalette.COLD_LIGHT), warm ones amber; everything else stays desaturated. (PointLight2D was
## not used: a light-per-lamp on Compatibility costs a lit pass over every sprite.)

## Most halos drawn in a frame; extra adds are ignored (the cap keeps the layer at one cheap quad batch).
const MAX_LIGHTS := 96

## Halo count this frame.
var count: int = 0
## A whole-view additive wash (the muzzle flash lighting the scene), 0 .. 1 and its colour.
var wash: float = 0.0
var wash_color: Color = TankPalette.AMBER

var _pos: PackedVector2Array = PackedVector2Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _color: PackedColorArray = PackedColorArray()
var _glow: Texture2D = null


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	_pos.resize(MAX_LIGHTS)
	_radius.resize(MAX_LIGHTS)
	_color.resize(MAX_LIGHTS)
	_glow = TankProcTex.glow()


## Starts a frame: forgets last frame's halos.
func begin() -> void:
	count = 0
	wash = 0.0


## Adds a halo at `at` (layer coordinates) of `radius` px in `color`, `intensity` 0 .. 1+.
func add(at: Vector2, radius: float, color: Color, intensity: float) -> void:
	if count >= MAX_LIGHTS or intensity <= 0.01 or radius < 1.0:
		return
	_pos[count] = at
	_radius[count] = radius
	_color[count] = Color(color.r, color.g, color.b, clampf(intensity, 0.0, 1.0) * color.a)
	count += 1


## Ends a frame: redraws.
func end() -> void:
	queue_redraw()


## The summed intensity of halos within `radius` of `at` (reflections in puddles and wet steel).
func intensity_near(at: Vector2, radius: float) -> float:
	var sum := 0.0
	for i in count:
		var d := at.distance_to(_pos[i])
		if d < radius + _radius[i]:
			sum += _color[i].a * (1.0 - d / (radius + _radius[i]))
	return sum


func _draw() -> void:
	if wash > 0.004:
		draw_rect(
			Rect2(0, 0, TankConst.SCREEN_W, TankConst.SCREEN_H),
			Color(wash_color.r, wash_color.g, wash_color.b, wash * wash * 0.3)
		)
	for i in count:
		var r := _radius[i]
		draw_texture_rect(
			_glow, Rect2(_pos[i] - Vector2(r, r), Vector2(r, r) * 2.0), false, _color[i]
		)
