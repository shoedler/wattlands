extends RefCounted
# Float image helpers for the v2 mock kit. Arrays are RGBA float 0..1, row-major.


static func to_f(img: Image) -> PackedFloat32Array:
	img.convert(Image.FORMAT_RGBA8)
	var b := img.get_data()
	var f := PackedFloat32Array()
	f.resize(b.size())
	for i in b.size():
		f[i] = b[i] / 255.0
	return f


static func to_img(f: PackedFloat32Array, w: int, h: int) -> Image:
	var b := PackedByteArray()
	b.resize(f.size())
	for i in f.size():
		b[i] = clampi(int(round(f[i] * 255.0)), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, b)


static func mask_new(w: int, h: int, v: float = 0.0) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(w * h)
	m.fill(v)
	return m


# Scanline polygon fill into a single-channel mask (max with existing), 4x4 supersampled edges.
static func poly_fill(m: PackedFloat32Array, w: int, h: int, pts: PackedVector2Array, val: float = 1.0) -> void:
	var minx := w
	var maxx := 0
	var miny := h
	var maxy := 0
	for p in pts:
		minx = mini(minx, int(floor(p.x)))
		maxx = maxi(maxx, int(ceil(p.x)))
		miny = mini(miny, int(floor(p.y)))
		maxy = maxi(maxy, int(ceil(p.y)))
	minx = clampi(minx, 0, w - 1)
	maxx = clampi(maxx, 0, w - 1)
	miny = clampi(miny, 0, h - 1)
	maxy = clampi(maxy, 0, h - 1)
	var n := pts.size()
	var acc := PackedFloat32Array()
	acc.resize(w)
	for y in range(miny, maxy + 1):
		acc.fill(0.0)
		for sy in 4:
			var fy := y + (sy + 0.5) / 4.0
			var xs: Array[float] = []
			for i in n:
				var a := pts[i]
				var b := pts[(i + 1) % n]
				if (a.y <= fy and b.y > fy) or (b.y <= fy and a.y > fy):
					xs.append(a.x + (fy - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			var k := 0
			while k + 1 < xs.size():
				var x0 := xs[k]
				var x1 := xs[k + 1]
				for x in range(maxi(int(floor(x0)), 0), mini(int(ceil(x1)), w)):
					var cov := clampf(minf(x + 1.0, x1) - maxf(float(x), x0), 0.0, 1.0)
					acc[x] += cov / 4.0
				k += 2
		for x in range(minx, maxx + 1):
			var v := acc[x] * val
			if v > m[y * w + x]:
				m[y * w + x] = v


static func rect_fill(m: PackedFloat32Array, w: int, h: int, r: Rect2i, val: float = 1.0) -> void:
	for y in range(maxi(r.position.y, 0), mini(r.end.y, h)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, w)):
			m[y * w + x] = maxf(m[y * w + x], val)


# Separable box blur on a single-channel mask.
static func blur1(m: PackedFloat32Array, w: int, h: int, r: int, passes: int = 3) -> PackedFloat32Array:
	var cur := m.duplicate()
	if r <= 0:
		return cur
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var inv := 1.0 / (2 * r + 1)
	for _p in passes:
		for y in h:
			var row := y * w
			var s := 0.0
			for k in range(-r, r + 1):
				s += cur[row + clampi(k, 0, w - 1)]
			for x in w:
				tmp[row + x] = s * inv
				s += cur[row + mini(x + r + 1, w - 1)] - cur[row + maxi(x - r, 0)]
		for x in w:
			var s2 := 0.0
			for k in range(-r, r + 1):
				s2 += tmp[clampi(k, 0, h - 1) * w + x]
			for y in h:
				cur[y * w + x] = s2 * inv
				s2 += tmp[mini(y + r + 1, h - 1) * w + x] - tmp[maxi(y - r, 0) * w + x]
	return cur


# Box blur (3 passes ~ gaussian) of an RGBA float image, alpha-premultiplied internally.
static func blur4(f: PackedFloat32Array, w: int, h: int, r: int, passes: int = 3) -> PackedFloat32Array:
	if r <= 0:
		return f.duplicate()
	var ch: Array[PackedFloat32Array] = []
	for c in 4:
		var m := PackedFloat32Array()
		m.resize(w * h)
		ch.append(m)
	for i in w * h:
		var a := f[i * 4 + 3]
		ch[0][i] = f[i * 4] * a
		ch[1][i] = f[i * 4 + 1] * a
		ch[2][i] = f[i * 4 + 2] * a
		ch[3][i] = a
	for c in 4:
		ch[c] = blur1(ch[c], w, h, r, passes)
	var out := PackedFloat32Array()
	out.resize(f.size())
	for i in w * h:
		var a := ch[3][i]
		out[i * 4 + 3] = a
		if a > 0.0001:
			out[i * 4] = ch[0][i] / a
			out[i * 4 + 1] = ch[1][i] / a
			out[i * 4 + 2] = ch[2][i] / a
	return out


static func dilate(m: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := m.duplicate()
	for y in h:
		for x in w:
			var v := 0.0
			for k in range(maxi(x - r, 0), mini(x + r + 1, w)):
				v = maxf(v, m[y * w + k])
			tmp[y * w + x] = v
	var out := tmp.duplicate()
	for y in h:
		for x in w:
			var v := 0.0
			for k in range(maxi(y - r, 0), mini(y + r + 1, h)):
				v = maxf(v, tmp[k * w + x])
			out[y * w + x] = v
	return out


static func erode(m: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var inv := PackedFloat32Array()
	inv.resize(m.size())
	for i in m.size():
		inv[i] = 1.0 - m[i]
	var d := dilate(inv, w, h, r)
	for i in d.size():
		d[i] = 1.0 - d[i]
	return d


static func mask_img(m: PackedFloat32Array, w: int, h: int) -> Image:
	var b := PackedByteArray()
	b.resize(w * h * 4)
	for i in w * h:
		var v := clampi(int(m[i] * 255.0), 0, 255)
		b[i * 4] = v
		b[i * 4 + 1] = v
		b[i * 4 + 2] = v
		b[i * 4 + 3] = 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, b)


# Resize an RGBA float image with premultiplied alpha (no colour bleed from transparent pixels).
static func resize_pm(img: Image, nw: int, nh: int, interp: int = Image.INTERPOLATE_LANCZOS) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var f := to_f(img)
	var pm := PackedFloat32Array()
	pm.resize(f.size())
	for i in w * h:
		var a := f[i * 4 + 3]
		pm[i * 4] = f[i * 4] * a
		pm[i * 4 + 1] = f[i * 4 + 1] * a
		pm[i * 4 + 2] = f[i * 4 + 2] * a
		pm[i * 4 + 3] = a
	var fi := Image.create_from_data(w, h, false, Image.FORMAT_RGBAF, pm.to_byte_array())
	fi.resize(nw, nh, interp)
	var g := fi.get_data().to_float32_array()
	for i in nw * nh:
		var a := clampf(g[i * 4 + 3], 0.0, 1.0)
		g[i * 4 + 3] = a
		for c in 3:
			g[i * 4 + c] = clampf(g[i * 4 + c] / a, 0.0, 1.0) if a > 0.002 else 0.0
	return to_img(g, nw, nh)
