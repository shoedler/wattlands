extends SceneTree

var L = load("res://build/v2/lib.gd")
var S = load("res://build/v2/shapes.gd")
const W := 1088
const H := 608
const BBOX := Rect2i(26, 120, 528, 274)


func _init() -> void:
	var ref: PackedFloat32Array = L.to_f(Image.load_from_file("res://build/v2/ref.png"))
	var bg: PackedFloat32Array = L.to_f(Image.load_from_file("res://build/v2/plate_ref.png"))
	var outer: PackedFloat32Array = L.mask_new(W, H)
	L.poly_fill(outer, W, H, PackedVector2Array(S.TANK_OUTER))
	var inner: PackedFloat32Array = L.mask_new(W, H)
	for p in S.INNER:
		L.poly_fill(inner, W, H, PackedVector2Array(p))
	var nod: PackedFloat32Array = L.mask_new(W, H)
	for p in S.NO_DIFF:
		L.poly_fill(nod, W, H, PackedVector2Array(p))
	var zone: PackedFloat32Array = L.dilate(inner, W, H, 3)
	for r in S.DIFF_EXTRA:
		L.rect_fill(zone, W, H, r)
	var alpha := PackedFloat32Array()
	alpha.resize(W * H)
	for i in W * H:
		if outer[i] <= 0.0:
			continue
		var d := 0.0
		for c in 3:
			d = maxf(d, absf(ref[i * 4 + c] - bg[i * 4 + c]))
		var warm := ref[i * 4] - ref[i * 4 + 2]
		var lum := (ref[i * 4] + ref[i * 4 + 1] + ref[i * 4 + 2]) / 3.0
		warm = maxf(warm, (lum - 0.25) * 0.5)
		var e := smoothstep(0.03, 0.10, d) * smoothstep(0.0, 0.035, warm) * (1.0 - nod[i]) * zone[i]
		alpha[i] = maxf(inner[i], outer[i] * e)
	# crew and searchlight on the turret roof are drawn by the engine
	var cr: Rect2i = S.TURRET_CREW
	for y in range(cr.position.y, cr.end.y):
		for x in range(246, 400):
			if y < 213 or (y < 215 and x > 246):
				alpha[y * W + x] = 0.0
	var fixed: PackedFloat32Array = L.to_f(Image.load_from_file("res://build/v2/ref_fixed.png"))
	var out := PackedFloat32Array()
	out.resize(W * H * 4)
	for i in W * H:
		var a := alpha[i]
		if a <= 0.0:
			continue
		for c in 3:
			var v := fixed[i * 4 + c]
			if a < 0.98:
				v = (v - (1.0 - a) * bg[i * 4 + c]) / a
			out[i * 4 + c] = clampf(v, 0.0, 1.0)
		out[i * 4 + 3] = a
	var img: Image = L.to_img(out, W, H)
	img.save_png("res://build/v2/tank_ref_full.png")
	var t := img.get_region(BBOX)
	t.save_png("res://build/v2/tank_ref.png")
	# previews: over magenta-ish and over plate
	var prev := Image.create(BBOX.size.x, BBOX.size.y, false, Image.FORMAT_RGBA8)
	prev.fill(Color(0.45, 0.1, 0.45))
	prev.blend_rect(t, Rect2i(Vector2i.ZERO, BBOX.size), Vector2i.ZERO)
	prev.resize(BBOX.size.x * 2, BBOX.size.y * 2, Image.INTERPOLATE_NEAREST)
	prev.save_png("res://build/v2/view/tank_mag.png")
	var z := Image.create(BBOX.size.x, BBOX.size.y, false, Image.FORMAT_RGBA8)
	z.fill(Color(0.45, 0.1, 0.45))
	z.blend_rect(t, Rect2i(Vector2i.ZERO, BBOX.size), Vector2i.ZERO)
	for spec in [[Rect2i(150, 60, 270, 110), "top"], [Rect2i(0, 120, 200, 154), "rear"], [Rect2i(330, 120, 198, 154), "front"]]:
		var zz := z.get_region(spec[0])
		zz.resize(spec[0].size.x * 4, spec[0].size.y * 4, Image.INTERPOLATE_NEAREST)
		zz.save_png("res://build/v2/view/tz_%s.png" % spec[1])
	quit()
