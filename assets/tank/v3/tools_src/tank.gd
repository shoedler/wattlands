extends RefCounted
## The v3 tank mock generator: three five-seat layouts (A long, B two-deck, C rhomboid) and a
## placeholder enemy, built from parts on the pixel grid (hull.gd), the running gear (gear.gd), the
## bay machines (mach.gd), and the guns and the loader drawn here. Everything is deterministic:
## a frame is a pure function of the layout and the state dictionary.
##
## State keys (all optional): t (s), travel (px the hull moved), rpm {drive, gun, loader, lights,
## sec}, crew {bay id: slot or -1}, elev (deg), sec_elev (deg), load_t (s in the 7 s cycle, -1 =
## idle), ready (shells in the ready rack), fire_t (s since the main gun fired), wc (road wheel
## centres in local px), gear (draw the running gear), guns (draw the barrels outside the hull).

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Hull = preload("res://assets/tank/v3/tools_src/hull.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Mach = preload("res://assets/tank/v3/tools_src/mach.gd")

const OUT := Color("#0b0806")
const BARREL: Array = [Color("#6f5638"), Color("#4a3826"), Color("#271c12")]
const BARREL_EN: Array = [Color("#5b6658"), Color("#3a433a"), Color("#1c221d")]
const LOAD_CYCLE := 7.0
## The loader's steps (s): rack -> hoist -> breech opens -> ram -> breech shut -> tray down.
const STEPS := [
	["RACK", 0.0, 1.0], ["HOIST", 1.0, 3.0], ["BREECH OPEN", 3.0, 3.8], ["RAM", 3.8, 5.0], ["BREECH SHUT", 5.0, 5.8],
	["TRAY DOWN", 5.8, 7.0]
]


static func P(a: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for k in range(0, a.size(), 2):
		o.append(Vector2(a[k], a[k + 1]))
	return o


static func _wheels(n: int, x0: float, dx: float, y: float, r: float) -> Array:
	var o: Array = []
	for i in n:
		o.append({"x": roundf(x0 + dx * i), "y": y, "r": r})
	return o


static func _bay(id: String, kind: String, r: Rect2i, group: int) -> Dictionary:
	return {"id": id, "kind": kind, "rect": r, "group": group}


## A dressed bay opening (dress.gd): door "L"/"R"/"", shelf [x0, x1], gauges x, valve x.
static func _open_bay(b: Dictionary, dress: Dictionary) -> Dictionary:
	dress["seed"] = int(b["group"]) * 13 + 5
	return {"rect": b["rect"], "group": b["group"], "dress": dress}


## The usual turret dressing: roof hatch, cupola periscope, searchlight, antenna, grab rail, vision.
static func _turret_details(o: Dictionary) -> Array:
	return [
		{"kind": "hatch_top", "at": o["hatch"], "w": 11},
		{"kind": "periscope", "at": o["periscope"]},
		{"kind": "searchlight", "at": o["searchlight"]},
		{"kind": "antenna", "at": o["antenna"], "h": 26},
		{"kind": "rail", "a": o["rail_a"], "b": o["rail_b"]},
		{"kind": "vision", "at": o["vision"], "w": 4},
		{"kind": "box", "rect": o["box"]},
		{"kind": "slit", "at": o["slit"], "w": 7},
	]


# --- Layouts ---------------------------------------------------------------------------------------


## R3: the reference's tank rebuilt on the pixel grid (Simon picked A, then asked for the reference's
## silhouette back): the long low hull with its wedge front and sloped rear, the second floor (crew
## quarters with a row of lamps, the turret ring hanging from the roof) over the lower deck's five
## stations of different widths (v2's room look: warm diesel, the dynamo's copper, the steam room,
## the arc's cold blue-white; the belt feed in the upper front room behind the bow guns' armoured
## box), the riveted boxy turret with the crate and grille at its rear, the antenna and the long
## barrel, the large high front sprocket and a flat lower run. Coordinates: the reference crop
## (x 30.., y 170..) at 0.9.
static func layout_r3() -> Dictionary:
	var lw := 160
	var bays := [
		_bay("drive", "diesel_long", Rect2i(98, 128, 88, 43), 1),
		_bay("gun", "dynamo_round", Rect2i(190, 128, 50, 43), 3),
		_bay("loader", "steam", Rect2i(244, 128, 74, 43), 4),
		_bay("lights", "arc_v", Rect2i(322, 128, 58, 43), 2),
		_bay("sec", "beltfeed", Rect2i(334, 90, 46, 34), 5),
	]
	var qlamps: Array = [Vector2(110, 96), Vector2(136, 96), Vector2(166, 96), Vector2(196, 96), Vector2(226, 96), Vector2(270, 96)]
	var openings: Array = [
		{"rect": bays[0]["rect"], "group": 1, "dress": {"shelf": [100, 116], "seed": 3}, "lamps": [Vector2(118, 133), Vector2(160, 133)], "reach": 30.0},
		{"rect": bays[1]["rect"], "group": 3, "dress": {"shelf": [192, 208], "seed": 5}, "lamp": Vector2(206, 133), "reach": 28.0},
		{"rect": bays[2]["rect"], "group": 4, "tint": "steam", "dress": {"shelf": [246, 262], "seed": 7}, "lamp": Vector2(270, 133), "reach": 34.0},
		{"rect": bays[3]["rect"], "group": 2, "tint": "cold", "dress": {"shelf": [324, 340], "seed": 9}, "lamp": Vector2(340, 133), "reach": 26.0},
		{"rect": bays[4]["rect"], "group": 5, "dress": {"seed": 11, "pipes": false}, "lamp": Vector2(352, 96), "reach": 26.0},
		{"rect": Rect2i(98, 90, 200, 34), "group": 6, "lamps": qlamps, "reach": 22.0, "quarters": {
			"walls": [128, 182, 240], "bunks": [102, 214], "tables": [150, 198], "lockers": [130],
			"ladders": [242], "ring": Vector2(296, 72), "ring_r": 46.0,
		}},
		{"rect": Rect2i(270, 50, 80, 33), "group": 4, "inset": 3, "lamp": Vector2(286, 54), "reach": 30.0, "dress": {"pipes": false}},
		{"rect": Rect2i(298, 80, 20, 52), "group": 4, "inset": 2, "has_lamp": false, "floor": false, "beam": false, "dim": 0.1},
		{"rect": Rect2i(66, 104, 28, 67), "group": 7, "has_lamp": false, "dim": 0.05, "machinery": true},
	]
	var details: Array = [
		{"kind": "rail", "a": Vector2i(96, 83), "b": Vector2i(330, 83)},
		{"kind": "louvre", "rect": Rect2i(20, 106, 36, 24)},
		{"kind": "hatch", "rect": Rect2i(30, 134, 12, 14)},
		{"kind": "stack", "x": 80, "y0": 63, "y1": 77},
		{"kind": "stack", "x": 92, "y0": 66, "y1": 77},
		{"kind": "can", "at": Vector2i(100, 70)},
		{"kind": "coil", "at": Vector2i(112, 74)},
		{"kind": "lamp_red", "at": Vector2i(19, 96)},
		{"kind": "lamp_green", "at": Vector2i(106, 72)},
		{"kind": "lamp_red", "at": Vector2i(444, 117)},
		{"kind": "headlight", "at": Vector2i(450, 138)},
		{"kind": "vision", "at": Vector2i(380, 128), "w": 5},
		{"kind": "bolt_row", "a": Vector2i(96, 126), "b": Vector2i(380, 126)},
		{"kind": "bolt_row", "a": Vector2i(58, 175), "b": Vector2i(396, 175)},
		{"kind": "bolt_row", "a": Vector2i(96, 88), "b": Vector2i(334, 88)},
		{"kind": "links", "a": Vector2(422, 126), "b": Vector2(442, 132), "n": 2},
		# turret
		{"kind": "louvre", "rect": Rect2i(126, 57, 40, 20)},
		{"kind": "crate", "rect": Rect2i(169, 52, 26, 26)},
		{"kind": "antenna", "at": Vector2i(183, 52), "h": 50},
		{"kind": "vision", "at": Vector2i(212, 62), "w": 5},
		{"kind": "vision", "at": Vector2i(240, 62), "w": 5},
		{"kind": "slit", "at": Vector2i(204, 52), "w": 10},
		{"kind": "periscope", "at": Vector2i(236, 44)},
		{"kind": "hatch_top", "at": Vector2i(262, 37), "w": 11},
		{"kind": "commander", "at": Vector2i(282, 37)},
		{"kind": "searchlight", "at": Vector2i(312, 39), "lit": true},
		{"kind": "rail", "a": Vector2i(200, 48), "b": Vector2i(262, 48)},
	]
	return {
		"name": "R3",
		"title": "V3 TANK (REFERENCE REBUILD)",
		"size": Vector2i(470, 202),
		"ground": 197.0,
		"spill_px": 9,
		"spill_amt": 0.45,
		"tints": {2: Color("#a8d0ff"), 7: Color(0, 0, 0, 0), 4: Color("#ffa040")},
		"parts": [
			{"poly": P([120, 86, 121, 54, 126, 50, 196, 50, 200, 44, 336, 44, 348, 50, 354, 60, 354, 86]), "seams_x": [168, 198, 268], "seams_y": [62], "tone": 0.02, "seed": 51},
			{"poly": P([70, 90, 73, 77, 118, 77, 121, 90]), "seams_x": [96], "tone": 0.0, "seed": 52},
			{"poly": P([12, 100, 30, 94, 70, 90, 94, 86, 338, 86, 420, 117, 446, 119, 452, 127, 452, 146, 444, 158, 420, 171, 398, 179, 54, 179, 30, 170, 14, 148, 8, 120]),
			 "seams_x": [64, 96, 188, 242, 320, 332, 392], "seams_y": [90, 126, 171], "seed": 53},
			{"poly": P([346, 62, 360, 60, 367, 64, 367, 80, 360, 84, 346, 84]), "cast": true, "tone": 0.06, "seed": 54},
			{"poly": P([248, 45, 252, 37, 288, 37, 292, 45]), "cast": true, "tone": 0.04, "seed": 55},
			{"poly": P([378, 104, 400, 97, 414, 100, 417, 121, 383, 125]), "seams_x": [398], "tone": 0.05, "seed": 56, "shadow": true, "top_face": 2},
		],
		"bays": bays,
		"openings": openings,
		"details": details,
		"gun": {"trunnion": Vector2(360, 72.5), "len": 86.0, "breech_off": 8.0},
		"sec": {"pivot": Vector2(412.5, 110.5), "len": 30.0, "feed": Vector2(372, 108), "boxed": true},
		"loader": {"bay": 2, "boiler_x": 266, "rack_x": 280, "hoist_x": 300, "window": Rect2i(270, 50, 80, 33), "green": true},
		"gear": {
			"T": 5.0, "up": 3.0, "droop": 2.0,
			"idler": {"c": Vector2(22, 158), "r": 11.0},
			"sprocket": {"c": Vector2(414, 162), "r": 17.0},
			"rollers": [
				{"c": Vector2(64, 173), "r": 2.5}, {"c": Vector2(134, 173), "r": 2.5}, {"c": Vector2(204, 173), "r": 2.5},
				{"c": Vector2(274, 173), "r": 2.5}, {"c": Vector2(344, 173), "r": 2.5},
			],
			"wheels": _wheels(13, 50.0, 28.0, 185.0, 7.0),
		},
		"_lw": lw,
	}


## The placeholder enemy (the generator again: no bays, a colder ramp), drawn facing right.
static func layout_enemy() -> Dictionary:
	return {
		"name": "enemy",
		"enemy": true,
		"size": Vector2i(176, 74),
		"ground": 70.0,
		"parts": [
			{"poly": P([52, 38, 56, 25, 64, 20, 108, 20, 117, 26, 118, 38]), "seams_x": [84], "seed": 41, "tone": 0.03},
			{"poly": P([10, 46, 22, 36, 140, 36, 160, 46, 158, 54, 146, 60, 26, 60, 12, 54]), "seams_x": [60, 100], "seams_y": [46], "seed": 42},
			{"poly": P([114, 24, 123, 24, 126, 27, 126, 34, 123, 37, 114, 37]), "cast": true, "seed": 43, "tone": 0.06},
		],
		"bays": [],
		"openings": [],
		"details": [
			{"kind": "vision", "at": Vector2i(132, 41), "w": 4},
			{"kind": "hatch", "rect": Rect2i(70, 40, 12, 10)},
			{"kind": "slit", "at": Vector2i(92, 28), "w": 8},
			{"kind": "hatch_top", "at": Vector2i(78, 20), "w": 9},
			{"kind": "stack", "x": 30, "y0": 28, "y1": 37},
			{"kind": "links", "a": Vector2(142, 39), "b": Vector2(154, 45), "n": 2},
		],
		"gun": {"trunnion": Vector2(120.5, 30.5), "len": 46.0},
		"gear": {
			"T": 3.0, "up": 3.0, "droop": 2.0,
			"idler": {"c": Vector2(17, 54), "r": 6.0},
			"sprocket": {"c": Vector2(151, 54), "r": 7.0},
			"rollers": [],
			"wheels": _wheels(6, 32.0, 21.0, 62.0, 5.0),
		},
	}


static func layouts() -> Array:
	return [layout_r3()]


# --- Build and compose ---------------------------------------------------------------------------


static func build(L: Dictionary) -> Dictionary:
	var B := Hull.build(L)
	B["L"] = L
	return B


## The road wheels' rest centres (local px).
static func rest_wheels(L: Dictionary) -> Array[Vector2]:
	var o: Array[Vector2] = []
	for w: Dictionary in L["gear"]["wheels"]:
		o.append(Vector2(float(w["x"]), float(w["y"])))
	return o


## One frame in the hull's own frame (local px).
static func frame(B: Dictionary, st: Dictionary) -> Image:
	var L: Dictionary = B["L"]
	var sz: Vector2i = L["size"]
	var img := Px.blank(sz.x, sz.y)
	var enemy := bool(L.get("enemy", false))
	var wc: Array[Vector2] = rest_wheels(L)
	if st.has("wc"):
		wc.assign(st["wc"])
	var travel := float(st.get("travel", 0.0))
	var with_gear := bool(st.get("gear", true))
	if with_gear:
		Gear.draw_back(img, L["gear"], Transform2D.IDENTITY, wc, travel, enemy)
	img.blend_rect(B["img"], Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	interior(img, B, st)
	if with_gear:
		Gear.draw_front(img, L["gear"], Transform2D.IDENTITY, wc, travel, enemy)
	if bool(st.get("front", true)):
		img.blend_rect(B["front"], Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	if bool(st.get("guns", true)):
		guns(img, L, Transform2D.IDENTITY, st)
	return img


## Everything inside the cutaway openings: machines, crew, the loader, the breech.
static func interior(img: Image, B: Dictionary, st: Dictionary) -> void:
	var L: Dictionary = B["L"]
	var t := float(st.get("t", 0.0))
	var rpm: Dictionary = st.get("rpm", {})
	var crew: Dictionary = st.get("crew", {})
	Mach.set_clip(B["open"], int(B["w"]), int(B["h"]))
	for b: Dictionary in L["bays"]:
		var r: Rect2i = b["rect"]
		var id := str(b["id"])
		var slot := int(crew.get(id, -1))
		var c := float(rpm.get(id, 85.0)) if slot >= 0 else 0.0
		match str(b["kind"]):
			"diesel":
				Mach.diesel(img, r, t, c, slot)
			"diesel_long":
				Mach.diesel_long(img, r, t, c, slot)
			"dynamo_round":
				Mach.dynamo_round(img, r, t, c, slot)
			"arc_v":
				Mach.arc_v(img, r, t, c, slot)
			"arcgen":
				Mach.arcgen(img, r, t, c, slot)
			"dynamo":
				Mach.dynamo(img, r, t, c, slot, absf(float(st.get("elev_rate", 0.0))) > 0.01)
			"beltfeed":
				Mach.beltfeed(img, r, t, c, slot, L["sec"]["feed"])
			"steam":
				loader(img, B, st, r, t, c, slot)
	if L.has("gun") and not L.get("enemy", false):
		breech(img, B, st)


# --- The main gun, the secondaries ------------------------------------------------------------------


static func gun_dir(elev_deg: float, rot: float) -> float:
	return -deg_to_rad(elev_deg) + rot


## The barrels outside the hull (main gun, twin secondaries with the ball mount), muzzle flashes.
## `xf` maps local px to the target image (the hull's pose in method b; identity otherwise).
static func guns(img: Image, L: Dictionary, xf: Transform2D, st: Dictionary) -> void:
	var enemy := bool(L.get("enemy", false))
	var rot := xf.get_rotation()
	var g: Dictionary = L["gun"]
	var ang := gun_dir(float(st.get("elev", 0.0)), rot)
	var dir := Vector2(cos(ang), sin(ang))
	var fire_t := float(st.get("fire_t", 99.0))
	var recoil := 0.0
	if fire_t >= 0.0 and fire_t < 0.6:
		recoil = 4.0 * (1.0 - fire_t / 0.6) if fire_t > 0.05 else 4.0
	var o: Vector2 = xf * (g["trunnion"] as Vector2) - dir * recoil
	var ln := float(g["len"])
	var c: Array = BARREL_EN if enemy else BARREL
	var segs := [
		[7.0, 16.0, 3.0, 2.6, c[0], c[1], c[2]],
		[16.0, ln * 0.55, 1.6, 1.5, c[0], c[1], c[2]],
		[ln * 0.55, ln * 0.66, 2.3, 2.3, c[0], c[1], c[2]],
		[ln * 0.66, ln - 6.0, 1.5, 1.5, c[0], c[1], c[2]],
		[ln - 6.0, ln, 2.4, 2.4, c[0], c[1], c[2]],
		[ln - 3.6, ln - 2.6, 2.4, 2.4, OUT, OUT, OUT],
		[15.4, 16.4, 2.9, 2.9, c[0].lightened(0.2), c[0], c[2]],
	]
	if enemy:
		segs = [
			[5.0, 12.0, 2.2, 2.0, c[0], c[1], c[2]],
			[12.0, ln - 4.0, 1.2, 1.2, c[0], c[1], c[2]],
			[ln - 4.0, ln, 1.8, 1.8, c[0], c[1], c[2]],
		]
	Px.profile(img, o, ang, segs)
	if fire_t >= 0.0 and fire_t < 0.12:
		_flash(img, o + dir * (ln + 2.0), ang, 1.0 if fire_t < 0.06 else 0.6)
	if L.has("sec"):
		var s: Dictionary = L["sec"]
		var sa := gun_dir(float(st.get("sec_elev", 0.0)), rot)
		var sd := Vector2(cos(sa), sin(sa))
		var sn := Vector2(-sd.y, sd.x)
		var piv: Vector2 = xf * (s["pivot"] as Vector2)
		var sl := float(s["len"])
		for k in 2:
			var off := -1.6 if k == 0 else 1.6
			Px.profile(img, piv + sn * off, sa, [
				[2.0, 10.0, 1.1, 1.1, Color("#5a5a52"), Color("#3a3a34"), Color("#1c1c18")],
				[10.0, sl, 0.55, 0.55, Color("#8a877e"), Color("#5a5850"), Color("#2a2a26")],
				[sl - 1.5, sl, 0.9, 0.9, Color("#3a3a34"), Color("#3a3a34"), Color("#1c1c18")],
			])
		if bool(s.get("boxed", false)):
			Px.profile(img, piv, sa, [[-1.0, 4.0, 4.2, 3.6, Color("#3a2c1e"), Color("#22180f"), Color("#100a06")]])
			Px.put(img, floori(piv.x + sd.x * 2.0 - sn.x * 3.0), floori(piv.y + sd.y * 2.0 - sn.y * 3.0), Color("#6e5638"))
		# ball mount over the roots
		for y in (range(floori(piv.y) - 5, floori(piv.y) + 6) if not bool(s.get("boxed", false)) else []):
			for x in range(floori(piv.x) - 5, floori(piv.x) + 6):
				var d := Vector2(x + 0.5, y + 0.5) - piv
				var rho := d.length()
				if rho < 3.6:
					Px.put(img, x, y, Color("#6e5536") if d.y < -1.0 else Color("#4a3826"))
				elif rho < 4.5:
					Px.put(img, x, y, OUT)
		Px.put(img, floori(piv.x) - 1, floori(piv.y) - 2, Color("#b2905e"))
		var revs := float(st.get("sec_revs", -1.0))
		if revs >= 0.0:
			var f := fposmod(revs * 2.0, 1.0)
			if f < 0.3:
				var kk := int(floor(revs * 2.0)) % 2
				var off2 := -1.6 if kk == 0 else 1.6
				_flash(img, piv + sn * off2 + sd * (sl + 1.5), sa, 0.6)


static func _flash(img: Image, at: Vector2, ang: float, size: float) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var core := Color("#fff6d8")
	var mid := Color("#ffd27a")
	var edge := Color("#ff8a3a")
	var ln := 6.0 * size
	var k := 0.0
	while k <= ln:
		var w := (1.0 - k / ln) * 2.5 * size + 0.5
		var j := -w
		while j <= w:
			var q := at + d * k + n * j
			var col := core if absf(j) < w * 0.35 and k < ln * 0.6 else (mid if absf(j) < w * 0.75 else edge)
			Px.put(img, floori(q.x), floori(q.y), col)
			j += 0.5
		k += 0.5
	Px.put(img, floori(at.x + n.x * 4.0 * size), floori(at.y + n.y * 4.0 * size), mid)
	Px.put(img, floori(at.x - n.x * 4.0 * size), floori(at.y - n.y * 4.0 * size), mid)


# --- The loader and the breech ---------------------------------------------------------------------


## Where the loader cycle is at time `lt` (s): {step, k (0..1 within it)}.
static func load_step(lt: float) -> Dictionary:
	for s: Array in STEPS:
		if lt >= float(s[1]) and lt < float(s[2]):
			return {"step": str(s[0]), "k": (lt - float(s[1])) / (float(s[2]) - float(s[1]))}
	return {"step": "IDLE", "k": 0.0}


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


## The bore point at local x (the tray's top position, behind the breech).
static func bore_at_x(L: Dictionary, x: float, elev: float) -> Dictionary:
	var g: Dictionary = L["gun"]
	var ang := gun_dir(elev, 0.0)
	var d := Vector2(cos(ang), sin(ang))
	var tr: Vector2 = g["trunnion"]
	var u := (x - tr.x) / d.x
	return {"p": tr + d * u, "u": u, "ang": ang, "d": d}


static func shell(img: Image, c: Vector2, ang: float, clip: PackedByteArray) -> void:
	Px.profile(img, c, ang, [
		[-7.0, -6.0, 1.7, 1.7, Mach.BR1, Mach.BR0, Mach.BR0],
		[-6.0, 1.0, 1.5, 1.5, Mach.BR2, Mach.BR1, Mach.BR0],
		[1.0, 2.0, 1.6, 1.6, Mach.CU2, Mach.CU1, Mach.CU0],
		[2.0, 7.0, 1.5, 0.5, Mach.ST4, Mach.ST2, Mach.ST1],
	], OUT, clip)


## The steam loader bay: crewman at the blower crank, the boiler and firebox, the stowage rack, the
## hoist up through the shaft into the turret, the tray, the rammer, the ready rack beside the breech.
static func loader(img: Image, B: Dictionary, st: Dictionary, r: Rect2i, t: float, rpm: float, slot: int) -> void:
	var L: Dictionary = B["L"]
	var lo: Dictionary = L["loader"]
	var clip: PackedByteArray = B["open"]
	var fy := r.end.y - 3
	var ang := t * rpm / 60.0 * TAU
	var cc := Mach.seat(img, r.position.x + 3, fy, ang, slot)
	# boiler: riveted copper drum with a dome, bands, a gauge, a safety valve and a whistle
	var bx := int(lo["boiler_x"])
	var top := maxi(fy - 32, r.position.y + 9)
	for y in range(top, fy):
		for x in range(bx, bx + 12):
			var dx := float(x - bx) - 5.5
			if y < top + 3 and absf(dx) > 3.0 + float(y - top) * 1.2:
				continue
			var col := Mach.CU2 if dx < -3.5 else (Mach.CU1 if dx < 1.5 else Mach.CU0)
			if bool(lo.get("green", false)):
				col = Color("#5a7a62") if dx < -3.5 else (Color("#2e4a3a") if dx < 1.5 else Color("#1a2c22"))
			if absf(dx) > 5.0 or (y == top and absf(dx) > 2.5):
				col = OUT
			elif (y - top) % 8 == 4:
				col = Mach.BR2 if dx < 0.0 else Mach.BR1
			elif (y - top) % 8 == 5 and absf(dx) < 5.0:
				col = Mach.BR0
			elif (y - top) % 4 == 2 and absf(dx - 3.5) < 0.6:
				col = Color("#e0b080")
			Mach.p(img, x, y, col)
	var fl := Px.h2(floori(t * 12.0), 5, 2)
	var on := slot >= 0 and rpm > 1.0
	var fire := Rect2i(bx + 2, fy - 8, 8, 6)
	Mach.box(img, fire, Mach.ST1, Mach.ST2, Mach.ST0)
	for y in range(fire.position.y + 2, fire.end.y - 1):
		for x in range(fire.position.x + 2, fire.end.x - 2):
			var hv := Px.h2(x, y + floori(t * 10.0), 3)
			var fc := Color("#3a1408")
			if on:
				fc = Mach.FIRE2 if hv > 0.7 else (Mach.FIRE1 if hv > 0.3 else Mach.FIRE0)
			Mach.p(img, x, y, fc)
	if on:
		Mach.glow(img, Vector2(bx + 6.0, fy - 4.0), 13.0, Color("#ff7a2a"), 0.35 + 0.15 * fl)
	Mach.dial(img, Vector2(bx + 6.5, top + 8.5), 0.7 if on else 0.1)
	Mach.pr(img, Rect2i(bx + 4, top - 3, 3, 3), Mach.BR1)
	Mach.p(img, bx + 5, top - 4, Mach.BR2)
	Mach.pr(img, Rect2i(bx + 8, top - 1, 2, 2), Mach.ST3)
	if on and fposmod(t, 2.3) < 0.3:
		Mach.p(img, bx + 5, top - 6, Color("#d8d8d0"))
		Mach.p(img, bx + 6, top - 7, Color("#a8a8a0"))
	# blower wheel at the firebox, chained to the pedals
	var bw := Vector2(bx + 6.0, fy - 14.0)
	Mach.chain(img, cc, bw, 2.5, 2.5, t * rpm / 60.0 * 9.0)
	Mach.wheel(img, bw, 3.5, ang * 2.0, Mach.ST2, 4)
	# steam pipe to the hoist winch at the ceiling
	var hx := int(lo["hoist_x"])
	Mach.pr(img, Rect2i(bx + 9, r.position.y + 8, 2, top - r.position.y - 7), Mach.CU1)
	Mach.pr(img, Rect2i(bx + 9, r.position.y + 8, 1, top - r.position.y - 7), Mach.CU2)
	Mach.pr(img, Rect2i(bx + 9, r.position.y + 8, hx - bx - 6, 2), Mach.CU1)
	Mach.pr(img, Rect2i(bx + 9, r.position.y + 8, hx - bx - 6, 1), Mach.CU2)
	# stowage rack: four rows, the top row's shell is the one this cycle moves
	var rx := int(lo["rack_x"])
	var rows := 4
	var row_y: Array[float] = []
	for k in rows:
		row_y.append(float(fy) - 3.5 - k * 5.0)
	Mach.pr(img, Rect2i(rx, int(row_y[rows - 1]) - 3, 1, fy - int(row_y[rows - 1]) + 3), Mach.ST1)
	Mach.pr(img, Rect2i(rx + 16, int(row_y[rows - 1]) - 3, 1, fy - int(row_y[rows - 1]) + 3), Mach.ST1)
	for k in rows:
		Mach.pr(img, Rect2i(rx, int(row_y[k]) + 2, 17, 1), Mach.ST2)
		Mach.p(img, rx + 3, int(row_y[k]) + 2, Mach.BR1)
		Mach.p(img, rx + 13, int(row_y[k]) + 2, Mach.BR1)
	Mach.pr(img, Rect2i(rx - 1, int(row_y[rows - 1]) - 4, 19, 1), Mach.ST3)
	var lt := float(st.get("load_t", -1.0))
	var ls := load_step(lt) if lt >= 0.0 else {"step": "IDLE", "k": 0.0}
	var step: String = ls["step"]
	var k := float(ls["k"])
	for kk in rows - 1:
		shell(img, Vector2(rx + 8.5, row_y[kk]), 0.0, clip)
	# the hoist
	var elev := float(st.get("elev", 0.0))
	var hc := float(hx) + 4.5
	var bt := bore_at_x(L, hc + 2.0, elev)
	var top_y: float = (bt["p"] as Vector2).y
	var low_y: float = row_y[rows - 1]
	var tray_y := low_y
	var shell_at := Vector2(rx + 8.5, row_y[rows - 1])
	var shell_ang := 0.0
	var show_shell := true
	var rammer := 0.0
	match step:
		"IDLE":
			show_shell = lt < 0.0
		"RACK":
			shell_at = Vector2(lerpf(rx + 8.5, hc + 2.0, _ease(k)), low_y)
		"HOIST":
			tray_y = lerpf(low_y, top_y, _ease(k))
			shell_at = Vector2(hc + 2.0, tray_y)
			shell_ang = float(bt["ang"]) * clampf((k - 0.8) / 0.2, 0.0, 1.0)
		"BREECH OPEN":
			tray_y = top_y
			shell_at = bt["p"]
			shell_ang = bt["ang"]
		"RAM":
			tray_y = top_y
			var g: Dictionary = L["gun"]
			var d: Vector2 = bt["d"]
			var u_ch := -12.0 - float(g.get("breech_off", 0.0))
			var u_now := lerpf(float(bt["u"]), u_ch, _ease(k))
			shell_at = (g["trunnion"] as Vector2) + d * u_now
			shell_ang = bt["ang"]
			rammer = u_now - float(bt["u"])
		"BREECH SHUT":
			tray_y = top_y
			show_shell = false
			rammer = lerpf(-12.0 - float((L["gun"] as Dictionary).get("breech_off", 0.0)) - float(bt["u"]), 0.0, _ease(k))
		"TRAY DOWN":
			tray_y = lerpf(top_y, low_y, _ease(k))
			show_shell = false
	# rails and chain (the chain moves with the tray)
	var rail_top := int(top_y) - 6
	Mach.pr(img, Rect2i(hx, rail_top, 1, fy - rail_top), Mach.ST2)
	Mach.pr(img, Rect2i(hx + 9, rail_top, 1, fy - rail_top), Mach.ST2)
	for y in range(rail_top, fy):
		Mach.p(img, hx + 11, y, Mach.BR1 if posmod(y + floori(tray_y), 3) == 0 else Mach.ST0)
	# winch drum at the top
	Mach.wheel(img, Vector2(hx + 11.5, rail_top - 1.5), 2.5, tray_y * 0.6, Mach.BR1, 3)
	# the tray: a cradle that rides the rails
	var ty := floori(tray_y) + 2
	Mach.pr(img, Rect2i(hx - 1, ty, 12, 1), Mach.BR1)
	Mach.p(img, hx - 1, ty - 1, Mach.BR0)
	Mach.p(img, hx + 10, ty - 1, Mach.BR0)
	Mach.pr(img, Rect2i(hx, ty + 1, 10, 1), OUT)
	if show_shell and step != "IDLE":
		shell(img, shell_at, shell_ang, clip)
	elif step == "IDLE" and lt < 0.0:
		shell(img, Vector2(rx + 8.5, row_y[rows - 1]), 0.0, clip)
	# the rammer behind the tray, along the bore
	var bd: Vector2 = bt["d"]
	var hous: Vector2 = (bt["p"] as Vector2) - bd * 14.0
	Px.profile(img, hous, float(bt["ang"]), [[-3.0, 2.0, 2.2, 2.2, Mach.ST3, Mach.ST2, Mach.ST1]], OUT, clip)
	if rammer > 0.5:
		Px.profile(img, hous, float(bt["ang"]), [[2.0, 7.0 + rammer - 0.5, 0.6, 0.6, Mach.ST4, Mach.ST3, Mach.ST2]], OUT, clip)
	# the ready rack: up to three shells standing beside the breech window's rear wall
	var win: Rect2i = lo["window"]
	var n_ready := int(st.get("ready", 2))
	for q in 3:
		var sx := win.position.x + 6 + q * 4
		var sy := win.end.y - 11.5
		Mach.pr(img, Rect2i(sx - 2, int(sy) + 8, 4, 1), Mach.ST1)
		if q < n_ready:
			shell(img, Vector2(sx, sy), -PI * 0.5, clip)
		else:
			Mach.p(img, sx, int(sy) + 7, Mach.ST0)


## The main gun's breech inside the turret window (the gun's rear, clipped to the openings): the
## ring, the sliding block (open while loading), the cradle, a ready lamp when loaded.
static func breech(img: Image, B: Dictionary, st: Dictionary) -> void:
	var L: Dictionary = B["L"]
	var clip: PackedByteArray = B["open"]
	var g: Dictionary = L["gun"]
	var ang := gun_dir(float(st.get("elev", 0.0)), 0.0)
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var fire_t := float(st.get("fire_t", 99.0))
	var recoil := 0.0
	if fire_t >= 0.0 and fire_t < 0.6:
		recoil = 4.0 * (1.0 - fire_t / 0.6) if fire_t > 0.05 else 4.0
	var o: Vector2 = (g["trunnion"] as Vector2) - d * (recoil + float(g.get("breech_off", 0.0)))
	var lt := float(st.get("load_t", -1.0))
	var ls := load_step(lt) if lt >= 0.0 else {"step": "IDLE", "k": 0.0}
	var opened := 0.0
	match str(ls["step"]):
		"BREECH OPEN":
			opened = _ease(float(ls["k"]))
		"RAM":
			opened = 1.0
		"BREECH SHUT":
			opened = 1.0 - _ease(float(ls["k"]))
	# cradle rails under the breech
	Px.profile(img, o + n * 4.5, ang, [[-34.0, -4.0, 0.6, 0.6, Mach.ST2, Mach.ST1, Mach.ST0]], OUT, clip)
	# barrel inside the turret, then the ring
	Px.profile(img, o, ang, [
		[-4.0, 8.0, 2.4, 2.4, BARREL[0], BARREL[1], BARREL[2]],
		[-16.0, -3.0, 4.0, 4.0, Mach.ST3, Mach.ST2, Mach.ST1],
		[-14.0, -13.0, 4.0, 4.0, Mach.BR2, Mach.BR1, Mach.BR0],
	], OUT, clip)
	# the bore, visible while the block is down
	if opened > 0.2:
		Px.profile(img, o, ang, [[-16.0, -15.0, 1.5, 1.5, Color("#050302"), Color("#050302"), Color("#050302")]], Color(0, 0, 0, 0), clip)
	# the sliding block
	var blk := o + n * (opened * 6.0)
	Px.profile(img, blk, ang, [[-18.0, -15.5, 3.8, 3.8, Mach.ST4, Mach.ST3, Mach.ST1]], OUT, clip)
	# ready lamp: lit when a round is chambered
	var loaded := lt < 0.0 or lt >= 5.0
	var lamp := o - d * 9.0 - n * 5.5
	Mach.p(img, floori(lamp.x), floori(lamp.y), Color("#ffd27a") if loaded else Color("#3a2414"))


# --- World rendering (terrain tilt) ---------------------------------------------------------------


## The hull's pose over `ground` (Callable: world x -> world y) with its local ground-contact point
## (centre x, L.ground) at world x `wx`: a least-squares line through the ground under the wheels.
static func pose(L: Dictionary, wx: float, ground: Callable, flip := false) -> Dictionary:
	var sz: Vector2i = L["size"]
	var cx := sz.x * 0.5
	var xs: Array[float] = []
	var ys: Array[float] = []
	for w: Dictionary in L["gear"]["wheels"]:
		var lx := float(w["x"]) - cx
		if flip:
			lx = -lx
		xs.append(wx + lx)
		ys.append(float(ground.call(wx + lx)))
	var n := float(xs.size())
	var mx := 0.0
	var my := 0.0
	for i in xs.size():
		mx += xs[i]
		my += ys[i]
	mx /= n
	my /= n
	var sxx := 0.0
	var sxy := 0.0
	for i in xs.size():
		sxx += (xs[i] - mx) * (xs[i] - mx)
		sxy += (xs[i] - mx) * (ys[i] - my)
	var slope := sxy / maxf(sxx, 0.001)
	var rot := atan(slope)
	var gy := my + slope * (wx - mx)
	# local (cx, ground) -> world (wx, gy), rotated by rot (flipped: mirrored in x first)
	var lp := Vector2(cx, float(L["ground"]))
	var basis := Transform2D(rot, Vector2.ZERO)
	if flip:
		basis = basis * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO)
	var xf := Transform2D(basis.x, basis.y, Vector2(wx, gy) - basis.basis_xform(lp))
	return {"xf": xf, "rot": rot, "deg": rad_to_deg(rot)}
