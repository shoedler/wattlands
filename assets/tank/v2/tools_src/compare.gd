extends SceneTree
# args: reference.webp mock_1920x1080.png out.png
# Left: the reference at the 960x540 framing (x*15/17, y*15/17+2). Right: the mock frame at 960x540.
# Below: the tank region (x 0..500, y 96..366 at 960) of both at 2x.

var F = load("res://build/v2/font.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var ref := Image.load_from_file(a[0])
	ref.convert(Image.FORMAT_RGBA8)
	ref.resize(960, 536, Image.INTERPOLATE_LANCZOS)
	var r960 := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	r960.blit_rect(ref, Rect2i(0, 0, 960, 536), Vector2i(0, 2))
	r960.blit_rect(ref, Rect2i(0, 0, 960, 2), Vector2i(0, 0))
	r960.blit_rect(ref, Rect2i(0, 534, 960, 2), Vector2i(0, 538))
	var mock := Image.load_from_file(a[1])
	mock.convert(Image.FORMAT_RGBA8)
	mock.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	var crop := Rect2i(0, 96, 500, 270)
	var out := Image.create(1920 + 30, 540 + 2 * 270 + 70, false, Image.FORMAT_RGBA8)
	out.fill(Color8(14, 14, 16))
	F.draw(out, 6, 4, "REFERENCE (960X540 FRAMING)", Color8(220, 210, 180), 2)
	F.draw(out, 990, 4, "MOCK: IN-ENGINE FRAME (TOOLS/SCREENSHOT, HUD INCLUDED), 960X540", Color8(220, 210, 180), 2)
	out.blit_rect(r960, Rect2i(0, 0, 960, 540), Vector2i(0, 20))
	out.blit_rect(mock, Rect2i(0, 0, 960, 540), Vector2i(990, 20))
	var y2 := 20 + 540 + 26
	F.draw(out, 6, y2 - 18, "REFERENCE TANK, 2X", Color8(220, 210, 180), 2)
	F.draw(out, 990, y2 - 18, "MOCK TANK, 2X (STAR AND A17 LEFT OUT: NO NATIONAL MARKINGS OR TEXT)", Color8(220, 210, 180), 2)
	var rc := r960.get_region(crop)
	rc.resize(crop.size.x * 2, crop.size.y * 2, Image.INTERPOLATE_NEAREST)
	var full := Image.load_from_file(a[1])
	full.convert(Image.FORMAT_RGBA8)
	var mc := full.get_region(Rect2i(crop.position * 2, crop.size * 2))
	out.blit_rect(rc, Rect2i(Vector2i.ZERO, rc.get_size()), Vector2i(0, y2))
	out.blit_rect(mc, Rect2i(Vector2i.ZERO, mc.get_size()), Vector2i(990, y2))
	out.save_png(a[2])
	quit()
