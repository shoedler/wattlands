extends SceneTree
# Writes assets/tank/v2/kit.json, the kit's single manifest: planes, tank variants with rooms + anchors (sprite px
# at 960x540 scale), module cuts, crew frames (from crew20.gd's build/v2/crew20.json), enemies (measured
# muzzles), cards. All tank coordinates are measured in the 1088x608 reference and mapped here.

const OUT := "res://assets/tank/v2/"
const BUILD := "res://build/v2/"
## The planes the view draws (planes2.gd writes them).
const PLANES := [
	{"name": "far", "file": "planes2/far_wide.png", "y0": 0, "parallax": 0.04, "blur_box_radius": 0, "layer": "back"},
	{"name": "forest", "file": "planes2/forest_wide.png", "y0": 0, "parallax": 0.3, "blur_box_radius": 1, "layer": "back"},
	{"name": "road", "file": "planes2/road_wide.png", "y0": 312, "parallax": 1.0, "blur_box_radius": 0, "layer": "road"},
	{"name": "foreground", "file": "planes2/foreground_wide.png", "y0": 344, "parallax": 1.35, "blur_box_radius": 2,
		"layer": "front", "darken": 0.86},
]
## In-engine renders for the picker and the lobby's content cards (tests/games/tank/view/card_scene.gd).
const CARDS := {"picker": "picker_card.png", "card_mission": "card_mission.png", "card_drill": "card_drill.png",
	"card_roam": "card_roam.png"}
## The free-roam zones' near planes (zones.gd writes them; the forest zone keeps the forest plane).
const ZONE_PLANES := {
	"note": "Free roam (docs/games/tank.md 2.10, 3.1): the zone's near plane replaces the forest plane (the "
		+ "same frame, y0, parallax and blur) while the tank drives through it; the pine forest keeps the forest "
		+ "plane. Built by zones.gd from the kit's own planes (the forest's trees squashed into lower tree lines, "
		+ "the far plane's pale cliff as quarry rock) plus houses, haystacks, fences, reeds and a gantry in code.",
	"replaces": "forest",
	"lake": "planes2/zone_lake_wide.png",
	"village": "planes2/zone_village_wide.png",
	"quarry": "planes2/zone_quarry_wide.png",
	"meadow": "planes2/zone_meadow_wide.png",
}
## Which tank each variant is (docs/games/tank.md 2.2).
const TANK_IDS := {"tank_1rider": ["bulwark", 1], "tank_2rider": ["rampart", 2], "tank_3rider": ["citadel", 3],
	"tank_4rider": ["bastion", 4]}
const S := 15.0 / 17.0
const X0 := 17.0
const Y0 := 119.0
const Y_LOWER := 310.0
const TURRET_PIVOT := Vector2(300, 263)

# Reference-px features. layer: "u" = upper hull layer, "l" = lower layer / running gear, "t" = turret.
const ANCHORS := {
	"muzzle": [528, 250, "t"], "barrel_pivot": [414, 249, "t"], "turret_pivot": [300, 263, "t"],
	"antenna_tip": [232, 128, "t"], "turret_roof_commander_feet": [345, 216, "t"],
	"searchlight_turret_lens": [362, 199, "t"],
	"headlight": [539, 326, "l"], "running_light_red_front": [522, 308, "u"],
	"running_light_red_rear": [54, 273, "u"], "running_light_green_rear": [151, 249, "u"],
	"exhaust": [112, 268, "u"],
	"bow_gun_upper_muzzle": [496, 279, "u"], "bow_gun_upper_pivot": [467, 279, "u"],
	"bow_gun_lower_muzzle": [532, 295, "u"], "bow_gun_lower_pivot": [505, 294, "u"],
	"drive_sprocket_centre": [492, 356, "l"],
}
const WHEELS_X := [107, 136, 173, 208, 242, 278, 313, 346, 380, 412, 448]

const VARIANTS := {
	"tank_1rider": {"upper": ["cut", 262, 391], "lower": ["cut", 257, 386], "delta": -129, "tdx": -60, "ts": 0.85,
		"rooms": [
			["diesel", "engine", 130, 311, 255, 349, "l"],
			["front_machinery", "spare", 400, 316, 456, 349, "l"],
			["quarters", "crew", 148, 276, 262, 306, "u"],
			["upper_front", "spare", 391, 284, 420, 314, "u"],
		]},
	"tank_2rider": {"upper": ["cut", 188, 264], "lower": ["cut", 256, 332], "delta": -76, "tdx": -40, "ts": 1.0,
		"rooms": [
			["diesel", "engine", 130, 311, 255, 349, "l"],
			["dynamo", "engine", 332, 311, 386, 349, "l"],
			["front_machinery", "spare", 400, 316, 456, 349, "l"],
			["quarters", "crew", 148, 276, 296, 306, "u"],
			["turret_drive", "gunner", 300, 274, 385, 308, "u"],
			["upper_front", "spare", 391, 284, 420, 314, "u"],
		]},
	"tank_3rider": {"upper": [], "lower": [], "delta": 0, "tdx": 0, "ts": 1.0,
		"rooms": [
			["diesel", "engine", 130, 311, 255, 349, "l"],
			["steam", "engine", 256, 311, 332, 349, "l"],
			["dynamo", "engine", 332, 311, 386, 349, "l"],
			["front_machinery", "spare", 400, 316, 456, 349, "l"],
			["quarters", "crew", 148, 276, 296, 306, "u"],
			["turret_drive", "gunner", 300, 274, 385, 308, "u"],
			["upper_front", "spare", 391, 284, 420, 314, "u"],
		]},
	"tank_4rider": {"upper": ["dup", 189, 243], "lower": ["dup", 332, 386], "delta": 54, "tdx": 44, "ts": 1.0,
		"rooms": [
			["diesel", "engine", 130, 311, 255, 349, "l"],
			["steam", "engine", 256, 311, 332, 349, "l"],
			["dynamo", "engine", 332, 311, 386, 349, "l"],
			["arc", "engine", 386, 311, 440, 349, "l*"],
			["front_machinery", "spare", 400, 316, 456, 349, "l"],
			["quarters", "crew", 148, 276, 350, 306, "u*"],
			["turret_drive", "gunner", 300, 274, 385, 308, "u"],
			["upper_front", "spare", 391, 284, 420, 314, "u"],
		]},
}


func map_x(op: Array, x: float) -> float:
	if op.is_empty():
		return x
	if op[0] == "cut":
		var d: float = op[2] - op[1]
		if x >= op[2]:
			return x - d
		return minf(x, op[1])
	# dup: [a, b) copied in at b
	var d2: float = op[2] - op[1]
	return x + d2 if x >= op[2] else x


func to_sprite(p: Vector2) -> Array:
	return [snappedf((p.x - X0) * S, 0.5), snappedf((p.y - Y0) * S, 0.5)]


func map_pt(v: Dictionary, x: float, y: float, layer: String) -> Vector2:
	if layer == "t":
		var p := TURRET_PIVOT + (Vector2(x, y) - TURRET_PIVOT) * float(v.ts)
		return p + Vector2(float(v.tdx), 0)
	var op: Array = v.upper if layer == "u" else v.lower
	return Vector2(map_x(op, x), y)


func _init() -> void:
	var variants := {}
	for name in VARIANTS:
		var v: Dictionary = VARIANTS[name]
		var img := Image.load_from_file(OUT + name + ".png")
		var anchors := {}
		for a in ANCHORS:
			var spec: Array = ANCHORS[a]
			anchors[a] = to_sprite(map_pt(v, spec[0], spec[1], spec[2]))
		var d: float = v.delta
		var wheels := []
		# same mapping as assemble.gd rg_px: k wheel periods removed/duplicated at the seam, middle resampled
		var per := 34.0
		var seam := 312.0 - 120.0
		var mid := 455.0 - 120.0
		var k := roundf(absf(d) / per)
		var inter := mid + signf(d) * k * per
		var new_mid := mid + d
		for wx in WHEELS_X:
			var su := float(wx) - 120.0
			var us := []
			if d == 0.0 or su < 0.0:
				us = [su]
			elif d < 0.0:
				if su < seam:
					us = [su]
				elif su >= seam + k * per:
					us = [su - k * per]
			else:
				if su < seam + per:
					us = [su]
					if su >= seam:
						for j in range(1, int(k) + 1):
							us.append(su + j * per)
				else:
					us = [su + k * per]
			for u in us:
				var uf: float = u
				var nx: float = 120.0 + (uf * new_mid / inter if su >= 0.0 else uf)
				wheels.append(to_sprite(Vector2(nx, 366))[0])
		wheels.sort()
		anchors["road_wheel_line"] = {"y": to_sprite(Vector2(0, 366))[1], "x_from": wheels[0], "x_to": wheels[-1],
			"wheel_centres_x": wheels, "wheel_radius": 8, "ground_contact_y": to_sprite(Vector2(0, 383))[1]}
		anchors["drive_sprocket_radius"] = 18.5
		if name == "tank_4rider":
			anchors["searchlight_tower_lens"] = [123, 103]
		var rooms := []
		for r in v.rooms:
			var layer: String = r[6]
			var p0: Vector2
			var p1: Vector2
			if layer == "l*":
				# the inserted copy sits right after the original room
				p0 = Vector2(r[2], r[3])
				p1 = Vector2(r[4], r[5])
			elif layer == "u*":
				p0 = Vector2(r[2], r[3])
				p1 = Vector2(r[4], r[5])
			else:
				var op: Array = v.upper if layer == "u" else v.lower
				p0 = Vector2(map_x(op, r[2]), r[3])
				p1 = Vector2(map_x(op, r[4] - 0.01), r[5])
			var a0 := to_sprite(p0)
			var a1 := to_sprite(p1)
			var room := {"id": r[0], "role": r[1], "deck": "lower" if layer.begins_with("l") else "upper",
				"rect": [a0[0], a0[1], snappedf(a1[0] - a0[0], 0.5), snappedf(a1[1] - a0[1], 0.5)],
				"floor_y": a1[1]}
			if r[1] == "engine":
				room["engine"] = r[0]
				room["lamp_tint_slot"] = true
				room["icon_chip_at"] = [a0[0] + 3, a0[1] + 3]
			rooms.append(room)
		variants[name] = {
			"tank": TANK_IDS[name][0], "crew": TANK_IDS[name][1],
			"file": name + ".png", "size": [img.get_width(), img.get_height()],
			"hull_length_px": snappedf((503.0 + d) * S, 1.0),
			"place_at_reference_framing": [15, 107],
			"turret_scale": v.ts,
			"rooms": rooms, "anchors": anchors,
		}
	var crew: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BUILD + "crew20.json"))
	var kit := {
		"version": "v2-2",
		"note": "Diesel Domestiques v2 art kit (docs/games/tank.md 3), built from the reference image only (no fal), "
			+ "960x540 art px. The single manifest the view reads (TankKit). Regenerate with tools_src/regen.sh.",
		"art_resolution": [960, 540],
		"reference": {"file": "source/reference.webp", "scale": 15.0 / 17.0, "offset_y": 2,
			"note": "x960 = x1088 * 15/17, y540 = y608 * 15/17 + 2 (1088x608 -> 960x536, edge rows repeated to 540)"},
		"planes": PLANES,
		"planes_note": "Back to front: far (sky with the Milky Way, mountains, the pale cliff, the misty lake), forest, "
			+ "[the tank, enemies and props on the road], road, foreground. Each file is the reference's own 960 px cut "
			+ "plus its mirror (1920 px, seamless). y0 = the row of the 960x540 frame the plane's top sits on; "
			+ "parallax = scroll factor against the road (1.0). The tilt-shift blur is baked once by planes2.gd: "
			+ "blur_box_radius (two box passes); the reference already carries its own depth of field, so the far "
			+ "plane keeps it. darken = the factor baked into the foreground.",
		"zone_planes": ZONE_PLANES,
		"tank": {
			"source": "cut from the reference (tank.gd, tankfix.gd: the star and A17 painted out, crew, beams, smoke "
				+ "and headlight glow removed), split into modules at its bulkheads and assembled per crew size "
				+ "(assemble.gd). turret_barrel.png shares the 3-rider frame (480x240): the view erases each "
				+ "variant's baked barrel and draws this one at the gun's elevation.",
			"barrel": "turret_barrel.png",
			"modules": {
				"note": "reference px. Hull layers: upper (y<310: roof + upper deck), lower (310..352: lower deck), "
					+ "running gear (y>=352, rebuilt per length by removing/duplicating 34 px wheel periods and "
					+ "resampling). Cuts sit at bulkheads; seams cross-fade 4 px.",
				"rear": "x 17..188 upper / 17..256 lower (rear plate, engine room, ladder 1)",
				"middle_steam": "lower 256..332 (ladder 2 + shell rack)",
				"middle_dynamo": "lower 332..386 (generator room)",
				"middle_arc": "lower 332..386 copied in at 386 (the Bastion's arc-generator room)",
				"middle_upper_bays": "upper 188..264 (desk bays), 300..385 turret-drive room",
				"front": "x 386..561 (front rooms, glacis, bow guns, headlight, sprocket)",
				"turret": "x 188..534 y 118..263, scaled 0.85 for 1 rider",
				"running_gear_period_ref_px": 34,
			},
			"variants": variants,
		},
		"crew": crew,
		"enemies": _enemies(),
		"cards": CARDS,
	}
	var f := FileAccess.open(OUT + "kit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(kit, "  ", false))
	f.close()
	print("kit.json written")
	quit()


## Each enemy's file, size and muzzle (the leftmost opaque pixel in its upper 70 %: they face left).
func _enemies() -> Dictionary:
	var out := {}
	for k in ["light", "medium", "destroyer", "heavy", "dugin"]:
		var img := Image.load_from_file(OUT + "enemies/%s.png" % k)
		img.convert(Image.FORMAT_RGBA8)
		var muzzle := [0, 0]
		var found := false
		for x in img.get_width():
			for y in int(img.get_height() * 0.7):
				if img.get_pixel(x, y).a > 0.5:
					muzzle = [x, y]
					found = true
					break
			if found:
				break
		out[k] = {"file": "enemies/%s.png" % k, "size": [img.get_width(), img.get_height()], "muzzle": muzzle}
	var b := Image.load_from_file(OUT + "enemies/behemoth.png")
	out["behemoth"] = {
		"file": "enemies/behemoth.png", "size": [b.get_width(), b.get_height()], "muzzle": [16, 140],
		"bogies_at": [[0.25, 0.78], [0.47, 0.78], [0.69, 0.78]], "turret_at": [0.62, 0.3],
		"note": "muzzle: the main gun's left end; bogies_at / turret_at: fractions of the sprite (fires, hits)",
	}
	return out
