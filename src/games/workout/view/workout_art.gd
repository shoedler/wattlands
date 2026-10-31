class_name WorkoutArt
extends RefCounted
## Workout's procedural pixel art (BRIEF 3.7 ride view, 960 x 540 art pixels): sky,
## clouds, three seamless hill and tree strips for the parallax, the pennant marker
## geometry (slot color + shape + pattern, BRIEF 3.9) and zone colors for the interval blocks.
## Everything is drawn from fixed seeds, so it is identical on every run and every machine.
## The picker card comes from src/games/workout/art/bake.mjs.
##
## Pennant geometry is a list of filled polygons in paint order ({points, color}), so the
## view draws it with draw_colored_polygon.

const W := 960
const H := 540

const SKY_TOP := Color("#5b8fc7")
const SKY_HORIZON := Color("#f2d9a8")
const CLOUD := Color("#fbfbf7")
const CLOUD_SHADE := Color("#dfe6ee")
const FAR_HILLS := Color("#7f9db6")
const FAR_TOP := Color("#97b3c9")
const MID_HILLS := Color("#5f8f6a")
const MID_TOP := Color("#77a77f")
const NEAR_TREES := Color("#3f6b4a")
const NEAR_TOP := Color("#55835c")
const TRUNK := Color("#4a3a2a")
const GRASS := Color("#6f9440")
const GRASS_DARK := Color("#5c7d35")
const DIRT := Color("#7a6646")
const DIRT_DARK := Color("#665438")
const ASPHALT := Color("#55515c")
const ROAD_EDGE := Color("#8f8a95")
const ROAD_DASH := Color("#ebe4c6")
const POLE := Color("#2b2b30")
const OUTLINE := Color("#1e1e24")
const HOLLOW_FILL := Color("#f4f2ea")
const GLOW := Color("#fff3a8")
const GREY := Color("#8a8a8a")
const WHITE := Color("#ffffff")
const GOLD := Color("#e8b923")

## Interval block colors by planned % FTP.
const ZONE_RECOVERY := Color("#8fa3b8")
const ZONE_ENDURANCE := Color("#4fa36a")
const ZONE_TEMPO := Color("#e3c04a")
const ZONE_THRESHOLD := Color("#e88a3a")
const ZONE_VO2 := Color("#d4553f")
const ZONE_SPRINT := Color("#b45fc4")
## A FREE phase longer than a sprint (an imported FreeRide): free riding, no target.
const ZONE_FREE := Color("#a3b0a0")
const ZONE_COURSE := Color("#4f8fc4")
const ZONE_COOLDOWN := Color("#6f8296")

## Layer image sizes (seamless horizontally) and their seeds.
const FAR_SIZE := Vector2i(480, 110)
const MID_SIZE := Vector2i(400, 90)
const NEAR_SIZE := Vector2i(320, 60)
const CLOUD_SIZE := Vector2i(320, 70)
const SEED_FAR := 11
const SEED_MID := 23
const SEED_NEAR := 37
const SEED_CLOUDS := 41


static func zone_color(pct: float) -> Color:
	if pct < 56.0:
		return ZONE_RECOVERY
	if pct < 76.0:
		return ZONE_ENDURANCE
	if pct < 91.0:
		return ZONE_TEMPO
	if pct <= 105.0:
		return ZONE_THRESHOLD
	return ZONE_VO2


## Block color for a phase of the timeline.
static func phase_color(p: PlanPhase) -> Color:
	if p.kind == Wl.COOLDOWN:
		return ZONE_COOLDOWN
	if p.kind == Wl.FREE:
		return ZONE_SPRINT if WorkoutSession.is_sprint(p) else ZONE_FREE
	if p.mode == Wl.SIM:
		return ZONE_COURSE
	return zone_color(maxf(p.target_pct, p.ramp_to_pct if p.has_ramp() else 0.0))


# --- layer images --------------------------------------------------------------------


static func sky_image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var horizon := 345
	for y in H:
		var f := clampf(float(y) / float(horizon), 0.0, 1.0)
		# Quantize to 12 bands for a pixel-art gradient.
		f = floor(f * 12.0) / 12.0
		img.fill_rect(Rect2i(0, y, W, 1), SKY_TOP.lerp(SKY_HORIZON, f))
	return img


static func clouds_image() -> Image:
	var img := Image.create(CLOUD_SIZE.x, CLOUD_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := SeededRng.make(SEED_CLOUDS)
	for c in 4:
		var cx := SeededRng.range_f(rng, 0.0, float(CLOUD_SIZE.x))
		var cy := SeededRng.range_f(rng, 14.0, float(CLOUD_SIZE.y) - 22.0)
		var puffs := SeededRng.range_i(rng, 3, 5)
		for k in puffs:
			var px := cx + float(k) * SeededRng.range_f(rng, 7.0, 11.0)
			var py := cy + SeededRng.range_f(rng, -4.0, 3.0)
			var rx := SeededRng.range_f(rng, 7.0, 12.0)
			var ry := rx * 0.6
			_ellipse_wrapped(img, Vector2(px, py + 2.0), rx, ry, CLOUD_SHADE)
			_ellipse_wrapped(img, Vector2(px, py), rx, ry, CLOUD)
	return img


## A seamless hill strip: integer wave counts across the width make both edges match.
static func hills_image(
	size: Vector2i, seed_value: int, body: Color, top: Color, min_h: float, max_h: float
) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := SeededRng.make(seed_value)
	var waves: Array = []
	for k in 3:
		waves.append(
			[
				SeededRng.range_i(rng, 1 + k * 2, 2 + k * 3),
				SeededRng.range_f(rng, 0.0, TAU),
				1.0 / float(k + 1)
			]
		)
	var heights := PackedFloat64Array()
	heights.resize(size.x)
	var lo := INF
	var hi := -INF
	for x in size.x:
		var v := 0.0
		for w: Array in waves:
			v += float(w[2]) * sin(TAU * float(int(w[0])) * float(x) / float(size.x) + float(w[1]))
		heights[x] = v
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for x in size.x:
		var f := (heights[x] - lo) / maxf(hi - lo, 1e-9)
		var hgt := int(round(lerpf(min_h, max_h, f)))
		var y0 := size.y - hgt
		img.fill_rect(Rect2i(x, y0, 1, hgt), body)
		img.fill_rect(Rect2i(x, y0, 1, 2), top)
	return img


## The near layer: a low bank with conifers and round trees, seamless.
static func trees_image() -> Image:
	var img := Image.create(NEAR_SIZE.x, NEAR_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bank := 12
	img.fill_rect(Rect2i(0, NEAR_SIZE.y - bank, NEAR_SIZE.x, bank), NEAR_TREES)
	img.fill_rect(Rect2i(0, NEAR_SIZE.y - bank, NEAR_SIZE.x, 1), NEAR_TOP)
	var rng := SeededRng.make(SEED_NEAR)
	var x := 4.0
	while x < float(NEAR_SIZE.x):
		var conifer := SeededRng.chance(rng, 0.55)
		var hgt := SeededRng.range_f(rng, 18.0, 40.0)
		var base_y := float(NEAR_SIZE.y - bank)
		if conifer:
			var half := hgt * 0.32
			var pts := PackedVector2Array(
				[Vector2(x, base_y - hgt), Vector2(x + half, base_y), Vector2(x - half, base_y)]
			)
			_fill_polygon_wrapped(img, pts, NEAR_TREES)
			_fill_polygon_wrapped(
				img,
				PackedVector2Array(
					[
						Vector2(x, base_y - hgt),
						Vector2(x + 2.0, base_y - hgt + 5.0),
						Vector2(x - 1.0, base_y - hgt + 5.0)
					]
				),
				NEAR_TOP
			)
		else:
			var r := hgt * 0.3
			_fill_rect_wrapped(
				img, Rect2i(int(x), int(base_y - hgt * 0.45), 2, int(hgt * 0.45)), TRUNK
			)
			_ellipse_wrapped(img, Vector2(x + 1.0, base_y - hgt * 0.55), r, r * 0.9, NEAR_TREES)
			_ellipse_wrapped(img, Vector2(x, base_y - hgt * 0.62), r * 0.5, r * 0.4, NEAR_TOP)
		x += SeededRng.range_f(rng, 14.0, 34.0)
	return img


static func far_hills_image() -> Image:
	return hills_image(FAR_SIZE, SEED_FAR, FAR_HILLS, FAR_TOP, 40.0, 100.0)


static func mid_hills_image() -> Image:
	return hills_image(MID_SIZE, SEED_MID, MID_HILLS, MID_TOP, 24.0, 80.0)


# --- pennants ----------------------------------------------------------------------


## Pole height (art px) for a slot, staggered so pennants at one spot stay readable.
static func pole_height(slot_index: int) -> float:
	return 16.0 + 5.0 * float(posmod(slot_index, 4)) + (2.0 if posmod(slot_index, 8) >= 4 else 0.0)


## The pennant marker as filled polygons in paint order, relative to the pole foot (y up
## is negative). `look`: Wl.slot_look() keys (color, shape, pattern, hollow). `opts`:
## {style: "" or a WorkoutProgress pennant id, bot, local, in_band, rescue, afk}.
static func pennant_shapes(
	look: Dictionary, slot_index: int, opts: Dictionary = {}
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var h := pole_height(slot_index)
	var color: Color = look.get("color", WHITE)
	if bool(opts.get("afk", false)):
		color = GREY
	elif bool(opts.get("rescue", false)):
		color = color.lerp(GREY, 0.55)
	var top := -h
	var flag: PackedVector2Array
	var style := str(opts.get("style", ""))
	if bool(opts.get("rescue", false)) or bool(opts.get("afk", false)):
		# Drooping flag hanging along the pole.
		flag = PackedVector2Array([Vector2(1, top), Vector2(5, top), Vector2(2, top + 12)])
	elif bool(opts.get("bot", false)):
		flag = PackedVector2Array(
			[Vector2(1, top), Vector2(11, top), Vector2(11, top + 7), Vector2(1, top + 7)]
		)
	elif style == "pennant_swallowtail":
		flag = PackedVector2Array(
			[
				Vector2(1, top),
				Vector2(14, top),
				Vector2(10, top + 4),
				Vector2(14, top + 8),
				Vector2(1, top + 8)
			]
		)
	else:
		flag = PackedVector2Array([Vector2(1, top), Vector2(14, top + 4), Vector2(1, top + 8)])
	if (
		bool(opts.get("in_band", false))
		and not bool(opts.get("rescue", false))
		and not bool(opts.get("afk", false))
	):
		out.append({"points": _grow(flag, 1.5), "color": GLOW})
	out.append(
		{
			"points":
			PackedVector2Array(
				[Vector2(0, top - 1), Vector2(1, top - 1), Vector2(1, 0), Vector2(0, 0)]
			),
			"color": POLE
		}
	)
	out.append({"points": _grow(flag, 0.8), "color": GOLD if style == "pennant_gold" else OUTLINE})
	out.append({"points": flag, "color": color})
	var dark := color.darkened(0.45)
	match str(look.get("pattern", "solid")):
		"dashed":
			out.append({"points": _rect(4, top + 2, 1, 4), "color": dark})
			out.append({"points": _rect(8, top + 3, 1, 2), "color": dark})
		"dotted":
			out.append({"points": _rect(3, top + 3, 2, 2), "color": dark})
			out.append({"points": _rect(7, top + 3, 2, 2), "color": dark})
		"double":
			var second := PackedVector2Array(
				[Vector2(1, top + 10), Vector2(10, top + 13), Vector2(1, top + 16)]
			)
			out.append({"points": _grow(second, 0.8), "color": OUTLINE})
			out.append({"points": second, "color": color})
	if style == "pennant_chevron":
		out.append(
			{
				"points":
				PackedVector2Array(
					[
						Vector2(3, top + 2),
						Vector2(6, top + 4),
						Vector2(3, top + 6),
						Vector2(4, top + 4)
					]
				),
				"color": WHITE
			}
		)
	elif style == "pennant_star":
		out.append({"points": _star(Vector2(5, top + 4), 2.6, 1.1), "color": WHITE})
	elif style == "pennant_bolt":
		out.append(
			{
				"points":
				PackedVector2Array(
					[
						Vector2(6, top + 1),
						Vector2(4, top + 4),
						Vector2(6, top + 4),
						Vector2(4, top + 7),
						Vector2(8, top + 3),
						Vector2(6, top + 3)
					]
				),
				"color": GOLD
			}
		)
	# Shape badge at the pole top.
	var c := Vector2(0.5, top - 4.0)
	var badge := shape_points(str(look.get("shape", "circle")), c, 3.0)
	out.append(
		{
			"points": shape_points(str(look.get("shape", "circle")), c, 4.2),
			"color": OUTLINE if not bool(look.get("hollow", false)) else color
		}
	)
	out.append(
		{"points": badge, "color": HOLLOW_FILL if bool(look.get("hollow", false)) else color}
	)
	if bool(opts.get("local", false)):
		out.append(
			{
				"points":
				PackedVector2Array(
					[Vector2(-2.5, top - 12), Vector2(3.5, top - 12), Vector2(0.5, top - 9)]
				),
				"color": WHITE
			}
		)
	return out


## A filled shape for the badge: circle, triangle, square or diamond.
static func shape_points(shape: String, c: Vector2, r: float) -> PackedVector2Array:
	match shape:
		"triangle":
			return PackedVector2Array(
				[c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)]
			)
		"square":
			var s := r * 0.85
			return PackedVector2Array(
				[c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(s, s), c + Vector2(-s, s)]
			)
		"diamond":
			return PackedVector2Array(
				[c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]
			)
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


# --- rasterizing helpers (Image) -----------------------------------------------------


## Fills a polygon (pixel centres inside, even-odd) into `img`, shifted by `offset`.
static func fill_polygon(
	img: Image, pts: PackedVector2Array, color: Color, offset: Vector2 = Vector2.ZERO
) -> void:
	if pts.size() < 3:
		return
	var moved := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var q := p + offset
		moved.append(q)
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)) + 1, img.get_height())):
		for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)) + 1, img.get_width())):
			if Geometry2D.is_point_in_polygon(Vector2(float(x) + 0.5, float(y) + 0.5), moved):
				_blend(img, x, y, color)


static func _fill_polygon_wrapped(img: Image, pts: PackedVector2Array, color: Color) -> void:
	var w := float(img.get_width())
	for shift: float in [-w, 0.0, w]:
		fill_polygon(img, pts, color, Vector2(shift, 0.0))


static func _fill_rect_wrapped(img: Image, r: Rect2i, color: Color) -> void:
	var w := img.get_width()
	for shift: int in [-w, 0, w]:
		var rr := Rect2i(r.position + Vector2i(shift, 0), r.size).intersection(
			Rect2i(0, 0, w, img.get_height())
		)
		if rr.has_area():
			img.fill_rect(rr, color)


static func _ellipse_wrapped(img: Image, c: Vector2, rx: float, ry: float, color: Color) -> void:
	var w := img.get_width()
	for y in range(maxi(int(floor(c.y - ry)), 0), mini(int(ceil(c.y + ry)) + 1, img.get_height())):
		for x in range(int(floor(c.x - rx)), int(ceil(c.x + rx)) + 1):
			var dx := (float(x) + 0.5 - c.x) / rx
			var dy := (float(y) + 0.5 - c.y) / ry
			if dx * dx + dy * dy <= 1.0:
				_blend(img, posmod(x, w), y, color)


static func _blend(img: Image, x: int, y: int, color: Color) -> void:
	if color.a >= 0.999:
		img.set_pixel(x, y, color)
	else:
		img.set_pixel(x, y, img.get_pixel(x, y).blend(color))


static func _grow(pts: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var out := PackedVector2Array()
	for p in pts:
		var d := p - c
		out.append(p + d.normalized() * by if d.length() > 0.0 else p)
	return out


static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
	)


static func _star(c: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		var r := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
