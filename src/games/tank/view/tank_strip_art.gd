class_name TankStripArt
extends RefCounted
## The plain stretches of a near strip, painted at load (brief 3 "Keep": rolling fields, hedgerows,
## poplar rows and pine woods, a village or a small foundry town). The generated strip has one
## landmark segment (TankPlaceholderArt.composed_strip); everything beside it, every column with
## nothing standing above the horizon, used to be flat streaks under a ruled horizon (the scene
## critic). Here those columns become:
## - ploughland: each row the darker-than-median tone of the plain columns, so the band is a soft
##   gradient by distance, cross-faded into the generated ground over 24 px with an ordered dither
##   (no seam), with two or three faint furrows per field converging toward the horizon;
## - a rolling horizon with a dark hedgerow mass along it;
## - trees in clumps of 3-7 with uneven gaps at two depths (the far row lighter and hazier):
##   Lombardy poplars 6-8 px wide shaded in three tones, or pines;
## - in every plain stretch, the location's own landmark again, so any fixed-time shot shows where
##   the tank is: farmsteads (one burning) on Poplar Road, cottages and a stone wall at Kettle Ford,
##   a rock face and a lit hut at Quarry Ridge, chimney stacks and a furnace shed by the foundry
##   town, a gantry crane and a floodlit shed at the depot. Their lit windows and fires are palette
##   light colours, so TankBackdrop.strip_lights gives them halos (and the fires flames and smoke).
## Deterministic (a fixed seed per strip), palette colours only, nothing within 44 px of the strip's
## edges (the mirror seams) but the hedgerow and the field.

const FILLER_STYLE := {
	"bg_fields_near": "fields",
	"bg_village_near": "village",
	"bg_quarry_near": "quarry",
	"bg_town_near": "town",
	"bg_depot_near": "depot",
}
## Props stay this far from the strip's edges (the mirrored seams).
const EDGE_PX := 44

const CLEAR := Color(0, 0, 0, 0)
const G0 := Color("#07080a")
const G1 := Color("#0f1012")
const G2 := Color("#17181b")
const G3 := Color("#202124")
const G4 := Color("#2a2b2e")
const G5 := Color("#353739")
const G6 := Color("#424446")
const B0 := Color("#17130f")
const B1 := Color("#241d17")
const B2 := Color("#33291f")
const O1 := Color("#3d3c33")
const R0 := Color("#3a2a24")
const R1 := Color("#5a3a2e")
const F0 := Color("#e8743a")
const F1 := Color("#ffb35c")
const F2 := Color("#ffd99a")
const C1 := Color("#5d86a3")
const C2 := Color("#9fc4dd")


## `src` (a composed near strip of `id`, its landmark segment `seg[0]` px wide in the middle) with its
## plain stretches painted (see the header). Other sizes come back unchanged.
static func filled(id: String, src: Image, seg: Array) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	if seg.size() < 3 or w != TankPlaceholderArt.size_of(id).x:
		return src
	var c := TankPlaceholderArt.Canvas.new(w, h)
	c.img = src.duplicate() as Image
	c.img.convert(Image.FORMAT_RGBA8)
	c.seed_value = absi(id.hash()) % 7919
	var top_of := PackedInt32Array()
	top_of.resize(w)
	var tops: Array[int] = []
	var lm0 := (w - int(seg[0])) / 2
	var lm1 := lm0 + int(seg[0])
	for x in w:
		top_of[x] = h
		for y in h:
			if c.solid(x, y):
				top_of[x] = y
				break
		if (x < lm0 or x >= lm1) and top_of[x] < h:
			tops.append(top_of[x])
	if tops.is_empty():
		return c.img
	tops.sort()
	var hz: int = tops[tops.size() / 2]
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(id.hash())
	var style := str(FILLER_STYLE.get(id, "fields"))
	var weight := _weights(top_of, hz, w)
	var rise := _rise(weight, rng, w)
	# The ground band is repainted everywhere outside the landmark's own core (the segment minus its
	# plain end bands), whatever stands on it, so no strip of the generated streaks is left between
	# two trees (the old "ladder" seam); it ramps in over 24 px at the core.
	var core0 := lm0 + int(seg[2])
	var core1 := lm1 - int(seg[1])
	var ground_w := PackedFloat32Array()
	ground_w.resize(w)
	for x in w:
		var d := float(maxi(core0 - x, x - core1 + 1))
		ground_w[x] = clampf(d / 24.0, 0.0, 1.0)
	_unstreak(c, hz)
	_ploughland(c, ground_w, hz)
	_furrows(c, ground_w, hz, rng)
	# The far trees first (behind the rolling field), then the field rises over their feet.
	for zone in _zones(weight, w):
		_far_clumps(c, rng, style, zone, hz, rise)
	for x in w:
		if rise[x] <= 0 or top_of[x] >= h:
			continue
		var col := c.img.get_pixel(x, mini(hz + 1, h - 1))
		for y in range(hz - rise[x], hz):
			c.px(x, y, col)
	_hedgerow(c, weight, hz, rise)
	var zi := 0
	for zone in _zones(weight, w):
		_location(c, rng, style, zone, hz, zi)
		zi += 1
	if style == "quarry":
		_spoil_heaps(c, rng, lm0, lm1, hz)
	return c.img


## 1 in the plain fields, ramping to 0 within 24 px of anything standing more than 6 px above the
## horizon (the landmark, a generated tree; low bushes do not count) and 0 within 10 px of the strip's edges.
static func _weights(top_of: PackedInt32Array, hz: int, w: int) -> PackedFloat32Array:
	var weight := PackedFloat32Array()
	weight.resize(w)
	for x in range(10, w - 10):
		var d := 24
		for dx in range(-24, 25):
			var xx := x + dx
			if xx >= 0 and xx < w and top_of[xx] < hz - 6:
				d = mini(d, absi(dx))
		weight[x] = float(d) / 24.0
	return weight


## The rolling rise of the horizon per column (0-7 px), tapering to nothing at the landmark.
static func _rise(
	weight: PackedFloat32Array, rng: RandomNumberGenerator, w: int
) -> PackedInt32Array:
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var rise := PackedInt32Array()
	rise.resize(w)
	for x in w:
		var r := (
			3.0 + 2.5 * sin(float(x) * TAU / 173.0 + p1) + 1.5 * sin(float(x) * TAU / 61.0 + p2)
		)
		rise[x] = int(round(maxf(r, 0.0) * weight[x]))
	return rise


## The plain stretches as [x0, x1) ranges where the weight is 1, inside the edge margins.
static func _zones(weight: PackedFloat32Array, w: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := -1
	for x in range(EDGE_PX, w - EDGE_PX + 1):
		var plain := x < w - EDGE_PX and weight[x] >= 0.6
		if plain and start < 0:
			start = x
		elif not plain and start >= 0:
			if x - start >= 24:
				out.append(Vector2i(start, x))
			start = -1
	return out


## The generated ground's thin horizontal streaks (1-2 px tall dashes that read as ruled lines) are
## removed over the whole band below the horizon: every pixel takes the median of the five rows
## around it in its column (vertical shapes, the crater, the reflections, survive; light colours are
## left alone).
static func _unstreak(c: TankPlaceholderArt.Canvas, hz: int) -> void:
	var src := c.img.duplicate() as Image
	var lights := TankPlaceholderArt.light_colours()
	for x in c.w:
		for y in range(hz + 3, c.h - 2):
			var here := src.get_pixel(x, y)
			if here.a < 0.5 or lights.has(here.to_rgba32()):
				continue
			var col: Array[Color] = []
			for dy in range(-2, 3):
				var p := src.get_pixel(x, y + dy)
				if p.a > 0.5:
					col.append(p)
			if col.size() < 5:
				continue
			col.sort_custom(_darker)
			c.px(x, y, col[2])


## The field band as a soft gradient: every row takes the darker-than-median tone of its seven-row
## neighbourhood over the plain columns, cross-faded into the generated ground by the weight with an
## ordered dither (no random speckle, no seam).
static func _ploughland(c: TankPlaceholderArt.Canvas, weight: PackedFloat32Array, hz: int) -> void:
	var w := c.w
	var h := c.h
	var row_col: Array[Color] = []
	for y in h:
		var cols: Array[Color] = []
		for x in range(0, w, 3):
			if weight[x] > 0.0 and c.solid(x, y):
				cols.append(c.img.get_pixel(x, y))
		cols.sort_custom(_darker)
		row_col.append(cols[cols.size() / 2] if not cols.is_empty() else CLEAR)
	var row_target: Array[Color] = []
	for y in h:
		var win: Array[Color] = []
		for dy in range(-3, 4):
			var rc: Color = row_col[clampi(y + dy, 0, h - 1)]
			if rc.a > 0.5:
				win.append(rc)
		win.sort_custom(_darker)
		row_target.append(win[maxi(win.size() / 2 - 1, 0)] if not win.is_empty() else CLEAR)
	for x in w:
		var k := weight[x]
		if k <= 0.0:
			continue
		for y in range(hz + 1, h):
			var col: Color = row_target[y]
			if col.a < 0.5 or not c.solid(x, y) or (k < 1.0 and c.bayer(x, y) > k):
				continue
			c.px(x, y, col)


## Two or three faint furrows per field (fields 90-150 px wide), converging toward a point on the
## horizon, drawn only over the lower two thirds of the band (they fade into the distance).
static func _furrows(
	c: TankPlaceholderArt.Canvas, weight: PackedFloat32Array, hz: int, rng: RandomNumberGenerator
) -> void:
	var w := c.w
	var h := c.h
	var x := EDGE_PX
	while x < w - EDGE_PX:
		var fw := rng.randi_range(90, 150)
		var vx := float(x) + float(fw) * 0.5
		var n := rng.randi_range(2, 3)
		for k in n:
			var bx := float(x) + float(fw) * (0.2 + 0.6 * float(k) / float(maxi(n - 1, 1)))
			var steps := h - hz
			for s in steps:
				var t := float(s) / float(steps)
				if t > 0.45:
					break
				# Broken, one tone darker than the soil it crosses: faint, never a ruled line.
				if (s / 3) % 3 == 2:
					continue
				var y := h - 1 - s
				var px := int(round(lerpf(bx, vx, t)))
				if px >= 0 and px < w and weight[px] >= 1.0 and c.solid(px, y):
					c.px(px, y, _one_darker(c.img.get_pixel(px, y)))
		x += fw


## The hedgerow mass along the risen horizon: a lumpy dark band 2-5 px high with a few lit crowns,
## broken now and then by a gap.
static func _hedgerow(
	c: TankPlaceholderArt.Canvas, weight: PackedFloat32Array, hz: int, rise: PackedInt32Array
) -> void:
	for x in range(10, c.w - 10):
		if weight[x] < 0.99:
			continue
		var gap := TankMaterial.smooth_noise(x, 0, 23.0, c.seed_value + 7)
		if gap < 0.2:
			continue
		var lump := TankMaterial.smooth_noise(x, 0, 5.0, c.seed_value + 3)
		var hh := 2 + int(lump * 3.5)
		var base := hz - rise[x]
		c.rect(x, base - hh, 1, hh + 1, G2)
		if lump > 0.7:
			c.px(x, base - hh, G3)


## Far trees in clumps along the horizon of `zone`: smaller, lighter and hazier.
static func _far_clumps(
	c: TankPlaceholderArt.Canvas,
	rng: RandomNumberGenerator,
	style: String,
	zone: Vector2i,
	hz: int,
	rise: PackedInt32Array
) -> void:
	var x := zone.x + rng.randi_range(0, 20)
	while x < zone.y - 6:
		var n := rng.randi_range(3, 6)
		for _k in n:
			if x >= zone.y - 4:
				break
			var b := hz - rise[x] - 1
			if style == "quarry" or style == "depot":
				_pine(c, x, b, rng.randi_range(10, 16), G3, G4)
			else:
				_poplar(c, x, b, rng.randi_range(12, 20), rng.randi_range(4, 5), G3, G3, G4)
			x += rng.randi_range(3, 5)
		x += rng.randi_range(30, 80)


## The near band of `zone`: the location's buildings once, and near tree clumps around them.
static func _location(
	c: TankPlaceholderArt.Canvas,
	rng: RandomNumberGenerator,
	style: String,
	zone: Vector2i,
	hz: int,
	index: int
) -> void:
	var zw := zone.y - zone.x
	var b := hz + 7
	var keep := Vector2i(-1, -1)
	if zw >= 70:
		var bx := zone.x + int(float(zw - 60) * rng.randf_range(0.2, 0.8))
		match style:
			"fields":
				_farmstead(c, bx, b, index % 2 == 0)
			"village":
				_cottages(c, rng, bx, b)
			"quarry":
				_rock_face(c, rng, bx, b)
			"town":
				_works(c, rng, bx, b)
			"depot":
				_gantry_yard(c, bx, b)
		keep = Vector2i(bx - 8, bx + 64)
	# Near clumps in the rest of the zone, on their own low hedge.
	var x := zone.x + rng.randi_range(2, 14)
	while x < zone.y - 6:
		if x >= keep.x and x < keep.y:
			x = keep.y + rng.randi_range(4, 12)
			continue
		var n := rng.randi_range(3, 7) if style != "town" else rng.randi_range(1, 3)
		var x_start := x
		for _k in n:
			if x >= zone.y - 4 or (x >= keep.x and x < keep.y):
				break
			var tb := b + rng.randi_range(-1, 2)
			if style == "quarry" or style == "depot":
				_pine(c, x, tb, rng.randi_range(18, 30), G1, G2)
				x += rng.randi_range(5, 8)
			else:
				_poplar(c, x, tb, rng.randi_range(26, 44), rng.randi_range(6, 8), G1, G2, O1)
				x += rng.randi_range(4, 6)
		for hx in range(x_start - 3, x + 2):
			var hh := 1 + int(TankMaterial.smooth_noise(hx, 1, 4.0, c.seed_value) * 3.0)
			c.rect(hx, b - hh, 1, hh + 1, G2)
		x += rng.randi_range(26, 90)


## A Lombardy poplar standing on `base`: a spindle `wd` px wide at a third of its height, pointed at
## the top, shaded in three tones (a dark left edge, the body, a lit right edge from the fires), on a
## stub of trunk.
static func _poplar(
	c: TankPlaceholderArt.Canvas,
	x: int,
	base: int,
	ht: int,
	wd: int,
	dark: Color,
	col: Color,
	lit: Color
) -> void:
	for r in ht:
		var t := float(r) / float(ht)
		var hw := (
			float(wd) * 0.5 * (0.6 + 0.4 * t / 0.3)
			if t < 0.3
			else float(wd) * 0.5 * pow(1.0 - (t - 0.3) / 0.7, 0.8)
		)
		var y := base - 2 - r
		var x0 := int(round(float(x) - hw))
		var x1 := int(round(float(x) + hw))
		if x1 < x0:
			x1 = x0
		c.rect(x0, y, x1 - x0 + 1, 1, col)
		if x1 - x0 >= 3:
			c.px(x0, y, dark)
			c.px(x1, y, lit)
	c.rect(x, base - 2, 1, 2, B0)


## A pine: three stacked tiers narrowing to a point, a lit pixel on the tiers' right edges.
static func _pine(
	c: TankPlaceholderArt.Canvas, x: int, base: int, ht: int, col: Color, lit: Color
) -> void:
	var half := maxf(3.0, float(ht) * 0.26)
	for r in ht:
		var t := float(r) / float(ht)
		var tier := fposmod(t * 3.0, 1.0)
		var hw := half * (1.0 - t * 0.75) * (0.55 + 0.45 * (1.0 - tier))
		var y := base - 1 - r
		c.rect(int(round(float(x) - hw)), y, int(round(hw * 2.0)) + 1, 1, col)
		c.px(int(round(float(x) + hw)), y, lit)
	c.rect(x, base - 1, 1, 1, B0)


## A gabled house `bw` x `wh` px (walls) with its ridge `rh` px above them, standing on `base` at x.
static func _house(
	c: TankPlaceholderArt.Canvas, x: int, base: int, bw: int, wh: int, rh: int, wall: Color
) -> void:
	c.rect(x, base - wh, bw, wh, wall)
	c.rect(x, base - wh, 1, wh, G1)
	for r in rh:
		var inset := int(float(r) * float(bw) * 0.5 / float(rh))
		c.rect(x - 1 + inset, base - wh - 1 - r, bw + 2 - inset * 2, 1, G2)
		c.px(x + bw - inset, base - wh - 1 - r, G4)
	c.rect(x - 1, base - wh - 1, bw + 2, 1, G1)


## Poplar Road's farmstead: a farmhouse with a chimney and lit windows and a barn beside it, the
## barn's roof burnt open with fire inside (or a lit door) when `burning`.
static func _farmstead(c: TankPlaceholderArt.Canvas, x: int, base: int, burning: bool) -> void:
	_house(c, x, base, 18, 10, 8, G3)
	c.rect(x + 13, base - 21, 2, 6, G2)
	c.rect(x + 4, base - 7, 2, 2, F1)
	c.rect(x + 11, base - 7, 2, 2, F2)
	c.rect(x + 8, base - 5, 2, 5, G1)
	var bx := x + 22
	_house(c, bx, base, 28, 12, 6, B1)
	c.rect(bx + 10, base - 8, 7, 8, G1)
	if burning:
		# The roof burnt through: a ragged gap with fire inside and flames licking out of it.
		for k in 9:
			var gx := bx + 7 + k
			var depth := 3 + int(absf(sin(float(k) * 1.7)) * 3.0)
			c.rect(gx, base - 19, 1, depth, CLEAR)
		c.rect(bx + 8, base - 14, 8, 3, F0)
		c.rect(bx + 10, base - 15, 4, 2, F1)
		c.rect(bx + 9, base - 17, 2, 2, F0)
		c.rect(bx + 13, base - 18, 1, 3, F0)
		c.rect(bx + 11, base - 12, 3, 1, F2)
	else:
		c.rect(bx + 21, base - 8, 2, 2, F1)


## Kettle Ford's outskirts: two or three cottages of different sizes, their windows lit, and a low
## stone wall along the road.
static func _cottages(
	c: TankPlaceholderArt.Canvas, rng: RandomNumberGenerator, x: int, base: int
) -> void:
	c.rect(x - 6, base - 3, 66, 3, G3)
	c.rect(x - 6, base - 3, 66, 1, G4)
	var cx := x
	for k in rng.randi_range(2, 3):
		var bw := rng.randi_range(12, 17)
		var wh := rng.randi_range(8, 11)
		_house(c, cx, base - 1, bw, wh, rng.randi_range(6, 9), G3 if k % 2 == 0 else B1)
		c.rect(cx + bw / 2 - 1, base - wh + 2, 2, 2, F1 if k != 1 else F2)
		c.rect(cx + bw - 4, base - wh - 6, 2, 4, G2)
		cx += bw + rng.randi_range(4, 9)


## Quarry Ridge again: a pale rock face with stepped ledges rising out of the field, a spoil slope at
## its foot and a hut with a lit window.
static func _rock_face(
	c: TankPlaceholderArt.Canvas, rng: RandomNumberGenerator, x: int, base: int
) -> void:
	var fw := 54
	var ht := rng.randi_range(24, 30)
	for i in fw:
		var t := float(i) / float(fw)
		var top := ht * (smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.78, 1.0, t)))
		top += 1.5 * sin(float(i) * 0.31) + (2.0 if (i / 9) % 2 == 0 and t > 0.3 else 0.0)
		var y0 := base - int(top)
		c.rect(x + i, y0, 1, base - y0, G4 if t < 0.45 else G3)
		c.px(x + i, y0, G5)
		var ly := y0 + 5
		while ly < base - 2:
			c.px(x + i, ly, G3)
			ly += 6 + (i / 13) % 2
	for i in 24:
		c.rect(x - 10 + i, base - int(float(i) * 0.25), 1, int(float(i) * 0.25) + 1, G3)
	var hx := x + fw + 4
	_house(c, hx, base, 12, 7, 4, B1)
	c.rect(hx + 3, base - 5, 2, 2, F1)


## The foundry town's edge: two chimney stacks of dark brick and a sawtooth-roofed shed with a row of
## lit windows and a furnace door glowing.
static func _works(
	c: TankPlaceholderArt.Canvas, rng: RandomNumberGenerator, x: int, base: int
) -> void:
	for k in 2:
		var sx := x + 6 + k * 34
		var sh := rng.randi_range(32, 44)
		c.rect(sx, base - sh, 4, sh, R0)
		c.rect(sx + 3, base - sh, 1, sh, R1)
		c.rect(sx - 1, base - sh, 6, 2, G2)
	var shed := x
	c.rect(shed, base - 10, 52, 10, G2)
	for t in 6:
		for r in 5:
			c.rect(shed + t * 9 + r, base - 11 - r, 9 - r, 1, G3)
		c.px(shed + t * 9, base - 15, G4)
	var wx := shed + 3
	while wx < shed + 46:
		c.rect(wx, base - 7, 1, 2, F1)
		wx += 5
	c.rect(shed + 30, base - 5, 5, 5, F0)
	c.rect(shed + 31, base - 4, 3, 3, F1)


## The depot's yard: a gantry crane with a hoist block, a shed under a cold floodlight on a pole and
## a run of fence posts.
static func _gantry_yard(c: TankPlaceholderArt.Canvas, x: int, base: int) -> void:
	for lx: int in [x, x + 32]:
		c.rect(lx, base - 30, 2, 30, G3)
		c.px(lx + 1, base - 30, G4)
	c.rect(x - 3, base - 33, 39, 3, G3)
	c.rect(x - 3, base - 33, 39, 1, G5)
	for k in 6:
		c.line(x + 2 + k * 5, base - 30, x + 7 + k * 5, base - 33, G2)
	c.rect(x + 17, base - 30, 1, 10, G2)
	c.rect(x + 15, base - 20, 5, 4, G4)
	var sx := x + 40
	c.rect(sx, base - 9, 22, 9, G2)
	for r in 4:
		c.rect(sx - 1 + r, base - 10 - r, 24 - r * 2, 1, G3)
	c.rect(sx + 26, base - 18, 1, 18, G3)
	c.rect(sx + 24, base - 19, 4, 1, G4)
	c.px(sx + 25, base - 18, C2)
	c.px(sx + 26, base - 18, C1)
	for k in 5:
		c.rect(x - 10 + k * 5, base - 5, 1, 5, G2)


## Spoil heaps either side of the quarry's landmark segment.
static func _spoil_heaps(
	c: TankPlaceholderArt.Canvas, rng: RandomNumberGenerator, lm0: int, lm1: int, hz: int
) -> void:
	for side in 2:
		var cx := (
			lm0 - 26 - rng.randi_range(0, 30) if side == 0 else lm1 + 26 + rng.randi_range(0, 30)
		)
		if cx < 40 or cx > c.w - 40:
			continue
		var rx := 18.0 + rng.randf() * 14.0
		var ry := 7.0 + rng.randf() * 6.0
		for y in range(int(hz - ry), hz + 1):
			for x in range(int(cx - rx), int(cx + rx) + 1):
				var dx := (float(x) - float(cx)) / rx
				var dy := (float(y) - float(hz)) / ry
				if dx * dx + dy * dy <= 1.0:
					c.px(x, y, G2 if dy > -0.75 else B1)


## The palette tone one step darker than `col` on its own ramp (greys or browns).
static func _one_darker(col: Color) -> Color:
	var greys: Array[Color] = [G0, G1, G2, G3, G4, G5, G6]
	var browns: Array[Color] = [G0, B0, B1, B2]
	for ramp: Array[Color] in [greys, browns]:
		var i := ramp.find(Color(col.r, col.g, col.b, 1.0))
		if i > 0:
			return ramp[i - 1]
	return col


static func _darker(a: Color, b: Color) -> bool:
	return a.get_luminance() < b.get_luminance()
