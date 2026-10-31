extends RefCounted
## The enemy faction's layouts (SPEC_TANK 5.2), one per kind, in the format of the v3 generator's
## Tank.layout_enemy(): "enemy": true, "parts" (armour polygons Hull.build plates and rivets), "details",
## "gun", "gear". Sprite px, y down; a far kind's bow is at the left, a near kind's at the right.
## Beside the v3 keys: "faces", "turret_parts" and "turret_details" (the block that traverses, baked on
## its own), "front_parts" (skirts over the track), "slits" and "lamps" ([x, y, w, on_turret]), "pivot_x",
## "exhaust", "arches" (recon), "bogies" (Behemoth), "fires" ([x, flame height], where the wreck burns),
## "night_low" (the row the night's fall ends on, for a hull all above its running gear; default the ground).
## A cast part takes rivets only on the seams it lists.
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


# --- tankette: a square riveted box, a short stepped nose under the MG, a tall drum, faces right -----------
# The box's lower corners stand clear of the belt's curve and the MG runs out over the nose, past the whole hull.


static func tankette() -> Dictionary:
	return {
		"name": "tankette", "enemy": true, "size": Vector2i(56, 26), "ground": 23.0, "faces": 1, "pitch": 4.0,
		"parts": [
			{"poly": P([2, 11, 2, 5, 40, 5, 40, 11]), "seams_x": [9, 38], "seams_y": [6], "split": false, "seed": 71, "rivet": 7},
			{"poly": P([40, 11, 40, 7, 48, 7, 48, 11]), "split": false, "seed": 73, "tone": 0.1, "rivet": 7},
		],
		"details": [
			{"kind": "louvre", "rect": Rect2i(4, 7, 4, 2)},
		],
		"turret_parts": [
			{"poly": P([21, 7, 21, 2, 23, 0, 34, 0, 36, 2, 36, 7]), "seams_y": [2], "cast": true, "seed": 72, "tone": 0.14, "rivet": 7},
		],
		"turret_details": [],
		"pivot_x": 28.0,
		"slits": [[43, 9, 3, 0]],
		"lamps": [],
		"gun": {"trunnion": Vector2(36.0, 3.5), "len": 14.0, "style": "mg"},
		"exhaust": Vector2(2, 8),
		"hit_centre": Vector2(28, 10),
		"fires": [[28, 7]],
		"gear": {
			"T": 2.0, "up": 2.0, "droop": 1.5,
			"idler": {"c": Vector2(7, 17), "r": 3.5},
			"sprocket": {"c": Vector2(45, 17.5), "r": 4.5},
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
		"name": "recon", "enemy": true, "size": Vector2i(78, 36), "ground": 33.0, "faces": 1, "night_low": 48,
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
			{"poly": P([34, 9, 34, 4, 37, 1, 50, 1, 54, 4, 54, 9]), "seams_y": [3], "cast": true, "seed": 83, "tone": 0.08, "rivet": 7},
			{"poly": P([50, 4, 54, 4, 56, 6, 54, 8, 50, 8]), "cast": true, "seed": 84, "tone": 0.02},
		],
		"turret_details": [],
		"pivot_x": 44.0,
		"fires": [[44, 9]],
		"slits": [[66, 17, 4, 0], [41, 3, 4, 1]],
		"lamps": [[74, 21]],
		"gun": {"trunnion": Vector2(52.0, 6.0), "len": 22.0, "style": "cannon"},
		"exhaust": Vector2(3, 18),
		"hit_centre": Vector2(40, 16),
		"gear": {"T": 0.0, "up": 3.0, "droop": 2.0, "tyres": true, "rollers": [], "wheels": wh},
	}


# --- light: a tall narrow turret far forward, a tail stepping down behind it, the top run bare, faces left --


static func light() -> Dictionary:
	return {
		"name": "light", "enemy": true, "size": Vector2i(96, 44), "ground": 41.0, "faces": -1, "pitch": 4.0, "night_low": 32,
		"parts": [
			{"poly": P([5, 21, 18, 10, 56, 10, 60, 14, 80, 14, 90, 19, 91, 22, 7, 22]), "seams_x": [24, 44, 62, 76], "seams_y": [15], "split": false, "seed": 18, "rivet": 7, "contrast": 1.5},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(58, 15, 8, 5)},
			{"kind": "louvre", "rect": Rect2i(72, 16, 10, 3)},
			{"kind": "antenna", "at": Vector2i(84, 18), "h": 15},
		],
		"turret_parts": [
			{"poly": P([33, 10, 34, 3, 37, 0, 49, 0, 52, 3, 54, 10]), "seams_y": [4], "cast": true, "seed": 12, "tone": 0.08, "rivet": 7},
			{"poly": P([28, 2, 34, 1, 35, 9, 29, 8]), "cast": true, "seed": 13, "tone": 0.0},
		],
		"turret_details": [],
		"pivot_x": 43.0,
		"slits": [[13, 16, 4, 0], [38, 2, 4, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(30.0, 5.0), "len": 34.0, "style": "cannon"},
		"exhaust": Vector2(90, 16),
		"hit_centre": Vector2(46, 18),
		"fires": [[43, 10]],
		"gear": {
			"T": 2.5, "up": 2.5, "droop": 2.0,
			"sprocket": {"c": Vector2(13, 29), "r": 6.0},
			"idler": {"c": Vector2(83, 31), "r": 5.0},
			"rollers": [{"c": Vector2(35, 25.5), "r": 1.5}, {"c": Vector2(60, 26), "r": 1.5}],
			"wheels": wheels(4, 27.0, 13.0, 33.0, 5.5),
		},
	}


# --- medium: box on box: a wide flat turret laden with racks, slab skirts hiding the top run, faces left ------


static func medium() -> Dictionary:
	return {
		"name": "medium", "enemy": true, "size": Vector2i(128, 58), "ground": 54.0, "faces": -1, "pitch": 4.0,
		"parts": [
			{"poly": P([4, 36, 10, 22, 116, 20, 122, 24, 124, 36, 121, 44, 8, 44]), "seams_x": [38, 62, 86, 104], "seams_y": [24], "seed": 21, "rivet": 8},
			{"poly": P([104, 21, 120, 24, 121, 27, 104, 27]), "seed": 22, "tone": 0.08, "split": false, "rivet": 8},
		],
		"details": [
			{"kind": "box", "rect": Rect2i(100, 15, 14, 6)},
			{"kind": "louvre", "rect": Rect2i(106, 24, 11, 3)},
			{"kind": "links", "a": Vector2(10, 33), "b": Vector2(21, 26), "n": 3},
		],
		"front_parts": [
			{"poly": P([22, 28, 52, 28, 52, 41, 22, 41]), "seed": 23, "tone": -0.02, "split": false, "seams_x": [37], "rivet": 8, "front": true},
			{"poly": P([54, 28, 80, 28, 80, 41, 54, 41]), "seed": 24, "tone": 0.03, "split": false, "seams_x": [67], "rivet": 8, "front": true},
			{"poly": P([82, 28, 110, 28, 110, 41, 82, 41]), "seed": 25, "tone": -0.05, "split": false, "seams_x": [96], "rivet": 8, "front": true},
		],
		"front_details": [],
		"turret_parts": [
			{"poly": P([38, 21, 38, 8, 41, 5, 92, 5, 95, 8, 96, 21]), "seams_x": [56, 76], "seams_y": [11], "seed": 26, "tone": 0.05, "rivet": 8},
			{"poly": P([31, 8, 38, 7, 38, 19, 31, 18]), "cast": true, "seed": 27, "tone": 0.02},
			{"poly": P([96, 7, 107, 7, 107, 17, 96, 17]), "seed": 29, "tone": -0.06, "split": false, "rivet": 8},
		],
		"turret_details": [
			{"kind": "box", "rect": Rect2i(46, 1, 12, 4)},
			{"kind": "box", "rect": Rect2i(60, 2, 8, 3)},
			{"kind": "box", "rect": Rect2i(80, 0, 12, 5)},
			{"kind": "bar", "at": Vector2i(44, 16), "w": 18},
			{"kind": "rail", "a": Vector2i(96, 5), "b": Vector2i(107, 5)},
		],
		"pivot_x": 66.0,
		"slits": [[13, 25, 5, 0], [72, 25, 5, 0], [44, 8, 5, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(33.0, 13.0), "len": 46.0, "style": "cannon"},
		"exhaust": Vector2(122, 28),
		"hit_centre": Vector2(62, 30),
		"fires": [[66, 14], [112, 7]],
		"gear": {
			"T": 3.0, "up": 3.0, "droop": 2.0,
			"sprocket": {"c": Vector2(14, 41), "r": 7.0},
			"idler": {"c": Vector2(114, 42), "r": 6.0},
			"rollers": [{"c": Vector2(38, 35), "r": 2.0}, {"c": Vector2(65, 35), "r": 2.0}, {"c": Vector2(92, 35.5), "r": 2.0}],
			"wheels": wheels(6, 29.0, 14.0, 45.0, 6.0),
		},
	}


# --- heavy: a stepped slab superstructure, a two-tier turret, a great muzzle brake, faces left ---------------


static func heavy() -> Dictionary:
	return {
		"name": "heavy", "enemy": true, "size": Vector2i(168, 72), "ground": 68.0, "faces": -1, "pitch": 5.0,
		"parts": [
			{"poly": P([4, 46, 18, 36, 152, 36, 162, 40, 165, 48, 162, 56, 8, 56]), "seams_x": [42, 70, 98, 126, 146], "seams_y": [40], "seed": 31, "rivet": 8},
			{"poly": P([24, 36, 38, 26, 150, 26, 150, 36]), "seams_x": [58, 88, 118], "seed": 32, "tone": 0.08, "split": false, "rivet": 8},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(44, 28, 10, 6)},
			{"kind": "louvre", "rect": Rect2i(130, 29, 13, 4)},
			{"kind": "stack", "x": 156, "y0": 15, "y1": 37},
			{"kind": "soot", "rect": Rect2i(148, 36, 14, 8)},
			{"kind": "shovel", "at": Vector2i(62, 31)},
			{"kind": "pick", "at": Vector2i(90, 31)},
		],
		"front_parts": [
			{"poly": P([24, 37, 56, 37, 56, 52, 24, 52]), "seed": 33, "tone": 0.0, "split": false, "seams_x": [40], "rivet": 8, "front": true},
			{"poly": P([58, 37, 92, 37, 92, 52, 58, 52]), "seed": 44, "tone": 0.04, "split": false, "seams_x": [75], "rivet": 8, "front": true},
			{"poly": P([94, 37, 126, 37, 126, 52, 94, 52]), "seed": 35, "tone": -0.04, "split": false, "seams_x": [110], "rivet": 8, "front": true},
			{"poly": P([128, 37, 150, 37, 150, 52, 128, 52]), "seed": 36, "tone": 0.02, "split": false, "rivet": 8, "front": true},
		],
		"turret_parts": [
			{"poly": P([60, 27, 60, 16, 130, 16, 132, 27]), "seams_x": [80, 106], "seed": 37, "tone": 0.03, "split": false, "rivet": 8},
			{"poly": P([72, 16, 73, 7, 76, 5, 114, 5, 118, 8, 120, 16]), "seams_x": [94], "seed": 40, "tone": 0.07, "split": false, "rivet": 8},
			{"poly": P([50, 8, 60, 6, 61, 24, 50, 21]), "cast": true, "bolts": true, "seed": 38, "tone": 0.03},
			{"poly": P([96, 5, 97, 0, 108, 0, 109, 5]), "cast": true, "seed": 39, "tone": 0.12},
		],
		"turret_details": [{"kind": "vent", "at": Vector2i(112, 11)}],
		"pivot_x": 96.0,
		"slits": [[31, 33, 6, 0], [104, 31, 5, 0], [78, 8, 6, 1], [100, 2, 5, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(52.0, 15.0), "len": 66.0, "style": "big"},
		"exhaust": Vector2(156, 13),
		"hit_centre": Vector2(84, 38),
		"fires": [[96, 18], [140, 10]],
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
			{"poly": P([4, 29, 34, 12, 108, 11, 140, 22, 146, 28, 144, 30, 8, 30]), "seams_x": [52, 78, 104, 124], "seams_y": [24], "seed": 41, "rivet": 8},
			{"poly": P([8, 28, 34, 13, 48, 13, 48, 26, 18, 30]), "seed": 42, "tone": 0.12, "split": false, "rivet": 8},
		],
		"details": [
			{"kind": "hatch", "rect": Rect2i(58, 15, 11, 8)},
			{"kind": "periscope", "at": Vector2i(52, 12)},
			{"kind": "periscope", "at": Vector2i(82, 11)},
			{"kind": "louvre", "rect": Rect2i(122, 24, 14, 3)},
			{"kind": "vent", "at": Vector2i(112, 19)},
			{"kind": "cable", "a": Vector2i(54, 26), "b": Vector2i(118, 26)},
		],
		"net": {"rect": Rect2i(74, 16, 34, 6)},
		"mount": {"c": Vector2(28, 25), "r": 7.0},
		"glint": Vector2i(44, 19),
		"slits": [[36, 18, 5, 0], [92, 15, 5, 0]],
		"lamps": [],
		"gun": {"trunnion": Vector2(28.0, 25.0), "len": 60.0, "style": "brake", "elev": [-2.0, 16.0]},
		"exhaust": Vector2(141, 24),
		"hit_centre": Vector2(76, 28),
		"fires": [[72, 14], [118, 8]],
		"gear": {
			"T": 3.0, "up": 3.0, "droop": 2.0,
			"sprocket": {"c": Vector2(15, 37), "r": 8.0},
			"idler": {"c": Vector2(135, 38), "r": 6.0},
			"rollers": [{"c": Vector2(48, 34), "r": 1.5}, {"c": Vector2(80, 34), "r": 1.5}, {"c": Vector2(110, 34), "r": 1.5}],
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
		"fires": [[165, 32], [38, 16], [250, 20]],
		"gear": {"T": 4.0, "up": 3.0, "droop": 2.5, "rollers": [], "wheels": wheels_all},
		"bogies": bogies,
	}
