class_name FishingPaletteMap
extends RefCounted
## The palette map (fishing_palette_map.gdshader) on a CanvasItem: swaps palette colours for
## palette colours, so nothing on screen ever leaves the palette. Fish, wobblers and hints shift
## along FishingPalette.LADDER with the water around them (shift_for()), a hint not picked is a
## flat silhouette, a boat's rows under its waterline take one flat water tone and a farther
## boat is drawn a step lighter.

const SHADER_PATH := "res://src/games/fishing/view/fishing_palette_map.gdshader"
const SLOTS := 8

static var _shader: Shader = null


static func shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


## A fresh map material on `item` (returned so the caller can set it every frame).
static func apply(item: CanvasItem) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	item.material = m
	return m


## src[i] -> dst[i] (at most SLOTS pairs).
static func set_pairs(m: ShaderMaterial, src: Array[Color], dst: Array[Color]) -> void:
	var n := mini(mini(src.size(), dst.size()), SLOTS)
	for i in SLOTS:
		m.set_shader_parameter("src_%d" % i, src[i] if i < n else Color(0, 0, 0, 0))
		m.set_shader_parameter("dst_%d" % i, dst[i] if i < n else Color(0, 0, 0, 0))
	m.set_shader_parameter("count", n)


## Every LADDER colour `steps` steps darker (lighter when negative).
static func set_shift(m: ShaderMaterial, steps: int) -> void:
	if m.has_meta("shift") and int(m.get_meta("shift")) == steps:
		return
	m.set_meta("shift", steps)
	var dst: Array[Color] = []
	for c in FishingPalette.LADDER:
		dst.append(FishingPalette.darker(c, steps))
	set_pairs(m, FishingPalette.LADDER, dst)


static func shift_of(m: ShaderMaterial) -> int:
	return int(m.get_meta("shift", 0))


## The shift for a sprite in water band `band` (FishingPalette.SEA index): fish as drawn on the
## foam and haze bands, a step darker on the teal bands, so they stay the darkest subject.
static func shift_for(band: int) -> int:
	return 0 if band <= 1 else 1


static func set_flat(m: ShaderMaterial, on: bool, col: Color = Color.BLACK) -> void:
	m.set_shader_parameter("flat_on", on)
	m.set_shader_parameter("flat_col", col)


static func is_flat(m: ShaderMaterial) -> bool:
	return bool(m.get_shader_parameter("flat_on"))


## Rows at or below view row `y` take `col`.
static func set_under(m: ShaderMaterial, y: float, col: Color) -> void:
	m.set_shader_parameter("under_y", y)
	m.set_shader_parameter("under_col", col)
