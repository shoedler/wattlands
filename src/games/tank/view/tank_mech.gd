class_name TankMech
extends RefCounted
## The station machines (v4: the six seats' machines) as
## procedural pixel art, painted into an Image with the Image API only (works headless, per frame):
## diesel (Drive), dynamo (Gun: turret traverse + gun charge), steam (Loader), arc (Lights),
## feed (v3, Secondaries: the crank-driven twin belt feed of the bow guns) and repair (v4, Repairs: the
## cam-lifted rivet hammer and the plate press). Designed for 112 x 64;
## other sizes get the 112 x 64 picture scaled (nearest).
##
## Coupling (docs/games/tank.md 3.4): `phase` = crank revolutions (integral of the rider's cadence,
## rpm / 60 per second); every moving part turns at a fixed integer ratio of it (PARTS), so one
## crank revolution is one seamless loop. `power` = watts / target (1 = in band): heat, light,
## smoke, sparks and needles. `t` (seconds) only flickers and drifts. `slot` tints the room lamp
## while in band and a small enamel tag.
##
## Rendering, cheap enough to repaint four cards every frame: the parts that never move are drawn
## once per kind and cached; the moving parts are drawn on a copy; the room light (lamp, fire, arc
## lamp; it depends on power only) is a cached shade overlay per power step, blended natively; the
## glowing parts (hot metal, fire, arcs, sparks, jars) are added last.

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
const SOOT := Color(0.05, 0.042, 0.035)
const VOID := Color(0.045, 0.038, 0.032)
const PAPER := Color(0.90, 0.84, 0.68)
const NEEDLE := Color(0.10, 0.04, 0.03)
const RED := Color(0.80, 0.20, 0.12)
const GLASS := Color(0.55, 0.64, 0.66)
const WARM := Color(1.0, 0.66, 0.34)
const ARC_CORE := Color(0.85, 0.92, 1.0)
const ARC_GLOW := Color(0.45, 0.55, 1.0)
## The ambient light (a cool night fill; the lamps are warm).
const AMBIENT := Color(0.15, 0.14, 0.16)
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

static var _seen: Dictionary = {}
static var _static_cache: Dictionary = {}
static var _lit_cache: Dictionary = {}
static var _key: Color = Color(1.0, 0.66, 0.34)
static var _amb_key: Color = Color(0.15, 0.14, 0.16)


## The contract (MOCK_SPEC_R2): clears and paints the whole Image. The rpm for the needles and
## motion blur is estimated from successive calls (phase over t) per kind and slot.
static func paint(
	img: Image, kind: String, phase: float, power: float, t: float, slot: Color
) -> void:
	paint_ex(img, kind, phase, power, t, slot, -1.0)


## As paint(), with the crank rpm given (rpm < 0: estimate it from successive calls).
static func paint_ex(
	img: Image, kind: String, phase: float, power: float, t: float, slot: Color, rpm: float
) -> void:
	var k := kind if kind in RATIO else "diesel"
	var rate := rpm / 60.0 if rpm >= 0.0 else _rate_of(k, slot, phase, t)
	var pw := clampf(power, 0.0, 1.6)
	_key = KEYS[k]
	_amb_key = AMBS[k]
	var cv := Cv.new(W, H)
	if not _static_cache.has(k):
		match k:
			"diesel":
				_diesel_static(cv)
			"dynamo":
				_dynamo_static(cv)
			"steam":
				_steam_static(cv)
			"arc":
				_arc_static(cv)
			"feed":
				_feed_static(cv)
			"repair":
				_repair_static(cv)
		_static_cache[k] = cv.al
	var bucket := roundi(pw * 20.0)
	var key := "%s|%d|%s" % [k, bucket, slot.to_html(false)]
	if not _lit_cache.has(key):
		if _lit_cache.size() > 160:
			_lit_cache.clear()
		var lc := Cv.new(W, H)
		var pb := float(bucket) / 20.0
		match k:
			"diesel":
				_lamp_light(lc, D_LAMP, pb, slot)
				_diesel_lights(lc, pb)
			"dynamo":
				_lamp_light(lc, Y_LAMP, pb, slot)
			"steam":
				_lamp_light(lc, S_LAMP, pb, slot)
				_steam_lights(lc, pb)
			"arc":
				_lamp_light(lc, A_LAMP, pb, slot)
				_arc_lights(lc, pb)
			"feed":
				_lamp_light(lc, F_LAMP, pb, slot)
				_feed_lights(lc, pb)
			"repair":
				_lamp_light(lc, R_LAMP, pb, slot)
				_repair_lights(lc, pb)
		_lit_cache[key] = lc.bake(_static_cache[k])
	var lit: Array = _lit_cache[key]
	cv.al = (lit[0] as PackedByteArray).duplicate()
	cv.lm = lit[1]
	cv.use_light = true
	match k:
		"diesel":
			_diesel(cv, phase, pw, t, slot, rate)
		"dynamo":
			_dynamo(cv, phase, pw, t, slot, rate)
		"steam":
			_steam(cv, phase, pw, t, slot, rate)
		"arc":
			_arc(cv, phase, pw, t, slot, rate)
		"feed":
			_feed(cv, phase, pw, t, slot, rate)
		"repair":
			_repair(cv, phase, pw, t, slot, rate)
	# over power: the whole machine shakes by a pixel
	cv.shake = _over(pw) > 0.4 and _h(floorf(t * 14.0)) > 0.45
	cv.finish(img)


## Crank revolutions per second from the previous call with the same kind and slot.
static func _rate_of(kind: String, slot: Color, phase: float, t: float) -> float:
	var key := kind + slot.to_html()
	var prev: Array = _seen.get(key, [phase, t, 0.0])
	var rate := float(prev[2])
	var dt := t - float(prev[1])
	if dt > 0.0005 and dt < 1.0:
		var r := maxf((phase - float(prev[0])) / dt, 0.0)
		rate = lerpf(rate, r, clampf(dt * 5.0, 0.0, 1.0))
	_seen[key] = [phase, t, rate]
	return rate


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


# --- Diesel ----------------------------------------------------------------------------------------------
# Three inline cylinders cut open: pistons, con-rods and crank throws in the open crankcase; the
# flywheel on the crankshaft's rear end, a chain from the front sprocket down to the gearbox (its
# output shaft goes to the tracks); each firing lights its bore and pops the stack's flapper cap
# with a puff; heads and manifold glow with power; the tacho reads rpm.

const D_FW := Vector2(17, 44)
const D_FR := 13.0
const D_CY := 45.0
const D_R := 6.0
const D_L := 13.0
const D_CX: Array[int] = [45, 61, 77]
const D_THROW: Array[float] = [0.0, 120.0, 240.0]
const D_CYCLE: Array[float] = [0.0, 480.0, 240.0]
const D_SPA := Vector2(92, 45)
const D_SPB := Vector2(103, 50)
const D_LAMP := 68


static func _diesel_static(cv: Cv) -> void:
	_room_static(cv, D_LAMP)
	# gearbox
	cv.rect(95, 38, 17, 19, IRON[2])
	cv.hl(95, 111, 38, IRON[4])
	cv.hl(95, 111, 39, IRON[3])
	cv.vl(95, 38, 56, IRON[3])
	for x in range(97, 111, 4):
		cv.rivet(x, 41)
	cv.rect(106, 31, 2, 7, STEEL[2])
	cv.vl(106, 31, 37, STEEL[3])
	cv.rect(105, 29, 4, 2, BRASS[2])
	cv.hl(105, 108, 29, BRASS[4])
	# output shaft to the tracks
	cv.rect(109, 49, 3, 3, STEEL[2])
	cv.hl(109, 111, 49, STEEL[4])
	# stack (a stub through the ceiling, with a flapper cap) and the manifold
	cv.rect(97, 5, 5, 8, IRON[2])
	cv.vl(98, 5, 12, IRON[4])
	cv.vl(101, 5, 12, IRON[0])
	cv.hl(96, 102, 12, IRON[3])
	cv.rect(40, 8, 61, 4, IRON[2])
	cv.hl(40, 100, 8, IRON[4])
	cv.hl(40, 100, 9, IRON[3])
	cv.hl(40, 100, 11, IRON[0])
	cv.vl(40, 8, 11, IRON[1])
	for x in range(46, 98, 9):
		cv.rect(x, 7, 2, 6, IRON[1])
		cv.p(x, 7, IRON[3])
	for cx: int in D_CX:
		cv.rect(cx + 2, 12, 3, 4, IRON[2])
		cv.vl(cx + 2, 12, 15, IRON[4])
	# block
	cv.rect(37, 23, 49, 18, IRON[2])
	cv.hl(37, 85, 23, IRON[4])
	cv.vl(37, 23, 40, IRON[3])
	cv.vl(85, 23, 40, IRON[1])
	for i in 3:
		var cx3 := D_CX[i]
		cv.rect(cx3 - 7, 16, 14, 7, IRON[2])
		for y in range(17, 23, 2):
			cv.hl(cx3 - 7, cx3 + 6, y, IRON[1])
		cv.hl(cx3 - 7, cx3 + 6, 16, IRON[4])
		cv.vl(cx3 - 7, 16, 22, IRON[3])
		cv.rivet(cx3 - 6, 21)
		cv.rivet(cx3 + 4, 21)
		cv.p(cx3, 15, STEEL[1])
		# the bore, cut open: a lit cylinder wall
		cv.rect(cx3 - 5, 23, 10, 18, Color(0.15, 0.125, 0.10))
		cv.vl(cx3 - 5, 23, 40, Color(0.07, 0.06, 0.05))
		cv.vl(cx3 - 3, 23, 40, Color(0.27, 0.23, 0.19))
		cv.vl(cx3 + 3, 23, 40, Color(0.10, 0.085, 0.07))
		cv.vl(cx3 + 4, 23, 40, Color(0.05, 0.04, 0.035))
	for x: int in [53, 69]:
		cv.vl(x, 24, 40, IRON[3])
		cv.vl(x + 1, 24, 40, IRON[1])
	# crankcase, open at the front; sump with the oil
	cv.rect(35, 41, 53, 12, Color(0.12, 0.10, 0.08))
	cv.vl(35, 41, 52, IRON[4])
	cv.vl(36, 41, 52, IRON[2])
	cv.vl(86, 41, 52, IRON[2])
	cv.vl(87, 41, 52, IRON[0])
	cv.hl(35, 87, 41, IRON[1])
	cv.hl(38, 84, 52, Color(0.10, 0.09, 0.05))
	cv.hl(40, 82, 51, Color(0.05, 0.045, 0.03))
	cv.rect(35, 53, 53, 4, IRON[2])
	cv.hl(35, 87, 53, IRON[4])
	for x2 in range(38, 86, 5):
		cv.rivet(x2, 55)
	for bx: int in [37, 53, 69, 85]:
		cv.rect(bx - 1, int(D_CY) - 2, 3, 5, BRASS[1])
		cv.p(bx - 1, int(D_CY) - 2, BRASS[3])
	# crankshaft: flywheel hub to the front sprocket
	cv.rect(18, int(D_CY) - 1, 76, 3, STEEL[2])
	cv.hl(18, 93, int(D_CY) - 1, STEEL[4])
	cv.hl(18, 93, int(D_CY) + 1, STEEL[1])
	# flywheel, gearbox sprocket, crank sprocket bodies
	_wheel_static(cv, D_FW, D_FR, 3, STEEL)
	cv.rect(int(D_FW.x) - 3, 56, 7, 1, IRON[3])
	cv.disc_f(D_SPB, 5.6, STEEL[1])
	cv.ring_shaded(D_SPB.x, D_SPB.y, 4.4, 6.0, STEEL)
	cv.disc_f(D_SPB, 1.4, BRASS[3])
	cv.disc_f(D_SPA, 3.0, STEEL[2])
	cv.ring_shaded(D_SPA.x, D_SPA.y, 2.0, 3.2, STEEL)
	cv.p(int(D_SPA.x), int(D_SPA.y), BRASS[4])
	# tacho on the wall, its drive cable down to the flywheel hub
	cv.vl(17, 22, 30, Color(0.07, 0.06, 0.05))
	cv.vl(18, 23, 30, Color(0.2, 0.17, 0.13))
	_gauge_face(cv, 17, 13, 7, 0.86)
	_gauge_face(cv, 32, 12, 4, 0.75)


static func _diesel_lights(cv: Cv, pw: float) -> void:
	var mglow := clampf(_heat(pw) * 1.35 - 0.45, 0.0, 1.0)
	cv.light(66, 12, 26.0, Color(1.0, 0.35, 0.1) * (0.5 * mglow))


static func _diesel(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var under := _under(pw)
	var e := ph * float(RATIO["diesel"])
	var th := e * TAU
	_lamp(cv, D_LAMP, pw, t, slot)
	# manifold and heads glow with heat (hot near the exhaust ports)
	var mglow := clampf(heat * 1.35 - 0.45, 0.0, 1.0)
	if mglow > 0.0:
		for x in range(41, 100):
			var hot := 0.35 + 0.15 * sin(float(x) * 0.5)
			for cx2: int in D_CX:
				hot += 0.9 * maxf(0.0, 1.0 - absf(float(x - cx2 - 3)) / 7.0)
			cv.e(x, 9, Color(0.85, 0.2, 0.04), mglow * 0.4 * hot)
			cv.e(x, 10, Color(0.65, 0.12, 0.03), mglow * 0.35 * hot)
	for i in 3:
		var cx3 := D_CX[i]
		var hg := heat * heat * (0.3 + 0.7 * over)
		if hg > 0.02:
			for x in range(cx3 - 6, cx3 + 6):
				for y in range(18, 23, 2):
					cv.e(x, y, Color(0.95, 0.24, 0.05), hg * (0.55 + 0.45 * _h(float(x * 3 + y))))
		# rocker on its post, tilting with the valve events
		var cyc := fposmod(e * 360.0 + D_CYCLE[i], 720.0)
		var tilt := 0
		if cyc > 540.0 and cyc < 700.0:
			tilt = 1
		elif cyc > 20.0 and cyc < 180.0:
			tilt = -1
		cv.p(cx3 - 3, 14 + tilt, STEEL[3])
		cv.p(cx3 - 2, 14 + (1 if tilt > 0 else 0), STEEL[3])
		cv.p(cx3 - 1, 14, STEEL[3])
		cv.p(cx3, 14, STEEL[4])
		cv.p(cx3 + 1, 14, STEEL[3])
		cv.p(cx3 + 2, 14 + (1 if tilt < 0 else 0), STEEL[3])
		cv.p(cx3 + 3, 14 - tilt, STEEL[3])
	# crank throws, con-rods, pistons; the bore lights up after each firing
	for i in 3:
		var cx4 := float(D_CX[i])
		var a := th + deg_to_rad(D_THROW[i])
		var pin := Vector2(cx4 + D_R * sin(a), D_CY - D_R * cos(a))
		var py := D_CY - (D_R * cos(a) + sqrt(D_L * D_L - D_R * D_R * sin(a) * sin(a)))
		var cw := Vector2(cx4, D_CY) - (pin - Vector2(cx4, D_CY)) * 0.6
		cv.disc_f(cw, 2.4, IRON[1])
		cv.thick(Vector2(cx4, D_CY), pin, IRON[3], IRON[1])
		cv.thick(Vector2(cx4, py), pin, STEEL[4], STEEL[2])
		cv.disc_f(pin, 1.6, STEEL[3])
		cv.p(roundi(pin.x), roundi(pin.y), BRASS[4])
		var top := roundi(py) - 3
		var cyc2 := fposmod(e * 360.0 + D_CYCLE[i], 720.0)
		if cyc2 < 90.0:
			var k := (1.0 - cyc2 / 90.0) * (0.3 + 0.9 * heat)
			for y in range(23, top):
				for x in range(int(cx4) - 4, int(cx4) + 4):
					var c := Color(1.0, 0.85, 0.5).lerp(Color(1.0, 0.38, 0.08), float(y - 23) / 9.0)
					cv.e(x, y, c, k * (0.75 + 0.25 * _h(float(x + y * 7) + floorf(t * 30.0))))
			cv.glow(cx4, 24.0, 9.0, Color(1.0, 0.5, 0.15), 0.3 * k)
		var px0 := int(cx4) - 5
		cv.rect(px0, top, 10, 6, STEEL[3])
		cv.hl(px0, px0 + 9, top, STEEL[4])
		cv.hl(px0, px0 + 9, top + 1, STEEL[1])
		cv.hl(px0, px0 + 9, top + 3, STEEL[1])
		cv.hl(px0, px0 + 9, top + 5, STEEL[2])
		cv.vl(px0, top, top + 5, STEEL[2])
		cv.vl(px0 + 9, top, top + 5, STEEL[1])
		cv.rect(int(cx4) - 1, roundi(py) - 1, 2, 2, BRASS[3])
	# flywheel spokes (smeared at speed) and its timing mark
	var blur := clampf((rate * float(RATIO["diesel"]) - 2.2) / 1.8, 0.0, 1.0)
	_spokes(cv, D_FW, D_FR - 2.6, 8, th, STEEL, blur)
	var tm := D_FW + _dir(th - PI * 0.5) * (D_FR - 1.4)
	cv.rect(roundi(tm.x), roundi(tm.y), 1, 1, BRASS[4])
	# drive chain: crank sprocket (x2) -> gearbox sprocket (x1)
	cv.teeth(D_SPA, 3.6, 8, th, STEEL[3])
	cv.teeth(D_SPB, 6.4, 15, ph * TAU, STEEL[3])
	for k2 in 4:
		var hp := D_SPB + _dir(ph * TAU + k2 * TAU / 4.0) * 3.0
		cv.p(roundi(hp.x), roundi(hp.y), IRON[0])
	_chain(cv, D_SPA, 3.9, D_SPB, 6.9, ph, 15, 3.0)
	# tacho by rpm, tag
	_gauge_needle(cv, 17, 13, 7, clampf(rate * 60.0 / 140.0, 0.0, 1.0), over)
	_gauge_needle(cv, 32, 12, 4, clampf(pw / 1.4, 0.0, 1.05), over)
	_tag(cv, 22, 23, slot, pw)
	# exhaust pulse: the flapper lifts and a puff leaves the stack (three per crank revolution)
	var since := fposmod(e * 360.0 - 200.0, 240.0)
	if since < 80.0:
		cv.p(96, 4, IRON[3])
		cv.p(97, 3, IRON[3])
		cv.p(98, 2, IRON[4])
		cv.p(99, 1, IRON[3])
		if heat > 0.45:
			cv.e(99, 4, Color(1.0, 0.45, 0.1), (heat - 0.45) * 1.2 * (1.0 - since / 80.0))
	else:
		cv.hl(96, 102, 4, IRON[3])
		cv.p(96, 4, IRON[4])
	var smoke := Color(0.5, 0.48, 0.45).lerp(Color(0.18, 0.16, 0.14), maxf(under * 0.5, over * 0.8))
	var dens := 0.35 + 0.1 * under + 0.35 * over + 0.15 * heat
	for k3 in 3:
		var age := (since + 240.0 * k3) / 720.0
		var c2 := Vector2(
			99.0 - age * 22.0 + sin(t * 2.0 + k3) * 0.8, 3.0 - age * 2.0 + under * age * 3.0
		)
		_puff(cv, c2, 1.6 + age * (4.5 + 3.0 * under), smoke, dens * (1.0 - age))
	_vent(cv, Vector2(38, 15), Vector2(-0.4, -1.0), over, t, 0.0, STEAM_WHITE)
	_vent(cv, Vector2(86, 40), Vector2(0.5, -1.0), over, t, 0.5, Color(0.55, 0.53, 0.5))
	if over > 0.1:
		for k4 in 3:
			var s := fposmod(t * 1.7 + k4 * 0.37, 1.0)
			var sp := Vector2(99.0 - s * 12.0 + k4 * 2.0, 3.0 - s * 3.0)
			cv.e(roundi(sp.x), roundi(sp.y), Color(1.0, 0.55, 0.15), over * (1.0 - s))


# --- Dynamo ----------------------------------------------------------------------------------------------
# Hero: the dynamo seen end-on, filling the left half: olive field frame with its pole shoes and
# copper field coils, the copper-wound armature turning 3:1, the commutator and two brushes that
# spark with power. The rider's crank pulley hangs from the ceiling bracket (top left) and belts
# the armature from behind. Right: the voltmeter, the traverse motor on the turret ring (edge-on
# along the ceiling, teeth sliding), and four tall capacitor jars that fill with charge once per
# crank revolution and dump it up the bus bar; over power they overflow, arcing jar to jar.

const Y_DC := Vector2(44, 32)
const Y_FR := 22.5
const Y_PUL := Vector2(10, 12)
const Y_PR := 7.0
const Y_LAMP := 70
const Y_RACK_Y := 2
const Y_JX := 72
const Y_JY := 28
const Y_VM := Vector2i(102, 15)


static func _dynamo_static(cv: Cv) -> void:
	_room_static(cv, Y_LAMP)
	# turret ring edge-on along the ceiling, the traverse motor hanging under it
	cv.rect(64, Y_RACK_Y, 48, 3, IRON[2])
	cv.hl(64, 111, Y_RACK_Y, IRON[4])
	cv.hl(64, 111, Y_RACK_Y + 2, IRON[1])
	cv.rect(76, 9, 12, 8, OLIVE[2])
	cv.hl(76, 87, 9, OLIVE[4])
	cv.vl(76, 9, 16, OLIVE[3])
	cv.vl(87, 9, 16, OLIVE[0])
	for y in range(11, 17, 2):
		cv.hl(77, 86, y, OLIVE[1])
	cv.rect(80, 8, 4, 1, STEEL[2])
	# bus bar: frame top -> ceiling -> motor; a tap down to the jars
	cv.rect(43, 5, 2, 5, COPPER[2])
	cv.vl(43, 5, 9, COPPER[3])
	cv.rect(43, 5, 33, 2, COPPER[2])
	cv.hl(43, 75, 5, COPPER[3])
	cv.hl(43, 75, 6, COPPER[1])
	for x in range(50, 74, 8):
		cv.rect(x, 4, 2, 4, Color(0.8, 0.77, 0.68))
	cv.vl(69, 7, 24, COPPER[1])
	cv.hl(69, 108, 24, COPPER[1])
	cv.hl(69, 108, 23, COPPER[3])
	# the jars on their shelf
	cv.rect(68, 50, 44, 2, LEATHER[2])
	cv.hl(68, 111, 50, LEATHER[4])
	cv.rect(70, 52, 2, 5, LEATHER[1])
	cv.rect(108, 52, 2, 5, LEATHER[1])
	for i in 4:
		_jar_static(cv, Y_JX + i * 9, Y_JY)
		cv.vl(Y_JX + 3 + i * 9, 24, Y_JY - 3, COPPER[2])
	# voltmeter
	_gauge_face(cv, Y_VM.x, Y_VM.y, 6, 0.8)
	cv.vl(Y_VM.x, Y_VM.y + 7, 23, COPPER[1])
	# the crank pulley on its ceiling bracket
	cv.line_f(Vector2(4, 3), Y_PUL, IRON[3])
	cv.line_f(Vector2(16, 3), Y_PUL, IRON[3])
	cv.hl(3, 17, 3, IRON[4])
	_wheel_static(cv, Y_PUL, Y_PR, 2, STEEL)
	# cast feet and the field frame
	cv.rect(25, 52, 39, 5, IRON[2])
	cv.hl(25, 63, 52, IRON[4])
	cv.rivet(28, 54)
	cv.rivet(59, 54)
	cv.disc_f(Y_DC, Y_FR, OLIVE[1])
	cv.ring_shaded(Y_DC.x, Y_DC.y, Y_FR - 3.2, Y_FR, OLIVE)
	cv.disc_f(Y_DC, Y_FR - 3.4, Color(0.06, 0.055, 0.045))
	for y2 in range(int(Y_DC.y - Y_FR), int(Y_DC.y + Y_FR) + 1):
		for x2 in range(int(Y_DC.x - Y_FR), int(Y_DC.x + Y_FR) + 1):
			var v := Vector2(x2, y2) - Y_DC
			var d := v.length()
			if d < 15.2 or d > Y_FR - 3.2 or absf(v.x) > d * 0.62:
				continue
			var lit := (-0.6 * v.x - 0.8 * v.y) / d
			if d > 17.2:
				cv.p(x2, y2, IRON[clampi(2 + roundi(lit), 1, 4)])
			else:
				var stripe := int(fposmod(v.angle() * 40.0 / TAU, 2.0))
				cv.p(x2, y2, COPPER[clampi(2 + stripe + roundi(lit * 0.8), 1, 4)])
	for k in 10:
		var bp := Y_DC + _dir(k * TAU / 10.0 + 0.3) * (Y_FR - 1.6)
		cv.rivet(roundi(bp.x), roundi(bp.y))
	# brush rocker arms
	for s: float in [-1.0, 1.0]:
		cv.line_f(
			Vector2(Y_DC.x + s * 7.0, Y_DC.y - 2.0),
			Vector2(Y_DC.x + s * 13.0, Y_DC.y - 13.0),
			BRASS[2]
		)


static func _jar_static(cv: Cv, x: int, y: int) -> void:
	cv.rect(x, y + 2, 7, 19, Color(0.08, 0.085, 0.09))
	cv.vl(x, y + 2, y + 20, GLASS)
	cv.vl(x + 6, y + 2, y + 20, GLASS.darkened(0.4))
	cv.hl(x + 1, x + 5, y + 20, GLASS.darkened(0.3))
	cv.hl(x, x + 6, y + 2, GLASS.darkened(0.2))
	cv.rect(x + 1, y + 12, 5, 8, STEEL[2])
	cv.vl(x + 1, y + 12, y + 19, STEEL[3])
	cv.rect(x + 2, y + 1, 3, 1, LEATHER[1])
	cv.vl(x + 3, y - 2, y + 10, BRASS[2])
	cv.p(x + 3, y - 2, BRASS[4])
	cv.p(x + 1, y + 4, Color(0.85, 0.9, 0.9))
	cv.p(x + 1, y + 5, Color(0.6, 0.66, 0.68))


static func _dynamo(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var under := _under(pw)
	var th := ph * TAU
	var arm := ph * float(RATIO["dynamo"]) * TAU
	_lamp(cv, Y_LAMP, pw, t, slot)
	# ring teeth slide (3 per crank revolution); the motor's pinion runs the other way
	var rshift := fposmod(ph * 3.0, 1.0) * 3.0
	for x in range(64, W):
		if fposmod(float(x) - rshift, 3.0) < 1.0:
			cv.p(x, Y_RACK_Y + 3, STEEL[3])
	var pshift := fposmod(ph * 9.0, 1.0) * 2.0
	for x2 in range(79, 85):
		if fposmod(float(x2) + pshift, 2.0) < 1.0:
			cv.p(x2, 6, STEEL[4])
			cv.p(x2, 7, STEEL[2])
	# belt from the crank pulley (behind the frame), the pulley and its pedal crank
	_belt(cv, Y_PUL, Y_PR + 0.6, Y_DC, 4.0, ph, 15, 4.6, Y_DC, Y_FR + 0.4)
	_spokes(cv, Y_PUL, Y_PR - 2.0, 4, th, STEEL, clampf((rate - 1.7) / 1.3, 0.0, 1.0))
	var pedal := Y_PUL + _dir(th + PI * 0.5) * 5.0
	cv.thick(Y_PUL, pedal, STEEL[4], STEEL[1])
	cv.rect(roundi(pedal.x) - 2, roundi(pedal.y), 5, 2, IRON[3])
	cv.hl(roundi(pedal.x) - 2, roundi(pedal.x) + 2, roundi(pedal.y), IRON[4])
	cv.disc_f(Y_PUL, 1.2, BRASS[3])
	# armature: 9 copper-wound slots between laminated iron teeth
	var cx := int(Y_DC.x)
	var cy := int(Y_DC.y)
	for y in range(cy - 15, cy + 16):
		for x3 in range(cx - 15, cx + 16):
			var v := Vector2(x3, y) - Y_DC
			var dist := v.length()
			if dist > 14.6 or dist < 4.6:
				continue
			var su := fposmod((v.angle() - arm) * 9.0 / TAU, 1.0)
			var lit := (-0.6 * v.x - 0.8 * v.y) / dist
			if dist > 13.6:
				cv.p(x3, y, IRON[clampi(1 + roundi(lit), 0, 3)] if su >= 0.5 else COPPER[1])
			elif su < 0.52:
				var wind := 1 if int(dist) % 2 == 0 else 0
				cv.p(x3, y, COPPER[clampi(2 + wind + roundi(lit), 1, 4)])
			elif su < 0.58 or su > 0.96:
				cv.p(x3, y, IRON[0])
			else:
				cv.p(x3, y, IRON[clampi(2 + roundi(lit * 1.2), 0, 4)])
	# commutator
	for y2 in range(cy - 4, cy + 5):
		for x4 in range(cx - 4, cx + 5):
			var v2 := Vector2(x4, y2) - Y_DC
			var d2 := v2.length()
			if d2 > 4.4:
				continue
			if d2 < 1.3:
				cv.p(x4, y2, STEEL[3])
				continue
			var su2 := fposmod((v2.angle() - arm) * 9.0 / TAU, 1.0)
			cv.p(x4, y2, LEATHER[0] if su2 < 0.22 else BRASS[2 if v2.y > 0 else 4])
	cv.p(cx, cy, STEEL[4])
	# brushes and their sparks (more with power; a shower over)
	for s2: float in [-1.0, 1.0]:
		var bx := cx + int(s2 * 5.0)
		cv.rect(bx - (1 if s2 < 0 else 0), cy - 1, 2, 3, Color(0.16, 0.16, 0.17))
		cv.rect(cx + int(s2 * 7.0) - (1 if s2 < 0 else 0), cy - 2, 2, 5, BRASS[2])
		cv.p(cx + int(s2 * 7.0), cy - 2, BRASS[4])
		var n := int(roundf(pw * 3.5 + over * 6.0))
		for k2 in n:
			var seed := floorf(t * 24.0) + k2 * 17.0 + s2 * 5.0 + floorf(ph * 36.0)
			if _h(seed) > 0.25 + 0.4 * under:
				var spread := 2.5 + 4.0 * over
				var sp := Vector2(
					bx + s2 * (_h(seed + 1.0) * spread - 1.0),
					Y_DC.y - 2.0 + _h(seed + 2.0) * (4.0 + 3.0 * over)
				)
				cv.e(roundi(sp.x), roundi(sp.y), ARC_CORE, 0.7 + 0.7 * heat)
		if pw > 0.15:
			cv.glow(bx, cy, 3.5 + 2.5 * heat + 3.0 * over, ARC_GLOW, 0.15 + 0.3 * heat + 0.2 * over)
	# capacitor jars: the charge builds over the crank revolution, then dumps up the bus bar
	var cyc := fposmod(ph, 1.0)
	var max_fill := clampf(pw / 1.15, 0.0, 1.0)
	var charge := 0.0
	var dump := 0.0
	if cyc < 0.8:
		charge = cyc / 0.8 * max_fill
	else:
		dump = 1.0 - (cyc - 0.8) / 0.2
		charge = max_fill * dump
	if over > 0.0:
		charge = maxf(charge, max_fill * over)
	for i in 4:
		_jar_fill(cv, Y_JX + i * 9, Y_JY, clampf(charge * 4.0 - float(i), 0.0, 1.0), t + i)
	if dump > 0.0 and max_fill > 0.4:
		for x5 in range(44, 76):
			cv.e(x5, 5, ARC_CORE, dump * max_fill * 0.55)
		cv.e_line(Vector2(69, 23), Vector2(69, 7), ARC_CORE, dump * max_fill * 0.5)
		cv.glow(82, 8, 7.0, ARC_GLOW, dump * max_fill * 0.4)
	# over: the jars overflow, arcing terminal to terminal, sparks dripping off the shelf
	if over > 0.05:
		var seed2 := floorf(t * 20.0)
		for i2 in 3:
			if _h(seed2 + i2 * 7.0) < 0.35 + 0.5 * over:
				var a := Vector2(Y_JX + 3 + i2 * 9, Y_JY - 2)
				var prev := a
				for k3 in range(1, 10):
					var q := (
						a
						+ Vector2(k3, -2.5 * sin(k3 / 9.0 * PI) + (_h(seed2 + k3 + i2) - 0.5) * 2.0)
					)
					cv.e_line(prev, q, ARC_CORE, 1.0)
					prev = q
				cv.glow(a.x + 4.5, a.y - 2.0, 6.0, ARC_GLOW, 0.4 * over)
		for k4 in 5:
			var fall := fposmod(t * 1.6 + k4 * 0.21, 1.0)
			var fx := float(Y_JX) + 2.0 + _h(float(k4) * 3.7 + floorf(t * 1.6 + k4 * 0.21)) * 34.0
			cv.e(roundi(fx), roundi(52.0 + fall * 5.0), Color(0.75, 0.85, 1.0), over * (1.0 - fall))
		# hot varnish fumes from the frame's vents
		_vent(cv, Vector2(27, 18), Vector2(-0.6, -1.0), over, t, 0.0, Color(0.62, 0.62, 0.62))
		_vent(cv, Vector2(61, 18), Vector2(0.6, -1.0), over, t, 0.5, Color(0.62, 0.62, 0.62))
	# voltmeter, tag
	var volt := clampf(pw / 1.4, 0.0, 1.05) * (0.97 + 0.03 * _h(floorf(t * 20.0)))
	_gauge_needle(cv, Y_VM.x, Y_VM.y, 6, volt, over)
	_tag(cv, 90, 18, slot, pw)


static func _jar_fill(cv: Cv, x: int, y: int, fill: float, seed: float) -> void:
	if fill <= 0.0:
		return
	var lvl := roundi(fill * 17.0)
	for yy in range(y + 20 - lvl, y + 20):
		for xx in range(x + 1, x + 6):
			var k := (
				(0.55 + 0.45 * fill) * (0.55 + 0.2 * _h(float(xx + yy * 3) + floorf(seed * 10.0)))
			)
			cv.e(xx, yy, Color(0.5, 0.68, 1.0), k)
	for xx2 in range(x + 2, x + 5):
		cv.e(xx2, y + 20 - lvl, ARC_CORE, 0.8 * fill)
	cv.glow(x + 3, y + 13, 7.0 + 4.0 * fill, Color(0.4, 0.55, 1.0), 0.2 * fill)


# --- Steam -----------------------------------------------------------------------------------------------
# Cool key: grey-green iron, brass and white steam. A vertical boiler over its firebox (fire =
# power) with the pressure gauge, sight glass and a lever safety valve (it lifts and blows when
# over); the steam pipe and throttle to the cylinder (cut open: the piston), piston rod, crosshead
# in its guides, con-rod to the flywheel; a chain from the flywheel shaft drives the wide shell
# hoist on the right, which lifts big brass shells up to the turret, one per crank revolution.

const GIRON: Array[Color] = [
	Color(0.08, 0.10, 0.095),
	Color(0.17, 0.20, 0.185),
	Color(0.28, 0.32, 0.29),
	Color(0.41, 0.46, 0.41),
	Color(0.58, 0.64, 0.57)
]
const S_FW := Vector2(66, 34)
const S_FR := 10.0
const S_CR := 4.0
const S_L := 16.0
const S_ROD := 15.0
const S_HS := Vector2(97, 50)
const S_HR := 7.0
const S_BX := 2
const S_BW := 20
const S_LAMP := 48
const S_FX := 7
const S_FY := 47
const S_SHELL := 22.0
const STEAM_WHITE := Color(0.93, 0.94, 0.92)


static func _steam_static(cv: Cv) -> void:
	_room_static(cv, S_LAMP)
	var bx := S_BX
	var bw := S_BW
	# hoist shaft: dark well between two rails, cross braces
	cv.rect(84, 3, 26, 54, Color(0.06, 0.07, 0.065))
	cv.vl(83, 3, 56, GIRON[3])
	cv.vl(82, 3, 56, GIRON[0])
	cv.vl(110, 3, 56, GIRON[3])
	cv.vl(111, 3, 56, GIRON[1])
	cv.rect(82, 2, 30, 1, GIRON[4])
	for y in range(8, 54, 12):
		cv.rivet(82, y)
		cv.rivet(110, y)
	# the shaft lamp (cage and bulb)
	cv.rect(95, 3, 5, 1, BRASS[2])
	cv.p(95, 4, STEEL[2])
	cv.p(99, 4, STEEL[2])
	cv.hl(96, 98, 5, Color(1.0, 0.95, 0.8))
	# boiler barrel, shaded round, brass bands
	for x in range(bx, bx + bw):
		var u := float(x - bx) / float(bw - 1)
		var lit := sin(u * PI) * 0.8 + (0.5 - u) * 0.7
		cv.vl(x, 11, 41, GIRON[clampi(1 + roundi(lit * 2.0), 0, 4)])
	for x2 in range(bx + 2, bx + bw - 2):
		cv.p(x2, 9, GIRON[2])
		cv.p(x2, 10, GIRON[3] if x2 < bx + 11 else GIRON[2])
	cv.hl(bx + 4, bx + bw - 5, 8, GIRON[3])
	for yb: int in [11, 26, 40]:
		cv.hl(bx, bx + bw - 1, yb, BRASS[2])
		for x3 in range(bx + 1, bx + bw - 1, 3):
			cv.p(x3, yb, BRASS[4])
	# sight glass frame and the gauge (with its siphon loop)
	cv.rect(bx + 15, 28, 3, 11, BRASS[2])
	cv.vl(bx + 15, 28, 38, BRASS[4])
	cv.vl(bx + 16, 29, 37, Color(0.1, 0.12, 0.12))
	_gauge_face(cv, bx + 8, 19, 5, 0.82)
	cv.p(bx + 8, 25, BRASS[2])
	cv.p(bx + 9, 26, BRASS[2])
	# firebox, its small fire door window, the door swung open
	cv.rect(bx - 1, 42, bw + 2, 14, GIRON[2])
	cv.hl(bx - 1, bx + bw, 42, GIRON[4])
	for x4 in range(bx + 1, bx + bw, 4):
		cv.rivet(x4, 44)
	cv.rect(S_FX - 1, S_FY - 1, 12, 7, GIRON[3])
	cv.rect(S_FX, S_FY, 10, 5, VOID)
	cv.rect(S_FX - 4, S_FY - 1, 3, 7, GIRON[2])
	cv.vl(S_FX - 4, S_FY - 1, S_FY + 5, GIRON[4])
	cv.rect(bx, 55, bw, 2, GIRON[0])
	# safety valve body on the dome; steam pipe with the throttle wheel to the steam chest
	cv.rect(bx + 6, 5, 3, 3, BRASS[2])
	cv.p(bx + 6, 5, BRASS[4])
	cv.p(bx + 3, 5, STEEL[1])
	cv.rect(bx + bw - 1, 6, 15, 3, BRASS[1])
	cv.hl(bx + bw - 1, bx + bw + 13, 6, BRASS[3])
	cv.rect(bx + bw + 11, 6, 3, 19, BRASS[1])
	cv.vl(bx + bw + 11, 6, 24, BRASS[3])
	cv.ring_shaded(28.0, 7.0, 1.5, 3.0, BRASS)
	cv.p(28, 7, BRASS[1])
	# cylinder (cut open) with its steam chest, gland, guides
	var cy := int(S_FW.y)
	cv.rect(26, cy - 6, 18, 13, GIRON[2])
	cv.hl(26, 43, cy - 6, GIRON[4])
	cv.hl(26, 43, cy + 6, GIRON[0])
	cv.rect(30, cy - 10, 11, 4, GIRON[2])
	cv.hl(30, 40, cy - 10, GIRON[4])
	cv.rect(26, cy - 6, 2, 13, GIRON[3])
	cv.rect(42, cy - 6, 2, 13, GIRON[1])
	cv.rect(28, cy - 3, 14, 7, VOID)
	cv.hl(28, 41, cy - 3, Color(0.15, 0.17, 0.16))
	for x5 in range(27, 43, 4):
		cv.rivet(x5, cy - 5)
		cv.rivet(x5, cy + 5)
	cv.rect(44, cy - 2, 2, 4, BRASS[2])
	cv.p(44, cy - 2, BRASS[4])
	cv.hl(46, 55, cy - 4, STEEL[4])
	cv.hl(46, 55, cy - 3, STEEL[1])
	cv.hl(46, 55, cy + 3, STEEL[3])
	cv.hl(46, 55, cy + 4, STEEL[1])
	cv.rect(29, cy + 7, 2, 16, GIRON[2])
	cv.rect(39, cy + 7, 2, 16, GIRON[2])
	# drain cocks under the cylinder
	cv.p(28, cy + 7, BRASS[3])
	cv.p(41, cy + 7, BRASS[3])
	# flywheel pedestal and wheel; the hoist's bottom sprocket body
	cv.rect(63, 43, 7, 14, GIRON[2])
	cv.vl(63, 43, 56, GIRON[4])
	cv.vl(69, 43, 56, GIRON[0])
	cv.rect(60, 54, 13, 3, GIRON[2])
	cv.hl(60, 72, 54, GIRON[4])
	_wheel_static(cv, S_FW, S_FR, 2, STEEL)
	cv.disc_f(S_HS, S_HR - 1.0, GIRON[1])
	cv.ring_shaded(S_HS.x, S_HS.y, S_HR - 2.0, S_HR, STEEL)
	cv.disc_f(S_HS, 3.0, GIRON[3])
	_tag(cv, 24, 12, Color(0.3, 0.3, 0.3), 0.0)


static func _steam(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var th := ph * TAU
	var bx := S_BX
	_lamp(cv, S_LAMP, pw, t, slot)
	# hoist: the up-run carries the shells, the down-run returns empty hooks
	var lift := fposmod(ph, 1.0) * S_SHELL
	for y in range(3, int(S_HS.y)):
		var u := fposmod(float(y) + lift, 4.0)
		cv.p(90, y, STEEL[4] if u < 1.5 else (STEEL[2] if u < 3.0 else IRON[0]))
		cv.p(91, y, STEEL[2] if u < 1.5 else IRON[0])
		var u2 := fposmod(float(y) - lift, 4.0)
		cv.p(104, y, STEEL[3] if u2 < 1.5 else (STEEL[1] if u2 < 3.0 else IRON[0]))
		var hk := fposmod(float(y) - lift, S_SHELL)
		if hk < 1.0:
			cv.p(103, y, STEEL[3])
			cv.p(102, y + 1, STEEL[2])
	cv.teeth(S_HS, S_HR + 0.6, 15, th, STEEL[4])
	for k in 4:
		var sy := S_HS.y - 8.0 - fposmod(float(k) * S_SHELL + lift, 4.0 * S_SHELL)
		var base := roundi(sy)
		if base < 0 or base > 52:
			continue
		# cradle
		cv.hl(90, 99, base + 1, STEEL[4])
		cv.p(99, base, STEEL[3])
		# brass case
		cv.rect(92, base - 8, 6, 9, BRASS[3])
		cv.vl(92, base - 8, base, BRASS[4])
		cv.vl(93, base - 8, base, BRASS[4])
		cv.vl(97, base - 8, base, BRASS[1])
		cv.hl(92, 97, base, BRASS[2])
		cv.hl(91, 98, base - 1, BRASS[2])
		# copper driving band, grey-green projectile with its pointed nose
		cv.hl(92, 97, base - 9, COPPER[3])
		cv.rect(92, base - 14, 6, 5, GIRON[3])
		cv.vl(92, base - 14, base - 10, GIRON[4])
		cv.vl(97, base - 14, base - 10, GIRON[1])
		cv.hl(93, 96, base - 15, GIRON[3])
		cv.hl(94, 95, base - 16, GIRON[4])
	# chain from the flywheel shaft's sprocket to the hoist sprocket's small wheel
	_chain(cv, S_FW, 3.4, S_HS, 3.4, ph, 4, 3.0)
	cv.disc_f(S_HS, 2.6, STEEL[2])
	cv.teeth(S_HS, 3.3, 7, th, STEEL[4])
	cv.p(int(S_HS.x), int(S_HS.y), BRASS[4])
	# flywheel spokes, the shaft sprocket over the hub
	var blur := clampf((rate - 1.7) / 1.3, 0.0, 1.0)
	_spokes(cv, S_FW, S_FR - 2.0, 4, th, STEEL, blur)
	cv.disc_f(S_FW, 2.6, STEEL[2])
	cv.teeth(S_FW, 3.3, 7, th, STEEL[4])
	cv.p(int(S_FW.x), int(S_FW.y), BRASS[4])
	# water level (bobs with the strokes; lower when worked hard)
	var wl := 32 + roundi(sin(th * 2.0) * 0.7 + (1.0 - minf(pw, 1.3)) * 2.5)
	for y3 in range(wl, 38):
		cv.p(bx + 16, y3, Color(0.42, 0.58, 0.64))
	cv.p(bx + 16, wl, Color(0.75, 0.88, 0.9))
	_gauge_needle(cv, bx + 8, 19, 5, clampf(pw / 1.4, 0.0, 1.05), over)
	_tag(cv, 24, 12, slot, pw)
	# the fire (brightness = power) behind the grate bars, a small window in a cool room
	var fire := 0.3 + 0.7 * smoothstep(0.0, 1.3, pw)
	for y4 in range(S_FY, S_FY + 5):
		for x in range(S_FX, S_FX + 10):
			var n := _h(float(x * 13 + y4 * 7) + floorf(t * 12.0) * 3.1)
			var depth := float(y4 - S_FY) / 4.0
			var f := clampf(fire * (0.45 + 0.8 * depth) + (n - 0.5) * 0.55, 0.0, 1.4)
			if f < 0.16:
				continue
			var c := Color(0.5, 0.08, 0.02).lerp(Color(1.0, 0.45, 0.08), clampf(f, 0.0, 1.0))
			if f > 1.0:
				c = c.lerp(Color(1.0, 0.92, 0.65), (f - 1.0) * 2.0)
			cv.p(x, y4, c * 0.5)
			cv.e(x, y4, c, 0.3 + 0.65 * f)
	for x2 in range(S_FX + 2, S_FX + 10, 3):
		cv.vl(x2, S_FY, S_FY + 4, Color(0.07, 0.06, 0.05))
	cv.glow(S_FX + 5, S_FY + 3, 7.0 + 5.0 * fire, Color(1.0, 0.4, 0.1), 0.22 * fire)
	# safety valve lever: lifts when over (the weight rises), and the valve roars
	var tip := 2 if over > 0.3 else 0
	cv.line_f(Vector2(bx + 3, 4), Vector2(bx + 17, 4 - tip), STEEL[4])
	cv.rect(bx + 16, 3 - tip, 3, 3, GIRON[3])
	cv.p(bx + 16, 3 - tip, GIRON[4])
	# piston, rod, crosshead, con-rod
	var pin := S_FW + _dir(th) * S_CR
	var xh := pin.x - sqrt(S_L * S_L - pow(pin.y - S_FW.y, 2.0))
	var xp := xh - S_ROD
	var cy := int(S_FW.y)
	var pxi := roundi(xp)
	var xhi := roundi(xh)
	cv.rect(pxi - 1, cy - 3, 3, 7, BRASS[2])
	cv.vl(pxi - 1, cy - 3, cy + 3, BRASS[4])
	cv.vl(pxi + 1, cy - 3, cy + 3, BRASS[1])
	cv.rect(pxi + 2, cy - 1, xhi - pxi - 2, 2, STEEL[3])
	cv.hl(pxi + 2, xhi, cy - 1, STEEL[4])
	cv.rect(44, cy - 2, 2, 4, BRASS[2])
	cv.p(44, cy - 2, BRASS[4])
	cv.rect(xhi - 2, cy - 2, 4, 5, BRASS[2])
	cv.hl(xhi - 2, xhi + 1, cy - 2, BRASS[4])
	cv.vl(xhi + 1, cy - 2, cy + 2, BRASS[1])
	cv.p(xhi, cy, STEEL[4])
	cv.thick(Vector2(xh, S_FW.y), pin, STEEL[4], STEEL[1])
	cv.disc_f(pin, 1.5, BRASS[2])
	cv.p(roundi(pin.x), roundi(pin.y), BRASS[4])
	# live steam: a thin wisp at the gland in band, the drain cocks spitting and the safety
	# valve blowing when over
	var stroke := fposmod(ph * 2.0, 1.0)
	if heat > 0.3:
		var wa := fposmod(t * 1.3, 1.0)
		_puff(
			cv,
			Vector2(45.0 + wa * 3.0, cy - 3.0 - wa * 5.0),
			0.8 + wa * 1.6,
			STEAM_WHITE,
			0.45 * heat * (1.0 - wa)
		)
	if over > 0.05:
		for k2 in 6:
			var age := fposmod(t * 2.4 + k2 / 6.0, 1.0)
			var c2 := Vector2(bx + 8.0 + age * 12.0 + sin(t * 3.0 + k2) * 1.2, 3.0 - age * 2.0)
			_puff(cv, c2, 1.6 + age * 5.0, STEAM_WHITE, over * 0.85 * (1.0 - age * 0.8))
		var sa := fposmod(stroke * 2.0, 1.0)
		for side: float in [28.0, 41.0]:
			var on := 1.0 if (side < 30.0) == (stroke < 0.5) else 0.45
			var dc := Vector2(side, cy + 8.0)
			_puff(
				cv,
				dc + Vector2((side - 34.5) * 0.25 * sa, sa * 6.0),
				1.5 + sa * 4.0,
				STEAM_WHITE,
				over * 0.9 * on * (1.0 - sa * 0.8)
			)


# --- Arc generator ---------------------------------------------------------------------------------------
# Hero: a tall Jacob's ladder filling the middle, its arc climbing twice per crank revolution
# (weak and low under band, doubled and spraying sparks over). Bottom left, the alternator side-on
# (finned housing, rotor poles sliding past its window) driven by the rider's small flywheel; its
# current goes to the induction coil (the interrupter chatters), then to the horns and to the
# carbon arc searchlight (top right, brightness = power, beam out to the right). Bottom right, the
# bow-gun belt feed advances out of the ammo box. Cold key: blue-white light, olive and copper.

const A_FW := Vector2(27, 48)
const A_FR := 6.0
const A_LAMP := 24
const A_LX := 84
const A_LY := 7
const A_HL0 := Vector2(58, 50)
const A_HL1 := Vector2(45, 4)
const A_HR0 := Vector2(62, 50)
const A_HR1 := Vector2(75, 4)
const A_AM := Vector2i(78, 38)


static func _arc_static(cv: Cv) -> void:
	_room_static(cv, A_LAMP)
	var wire := Color(0.08, 0.07, 0.06)
	# wires: alternator -> induction coil -> horns and the lamp
	cv.vl(12, 22, 40, wire)
	cv.hl(12, 37, 22, wire)
	cv.vl(37, 22, 25, wire)
	cv.vl(41, 14, 25, wire)
	cv.hl(41, 83, 14, wire)
	cv.hl(42, 82, 13, Color(0.28, 0.2, 0.12))
	cv.hl(39, 55, 54, wire)
	cv.hl(39, 65, 55, wire)
	# alternator: finned housing, the window onto its rotor, slip-ring end, feet
	cv.rect(3, 41, 18, 15, OLIVE[2])
	cv.hl(3, 20, 41, OLIVE[4])
	cv.hl(3, 20, 55, OLIVE[0])
	for x in range(4, 20, 2):
		cv.vl(x, 42, 54, OLIVE[1])
	cv.rect(6, 44, 11, 9, BRASS[1])
	cv.rect(7, 45, 9, 7, VOID)
	cv.rect(1, 45, 2, 7, COPPER[2])
	cv.vl(1, 45, 51, COPPER[4])
	cv.rect(21, 47, 6, 2, STEEL[2])
	cv.hl(21, 26, 47, STEEL[4])
	_wheel_static(cv, A_FW, A_FR, 2, STEEL)
	# induction coil on its wooden base
	cv.rect(31, 51, 13, 5, LEATHER[2])
	cv.hl(31, 43, 51, LEATHER[4])
	cv.rect(33, 27, 9, 24, COPPER[2])
	for y in range(28, 50):
		cv.hl(33, 41, y, COPPER[3] if y % 2 == 0 else COPPER[1])
		cv.p(33, y, COPPER[1])
		cv.p(34, y, COPPER[4] if y % 2 == 0 else COPPER[2])
		cv.p(41, y, COPPER[0])
	cv.rect(32, 25, 11, 3, BRASS[2])
	cv.hl(32, 42, 25, BRASS[4])
	cv.rect(32, 49, 11, 2, BRASS[1])
	cv.p(35, 24, BRASS[3])
	cv.p(39, 24, BRASS[3])
	# Jacob's ladder: two tall copper horns on a porcelain insulator
	cv.rect(54, 50, 13, 5, Color(0.66, 0.64, 0.58))
	cv.hl(54, 66, 50, Color(0.86, 0.84, 0.77))
	cv.hl(54, 66, 52, Color(0.44, 0.42, 0.38))
	cv.rect(57, 55, 7, 2, IRON[2])
	cv.line_f(A_HL0 + Vector2(-1, 0), A_HL1 + Vector2(-1, 0), COPPER[1])
	cv.line_f(A_HL0, A_HL1, COPPER[4])
	cv.line_f(A_HR0, A_HR1, COPPER[4])
	cv.line_f(A_HR0 + Vector2(1, 0), A_HR1 + Vector2(1, 0), COPPER[1])
	cv.rect(int(A_HL1.x) - 1, int(A_HL1.y) - 1, 3, 2, COPPER[3])
	cv.rect(int(A_HR1.x) - 1, int(A_HR1.y) - 1, 3, 2, COPPER[3])
	# ammeter
	_gauge_face(cv, A_AM.x, A_AM.y, 5, 0.82)
	cv.vl(A_AM.x, A_AM.y + 6, 55, wire)
	# carbon arc searchlight: ribbed drum, chimney, feed knob, lens ring, peek window
	var lx := A_LX
	var ly := A_LY
	cv.rect(lx, ly, 20, 17, IRON[2])
	for y2 in range(ly, ly + 17):
		var u := float(y2 - ly) / 16.0
		var lit := sin(u * PI) * 0.8 + (0.4 - u) * 0.9
		cv.hl(lx, lx + 19, y2, IRON[clampi(1 + roundi(lit * 2.0), 0, 4)])
	for x2 in range(lx + 2, lx + 19, 3):
		cv.vl(x2, ly + 1, ly + 15, IRON[1])
	cv.rect(lx + 7, ly - 4, 5, 4, IRON[2])
	cv.vl(lx + 7, ly - 4, ly - 1, IRON[4])
	cv.rect(lx + 6, ly - 5, 7, 1, IRON[3])
	cv.rect(lx - 2, ly + 7, 2, 3, BRASS[2])
	cv.rect(lx + 20, ly - 1, 3, 19, BRASS[2])
	cv.vl(lx + 20, ly - 1, ly + 17, BRASS[4])
	cv.vl(lx + 22, ly - 1, ly + 17, BRASS[1])
	cv.rect(lx + 3, ly + 17, 2, 4, IRON[2])
	cv.rect(lx + 15, ly + 17, 2, 4, IRON[2])
	var wx := lx + 4
	var wy := ly + 5
	cv.rect(wx - 1, wy - 1, 13, 9, BRASS[1])
	cv.hl(wx - 1, wx + 11, wy - 1, BRASS[3])
	cv.rect(wx, wy, 11, 7, VOID)
	cv.rect(wx, wy + 3, 4, 1, Color(0.2, 0.2, 0.21))
	cv.rect(wx + 6, wy + 3, 5, 1, Color(0.2, 0.2, 0.21))
	# ammo box and the feed sprocket's bracket
	cv.rect(86, 44, 16, 13, OLIVE[2])
	cv.hl(86, 101, 44, OLIVE[4])
	cv.vl(86, 44, 56, OLIVE[3])
	cv.vl(101, 44, 56, OLIVE[0])
	cv.rect(88, 48, 12, 1, OLIVE[1])
	cv.rect(92, 42, 4, 2, IRON[3])
	for x3 in range(88, 101, 4):
		cv.rivet(x3, 53)
	cv.disc_f(Vector2(105, 41), 2.8, STEEL[2])
	cv.ring_shaded(105.0, 41.0, 1.8, 3.0, STEEL)
	cv.rect(104, 44, 3, 13, IRON[2])


static func _arc(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var under := _under(pw)
	var th := ph * TAU
	_lamp(cv, A_LAMP, pw, t, slot)
	# alternator: rotor poles slide past the window (9 px per crank revolution), the flywheel
	var shift := ph * 9.0
	for y in range(45, 52):
		var u := fposmod(float(y) - shift, 4.0)
		var c := COPPER[3] if u < 1.0 else (COPPER[1] if u < 2.0 else IRON[1])
		for x in range(7, 16):
			cv.p(x, y, c)
	cv.vl(7, 45, 51, Color(0.05, 0.05, 0.05))
	var blur := clampf((rate - 1.7) / 1.3, 0.0, 1.0)
	_spokes(cv, A_FW, A_FR - 1.6, 3, th, STEEL, blur)
	cv.disc_f(A_FW, 1.4, BRASS[3])
	if pw > 0.1 and _h(floorf(t * 30.0)) < 0.3 + 0.6 * heat:
		cv.e(2, 46 + int(_h(floorf(t * 30.0) + 1.0) * 5.0), ARC_CORE, 0.6 + 0.6 * heat)
	# induction coil's interrupter chatters
	var chatter := 1 if (pw > 0.1 and _h(floorf(t * 40.0)) < 0.5 + 0.4 * heat) else 0
	cv.rect(39, 46 - chatter, 2, 3, STEEL[4])
	if chatter == 1 and pw > 0.3:
		cv.e(39, 49, ARC_CORE, 0.7 * heat)
		cv.glow(39, 49, 2.5, ARC_GLOW, 0.3 * heat)
	# Jacob's ladder: the arc climbs twice per crank revolution (doubled when over)
	var strength := smoothstep(0.12, 0.7, pw)
	var reach := 0.25 + 0.75 * smoothstep(0.3, 0.9, pw)
	var arcs := 2 if over > 0.3 else 1
	for ai in arcs:
		var climb := fposmod(ph * 2.0 + float(ai) * 0.5, 1.0)
		if strength <= 0.0 or climb > reach + 0.02:
			continue
		var hk := minf(climb, reach)
		var y_arc := lerpf(47.0, 7.0, hk)
		var f := (A_HL0.y - y_arc) / (A_HL0.y - A_HL1.y)
		var xa := lerpf(A_HL0.x, A_HL1.x, f) + 1.0
		var xb := lerpf(A_HR0.x, A_HR1.x, f) - 1.0
		var seed := floorf(t * 30.0) + floorf(ph * 48.0) * 7.0 + ai * 31.0
		var prev := Vector2(xa, y_arc)
		var bow := 0.5 + 4.0 * hk
		var steps := maxi(int(xb - xa), 2)
		for i in range(1, steps + 1):
			var fr := float(i) / steps
			var jit := (_h(seed + i * 3.1) - 0.5) * (1.0 + 2.5 * hk)
			var q := Vector2(lerpf(xa, xb, fr), y_arc - sin(fr * PI) * bow + jit)
			cv.e_line(prev, q, ARC_CORE, 0.9 + 0.6 * heat)
			if over > 0.3:
				cv.e_line(prev + Vector2(0, 1), q + Vector2(0, 1), ARC_GLOW, 0.6 * over)
			prev = q
		var mid := Vector2((xa + xb) * 0.5, y_arc - bow)
		cv.glow(
			mid.x, mid.y, 7.0 + 8.0 * strength + 6.0 * over, ARC_GLOW, 0.35 * strength + 0.25 * over
		)
		if over > 0.3 and hk > 0.7:
			for k in 6:
				var sp := Vector2(
					xa + _h(seed + k) * (xb - xa), y_arc - bow - _h(seed + k + 9.0) * 5.0
				)
				cv.e(roundi(sp.x), roundi(sp.y), ARC_CORE, over)
	if strength > 0.0:
		cv.glow(60, 48, 3.0, ARC_GLOW, 0.25 * strength)
	if under > 0.5 and _h(floorf(t * 7.0)) < 0.4:
		cv.e(60, 48, ARC_CORE, 0.7)
	# carbon arc searchlight: the arc between the carbon tips; the lens and the beam to the right
	var lamp := clampf(pw / 1.2, 0.0, 1.3) * (0.92 + 0.08 * _h(floorf(t * 25.0)))
	var wx := A_LX + 4
	var wy := A_LY + 5
	if pw > 0.05:
		var tips := Color(1.0, 0.95, 0.85)
		cv.e(wx + 4, wy + 3, tips, 0.5 + 0.8 * lamp)
		cv.e(wx + 5, wy + 3, ARC_CORE, 0.7 + 1.0 * lamp)
		cv.e(wx + 5, wy + 2, ARC_GLOW, 0.5 * lamp)
		cv.e(wx + 6, wy + 3, tips, 0.5 + 0.6 * lamp)
		cv.glow(wx + 5, wy + 3, 4.0 + 3.0 * lamp, Color(0.85, 0.9, 1.0), 0.35 * lamp)
		for y3 in range(A_LY, A_LY + 17):
			var k3 := 1.0 - absf(float(y3 - A_LY - 8)) / 9.0
			cv.e(A_LX + 21, y3, Color(0.92, 0.95, 1.0), lamp * 0.8 * k3)
		for x2 in range(A_LX + 23, W):
			var dx := float(x2 - A_LX - 23)
			var half := 8.0 + dx * 0.5
			for y4 in range(roundi(A_LY + 8 - half), roundi(A_LY + 8 + half) + 1):
				var dy := absf(float(y4) - (A_LY + 8.0)) / half
				cv.e(x2, y4, Color(0.75, 0.82, 1.0), lamp * 0.3 * (1.0 - dy) * (1.0 - dx / 12.0))
	# belt feed: sprocket teeth and the cartridges advancing (4 per crank revolution)
	cv.teeth(Vector2(105, 41), 3.6, 4, th, STEEL[4])
	cv.p(105, 41, BRASS[3])
	var bshift := fposmod(ph * 12.0, 3.0)
	for i2 in 9:
		var s := float(i2) * 3.0 + bshift
		var bp := Vector2.ZERO
		if s < 7.0:
			bp = Vector2(99.0 + s * 0.5, 45.0 - s * 0.6)
		else:
			bp = Vector2(102.5 + (s - 7.0), 37.5)
		if bp.x > 111.0:
			continue
		var bi := Vector2i(roundi(bp.x), roundi(bp.y))
		cv.rect(bi.x, bi.y - 3, 1, 4, BRASS[3])
		cv.p(bi.x, bi.y - 4, COPPER[3])
		cv.p(bi.x, bi.y + 1, STEEL[2])
	# ammeter, tag
	_gauge_needle(cv, A_AM.x, A_AM.y, 5, clampf(pw / 1.4, 0.0, 1.05), over)
	_tag(cv, 4, 4, slot, pw)
	# over: the alternator runs hot, vapour off its fins
	if over > 0.05:
		_vent(cv, Vector2(8, 40), Vector2(-0.3, -1.0), over, t, 0.0, Color(0.85, 0.86, 0.88))
		_vent(cv, Vector2(16, 40), Vector2(0.3, -1.0), over, t, 0.4, Color(0.85, 0.86, 0.88))


# --- Feed (v3, Secondaries) -----------------------------------------------------------------------------
# The crank-driven twin belt feed of the two bow guns. The rider's flywheel (left) drives a chain up
# to the brass feed drum; the drum turns the feed shaft between the two gun lines, whose sprockets
# pull both linked belts up out of their ammo boxes and into the two receivers at the wall (upper
# and lower bow gun), whose bolts cycle in turn. Each crank revolution feeds exactly
# TankFeedState.ROUNDS_PER_REV rounds (one per belt, the belts half a revolution apart, so the guns
# alternate): each belt advances one cartridge pitch, each bolt strokes once, a flash at the
# receiver and a spent casing drops down the chute. A round counter steps per round, a dial reads
# the rate. Warm brass key, olive boxes.

const F_FW := Vector2(15, 45)
const F_FR := 11.0
const F_CS := 3.5
const F_DRUM := Vector2(56, 15)
const F_DR := 7.5
const F_LAMP := 36
## The belts: up from each box's mouth to its gun line, then right into its receiver.
const F_BELT_X: Array[int] = [70, 87]
const F_BELT_Y0 := 43
const F_GUN_Y: Array[int] = [8, 22]
const F_SHAFT_Y := 15
const F_RECV_X := 97
const F_PITCH := 4.0
const F_DIAL := Vector2i(40, 47)


static func _feed_static(cv: Cv) -> void:
	_room_static(cv, F_LAMP)
	# the flywheel on its pedestal
	cv.rect(10, 53, 11, 4, IRON[2])
	cv.hl(10, 20, 53, IRON[4])
	cv.vl(20, 53, 56, IRON[0])
	_wheel_static(cv, F_FW, F_FR, 3, STEEL)
	# the feed drum's bracket from the ceiling beam, the drum's web and its brass rim
	cv.rect(int(F_DRUM.x) - 1, 3, 3, 6, IRON[2])
	cv.vl(int(F_DRUM.x) - 1, 3, 8, IRON[4])
	cv.disc_f(F_DRUM, F_DR, IRON[1])
	cv.ring_shaded(F_DRUM.x, F_DRUM.y, F_DR - 2.0, F_DR, BRASS)
	cv.disc_f(F_DRUM, 2.2, STEEL[2])
	# the feed shaft between the gun lines, out to the receivers
	cv.rect(int(F_DRUM.x), F_SHAFT_Y - 1, F_RECV_X - int(F_DRUM.x), 3, STEEL[1])
	cv.hl(int(F_DRUM.x), F_RECV_X - 1, F_SHAFT_Y - 1, STEEL[3])
	cv.hl(int(F_DRUM.x), F_RECV_X - 1, F_SHAFT_Y + 1, STEEL[0])
	# the guide channels the belts run in
	for k in 2:
		var bx := F_BELT_X[k]
		var gy := F_GUN_Y[k]
		cv.vl(bx - 4, gy + 3, 43, IRON[0])
		cv.vl(bx + 5, gy + 3, 43, IRON[2])
		cv.hl(bx + 5, F_RECV_X - 1, gy + 3, IRON[2])
		cv.hl(bx - 4, F_RECV_X - 1, gy - 3, IRON[0])
	# the ammo boxes (olive, a stencilled band, a brass latch)
	for bx2: int in [62, 79]:
		cv.rect(bx2, 44, 16, 13, OLIVE[2])
		cv.hl(bx2, bx2 + 15, 44, OLIVE[4])
		cv.vl(bx2, 44, 56, OLIVE[3])
		cv.vl(bx2 + 15, 44, 56, OLIVE[0])
		cv.hl(bx2 + 1, bx2 + 14, 50, OLIVE[1])
		cv.rect(bx2 + 6, 47, 4, 2, BRASS[2])
		cv.p(bx2 + 7, 47, BRASS[4])
		cv.rivet(bx2 + 2, 53)
		cv.rivet(bx2 + 12, 53)
	# the two receivers through the wall (the guns are outside): blocks with their bolts' slots
	for gy2 in F_GUN_Y:
		cv.rect(F_RECV_X, gy2 - 3, W - F_RECV_X, 7, IRON[2])
		cv.hl(F_RECV_X, W - 1, gy2 - 3, IRON[4])
		cv.hl(F_RECV_X, W - 1, gy2 + 3, IRON[0])
		cv.vl(F_RECV_X, gy2 - 3, gy2 + 3, IRON[3])
		cv.rect(F_RECV_X + 3, gy2 - 1, 8, 2, VOID)
		cv.rivet(W - 3, gy2 + 1)
	# the spent-casing chute down to a bin on the deck
	cv.rect(100, 26, 4, 17, IRON[1])
	cv.vl(100, 26, 42, IRON[3])
	cv.rect(97, 43, 13, 14, IRON[2])
	cv.hl(97, 109, 43, IRON[4])
	cv.vl(109, 43, 56, IRON[0])
	# the round counter (three drums behind a window) and the rate dial
	cv.rect(12, 5, 17, 9, IRON[0])
	cv.hl(12, 28, 5, IRON[2])
	cv.rect(13, 7, 15, 5, PAPER.darkened(0.25))
	_gauge_face(cv, F_DIAL.x, F_DIAL.y, 5, 0.8)
	cv.vl(F_DIAL.x, F_DIAL.y + 6, 56, Color(0.08, 0.07, 0.06))


static func _feed(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var th := ph * TAU
	_lamp(cv, F_LAMP, pw, t, slot)
	# the flywheel and its crank pin, the chain up to the feed drum (one drum revolution a crank
	# revolution), the drum's spokes and teeth
	var blur := clampf((rate - 1.7) / 1.3, 0.0, 1.0)
	_spokes(cv, F_FW, F_FR - 2.6, 5, th, STEEL, blur)
	cv.disc_f(F_FW, F_CS, BRASS[1])
	var pin := F_FW + _dir(th) * (F_FR - 5.0)
	cv.rect(roundi(pin.x) - 1, roundi(pin.y) - 1, 3, 3, BRASS[3])
	cv.p(roundi(pin.x) - 1, roundi(pin.y) - 1, BRASS[4])
	_chain(cv, F_FW, F_CS + 0.5, F_DRUM, 3.0, ph, 7, 3.0)
	_spokes(cv, F_DRUM, F_DR - 2.2, 4, th, BRASS, blur)
	cv.teeth(F_DRUM, F_DR + 0.4, 10, th, BRASS[4])
	cv.disc_f(F_DRUM, 1.6, BRASS[3])
	# the shaft's sprockets at the belts' corners turn with it
	for k in 2:
		cv.teeth(Vector2(F_BELT_X[k], F_SHAFT_Y), 2.4, 4, th + k * PI, STEEL[4])
	# the two belts: each advances one pitch a revolution, the lower half a revolution behind the
	# upper (the guns alternate); cartridges lie across the belt, brass cases and copper noses
	for k2 in 2:
		var bx := F_BELT_X[k2]
		var gy := F_GUN_Y[k2]
		var up := float(F_BELT_Y0 - gy)
		var run := float(F_RECV_X + 3 - bx)
		var s := fposmod((ph - 0.5 * float(k2)) * F_PITCH, F_PITCH)
		while s < up + run:
			if s < up:
				var y := roundi(F_BELT_Y0 - s)
				cv.p(bx - 3, y, STEEL[1])
				cv.hl(bx - 2, bx + 2, y, BRASS[3])
				cv.hl(bx - 2, bx + 2, y + 1, BRASS[1])
				cv.p(bx - 2, y, BRASS[4])
				cv.rect(bx + 3, y, 1, 2, COPPER[3])
			else:
				var x := roundi(bx + (s - up))
				cv.p(x, gy - 2, STEEL[1])
				cv.vl(x, gy - 1, gy + 1, BRASS[3])
				cv.vl(x + 1, gy - 1, gy + 1, BRASS[1])
				cv.p(x, gy - 1, BRASS[4])
				cv.rect(x, gy + 2, 2, 1, COPPER[3])
			s += F_PITCH
		# the bolt: home (and the shot) at the start of its stroke, back while the next round feeds
		var u := fposmod(ph - 0.5 * float(k2), 1.0)
		var back := roundi(5.0 * sin(u * PI))
		cv.rect(F_RECV_X + 3 + back, gy - 1, 4, 2, BRASS[3])
		cv.p(F_RECV_X + 3 + back, gy - 1, BRASS[4])
		cv.rect(F_RECV_X + 5 + back, gy - 3, 1, 2, BRASS[2])
		if pw > 0.1 and u < 0.12:
			var k3 := (1.0 - u / 0.12) * (0.6 + 0.6 * heat)
			cv.e(W - 1, gy - 1, Color(1.0, 0.85, 0.5), k3)
			cv.e(W - 1, gy, Color(1.0, 0.7, 0.35), k3)
			cv.e(W - 2, gy, Color(1.0, 0.8, 0.45), 0.6 * k3)
			cv.glow(W - 1, gy, 5.0, Color(1.0, 0.7, 0.35), 0.4 * k3)
		# the spent casing drops down the chute
		if pw > 0.05:
			cv.rect(101, roundi(27.0 + u * 14.0), 2, 2, BRASS[3])
	# the counter's drums step one round at a time
	var rounds := floori(ph * float(TankFeedState.ROUNDS_PER_REV))
	for i in 3:
		var dg := posmod(floori(float(rounds) / pow(10.0, 2 - i)), 10)
		var dx := 14 + i * 5
		cv.rect(dx, 7, 4, 5, PAPER if i == 2 else PAPER.darkened(0.1))
		cv.rect(dx + 1, 8 + dg % 3, 2, 1, NEEDLE)
		if dg >= 5:
			cv.p(dx + 1, 10, NEEDLE)
	# the rate dial, the tag
	_gauge_needle(cv, F_DIAL.x, F_DIAL.y, 5, clampf(rate / 2.0, 0.0, 1.05), over)
	_tag(cv, 4, 4, slot, pw)
	# over: the receivers smoke
	if over > 0.05:
		_vent(cv, Vector2(95, 6), Vector2(-0.4, -1.0), over, t, 0.0, Color(0.7, 0.7, 0.72))
		_vent(cv, Vector2(95, 20), Vector2(-0.4, -1.0), over, t, 0.5, Color(0.7, 0.7, 0.72))


static func _steam_lights(cv: Cv, pw: float) -> void:
	var fire := 0.3 + 0.7 * smoothstep(0.0, 1.3, pw)
	cv.light(S_FX + 5, S_FY + 3, 10.0 + 12.0 * fire, Color(1.0, 0.5, 0.2) * (0.2 + 0.5 * fire))
	# the hoist's own caged lamp at the top of the shaft
	cv.light(97, 5, 34.0, _key * (0.75 * (0.85 + 0.15 * minf(pw, 1.0))))


static func _arc_lights(cv: Cv, pw: float) -> void:
	var lamp := clampf(pw / 1.2, 0.0, 1.3)
	cv.light(A_LX + 10, A_LY + 8, 34.0, Color(0.55, 0.65, 1.0) * (0.7 * lamp))
	cv.light(60, 28, 30.0, Color(0.45, 0.55, 1.0) * (0.5 * smoothstep(0.12, 0.7, pw)))


static func _feed_lights(cv: Cv, pw: float) -> void:
	# the breech flashes' glow on the tray, and the counter's little lamp
	cv.light(F_RECV_X, 15, 26.0, Color(1.0, 0.7, 0.4) * (0.3 * smoothstep(0.1, 1.0, pw)))
	cv.light(20, 9, 14.0, _key * 0.35)
	# the caged lamp over the ammo boxes
	cv.light(78, 4, 34.0, _key * (0.7 * (0.85 + 0.15 * minf(pw, 1.0))))


# --- Repair ----------------------------------------------------------------------------------------------
# A helve hammer, the rivet hammer of the Repairs seat, and the card's hero. The flywheel chains to a small cam
# on its shaft, one turn per crank revolution. The cam's lobe lifts a tappet in its guide, the tappet lifts the
# helve about its pillar (a counterweight rocks on the tail), and at the lobe's drop the forged head falls: one
# stroke, and a rivet set, per crank revolution, its sparks on the strike. The patch plate steps one rivet along
# the anvil per stroke, fed down a chute from the rivet pot. To the right the screw press works its platen on
# the stack. The lamp is a pinker copper than the diesel's. Everything moving is a pure function of the crank
# revolutions.

const R_FW := Vector2(14, 45)
const R_FR := 10.0
const R_HUB := 3.5
const R_CAM := Vector2(46, 40)
const R_CAM_R := 3.0
const R_PIVOT := Vector2(30, 19)
const R_HEAD_X := 76.0
## The helve's end: its height with the head down on the plate, and how far the head lifts.
const R_REST_Y := 32.0
const R_HEAD_LIFT := 15.0
## The tappet's and so the cam's lift (px) at the top of the stroke.
const R_LIFT := R_HEAD_LIFT * (46.0 - 30.0) / (76.0 - 30.0)
const R_ANVIL := Rect2i(64, 47, 24, 10)
const R_PLATE_Y := 45
const R_RIVET_PITCH := 5.0
const R_PRESS_X := 100
const R_LAMP := 60
const R_POT := Rect2i(50, 50, 10, 7)
const R_DIAL := Vector2i(15, 13)
## The room's own wall: the card's plain wall under a pinker wash, so its lamp reads copper, not orange.
const R_WALL_WASH := Color(0.92, 0.9, 1.3)
## The share of a revolution the hammer takes to fall.
const R_FALL := 0.12
## Sparks last this share of a revolution after the strike.
const R_SPARK := 0.2


## The hammer's lift (0 down on the plate .. 1 at the top), a pure function of the crank revolutions: the
## cam raises it through the revolution, it falls at the end and strikes on each whole revolution.
static func hammer_lift(revs: float) -> float:
	var f := fposmod(revs, 1.0)
	var up := 1.0 - R_FALL
	if f < up:
		return smoothstep(0.0, up, f)
	var k := (f - up) / R_FALL
	return 1.0 - k * k


## How long since the strike, in revolutions (0..1): the sparks' clock.
static func since_strike(revs: float) -> float:
	return fposmod(revs, 1.0)


## The press's platen (0 open .. 1 closed), once a revolution, shut as the hammer strikes.
static func press_closed(revs: float) -> float:
	return 0.5 + 0.5 * cos(fposmod(revs, 1.0) * TAU)


static func _repair_static(cv: Cv) -> void:
	_room_static(cv, R_LAMP)
	# the room's pinker wall (the machine, drawn after this, keeps its own iron)
	var data := cv.al
	for j in range(0, data.size(), 4):
		data[j] = mini(int(data[j] * R_WALL_WASH.r), 255)
		data[j + 1] = mini(int(data[j + 1] * R_WALL_WASH.g), 255)
		data[j + 2] = mini(int(data[j + 2] * R_WALL_WASH.b), 255)
	cv.al = data
	# the flywheel on its pedestal
	cv.rect(int(R_FW.x) - 6, 53, 13, 4, IRON[2])
	cv.hl(int(R_FW.x) - 6, int(R_FW.x) + 6, 53, IRON[4])
	cv.vl(int(R_FW.x) + 6, 53, 56, IRON[0])
	_wheel_static(cv, R_FW, R_FR, 3, STEEL)
	# the helve's pillar and its bearing, riveted
	cv.rect(27, 21, 7, 36, IRON[2])
	cv.vl(27, 21, 56, IRON[4])
	cv.vl(28, 21, 56, IRON[3])
	cv.vl(33, 21, 56, IRON[0])
	for y in range(25, 54, 6):
		cv.rivet(30, y)
	cv.rect(24, 53, 13, 4, IRON[3])
	cv.hl(24, 36, 53, IRON[4])
	cv.disc_f(R_PIVOT, 4.0, IRON[2])
	cv.ring_shaded(R_PIVOT.x, R_PIVOT.y, 2.6, 4.0, BRASS)
	# the cam's bearing post with its base, and the tappet's guide on a bracket off the post
	cv.rect(int(R_CAM.x) - 2, int(R_CAM.y), 5, 57 - int(R_CAM.y), IRON[1])
	cv.vl(int(R_CAM.x) - 2, int(R_CAM.y), 56, IRON[3])
	cv.vl(int(R_CAM.x) + 2, int(R_CAM.y), 56, IRON[0])
	cv.rect(int(R_CAM.x) - 7, 53, 15, 4, IRON[2])
	cv.hl(int(R_CAM.x) - 7, int(R_CAM.x) + 7, 53, IRON[4])
	cv.rivet(int(R_CAM.x) - 5, 54)
	cv.rivet(int(R_CAM.x) + 5, 54)
	cv.line_f(R_CAM + Vector2(3, -2), R_CAM + Vector2(6, -9), IRON[2])
	cv.line_f(R_CAM + Vector2(6, -9), R_CAM + Vector2(2, -12), IRON[2])
	cv.rect(int(R_CAM.x) - 2, int(R_CAM.y) - 13, 5, 2, BRASS[1])
	cv.hl(int(R_CAM.x) - 2, int(R_CAM.x) + 2, int(R_CAM.y) - 13, BRASS[2])
	# the anvil: a block on its stump, a horn on the far side
	cv.rect(R_ANVIL.position.x, R_ANVIL.position.y, R_ANVIL.size.x, 4, STEEL[1])
	cv.hl(R_ANVIL.position.x, R_ANVIL.end.x - 1, R_ANVIL.position.y, STEEL[4])
	cv.hl(R_ANVIL.position.x, R_ANVIL.end.x - 1, R_ANVIL.position.y + 1, STEEL[3])
	cv.vl(R_ANVIL.end.x - 1, R_ANVIL.position.y, R_ANVIL.position.y + 3, STEEL[0])
	cv.hl(R_ANVIL.end.x, R_ANVIL.end.x + 3, R_ANVIL.position.y, STEEL[3])
	cv.hl(R_ANVIL.end.x, R_ANVIL.end.x + 1, R_ANVIL.position.y + 1, STEEL[1])
	cv.rect(R_ANVIL.position.x + 5, 51, R_ANVIL.size.x - 10, 6, IRON[1])
	cv.vl(R_ANVIL.position.x + 5, 51, 56, IRON[3])
	cv.vl(R_ANVIL.end.x - 6, 51, 56, IRON[0])
	cv.rect(R_ANVIL.position.x + 2, 55, R_ANVIL.size.x - 4, 2, IRON[2])
	cv.rivet(R_ANVIL.position.x + 7, 52)
	cv.rivet(R_ANVIL.end.x - 8, 52)
	# the pot of rivets and the chute from it up to the plate
	cv.rect(R_POT.position.x, R_POT.position.y, R_POT.size.x, R_POT.size.y, IRON[1])
	cv.hl(R_POT.position.x - 1, R_POT.end.x, R_POT.position.y, IRON[4])
	cv.vl(R_POT.position.x, R_POT.position.y, R_POT.end.y - 1, IRON[3])
	cv.vl(R_POT.end.x - 1, R_POT.position.y, R_POT.end.y - 1, IRON[0])
	cv.line_f(Vector2(R_POT.position.x + 2, 49), Vector2(63, 44), IRON[3])
	cv.line_f(Vector2(R_POT.position.x + 2, 50), Vector2(63, 45), IRON[0])
	# the press: screw frame from the ceiling to the deck, a stack of plates at its foot
	cv.rect(R_PRESS_X - 8, 6, 2, 51, IRON[2])
	cv.vl(R_PRESS_X - 8, 6, 56, IRON[4])
	cv.rect(R_PRESS_X + 7, 6, 2, 51, IRON[1])
	cv.rect(R_PRESS_X - 8, 6, 17, 4, IRON[2])
	cv.hl(R_PRESS_X - 8, R_PRESS_X + 8, 6, IRON[4])
	for k in 5:
		var py := 55 - k * 2
		cv.hl(R_PRESS_X - 5, R_PRESS_X + 5, py, COPPER[2 if k % 2 == 0 else 1])
		cv.hl(R_PRESS_X - 5, R_PRESS_X + 5, py + 1, IRON[0])
		cv.p(R_PRESS_X - 5, py, COPPER[4])
	# the rate dial
	_gauge_face(cv, R_DIAL.x, R_DIAL.y, 5, 0.8)


static func _repair_lights(cv: Cv, pw: float) -> void:
	var heat := 0.3 + 0.7 * smoothstep(0.0, 1.3, pw)
	# the flywheel's own caged lamp, so the crank end reads
	cv.light(R_FW.x + 6.0, 36.0, 24.0, _key * (0.35 * (0.85 + 0.15 * minf(pw, 1.0))))
	cv.light(
		R_POT.position.x + 5, R_POT.position.y - 1, 10.0, Color(1.0, 0.5, 0.42) * (0.1 + 0.2 * heat)
	)
	# the work light over the anvil: the head is what the room is lit for
	cv.light(R_HEAD_X, 26.0, 24.0, Color(0.95, 0.8, 0.8) * 0.3)


static func _repair(cv: Cv, ph: float, pw: float, t: float, slot: Color, rate: float) -> void:
	var heat := _heat(pw)
	var over := _over(pw)
	var th := ph * TAU
	var lift := hammer_lift(ph)
	_lamp(cv, R_LAMP, pw, t, slot)
	# the rivets in the pot glow with the power; one rides the chute each stroke
	for x in range(R_POT.position.x + 2, R_POT.end.x - 1):
		var hot := 0.3 + 0.5 * heat * (0.65 + 0.35 * _h(float(x) + floorf(t * 8.0)))
		cv.p(x, R_POT.position.y + 1, Color(0.3, 0.14, 0.12))
		cv.e(x, R_POT.position.y + 1, Color(1.0, 0.45, 0.28), hot)
	var fr := fposmod(ph, 1.0)
	var ride := Vector2(R_POT.position.x + 2, 48).lerp(Vector2(63, 43), smoothstep(0.1, 0.85, fr))
	cv.rect(roundi(ride.x), roundi(ride.y), 2, 1, Color(0.7, 0.42, 0.3))
	cv.e(roundi(ride.x), roundi(ride.y), Color(1.0, 0.45, 0.28), 0.5)
	# the flywheel, its chain to the cam's sprocket (1:1)
	_spokes(cv, R_FW, R_FR - 2.6, 5, th, STEEL, clampf((rate - 1.7) / 1.3, 0.0, 1.0))
	cv.disc_f(R_FW, R_HUB, BRASS[1])
	var pin := R_FW + _dir(th) * (R_FR - 5.0)
	cv.rect(roundi(pin.x) - 1, roundi(pin.y) - 1, 3, 3, BRASS[3])
	_chain(cv, R_FW, R_HUB + 0.4, R_CAM, R_HUB + 0.4, ph, 11, 3.0)
	cv.teeth(R_CAM, R_HUB + 0.6, 8, th, BRASS[2])
	# the small cam: a snail with a shaded rim on its shaft; its radius is the hammer's lift round the turn
	var cri := ceili(R_CAM_R + R_LIFT) + 1
	for y in range(int(R_CAM.y) - cri, int(R_CAM.y) + cri + 1):
		for x2 in range(int(R_CAM.x) - cri, int(R_CAM.x) + cri + 1):
			var v := Vector2(x2, y) - R_CAM
			var rho := v.length()
			# the point of the cam on top (angle -90 degrees) has the lift of the moment
			var along := fposmod((v.angle() + PI * 0.5) / TAU - ph, 1.0)
			var rim := R_CAM_R + R_LIFT * hammer_lift(_cam_at(along, ph))
			if rho > rim + 0.4:
				continue
			var lit := (-0.6 * v.x - 0.8 * v.y) / maxf(rho, 0.01)
			var c: Color = STEEL[clampi(1 + roundi(lit * 1.2), 0, 3)]
			if rho > rim - 0.8:
				c = STEEL[0] if lit < 0.2 else STEEL[3]
			cv.p(x2, y, c)
	cv.disc_f(R_CAM, 1.8, IRON[0])
	cv.disc_f(R_CAM + Vector2(-0.4, -0.4), 1.0, BRASS[3])
	# the tappet riding on the cam, the helve on the tappet, the head on the helve's end
	var end_y := R_REST_Y - R_HEAD_LIFT * lift
	var slope := (end_y - R_PIVOT.y) / (R_HEAD_X - R_PIVOT.x)
	var at_rod := R_PIVOT.y + slope * (R_CAM.x - R_PIVOT.x)
	var rod_low := R_CAM.y - R_CAM_R - R_LIFT * lift
	cv.rect(int(R_CAM.x), roundi(at_rod), 2, maxi(roundi(rod_low - at_rod), 1), STEEL[1])
	cv.vl(int(R_CAM.x), roundi(at_rod), roundi(rod_low), STEEL[3])
	var end := Vector2(R_HEAD_X, end_y)
	# the tail behind the pillar, its counterweight rocking the other way
	var tail := R_PIVOT - Vector2(11.0, 11.0 * slope)
	cv.line_f(R_PIVOT + Vector2(0, 1), tail + Vector2(0, 1), IRON[0])
	cv.line_f(R_PIVOT, tail, LEATHER[2])
	cv.rect(roundi(tail.x) - 3, roundi(tail.y) - 2, 6, 6, IRON[0])
	cv.rect(roundi(tail.x) - 2, roundi(tail.y) - 1, 4, 4, IRON[2])
	cv.hl(roundi(tail.x) - 2, roundi(tail.x) + 1, roundi(tail.y) - 1, IRON[4])
	# the helve: a thick ash beam with iron straps
	for k in 4:
		cv.line_f(
			R_PIVOT + Vector2(0, k - 1),
			end + Vector2(0, k - 2),
			[LEATHER[4], LEATHER[3], LEATHER[2], IRON[0]][k]
		)
	for k2 in 3:
		var q := R_PIVOT.lerp(end, 0.3 + k2 * 0.22)
		cv.vl(roundi(q.x), roundi(q.y) - 2, roundi(q.y) + 1, IRON[3])
	cv.disc_f(R_PIVOT, 1.6, BRASS[4])
	_repair_head(cv, end)
	# the patch plate on the anvil, stepping one rivet along per stroke; the newest rivet is hot
	var step := smoothstep(0.1, 0.5, fposmod(ph, 1.0)) * R_RIVET_PITCH
	cv.rect(56, R_PLATE_Y, 38, 2, COPPER[1])
	cv.hl(56, 93, R_PLATE_Y, COPPER[3])
	var rx := 0.0
	while rx < 40.0:
		var px := int(R_HEAD_X - rx - step + R_RIVET_PITCH)
		if px >= 56 and px < 94:
			cv.p(px, R_PLATE_Y - 1, STEEL[3])
			cv.p(px, R_PLATE_Y, STEEL[4])
		rx += R_RIVET_PITCH
	var since := since_strike(ph)
	var fresh := 1.0 - since / 0.75
	if fresh > 0.0 and pw > 0.05:
		cv.e(int(R_HEAD_X - step + R_RIVET_PITCH), R_PLATE_Y - 1, Color(1.0, 0.5, 0.25), fresh)
	# the strike: sparks fly out from under the head; a shower over power
	if since < R_SPARK and pw > 0.05:
		var k3 := 1.0 - since / R_SPARK
		var n := int(roundf(6.0 + 8.0 * heat + 10.0 * over))
		var st := floorf(ph)
		for i in n:
			var a := -PI * (0.05 + 0.9 * _h(st + float(i) * 1.7))
			var sp := 12.0 + 18.0 * _h(st + float(i) * 3.1)
			var u := since / R_SPARK
			var sq := (
				Vector2(R_HEAD_X, R_PLATE_Y - 1.0) + _dir(a) * sp * u + Vector2(0.0, 9.0 * u * u)
			)
			cv.e(roundi(sq.x), roundi(sq.y), Color(1.0, 0.72, 0.42), k3 * (0.8 + 0.6 * heat))
		cv.glow(
			R_HEAD_X, R_PLATE_Y - 1.0, 13.0, Color(1.0, 0.55, 0.36), 0.5 * k3 * (0.4 + 0.6 * heat)
		)
	# the press: the screw turns, the crosshead comes down on the stack
	var closed := press_closed(ph)
	var ph_y := 20 + roundi(closed * 22.0)
	cv.vl(R_PRESS_X, 2, ph_y, STEEL[2])
	for y2 in range(3, ph_y, 2):
		cv.p(R_PRESS_X, y2 + (1 if fposmod(ph * 2.0, 1.0) > 0.5 else 0), STEEL[4])
	cv.rect(R_PRESS_X - 6, ph_y, 13, 3, IRON[2])
	cv.hl(R_PRESS_X - 6, R_PRESS_X + 6, ph_y, IRON[4])
	cv.hl(R_PRESS_X - 6, R_PRESS_X + 6, ph_y + 2, IRON[0])
	cv.teeth(Vector2(R_PRESS_X, 3), 4.0, 6, th, BRASS[3])
	# the dial, the tag
	_gauge_needle(cv, R_DIAL.x, R_DIAL.y, 5, clampf(rate / 2.0, 0.0, 1.05), over)
	_tag(cv, 4, 4, slot, pw)
	if over > 0.05:
		_vent(cv, Vector2(48, 44), Vector2(0.2, -1.0), over, t, 0.0, Color(0.6, 0.55, 0.52))


## The forged head, the card's hero: a poll with its eye for the helve, a broad banded cheek, a narrow striking
## face, every edge outlined and lit from above.
static func _repair_head(cv: Cv, end: Vector2) -> void:
	var x := int(end.x)
	var y := roundi(end.y)
	# outline
	cv.rect(x - 6, y - 4, 13, 4, IRON[0])
	cv.rect(x - 9, y - 1, 19, 9, IRON[0])
	cv.rect(x - 5, y + 8, 11, 4, IRON[0])
	# the poll, the eye the helve enters
	cv.rect(x - 5, y - 3, 11, 3, STEEL[3])
	cv.hl(x - 5, x + 5, y - 3, STEEL[4])
	cv.rect(x - 2, y - 2, 4, 2, IRON[0])
	# the cheek
	cv.rect(x - 8, y, 17, 7, STEEL[2])
	cv.hl(x - 8, x + 8, y, STEEL[4])
	cv.hl(x - 8, x + 8, y + 1, STEEL[3])
	cv.vl(x - 8, y + 1, y + 6, STEEL[3])
	cv.vl(x + 8, y + 1, y + 6, STEEL[1])
	cv.hl(x - 8, x + 8, y + 6, STEEL[1])
	cv.hl(x - 7, x + 7, y + 4, STEEL[1])
	cv.rivet(x - 6, y + 2)
	cv.rivet(x, y + 2)
	cv.rivet(x + 5, y + 2)
	# the striking face
	cv.rect(x - 4, y + 7, 9, 4, STEEL[2])
	cv.vl(x - 4, y + 7, y + 10, STEEL[3])
	cv.vl(x + 4, y + 7, y + 10, STEEL[1])
	cv.hl(x - 4, x + 4, y + 10, STEEL[4])


## The cam's lift at `along` of the way round from its top: the lift the hammer had `along` of a revolution
## ago, so the point on top always carries the lift of now.
static func _cam_at(along: float, ph: float) -> float:
	return ph - along


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
