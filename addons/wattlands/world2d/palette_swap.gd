class_name PaletteSwap
extends RefCounted
## Helpers for the PaletteSwap shader (BRIEF 3.9): recolor a sprite's key colors to a player
## color ramp at draw time. Fishing draws every boat with one 2-color red key ramp (trim and
## canopy, cap and shirt) and swaps it to each slot's ramp.
##
## Ramps run light to dark; a key ramp and its swap ramp must have the same length and order
## (at most MAX_KEYS colors). Matching is per channel within `tolerance` (0.02 by default),
## which suits palette-exact sprites (lossless import, pixelate's palette quantization).
## [codeblock]
## const BOAT_KEYS := [Color("#c8323c"), Color("#82202a")]   # light, dark
## PaletteSwap.apply_slot(boat_sprite, PackedColorArray(BOAT_KEYS), slot.slot_index)
## # or any color: PaletteSwap.apply(sprite, keys, PaletteSwap.ramp_from(Color.ORANGE, 2))
## [/codeblock]

const SHADER_PATH := "res://addons/wattlands/world2d/palette_swap.gdshader"
const MAX_KEYS := 8
const DEFAULT_TOLERANCE := 0.02
## How much darker the last color of ramp_from() is than the first.
const DEFAULT_SHADE := 0.35


## The PaletteSwap shader (loaded once and cached by the ResourceLoader).
static func shader() -> Shader:
	return load(SHADER_PATH) as Shader


## A new material mapping keys[i] -> swaps[i]. Extra colors beyond MAX_KEYS, or beyond the
## shorter of the two ramps, are dropped with an error.
static func make_material(keys: PackedColorArray, swaps: PackedColorArray, tolerance: float = DEFAULT_TOLERANCE) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	set_ramps(mat, keys, swaps, tolerance)
	return mat


## Give `item` a new PaletteSwap material and return it.
static func apply(item: CanvasItem, keys: PackedColorArray, swaps: PackedColorArray, tolerance: float = DEFAULT_TOLERANCE) -> ShaderMaterial:
	var mat := make_material(keys, swaps, tolerance)
	if item != null:
		item.material = mat
	return mat


## Swap `keys` to the session look color of `slot_index` (Wl.slot_look), as a ramp of the
## same length as `keys`.
static func apply_slot(item: CanvasItem, keys: PackedColorArray, slot_index: int, tolerance: float = DEFAULT_TOLERANCE) -> ShaderMaterial:
	return apply(item, keys, slot_ramp(slot_index, keys.size()), tolerance)


## Set both ramps (and the tolerance) on an existing PaletteSwap material.
static func set_ramps(mat: ShaderMaterial, keys: PackedColorArray, swaps: PackedColorArray, tolerance: float = DEFAULT_TOLERANCE) -> void:
	var n := mini(keys.size(), swaps.size())
	if keys.size() != swaps.size():
		push_error("PaletteSwap: %d key colors but %d swap colors; using %d" % [keys.size(), swaps.size(), mini(n, MAX_KEYS)])
	if n > MAX_KEYS:
		push_error("PaletteSwap: %d colors exceed MAX_KEYS (%d); extra colors dropped" % [n, MAX_KEYS])
		n = MAX_KEYS
	for i in MAX_KEYS:
		mat.set_shader_parameter("key_%d" % i, keys[i] if i < n else Color(0, 0, 0, 0))
		mat.set_shader_parameter("swap_%d" % i, swaps[i] if i < n else Color(0, 0, 0, 0))
	mat.set_shader_parameter("key_count", n)
	mat.set_shader_parameter("tolerance", maxf(tolerance, 0.0))


## Replace only the swap ramp (same key count), e.g. when a slot changes.
static func set_swaps(mat: ShaderMaterial, swaps: PackedColorArray) -> void:
	var n: int = int(mat.get_shader_parameter("key_count"))
	if swaps.size() < n:
		push_error("PaletteSwap: %d swap colors for %d keys" % [swaps.size(), n])
	for i in mini(swaps.size(), n):
		mat.set_shader_parameter("swap_%d" % i, swaps[i])


## The key colors set on a PaletteSwap material.
static func keys_of(mat: ShaderMaterial) -> PackedColorArray:
	return _read(mat, "key_")


## The swap colors set on a PaletteSwap material.
static func swaps_of(mat: ShaderMaterial) -> PackedColorArray:
	return _read(mat, "swap_")


## A ramp of `steps` colors from `color` (first, lightest) to color darkened by `shade`
## (last). steps 1 returns [color].
static func ramp_from(color: Color, steps: int = 2, shade: float = DEFAULT_SHADE) -> PackedColorArray:
	var out := PackedColorArray()
	var n := clampi(steps, 1, MAX_KEYS)
	for i in n:
		var t := float(i) / float(n - 1) if n > 1 else 0.0
		var c := color.darkened(shade * t)
		c.a = color.a
		out.append(c)
	return out


## The ramp for a session slot's color (Wl.slot_look(slot_index).color).
static func slot_ramp(slot_index: int, steps: int = 2, shade: float = DEFAULT_SHADE) -> PackedColorArray:
	var look: Dictionary = Wl.slot_look(slot_index)
	return ramp_from(look["color"], steps, shade)


## CPU reference of the shader for one color (tests; recoloring menu icons).
static func swap_color(c: Color, keys: PackedColorArray, swaps: PackedColorArray, tolerance: float = DEFAULT_TOLERANCE) -> Color:
	var n := mini(mini(keys.size(), swaps.size()), MAX_KEYS)
	for i in n:
		var k := keys[i]
		if absf(c.r - k.r) <= tolerance and absf(c.g - k.g) <= tolerance and absf(c.b - k.b) <= tolerance:
			return Color(swaps[i].r, swaps[i].g, swaps[i].b, c.a)
	return c


## A recolored copy of `img` (CPU), for places that need a baked texture instead of a shader.
static func swap_image(img: Image, keys: PackedColorArray, swaps: PackedColorArray, tolerance: float = DEFAULT_TOLERANCE) -> Image:
	var out := img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, swap_color(c, keys, swaps, tolerance))
	return out


static func _read(mat: ShaderMaterial, prefix: String) -> PackedColorArray:
	var out := PackedColorArray()
	var n: int = int(mat.get_shader_parameter("key_count"))
	for i in n:
		var v: Variant = mat.get_shader_parameter("%s%d" % [prefix, i])
		out.append(v as Color if v is Color else Color(0, 0, 0, 0))
	return out
