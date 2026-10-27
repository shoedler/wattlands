extends RefCounted
## The additive light layer of the v3 tank mock (what the game's Light layer would draw): a bloom of
## the tank's bright pixels (lamps, the arc, the firebox, warm pools spilling out of the cutaways),
## halos round the position lights and the headlight, and the headlight's and searchlight's beams.
## Everything is added onto an already composited frame.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")


## Pixels of `src` brighter than `thr` (luminance), scaled to 0..1 above it, the rest black.
static func bright(src: Image, thr: float, rect: Rect2i) -> Image:
	var o := Image.create_empty(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	o.fill(Color(0, 0, 0, 1))
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, src.get_height())):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, src.get_width())):
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
			if l <= thr:
				continue
			var k := (l - thr) / (1.0 - thr)
			o.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1))
	return o


## A cheap wide blur: down to 1/k with bilinear, back up with bilinear (twice).
static func blur(src: Image, k: int) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var o := src.duplicate() as Image
	o.resize(maxi(w / k, 1), maxi(h / k, 1), Image.INTERPOLATE_BILINEAR)
	o.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var k2 := maxi(k / 2, 1)
	o.resize(maxi(w / k2, 1), maxi(h / k2, 1), Image.INTERPOLATE_BILINEAR)
	o.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return o


## dst += src * gain (rgb), inside `rect`.
static func add_into(dst: Image, src: Image, gain: float, rect: Rect2i) -> void:
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, dst.get_height())):
		for x in range(maxi(rect.position.x, 0), mini(rect.end.x, dst.get_width())):
			var s := src.get_pixel(x, y)
			if s.r + s.g + s.b < 0.004:
				continue
			var d := dst.get_pixel(x, y)
			dst.set_pixel(x, y, Color(minf(d.r + s.r * gain, 1.0), minf(d.g + s.g * gain, 1.0), minf(d.b + s.b * gain, 1.0), d.a))


## Bloom of `tank_layer` (the tank alone on a clear canvas the size of `dst`) added onto `dst`.
static func bloom(dst: Image, tank_layer: Image, rect: Rect2i) -> void:
	var r := rect.grow(24)
	var wide := blur(bright(tank_layer, 0.32, rect), 8)
	add_into(dst, wide, 0.9, r)
	var tight := blur(bright(tank_layer, 0.62, rect), 3)
	add_into(dst, tight, 1.3, r)


## A soft round halo.
static func halo(dst: Image, at: Vector2, rad: float, col: Color, a: float) -> void:
	for y in range(floori(at.y - rad), ceili(at.y + rad) + 1):
		for x in range(floori(at.x - rad), ceili(at.x + rad) + 1):
			if not Px.inside(dst, x, y):
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(at) / rad
			if d >= 1.0:
				continue
			var f := (1.0 - d) * (1.0 - d) * a
			var o := dst.get_pixel(x, y)
			dst.set_pixel(x, y, Color(minf(o.r + col.r * f, 1.0), minf(o.g + col.g * f, 1.0), minf(o.b + col.b * f, 1.0), o.a))


## A flat oval pool of light on the ground (rx wide, ry tall).
static func pool(dst: Image, at: Vector2, rx: float, ry: float, col: Color, a: float) -> void:
	for y in range(floori(at.y - ry), ceili(at.y + ry) + 1):
		for x in range(floori(at.x - rx), ceili(at.x + rx) + 1):
			if not Px.inside(dst, x, y):
				continue
			var d := Vector2((x + 0.5 - at.x) / rx, (y + 0.5 - at.y) / ry).length()
			if d >= 1.0:
				continue
			var f := (1.0 - d) * (1.0 - d) * a
			var o := dst.get_pixel(x, y)
			dst.set_pixel(x, y, Color(minf(o.r + col.r * f, 1.0), minf(o.g + col.g * f, 1.0), minf(o.b + col.b * f, 1.0), o.a))


## A light cone from `at` along `ang` (radians, y down), `length` px, half-angle `half`.
static func beam(dst: Image, at: Vector2, ang: float, length: float, half: float, col: Color, a: float) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var t := tan(half)
	var pts := [at, at + d * length + n * length * t, at + d * length - n * length * t]
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p: Vector2 in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	for y in range(maxi(floori(mn.y) - 2, 0), mini(ceili(mx.y) + 2, dst.get_height())):
		for x in range(maxi(floori(mn.x) - 2, 0), mini(ceili(mx.x) + 2, dst.get_width())):
			var v := Vector2(x + 0.5, y + 0.5) - at
			var along := v.dot(d)
			if along <= 0.0 or along > length:
				continue
			var w := along * t + 1.5
			var perp := absf(v.dot(n))
			if perp > w:
				continue
			var f := pow(1.0 - along / length, 1.4) * (1.0 - perp / w) * a
			f *= clampf(along / 6.0, 0.3, 1.0)
			var o := dst.get_pixel(x, y)
			dst.set_pixel(x, y, Color(minf(o.r + col.r * f, 1.0), minf(o.g + col.g * f, 1.0), minf(o.b + col.b * f, 1.0), o.a))


## The tank's own lights from its layout's details, through `xf` (local -> canvas): position light
## halos, the headlight's halo and beam, the searchlight's beam when `search_on`.
static func tank_lights(dst: Image, L: Dictionary, xf: Transform2D, search_on: bool) -> void:
	var rot := xf.get_rotation()
	for d: Dictionary in L.get("details", []):
		match str(d["kind"]):
			"lamp_red":
				var p := xf * (Vector2(d["at"]) + Vector2(0.5, 0.5))
				halo(dst, p, 7.0, Color("#ff3a20"), 0.9)
				halo(dst, p, 2.5, Color("#ffb0a0"), 0.8)
			"lamp_green":
				var p2 := xf * (Vector2(d["at"]) + Vector2(0.5, 0.5))
				halo(dst, p2, 7.0, Color("#20ff60"), 0.8)
				halo(dst, p2, 2.5, Color("#b0ffc8"), 0.8)
			"headlight":
				var p3 := xf * (Vector2(d["at"]) + Vector2(3.5, 0.0))
				beam(dst, p3, rot + deg_to_rad(5.0), 230.0, deg_to_rad(9.0), Color("#ffd890"), 0.32)
				halo(dst, p3, 12.0, Color("#ffd890"), 0.9)
				halo(dst, p3, 4.0, Color("#fff6d8"), 1.0)
			"searchlight", "searchlight_rear":
				var off: Vector2 = d.get("lens", Vector2(5.5, -0.5))
				var p4 := xf * (Vector2(d["at"]) + off)
				if search_on or bool(d.get("always", false)):
					var a := rot + deg_to_rad(float(d.get("ang", -11.0)))
					var ln := float(d.get("len", 300.0))
					var hf := deg_to_rad(float(d.get("half", 5.0)))
					beam(dst, p4, a, ln, hf, Color("#fff0c8"), float(d.get("a", 0.36)))
					halo(dst, p4, 10.0, Color("#fff0c8"), 0.9)
					if d.has("ground"):
						# where the cone's axis meets the road: a warm oval pool
						var gy: float = (xf * Vector2(0, float(d["ground"]))).y
						var dv := Vector2(cos(a), sin(a))
						if dv.y > 0.01:
							var hit := p4 + dv * ((gy - p4.y) / dv.y)
							pool(dst, hit, 46.0, 7.0, Color("#ffe8b8"), 0.32)
