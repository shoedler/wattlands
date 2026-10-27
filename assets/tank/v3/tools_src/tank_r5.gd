extends RefCounted
## r5: r4 (the reference's tank re-pixelled at 0.9 with live parts) after Simon's review: a brighter
## hull, the rear searchlight looking aft and down with its own cone, the turret searchlight aimed
## down at the road, dark close-set track shoes, road wheels 1.6x larger, deep shadow under the skirt
## and between the wheels, shadows under overhangs, the rear idler behind the armour, a turret cutaway
## (breech, rammer, the hoist arriving, the 3-round ready rack) and a cutaway in the bow guns' box
## (receivers, belts), a thicker stepped barrel, the diesel's cylinders open and running, cupolas and
## more turret fittings. Coordinates: base px (v2 4-rider px x 0.9).

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Mach = preload("res://assets/tank/v3/tools_src/mach.gd")
const Dress = preload("res://assets/tank/v3/tools_src/dress.gd")
const Tank = preload("res://assets/tank/v3/tools_src/tank.gd")
const Tank4 = preload("res://assets/tank/v3/tools_src/tank_r4.gd")

const BASE := "res://build/v3mock/r5/base.png"
const OUT := Color("#050302")
const BARREL: Array = [Color("#6a5a48"), Color("#3a3026"), Color("#17110c")]


static func layout() -> Dictionary:
	var wheels: Array = []
	for i in 11:
		wheels.append({"x": 71.5 + i * 31.4, "y": 192.0, "r": 12.0})
	var rooms := {
		"drive": Rect2i(89, 152, 92, 31), "loader": Rect2i(181, 152, 69, 31), "gun": Rect2i(250, 152, 43, 31),
		"lights": Rect2i(293, 152, 43, 31), "sec": Rect2i(361, 156, 30, 27),
		"quarters": Rect2i(104, 125, 160, 24), "turret_drive": Rect2i(268, 123, 67, 27), "upper_front": Rect2i(340, 131, 22, 24),
	}
	var shaft := Rect2i(237, 108, 10, 45)
	var window := Rect2i(230, 89, 124, 22)
	var boxwin := Rect2i(366, 116, 27, 12)
	var all: Array = []
	var groups: Array = []
	var gmap := {"drive": 1, "loader": 4, "gun": 3, "lights": 2, "sec": 5, "quarters": 6, "turret_drive": 6, "upper_front": 6}
	for k: String in rooms:
		all.append(rooms[k])
		groups.append(gmap[k])
	for extra: Rect2i in [shaft, window, boxwin]:
		all.append(extra)
		groups.append(4)
	return {
		"name": "R5",
		"size": Vector2i(475, 216),
		"ground": 209.0,
		"rooms": rooms,
		"rooms_all": all,
		"room_groups": groups,
		"shaft": shaft,
		"window": window,
		"boxwin": boxwin,
		"cuts": [
			{"rect": shaft, "floor": false, "reach": 20.0},
			{"rect": window, "lamp": Vector2(318, 91), "reach": 38.0},
			{"rect": boxwin, "lamp": Vector2(380, 118), "reach": 20.0, "floor": false},
		],
		"crate": Rect2i(199, 85, 16, 20),
		"plaques": [Rect2i(216, 89, 14, 12), Rect2i(243, 90, 9, 9)],
		"rear_lamp_mask": Rect2i(97, 85, 18, 12),
		"mask_bands": [[Rect2i(366, 97, 80, 12)], [Rect2i(403, 123, 24, 8)], [Rect2i(433, 135, 22, 8)]],
		"shadows": [
			{"rect": Rect2i(214, 118, 152, 6), "amt": 0.6},
			{"rect": Rect2i(180, 110, 36, 6), "amt": 0.5},
			{"rect": Rect2i(84, 113, 40, 4), "amt": 0.45},
			{"rect": Rect2i(352, 119, 44, 4), "amt": 0.45},
			{"rect": Rect2i(18, 183, 420, 4), "amt": 0.55},
		],
		"prep_details": [
			{"kind": "cupola", "rect": Rect2i(250, 70, 22, 8)},
			{"kind": "periscope", "at": Vector2i(283, 78)},
			{"kind": "periscope", "at": Vector2i(232, 78)},
			{"kind": "hatch_top", "at": Vector2i(318, 78), "w": 10},
			{"kind": "vision", "at": Vector2i(300, 81), "w": 5},
			{"kind": "vision", "at": Vector2i(335, 83), "w": 4},
			{"kind": "rail", "a": Vector2i(236, 85), "b": Vector2i(346, 85)},
			{"kind": "bolt_row", "a": Vector2i(216, 80), "b": Vector2i(356, 80)},
			{"kind": "bolt_row", "a": Vector2i(232, 113), "b": Vector2i(356, 113)},
			{"kind": "box", "rect": Rect2i(202, 79, 8, 4)},
			{"kind": "box", "rect": Rect2i(182, 78, 15, 5)},
		],
		"spill_px": 7,
		"spill_amt": 0.3,
		"tints": {2: Color("#a8d0ff"), 4: Color("#ffa040")},
		"gun": {"trunnion": Vector2(350.1, 103.05), "len": 90.5},
		"bow": [{"pivot": Vector2(400.0, 126.9), "len": 23.5}, {"pivot": Vector2(430.2, 139.0), "len": 22.0}],
		"details": [
			{"kind": "lamp_red", "at": Vector2i(31, 127)},
			{"kind": "lamp_red", "at": Vector2i(442, 149)},
			{"kind": "lamp_green", "at": Vector2i(105, 102)},
			{"kind": "headlight", "at": Vector2i(453, 164)},
			{"kind": "searchlight", "at": Vector2i(303, 64), "lens": Vector2(6.5, 1.5), "ang": 11.0, "len": 560.0, "half": 6.0, "ground": 209.0, "a": 0.4},
			{"kind": "searchlight_rear", "at": Vector2i(105, 91), "lens": Vector2(-7.0, 1.5), "ang": 167.0, "len": 220.0, "half": 8.0, "ground": 209.0, "a": 0.34, "always": true},
		],
		"gear": {
			"T": 5.0, "up": 3.0, "droop": 2.0, "skirt_y": 187, "rear_cut": [Vector2(14, 140), Vector2(56, 187)],
			"dark": true, "idler_back": true,
			"idler": {"c": Vector2(30, 162), "r": 11.0},
			"sprocket": {"c": Vector2(420.3, 188.1), "r": 16.6},
			"rollers": [
				{"c": Vector2(87, 177), "r": 2.0}, {"c": Vector2(150, 177), "r": 2.0}, {"c": Vector2(213, 177), "r": 2.0},
				{"c": Vector2(276, 177), "r": 2.0}, {"c": Vector2(339, 177), "r": 2.0}, {"c": Vector2(398, 176), "r": 2.0},
			],
			"wheels": wheels,
		},
	}


static func build() -> Dictionary:
	var L := layout()
	var base := Image.load_from_file(ProjectSettings.globalize_path(BASE))
	base.convert(Image.FORMAT_RGBA8)
	var sz: Vector2i = L["size"]
	var open := PackedByteArray()
	open.resize(sz.x * sz.y)
	var gi := 0
	for r: Rect2i in L["rooms_all"]:
		gi += 1
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x >= 0 and y >= 0 and x < sz.x and y < sz.y:
					open[y * sz.x + x] = int(L["room_groups"][gi - 1])
	return {"L": L, "img": base, "open": open, "w": sz.x, "h": sz.y}


static func frame(B: Dictionary, st: Dictionary) -> Image:
	var L: Dictionary = B["L"]
	var sz: Vector2i = L["size"]
	var img := Px.blank(sz.x, sz.y)
	var wc: Array[Vector2] = []
	for w: Dictionary in L["gear"]["wheels"]:
		wc.append(Vector2(float(w["x"]), float(w["y"])))
	if st.has("wc"):
		wc.assign(st["wc"])
	var travel := float(st.get("travel", 0.0))
	# the hull's underside: dark between the wheels
	for y in range(176, 204):
		for x in range(44, 412):
			img.set_pixel(x, y, Color("#0a0705") if y < 198 else Color("#070504"))
	Gear.draw_back(img, L["gear"], Transform2D.IDENTITY, wc, travel)
	# the skirt's deep shadow over the running gear
	for y in range(180, 200):
		var k := lerpf(0.3, 1.0, float(y - 180) / 20.0)
		for x in range(20, 445):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	img.blend_rect(B["img"], Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	interior(img, B, st)
	Gear.draw_front(img, L["gear"], Transform2D.IDENTITY, wc, travel)
	roof(img, st)
	guns(img, L, st)
	return img


# --- the stations ---------------------------------------------------------------------------------------


static func interior(img: Image, B: Dictionary, st: Dictionary) -> void:
	var L: Dictionary = B["L"]
	var rooms: Dictionary = L["rooms"]
	var t := float(st.get("t", 0.0))
	var rpm: Dictionary = st.get("rpm", {})
	var crew: Dictionary = st.get("crew", {})
	Mach.set_clip(B["open"], int(B["w"]), int(B["h"]))
	var sl := func(id: String) -> int: return int(crew.get(id, -1))
	var rp := func(id: String) -> float: return float(rpm.get(id, 85.0)) if int(crew.get(id, -1)) >= 0 else 0.0
	# drive: the rider, the flywheel, and the diesel opened: four cylinders, pistons, con-rods, crank
	var rd: Rect2i = rooms["drive"]
	var fyd := rd.end.y - 2
	var ad := t * float(rp.call("drive")) / 60.0 * TAU
	var eng := ad * 2.4
	var cc := Mach.seat(img, rd.position.x + 1, fyd, ad, sl.call("drive"))
	diesel_open(img, Rect2i(rd.position.x + 33, rd.position.y + 6, 48, 22), eng, int(sl.call("drive")) >= 0, t)
	var fw := Vector2(rd.position.x + 25.5, fyd - 9.5)
	Mach.chain(img, cc, fw, 2.5, 3.0, ad * 1.4)
	Mach.wheel(img, fw, 6.5, eng, Mach.ST2, 6)
	Mach.wheel(img, fw, 2.0, eng, Mach.BR1, 3, 6)
	Mach.dynamo_round(img, rooms["gun"], t, rp.call("gun"), sl.call("gun"))
	Mach.arc_v(img, rooms["lights"], t, rp.call("lights"), sl.call("lights"))
	Tank4.beltfeed_small(img, rooms["sec"], t, rp.call("sec"), sl.call("sec"))
	loader(img, B, st, rooms["loader"], t, rp.call("loader"), sl.call("loader"))
	boxwin(img, L, st)
	Dress._open = B["open"]
	Dress._w = int(B["w"])
	Dress._h = int(B["h"])
	Dress._g = 6
	var q: Rect2i = rooms["quarters"]
	for k in [0, 2, 3, 5]:
		Dress.sitter(img, q.position.x + 14 + k * 20, q.end.y - 1, 1 if k % 2 == 0 else -1, k)


## The diesel with its side open: four bores, pistons rising and falling a quarter turn apart,
## con-rods to a turning crank, rockers on top, the crankcase lit by the engine's own heat.
static func diesel_open(img: Image, r: Rect2i, eng: float, on: bool, t: float) -> void:
	Mach.pr(img, r, OUT)
	Mach.pr(img, r.grow(-1), Color("#120d0a"))
	var crank_y := r.end.y - 5
	Mach.pr(img, Rect2i(r.position.x + 1, crank_y, r.size.x - 2, 1), Mach.BR0)
	for k in 4:
		var bx := r.position.x + 3 + k * 11
		var ph := eng + k * PI * 0.5
		# the bore
		Mach.pr(img, Rect2i(bx, r.position.y + 2, 8, 11), Color("#2a2622"))
		Mach.pr(img, Rect2i(bx, r.position.y + 2, 1, 11), Mach.ST1)
		Mach.pr(img, Rect2i(bx + 7, r.position.y + 2, 1, 11), Color("#0a0806"))
		# the piston
		var py := r.position.y + 4 + roundi(3.0 * (1.0 - cos(ph)))
		Mach.pr(img, Rect2i(bx + 1, py, 6, 3), Mach.ST3)
		Mach.pr(img, Rect2i(bx + 1, py, 6, 1), Mach.ST4)
		Mach.p(img, bx + 1, py + 1, Mach.ST1)
		# con-rod to the crank pin
		var cxp := Vector2(bx + 4.0 + 2.0 * sin(ph), crank_y + 0.5 - 2.0 * cos(ph))
		Mach.pl(img, Vector2(bx + 4.0, py + 3.0), cxp, Mach.ST3)
		Mach.p(img, floori(cxp.x), floori(cxp.y), Mach.BR2)
		# rocker and valve stem on top
		var bob := roundi(sin(ph * 1.0 + 1.0) + 1.0)
		Mach.pr(img, Rect2i(bx + 2, r.position.y - 1 - bob, 4, 1), Mach.CU1)
		if on and cos(ph) > 0.92:
			Mach.p(img, bx + 3, r.position.y + 3, Mach.FIRE1)
	if on:
		Mach.glow(img, Vector2(r.position.x + r.size.x * 0.5, crank_y - 2), 20.0, Color("#ff8a30"), 0.16 + 0.05 * sin(t * 13.0))


## The loader: rider, the green boiler, the hoist up the shaft into the turret's cutaway, then the
## shell rammed along to the breech; the ready rack of three beside the hoist head.
static func loader(img: Image, B: Dictionary, st: Dictionary, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var L: Dictionary = B["L"]
	var clip: PackedByteArray = B["open"]
	var fy := r.end.y - 2
	var ang := t * rpm / 60.0 * TAU
	var on := slot >= 0 and rpm > 1.0
	var cc := Mach.seat(img, r.position.x + 1, fy, ang, slot)
	var bx := r.position.x + 18
	var top := fy - 27
	for y in range(top, fy):
		for x in range(bx, bx + 11):
			var dx := float(x - bx) - 5.0
			if y < top + 3 and absf(dx) > 2.5 + float(y - top) * 1.2:
				continue
			var col := Color("#5a7a62") if dx < -3.0 else (Color("#2e4a3a") if dx < 1.5 else Color("#1a2c22"))
			if absf(dx) > 4.6 or (y == top and absf(dx) > 2.0):
				col = OUT
			elif (y - top) % 8 == 4:
				col = Mach.BR1
			Mach.p(img, x, y, col)
	var fire := Rect2i(bx + 2, fy - 7, 7, 5)
	Mach.box(img, fire, Mach.ST1, Mach.ST2, Mach.ST0)
	for y in range(fire.position.y + 1, fire.end.y - 1):
		for x in range(fire.position.x + 1, fire.end.x - 1):
			var hv := Px.h2(x, y + floori(t * 10.0), 3)
			Mach.p(img, x, y, (Mach.FIRE2 if hv > 0.7 else (Mach.FIRE1 if hv > 0.3 else Mach.FIRE0)) if on else Color("#3a1408"))
	if on:
		Mach.glow(img, Vector2(bx + 5.5, fy - 4.0), 12.0, Color("#ff7a2a"), 0.4)
	Mach.dial(img, Vector2(bx + 5.5, top + 7.5), 0.7 if on else 0.1)
	var bw := Vector2(bx + 5.5, fy - 13.5)
	Mach.chain(img, cc, bw, 2.5, 2.5, ang * 1.4)
	Mach.wheel(img, bw, 3.0, ang * 2.0, Mach.ST2, 4)
	# the cycle
	var lt := float(st.get("load_t", -1.0))
	var ls := Tank.load_step(lt) if lt >= 0.0 else {"step": "IDLE", "k": 0.0}
	var step: String = ls["step"]
	var k := float(ls["k"])
	var sh: Rect2i = L["shaft"]
	var win: Rect2i = L["window"]
	var hc := sh.position.x + sh.size.x * 0.5
	var g: Dictionary = L["gun"]
	var gang := Tank.gun_dir(float(st.get("elev", 0.0)), 0.0)
	var gd := Vector2(cos(gang), sin(gang))
	var tr: Vector2 = g["trunnion"]
	var chamber := tr + gd * -14.0
	var low_y := float(fy) - 15.0
	var top_pt := Vector2(hc, tr.y + (hc - tr.x) * gd.y / gd.x)
	var tray_y := low_y
	var shell_at := Vector2(222.0, low_y)
	var shell_ang := 0.0
	var show := lt >= 0.0
	var rammer := 0.0
	match step:
		"RACK":
			shell_at = Vector2(lerpf(222.0, hc, Tank._ease(k)), low_y)
		"HOIST":
			tray_y = lerpf(low_y, top_pt.y, Tank._ease(k))
			shell_at = Vector2(hc, tray_y)
		"BREECH OPEN":
			tray_y = top_pt.y
			shell_at = top_pt
		"RAM":
			tray_y = top_pt.y
			shell_at = top_pt.lerp(chamber, Tank._ease(k))
			shell_ang = (chamber - top_pt).angle()
			rammer = shell_at.distance_to(top_pt)
		"BREECH SHUT":
			tray_y = top_pt.y
			show = false
			rammer = lerpf(top_pt.distance_to(chamber), 0.0, Tank._ease(k))
		"TRAY DOWN":
			tray_y = lerpf(top_pt.y, low_y, Tank._ease(k))
			show = false
	# rails and chain up the shaft into the turret
	var rail_top := floori(top_pt.y) - 5
	for y in range(rail_top, fy):
		Mach.p(img, sh.position.x + 1, y, Mach.ST2)
		Mach.p(img, sh.end.x - 2, y, Mach.ST2)
		Mach.p(img, sh.end.x - 1, y, Mach.BR1 if posmod(y + floori(tray_y), 3) == 0 else Mach.ST0)
	Mach.wheel(img, Vector2(sh.end.x - 0.5, rail_top - 1.5), 2.0, tray_y * 0.6, Mach.BR1, 3)
	var ty := floori(tray_y) + 2
	Mach.pr(img, Rect2i(sh.position.x, ty, sh.size.x, 1), Mach.BR1)
	Mach.pr(img, Rect2i(sh.position.x + 1, ty + 1, sh.size.x - 2, 1), OUT)
	# the rammer behind the tray head, a chain rammer along the loading line
	var rdir := (chamber - top_pt).normalized()
	var hous := top_pt - rdir * 9.0
	Px.profile(img, hous, rdir.angle(), [[-3.0, 2.0, 2.4, 2.4, Mach.ST3, Mach.ST2, Mach.ST1]], OUT, clip)
	if rammer > 0.5:
		Px.profile(img, hous, rdir.angle(), [[2.0, 2.0 + rammer, 0.6, 0.6, Mach.ST4, Mach.ST3, Mach.ST2]], OUT, clip)
	# the ready rack of three, standing beside the hoist head
	var n_ready := int(st.get("ready", 2))
	for q in 3:
		var sx := float(sh.end.x + 4 + q * 5)
		var sy := float(win.end.y) - 10.5
		Mach.pr(img, Rect2i(int(sx) - 2, win.end.y - 3, 5, 1), Mach.ST1)
		Mach.pr(img, Rect2i(int(sx) - 2, int(sy) - 6, 5, 1), Mach.ST2)
		if q < n_ready:
			Tank.shell(img, Vector2(sx, sy), -PI * 0.5, clip)
	if show:
		Tank.shell(img, shell_at, shell_ang, clip)
	breech(img, L, st, clip)


## The breech in the turret's cutaway: the barrel's root, the ring, the sliding block, the cradle,
## a ready lamp when loaded.
static func breech(img: Image, L: Dictionary, st: Dictionary, clip: PackedByteArray) -> void:
	var g: Dictionary = L["gun"]
	var ang := Tank.gun_dir(float(st.get("elev", 0.0)), 0.0)
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var fire_t := float(st.get("fire_t", 99.0))
	var recoil := 0.0
	if fire_t >= 0.0 and fire_t < 0.6:
		recoil = 4.0 * (1.0 - fire_t / 0.6) if fire_t > 0.05 else 4.0
	var o: Vector2 = (g["trunnion"] as Vector2) - d * recoil
	var lt := float(st.get("load_t", -1.0))
	var ls := Tank.load_step(lt) if lt >= 0.0 else {"step": "IDLE", "k": 0.0}
	var opened := 0.0
	match str(ls["step"]):
		"BREECH OPEN":
			opened = Tank._ease(float(ls["k"]))
		"RAM":
			opened = 1.0
		"BREECH SHUT":
			opened = 1.0 - Tank._ease(float(ls["k"]))
	Px.profile(img, o + n * 5.0, ang, [[-36.0, -4.0, 0.7, 0.7, Mach.ST2, Mach.ST1, Mach.ST0]], OUT, clip)
	Px.profile(img, o, ang, [
		[-6.0, 8.0, 2.6, 2.6, BARREL[0], BARREL[1], BARREL[2]],
		[-20.0, -5.0, 4.2, 4.2, Mach.ST3, Mach.ST2, Mach.ST1],
		[-18.0, -17.0, 4.2, 4.2, Mach.BR2, Mach.BR1, Mach.BR0],
		[-9.0, -8.0, 4.2, 4.2, Mach.BR2, Mach.BR1, Mach.BR0],
	], OUT, clip)
	if opened > 0.2:
		Px.profile(img, o, ang, [[-20.5, -19.5, 1.6, 1.6, OUT, OUT, OUT]], Color(0, 0, 0, 0), clip)
	Px.profile(img, o + n * (opened * 6.0), ang, [[-23.0, -20.0, 4.0, 4.0, Mach.ST4, Mach.ST3, Mach.ST1]], OUT, clip)
	var loaded := lt < 0.0 or lt >= 5.0
	var lamp := o - d * 13.0 - n * 6.0
	Mach.p(img, floori(lamp.x), floori(lamp.y), Color("#ffd27a") if loaded else Color("#3a2414"))


## The bow guns' box opened: the two receivers, the belts feeding in, the cocking levers working.
static func boxwin(img: Image, L: Dictionary, st: Dictionary) -> void:
	var r: Rect2i = L["boxwin"]
	var revs := float(st.get("sec_revs", -1.0))
	var on := revs >= 0.0
	var ph := revs * 2.0 if on else 0.0
	for k in 2:
		var ry := r.position.y + 2 + k * 5
		Mach.box(img, Rect2i(r.position.x + 9, ry, 15, 5), Mach.ST2, Mach.ST3, Mach.ST1)
		var cock := roundi(fposmod(ph + k * 0.5, 1.0) * 3.0) if on else 0
		Mach.p(img, r.position.x + 13 + cock, ry + 1, Mach.BR2)
		# the belt coming in from below, rounds moving
		for j in 8:
			var u := fposmod(float(j) - ph * 2.0, 8.0)
			var bxp := r.position.x + 2 + floori(u)
			var byp := ry + 3 + (1 if k == 0 else 0)
			Mach.p(img, bxp, byp, Mach.BR2 if j % 2 == 0 else Mach.BR0)
		if on and fposmod(ph, 1.0) < 0.3 and int(floor(ph)) % 2 == k:
			Mach.glow(img, Vector2(r.end.x - 1, ry + 2), 5.0, Color("#ffb060"), 0.6)
	Mach.glow(img, Vector2(r.position.x + 13, r.position.y + 2), 9.0, Color("#ffb060"), 0.25)


# --- the roof: the turret searchlight aimed down the road, the commander in the cupola, the rear
# searchlight looking aft and down ------------------------------------------------------------------


static func roof(img: Image, st: Dictionary) -> void:
	var lit := bool(st.get("search_on", true))
	_lamp(img, Vector2(303, 64), deg_to_rad(11.0), lit)
	Px.rect(img, Rect2i(301, 68, 4, 9), OUT)
	Px.rect(img, Rect2i(302, 68, 2, 9), Color("#2a2018"))
	# the commander in the cupola
	var c := Vector2i(261, 70)
	Px.rect(img, Rect2i(c.x - 3, c.y - 5, 7, 5), Color("#2e2618"))
	Px.rect(img, Rect2i(c.x - 2, c.y - 5, 5, 1), Color("#4a3e28"))
	Px.rect(img, Rect2i(c.x - 1, c.y - 9, 3, 3), Color("#7a5a40"))
	Px.rect(img, Rect2i(c.x - 2, c.y - 10, 5, 1), Color("#2a2a22"))
	Px.rect(img, Rect2i(c.x - 1, c.y - 11, 3, 1), Color("#3a3a2e"))
	Px.line(img, Vector2i(c.x + 3, c.y - 4), Vector2i(c.x + 8, c.y - 6), Color("#3a3226"))
	# the rear searchlight on its post: looking aft, 13 degrees down
	_lamp(img, Vector2(105, 91), PI - deg_to_rad(13.0), true)


## A searchlight drum aimed along `a` (radians, y down) from its centre `c`, the lens at the front.
static func _lamp(img: Image, c: Vector2, a: float, lit: bool) -> void:
	Px.profile(img, c, a, [
		[-5.0, 4.0, 3.5, 3.5, Color("#4e3c2a"), Color("#2e2218"), Color("#140e0a")],
		[4.0, 6.0, 4.0, 4.0, Color("#8a6a3a"), Color("#6a5236"), Color("#3a2c1e")],
		[6.0, 7.0, 3.0, 3.0, Color("#fff6d8") if lit else Color("#3a4a4c"), Color("#fff6d8") if lit else Color("#2a3a3c"), Color("#ffd98a") if lit else Color("#1a2a2c")],
	])


# --- the barrel and the bow guns ---------------------------------------------------------------------------


static func guns(img: Image, L: Dictionary, st: Dictionary, xf := Transform2D.IDENTITY) -> void:
	var rot := xf.get_rotation()
	var g: Dictionary = L["gun"]
	var ang := Tank.gun_dir(float(st.get("elev", 0.0)), rot)
	var dir := Vector2(cos(ang), sin(ang))
	var fire_t := float(st.get("fire_t", 99.0))
	var recoil := 0.0
	if fire_t >= 0.0 and fire_t < 0.6:
		recoil = 4.0 * (1.0 - fire_t / 0.6) if fire_t > 0.05 else 4.0
	var o: Vector2 = xf * (g["trunnion"] as Vector2) - dir * recoil
	var ln := float(g["len"])
	var c := BARREL
	var lit := Color("#8a7458")
	Px.profile(img, o, ang, [
		[9.0, 12.0, 4.6, 4.6, Color("#3a3026"), Color("#241c14"), Color("#100a06")],
		[12.0, 25.0, 3.4, 3.0, c[0], c[1], c[2]],
		[24.0, 26.0, 3.6, 3.6, lit, c[0], c[2]],
		[26.0, ln * 0.62, 2.3, 2.1, c[0], c[1], c[2]],
		[ln * 0.62, ln * 0.71, 3.0, 3.0, c[0], c[1], c[2]],
		[ln * 0.62, ln * 0.62 + 1.0, 3.0, 3.0, lit, c[0], c[2]],
		[ln * 0.71, ln - 7.0, 2.0, 1.9, c[0], c[1], c[2]],
		[ln - 7.0, ln, 3.2, 3.2, c[0], c[1], c[2]],
		[ln - 4.5, ln - 3.5, 3.2, 3.2, OUT, OUT, OUT],
		[ln - 1.0, ln, 3.2, 3.2, lit, c[0], c[2]],
	])
	if fire_t >= 0.0 and fire_t < 0.12:
		Tank._flash(img, o + dir * (ln + 2.0), ang, 1.2 if fire_t < 0.06 else 0.7)
	var sa := Tank.gun_dir(float(st.get("sec_elev", 0.0)), rot)
	var sd := Vector2(cos(sa), sin(sa))
	var revs := float(st.get("sec_revs", -1.0))
	var k := 0
	for b: Dictionary in L["bow"]:
		var piv: Vector2 = xf * (b["pivot"] as Vector2)
		var bl := float(b["len"])
		Px.profile(img, piv, sa, [
			[2.0, 10.0, 1.6, 1.6, Color("#4a4238"), Color("#2c261e"), Color("#120e0a")],
			[10.0, bl, 0.9, 0.9, Color("#6a5c4a"), Color("#3a3228"), Color("#16110c")],
			[bl - 2.5, bl, 1.3, 1.3, Color("#2c261e"), Color("#2c261e"), Color("#120e0a")],
		])
		Px.profile(img, piv, sa, [[-1.0, 3.0, 3.2, 2.8, Color("#3a2c1e"), Color("#22180f"), Color("#100a06")]])
		if revs >= 0.0:
			var f := fposmod(revs * 2.0, 1.0)
			if f < 0.3 and int(floor(revs * 2.0)) % 2 == k:
				Tank._flash(img, piv + sd * (bl + 1.5), sa, 0.6)
		k += 1
