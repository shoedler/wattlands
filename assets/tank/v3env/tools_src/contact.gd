extends SceneTree
# MOCK: a contact sheet of review frames (Image API only). Labels in the HUD's own stencil face
# (TankHudFont's glyph grid, scaled 2x).
#   tools/godot.sh --headless --path . -s <this> -- --out=<png> --cols=<n> --thumb=<w> <png>|<label>[|x,y,w,h] ...

const BG := Color(0.07, 0.06, 0.05)
const INK := Color(0.91, 0.86, 0.75)
const GAP := 12

var glyphs: Image
var chars: Array[String]


func _init() -> void:
	glyphs = TankHudFont.text_image()
	chars = TankHudFont.chars()
	var out := ""
	var cols := 4
	var tw := 480
	var items: Array = []
	var title := ""
	var thumb_h := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cols="):
			cols = int(a.substr(7))
		elif a.begins_with("--thumb="):
			tw = int(a.substr(8))
		elif a.begins_with("--thumbh="):
			thumb_h = int(a.substr(9))
		elif a.begins_with("--title="):
			title = a.substr(8)
		else:
			items.append(a.split("|"))
	var th := thumb_h if thumb_h > 0 else int(tw * 9 / 16)
	var lab_h := 26
	var rows := ceili(float(items.size()) / cols)
	var head := 40 if title != "" else 0
	var w := cols * tw + (cols + 1) * GAP
	var h := head + rows * (th + lab_h) + (rows + 1) * GAP
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	if title != "":
		_text(sheet, GAP, GAP, title, 3)
	for i in items.size():
		var it: Array = items[i]
		var img := Image.load_from_file(ProjectSettings.globalize_path(str(it[0])))
		if img == null or img.is_empty():
			push_warning("contact: cannot read %s" % it[0])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var interp := Image.INTERPOLATE_LANCZOS
		if it.size() > 2:
			# a 16:9 region "x,y,w,h" of the frame, blown up with nearest filtering
			var r := str(it[2]).split(",")
			var rr := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
			rr = rr.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img = img.get_region(rr)
			interp = Image.INTERPOLATE_NEAREST
		# fit inside the thumb, aspect kept (letterboxed on the sheet's background)
		var k := minf(float(tw) / img.get_width(), float(th) / img.get_height())
		var sw := maxi(int(img.get_width() * k), 1)
		var sh := maxi(int(img.get_height() * k), 1)
		img.resize(sw, sh, interp)
		var x := GAP + (i % cols) * (tw + GAP)
		var y := head + GAP + (i / cols) * (th + lab_h + GAP)
		sheet.blit_rect(img, Rect2i(0, 0, sw, sh), Vector2i(x + (tw - sw) / 2, y + (th - sh) / 2))
		_text(sheet, x, y + th + 6, str(it[1]) if it.size() > 1 else "", 2)
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("contact: %s (%dx%d, %d frames)" % [out, w, h, items.size()])
	quit()


func _text(img: Image, x: int, y: int, s: String, k: int) -> void:
	var cx := x
	for ch in s:
		var idx := chars.find(ch)
		if idx < 0:
			cx += 3 * k
			continue
		var gx := (idx % TankHudFont.COLUMNS) * TankHudFont.CELL.x
		var gy := (idx / TankHudFont.COLUMNS) * TankHudFont.CELL.y
		for yy in TankHudFont.CELL.y:
			for xx in TankHudFont.CELL.x:
				if glyphs.get_pixel(gx + xx, gy + yy).a > 0.5:
					img.fill_rect(Rect2i(cx + xx * k, y + yy * k, k, k), INK)
		cx += TankHudFont.CELL.x * k
