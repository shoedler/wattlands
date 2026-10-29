extends RefCounted
## r6: r5 after Simon's second review.
##  - The turret shows two tight windows instead of one long one: the ready-rack window by the hoist
##    head (three rounds lying horizontal, nose to the gun; a swinging, telescoping manipulator arm
##    on a chain-driven pivot that takes the round off the hoist head and stows it, the top round fed
##    forward along its rail, a latch per slot) and the breech window (the loading tray, the chain
##    rammer, the breech block). The rack count changes with the cycle.
##  - Both bow guns' receivers show (the box's window and a second one under the lower mount).
##  - Suspension: each road wheel on its own arm and spring follows the ground under it within a
##    larger travel; the hull rides on the fit of the contact points (mock_r6.gd's tilt job).
##  - Firing: pixel-art muzzle blast (star flash, fire ball, smoke puffs and a smoke ring, sparks,
##    dust kick), 9 px recoil and return, the hull rocking back; the bow guns' per-round flashes,
##    tracers, tumbling cases and barrel kick (blast(), bursts(): drawn on the canvas).
## Coordinates: base px (v2 4-rider px x 0.9).

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Mach = preload("res://assets/tank/v3/tools_src/mach.gd")
const Dress = preload("res://assets/tank/v3/tools_src/dress.gd")
const Tank = preload("res://assets/tank/v3/tools_src/tank.gd")
const Tank4 = preload("res://assets/tank/v3/tools_src/tank_r4.gd")
const Tank5 = preload("res://assets/tank/v3/tools_src/tank_r5.gd")

const BASE := "res://build/v3mock/r6/base.png"
const OUT := Color("#050302")
const BARREL: Array = [Color("#6a5a48"), Color("#3a3026"), Color("#17110c")]
const CYCLE := 7.0
## The r6 loader: hull rack -> hoist -> stow in the ready rack -> feed the top round to the tray ->
## breech open -> ram -> breech shut -> reset.
const STEPS := [
	["RACK", 0.0, 1.0], ["HOIST", 1.0, 2.4], ["STOW", 2.4, 3.4], ["FEED", 3.4, 4.4], ["BREECH OPEN", 4.4, 4.9],
	["RAM", 4.9, 5.8], ["BREECH SHUT", 5.8, 6.3], ["RESET", 6.3, 7.0]
]
const F_WHITE := Color("#fff8e0")
const F_YEL := Color("#ffd848")
const F_ORA := Color("#ff8a20")
const F_RED := Color("#c83a14")
const F_DRED := Color("#5a1808")
const SMOKE: Array = [Color("#2a2622"), Color("#3e3832"), Color("#5a5248"), Color("#7a7062")]
const DUST: Array = [Color("#2e2618"), Color("#463a28"), Color("#6a5a40")]


static func step_at(lt: float) -> Dictionary:
	for s: Array in STEPS:
		if lt >= float(s[1]) and lt < float(s[2]):
			return {"step": str(s[0]), "k": (lt - float(s[1])) / (float(s[2]) - float(s[1]))}
	return {"step": "IDLE", "k": 0.0}


static func layout() -> Dictionary:
	var L := Tank5.layout()
	L["name"] = "R6"
	var shaft := Rect2i(237, 106, 10, 47)
	var rackwin := Rect2i(234, 90, 39, 21)
	var breechwin := Rect2i(313, 95, 34, 15)
	var boxwin := Rect2i(366, 116, 27, 12)
	var boxwin2 := Rect2i(410, 140, 18, 9)
	var rooms: Dictionary = L["rooms"]
	var all: Array = []
	var groups: Array = []
	var gmap := {"drive": 1, "loader": 4, "gun": 3, "lights": 2, "sec": 5, "quarters": 6, "turret_drive": 6, "upper_front": 6}
	for k: String in rooms:
		all.append(rooms[k])
		groups.append(gmap[k])
	for extra: Rect2i in [shaft, rackwin, breechwin, boxwin, boxwin2]:
		all.append(extra)
		groups.append(4)
	L["rooms_all"] = all
	L["room_groups"] = groups
	L["shaft"] = shaft
	L["rackwin"] = rackwin
	L["breechwin"] = breechwin
	L["boxwin"] = boxwin
	L["boxwin2"] = boxwin2
	L.erase("window")
	L["cuts"] = [
		{"rect": shaft, "floor": false, "reach": 20.0},
		{"rect": rackwin, "lamp": Vector2(262, 92), "reach": 26.0, "floor": false},
		{"rect": breechwin, "lamp": Vector2(326, 97), "reach": 20.0, "floor": false},
		{"rect": boxwin, "lamp": Vector2(380, 118), "reach": 20.0, "floor": false},
		{"rect": boxwin2, "lamp": Vector2(418, 141), "reach": 12.0, "floor": false},
	]
	var g: Dictionary = L["gear"]
	g["up"] = 7.0
	g["droop"] = 5.0
	# the aft idler 6 px further in (art fix round, 2026-10-28): the track round it no longer pokes
	# past the rear plate; it still sits behind the armour as approved
	g["idler"] = {"c": Vector2(36, 162), "r": 11.0}
	L["rack"] = {"pivot": Vector2(251.5, 95.5), "slots_x": 263.0, "slots_y": [107.0, 102.0, 97.0], "head": Vector2(242.0, 105.0)}
	return L


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


## The main gun's recoil (px back along the bore) `ft` s after the shot: 11 px in two frames,
## back over about 0.55 s.
static func recoil(ft: float) -> float:
	if ft < 0.0 or ft > 0.65:
		return 0.0
	if ft < 0.06:
		return 11.0 * ft / 0.06
	var k := (ft - 0.06) / 0.59
	return 11.0 * (1.0 - k) * (1.0 - k)


## The hull's rock on its springs after the shot (degrees, negative = nose up): about 2 degrees back,
## a bounce, settled by 1.5 s.
static func rock(ft: float) -> float:
	if ft < 0.0 or ft > 1.8:
		return 0.0
	return -2.2 * exp(-ft * 2.6) * cos(ft * 9.0) * minf(ft / 0.05, 1.0)


## The turret's jolt (px, along the bore, backwards) in the first frames.
static func jolt(ft: float) -> float:
	if ft < 0.0 or ft > 0.15:
		return 0.0
	return 2.0 if ft < 0.07 else 1.0


## A screen-shake hint for the view (canvas px) for the first three frames after the shot.
static func shake(ft: float) -> Vector2i:
	if ft < 0.0 or ft >= 0.1:
		return Vector2i.ZERO
	var k := int(floor(ft * 30.0))
	return [Vector2i(2, -1), Vector2i(-2, 1), Vector2i(1, 1)][clampi(k, 0, 2)]


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
	for y in range(176, 204):
		for x in range(44, 412):
			img.set_pixel(x, y, Color("#0a0705") if y < 198 else Color("#070504"))
	Gear.draw_back(img, L["gear"], Transform2D.IDENTITY, wc, travel)
	for y in range(180, 200):
		var k := lerpf(0.3, 1.0, float(y - 180) / 20.0)
		for x in range(20, 445):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	img.blend_rect(B["img"], Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	interior(img, B, st)
	Gear.draw_front(img, L["gear"], Transform2D.IDENTITY, wc, travel)
	Tank5.roof(img, st)
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
	var rd: Rect2i = rooms["drive"]
	var fyd := rd.end.y - 2
	var ad := t * float(rp.call("drive")) / 60.0 * TAU
	var eng := ad * 2.4
	var cc := Mach.seat(img, rd.position.x + 1, fyd, ad, sl.call("drive"))
	Tank5.diesel_open(img, Rect2i(rd.position.x + 33, rd.position.y + 6, 48, 22), eng, int(sl.call("drive")) >= 0, t)
	var fw := Vector2(rd.position.x + 25.5, fyd - 9.5)
	Mach.chain(img, cc, fw, 2.5, 3.0, ad * 1.4)
	Mach.wheel(img, fw, 6.5, eng, Mach.ST2, 6)
	Mach.wheel(img, fw, 2.0, eng, Mach.BR1, 3, 6)
	Mach.dynamo_round(img, rooms["gun"], t, rp.call("gun"), sl.call("gun"))
	Mach.arc_v(img, rooms["lights"], t, rp.call("lights"), sl.call("lights"))
	Tank4.beltfeed_small(img, rooms["sec"], t, rp.call("sec"), sl.call("sec"))
	loader(img, B, st, rooms["loader"], t, rp.call("loader"), sl.call("loader"))
	receivers(img, L, st)
	Dress._open = B["open"]
	Dress._w = int(B["w"])
	Dress._h = int(B["h"])
	Dress._g = 6
	var q: Rect2i = rooms["quarters"]
	for k in [0, 2, 3, 5]:
		Dress.sitter(img, q.position.x + 14 + k * 20, q.end.y - 1, 1 if k % 2 == 0 else -1, k)


static func round_h(img: Image, c: Vector2, clip: PackedByteArray) -> void:
	Tank.shell(img, c, 0.0, clip)


## The loader: rider and boiler (as r5), the hoist up the shaft to the hoist head in the ready-rack
## window, the manipulator arm stowing the round, the feed rail, then the breech window.
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
	var lt := float(st.get("load_t", -1.0))
	var ls := step_at(lt) if lt >= 0.0 else {"step": "IDLE", "k": 0.0}
	var step: String = ls["step"]
	var k := float(ls["k"])
	var rk: Dictionary = L["rack"]
	var sh: Rect2i = L["shaft"]
	var head: Vector2 = rk["head"]
	var low_y := float(fy) - 15.0
	var tray_y := low_y
	var on_tray := false
	var tray_shell := Vector2(222.0, low_y)
	match step:
		"RACK":
			tray_shell = Vector2(lerpf(222.0, head.x, Tank._ease(k)), low_y)
			on_tray = true
		"HOIST":
			tray_y = lerpf(low_y, head.y, Tank._ease(k))
			tray_shell = Vector2(head.x, tray_y)
			on_tray = true
		"STOW", "FEED", "BREECH OPEN", "RAM", "BREECH SHUT":
			tray_y = head.y
		"RESET":
			tray_y = lerpf(head.y, low_y, Tank._ease(k))
	var rail_top := floori(head.y) - 12
	for y in range(rail_top, fy):
		Mach.p(img, sh.position.x + 1, y, Mach.ST2)
		Mach.p(img, sh.end.x - 2, y, Mach.ST2)
		Mach.p(img, sh.end.x - 1, y, Mach.BR1 if posmod(y + floori(tray_y), 3) == 0 else Mach.ST0)
	Mach.wheel(img, Vector2(sh.end.x - 0.5, rail_top - 0.5), 2.0, tray_y * 0.6, Mach.BR1, 3)
	var ty := floori(tray_y) + 2
	Mach.pr(img, Rect2i(sh.position.x, ty, sh.size.x, 1), Mach.BR1)
	Mach.p(img, sh.position.x, ty - 1, Mach.BR0)
	Mach.p(img, sh.end.x - 1, ty - 1, Mach.BR0)
	if on_tray:
		round_h(img, tray_shell, clip)
	rack(img, L, st, step, k, clip)
	breech6(img, L, st, step, k, clip)


## The ready rack and its manipulator: three horizontal slots with a latch each; the arm pivots on a
## sprocket chained to a small motor, telescopes, and carries the round in its two-pronged gripper
## from the hoist head into the next free slot (STOW); the top round slides forward out of the rack
## along its rail toward the breech (FEED).
static func rack(img: Image, L: Dictionary, st: Dictionary, step: String, k: float, clip: PackedByteArray) -> void:
	var rk: Dictionary = L["rack"]
	var piv: Vector2 = rk["pivot"]
	var head: Vector2 = rk["head"]
	var sx: float = rk["slots_x"]
	var sy: Array = rk["slots_y"]
	var base_n := clampi(int(st.get("ready", 2)), 0, 2)
	var x0 := floori(sx) - 8
	var x1 := floori(sx) + 9
	for y in range(floori(float(sy[2])) - 3, floori(float(sy[0])) + 4):
		Mach.p(img, x0, y, Mach.ST2)
		Mach.p(img, x1, y, Mach.ST1)
	for s in 3:
		var yy := floori(float(sy[s])) + 2
		Mach.pr(img, Rect2i(x0, yy, x1 - x0 + 1, 1), Mach.ST2)
	Mach.pr(img, Rect2i(x0, floori(float(sy[2])) - 3, 40, 1), Mach.ST3)
	var filled: Array[bool] = [false, false, false]
	for s in base_n:
		filled[s] = true
	if step == "STOW" and k > 0.85:
		filled[base_n] = true
	for s in 3:
		if filled[s]:
			round_h(img, Vector2(sx, float(sy[s])), clip)
		var lx := x1 + 1
		var ly := floori(float(sy[s]))
		Mach.p(img, lx, ly - (1 if filled[s] else -1), Mach.BR2)
		Mach.p(img, lx, ly, Mach.BR1)
	var rest := piv + Vector2(-1, 9)
	var grip := rest
	var carrying := false
	if step == "STOW":
		var target := Vector2(sx, float(sy[base_n]))
		if k < 0.25:
			grip = rest.lerp(head, Tank._ease(k / 0.25))
		elif k < 0.85:
			var u := Tank._ease((k - 0.25) / 0.6)
			grip = head.lerp(target, u) + Vector2(0, -6.0 * sin(u * PI))
			carrying = true
		else:
			grip = target.lerp(rest, Tank._ease((k - 0.85) / 0.15))
	elif step == "FEED" and k < 0.3:
		# the arm nudges the top round onto its rail
		grip = rest.lerp(Vector2(sx - 7.0, float(sy[base_n])), Tank._ease(k / 0.3))
	var mot := piv + Vector2(-2, 12)
	Mach.box(img, Rect2i(floori(mot.x) - 3, floori(mot.y) - 2, 6, 5), Mach.ST1, Mach.ST2, Mach.ST0)
	var aang := (grip - piv).angle()
	Mach.chain(img, mot, piv, 1.5, 2.0, aang * 4.0)
	Mach.wheel(img, piv, 2.5, aang, Mach.BR1, 3, 6)
	var d := grip - piv
	var ln := d.length()
	var dn := d / maxf(ln, 0.001)
	var nn := Vector2(-dn.y, dn.x)
	Mach.pl(img, piv, piv + dn * minf(ln, 6.0), Mach.ST3)
	Mach.pl(img, piv + nn, piv + nn + dn * minf(ln, 6.0), Mach.ST1)
	Mach.pl(img, piv + dn * 5.0, grip, Mach.ST4)
	for side in [-1.0, 1.0]:
		var pp := grip + Vector2(0, 2.4 * side)
		Mach.p(img, floori(pp.x), floori(pp.y), Mach.BR2)
		Mach.p(img, floori(pp.x) + 1, floori(pp.y), Mach.BR1)
	if carrying:
		round_h(img, grip, clip)
	if step == "STOW" and k < 0.25:
		round_h(img, head, clip)
	if step == "FEED":
		var fx := lerpf(sx, sx + 30.0, Tank._ease(k))
		round_h(img, Vector2(fx, float(sy[base_n])), clip)


## The breech window: the loading tray, the chain rammer, the breech block.
static func breech6(img: Image, L: Dictionary, st: Dictionary, step: String, k: float, clip: PackedByteArray) -> void:
	var g: Dictionary = L["gun"]
	var ang := Tank.gun_dir(float(st.get("elev", 0.0)), 0.0)
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var o: Vector2 = (g["trunnion"] as Vector2) - d * recoil(float(st.get("fire_t", 99.0)))
	var opened := 0.0
	var shell_u := -999.0
	var ram := 0.0
	match step:
		"FEED":
			if k > 0.4:
				shell_u = lerpf(-50.0, -30.0, Tank._ease((k - 0.4) / 0.6))
		"BREECH OPEN":
			opened = Tank._ease(k)
			shell_u = -30.0
		"RAM":
			opened = 1.0
			shell_u = lerpf(-30.0, -14.0, Tank._ease(k))
			ram = shell_u + 30.0
		"BREECH SHUT":
			opened = 1.0 - Tank._ease(k)
			ram = lerpf(16.0, 0.0, Tank._ease(k))
	Px.profile(img, o + n * 2.6, ang, [[-36.0, -21.0, 0.6, 0.6, Mach.ST3, Mach.ST2, Mach.ST1]], OUT, clip)
	Px.profile(img, o + n * 1.6, ang, [[-36.0, -35.0, 1.2, 1.2, Mach.BR1, Mach.BR1, Mach.BR0], [-22.0, -21.0, 1.2, 1.2, Mach.BR1, Mach.BR1, Mach.BR0]], OUT, clip)
	var hous := o + d * -40.0
	Px.profile(img, hous, ang, [[-3.0, 3.0, 2.6, 2.6, Mach.ST3, Mach.ST2, Mach.ST1]], OUT, clip)
	for j in int(ram) + 1:
		var q := hous + d * (3.0 + j)
		Mach.p(img, floori(q.x), floori(q.y), Mach.BR2 if j % 2 == 0 else Mach.ST0)
	if shell_u > -900.0:
		Tank.shell(img, o + d * shell_u, ang, clip)
	Px.profile(img, o, ang, [
		[-20.0, -6.0, 4.2, 4.2, Mach.ST3, Mach.ST2, Mach.ST1],
		[-18.0, -17.0, 4.2, 4.2, Mach.BR2, Mach.BR1, Mach.BR0],
	], OUT, clip)
	if opened > 0.2:
		Px.profile(img, o, ang, [[-20.5, -19.5, 1.6, 1.6, OUT, OUT, OUT]], Color(0, 0, 0, 0), clip)
	Px.profile(img, o + n * (opened * 6.0), ang, [[-23.0, -20.0, 4.0, 4.0, Mach.ST4, Mach.ST3, Mach.ST1]], OUT, clip)


## Both bow guns' receivers: the box's window (upper gun) and the window under the lower mount;
## each with its belt feeding in and a cocking slide working, a glow on each shot.
static func receivers(img: Image, L: Dictionary, st: Dictionary) -> void:
	var revs := float(st.get("sec_revs", -1.0))
	var on := revs >= 0.0
	var ph := revs * 2.0 if on else 0.0
	var wins: Array = [L["boxwin"], L["boxwin2"]]
	for k in 2:
		var r: Rect2i = wins[k]
		var rw := Rect2i(r.end.x - 13, r.position.y + r.size.y / 2 - 2, 11, 5)
		Mach.box(img, rw, Mach.ST2, Mach.ST3, Mach.ST1)
		var shot := on and fposmod(ph, 1.0) < 0.3 and int(floor(ph)) % 2 == k
		Mach.p(img, rw.position.x + 3 + (2 if shot else 0), rw.position.y + 1, Mach.BR2)
		for j in 10:
			var u := fposmod(float(j) * 2.0 - ph * 4.0, 20.0)
			var bxp := r.position.x + 1 + floori(u * float(rw.position.x - r.position.x - 1) / 20.0)
			Mach.p(img, bxp, rw.position.y + 3, Mach.BR2 if j % 2 == 0 else Mach.BR0)
			Mach.p(img, bxp, rw.position.y + 4, Mach.ST0)
		if shot:
			Mach.glow(img, Vector2(rw.end.x, rw.position.y + 2), 6.0, Color("#ffb060"), 0.7)


# --- the barrel and the bow guns ---------------------------------------------------------------------------


static func guns(img: Image, L: Dictionary, st: Dictionary, xf := Transform2D.IDENTITY) -> void:
	var rot := xf.get_rotation()
	var g: Dictionary = L["gun"]
	var ang := Tank.gun_dir(float(st.get("elev", 0.0)), rot)
	var dir := Vector2(cos(ang), sin(ang))
	var o: Vector2 = xf * (g["trunnion"] as Vector2) - dir * recoil(float(st.get("fire_t", 99.0)))
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
	var sa := Tank.gun_dir(float(st.get("sec_elev", 0.0)), rot)
	var sd := Vector2(cos(sa), sin(sa))
	var revs := float(st.get("sec_revs", -1.0))
	var k := 0
	for b: Dictionary in L["bow"]:
		var kick := 0.0
		if revs >= 0.0:
			var f := fposmod(revs * 2.0, 1.0)
			if f < 0.18 and int(floor(revs * 2.0)) % 2 == k:
				kick = 1.5
		var piv: Vector2 = xf * (b["pivot"] as Vector2) - sd * kick
		var bl := float(b["len"])
		Px.profile(img, piv, sa, [
			[2.0, 10.0, 1.6, 1.6, Color("#4a4238"), Color("#2c261e"), Color("#120e0a")],
			[10.0, bl, 0.9, 0.9, Color("#6a5c4a"), Color("#3a3228"), Color("#16110c")],
			[bl - 2.5, bl, 1.3, 1.3, Color("#2c261e"), Color("#2c261e"), Color("#120e0a")],
		])
		Px.profile(img, xf * (b["pivot"] as Vector2), sa, [[-1.0, 3.0, 3.2, 2.8, Color("#3a2c1e"), Color("#22180f"), Color("#100a06")]])
		k += 1


## The main gun's muzzle in canvas px through `xf`, at the current recoil.
static func muzzle(L: Dictionary, st: Dictionary, xf: Transform2D) -> Dictionary:
	var g: Dictionary = L["gun"]
	var ang := Tank.gun_dir(float(st.get("elev", 0.0)), xf.get_rotation())
	var dir := Vector2(cos(ang), sin(ang))
	var o: Vector2 = xf * (g["trunnion"] as Vector2) - dir * recoil(float(st.get("fire_t", 99.0)))
	return {"p": o + dir * (float(g["len"]) + 1.0), "a": ang}


# --- firing effects, on the canvas ---------------------------------------------------------------------------


## A hard-edged lumpy pixel disc with a lit upper-left, from a 4-step ramp (dark -> light); `fade`
## drops pixels by a fixed hash (dithered dissolve).
static func puff(img: Image, c: Vector2, r: float, ramp: Array, fade: float, seed: int) -> void:
	for y in range(floori(c.y - r) - 1, ceili(c.y + r) + 2):
		for x in range(floori(c.x - r) - 1, ceili(c.x + r) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var lump := r * (0.85 + 0.25 * Px.h2(floori(atan2(d.y, d.x) * 3.0) + 9, seed, 7))
			var rho := d.length()
			if rho > lump:
				continue
			if fade > 0.0 and Px.h2(x, y, seed + 3) < fade:
				continue
			var lit := (-d.x - d.y) / maxf(rho, 0.001)
			var col: Color = ramp[1]
			if rho > lump - 1.0:
				col = ramp[0]
			elif lit > 0.5 and rho > lump * 0.45:
				col = ramp[3]
			elif lit > -0.1:
				col = ramp[2]
			Px.put(img, x, y, col)


## The main gun's blast `ft` s after the shot (r6b: 2-3x the r6 one), hard pixels throughout:
##  0.00-0.07  a big cross/star flash (about 50 px across) with blade jets out of the slotted brake
##  0.05-0.22  a lumpy fire ball (30-40 px) rolling forward, flame fragments thrown off
##  0.08-1.9   a billowing grey-brown smoke cloud growing to about 100 px, a smoke ring
##  0.02-1.4   blast dust off the road under the muzzle, a dust shockwave running along the road both
##             ways, pebbles kicked up; sparks
## `m` = muzzle, `a` = bore angle, `gy` = the road's canvas y under the muzzle.
static func blast(img: Image, m: Vector2, a: float, ft: float, gy: float) -> void:
	if ft < 0.0 or ft > 2.0:
		return
	var d := Vector2(cos(a), sin(a))
	var n := Vector2(-d.y, d.x)
	# smoke (behind everything else)
	if ft > 0.08:
		var age := ft - 0.08
		for j in 16:
			var sp := 18.0 + 46.0 * Px.h2(j, 1, 41)
			var up := 10.0 + 26.0 * Px.h2(j, 2, 41)
			var slow := 1.0 / (1.0 + age * 1.2)
			var c := m + d * (6.0 + j * 4.5 + sp * age * slow) + n * ((Px.h2(j, 3, 41) - 0.5) * 26.0 * minf(age * 2.0, 1.0)) + Vector2(0, -up * age)
			var r := 4.0 + 13.0 * minf(age * 1.1, 1.0) + Px.h2(j, 4, 41) * 4.0
			puff(img, c, r, SMOKE, clampf((age - 0.9) / 1.0, 0.0, 1.0), j * 13)
		var rc := m + d * (8.0 + 60.0 * age / (1.0 + age))
		var rr := 5.0 + 16.0 * minf(age * 1.6, 1.0)
		var fade := clampf((age - 0.5) / 0.8, 0.0, 1.0)
		for k in 72:
			var t := TAU * k / 72.0
			for w in 2:
				var q := rc + d * cos(t) * (rr * 0.42 + w) + n * sin(t) * (rr + w)
				if Px.h2(k, 9 + w, 5) >= fade:
					Px.put(img, floori(q.x), floori(q.y), SMOKE[2] if sin(t) < 0 else SMOKE[1])
	# dust: the blast off the road under the muzzle, the shockwave along it, pebbles
	if ft > 0.02 and ft < 1.6:
		var age2 := ft - 0.02
		for j in 9:
			var c2 := Vector2(m.x - 30.0 + j * 9.0 + 14.0 * age2, gy - 3.0 - 22.0 * age2 * (0.4 + Px.h2(j, 5, 43)))
			puff(img, c2, 3.0 + 7.0 * minf(age2 * 1.8, 1.0), [DUST[0], DUST[0], DUST[1], DUST[2]], clampf((age2 - 0.6) / 0.8, 0.0, 1.0), j * 7 + 100)
		if age2 < 0.9:
			for side in [-1.0, 1.0]:
				for j in 4:
					var xr: float = m.x + side * (14.0 + 150.0 * age2 - j * 7.0)
					puff(img, Vector2(xr, gy - 2.0), 2.0 + 1.5 * Px.h2(j, 6, 44), [DUST[0], DUST[0], DUST[1], DUST[2]], clampf(age2 / 0.9, 0.0, 1.0), j * 5 + 200 + int(side))
		if age2 < 0.8:
			for j in 12:
				var vx := (Px.h2(j, 7, 45) - 0.3) * 120.0
				var vy := -70.0 - 80.0 * Px.h2(j, 8, 45)
				var pp := Vector2(m.x - 10.0 + j * 3.0, gy - 1.0) + Vector2(vx, vy) * age2 + Vector2(0, 260.0 * age2 * age2)
				if pp.y <= gy:
					Px.put(img, floori(pp.x), floori(pp.y), DUST[0] if j % 2 else Color("#1a140e"))
					Px.put(img, floori(pp.x) + 1, floori(pp.y), DUST[1])
	# sparks
	if ft < 0.5:
		for j in 26:
			var sa := a + (Px.h2(j, 6, 47) - 0.5) * 2.0
			var spd := 120.0 + 180.0 * Px.h2(j, 7, 47)
			var p0 := m + Vector2(cos(sa), sin(sa)) * spd * ft + Vector2(0, 80.0 * ft * ft)
			var p1 := p0 - Vector2(cos(sa), sin(sa)) * 4.0
			Px.linef(img, p1, p0, F_YEL if j % 3 else F_ORA)
	# the fire ball and its fragments
	if ft >= 0.05 and ft < 0.24:
		var u := ft - 0.05
		var fb := m + d * (12.0 + 90.0 * u)
		var fr := 19.0 - 30.0 * u
		puff(img, fb, fr + 3.0, [F_DRED, F_RED, F_ORA, F_YEL], clampf((u - 0.12) / 0.07, 0.0, 1.0) * 0.6, 77)
		puff(img, fb - d * 2.0 + n * 3.0, fr * 0.62, [F_ORA, F_YEL, F_WHITE, F_WHITE], 0.0, 78)
		puff(img, fb + d * (fr * 0.7) - n * 5.0, fr * 0.45, [F_RED, F_ORA, F_YEL, F_YEL], 0.0, 79)
		for j in 7:
			var fa := a + (Px.h2(j, 11, 49) - 0.5) * 2.4
			var fp := m + Vector2(cos(fa), sin(fa)) * (20.0 + 160.0 * u) + Vector2(0, 50.0 * u * u)
			puff(img, fp, 2.5 + 1.5 * Px.h2(j, 12, 49), [F_DRED, F_RED, F_ORA, F_YEL], 0.0, 80 + j)
	# the cross/star flash with the brake's side jets
	if ft < 0.075:
		var big := 1.0 if ft < 0.04 else 0.75
		var bk := m - d * 4.0
		for y in range(floori(m.y) - 34, ceili(m.y) + 35):
			for x in range(floori(m.x) - 16, ceili(m.x) + 58):
				var v := Vector2(x + 0.5, y + 0.5) - m
				var rho := v.length()
				var phi := atan2(v.dot(n), v.dot(d))
				var R := (8.0 + 40.0 * pow(maxf(cos(phi), 0.0), 7.0) + 20.0 * pow(maxf(cos(4.0 * phi), 0.0), 12.0) + 10.0 * pow(maxf(cos(8.0 * phi + 0.4), 0.0), 16.0)) * big
				# the brake's side jets: blades straight up and down out of the slots
				var vb := Vector2(x + 0.5, y + 0.5) - bk
				var jet := absf(vb.dot(d)) < 2.5 - absf(vb.dot(n)) * 0.06 and absf(vb.dot(n)) < 24.0 * big
				if rho > R + 1.5 and not jet:
					continue
				var col := F_ORA
				if jet:
					col = F_YEL if absf(vb.dot(n)) < 14.0 * big else F_ORA
				elif rho > R:
					col = F_RED
				elif rho < R * 0.45:
					col = F_WHITE
				elif rho < R * 0.72:
					col = F_YEL
				Px.put(img, x, y, col)


## The bow guns' fire: per-round flashes at the muzzles (alternating), tracers flying out, cases
## tumbling down from under the receivers.
static func bursts(img: Image, L: Dictionary, xf: Transform2D, st: Dictionary) -> void:
	var revs := float(st.get("sec_revs", -1.0))
	if revs < 0.0:
		return
	var rps := float(st.get("sec_rpm", 95.0)) / 60.0 * 2.0
	var sa := Tank.gun_dir(float(st.get("sec_elev", 0.0)), xf.get_rotation())
	var sd := Vector2(cos(sa), sin(sa))
	var now := revs * 2.0
	var wins: Array = [L["boxwin"], L["boxwin2"]]
	for j in range(maxi(int(floor(now)) - 10, 0), int(floor(now)) + 1):
		var k := j % 2
		var age := (now - j) / rps
		var b: Dictionary = L["bow"][k]
		var m: Vector2 = xf * (b["pivot"] as Vector2) + sd * (float(b["len"]) + 1.0)
		if age < 0.9:
			var tp := m + sd * (240.0 * age + 4.0)
			Px.linef(img, tp - sd * 5.0, tp - sd * 2.0, F_ORA)
			Px.linef(img, tp - sd * 2.0, tp, F_WHITE)
		if age < 0.05:
			var nn := Vector2(-sd.y, sd.x)
			for s in 5:
				var q := m + sd * s
				Px.put(img, floori(q.x), floori(q.y), F_WHITE if s < 2 else F_YEL)
			for e in [-2.0, -1.0, 1.0, 2.0]:
				var q2: Vector2 = m + sd * 1.0 + nn * float(e)
				Px.put(img, floori(q2.x), floori(q2.y), F_ORA if absf(e) > 1.0 else F_YEL)
			Px.put(img, floori(m.x + sd.x * 5.0), floori(m.y + sd.y * 5.0), F_ORA)
		if age < 0.55:
			var r: Rect2i = wins[k]
			var e0: Vector2 = xf * Vector2(r.position.x + 6, r.end.y)
			var cp := e0 + Vector2(-14.0 * age, 20.0 * age + 0.5 * 260.0 * age * age)
			var tumble := int(floor(age * 24.0)) % 2
			Px.put(img, floori(cp.x), floori(cp.y), Mach.BR2)
			Px.put(img, floori(cp.x) + (1 if tumble == 0 else 0), floori(cp.y) + (0 if tumble == 0 else 1), Mach.BR1)
