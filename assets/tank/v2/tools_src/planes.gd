extends SceneTree
# Cuts the 960x540 plate into depth planes, bakes the tilt-shift blur per plane, makes wide (1920) tiling strips,
# and writes a recomposite preview. Prints the plane table as JSON (kit.json is written by kit.gd).

var L = load("res://build/v2/lib.gd")
const W := 960
const H := 540
const OUT := "res://assets/tank/v2/"
const WIDE := 1920

var plate: PackedFloat32Array
var ridge := PackedInt32Array()


func lum(f: PackedFloat32Array, i: int) -> float:
	return (f[i * 4] + f[i * 4 + 1] + f[i * 4 + 2]) / 3.0


func curve_y(pts: Array, x: float) -> float:
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		if x >= a.x and x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.001))
	return pts[pts.size() - 1].y


func find_ridge() -> void:
	var l := PackedFloat32Array()
	l.resize(W * H)
	for i in W * H:
		l[i] = lum(plate, i)
	var lb: PackedFloat32Array = L.blur1(l, W, H, 2)
	var thr := 12.5 / 255.0
	var raw := PackedFloat32Array()
	raw.resize(W)
	for x in W:
		var r := 220
		for y in range(16, 220):
			var ok := true
			for k in 6:
				if lb[(y + k) * W + x] >= thr:
					ok = false
					break
			if ok:
				r = y
				break
		raw[x] = maxf(r, 24)
	# median 9 then box 5
	ridge.resize(W)
	var med := PackedFloat32Array()
	med.resize(W)
	for x in W:
		var win: Array[float] = []
		for k in range(-4, 5):
			win.append(raw[clampi(x + k, 0, W - 1)])
		win.sort()
		med[x] = win[4]
	for x in W:
		var s := 0.0
		for k in range(-5, 6):
			s += med[clampi(x + k, 0, W - 1)]
		ridge[x] = int(round(s / 11.0))


func plane_from(alpha_fn: Callable, gain: float = 1.0) -> PackedFloat32Array:
	var out := plate.duplicate()
	for y in H:
		for x in W:
			var i := (y * W + x) * 4
			var a: float = alpha_fn.call(x, y)
			out[i + 3] = a
			if gain != 1.0:
				for c in 3:
					out[i + c] *= gain
	return out


func sky_plane() -> PackedFloat32Array:
	var out := plate.duplicate()
	# column sky colour just above the ridge, smoothed along x
	var cols: Array[Color] = []
	for x in W:
		var s := Color(0, 0, 0)
		var r := ridge[x]
		for y in range(maxi(r - 12, 0), maxi(r - 3, 1)):
			var i := (y * W + x) * 4
			s += Color(plate[i], plate[i + 1], plate[i + 2])
		cols.append(s / 9.0)
	var sm: Array[Color] = []
	for x in W:
		var s := Color(0, 0, 0)
		for k in range(-12, 13):
			s += cols[clampi(x + k, 0, W - 1)]
		sm.append(s / 25.0)
	for x in W:
		for y in range(ridge[x] - 3, H):
			var i := (y * W + x) * 4
			var t := clampf((y - ridge[x] + 3) / 6.0, 0.0, 1.0)
			var c := sm[x].darkened(clampf((y - ridge[x]) / 400.0, 0.0, 0.3))
			for ch in 3:
				out[i + ch] = lerpf(out[i + ch], c[ch], t)
			out[i + 3] = 1.0
	return out


func save_plane(f: PackedFloat32Array, name: String, blur: int, y0: int, y1: int) -> Image:
	var b: PackedFloat32Array = L.blur4(f, W, H, blur) if blur > 0 else f
	var img: Image = L.to_img(b, W, H)
	var crop := img.get_region(Rect2i(0, y0, W, y1 - y0))
	crop.save_png(OUT + "plane_%s.png" % name)
	return crop


# Edge energy per column (low = calm place to cut).
func busy(img: Image) -> PackedFloat32Array:
	var w := img.get_width()
	var h := img.get_height()
	var e := PackedFloat32Array()
	e.resize(w)
	for x in range(1, w):
		var s := 0.0
		for y in range(0, h, 2):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x - 1, y)
			s += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * a.a + absf(a.a - b.a) * 0.3
		e[x] = s
	var sm := e.duplicate()
	for x in w:
		var s2 := 0.0
		for k in range(-3, 4):
			s2 += e[clampi(x + k, 0, w - 1)]
		sm[x] = s2
	return sm


func calm(e: PackedFloat32Array, x: int, lo: int, hi: int) -> int:
	var best := x
	for k in range(maxi(x - 24, lo), mini(x + 25, hi)):
		if e[k] < e[best]:
			best = k
	return best


func mixc(a: Color, b: Color, t: float) -> Color:
	var aa := a.a * (1.0 - t)
	var bb := b.a * t
	var al := aa + bb
	if al <= 0.0001:
		return Color(0, 0, 0, 0)
	return Color((a.r * aa + b.r * bb) / al, (a.g * aa + b.g * bb) / al, (a.b * aa + b.b * bb) / al, al)


# Seamless WIDE strip: the original 960 first, then random calm-cut windows, cross-faded (ov px), wrapped.
func wide_quilt(img: Image, seed_v: int, ov: int = 40, d0: int = 0, d1: int = W, keep_first: bool = true) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var h := img.get_height()
	var e := busy(img)
	var out := Image.create(WIDE + ov + 600, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var pos := 0
	if keep_first:
		out.blit_rect(img, Rect2i(0, 0, W, h), Vector2i.ZERO)
		pos = W  # next write position (start of overlap is pos - ov)
	while pos < WIDE + ov:
		var ln := rng.randi_range(240, 420)
		ln = mini(ln, d1 - d0 - ov - 10)
		var st := calm(e, rng.randi_range(d0 + ov + 4, d1 - ln - 4), d0 + ov + 2, d1 - ln - 2)
		var en := calm(e, st + ln, st + 160, d1 - 1)
		ln = en - st
		# window [st - ov, en): first ov px cross-fade with what is already at [pos - ov, pos)
		for x in range(-ov, ln):
			var tx := pos + x
			if tx >= out.get_width():
				break
			if tx < 0:
				continue
			for y in h:
				var src := img.get_pixel(st + x, y)
				if x < 0 and pos > 0:
					var t := (x + ov + 0.5) / ov
					out.set_pixel(tx, y, mixc(out.get_pixel(tx, y), src, t))
				else:
					out.set_pixel(tx, y, src)
		pos += ln
	# wrap: blend [WIDE, WIDE + ov) into [0, ov)
	var res := out.get_region(Rect2i(0, 0, WIDE, h))
	for x in ov:
		var t := (x + 0.5) / ov
		for y in h:
			res.set_pixel(x, y, mixc(out.get_pixel(WIDE + x, y), out.get_pixel(x, y), t))
	return res


func wide_mirror(img: Image) -> Image:
	var h := img.get_height()
	var res := Image.create(WIDE, h, false, Image.FORMAT_RGBA8)
	res.blit_rect(img, Rect2i(0, 0, W, h), Vector2i.ZERO)
	var m := img.duplicate()
	m.flip_x()
	res.blit_rect(m, Rect2i(0, 0, W, h), Vector2i(W, 0))
	return res


func _init() -> void:
	plate = L.to_f(Image.load_from_file(OUT + "plate_full.png"))
	find_ridge()
	var forest_top := [
		Vector2(0, 0), Vector2(60, 0), Vector2(80, 40), Vector2(150, 58), Vector2(260, 88), Vector2(380, 108),
		Vector2(470, 128), Vector2(560, 156), Vector2(620, 186), Vector2(680, 212), Vector2(760, 236),
		Vector2(860, 252), Vector2(960, 248),
	]
	var cliff_top := [
		Vector2(0, 150), Vector2(560, 160), Vector2(700, 150), Vector2(768, 118), Vector2(790, 52),
		Vector2(960, 46),
	]
	var planes := []
	# 1 sky (backdrop, opaque)
	var sky := sky_plane()
	for i in W * H:
		sky[i * 4 + 3] = 1.0
	var sky_img := save_plane(sky, "sky", 1, 0, 260)
	planes.append({"name": "sky", "y0": 0, "y1": 260, "blur": 1, "parallax": 0.02, "img": sky_img, "wide": "mirror"})
	# 2 mountains: ridge silhouette, fades out below the forest top
	var mtn := plane_from(func(x: int, y: int) -> float:
		# the cliff (x > 760) belongs to the cliff_lake plane
		return smoothstep(ridge[x] - 2.0, ridge[x] + 2.0, y) * (1.0 - smoothstep(196.0, 226.0, y)) 			* (1.0 - smoothstep(740.0, 785.0, x)))
	var mtn_img := save_plane(mtn, "mountains", 3, 20, 232)
	planes.append({"name": "mountains", "y0": 20, "y1": 232, "blur": 3, "parallax": 0.08, "img": mtn_img, "wide": "mirror"})
	# 3 cliff + lake + misty valley (right side landmark)
	var cl := plane_from(func(x: int, y: int) -> float:
		var top := curve_y(cliff_top, x)
		return smoothstep(top - 4.0, top + 6.0, y) * smoothstep(520.0, 640.0, x) * (1.0 - smoothstep(300.0, 326.0, y)))
	var cl_img := save_plane(cl, "cliff_lake", 3, 40, 330)
	planes.append({"name": "cliff_lake", "y0": 40, "y1": 330, "blur": 3, "parallax": 0.2, "img": cl_img, "wide": "none"})
	# 4 far forest: tree-top curve with a soft 30 px fade, down to the road
	var fo := plane_from(func(x: int, y: int) -> float:
		var top := curve_y(forest_top, x)
		return smoothstep(top - 30.0, top + 2.0, y) * (1.0 - smoothstep(344.0, 352.0, y)))
	var fo_img := save_plane(fo, "forest", 2, 0, 354)
	planes.append({"name": "forest", "y0": 0, "y1": 354, "blur": 2, "parallax": 0.45, "img": fo_img, "wide": "level"})
	var fo_lv := plane_from(func(_x: int, y: int) -> float:
		return smoothstep(110.0, 150.0, y) * (1.0 - smoothstep(344.0, 352.0, y)))
	var fo_lv_img := save_plane(fo_lv, "forest_level_tmp", 2, 0, 354)
	# 5 road band (sharp focal plane, the tank drives here)
	var rd := plane_from(func(_x: int, y: int) -> float:
		return smoothstep(314.0, 328.0, y) * (1.0 - smoothstep(376.0, 390.0, y)))
	var rd_img := save_plane(rd, "road", 0, 312, 392)
	planes.append({"name": "road", "y0": 312, "y1": 392, "blur": 0, "parallax": 1.0, "img": rd_img, "wide": "quilt"})
	# 6 foreground: strong blur, darker
	var fg := plane_from(func(_x: int, y: int) -> float:
		return smoothstep(362.0, 380.0, y), 0.72)
	var fg_img := save_plane(fg, "foreground", 6, 344, 540)
	planes.append({"name": "foreground", "y0": 344, "y1": 540, "blur": 6, "parallax": 1.35, "img": fg_img, "wide": "quilt"})
	# wide strips + recomposite
	var comp := Image.create(W, H, false, Image.FORMAT_RGBA8)
	comp.fill(Color(0, 0, 0, 1))
	var table := []
	var seed_v := 5
	for p in planes:
		var img: Image = p.img
		comp.blend_rect(img, Rect2i(0, 0, W, img.get_height()), Vector2i(0, p.y0))
		var wide_name := ""
		if p.wide == "mirror":
			wide_mirror(img).save_png(OUT + "plane_%s_wide.png" % p.name)
			wide_name = "plane_%s_wide.png" % p.name
		elif p.wide == "level":
			wide_quilt(fo_lv_img, 21, 48, 70, 640, false).save_png(OUT + "plane_%s_wide.png" % p.name)
			wide_name = "plane_%s_wide.png" % p.name
		elif p.wide == "quilt":
			seed_v += 7
			wide_quilt(img, seed_v, 40, 0, W, false).save_png(OUT + "plane_%s_wide.png" % p.name)
			wide_name = "plane_%s_wide.png" % p.name
		var sigma := sqrt(3.0 * ((2 * p.blur + 1) * (2 * p.blur + 1) - 1) / 12.0) if p.blur > 0 else 0.0
		table.append({
			"name": p.name, "file": "plane_%s.png" % p.name, "wide_file": wide_name,
			"wide_px": WIDE if wide_name != "" else 0,
			"y0": p.y0, "y1": p.y1, "blur_box_radius": p.blur, "blur_sigma_px": snappedf(sigma, 0.01),
			"parallax": p.parallax,
		})
	comp.save_png("res://build/v2/planes_recomposite.png")
	var f := FileAccess.open("res://build/v2/planes.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"planes": table, "ridge_sample": [ridge[0], ridge[240], ridge[480], ridge[720], ridge[959]]}, "  "))
	f.close()
	print("planes done")
	quit()
