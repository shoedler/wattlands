extends SceneTree

var L = load("res://build/v2/lib.gd")
var S = load("res://build/v2/shapes.gd")
const W := 1088
const H := 608


# Quilt band: rows [y0,y1) with vertical fade; segments of width seg (overlap ov) cover x in [xa, xb);
# each segment copies from a random donor [x0, x1, dy] (optionally mirrored).
func quilt(ref: PackedFloat32Array, hole: PackedFloat32Array, acc: PackedFloat32Array, wsum: PackedFloat32Array,
		b: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.seed)
	var y0: int = b.y0
	var y1: int = b.y1
	var fade: int = b.fade
	var seg: int = b.seg
	var ov: int = b.ov
	var x := int(b.xa) - ov
	while x < int(b.xb):
		var d: Array = b.donors[rng.randi() % b.donors.size()]
		var span: int = seg + 2 * ov
		var off := 0
		if d.size() > 3:
			# fixed window: whole donor window [d0, d1) used as one segment
			span = int(d[1]) - int(d[0])
			off = int(d[0])
		else:
			off = rng.randi_range(int(d[0]), int(d[1]) - span)
		var flip := rng.randf() < 0.5 and bool(b.get("flip", true))
		for u in span:
			var tx := x + u
			if tx < 0 or tx >= W:
				continue
			var wx := 1.0
			if u < ov:
				wx = (u + 0.5) / ov
			elif u >= span - ov:
				wx = (span - u - 0.5) / ov
			var sx := off + (span - 1 - u if flip else u)
			for y in range(y0, y1):
				var i := y * W + tx
				if hole[i] <= 0.0:
					continue
				var wy := 1.0
				if y < y0 + fade:
					wy = (y - y0 + 0.5) / fade
				elif y >= y1 - fade:
					wy = (y1 - y - 0.5) / fade
				var ww := wx * wy
				var sy := clampi(y + int(d[2]), 0, H - 1)
				var j := (sy * W + sx) * 4
				for c in 3:
					acc[i * 4 + c] += ref[j + c] * ww
				wsum[i] += ww
		x += span - ov


func _init() -> void:
	var src := Image.load_from_file("res://build/v2/ref.png")
	var ref: PackedFloat32Array = L.to_f(src)
	var hole: PackedFloat32Array = L.mask_new(W, H)
	L.poly_fill(hole, W, H, PackedVector2Array(S.TANK_OUTER))
	L.rect_fill(hole, W, H, S.TURRET_CREW)
	L.poly_fill(hole, W, H, PackedVector2Array(S.SEARCH_BEAM))
	L.poly_fill(hole, W, H, PackedVector2Array(S.HEAD_BEAM))
	L.poly_fill(hole, W, H, PackedVector2Array(S.SMOKE))
	var hole0: PackedFloat32Array = L.dilate(hole, W, H, 3)
	hole = L.dilate(hole0, W, H, 9)
	var bands := [
		{"y0": 100, "y1": 206, "fade": 8, "xa": 220, "xb": 440, "seg": 40, "ov": 12, "seed": 3,
			"donors": [[20, 222, 0]]},
		{"y0": 164, "y1": 330, "fade": 10, "xa": 0, "xb": 740, "seg": 34, "ov": 12, "seed": 11,
			"donors": [[622, 699, 0]]},
		{"y0": 318, "y1": 356, "fade": 10, "xa": 0, "xb": 740, "seg": 34, "ov": 12, "seed": 17,
			"donors": [[622, 699, -24]]},
		{"y0": 344, "y1": 412, "fade": 10, "xa": 0, "xb": 740, "seg": 90, "ov": 14, "seed": 5,
			"donors": [[1001, 1086, 0, 1], [778, 858, 0, 1], [1001, 1086, 0, 1], [778, 858, 0, 1], [846, 968, 0, 1]]},
	]
	var acc := PackedFloat32Array()
	acc.resize(W * H * 4)
	var wsum := PackedFloat32Array()
	wsum.resize(W * H)
	for b in bands:
		quilt(ref, hole, acc, wsum, b)
	var soft: PackedFloat32Array = L.blur1(L.dilate(hole0, W, H, 4), W, H, 2, 2)
	var out := ref.duplicate()
	var miss := 0
	for i in W * H:
		var a := soft[i]
		if a <= 0.0:
			continue
		if wsum[i] <= 0.0:
			miss += 1
			continue
		for c in 3:
			out[i * 4 + c] = lerpf(ref[i * 4 + c], acc[i * 4 + c] / wsum[i], a)
	print("unfilled hole px: ", miss)
	var dbg := ref.duplicate()
	for i in W * H:
		if wsum[i] > 0.0:
			for c in 3:
				dbg[i * 4 + c] = acc[i * 4 + c] / wsum[i]
		elif hole[i] > 0.0:
			dbg[i * 4] = 1.0
			dbg[i * 4 + 1] = 0.0
			dbg[i * 4 + 2] = 1.0
	L.to_img(dbg, W, H).save_png("res://build/v2/view/fill_dbg.png")
	var img: Image = L.to_img(out, W, H)
	img.save_png("res://build/v2/plate_ref.png")
	# 960-scale: x * 960/1088, y * 960/1088 + 2 (536 rows, edge rows replicated to 540)
	var sm := img.duplicate()
	sm.resize(960, 536, Image.INTERPOLATE_LANCZOS)
	var p960 := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	p960.blit_rect(sm, Rect2i(0, 0, 960, 536), Vector2i(0, 2))
	for x in 960:
		for y in 2:
			p960.set_pixel(x, y, sm.get_pixel(x, 0))
			p960.set_pixel(x, 538 + y, sm.get_pixel(x, 535))
	p960.save_png("res://build/v2/plate_full.png")
	quit()
