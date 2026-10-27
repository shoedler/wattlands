extends RefCounted
## The static hull of the v3 tank mock, built once per layout:
##  - plated parts: each part is cut into overlapping armour plates of different sizes (the
##    layout's structural seams, then a seeded split or two), each plate with a lit top edge and a
##    shadowed lower edge, its own tone, and its fasteners (rivet rows, bolt heads with highlight and
##    shadow, or a weld bead); weathering (rust streaks under fasteners, chipped edges, grime low
##    down); the outline and a moonlit top edge. Cast parts (mantlet, cupola) get rounded shading and
##    pitting instead. Parts marked front (side skirts) go to a separate layer drawn over the track.
##  - the cutaway openings (bays, the hoist shaft, the turret window), dressed by dress.gd;
##  - exterior details: hatches with hinges, periscopes, vision blocks, vents, louvres, exhaust
##    stacks with soot, grab rails, tool racks, tow cable, jerrycans, spare track links, stowage box,
##    position lights, the headlight, the turret searchlight, the antenna.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Dress = preload("res://assets/tank/v3/tools_src/dress.gd")

const OUT := Color("#0b0806")
const RAMP_HULL: Array = [
	Color("#060403"), Color("#0c0806"), Color("#130d09"), Color("#1b130d"), Color("#251a12"), Color("#322419")
]
const RAMP_ENEMY: Array = [
	Color("#0d100e"), Color("#161b17"), Color("#212722"), Color("#2d352e"), Color("#3b443b"), Color("#4d574b")
]
const HI := Color("#4c3c2a")
const HI_EN := Color("#66705f")
const RUST := Color("#2e180c")
const RUST_L := Color("#45250f")
const CHIP := Color("#3e3428")
const RIV_HI := Color("#86683f")
const RIV_MID := Color("#33261a")
const RIV_HI_EN := Color("#8c9584")
const RIV_LO := Color("#0e0906")
const LAMP := Color("#ffd98a")
const LAMP_CORE := Color("#fff6d8")
const BRASS := Color("#b08a4a")
const STEEL := Color("#55534e")
const STEEL_L := Color("#8a877e")


## {img (hull body), front (skirts, over the track), mask (part id), open (opening group), dist
## (px to the hull's edge), w, h}.
static func build(L: Dictionary) -> Dictionary:
	var sz: Vector2i = L["size"]
	var w := sz.x
	var h := sz.y
	var img := Px.blank(w, h)
	var front := Px.blank(w, h)
	var mask := PackedByteArray()
	mask.resize(w * h)
	var fmask := PackedByteArray()
	fmask.resize(w * h)
	var enemy := bool(L.get("enemy", false))
	var pid := 0
	for part: Dictionary in L["parts"]:
		pid += 1
		if bool(part.get("front", false)):
			_part(front, fmask, w, h, part, pid, enemy)
		else:
			_part(img, mask, w, h, part, pid, enemy)
	var dist := _distance(mask, w, h)
	var open := PackedByteArray()
	open.resize(w * h)
	var oid := 0
	for o: Dictionary in L.get("openings", []):
		oid += 1
		_opening(img, open, dist, w, h, o, oid)
	_cut_edges(img, open, mask, w, h)
	for o: Dictionary in L.get("openings", []):
		if o.has("dress"):
			Dress.bay(img, open, w, h, o)
		if o.has("quarters"):
			Dress.quarters(img, open, w, h, o)
		if bool(o.get("machinery", false)):
			Dress.machinery(img, open, w, h, o)
	# exterior details never paint into a cutaway: keep the openings' pixels and put them back
	var keep := img.duplicate() as Image
	for d: Dictionary in L.get("details", []):
		_detail(front if bool(d.get("front", false)) else img, d, enemy)
	for y in h:
		for x in w:
			if open[y * w + x] != 0:
				img.set_pixel(x, y, keep.get_pixel(x, y))
	_spill(img, mask, open, w, h, L)
	return {"img": img, "front": front, "mask": mask, "open": open, "dist": dist, "w": w, "h": h}


# --- Plated parts ---------------------------------------------------------------------------------------


## The plates of a part: the structural grid (seams_x, seams_y over the bounds), each cell split once
## or twice more at a seeded point when it is big enough.
static func _plates(bb: Rect2i, sx: Array, sy: Array, seed: int, split: bool) -> Array[Rect2i]:
	var xs: Array[int] = [bb.position.x]
	for s in sx:
		xs.append(int(s))
	xs.append(bb.end.x)
	var ys: Array[int] = [bb.position.y]
	for s in sy:
		ys.append(int(s))
	ys.append(bb.end.y)
	var out: Array[Rect2i] = []
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var cell := Rect2i(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if split:
				_split(cell, 2, seed + i * 31 + j * 7, out)
			else:
				out.append(cell)
	return out


static func _split(r: Rect2i, depth: int, seed: int, out: Array[Rect2i]) -> void:
	var hv := Px.h2(r.position.x, r.position.y, seed)
	if depth > 0 and r.size.x > 34 and hv < 0.6:
		var f := 0.35 + Px.h2(r.position.y, r.size.x, seed + 1) * 0.3
		var cut := r.position.x + roundi(r.size.x * f)
		_split(Rect2i(r.position.x, r.position.y, cut - r.position.x, r.size.y), depth - 1, seed + 3, out)
		_split(Rect2i(cut, r.position.y, r.end.x - cut, r.size.y), depth - 1, seed + 5, out)
	elif depth > 0 and r.size.y > 20 and hv < 0.85:
		var cut2 := r.position.y + roundi(r.size.y * (0.4 + Px.h2(r.position.x, r.size.y, seed + 2) * 0.2))
		_split(Rect2i(r.position.x, r.position.y, r.size.x, cut2 - r.position.y), depth - 1, seed + 7, out)
		_split(Rect2i(r.position.x, cut2, r.size.x, r.end.y - cut2), depth - 1, seed + 9, out)
	else:
		out.append(r)


static func _part(img: Image, mask: PackedByteArray, w: int, h: int, part: Dictionary, pid: int, enemy: bool) -> void:
	var poly: PackedVector2Array = part["poly"]
	var bb := Px.poly_bounds(poly)
	var seed := int(part.get("seed", pid * 17))
	var tone := float(part.get("tone", 0.0))
	var cast := bool(part.get("cast", false))
	var ramp: Array = RAMP_ENEMY if enemy else RAMP_HULL
	var own := PackedByteArray()
	own.resize(w * h)
	var x0 := maxi(bb.position.x, 0)
	var x1 := mini(bb.end.x, w)
	var y0 := maxi(bb.position.y, 0)
	var y1 := mini(bb.end.y, h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if Px.in_poly(Vector2(x + 0.5, y + 0.5), poly):
				own[y * w + x] = 1
	var top_face := int(part.get("top_face", 0))
	if bool(part.get("shadow", false)):
		for y in range(y0, mini(y1 + 3, h)):
			for x in range(maxi(x0 - 3, 0), x1):
				if own[y * w + x] == 0 and _own(own, w, h, x + 3, y - 3) and mask[y * w + x] != 0:
					img.set_pixel(x, y, ramp[0])
	var plates := _plates(bb, part.get("seams_x", []), part.get("seams_y", []), seed, not cast and bool(part.get("split", true)))
	var pmap := PackedInt32Array()
	pmap.resize(w * h)
	pmap.fill(-1)
	for k in plates.size():
		var pr := plates[k]
		for y in range(maxi(pr.position.y, 0), mini(pr.end.y, h)):
			for x in range(maxi(pr.position.x, 0), mini(pr.end.x, w)):
				pmap[y * w + x] = k
	# fill
	for y in range(y0, y1):
		for x in range(x0, x1):
			if own[y * w + x] == 0:
				continue
			mask[y * w + x] = pid
			var v := 0.5 + tone
			v += (Px.vnoise(x, y, 11.0, seed) - 0.5) * 0.18
			v += (Px.vnoise(x, y, 3.0, seed + 1) - 0.5) * 0.1
			v += (1.0 - float(y - bb.position.y) / float(maxi(bb.size.y, 1))) * 0.18 - 0.1
			if top_face > 0 and not _own(own, w, h, x, y - top_face):
				v += 0.3
			if cast:
				var e := _edge_dist(own, w, h, x, y, 4)
				var up := 0 if _own(own, w, h, x, y - e - 1) else 1
				v += (0.18 if up == 1 else -0.12) * (1.0 - e / 4.0)
				if Px.h2(x, y, seed + 9) > 0.9:
					v -= 0.25
			else:
				var k := pmap[y * w + x]
				if k >= 0:
					var pr := plates[k]
					v += (Px.h2(k, seed, 5) - 0.5) * 0.2
					if y == pr.position.y:
						v += 0.3
					elif y == pr.position.y + 1:
						v += 0.1
					if x == pr.position.x:
						v += 0.14
					if y == pr.end.y - 1:
						v -= 0.4
					if x == pr.end.x - 1:
						v -= 0.25
			var col := Px.dither(ramp, v, x, y)
			if not enemy and Px.vnoise(x, y, 7.0, seed + 7) > 0.76 and Px.h2(x, y, seed + 2) > 0.5:
				col = RUST
			img.set_pixel(x, y, col)
	var rv: Color = RIV_HI_EN if enemy else RIV_HI
	var step := int(part.get("rivet", 4))
	# fasteners per plate, rust streaks under some of them
	if not cast:
		for k in plates.size():
			var pr := plates[k]
			var kind := Px.h2(k, seed, 11)
			if pr.size.x < 6 or pr.size.y < 6:
				continue
			if kind < 0.55:
				var xx := pr.position.x + 2
				while xx < pr.end.x - 2:
					_fasten(img, own, w, h, xx, pr.position.y + 2, rv, false, enemy, seed)
					if pr.size.y > 9:
						_fasten(img, own, w, h, xx, pr.end.y - 4, rv, false, enemy, seed)
					xx += step
				if pr.size.y > 14:
					var yy := pr.position.y + 2 + step
					while yy < pr.end.y - 5:
						_fasten(img, own, w, h, pr.position.x + 2, yy, rv, false, enemy, seed)
						_fasten(img, own, w, h, pr.end.x - 4, yy, rv, false, enemy, seed)
						yy += step
			elif kind < 0.82:
				var xb := pr.position.x + 2
				while xb < pr.end.x - 3:
					_fasten(img, own, w, h, xb, pr.position.y + 2, rv, true, enemy, seed)
					if pr.size.y > 10:
						_fasten(img, own, w, h, xb, pr.end.y - 5, rv, true, enemy, seed)
					xb += 8
			else:
				for xw in range(pr.position.x, pr.end.x):
					if _deep(own, w, h, xw, pr.position.y, 1):
						img.set_pixel(xw, pr.position.y, ramp[5] if xw % 2 == 0 else ramp[2])
				for yw in range(pr.position.y, pr.end.y):
					if _deep(own, w, h, pr.position.x, yw, 1):
						img.set_pixel(pr.position.x, yw, ramp[5] if yw % 2 == 0 else ramp[2])
	elif bool(part.get("bolts", false)):
		for y in range(y0 + 3, y1 - 3, 5):
			_fasten(img, own, w, h, x0 + 2, y, rv, true, enemy, seed)
	# chipped edges and grime
	for y in range(y0, y1):
		for x in range(x0, x1):
			if own[y * w + x] == 0:
				continue
			var e := _edge_dist(own, w, h, x, y, 3)
			if e >= 1 and e <= 2 and Px.h2(x, y, seed + 13) > (0.86 if e == 1 else 0.94):
				img.set_pixel(x, y, CHIP if not enemy else ramp[5])
	# outline and moonlit top edge
	var hi: Color = HI_EN if enemy else HI
	for y in range(y0, y1):
		for x in range(x0, x1):
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
				img.set_pixel(x, y, hi if Px.h2(x, y, seed + 17) > 0.12 else CHIP)
			elif not _own(own, w, h, x, y + 2):
				img.set_pixel(x, y, ramp[1])


## A rivet (1 px head, shadow down-right) or a bolt (2 x 2: lit, mid, shadow), sometimes with a rust
## streak running down from it.
static func _fasten(
	img: Image, own: PackedByteArray, w: int, h: int, x: int, y: int, c: Color, bolt: bool, enemy: bool, seed: int
) -> void:
	if not _deep(own, w, h, x, y, 2):
		return
	if bolt:
		img.set_pixel(x, y, c)
		Px.put(img, x + 1, y, RIV_MID)
		Px.put(img, x, y + 1, RIV_MID)
		Px.put(img, x + 1, y + 1, RIV_LO)
		Px.put(img, x + 2, y + 1, RIV_LO)
		Px.put(img, x + 1, y + 2, RIV_LO)
	else:
		img.set_pixel(x, y, c)
		Px.put(img, x + 1, y + 1, RIV_LO)
	if not enemy and Px.h2(x, y, seed + 21) > 0.86:
		var ln := 3 + floori(Px.h2(y, x, seed + 22) * 9.0)
		for k in ln:
			var yy := y + 2 + k
			if _deep(own, w, h, x, yy, 1):
				Px.mix(img, x, yy, RUST_L if k < 2 else RUST, 0.7 * (1.0 - float(k) / ln))


static func _own(own: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and own[y * w + x] != 0


static func _deep(own: PackedByteArray, w: int, h: int, x: int, y: int, r: int) -> bool:
	return (
		_own(own, w, h, x - r, y) and _own(own, w, h, x + r, y) and _own(own, w, h, x, y - r) and _own(own, w, h, x, y + r)
	)


## Chebyshev-ish distance to the part's edge, capped at `cap`.
static func _edge_dist(own: PackedByteArray, w: int, h: int, x: int, y: int, cap: int) -> int:
	for r in range(1, cap + 1):
		if not _deep(own, w, h, x, y, r):
			return r - 1
	return cap


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
			m = mini(m, d[i - 1] + 1) if x > 0 else 1
			m = mini(m, d[i - w] + 1) if y > 0 else 1
			d[i] = m
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0:
				continue
			var m := d[i]
			m = mini(m, d[i + 1] + 1) if x < w - 1 else 1
			m = mini(m, d[i + w] + 1) if y < h - 1 else 1
			d[i] = m
	return d


## Lamp light spilling out of the cutaways onto the hull round them: a breadth-first distance from
## every opening into the hull (up to `spill_px`), each hull pixel lit in its nearest opening's tint
## (L.tints: group -> Color; warm by default, none for an unlit group).
static func _spill(img: Image, mask: PackedByteArray, open: PackedByteArray, w: int, h: int, L: Dictionary) -> void:
	var reach := int(L.get("spill_px", 0))
	if reach <= 0:
		return
	var tints: Dictionary = L.get("tints", {})
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var grp := PackedByteArray()
	grp.resize(w * h)
	var q := PackedInt32Array()
	for i in w * h:
		if open[i] != 0:
			dist[i] = 0
			grp[i] = open[i]
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var d := dist[i]
		if d >= reach:
			continue
		var x := i % w
		var y := i / w
		for nb in [i - 1, i + 1, i - w, i + w]:
			if nb < 0 or nb >= w * h:
				continue
			if (nb == i - 1 and x == 0) or (nb == i + 1 and x == w - 1):
				continue
			if dist[nb] >= 0 or mask[nb] == 0:
				continue
			dist[nb] = d + 1
			grp[nb] = grp[i]
			q.append(nb)
	var amt := float(L.get("spill_amt", 0.5))
	for i in w * h:
		var d := dist[i]
		if d <= 1 or open[i] != 0:
			continue
		var g := int(grp[i])
		var tc: Color = tints.get(g, Color("#ff9a48"))
		if tc.a < 0.01:
			continue
		var f := 1.0 - float(d) / float(reach + 1)
		Px.add(img, i % w, i / w, tc, amt * f * f)


# --- Openings -------------------------------------------------------------------------------------------


## One cutaway opening: rect r inside the hull (at least `inset` px from its edge). The interior is
## filled with the wall shade here; dress.gd lights and furnishes it.
static func _opening(
	img: Image, open: PackedByteArray, dist: PackedInt32Array, w: int, h: int, o: Dictionary, oid: int
) -> void:
	var r: Rect2i = o["rect"]
	var inset := int(o.get("inset", 4))
	oid = int(o.get("group", oid))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= w or y >= h or dist[y * w + x] < inset:
				continue
			open[y * w + x] = oid
			img.set_pixel(x, y, Dress.WALL[1])
	Dress.light(img, open, w, h, o, oid)


## Hull pixels touching an opening become the cut's dark edge, with a lit lip below it.
static func _cut_edges(img: Image, open: PackedByteArray, mask: PackedByteArray, w: int, h: int) -> void:
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			if open[i] != 0 or mask[i] == 0:
				continue
			if open[i - 1] != 0 or open[i + 1] != 0 or open[i - w] != 0 or open[i + w] != 0:
				img.set_pixel(x, y, OUT)
			elif open[i - w * 2] != 0 and open[i - w] == 0:
				img.set_pixel(x, y, RAMP_HULL[4])


# --- Exterior details ------------------------------------------------------------------------------------


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
					if not edge and (x == r.end.x - 2 or y == r.end.y - 2):
						col = ramp[1]
					if not edge and Px.h2(x, y, 3) > 0.9:
						col = ramp[2]
					Px.put(img, x, y, col)
			# hinges, bolts, handle
			for hy in [r.position.y + 2, r.end.y - 4]:
				Px.rect(img, Rect2i(r.position.x - 2, hy, 3, 2), OUT)
				Px.put(img, r.position.x - 1, hy, ramp[5])
			Px.put(img, r.position.x + 2, r.position.y + 2, RIV_HI)
			Px.put(img, r.end.x - 3, r.position.y + 2, RIV_HI)
			Px.put(img, r.position.x + 2, r.end.y - 3, RIV_HI)
			Px.put(img, r.end.x - 3, r.end.y - 3, RIV_HI)
			var hx := r.end.x - 4
			var hy2 := r.position.y + r.size.y / 2
			Px.rect(img, Rect2i(hx - 1, hy2 - 1, 1, 3), BRASS)
			Px.put(img, hx, hy2 - 1, OUT)
			Px.put(img, hx, hy2 + 1, OUT)
		"hatch_top":
			# a raised roof hatch: lid ajar, hinge at the rear
			var p: Vector2i = d["at"]
			var wd := int(d.get("w", 10))
			Px.rect(img, Rect2i(p.x - 1, p.y - 3, wd + 2, 4), OUT)
			Px.rect(img, Rect2i(p.x, p.y - 2, wd, 2), ramp[4])
			Px.rect(img, Rect2i(p.x, p.y - 2, wd, 1), ramp[5])
			Px.rect(img, Rect2i(p.x + 2, p.y - 4, wd - 4, 1), OUT)
			Px.put(img, p.x + wd / 2, p.y - 4, BRASS)
			Px.put(img, p.x - 2, p.y - 1, ramp[5])
		"vision":
			var p: Vector2i = d["at"]
			var ln := int(d.get("w", 5))
			Px.rect(img, Rect2i(p.x - 2, p.y - 2, ln + 4, 6), OUT)
			Px.rect(img, Rect2i(p.x - 1, p.y - 1, ln + 2, 4), ramp[4])
			Px.rect(img, Rect2i(p.x - 1, p.y - 1, ln + 2, 1), ramp[5])
			Px.rect(img, Rect2i(p.x, p.y, ln, 2), Color("#0f1a1c"))
			Px.put(img, p.x + 1, p.y, Color("#7fb0b4"))
			Px.put(img, p.x + 2, p.y, Color("#3f6668"))
			Px.put(img, p.x - 1, p.y + 2, RIV_HI)
			Px.put(img, p.x + ln, p.y + 2, RIV_HI)
		"periscope":
			var p: Vector2i = d["at"]
			Px.rect(img, Rect2i(p.x - 1, p.y - 5, 6, 6), OUT)
			Px.rect(img, Rect2i(p.x, p.y - 4, 4, 4), ramp[4])
			Px.rect(img, Rect2i(p.x, p.y - 4, 4, 1), ramp[5])
			Px.rect(img, Rect2i(p.x + 3, p.y - 3, 1, 2), Color("#7fb0b4"))
		"stack":
			var x0 := int(d["x"])
			var ya := int(d["y0"])
			var yb := int(d["y1"])
			for y in range(ya, yb):
				Px.put(img, x0 - 2, y, OUT)
				Px.put(img, x0 - 1, y, Color("#6a4a2e"))
				Px.put(img, x0, y, Color("#4a3020"))
				Px.put(img, x0 + 1, y, Color("#2a1a10"))
				Px.put(img, x0 + 2, y, OUT)
				if (y - ya) % 4 == 1:
					Px.put(img, x0 - 1, y, Color("#8a6a48"))
			# soot-blackened lip and cap
			Px.rect(img, Rect2i(x0 - 3, ya - 2, 7, 3), OUT)
			Px.rect(img, Rect2i(x0 - 2, ya - 1, 5, 1), Color("#2a2420"))
			Px.rect(img, Rect2i(x0 - 1, ya - 1, 3, 1), Color("#141010"))
			# clamp
			Px.rect(img, Rect2i(x0 - 2, yb - 4, 5, 1), BRASS)
		"soot":
			var r2: Rect2i = d["rect"]
			for y in range(r2.position.y, r2.end.y):
				for x in range(r2.position.x, r2.end.x):
					var f := 1.0 - float(y - r2.position.y) / r2.size.y
					var cx := absf(x - r2.position.x - r2.size.x * 0.5) / (r2.size.x * 0.5)
					Px.mix(img, x, y, Color("#0a0806"), 0.6 * f * (1.0 - cx))
		"headlight":
			var p2: Vector2i = d["at"]
			Px.rect(img, Rect2i(p2.x - 3, p2.y - 4, 7, 8), OUT)
			Px.rect(img, Rect2i(p2.x - 2, p2.y - 3, 4, 6), ramp[4])
			Px.rect(img, Rect2i(p2.x - 2, p2.y - 3, 5, 1), ramp[5])
			Px.rect(img, Rect2i(p2.x + 1, p2.y - 2, 2, 4), LAMP)
			Px.rect(img, Rect2i(p2.x + 2, p2.y - 1, 1, 2), LAMP_CORE)
			Px.put(img, p2.x + 3, p2.y - 1, LAMP_CORE)
			Px.put(img, p2.x + 3, p2.y, LAMP)
			Px.rect(img, Rect2i(p2.x - 2, p2.y + 4, 3, 2), OUT)
		"searchlight":
			var p3: Vector2i = d["at"]
			# yoke, drum, lens, cable
			Px.rect(img, Rect2i(p3.x - 4, p3.y + 3, 5, 4), OUT)
			Px.rect(img, Rect2i(p3.x - 3, p3.y + 3, 3, 3), ramp[3])
			Px.rect(img, Rect2i(p3.x - 8, p3.y - 5, 12, 9), OUT)
			Px.rect(img, Rect2i(p3.x - 7, p3.y - 4, 10, 7), ramp[3])
			Px.rect(img, Rect2i(p3.x - 7, p3.y - 4, 10, 1), ramp[5])
			Px.rect(img, Rect2i(p3.x - 7, p3.y + 2, 10, 1), ramp[1])
			for x in range(p3.x - 6, p3.x + 2, 3):
				Px.put(img, x, p3.y - 2, ramp[5])
				Px.put(img, x, p3.y, ramp[1])
			Px.rect(img, Rect2i(p3.x + 3, p3.y - 5, 2, 9), BRASS)
			var lit := bool(d.get("lit", false))
			Px.rect(img, Rect2i(p3.x + 5, p3.y - 4, 1, 7), LAMP_CORE if lit else Color("#3a4a4c"))
			Px.put(img, p3.x + 5, p3.y - 2, Color("#9fc8cc") if not lit else LAMP_CORE)
		"lamp_red", "lamp_green":
			var p4: Vector2i = d["at"]
			var c1 := Color("#ff5a3c") if str(d["kind"]) == "lamp_red" else Color("#5cff8a")
			var c0 := Color("#8a2a1c") if str(d["kind"]) == "lamp_red" else Color("#1c7a3a")
			Px.rect(img, Rect2i(p4.x - 1, p4.y - 1, 3, 4), OUT)
			Px.put(img, p4.x, p4.y, c1)
			Px.put(img, p4.x, p4.y + 1, c0)
		"rail":
			var a: Vector2i = d["a"]
			var b: Vector2i = d["b"]
			Px.line(img, a + Vector2i(0, 1), b + Vector2i(0, 1), OUT)
			Px.line(img, a, b, Color("#7a6044"))
			var n := maxi(int(a.distance_to(b) / 10.0), 1)
			for k in n + 1:
				var q := Vector2(a).lerp(Vector2(b), float(k) / n)
				Px.put(img, floori(q.x), floori(q.y) + 1, ramp[3])
				Px.put(img, floori(q.x), floori(q.y) + 2, OUT)
		"antenna":
			var p5: Vector2i = d["at"]
			for y in range(p5.y - int(d["h"]), p5.y):
				Px.put(img, p5.x, y, Color("#3a2c1e") if y % 5 else Color("#6a5236"))
			Px.rect(img, Rect2i(p5.x - 2, p5.y - 2, 5, 3), OUT)
			Px.rect(img, Rect2i(p5.x - 1, p5.y - 1, 3, 1), BRASS)
			Px.put(img, p5.x, p5.y - int(d["h"]) - 1, Color("#b2905e"))
		"slit":
			var p6: Vector2i = d["at"]
			Px.rect(img, Rect2i(p6.x - 1, p6.y - 1, int(d.get("w", 6)) + 2, 3), ramp[4])
			Px.rect(img, Rect2i(p6.x, p6.y, int(d.get("w", 6)), 1), OUT)
			Px.rect(img, Rect2i(p6.x, p6.y + 1, int(d.get("w", 6)), 1), ramp[5])
		"louvre":
			var r3: Rect2i = d["rect"]
			Px.rect(img, r3.grow(1), OUT)
			for y in range(r3.position.y, r3.end.y):
				for x in range(r3.position.x, r3.end.x):
					var k := (y - r3.position.y) % 3
					var col: Color = ramp[4] if k == 0 else (ramp[2] if k == 1 else OUT)
					if x == r3.position.x or x == r3.end.x - 1:
						col = ramp[3]
					Px.put(img, x, y, col)
			for y in range(r3.end.y + 1, r3.end.y + 7):
				for x in range(r3.position.x, r3.end.x):
					Px.mix(img, x, y, Color("#0a0806"), 0.4 * (1.0 - float(y - r3.end.y) / 7.0))
		"vent":
			var p7: Vector2i = d["at"]
			Px.rect(img, Rect2i(p7.x - 3, p7.y - 3, 7, 4), OUT)
			Px.rect(img, Rect2i(p7.x - 2, p7.y - 2, 5, 2), ramp[4])
			Px.rect(img, Rect2i(p7.x - 2, p7.y - 2, 5, 1), ramp[5])
			Px.rect(img, Rect2i(p7.x - 1, p7.y, 3, 1), ramp[1])
		"cable":
			# tow cable along the hull in clamps, eyes at both ends
			var a2: Vector2i = d["a"]
			var b2: Vector2i = d["b"]
			for x in range(a2.x, b2.x + 1):
				var t := (x - a2.x) % 3
				Px.put(img, x, a2.y, Color("#8a7a60") if t == 0 else Color("#4a4034"))
				Px.put(img, x, a2.y + 1, OUT)
			for x in range(a2.x + 6, b2.x - 4, 18):
				Px.rect(img, Rect2i(x, a2.y - 1, 2, 3), ramp[5])
				Px.put(img, x + 1, a2.y + 1, OUT)
			for e in [a2.x - 3, b2.x + 1]:
				Px.rect(img, Rect2i(e, a2.y - 1, 3, 3), Color("#6a5c48"))
				Px.put(img, e + 1, a2.y, OUT)
		"coil":
			var p8: Vector2i = d["at"]
			for ring in 3:
				for k in 40:
					var a3 := TAU * k / 40.0
					var q := Vector2(p8) + Vector2(cos(a3) * (6.0 - ring), sin(a3) * (2.4 - ring * 0.3))
					Px.put(img, floori(q.x), floori(q.y), Color("#7a6a52") if (k + ring) % 3 == 0 else Color("#3e352a"))
		"can":
			var p9: Vector2i = d["at"]
			Px.rect(img, Rect2i(p9.x - 1, p9.y - 1, 7, 9), OUT)
			Px.rect(img, Rect2i(p9.x, p9.y, 5, 7), Color("#3e4528"))
			Px.rect(img, Rect2i(p9.x, p9.y, 5, 1), Color("#5c6640"))
			Px.rect(img, Rect2i(p9.x, p9.y + 3, 5, 1), Color("#2a3018"))
			Px.rect(img, Rect2i(p9.x + 1, p9.y - 2, 2, 1), OUT)
			Px.put(img, p9.x + 3, p9.y - 1, Color("#5c6640"))
		"shovel":
			var a4: Vector2i = d["at"]
			Px.line(img, a4 + Vector2i(0, 1), a4 + Vector2i(16, 1), OUT)
			Px.line(img, a4, a4 + Vector2i(15, 0), Color("#7a5a36"))
			Px.rect(img, Rect2i(a4.x + 16, a4.y - 2, 5, 5), OUT)
			Px.rect(img, Rect2i(a4.x + 16, a4.y - 1, 4, 3), STEEL_L)
			Px.put(img, a4.x - 1, a4.y, OUT)
			Px.rect(img, Rect2i(a4.x + 4, a4.y - 1, 1, 3), ramp[5])
			Px.rect(img, Rect2i(a4.x + 12, a4.y - 1, 1, 3), ramp[5])
		"pick":
			var a5: Vector2i = d["at"]
			Px.line(img, a5 + Vector2i(0, 1), a5 + Vector2i(18, 1), OUT)
			Px.line(img, a5, a5 + Vector2i(17, 0), Color("#7a5a36"))
			Px.line(img, a5 + Vector2i(15, -3), a5 + Vector2i(19, 3), OUT)
			Px.line(img, a5 + Vector2i(16, -3), a5 + Vector2i(18, 2), STEEL_L)
			Px.rect(img, Rect2i(a5.x + 5, a5.y - 1, 1, 3), ramp[5])
		"bar":
			var a6: Vector2i = d["at"]
			Px.line(img, a6 + Vector2i(0, 1), a6 + Vector2i(int(d.get("w", 24)), 1), OUT)
			Px.line(img, a6, a6 + Vector2i(int(d.get("w", 24)), 0), STEEL)
			Px.put(img, a6.x + int(d.get("w", 24)), a6.y - 1, STEEL)
		"links":
			# spare track shoes hung along a line (a -> b)
			var a7: Vector2 = d["a"]
			var b7: Vector2 = d["b"]
			var n7 := int(d.get("n", 3))
			var ang := (b7 - a7).angle()
			for k in n7:
				var q := a7.lerp(b7, (k + 0.5) / n7)
				Px.profile(img, q, ang, [
					[-3.0, 3.0, 2.2, 2.2, Color("#8a7658"), Color("#5a4a38"), Color("#2e251b")],
					[-0.6, 0.6, 3.0, 3.0, Color("#a08a66"), Color("#6c5a44"), Color("#3a3128")],
				])
				var nn := Vector2(-sin(ang), cos(ang))
				Px.put(img, floori(q.x - cos(ang) * 2.0 - nn.x), floori(q.y - sin(ang) * 2.0 - nn.y), Color("#c8b088"))
				Px.put(img, floori(q.x + cos(ang) * 2.0 - nn.x), floori(q.y + sin(ang) * 2.0 - nn.y), Color("#c8b088"))
		"box":
			var r4: Rect2i = d["rect"]
			Px.rect(img, r4.grow(1), OUT)
			Px.rect(img, r4, ramp[3])
			Px.rect(img, Rect2i(r4.position.x, r4.position.y, r4.size.x, 2), ramp[5])
			Px.rect(img, Rect2i(r4.position.x, r4.position.y + 2, r4.size.x, 1), OUT)
			Px.rect(img, Rect2i(r4.position.x, r4.end.y - 1, r4.size.x, 1), ramp[1])
			for x in [r4.position.x + 2, r4.end.x - 3]:
				Px.rect(img, Rect2i(x, r4.position.y + 2, 1, 3), BRASS)
		"crate":
			var rc: Rect2i = d["rect"]
			Px.rect(img, rc.grow(1), OUT)
			for y in range(rc.position.y, rc.end.y):
				for x in range(rc.position.x, rc.end.x):
					var plank := (y - rc.position.y) % 5
					var col := Color("#3a1a10") if plank > 0 else Color("#1a0a06")
					if plank == 1:
						col = Color("#4e2416")
					if Px.h2(x, y, 61) > 0.85:
						col = Color("#2a120a")
					Px.put(img, x, y, col)
			for x in [rc.position.x, rc.end.x - 2]:
				Px.rect(img, Rect2i(x, rc.position.y, 2, rc.size.y), Color("#2a1c12"))
				Px.rect(img, Rect2i(x, rc.position.y, 1, rc.size.y), Color("#4a3a28"))
			Px.rect(img, Rect2i(rc.position.x, rc.position.y + rc.size.y / 2, rc.size.x, 1), Color("#2a1c12"))
		"commander":
			# head and shoulders out of the roof hatch, by the searchlight (crew on the tank)
			var pc: Vector2i = d["at"]
			Px.rect(img, Rect2i(pc.x - 3, pc.y - 4, 7, 4), Color("#2e2618"))
			Px.rect(img, Rect2i(pc.x - 2, pc.y - 4, 5, 1), Color("#4a3e28"))
			Px.rect(img, Rect2i(pc.x - 1, pc.y - 8, 3, 3), Color("#7a5a40"))
			Px.rect(img, Rect2i(pc.x - 2, pc.y - 9, 5, 1), Color("#2a2a22"))
			Px.rect(img, Rect2i(pc.x - 1, pc.y - 10, 3, 1), Color("#3a3a2e"))
			Px.put(img, pc.x + 1, pc.y - 7, Color("#1a120a"))
			Px.line(img, Vector2i(pc.x + 3, pc.y - 3), Vector2i(pc.x + 6, pc.y - 4), Color("#3a3226"))
		"bolt_row":
			var a8: Vector2i = d["a"]
			var b8: Vector2i = d["b"]
			var n8 := maxi(int(Vector2(a8).distance_to(Vector2(b8)) / 5.0), 1)
			for k in n8 + 1:
				var q := Vector2(a8).lerp(Vector2(b8), float(k) / n8)
				Px.put(img, floori(q.x), floori(q.y), RIV_HI)
				Px.put(img, floori(q.x) + 1, floori(q.y) + 1, RIV_LO)
