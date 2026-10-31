extends SceneTree
## r6 base: the reference's tank (v2's 4-rider cut of it, 960 scale) at 0.9, re-pixelled.
##   prep:  build/v3mock/r6/s90.png (magick: Box 90% + a light unsharp) -> darkened hull, masked live
##          parts (running gear, barrel, bow-gun barrels), the crate repainted, plaques removed, the
##          hoist shaft and the breech glimpse cut -> prep.png
##   clean: q.png (magick: +dither -remap onto the curated palette) -> binary alpha, noise pixels
##          snapped to their neighbours, rivet highlights paired with a shadow, a hard outline, the
##          lamp spill round the rooms -> base.png
## Run through assets/tank/v3/tools_src/r6_base.sh.

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const TankGen = preload("res://assets/tank/v3/tools_src/tank_gen.gd")
const Hull = preload("res://assets/tank/v3/tools_src/hull.gd")
const Dress = preload("res://assets/tank/v3/tools_src/dress.gd")

const DIR := "res://build/v3mock/r6/"


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
	var L := TankGen.layout()
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
			var f := lerpf(0.86, 1.04, smoothstep(0.2, 0.66, l))
			if _in_rooms(L, x, y):
				f = maxf(f, 0.92)
			img.set_pixel(x, y, Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f * 0.97, 1.0), c.a))
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
	# the rear searchlight comes off (it is redrawn per frame, looking aft)
	for y in range(L["rear_lamp_mask"].position.y, L["rear_lamp_mask"].end.y):
		for x in range(L["rear_lamp_mask"].position.x, L["rear_lamp_mask"].end.x):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	# the hoist shaft, the turret's cutaway and the bow guns' box cutaway: lit interiors
	for cut: Dictionary in L["cuts"]:
		var cut_r: Rect2i = cut["rect"]
		var lamp: Vector2 = cut.get("lamp", Vector2(cut_r.position.x + cut_r.size.x * 0.5, cut_r.position.y + 2))
		var reach := float(cut.get("reach", 30.0))
		for y in range(cut_r.position.y, cut_r.end.y):
			for x in range(cut_r.position.x, cut_r.end.x):
				var edge := x == cut_r.position.x or x == cut_r.end.x - 1 or y == cut_r.position.y or y == cut_r.end.y - 1
				var v := clampf(1.0 - Vector2(x + 0.5, y + 0.5).distance_to(lamp) / reach, 0.0, 1.0)
				v = v * v * 0.8 + 0.1
				if (x - cut_r.position.x) % 9 == 0:
					v -= 0.08
				var col := Px.dither(Dress.WALL, v, x, y)
				if y >= cut_r.end.y - 3 and bool(cut.get("floor", true)):
					col = Color("#3a2814") if y == cut_r.end.y - 3 else Color("#1a120a")
				if edge:
					col = Color("#0a0604")
				img.set_pixel(x, y, col)
		if cut.has("lamp"):
			img.set_pixel(floori(lamp.x), floori(lamp.y), Color("#fff6d8"))
			img.set_pixel(floori(lamp.x) - 1, floori(lamp.y), Color("#ffd98a"))
			img.set_pixel(floori(lamp.x) + 1, floori(lamp.y), Color("#ffd98a"))
	# shadows under overhangs: the turret onto the deck, the deck edges, the glacis lip
	for sh: Dictionary in L["shadows"]:
		var sr: Rect2i = sh["rect"]
		var amt := float(sh.get("amt", 0.5))
		for y in range(sr.position.y, sr.end.y):
			var k := 1.0 - amt * (1.0 - float(y - sr.position.y) / sr.size.y)
			for x in range(sr.position.x, sr.end.x):
				if _in_rooms(L, x, y):
					continue
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, c.a))
	# the turret's and the deck's added fittings (cupolas, periscope housing, vision blocks, hatch,
	# grab rails, bolt strips, the antenna's base, the stowage box)
	for d: Dictionary in L["prep_details"]:
		if str(d["kind"]) == "cupola":
			_cupola(img, d["rect"])
		else:
			Hull._detail(img, d, false)
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
	var L := TankGen.layout()
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


## A commander's cupola: a riveted drum on the roof with vision slits and a hatch lid.
func _cupola(img: Image, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var top := y - r.position.y
			var corner := top < 2 and (x - r.position.x < 2 - top or r.end.x - 1 - x < 2 - top)
			if corner:
				continue
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y
			var col := Color("#3a2c20") if top < 2 else Color("#271c14")
			if x > r.end.x - 3:
				col = Color("#140e0a")
			if edge:
				col = Color("#050302")
			img.set_pixel(x, y, col)
	for x in range(r.position.x + 3, r.end.x - 3, 5):
		img.set_pixel(x, r.position.y + 3, Color("#050302"))
		img.set_pixel(x + 1, r.position.y + 3, Color("#050302"))
		img.set_pixel(x, r.position.y + 4, Color("#6a8a8c"))
	for x in range(r.position.x + 2, r.end.x - 2, 3):
		img.set_pixel(x, r.end.y - 2, Color("#86683f"))
	Px.rect(img, Rect2i(r.position.x + 2, r.position.y - 2, r.size.x - 4, 2), Color("#050302"))
	Px.rect(img, Rect2i(r.position.x + 3, r.position.y - 2, r.size.x - 6, 1), Color("#4a3a28"))
