extends GutTest
## The kit's turret side after artfix.gd (assets/tank/v2/tools_src): the pistol port is a plain
## round plug, a dark disc in a brass rim (one highlight pixel) with no cross or centre mark (the critique's N6: a ring
## with a cross reads as a sight or a roundel), on every variant.

## artfix.gd's numbers: the 3-rider's turret pivot and the port's patch measured on it.
const TP3 := Vector2(249.5, 127.0)
const PORT := Rect2i(228, 98, 14, 15)


func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.55 + c.b * 0.15


func test_the_pistol_port_is_a_plain_round_plug_on_every_variant() -> void:
	var kit := TankKit.load_manifest()
	for vn: String in TankKit.VARIANTS:
		var v: Dictionary = kit["tank"]["variants"][vn]
		var tp := TankKit.vec(v["anchors"]["turret_pivot"])
		var sc := float(v.get("turret_scale", 1.0))
		var p := tp + (Vector2(PORT.position) - TP3) * sc
		var e := tp + (Vector2(PORT.end) - TP3) * sc
		var r := Rect2i(Vector2i(p.round()), Vector2i((e - p).round()))
		var c := Vector2i(r.position.x + r.size.x / 2, r.position.y + roundi(6 * sc))
		var img := Image.load_from_file(
			ProjectSettings.globalize_path(TankKit.DIR + str(v["file"]))
		)
		img.convert(Image.FORMAT_RGBA8)
		var rim := 0.0
		for o: Vector2i in [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]:
			rim += _lum(img.get_pixelv(c + o))
		rim /= 4.0
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == -1 and oy == -1:
					continue  # the one highlight pixel
				var l := _lum(img.get_pixelv(c + Vector2i(ox, oy)))
				assert_lt(l, rim * 0.6, "%s: the plug's face is dark at %d,%d" % [vn, ox, oy])
		# No arm of a cross reaching out of the plug.
		for o2: Vector2i in [Vector2i(0, -3), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(3, 0)]:
			assert_lt(_lum(img.get_pixelv(c + o2)), rim, "%s: nothing sticks out at %s" % [vn, o2])
