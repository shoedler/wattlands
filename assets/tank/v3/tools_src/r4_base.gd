extends SceneTree
## r4 base: the reference's tank (v2's 4-rider cut of it, 960 scale) at 0.9, re-pixelled.
##   prep:  build/v3mock/r4/s90.png (magick: Box 90% + a light unsharp) -> darkened hull, masked live
##          parts (running gear, barrel, bow-gun barrels), the crate repainted, plaques removed, the
##          hoist shaft and the breech glimpse cut -> prep.png
##   clean: q.png (magick: +dither -remap onto the curated palette) -> binary alpha, noise pixels
##          snapped to their neighbours, rivet highlights paired with a shadow, a hard outline, the
##          lamp spill round the rooms -> base.png
## Run through assets/tank/v3/tools_src/r4_base.sh.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Tank4 = preload("res://assets/tank/v3/tools_src/tank_r4.gd")
const Hull = preload("res://assets/tank/v3/tools_src/hull.gd")

const DIR := "res://build/v3mock/r4/"


func _init() -> void:
	var job := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "prep"
	if job == "prep":
		prep()
	else:
		clean()
	quit()


func _load(n: String) -> Image:
	var i := Image.load_from_file(ProjectSettings.globalize_path(DIR + n))
	i.convert(Image.FORMAT_RGBA8)
	return i


func _in_rooms(L: Dictionary, x: int, y: int) -> bool:
	for r: Rect2i in L["rooms_all"]:
		if r.has_point(Vector2i(x, y)):
			return true
	return false


func prep() -> void:
	var L := Tank4.layout()
	var img := _load("s90.png")
	var w := img.get_width()
	var h := img.get_height()
	# darken the hull strongly, keep the lit rooms bright
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.05:
				continue
			var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
			var f := lerpf(0.66, 1.0, smoothstep(0.3, 0.66, l))
			if _in_rooms(L, x, y):
				f = maxf(f, 0.92)
			img.set_pixel(x, y, Color(c.r * f, c.g * f, c.b * f * 0.96, c.a))
	# masks: the live parts are redrawn per frame
	var clear := Color(0, 0, 0, 0)
	var g: Dictionary = L["gear"]
	var skirt := int(g["skirt_y"])
	var sp: Dictionary = g["sprocket"]
	var spc: Vector2 = sp["c"]
	var spr := float(sp["r"]) + 7.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var m := y >= skirt
			# the rear wrap: below the line from the rear plate's foot down to the first wheel
			var rl: Array = g["rear_cut"]
			var a: Vector2 = rl[0]
			var b: Vector2 = rl[1]
			if y > a.y and x < a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y):
				m = true
			if p.distance_to(spc) < spr and y > spc.y - spr * 0.6:
				m = true
			for band: Array in L["mask_bands"]:
				var r: Rect2i = band[0]
				if r.has_point(Vector2i(x, y)):
					m = true
			if m:
				img.set_pixel(x, y, clear)
	# the crate: planks, no X
	var cr: Rect2i = L["crate"]
	for y in range(cr.position.y, cr.end.y):
		for x in range(cr.position.x, cr.end.x):
			var plank := (y - cr.position.y) % 4
			var col := Color("#2e140c") if plank > 0 else Color("#140805")
			if plank == 1:
				col = Color("#42200f")
			if x == cr.position.x or x == cr.end.x - 1:
				col = Color("#1c120c")
			if (x - cr.position.x) in [1, cr.size.x - 2]:
				col = Color("#3a2c1e")
			img.set_pixel(x, y, col)
	# plaques and rings off the turret side: fill from the plate just above
	for r: Rect2i in L["plaques"]:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				img.set_pixel(x, y, img.get_pixel(x, r.position.y - 2 - (y - r.position.y) % 2))
	# the hoist shaft through the deck, the quarters' floor and the roof band, and the breech glimpse
	for cut: Rect2i in [L["shaft"], L["glimpse"]]:
		for y in range(cut.position.y, cut.end.y):
			for x in range(cut.position.x, cut.end.x):
				var edge := x == cut.position.x or x == cut.end.x - 1 or y == cut.position.y
				var v := 0.18 + 0.1 * float(cut.end.y - y) / cut.size.y
				var col := Color("#0a0604") if edge else Color(0.32, 0.2, 0.1).darkened(1.0 - v * 2.4)
				img.set_pixel(x, y, col)
	# lamp spill round the rooms onto the dark hull
	var mask := PackedByteArray()
	mask.resize(w * h)
	var open := PackedByteArray()
	open.resize(w * h)
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				mask[y * w + x] = 1
	var gi := 0
	for r: Rect2i in L["rooms_all"]:
		gi += 1
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x >= 0 and y >= 0 and x < w and y < h:
					open[y * w + x] = int(L["room_groups"][gi - 1])
	Hull._spill(img, mask, open, w, h, L)
	img.save_png(ProjectSettings.globalize_path(DIR + "prep.png"))
	print("prep %dx%d" % [w, h])


func clean() -> void:
	var L := Tank4.layout()
	var img := _load("q.png")
	var pa := _load("prep.png")
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0 if pa.get_pixel(x, y).a > 0.5 else 0.0))
	var src := img.duplicate() as Image
	var outline := Color("#050302")
	var shadow := Color("#0b0705")
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var same := 0
			var cols: Dictionary = {}
			var opaque := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var n := src.get_pixel(x + dx, y + dy)
					if n.a < 0.5:
						continue
					opaque += 1
					if n.is_equal_approx(c):
						same += 1
					var key := n.to_html(false)
					cols[key] = int(cols.get(key, 0)) + 1
			if same > 0 or opaque < 6:
				continue
			var best := ""
			var bn := 0
			for k: String in cols:
				if int(cols[k]) > bn:
					bn = int(cols[k])
					best = k
			var mode := Color(best)
			var lc := c.get_luminance()
			var lm := mode.get_luminance()
			if lc > lm + 0.09 and not _in_rooms(L, x, y):
				# a rivet head: keep it, give it its shadow
				if src.get_pixel(x + 1, y + 1).a > 0.5:
					img.set_pixel(x + 1, y + 1, shadow)
			elif absf(lc - lm) < 0.09:
				img.set_pixel(x, y, mode)
	# hard outline
	var out := img.duplicate() as Image
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				continue
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or img.get_pixel(q.x, q.y).a < 0.5:
					edge = true
			if edge:
				out.set_pixel(x, y, outline)
	out.save_png(ProjectSettings.globalize_path(DIR + "base.png"))
	print("clean %dx%d" % [w, h])
