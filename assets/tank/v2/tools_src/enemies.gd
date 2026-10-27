extends SceneTree
# Enemy tanks in the kit's style: closed hulls (the cutaway rooms plated over with the turret's riveted
# plates), darker grey-green paint, facing left. Writes assets/tank/v2/enemies/*.png + a sheet.

var L = load("res://build/v2/lib.gd")
var F = load("res://build/v2/font.gd")
const KIT := "res://assets/tank/v2/"
const OUT := "res://assets/tank/v2/enemies/"
const BUILD := "res://build/v2/"

var kit: Dictionary = {}
var plate: Image = null


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	kit = JSON.parse_string(FileAccess.get_file_as_string(KIT + "kit.json"))
	var tb := Image.load_from_file(BUILD + "turret_body.png")
	tb.convert(Image.FORMAT_RGBA8)
	plate = tb.get_region(Rect2i(206, 94, 136, 30))
	var out := {}
	# light: the 1-rider hull, no turret, no antenna (short, low)
	var t1 := closed("tank_1rider")
	var light := t1.get_region(Rect2i(0, 128, 366, 112))
	light = finish(light, 0.40, false)
	add_cupola(light)
	out["light"] = light
	# medium: the 1-rider with its turret (taller)
	var med := t1.get_region(Rect2i(0, 60, 380, 180))
	out["medium"] = finish(med, 0.46, false)
	# destroyer: the 2-rider hull, low casemate, long gun kept from the turret band
	var t2 := closed("tank_2rider")
	var des := t2.get_region(Rect2i(0, 100, 420, 140))
	out["destroyer"] = finish(des, 0.40, false)
	# heavy: the 3-rider, long, twin bogies
	var t3 := closed("tank_3rider")
	var hv := t3.get_region(Rect2i(0, 60, 480, 180))
	out["heavy"] = finish(hv, 0.44, false)
	# dug-in: a turret behind sandbags
	out["dugin"] = dugin()
	# Behemoth: the 3-rider closed, scaled up and darkened (the view draws it 1.0x, partly off screen)
	var bh := t3.get_region(Rect2i(0, 0, 480, 240))
	out["behemoth"] = finish(bh, 1.30, true)
	var sheet := Image.create(1100, 640, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(22, 24, 26))
	F.draw(sheet, 8, 6, "ENEMIES V2 MOCK (1X, FACING LEFT): LIGHT, MEDIUM, DESTROYER, HEAVY, DUG-IN, BEHEMOTH", Color8(200, 190, 170))
	var x := 10
	var y := 30
	for k: String in ["light", "medium", "destroyer", "heavy", "dugin"]:
		var im: Image = out[k]
		im.save_png(OUT + "%s.png" % k)
		F.draw(sheet, x, y, "%s %dX%d" % [k, im.get_width(), im.get_height()], Color8(160, 150, 130))
		sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, y + 10))
		x += im.get_width() + 20
		if x > 800:
			x = 10
			y += 130
	var b: Image = out["behemoth"]
	b.save_png(OUT + "behemoth.png")
	F.draw(sheet, 10, 300, "BEHEMOTH %dX%d" % [b.get_width(), b.get_height()], Color8(160, 150, 130))
	sheet.blend_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(10, 310))
	sheet.save_png(BUILD + "enemies_sheet.png")
	print("enemies: ", out.keys())
	quit()


# The variant image with every room plated over.
func closed(variant: String) -> Image:
	var img := Image.load_from_file(KIT + variant + ".png")
	img.convert(Image.FORMAT_RGBA8)
	var v: Dictionary = kit["tank"]["variants"][variant]
	for room: Dictionary in v["rooms"]:
		var r: Array = room["rect"]
		var rr := Rect2i(int(r[0]) - 1, int(r[1]) - 2, int(r[2]) + 2, int(r[3]) + 2)
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				if img.get_pixel(x, y).a < 0.5:
					continue
				var p := plate.get_pixel(posmod(x * 1, plate.get_width()), posmod(y, plate.get_height()))
				img.set_pixel(x, y, p.darkened(0.12))
	# the gaps between rooms (ladders, bulkhead lamps) dimmed so no lit interior shows
	return img


# Grey-green enemy paint: luminance with a cold olive tint, darker; flipped to face left.
func finish(src: Image, scale: float, boss: bool) -> Image:
	var img: Image = src.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
			# kill the warm lamp highlights (bright warm pixels become plate grey)
			l = minf(l, 0.5)
			l = pow(l, 0.85)
			var k := 1.10 if not boss else 0.78
			var col := Color(l * 0.86 * k, l * 1.0 * k, l * 0.84 * k, c.a)
			img.set_pixel(x, y, col)
	img.flip_x()
	var nw := maxi(1, roundi(w * scale))
	var nh := maxi(1, roundi(h * scale))
	var out: Image = L.resize_pm(img, nw, nh, Image.INTERPOLATE_LANCZOS)
	# trim empty rows/columns
	var used := out.get_used_rect()
	out = out.get_region(used)
	# a cold rim on the top edges (moonlight) so the dark hulls read against the night
	var ow := out.get_width()
	var oh := out.get_height()
	var src2: Image = out.duplicate()
	for y in range(1, oh):
		for x in ow:
			var c2 := src2.get_pixel(x, y)
			if c2.a > 0.5 and src2.get_pixel(x, y - 1).a < 0.3:
				out.set_pixel(x, y, c2.lerp(Color(0.62, 0.68, 0.64, c2.a), 0.55))
	return out


func add_cupola(img: Image) -> void:
	# a small hatch cupola on the light tank's roof
	var used := img.get_used_rect()
	var cx := used.position.x + int(used.size.x * 0.55)
	var top := used.position.y
	var c := Color8(52, 58, 50)
	for y in range(top, top + 3):
		for x in range(cx - 4, cx + 5):
			if y >= 0:
				img.set_pixel(x, y, c if y > top else c.lightened(0.25))


func dugin() -> Image:
	var tb := Image.load_from_file(BUILD + "turret_body.png")
	tb.convert(Image.FORMAT_RGBA8)
	var bar := Image.load_from_file(KIT + "turret_barrel.png")
	bar.convert(Image.FORMAT_RGBA8)
	var t := Image.create(480, 240, false, Image.FORMAT_RGBA8)
	t.fill(Color(0, 0, 0, 0))
	t.blend_rect(tb, Rect2i(0, 0, 480, 240), Vector2i.ZERO)
	t.blend_rect(bar, Rect2i(0, 0, 480, 240), Vector2i.ZERO)
	# turret + barrel only (no antenna): rows 84..134, from the crate's right edge
	var tur := t.get_region(Rect2i(196, 84, 270, 50))
	var g := finish(tur, 0.38, false)
	var w := g.get_width() + 10
	var h := g.get_height() + 9
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.blend_rect(g, Rect2i(Vector2i.ZERO, g.get_size()), Vector2i(4, 2))
	# a sandbag berm in front: rows of rounded bags
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var berm_top := h - 9
	for row in 2:
		var y0 := berm_top + row * 4
		var x := 2 - row * 2 + (row % 2) * 3
		while x < w - 1:
			var bw := 6 + rng.randi_range(0, 2)
			var base := Color8(64, 60, 46).darkened(0.12 * row + rng.randf() * 0.15)
			for yy in 4:
				for xx in bw:
					var px := x + xx
					var py := y0 + yy
					if px < 0 or px >= w or py >= h:
						continue
					if (xx == 0 or xx == bw - 1) and (yy == 0 or yy == 3):
						continue
					var col := base.lightened(0.18) if yy == 0 else (base.darkened(0.4) if yy == 3 else base)
					img.set_pixel(px, py, col)
			x += bw
	return img
