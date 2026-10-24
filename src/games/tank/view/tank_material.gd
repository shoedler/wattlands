class_name TankMaterial
extends RefCounted
## The armour's shading at load (brief 3 "Not chunky pixel art"): riveted plates, each one flat
## tone bounded by its seams, with a lit top edge, a shaded bottom edge and soft soot runs under its
## top edge, over the generated plates. Seams, rivets and hatch outlines stay crisp. Used by
## TankPlaceholderArt.material_grade for the hulls, turrets, enemies and the Behemoth; the details
## pass (crew_details, armour_details) draws a seam on every plate boundary chosen here
## (seams_x / seams_y), so no tonal edge ever crosses a seam or runs between them.

const G0 := Color("#07080a")
const G1 := Color("#0f1012")
const G2 := Color("#17181b")
const G3 := Color("#202124")
const G4 := Color("#2a2b2e")
const G5 := Color("#353739")
const G6 := Color("#424446")
const G7 := Color("#525456")
const G8 := Color("#666869")
const G9 := Color("#808182")
const G10 := Color("#a3a4a4")
const G11 := Color("#cfd0cf")
const O0 := Color("#59636c")
const O2 := Color("#4b5561")
const C0 := Color("#2e3944")
const R0 := Color("#3a2a24")

## Luminance gap from the plate tone above which a pixel on a thin line (a hatch outline, a lit
## lip) is kept as detail; fainter marks are flattened into their plate.
const DETAIL_LUM := 0.06
## Plate tones vary by at most this much luminance (the scene critic: about 6% plate to plate).
const PLATE_SPREAD := 0.036
## The widest plate (art px) before an extra seam is added, by sprite family.
const MAX_PLATE_W := {"hull_": 40, "turret_": 30, "enemy_": 26, "boss_": 44}
## Soot runs: how far a run darkens toward #07080a at its top (the Behemoth's at half).
const SOOT_A := 0.3
const SOOT_A_BOSS := 0.15

## The plate boundaries chosen for each id at load: id -> {"x": PackedInt32Array, "y": ...}.
static var _seams: Dictionary = {}


## The vertical plate seams of `id` (columns), as chosen by the last tonal_patches of that id.
static func seams_x(id: String) -> PackedInt32Array:
	return (_seams.get(id, {}) as Dictionary).get("x", PackedInt32Array())


## The horizontal plate seams of `id` (rows), as chosen by the last tonal_patches of that id.
static func seams_y(id: String) -> PackedInt32Array:
	return (_seams.get(id, {}) as Dictionary).get("y", PackedInt32Array())


## Armour as seam-bounded plates instead of free-form patches (the round 3 scene critic: blotches
## crossing the seams read as camouflage). The generated sprite's own long vertical and horizontal
## seams are found, plates wider than MAX_PLATE_W get an extra seam, and every grey or slate armour
## pixel takes its plate's one tone: the sprite's mean, offset per plate by at most PLATE_SPREAD,
## lit on the two rows under the plate's top edge and shaded on its bottom row, with a slight grade
## from the upper plates to the lower. Thin lines standing DETAIL_LUM off the plate (hatch outlines,
## lit lips) keep their tone, capped at #525456; lone pixels (dust) and rust or mud stains are
## flattened (the details pass draws the rivet rows, the skirt's rust and the mud splashes). Soot
## runs down from under each plate's top edge in 1-3 px soft vertical gradients that fade out
## inside the plate.
static func tonal_patches(img: Image, id: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var steel_keys := {}
	var olives: Array[Color] = [Color("#2b2a24"), Color("#3d3c33"), Color("#545246")]
	for col: Color in [G0, G1, G2, G3, G4, G5, G6, G7, G8, G9, G10, G11, O0, O2, C0] + olives:
		steel_keys[col.to_rgba32()] = true
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var steel := PackedByteArray()
	steel.resize(w * h)
	# Rust stains and mud crumbs on the plates are flattened into their plate too (rust lives on the
	# code-drawn skirt, mud in the details pass's few large splashes).
	var rust_keys := {}
	for col: String in [
		"#3a2a24", "#5a3a2e", "#7d4f3a", "#17130f", "#241d17", "#33291f", "#443628"
	]:
		rust_keys[Color(col).to_rgba32()] = true
	var total := 0.0
	var count := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var i := y * w + x
			lum[i] = -1.0
			if c.a <= 0.5:
				continue
			if rust_keys.has(c.to_rgba32()):
				steel[i] = 1
				lum[i] = G3.get_luminance()
				continue
			if steel_keys.has(c.to_rgba32()):
				steel[i] = 1
				lum[i] = c.get_luminance()
				total += lum[i]
				count += 1
	if count == 0:
		return
	var global_mean := clampf(total / float(count), 0.085, 0.15)
	var xs := _fill_gaps(_find_seams(lum, steel, w, h, true), w, _max_plate(id))
	var ys := _find_seams(lum, steel, w, h, false)
	_seams[id] = {"x": xs, "y": ys}
	var col_of := _band_index(xs, w)
	var row_of := _band_index(ys, h)
	var seed_value := absi(id.hash()) % 7919
	var src := img.duplicate() as Image
	# The tone of every pixel, walked per column through its plate runs (a run ends at a horizontal
	# seam or the silhouette's edge).
	var tones := PackedFloat32Array()
	tones.resize(w * h)
	for x in w:
		var y := 0
		while y < h:
			if src.get_pixel(x, y).a < 0.5:
				y += 1
				continue
			var y0 := y
			var y1 := y
			while y1 + 1 < h and src.get_pixel(x, y1 + 1).a > 0.5 and row_of[y1 + 1] == row_of[y0]:
				y1 += 1
			var tone := global_mean + _plate_offset(Vector2i(col_of[x], row_of[y0]), seed_value)
			tone += 0.012 if row_of[y0] == 0 else 0.0
			for yy in range(y0, y1 + 1):
				var t := tone + 0.018 * (1.0 - 2.0 * float(yy) / float(h))
				var d := yy - y0
				if d == 0:
					t += 0.035
				elif d == 1:
					t += 0.02
				elif yy == y1 and y1 - y0 >= 4:
					t -= 0.03
				tones[yy * w + x] = t
			y = y1 + 1
	for y in h:
		for x in w:
			var i := y * w + x
			if steel[i] == 0:
				continue
			var l := lum[i]
			var t := tones[i]
			# Lone light pixels are dust, not rivets: the details pass draws every rivet row itself.
			if absf(l - t) > DETAIL_LUM and _line_pixel(lum, steel, w, h, x, y, t):
				img.set_pixel(x, y, _ramp_colour(minf(l, G7.get_luminance())))
				continue
			img.set_pixel(x, y, _ramp_colour(t))
	var soot_a := SOOT_A_BOSS if id.begins_with("boss_") else SOOT_A
	_soot_runs(img, steel, row_of, xs, seed_value, soot_a)
	# Outline pixels (the silhouette's dark edge) stay dark.
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if steel[y * w + x] == 0 or src.get_pixel(x, y) != G0:
				continue
			for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if src.get_pixel(x + dv.x, y + dv.y).a < 0.5:
					img.set_pixel(x, y, G0)
					break


## Rust under the rivets, soot where smoke and powder blow, and the Behemoth's own lights (the round
## 5 scene critic: clean, even grey plates with regular rivet dots read as code-drawn). At load,
## deterministic, on the details pass's result:
## - a thin rust streak runs down from about a third of the rivets (a rivet head over its shadow, as
##   the details pass draws them): 1 px wide, 3-8 px long, blending toward #5a3a2e from 45% to
##   nothing, stopping at a seam, the silhouette's edge or the skirt;
## - the crew's hull is sooted round its exhaust stack (rigs.json `exhaust`), a soft gradient
##   blown back along the deck; every turret's face round its gun is powder-sooted;
## - rain-washed grime: narrow vertical streaks from under the top edge down the plates, soot-dark or
##   rust-brown, fading out over 8-30 px (strongest on the Behemoth, mildest on the crew's hull);
## - the Behemoth's upper plates catch a little more light than its lower ones, three lit vision
##   slits (amber in a dark recess, never round, never side by side) and a glowing engine grille on
##   its rear deck, and its turret one slit, so it is lit from within.
static func weathered(src: Image, id: String) -> Image:
	var img := src.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	var c := TankPlaceholderArt.Canvas.new(w, h)
	c.img = img
	c.seed_value = absi(id.hash()) % 9973
	var stop_y := h
	if id.begins_with("hull_"):
		stop_y = TankPlaceholderArt.skirt_row(id)
	elif id == "boss_hull":
		stop_y = int(h * 0.8)
	elif id.begins_with("enemy_"):
		var rigs: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(TankPlaceholderArt.RIGS_JSON)
		)
		var en: Dictionary = (
			((rigs as Dictionary).get("enemies", {}) as Dictionary).get(id, {})
			if rigs is Dictionary
			else {}
		)
		stop_y = int(en.get("track_y", h)) - 7 if en.has("track_y") else int(h * 0.55)
	if id == "boss_hull":
		_upper_light(c, int(h * 0.7))
	var grime := 1.0 if id.begins_with("boss_") else (0.75 if id.begins_with("enemy_") else 0.6)
	if id != "enemy_dugin":
		_grime_streaks(c, stop_y, grime)
	_rust_streaks(c, stop_y)
	if id.begins_with("hull_"):
		var def := TankRigs.tank_def(id.trim_prefix("hull_"))
		if def.has("exhaust"):
			var ex := TankRigs.vec(def.get("exhaust"))
			_soot_fan(c, int(ex.x), stop_y)
	elif id.begins_with("turret_") and id != "turret_secondary":
		var tdef: Dictionary = TankRigs.tank_def(id.trim_prefix("turret_")).get("turret", {})
		var tr := TankRigs.rect(tdef.get("rect"))
		var tn := TankRigs.vec(tdef.get("trunnion")) - tr.position
		_soot_blot(c, Vector2(minf(tn.x, float(w) - 3.0), tn.y), 8.0, 0.45)
	elif id.begins_with("boss_turret"):
		_soot_blot(c, Vector2(4.0, h * 0.45), 9.0, 0.4)
	if id == "boss_hull":
		for f: Vector2 in [Vector2(0.19, 0.44), Vector2(0.5, 0.3), Vector2(0.81, 0.5)]:
			_port(c, int(f.x * float(w)), f.y)
		_grille(c, int(w * 0.9))
	elif id == "boss_turret":
		_port(c, int(w * 0.62), 0.42)
	return c.img


## Rows above `to_y` lifted a little toward #525456 (up to 22% at the top): the upper plates catch
## the sky's light, the lower ones (with _lower_gradient) sink into grime.
static func _upper_light(c: TankPlaceholderArt.Canvas, to_y: int) -> void:
	for y in mini(to_y, c.h):
		var k := 0.22 * (1.0 - float(y) / float(maxi(to_y, 1)))
		for x in c.w:
			var cc := c.img.get_pixel(x, y)
			if cc.a < 0.5 or cc.get_luminance() > G7.get_luminance() or cc.r > cc.b + 0.04:
				continue
			if cc == G0 or cc == G1:
				continue
			c.px(x, y, cc.lerp(G7, k))


## Rain-washed grime above `stop_y`, `strength` 0 .. 1 (see weathered): every 5-11 px a 1-2 px
## streak from 2-5 px under the column's top edge, soot (toward #0f1012) or rust (toward #3a2a24),
## fading to nothing over 8-30 px. Seams, rivets and outlines are left as they are.
static func _grime_streaks(c: TankPlaceholderArt.Canvas, stop_y: int, strength: float) -> void:
	var tops := _tops_of(c.img)
	var x := 3 + int(c.noise(1, 2, 51) * 5.0)
	var n := 0
	while x < c.w - 3:
		n += 1
		var width := 1 + int(c.noise(x, n, 53) * 2.0)
		var y0 := tops[x] + 2 + int(c.noise(x, n, 55) * 4.0)
		var length := 8 + int(c.noise(x, n, 57) * 23.0)
		var rust := c.noise(x, n, 59) < 0.4
		var col := R0 if rust else G1
		var a0 := (0.32 if rust else 0.4) * strength
		for dx in width:
			var xx := x + dx
			for d in length:
				var yy := y0 + d
				if yy >= stop_y or not c.solid(xx, yy):
					break
				var cc := c.img.get_pixel(xx, yy)
				if cc == G0 or cc == G1 or cc == G7:
					continue
				var k := a0 * (1.0 - float(d) / float(length)) * (0.6 if dx > 0 else 1.0)
				c.px(xx, yy, cc.lerp(col, k))
		x += 5 + int(c.noise(x, n, 61) * 7.0)


## Rust streaks from about a third of the rivets above `stop_y` (see weathered).
static func _rust_streaks(c: TankPlaceholderArt.Canvas, stop_y: int) -> void:
	var heads: Array[Vector2i] = []
	for y in range(0, mini(stop_y, c.h) - 2):
		for x in range(0, c.w - 1):
			if c.img.get_pixel(x, y) == G7 and c.img.get_pixel(x + 1, y + 1) == G1:
				heads.append(Vector2i(x, y))
	for hd in heads:
		if c.noise(hd.x, hd.y, 41) > 0.33:
			continue
		var length := 3 + int(c.noise(hd.x, hd.y, 43) * 6.0)
		for d in length:
			var yy := hd.y + 2 + d
			if yy >= stop_y or not c.solid(hd.x, yy):
				break
			var cc := c.img.get_pixel(hd.x, yy)
			if cc.get_luminance() < G2.get_luminance() + 0.005 or cc == G7:
				break
			c.px(hd.x, yy, cc.lerp(TankPlaceholderArt.R1, 0.45 * (1.0 - float(d) / float(length))))


## Soot round an exhaust stack at column `ex`: a soft gradient over the deck and the plates under it,
## strongest at the stack's foot and blown back (left) along the deck, fading out within ~26 px.
static func _soot_fan(c: TankPlaceholderArt.Canvas, ex: int, stop_y: int) -> void:
	var tops := _tops_of(c.img)
	if ex < 0 or ex >= c.w:
		return
	var deck := tops[ex]
	for y in range(deck, mini(deck + 16, stop_y)):
		for x in range(maxi(ex - 28, 0), mini(ex + 8, c.w)):
			if not c.solid(x, y):
				continue
			var back := float(ex + 2 - x) / 26.0
			var along := 1.0 - absf(back - 0.25) / 0.9
			var down := 1.0 - float(y - tops[x]) / 14.0
			var k := clampf(along, 0.0, 1.0) * clampf(down, 0.0, 1.0)
			if k <= 0.02:
				continue
			var cc := c.img.get_pixel(x, y)
			c.px(x, y, cc.lerp(G0, 0.7 * k * k))


## A soft round soot blot of `radius` at `at` (powder smoke round a gun), rising a little.
static func _soot_blot(c: TankPlaceholderArt.Canvas, at: Vector2, radius: float, a: float) -> void:
	for y in range(int(at.y - radius * 1.3), int(at.y + radius * 0.8) + 1):
		for x in range(int(at.x - radius), int(at.x + radius) + 1):
			if not c.solid(x, y):
				continue
			var d := Vector2(float(x) - at.x, (float(y) - at.y) * (0.75 if y < at.y else 1.25))
			var k := 1.0 - d.length() / radius
			if k <= 0.0:
				continue
			c.px(x, y, c.img.get_pixel(x, y).lerp(G0, a * k * k))


## A lit vision slit on the Behemoth at column `x`, `fy` of the way down its column: a dark 11 x 4
## recess with a lit lip above, a fire-orange slit 9 px wide with an amber core inside, and its warm
## spill on the two rows of plate below. Skipped where the armour is not solid round it.
static func _port(c: TankPlaceholderArt.Canvas, x: int, fy: float) -> void:
	var tops := _tops_of(c.img)
	if x < 6 or x >= c.w - 6:
		return
	var y := tops[x] + int(fy * float(c.h - tops[x]))
	for yy in range(y - 3, y + 5):
		for xx in range(x - 6, x + 7):
			if not c.solid(xx, yy):
				return
	c.rect(x - 5, y - 2, 11, 1, G7)
	c.rect(x - 5, y - 1, 11, 4, G0)
	c.rect(x - 4, y, 9, 2, TankPlaceholderArt.F0)
	c.rect(x - 2, y, 5, 1, TankPlaceholderArt.F1)
	c.px(x, y, TankPlaceholderArt.F2)
	for k in 2:
		for xx in range(x - 4, x + 5):
			c.px(
				xx,
				y + 3 + k,
				c.img.get_pixel(xx, y + 3 + k).lerp(TankPlaceholderArt.R2, 0.45 - 0.2 * float(k))
			)


## A glowing engine grille on the Behemoth's rear deck near column `x`: five vertical bars, dark
## between, fire-lit from inside under an amber top row.
static func _grille(c: TankPlaceholderArt.Canvas, x: int) -> void:
	var tops := _tops_of(c.img)
	var y0 := tops[clampi(x, 0, c.w - 1)] + 4
	for xx in range(x - 5, x + 5):
		for yy in range(y0 - 1, y0 + 6):
			if not c.solid(xx, yy):
				return
	c.rect(x - 5, y0 - 1, 10, 7, G0)
	for k in 5:
		var bx := x - 4 + k * 2
		c.rect(bx, y0, 1, 5, TankPlaceholderArt.F0 if k % 2 == 0 else TankPlaceholderArt.R2)
		c.px(bx, y0, TankPlaceholderArt.F1)
	c.rect(x - 5, y0 - 2, 10, 1, G6)


## Every column's first opaque row (the image height for an empty column).
static func _tops_of(img: Image) -> PackedInt32Array:
	var w := img.get_width()
	var h := img.get_height()
	var tops := PackedInt32Array()
	tops.resize(w)
	for x in w:
		tops[x] = h
		for y in h:
			if img.get_pixel(x, y).a > 0.5:
				tops[x] = y
				break
	return tops


## For every column (row) 0 .. n-1, how many of the sorted `seams` are at or before it.
static func _band_index(seams: PackedInt32Array, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(n)
	var k := 0
	for a in n:
		while k < seams.size() and seams[k] <= a:
			k += 1
		out[a] = k
	return out


## Soft soot under each plate's top edge: per plate one or two runs (two only in their own halves of
## a wide plate) at hashed columns at least three pixels inside its seams, 1-3 px wide with a
## half-strength column either side, each starting 2 px under its plate's top and fading linearly
## to nothing over 25-50% of the plate's height.
static func _soot_runs(
	img: Image,
	steel: PackedByteArray,
	row_of: PackedInt32Array,
	xs: PackedInt32Array,
	seed_value: int,
	soot_a: float
) -> void:
	var w := img.get_width()
	var bounds := PackedInt32Array([0])
	bounds.append_array(xs)
	bounds.append(w)
	for p in range(bounds.size() - 1):
		var x0 := bounds[p] + 3
		var x1 := bounds[p + 1] - 3
		if x1 - x0 < 5:
			continue
		# Two runs only in a plate wide enough for both, each in its own half, so they never overlap.
		var runs := 1 + int(_lattice(p, 7, seed_value) * 2.0) if x1 - x0 >= 14 else 1
		var part := float(x1 - x0) / float(runs)
		for n in runs:
			var width := 1 + int(_lattice(p, 17 + n, seed_value) * 3.0)
			var lo := x0 + int(part * float(n)) + 1
			var room := maxi(int(part) - width - 2, 1)
			var cx := lo + int(_lattice(p, 11 + n, seed_value) * float(room))
			var reach := 0.25 + 0.25 * _lattice(p, 23 + n, seed_value)
			for dx in range(-1, width + 1):
				var side := 0.5 if (dx < 0 or dx >= width) else 1.0
				_soot_column(img, steel, row_of, cx + dx, reach, soot_a * side)


## One soot column at `x`: in every plate run of the column, from 2 px under its top downward over
## `reach` of its height, blended toward #07080a from `a` to 0.
static func _soot_column(
	img: Image, steel: PackedByteArray, row_of: PackedInt32Array, x: int, reach: float, a: float
) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if x < 0 or x >= w:
		return
	var y := 0
	while y < h:
		if steel[y * w + x] == 0:
			y += 1
			continue
		var y0 := y
		var y1 := y
		while y1 + 1 < h and steel[(y1 + 1) * w + x] == 1 and row_of[y1 + 1] == row_of[y0]:
			y1 += 1
		var run_len := int(float(y1 - y0 + 1) * reach)
		for d in run_len:
			var yy := y0 + 2 + d
			if yy >= y1:
				break
			var k := a * (1.0 - float(d) / float(maxi(run_len, 1)))
			img.set_pixel(x, yy, img.get_pixel(x, yy).lerp(G0, k))
		y = y1 + 1


## Columns (vertical) or rows (horizontal) where the sprite carries a long seam: at least 40% of the
## column's (row's) steel pixels, and at least 10, stand 0.012 off both neighbours across the line
## the same way (a dark joint or a lit lip). Neighbouring hits within 3 px keep only the strongest,
## and none lies within 4 px of the sprite's edge.
static func _find_seams(
	lum: PackedFloat32Array, steel: PackedByteArray, w: int, h: int, vertical: bool
) -> PackedInt32Array:
	var n_lines := w if vertical else h
	var n_along := h if vertical else w
	var score := PackedFloat32Array()
	score.resize(n_lines)
	for a in range(1, n_lines - 1):
		var on := 0
		var dark := 0
		var lit := 0
		for b in n_along:
			var i := b * w + a if vertical else a * w + b
			if steel[i] == 0:
				continue
			on += 1
			var p := i - 1 if vertical else i - w
			var q := i + 1 if vertical else i + w
			if steel[p] == 0 or steel[q] == 0:
				continue
			if lum[i] < minf(lum[p], lum[q]) - 0.012:
				dark += 1
			elif lum[i] > maxf(lum[p], lum[q]) + 0.012:
				lit += 1
		var best_n := maxi(dark, lit)
		if on >= 10 and best_n >= 10 and float(best_n) / float(on) >= 0.4:
			score[a] = float(best_n) / float(on)
	var out := PackedInt32Array()
	for a in range(4, n_lines - 4):
		if score[a] <= 0.0:
			continue
		var best := true
		for d in range(-3, 4):
			var b := a + d
			if d != 0 and (score[b] > score[a] or (score[b] == score[a] and b < a)):
				best = false
		if best:
			out.append(a)
	return out


## `xs` with extra seams so no plate is wider than `max_w` (each gap split evenly).
static func _fill_gaps(xs: PackedInt32Array, w: int, max_w: int) -> PackedInt32Array:
	var bounds := PackedInt32Array([0])
	bounds.append_array(xs)
	bounds.append(w)
	var out := PackedInt32Array()
	for i in range(bounds.size() - 1):
		var a := bounds[i]
		var b := bounds[i + 1]
		if i > 0:
			out.append(a)
		var parts := ceili(float(b - a) / float(max_w))
		for k in range(1, parts):
			out.append(a + roundi(float(b - a) * float(k) / float(parts)))
	return out


static func _max_plate(id: String) -> int:
	for prefix: String in MAX_PLATE_W:
		if id.begins_with(prefix):
			return int(MAX_PLATE_W[prefix])
	return 32


## The tone offset of plate `cell`: one of four steps across PLATE_SPREAD.
static func _plate_offset(cell: Vector2i, seed_value: int) -> float:
	var step := int(_lattice(cell.x, cell.y, seed_value + 31) * 4.0)
	return (float(step) / 3.0 - 0.5) * PLATE_SPREAD


## The steel colour of luminance `l` on the art.json grey ramp (#07080a .. #666869), interpolated
## between the two nearest greys, so plates keep the palette's slight cool cast.
static func _ramp_colour(l: float) -> Color:
	var ramp: Array[Color] = [G0, G1, G2, G3, G4, G5, G6, G7, G8]
	if l <= ramp[0].get_luminance():
		return ramp[0]
	for k in range(1, ramp.size()):
		var lo := ramp[k - 1].get_luminance()
		var hi := ramp[k].get_luminance()
		if l <= hi:
			return ramp[k - 1].lerp(ramp[k], (l - lo) / maxf(hi - lo, 0.0001))
	return ramp[ramp.size() - 1]


## True when (x, y) lies on a thin run of at least five like pixels (within 0.03 of it and off the
## plate tone `m` the same way) along its row, with unlike pixels above and below: a hatch outline or
## a lit lip, not a scratch, a streak, dust or the inside of a lighter patch.
static func _line_pixel(
	lum: PackedFloat32Array, steel: PackedByteArray, w: int, h: int, x: int, y: int, m: float
) -> bool:
	var l := lum[y * w + x]
	var sgn := signf(l - m)
	# Only horizontal lines: the generated art's vertical marks are streaks, and the details pass
	# draws every vertical seam itself.
	for axis in 1:
		var run := 1
		for side: int in [-1, 1]:
			for d in range(1, 5):
				var xx := x + side * d * (1 - axis)
				var yy := y + side * d * axis
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					break
				var j := yy * w + xx
				if steel[j] == 0 or absf(lum[j] - l) > 0.03 or signf(lum[j] - m) != sgn:
					break
				run += 1
		if run < 5:
			continue
		# A line is thin and stands out: one pixel either side across it differs from it by more
		# than DETAIL_LUM (so speckle between two close greys is never kept as a line).
		var thin := true
		for side: int in [-1, 1]:
			var xx := x + side * axis
			var yy := y + side * (1 - axis)
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var j := yy * w + xx
			if steel[j] == 1 and absf(lum[j] - l) <= DETAIL_LUM:
				thin = false
		if thin:
			return true
	return false


## A smooth 0 .. 1 value noise (bilinear between hashed lattice points `cell` px apart).
static func smooth_noise(x: int, y: int, cell: float, salt: int) -> float:
	var fx := float(x) / cell
	var fy := float(y) / cell
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - float(ix)
	var ty := fy - float(iy)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _lattice(ix, iy, salt)
	var b := _lattice(ix + 1, iy, salt)
	var c := _lattice(ix, iy + 1, salt)
	var d := _lattice(ix + 1, iy + 1, salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


static func _lattice(x: int, y: int, salt: int) -> float:
	var n := (x * 374761393 + y * 668265263 + salt * 1274126177) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65536.0
