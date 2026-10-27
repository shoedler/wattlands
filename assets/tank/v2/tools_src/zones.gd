extends SceneTree
# The free-roam zones' near planes (docs/games/tank.md 2.10, 3.1: "zones swap the near planes (village,
# quarry, meadow, lake shore) from the same procedural kit"). Each replaces the forest plane (the same
# 1920 x 354 frame, y0 0, parallax 0.3, the same two-pass box blur of radius 1) while the tank drives
# through its zone; the pine forest zone keeps planes2/forest_wide.png. Built from the kit's own planes
# only (no fal): the forest plane's trees squashed into a lower or distant tree line, the far plane's
# lake mist as the lake's water; houses, haystacks, fences, reeds, the quarry's benched rock faces,
# spoil cones, a conveyor and a timber gantry drawn in code in the planes' palette. Seamless (every feature wraps at
# 1920 px) and seeded (a fixed LCG), so a rerun is bit-exact.
# Run by regen.sh after planes2.gd, or alone from the repository root:
#   cp assets/tank/v2/tools_src/zones.gd build/v2/ && tools/godot.sh --headless --path . -s build/v2/zones.gd
# Writes assets/tank/v2/planes2/zone_<lake|village|quarry|meadow>_wide.png and previews in build/v2/.

const SRC := "res://assets/tank/v2/planes2/"
const PREVIEW := "res://build/v2/"
const W := 1920
const H := 354
## The forest plane's foot (the road's far edge) in plane rows.
const FOOT := 344.0

var forest: Image
var far: Image
var _s: int = 1


func rnd() -> float:
	_s = (_s * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_s) / 2147483648.0


func between(a: float, b: float) -> float:
	return a + (b - a) * rnd()


func _init() -> void:
	forest = Image.load_from_file(SRC + "forest_wide.png")
	forest.convert(Image.FORMAT_RGBA8)
	far = Image.load_from_file(SRC + "far_wide.png")
	far.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW))
	var makers := {"lake": _lake, "village": _village, "quarry": _quarry, "meadow": _meadow}
	var seeds := {"lake": 11, "village": 23, "quarry": 37, "meadow": 41}
	for zone: String in makers:
		_s = int(seeds[zone])
		var img: Image = (makers[zone] as Callable).call()
		img = blur(img, 1, 2)
		img.save_png(SRC + "zone_%s_wide.png" % zone)
		_preview(img, zone)
		print("zones: ", zone)
	quit()


# --- Pixel helpers ------------------------------------------------------------------------------------


func blank() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


## `c` over the pixel at (x wrapped, y) with coverage `a`.
func over(img: Image, x: int, y: int, c: Color, a: float = 1.0) -> void:
	if y < 0 or y >= H or a <= 0.0:
		return
	var px := posmod(x, W)
	var d := img.get_pixel(px, y)
	var sa := clampf(c.a * a, 0.0, 1.0)
	var oa := sa + d.a * (1.0 - sa)
	if oa <= 0.0:
		return
	var rgb := (Color(c.r, c.g, c.b) * sa + Color(d.r, d.g, d.b) * d.a * (1.0 - sa)) / oa
	img.set_pixel(px, y, Color(rgb.r, rgb.g, rgb.b, oa))


func rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color, a: float = 1.0) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			over(img, x, y, c, a)


## A filled triangle (apex up) from base [x0, x1] at y_base to the apex (ax, ay).
func gable(img: Image, x0: float, x1: float, y_base: float, ax: float, ay: float, c: Color) -> void:
	for y in range(int(ay), int(y_base) + 1):
		var k := (float(y) - ay) / maxf(y_base - ay, 1.0)
		var l := lerpf(ax, x0, k)
		var r := lerpf(ax, x1, k)
		for x in range(int(roundf(l)), int(roundf(r)) + 1):
			over(img, x, y, c)


func line(img: Image, a: Vector2, b: Vector2, c: Color, width: int = 1) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		for k in width:
			over(img, int(roundf(p.x)) + k, int(roundf(p.y)), c)


## The forest plane's trees squashed by `k` toward a foot `lift` px above the plane's own (a lower
## or more distant tree line), dimmed by `dim` toward the night haze.
func squash(k: float, lift: float, dim: float) -> Image:
	var out := blank()
	var foot := FOOT - lift
	var haze := Color(0.035, 0.05, 0.055)
	for y in H:
		var sy := int(roundf(FOOT - (foot - float(y)) / k))
		if sy < 0 or sy >= H:
			continue
		for x in W:
			var c := forest.get_pixel(x, sy)
			if c.a <= 0.0:
				continue
			var rgb := Color(c.r, c.g, c.b).lerp(haze, dim)
			out.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, c.a))
	return out


## Box blur of radius `r`, `passes` times, over all four channels (x wraps), like planes2.gd's.
func blur(img: Image, r: int, passes: int) -> Image:
	var data := PackedFloat32Array()
	data.resize(W * H * 4)
	for y in H:
		for x in W:
			var c := img.get_pixel(x, y)
			var i := (y * W + x) * 4
			data[i] = c.r * c.a
			data[i + 1] = c.g * c.a
			data[i + 2] = c.b * c.a
			data[i + 3] = c.a
	var tmp := PackedFloat32Array()
	tmp.resize(data.size())
	var n := float(2 * r + 1)
	for _p in passes:
		for y in H:
			for x in W:
				for ch in 4:
					var acc := 0.0
					for dx in range(-r, r + 1):
						acc += data[(y * W + posmod(x + dx, W)) * 4 + ch]
					tmp[(y * W + x) * 4 + ch] = acc / n
		for y in H:
			for x in W:
				for ch in 4:
					var acc2 := 0.0
					for dy in range(-r, r + 1):
						acc2 += tmp[(clampi(y + dy, 0, H - 1) * W + x) * 4 + ch]
					data[(y * W + x) * 4 + ch] = acc2 / n
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var i2 := (y * W + x) * 4
			var a := data[i2 + 3]
			if a <= 0.0001:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				out.set_pixel(x, y, Color(data[i2] / a, data[i2 + 1] / a, data[i2 + 2] / a, a))
	return out


# --- The zones ------------------------------------------------------------------------------------------
# The road plane (y0 312) covers the near plane from about row 322 down, so every feature stands on
# GROUND, where the road's far verge meets them.

const GROUND := 321.0


## A noisy line height (0..1) at x, wrapping at W (two seeded sines).
func wave(x: float, p1: float, p2: float, ph: float) -> float:
	return 0.5 + 0.3 * sin(x * TAU / p1 + ph) + 0.2 * sin(x * TAU / p2 + ph * 1.7)


## The lake shore under the cliffs: a low far shore with its reflection in still, misty water down
## to the road, ripples, star glints and reeds along the near bank.
func _lake() -> Image:
	var shore := 264.0
	var trees := squash(0.3, FOOT - shore, 0.35)
	var img := blank()
	img.blit_rect(trees, Rect2i(0, 0, W, int(shore) + 1), Vector2i.ZERO)
	for y in range(int(shore), int(GROUND) + 6):
		var k := (float(y) - shore) / (GROUND - shore)
		var c := Color(0.17, 0.21, 0.22).lerp(Color(0.045, 0.065, 0.075), pow(clampf(k, 0.0, 1.0), 0.7))
		for x in W:
			over(img, x, y, c)
			var sy := int(2.0 * shore - float(y))
			var sx := x + int(roundf(1.5 * sin(float(y) * 0.9 + float(x) * 0.05)))
			if sy >= 0:
				var t := trees.get_pixel(posmod(sx, W), sy)
				if t.a > 0.0:
					var rt := Color(t.r * 0.8, t.g * 0.8, t.b * 0.8)
					over(img, x, y, rt, t.a * 0.55 * (1.0 - clampf(k, 0.0, 1.0) * 0.6))
	for x in W:
		var m := wave(float(x), 480.0, 137.0, 0.4)
		for y in range(int(shore) - 7, int(shore) + 7):
			var a2 := (1.0 - absf(float(y) - shore) / 7.0) * 0.5 * m
			over(img, x, y, Color(0.36, 0.41, 0.43), a2 * 1.2)
	for i in 320:
		var x0 := int(rnd() * W)
		var y0 := int(between(shore + 4.0, GROUND - 3.0))
		var l := int(between(4.0, 30.0))
		var a3 := between(0.12, 0.32)
		for dx in l:
			var fall := 1.0 - absf(float(dx) / float(l) - 0.5) * 1.6
			over(img, x0 + dx, y0, Color(0.34, 0.4, 0.42), a3 * fall)
	for i in 70:
		over(img, int(rnd() * W), int(between(shore + 6.0, GROUND - 6.0)), Color(0.8, 0.84, 0.84), 0.5)
	var x1 := 0.0
	while x1 < W:
		x1 += between(4.0, 22.0)
		var n := int(between(2.0, 8.0))
		for j in n:
			var bx := x1 + j * between(1.0, 3.0)
			var h := between(6.0, 20.0)
			var lean := between(-0.25, 0.25)
			for dy in int(h):
				over(img, int(bx + lean * dy), int(GROUND + 3.0) - dy, Color(0.02, 0.028, 0.026), 0.95)
	return img


## The village: a lower tree line behind dark gabled houses and a steeple (no signs, no symbols), a
## few warm windows, chimneys, a fence along the road.
func _village() -> Image:
	var img := squash(0.62, FOOT - GROUND + 18.0, 0.3)
	# A back row first (smaller, higher on the slope, dimmer), then the street along the road.
	var x0 := between(0.0, 40.0)
	while x0 < W - 60:
		if rnd() < 0.55:
			_house(img, x0, GROUND - 8.0, 0.7, 0.6)
		x0 += between(50.0, 120.0)
	var x := 10.0
	var steeple_at := int(between(500.0, 1400.0))
	var steeple_done := false
	while x < W - 50:
		if not steeple_done and x > steeple_at:
			_steeple(img, x + 26.0, GROUND + 2.0)
			steeple_done = true
			x += 64.0
			continue
		if rnd() < 0.18:
			x += between(30.0, 80.0)  # a garden: the trees behind show through
			continue
		x = _house(img, x, GROUND + 2.0, 1.0, 1.0) + between(4.0, 40.0)
	var fx := 0
	while fx < W:
		rect(img, fx, int(GROUND) - 7, 1, 10, Color(0.07, 0.06, 0.05))
		fx += 9
	for fy: int in [int(GROUND) - 5, int(GROUND) - 1]:
		for xx in W:
			over(img, xx, fy, Color(0.08, 0.07, 0.06), 0.8)
	return img


## One gabled house standing on `base` from x `x`, scaled by `k`, its colours dimmed by `light`
## (a back-row house is smaller and darker); now and then a barn (wide and low) or a lower annex.
## Returns its right end.
func _house(img: Image, x: float, base: float, k: float, light: float) -> float:
	var haze := Color(0.04, 0.05, 0.055)
	var wall := Color(0.105, 0.105, 0.096).lerp(haze, 1.0 - light)
	var wall_lit := Color(0.17, 0.168, 0.15).lerp(haze, 1.0 - light)
	var roof := Color(0.055, 0.06, 0.066).lerp(haze, 1.0 - light)
	var ridge := Color(0.22, 0.23, 0.23).lerp(haze, 1.0 - light)
	var barn := rnd() < 0.15
	var w := (between(70.0, 100.0) if barn else between(30.0, 76.0)) * k
	var wall_h := (between(20.0, 28.0) if barn else between(26.0, 52.0)) * k
	var roof_h := (between(18.0, 26.0) if barn else between(12.0, 32.0)) * k
	var x1 := x + w
	var top := base - wall_h
	rect(img, int(x), int(top), int(w), int(wall_h) + 1, wall)
	rect(img, int(x), int(top), 2, int(wall_h) + 1, wall_lit)
	gable(img, x - 3.0, x1 + 3.0, top, (x + x1) * 0.5, top - roof_h, roof)
	line(img, Vector2(x - 3.0, top), Vector2((x + x1) * 0.5, top - roof_h), ridge)
	if not barn and rnd() < 0.7:
		var cx := int(lerpf(x, x1, between(0.6, 0.8)))
		rect(img, cx, int(top - roof_h * 0.7) - 6, 4, 9, roof)
	var right := x1
	if not barn and rnd() < 0.35:
		var aw := between(16.0, 30.0) * k
		var ah := wall_h * between(0.45, 0.6)
		rect(img, int(x1), int(base - ah), int(aw), int(ah) + 1, wall.darkened(0.15))
		line(img, Vector2(x1, base - ah - 6.0 * k), Vector2(x1 + aw + 2.0, base - ah), roof)
		right = x1 + aw
	var floors := 2 if wall_h > 40.0 * k else 1
	var nwin := int(between(1.0, 3.99)) if not barn else 1
	for f in floors:
		for i in nwin:
			var wx := int(lerpf(x + 5.0, x1 - 8.0, (float(i) + 0.5) / float(nwin)))
			var wy := int(top + wall_h * (0.22 + 0.4 * float(f)))
			var lit := rnd() < 0.45 * light
			var wc := Color(0.86, 0.6, 0.25) if lit else Color(0.025, 0.03, 0.035)
			rect(img, wx, wy, maxi(int(4.0 * k), 2), maxi(int(5.0 * k), 3), wc)
			if lit:
				rect(img, wx - 1, wy + int(5.0 * k), int(6.0 * k), 1, Color(0.5, 0.36, 0.16), 0.6)
	if barn:
		rect(img, int((x + x1) * 0.5) - 6, int(base - wall_h * 0.8), 12, int(wall_h * 0.8), roof)
	return right


func _steeple(img: Image, x: float, base: float) -> void:
	var c := Color(0.1, 0.1, 0.092)
	var roof := Color(0.05, 0.055, 0.06)
	rect(img, int(x), int(base - 66.0), 20, 67, c)
	rect(img, int(x), int(base - 66.0), 2, 67, Color(0.17, 0.168, 0.15))
	gable(img, x - 2.0, x + 22.0, base - 66.0, x + 10.0, base - 108.0, roof)
	rect(img, int(x) + 7, int(base - 54.0), 6, 9, Color(0.02, 0.025, 0.03))
	rect(img, int(x) - 28, int(base - 32.0), 28, 33, c)
	gable(img, x - 31.0, x + 1.0, base - 32.0, x - 14.0, base - 46.0, roof)


## The quarry: worked rock faces cut in benches, each with a ragged crest tapering at both ends into
## talus slopes, built procedurally (no copied texture, nothing mirrored or tiled under the plane's
## 1920 px): horizontal strata of varying height and tone, a lit lip over a shadow at every bench,
## per-column noise, vertical cracks, scree fans at the foot; moonlit grey-teal at the crest darkening
## toward the night teal at the foot, kept below the hero's values. At their feet gravel spoil cones,
## one fed by a conveyor on trestles, and a timber gantry with its pulley; the forest low behind.
func _quarry() -> Image:
	var img := squash(0.5, FOOT - GROUND, 0.3)
	var spans: Array[Vector2] = []
	var x := between(40.0, 200.0)
	while x < W - 260:
		var w := between(300.0, 560.0)
		spans.append(Vector2(x, x + w))
		x += w + between(160.0, 300.0)
	var rock_top := Color(0.25, 0.285, 0.285)
	var rock_foot := Color(0.075, 0.095, 0.1)
	for sp in spans:
		var ph := rnd() * TAU
		var crest := between(186.0, 208.0)
		var talus := between(60.0, 96.0)
		# Benches (fractions of the face) and the strata between them, each with its own tone.
		var benches: Array[float] = []
		var b := between(0.18, 0.3)
		while b < 0.85:
			benches.append(b)
			b += between(0.16, 0.3)
		# Strata: [start (fraction of the face), tone, joint spacing (px), joint offset].
		var strata: Array[Vector4] = []
		var s := 0.0
		while s < 1.0:
			var sh := between(0.05, 0.14)
			strata.append(Vector4(s, between(-0.05, 0.05), between(8.0, 22.0), between(0.0, 40.0)))
			s += sh
		for xx in range(int(sp.x), int(sp.y)):
			var top := crest + 14.0 * (wave(float(xx), 230.0, 67.0, ph) - 0.5)
			top += 3.0 * (wave(float(xx), 13.0, 5.0, ph * 2.0) - 0.5)
			var side := minf(float(xx) - sp.x, sp.y - float(xx))
			var t_end := smoothstep(0.0, 1.0, side / talus)
			top = lerpf(GROUND - 2.0, top, t_end)
			var face_h := GROUND + 2.0 - top
			var col_noise := (_hash(float(xx) * 0.37 + ph) - 0.5) * 0.05
			var dip := 0.02 * (wave(float(xx), 310.0, 97.0, ph * 0.7) - 0.5)
			var prev_si := -1
			for y in range(int(top), int(GROUND) + 3):
				var k := (float(y) - top) / maxf(face_h, 1.0)
				var c := rock_top.lerp(rock_foot, pow(k, 0.8))
				var si := 0
				for i2 in strata.size():
					if k + dip >= strata[i2].x:
						si = i2
				var st: Vector4 = strata[si]
				var n := st.y + col_noise + (_hash(float(xx) * 1.3 + float(y) * 7.1) - 0.5) * 0.035
				if t_end < 1.0:
					n -= 0.04 * (1.0 - t_end)
				var jx := posmod(xx + int(st.w), maxi(int(st.z), 2))
				if t_end >= 1.0 and si != prev_si and prev_si >= 0:
					n -= 0.07
				elif t_end >= 1.0 and jx == 0:
					n -= 0.06
				elif t_end >= 1.0 and jx == 1:
					n += 0.03
				prev_si = si
				over(img, xx, y, Color(c.r + n, c.g + n, c.b + n * 0.9))
			over(img, xx, int(top), Color(0.34, 0.37, 0.36), 0.5)
			if t_end >= 1.0:
				for bk in benches:
					var wob := 1.5 * (wave(float(xx), 41.0, 11.0, bk * 9.0) - 0.5)
					var ly := int(top + face_h * bk + wob)
					over(img, xx, ly, Color(0.3, 0.33, 0.32), 0.45)
					over(img, xx, ly + 1, Color(0.02, 0.025, 0.028), 0.7)
					over(img, xx, ly + 2, Color(0.02, 0.025, 0.028), 0.35)
			else:
				# Talus: loose scree, a speckle of lighter stones.
				for y2 in range(int(top) + 1, int(GROUND) + 2):
					if _hash(float(xx) * 3.7 + float(y2) * 1.9) > 0.9:
						over(img, xx, y2, Color(0.22, 0.24, 0.24), 0.6)
		# Cracks: thin dark verticals, a little crooked.
		var nc := int((sp.y - sp.x) / 26.0)
		for i in nc:
			var fx := between(sp.x + talus, sp.y - talus)
			var fy := between(crest + 6.0, GROUND - 34.0)
			var fl := between(8.0, 34.0)
			var lean := between(-0.2, 0.2)
			for d in int(fl):
				over(img, int(fx + lean * d), int(fy) + d, Color(0.02, 0.025, 0.028), 0.65)
		# Scree fans at the foot of the face.
		for i in int(between(2.0, 4.99)):
			var cx := between(sp.x + talus, sp.y - talus)
			var fw := between(18.0, 34.0)
			var fh := between(8.0, 16.0)
			for y3 in range(int(GROUND - fh), int(GROUND) + 3):
				var kk := (float(y3) - (GROUND - fh)) / fh
				var hw := fw * 0.5 * kk
				for x3 in range(int(cx - hw), int(cx + hw) + 1):
					var h3 := _hash(float(x3) * 2.1 + float(y3) * 5.3)
					over(img, x3, y3, Color(0.14, 0.155, 0.155) if h3 > 0.3 else Color(0.2, 0.22, 0.22))
	# Spoil cones of gravel at the faces' feet, one fed by a conveyor on trestles.
	for i in spans.size():
		var sp2 := spans[i]
		var hx := between(sp2.x + 60.0, sp2.y - 90.0)
		var hw2 := between(60.0, 90.0)
		var hh2 := between(20.0, 30.0)
		var hb := GROUND + 3.0
		for y4 in range(int(hb - hh2), int(hb) + 1):
			var k4 := (float(y4) - (hb - hh2)) / hh2
			for x4 in range(int(hx - hw2 * 0.5 * k4), int(hx + hw2 * 0.5 * k4) + 1):
				var h4 := _hash(float(x4) * 1.7 + float(y4) * 3.1)
				var lit := 0.03 if x4 < hx else -0.03
				var g4 := 0.12 + lit + (0.06 if h4 > 0.82 else 0.0) - (0.05 if h4 < 0.2 else 0.0)
				over(img, x4, y4, Color(g4 * 1.05, g4, g4 * 0.9))
		if i % 2 == 0:
			var top2 := Vector2(hx, hb - hh2 - 2.0)
			var far2 := top2 + Vector2(70.0, -46.0)
			line(img, top2, far2, Color(0.05, 0.045, 0.04), 2)
			for tk in [0.35, 0.7]:
				var tp := top2.lerp(far2, tk)
				line(img, tp, Vector2(tp.x, hb), Color(0.06, 0.055, 0.05))
			over(img, int(far2.x), int(far2.y) - 1, Color(0.9, 0.62, 0.3), 0.8)
	var gx := spans[0].y - 50.0 if not spans.is_empty() else 600.0
	_gantry(img, gx)
	return img


## A stable 0..1 from a number (the quarry's grain).
func _hash(a: float) -> float:
	var s := sin(a * 12.9898 + 78.233) * 43758.5453
	return s - floorf(s)


func _gantry(img: Image, x: float) -> void:
	var c := Color(0.05, 0.045, 0.04)
	var base := GROUND + 2.0
	line(img, Vector2(x, base), Vector2(x + 10.0, base - 84.0), c, 2)
	line(img, Vector2(x + 34.0, base), Vector2(x + 24.0, base - 84.0), c, 2)
	line(img, Vector2(x - 8.0, base - 84.0), Vector2(x + 72.0, base - 84.0), c, 2)
	for i in 4:
		var y := base - 18.0 - i * 17.0
		line(img, Vector2(x + 2.0 + i * 2.0, y), Vector2(x + 32.0 - i * 2.0, y - 15.0), c)
	line(img, Vector2(x + 66.0, base - 84.0), Vector2(x + 66.0, base - 42.0), Color(0.14, 0.14, 0.13))
	for a in 16:
		var p := Vector2(x + 66.0, base - 86.0) + Vector2.from_angle(a * TAU / 16.0) * 4.0
		over(img, int(p.x), int(p.y), c)
	rect(img, int(x) + 62, int(base) - 44, 9, 7, Color(0.09, 0.08, 0.07))


## The open meadow: a distant low tree line, a dark grass slope to the road, haystacks, a fence and
## lone broad trees.
func _meadow() -> Image:
	var horizon := 272.0
	var img := squash(0.3, FOOT - horizon, 0.5)
	for y in range(int(horizon) - 2, int(GROUND) + 6):
		var k := (float(y) - horizon) / (GROUND - horizon)
		var c := Color(0.05, 0.066, 0.05).lerp(Color(0.032, 0.042, 0.034), clampf(k, 0.0, 1.0))
		var a := smoothstep(horizon - 2.0, horizon + 3.0, float(y))
		for x in W:
			var n := 0.9 + 0.2 * rnd()
			over(img, x, y, Color(c.r * n, c.g * n, c.b * n), a)
	for i in 14:
		var hy := between(horizon + 8.0, GROUND - 1.0)
		var depth := (hy - horizon) / (GROUND - horizon)
		var hx := between(0.0, W)
		var hw := lerpf(8.0, 26.0, depth)
		var hh := hw * 0.62
		for dy in int(hh):
			var half := hw * 0.5 * sqrt(1.0 - pow(1.0 - float(dy) / hh, 2.0))
			for dx in range(int(-half), int(half) + 1):
				var c2 := Color(0.25, 0.22, 0.15) if dy < 2 else Color(0.16, 0.14, 0.095)
				over(img, int(hx) + dx, int(hy - hh + dy), c2)
	var fx := 0
	while fx < W:
		rect(img, fx, int(GROUND) - 10, 1, 12, Color(0.075, 0.065, 0.05))
		fx += 14
	for fy: int in [int(GROUND) - 8, int(GROUND) - 3]:
		for xx in W:
			over(img, xx, fy, Color(0.08, 0.07, 0.055), 0.75)
	for t in 2:
		var tx := between(200.0, 900.0) + t * 860.0
		var ty := GROUND - 4.0
		line(img, Vector2(tx, ty), Vector2(tx, ty - 34.0), Color(0.035, 0.035, 0.03), 3)
		for b in 360:
			var a3 := rnd() * TAU
			var rr := sqrt(rnd()) * 24.0
			var p := Vector2(tx + 1.0, ty - 52.0) + Vector2(cos(a3) * rr * 1.3, sin(a3) * rr * 0.8)
			var g := Color(0.035, 0.05, 0.045).lerp(Color(0.07, 0.09, 0.08), rnd())
			over(img, int(p.x), int(p.y), g)
	return img


## far + zone + road + foreground at the first 960 px, the way the view stacks them.
func _preview(zone: Image, name: String) -> void:
	var comp := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	comp.fill(Color(0, 0, 0, 1))
	comp.blend_rect(far, Rect2i(0, 0, 960, 330), Vector2i.ZERO)
	comp.blend_rect(zone, Rect2i(0, 0, 960, H), Vector2i.ZERO)
	var road := Image.load_from_file(SRC + "road_wide.png")
	road.convert(Image.FORMAT_RGBA8)
	comp.blend_rect(road, Rect2i(0, 0, 960, road.get_height()), Vector2i(0, 312))
	var fg := Image.load_from_file(SRC + "foreground_wide.png")
	fg.convert(Image.FORMAT_RGBA8)
	comp.blend_rect(fg, Rect2i(0, 0, 960, fg.get_height()), Vector2i(0, 344))
	comp.save_png(PREVIEW + "zone_%s_preview.png" % name)
