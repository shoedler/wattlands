extends SceneTree
# Writes assets/tank/v2/kit.json: planes, tank variants with rooms + anchors (sprite px at 960x540 scale),
# module cuts, crew frames. All tank coordinates are measured in the 1088x608 reference and mapped here.

const OUT := "res://assets/tank/v2/"
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
	var planes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://build/v2/planes.json"))
	for pl in planes.planes:
		for k in pl:
			if typeof(pl[k]) == TYPE_FLOAT and pl[k] == floor(pl[k]) and k != "parallax":
				pl[k] = int(pl[k])
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
			"file": name + ".png", "size": [img.get_width(), img.get_height()],
			"hull_length_px": snappedf((503.0 + d) * S, 1.0),
			"place_at_reference_framing": [15, 107],
			"turret_scale": v.ts,
			"rooms": rooms, "anchors": anchors,
		}
	var crew := {}
	for f in DirAccess.get_files_at(OUT + "crew_frames"):
		if not f.ends_with(".png"):
			continue
		var pose := f.get_basename().rsplit("_", true, 1)[0]
		if not crew.has(pose):
			crew[pose] = []
		crew[pose].append("crew_frames/" + f)
	for k in crew:
		crew[k].sort()
	var kit := {
		"version": "v2-1",
		"note": "Mock asset kit for owner approval, built from the reference image only (no fal). 960x540 art px.",
		"art_resolution": [960, 540],
		"reference_to_art": {"scale": 15.0 / 17.0, "offset_y": 2,
			"note": "x960 = x1088 * 15/17, y540 = y608 * 15/17 + 2 (1088x608 -> 960x536, edge rows repeated to 540)"},
		"plate": {"file": "plate_full.png",
			"note": "reference without tank, beams, smoke and turret crew; tank area filled by quilting tank-free bands"},
		"planes": planes.planes,
		"planes_note": "Back to front: sky, mountains, cliff_lake, forest, [tank on road], road, foreground. "
			+ "y0/y1 = rows of the 960x540 frame the plane image covers. parallax = scroll factor vs the road (1.0). "
			+ "Blur is baked (box radius x3 passes ~ gaussian sigma). Wide files are 1920 px seamless tiles "
			+ "(sky/mountains mirrored, forest/road/foreground quilted from calm cut points; the forest wide strip "
			+ "has a level tree-top fade). cliff_lake is a single landmark piece (alpha 0 left of x~560).",
		"tank": {
			"source": "tank_citadel.png (= tank_3rider.png), cut from the reference, star and A17 painted out, "
				+ "crew removed from rooms and turret roof, beams/smoke/headlight glow removed",
			"parts": {"hull_3rider": "hull_3rider.png", "turret_body": "turret_body.png",
				"turret_barrel": "turret_barrel.png",
				"note": "parts share the tank_3rider frame (480x240): overlay at the same origin"},
			"modules": {
				"note": "reference px. Hull layers: upper (y<310: roof + upper deck), lower (310..352: lower deck), "
					+ "running gear (y>=352, rebuilt per length by removing/duplicating 34 px wheel periods and "
					+ "resampling). Cuts sit at bulkheads; seams cross-fade 4 px.",
				"rear": "x 17..188 upper / 17..256 lower (rear plate, engine room, ladder 1)",
				"middle_steam": "lower 256..332 (ladder 2 + shell rack)",
				"middle_dynamo": "lower 332..386 (generator room)",
				"middle_upper_bays": "upper 188..264 (desk bays), 300..385 turret-drive room",
				"front": "x 386..561 (front rooms, glacis, bow guns, headlight, sprocket)",
				"turret": "x 188..534 y 118..263, scaled 0.85 for 1 rider",
				"running_gear_period_ref_px": 34,
			},
			"variants": variants,
		},
		"crew": {
			"sheet": "crew_sheet.png", "cell": [16, 14], "facing": "right", "feet_row": 13,
			"figure_height_px": "11-13", "frames": crew,
			"commander_lens_px": {"0": [11, 5], "1": [10, 3], "2": [11, 7]},
			"commander_beam_angle_deg": {"0": 0, "1": -35, "2": 25},
			"note": "the reference crew are ~20 px tall at 960 scale; these follow the 10-12 px spec",
		},
	}
	var f := FileAccess.open(OUT + "kit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(kit, "  ", false))
	f.close()
	print("kit.json written")
	quit()
