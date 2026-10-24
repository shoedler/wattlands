class_name TankLights
extends Node2D
## One additive layer of soft halos (brief 3, "Light"): lamps, cylinder windows, the dynamo's arc,
## fires, muzzle flashes and tracers all add a glow each frame; the layer draws them in one canvas
## item with a procedural radial falloff, so a light costs one quad. Cold lights are blue-white
## (TankPalette.COLD_LIGHT), warm ones amber; everything else stays desaturated. (PointLight2D was
## not used: a light-per-lamp on Compatibility costs a lit pass over every sprite.)

## Most halos drawn in a frame; extra adds are ignored (the cap keeps the layer at one cheap quad batch).
const MAX_LIGHTS := 96
## The muzzle flash's light radius (art px).
const WASH_RADIUS := 150.0

## Halo count this frame.
var count: int = 0
## The muzzle flash lighting the scene around the gun, 0 .. 1, its colour and centre: a radial
## additive light of WASH_RADIUS px falling off fast (never a full-screen grade).
var wash: float = 0.0
var wash_color: Color = TankPalette.AMBER
var wash_pos: Vector2 = Vector2.ZERO

var _pos: PackedVector2Array = PackedVector2Array()
## Reflection streaks and specular lines this frame: [a, b, colour, width].
var _lines: Array[Array] = []
var _streaks: Array[Array] = []
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
	_lines.clear()
	_streaks.clear()


## Adds a halo at `at` (layer coordinates) of `radius` px in `color`, `intensity` 0 .. 1+.
func add(at: Vector2, radius: float, color: Color, intensity: float) -> void:
	if count >= MAX_LIGHTS or intensity <= 0.01 or radius < 1.0:
		return
	_pos[count] = at
	_radius[count] = radius
	_color[count] = Color(color.r, color.g, color.b, clampf(intensity, 0.0, 1.0) * color.a)
	count += 1


## Wet-ground reflections: every halo of this frame between `top_y` and `ground_y` (and bright
## enough) drops a soft vertical streak of its colour from `ground_y` down 20-30 px, 2-4 px wide,
## at `alpha` of its own strength. Call after the frame's lights are in.
func add_reflections(ground_y: float, top_y: float, alpha: float) -> void:
	for i in count:
		var p := _pos[i]
		var c := _color[i]
		if p.y < top_y or p.y > ground_y + 4.0 or c.a < 0.12 or _radius[i] < 6.0:
			continue
		if _streaks.size() >= MAX_LIGHTS:
			return
		var w := clampf(_radius[i] * 0.08, 2.0, 4.0)
		var h := clampf(_radius[i] * 0.6, 20.0, 30.0)
		var a := minf(c.a * alpha * 1.6, 0.3)
		_streaks.append([Rect2(p.x - w * 0.5, ground_y, w, h), Color(c.r, c.g, c.b, a)])


## A thin additive line (a specular edge on wet steel).
func add_line(a: Vector2, b: Vector2, color: Color, intensity: float) -> void:
	if intensity <= 0.01:
		return
	_lines.append([a, b, Color(color.r, color.g, color.b, clampf(intensity, 0.0, 1.0))])


## The intensity-weighted colour of this frame's halos (the light a wet edge catches); amber when
## there are none.
func near_color() -> Color:
	var sum := Color(0, 0, 0, 0)
	var wsum := 0.0
	for i in count:
		var k := _color[i].a * _radius[i]
		sum += Color(_color[i].r * k, _color[i].g * k, _color[i].b * k, 0.0)
		wsum += k
	if wsum <= 0.0:
		return TankPalette.AMBER
	return Color(sum.r / wsum, sum.g / wsum, sum.b / wsum, 1.0).lerp(TankPalette.GLOW_WARM, 0.3)


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
		# Two stacked radial glows: a wide soft throw and a hot core, so the light falls off fast.
		var big := Vector2(WASH_RADIUS, WASH_RADIUS)
		var wc := Color(wash_color.r, wash_color.g, wash_color.b, wash * 0.55)
		draw_texture_rect(_glow, Rect2(wash_pos - big, big * 2.0), false, wc)
		var core := big * 0.4
		wc.a = wash * 0.5
		draw_texture_rect(_glow, Rect2(wash_pos - core, core * 2.0), false, wc)
	for i in count:
		var r := _radius[i]
		draw_texture_rect(
			_glow, Rect2(_pos[i] - Vector2(r, r), Vector2(r, r) * 2.0), false, _color[i]
		)
	for st in _streaks:
		# The glow's lower half stretched into a soft vertical streak, brightest at the ground line.
		draw_texture_rect_region(_glow, st[0], Rect2(0, 32, 64, 32), st[1])
	for ln in _lines:
		draw_line(ln[0], ln[1], ln[2], 1.0)
