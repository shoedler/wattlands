extends RefCounted
## The Foundry Pact's layouts (SPEC_TANK 5.2), one per kind. Sprite px, y down; a far kind's bow is at the left, a near
## kind's at the right. Painted by enemy_paint.gd, read by enemy_bake.gd.
## "enemy": true, "parts" (armour polygons, in enemy_paint.part's keys), "details", "gun", "gear". Beside them: "faces",
## "turret_parts" and "turret_details" (the block that traverses, baked on its own), "front_parts" and "front_details"
## (skirts over the track), "slits" and "lamps" ([x, y, w, on_turret]), "pivot_x", "exhaust", "arches" (recon), "bogies"
## (Behemoth), "fires" ([x, flame height], where the wreck burns), "night_low" (the row the value's fall ends on, for a
## hull all above its running gear; default the ground), "bands", "turret_bands" and "paint" (enemy_paint.canvas),
## "rivets", "front_rivets" and "turret_rivets" ([x0, x1, y] rows), "rivet_cols", "streak_every", "moon_share", "moon_hot"
## (the bright step all along), "mud" (false: a box of four rows has no low third), "turret_boost", "turret_band_step".
##
## Faction look: sealed factory slab. Flat-topped decks, straight facets, welded seams, no windows, long guns, stowage.
## Field grey with hard stepped bands of dark yellow. Rivets only on skirts, hatches, mantlets and access plates.
## The mark is the Pact's own diamond; the numbers use only 0, 1 and 8, because a turret's traverse and `flip` mirror them.


static func P(a: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for i in range(0, a.size(), 2):
		o.append(Vector2(float(a[i]), float(a[i + 1])))
	return o


## One plated part: every plate boundary comes from the layout's seams, never a seeded split.
static func plate(poly: Array, keys: Dictionary = {}) -> Dictionary:
	var part := {"poly": P(poly), "split": false}
	part.merge(keys)
	return part


static func wheels(n: int, x0: float, dx: float, y: float, r: float) -> Array:
	var o: Array = []
	for i in n:
		o.append({"x": x0 + dx * i, "y": y, "r": r})
	return o


## A finger joint's top edge, left to right: 2 px notches every 4 px, `depth` rows deep.
static func fingers(x0: int, x1: int, y: int, depth: int = 2) -> Array:
	var o: Array = []
	var x := x0
	while x + 4 <= x1:
		o.append_array([x, y, x + 2, y, x + 2, y + depth, x + 4, y + depth])
		x += 4
	o.append_array([x, y])
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


# --- tankette: a square welded box, a stepped nose with one facet under the MG, a flat drum, faces right ---------
# The box's lower corners stand clear of the belt's curve and the MG runs out over the nose, past the whole hull.


static func tankette() -> Dictionary:
	return {
		"name": "tankette",
		"enemy": true,
		"size": Vector2i(56, 26),
		"ground": 23.0,
		"faces": 1,
		"pitch": 4.0,
		"bands": [[14, 21, 0]],
		"moon_share": 0.5,
		"moon_hot": true,
		"mud": false,
		"streak_every": 18,
		"parts":
		[
			plate([2, 11, 2, 5, 40, 5, 40, 11], {"seams_x": [21], "seed": 71, "step": 1}),
			plate([40, 11, 40, 7, 46, 7, 48, 9, 48, 11], {"seed": 73, "step": 1, "paint": 0}),
		],
		"details":
		[
			{"kind": "can", "rect": Rect2i(3, 5, 3, 3)},
			{"kind": "louvre", "rect": Rect2i(3, 9, 4, 1)},
			{"kind": "mark", "at": Vector2i(8, 7), "size": 3},
		],
		"rivets": [[15, 38, 9]],
		"turret_parts":
		[
			plate([21, 7, 21, 1, 22, 0, 35, 0, 36, 1, 36, 7], {"seed": 72}),
		],
		"turret_details": [],
		"turret_rivets": [[24, 34, 3]],
		"turret_boost": 1.8,
		"pivot_x": 28.0,
		"slits": [[43, 9, 3, 0]],
		"lamps": [],
		"gun": {"trunnion": Vector2(36.0, 3.5), "len": 14.0, "style": "mg"},
		"exhaust": Vector2(2, 8),
		"hit_centre": Vector2(28, 10),
		"fires": [[28, 7]],
		"gear":
		{
			"T": 2.0,
			"up": 2.0,
			"droop": 1.5,
			"idler": {"c": Vector2(7, 17), "r": 3.5},
			"sprocket": {"c": Vector2(45, 17.5), "r": 4.5},
			"rollers": [],
			"wheels": wheels(3, 16.0, 8.5, 17.0, 4.0),
		},
	}


# --- recon: a six-wheeled faceted coffin, creased nose to tail, a bedstead aerial, faces right -----------------


static func recon() -> Dictionary:
	var near_x := [13.0, 28.0, 62.0]
	var wh: Array = []
	for x: float in near_x:
		wh.append({"x": x + 3.0, "y": 26.0, "r": 6.0, "far": true})
	for x2: float in near_x:
		wh.append({"x": x2, "y": 27.0, "r": 6.0})
	return {
		"name": "recon",
		"enemy": true,
		"size": Vector2i(78, 36),
		"ground": 33.0,
		"faces": 1,
		"night_low": 48,
		"bands": [[35, 52, -1]],
		"moon_share": 0.42,
		"streak_every": 18,
		"parts":
		[
			plate(
				[2, 17, 9, 9, 54, 9, 76, 17, 76, 22, 71, 27, 7, 27],
				{"seams_x": [16, 33, 54], "seams_y": [17], "row_steps": [0, -1], "row_weld": false, "seed": 81}
			),
		],
		"details":
		[
			{"kind": "louvre", "rect": Rect2i(5, 13, 9, 3)},
			{"kind": "hatch", "rect": Rect2i(40, 18, 9, 8), "lit": false},
			{"kind": "digits", "at": Vector2i(19, 11), "text": "10"},
			{"kind": "access", "rect": Rect2i(27, 11, 14, 6), "rows": false},
			{"kind": "rail", "a": Vector2i(6, 4), "b": Vector2i(30, 4), "drop": 0},
		],
		"rivets":
		[
			[27, 40, 11],
			[27, 40, 15],
			[3, 8, 18],
			[55, 60, 12],
			[10, 16, 11],
			[36, 39, 21],
			[50, 54, 21],
			[56, 68, 14],
			[50, 54, 19],
			[36, 39, 19],
			[36, 39, 24],
			[50, 54, 24]
		],
		"arches":
		[
			{"c": Vector2(13, 27), "r": 7.5},
			{"c": Vector2(28, 27), "r": 7.5},
			{"c": Vector2(62, 27), "r": 7.5}
		],
		"posts": [[8, 4, 9], [20, 4, 9], [29, 4, 9]],
		"spare": {"c": Vector2(46, 13), "r": 3.5},
		"turret_parts":
		[
			plate(
				[34, 9, 34, 4, 37, 1, 50, 1, 53, 4, 53, 9],
				{"seed": 83, "seams_y": [4], "row_steps": [1, 0], "row_weld": false}
			),
			plate([50, 3, 54, 3, 56, 5, 56, 7, 54, 9, 50, 9], {"cast": true, "seed": 84}),
		],
		"turret_details": [],
		"turret_rivets": [[35, 48, 7]],
		"turret_boost": 1.45,
		"pivot_x": 44.0,
		"fires": [[44, 9]],
		"slits": [[66, 18, 4, 0], [40, 5, 4, 1]],
		"lamps": [[74, 21]],
		"gun": {"trunnion": Vector2(52.0, 6.0), "len": 22.0, "style": "cannon"},
		"exhaust": Vector2(3, 18),
		"hit_centre": Vector2(40, 16),
		"gear": {"T": 0.0, "up": 3.0, "droop": 2.0, "tyres": true, "rollers": [], "wheels": wh},
	}


# --- light: a tall narrow turret far forward, a tail stepping down behind it, the top run bare, faces left ---------


static func light() -> Dictionary:
	return {
		"name": "light",
		"enemy": true,
		"size": Vector2i(96, 44),
		"ground": 41.0,
		"faces": -1,
		"pitch": 4.0,
		"night_low": 32,
		"bands": [[17, 30, 1], [58, 80, 1]],
		"moon_share": 0.55,
		"streak_every": 30,
		"parts":
		[
			plate(
				[5, 21, 16, 10, 56, 10, 56, 14, 80, 14, 80, 18, 90, 18, 91, 22, 7, 22],
				{"seams_x": [28, 56, 68], "seams_y": [16], "row_steps": [1, -1], "col_steps": [0, 1, -1, 1], "row_weld": false, "seed": 18}
			),
		],
		"details":
		[
			{"kind": "access", "rect": Rect2i(24, 16, 18, 6)},
			{"kind": "hatch", "rect": Rect2i(46, 15, 8, 6)},
			{"kind": "can", "rect": Rect2i(70, 9, 3, 5)},
			{"kind": "can", "rect": Rect2i(74, 9, 4, 5)},
			{"kind": "louvre", "rect": Rect2i(60, 16, 10, 3)},
			{"kind": "antenna", "at": Vector2i(87, 19), "h": 15},
		],
		"rivets": [[20, 54, 13], [58, 78, 20], [74, 88, 20]],
		"turret_parts":
		[
			plate([33, 10, 33, 2, 35, 0, 52, 0, 54, 2, 54, 10], {"seed": 12}),
			plate([28, 2, 33, 1, 34, 9, 29, 8], {"cast": true, "seed": 13}),
		],
		"turret_details":
		[
			{"kind": "digits", "at": Vector2i(44, 4), "text": "80"},
		],
		"turret_rivets": [[35, 42, 8], [48, 52, 8], [47, 52, 3]],
		"turret_boost": 1.25,
		"pivot_x": 43.0,
		"slits": [[12, 18, 4, 0], [37, 4, 4, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(30.0, 5.0), "len": 34.0, "style": "cannon"},
		"exhaust": Vector2(90, 16),
		"hit_centre": Vector2(46, 18),
		"fires": [[43, 10]],
		"gear":
		{
			"T": 2.5,
			"up": 2.5,
			"droop": 2.0,
			"sprocket": {"c": Vector2(13, 29), "r": 6.0},
			"idler": {"c": Vector2(83, 31), "r": 5.0},
			"rollers": [{"c": Vector2(35, 25.5), "r": 1.5}, {"c": Vector2(60, 26), "r": 1.5}],
			"wheels": wheels(4, 27.0, 13.0, 33.0, 5.5),
		},
	}


# --- medium: a straight glacis, a flat deck, a wide low turret with its bin, a row of slab skirts, faces left ------


static func medium() -> Dictionary:
	return {
		"name": "medium",
		"enemy": true,
		"size": Vector2i(128, 58),
		"ground": 54.0,
		"faces": -1,
		"pitch": 4.0,
		"bands": [[46, 66, 2], [100, 120, 2]],
		"turret_bands": [[52, 74, 2]],
		"moon_share": 0.66,
		"streak_every": 24,
		"parts":
		[
			plate(
				[4, 36, 30, 20, 122, 20, 124, 36, 121, 44, 8, 44],
				{"seams_x": [38, 62, 86, 104], "seams_y": [28], "row_weld": false, "seed": 21}
			),
			plate(
				[5, 36, 30, 20, 38, 20, 38, 28, 22, 36, 12, 42],
				{"seed": 22, "step": 1, "paint": 0}
			),
		],
		"details":
		[
			{"kind": "box", "rect": Rect2i(100, 14, 14, 6)},
			{"kind": "access", "rect": Rect2i(42, 22, 20, 6)},
			{"kind": "louvre", "rect": Rect2i(106, 24, 11, 3)},
			{"kind": "links", "a": Vector2(11, 33), "b": Vector2(24, 25), "n": 3},
		],
		"rivets": [[64, 80, 24], [84, 100, 24], [40, 100, 31], [40, 100, 38], [104, 120, 31], [104, 120, 38]],
		"front_parts":
		[
			plate(
				[22, 28, 52, 28, 52, 41, 22, 41],
				{"seed": 23, "seams_x": [37], "front": true}
			),
			plate(
				[54, 28, 80, 28, 80, 41, 54, 41],
				{"seed": 24, "seams_x": [72], "front": true}
			),
			plate(
				[82, 28, 110, 28, 110, 38, 106, 41, 82, 41],
				{"seed": 25, "seams_x": [96], "front": true}
			),
		],
		"front_details":
		[
			{"kind": "mark", "at": Vector2i(61, 31), "size": 5},
		],
		"front_rivets":
		[
			[24, 50, 30],
			[73, 78, 30],
			[56, 60, 30],
			[84, 108, 30],
			[84, 104, 38]
		],
		"turret_parts":
		[
			plate(
				[38, 21, 38, 12, 41, 9, 92, 9, 95, 12, 96, 21],
				{"seams_x": [56, 76], "seams_y": [14], "row_weld": false, "seed": 26}
			),
			plate([31, 10, 38, 9, 38, 19, 31, 18], {"cast": true, "seed": 27}),
			plate([96, 9, 107, 9, 107, 18, 96, 18], {"seed": 29, "paint": 1}),
		],
		"turret_details":
		[
			{"kind": "access", "rect": Rect2i(40, 14, 14, 7)},
			{"kind": "digits", "at": Vector2i(61, 15), "text": "808"},
			{"kind": "hatch", "rect": Rect2i(79, 14, 12, 7)},
			{"kind": "bar", "at": Vector2i(58, 11), "w": 16},
		],
		"turret_rivets": [[98, 106, 11], [98, 106, 16], [56, 92, 12], [41, 92, 20], [32, 36, 12], [32, 36, 15]],
		"pivot_x": 66.0,
		"slits": [[27, 26, 4, 0], [68, 22, 4, 0], [44, 12, 4, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(33.0, 13.0), "len": 46.0, "style": "cannon"},
		"exhaust": Vector2(122, 28),
		"hit_centre": Vector2(62, 30),
		"fires": [[66, 14], [112, 7]],
		"gear":
		{
			"T": 3.0,
			"up": 3.0,
			"droop": 2.0,
			"sprocket": {"c": Vector2(14, 41), "r": 7.0},
			"idler": {"c": Vector2(114, 42), "r": 6.0},
			"rollers":
			[
				{"c": Vector2(38, 35), "r": 2.0},
				{"c": Vector2(65, 35), "r": 2.0},
				{"c": Vector2(92, 35.5), "r": 2.0}
			],
			"wheels": wheels(6, 29.0, 14.0, 45.0, 6.0),
		},
	}


# --- heavy: near-vertical slabs, finger-jointed corners, one flat turret tier, a great muzzle brake, faces left -----


static func heavy() -> Dictionary:
	var poly: Array = [6, 56, 10, 28]
	poly.append_array(fingers(10, 26, 26))
	poly.append_array([144, 26])
	poly.append_array(fingers(144, 160, 26))
	poly.append_array([160, 28, 164, 56])
	return {
		"name": "heavy",
		"enemy": true,
		"size": Vector2i(168, 72),
		"ground": 68.0,
		"faces": -1,
		"pitch": 5.0,
		"bands": [[30, 58, 2], [112, 140, 2]],
		"turret_bands": [[92, 116, 2]],
		"moon_share": 0.66,
		"streak_every": 34,
		"parts":
		[
			plate(
				poly,
				{"seams_x": [70, 126], "seams_y": [37], "row_weld": false, "seed": 31}
			),
		],
		"details":
		[
			{"kind": "access", "rect": Rect2i(13, 30, 26, 7)},
			{"kind": "hatch", "rect": Rect2i(44, 28, 12, 7)},
			{"kind": "louvre", "rect": Rect2i(130, 29, 13, 3)},
			{"kind": "stack", "x": 156, "y0": 15, "y1": 37},
			{"kind": "soot", "rect": Rect2i(148, 30, 14, 8)},
			{"kind": "shovel", "at": Vector2i(62, 31)},
			{"kind": "pick", "at": Vector2i(90, 31)},
			{"kind": "cable", "a": Vector2i(62, 35), "b": Vector2i(104, 35)},
		],
		"rivets":
		[
			[60, 150, 40],
			[26, 150, 47],
			[60, 150, 54]
		],
		"front_parts":
		[
			plate([24, 37, 57, 37, 57, 52, 24, 52], {"seed": 33, "front": true}),
			plate([56, 37, 93, 37, 93, 52, 56, 52], {"seed": 44, "front": true}),
			plate([92, 37, 127, 37, 127, 52, 92, 52], {"seed": 35, "front": true}),
			plate([126, 37, 150, 37, 150, 52, 126, 52], {"seed": 36, "front": true}),
		],
		"front_rivets":
		[
			[26, 54, 40],
			[26, 54, 49],
			[60, 90, 40],
			[60, 90, 49],
			[96, 124, 40],
			[96, 124, 49],
			[130, 148, 40],
			[130, 148, 49]
		],
		"turret_parts":
		[
			plate(
				[60, 27, 60, 6, 62, 4, 130, 4, 132, 6, 132, 27],
				{"seams_x": [80, 106], "seams_y": [11], "row_weld": false, "seed": 37}
			),
			plate([50, 8, 60, 6, 61, 24, 50, 21], {"cast": true, "seed": 38}),
		],
		"turret_details":
		[
			{"kind": "access", "rect": Rect2i(62, 15, 18, 10)},
			{"kind": "access", "rect": Rect2i(108, 15, 22, 10)},
			{"kind": "digits", "at": Vector2i(88, 16), "text": "110"},
			{"kind": "vent", "at": Vector2i(122, 11)},
		],
		"turret_rivets": [[52, 58, 10], [52, 58, 19], [82, 104, 24], [62, 128, 12]],
		"pivot_x": 96.0,
		"slits": [[31, 33, 4, 0], [116, 31, 4, 0], [70, 10, 4, 1], [100, 10, 4, 1]],
		"lamps": [],
		"gun": {"trunnion": Vector2(52.0, 15.0), "len": 66.0, "style": "big"},
		"exhaust": Vector2(156, 13),
		"hit_centre": Vector2(84, 38),
		"fires": [[96, 18], [140, 10]],
		"gear":
		{
			"T": 4.0,
			"up": 3.5,
			"droop": 2.5,
			"sprocket": {"c": Vector2(14, 53), "r": 9.0},
			"idler": {"c": Vector2(153, 54), "r": 7.0},
			"rollers":
			[
				{"c": Vector2(44, 45), "r": 2.0},
				{"c": Vector2(76, 45), "r": 2.0},
				{"c": Vector2(108, 45), "r": 2.0},
				{"c": Vector2(136, 46), "r": 2.0}
			],
			"wheels": wheels(8, 30.0, 15.5, 57.0, 7.0),
		},
	}


# --- destroyer: a low casemate, one unbroken wedge, the gun out of a cast boar's head in the bow, faces left -------


static func destroyer() -> Dictionary:
	return {
		"name": "destroyer",
		"enemy": true,
		"size": Vector2i(150, 54),
		"ground": 50.0,
		"faces": -1,
		"pitch": 4.0,
		"paint": 1,
		"bands": [[60, 72, 2]],
		"moon_share": 0.66,
		"streak_every": 44,
		"parts":
		[
			plate(
				[4, 29, 34, 11, 108, 11, 130, 24, 146, 24, 146, 28, 144, 30, 8, 30],
				{"seams_x": [52, 78, 104, 124], "seams_y": [24], "row_weld": false, "seed": 41}
			),
			plate(
				[8, 28, 34, 13, 48, 13, 48, 26, 18, 30],
				{"seed": 42, "step": 1}
			),
		],
		"details":
		[
			{"kind": "hatch", "rect": Rect2i(54, 14, 12, 8)},
			{"kind": "louvre", "rect": Rect2i(132, 25, 9, 3)},
			{"kind": "vent", "at": Vector2i(122, 21)},
			{"kind": "cable", "a": Vector2i(94, 26), "b": Vector2i(124, 26)},
			{"kind": "mark", "at": Vector2i(109, 16), "size": 5},
		],
		"rivets":
		[
			[50, 72, 13],
			[36, 46, 16],
			[10, 28, 28],
			[30, 50, 28],
			[92, 128, 23],
			[52, 92, 28],
			[96, 128, 28]
		],
		"rivet_cols": [[50, 16, 28]],
		"net": {"rect": Rect2i(74, 16, 34, 6)},
		"mount": {"c": Vector2(28, 25), "r": 7.0},
		"slits": [[36, 19, 4, 0], [68, 15, 4, 0]],
		"lamps": [],
		"gun":
		{"trunnion": Vector2(28.0, 25.0), "len": 60.0, "style": "brake", "elev": [-2.0, 16.0]},
		"exhaust": Vector2(141, 24),
		"hit_centre": Vector2(76, 28),
		"fires": [[72, 14], [118, 8]],
		"gear":
		{
			"T": 3.0,
			"up": 3.0,
			"droop": 2.0,
			"sprocket": {"c": Vector2(15, 37), "r": 8.0},
			"idler": {"c": Vector2(135, 38), "r": 6.0},
			"rollers":
			[
				{"c": Vector2(48, 34), "r": 1.5},
				{"c": Vector2(80, 34), "r": 1.5},
				{"c": Vector2(110, 34), "r": 1.5}
			],
			"wheels": wheels(7, 31.0, 14.5, 41.0, 6.0),
		},
	}


# --- behemoth: three flat decks with 45 degree ends on three bogies, a factory that walks, faces left ---------------


static func behemoth() -> Dictionary:
	var bogies: Array = []
	var wheels_all: Array = []
	for i in 3:
		var bx := 8.0 + i * 96.0
		var wh := wheels(5, bx + 24.0, 15.0, 133.0, 7.0)
		wheels_all.append_array(wh)
		(
			bogies
			. append(
				{
					"x_offset": bx,
					"sprocket": {"c": Vector2(bx + 11.0, 125.0), "r": 10.0},
					"rollers": [{"c": Vector2(bx + 50.0, 119.0), "r": 2.0}],
					"wheels": wh,
					"frame": Rect2i(int(bx) + 14, 111, 74, 16),
				}
			)
		)
	return {
		"name": "behemoth",
		"enemy": true,
		"size": Vector2i(300, 148),
		"ground": 144.0,
		"faces": -1,
		"pitch": 6.0,
		"bands": [[64, 104, 3], [176, 216, 3]],
		"turret_bands": [[154, 192, 1]],
		"turret_band_step": -1,
		"moon_share": 0.72,
		"streak_every": 20,
		"parts":
		[
			# the lower deck, slabs at least 40 px wide, each a step from its neighbour
			plate(
				[4, 104, 34, 74, 276, 74, 296, 94, 298, 112, 294, 124, 10, 124],
				{
					"seams_x": [52, 92, 132, 172, 212, 252],
					"seams_y": [98],
					"row_weld": false,
					"col_steps": [0, 1, 0, -1],
					"seed": 51
				}
			),
			# the bow wedge
			plate([6, 102, 34, 74, 50, 74, 50, 94, 18, 110], {"seed": 52, "step": 1}),
			# the middle deck
			plate(
				[40, 74, 64, 50, 244, 50, 268, 74],
				{
					"seams_x": [84, 128, 172, 216],
					"seams_y": [62],
					"col_steps": [0, -1],
					"row_weld": false,
					"seed": 53
				}
			),
			# the stern casemate, the third deck
			plate(
				[226, 66, 226, 50, 240, 36, 256, 36, 270, 50, 270, 66],
				{"seams_x": [246], "seed": 54, "step": 1}
			),
			# buttresses down the lower deck
			plate([72, 76, 80, 76, 80, 122, 72, 122], {"seed": 59, "step": 2, "paint": 0}),
			plate([150, 76, 158, 76, 158, 122, 150, 122], {"seed": 60, "step": 2, "paint": 0}),
			plate([232, 76, 240, 76, 240, 122, 232, 122], {"seed": 61, "step": 2, "paint": 0}),
			# a sponson mid deck
			plate(
				[92, 84, 98, 80, 128, 80, 132, 84, 132, 92, 92, 92],
				{"seed": 62, "step": 1, "seams_x": [112]}
			),
			# the gun house on the middle deck
			plate([72, 50, 72, 40, 76, 36, 94, 36, 96, 40, 96, 50], {"seed": 63, "step": 1}),
			# the bow sponson
			plate([12, 84, 28, 80, 40, 80, 40, 98, 24, 98, 12, 94], {"cast": true, "seed": 55}),
		],
		"details":
		[
			{"kind": "hatch", "rect": Rect2i(58, 78, 13, 10)},
			{"kind": "hatch", "rect": Rect2i(186, 78, 14, 10)},
			{"kind": "hatch", "rect": Rect2i(100, 53, 12, 8)},
			{"kind": "access", "rect": Rect2i(134, 77, 15, 11)},
			{"kind": "access", "rect": Rect2i(202, 77, 28, 11)},
			{"kind": "access", "rect": Rect2i(242, 77, 24, 11)},
			{"kind": "access", "rect": Rect2i(134, 52, 56, 9)},
			{"kind": "louvre", "rect": Rect2i(268, 78, 20, 3)},
			{"kind": "louvre", "rect": Rect2i(206, 94, 22, 3)},
			{"kind": "vent", "at": Vector2i(200, 56)},
			{"kind": "rail", "a": Vector2i(56, 66), "b": Vector2i(248, 66), "drop": 6, "every": 12},
			{"kind": "stack", "x": 240, "y0": 14, "y1": 37},
			{"kind": "stack", "x": 254, "y0": 20, "y1": 37},
			{"kind": "soot", "rect": Rect2i(232, 38, 30, 10)},
			{"kind": "cable", "a": Vector2i(160, 92), "b": Vector2i(202, 92)},
			{"kind": "box", "rect": Rect2i(164, 96, 22, 8)},
			{"kind": "links", "a": Vector2(192, 101), "b": Vector2(228, 101), "n": 6},
			{"kind": "antenna", "at": Vector2i(248, 36), "h": 30},
		],
		"rivets":
		[
			[14, 288, 109],
			[12, 290, 121],
			[52, 148, 92],
			[84, 130, 57],
			[194, 224, 57],
			[50, 290, 101],
			[160, 240, 84],
		],
		"turret_parts":
		[
			plate(
				[112, 50, 112, 28, 126, 14, 200, 14, 216, 30, 220, 50],
				{"seams_x": [150, 186], "seams_y": [30], "row_weld": false, "seed": 56}
			),
			plate([96, 18, 112, 14, 114, 44, 96, 40], {"cast": true, "seed": 57}),
			plate([162, 14, 164, 2, 186, 2, 188, 14], {"seed": 58}),
			plate([216, 26, 232, 26, 232, 46, 219, 46], {"seed": 64, "paint": 1, "step": -1}),
		],
		"turret_details":
		[
			{"kind": "mark", "at": Vector2i(140, 32), "size": 9},
			{"kind": "digits", "at": Vector2i(156, 34), "text": "808", "tall": 7},
			{"kind": "hatch", "rect": Rect2i(192, 33, 14, 10)},
			{"kind": "vent", "at": Vector2i(206, 26)},
			{"kind": "access", "rect": Rect2i(116, 31, 22, 16)},
			{"kind": "bar", "at": Vector2i(122, 28), "w": 24},
		],
		"turret_rivets":
		[[100, 110, 22], [100, 110, 36], [142, 186, 46], [150, 184, 18], [218, 230, 30]],
		"pivot_x": 165.0,
		"slits":
		[
			[18, 96, 4, 0],
			[66, 56, 4, 0],
			[124, 22, 4, 1],
			[170, 6, 4, 1]
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
