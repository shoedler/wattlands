extends RefCounted
## The base's finishing pass (v3 art fix round, 2026-10-28), run by bake.gd on tank_base.png and its
## lit twin alike, only on the hull's exterior (never in the rooms, the windows, the cuts, the
## dressing on the roof, the lamps or the running gear's masks):
##   1. the silhouette fringe: the outline's top, rear and front profiles each median-filtered over
##      five columns (rows), twice, moving the edge by at most PROFILE_MAX px, so one- and two-pixel bumps
##      and notches go and the plates' corners stay; then the spur pixels left sticking off it go and
##      one-pixel notches fill; thin posts and rails (runs of three or more one-pixel-wide pixels),
##      the dressing and the lamps stay
##   2. lone pixels floating off the hull go (anywhere); stray isolated pixels: a pixel lighter or darker than all eight neighbours by more than
##      SPECK takes its neighbours' median
##   3. moonlight: a cool 1 px rim under the hull's top outline and on the top edge of every long
##      plate seam (a dark row over a lighter one, at least SEAM_RUN px long), and a few lit rivet
##      dots along the longest seams
## Every new colour snaps to the base's own palette (the nearest of its colours at least a little
## lighter than the pixel it replaces), so the base keeps its r6 palette. The exterior's mean value
## rises by a few percent at most (bake.gd prints it); the rooms do not change.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const MOON := Color("#8a9cb0")
const RIM_K := 0.45
const SEAM_K := 0.32
const RIVET := Color("#b49c76")
const SPECK := 0.07
const PROFILE_MAX := 2
const SNAP_LIFT := 0.025
const SEAM_DARK := 0.09
const SEAM_STEP := 0.04
const SEAM_RUN := 10
const RIVET_RUN := 24
const RIVET_EVERY := 15
## Above this row the outline is the hull's own (below it the sprocket's and the skirt's masks cut
## it straight).
const FRINGE_MAX_Y := 172
## The roof's dressing: the commander in the cupola, the turret searchlight, the rear searchlight on
## its post.
const DRESSING: Array[Rect2i] = [
	Rect2i(254, 54, 22, 20),
	Rect2i(292, 54, 26, 26),
	Rect2i(94, 82, 24, 32),
]


## The finished copy of `img` and its stats: {img, before (exterior mean value), after, changed}.
static func apply(img: Image, L: Dictionary) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var keep := _protected(img, L)
	var skirt := int(L["gear"]["skirt_y"])
	var ext := func(x: int, y: int) -> bool: return (
		x >= 0 and y >= 0 and x < w and y < skirt and not keep[y * w + x]
	)
	var before := _mean(img, ext)
	var out := img.duplicate() as Image
	for _round in 2:
		out = _profile(out, ext, Vector2i(0, 1), Vector2i(1, 0), w, FRINGE_MAX_Y)
		out = _profile(out, ext, Vector2i(1, 0), Vector2i(0, 1), FRINGE_MAX_Y, w)
		out = _profile(out, ext, Vector2i(-1, 0), Vector2i(0, 1), FRINGE_MAX_Y, w)
		out = _fringe(out, ext)
	out = _speckle(out, ext)
	out = _moon(out, ext, skirt)
	out = _snap(out, img)
	out = _lone(out)
	var changed := 0
	for y in h:
		for x in w:
			if not out.get_pixel(x, y).is_equal_approx(img.get_pixel(x, y)):
				changed += 1
	return {"img": out, "before": before, "after": _mean(out, ext), "changed": changed}


static func lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.55 + c.b * 0.15


static func _opaque(img: Image, x: int, y: int) -> bool:
	return Px.inside(img, x, y) and img.get_pixel(x, y).a > 0.5


## The pixels the pass leaves alone: the rooms, the windows and the cuts (grown by a pixel), the
## roof's dressing, 4 px round every detail and lamp, and thin posts and rails.
static func _protected(img: Image, L: Dictionary) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var keep := PackedByteArray()
	keep.resize(w * h)
	var rects: Array[Rect2i] = []
	for k: String in L["rooms"]:
		rects.append((L["rooms"][k] as Rect2i).grow(1))
	for k2: String in ["shaft", "rackwin", "breechwin", "boxwin", "boxwin2"]:
		rects.append((L[k2] as Rect2i).grow(1))
	for c: Dictionary in L["cuts"]:
		rects.append((c["rect"] as Rect2i).grow(1))
	for r in DRESSING:
		rects.append(r)
	rects.append(L["crate"] as Rect2i)
	for pq: Rect2i in L["plaques"]:
		rects.append(pq)
	for d: Dictionary in L["details"]:
		var at := Vector2i(d["at"])
		rects.append(Rect2i(at - Vector2i(4, 4), Vector2i(9, 9)))
	for r2 in rects:
		for y in range(maxi(r2.position.y, 0), mini(r2.end.y, h)):
			for x in range(maxi(r2.position.x, 0), mini(r2.end.x, w)):
				keep[y * w + x] = 1
	# thin posts (one pixel wide, three or more tall) and rails (one pixel tall, three or more wide)
	for y in h:
		for x in w:
			if not _opaque(img, x, y):
				continue
			var thin_v := not _opaque(img, x - 1, y) and not _opaque(img, x + 1, y)
			var thin_h := not _opaque(img, x, y - 1) and not _opaque(img, x, y + 1)
			if thin_v and _run(img, x, y, Vector2i(0, 1)) >= 3:
				keep[y * w + x] = 1
			if thin_h and _run(img, x, y, Vector2i(1, 0)) >= 3:
				keep[y * w + x] = 1
	return keep


## How many one-pixel-wide pixels run through (x, y) along `d` (thin across `d`).
static func _run(img: Image, x: int, y: int, d: Vector2i) -> int:
	var n := 1
	var a := Vector2i(d.y, d.x)
	for s: int in [-1, 1]:
		var p := Vector2i(x, y) + d * s
		while (
			_opaque(img, p.x, p.y)
			and not _opaque(img, p.x - a.x, p.y - a.y)
			and not _opaque(img, p.x + a.x, p.y + a.y)
		):
			n += 1
			p += d * s
	return n


## One silhouette profile median-filtered: scanning along `inward` from the edge on each of `lines`
## lines (stepping `across`), the first exterior pixel is the edge; a line whose first opaque pixel
## is protected (a post, a lamp) keeps its edge and leaves the median. Where the median of the five
## edges round a line differs by 1..PROFILE_MAX px, the edge moves there: bump pixels clear, a notch
## fills; the edge pixel keeps the outline's colour and the plate under it its own.
static func _profile(
	img: Image, ext: Callable, inward: Vector2i, across: Vector2i, lines: int, depth: int
) -> Image:
	var out := img.duplicate() as Image
	var start := Vector2i.ZERO
	if inward.x < 0:
		start = Vector2i(img.get_width() - 1, 0)
	var edge := PackedInt32Array()
	edge.resize(lines)
	for i in lines:
		edge[i] = -1
		var p := start + across * i
		for k in depth:
			var q := p + inward * k
			if not Px.inside(img, q.x, q.y):
				break
			if _opaque(img, q.x, q.y):
				edge[i] = k if ext.call(q.x, q.y) else -1
				break
	for i in lines:
		if edge[i] < 0:
			continue
		var win: Array[int] = []
		for j in range(i - 2, i + 3):
			if j >= 0 and j < lines and edge[j] >= 0:
				win.append(edge[j])
		if win.size() < 4:
			continue
		win.sort()
		var med := win[win.size() / 2]
		var dk := med - edge[i]
		if dk == 0 or absi(dk) > PROFILE_MAX:
			continue
		var p0 := start + across * i
		var e := p0 + inward * edge[i]
		var outline := img.get_pixel(e.x, e.y)
		var plate := img.get_pixel(e.x + inward.x, e.y + inward.y)
		if dk > 0:
			var ok := true
			for k in dk + 1:
				var q := e + inward * k
				ok = ok and ext.call(q.x, q.y)
			if not ok:
				continue
			for k in dk:
				var q2 := e + inward * k
				out.set_pixel(q2.x, q2.y, Color(0, 0, 0, 0))
			var ne := e + inward * dk
			out.set_pixel(ne.x, ne.y, outline)
		else:
			for k in range(1, -dk + 1):
				var q3 := e - inward * k
				if not ext.call(q3.x, q3.y) or _opaque(img, q3.x, q3.y):
					continue
				out.set_pixel(q3.x, q3.y, outline if k == -dk else plate)
			if plate.a > 0.5:
				out.set_pixel(e.x, e.y, plate)
	return out


## One fringe pass: an exterior pixel on the outline with at most one opaque 4-neighbour goes; a
## clear pixel with three or four opaque 4-neighbours fills with the darkest of them.
static func _fringe(img: Image, ext: Callable) -> Image:
	var out := img.duplicate() as Image
	var n4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in mini(img.get_height(), FRINGE_MAX_Y):
		for x in img.get_width():
			if not ext.call(x, y):
				continue
			var cnt := 0
			var dark := Color(1, 1, 1)
			for o in n4:
				if _opaque(img, x + o.x, y + o.y):
					cnt += 1
					var c := img.get_pixel(x + o.x, y + o.y)
					if lum(c) < lum(dark):
						dark = c
			if _opaque(img, x, y):
				if cnt <= 1:
					out.set_pixel(x, y, Color(0, 0, 0, 0))
			elif cnt >= 3:
				out.set_pixel(x, y, dark)
	return out


## Stray isolated pixels: one lighter or darker than all eight neighbours by SPECK takes the colour
## of the neighbour with the median value.
static func _speckle(img: Image, ext: Callable) -> Image:
	var out := img.duplicate() as Image
	for y in range(1, img.get_height() - 1):
		for x in range(1, img.get_width() - 1):
			if not ext.call(x, y) or not _opaque(img, x, y):
				continue
			var l := lum(img.get_pixel(x, y))
			var ns: Array[Color] = []
			var hi := true
			var lo := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					if not _opaque(img, x + dx, y + dy):
						hi = false
						lo = false
						continue
					var c := img.get_pixel(x + dx, y + dy)
					ns.append(c)
					var ln := lum(c)
					hi = hi and l - ln > SPECK
					lo = lo and ln - l > SPECK
			if (hi or lo) and ns.size() == 8:
				ns.sort_custom(func(a: Color, b: Color) -> bool: return lum(a) < lum(b))
				out.set_pixel(x, y, ns[4])
	return out


## The moonlight: the rim under the top outline, the seams' top edges, a few rivets.
static func _moon(img: Image, ext: Callable, skirt: int) -> Image:
	var out := img.duplicate() as Image
	var w := img.get_width()
	# the rim: the first pixel under the outline (the outline itself stays dark)
	for x in w:
		for y in range(1, skirt - 1):
			if _opaque(img, x, y) and not _opaque(img, x, y - 1):
				var ry := y + 1 if lum(img.get_pixel(x, y)) < 0.06 else y
				if ext.call(x, ry) and _opaque(img, x, ry):
					out.set_pixel(x, ry, img.get_pixel(x, ry).lerp(MOON, RIM_K))
	# the seams: a dark row over a lighter one, SEAM_RUN px or longer
	for y in range(1, skirt - 2):
		var x := 0
		while x < w:
			var x0 := x
			while x < w and _seam(img, ext, x, y):
				x += 1
			var run := x - x0
			if run >= SEAM_RUN:
				for xx in range(x0, x):
					out.set_pixel(xx, y + 1, img.get_pixel(xx, y + 1).lerp(MOON, SEAM_K))
				if run >= RIVET_RUN:
					var rx := x0 + 5
					while rx < x - 4:
						if ext.call(rx, y + 3) and _opaque(img, rx, y + 4):
							var under := img.get_pixel(rx, y + 3)
							out.set_pixel(rx, y + 3, under.lerp(RIVET, 0.6))
							out.set_pixel(rx, y + 4, img.get_pixel(rx, y + 4).darkened(0.35))
						rx += RIVET_EVERY
			x = maxi(x, x0 + 1)
	return out


## Lone pixels floating off the hull (no opaque pixel among their eight neighbours) go, anywhere on
## the sprite, the dressing included.
static func _lone(img: Image) -> Image:
	var out := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if not _opaque(img, x, y):
				continue
			var nb := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if (dx != 0 or dy != 0) and _opaque(img, x + dx, y + dy):
						nb = true
			if not nb:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out


## Snaps every pixel of `img` whose colour is not in `ref`'s palette to the nearest palette colour
## at least SNAP_LIFT lighter than `ref`'s pixel there (else the nearest at all).
static func _snap(img: Image, ref: Image) -> Image:
	var pal := {}
	for y in ref.get_height():
		for x in ref.get_width():
			var c := ref.get_pixel(x, y)
			if c.a > 0.5:
				pal[c.to_html(false)] = c
	var cols: Array = pal.values()
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or pal.has(c.to_html(false)):
				continue
			var floor_l := lum(ref.get_pixel(x, y)) + SNAP_LIFT
			var best := c
			var best_d := INF
			var any := c
			var any_d := INF
			for q: Color in cols:
				var d := Vector3(q.r - c.r, q.g - c.g, q.b - c.b).length_squared()
				if d < any_d:
					any_d = d
					any = q
				if lum(q) >= floor_l and d < best_d:
					best_d = d
					best = q
			img.set_pixel(x, y, best if best_d < INF else any)
	return img


static func _seam(img: Image, ext: Callable, x: int, y: int) -> bool:
	if not ext.call(x, y) or not ext.call(x, y + 1):
		return false
	if not _opaque(img, x, y) or not _opaque(img, x, y + 1) or not _opaque(img, x, y - 1):
		return false
	var a := lum(img.get_pixel(x, y))
	var b := lum(img.get_pixel(x, y + 1))
	return a < SEAM_DARK and b - a > SEAM_STEP


static func _mean(img: Image, ext: Callable) -> float:
	var s := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if ext.call(x, y) and _opaque(img, x, y):
				s += lum(img.get_pixel(x, y))
				n += 1
	return s / maxf(float(n), 1.0)
