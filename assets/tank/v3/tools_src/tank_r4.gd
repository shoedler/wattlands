extends RefCounted
## r4: the reference's own tank (v2's 4-rider cut, 960 scale) at 0.9, re-pixelled (r4_base.gd) as the
## static base, with the live parts drawn over and under it per frame: the track (shoes, the rear
## wrap round the idler, the high front sprocket, the flat lower run, the top run under the skirt),
## the road wheels, the main barrel, the two bow guns tilting out of their armoured box, a rider on a
## crank in each of the five stations, the machines' moving parts, the loader cycle (rack -> hoist up
## a shaft through the hull into the turret -> a breech glimpse: open, ram, shut), the seated crew in
## the quarters, the turret's searchlight and commander. Coordinates: base px (v2 4-rider px x 0.9).

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Mach = preload("res://assets/tank/v3/tools_src/mach.gd")
const Dress = preload("res://assets/tank/v3/tools_src/dress.gd")
const Tank = preload("res://assets/tank/v3/tools_src/tank.gd")

const BASE := "res://build/v3mock/r4/base.png"
const OUT := Color("#050302")
const BARREL: Array = [Color("#5e5040"), Color("#342a20"), Color("#140e0a")]


static func layout() -> Dictionary:
	var xs: Array = [71.55, 94.05, 122.4, 149.4, 175.5, 202.95, 229.95, 255.6, 281.7, 307.35, 333.0, 357.75, 385.2]
	var wheels: Array = []
	for x in xs:
		wheels.append({"x": float(x), "y": 196.5, "r": 7.5})
	var rooms := {
		"drive": Rect2i(89, 152, 92, 31), "loader": Rect2i(181, 152, 69, 31), "gun": Rect2i(250, 152, 43, 31),
		"lights": Rect2i(293, 152, 43, 31), "sec": Rect2i(361, 156, 30, 27),
		"quarters": Rect2i(104, 125, 160, 24), "turret_drive": Rect2i(268, 123, 67, 27), "upper_front": Rect2i(340, 131, 22, 24),
	}
	var shaft := Rect2i(235, 110, 10, 43)
	var glimpse := Rect2i(326, 95, 20, 13)
	var all: Array = []
	var groups: Array = []
	var gmap := {"drive": 1, "loader": 4, "gun": 3, "lights": 2, "sec": 5, "quarters": 6, "turret_drive": 6, "upper_front": 6}
	for k: String in rooms:
		all.append(rooms[k])
		groups.append(gmap[k])
	all.append(shaft)
	groups.append(4)
	all.append(glimpse)
	groups.append(4)
	return {
		"name": "R4",
		"size": Vector2i(475, 216),
		"ground": 209.0,
		"rooms": rooms,
		"rooms_all": all,
		"room_groups": groups,
		"shaft": shaft,
		"glimpse": glimpse,
		"crate": Rect2i(199, 85, 16, 20),
		"plaques": [Rect2i(216, 89, 19, 12), Rect2i(243, 90, 9, 9)],
		"mask_bands": [[Rect2i(366, 97, 80, 12)], [Rect2i(403, 123, 24, 8)], [Rect2i(433, 135, 22, 8)]],
		"spill_px": 7,
		"spill_amt": 0.35,
		"tints": {2: Color("#a8d0ff"), 4: Color("#ffa040")},
		"gun": {"trunnion": Vector2(350.1, 103.05), "len": 90.5},
		"bow": [{"pivot": Vector2(400.0, 126.9), "len": 23.5}, {"pivot": Vector2(430.2, 139.0), "len": 22.0}],
		"details": [
			{"kind": "lamp_red", "at": Vector2i(31, 127)},
			{"kind": "lamp_red", "at": Vector2i(442, 149)},
			{"kind": "lamp_green", "at": Vector2i(105, 102)},
			{"kind": "headlight", "at": Vector2i(453, 164)},
			{"kind": "searchlight", "at": Vector2i(303, 64)},
		],
		"gear": {
			"T": 5.0, "up": 3.0, "droop": 2.0, "skirt_y": 187, "rear_cut": [Vector2(14, 140), Vector2(56, 187)],
			"idler": {"c": Vector2(30, 162), "r": 11.0},
			"sprocket": {"c": Vector2(420.3, 188.1), "r": 16.6},
			"rollers": [
				{"c": Vector2(108, 189), "r": 2.0}, {"c": Vector2(189, 189), "r": 2.0}, {"c": Vector2(268, 189), "r": 2.0},
				{"c": Vector2(345, 189), "r": 2.0}, {"c": Vector2(398, 188), "r": 2.0},
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
	Gear.draw_back(img, L["gear"], Transform2D.IDENTITY, wc, travel)
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
	# drive: the rider before the long diesel, a flywheel on its rear end, rockers bobbing
	var rd: Rect2i = rooms["drive"]
	var fyd := rd.end.y - 2
	var ad := t * float(rp.call("drive")) / 60.0 * TAU
	var cc := Mach.seat(img, rd.position.x + 1, fyd, ad, sl.call("drive"))
	var fw := Vector2(rd.position.x + 25.5, fyd - 9.5)
	Mach.chain(img, cc, fw, 2.5, 3.0, ad * 1.4)
	Mach.wheel(img, fw, 6.5, ad * 2.4, Mach.ST2, 6)
	Mach.wheel(img, fw, 2.0, ad * 2.4, Mach.BR1, 3, 6)
	if int(sl.call("drive")) >= 0:
		for k in 4:
			var bob := roundi(sin(ad * 2.4 + k * 1.9) + 1.0)
			Mach.pr(img, Rect2i(rd.position.x + 38 + k * 12, fyd - 26 - bob, 2, 2 + bob), Mach.ST3)
		Mach.glow(img, Vector2(rd.position.x + 58, fyd - 18), 16.0, Color("#ff8a30"), 0.12 + 0.05 * sin(t * 13.0))
	# gun: the dynamo, face on
	Mach.dynamo_round(img, rooms["gun"], t, rp.call("gun"), sl.call("gun"))
	# lights: the coil and the V-arc in the cold room
	Mach.arc_v(img, rooms["lights"], t, rp.call("lights"), sl.call("lights"))
	# secondaries: the compact belt feed in the front room, belts up to the bow guns
	beltfeed_small(img, rooms["sec"], t, rp.call("sec"), sl.call("sec"))
	# loader: boiler, rack (baked), hoist up the shaft, the breech glimpse
	loader(img, B, st, rooms["loader"], t, rp.call("loader"), sl.call("loader"))
	# the quarters' crew at their desks (not riders)
	Dress._open = B["open"]
	Dress._w = int(B["w"])
	Dress._h = int(B["h"])
	Dress._g = 6
	var q: Rect2i = rooms["quarters"]
	for k in [0, 2, 3, 5]:
		Dress.sitter(img, q.position.x + 14 + k * 20, q.end.y - 1, 1 if k % 2 == 0 else -1, k)


## The secondaries' front room: rider, a 4-point star on the crank's chain, an ammunition box, two
## belts running up the front wall to the bow guns (2 rounds per pedal revolution).
static func beltfeed_small(i: Image, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var fy := r.end.y - 2
	var on := slot >= 0 and rpm > 1.0
	var revs := t * rpm / 60.0 if on else 0.0
	var cc := Mach.seat(i, r.position.x, fy, revs * TAU, slot)
	var star := Vector2(r.end.x - 7.5, fy - 18.5)
	Mach.chain(i, cc, star, 2.5, 2.5, revs * 9.0)
	for y in range(floori(star.y) - 5, floori(star.y) + 6):
		for x in range(floori(star.x) - 5, floori(star.x) + 6):
			var d := Vector2(x + 0.5, y + 0.5) - star
			var rho := d.length()
			var rr := 2.5 + 1.8 * maxf(cos(4.0 * (atan2(d.y, d.x) - revs * PI)), 0.0)
			if rho < rr:
				Mach.p(i, x, y, Mach.BR2 if d.y < -1.0 else Mach.BR1)
			elif rho < rr + 0.8:
				Mach.p(i, x, y, OUT)
	Mach.box(i, Rect2i(r.end.x - 11, fy - 8, 10, 8), Mach.AMMO, Mach.AMMO_L, Mach.AMMO_D)
	for k in 2:
		var x0 := r.end.x - 8 + k * 3
		for y in range(r.position.y, fy - 8):
			var u := fposmod(float(y) + revs * 4.0, 2.0)
			Mach.p(i, x0, y, Mach.BR2 if u < 1.0 else Mach.BR0)


## The loader: rider, the green boiler on the crank's chain, the hoist rails up the shaft, the tray,
## the shell from the rack onto the tray and up into the turret, then the breech glimpse.
static func loader(img: Image, B: Dictionary, st: Dictionary, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var L: Dictionary = B["L"]
	var clip: PackedByteArray = B["open"]
	var fy := r.end.y - 2
	var ang := t * rpm / 60.0 * TAU
	var on := slot >= 0 and rpm > 1.0
	var cc := Mach.seat(img, r.position.x + 1, fy, ang, slot)
	# the boiler
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
	var hc := sh.position.x + sh.size.x * 0.5
	var low_y := float(fy) - 15.0
	var top_y := float(sh.position.y) - 6.0
	var tray_y := low_y
	var shell_at := Vector2(222.0, low_y)
	var show := lt >= 0.0
	match step:
		"RACK":
			shell_at = Vector2(lerpf(222.0, hc, Tank._ease(k)), low_y)
		"HOIST":
			tray_y = lerpf(low_y, top_y, Tank._ease(k))
			shell_at = Vector2(hc, tray_y)
		"BREECH OPEN", "RAM", "BREECH SHUT":
			tray_y = top_y
			show = false
		"TRAY DOWN":
			tray_y = lerpf(top_y, low_y, Tank._ease(k))
			show = false
	# rails and chain up the shaft
	for y in range(sh.position.y, fy):
		Mach.p(img, sh.position.x + 1, y, Mach.ST2)
		Mach.p(img, sh.end.x - 2, y, Mach.ST2)
		Mach.p(img, sh.end.x - 1, y, Mach.BR1 if posmod(y + floori(tray_y), 3) == 0 else Mach.ST0)
	var ty := floori(tray_y) + 2
	Mach.pr(img, Rect2i(sh.position.x, ty, sh.size.x, 1), Mach.BR1)
	Mach.pr(img, Rect2i(sh.position.x + 1, ty + 1, sh.size.x - 2, 1), OUT)
	if show:
		Tank.shell(img, shell_at, 0.0, clip)
	breech(img, L, st, clip)


## The breech glimpse in the turret side: the breech ring, the sliding block, the round going in.
static func breech(img: Image, L: Dictionary, st: Dictionary, clip: PackedByteArray) -> void:
	var g: Dictionary = L["gun"]
	var ang := Tank.gun_dir(float(st.get("elev", 0.0)), 0.0)
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var o: Vector2 = g["trunnion"]
	var lt := float(st.get("load_t", -1.0))
	var ls := Tank.load_step(lt) if lt >= 0.0 else {"step": "IDLE", "k": 0.0}
	var opened := 0.0
	var shell_u := -999.0
	match str(ls["step"]):
		"BREECH OPEN":
			opened = Tank._ease(float(ls["k"]))
		"RAM":
			opened = 1.0
			shell_u = lerpf(-46.0, -16.0, Tank._ease(float(ls["k"])))
		"BREECH SHUT":
			opened = 1.0 - Tank._ease(float(ls["k"]))
	Px.profile(img, o + n * 4.0, ang, [[-30.0, -6.0, 0.6, 0.6, Mach.ST2, Mach.ST1, Mach.ST0]], OUT, clip)
	if shell_u > -900.0:
		Tank.shell(img, o + d * shell_u, ang, clip)
		Px.profile(img, o + d * (shell_u - 7.0), ang, [[-30.0, 0.0, 0.6, 0.6, Mach.ST4, Mach.ST3, Mach.ST2]], OUT, clip)
	Px.profile(img, o, ang, [[-20.0, -6.0, 3.6, 3.6, Mach.ST3, Mach.ST2, Mach.ST1], [-18.0, -17.0, 3.6, 3.6, Mach.BR2, Mach.BR1, Mach.BR0]], OUT, clip)
	Px.profile(img, o + n * (opened * 5.0), ang, [[-22.5, -20.0, 3.4, 3.4, Mach.ST4, Mach.ST3, Mach.ST1]], OUT, clip)
	var loaded := lt < 0.0 or lt >= 5.0
	var lamp := o - d * 13.0 - n * 5.0
	Mach.p(img, floori(lamp.x), floori(lamp.y), Color("#ffd27a") if loaded else Color("#3a2414"))
	Mach.glow(img, Vector2(336, 99), 9.0, Color("#ffb060"), 0.35)


# --- the turret roof: the searchlight on its yoke and the commander -------------------------------------


static func roof(img: Image, st: Dictionary) -> void:
	var p := Vector2i(303, 64)
	Px.rect(img, Rect2i(p.x - 2, p.y + 4, 5, 9), OUT)
	Px.rect(img, Rect2i(p.x - 1, p.y + 4, 3, 9), Color("#2a2018"))
	Px.rect(img, Rect2i(p.x - 6, p.y - 4, 12, 9), OUT)
	Px.rect(img, Rect2i(p.x - 5, p.y - 3, 10, 7), Color("#2e2218"))
	Px.rect(img, Rect2i(p.x - 5, p.y - 3, 10, 1), Color("#4e3c2a"))
	Px.rect(img, Rect2i(p.x + 4, p.y - 3, 2, 7), Color("#8a6a3a"))
	var lit := bool(st.get("search_on", true))
	Px.rect(img, Rect2i(p.x + 6, p.y - 3, 1, 7), Color("#fff6d8") if lit else Color("#3a4a4c"))
	# the commander behind it, head and shoulders out of the hatch
	var c := Vector2i(288, 78)
	Px.rect(img, Rect2i(c.x - 4, c.y - 2, 9, 3), OUT)
	Px.rect(img, Rect2i(c.x - 3, c.y - 6, 7, 5), Color("#2e2618"))
	Px.rect(img, Rect2i(c.x - 2, c.y - 6, 5, 1), Color("#4a3e28"))
	Px.rect(img, Rect2i(c.x - 1, c.y - 10, 3, 3), Color("#7a5a40"))
	Px.rect(img, Rect2i(c.x - 2, c.y - 11, 5, 1), Color("#2a2a22"))
	Px.rect(img, Rect2i(c.x - 1, c.y - 12, 3, 1), Color("#3a3a2e"))
	Px.line(img, Vector2i(c.x + 3, c.y - 5), Vector2i(c.x + 9, c.y - 7), Color("#3a3226"))


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
	Px.profile(img, o, ang, [
		[13.0, 22.0, 2.8, 2.4, c[0], c[1], c[2]],
		[22.0, ln * 0.6, 1.6, 1.5, c[0], c[1], c[2]],
		[ln * 0.6, ln * 0.68, 2.2, 2.2, c[0], c[1], c[2]],
		[ln * 0.68, ln - 5.0, 1.5, 1.4, c[0], c[1], c[2]],
		[ln - 5.0, ln, 2.2, 2.2, c[0], c[1], c[2]],
		[ln - 3.0, ln - 2.2, 2.2, 2.2, OUT, OUT, OUT],
		[21.4, 22.4, 2.6, 2.6, Color("#8a7458"), c[0], c[2]],
		[ln * 0.6, ln * 0.6 + 0.8, 2.2, 2.2, Color("#8a7458"), c[0], c[2]],
	])
	if fire_t >= 0.0 and fire_t < 0.12:
		Tank._flash(img, o + dir * (ln + 2.0), ang, 1.0 if fire_t < 0.06 else 0.6)
	var sa := Tank.gun_dir(float(st.get("sec_elev", 0.0)), rot)
	var sd := Vector2(cos(sa), sin(sa))
	var revs := float(st.get("sec_revs", -1.0))
	var k := 0
	for b: Dictionary in L["bow"]:
		var piv: Vector2 = xf * (b["pivot"] as Vector2)
		var bl := float(b["len"])
		Px.profile(img, piv, sa, [
			[2.0, 9.0, 1.4, 1.4, Color("#4a4238"), Color("#2c261e"), Color("#120e0a")],
			[9.0, bl, 0.7, 0.7, Color("#7a6c58"), Color("#4a4034"), Color("#1c1610")],
			[bl - 2.0, bl, 1.0, 1.0, Color("#2c261e"), Color("#2c261e"), Color("#120e0a")],
		])
		Px.profile(img, piv, sa, [[-1.0, 3.0, 3.0, 2.6, Color("#3a2c1e"), Color("#22180f"), Color("#100a06")]])
		if revs >= 0.0:
			var f := fposmod(revs * 2.0, 1.0)
			if f < 0.3 and int(floor(revs * 2.0)) % 2 == k:
				Tank._flash(img, piv + sd * (bl + 1.5), sa, 0.55)
		k += 1
