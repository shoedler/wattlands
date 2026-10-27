extends SceneTree
# Splits the cut-out tank (reference scale) into hull layers + turret + barrel and assembles the 1-4 rider variants.
# Writes reference-scale intermediates to build/v2/ and 960-scale results to assets/tank/v2/.

var L = load("res://build/v2/lib.gd")
var F = load("res://build/v2/font.gd")
const W := 1088
const H := 608
const S := 15.0 / 17.0  # 960 / 1088
const OUT := "res://assets/tank/v2/"
# Layer split rows (reference px): upper = hull roof + upper deck, lower = lower deck, rg = running gear.
const Y_LOWER := 310
const Y_RG := 352
const RG_A := 120  # running gear: rear part ends / tiled middle starts
const RG_B := 455  # front part (sprocket) starts
const X0 := 17  # left edge of the tank crop (reference px)
const X1 := 561  # right edge (exclusive)
const Y0 := 119
const Y1 := 391

var tank: PackedFloat32Array  # RGBA float, W x H
var hull: PackedFloat32Array
var turret: PackedFloat32Array  # body incl. mantlet and antenna, without barrel
var barrel: PackedFloat32Array
var period := 34
var ex_start := 300


func poly_mask(pts: Array) -> PackedFloat32Array:
	var m: PackedFloat32Array = L.mask_new(W, H)
	L.poly_fill(m, W, H, PackedVector2Array(pts))
	return m


func sample(buf: PackedFloat32Array, x: int, y: int) -> Color:
	if x < 0 or x >= W or y < 0 or y >= H:
		return Color(0, 0, 0, 0)
	var i := (y * W + x) * 4
	return Color(buf[i], buf[i + 1], buf[i + 2], buf[i + 3])


func sample_f(buf: PackedFloat32Array, fx: float, y: int) -> Color:
	var x0 := int(floor(fx))
	var t := fx - x0
	var a := sample(buf, x0, y)
	var b := sample(buf, x0 + 1, y)
	return mix(a, b, t)


# Premultiplied mix of two straight-alpha colours.
func mix(a: Color, b: Color, t: float) -> Color:
	var aa := a.a * (1.0 - t)
	var bb := b.a * t
	var al := aa + bb
	if al <= 0.0001:
		return Color(0, 0, 0, 0)
	return Color((a.r * aa + b.r * bb) / al, (a.g * aa + b.g * bb) / al, (a.b * aa + b.b * bb) / al, al)


func find_period() -> void:
	var best := 1e20
	for p in range(28, 42):
		var s := 0.0
		var n := 0
		for x in range(RG_A + 10, RG_B - 10 - p):
			for y in range(Y_RG + 4, Y_RG + 30):
				var a := sample(tank, x, y)
				var b := sample(tank, x + p, y)
				s += (a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)
				n += 1
		s /= n
		if s < best:
			best = s
			period = p
	best = 1e20
	for st in range(RG_A + 4, RG_B - 2 * period - 4):
		var s := 0.0
		for x in range(st, st + period):
			for y in range(Y_RG + 2, Y_RG + 32):
				var a := sample(tank, x, y)
				var b := sample(tank, x + period, y)
				s += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		if s < best:
			best = s
			ex_start = st
	print("running gear period ", period, " exemplar start ", ex_start)


# One output row segment of a hull layer: maps output x to source x for the given op.
# op = {} (identity), {"cut": [a, b]} (remove [a,b)), {"dup": [a, b]} (insert a copy of [a,b) at b).
func layer_px(op: Dictionary, x: int, y: int) -> Color:
	if op.has("cut"):
		var a: int = op.cut[0]
		var d: int = op.cut[1] - a
		if x < a - 2:
			return sample(hull, x, y)
		if x >= a + 2:
			return sample(hull, x + d, y)
		return mix(sample(hull, x, y), sample(hull, x + d, y), (x - (a - 2) + 0.5) / 4.0)
	if op.has("dup"):
		var a2: int = op.dup[0]
		var b2: int = op.dup[1]
		var d2 := b2 - a2
		if x < b2 - 2:
			return sample(hull, x, y)
		if x >= b2 + 2:
			return sample(hull, x - d2, y)
		return mix(sample(hull, x, y), sample(hull, x - d2, y), (x - (b2 - 2) + 0.5) / 4.0)
	return sample(hull, x, y)


# Running gear for a hull whose middle is delta px longer (negative = shorter).
# Removes/duplicates whole wheel periods at a gap, then resamples the middle to the exact length.
func rg_px(delta: int, x: int, y: int) -> Color:
	if delta == 0 or x < RG_A:
		return sample(hull, x, y)
	var mid := RG_B - RG_A
	var new_mid := mid + delta
	if x >= RG_A + new_mid:
		return sample(hull, x - delta, y)
	var k := int(round(float(absi(delta)) / period))
	var inter := mid + signi(delta) * k * period
	# position in the intermediate strip
	var u := (x - RG_A + 0.5) * float(inter) / new_mid - 0.5
	# intermediate strip: original middle with k periods removed/duplicated after ex_start
	var seam := ex_start - RG_A
	var src_u := u
	if delta < 0 and u >= seam:
		src_u = u + k * period
	elif delta > 0 and u >= seam + period and u < seam + period + k * period:
		src_u = seam + fposmod(u - seam, float(period))
	elif delta > 0 and u >= seam + period + k * period:
		src_u = u - k * period
	return sample_f(hull, RG_A + src_u, y)


func build_hull(ops: Dictionary, delta: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(W * H * 4)
	for y in range(Y0, Y1):
		var op: Dictionary = ops.upper if y < Y_LOWER else ops.lower
		for x in range(X0, mini(X1 + maxi(delta, 0), W)):
			var c: Color
			if y >= Y_RG:
				c = rg_px(delta, x, y)
			else:
				c = layer_px(op, x, y)
			var i := (y * W + x) * 4
			out[i] = c.r
			out[i + 1] = c.g
			out[i + 2] = c.b
			out[i + 3] = c.a
	return out


# Composites src (straight alpha float buffer, W x H) onto dst at offset, optionally scaled about a pivot.
func comp(dst: PackedFloat32Array, src: PackedFloat32Array, off: Vector2, scale: float = 1.0,
		pivot: Vector2 = Vector2.ZERO) -> void:
	var srci: Image = L.to_img(src, W, H)
	var shown := srci
	var shift := off
	if scale != 1.0:
		var r := Rect2i(160, 110, 400, 160)
		var piece := srci.get_region(r)
		var nw := int(round(r.size.x * scale))
		var nh := int(round(r.size.y * scale))
		piece = L.resize_pm(piece, nw, nh, Image.INTERPOLATE_CUBIC)
		# pivot maps to itself: new_pos = pivot + (old - pivot) * scale
		var np := pivot + (Vector2(r.position) - pivot) * scale
		shown = Image.create(W, H, false, Image.FORMAT_RGBA8)
		shown.blit_rect(piece, Rect2i(0, 0, nw, nh), Vector2i(int(round(np.x)), int(round(np.y))))
	var sf: PackedFloat32Array = L.to_f(shown)
	var ox := int(round(shift.x))
	var oy := int(round(shift.y))
	for y in H:
		for x in W:
			var j := (y * W + x) * 4
			var a := sf[j + 3]
			if a <= 0.0:
				continue
			var tx := x + ox
			var ty := y + oy
			if tx < 0 or ty < 0 or tx >= W or ty >= H:
				continue
			var i := (ty * W + tx) * 4
			var da := dst[i + 3]
			var oa := a + da * (1.0 - a)
			for c in 3:
				dst[i + c] = (sf[j + c] * a + dst[i + c] * da * (1.0 - a)) / oa
			dst[i + 3] = oa


func save_variant(buf: PackedFloat32Array, name: String, width_ref: int) -> Image:
	var img: Image = L.to_img(buf, W, H)
	var r := Rect2i(X0, Y0, width_ref, Y1 - Y0)
	var crop := img.get_region(r)
	crop.save_png("res://build/v2/%s_ref.png" % name)
	var nw := int(round(width_ref * S))
	var nh := int(round((Y1 - Y0) * S))
	var small: Image = L.resize_pm(crop, nw, nh, Image.INTERPOLATE_LANCZOS)
	small.save_png(OUT + name + ".png")
	return small


func _init() -> void:
	tank = L.to_f(Image.load_from_file("res://build/v2/tank_ref_full.png"))
	var tm := poly_mask([
		Vector2(188, 118), Vector2(242, 118), Vector2(242, 204), Vector2(400, 204), Vector2(421, 236),
		Vector2(534, 236), Vector2(534, 261), Vector2(421, 259), Vector2(415, 263), Vector2(188, 263),
	])
	var bm := poly_mask([Vector2(419, 238), Vector2(534, 238), Vector2(534, 259), Vector2(419, 259)])
	hull = tank.duplicate()
	turret = tank.duplicate()
	barrel = tank.duplicate()
	for i in W * H:
		var t := tm[i]
		var b := bm[i] * t
		hull[i * 4 + 3] *= (1.0 - t)
		turret[i * 4 + 3] *= t * (1.0 - b)
		barrel[i * 4 + 3] *= b
	find_period()
	# Variants: cuts at bulkheads (see kit.json). delta = change in hull length (reference px).
	var variants := {
		"tank_1rider": {"upper": {"cut": [262, 391]}, "lower": {"cut": [257, 386]}, "delta": -129,
			"turret_dx": -60, "turret_scale": 0.85},
		"tank_2rider": {"upper": {"cut": [188, 264]}, "lower": {"cut": [256, 332]}, "delta": -76,
			"turret_dx": -40, "turret_scale": 1.0},
		"tank_3rider": {"upper": {}, "lower": {}, "delta": 0, "turret_dx": 0, "turret_scale": 1.0},
		"tank_4rider": {"upper": {"dup": [189, 243]}, "lower": {"dup": [332, 386]}, "delta": 54,
			"turret_dx": 44, "turret_scale": 1.0, "tower": true},
	}
	var results := {}
	for name in variants:
		var v: Dictionary = variants[name]
		var d: int = v.delta
		var buf := build_hull(v, d)
		var sc: float = v.turret_scale
		var piv := Vector2(300, 263)
		if bool(v.get("tower", false)):
			arc_tint(buf, 386, 440)
		comp(buf, barrel, Vector2(v.turret_dx, 0), sc, piv)
		comp(buf, turret, Vector2(v.turret_dx, 0), sc, piv)
		results[name] = save_variant(buf, name, X1 - X0 + d)
		if bool(v.get("tower", false)):
			draw_tower(results[name], int(round((150 - X0) * S)), int(round((251 - Y0) * S)))
			results[name].save_png(OUT + name + ".png")
		print(name, " ref width ", X1 - X0 + d, " -> ", results[name].get_width(), "x", results[name].get_height())
	# separate parts at 960 scale (reference = 3 rider)
	var parts := {"hull_3rider": hull, "turret_body": turret, "turret_barrel": barrel}
	for pn in parts:
		save_variant(parts[pn], pn, X1 - X0)
	results["tank_3rider"].save_png(OUT + "tank_citadel.png")
	lineup(results)
	quit()


# The duplicated lower room becomes the arc generator room: its warm light turns cold blue-white.
func arc_tint(buf: PackedFloat32Array, xa: int, xb: int) -> void:
	for y in range(Y_LOWER, Y_RG - 2):
		for x in range(xa + 3, xb - 2):
			var i := (y * W + x) * 4
			var l := (buf[i] + buf[i + 1] + buf[i + 2]) / 3.0
			var k := smoothstep(0.07, 0.32, l)
			buf[i] = lerpf(buf[i], l * 0.78, k)
			buf[i + 1] = lerpf(buf[i + 1], l * 0.98, k)
			buf[i + 2] = lerpf(buf[i + 2], minf(l * 1.3, 1.0), k)


const TOWER := [
	"....hhhhhhh.RR.",
	"...hMMMMMMMRLR.",
	"..hMmmmmmmmRLLR",
	"..MmmmmmmmmRLLR",
	"..MmmmmmmmmRLLR",
	"..MMMMMMMMMRLLR",
	"...MMMMMMMMRLR.",
	"....sssssss.RR.",
	"......y.y......",
	"......yyy......",
	".......p.......",
	".......p.......",
	".......p.......",
	".......p.......",
	".......p.......",
	"......ppp......",
	".....qqqqq.....",
]
const TOWER_PAL := {
	"h": Color8(150, 118, 76), "M": Color8(62, 48, 34), "m": Color8(92, 72, 48), "R": Color8(176, 146, 98),
	"L": Color8(255, 238, 180), "s": Color8(40, 32, 24), "y": Color8(84, 66, 44), "p": Color8(70, 56, 40),
	"q": Color8(48, 40, 30),
}


# Searchlight tower drawn at 960 scale; (bx, by) = post foot on the rear deck house roof.
func draw_tower(img: Image, bx: int, by: int) -> void:
	var rows: Array = TOWER
	var ox := bx - 7
	var oy := by - rows.size() + 1
	for r in rows.size():
		var row: String = rows[r]
		for c in row.length():
			var ch := row[c]
			if ch != "." and TOWER_PAL.has(ch):
				img.set_pixel(ox + c, oy + r, TOWER_PAL[ch])
	print("tower lens at 960 px ", ox + 13, ",", oy + 3)


# (unused) Searchlight tower on the rear deck house (4 riders): a post plus the old turret-top sight box as lamp housing.
func add_tower(buf: PackedFloat32Array) -> void:
	var ref: PackedFloat32Array = L.to_f(Image.load_from_file("res://build/v2/ref.png"))
	var bg: PackedFloat32Array = L.to_f(Image.load_from_file("res://build/v2/plate_ref.png"))
	var post_c := Color8(58, 46, 34)
	var post_hi := Color8(112, 88, 60)
	var px0 := 150
	for y in range(236, 252):
		for x in range(px0, px0 + 3):
			var c := post_hi if x == px0 else post_c
			if y % 5 == 0 and x == px0 + 1:
				c = Color8(150, 120, 80)
			put(buf, x, y, c)
	for x in range(px0 - 3, px0 + 6):
		put(buf, x, 250, Color8(70, 56, 40))
		put(buf, x, 251, Color8(44, 36, 28))
	# lamp housing from the sight box (281..302, 196..213), alpha from the difference to the plate
	var hx := px0 - 9
	var hy := 222
	for y in range(196, 213):
		for x in range(281, 302):
			var i := (y * W + x) * 4
			var d := maxf(absf(ref[i] - bg[i]), maxf(absf(ref[i + 1] - bg[i + 1]), absf(ref[i + 2] - bg[i + 2])))
			var a := smoothstep(0.03, 0.09, d)
			if x >= 299:
				a = 0.0
			if a <= 0.0:
				continue
			var tx := hx + (x - 281)
			var ty := hy + (y - 196)
			var j := (ty * W + tx) * 4
			var c := Color(ref[i], ref[i + 1], ref[i + 2])
			var da := buf[j + 3]
			var oa := a + da * (1.0 - a)
			buf[j] = (c.r * a + buf[j] * da * (1.0 - a)) / oa
			buf[j + 1] = (c.g * a + buf[j + 1] * da * (1.0 - a)) / oa
			buf[j + 2] = (c.b * a + buf[j + 2] * da * (1.0 - a)) / oa
			buf[j + 3] = oa
	# lens
	for y in range(hy + 4, hy + 11):
		put(buf, hx + 18, y, Color8(255, 236, 170))
		put(buf, hx + 19, y, Color8(255, 214, 130) if y > hy + 4 and y < hy + 10 else Color8(90, 80, 60))


func put(buf: PackedFloat32Array, x: int, y: int, c: Color) -> void:
	var i := (y * W + x) * 4
	buf[i] = c.r
	buf[i + 1] = c.g
	buf[i + 2] = c.b
	buf[i + 3] = 1.0


func lineup(results: Dictionary) -> void:
	var names := ["tank_1rider", "tank_2rider", "tank_3rider", "tank_4rider"]
	var maxw := 0
	var hsum := 0
	for n in names:
		maxw = maxi(maxw, results[n].get_width())
		hsum += results[n].get_height() + 24
	var sheet := Image.create(maxw + 140, hsum + 30, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(16, 18, 20))
	F.draw(sheet, 8, 8, "TANK VARIANTS AT 960X540 ART SCALE (REAR ALIGNED)", Color8(200, 190, 170), 1)
	var y := 30
	var labels := ["1 RIDER", "2 RIDERS", "3 RIDERS", "4 RIDERS"]
	for k in names.size():
		var img: Image = results[names[k]]
		F.draw(sheet, 8, y + img.get_height() / 2 - 10, labels[k], Color8(230, 210, 160), 2)
		F.draw(sheet, 8, y + img.get_height() / 2 + 6, "%d PX" % img.get_width(), Color8(150, 140, 120), 1)
		# ground line
		sheet.fill_rect(Rect2i(130, y + img.get_height() - 4, maxw, 1), Color8(60, 52, 40))
		sheet.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(130, y))
		y += img.get_height() + 24
	sheet.save_png(OUT + "variants_lineup.png")
