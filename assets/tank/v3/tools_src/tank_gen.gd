extends RefCounted
## The landship's generator: the layout every bake reads (the rooms, the cuts, the running gear, the
## guns' anchors), the base image with its open-room mask, the roof's fittings and the blast's puffs.
## Coordinates: base px (the reference's 4-rider cut of the tank x 0.9).

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const BASE := "res://build/v3mock/r6/base.png"
const OUT := Color("#050302")
const BARREL: Array = [Color("#6a5a48"), Color("#3a3026"), Color("#17110c")]
const F_WHITE := Color("#fff8e0")
const F_YEL := Color("#ffd848")
const F_ORA := Color("#ff8a20")
const F_RED := Color("#c83a14")
const F_DRED := Color("#5a1808")
const SMOKE: Array = [Color("#2a2622"), Color("#3e3832"), Color("#5a5248"), Color("#7a7062")]
const DUST: Array = [Color("#2e2618"), Color("#463a28"), Color("#6a5a40")]


static func _hull_layout() -> Dictionary:
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


static func layout() -> Dictionary:
	var L := _hull_layout()
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
	_lamp(img, Vector2(105, 91), PI - deg_to_rad(13.0), bool(st.get("rear_on", true)))


## A searchlight drum aimed along `a` (radians, y down) from its centre `c`, the lens at the front.
static func _lamp(img: Image, c: Vector2, a: float, lit: bool) -> void:
	Px.profile(img, c, a, [
		[-5.0, 4.0, 3.5, 3.5, Color("#4e3c2a"), Color("#2e2218"), Color("#140e0a")],
		[4.0, 6.0, 4.0, 4.0, Color("#8a6a3a"), Color("#6a5236"), Color("#3a2c1e")],
		[6.0, 7.0, 3.0, 3.0, Color("#fff6d8") if lit else Color("#3a4a4c"), Color("#fff6d8") if lit else Color("#2a3a3c"), Color("#ffd98a") if lit else Color("#1a2a2c")],
	])


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
