class_name TankMechKit
extends RefCounted
## What every machine of TankMech paints with: its size and part ratios, the palette, the room, the Canvas.
## TankMech and each TankMech<Machine> extend this, so all of it resolves unqualified in them, and outsiders
## keep reading it as TankMech.W, TankMech.in_band and so on.

const W := 112
const H := 64
## The main rotating part of each machine, in revolutions per crank revolution.
const RATIO := {"diesel": 2.0, "dynamo": 3.0, "steam": 1.0, "arc": 1.0, "feed": 1.0, "repair": 1.0}
## Every animated part per crank revolution (all integers: one crank revolution loops seamlessly).
const PARTS := {
	"diesel":
	{
		"crankshaft_and_flywheel_revs": 2,
		"firings_and_stack_puffs": 3,
		"gearbox_sprocket_revs": 1,
	},
	"dynamo":
	{
		"crank_pulley_revs": 1,
		"armature_and_commutator_revs": 3,
		"capacitor_charge_cycles": 1,
	},
	"steam":
	{
		"flywheel_revs": 1,
		"piston_double_strokes": 1,
		"hoist_shells_raised": 1,
		"safety_valve_lifts_when_over": 1,
	},
	"arc":
	{
		"flywheel_revs": 1,
		"alternator_rotor_px": 9,
		"ladder_arc_climbs": 2,
		"belt_cartridges_fed": 4,
	},
	"feed":
	{
		"crank_and_sprocket_revs": 1,
		"rounds_fed_both_belts": TankFeedState.ROUNDS_PER_REV,
		"bolt_strokes_each_gun": 1,
		"counter_drum_steps": TankFeedState.ROUNDS_PER_REV,
	},
	"repair":
	{
		"flywheel_and_cam_revs": 1,
		"hammer_strokes": 1,
		"rivets_set": 1,
		"press_cycles": 1,
	},
}
const IN_BAND_LO := 0.84
const IN_BAND_HI := 1.17

# --- Palette (albedo ramps, dark to light) ---------------------------------------------------------------
const IRON: Array[Color] = [
	Color(0.10, 0.085, 0.07),
	Color(0.21, 0.17, 0.135),
	Color(0.33, 0.27, 0.21),
	Color(0.47, 0.38, 0.29),
	Color(0.64, 0.53, 0.40)
]
const STEEL: Array[Color] = [
	Color(0.12, 0.12, 0.115),
	Color(0.26, 0.25, 0.23),
	Color(0.42, 0.40, 0.37),
	Color(0.62, 0.59, 0.53),
	Color(0.86, 0.82, 0.74)
]
const BRASS: Array[Color] = [
	Color(0.30, 0.18, 0.06),
	Color(0.53, 0.36, 0.13),
	Color(0.76, 0.56, 0.24),
	Color(0.93, 0.75, 0.40),
	Color(1.0, 0.92, 0.64)
]
const COPPER: Array[Color] = [
	Color(0.32, 0.13, 0.06),
	Color(0.55, 0.24, 0.11),
	Color(0.78, 0.40, 0.19),
	Color(0.95, 0.59, 0.34),
	Color(1.0, 0.79, 0.55)
]
const OLIVE: Array[Color] = [
	Color(0.10, 0.10, 0.07),
	Color(0.19, 0.19, 0.125),
	Color(0.29, 0.29, 0.19),
	Color(0.40, 0.39, 0.26),
	Color(0.53, 0.51, 0.36)
]
const LEATHER: Array[Color] = [
	Color(0.14, 0.08, 0.05),
	Color(0.27, 0.155, 0.085),
	Color(0.40, 0.24, 0.13),
	Color(0.54, 0.35, 0.19),
	Color(0.68, 0.46, 0.27)
]
const WALL := Color(0.24, 0.19, 0.145)
const WALL_DK := Color(0.11, 0.09, 0.07)
const WALL_LT := Color(0.33, 0.265, 0.20)
const VOID := Color(0.045, 0.038, 0.032)
const PAPER := Color(0.90, 0.84, 0.68)
const NEEDLE := Color(0.10, 0.04, 0.03)
const RED := Color(0.80, 0.20, 0.12)
const GLASS := Color(0.55, 0.64, 0.66)
const WARM := Color(1.0, 0.66, 0.34)
const ARC_CORE := Color(0.85, 0.92, 1.0)
const ARC_GLOW := Color(0.45, 0.55, 1.0)
## Each machine's key: the colour of its room lamp (diesel orange, dynamo pale amber, steam a cool
## brass-white, arc a cold white, repair a pinker copper) and of its ambient fill.
const KEYS := {
	"diesel": Color(1.0, 0.8, 0.6),
	"dynamo": Color(1.0, 0.8, 0.56),
	"steam": Color(0.9, 0.9, 0.8),
	"arc": Color(0.82, 0.85, 0.97),
	"feed": Color(1.0, 0.86, 0.66),
	"repair": Color(1.0, 0.74, 0.5),
}
const AMBS := {
	"diesel": Color(0.15, 0.14, 0.16),
	"dynamo": Color(0.15, 0.14, 0.16),
	"steam": Color(0.15, 0.17, 0.16),
	"arc": Color(0.14, 0.15, 0.19),
	"feed": Color(0.15, 0.15, 0.17),
	"repair": Color(0.17, 0.13, 0.13),
}
const STEAM_WHITE := Color(0.93, 0.94, 0.92)

static var _key: Color = Color(1.0, 0.66, 0.34)
static var _amb_key: Color = Color(0.15, 0.14, 0.16)


static func in_band(power: float) -> bool:
	return power >= IN_BAND_LO and power <= IN_BAND_HI


## The rider's power for the machines: %FTP over the sim band's centre (76-105 % -> 90.5).
static func rider_power(ftp_pct: float) -> float:
	return clampf(ftp_pct / 90.5, 0.0, 1.6)


static func _h(a: float) -> float:
	var s := sin(a * 12.9898 + 78.233) * 43758.5453
	return s - floorf(s)


static func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


static func _heat(pw: float) -> float:
	return smoothstep(0.2, 1.45, pw)


static func _over(pw: float) -> float:
	return smoothstep(1.18, 1.42, pw)


static func _under(pw: float) -> float:
	return 1.0 - smoothstep(0.55, 0.84, pw)


# --- The room (wall, floor, lamp) ------------------------------------------------------------------------


static func _room_static(cv: Cv, lamp_x: int) -> void:
	cv.rect(0, 0, W, 57, WALL)
	for sx: int in [0, 37, 74]:
		cv.vl(sx, 0, 56, WALL_DK)
		cv.vl(sx + 1, 0, 56, WALL_LT)
		for y in range(5, 56, 6):
			cv.rivet(sx + 3, y)
	cv.hl(0, W - 1, 23, WALL_DK)
	cv.hl(0, W - 1, 24, WALL_LT)
	for x in range(5, W, 6):
		cv.rivet(x, 26)
	# ceiling beam
	cv.rect(0, 0, W, 2, IRON[1])
	cv.hl(0, W - 1, 2, IRON[0])
	# deck plate with its tread
	cv.hl(0, W - 1, 57, IRON[3])
	cv.rect(0, 58, W, 6, IRON[1])
	for y in range(59, 63, 2):
		for x in W:
			if (x + (y - 59)) % 4 == 0:
				cv.p(x, y, IRON[2])
				cv.p(x + 1, y + 1, IRON[0])
	cv.hl(0, W - 1, 63, IRON[0])
	# lamp fixture: wire, cap, cage
	cv.vl(lamp_x, 0, 2, STEEL[1])
	cv.rect(lamp_x - 1, 3, 3, 1, BRASS[2])
	cv.p(lamp_x, 3, BRASS[3])
	for y2: int in [4, 5]:
		cv.p(lamp_x - 2, y2, STEEL[2])
		cv.p(lamp_x + 2, y2, STEEL[2])
	cv.hl(lamp_x - 1, lamp_x + 1, 6, STEEL[2])


## The room light's colour and strength: the machine's own key (the slot colour stays on the bulb
## and the enamel tag, so the rider's colour never washes the picture out), a dim amber under band,
## a hot white over. Under band keeps about 75 % of the light (only heat and glow go out: never
## "broken").
static func _lamp_col(pw: float, _slot: Color) -> Color:
	if in_band(pw):
		return _key * (1.05 / maxf(_key.r, maxf(_key.g, _key.b)))
	if pw < IN_BAND_LO:
		return _key * (0.74 + 0.26 * smoothstep(0.1, 0.84, pw))
	return _key.lerp(Color(1.0, 0.95, 0.85), 0.3) * 1.15


## The bulb itself: the room light's colour, tinted by the rider's slot colour while in band.
static func _bulb_col(pw: float, slot: Color) -> Color:
	var c := _lamp_col(pw, slot)
	if not in_band(pw):
		return c
	var tint := _key.lerp(slot, 0.4)
	return tint * (maxf(c.r, maxf(c.g, c.b)) / maxf(tint.r, maxf(tint.g, tint.b)))


static func _lamp_light(cv: Cv, x: int, pw: float, slot: Color) -> void:
	cv.amb = _amb_key * (0.85 + 0.15 * minf(pw, 1.0))
	cv.light(x, 7, 58.0, _lamp_col(pw, slot) * 1.1)


## The bulb (flickering under band) and its halo.
static func _lamp(cv: Cv, x: int, pw: float, t: float, slot: Color) -> void:
	var c0 := _bulb_col(pw, slot)
	var inten := maxf(c0.r, maxf(c0.g, c0.b))
	var col := c0 / maxf(inten, 0.01)
	var flick := 1.0
	if pw < IN_BAND_LO:
		flick = 0.9 + 0.1 * _h(floorf(t * 9.0))
	var bulb := Color(col.r * 0.4 + 0.6, col.g * 0.4 + 0.6, col.b * 0.4 + 0.6)
	cv.p(x, 4, bulb)
	cv.p(x, 5, bulb)
	cv.p(x - 1, 5, col)
	cv.p(x + 1, 5, col)
	cv.e(x, 4, bulb, inten * flick)
	cv.e(x, 5, bulb, inten * flick)
	cv.e(x - 1, 5, col, 0.6 * inten * flick)
	cv.e(x + 1, 5, col, 0.6 * inten * flick)
	cv.glow(x, 5, 8.0, col, 0.4 * inten * flick)


## A small enamel tag in the rider's slot colour (drawn every frame: the slot can change).
static func _tag(cv: Cv, x: int, y: int, slot: Color, pw: float) -> void:
	cv.rect(x, y, 5, 4, IRON[0])
	cv.rect(x + 1, y + 1, 3, 2, slot)
	cv.p(x + 1, y + 1, slot.lightened(0.3))
	var k := 0.3 if in_band(pw) else 0.1
	for xx in range(x + 1, x + 4):
		cv.e(xx, y + 1, slot, k)
		cv.e(xx, y + 2, slot, k * 0.7)


## A round dial (static part): bezel, face, ticks, red zone from `red_from`.
static func _gauge_face(cv: Cv, cx: int, cy: int, r: int, red_from: float) -> void:
	cv.disc(cx, cy, r + 1, BRASS[1])
	cv.ring_shaded(cx, cy, r, r + 1, BRASS)
	cv.disc(cx, cy, r - 1, PAPER)
	for i in 6:
		var a := deg_to_rad(135.0 + 270.0 * float(i) / 5.0)
		var q := Vector2(cx, cy) + _dir(a) * (r - 1)
		cv.p(roundi(q.x), roundi(q.y), Color(0.32, 0.27, 0.2))
	for i in 9:
		var a2 := deg_to_rad(135.0 + 270.0 * lerpf(red_from, 1.0, float(i) / 8.0))
		var q2 := Vector2(cx, cy) + _dir(a2) * (r - 1)
		cv.p(roundi(q2.x), roundi(q2.y), RED)


## The needle at `val` (0..1); `over` tints the face red-hot.
static func _gauge_needle(cv: Cv, cx: int, cy: int, r: int, val: float, over: float) -> void:
	var an := deg_to_rad(135.0 + 270.0 * clampf(val, 0.0, 1.06))
	cv.line_f(Vector2(cx, cy), Vector2(cx, cy) + _dir(an) * (r - 1.3), NEEDLE)
	cv.p(cx, cy, BRASS[3])
	for y in range(cy - r + 1, cy + r):
		for x in range(cx - r + 1, cx + r):
			if Vector2(x - cx, y - cy).length() <= r - 1:
				cv.e(x, y, PAPER, 0.07)
				if over > 0.01:
					cv.e(x, y, Color(0.6, 0.06, 0.02), 0.4 * over)


## Smoke / steam puff into the albedo (shaded like everything else); dithered edge, no blur.
static func _puff(cv: Cv, c: Vector2, r: float, col: Color, a: float) -> void:
	if a <= 0.01:
		return
	var ri := ceili(r)
	for y in range(floori(c.y) - ri, floori(c.y) + ri + 1):
		for x in range(floori(c.x) - ri, floori(c.x) + ri + 1):
			var d := Vector2(x, y).distance_to(c) / maxf(r, 0.5)
			if d > 1.0:
				continue
			var k := 1.0 - d * d
			var th := float((x + y * 2) % 4) / 4.0
			if k * 1.6 < th:
				continue
			cv.mix(x, y, col, clampf(a * (0.55 + 0.45 * k), 0.0, 1.0))


## Vapour leaving a vent along `dir` (white steam, or fumes): three puffs cycling on t.
static func _vent(
	cv: Cv, at: Vector2, dir: Vector2, k: float, t: float, seed: float, col: Color
) -> void:
	if k <= 0.02:
		return
	for i in 3:
		var age := fposmod(t * 1.8 + seed + float(i) / 3.0, 1.0)
		var c := at + dir * (age * 9.0) + Vector2(sin(t * 3.0 + i + seed * 7.0) * 0.8, 0.0)
		_puff(cv, c, 1.2 + age * 3.4, col, k * 0.85 * (1.0 - age * 0.85))


## Flywheel, static part: dark web, rim, hub (the spokes are drawn per frame between them).
static func _wheel_static(cv: Cv, c: Vector2, r: float, rim: int, ramp: Array[Color]) -> void:
	cv.ring_shaded(c.x, c.y, r - rim + 0.6, r, ramp)
	cv.disc_f(c, 2.6, BRASS[1])
	cv.disc_f(c + Vector2(-0.6, -0.6), 1.6, BRASS[3])
	cv.p(roundi(c.x), roundi(c.y), STEEL[0])


## Spokes at angle `ang` (they stop inside the rim and outside the hub); `blur` smears them.
static func _spokes(
	cv: Cv, c: Vector2, r_in: float, n: int, ang: float, ramp: Array[Color], blur: float
) -> void:
	if blur > 0.0:
		for j in range(3, 0, -1):
			for k in n:
				var a := ang - float(j) * 0.12 + k * TAU / n
				cv.mix_line(c + _dir(a) * 3.5, c + _dir(a) * r_in, ramp[2], blur * 0.55 / j)
	for k in n:
		var a2 := ang + k * TAU / n
		cv.thick(c + _dir(a2) * 3.2, c + _dir(a2) * r_in, ramp[3], ramp[1])


## A chain loop around two circles; links advance `m` periods per crank revolution.
static func _chain(
	cv: Cv, c1: Vector2, r1: float, c2: Vector2, r2: float, ph: float, m: int, period: float
) -> void:
	var pts := _loop(c1, r1, c2, r2)
	var total: float = pts[pts.size() - 1].z
	var per := total / maxf(roundf(total / period), 1.0)
	var shift := ph * float(m) * per
	for q: Vector3 in pts:
		var u := fposmod(q.z - shift, per) / per
		cv.p(
			roundi(q.x), roundi(q.y), STEEL[4] if u < 0.34 else (STEEL[2] if u < 0.67 else IRON[0])
		)


## A flat belt loop (2 px: a lit outer face with moving lacing marks, a dark inner face); pixels
## inside `hide_c`/`hide_r` are skipped (it runs behind that).
static func _belt(
	cv: Cv,
	c1: Vector2,
	r1: float,
	c2: Vector2,
	r2: float,
	ph: float,
	m: int,
	period: float,
	hide_c: Vector2,
	hide_r: float
) -> void:
	var pts := _loop(c1, r1, c2, r2)
	var total: float = pts[pts.size() - 1].z
	var per := total / maxf(roundf(total / period), 1.0)
	var shift := ph * float(m) * per
	var mid_y := (c1.y + c2.y) * 0.5
	for q: Vector3 in pts:
		var pp := Vector2(q.x, q.y)
		var inner := pp
		if pp.distance_to(c1) <= r1 + 0.7:
			inner = pp - (pp - c1).normalized()
		elif pp.distance_to(c2) <= r2 + 0.7:
			inner = pp - (pp - c2).normalized()
		else:
			inner = pp + (Vector2(0, 1) if q.y < mid_y else Vector2(0, -1))
		var u := fposmod(q.z - shift, per) / per
		if inner.distance_to(hide_c) > hide_r:
			cv.p(roundi(inner.x), roundi(inner.y), LEATHER[0] if u >= 0.2 else LEATHER[2])
		if pp.distance_to(hide_c) > hide_r:
			cv.p(roundi(pp.x), roundi(pp.y), LEATHER[4] if u < 0.2 else LEATHER[3])


## Points (x, y, arc length) along an open loop around two circles, clockwise on screen: the
## upper run from c1 to c2, around c2, the lower run back, around c1.
static func _loop(c1: Vector2, r1: float, c2: Vector2, r2: float) -> Array[Vector3]:
	var d := c2 - c1
	var phi := d.angle()
	var beta := acos(clampf((r1 - r2) / d.length(), -1.0, 1.0))
	var a_top := phi - beta
	var a_bot := phi + beta
	var out: Array[Vector3] = []
	var acc := 0.0
	var prev := c1 + _dir(a_top) * r1
	var runs: Array[Array] = [
		[c1 + _dir(a_top) * r1, c2 + _dir(a_top) * r2],
		[c2, r2, a_top, a_bot],
		[c2 + _dir(a_bot) * r2, c1 + _dir(a_bot) * r1],
		[c1, r1, a_bot, a_top + TAU],
	]
	for s: Array in runs:
		if s.size() == 2:
			var p0: Vector2 = s[0]
			var p1: Vector2 = s[1]
			var n := maxi(ceili(p0.distance_to(p1) * 2.0), 1)
			for i in n:
				var q := p0.lerp(p1, float(i) / n)
				acc += q.distance_to(prev)
				prev = q
				out.append(Vector3(q.x, q.y, acc))
		else:
			var c: Vector2 = s[0]
			var r: float = s[1]
			var a0: float = s[2]
			var a1: float = s[3]
			var n2 := maxi(ceili(absf(a1 - a0) * r * 2.0), 1)
			for i in n2:
				var q2 := c + _dir(lerpf(a0, a1, float(i) / n2)) * r
				acc += q2.distance_to(prev)
				prev = q2
				out.append(Vector3(q2.x, q2.y, acc))
	acc += (c1 + _dir(a_top) * r1).distance_to(prev)
	out.append(Vector3(prev.x, prev.y, acc))
	return out


# --- Canvas ----------------------------------------------------------------------------------------------


class Cv:
	extends RefCounted
	var w: int = 0
	var h: int = 0
	## The frame (RGBA8): raw albedo while the static layer is drawn, lit afterwards.
	var al: PackedByteArray = PackedByteArray()
	## The light map (RGB floats per pixel; shared from the cache, read only) and its switch.
	var lm: PackedFloat32Array = PackedFloat32Array()
	var use_light: bool = false
	## Emissive (RGB floats, added last) and the pixels that have any.
	var em: PackedFloat32Array = PackedFloat32Array()
	var lit: PackedInt32Array = PackedInt32Array()
	var lpos: Array[Vector3] = []
	var lcol: Array[Color] = []
	var amb: Color = Color(0.15, 0.14, 0.16)
	## Shift the finished picture down a pixel (the over-power shake).
	var shake: bool = false

	func _init(width: int, height: int) -> void:
		w = width
		h = height
		al.resize(w * h * 4)
		em.resize(w * h * 3)

	func p(x: int, y: int, c: Color) -> void:
		if x < 0 or y < 0 or x >= w or y >= h:
			return
		var j := y * w + x
		var i := j * 4
		if use_light:
			var k := j * 3
			al[i] = mini(int(c.r * lm[k] * 255.0), 255)
			al[i + 1] = mini(int(c.g * lm[k + 1] * 255.0), 255)
			al[i + 2] = mini(int(c.b * lm[k + 2] * 255.0), 255)
		else:
			al[i] = mini(int(c.r * 255.0), 255)
			al[i + 1] = mini(int(c.g * 255.0), 255)
			al[i + 2] = mini(int(c.b * 255.0), 255)
		al[i + 3] = 255

	func mix(x: int, y: int, c: Color, a: float) -> void:
		if x < 0 or y < 0 or x >= w or y >= h:
			return
		var j := y * w + x
		var i := j * 4
		var lr := 1.0
		var lg := 1.0
		var lb := 1.0
		if use_light:
			lr = lm[j * 3]
			lg = lm[j * 3 + 1]
			lb = lm[j * 3 + 2]
		al[i] = mini(int(lerpf(al[i], c.r * lr * 255.0, a)), 255)
		al[i + 1] = mini(int(lerpf(al[i + 1], c.g * lg * 255.0, a)), 255)
		al[i + 2] = mini(int(lerpf(al[i + 2], c.b * lb * 255.0, a)), 255)

	func e(x: int, y: int, c: Color, k: float = 1.0) -> void:
		if x < 0 or y < 0 or x >= w or y >= h or k <= 0.0:
			return
		var j := y * w + x
		var i := j * 3
		if em[i] == 0.0 and em[i + 1] == 0.0 and em[i + 2] == 0.0:
			lit.append(j)
		em[i] += c.r * k + 0.0001
		em[i + 1] += c.g * k
		em[i + 2] += c.b * k

	func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		for yy in range(maxi(y, 0), mini(y + rh, h)):
			for xx in range(maxi(x, 0), mini(x + rw, w)):
				p(xx, yy, c)

	func hl(x0: int, x1: int, y: int, c: Color) -> void:
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			p(x, y, c)

	func vl(x: int, y0: int, y1: int, c: Color) -> void:
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			p(x, y, c)

	func rivet(x: int, y: int) -> void:
		p(x, y, Color(0.56, 0.45, 0.32))
		p(x + 1, y + 1, Color(0.07, 0.06, 0.045))

	func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
		var dx := absi(x1 - x0)
		var dy := -absi(y1 - y0)
		var sx := 1 if x0 < x1 else -1
		var sy := 1 if y0 < y1 else -1
		var err := dx + dy
		var x := x0
		var y := y0
		for _i in 256:
			p(x, y, c)
			if x == x1 and y == y1:
				break
			var e2 := 2 * err
			if e2 >= dy:
				err += dy
				x += sx
			if e2 <= dx:
				err += dx
				y += sy

	func line_f(a: Vector2, b: Vector2, c: Color) -> void:
		line(roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y), c)

	## A 2 px rod: the line, and a shade line beside it (below, or right when steep).
	func thick(a: Vector2, b: Vector2, c: Color, shade: Color) -> void:
		var d := b - a
		var off := Vector2(0, 1) if absf(d.x) >= absf(d.y) else Vector2(1, 0)
		line_f(a + off, b + off, shade)
		line_f(a, b, c)

	func mix_line(a: Vector2, b: Vector2, c: Color, k: float) -> void:
		var n := maxi(ceili(a.distance_to(b)), 1)
		for i in n + 1:
			var q := a.lerp(b, float(i) / n)
			mix(roundi(q.x), roundi(q.y), c, k)

	func e_line(a: Vector2, b: Vector2, c: Color, k: float) -> void:
		var n := maxi(ceili(a.distance_to(b)), 1)
		for i in n:
			var q := a.lerp(b, float(i) / n)
			e(roundi(q.x), roundi(q.y), c, k)

	func disc(cx: int, cy: int, r: int, c: Color) -> void:
		disc_f(Vector2(cx, cy), float(r), c)

	func disc_f(c0: Vector2, r: float, c: Color) -> void:
		var ri := ceili(r) + 1
		var cx := roundi(c0.x)
		var cy := roundi(c0.y)
		var rr := (r + 0.35) * (r + 0.35)
		for y in range(cy - ri, cy + ri + 1):
			for x in range(cx - ri, cx + ri + 1):
				var dx := float(x) - c0.x
				var dy := float(y) - c0.y
				if dx * dx + dy * dy <= rr:
					p(x, y, c)

	## Annulus r0..r1 shaded by angle (lit from the top left).
	func ring_shaded(cx: float, cy: float, r0: float, r1: float, ramp: Array[Color]) -> void:
		var ri := ceili(r1) + 1
		var x0 := roundi(cx)
		var y0 := roundi(cy)
		for y in range(y0 - ri, y0 + ri + 1):
			for x in range(x0 - ri, x0 + ri + 1):
				var dx := float(x) - cx
				var dy := float(y) - cy
				var d := sqrt(dx * dx + dy * dy)
				if d > r1 + 0.35 or d < r0 - 0.35:
					continue
				var l := (-0.6 * dx - 0.8 * dy) / maxf(d, 0.01)
				var idx := 2 + roundi(l * 1.5)
				if d > r1 - 0.6:
					idx -= 1
				p(x, y, ramp[clampi(idx, 0, ramp.size() - 1)])

	func teeth(c0: Vector2, r: float, n: int, ang: float, c: Color) -> void:
		for k in n:
			var q := c0 + Vector2(cos(ang + k * TAU / n), sin(ang + k * TAU / n)) * r
			p(roundi(q.x), roundi(q.y), c)

	func glow(cx: float, cy: float, r: float, c: Color, k: float) -> void:
		if k <= 0.0:
			return
		var ri := ceili(r)
		var inv := 1.0 / r
		for y in range(maxi(floori(cy) - ri, 0), mini(floori(cy) + ri + 1, h)):
			for x in range(maxi(floori(cx) - ri, 0), mini(floori(cx) + ri + 1, w)):
				var dx := float(x) - cx
				var dy := float(y) - cy
				var d := sqrt(dx * dx + dy * dy) * inv
				if d >= 1.0:
					continue
				e(x, y, c, k * (1.0 - d) * (1.0 - d))

	## A light on the room (power dependent only: it is baked per power step).
	func light(x: float, y: float, r: float, c: Color) -> void:
		lpos.append(Vector3(x, y, r))
		lcol.append(c)

	## Bakes the lights into a light map and lights `raw` (the static albedo) with it:
	## returns [lit bytes, light map].
	func bake(raw: PackedByteArray) -> Array:
		var lmap := PackedFloat32Array()
		lmap.resize(w * h * 3)
		var out := raw.duplicate()
		var n := lpos.size()
		for y in h:
			for x in w:
				var lr := amb.r
				var lg := amb.g
				var lb := amb.b
				for k in n:
					var lp: Vector3 = lpos[k]
					var dx := float(x) - lp.x
					var dy := float(y) - lp.y
					var f := 1.0 / (1.0 + (dx * dx + dy * dy) / (lp.z * lp.z * 0.25))
					var lc: Color = lcol[k]
					lr += lc.r * f
					lg += lc.g * f
					lb += lc.b * f
				var j := y * w + x
				lmap[j * 3] = lr
				lmap[j * 3 + 1] = lg
				lmap[j * 3 + 2] = lb
				var o := j * 4
				out[o] = mini(int(raw[o] * lr), 255)
				out[o + 1] = mini(int(raw[o + 1] * lg), 255)
				out[o + 2] = mini(int(raw[o + 2] * lb), 255)
		return [out, lmap]

	func finish(img: Image) -> void:
		var data := al
		for j in lit:
			var i := j * 3
			var o := j * 4
			data[o] = mini(data[o] + int(em[i] * 255.0), 255)
			data[o + 1] = mini(data[o + 1] + int(em[i + 1] * 255.0), 255)
			data[o + 2] = mini(data[o + 2] + int(em[i + 2] * 255.0), 255)
		if shake:
			data = data.slice(0, w * 4) + data.slice(0, (h - 1) * w * 4)
		if img.get_width() == w and img.get_height() == h:
			img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
			return
		var tmp := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		var tw := maxi(img.get_width(), 1)
		var tht := maxi(img.get_height(), 1)
		tmp.resize(tw, tht, Image.INTERPOLATE_NEAREST)
		img.set_data(tw, tht, false, Image.FORMAT_RGBA8, tmp.get_data())
