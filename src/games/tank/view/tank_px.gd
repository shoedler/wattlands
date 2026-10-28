class_name TankPx
extends RefCounted
## Pixel helpers on Image for the v3 tank's live room painter (TankInterior), ported from the r6
## generator (assets/tank/v3/tools_src/px.gd): a deterministic hash, additive light onto a pixel,
## and oriented profiles (barrels, shells, rods) drawn per pixel at any angle, clipped by a mask.

const OUTLINE := Color("#0b0806")


## Deterministic hash in [0, 1) (px.gd h2).
static func h2(x: int, y: int, s: int = 0) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65536.0


## Additive light `c` x `a` onto an opaque pixel.
static func add(i: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= i.get_width() or y >= i.get_height():
		return
	var o := i.get_pixel(x, y)
	if o.a < 0.01:
		return
	i.set_pixel(
		x,
		y,
		Color(minf(o.r + c.r * a, 1.0), minf(o.g + c.g * a, 1.0), minf(o.b + c.b * a, 1.0), o.a)
	)


## Smoothstep ease (tank.gd _ease).
static func ease_k(k: float) -> float:
	var t := clampf(k, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## A profile along direction `ang` from `o`: segs = [[u0, u1, hw0, hw1, top, mid, bot], ...]
## (half-width tapering hw0 -> hw1; top = the side towards -normal, lit), ringed by `outline` unless
## it is transparent. Only pixels whose `clip` byte is non-zero are drawn (an empty clip: all).
static func profile(
	i: Image,
	o: Vector2,
	ang: float,
	segs: Array,
	outline: Color = OUTLINE,
	clip: PackedByteArray = PackedByteArray()
) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var nrm := Vector2(-dir.y, dir.x)
	var umin := 1e9
	var umax := -1e9
	var hmax := 0.0
	for s: Array in segs:
		umin = minf(umin, float(s[0]))
		umax = maxf(umax, float(s[1]))
		hmax = maxf(hmax, maxf(float(s[2]), float(s[3])))
	var a := o + dir * umin
	var b := o + dir * umax
	var mn := a.min(b) - Vector2.ONE * (hmax + 2.0)
	var mx := a.max(b) + Vector2.ONE * (hmax + 2.0)
	var w := i.get_width()
	var h := i.get_height()
	for y in range(maxi(floori(mn.y), 0), mini(ceili(mx.y) + 1, h)):
		for x in range(maxi(floori(mn.x), 0), mini(ceili(mx.x) + 1, w)):
			if clip.size() > 0 and clip[y * w + x] == 0:
				continue
			var d := Vector2(x + 0.5, y + 0.5) - o
			var u := d.dot(dir)
			var v := d.dot(nrm)
			var best := Color(0, 0, 0, 0)
			var edge := false
			for s: Array in segs:
				var u0 := float(s[0])
				var u1 := float(s[1])
				if u < u0 - 0.7 or u > u1 + 0.7:
					continue
				var t := clampf((u - u0) / maxf(u1 - u0, 0.001), 0.0, 1.0)
				var hw := lerpf(float(s[2]), float(s[3]), t)
				if u >= u0 and u <= u1 and absf(v) <= hw:
					if v < -hw + 1.0:
						best = s[4]
					elif v > hw - 1.0:
						best = s[6]
					else:
						best = s[5]
				elif absf(v) <= hw + 0.85:
					edge = true
			if best.a > 0.0:
				i.set_pixel(x, y, best)
			elif edge and outline.a > 0.0:
				i.set_pixel(x, y, outline)
