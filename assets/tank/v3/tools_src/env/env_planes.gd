extends SceneTree
# Bakes the v3 night-forest planes into assets/tank/v3/planes/ at the moderate tilt-shift Simon chose
# (--only=strong|extreme writes those strengths into build/v3planes/ for comparison). Sources: the v2
# far and foreground planes, kept in tools_src/src/.
#   far        the v2 far plane (sky, Milky Way, mountains) regraded blue-green, the reference's baked
#              warm light neutralised
#   ridge      a distant pine ridge in mist (new, procedural)
#   forest     the pine forest along the road: two rows of pines, gaps, undergrowth (new, procedural)
#   verge      the road's far edge: grass, ferns, rocks, stumps, saplings (new, procedural, sharp)
#   foreground the v2 foreground regraded and blurred further
# Tilt-shift: every plane gets a per-row blur = its depth base + a ramp with the distance (stage y)
# from the focus band, so everything above and below the road/tank band blurs progressively more.
# Run (Git Bash, repo root):  bash assets/tank/v3/tools_src/env_regen.sh

const W := 1920
const OUT := "res://assets/tank/v3/planes/"
const V2 := "res://assets/tank/v3/tools_src/src/"
## The sharp band (stage y) the baked ramp is measured from.
const BAND := Vector2(150.0, 352.0)
## Per strength: ramp max radius (box px), ramp length (px), each plane's depth base radius.
const STRENGTHS := {
	"moderate":
	{
		"maxr": 2.5,
		"ramp": 130.0,
		"far": 1.2,
		"ridge": 0.8,
		"forest": 0.25,
		"verge": 0.0,
		"near": 0.4,
		"fg": 1.0
	},
	"strong":
	{
		"maxr": 4.5,
		"ramp": 110.0,
		"far": 2.2,
		"ridge": 1.6,
		"forest": 0.6,
		"verge": 0.0,
		"near": 0.8,
		"fg": 2.5
	},
	"extreme":
	{
		"maxr": 7.5,
		"ramp": 90.0,
		"far": 3.5,
		"ridge": 2.6,
		"forest": 1.0,
		"verge": 0.0,
		"near": 1.2,
		"fg": 4.5
	},
}
## r2: the far plane gets this much more sky on top (mirrored from its own top rows), so the
## layout can drop the road and the tank lower without a seam over the sky.
const SKY_EXTRA := 80
## r2: the road's near edge (stage y, wavy round it): the near shoulder plane and the foreground's
## alpha follow it, so the road fades into the foreground without a straight seam.
const NEAR_EDGE := 377.0
## Planes: stage y0 and height.
const PLANES := {
	"far": Vector2i(-SKY_EXTRA, 330 + SKY_EXTRA),
	"ridge": Vector2i(0, 342),
	"forest": Vector2i(0, 352),
	"verge": Vector2i(296, 112),
	"near": Vector2i(356, 74),
	"foreground": Vector2i(344, 196),
}

# Night grade (blue-green).
const TINT := Color(0.42, 1.0, 1.12)
const LIFT := Color(0.0, 0.01, 0.016)
# Ridge.
const RIDGE_BODY := Color(0.04, 0.09, 0.1)
const RIDGE_HAZE := Color(0.07, 0.14, 0.15)
const MIST := Color(0.1, 0.18, 0.19)
# Forest.
const PINE := Color(0.017, 0.036, 0.04)
const PINE_GREEN := Color(0.02, 0.045, 0.036)
const PINE_RIM := Color(0.07, 0.13, 0.135)
const PINE_SHADE := Color(0.008, 0.02, 0.024)
const TRUNK := Color(0.03, 0.03, 0.032)
const SCRUB := Color(0.02, 0.04, 0.036)
# Verge.
const GRASS := Color(0.035, 0.07, 0.052)
const GRASS_TIP := Color(0.1, 0.16, 0.12)
const FERN := Color(0.03, 0.075, 0.05)
const ROCK := Color(0.075, 0.088, 0.09)
const ROCK_TOP := Color(0.16, 0.2, 0.2)
const ROCK_DK := Color(0.03, 0.035, 0.038)
const STUMP := Color(0.07, 0.056, 0.046)
const STUMP_TOP := Color(0.17, 0.15, 0.12)

var rng := RandomNumberGenerator.new()
## The far plane's stars [x, y, intensity, Color], taken out before its blur and put back as
## bokeh discs sized by the blur at their row (a tilt-shift lens turns them into soft discs).
var stars: Array = []


func _init() -> void:
	rng.seed = 3003
	var t0 := Time.get_ticks_msec()
	var raw := {
		"far": _far(),
		"ridge": _ridge(),
		"forest": _forest(),
		"verge": _verge(),
		"foreground": _foreground(),
		"near": _near(),
	}
	print("env_planes: raw planes in %d ms" % (Time.get_ticks_msec() - t0))
	var only := "moderate"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for sname: String in STRENGTHS:
		if only != "" and sname != only:
			continue
		var st: Dictionary = STRENGTHS[sname]
		# v3 production: the moderate strength straight into planes/ (the others into build/)
		var dir := ProjectSettings.globalize_path(OUT if sname == "moderate" else "res://build/v3planes/" + sname)
		DirAccess.make_dir_recursive_absolute(dir)
		var imgs := {}
		for pname: String in raw:
			var g: Vector2i = PLANES[pname]
			var radii := PackedFloat32Array()
			radii.resize(g.y)
			for y in g.y:
				radii[y] = _radius(st, pname, float(g.x + y))
			var b := _blur_rows(raw[pname], W, g.y, radii, pname != "foreground" and pname != "far")
			if pname == "far":
				_bokeh(b, g.y, radii)
			var img := _to_img(b, W, g.y)
			img.save_png(dir + "/" + pname + ".png")
			imgs[pname] = img
		_preview(imgs, ProjectSettings.globalize_path("res://build/v3planes_preview_%s.png" % sname))
		print("env_planes: %s done (%d ms)" % [sname, Time.get_ticks_msec() - t0])
	quit()


## The blur radius (box px) of a plane's row at stage y.
func _radius(st: Dictionary, pname: String, y: float) -> float:
	var d := maxf(BAND.x - y, y - BAND.y)
	var k := clampf(d / float(st["ramp"]), 0.0, 1.0)
	var base := float(st["fg" if pname == "foreground" else pname])
	if pname == "verge":
		return base + k * k * float(st["maxr"]) * 0.5
	if pname == "near":
		# graded: sharp where it meets the road, softer row by row toward the viewer
		return base + clampf((y - NEAR_EDGE + 4.0) / 40.0, 0.0, 1.0) * float(st["maxr"]) * 0.8
	return base + pow(k, 1.3) * float(st["maxr"])


# --- Grade ----------------------------------------------------------------------------------------------


## The v3 night grade: towards a blue-green luminance tint; warm baked light (the reference's
## headlight on trees and rocks) neutralised so no light without a source stays in the planes.
static func grade(c: Color, amount: float = 0.7) -> Color:
	var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
	var warm := clampf((c.r - c.b) * 5.0 - 0.05, 0.0, 1.0)
	var target := Color(l * TINT.r + LIFT.r, l * TINT.g + LIFT.g, l * TINT.b + LIFT.b)
	target = target.darkened(0.35 * warm)
	var out := c.lerp(target, clampf(amount + 0.3 * warm, 0.0, 1.0))
	out.a = c.a
	return out


func _graded(img: Image, amount: float) -> PackedFloat32Array:
	var f := _to_f(img)
	for i in f.size() / 4:
		var c := Color(f[i * 4], f[i * 4 + 1], f[i * 4 + 2], f[i * 4 + 3])
		var g := grade(c, amount)
		f[i * 4] = g.r
		f[i * 4 + 1] = g.g
		f[i * 4 + 2] = g.b
	return f


func _far() -> PackedFloat32Array:
	var src := Image.load_from_file(ProjectSettings.globalize_path(V2 + "far_wide.png"))
	src.convert(Image.FORMAT_RGBA8)
	var img := Image.create(W, src.get_height() + SKY_EXTRA, false, Image.FORMAT_RGBA8)
	img.blit_rect(src, Rect2i(0, 0, W, src.get_height()), Vector2i(0, SKY_EXTRA))
	var top := src.get_region(Rect2i(0, 0, W, SKY_EXTRA))
	top.flip_y()
	img.blit_rect(top, Rect2i(0, 0, W, SKY_EXTRA), Vector2i.ZERO)
	var h := img.get_height()
	var f := _to_f(img)
	# take the stars out (a pixel well above its 5 x 5 neighbourhood, in the sky)
	var lum := PackedFloat32Array()
	lum.resize(W * h)
	for i in W * h:
		lum[i] = f[i * 4] * 0.3 + f[i * 4 + 1] * 0.55 + f[i * 4 + 2] * 0.15
	var fill := {}
	for y in range(2, 250 + SKY_EXTRA):
		for x in W:
			var c := lum[y * W + x]
			if c < 0.12:
				continue
			var m := 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					m += lum[(y + dy) * W + posmod(x + dx, W)]
			m = (m - c) / 24.0
			if c - m > 0.09:
				var i := (y * W + x) * 4
				stars.append([x, y, c - m, Color(f[i], f[i + 1], f[i + 2])])
				fill[y * W + x] = m
	for k: int in fill:
		var mm: float = fill[k]
		f[k * 4] = mm * 0.45
		f[k * 4 + 1] = mm * 1.05
		f[k * 4 + 2] = mm * 1.2
	print("env_planes: %d stars" % stars.size())
	for i in W * h:
		var c2 := Color(f[i * 4], f[i * 4 + 1], f[i * 4 + 2], f[i * 4 + 3])
		var g := grade(c2, 0.75)
		var y2 := i / W
		# a little more light in the sky, a teal glow low over the mountains
		var gain := 1.18 + 0.25 * exp(-pow((float(y2) - 215.0) / 55.0, 2.0))
		f[i * 4] = g.r * gain
		f[i * 4 + 1] = g.g * gain
		f[i * 4 + 2] = g.b * gain
	return f


## The stars put back after the blur: a 1 px point where the plane is sharp, else a soft disc whose
## radius follows the row's blur and whose brightness spreads over it (never quite vanishing).
func _bokeh(f: PackedFloat32Array, h: int, radii: PackedFloat32Array) -> void:
	for s: Array in stars:
		var x: int = s[0]
		var y: int = s[1]
		var k: float = s[2]
		var col: Color = (s[3] as Color).lerp(Color(0.75, 0.95, 1.0), 0.4)
		var r := radii[y] * 0.95
		if r < 0.9:
			_add(f, h, x, y, col, k * 2.2)
			continue
		if k < 0.13 and r > 3.0:
			continue
		var peak := clampf(k * 1.8 / (1.0 + 0.4 * r * r), 0.03, 0.35)
		var ri := int(ceilf(r))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var d := sqrt(float(dx * dx + dy * dy))
				if d > r + 0.5:
					continue
				var edge := clampf(r + 0.5 - d, 0.0, 1.0)
				var rim := 1.0 + 0.35 * smoothstep(r - 1.5, r, d)
				_add(f, h, x + dx, y + dy, col, peak * edge * rim)


func _add(f: PackedFloat32Array, h: int, x: int, y: int, c: Color, a: float) -> void:
	if y < 0 or y >= h:
		return
	var i := (y * W + posmod(x, W)) * 4
	for k in 3:
		f[i + k] = minf(f[i + k] + c[k] * a, 1.0)


func _foreground() -> PackedFloat32Array:
	var f := _graded(
		Image.load_from_file(ProjectSettings.globalize_path(V2 + "foreground_wide.png")), 0.8
	)
	var y0: int = PLANES["foreground"].x
	var h: int = PLANES["foreground"].y
	for i in f.size() / 4:
		for c in 3:
			f[i * 4 + c] *= 1.05
	# r2: the alpha follows the near edge, wavy, and ramps over 26 rows (no straight seam)
	for x in W:
		var e := _edge(x) + 5.0
		for y in h:
			var sy := float(y0 + y)
			var a := smoothstep(e - 2.0, e + 26.0, sy)
			var i2 := (y * W + x) * 4 + 3
			f[i2] = minf(f[i2], a) if sy < e + 26.0 else f[i2]
	return f


## The road's near edge (stage y) at tile column x: wavy, a little ragged.
func _edge(x: int) -> float:
	var a := TAU * float(x) / W
	return (
		NEAR_EDGE
		+ 3.5 * sin(a * 9.0 + 0.6)
		+ 2.0 * sin(a * 31.0 + 2.0)
		+ 1.5 * (_hash(x * 0.37) - 0.5)
	)


## r2: the road's near shoulder, between the road band and the foreground: dark earth and grass
## under a wavy edge, grass tufts and stones crossing up over the gravel's near rows, fading out
## below into the foreground (whose blur it shares toward the bottom).
func _near() -> PackedFloat32Array:
	var y0: int = PLANES["near"].x
	var h: int = PLANES["near"].y
	var f := _new(h)
	for x in W:
		var e := int(roundf(_edge(x))) - y0
		for y in range(e, h):
			var k := float(y - e) / 30.0
			var c := GRASS.darkened(0.45).lerp(Color(0.01, 0.018, 0.02), clampf(k, 0.0, 1.0))
			c.a = 1.0 - smoothstep(0.6, 1.0, k * 0.75)
			_put(f, h, x, y, c)
		# the edge itself: crumbled gravel, darker under the grass
		_put(f, h, x, e - 1, Color(0.05, 0.06, 0.055, 0.7))
		# grass rising over the road's near rows
		var tuft := _hash(floorf(x / 4.0) * 5.3)
		var gh := int(2.0 + 9.0 * tuft * _hash(x * 1.7 + 2.0))
		if _hash(x * 0.9) < 0.3:
			gh = int(gh * 0.3)
		for k2 in gh:
			var lean := 0 if k2 < gh / 2 else (1 if _hash(x + 0.25) > 0.5 else -1)
			var col := GRASS.darkened(0.2) if k2 < gh - 2 else GRASS.lerp(GRASS_TIP, 0.6)
			_put(f, h, x + lean, e - 1 - k2, col)
	# stones and clods sitting on the edge, half over the gravel
	var x := rng.randf_range(0.0, 40.0)
	while x < W:
		var cx := int(x)
		_rock(
			f, h, cx, int(roundf(_edge(cx))) - y0 + 2, rng.randi_range(4, 9), rng.randi_range(3, 5)
		)
		x += rng.randf_range(30.0, 100.0)
	x = rng.randf_range(0.0, 60.0)
	while x < W:
		var fx := int(x)
		_fern(f, h, fx, int(roundf(_edge(fx))) - y0, rng.randi_range(6, 11))
		x += rng.randf_range(50.0, 120.0)
	return f


# --- Painting helpers ------------------------------------------------------------------------------------


func _new(h: int) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(W * h * 4)
	f.fill(0.0)
	return f


## `c` over the pixel (x wraps round the tile).
func _put(f: PackedFloat32Array, h: int, x: int, y: int, c: Color) -> void:
	if y < 0 or y >= h:
		return
	var i := (y * W + posmod(x, W)) * 4
	var a := c.a
	var da := f[i + 3]
	var oa := a + da * (1.0 - a)
	if oa <= 0.0:
		return
	for k in 3:
		f[i + k] = (c[k] * a + f[i + k] * da * (1.0 - a)) / oa
	f[i + 3] = oa


func _hash(n: float) -> float:
	var s := sin(n * 12.9898 + 78.233) * 43758.5453
	return s - floorf(s)


## A pixel pine (spruce-like): a 1 px leader leaning a little, tiers of drooping branches whose
## left and right lengths vary per tier, ragged edges, dark holes inside the crown, sparse cool
## highlights on the sky side and shade on the other, branch tips hanging below each tier, and a
## short trunk under the lowest tier.
func _pine(
	f: PackedFloat32Array,
	h: int,
	cx: int,
	base: int,
	ht: int,
	wd: float,
	body: Color,
	rim: Color,
	shade: Color,
	seed_v: float
) -> void:
	var top := base - ht
	var crown := int(ht * 0.95)
	var tiers := 5 + int(ht / 20.0)
	var lean := (_hash(seed_v * 1.1) - 0.5) * 0.05
	var slim := 0.8 + 0.4 * _hash(seed_v * 2.3)
	for row in crown:
		var t := float(row) / float(crown)
		var tf := t * tiers
		var tier := int(tf)
		var u := tf - tier
		var env := wd * 0.5 * slim * (0.06 + 0.94 * pow(t, 0.9))
		var prof := 0.4 + 0.6 * pow(u, 0.65)
		var sl := 0.7 + 0.5 * _hash(seed_v + tier * 3.1)
		var sr := 0.7 + 0.5 * _hash(seed_v + tier * 5.7 + 1.0)
		var jl := (_hash(seed_v + row * 1.7) - 0.5) * 2.0 * t
		var jr := (_hash(seed_v + row * 2.9 + 0.3) - 0.5) * 2.0 * t
		var c0 := cx + lean * float(ht - row)
		var hl := env * prof * sl + jl
		var hr := env * prof * sr + jr
		if row < 2:
			hl = 0.0
			hr = 0.0
		var y := top + row
		var x0 := int(roundf(c0 - hl))
		var x1 := int(roundf(c0 + hr))
		var mid := roundf(c0)
		for x in range(x0, x1 + 1):
			var c := body
			var hx := _hash(seed_v * 0.7 + x * 1.31 + row * 0.173)
			if x == x0 and u > 0.45 and hx > 0.35:
				c = rim
			elif x - x0 == 1 and u > 0.75 and hx > 0.7:
				c = body.lerp(rim, 0.45)
			elif x > mid + (x1 - mid) * 0.45:
				c = shade if hx > 0.35 or x >= x1 - 1 else body
			elif u > 0.2 and u < 0.85 and hx > 0.93 and x > x0 + 1:
				c = shade
			_put(f, h, x, y, c)
		# branch tips hanging below a tier's outer ends
		if u > 0.85 and hl + hr > 6.0:
			var dl := 1 + int(_hash(seed_v + tier * 7.7) * 2.0)
			var dr := 1 + int(_hash(seed_v + tier * 9.1) * 2.0)
			for k in dl:
				_put(f, h, x0 + k, y + 1 + k, body if k == 0 else shade)
			for k in dr:
				_put(f, h, x1 - k, y + 1 + k, shade)
	for row in range(crown, ht):
		var y := top + row
		var tw := 1 if ht < 90 else 2
		for x in range(cx - tw / 2, cx - tw / 2 + tw):
			_put(f, h, x, y, TRUNK)


# --- Ridge ---------------------------------------------------------------------------------------------


## A distant pine ridge: a hill body under an undulating crest, tiny pines on and in front of the
## crest, the whole thing hazier lower down where the ground mist lies.
func _ridge() -> PackedFloat32Array:
	var h: int = PLANES["ridge"].y
	var f := _new(h)
	var crest := PackedFloat32Array()
	crest.resize(W)
	for x in W:
		var a := TAU * float(x) / W
		crest[x] = (
			262.0 + 16.0 * sin(a * 2.0 + 0.4) + 9.0 * sin(a * 5.0 + 1.3) + 4.0 * sin(a * 11.0 + 2.1)
		)
	for x in W:
		for y in range(int(crest[x]), h):
			var k := clampf((float(y) - crest[x]) / 70.0, 0.0, 1.0)
			_put(f, h, x, y, RIDGE_BODY.lerp(RIDGE_HAZE, 0.3 + 0.5 * k))
	# pines along the crest and down the slope
	var x := 0.0
	while x < W:
		var cx := int(x)
		var ht := int(rng.randf_range(16.0, 46.0))
		var base := int(crest[cx] + rng.randf_range(4.0, 26.0))
		var haze := clampf((float(base) - 262.0) / 90.0, 0.0, 0.7)
		var body := RIDGE_BODY.darkened(0.15).lerp(RIDGE_HAZE, haze)
		_pine(
			f,
			h,
			cx,
			base,
			ht,
			ht * 0.42,
			body,
			body.lerp(MIST, 0.35),
			body.darkened(0.25),
			x * 0.37
		)
		x += rng.randf_range(4.0, 11.0)
	_mist(f, h, 262.0, 324.0, 0.5)
	return f


## A band of ground mist from y0 (clear) to y1 (densest `a`), wavy in thickness.
func _mist(f: PackedFloat32Array, h: int, y0: float, y1: float, a: float) -> void:
	for x in W:
		var wob := 6.0 * sin(TAU * x / W * 7.0 + 0.8) + 4.0 * sin(TAU * x / W * 17.0)
		for y in range(int(y0), mini(int(y1) + 1, h)):
			var k := clampf((float(y) - y0 - wob) / (y1 - y0), 0.0, 1.0)
			if k <= 0.0:
				continue
			_put(f, h, x, y, Color(MIST.r, MIST.g, MIST.b, a * k * k))


# --- Forest --------------------------------------------------------------------------------------------


## The pine forest along the road: a back row of mid-sized pines in thin mist, then the big pines
## standing in clumps with gaps (the ridge and the sky show through), a few taller ones, and dark
## undergrowth along the bottom that the verge plane sits on.
func _forest() -> PackedFloat32Array:
	var h: int = PLANES["forest"].y
	var f := _new(h)
	var x := 0.0
	while x < W:
		var ht := int(rng.randf_range(70.0, 140.0))
		var base := int(rng.randf_range(322.0, 334.0))
		var body := PINE.lerp(RIDGE_BODY, 0.45)
		_pine(
			f,
			h,
			int(x),
			base,
			ht,
			ht * 0.36,
			body,
			body.lerp(PINE_RIM, 0.6),
			body.darkened(0.3),
			x * 0.11
		)
		x += rng.randf_range(9.0, 22.0)
	_mist(f, h, 270.0, 326.0, 0.2)
	x = 0.0
	while x < W:
		# a clump of 2-6 big pines, then a gap
		var n := rng.randi_range(2, 6)
		for i in n:
			var ht := int(rng.randf_range(115.0, 215.0))
			if rng.randf() < 0.12:
				ht = int(rng.randf_range(230.0, 270.0))
			var base := int(rng.randf_range(336.0, 346.0))
			var body := PINE if rng.randf() < 0.65 else PINE_GREEN
			_pine(f, h, int(x), base, ht, ht * 0.34, body, PINE_RIM, PINE_SHADE, x * 0.53 + i)
			x += rng.randf_range(16.0, 34.0)
		x += rng.randf_range(30.0, 110.0)
	# undergrowth along the bottom: bushes of round heads (4-13 px) packed along y 336, so the
	# forest floor has an organic top line
	var top := PackedFloat32Array()
	top.resize(W)
	top.fill(337.0)
	var bx := 0.0
	while bx < W:
		var r := rng.randf_range(6.0, 16.0)
		var cy := 335.0 + rng.randf_range(-1.0, 3.0)
		for dx in range(-int(r), int(r) + 1):
			var hh := sqrt(maxf(r * r - float(dx * dx), 0.0))
			var xi := posmod(int(bx) + dx, W)
			top[xi] = minf(top[xi], cy - hh)
		bx += rng.randf_range(r * 0.6, r * 1.6)
	for xx in W:
		var t0 := roundf(top[xx])
		for y in range(int(t0), h):
			var c := SCRUB.lerp(PINE_SHADE, clampf((y - t0) / 10.0, 0.0, 1.0))
			if y == int(t0) and _hash(xx * 1.9) > 0.55:
				c = SCRUB.lerp(PINE_RIM, 0.45)
			elif y == int(t0) + 1 and _hash(xx * 2.7) > 0.8:
				c = SCRUB.lerp(PINE_RIM, 0.25)
			_put(f, h, xx, y, c)
	return f


# --- Verge ---------------------------------------------------------------------------------------------


## The road's far edge (sharp, in the focus band): grass in tufts with a few lit tips, ferns, rocks
## with a cool top light, stumps with a pale cut top, small pines, a fallen log now and then.
func _verge() -> PackedFloat32Array:
	var y0: int = PLANES["verge"].x
	var h: int = PLANES["verge"].y
	var f := _new(h)
	var edge := 334 - y0
	# saplings first (behind)
	var x := rng.randf_range(0.0, 60.0)
	while x < W:
		var ht := int(rng.randf_range(16.0, 34.0))
		_pine(
			f,
			h,
			int(x),
			edge + rng.randi_range(-1, 2),
			ht,
			ht * 0.5,
			PINE_GREEN,
			PINE_RIM,
			PINE_SHADE,
			x
		)
		x += rng.randf_range(120.0, 320.0)
	# rocks
	x = rng.randf_range(0.0, 80.0)
	while x < W:
		_rock(f, h, int(x), edge + 2, rng.randi_range(4, 11), rng.randi_range(3, 7))
		x += rng.randf_range(70.0, 210.0)
	# stumps and a log
	x = rng.randf_range(100.0, 200.0)
	while x < W:
		if rng.randf() < 0.3:
			_log(f, h, int(x), edge + 1, rng.randi_range(22, 40))
		else:
			_stump(f, h, int(x), edge + 1, rng.randi_range(5, 8), rng.randi_range(4, 9))
		x += rng.randf_range(240.0, 480.0)
	# ferns
	x = rng.randf_range(0.0, 40.0)
	while x < W:
		_fern(f, h, int(x), edge + 1, rng.randi_range(5, 10))
		x += rng.randf_range(26.0, 70.0)
	# the near ground under the road's near edge (the road band fades out over it): dark earth
	# with grass along its top, darker downwards, under the foreground
	for xx in W:
		var ny := 357 - y0 + int(roundf(1.5 * sin(TAU * xx / W * 13.0) + _hash(xx * 0.37)))
		for y in range(ny, h):
			var k := clampf(float(y - ny) / 30.0, 0.0, 1.0)
			_put(f, h, xx, y, GRASS.darkened(0.35).lerp(Color(0.012, 0.02, 0.02), k))
		var gh := int(_hash(xx * 1.13) * 4.0)
		for kk in gh:
			_put(f, h, xx, ny - 1 - kk, GRASS if kk < gh - 1 else GRASS.lerp(GRASS_TIP, 0.5))
	# grass everywhere along the edge, a few blades leaning out over the gravel
	for xx in W:
		var tuft := _hash(float(int(xx / 5)) * 3.7)
		var ht := int(1.0 + 7.0 * tuft * _hash(xx * 0.91 + 4.0))
		if _hash(xx * 2.3) < 0.25:
			ht = 0
		for k in ht:
			var lean := 0 if k < ht / 2 else (1 if _hash(xx + 0.5) > 0.5 else -1)
			var c := GRASS if k < ht - 1 else (GRASS_TIP if _hash(xx * 5.1) > 0.75 else GRASS)
			_put(f, h, xx + lean, edge + 2 - k, c)
		_put(f, h, xx, edge + 3, Color(GRASS.r, GRASS.g, GRASS.b, 0.6))
	return f


func _rock(f: PackedFloat32Array, h: int, cx: int, foot: int, rw: int, rh: int) -> void:
	for dy in rh:
		var t := float(dy) / float(rh)
		var hw := int(roundf(rw * sqrt(1.0 - (1.0 - t) * (1.0 - t)) * 0.5 + 1.0))
		var y := foot - rh + dy
		for x in range(cx - hw, cx + hw + 1):
			var c := ROCK
			if dy == 0 or (dy == 1 and x < cx):
				c = ROCK_TOP
			elif x > cx + hw - 2:
				c = ROCK_DK
			elif _hash(x * 1.3 + y * 0.7) > 0.86:
				c = ROCK_DK
			_put(f, h, x, y, c)
	for x in range(cx - rw / 2 - 2, cx + rw / 2 + 3):
		_put(f, h, x, foot, Color(0, 0, 0, 0.55))


func _stump(f: PackedFloat32Array, h: int, cx: int, foot: int, sw: int, sh: int) -> void:
	for dy in sh:
		for dx in sw:
			var c := STUMP if dx > 0 else STUMP.lightened(0.15)
			if dx == sw - 1:
				c = STUMP.darkened(0.4)
			_put(f, h, cx + dx, foot - sh + dy, c)
	for dx in sw:
		_put(f, h, cx + dx, foot - sh, STUMP_TOP if dx > 0 and dx < sw - 1 else STUMP)
	_put(f, h, cx - 1, foot - 1, STUMP)
	_put(f, h, cx + sw, foot - 1, STUMP.darkened(0.3))


func _log(f: PackedFloat32Array, h: int, x0: int, foot: int, lw: int) -> void:
	for dx in lw:
		for dy in 4:
			var c := STUMP if dy > 0 else STUMP.lightened(0.12)
			if dy == 3:
				c = STUMP.darkened(0.45)
			_put(f, h, x0 + dx, foot - 4 + dy, c)
	for dy in 4:
		_put(f, h, x0 + lw, foot - 4 + dy, STUMP_TOP if dy in [1, 2] else STUMP)


func _fern(f: PackedFloat32Array, h: int, cx: int, foot: int, s: int) -> void:
	for side: int in [-1, 1]:
		for k in s:
			var t := float(k) / float(s)
			var px := cx + side * k
			var py := foot - int(roundf(s * 0.7 * sin(t * PI * 0.85)))
			_put(f, h, px, py, FERN if k < s - 2 else GRASS_TIP.lerp(FERN, 0.5))
			if k % 2 == 0:
				_put(f, h, px, py + 1, FERN.darkened(0.3))
	for k in s / 2:
		_put(f, h, cx, foot - k, FERN)


# --- Blur, conversion, preview -------------------------------------------------------------------------


## Two passes of a separable box blur whose radius varies per row (`radii`, fractional radii blend
## the two neighbouring integer boxes); alpha-premultiplied; `wrap` the rows round the tile.
func _blur_rows(
	src: PackedFloat32Array, w: int, h: int, radii: PackedFloat32Array, _wrap: bool
) -> PackedFloat32Array:
	var any := false
	for r in radii:
		if r > 0.05:
			any = true
	if not any:
		return src
	var ch: Array[PackedFloat32Array] = []
	for c in 4:
		var m := PackedFloat32Array()
		m.resize(w * h)
		ch.append(m)
	for i in w * h:
		var a := src[i * 4 + 3]
		ch[0][i] = src[i * 4] * a
		ch[1][i] = src[i * 4 + 1] * a
		ch[2][i] = src[i * 4 + 2] * a
		ch[3][i] = a
	for c in 4:
		for _p in 2:
			ch[c] = _hpass(ch[c], w, h, radii)
			ch[c] = _vpass(ch[c], w, h, radii)
	var out := PackedFloat32Array()
	out.resize(src.size())
	for i in w * h:
		var a := ch[3][i]
		out[i * 4 + 3] = a
		if a > 0.0001:
			out[i * 4] = ch[0][i] / a
			out[i * 4 + 1] = ch[1][i] / a
			out[i * 4 + 2] = ch[2][i] / a
	return out


func _hpass(m: PackedFloat32Array, w: int, h: int, radii: PackedFloat32Array) -> PackedFloat32Array:
	var out := m.duplicate()
	var pre := PackedFloat32Array()
	for y in h:
		var r := radii[y]
		if r <= 0.05:
			continue
		var k0 := int(floorf(r))
		var fr := r - k0
		var kk := k0 + 1
		pre.resize(w + 2 * kk + 2)
		var row := y * w
		pre[0] = 0.0
		for i in w + 2 * kk + 1:
			pre[i + 1] = pre[i] + m[row + posmod(i - kk, w)]
		for x in w:
			# window [x - k, x + k] -> pre indexes (x - k + kk) .. (x + k + kk + 1)
			var b0 := (pre[x + k0 + kk + 1] - pre[x - k0 + kk]) / float(2 * k0 + 1)
			var b1 := (pre[x + kk + kk + 1] - pre[x]) / float(2 * kk + 1)
			out[row + x] = lerpf(b0, b1, fr)
	return out


func _vpass(m: PackedFloat32Array, w: int, h: int, radii: PackedFloat32Array) -> PackedFloat32Array:
	var out := m.duplicate()
	var pre := PackedFloat32Array()
	pre.resize(h + 1)
	for x in w:
		pre[0] = 0.0
		for y in h:
			pre[y + 1] = pre[y] + m[y * w + x]
		for y in h:
			var r := radii[y]
			if r <= 0.05:
				continue
			var k0 := int(floorf(r))
			var fr := r - k0
			var a0 := maxi(y - k0, 0)
			var e0 := mini(y + k0, h - 1)
			var b0 := (pre[e0 + 1] - pre[a0]) / float(e0 - a0 + 1)
			var a1 := maxi(y - k0 - 1, 0)
			var e1 := mini(y + k0 + 1, h - 1)
			var b1 := (pre[e1 + 1] - pre[a1]) / float(e1 - a1 + 1)
			out[y * w + x] = lerpf(b0, b1, fr)
	return out


func _to_f(img: Image) -> PackedFloat32Array:
	img.convert(Image.FORMAT_RGBA8)
	var b := img.get_data()
	var f := PackedFloat32Array()
	f.resize(b.size())
	for i in b.size():
		f[i] = b[i] / 255.0
	return f


func _to_img(f: PackedFloat32Array, w: int, h: int) -> Image:
	var b := PackedByteArray()
	b.resize(f.size())
	for i in f.size():
		b[i] = clampi(int(roundf(f[i] * 255.0)), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, b)


## A 960 x 540 composite of the first tile (no road band, no tank) to review the planes.
func _preview(imgs: Dictionary, path: String) -> void:
	var comp := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	comp.fill(Color(0.016, 0.03, 0.035))
	for pname: String in ["far", "ridge", "forest", "verge", "near", "foreground"]:
		var img: Image = imgs[pname]
		var g: Vector2i = PLANES[pname]
		comp.blend_rect(img, Rect2i(0, 0, 960, g.y), Vector2i(0, g.x + 40))
	comp.save_png(path)
