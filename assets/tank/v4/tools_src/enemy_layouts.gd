extends RefCounted
## The enemy faction's layouts (SPEC_TANK 5.2), one per kind, in the format of the v3 generator's
## Tank.layout_enemy(): "enemy": true, "parts" (armour polygons Hull.build plates and rivets), "details",
## "gun", "gear". Sprite px, y down; a far kind's bow is at the left, a near kind's at the right.
## Beside the v3 keys: "faces", "turret_parts" and "turret_details" (the block that traverses, baked on
## its own), "front_parts" (skirts over the track), "slits" and "lamps" ([x, y, w, on_turret]), "pivot_x",
## "exhaust", "arches" (recon), "bogies" (Behemoth).
## Faction look: wedge bows, hooded slits, tall cupolas, slab skirts on hangers. Cold grey-green only.


static func P(a: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for i in range(0, a.size(), 2):
		o.append(Vector2(float(a[i]), float(a[i + 1])))
	return o


static func wheels(n: int, x0: float, dx: float, y: float, r: float) -> Array:
	var o: Array = []
	for i in n:
		o.append({"x": x0 + dx * i, "y": y, "r": r})
	return o


static func all() -> Dictionary:
	return {
		"tankette": tankette(),
		"recon": recon(),
		"light": light(),
		"medium": medium(),
		"heavy": heavy(),
		"destroyer": destroyer(),
		"behemoth": behemoth(),
	}


# --- tankette: a riveted box on three wheels, a little drum on top, faces right --------------------------


static func tankette() -> Dictionary:
	return {
		"name": "tankette", "enemy": true, "size": Vector2i(56, 26), "ground": 23.0, "faces": 1, "pitch": 4.0,
		"parts": [
			{"poly": P([8, 12, 50, 12, 50, 19, 8, 19]), "split": false, "seed": 70, "tone": -0.25, "rivet": 90},
		],
		"details": [],
		"front_parts": [
			{"poly": P([2, 9, 8, 6, 36, 6, 48, 10, 53, 14, 52, 16, 3, 16, 2, 12]), "seams_x": [17, 36], "split": false, "seed": 71, "rivet": 7, "front": true},
		],
		"front_details": [
			{"kind": "louvre", "rect": Rect2i(6, 9, 8, 2), "front": true},
			{"kind": "vent", "at": Vector2i(30, 10), "front": true},
		],
		"turret_parts": [
			{"poly": P([19, 7, 19, 3, 22, 0, 32, 0, 35, 3, 35, 7]), "cast": true, "seed": 72, "tone": 0.08},
		],
		"turret_details": [{"kind": "bolt_row", "a": Vector2i(21, 5), "b": Vector2i(33, 5)}],
		"pivot_x": 27.0,
		"slits": [[42, 11, 4, 2]],
		"lamps": [],
		"gun": {"trunnion": Vector2(31.0, 3.5), "len": 14.0, "style": "mg"},
		"exhaust": Vector2(4, 8),
		"hit_centre": Vector2(28, 12),
		"gear": {
			"T": 2.0, "up": 2.0, "droop": 1.5,
			"idler": {"c": Vector2(7, 16.5), "r": 3.5},
			"sprocket": {"c": Vector2(45.5, 15.5), "r": 4.5},
			"rollers": [],
			"wheels": wheels(3, 16.0, 8.5, 17.0, 4.0),
		},
	}


# --- recon: the six-wheeled armoured car, sloped plates, bedstead aerial, faces right -------------------


static func recon() -> Dictionary:
	var near_x := [13.0, 28.0, 62.0]
	var wh: Array = []
	for x: float in near_x:
		wh.append({"x": x + 3.0, "y": 26.0, "r": 6.0, "far": true})
	for x2: float in near_x:
		wh.append({"x": x2, "y": 27.0, "r": 6.0})
	return {
		"name": "recon", "enemy": true, "size": Vector2i(78, 36), "ground": 33.0, "faces": 1,
		"parts": [
			{"poly": P([2, 15, 8, 9, 50, 9, 60, 11, 74, 18, 76, 23, 72, 27, 5, 27, 2, 22]), "seams_x": [20, 36, 52], "seams_y": [17], "split": false, "seed": 81, "rivet": 7},
			{"poly": P([52, 10, 60, 11, 66, 14, 60, 15, 52, 14]), "seed": 82, "tone": 0.1, "split": false, "rivet": 7},
		],
		"details": [
			{"kind": "louvre", "rect": Rect2i(6, 12, 9, 3)},
			{"kind": "hatch", "rect": Rect2i(40, 17, 8, 8)},
			{"kind": "rail", "a": Vector2i(6, 4), "b": Vector2i(30, 4)},
			{"kind": "bar", "at": Vector2i(8, 8), "w": 2},
		],
		"arches": [{"c": Vector2(13, 27), "r": 7.5}, {"c": Vector2(28, 27), "r": 7.5}, {"c": Vector2(62, 27), "r": 7.5}],
		"posts": [[8, 4, 9], [20, 4, 9], [29, 4, 9]],
		"spare": {"c": Vector2(46, 13), "r": 3.5},
		"turret_parts": [
			{"poly": P([34, 9, 34, 4, 37, 1, 50, 1, 54, 4, 54, 9]), "cast": true, "seed": 83, "tone": 0.08},
			{"poly": P([50, 4, 54, 4, 56, 6, 54, 8, 50, 8]), "cast": true, "seed": 84, "tone": 0.02},
		],
		"turret_details": [{"kind": "bolt_row", "a": Vector2i(36, 7), "b": Vector2i(49, 7)}],
		"pivot_x": 44.0,
		"slits": [[66, 17, 4, 0], [56, 13, 3, 0], [41, 3, 4, 1]],
		"lamps": [[74, 21]],
		"gun": {"trunnion": Vector2(52.0, 6.0), "len": 22.0, "style": "cannon"},
		"exhaust": Vector2(3, 18),
		"hit_centre": Vector2(40, 16),
		"gear": {"T": 0.0, "up": 3.0, "droop": 2.0, "tyres": true, "rollers": [], "wheels": wh},
	}


# --- light: angled glacis, cast turret, the whole track on show, faces left --------------------------------


static func light() -> Dictionary:
	return {
		"name": "light", "enemy": true, "size": Vector2i(96, 44), "ground": 41.0, "faces": -1, "pitch": 4.0,
		"parts": [
			{"poly": P([5, 27, 18, 15, 70, 15, 88, 21, 91, 28, 88, 32, 8, 32]), "seams_x": [30, 52, 72], "seams_y": [22], "split": false, "seed": 11, "rivet": 7},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(22, 17, 8, 6)},
			{"kind": "louvre", "rect": Rect2i(74, 18, 10, 3)},
			{"kind": "vent", "at": Vector2i(68, 19)},
			{"kind": "bar", "at": Vector2i(32, 18), "w": 14},
			{"kind": "antenna", "at": Vector2i(78, 20), "h": 15},
		],
		"turret_parts": [
			{"poly": P([34, 15, 36, 7, 42, 3, 58, 3, 64, 8, 65, 15]), "cast": true, "seed": 12, "tone": 0.06},
			{"poly": P([30, 8, 36, 7, 37, 14, 31, 13]), "cast": true, "seed": 13, "tone": 0.0},
			{"poly": P([46, 3, 47, 0, 54, 0, 55, 3]), "cast": true, "seed": 14, "tone": 0.12},
		],
		"turret_details": [{"kind": "vent", "at": Vector2i(60, 10)}],
		"pivot_x": 50.0,
		"slits": [[12, 25, 4, 0], [40, 6, 4, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(33.0, 10.0), "len": 34.0, "style": "cannon"},
		"exhaust": Vector2(90, 24),
		"hit_centre": Vector2(46, 22),
		"gear": {
			"T": 2.5, "up": 2.5, "droop": 2.0,
			"sprocket": {"c": Vector2(13, 29), "r": 6.0},
			"idler": {"c": Vector2(83, 31), "r": 5.0},
			"rollers": [{"c": Vector2(35, 25), "r": 1.5}, {"c": Vector2(60, 25.5), "r": 1.5}],
			"wheels": wheels(4, 27.0, 13.0, 33.0, 5.5),
		},
	}


# --- medium: plated, skirt plates on hangers, stowage, cupola, faces left ----------------------------------


static func medium() -> Dictionary:
	return {
		"name": "medium", "enemy": true, "size": Vector2i(128, 58), "ground": 54.0, "faces": -1, "pitch": 4.0,
		"parts": [
			{"poly": P([5, 34, 22, 20, 98, 20, 120, 26, 124, 35, 121, 44, 8, 44]), "seams_x": [38, 62, 86, 104], "seams_y": [28], "seed": 21, "rivet": 8},
			{"poly": P([104, 21, 120, 26, 121, 29, 104, 29]), "seed": 22, "tone": 0.08, "split": false, "rivet": 8},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(26, 22, 10, 7)},
			{"kind": "box", "rect": Rect2i(94, 16, 14, 6)},
			{"kind": "louvre", "rect": Rect2i(106, 24, 11, 3)},
			{"kind": "cable", "a": Vector2i(40, 26), "b": Vector2i(100, 26)},
		],
		"front_parts": [
			{"poly": P([25, 31, 52, 31, 52, 40, 25, 40]), "seed": 23, "tone": -0.02, "split": false, "seams_x": [38], "rivet": 8, "front": true},
			{"poly": P([55, 31, 80, 31, 80, 40, 55, 40]), "seed": 24, "tone": 0.03, "split": false, "seams_x": [67], "rivet": 8, "front": true},
			{"poly": P([83, 31, 108, 32, 108, 40, 83, 40]), "seed": 25, "tone": -0.05, "split": false, "seams_x": [96], "rivet": 8, "front": true},
		],
		"front_details": [
			{"kind": "links", "a": Vector2(10, 33), "b": Vector2(21, 24), "n": 3, "front": true},
		],
		"turret_parts": [
			{"poly": P([46, 20, 47, 9, 53, 5, 84, 5, 90, 11, 91, 20]), "seams_x": [68], "seams_y": [12], "seed": 26, "tone": 0.05, "rivet": 8},
			{"poly": P([40, 8, 47, 6, 48, 18, 41, 17]), "cast": true, "seed": 27, "tone": 0.02},
			{"poly": P([66, 5, 67, 0, 77, 0, 78, 5]), "cast": true, "seed": 28, "tone": 0.12},
		],
		"turret_details": [{"kind": "vent", "at": Vector2i(82, 9)}, {"kind": "bar", "at": Vector2i(52, 16), "w": 16}],
		"pivot_x": 68.0,
		"slits": [[12, 32, 5, 0], [52, 8, 5, 1], [70, 2, 4, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(43.0, 12.0), "len": 46.0, "style": "cannon"},
		"exhaust": Vector2(122, 30),
		"hit_centre": Vector2(62, 30),
		"gear": {
			"T": 3.0, "up": 3.0, "droop": 2.0,
			"sprocket": {"c": Vector2(14, 41), "r": 7.0},
			"idler": {"c": Vector2(114, 42), "r": 6.0},
			"rollers": [{"c": Vector2(38, 35), "r": 2.0}, {"c": Vector2(65, 35), "r": 2.0}, {"c": Vector2(92, 35.5), "r": 2.0}],
			"wheels": wheels(6, 29.0, 14.0, 45.0, 6.0),
		},
	}


# --- heavy: two rows of thick plates, big bolts, exhaust stack, tool rack, long gun, faces left ------------


static func heavy() -> Dictionary:
	return {
		"name": "heavy", "enemy": true, "size": Vector2i(168, 72), "ground": 68.0, "faces": -1, "pitch": 5.0,
		"parts": [
			{"poly": P([4, 44, 24, 27, 130, 27, 160, 34, 165, 46, 162, 56, 8, 56]), "seams_x": [42, 70, 98, 126, 146], "seams_y": [36], "seed": 31, "rivet": 8},
			{"poly": P([6, 42, 24, 28, 34, 28, 34, 38, 12, 46]), "seed": 32, "tone": 0.1, "split": false, "rivet": 8},
			{"poly": P([25, 28, 26, 20, 30, 17, 40, 17, 44, 20, 45, 28]), "cast": true, "seed": 30, "tone": 0.08},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(38, 29, 11, 7)},
			{"kind": "louvre", "rect": Rect2i(132, 30, 13, 4)},
			{"kind": "stack", "x": 151, "y0": 17, "y1": 36},
			{"kind": "soot", "rect": Rect2i(146, 34, 12, 8)},
			{"kind": "shovel", "at": Vector2i(62, 38)},
			{"kind": "pick", "at": Vector2i(92, 38)},
			{"kind": "bar", "at": Vector2i(118, 38), "w": 18},
		],
		"front_parts": [
			{"poly": P([24, 41, 56, 41, 56, 51, 24, 51]), "seed": 33, "tone": 0.0, "split": false, "seams_x": [40], "rivet": 8, "front": true},
			{"poly": P([59, 41, 92, 41, 92, 51, 59, 51]), "seed": 34, "tone": 0.04, "split": false, "seams_x": [75], "rivet": 8, "front": true},
			{"poly": P([95, 41, 126, 41, 126, 51, 95, 51]), "seed": 35, "tone": -0.04, "split": false, "seams_x": [110], "rivet": 8, "front": true},
			{"poly": P([129, 41, 150, 42, 150, 51, 129, 51]), "seed": 36, "tone": 0.02, "split": false, "rivet": 8, "front": true},
		],
		"turret_parts": [
			{"poly": P([62, 27, 63, 13, 72, 6, 112, 6, 122, 12, 124, 27]), "seams_x": [92], "seams_y": [16], "seed": 37, "tone": 0.05, "rivet": 8},
			{"poly": P([52, 11, 63, 8, 64, 25, 52, 22]), "cast": true, "bolts": true, "seed": 38, "tone": 0.03},
			{"poly": P([86, 6, 87, 0, 100, 0, 101, 6]), "cast": true, "seed": 39, "tone": 0.12},
		],
		"turret_details": [{"kind": "vent", "at": Vector2i(114, 11)}, {"kind": "hatch_top", "at": Vector2i(106, 6), "w": 7}],
		"pivot_x": 92.0,
		"slits": [[13, 42, 6, 0], [29, 21, 6, 0], [72, 10, 6, 1], [89, 2, 5, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(55.0, 16.0), "len": 66.0, "style": "brake"},
		"exhaust": Vector2(151, 15),
		"hit_centre": Vector2(84, 38),
		"gear": {
			"T": 4.0, "up": 3.5, "droop": 2.5,
			"sprocket": {"c": Vector2(14, 53), "r": 9.0},
			"idler": {"c": Vector2(153, 54), "r": 7.0},
			"rollers": [{"c": Vector2(44, 45), "r": 2.0}, {"c": Vector2(76, 45), "r": 2.0}, {"c": Vector2(108, 45), "r": 2.0}, {"c": Vector2(136, 46), "r": 2.0}],
			"wheels": wheels(8, 30.0, 15.5, 57.0, 7.0),
		},
	}


# --- destroyer: a low slab casemate, the gun in the bow plate, net stowage, faces left ---------------------


static func destroyer() -> Dictionary:
	return {
		"name": "destroyer", "enemy": true, "size": Vector2i(150, 54), "ground": 50.0, "faces": -1, "pitch": 4.0,
		"parts": [
			{"poly": P([4, 31, 34, 12, 108, 11, 140, 22, 146, 32, 143, 41, 8, 41]), "seams_x": [52, 78, 104, 124], "seams_y": [26], "seed": 41, "rivet": 8},
			{"poly": P([8, 30, 34, 13, 48, 13, 48, 26, 18, 33]), "seed": 42, "tone": 0.12, "split": false, "rivet": 8},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(58, 15, 11, 8)},
			{"kind": "periscope", "at": Vector2i(52, 12)},
			{"kind": "periscope", "at": Vector2i(82, 11)},
			{"kind": "louvre", "rect": Rect2i(122, 24, 14, 3)},
			{"kind": "vent", "at": Vector2i(112, 19)},
			{"kind": "cable", "a": Vector2i(52, 30), "b": Vector2i(120, 30)},
		],
		"net": {"rect": Rect2i(74, 16, 34, 6)},
		"mount": {"c": Vector2(28, 25), "r": 7.0},
		"glint": Vector2i(44, 19),
		"slits": [[36, 18, 5, 0], [92, 15, 5, 0]],
		"lamps": [],
		"gun": {"trunnion": Vector2(28.0, 25.0), "len": 60.0, "style": "brake", "elev": [-2.0, 16.0]},
		"exhaust": Vector2(141, 24),
		"hit_centre": Vector2(76, 28),
		"gear": {
			"T": 3.0, "up": 3.0, "droop": 2.0,
			"sprocket": {"c": Vector2(15, 37), "r": 8.0},
			"idler": {"c": Vector2(135, 38), "r": 6.0},
			"rollers": [{"c": Vector2(48, 32), "r": 2.0}, {"c": Vector2(80, 32), "r": 2.0}, {"c": Vector2(110, 32), "r": 2.0}],
			"wheels": wheels(7, 31.0, 14.5, 41.0, 6.0),
		},
	}


# --- behemoth: the multi-deck fortress on three bogies, faces left ----------------------------------------


static func behemoth() -> Dictionary:
	var bogies: Array = []
	var wheels_all: Array = []
	for i in 3:
		var bx := 8.0 + i * 96.0
		var wh := wheels(5, bx + 24.0, 15.0, 133.0, 7.0)
		wheels_all.append_array(wh)
		bogies.append({
			"x_offset": bx,
			"sprocket": {"c": Vector2(bx + 11.0, 125.0), "r": 10.0},
			"rollers": [{"c": Vector2(bx + 50.0, 119.0), "r": 2.0}],
			"wheels": wh,
			"frame": Rect2i(int(bx) + 14, 111, 74, 16),
		})
	return {
		"name": "behemoth", "enemy": true, "size": Vector2i(300, 148), "ground": 144.0, "faces": -1, "pitch": 6.0,
		"parts": [
			# the lower deck, a long wedge
			{"poly": P([4, 104, 30, 74, 276, 74, 296, 88, 298, 112, 294, 124, 10, 124]), "seams_x": [52, 92, 132, 172, 212, 252], "seams_y": [90, 106], "seed": 51, "rivet": 8},
			# the bow wedge
			{"poly": P([6, 102, 30, 76, 50, 76, 50, 94, 18, 110]), "seed": 52, "tone": 0.1, "split": false, "rivet": 8},
			# the upper deck
			{"poly": P([40, 74, 60, 50, 244, 50, 268, 74]), "seams_x": [84, 128, 172, 216], "seams_y": [62], "seed": 53, "tone": 0.03, "rivet": 8},
			# the stern casemate
			{"poly": P([226, 50, 232, 36, 262, 36, 268, 50, 268, 66, 226, 66]), "seams_x": [246], "split": false, "seed": 54, "tone": 0.06, "rivet": 8},
			# buttress plates down the lower deck
			{"poly": P([72, 76, 80, 76, 80, 122, 72, 122]), "seed": 59, "tone": 0.14, "split": false, "rivet": 8},
			{"poly": P([150, 76, 158, 76, 158, 122, 150, 122]), "seed": 60, "tone": 0.14, "split": false, "rivet": 8},
			{"poly": P([232, 76, 240, 76, 240, 122, 232, 122]), "seed": 61, "tone": 0.14, "split": false, "rivet": 8},
			# a sponson mid deck, its gun a stub
			{"poly": P([92, 84, 98, 80, 128, 80, 132, 84, 132, 92, 92, 92]), "seed": 62, "tone": 0.1, "split": false, "seams_x": [112], "rivet": 8},
			# the stern gun house on the upper deck
			{"poly": P([72, 50, 74, 40, 80, 36, 100, 36, 104, 40, 106, 50]), "cast": true, "seed": 63, "tone": 0.07},
			# the bow sponson
			{"poly": P([12, 84, 28, 80, 40, 80, 40, 98, 24, 98, 12, 94]), "cast": true, "bolts": true, "seed": 55, "tone": 0.08},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(60, 78, 14, 10)},
			{"kind": "hatch", "rect": Rect2i(186, 78, 14, 10)},
			{"kind": "hatch", "rect": Rect2i(94, 54, 12, 7)},
			{"kind": "louvre", "rect": Rect2i(268, 78, 20, 6)},
			{"kind": "louvre", "rect": Rect2i(206, 94, 22, 4)},
			{"kind": "vent", "at": Vector2i(150, 56)},
			{"kind": "vent", "at": Vector2i(200, 56)},
			{"kind": "rail", "a": Vector2i(60, 47), "b": Vector2i(108, 47)},
			{"kind": "rail", "a": Vector2i(34, 72), "b": Vector2i(58, 72)},
			{"kind": "stack", "x": 240, "y0": 14, "y1": 37},
			{"kind": "stack", "x": 254, "y0": 20, "y1": 37},
			{"kind": "soot", "rect": Rect2i(232, 36, 30, 10)},
			{"kind": "cable", "a": Vector2i(160, 88), "b": Vector2i(226, 88)},
			{"kind": "box", "rect": Rect2i(164, 94, 22, 8)},
			{"kind": "links", "a": Vector2(192, 98), "b": Vector2(226, 98), "n": 6},
			
			{"kind": "antenna", "at": Vector2i(248, 36), "h": 30},
		],
		"turret_parts": [
			{"poly": P([110, 50, 112, 28, 124, 14, 200, 14, 216, 26, 220, 50]), "seams_x": [150, 186], "seams_y": [30], "seed": 56, "tone": 0.06, "rivet": 8},
			{"poly": P([96, 18, 112, 14, 114, 44, 96, 40]), "cast": true, "bolts": true, "seed": 57, "tone": 0.03},
			{"poly": P([162, 14, 164, 2, 186, 2, 188, 14]), "cast": true, "seed": 58, "tone": 0.12},
		],
		"turret_details": [
			{"kind": "vent", "at": Vector2i(206, 22)},
			{"kind": "hatch", "rect": Rect2i(192, 32, 12, 9)},
			{"kind": "hatch_top", "at": Vector2i(148, 14), "w": 9},
			{"kind": "bar", "at": Vector2i(122, 42), "w": 26},
		],
		"pivot_x": 165.0,
		"slits": [[18, 96, 7, 0], [62, 64, 7, 0], [130, 66, 7, 0], [212, 66, 7, 0], [124, 22, 8, 1], [168, 6, 6, 1]],
		"ports": [
			[88, 108], [100, 108], [112, 108], [124, 108], [136, 108], [168, 108], [180, 108], [192, 108], [204, 108], [216, 108],
			[150, 66], [162, 66], [174, 66], [186, 66], [198, 66],
		],
		"lamps": [],
		"furnace": Rect2i(244, 96, 22, 8),
		"gun": {"trunnion": Vector2(100.0, 29.0), "len": 96.0, "style": "brake"},
		"secondary": {"pivot": Vector2(14.0, 89.0), "len": 24.0},
		"exhaust": Vector2(240, 12),
		"hit_centre": Vector2(150, 80),
		"gear": {"T": 4.0, "up": 3.0, "droop": 2.5, "rollers": [], "wheels": wheels_all},
		"bogies": bogies,
	}
