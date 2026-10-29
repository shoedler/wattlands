extends RefCounted
## The seat bays' machines and crew for the v3 tank mock, drawn per frame into the cutaway openings
## (clipped to them). Each bay: a pedal station on the left (the rider, 20 px, on a crank with a
## chain ring; an empty seat is a bare saddle and a still crank) whose chain runs to the machine's
## input, and the machine filling about two thirds of the bay's height:
##   diesel      flywheel, crankcase, cylinder block, three heads with bobbing rockers, injector
##               lines, exhaust manifold to the roof, the drive shaft down through the floor
##   arc gen     dynamo drum, switchboard with dials and a knife switch, the glass arc tower with
##               carbon rods and a cold arc, cables to the roof (the searchlight)
##   dynamo      drum dynamo with turning windings and commutator sparks, gearbox with the laying
##               handwheel, a shaft to the turret ring's bevel gear in the ceiling
##   belt feed   two-by-two ammunition boxes, a feed gearbox with a 4-point star, two belts to the
##               twin guns' receivers, a spent-case chute into a bin
## Every motion is a function of (t, rpm): deterministic.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const OUT := Color("#0b0806")
const ST0 := Color("#1e1d1b")
const ST1 := Color("#3a3834")
const ST2 := Color("#5f5c55")
const ST3 := Color("#8e8a7e")
const ST4 := Color("#c9c4b4")
const BR0 := Color("#5e4220")
const BR1 := Color("#a07c40")
const BR2 := Color("#e0bd74")
const CU0 := Color("#6e3a1f")
const CU1 := Color("#b0643a")
const CU2 := Color("#e09a62")
const FIRE0 := Color("#c2461c")
const FIRE1 := Color("#ff9a3a")
const FIRE2 := Color("#ffe08a")
const ARC := Color("#f2f8ff")
const ARC_GLOW := Color("#9fd0ff")
const SKIN := Color("#d0a274")
const SKIN_D := Color("#8a6040")
const UNI := Color("#7a6a42")
const UNI_D := Color("#3e3424")
const UNI_L := Color("#a8925a")
const TROU := Color("#3c3c46")
const TROU_D := Color("#24242c")
const BOOT := Color("#120d09")
const AMMO := Color("#3c4128")
const AMMO_L := Color("#5c6440")
const AMMO_D := Color("#262a19")
const GREEN_M := Color("#2c3a34")
const GREEN_L := Color("#4e665a")
const SLOT: Array[Color] = [Color("#D55E00"), Color("#0072B2"), Color("#F0E442"), Color("#009E73")]

static var clip := PackedByteArray()
static var cw := 0
static var ch := 0


static func set_clip(c: PackedByteArray, w: int, h: int) -> void:
	clip = c
	cw = w
	ch = h


static func p(i: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= cw or y >= ch or clip[y * cw + x] == 0:
		return
	i.set_pixel(x, y, c)


static func pr(i: Image, r: Rect2i, c: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			p(i, x, y, c)


static func pl(i: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := maxi(ceili(maxf(absf(b.x - a.x), absf(b.y - a.y))), 1)
	for k in n + 1:
		var q := a.lerp(b, float(k) / float(n))
		p(i, floori(q.x), floori(q.y), c)


## An outlined, top-lit box: fill `c`, a lit top row `hi`, a dark right column and bottom row.
static func box(i: Image, r: Rect2i, c: Color, hi: Color, lo: Color) -> void:
	pr(i, r, OUT)
	var inner := r.grow(-1)
	pr(i, inner, c)
	pr(i, Rect2i(inner.position.x, inner.position.y, inner.size.x, 1), hi)
	pr(i, Rect2i(inner.end.x - 1, inner.position.y + 1, 1, inner.size.y - 1), lo)
	pr(i, Rect2i(inner.position.x, inner.end.y - 1, inner.size.x, 1), lo)


static func glow(i: Image, c: Vector2, rad: float, col: Color, a: float) -> void:
	for y in range(floori(c.y - rad), ceili(c.y + rad) + 1):
		for x in range(floori(c.x - rad), ceili(c.x + rad) + 1):
			if x < 0 or y < 0 or x >= cw or y >= ch or clip[y * cw + x] == 0:
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / rad
			if d < 1.0:
				Px.add(i, x, y, col, a * (1.0 - d) * (1.0 - d))


static func dial(i: Image, c: Vector2, load: float) -> void:
	for y in range(floori(c.y) - 3, floori(c.y) + 4):
		for x in range(floori(c.x) - 3, floori(c.x) + 4):
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if dd < 1.9:
				p(i, x, y, Color("#e8dcc0"))
			elif dd < 2.9:
				p(i, x, y, BR2 if y < c.y else BR1)
			elif dd < 3.5:
				p(i, x, y, OUT)
	var na := PI * (1.1 + 0.8 * clampf(load, 0.0, 1.0))
	pl(i, c, c + Vector2(cos(na), sin(na)) * 1.6, OUT)


## A chain between two sprockets (centres a and b, radius ra and rb): two runs whose links travel.
static func chain(i: Image, a: Vector2, b: Vector2, ra: float, rb: float, phase: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	for side in [-1.0, 1.0]:
		var p0: Vector2 = a + n * ra * side
		var p1: Vector2 = b + n * rb * side
		var ln := p0.distance_to(p1)
		var m := maxi(ceili(ln), 1)
		for k in m + 1:
			var q := p0.lerp(p1, float(k) / float(m))
			var s := fposmod(float(k) - phase * side, 2.0)
			p(i, floori(q.x), floori(q.y), BR2 if s < 1.0 else ST0)


## A spoked wheel at c, radius r, turned ang (teeth > 0: a sprocket).
static func wheel(i: Image, c: Vector2, r: float, ang: float, rim: Color, spokes := 4, teeth := 0) -> void:
	for y in range(floori(c.y - r) - 2, ceili(c.y + r) + 2):
		for x in range(floori(c.x - r) - 2, ceili(c.x + r) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rho := d.length()
			var phi := atan2(d.y, d.x) - ang
			if teeth > 0 and rho > r and rho < r + 1.2 and cos(teeth * phi) > 0.2:
				p(i, x, y, rim)
				continue
			if rho > r + 0.6:
				continue
			if rho > r - 0.4:
				p(i, x, y, OUT)
				continue
			var lit := -d.y - d.x * 0.3 > 0.0
			if rho > r - 1.6:
				p(i, x, y, rim.lightened(0.3) if lit else rim)
				continue
			if rho < 1.4:
				p(i, x, y, BR2 if rho < 0.8 else BR1)
				continue
			var sp := fposmod(phi, TAU / spokes)
			sp = minf(sp, TAU / spokes - sp) * rho
			if sp < 0.8:
				p(i, x, y, rim.darkened(0.1) if lit else rim.darkened(0.3))


# --- Crew -----------------------------------------------------------------------------------------------


## A pedal station (facing right) from x `x0`, standing on floor row `fy`: saddle, frame, chain ring
## and cranks; the rider (slot colour cap) unless `slot` < 0. Returns the chain ring's centre.
static func seat(i: Image, x0: int, fy: int, ang: float, slot: int) -> Vector2:
	var sad := Vector2(x0 + 5.5, fy - 9.5)
	var cc := Vector2(x0 + 10.5, fy - 4.5)
	var bar := Vector2(x0 + 14.5, fy - 13.5)
	pr(i, Rect2i(x0 + 2, fy - 1, 14, 1), ST2)
	pl(i, Vector2(x0 + 4, fy - 1), sad + Vector2(0, 1), ST2)
	pl(i, Vector2(x0 + 5, fy - 1), sad + Vector2(1, 1), ST1)
	pl(i, sad + Vector2(0.5, 1), cc, ST2)
	pl(i, cc, bar, ST2)
	pl(i, cc + Vector2(1, 0), bar + Vector2(1, 1), ST1)
	pl(i, bar + Vector2(-1, 0), bar + Vector2(1, 0), ST3)
	for k in 12:
		var a := TAU * k / 12.0 + ang
		var q := cc + Vector2(cos(a), sin(a)) * 2.5
		p(i, floori(q.x), floori(q.y), BR2 if k % 3 == 0 else BR1)
	p(i, floori(cc.x), floori(cc.y), BR2)
	var cv := Vector2(cos(ang), sin(ang)) * 3.0
	var f1 := cc + cv
	var f2 := cc - cv
	if slot < 0:
		pl(i, cc, f1, ST3)
		pl(i, cc, f2, ST2)
		pr(i, Rect2i(floori(f1.x) - 1, floori(f1.y), 3, 1), ST3)
		pr(i, Rect2i(floori(f2.x) - 1, floori(f2.y), 3, 1), ST2)
		pr(i, Rect2i(floori(sad.x) - 2, floori(sad.y), 5, 1), Color("#4a2c18"))
		pr(i, Rect2i(floori(sad.x) - 2, floori(sad.y) + 1, 5, 1), OUT)
		return cc
	var hip := sad + Vector2(0, -1)
	_leg(i, hip, f2, TROU_D, true)
	pl(i, cc, f2, ST2)
	pr(i, Rect2i(floori(sad.x) - 2, floori(sad.y), 5, 1), Color("#4a2c18"))
	var sh := hip + Vector2(3, -6)
	pl(i, hip + Vector2(-1, 0), sh + Vector2(-1, 0), UNI_D)
	pl(i, hip, sh, UNI)
	pl(i, hip + Vector2(1, -1), sh + Vector2(1, 0), UNI_L)
	p(i, floori(hip.x), floori(hip.y) - 1, BR0)
	p(i, floori(hip.x) + 1, floori(hip.y) - 1, BR0)
	var el := sh + Vector2(3, 3)
	pl(i, sh + Vector2(1, 0), el, UNI_L)
	pl(i, el, bar + Vector2(-1, 0), UNI)
	p(i, floori(bar.x) - 1, floori(bar.y), SKIN)
	var hd := Vector2i(floori(sh.x) - 1, floori(sh.y) - 4)
	pr(i, Rect2i(hd.x - 1, hd.y + 3, 4, 1), UNI_D)
	pr(i, Rect2i(hd.x, hd.y, 3, 3), SKIN)
	p(i, hd.x, hd.y + 1, SKIN_D)
	p(i, hd.x, hd.y + 2, SKIN_D)
	p(i, hd.x + 2, hd.y + 1, Color("#3a2414"))
	var sc := SLOT[slot % SLOT.size()]
	pr(i, Rect2i(hd.x, hd.y - 1, 3, 1), sc.lightened(0.2))
	p(i, hd.x - 1, hd.y, sc.darkened(0.3))
	p(i, hd.x + 3, hd.y, sc.darkened(0.2))
	p(i, hd.x + 3, hd.y - 1, sc)
	_leg(i, hip + Vector2(1, 0), f1, TROU, false)
	pl(i, cc, f1, ST3)
	return cc


static func _leg(i: Image, hip: Vector2, foot: Vector2, col: Color, far: bool) -> void:
	var d := foot - hip
	var dl := clampf(d.length(), 0.1, 9.0)
	var half := dl * 0.5
	var up := sqrt(maxf(4.6 * 4.6 - half * half, 0.0))
	var n := Vector2(d.y, -d.x).normalized()
	if n.x < 0.0:
		n = -n
	var knee := hip + d.normalized() * half + n * up
	pl(i, hip, knee, col)
	pl(i, hip + Vector2(0, 1), knee + Vector2(0, 1), col.darkened(0.25))
	pl(i, knee, foot, col.darkened(0.15))
	p(i, floori(foot.x), floori(foot.y), BOOT)
	p(i, floori(foot.x) + 1, floori(foot.y), BOOT if not far else ST0)
	p(i, floori(foot.x) - 1, floori(foot.y), BOOT)


# --- Machines -------------------------------------------------------------------------------------------


## The drive bay's diesel.
static func diesel(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 3
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, r.position.x + 3, fy, ang, slot)
	var x0 := r.position.x + 21
	var x1 := mini(r.end.x - 2, x0 + 40)
	var eng := ang * 2.4 if slot >= 0 else 0.0
	for y in range(fy - 4, fy + 3):
		p(i, x0 + 15, y, ST3 if (y + floori(eng * 2.0)) % 3 == 0 else ST1)
		p(i, x0 + 16, y, ST1)
	box(i, Rect2i(x0 + 3, fy - 12, x1 - x0 - 3, 12), ST1, ST3, ST0)
	box(i, Rect2i(x0 + 8, fy - 24, x1 - x0 - 9, 13), ST2, ST3, ST1)
	for x in range(x0 + 10, x1 - 2, 3):
		p(i, x, fy - 21, ST1)
		p(i, x, fy - 16, ST1)
		p(i, x + 1, fy - 9, ST3)
	var heads := clampi((x1 - x0 - 10) / 6, 2, 5)
	for k in heads:
		var hx := x0 + 9 + k * 6
		box(i, Rect2i(hx, fy - 29, 6, 6), CU1, CU2, CU0)
		var bob := roundi((sin(eng + k * 2.1) + 1.0))
		pr(i, Rect2i(hx + 2, fy - 31 - bob, 2, 2 + bob), ST3)
		p(i, hx + 2, fy - 31 - bob, ST4)
		pl(i, Vector2(x0 + 6, fy - 20), Vector2(hx + 1, fy - 24), CU2 if k % 2 == 0 else CU1)
	box(i, Rect2i(x0 + 3, fy - 23, 6, 8), BR1, BR2, BR0)
	var ex := x1 - 3
	pr(i, Rect2i(x0 + 9, fy - 34, ex - x0 - 7, 2), CU1)
	pr(i, Rect2i(x0 + 9, fy - 34, ex - x0 - 7, 1), CU2)
	pr(i, Rect2i(ex, r.position.y, 3, fy - 32 - r.position.y), CU0)
	pr(i, Rect2i(ex, r.position.y, 1, fy - 32 - r.position.y), CU2)
	pr(i, Rect2i(ex - 1, fy - 40, 5, 1), BR1)
	var fw := Vector2(x0 + 6.5, fy - 9.5)
	chain(i, cc, fw, 2.5, 3.0, t * rpm / 60.0 * 9.0)
	wheel(i, fw, 8.0, eng, ST2, 6)
	wheel(i, fw, 3.0, eng, BR1, 3, 8)
	dial(i, Vector2(x1 - 5.5, fy - 6.5), 0.7 if slot >= 0 else 0.0)
	if slot >= 0:
		glow(i, Vector2(x0 + 18, fy - 27), 10.0, Color("#ff9a3a"), 0.16 + 0.06 * sin(t * 13.0))


## The lights bay's arc generator.
static func arcgen(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, r.position.x + 3, fy, ang, slot)
	var x0 := r.position.x + 21
	var x1 := mini(r.end.x - 2, x0 + 34)
	var dc := Vector2(x0 + 5.5, fy - 9.5)
	box(i, Rect2i(x0 - 1, fy - 3, 14, 3), ST1, ST2, ST0)
	var sp := ang * 3.0 if on else 0.0
	for y in range(floori(dc.y) - 7, floori(dc.y) + 8):
		for x in range(floori(dc.x) - 7, floori(dc.x) + 8):
			var d := Vector2(x + 0.5, y + 0.5) - dc
			var rho := d.length()
			if rho > 6.6:
				continue
			if rho > 5.8:
				p(i, x, y, OUT)
			elif rho > 4.4:
				p(i, x, y, GREEN_L if d.y < -1.0 else GREEN_M)
			elif rho > 1.4:
				var st := fposmod(atan2(d.y, d.x) - sp, TAU / 8.0)
				p(i, x, y, CU2 if st < 0.3 else (CU1 if rho > 2.6 else CU0))
			else:
				p(i, x, y, BR2)
	chain(i, cc, dc, 2.5, 2.0, t * rpm / 60.0 * 9.0)
	var pb := Rect2i(x0, fy - 32, 12, 15)
	box(i, pb, Color("#1c2321"), Color("#3e4a46"), OUT)
	dial(i, Vector2(pb.position.x + 3.5, pb.position.y + 4.5), 0.8 if on else 0.0)
	dial(i, Vector2(pb.position.x + 8.5, pb.position.y + 4.5), 0.55 if on else 0.0)
	var kx := pb.position.x + 4
	var ky := pb.position.y + 10
	pr(i, Rect2i(kx - 1, ky + 2, 6, 2), Color("#3a2c1e"))
	if on:
		pl(i, Vector2(kx + 2, ky + 2), Vector2(kx + 2, ky - 2), BR2)
	else:
		pl(i, Vector2(kx + 2, ky + 2), Vector2(kx + 6, ky), BR1)
	var tx := x1 - 9
	var top := fy - 33
	box(i, Rect2i(tx, top, 9, 3), BR1, BR2, BR0)
	box(i, Rect2i(tx, fy - 3, 9, 3), BR1, BR2, BR0)
	for y in range(top + 3, fy - 3):
		p(i, tx, y, OUT)
		p(i, tx + 8, y, OUT)
		for x in range(tx + 1, tx + 8):
			p(i, x, y, Color("#1a2a2e") if not on else Color("#2a4250"))
		p(i, tx + 1, y, Color("#5a7a80"))
	var ay := (top + fy) / 2
	pr(i, Rect2i(tx + 4, top + 3, 1, ay - top - 5), ST1)
	pr(i, Rect2i(tx + 4, ay + 2, 1, fy - 3 - ay - 2), ST1)
	p(i, tx + 4, ay - 2, ST3)
	p(i, tx + 4, ay + 2, ST3)
	if on:
		var fl := Px.h2(floori(t * 30.0), 3, 9)
		for y in range(ay - 1, ay + 2):
			p(i, tx + 4, y, ARC)
		p(i, tx + 3 + floori(fl * 3.0), ay - 1 + floori(fl * 2.0), ARC_GLOW)
		glow(i, Vector2(tx + 4.5, ay + 0.5), 18.0, ARC_GLOW, 0.55 + 0.25 * fl)
		glow(i, Vector2(tx + 4.5, ay + 0.5), 5.0, ARC, 0.7)
	pl(i, Vector2(tx + 3, top), Vector2(tx + 3, r.position.y), OUT)
	pl(i, Vector2(tx + 5, top), Vector2(tx + 5, r.position.y), Color("#3a1a10"))
	pl(i, Vector2(pb.position.x + 6, pb.position.y), Vector2(pb.position.x + 6, r.position.y), OUT)


## The gun bay's dynamo with the laying gearbox.
static func dynamo(i: Image, r: Rect2i, t: float, rpm: float, slot: int, laying: bool) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, r.position.x + 3, fy, ang, slot)
	var x0 := r.position.x + 21
	var x1 := mini(r.end.x - 2, x0 + 40)
	var d := Rect2i(x0, fy - 16, x1 - x0, 15)
	box(i, d, GREEN_M, GREEN_L, Color("#1a2420"))
	var win := Rect2i(d.position.x + 4, d.position.y + 3, d.size.x - 9, d.size.y - 6)
	for y in range(win.position.y, win.end.y):
		for x in range(win.position.x, win.end.x):
			var s := fposmod(float(x) + (ang * 4.0 if on else 0.0), 3.0)
			p(i, x, y, CU2 if s < 1.0 else (CU1 if y > win.position.y else CU0))
	pr(i, Rect2i(d.position.x, d.end.y, d.size.x, 1), ST1)
	var cx := d.end.x - 4
	pr(i, Rect2i(cx, d.position.y + 3, 2, d.size.y - 6), BR1)
	p(i, cx, d.position.y + 2, ST0)
	p(i, cx, d.end.y - 3, ST0)
	if on and Px.h2(floori(t * 24.0), 1, 4) > 0.4:
		p(i, cx + 1, d.position.y + 2, ARC)
		glow(i, Vector2(cx + 1.5, d.position.y + 2.5), 5.0, ARC_GLOW, 0.5)
	var pul := Vector2(x0 + 3.5, fy - 8.5)
	chain(i, cc, pul, 2.5, 2.5, t * rpm / 60.0 * 9.0)
	wheel(i, pul, 3.0, ang * 3.0, BR1, 3)
	var gb := Rect2i(x0 + 2, fy - 27, x1 - x0 - 4, 11)
	box(i, gb, ST2, ST3, ST1)
	var hw := Vector2(gb.position.x + 5.5, gb.position.y + 5.5)
	wheel(i, hw, 4.0, (t * 3.0 if laying else 0.0), BR1, 3)
	var sx := gb.end.x - 4
	pr(i, Rect2i(sx, r.position.y + 6, 2, gb.position.y - r.position.y - 6), ST2)
	pr(i, Rect2i(sx, r.position.y + 6, 1, gb.position.y - r.position.y - 6), ST4)
	var gy := r.position.y + 8
	var gph := t * 6.0 if laying else 0.0
	for x in range(sx - 8, sx + 10):
		var tooth := fposmod(float(x) + gph, 3.0) < 1.6
		p(i, x, gy - 1, BR2 if tooth else BR0)
		p(i, x, gy, BR1)
		p(i, x, gy + 1, BR0)
	dial(i, Vector2(gb.end.x - 3.5, gb.position.y - 4.5), 0.75 if on else 0.05)


## The secondaries bay's crank-driven twin belt feed; `feed` is the receivers' position.
static func beltfeed(i: Image, r: Rect2i, t: float, rpm: float, slot: int, feed: Vector2) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var revs := t * rpm / 60.0 if on else 0.0
	var ang := revs * TAU
	var cc := seat(i, r.position.x + 3, fy, ang, slot)
	var star := Vector2(r.position.x + 29.5, fy - 19.5)
	pr(i, Rect2i(floori(star.x) - 1, floori(star.y) + 3, 3, fy - floori(star.y) - 3), ST1)
	pr(i, Rect2i(floori(star.x) - 1, floori(star.y) + 3, 1, fy - floori(star.y) - 3), ST2)
	box(i, Rect2i(floori(star.x) - 6, floori(star.y) - 6, 12, 11), ST2, ST3, ST1)
	chain(i, cc, star, 2.5, 2.5, revs * 9.0)
	for y in range(floori(star.y) - 6, floori(star.y) + 7):
		for x in range(floori(star.x) - 6, floori(star.x) + 7):
			var d := Vector2(x + 0.5, y + 0.5) - star
			var rho := d.length()
			var phi := atan2(d.y, d.x) - ang * 0.5
			var rr := 3.0 + 2.0 * maxf(cos(4.0 * phi), 0.0)
			if rho < rr:
				p(i, x, y, BR2 if d.y < -1.0 else (BR1 if rho > 1.2 else BR0))
			elif rho < rr + 0.8:
				p(i, x, y, OUT)
	var bx := r.position.x + 38
	for col in 2:
		for row in 2:
			var b := Rect2i(bx + col * 11, fy - 9 - row * 9, 11, 9)
			box(i, b, AMMO, AMMO_L, AMMO_D)
			pr(i, Rect2i(b.position.x + 3, b.position.y + 3, 5, 1), AMMO_D)
			p(i, b.position.x + 5, b.position.y + 1, BR1)
	var rc := Rect2i(floori(feed.x) - 6, floori(feed.y) - 4, 11, 8)
	box(i, rc, ST2, ST3, ST1)
	p(i, rc.position.x + 2, rc.position.y + 2, BR1)
	p(i, rc.position.x + 2, rc.position.y + 5, BR1)
	for k in 2:
		var a := Vector2(bx + 5 + k * 11, fy - 18)
		var path := [a, a + Vector2(0, -3), star + Vector2(-1 + k * 2, -5), Vector2(rc.position.x, rc.position.y + 2 + k * 3)]
		var ph := revs * 2.0 * 2.0
		var acc := 0.0
		for s in path.size() - 1:
			var p0: Vector2 = path[s]
			var p1: Vector2 = path[s + 1]
			var n := maxi(ceili(p0.distance_to(p1)), 1)
			for m in n:
				var q := p0.lerp(p1, float(m) / float(n))
				var u := fposmod(acc + m - ph, 2.0)
				p(i, floori(q.x), floori(q.y), BR2 if u < 1.0 else BR0)
				p(i, floori(q.x), floori(q.y) + 1, ST0)
			acc += n
	var bin := Rect2i(rc.position.x - 2, fy - 6, 9, 6)
	box(i, bin, ST1, ST2, ST0)
	pl(i, Vector2(rc.position.x + 3, rc.end.y), Vector2(bin.position.x + 4, bin.position.y), ST2)
	pl(i, Vector2(rc.position.x + 4, rc.end.y), Vector2(bin.position.x + 5, bin.position.y), ST1)
	if on:
		for k in 3:
			var f := fposmod(revs * 2.0 + k / 3.0, 1.0)
			var y := lerpf(float(rc.end.y + 1), float(bin.position.y), f)
			var x := lerpf(rc.position.x + 2.0, bin.position.x + 3.0, f)
			p(i, floori(x), floori(y), BR2)


# --- r3: v2-style stations ---------------------------------------------------------------------------


## The drive room's long diesel (the reference's engine): two finned cylinders lying on a cradle,
## a flywheel at the rear end on the pedals' chain, rockers bobbing, the exhaust to the roof.
static func diesel_long(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 3
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, r.position.x + 3, fy, ang, slot)
	var eng := ang * 2.4 if slot >= 0 else 0.0
	var x0 := r.position.x + 30
	var x1 := r.end.x - 4
	box(i, Rect2i(x0 + 2, fy - 3, x1 - x0 - 4, 3), ST1, ST2, ST0)
	for k in 2:
		var y0 := fy - 11 - k * 9
		for y in range(y0, y0 + 8):
			for x in range(x0, x1):
				var row := y - y0
				var col := ST2 if row < 3 else (ST1 if row < 6 else ST0)
				if row == 0:
					col = ST3
				if (x - x0) % 3 == 0 and row > 0 and row < 7:
					col = col.darkened(0.45)
				if x == x0 or x == x1 - 1 or row == 7:
					col = OUT
				p(i, x, y, col)
		pr(i, Rect2i(x0 - 2, y0 + 1, 2, 6), ST3)
		pr(i, Rect2i(x1, y0 + 1, 2, 6), ST1)
	var n := (x1 - x0 - 6) / 7
	for k in n:
		var hx := x0 + 4 + k * 7
		var bob := roundi(sin(eng + k * 1.9) + 1.0)
		pr(i, Rect2i(hx, fy - 22, 4, 2), CU1)
		pr(i, Rect2i(hx + 1, fy - 24 - bob, 2, 2 + bob), ST3)
	pr(i, Rect2i(x1 - 3, r.position.y + 2, 2, fy - 22 - r.position.y - 2), CU0)
	pr(i, Rect2i(x1 - 3, r.position.y + 2, 1, fy - 22 - r.position.y - 2), CU1)
	var fw := Vector2(x0 - 6.5, fy - 9.5)
	chain(i, cc, fw, 2.5, 3.0, t * rpm / 60.0 * 9.0)
	wheel(i, fw, 7.5, eng, ST2, 6)
	wheel(i, fw, 2.5, eng, BR1, 3, 7)
	if slot >= 0:
		glow(i, Vector2((x0 + x1) * 0.5, fy - 20), 14.0, Color("#ff8a30"), 0.14 + 0.05 * sin(t * 13.0))


## The gun room's dynamo, face on (v2's card): copper windings round a dark hub, turning; sparks.
static func dynamo_round(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, r.position.x + 3, fy, ang, slot)
	var rad := minf(12.0, (fy - r.position.y - 6) * 0.5)
	var dc := Vector2(r.end.x - rad - 4.5, fy - rad - 1.5)
	box(i, Rect2i(floori(dc.x - rad) + 1, fy - 3, floori(rad * 2.0) - 1, 3), ST1, ST2, ST0)
	var sp := ang * 3.0 if on else 0.0
	for y in range(floori(dc.y - rad) - 1, ceili(dc.y + rad) + 2):
		for x in range(floori(dc.x - rad) - 1, ceili(dc.x + rad) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - dc
			var rho := d.length()
			if rho > rad + 0.6:
				continue
			var phi := atan2(d.y, d.x)
			if rho > rad - 0.4:
				p(i, x, y, OUT)
			elif rho > rad - 2.0:
				p(i, x, y, ST3 if d.y < -rad * 0.3 else ST1)
				if fposmod(phi * 8.0 / TAU, 1.0) < 0.15:
					p(i, x, y, BR1)
			elif rho > rad * 0.35:
				var seg := fposmod((phi - sp) * 14.0 / TAU, 1.0)
				var c := CU2 if seg < 0.3 else (CU1 if seg < 0.75 else CU0)
				if d.y > rad * 0.4:
					c = c.darkened(0.35)
				p(i, x, y, c)
			elif rho > 2.0:
				p(i, x, y, Color("#1a1210"))
			else:
				p(i, x, y, BR2)
	chain(i, cc, dc, 2.5, 3.0, t * rpm / 60.0 * 9.0)
	if on:
		var fl := Px.h2(floori(t * 24.0), 5, 1)
		var sa := fl * TAU
		var spk := dc + Vector2(cos(sa), sin(sa)) * (rad - 1.0)
		p(i, floori(spk.x), floori(spk.y), ARC)
		glow(i, spk, 6.0, ARC_GLOW, 0.5)
		glow(i, dc, rad + 6.0, Color("#ff8a40"), 0.12)
	pr(i, Rect2i(floori(dc.x) - 1, r.position.y + 2, 2, floori(dc.y - rad) - r.position.y - 2), ST2)
	pr(i, Rect2i(floori(dc.x) - 1, r.position.y + 2, 1, floori(dc.y - rad) - r.position.y - 2), ST4)


## The lights room's arc generator (v2's card): a copper coil, two carbon rods in a V, the arc at
## its foot, cold light; cables up to the searchlight.
static func arc_v(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, r.position.x + 3, fy, ang, slot)
	var x0 := r.position.x + 20
	var coil := Rect2i(x0, fy - 16, 7, 14)
	box(i, Rect2i(x0 - 1, fy - 2, 9, 2), ST1, ST2, ST0)
	for y in range(coil.position.y, coil.end.y):
		for x in range(coil.position.x, coil.end.x):
			var band := (y + (floori(ang * 2.0) if on else 0)) % 2 == 0
			var c := CU2 if band else CU0
			if x == coil.position.x or x == coil.end.x - 1:
				c = OUT
			p(i, x, y, c)
	pr(i, Rect2i(x0 - 1, coil.position.y - 1, 9, 1), ST3)
	chain(i, cc, Vector2(x0 + 3.5, fy - 6.5), 2.5, 2.0, t * rpm / 60.0 * 9.0)
	var tip := Vector2(r.end.x - 9.5, fy - 7.5)
	var la := Vector2(tip.x - 8.0, r.position.y + 6.0)
	var ra := Vector2(tip.x + 8.0, r.position.y + 6.0)
	pr(i, Rect2i(floori(la.x) - 2, floori(la.y) - 2, floori(ra.x - la.x) + 5, 2), BR1)
	pl(i, la, tip + Vector2(-1, -1), ST1 if not on else ST3)
	pl(i, ra, tip + Vector2(1, -1), ST1 if not on else ST3)
	pl(i, la + Vector2(1, 0), tip + Vector2(0, -1), ST0)
	pl(i, ra + Vector2(-1, 0), tip + Vector2(0, -1), ST0)
	box(i, Rect2i(floori(tip.x) - 4, fy - 4, 9, 4), ST1, ST2, ST0)
	if on:
		var fl := Px.h2(floori(t * 30.0), 3, 9)
		p(i, floori(tip.x), floori(tip.y), ARC)
		p(i, floori(tip.x) - 1, floori(tip.y), ARC)
		p(i, floori(tip.x) + floori(fl * 3.0) - 1, floori(tip.y) - 1, ARC_GLOW)
		glow(i, tip, 22.0, ARC_GLOW, 0.65 + 0.25 * fl)
		glow(i, tip, 5.0, ARC, 0.8)
	pl(i, Vector2(ra.x + 2, ra.y), Vector2(ra.x + 2, r.position.y), OUT)
	pl(i, Vector2(ra.x + 3, ra.y), Vector2(ra.x + 3, r.position.y), Color("#3a1a10"))
