extends RefCounted
## The seat bays' machines and crew for the v3 tank mock, drawn per frame into the cutaway
## openings (clipped to them): the pedalling crewman (slot-coloured cap) or an empty saddle, the
## diesel, the arc generator, the steam loader with its stowage rack and hoist, the dynamo, and the
## crank-driven twin belt feed. Every motion comes from (t, rpm, phase): deterministic.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const OUT := Color("#0b0806")
const ST0 := Color("#22211f")
const ST1 := Color("#3f3d39")
const ST2 := Color("#67645c")
const ST3 := Color("#9a968a")
const ST4 := Color("#cfcabb")
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
const SKIN := Color("#c99c70")
const SKIN_D := Color("#8a6040")
const UNI := Color("#4a4632")
const UNI_D := Color("#2e2b1f")
const UNI_L := Color("#6a6446")
const BOOT := Color("#120d09")
const AMMO := Color("#3c4128")
const AMMO_L := Color("#5a6040")
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


static func glow(i: Image, c: Vector2, rad: float, col: Color, a: float) -> void:
	for y in range(floori(c.y - rad), ceili(c.y + rad) + 1):
		for x in range(floori(c.x - rad), ceili(c.x + rad) + 1):
			if x < 0 or y < 0 or x >= cw or y >= ch or clip[y * cw + x] == 0:
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / rad
			if d < 1.0:
				Px.add(i, x, y, col, a * (1.0 - d) * (1.0 - d))


## A moving chain from a to b: links alternate bright/dark and travel with `phase` (px).
static func chain(i: Image, a: Vector2, b: Vector2, phase: float) -> void:
	var ln := a.distance_to(b)
	var n := maxi(ceili(ln), 1)
	for k in n + 1:
		var q := a.lerp(b, float(k) / float(n))
		var s := fposmod(float(k) - phase, 3.0)
		p(i, floori(q.x), floori(q.y), BR1 if s < 1.0 else ST0)


## A spoked wheel (flywheel, pulley) at c, radius r, turned ang.
static func wheel(i: Image, c: Vector2, r: float, ang: float, rim: Color, spokes := 4) -> void:
	for y in range(floori(c.y - r) - 1, ceili(c.y + r) + 1):
		for x in range(floori(c.x - r) - 1, ceili(c.x + r) + 1):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rho := d.length()
			if rho > r + 0.6:
				continue
			if rho > r - 0.4:
				p(i, x, y, OUT)
				continue
			var lit := -d.y > 0.0
			if rho > r - 1.6:
				p(i, x, y, rim.lightened(0.25) if lit else rim)
				continue
			if rho < 1.3:
				p(i, x, y, BR2)
				continue
			var phi := atan2(d.y, d.x) - ang
			var sp := fposmod(phi, TAU / spokes)
			sp = minf(sp, TAU / spokes - sp) * rho
			if sp < 0.8:
				p(i, x, y, rim.darkened(0.15))


# --- Crew ---------------------------------------------------------------------------------------


## A pedalling station facing right: saddle top at `hip`, crank angle `ang`; `slot` -1 = empty.
## Returns the crank centre (for the chain).
static func seat(i: Image, hip: Vector2i, ang: float, slot: int, floor_y: int) -> Vector2:
	var hv := Vector2(hip) + Vector2(0.5, 0.5)
	var cc := hv + Vector2(4, 7)
	var bar := hv + Vector2(8, -4)
	# frame
	pl(i, hv + Vector2(0, 1), cc, ST2)
	pl(i, cc, bar, ST2)
	pl(i, bar, bar + Vector2(1, 0), ST3)
	pl(i, cc + Vector2(-3, 0), Vector2(cc.x - 4, floor_y), ST1)
	pl(i, cc + Vector2(3, -1), Vector2(cc.x + 4, floor_y), ST1)
	pr(i, Rect2i(floori(cc.x) - 6, floor_y - 1, 13, 1), ST1)
	# crank sprocket
	for k in 8:
		var a := TAU * k / 8.0 + ang
		p(i, floori(cc.x + cos(a) * 2.0), floori(cc.y + sin(a) * 2.0), BR1)
	var f1 := cc + Vector2(cos(ang), sin(ang)) * 2.6
	var f2 := cc - Vector2(cos(ang), sin(ang)) * 2.6
	if slot < 0:
		pr(i, Rect2i(hip.x - 2, hip.y, 5, 1), Color("#3a2414"))
		pl(i, cc, f1, ST3)
		pl(i, cc, f2, ST2)
		return cc
	var hp := hv + Vector2(0, -1)
	_leg(i, hp, f2, UNI_D, true)
	pr(i, Rect2i(hip.x - 2, hip.y, 5, 1), Color("#3a2414"))
	var sh := hp + Vector2(2.5, -7)
	# torso (2 px), arm to the bar
	pl(i, hp, sh, UNI)
	pl(i, hp + Vector2(-1, 0), sh + Vector2(-1, 0), UNI_D)
	pl(i, hp + Vector2(1, -1), sh + Vector2(1, 0), UNI_L)
	pl(i, sh + Vector2(1, 1), bar + Vector2(-1, 0), UNI_L)
	p(i, floori(bar.x), floori(bar.y), SKIN)
	# head and cap
	var hd := Vector2i(floori(sh.x), floori(sh.y) - 4)
	pr(i, Rect2i(hd.x, hd.y, 3, 3), SKIN)
	p(i, hd.x, hd.y + 2, SKIN_D)
	p(i, hd.x + 2, hd.y + 1, SKIN_D)
	var sc := SLOT[slot % SLOT.size()]
	pr(i, Rect2i(hd.x - 1, hd.y - 1, 4, 1), sc)
	pr(i, Rect2i(hd.x, hd.y - 2, 3, 1), sc.lightened(0.15))
	p(i, hd.x + 3, hd.y, sc.darkened(0.35))
	_leg(i, hp, f1, UNI, false)
	return cc


static func _leg(i: Image, hip: Vector2, foot: Vector2, col: Color, far: bool) -> void:
	var d := foot - hip
	var dl := clampf(d.length(), 0.1, 8.8)
	var half := dl * 0.5
	var up := sqrt(maxf(4.5 * 4.5 - half * half, 0.0))
	var n := Vector2(d.y, -d.x).normalized()
	if n.x < 0.0:
		n = -n
	var knee := hip + d.normalized() * half + n * up
	pl(i, hip, knee, col)
	pl(i, knee, foot, col.darkened(0.2))
	p(i, floori(foot.x), floori(foot.y), BOOT)
	p(i, floori(foot.x) + 1, floori(foot.y), BOOT if not far else ST0)


# --- Machines ------------------------------------------------------------------------------------


## The drive bay: crewman, flywheel, a three-head diesel with bobbing rockers, exhaust to the roof.
static func diesel(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 3
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, Vector2i(r.position.x + 6, fy - 12), ang, slot, fy)
	var x0 := r.position.x + 18
	var x1 := mini(r.end.x - 2, x0 + 50)
	var fw := Vector2(x0 + 6.5, fy - 8.5)
	chain(i, cc + Vector2(0, -2), fw + Vector2(0, -2), t * rpm / 60.0 * 9.0)
	chain(i, cc + Vector2(0, 2), fw + Vector2(0, 2), -t * rpm / 60.0 * 9.0)
	wheel(i, fw, 6.5, ang * 2.2, ST2, 5)
	var bx := x0 + 13
	var block := Rect2i(bx, fy - 14, x1 - bx, 14)
	pr(i, block, ST1)
	pr(i, Rect2i(bx, fy - 14, block.size.x, 1), ST3)
	pr(i, Rect2i(bx, fy - 4, block.size.x, 4), ST0)
	for x in range(bx + 2, x1 - 1, 4):
		p(i, x, fy - 12, ST3)
		p(i, x, fy - 6, ST0)
	# gauge
	p(i, bx + 3, fy - 9, BR2)
	p(i, bx + 4, fy - 9, ST4)
	p(i, bx + 4, fy - 8, OUT)
	var heads := maxi((x1 - bx - 2) / 8, 2)
	for k in heads:
		var hx := bx + 2 + k * 8
		pr(i, Rect2i(hx, fy - 19, 6, 5), ST2)
		pr(i, Rect2i(hx, fy - 19, 6, 1), ST4)
		pr(i, Rect2i(hx + 5, fy - 18, 1, 4), ST0)
		var bob := roundi((sin(ang * 2.2 + k * 2.1) + 1.0) * 1.0)
		pr(i, Rect2i(hx + 2, fy - 21 - bob, 2, 2 + bob), BR1)
		p(i, hx + 2, fy - 21 - bob, BR2)
	# exhaust manifold and stack to the ceiling
	var ex := x1 - 2
	pr(i, Rect2i(bx + 4, fy - 24, ex - bx - 3, 2), CU0)
	pr(i, Rect2i(bx + 4, fy - 24, ex - bx - 3, 1), CU1)
	pr(i, Rect2i(ex, r.position.y, 2, fy - 22 - r.position.y), CU0)
	pr(i, Rect2i(ex, r.position.y, 1, fy - 22 - r.position.y), CU1)
	# a heat shimmer of warm light over the heads
	glow(i, Vector2(bx + block.size.x * 0.5, fy - 16), 10.0, Color("#ff9a3a"), 0.18 + 0.05 * sin(t * 13.0))


## The lights bay: dynamo drum, switchboard with dials and a knife switch, the carbon arc lamp.
static func arcgen(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, Vector2i(r.position.x + 6, fy - 12), ang, slot, fy)
	var x0 := r.position.x + 18
	var x1 := r.end.x - 2
	var dc := Vector2(x0 + 5.5, fy - 5.5)
	chain(i, cc, dc, t * rpm / 60.0 * 9.0)
	# dynamo drum with turning copper windings
	for y in range(floori(dc.y) - 5, floori(dc.y) + 6):
		for x in range(floori(dc.x) - 5, floori(dc.x) + 6):
			var d := Vector2(x + 0.5, y + 0.5) - dc
			var rho := d.length()
			if rho > 5.4:
				continue
			if rho > 4.4:
				p(i, x, y, OUT)
			elif rho > 3.2:
				p(i, x, y, ST2 if d.y < 0 else ST1)
			else:
				var st := fposmod(atan2(d.y, d.x) - ang * 3.0, TAU / 6.0)
				p(i, x, y, CU2 if st < 0.35 else CU1 if rho > 1.2 else BR0)
	# switchboard
	var pb := Rect2i(x0 + 12, fy - 28, mini(x1 - x0 - 12, 24), 24)
	pr(i, pb, Color("#1b201e"))
	pr(i, Rect2i(pb.position.x, pb.position.y, pb.size.x, 1), ST3)
	pr(i, Rect2i(pb.position.x, pb.end.y - 1, pb.size.x, 1), OUT)
	pr(i, Rect2i(pb.position.x, pb.position.y, 1, pb.size.y), OUT)
	var load := 0.75 if on else 0.0
	for k in 2:
		var gc := Vector2(pb.position.x + 4.5 + k * 7, pb.position.y + 5.5)
		for y in range(floori(gc.y) - 3, floori(gc.y) + 4):
			for x in range(floori(gc.x) - 3, floori(gc.x) + 4):
				var dd := Vector2(x + 0.5, y + 0.5).distance_to(gc)
				if dd < 2.2:
					p(i, x, y, Color("#e8dcc0"))
				elif dd < 3.2:
					p(i, x, y, BR1)
		var na := PI + (load + 0.08 * sin(t * 7.0 + k)) * PI * (0.8 if k == 0 else 0.6)
		pl(i, gc, gc + Vector2(cos(na), sin(na)) * 1.8, OUT)
	# knife switch
	var kx := pb.position.x + 4
	var ky := pb.position.y + 13
	pr(i, Rect2i(kx - 1, ky + 3, 5, 2), Color("#3a2c1e"))
	if on:
		pl(i, Vector2(kx + 1, ky + 3), Vector2(kx + 1, ky - 2), BR2)
	else:
		pl(i, Vector2(kx + 1, ky + 3), Vector2(kx + 5, ky + 1), BR1)
	# the arc lamp: two carbon rods in a cage on the board's right
	var ax := pb.end.x - 5
	var ay := pb.position.y + 13
	pr(i, Rect2i(ax - 3, pb.position.y + 3, 7, 18), Color("#141a1c"))
	pl(i, Vector2(ax - 3, pb.position.y + 3), Vector2(ax - 3, pb.position.y + 20), BR0)
	pl(i, Vector2(ax + 3, pb.position.y + 3), Vector2(ax + 3, pb.position.y + 20), BR0)
	pr(i, Rect2i(ax, pb.position.y + 4, 1, 7), ST1)
	pr(i, Rect2i(ax, ay + 2, 1, 7), ST1)
	if on:
		var fl := Px.h2(floori(t * 30.0), 3, 9)
		p(i, ax, ay - 2, ARC)
		p(i, ax, ay - 1, ARC)
		p(i, ax, ay, ARC)
		p(i, ax, ay + 1, ARC)
		p(i, ax - 1 + floori(fl * 3.0), ay - 1 + floori(fl * 2.0), ARC_GLOW)
		glow(i, Vector2(ax + 0.5, ay + 0.5), 16.0, ARC_GLOW, 0.55 + 0.25 * fl)
		glow(i, Vector2(ax + 0.5, ay + 0.5), 4.0, ARC, 0.6)
	else:
		p(i, ax, ay - 2, ST2)
		p(i, ax, ay + 1, ST2)
	# cables to the roof (the searchlight)
	pl(i, Vector2(pb.position.x + 9, pb.position.y), Vector2(pb.position.x + 9, r.position.y), OUT)
	pl(i, Vector2(pb.position.x + 11, pb.position.y), Vector2(pb.position.x + 11, r.position.y), Color("#2a1a10"))


## The gun bay: crewman, a drum dynamo with commutator sparks, a shaft and bevel gear to the ring.
static func dynamo(i: Image, r: Rect2i, t: float, rpm: float, slot: int, traversing: bool) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var ang := t * rpm / 60.0 * TAU
	var cc := seat(i, Vector2i(r.position.x + 6, fy - 12), ang, slot, fy)
	var x0 := r.position.x + 18
	var x1 := r.end.x - 3
	var pul := Vector2(x0 + 3.5, fy - 8.5)
	chain(i, cc, pul, t * rpm / 60.0 * 9.0)
	wheel(i, pul, 3.5, ang * 3.0, BR1, 3)
	# drum: rounded box with a window on its windings
	var d := Rect2i(x0 + 7, fy - 15, mini(x1 - x0 - 7, 34), 13)
	pr(i, d, Color("#2b3a3a"))
	pr(i, Rect2i(d.position.x, d.position.y, d.size.x, 1), Color("#5c7a76"))
	pr(i, Rect2i(d.position.x, d.end.y - 1, d.size.x, 1), OUT)
	pr(i, Rect2i(d.position.x, d.position.y, 1, d.size.y), OUT)
	pr(i, Rect2i(d.end.x - 1, d.position.y, 1, d.size.y), OUT)
	var win := Rect2i(d.position.x + 3, d.position.y + 3, d.size.x - 9, d.size.y - 6)
	for y in range(win.position.y, win.end.y):
		for x in range(win.position.x, win.end.x):
			var s := fposmod(float(x) + (ang * 3.0 if on else 0.0) * 2.0, 3.0)
			p(i, x, y, CU2 if s < 1.0 else (CU1 if y > win.position.y else CU0))
	# commutator and brushes, sparks
	var cx := d.end.x - 4
	pr(i, Rect2i(cx, d.position.y + 3, 3, d.size.y - 6), BR1)
	p(i, cx + 1, d.position.y + 2, ST0)
	p(i, cx + 1, d.end.y - 3, ST0)
	if on and Px.h2(floori(t * 24.0), 1, 4) > 0.45:
		p(i, cx + 1 + (1 if Px.h2(floori(t * 24.0), 2) > 0.5 else -1), d.position.y + 2, ARC)
		glow(i, Vector2(cx + 1.5, d.position.y + 2.5), 4.0, ARC_GLOW, 0.5)
	# vertical shaft and bevel gear under the turret ring
	var sx := d.position.x + d.size.x / 2
	pr(i, Rect2i(sx, r.position.y + 4, 2, d.position.y - r.position.y - 4), ST2)
	pr(i, Rect2i(sx, r.position.y + 4, 1, d.position.y - r.position.y - 4), ST3)
	var gy := r.position.y + 5
	var gph := (t * 6.0) if traversing else 0.0
	for x in range(sx - 7, sx + 9):
		var tooth := fposmod(float(x) + gph, 3.0) < 1.6
		p(i, x, gy - 1, BR2 if tooth else BR0)
		p(i, x, gy, BR1)
		p(i, x, gy + 1, BR0)
	# volts gauge
	var gc := Vector2(x0 + 11.5, d.position.y - 6.5)
	for y in range(floori(gc.y) - 3, floori(gc.y) + 4):
		for x in range(floori(gc.x) - 3, floori(gc.x) + 4):
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(gc)
			if dd < 2.2:
				p(i, x, y, Color("#e8dcc0"))
			elif dd < 3.2:
				p(i, x, y, BR1)
	var na := PI + (0.7 if on else 0.05) * PI
	pl(i, gc, gc + Vector2(cos(na), sin(na)) * 1.8, OUT)


## The secondaries bay: crewman, a crank-driven star sprocket pulling two belts from two ammunition
## boxes up to the twin guns' feed (`feed`, opening px); 2 rounds per pedal revolution.
static func beltfeed(i: Image, r: Rect2i, t: float, rpm: float, slot: int, feed: Vector2) -> void:
	var fy := r.end.y - 3
	var on := slot >= 0 and rpm > 1.0
	var revs := t * rpm / 60.0 if on else 0.0
	var ang := revs * TAU
	var cc := seat(i, Vector2i(r.position.x + 6, fy - 12), ang, slot, fy)
	var star := Vector2(r.position.x + 26.5, fy - 16.5)
	chain(i, cc, star, revs * 9.0)
	# star sprocket (4 points: 2 rounds a turn per belt)
	for y in range(floori(star.y) - 5, floori(star.y) + 6):
		for x in range(floori(star.x) - 5, floori(star.x) + 6):
			var d := Vector2(x + 0.5, y + 0.5) - star
			var rho := d.length()
			var phi := atan2(d.y, d.x) - ang * 0.5
			var rr := 3.0 + 1.6 * maxf(cos(4.0 * phi), 0.0)
			if rho < rr:
				p(i, x, y, BR1 if d.y < 0 else BR0)
			elif rho < rr + 0.8:
				p(i, x, y, OUT)
	p(i, floori(star.x), floori(star.y), BR2)
	# ammunition boxes
	var bx := r.position.x + 32
	for k in 2:
		var b := Rect2i(bx + k * 11, fy - 9, 10, 9)
		pr(i, b, AMMO)
		pr(i, Rect2i(b.position.x, b.position.y, b.size.x, 1), AMMO_L)
		pr(i, Rect2i(b.position.x, b.position.y, 1, b.size.y), OUT)
		pr(i, Rect2i(b.end.x - 1, b.position.y, 1, b.size.y), OUT)
		pr(i, Rect2i(b.position.x + 3, b.position.y + 3, 4, 1), OUT)
		# belts: box -> star -> feed, rounds (brass) every 2 px, moving 2 per revolution each
		var a := Vector2(b.position.x + 5, b.position.y)
		var via := star + Vector2(2 + k * 2, -4 - k * 2)
		var path := [a, a + Vector2(0, -4 - k * 3), via, feed + Vector2(-3 + k * 2, 2 + k * 2)]
		var ph := revs * 2.0 * 2.0
		var acc := 0.0
		for s in path.size() - 1:
			var p0: Vector2 = path[s]
			var p1: Vector2 = path[s + 1]
			var n := maxi(ceili(p0.distance_to(p1)), 1)
			for m in n:
				var q := p0.lerp(p1, float(m) / float(n))
				var u := fposmod(acc + m - ph, 2.0)
				p(i, floori(q.x), floori(q.y), BR2 if u < 1.0 else ST0)
			acc += n
	# spent cases dropping into a bin under the feed
	var bin := Rect2i(floori(feed.x) - 4, fy - 5, 7, 5)
	pr(i, bin, ST1)
	pr(i, Rect2i(bin.position.x, bin.position.y, bin.size.x, 1), ST3)
	if on:
		for k in 3:
			var f := fposmod(revs * 2.0 + k / 3.0, 1.0)
			var y := lerpf(feed.y + 4.0, float(fy - 6), f * f)
			p(i, floori(feed.x) - 1 + k, floori(y), BR2)
