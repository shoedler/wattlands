extends SceneTree
# Kit preview: planes recomposited at the reference framing, the 3-rider tank on the road, crew sprites in rooms.
const OUT := "res://assets/tank/v2/"


func blit(dst: Image, src: Image, pos: Vector2i) -> void:
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), pos)


func _init() -> void:
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "kit.json"))
	var comp := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	comp.fill(Color(0, 0, 0, 1))
	for p in kit.planes:
		if p.name == "foreground":
			continue
		blit(comp, Image.load_from_file(OUT + p.file), Vector2i(0, int(p.y0)))
	var v: Dictionary = kit.tank.variants.tank_3rider
	var tpos := Vector2i(15, 107)
	var tank := Image.load_from_file(OUT + v.file)
	blit(comp, tank, tpos)
	# crew: [pose, frame, room id, x offset in room, mirror]
	var crew := [
		["stoker", 2, "diesel", 2, false], ["engineer", 0, "diesel", 60, false], ["loader", 1, "steam", 10, false],
		["tech", 1, "dynamo", 22, false], ["gunner", 0, "turret_drive", 30, false],
		["loader", 3, "quarters", 50, true],
	]
	for c in crew:
		var img := Image.load_from_file(OUT + "crew_frames/%s_%d.png" % [c[0], c[1]])
		if c[4]:
			img.flip_x()
		for r in v.rooms:
			if r.id == c[2]:
				var x := tpos.x + int(r.rect[0]) + int(c[3])
				var y := tpos.y + int(r.floor_y) - 14
				blit(comp, img, Vector2i(x, y))
	var cmd := Image.load_from_file(OUT + "crew_frames/commander_0.png")
	var feet: Array = v.anchors.turret_roof_commander_feet
	blit(comp, cmd, tpos + Vector2i(int(feet[0]) - 4, int(feet[1]) - 13))
	blit(comp, Image.load_from_file(OUT + "plane_foreground.png"), Vector2i(0, 344))
	comp.save_png(OUT + "kit_preview.png")
	var z := comp.get_region(Rect2i(20, 170, 480, 190))
	z.resize(960, 380, Image.INTERPOLATE_NEAREST)
	z.save_png("res://build/v2/view/kit_preview_zoom.png")
	quit()
