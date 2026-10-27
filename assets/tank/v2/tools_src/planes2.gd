extends SceneTree
# The planes the view draws (assets/tank/v2/planes2/), sharper and reference-faithful. The kit's planes
# double-blur the reference (it already carries its own depth of field) and its level-quilted forest hides
# the lake; here: far (sky + mountains + cliff + misty lake, opaque), forest (the reference's own sloping
# tree line, so the lake shows on the right), road; each 1920 wide = the 960 cut + its mirror (seamless,
# and the first 960 px are the reference itself). The foreground stays the kit's (blur 6, darkened).

var L = load("res://build/v2/lib.gd")
const W := 960
const H := 540
const KIT := "res://assets/tank/v2/"
const OUT := "res://assets/tank/v2/planes2/"

var plate: PackedFloat32Array


func curve_y(pts: Array, x: float) -> float:
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.001))
	return pts[pts.size() - 1].y


func plane_from(alpha_fn: Callable) -> PackedFloat32Array:
	var out := plate.duplicate()
	for y in H:
		for x in W:
			out[(y * W + x) * 4 + 3] = alpha_fn.call(x, y)
	return out


func cut(f: PackedFloat32Array, blur: int, y0: int, y1: int) -> Image:
	var b: PackedFloat32Array = L.blur4(f, W, H, blur, 2) if blur > 0 else f
	var img: Image = L.to_img(b, W, H)
	return img.get_region(Rect2i(0, y0, W, y1 - y0))


func mirror(img: Image) -> Image:
	var h := img.get_height()
	var res := Image.create(W * 2, h, false, Image.FORMAT_RGBA8)
	res.blit_rect(img, Rect2i(0, 0, W, h), Vector2i.ZERO)
	var m: Image = img.duplicate()
	m.flip_x()
	res.blit_rect(m, Rect2i(0, 0, W, h), Vector2i(W, 0))
	return res


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	plate = L.to_f(Image.load_from_file("res://build/v2/plate_full.png"))
	var forest_top := [
		Vector2(0, 0), Vector2(60, 0), Vector2(80, 40), Vector2(150, 58), Vector2(260, 88), Vector2(380, 108),
		Vector2(470, 128), Vector2(560, 156), Vector2(620, 186), Vector2(680, 212), Vector2(760, 236),
		Vector2(860, 252), Vector2(960, 248),
	]
	var far := plane_from(func(_x: int, _y: int) -> float: return 1.0)
	var far_img := cut(far, 0, 0, 330)
	mirror(far_img).save_png(OUT + "far_wide.png")
	var fo := plane_from(func(x: int, y: int) -> float:
		var top := curve_y(forest_top, x)
		return smoothstep(top - 8.0, top + 2.0, y) * (1.0 - smoothstep(344.0, 352.0, y)))
	var fo_img := cut(fo, 1, 0, 354)
	mirror(fo_img).save_png(OUT + "forest_wide.png")
	var rd := plane_from(func(_x: int, y: int) -> float:
		return smoothstep(314.0, 326.0, y) * (1.0 - smoothstep(380.0, 392.0, y)))
	var rd_img := cut(rd, 0, 312, 392)
	mirror(rd_img).save_png(OUT + "road_wide.png")
	var fgf := plane_from(func(_x: int, y: int) -> float: return smoothstep(362.0, 380.0, y))
	for i in W * H:
		for c in 3:
			fgf[i * 4 + c] *= 0.86
	var fg2 := cut(fgf, 2, 344, 540)
	mirror(fg2).save_png(OUT + "foreground_wide.png")
	var comp := Image.create(W, H, false, Image.FORMAT_RGBA8)
	comp.fill(Color(0, 0, 0, 1))
	comp.blend_rect(far_img, Rect2i(0, 0, W, 330), Vector2i.ZERO)
	comp.blend_rect(fo_img, Rect2i(0, 0, W, 354), Vector2i.ZERO)
	comp.blend_rect(rd_img, Rect2i(0, 0, W, 80), Vector2i(0, 312))
	comp.blend_rect(fg2, Rect2i(0, 0, W, 196), Vector2i(0, 344))
	comp.save_png("res://build/v2/planes2_recomposite.png")
	print("planes2 done")
	quit()
