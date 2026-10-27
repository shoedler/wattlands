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


## A: long, five bays in a row under one roof, the turret over the gun and loader bays.
static func layout_a() -> Dictionary:
	var bays := [
		_bay("drive", "diesel", Rect2i(62, 88, 50, 51), 1),
		_bay("lights", "arcgen", Rect2i(116, 88, 48, 51), 2),
		_bay("gun", "dynamo", Rect2i(168, 88, 48, 51), 3),
		_bay("loader", "steam", Rect2i(220, 88, 66, 51), 4),
		_bay("sec", "beltfeed", Rect2i(290, 88, 84, 51), 5),
	]
	var openings: Array = [
		_open_bay(bays[0], {"shelf": [64, 80], "valve": 82}),
		_open_bay(bays[1], {"shelf": [118, 134]}),
		_open_bay(bays[2], {"shelf": [170, 186], "valve": 188}),
		_open_bay(bays[3], {"shelf": [222, 238]}),
		_open_bay(bays[4], {"shelf": [328, 352], "gauges": 312}),
		{"rect": Rect2i(254, 47, 72, 28), "group": 4, "inset": 3, "lamp": Vector2(288, 52), "dress": {"pipes": false}},
		{"rect": Rect2i(269, 71, 17, 21), "group": 4, "inset": 2, "has_lamp": false, "floor": false, "beam": false, "dim": 0.15},
	]
	var details: Array = []
	for b: Dictionary in bays:
		var r: Rect2i = b["rect"]
		details.append({"kind": "vision", "at": Vector2i(r.position.x + r.size.x / 2 - 2, 79), "w": 5})
	details.append_array([
		{"kind": "shovel", "at": Vector2i(94, 82)},
		{"kind": "pick", "at": Vector2i(148, 82)},
		{"kind": "bar", "at": Vector2i(199, 82), "w": 40},
		{"kind": "cable", "a": Vector2i(264, 82), "b": Vector2i(324, 82)},
		{"kind": "louvre", "rect": Rect2i(36, 90, 20, 13)},
		{"kind": "lamp_red", "at": Vector2i(28, 101)},
		{"kind": "lamp_green", "at": Vector2i(69, 61)},
		{"kind": "lamp_red", "at": Vector2i(400, 108)},
		{"kind": "stack", "x": 76, "y0": 50, "y1": 64},
		{"kind": "stack", "x": 89, "y0": 53, "y1": 64},
		{"kind": "can", "at": Vector2i(99, 57)},
		{"kind": "can", "at": Vector2i(106, 57)},
		{"kind": "coil", "at": Vector2i(121, 61)},
		{"kind": "hatch_top", "at": Vector2i(138, 74), "w": 10},
		{"kind": "periscope", "at": Vector2i(156, 74)},
		{"kind": "vent", "at": Vector2i(176, 74)},
		{"kind": "vent", "at": Vector2i(186, 74)},
		{"kind": "periscope", "at": Vector2i(335, 74)},
		{"kind": "links", "a": Vector2(347, 82), "b": Vector2(372, 96), "n": 3},
		{"kind": "headlight", "at": Vector2i(405, 117)},
	])
	details.append_array(_turret_details({
		"hatch": Vector2i(286, 44), "periscope": Vector2i(224, 37), "searchlight": Vector2i(248, 37),
		"antenna": Vector2i(208, 48), "rail_a": Vector2i(210, 57), "rail_b": Vector2i(248, 57),
		"vision": Vector2i(226, 64), "box": Rect2i(191, 55, 10, 13), "slit": Vector2i(218, 40),
	}))
	return {
		"name": "A",
		"title": "A  LONG: FIVE BAYS IN A ROW",
		"size": Vector2i(440, 176),
		"ground": 170.0,
		"parts": [
			{"poly": P([200, 76, 203, 52, 212, 44, 318, 44, 331, 51, 335, 62, 333, 76]), "seams_x": [236, 254], "seams_y": [60], "tone": 0.03, "seed": 11},
			{"poly": P([66, 76, 70, 64, 126, 64, 130, 76]), "seams_x": [98], "tone": -0.02, "seed": 12},
			{"poly": P([26, 96, 36, 84, 62, 74, 340, 74, 404, 110, 411, 118, 409, 127, 394, 144, 60, 144, 46, 140, 30, 124, 24, 108]),
			 "seams_x": [114, 166, 218, 288], "seams_y": [86, 139], "seed": 13},
			{"poly": P([323, 48, 337, 48, 342, 53, 342, 62, 337, 67, 323, 67]), "cast": true, "tone": 0.06, "seed": 14},
			{"poly": P([214, 44, 216, 37, 236, 37, 238, 44]), "cast": true, "tone": 0.05, "seed": 15},
			{"poly": P([66, 139, 128, 139, 128, 146, 66, 146]), "front": true, "seams_x": [97], "split": false, "tone": 0.04, "seed": 16},
			{"poly": P([146, 139, 214, 139, 214, 146, 146, 146]), "front": true, "seams_x": [180], "split": false, "tone": 0.04, "seed": 17},
			{"poly": P([232, 139, 300, 139, 300, 146, 232, 146]), "front": true, "seams_x": [266], "split": false, "tone": 0.04, "seed": 18},
		],
		"bays": bays,
		"openings": openings,
		"details": details,
		"gun": {"trunnion": Vector2(333, 57.5), "len": 80.0},
		"sec": {"pivot": Vector2(383.5, 100.5), "len": 22.0, "feed": Vector2(364, 101)},
		"loader": {"bay": 3, "boiler_x": 241, "rack_x": 254, "hoist_x": 272, "window": Rect2i(254, 47, 72, 28)},
		"gear": {
			"T": 5.0, "up": 4.0, "droop": 2.0, "track_front": true,
			"idler": {"c": Vector2(38, 126), "r": 11.0},
			"sprocket": {"c": Vector2(396, 132), "r": 13.0},
			"rollers": [
				{"c": Vector2(77, 148.5), "r": 2.5}, {"c": Vector2(152, 148.5), "r": 2.5}, {"c": Vector2(228, 148.5), "r": 2.5},
				{"c": Vector2(303, 148.5), "r": 2.5}, {"c": Vector2(354, 148.5), "r": 2.5},
			],
			"wheels": _wheels(13, 64.0, 25.2, 158.0, 7.0),
		},
	}


## B: compact two-deck: lights and loader above, drive, gun and the belt feed below.
static func layout_b() -> Dictionary:
	var bays := [
		_bay("lights", "arcgen", Rect2i(56, 82, 64, 44), 2),
		_bay("loader", "steam", Rect2i(124, 82, 82, 44), 4),
		_bay("drive", "diesel", Rect2i(50, 131, 74, 44), 1),
		_bay("gun", "dynamo", Rect2i(128, 131, 86, 44), 3),
		_bay("sec", "beltfeed", Rect2i(218, 131, 96, 44), 5),
	]
	var openings: Array = [
		_open_bay(bays[0], {"shelf": [58, 74], "door": "R"}),
		_open_bay(bays[1], {"shelf": [126, 142]}),
		_open_bay(bays[2], {"shelf": [52, 68], "door": "R"}),
		_open_bay(bays[3], {"shelf": [130, 146], "door": "R", "valve": 192}),
		_open_bay(bays[4], {"shelf": [256, 280], "gauges": 240}),
		{"rect": Rect2i(176, 48, 66, 29), "group": 4, "inset": 3, "lamp": Vector2(206, 52), "dress": {"pipes": false}},
		{"rect": Rect2i(189, 73, 17, 12), "group": 4, "inset": 2, "has_lamp": false, "floor": false, "beam": false, "dim": 0.15},
	]
	var details: Array = [
		{"kind": "vision", "at": Vector2i(226, 88), "w": 5},
		{"kind": "vision", "at": Vector2i(256, 102), "w": 5},
		{"kind": "hatch", "rect": Rect2i(222, 100, 16, 14)},
		{"kind": "links", "a": Vector2(262, 86), "b": Vector2(296, 111), "n": 4},
		{"kind": "shovel", "at": Vector2i(214, 120)},
		{"kind": "louvre", "rect": Rect2i(34, 118, 14, 12)},
		{"kind": "stack", "x": 68, "y0": 54, "y1": 68},
		{"kind": "stack", "x": 82, "y0": 57, "y1": 68},
		{"kind": "can", "at": Vector2i(90, 61)},
		{"kind": "coil", "at": Vector2i(108, 72)},
		{"kind": "headlight", "at": Vector2i(318, 129)},
		{"kind": "lamp_red", "at": Vector2i(28, 126)},
		{"kind": "lamp_green", "at": Vector2i(57, 65)},
		{"kind": "lamp_red", "at": Vector2i(312, 118)},
		{"kind": "cable", "a": Vector2i(60, 128), "b": Vector2i(206, 128)},
		{"kind": "periscope", "at": Vector2i(112, 76)},
		{"kind": "vent", "at": Vector2i(250, 76)},
	]
	details.append_array(_turret_details({
		"hatch": Vector2i(200, 44), "periscope": Vector2i(146, 37), "searchlight": Vector2i(170, 37),
		"antenna": Vector2i(130, 56), "rail_a": Vector2i(132, 54), "rail_b": Vector2i(172, 54),
		"vision": Vector2i(150, 62), "box": Rect2i(114, 54, 10, 14), "slit": Vector2i(142, 40),
	}))
	return {
		"name": "B",
		"title": "B  COMPACT TWO-DECK",
		"size": Vector2i(360, 212),
		"ground": 206.0,
		"parts": [
			{"poly": P([124, 78, 128, 52, 138, 44, 226, 44, 240, 51, 244, 62, 242, 78]), "seams_x": [160, 176], "seams_y": [60], "tone": 0.03, "seed": 21},
			{"poly": P([54, 78, 58, 68, 102, 68, 106, 78]), "seams_x": [80], "tone": -0.02, "seed": 22},
			{"poly": P([26, 116, 40, 92, 58, 76, 256, 76, 318, 122, 325, 132, 322, 146, 312, 178, 64, 180, 48, 176, 30, 152, 24, 130]),
			 "seams_x": [122, 210], "seams_y": [128, 176], "seed": 23},
			{"poly": P([236, 51, 250, 51, 255, 56, 255, 65, 250, 70, 236, 70]), "cast": true, "tone": 0.06, "seed": 24},
			{"poly": P([138, 44, 140, 37, 158, 37, 160, 44]), "cast": true, "tone": 0.05, "seed": 25},
			{"poly": P([66, 176, 130, 176, 130, 183, 66, 183]), "front": true, "seams_x": [98], "split": false, "tone": 0.04, "seed": 26},
			{"poly": P([148, 176, 214, 176, 214, 183, 148, 183]), "front": true, "seams_x": [181], "split": false, "tone": 0.04, "seed": 27},
			{"poly": P([232, 176, 296, 176, 296, 183, 232, 183]), "front": true, "seams_x": [264], "split": false, "tone": 0.04, "seed": 28},
		],
		"bays": bays,
		"openings": openings,
		"details": details,
		"gun": {"trunnion": Vector2(245.5, 60.5), "len": 76.0},
		"sec": {"pivot": Vector2(321.5, 140.5), "len": 20.0, "feed": Vector2(306, 142)},
		"loader": {"bay": 1, "boiler_x": 145, "rack_x": 160, "hoist_x": 190, "window": Rect2i(176, 48, 66, 29)},
		"gear": {
			"T": 5.0, "up": 4.0, "droop": 2.0, "track_front": true,
			"idler": {"c": Vector2(40, 158), "r": 11.0},
			"sprocket": {"c": Vector2(316, 162), "r": 13.0},
			"rollers": [
				{"c": Vector2(81, 184.5), "r": 2.5}, {"c": Vector2(133, 184.5), "r": 2.5}, {"c": Vector2(185, 184.5), "r": 2.5},
				{"c": Vector2(237, 184.5), "r": 2.5}, {"c": Vector2(289, 184.5), "r": 2.5},
			],
			"wheels": _wheels(9, 68.0, 26.0, 194.0, 7.0),
		},
	}


## C: a rhomboid landship: the track runs round the whole hull, the turret rides above the top run,
## the twin guns sit in a side sponson.
static func layout_c() -> Dictionary:
	var gear := {
		"T": 5.0, "up": 3.0, "droop": 2.0, "track_front": true,
		"idler": {"c": Vector2(38, 96), "r": 10.0},
		"sprocket": {"c": Vector2(376, 84), "r": 13.0},
		"rollers": [{"c": Vector2(110, 69), "r": 4.0}, {"c": Vector2(200, 65), "r": 4.0}, {"c": Vector2(290, 65), "r": 4.0}],
		"wheels": _wheels(10, 96.0, 24.0, 195.0, 6.0),
	}
	var rest: Array[Vector2] = []
	for w: Dictionary in gear["wheels"]:
		rest.append(Vector2(float(w["x"]), float(w["y"])))
	var b := Gear.belt(Gear._circles(gear, Transform2D.IDENTITY, rest), 1.0)
	var side := PackedVector2Array()
	var k := 0
	for e: Array in b["pts"]:
		if k % 5 == 0:
			var q: Vector2 = (e[0] as Vector2) - (e[1] as Vector2) * 1.0
			q.y = minf(q.y, 187.0)
			side.append(q)
		k += 1
	var bays := [
		_bay("loader", "steam", Rect2i(134, 78, 82, 46), 4),
		_bay("lights", "arcgen", Rect2i(222, 78, 84, 46), 2),
		_bay("drive", "diesel", Rect2i(98, 129, 66, 53), 1),
		_bay("gun", "dynamo", Rect2i(168, 129, 62, 53), 3),
		_bay("sec", "beltfeed", Rect2i(238, 127, 76, 50), 5),
	]
	var openings: Array = [
		_open_bay(bays[0], {"shelf": [136, 152]}),
		_open_bay(bays[1], {"shelf": [224, 240], "door": "R", "valve": 268}),
		_open_bay(bays[2], {"shelf": [100, 116]}),
		_open_bay(bays[3], {"shelf": [170, 186], "valve": 190}),
		_open_bay(bays[4], {"shelf": [276, 300], "gauges": 262}),
		{"rect": Rect2i(182, 40, 68, 20), "group": 4, "inset": 3, "lamp": Vector2(216, 44), "dress": {"pipes": false}},
		{"rect": Rect2i(197, 56, 17, 25), "group": 4, "inset": 2, "has_lamp": false, "floor": false, "beam": false, "dim": 0.15},
	]
	var details: Array = [
		{"kind": "louvre", "rect": Rect2i(56, 98, 22, 13)},
		{"kind": "hatch", "rect": Rect2i(90, 88, 14, 18)},
		{"kind": "vision", "at": Vector2i(114, 82), "w": 5},
		{"kind": "shovel", "at": Vector2i(58, 118)},
		{"kind": "pick", "at": Vector2i(88, 122)},
		{"kind": "vision", "at": Vector2i(320, 84), "w": 5},
		{"kind": "vision", "at": Vector2i(336, 96), "w": 5},
		{"kind": "hatch", "rect": Rect2i(316, 100, 13, 17)},
		{"kind": "rail", "a": Vector2i(262, 72), "b": Vector2i(330, 72)},
		{"kind": "bolt_row", "a": Vector2i(312, 124), "b": Vector2i(340, 124)},
		{"kind": "headlight", "at": Vector2i(388, 100)},
		{"kind": "lamp_red", "at": Vector2i(31, 110)},
		{"kind": "lamp_green", "at": Vector2i(47, 86)},
		{"kind": "lamp_red", "at": Vector2i(384, 108)},
		{"kind": "cable", "a": Vector2i(100, 126), "b": Vector2i(228, 126)},
		{"kind": "bolt_row", "a": Vector2i(234, 124), "b": Vector2i(300, 124)},
		{"kind": "can", "at": Vector2i(64, 132)},
		{"kind": "can", "at": Vector2i(71, 132)},
	]
	details.append_array(_turret_details({
		"hatch": Vector2i(222, 36), "periscope": Vector2i(160, 29), "searchlight": Vector2i(184, 30),
		"antenna": Vector2i(146, 50), "rail_a": Vector2i(150, 46), "rail_b": Vector2i(176, 46),
		"vision": Vector2i(158, 52), "box": Rect2i(130, 44, 10, 13), "slit": Vector2i(154, 32),
	}))
	return {
		"name": "C",
		"title": "C  RHOMBOID LANDSHIP + SPONSON",
		"size": Vector2i(420, 214),
		"ground": 206.0,
		"parts": [
			{"poly": P([140, 64, 144, 44, 152, 36, 238, 36, 250, 42, 254, 52, 252, 64]), "seams_x": [176, 182], "seams_y": [50], "tone": 0.03, "seed": 31},
			{"poly": side, "seams_x": [132, 166, 232, 300], "seams_y": [126, 182], "seed": 33},
			{"poly": P([232, 121, 304, 121, 320, 133, 320, 178, 232, 182]), "seams_x": [276], "tone": 0.04, "seed": 36, "shadow": true, "top_face": 3},
			{"poly": P([246, 40, 260, 40, 264, 44, 264, 53, 260, 57, 246, 57]), "cast": true, "tone": 0.06, "seed": 34},
			{"poly": P([152, 36, 154, 29, 172, 29, 174, 36]), "cast": true, "tone": 0.05, "seed": 35},
		],
		"bays": bays,
		"openings": openings,
		"details": details,
		"gun": {"trunnion": Vector2(255.5, 48.5), "len": 72.0},
		"sec": {"pivot": Vector2(321.5, 146.5), "len": 20.0, "feed": Vector2(306, 146)},
		"loader": {"bay": 0, "boiler_x": 155, "rack_x": 170, "hoist_x": 198, "window": Rect2i(182, 40, 68, 20)},
		"gear": gear,
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
	return [layout_a(), layout_b(), layout_c()]


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
		# ball mount over the roots
		for y in range(floori(piv.y) - 5, floori(piv.y) + 6):
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
			var u_ch := -12.0
			var u_now := lerpf(float(bt["u"]), u_ch, _ease(k))
			shell_at = (g["trunnion"] as Vector2) + d * u_now
			shell_ang = bt["ang"]
			rammer = u_now - float(bt["u"])
		"BREECH SHUT":
			tray_y = top_y
			show_shell = false
			rammer = lerpf(-12.0 - float(bt["u"]), 0.0, _ease(k))
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
	var o: Vector2 = (g["trunnion"] as Vector2) - d * recoil
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
