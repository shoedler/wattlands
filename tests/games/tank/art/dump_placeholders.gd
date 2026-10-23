extends SceneTree
## Renders the procedural placeholder art (TankPlaceholderArt) to PNG contact sheets for a look.
## Not a test and not part of any gate; it writes only where you point it, never into assets/.
##
##   tools/godot.sh --headless --path . -s tests/games/tank/art/dump_placeholders.gd -- --out=<dir> [--scale=3]
##
## One PNG per group (hulls.png, rooms.png, ...) with the sprites on a flat olive ground at
## <scale>x, nearest filtering, and sprites/<id>.png at 1x for each id.

const GROUPS := {
	"hulls": ["hull_bulwark", "hull_rampart", "hull_citadel"],
	"turrets": ["turret_bulwark", "turret_rampart", "turret_citadel", "turret_secondary"],
	"rooms": ["room_bulwark", "room_diesel", "room_dynamo", "room_steam"],
	"machinery":
	[
		"diesel_block",
		"flywheel_large",
		"flywheel_small",
		"gear_large",
		"gear_medium",
		"gearbox",
		"dynamo_housing",
		"dynamo_armature",
		"spark",
		"boiler",
		"firebox",
		"firebox_flame",
		"governor",
		"steam_puff",
		"shell_rack"
	],
	"running": ["road_wheel", "drive_sprocket", "idler_wheel"],
	"enemies": ["enemy_light", "enemy_medium", "enemy_heavy", "enemy_destroyer", "enemy_dugin"],
	"boss": ["boss_hull", "boss_turret", "boss_turret_broken", "boss_bogie", "boss_bogie_broken"],
	"props":
	[
		"prop_tank_traps",
		"prop_wire",
		"prop_wreck_barricade",
		"prop_crater",
		"prop_rubble",
		"depot_gate"
	],
	"effects":
	[
		"muzzle_flash",
		"explosion_large",
		"explosion_small",
		"smoke_puff",
		"fire_small",
		"dirt_spray"
	],
	"sky_ground": ["bg_sky", "bg_ground", "fg_debris"],
	"strips1": ["bg_hills_far", "bg_fields_near", "bg_village_near"],
	"strips2": ["bg_quarry_near", "bg_town_near", "bg_depot_near"],
	"picker": ["picker_card"],
}
const GROUND := Color("#6e7f5a")


func _initialize() -> void:
	var args: Dictionary = CmdLine.parse(OS.get_cmdline_user_args())
	var out_dir := str(_last(args, "out"))
	if out_dir == "" or out_dir == "true":
		printerr("dump_placeholders: --out=<dir> is required")
		quit(2)
		return
	var scale := maxi(int(_last(args, "scale", "3")), 1)
	var only: Array[String] = []
	for v: Variant in args.get("only", []):
		for id: String in str(v).split(",", false):
			only.append(id.strip_edges())
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("sprites"))
	var t0 := Time.get_ticks_msec()
	for group: String in GROUPS:
		var ids: Array = GROUPS[group]
		if not only.is_empty():
			ids = ids.filter(func(i: String) -> bool: return only.has(i))
		if ids.is_empty():
			continue
		_sheet(out_dir, group, ids, scale)
	print("dump_placeholders: done in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _sheet(out_dir: String, group: String, ids: Array, scale: int) -> void:
	var gap := 8
	var imgs: Array[Image] = []
	var total_h := gap
	var max_w := 0
	for id: String in ids:
		var t0 := Time.get_ticks_usec()
		var img := TankPlaceholderArt.placeholder_image(id)
		print(
			(
				"  %s %dx%d %d ms"
				% [id, img.get_width(), img.get_height(), (Time.get_ticks_usec() - t0) / 1000]
			)
		)
		img.save_png(out_dir.path_join("sprites").path_join(id + ".png"))
		imgs.append(img)
		total_h += img.get_height() * scale + gap
		max_w = maxi(max_w, img.get_width() * scale)
	var sheet := Image.create(max_w + gap * 2, total_h, false, Image.FORMAT_RGBA8)
	sheet.fill(GROUND)
	var y := gap
	for img in imgs:
		var big := img.duplicate() as Image
		big.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(big, Rect2i(0, 0, big.get_width(), big.get_height()), Vector2i(gap, y))
		y += big.get_height() + gap
	sheet.save_png(out_dir.path_join(group + ".png"))


func _last(args: Dictionary, key: String, fallback: String = "") -> String:
	var v: Variant = args.get(key, [])
	if v is Array and not (v as Array).is_empty():
		return str((v as Array).back())
	return fallback
