class_name DitherDissolve
extends RefCounted
## Helpers for the DitherDissolve shader: fade pixel-art effects in or out through a 4 x 4
## ordered-dither pattern (Fishing F3.3 "effects end in a dither dissolve"), so a sprite
## never turns translucent and keeps hard pixel edges.
## [codeblock]
## var mat := DitherDissolve.apply(splash)        # amount 0: fully shown
## DitherDissolve.set_amount(mat, life_t)          # 0..1 over the effect's last frames
## [/codeblock]

const SHADER_PATH := "res://addons/wattlands/world2d/dither_dissolve.gdshader"


## The DitherDissolve shader (cached by the ResourceLoader).
static func shader() -> Shader:
	return load(SHADER_PATH) as Shader


## A new material at `amount` (0 shown .. 1 gone), with dither cells of `cell_px` texels.
static func make_material(amount: float = 0.0, cell_px: int = 1) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader()
	set_amount(mat, amount)
	mat.set_shader_parameter("cell_px", float(maxi(cell_px, 1)))
	return mat


## Give `item` a new DitherDissolve material and return it.
static func apply(item: CanvasItem, amount: float = 0.0, cell_px: int = 1) -> ShaderMaterial:
	var mat := make_material(amount, cell_px)
	if item != null:
		item.material = mat
	return mat


## Set how far the dissolve has gone (clamped to 0..1).
static func set_amount(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))


## The 4 x 4 Bayer threshold index (0..15) of a texel (same table as PixelPainter.BAYER4).
static func bayer4(x: int, y: int) -> int:
	var xm := x & 3
	var ym := y & 3
	return 4 * _bayer2(xm & 1, ym & 1) + _bayer2((xm >> 1) & 1, (ym >> 1) & 1)


## CPU reference: whether the texel at (x, y) still shows at `amount`.
static func visible_at(x: int, y: int, amount: float) -> bool:
	return (float(bayer4(x, y)) + 0.5) / 16.0 >= amount


static func _bayer2(x: int, y: int) -> int:
	return (x ^ y) * 2 + y
