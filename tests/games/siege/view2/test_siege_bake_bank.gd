extends GutTest
## The v2 bake (assets/siege/bake/, src/games/siege/art/bake.mjs) as SiegeBakeBank reads it:
## the manifest, the frame rects, the depth encodings, the anchors, the key-ramp recolour and
## the generator version.

const BAKE_MJS := "res://src/games/siege/art/bake.mjs"
const MAP := "res://content/siege/maps/rotae.json"

var bank: SiegeBakeBank = null
var path: SiegePath = null


func before_all() -> void:
	bank = SiegeBakeBank.shared()
	path = SiegePath.load_file(MAP)


func test_manifest_loads() -> void:
	assert_true(bank.ok, "bank loads: %s" % bank.error)
	assert_eq(bank.manifest.get("art_size"), [960.0, 540.0])
	# the design frame and the flex canvas's margin round it
	assert_eq(bank.world_texture.get_size(), Vector2(1920, 1084))
	assert_eq(bank.world_depth_image.get_size(), Vector2i(1920, 1084))
	assert_gt(bank.atlases.size(), 0)
	assert_eq(bank.atlases.size(), bank.depth_atlases.size())
	for name in [
		"wheel_0",
		"wheel_3",
		"route_2_4",
		"sshaft_3",
		"ballista",
		"onager",
		"arrows",
		"mine",
		"gate"
	]:
		assert_true(bank.has_part(name), name)
	for name in [
		"spear", "shield", "chariot", "ram", "tower", "tower_dock", "walker", "px", "fx_dust"
	]:
		assert_true(bank.has_part(name), name)


func test_bake_check_passes() -> void:
	# the committed manifest matches the generator's BAKE_VERSION (bake.mjs --check)
	var src := FileAccess.get_file_as_string(BAKE_MJS)
	var re := RegEx.create_from_string("export const BAKE_VERSION = (\\d+);")
	var m := re.search(src)
	assert_not_null(m, "BAKE_VERSION in bake.mjs")
	if m != null:
		assert_eq(bank.bake_version, int(m.get_string(1)))
	assert_eq(str(bank.manifest.get("generator")), "src/games/siege/art/bake.mjs")


func test_every_frame_rect_is_inside_its_atlas() -> void:
	var frames := 0
	var bad := 0
	for name in bank.part_names():
		for i in bank.frame_count(name):
			var f := bank.frame(name, i)
			if int(f["atlas"]) < 0:
				continue
			frames += 1
			var size := Vector2i(bank.atlases[int(f["atlas"])].get_size())
			var r: Rect2i = f["rect"]
			if (
				r.position.x < 0
				or r.position.y < 0
				or r.end.x > size.x
				or r.end.y > size.y
				or r.size.x < 1
			):
				bad += 1
			if Vector2i(bank.depth_atlases[int(f["atlas"])].get_size()) != size:
				bad += 1
	assert_gt(frames, 800, "frames")
	assert_eq(bad, 0, "frames outside their atlas")


func test_frame_counts_follow_the_layouts() -> void:
	for s in 4:
		var lay := bank.layout("wheel_%d" % s)
		var n := roundi(float(lay["period_deg"]) / float(lay["step_deg"]))
		assert_eq(bank.frame_count("wheel_%d" % s), n, "wheel %d" % s)
		assert_eq(bank.frame_count("walker_%d" % s), 12)
		assert_eq(bank.anchors("walker_%d" % s).size(), 3)
	assert_eq(bank.frame_count("ballista"), 16 * 4)
	assert_eq(bank.frame_count("onager"), 16 * 12)
	assert_eq(bank.frame_count("arrows"), 16 * 8)
	assert_eq(bank.frame_count("gate"), 4)
	assert_eq(bank.frame_count("spear"), 8)
	assert_eq(bank.frame_count("chariot"), 16)
	assert_eq(bank.frame_count("ram"), 8)
	for i in 4:
		for j in 5:
			assert_eq(bank.frame_count("route_%d_%d" % [i, j]), 1)


func test_world_depth_encoding_round_trips() -> void:
	for d in [-399.0, -12.5, 0.0, 0.015625, 107.3, 431.9, 600.0]:
		var v := bank.encode_world_depth(d)
		assert_almost_eq(bank.decode_world_depth(v), d, 0.5 / bank.world_scale, "world %f" % d)
		var c := Color8(v >> 8, v & 255, 0)
		assert_eq(SiegeBakeBank.rg16(c), v)
	assert_lt(bank.decode_world_depth(0), -1.0e8, "0 is the sky")


func test_sprite_depth_encoding_round_trips() -> void:
	for rel in [-60.0, -2.5, 0.0, 0.004, 1.75, 33.3]:
		var v := bank.encode_sprite_depth(rel)
		assert_almost_eq(
			bank.decode_sprite_depth(v), rel, 0.5 / bank.sprite_scale, "sprite %f" % rel
		)


func test_modulate_packing_round_trips() -> void:
	var c := bank.pack_modulate(123.456, 7, 1.0, 0.5)
	assert_almost_eq(bank.decode_world_depth(c.r8 * 256 + c.g8), 123.456, 0.01)
	assert_eq(c.b8 >> 4, 7, "ramp row")
	assert_eq(c.b8 & 15, SiegeBakeBank.SHADE_LEVELS, "shade")
	assert_almost_eq(c.a, 0.5, 0.01)


func test_world_depth_matches_the_road() -> void:
	# the road's own surface is what the world depth holds along it (palms aside)
	var near := 0
	var n := 0
	var prog := 20.0
	while prog < path.moat_edge_m:
		var p := path.point_at(prog)
		var px := bank.art_pixel(p)
		if px.x >= 0 and px.y >= 0 and px.x < 960 and px.y < 540:
			n += 1
			if absf(bank.world_depth_at(px) - SiegeBakeBank.depth_of(p)) < 1.0:
				near += 1
		prog += 6.0
	assert_gt(n, 30)
	assert_gt(float(near) / n, 0.8, "road pixels at the road's depth: %d of %d" % [near, n])


func test_anchors_project_to_the_art_pixels() -> void:
	for s in 4:
		var a := bank.anchor("wheel_%d" % s)
		assert_almost_eq(a.distance_to(path.wheels[s]), 0.0, 0.01, "wheel %d hub" % s)
		var art := path.to_art(a)
		assert_eq(bank.art_pixel(a), Vector2i(floori(art.x), floori(art.y)))
		# the hub is inside every frame, and every frame hangs on the same art pixel
		for i in [0, 7, bank.frame_count("wheel_%d" % s) - 1]:
			var f := bank.frame("wheel_%d" % s, i)
			var r: Rect2i = f["rect"]
			var o: Vector2i = f["offset"]
			assert_true(
				o.x >= 0 and o.y >= 0 and o.x < r.size.x and o.y < r.size.y, "hub in frame %d" % i
			)
	for id in [1, 2, 3]:
		var name: String = ["", "ballista", "onager", "arrows"][id]
		var a := bank.anchor(name)
		var pivot := path.station_pos[id]
		assert_almost_eq(Vector2(a.x, a.y).distance_to(Vector2(pivot.x, pivot.y)), 0.0, 0.01, name)
	for pad in 4:
		var a := bank.anchor("scorpion_%d" % (pad + 1))
		assert_almost_eq(
			Vector2(a.x, a.y).distance_to(Vector2(path.pads[pad].x, path.pads[pad].y)), 0.0, 0.01
		)


func test_key_colors_map_to_each_slot_ramp() -> void:
	var rows := bank.ramp_rows
	assert_eq(rows.slice(0, 4), PackedStringArray(["slot0", "slot1", "slot2", "slot3"]))
	var ramps: Dictionary = bank.manifest["ramps"]
	for idx in bank.key_count:
		var key := bank.key_color(idx)
		assert_eq(bank.key_index(key), idx)
		for s in 4:
			var want: Array = ramps["slot%d" % s][idx]
			assert_eq(
				bank.recolor(key, s).to_rgba32(),
				Color8(int(want[0]), int(want[1]), int(want[2])).to_rgba32()
			)
	# a lit, unoutlined entry carries the slot's hue (Okabe-Ito orange, blue, yellow, green)
	var mid := 6 * 2
	var hues := [0.07, 0.56, 0.15, 0.45]
	for s in 4:
		var c := bank.recolor(bank.key_color(mid), s)
		var dh := absf(c.h - hues[s])
		assert_lt(minf(dh, 1.0 - dh), 0.06, "slot %d hue %f" % [s, c.h])
		assert_gt(c.s, 0.5, "slot %d stays saturated" % s)
	assert_eq(bank.key_index(Color8(250, 60, 250)), -1)
	assert_eq(bank.key_index(Color8(255, 5, 255)), -1)
	assert_eq(bank.recolor(Color8(120, 90, 60), 2), Color8(120, 90, 60), "other colours are kept")


func test_wheel_frames_carry_key_pixels_and_no_stray_magenta() -> void:
	var f := bank.frame("wheel_1", 0)
	var img := bank.atlas_image(int(f["atlas"]))
	assert_not_null(img)
	if img == null:
		return
	var r: Rect2i = f["rect"]
	var keys := 0
	var stray := 0
	for y in r.size.y:
		for x in r.size.x:
			var c := img.get_pixel(r.position.x + x, r.position.y + y)
			if c.a8 < 250:
				continue
			if bank.key_index(c) >= 0:
				keys += 1
			elif c.r8 >= 250 and c.b8 >= 250:
				stray += 1
	assert_gt(keys, 200, "rider-hue pixels in the key ramp")
	assert_eq(stray, 0)


func test_ramp_rows_for_parts() -> void:
	assert_eq(bank.ramp_row_for("onager", 2), 2)
	assert_eq(bank.ramp_rows[bank.ramp_row_for("onager", -1)], "wood_light")
	assert_eq(bank.ramp_rows[bank.ramp_row_for("ballista", -1)], "rope")
	assert_eq(bank.ramp_rows[bank.ramp_row_for("mark_0", -1)], "stone_dark")
	assert_eq(bank.ramp_rows[bank.ramp_row_for("wheel_0", -1)], "wood")
