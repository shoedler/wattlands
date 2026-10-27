extends SceneTree
# Paints over markings and crew on the tank surface (reference coordinates). Writes ref_fixed.png.

var L = load("res://build/v2/lib.gd")
var S = load("res://build/v2/shapes.gd")
const W := 1088
const H := 608
var col: PackedFloat32Array
var rng := RandomNumberGenerator.new()


func px(x: int, y: int) -> Color:
	var i := (y * W + x) * 4
	return Color(col[i], col[i + 1], col[i + 2])


func put(x: int, y: int, c: Color, a: float = 1.0) -> void:
	var i := (y * W + x) * 4
	col[i] = lerpf(col[i], c.r, a)
	col[i + 1] = lerpf(col[i + 1], c.g, a)
	col[i + 2] = lerpf(col[i + 2], c.b, a)


func avg(x0: int, x1: int, y0: int, y1: int) -> Color:
	var s := Color(0, 0, 0)
	var n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			s += px(x, y)
			n += 1
	return s / float(n)


# Row interpolation between the columns just outside r, plus seeded grain.
func heal(r: Rect2i, grain: float, feather: int = 1) -> void:
	var rows: Array[Array] = []
	for y in range(r.position.y, r.end.y):
		var lc := avg(r.position.x - 2, r.position.x - 1, y - 1, y + 1)
		var rc := avg(r.end.x, r.end.x + 1, y - 1, y + 1)
		var row: Array[Color] = []
		for x in range(r.position.x, r.end.x):
			var t := (x - r.position.x + 0.5) / r.size.x
			var c := lerp(lc, rc, t) as Color
			var g := rng.randfn(0.0, grain)
			row.append(Color(c.r + g, c.g + g * 0.9, c.b + g * 0.8))
		rows.append(row)
	for yy in rows.size():
		for xx in r.size.x:
			var d := mini(mini(xx, r.size.x - 1 - xx), mini(yy, r.size.y - 1 - yy))
			var a := 1.0 if d >= feather else (d + 1.0) / (feather + 1.0)
			put(r.position.x + xx, r.position.y + yy, rows[yy][xx], a)


# Copy a block from src offset into r with a feathered border.
func clone(r: Rect2i, off: Vector2i, feather: int = 2, flip: bool = false) -> void:
	var buf: Array[Color] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var sx := (r.end.x - 1 - (x - r.position.x)) if flip else x
			buf.append(px(sx + off.x, y + off.y))
	var k := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var d := mini(mini(x - r.position.x, r.end.x - 1 - x), mini(y - r.position.y, r.end.y - 1 - y))
			var a := 1.0 if d >= feather else (d + 1.0) / (feather + 1.0)
			put(x, y, buf[k], a)
			k += 1


func _init() -> void:
	rng.seed = 17
	col = L.to_f(Image.load_from_file("res://build/v2/ref.png"))
	# Turret side: white star and "A17" -> plain plate.
	heal(Rect2i(304, 231, 26, 25), 0.012, 2)
	heal(Rect2i(341, 238, 30, 18), 0.012, 2)
	# Searchlight beam glow over the turret's sloped front: pull luminance back to the plate level.
	var plate_c := avg(340, 368, 226, 236)
	var plate_l := (plate_c.r + plate_c.g + plate_c.b) / 3.0
	var beam: PackedFloat32Array = L.mask_new(W, H)
	L.poly_fill(beam, W, H, PackedVector2Array(S.SEARCH_BEAM))
	beam = L.blur1(beam, W, H, 2)
	var lum: PackedFloat32Array = L.mask_new(W, H)
	for i in W * H:
		lum[i] = (col[i * 4] + col[i * 4 + 1] + col[i * 4 + 2]) / 3.0
	var lum_lp: PackedFloat32Array = L.blur1(lum, W, H, 4)
	for y in range(196, 262):
		for x in range(360, 422):
			var i := y * W + x
			if beam[i] <= 0.0:
				continue
			var k := clampf(plate_l / maxf(lum_lp[i], 0.001), 0.35, 1.0)
			k = lerpf(1.0, k, beam[i])
			var c := px(x, y)
			put(x, y, Color(c.r * k, c.g * k * 0.97, c.b * k * 0.95))
	# Upper rear room: four standing crew -> empty room (clone the furniture bays left/right).
	clone(Rect2i(188, 283, 22, 23), Vector2i(-38, 0), 2)
	clone(Rect2i(208, 283, 22, 23), Vector2i(58, 0), 2, true)
	clone(Rect2i(228, 283, 18, 23), Vector2i(-78, 0), 2, true)
	clone(Rect2i(244, 283, 20, 23), Vector2i(26, 0), 2)
	# Lower deck figure between the ladders.
	heal(Rect2i(257, 315, 13, 21), 0.01, 1)
	# Lower front room: two crew.
	heal(Rect2i(428, 330, 9, 20), 0.012, 1)
	heal(Rect2i(439, 329, 9, 21), 0.012, 1)
	# Upper front room: small figure.
	heal(Rect2i(390, 297, 8, 11), 0.01, 1)
	# Upper middle room: seated figure at the left; shell-rack room: crouching figure.
	heal(Rect2i(300, 293, 10, 15), 0.01, 1)
	heal(Rect2i(313, 339, 12, 10), 0.01, 1)
	L.to_img(col, W, H).save_png("res://build/v2/ref_fixed.png")
	quit()
