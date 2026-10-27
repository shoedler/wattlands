extends RefCounted
## The static hull of the v3 tank mock: plated parts (fill on a fixed ramp with ordered dither,
## plate tones, weathering, seams with a lit bevel, rivet rows, the outline and a lit top edge),
## the cutaway openings (bays, the hoist shaft, the turret window) with their lamp-lit interiors,
## hatches, vision blocks, exhaust stacks, the headlight. Built once per layout.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const OUT := Color("#0b0806")
const RAMP_HULL: Array = [
	Color("#120c08"), Color("#1d150e"), Color("#2a1f15"), Color("#382a1d"), Color("#483626"), Color("#5c4530")
]
const RAMP_ENEMY: Array = [
	Color("#0d100e"), Color("#161b17"), Color("#212722"), Color("#2d352e"), Color("#3b443b"), Color("#4d574b")
]
const RAMP_WALL: Array = [
	Color("#1a1109"), Color("#2c1d0e"), Color("#432c14"), Color("#62411c"), Color("#875b27"), Color("#b07a34")
]
const HI := Color("#86683f")
const HI_EN := Color("#66705f")
const RUST := Color("#4f2e18")
const RIV_HI := Color("#b2905e")
const RIV_HI_EN := Color("#8c9584")
const RIV_LO := Color("#0e0906")
const LAMP := Color("#ffd98a")
const LAMP_CORE := Color("#fff6d8")
const FLOOR := Color("#1d140b")
const FLOOR_EDGE := Color("#7a5a30")
const BEAM := Color("#120c07")


## Builds the static image and masks of layout `L`: {img, mask (part id + 1), open (opening id + 1),
## dist (px to the hull's edge), w, h}.
static func build(L: Dictionary) -> Dictionary:
	var sz: Vector2i = L["size"]
	var w := sz.x
	var h := sz.y
	var img := Px.blank(w, h)
	var mask := PackedByteArray()
	mask.resize(w * h)
	var enemy := bool(L.get("enemy", false))
	var pid := 0
	for part: Dictionary in L["parts"]:
		pid += 1
		_part(img, mask, w, h, part, pid, enemy)
	var dist := _distance(mask, w, h)
	var open := PackedByteArray()
	open.resize(w * h)
	var oid := 0
	for o: Dictionary in L.get("openings", []):
		oid += 1
		_opening(img, open, dist, w, h, o, oid)
	_cut_edges(img, open, mask, w, h)
	for d: Dictionary in L.get("details", []):
		_detail(img, d, enemy)
	return {"img": img, "mask": mask, "open": open, "dist": dist, "w": w, "h": h}


static func _part(img: Image, mask: PackedByteArray, w: int, h: int, part: Dictionary, pid: int, enemy: bool) -> void:
	var poly: PackedVector2Array = part["poly"]
	var bb := Px.poly_bounds(poly)
	var seed := int(part.get("seed", pid * 17))
	var tone := float(part.get("tone", 0.0))
	var sx: Array = part.get("seams_x", [])
	var sy: Array = part.get("seams_y", [])
	var ramp: Array = RAMP_ENEMY if enemy else RAMP_HULL
	var own := PackedByteArray()
	own.resize(w * h)
	for y in range(maxi(bb.position.y, 0), mini(bb.end.y, h)):
		for x in range(maxi(bb.position.x, 0), mini(bb.end.x, w)):
			if Px.in_poly(Vector2(x + 0.5, y + 0.5), poly):
				own[y * w + x] = 1
	# a part that stands proud of the hull (a sponson) casts a shadow down-left and has a lit top face
	var top_face := int(part.get("top_face", 0))
	if bool(part.get("shadow", false)):
		for y in range(maxi(bb.position.y, 0), mini(bb.end.y + 3, h)):
			for x in range(maxi(bb.position.x - 3, 0), mini(bb.end.x, w)):
				if own[y * w + x] == 0 and _own(own, w, h, x + 3, y - 3) and mask[y * w + x] != 0:
					img.set_pixel(x, y, ramp[0])
	for y in range(maxi(bb.position.y, 0), mini(bb.end.y, h)):
		for x in range(maxi(bb.position.x, 0), mini(bb.end.x, w)):
			if own[y * w + x] == 0:
				continue
			mask[y * w + x] = pid
			var px_i := 0
			for s in sx:
				if x > int(s):
					px_i += 1
			var py_i := 0
			for s in sy:
				if y > int(s):
					py_i += 1
			var v := 0.5 + tone
			if top_face > 0 and not _own(own, w, h, x, y - top_face):
				v += 0.3
			v += (Px.h2(px_i, py_i, seed) - 0.5) * 0.16
			v += (Px.vnoise(x, y, 11.0, seed) - 0.5) * 0.22
			v += (Px.vnoise(x, y, 3.0, seed + 1) - 0.5) * 0.12
			v += (1.0 - float(y - bb.position.y) / float(maxi(bb.size.y, 1))) * 0.16 - 0.08
			var col := Px.dither(ramp, v, x, y)
			if not enemy and Px.vnoise(x, y, 6.0, seed + 7) > 0.74 and Px.h2(x, y, seed + 2) > 0.55:
				col = RUST
			if Px.h2(x, y, seed + 3) > 0.988:
				col = ramp[5]
			img.set_pixel(x, y, col)
	var hi: Color = HI_EN if enemy else HI
	var rv: Color = RIV_HI_EN if enemy else RIV_HI
	var step := int(part.get("rivet", 4))
	# vertical seams: dark line, lit bevel right of it, rivet columns either side
	for s in sx:
		var x := int(s)
		for y in range(bb.position.y, bb.end.y):
			if _own(own, w, h, x, y):
				img.set_pixel(x, y, ramp[0])
				if _own(own, w, h, x + 1, y):
					img.set_pixel(x + 1, y, ramp[4])
				if y % step == 1 and _deep(own, w, h, x, y, 3):
					_rivet(img, x - 2, y, rv)
					_rivet(img, x + 3, y, rv)
	for s in sy:
		var y := int(s)
		for x in range(bb.position.x, bb.end.x):
			if _own(own, w, h, x, y):
				img.set_pixel(x, y, ramp[0])
				if _own(own, w, h, x, y - 1):
					img.set_pixel(x, y - 1, ramp[4])
				if x % step == 2 and _deep(own, w, h, x, y, 3):
					_rivet(img, x, y - 3, rv)
					_rivet(img, x, y + 2, rv)
	# rivet rows along the edges, 3 px in
	if bool(part.get("edge_rivets", true)):
		var n := poly.size()
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			var d := b - a
			var ln := d.length()
			if ln < 6.0:
				continue
			var nin := Vector2(-d.y, d.x) / ln
			if not Px.in_poly(a.lerp(b, 0.5) + nin * 3.0, poly):
				nin = -nin
			var k := 3.0
			while k < ln - 2.0:
				var p := a + d / ln * k + nin * 3.0
				if _deep(own, w, h, floori(p.x), floori(p.y), 2):
					_rivet(img, floori(p.x), floori(p.y), rv)
				k += step
	# outline and lit top edge, shadowed lower edge
	for y in range(bb.position.y, bb.end.y):
		for x in range(bb.position.x, bb.end.x):
			if not _own(own, w, h, x, y):
				continue
			var edge := (
				not _own(own, w, h, x - 1, y)
				or not _own(own, w, h, x + 1, y)
				or not _own(own, w, h, x, y - 1)
				or not _own(own, w, h, x, y + 1)
			)
			if edge:
				img.set_pixel(x, y, OUT)
			elif not _own(own, w, h, x, y - 2):
				img.set_pixel(x, y, hi)
			elif not _own(own, w, h, x, y + 2):
				img.set_pixel(x, y, ramp[1])


static func _own(own: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and own[y * w + x] != 0


static func _deep(own: PackedByteArray, w: int, h: int, x: int, y: int, r: int) -> bool:
	return (
		_own(own, w, h, x - r, y) and _own(own, w, h, x + r, y) and _own(own, w, h, x, y - r) and _own(own, w, h, x, y + r)
	)


static func _rivet(img: Image, x: int, y: int, c: Color) -> void:
	Px.put(img, x, y, c)
	Px.put(img, x + 1, y + 1, RIV_LO)


## City-block distance of every hull pixel to the nearest non-hull pixel.
static func _distance(mask: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(w * h)
	var big := 1 << 20
	for i in w * h:
		d[i] = big if mask[i] != 0 else 0
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0:
				continue
			var m := d[i]
			if x > 0:
				m = mini(m, d[i - 1] + 1)
			else:
				m = 1
			if y > 0:
				m = mini(m, d[i - w] + 1)
			else:
				m = 1
			d[i] = m
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0:
				continue
			var m := d[i]
			if x < w - 1:
				m = mini(m, d[i + 1] + 1)
			else:
				m = 1
			if y < h - 1:
				m = mini(m, d[i + w] + 1)
			else:
				m = 1
			d[i] = m
	return d


## One cutaway opening: rect r inside the hull (at least `inset` px from its edge), lit by a lamp
## at the top centre (or `lamp` px), with wall ribs, plank lines, a ceiling beam and a floor.
static func _opening(
	img: Image, open: PackedByteArray, dist: PackedInt32Array, w: int, h: int, o: Dictionary, oid: int
) -> void:
	var r: Rect2i = o["rect"]
	var inset := int(o.get("inset", 4))
	var lamp: Vector2 = o.get("lamp", Vector2(r.position.x + r.size.x * 0.5, r.position.y + 3))
	var has_lamp := bool(o.get("has_lamp", true))
	var reach := float(o.get("reach", maxf(r.size.x, r.size.y) * 0.8))
	var dim := float(o.get("dim", 0.0))
	var floor_y := r.end.y - 3 if bool(o.get("floor", true)) else r.end.y + 10
	var beam := bool(o.get("beam", true))
	oid = int(o.get("group", oid))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if dist[y * w + x] < inset:
				continue
			open[y * w + x] = oid
			var dl := Vector2(x + 0.5, (y + 0.5 - lamp.y) * 1.25 + lamp.y).distance_to(lamp)
			var v := clampf(1.0 - dl / reach, 0.0, 1.0)
			v = v * v * 0.95 + 0.08 - dim
			var rx := (x - r.position.x) % 13
			if rx == 0:
				v -= 0.14
			elif rx == 1:
				v += 0.04
			if (y - r.position.y) % 8 == 7:
				v -= 0.06
			var col := Px.dither(RAMP_WALL, v, x, y)
			if beam and y < r.position.y + 2:
				col = BEAM
			if y >= floor_y:
				col = FLOOR if y > floor_y else FLOOR_EDGE
			img.set_pixel(x, y, col)
	# the cut's own shadow: the first two rows under the hull and the column right of the left wall
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h or open[y * w + x] != oid:
				continue
			var up_wall := y - 1 >= 0 and open[(y - 1) * w + x] != oid
			var up2 := y - 2 >= 0 and open[(y - 2) * w + x] != oid
			var lw := x - 1 >= 0 and open[y * w + x - 1] != oid
			if up_wall or lw:
				img.set_pixel(x, y, BEAM)
			elif up2:
				Px.mix(img, x, y, BEAM, 0.55)
	if has_lamp:
		var lx := floori(lamp.x)
		var ly := floori(lamp.y)
		Px.put(img, lx - 1, ly - 1, BEAM)
		Px.put(img, lx, ly - 1, BEAM)
		Px.put(img, lx - 1, ly, LAMP)
		Px.put(img, lx, ly, LAMP_CORE)
		Px.put(img, lx + 1, ly, LAMP)
		Px.put(img, lx, ly + 1, LAMP)


## Hull pixels touching an opening become the cut's dark edge.
static func _cut_edges(img: Image, open: PackedByteArray, mask: PackedByteArray, w: int, h: int) -> void:
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			if open[i] != 0 or mask[i] == 0:
				continue
			if open[i - 1] != 0 or open[i + 1] != 0 or open[i - w] != 0 or open[i + w] != 0:
				img.set_pixel(x, y, OUT)


static func _detail(img: Image, d: Dictionary, enemy: bool) -> void:
	var ramp: Array = RAMP_ENEMY if enemy else RAMP_HULL
	match str(d["kind"]):
		"hatch":
			var r: Rect2i = d["rect"]
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
					var col: Color = ramp[3] if not edge else OUT
					if not edge and y == r.position.y + 1:
						col = ramp[5]
					if not edge and x == r.end.x - 2:
						col = ramp[1]
					Px.put(img, x, y, col)
			# hinges and handle
			Px.put(img, r.position.x - 1, r.position.y + 2, ramp[4])
			Px.put(img, r.position.x - 1, r.end.y - 3, ramp[4])
			Px.put(img, r.end.x - 4, r.position.y + r.size.y / 2, RIV_HI)
			Px.put(img, r.end.x - 4, r.position.y + r.size.y / 2 + 1, RIV_LO)
		"vision":
			var p: Vector2i = d["at"]
			var ln := int(d.get("w", 5))
			Px.rect(img, Rect2i(p.x - 1, p.y - 1, ln + 2, 4), OUT)
			Px.rect(img, Rect2i(p.x, p.y, ln, 2), Color("#0f1a1c"))
			Px.put(img, p.x + 1, p.y, Color("#6f9aa0"))
			Px.rect(img, Rect2i(p.x - 1, p.y - 2, ln + 2, 1), ramp[5])
		"stack":
			var x0 := int(d["x"])
			for y in range(int(d["y0"]), int(d["y1"])):
				Px.put(img, x0 - 1, y, OUT)
				Px.put(img, x0, y, Color("#5a3a24"))
				Px.put(img, x0 + 1, y, Color("#3a2416"))
				Px.put(img, x0 + 2, y, OUT)
			Px.rect(img, Rect2i(x0 - 2, int(d["y0"]) - 1, 5, 2), OUT)
			Px.rect(img, Rect2i(x0 - 1, int(d["y0"]) - 1, 3, 1), Color("#7a5a3a"))
		"headlight":
			var p2: Vector2i = d["at"]
			Px.rect(img, Rect2i(p2.x - 2, p2.y - 3, 5, 6), OUT)
			Px.rect(img, Rect2i(p2.x - 1, p2.y - 2, 3, 4), Color("#b08a4a"))
			Px.rect(img, Rect2i(p2.x, p2.y - 1, 2, 2), LAMP_CORE)
			Px.put(img, p2.x + 2, p2.y - 1, LAMP)
			Px.put(img, p2.x + 2, p2.y, LAMP)
		"searchlight":
			var p3: Vector2i = d["at"]
			Px.rect(img, Rect2i(p3.x - 6, p3.y - 4, 9, 8), OUT)
			Px.rect(img, Rect2i(p3.x - 5, p3.y - 3, 7, 6), ramp[3])
			Px.rect(img, Rect2i(p3.x - 5, p3.y - 3, 7, 1), ramp[5])
			Px.rect(img, Rect2i(p3.x + 2, p3.y - 3, 2, 6), Color("#b08a4a"))
			Px.rect(img, Rect2i(p3.x - 3, p3.y + 4, 3, 3), OUT)
		"lamp_red":
			var p4: Vector2i = d["at"]
			Px.put(img, p4.x, p4.y, Color("#ff5a3c"))
			Px.put(img, p4.x, p4.y + 1, Color("#8a2a1c"))
		"rail":
			var a: Vector2i = d["a"]
			var b: Vector2i = d["b"]
			Px.line(img, a, b, ramp[4])
			Px.line(img, a + Vector2i(0, 1), b + Vector2i(0, 1), OUT)
			var x := a.x
			while x <= b.x:
				Px.put(img, x, a.y + 2, OUT)
				x += 8
		"antenna":
			var p5: Vector2i = d["at"]
			for y in range(p5.y - int(d["h"]), p5.y):
				Px.put(img, p5.x, y, Color("#3a2c1e") if y % 5 else Color("#6a5236"))
			Px.rect(img, Rect2i(p5.x - 1, p5.y - 1, 3, 2), OUT)
		"slit":
			var p6: Vector2i = d["at"]
			Px.rect(img, Rect2i(p6.x, p6.y, int(d.get("w", 6)), 1), OUT)
			Px.rect(img, Rect2i(p6.x, p6.y + 1, int(d.get("w", 6)), 1), ramp[5])
