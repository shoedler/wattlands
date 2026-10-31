class_name TankInterior
extends RefCounted
## The v3 tank's rooms, painted live (docs/games/tank.md v3 "The tank, in the view"), ported from
## the r6 generator (assets/tank/v3/tools_src/mach.gd, tank_r4.gd, tank_r5.gd, tank_r6.gd): one Image
## the size of the sprite that starts as the base art and gets each seat's machine painted into its
## room, clipped to the room's open cutaway:
##   drive    the rider on the crank, the chain to the flywheel, the diesel opened (four pistons on
##            con-rods, rockers, the crankcase glowing)
##   gun      the rider and the dynamo face on (copper windings turning, commutator sparks)
##   lights   the rider and the arc generator (the coil, two carbon rods, the cold arc)
##   sec      the rider and the crank-driven twin belt feed (the star wheel, the belts climbing)
##   loader   the rider and the green boiler with its firebox, the hoist up the shaft, the ready
##            rack's window (three slots with latches, the telescoping manipulator) and the breech
##            window (the tray, the chain rammer, the breech block, recoiling with the gun)
##   bow      both bow-gun receivers (belts feeding, cocking slides kicking, a glow per round)
##   repair   v4, on the upper deck: the rider, the chain to the flywheel and its tappet, the rivet hammer
##            (one stroke per crank revolution, TankMech.hammer_lift), the patch press, the plate stack
## A manned seat shows its rider (slot colour cap) and turns with the rider's crank revolutions; an
## empty seat (station slot -1) shows a bare saddle and a still crank, its machine stopped.
##
## Cost: painting is per pixel on the CPU, so paint() repaints only the units whose inputs changed
## (machines quantised to UNIT_STEPS per crank revolution, flicker to FLICKER_HZ), each at most
## MAX_HZ, at most `budget` units per call; the texture uploads once per call that painted.

const UNITS: Array[String] = ["drive", "gun", "lights", "sec", "loader", "bow", "repair"]
## The rooms and windows each unit paints into (it is clipped to them).
const UNIT_RECTS := {
	"drive": ["drive"],
	"gun": ["gun"],
	"lights": ["lights"],
	"sec": ["sec"],
	"loader": ["loader", "shaft", "rackwin", "breechwin"],
	"bow": ["boxwin", "boxwin2"],
	"repair": ["turret_drive"],
}
const UNIT_STEPS := 24.0
const FLICKER_HZ := 15.0
const MAX_HZ := 30.0
## The loader's cycle (r6 tank_r6.gd STEPS): [step, from s, to s] of the mock's 7 s cycle.
const STEPS: Array = [
	["RACK", 0.0, 1.0],
	["HOIST", 1.0, 2.4],
	["STOW", 2.4, 3.4],
	["FEED", 3.4, 4.4],
	["BREECH OPEN", 4.4, 4.9],
	["RAM", 4.9, 5.8],
	["BREECH SHUT", 5.8, 6.3],
	["RESET", 6.3, 7.0],
]
const CYCLE := 7.0
## v4: the Repairs room's plate stack: patches mod this many lie by the press.
const PATCH_STACK := 5
## v4: the Repairs room's own slight colour (SPEC_TANK 5.3): its wall and its lamp, a pinker copper.
const REPAIR_WALL := Color("#2a1a18")
const REPAIR_LAMP := Color(1.0, 0.7, 0.48)
const REPAIR_HOT := Color(1.0, 0.72, 0.42)
## v4: the machine's iron under that lamp (never the neutral greys of a diagram), dark to light.
const RP_IRON: Array[Color] = [
	Color("#160d0b"), Color("#2e1d18"), Color("#4c312a"), Color("#74503f"), Color("#a67a60")
]
## The hammer's forged head: the room's lightest iron, the thing the eye goes to first.
const RP_HEAD: Array[Color] = [
	Color("#21140f"), Color("#5a4034"), Color("#94705a"), Color("#d9b394"), Color("#f7dcc0")
]
const RP_HAFT: Array[Color] = [Color("#1e100a"), Color("#59331d"), Color("#8c5a33")]
const RP_CHAIN: Array[Color] = [Color("#1d120d"), Color("#5a3a26"), Color("#8c6240")]
const RP_PLATE: Array[Color] = [Color("#3c1e13"), Color("#7a4326"), Color("#ad6c40")]

const OUT := Color("#0b0806")
const OUT6 := Color("#050302")
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
const SADDLE := Color("#4a2c18")
## The riders' slot colours (the HUD's and the platform's).
const SLOT: Array[Color] = [Color("#D55E00"), Color("#0072B2"), Color("#F0E442"), Color("#009E73")]

var rig: TankRig = null
var img: Image = null
var tex: ImageTexture = null
## Paints done (tests and the perf note).
var paints: int = 0

var _w: int = 0
var _h: int = 0
var _clip: PackedByteArray = PackedByteArray()
var _clips: Dictionary = {}
var _keys: Dictionary = {}
var _last: Dictionary = {}
var _next: int = 0
var _repair_walls: Dictionary = {}


func _init(p_rig: TankRig) -> void:
	rig = p_rig
	_w = int(rig.size.x)
	_h = int(rig.size.y)
	img = Image.create_empty(_w, _h, false, Image.FORMAT_RGBA8)
	if rig.base_img != null:
		img.blit_rect(rig.base_img, Rect2i(0, 0, _w, _h), Vector2i.ZERO)
	tex = ImageTexture.create_from_image(img)
	for u in UNITS:
		var c := PackedByteArray()
		c.resize(_w * _h)
		for rid: String in UNIT_RECTS[u]:
			var r := Rect2i(_unit_rect(rid))
			for y in range(maxi(r.position.y, 0), mini(r.end.y, _h)):
				for x in range(maxi(r.position.x, 0), mini(r.end.x, _w)):
					c[y * _w + x] = 1
		_clips[u] = c


func _unit_rect(rid: String) -> Rect2:
	if rig.rooms.has(rid):
		return rig.rooms[rid]
	return rig.windows.get(rid, Rect2())


## The loader's step at `lt` s into the 7 s cycle: {step, k (0..1 through it)}; IDLE below 0.
static func step_at(lt: float) -> Dictionary:
	for s: Array in STEPS:
		if lt >= float(s[1]) and lt < float(s[2]):
			return {"step": str(s[0]), "k": (lt - float(s[1])) / (float(s[2]) - float(s[1]))}
	return {"step": "IDLE", "k": 0.0}


## The main gun's recoil (px back along the bore) `ft` s after the shot (r6b: 11 px in two frames,
## back over about 0.55 s).
static func recoil(ft: float) -> float:
	if ft < 0.0 or ft > 0.65:
		return 0.0
	if ft < 0.06:
		return 11.0 * ft / 0.06
	var k := (ft - 0.06) / 0.59
	return 11.0 * (1.0 - k) * (1.0 - k)


## Repaints the units whose inputs changed. `inp`: seat id -> {slot, revs, on} for the six seats ("repair"
## also press_t, patches), "t" (flicker clock, s), "loader" {lt, ready, elev, fire_t}, "bow" {revs (-1 silent)}.
## At most
## `budget` units paint; the rest wait for the next call. True when the texture changed.
func paint(inp: Dictionary, now: float, budget: int = 2) -> bool:
	var done := 0
	for n in UNITS.size():
		var u: String = UNITS[(_next + n) % UNITS.size()]
		var key := _key(u, inp)
		if _keys.get(u, null) == key:
			continue
		if now - float(_last.get(u, -1e9)) < 1.0 / MAX_HZ and _keys.has(u):
			continue
		_keys[u] = key
		_last[u] = now
		_paint_unit(u, inp)
		done += 1
		if done >= budget:
			_next = (_next + n + 1) % UNITS.size()
			break
	if done > 0:
		tex.update(img)
		paints += done
	return done > 0


## Paints every unit now (the first frame, tests).
func paint_all(inp: Dictionary) -> void:
	for u in UNITS:
		_keys[u] = _key(u, inp)
		_paint_unit(u, inp)
	tex.update(img)
	paints += UNITS.size()


func _key(u: String, inp: Dictionary) -> Array:
	var t := float(inp.get("t", 0.0))
	var fl := floori(t * FLICKER_HZ)
	match u:
		"loader":
			var ld: Dictionary = inp.get("loader", {})
			var s: Dictionary = inp.get("loader_seat", {})
			return [
				_seat_key(s),
				fl if bool(s.get("on", false)) else 0,
				snappedf(float(ld.get("lt", -1.0)), 0.04),
				int(ld.get("ready", 0)),
				snappedf(float(ld.get("elev", 0.0)), 0.25),
				snappedf(TankInterior.recoil(float(ld.get("fire_t", 99.0))), 0.5),
			]
		"bow":
			var revs := float((inp.get("bow", {}) as Dictionary).get("revs", -1.0))
			return [-1.0 if revs < 0.0 else floorf(revs * 2.0 * 8.0)]
		"repair":
			var rp: Dictionary = inp.get("repair", {})
			return [
				_seat_key(rp),
				fl if bool(rp.get("on", false)) else 0,
				snappedf(float(rp.get("press_t", 0.0)), 0.05),
				int(rp.get("patches", 0)) % PATCH_STACK,
			]
		_:
			var st: Dictionary = inp.get(u, {})
			return [_seat_key(st), fl if bool(st.get("on", false)) else 0]


static func _seat_key(st: Dictionary) -> Array:
	var on := bool(st.get("on", false))
	var q := floorf(float(st.get("revs", 0.0)) * UNIT_STEPS) if on else 0.0
	return [int(st.get("slot", -1)), on, q]


func _paint_unit(u: String, inp: Dictionary) -> void:
	_clip = _clips[u]
	for rid: String in UNIT_RECTS[u]:
		var r := Rect2i(_unit_rect(rid))
		if rig.base_img != null:
			img.blit_rect(rig.base_img, r, r.position)
	var t := floorf(float(inp.get("t", 0.0)) * FLICKER_HZ) / FLICKER_HZ
	match u:
		"drive":
			_drive(inp.get("drive", {}), t)
		"gun":
			var g: Dictionary = inp.get("gun", {})
			dynamo_round(rig.rooms["gun"], _ang(g), t, int(g.get("slot", -1)), _on(g))
		"lights":
			var l: Dictionary = inp.get("lights", {})
			arc_v(rig.rooms["lights"], _ang(l), t, int(l.get("slot", -1)), _on(l))
		"sec":
			var s: Dictionary = inp.get("sec", {})
			beltfeed(rig.rooms["sec"], float(s.get("revs", 0.0)), int(s.get("slot", -1)), _on(s))
		"loader":
			loader(inp.get("loader_seat", {}), inp.get("loader", {}), t)
		"bow":
			receivers(float((inp.get("bow", {}) as Dictionary).get("revs", -1.0)))
		"repair":
			var rp: Dictionary = inp.get("repair", {})
			repair_bay(
				rig.rooms["turret_drive"],
				float(rp.get("revs", 0.0)),
				int(rp.get("slot", -1)),
				_on(rp),
				float(rp.get("press_t", 0.0)),
				int(rp.get("patches", 0))
			)


static func _ang(st: Dictionary) -> float:
	return float(st.get("revs", 0.0)) * TAU if _on(st) else 0.0


static func _on(st: Dictionary) -> bool:
	return int(st.get("slot", -1)) >= 0 and bool(st.get("on", false))


# --- Pixel primitives (mach.gd), clipped to the unit being painted --------------------------------------


func p(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= _w or y >= _h or _clip[y * _w + x] == 0:
		return
	img.set_pixel(x, y, c)


func pr(r: Rect2i, c: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			p(x, y, c)


func pl(a: Vector2, b: Vector2, c: Color) -> void:
	var n := maxi(ceili(maxf(absf(b.x - a.x), absf(b.y - a.y))), 1)
	for k in n + 1:
		var q := a.lerp(b, float(k) / float(n))
		p(floori(q.x), floori(q.y), c)


## An outlined, top-lit box: fill `c`, a lit top row `hi`, a dark right column and bottom row.
func box(r: Rect2i, c: Color, hi: Color, lo: Color) -> void:
	pr(r, OUT)
	var inner := r.grow(-1)
	pr(inner, c)
	pr(Rect2i(inner.position.x, inner.position.y, inner.size.x, 1), hi)
	pr(Rect2i(inner.end.x - 1, inner.position.y + 1, 1, inner.size.y - 1), lo)
	pr(Rect2i(inner.position.x, inner.end.y - 1, inner.size.x, 1), lo)


func glow(c: Vector2, rad: float, col: Color, a: float) -> void:
	for y in range(floori(c.y - rad), ceili(c.y + rad) + 1):
		for x in range(floori(c.x - rad), ceili(c.x + rad) + 1):
			if x < 0 or y < 0 or x >= _w or y >= _h or _clip[y * _w + x] == 0:
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / rad
			if d < 1.0:
				TankPx.add(img, x, y, col, a * (1.0 - d) * (1.0 - d))


func dial(c: Vector2, load: float) -> void:
	for y in range(floori(c.y) - 3, floori(c.y) + 4):
		for x in range(floori(c.x) - 3, floori(c.x) + 4):
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if dd < 1.9:
				p(x, y, Color("#e8dcc0"))
			elif dd < 2.9:
				p(x, y, BR2 if y < c.y else BR1)
			elif dd < 3.5:
				p(x, y, OUT)
	var na := PI * (1.1 + 0.8 * clampf(load, 0.0, 1.0))
	pl(c, c + Vector2(cos(na), sin(na)) * 1.6, OUT)


## A chain between two sprockets: two runs whose links travel with `phase`.
func chain(a: Vector2, b: Vector2, ra: float, rb: float, phase: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	for side: float in [-1.0, 1.0]:
		var p0: Vector2 = a + n * ra * side
		var p1: Vector2 = b + n * rb * side
		var m := maxi(ceili(p0.distance_to(p1)), 1)
		for k in m + 1:
			var q := p0.lerp(p1, float(k) / float(m))
			var s := fposmod(float(k) - phase * side, 2.0)
			p(floori(q.x), floori(q.y), BR2 if s < 1.0 else ST0)


## A spoked wheel at c, radius r, turned ang (teeth > 0: a sprocket).
func wheel(c: Vector2, r: float, ang: float, rim: Color, spokes: int = 4, teeth: int = 0) -> void:
	for y in range(floori(c.y - r) - 2, ceili(c.y + r) + 2):
		for x in range(floori(c.x - r) - 2, ceili(c.x + r) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rho := d.length()
			var phi := atan2(d.y, d.x) - ang
			if teeth > 0 and rho > r and rho < r + 1.2 and cos(teeth * phi) > 0.2:
				p(x, y, rim)
				continue
			if rho > r + 0.6:
				continue
			if rho > r - 0.4:
				p(x, y, OUT)
				continue
			var lit := -d.y - d.x * 0.3 > 0.0
			if rho > r - 1.6:
				p(x, y, rim.lightened(0.3) if lit else rim)
				continue
			if rho < 1.4:
				p(x, y, BR2 if rho < 0.8 else BR1)
				continue
			var sp := fposmod(phi, TAU / spokes)
			sp = minf(sp, TAU / spokes - sp) * rho
			if sp < 0.8:
				p(x, y, rim.darkened(0.1) if lit else rim.darkened(0.3))


# --- Repair --------------------------------------------------------------------------------------------


## v4: the Repairs machine in room `rr`, facing right from the saddle: one chain from the crank to the flywheel,
## a cam on the flywheel's own shaft, a tappet from the cam to the helve, and the helve's forged head falling on
## the patch on its anvil once per crank revolution (a pure function of `revs`: TankMech.hammer_lift), with
## sparks. The screw press to the right closes at `press_t`, and `patches` mod PATCH_STACK plates lie stacked by
## it.
func repair_bay(rr: Rect2, revs: float, slot: int, on: bool, press_t: float, patches: int) -> void:
	var r := Rect2i(rr)
	img.blit_rect(_repair_wall(r, on), Rect2i(Vector2i.ZERO, r.size), r.position)
	var fy := r.end.y - 2
	var x0 := r.position.x
	var y0 := r.position.y
	var rv := revs if on else 0.0
	var ang := rv * TAU
	var cc := seat(x0 + 1, fy, ang, slot)
	var lift := TankMech.hammer_lift(rv)
	# the helve's pillar, behind everything
	pr(Rect2i(x0 + 18, y0 + 4, 4, fy - y0 - 4), RP_IRON[1])
	pr(Rect2i(x0 + 18, y0 + 4, 1, fy - y0 - 4), RP_IRON[3])
	pr(Rect2i(x0 + 21, y0 + 4, 1, fy - y0 - 4), RP_IRON[0])
	pr(Rect2i(x0 + 16, fy - 2, 8, 2), RP_IRON[2])
	pr(Rect2i(x0 + 16, fy - 2, 8, 1), RP_IRON[3])
	# the flywheel on its pedestal, its one chain, 1:1 with the crank
	var fw := Vector2(x0 + 30.5, fy - 6.5)
	pr(Rect2i(floori(fw.x) - 4, fy - 2, 9, 2), RP_IRON[2])
	pr(Rect2i(floori(fw.x) - 4, fy - 2, 9, 1), RP_IRON[3])
	_rp_chain(cc, fw, 2.5, 2.0, rv * 8.0)
	wheel(fw, 6.0, ang, RP_IRON[3], 5)
	# the cam on its shaft: a lobe that lifts the tappet; the tappet to the helve
	var piv := Vector2(x0 + 20.5, y0 + 4.5)
	var head_x := x0 + 48.5
	var rest_y := fy - 12.0
	var end := Vector2(head_x, rest_y - 9.0 * lift)
	var tap_x := fw.x
	var tap_top := piv.y + (end.y - piv.y) * (tap_x - piv.x) / (head_x - piv.x)
	var cam_top := fw.y - 2.0 - 2.6 * lift
	pl(Vector2(tap_x, tap_top + 1.0), Vector2(tap_x, cam_top), RP_IRON[4])
	for a2 in 16:
		var th := TAU * float(a2) / 16.0
		var along := fposmod(th / TAU + 0.25 - fposmod(rv, 1.0), 1.0)
		var rad := 1.6 + 2.6 * TankMech.hammer_lift(fposmod(rv, 1.0) - along)
		for k3 in 3:
			var q2 := fw + Vector2(cos(th), sin(th)) * rad * (1.0 - float(k3) * 0.35)
			p(floori(q2.x), floori(q2.y), RP_IRON[4] if k3 == 0 and sin(th) < 0.2 else RP_IRON[2])
	p(floori(fw.x), floori(fw.y), RP_IRON[0])
	# the helve: wood with iron straps, a bearing on the pillar, its end in the head's eye
	pl(piv + Vector2(0, 1), end + Vector2(0, 1), RP_HAFT[0])
	pl(piv, end, RP_HAFT[2])
	for k4 in 3:
		var q3 := piv.lerp(end, 0.3 + float(k4) * 0.24)
		p(floori(q3.x), floori(q3.y), RP_IRON[4])
		p(floori(q3.x), floori(q3.y) + 1, RP_IRON[2])
	pr(Rect2i(floori(piv.x) - 1, floori(piv.y) - 1, 3, 3), RP_IRON[1])
	p(floori(piv.x), floori(piv.y), RP_IRON[4])
	_rp_hammer(end)
	# the anvil on its stump and the patch plate on it, under the head
	var anvil := Rect2i(x0 + 42, fy - 6, 14, 4)
	box(anvil, RP_IRON[2], RP_IRON[4], RP_IRON[0])
	pr(Rect2i(x0 + 45, fy - 3, 8, 3), RP_IRON[1])
	pr(Rect2i(x0 + 45, fy - 3, 1, 3), RP_IRON[3])
	pr(Rect2i(x0 + 39, fy - 7, 20, 1), RP_PLATE[1])
	pr(Rect2i(x0 + 39, fy - 7, 7, 1), RP_PLATE[2])
	# the strike's sparks, on the whole revolution
	var since := TankMech.since_strike(rv)
	if on and since < TankMech.R_SPARK:
		var k := 1.0 - since / TankMech.R_SPARK
		var st := floorf(rv)
		for i in 9:
			var a := -PI * (0.05 + 0.9 * TankPx.h2(int(st), i, 11))
			var spd := 6.0 + 11.0 * TankPx.h2(int(st), i, 12)
			var q := (
				Vector2(head_x, fy - 8.0)
				+ Vector2(cos(a), sin(a)) * spd * (since / TankMech.R_SPARK)
			)
			p(floori(q.x), floori(q.y), REPAIR_HOT)
		glow(Vector2(head_x, fy - 8.0), 12.0, REPAIR_HOT, 0.7 * k)
	# the screw press on the right: it closes at press_t; the plates lie by its foot
	var px := x0 + 60
	pr(Rect2i(px - 1, y0 + 1, 1, fy - y0 - 1), RP_IRON[3])
	pr(Rect2i(px + 5, y0 + 1, 1, fy - y0 - 1), RP_IRON[1])
	pr(Rect2i(px - 1, y0 + 1, 7, 2), RP_IRON[3])
	var ty := y0 + 5 + roundi(clampf(press_t, 0.0, 1.0) * float(fy - y0 - 11))
	pl(Vector2(px + 2.5, y0 + 3), Vector2(px + 2.5, ty), RP_IRON[4])
	box(Rect2i(px, ty, 5, 3), RP_IRON[2], RP_IRON[4], RP_IRON[0])
	var stack := posmod(patches, PATCH_STACK)
	for s2 in stack:
		var sy := fy - 1 - s2 * 2
		pr(Rect2i(px, sy, 5, 1), RP_PLATE[2] if s2 % 2 == 0 else RP_PLATE[1])
		pr(Rect2i(px, sy + 1, 5, 1), OUT)
	# the lamp
	if on:
		p(x0 + 40, y0 + 3, Color(1.0, 0.92, 0.8))
		glow(Vector2(x0 + 40.5, y0 + 3.5), 8.0, REPAIR_LAMP, 0.5)
	else:
		p(x0 + 40, y0 + 3, RP_IRON[2])


## The Repairs chain: dark oily links, every fourth catching the lamp, so it travels without beading.
func _rp_chain(a: Vector2, b: Vector2, ra: float, rb: float, phase: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	for side: float in [-1.0, 1.0]:
		var p0: Vector2 = a + n * ra * side
		var p1: Vector2 = b + n * rb * side
		var m := maxi(ceili(p0.distance_to(p1)), 1)
		for k in m + 1:
			var q := p0.lerp(p1, float(k) / float(m))
			var s := fposmod(float(k) - phase * side, 4.0)
			p(
				floori(q.x),
				floori(q.y),
				RP_CHAIN[2] if s < 1.0 else RP_CHAIN[0] if s < 2.0 else RP_CHAIN[1]
			)


## The forged hammer head hung on the helve's end at `end`: a poll, a broad cheek, a narrower face below.
func _rp_hammer(end: Vector2) -> void:
	var x := floori(end.x)
	var y := floori(end.y)
	# the outline, then the shaded forging
	pr(Rect2i(x - 5, y - 3, 11, 9), OUT)
	pr(Rect2i(x - 3, y + 6, 7, 2), OUT)
	pr(Rect2i(x - 4, y - 2, 9, 7), RP_HEAD[2])
	pr(Rect2i(x - 4, y - 2, 9, 1), RP_HEAD[4])
	pr(Rect2i(x - 4, y - 1, 1, 6), RP_HEAD[3])
	pr(Rect2i(x + 4, y - 1, 1, 6), RP_HEAD[1])
	pr(Rect2i(x - 3, y + 4, 8, 1), RP_HEAD[1])
	pr(Rect2i(x - 2, y + 5, 5, 2), RP_HEAD[2])
	pr(Rect2i(x - 2, y + 6, 5, 1), RP_HEAD[3])
	pr(Rect2i(x - 3, y + 2, 7, 1), RP_HEAD[1])


## The room's backing: the base's picture sunk into the room's own colour (so the machine reads) and fading
## back to it at the room's edge, plated wall with what a repair shop hangs on one, lit from the lamp when the
## seat works. Made once per state.
func _repair_wall(r: Rect2i, on: bool) -> Image:
	if _repair_walls.has(on):
		return _repair_walls[on]
	var w := Image.create_empty(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	var lamp := Vector2(40.5, 4.0)
	for y in r.size.y:
		for x in r.size.x:
			var o := REPAIR_WALL
			if rig.base_img != null:
				o = rig.base_img.get_pixel(r.position.x + x, r.position.y + y)
			# the room's edge dissolves into the hull's art round it, unevenly
			var edge := float(mini(mini(x, r.size.x - 1 - x), mini(y, r.size.y - 1 - y)))
			edge += (TankPx.h2(x, y, 31) - 0.5) * 3.0 + (TankPx.h2(x / 5, y / 4, 33) - 0.5) * 3.0
			var sink := lerpf(0.12, 0.8, clampf(edge / 5.0, 0.0, 1.0))
			var c := o.lerp(_rp_wall_at(x, y, r.size), sink)
			c.a = 1.0
			w.set_pixel(x, y, c)
	_rp_clutter(w, r.size)
	for y2 in r.size.y:
		for x2 in r.size.x:
			var c2 := w.get_pixel(x2, y2)
			var k := maxf(1.0 - Vector2(x2, y2).distance_to(lamp) / 36.0, 0.0)
			k = k * k * (0.3 if on else 0.07)
			c2.r = minf(c2.r + REPAIR_LAMP.r * k, 1.0)
			c2.g = minf(c2.g + REPAIR_LAMP.g * k, 1.0)
			c2.b = minf(c2.b + REPAIR_LAMP.b * k, 1.0)
			w.set_pixel(x2, y2, c2)
	_repair_walls[on] = w
	return w


## The wall's own picture at (x, y): plates of different tones with their seams, grime rising from the deck.
func _rp_wall_at(x: int, y: int, size: Vector2i) -> Color:
	var col := REPAIR_WALL
	var plate := floori(float(x + 3) / 19.0) + (floori(float(y) / 12.0) * 3)
	col = col.lightened((TankPx.h2(plate, 3, 37) - 0.4) * 0.14)
	var low := float(y) / float(size.y)
	col = col.darkened(smoothstep(0.55, 1.0, low) * 0.45)
	col = col.darkened((TankPx.h2(x, y, 39) - 0.3) * 0.16)
	if (x + 3) % 19 == 0 or y % 12 == 0:
		col = col.darkened(0.55)
	elif (x + 3) % 19 == 1 or y % 12 == 1:
		col = col.lightened(0.1)
	return col


## What a repair shop keeps on its wall, all in the lamp's iron: a pipe along the ceiling running out through
## both walls, a shelf of tins and a box, tools on nails, patches leaning in the corner.
func _rp_clutter(w: Image, size: Vector2i) -> void:
	# the pipe
	for x in size.x:
		w.set_pixel(x, 1, RP_PLATE[1])
		w.set_pixel(x, 2, RP_PLATE[0])
		if x % 17 == 8:
			for y in range(0, 4):
				w.set_pixel(x, y, RP_IRON[3] if y == 0 else RP_IRON[2])
	# a drop off the pipe, to a valve
	for y2 in range(3, 7):
		w.set_pixel(27, y2, RP_PLATE[1])
	w.set_pixel(26, 6, RP_IRON[3])
	w.set_pixel(28, 6, RP_IRON[3])
	# the shelf, its brackets and what is on it
	for x2 in range(31, 45):
		w.set_pixel(x2, 11, RP_HAFT[1])
		w.set_pixel(x2, 12, RP_IRON[0])
	for x3: int in [33, 42]:
		w.set_pixel(x3, 13, RP_IRON[2])
		w.set_pixel(x3, 14, RP_IRON[1])
	_rp_block(w, Rect2i(32, 8, 3, 3), RP_IRON[3], RP_IRON[1])
	_rp_block(w, Rect2i(36, 9, 2, 2), RP_PLATE[2], RP_PLATE[0])
	_rp_block(w, Rect2i(39, 7, 5, 4), RP_HAFT[2], RP_HAFT[1])
	# tools on nails, between the anvil and the press
	for y3 in range(5, 13):
		w.set_pixel(56, y3, RP_IRON[3])
	w.set_pixel(55, 12, RP_IRON[3])
	w.set_pixel(57, 12, RP_IRON[3])
	for y4 in range(5, 11):
		w.set_pixel(53, y4, RP_HAFT[1])
	_rp_block(w, Rect2i(52, 3, 3, 2), RP_IRON[3], RP_IRON[1])
	# grime under the shelf, a stain from the pipe's flange
	for k in 9:
		var sx := 9 + (k % 3)
		for y5 in range(3, 12 - k % 4):
			var c := w.get_pixel(25 + sx, y5)
			w.set_pixel(25 + sx, y5, c.darkened(0.25))


func _rp_block(w: Image, r: Rect2i, c: Color, lo: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			w.set_pixel(x, y, lo if x == r.end.x - 1 or y == r.end.y - 1 else c)
	for x2 in range(r.position.x, r.end.x):
		w.set_pixel(x2, r.end.y, OUT)


# --- The pedal station ------------------------------------------------------------------------------------


## A pedal station facing right from x `x0` on floor row `fy`: saddle, frame, chain ring and cranks
## at `ang`; the rider in slot `slot`'s colour, or a bare saddle and a still crank when `slot` < 0.
## Returns the chain ring's centre.
func seat(x0: int, fy: int, ang: float, slot: int) -> Vector2:
	var sad := Vector2(x0 + 5.5, fy - 9.5)
	var cc := Vector2(x0 + 10.5, fy - 4.5)
	var bar := Vector2(x0 + 14.5, fy - 13.5)
	pr(Rect2i(x0 + 2, fy - 1, 14, 1), ST2)
	pl(Vector2(x0 + 4, fy - 1), sad + Vector2(0, 1), ST2)
	pl(Vector2(x0 + 5, fy - 1), sad + Vector2(1, 1), ST1)
	pl(sad + Vector2(0.5, 1), cc, ST2)
	pl(cc, bar, ST2)
	pl(cc + Vector2(1, 0), bar + Vector2(1, 1), ST1)
	pl(bar + Vector2(-1, 0), bar + Vector2(1, 0), ST3)
	for k in 12:
		var a := TAU * k / 12.0 + ang
		var q := cc + Vector2(cos(a), sin(a)) * 2.5
		p(floori(q.x), floori(q.y), BR2 if k % 3 == 0 else BR1)
	p(floori(cc.x), floori(cc.y), BR2)
	var cv := Vector2(cos(ang), sin(ang)) * 3.0
	var f1 := cc + cv
	var f2 := cc - cv
	if slot < 0:
		pl(cc, f1, ST3)
		pl(cc, f2, ST2)
		pr(Rect2i(floori(f1.x) - 1, floori(f1.y), 3, 1), ST3)
		pr(Rect2i(floori(f2.x) - 1, floori(f2.y), 3, 1), ST2)
		pr(Rect2i(floori(sad.x) - 2, floori(sad.y), 5, 1), SADDLE)
		pr(Rect2i(floori(sad.x) - 2, floori(sad.y) + 1, 5, 1), OUT)
		return cc
	var hip := sad + Vector2(0, -1)
	_leg(hip, f2, TROU_D, true)
	pl(cc, f2, ST2)
	pr(Rect2i(floori(sad.x) - 2, floori(sad.y), 5, 1), SADDLE)
	var sh := hip + Vector2(3, -6)
	pl(hip + Vector2(-1, 0), sh + Vector2(-1, 0), UNI_D)
	pl(hip, sh, UNI)
	pl(hip + Vector2(1, -1), sh + Vector2(1, 0), UNI_L)
	p(floori(hip.x), floori(hip.y) - 1, BR0)
	p(floori(hip.x) + 1, floori(hip.y) - 1, BR0)
	var el := sh + Vector2(3, 3)
	pl(sh + Vector2(1, 0), el, UNI_L)
	pl(el, bar + Vector2(-1, 0), UNI)
	p(floori(bar.x) - 1, floori(bar.y), SKIN)
	var hd := Vector2i(floori(sh.x) - 1, floori(sh.y) - 4)
	pr(Rect2i(hd.x - 1, hd.y + 3, 4, 1), UNI_D)
	pr(Rect2i(hd.x, hd.y, 3, 3), SKIN)
	p(hd.x, hd.y + 1, SKIN_D)
	p(hd.x, hd.y + 2, SKIN_D)
	p(hd.x + 2, hd.y + 1, Color("#3a2414"))
	var sc := SLOT[slot % SLOT.size()]
	pr(Rect2i(hd.x, hd.y - 1, 3, 1), sc.lightened(0.2))
	p(hd.x - 1, hd.y, sc.darkened(0.3))
	p(hd.x + 3, hd.y, sc.darkened(0.2))
	p(hd.x + 3, hd.y - 1, sc)
	_leg(hip + Vector2(1, 0), f1, TROU, false)
	pl(cc, f1, ST3)
	return cc


func _leg(hip: Vector2, foot: Vector2, col: Color, far: bool) -> void:
	var d := foot - hip
	var dl := clampf(d.length(), 0.1, 9.0)
	var half := dl * 0.5
	var up := sqrt(maxf(4.6 * 4.6 - half * half, 0.0))
	var n := Vector2(d.y, -d.x).normalized()
	if n.x < 0.0:
		n = -n
	var knee := hip + d.normalized() * half + n * up
	pl(hip, knee, col)
	pl(hip + Vector2(0, 1), knee + Vector2(0, 1), col.darkened(0.25))
	pl(knee, foot, col.darkened(0.15))
	p(floori(foot.x), floori(foot.y), BOOT)
	p(floori(foot.x) + 1, floori(foot.y), BOOT if not far else ST0)
	p(floori(foot.x) - 1, floori(foot.y), BOOT)


# --- The machines -----------------------------------------------------------------------------------------


## Drive: the rider, the flywheel on the crank's chain, the diesel opened (tank_r5 diesel_open).
func _drive(st: Dictionary, t: float) -> void:
	var rd: Rect2i = Rect2i(rig.rooms["drive"])
	var fyd := rd.end.y - 2
	var ad := _ang(st)
	var eng := ad * 2.4
	var slot := int(st.get("slot", -1))
	var cc := seat(rd.position.x + 1, fyd, ad, slot)
	diesel_open(Rect2i(rd.position.x + 33, rd.position.y + 6, 48, 22), eng, _on(st), t)
	var fw := Vector2(rd.position.x + 25.5, fyd - 9.5)
	chain(cc, fw, 2.5, 3.0, ad * 1.4)
	wheel(fw, 6.5, eng, ST2, 6)
	wheel(fw, 2.0, eng, BR1, 3, 6)


## The diesel with its side open: four bores, pistons a quarter turn apart, con-rods to the crank,
## rockers on top, the crankcase lit by its own heat.
func diesel_open(r: Rect2i, eng: float, on: bool, t: float) -> void:
	pr(r, OUT6)
	pr(r.grow(-1), Color("#120d0a"))
	var crank_y := r.end.y - 5
	pr(Rect2i(r.position.x + 1, crank_y, r.size.x - 2, 1), BR0)
	for k in 4:
		var bx := r.position.x + 3 + k * 11
		var ph := eng + k * PI * 0.5
		pr(Rect2i(bx, r.position.y + 2, 8, 11), Color("#2a2622"))
		pr(Rect2i(bx, r.position.y + 2, 1, 11), ST1)
		pr(Rect2i(bx + 7, r.position.y + 2, 1, 11), Color("#0a0806"))
		var py := r.position.y + 4 + roundi(3.0 * (1.0 - cos(ph)))
		pr(Rect2i(bx + 1, py, 6, 3), ST3)
		pr(Rect2i(bx + 1, py, 6, 1), ST4)
		p(bx + 1, py + 1, ST1)
		var cxp := Vector2(bx + 4.0 + 2.0 * sin(ph), crank_y + 0.5 - 2.0 * cos(ph))
		pl(Vector2(bx + 4.0, py + 3.0), cxp, ST3)
		p(floori(cxp.x), floori(cxp.y), BR2)
		var bob := roundi(sin(ph + 1.0) + 1.0)
		pr(Rect2i(bx + 2, r.position.y - 1 - bob, 4, 1), CU1)
		if on and cos(ph) > 0.92:
			p(bx + 3, r.position.y + 3, FIRE1)
	if on:
		glow(
			Vector2(r.position.x + r.size.x * 0.5, crank_y - 2),
			20.0,
			Color("#ff8a30"),
			0.16 + 0.05 * sin(t * 13.0)
		)


## The gun room's dynamo face on: copper windings round a dark hub, turning; sparks.
func dynamo_round(rr: Rect2, ang: float, t: float, slot: int, on: bool) -> void:
	var r := Rect2i(rr)
	var fy := r.end.y - 3
	var cc := seat(r.position.x + 3, fy, ang, slot)
	var rad := minf(12.0, (fy - r.position.y - 6) * 0.5)
	var dc := Vector2(r.end.x - rad - 4.5, fy - rad - 1.5)
	box(Rect2i(floori(dc.x - rad) + 1, fy - 3, floori(rad * 2.0) - 1, 3), ST1, ST2, ST0)
	var sp := ang * 3.0 if on else 0.0
	for y in range(floori(dc.y - rad) - 1, ceili(dc.y + rad) + 2):
		for x in range(floori(dc.x - rad) - 1, ceili(dc.x + rad) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - dc
			var rho := d.length()
			if rho > rad + 0.6:
				continue
			var phi := atan2(d.y, d.x)
			if rho > rad - 0.4:
				p(x, y, OUT)
			elif rho > rad - 2.0:
				p(x, y, ST3 if d.y < -rad * 0.3 else ST1)
				if fposmod(phi * 8.0 / TAU, 1.0) < 0.15:
					p(x, y, BR1)
			elif rho > rad * 0.35:
				var seg := fposmod((phi - sp) * 14.0 / TAU, 1.0)
				var c := CU2 if seg < 0.3 else (CU1 if seg < 0.75 else CU0)
				if d.y > rad * 0.4:
					c = c.darkened(0.35)
				p(x, y, c)
			elif rho > 2.0:
				p(x, y, Color("#1a1210"))
			else:
				p(x, y, BR2)
	chain(cc, dc, 2.5, 3.0, ang / TAU * 9.0)
	if on:
		var fl := TankPx.h2(floori(t * 24.0), 5, 1)
		var sa := fl * TAU
		var spk := dc + Vector2(cos(sa), sin(sa)) * (rad - 1.0)
		p(floori(spk.x), floori(spk.y), ARC)
		glow(spk, 6.0, ARC_GLOW, 0.5)
		glow(dc, rad + 6.0, Color("#ff8a40"), 0.12)
	var top := floori(dc.y - rad) - r.position.y - 2
	pr(Rect2i(floori(dc.x) - 1, r.position.y + 2, 2, top), ST2)
	pr(Rect2i(floori(dc.x) - 1, r.position.y + 2, 1, top), ST4)


## The lights room's arc generator: a copper coil, two carbon rods in a V, the cold arc at its foot,
## cables up to the searchlight.
func arc_v(rr: Rect2, ang: float, t: float, slot: int, on: bool) -> void:
	var r := Rect2i(rr)
	var fy := r.end.y - 3
	var cc := seat(r.position.x + 3, fy, ang, slot)
	var x0 := r.position.x + 20
	var coil := Rect2i(x0, fy - 16, 7, 14)
	box(Rect2i(x0 - 1, fy - 2, 9, 2), ST1, ST2, ST0)
	for y in range(coil.position.y, coil.end.y):
		for x in range(coil.position.x, coil.end.x):
			var band := (y + (floori(ang * 2.0) if on else 0)) % 2 == 0
			var c := CU2 if band else CU0
			if x == coil.position.x or x == coil.end.x - 1:
				c = OUT
			p(x, y, c)
	pr(Rect2i(x0 - 1, coil.position.y - 1, 9, 1), ST3)
	chain(cc, Vector2(x0 + 3.5, fy - 6.5), 2.5, 2.0, ang / TAU * 9.0)
	var tip := Vector2(r.end.x - 9.5, fy - 7.5)
	var la := Vector2(tip.x - 8.0, r.position.y + 6.0)
	var ra := Vector2(tip.x + 8.0, r.position.y + 6.0)
	pr(Rect2i(floori(la.x) - 2, floori(la.y) - 2, floori(ra.x - la.x) + 5, 2), BR1)
	pl(la, tip + Vector2(-1, -1), ST1 if not on else ST3)
	pl(ra, tip + Vector2(1, -1), ST1 if not on else ST3)
	pl(la + Vector2(1, 0), tip + Vector2(0, -1), ST0)
	pl(ra + Vector2(-1, 0), tip + Vector2(0, -1), ST0)
	box(Rect2i(floori(tip.x) - 4, fy - 4, 9, 4), ST1, ST2, ST0)
	if on:
		var fl := TankPx.h2(floori(t * 30.0), 3, 9)
		p(floori(tip.x), floori(tip.y), ARC)
		p(floori(tip.x) - 1, floori(tip.y), ARC)
		p(floori(tip.x) + floori(fl * 3.0) - 1, floori(tip.y) - 1, ARC_GLOW)
		glow(tip, 22.0, ARC_GLOW, 0.65 + 0.25 * fl)
		glow(tip, 5.0, ARC, 0.8)
	pl(Vector2(ra.x + 2, ra.y), Vector2(ra.x + 2, r.position.y), OUT)
	pl(Vector2(ra.x + 3, ra.y), Vector2(ra.x + 3, r.position.y), Color("#3a1a10"))


## The secondaries' crank-driven twin belt feed (tank_r4 beltfeed_small): the star wheel turning
## half a turn per crank revolution, the ammunition box, two belts climbing to the receivers.
func beltfeed(rr: Rect2, revs_in: float, slot: int, on: bool) -> void:
	var r := Rect2i(rr)
	var fy := r.end.y - 2
	var revs := revs_in if on else 0.0
	var cc := seat(r.position.x, fy, revs * TAU, slot)
	var star := Vector2(r.end.x - 7.5, fy - 18.5)
	chain(cc, star, 2.5, 2.5, revs * 9.0)
	for y in range(floori(star.y) - 5, floori(star.y) + 6):
		for x in range(floori(star.x) - 5, floori(star.x) + 6):
			var d := Vector2(x + 0.5, y + 0.5) - star
			var rho := d.length()
			var rr2 := 2.5 + 1.8 * maxf(cos(4.0 * (atan2(d.y, d.x) - revs * PI)), 0.0)
			if rho < rr2:
				p(x, y, BR2 if d.y < -1.0 else BR1)
			elif rho < rr2 + 0.8:
				p(x, y, OUT)
	box(Rect2i(r.end.x - 11, fy - 8, 10, 8), AMMO, AMMO_L, AMMO_D)
	for k in 2:
		var x0 := r.end.x - 8 + k * 3
		for y in range(r.position.y, fy - 8):
			var u := fposmod(float(y) + revs * 4.0, 2.0)
			p(x0, y, BR2 if u < 1.0 else BR0)


# --- The loader and the turret windows (tank_r6) ------------------------------------------------------------


## A round lying along `ang` with its middle at `c` (tank.gd shell).
func shell(c: Vector2, ang: float) -> void:
	(
		TankPx
		. profile(
			img,
			c,
			ang,
			[
				[-7.0, -6.0, 1.7, 1.7, BR1, BR0, BR0],
				[-6.0, 1.0, 1.5, 1.5, BR2, BR1, BR0],
				[1.0, 2.0, 1.6, 1.6, CU2, CU1, CU0],
				[2.0, 7.0, 1.5, 0.5, ST4, ST2, ST1],
			],
			OUT,
			_clip
		)
	)


## The loader: the rider and the boiler, the hoist up the shaft to the hoist head, the ready rack
## with its manipulator, the breech window. `st` {slot, revs, on}; `ld` {lt (s into the 7 s cycle,
## < 0 idle), ready (0..3), elev (deg), fire_t (s since the last shot)}.
func loader(st: Dictionary, ld: Dictionary, t: float) -> void:
	var r: Rect2i = Rect2i(rig.rooms["loader"])
	var fy := r.end.y - 2
	var ang := _ang(st)
	var on := _on(st)
	var cc := seat(r.position.x + 1, fy, ang, int(st.get("slot", -1)))
	var bx := r.position.x + 18
	var top := fy - 27
	for y in range(top, fy):
		for x in range(bx, bx + 11):
			var dx := float(x - bx) - 5.0
			if y < top + 3 and absf(dx) > 2.5 + float(y - top) * 1.2:
				continue
			var col := (
				Color("#5a7a62")
				if dx < -3.0
				else (Color("#2e4a3a") if dx < 1.5 else Color("#1a2c22"))
			)
			if absf(dx) > 4.6 or (y == top and absf(dx) > 2.0):
				col = OUT6
			elif (y - top) % 8 == 4:
				col = BR1
			p(x, y, col)
	var fire := Rect2i(bx + 2, fy - 7, 7, 5)
	box(fire, ST1, ST2, ST0)
	for y in range(fire.position.y + 1, fire.end.y - 1):
		for x in range(fire.position.x + 1, fire.end.x - 1):
			var hv := TankPx.h2(x, y + floori(t * 10.0), 3)
			var fc := FIRE2 if hv > 0.7 else (FIRE1 if hv > 0.3 else FIRE0)
			p(x, y, fc if on else Color("#3a1408"))
	if on:
		glow(Vector2(bx + 5.5, fy - 4.0), 12.0, Color("#ff7a2a"), 0.4)
	dial(Vector2(bx + 5.5, top + 7.5), 0.7 if on else 0.1)
	var bw := Vector2(bx + 5.5, fy - 13.5)
	chain(cc, bw, 2.5, 2.5, ang * 1.4)
	wheel(bw, 3.0, ang * 2.0, ST2, 4)
	var lt := float(ld.get("lt", -1.0))
	var ls := step_at(lt) if lt >= 0.0 else {"step": "IDLE", "k": 0.0}
	var step: String = ls["step"]
	var k := float(ls["k"])
	var head: Vector2 = rig.rack["head"]
	var sh: Rect2i = Rect2i(rig.windows["shaft"])
	var low_y := float(fy) - 15.0
	var tray_y := low_y
	var on_tray := false
	var tray_shell := Vector2(222.0, low_y)
	match step:
		"RACK":
			tray_shell = Vector2(lerpf(222.0, head.x, TankPx.ease_k(k)), low_y)
			on_tray = true
		"HOIST":
			tray_y = lerpf(low_y, head.y, TankPx.ease_k(k))
			tray_shell = Vector2(head.x, tray_y)
			on_tray = true
		"STOW", "FEED", "BREECH OPEN", "RAM", "BREECH SHUT":
			tray_y = head.y
		"RESET":
			tray_y = lerpf(head.y, low_y, TankPx.ease_k(k))
	var rail_top := floori(head.y) - 12
	for y in range(rail_top, fy):
		p(sh.position.x + 1, y, ST2)
		p(sh.end.x - 2, y, ST2)
		p(sh.end.x - 1, y, BR1 if posmod(y + floori(tray_y), 3) == 0 else ST0)
	wheel(Vector2(sh.end.x - 0.5, rail_top - 0.5), 2.0, tray_y * 0.6, BR1, 3)
	var ty := floori(tray_y) + 2
	pr(Rect2i(sh.position.x, ty, sh.size.x, 1), BR1)
	p(sh.position.x, ty - 1, BR0)
	p(sh.end.x - 1, ty - 1, BR0)
	if on_tray:
		shell(tray_shell, 0.0)
	rack_window(int(ld.get("ready", 0)), step, k)
	breech_window(float(ld.get("elev", 0.0)), float(ld.get("fire_t", 99.0)), step, k)


## The ready rack: three slots with a latch each (flipped when full), the manipulator on its
## chain-driven pivot carrying a round from the hoist head into the next free slot (STOW), the top
## round slid forward along its rail toward the breech (FEED). `ready` rounds lie in the rack.
func rack_window(ready: int, step: String, k: float) -> void:
	var piv: Vector2 = rig.rack["pivot"]
	var head: Vector2 = rig.rack["head"]
	var sx := float(rig.rack["slots_x"])
	var sy: Array = rig.rack["slots_y"]
	var n := clampi(ready, 0, 3)
	var x0 := floori(sx) - 8
	var x1 := floori(sx) + 9
	for y in range(floori(float(sy[2])) - 3, floori(float(sy[0])) + 4):
		p(x0, y, ST2)
		p(x1, y, ST1)
	for s in 3:
		pr(Rect2i(x0, floori(float(sy[s])) + 2, x1 - x0 + 1, 1), ST2)
	pr(Rect2i(x0, floori(float(sy[2])) - 3, 40, 1), ST3)
	var slot_i := mini(n, 2)
	var filled: Array[bool] = [n > 0, n > 1, n > 2]
	if step == "STOW" and k > 0.85:
		filled[slot_i] = true
	for s2 in 3:
		if filled[s2]:
			shell(Vector2(sx, float(sy[s2])), 0.0)
		var ly := floori(float(sy[s2]))
		p(x1 + 1, ly - (1 if filled[s2] else -1), BR2)
		p(x1 + 1, ly, BR1)
	var rest := piv + Vector2(-1, 9)
	var grip := rest
	var carrying := false
	if step == "STOW":
		var target := Vector2(sx, float(sy[slot_i]))
		if k < 0.25:
			grip = rest.lerp(head, TankPx.ease_k(k / 0.25))
		elif k < 0.85:
			var u := TankPx.ease_k((k - 0.25) / 0.6)
			grip = head.lerp(target, u) + Vector2(0, -6.0 * sin(u * PI))
			carrying = true
		else:
			grip = target.lerp(rest, TankPx.ease_k((k - 0.85) / 0.15))
	elif step == "FEED" and k < 0.3:
		grip = rest.lerp(Vector2(sx - 7.0, float(sy[slot_i])), TankPx.ease_k(k / 0.3))
	var mot := piv + Vector2(-2, 12)
	box(Rect2i(floori(mot.x) - 3, floori(mot.y) - 2, 6, 5), ST1, ST2, ST0)
	var aang := (grip - piv).angle()
	chain(mot, piv, 1.5, 2.0, aang * 4.0)
	wheel(piv, 2.5, aang, BR1, 3, 6)
	var d := grip - piv
	var ln := d.length()
	var dn := d / maxf(ln, 0.001)
	var nn := Vector2(-dn.y, dn.x)
	pl(piv, piv + dn * minf(ln, 6.0), ST3)
	pl(piv + nn, piv + nn + dn * minf(ln, 6.0), ST1)
	pl(piv + dn * 5.0, grip, ST4)
	for side: float in [-1.0, 1.0]:
		var pp := grip + Vector2(0, 2.4 * side)
		p(floori(pp.x), floori(pp.y), BR2)
		p(floori(pp.x) + 1, floori(pp.y), BR1)
	if carrying:
		shell(grip, 0.0)
	if step == "STOW" and k < 0.25:
		shell(head, 0.0)
	if step == "FEED":
		shell(Vector2(lerpf(sx, sx + 30.0, TankPx.ease_k(k)), float(sy[slot_i])), 0.0)


## The breech window: the loading tray (a trough under its rail, on two struts), the chain rammer
## in its casing over it (links showing), the breech ring and its sliding block, at the gun's
## elevation and recoiling with it; the tray and the casing fill the window behind the breech even
## while it is run out and idle.
func breech_window(elev: float, fire_t: float, step: String, k: float) -> void:
	var ang := -deg_to_rad(elev)
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var o := rig.trunnion - d * recoil(fire_t)
	var opened := 0.0
	var shell_u := -999.0
	var ram := 0.0
	match step:
		"FEED":
			if k > 0.4:
				shell_u = lerpf(-50.0, -30.0, TankPx.ease_k((k - 0.4) / 0.6))
		"BREECH OPEN":
			opened = TankPx.ease_k(k)
			shell_u = -30.0
		"RAM":
			opened = 1.0
			shell_u = lerpf(-30.0, -14.0, TankPx.ease_k(k))
			ram = shell_u + 30.0
		"BREECH SHUT":
			opened = 1.0 - TankPx.ease_k(k)
			ram = lerpf(16.0, 0.0, TankPx.ease_k(k))
	# the rammer's casing over the tray, its chain's links along the bottom
	TankPx.profile(img, o - n * 2.4, ang, [[-41.0, -21.0, 1.3, 1.3, ST2, ST1, ST0]], OUT6, _clip)
	var ph := floori(ram)
	for j in 18:
		var lq := o - n * 1.2 + d * (-39.0 + float(j))
		if (j + ph) % 2 == 0:
			p(floori(lq.x), floori(lq.y), BR1)
	# the tray: a trough under the rail, on two struts down to the window's floor
	TankPx.profile(img, o + n * 4.6, ang, [[-37.0, -21.0, 1.5, 1.2, ST2, ST1, ST0]], OUT6, _clip)
	for su: float in [-34.0, -25.0]:
		for j2 in 4:
			var sq := o + n * (6.5 + float(j2)) + d * su
			p(floori(sq.x), floori(sq.y), ST1 if j2 % 2 == 0 else ST0)
	TankPx.profile(img, o + n * 2.6, ang, [[-36.0, -21.0, 0.6, 0.6, ST3, ST2, ST1]], OUT6, _clip)
	TankPx.profile(
		img,
		o + n * 1.6,
		ang,
		[[-36.0, -35.0, 1.2, 1.2, BR1, BR1, BR0], [-22.0, -21.0, 1.2, 1.2, BR1, BR1, BR0]],
		OUT6,
		_clip
	)
	var hous := o + d * -40.0
	TankPx.profile(img, hous, ang, [[-3.0, 3.0, 2.6, 2.6, ST3, ST2, ST1]], OUT6, _clip)
	for j in int(ram) + 1:
		var q := hous + d * (3.0 + j)
		p(floori(q.x), floori(q.y), BR2 if j % 2 == 0 else ST0)
	if shell_u > -900.0:
		shell(o + d * shell_u, ang)
	TankPx.profile(
		img,
		o,
		ang,
		[[-20.0, -6.0, 4.2, 4.2, ST3, ST2, ST1], [-18.0, -17.0, 4.2, 4.2, BR2, BR1, BR0]],
		OUT6,
		_clip
	)
	if opened > 0.2:
		TankPx.profile(
			img, o, ang, [[-20.5, -19.5, 1.6, 1.6, OUT6, OUT6, OUT6]], Color(0, 0, 0, 0), _clip
		)
	TankPx.profile(
		img, o + n * (opened * 6.0), ang, [[-23.0, -20.0, 4.0, 4.0, ST4, ST3, ST1]], OUT6, _clip
	)


## Both bow guns' receivers (the box's window and the one under the lower mount): a belt feeding in,
## the cocking slide kicking, a glow on each round. `revs` the Secondaries' crank revolutions (2
## rounds each, alternating guns), < 0 silent.
func receivers(revs: float) -> void:
	var on := revs >= 0.0
	var ph := revs * 2.0 if on else 0.0
	var wins: Array[Rect2] = [rig.windows["boxwin"], rig.windows["boxwin2"]]
	for k in 2:
		var r := Rect2i(wins[k])
		var rw := Rect2i(r.end.x - 13, r.position.y + r.size.y / 2 - 2, 11, 5)
		box(rw, ST2, ST3, ST1)
		var shot := on and fposmod(ph, 1.0) < 0.3 and int(floor(ph)) % 2 == k
		p(rw.position.x + 3 + (2 if shot else 0), rw.position.y + 1, BR2)
		for j in 10:
			var u := fposmod(float(j) * 2.0 - ph * 4.0, 20.0)
			var bxp := r.position.x + 1 + floori(u * float(rw.position.x - r.position.x - 1) / 20.0)
			p(bxp, rw.position.y + 3, BR2 if j % 2 == 0 else BR0)
			p(bxp, rw.position.y + 4, ST0)
		if shot:
			glow(Vector2(rw.end.x, rw.position.y + 2), 6.0, Color("#ffb060"), 0.7)
