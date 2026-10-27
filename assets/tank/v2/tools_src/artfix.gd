extends SceneTree
# The art-fix pass (2026-10-27 critique) over the shipped kit PNGs, after enemies.gd (regen.sh). Every
# step paints absolute colours at fixed places, so running it again changes nothing.
#  - The four variants' turret side: the healed star and "A17" read as heraldic ghosts (a shield, a
#    "Y"); they become plain plate with a vision block (a dark slit in an iron box, brass rim, a lit
#    pixel) and a pistol port. The red crate with its X brace (a saltire at 1x) becomes a planked
#    crate under an iron strap with a brass buckle.
#  - The dug-in tank: the two full-width rows of sandbags read as a track under a floating turret;
#    it now sits in an earthwork: a concrete casemate lip in front, an earth berm with a lit crest
#    tapering into the ground at both ends, a short row of sandbags on the crest. Same size, same
#    muzzle (enemies.json and rigs.json keep their numbers).
#  - The tanks (light, medium, destroyer, heavy): a dark 1 px outline, the cold rim on top edges, a
#    rivet row under the roof line.
# Run: copy to build/v2/ and run with tools/godot.sh --headless --path . -s build/v2/artfix.gd

const KIT := "res://assets/tank/v2/"
const VARIANTS := ["tank_1rider", "tank_2rider", "tank_3rider", "tank_4rider"]
## The 3-rider's turret pivot and the patches measured on it (variant px).
const TP3 := Vector2(249.5, 127.0)
const CRATE := Rect2i(181, 95, 20, 23)
const BLOB_Y := Rect2i(207, 98, 18, 22)
const BLOB_SHIELD := Rect2i(228, 98, 14, 15)
## The clean plate the ghosts are healed from (this many px to the right, past the panel seam).
const HEAL_DX := 46

const PLANK := Color(0.3, 0.11, 0.07)
const PLANK_GAP := Color(0.12, 0.05, 0.035)
const PLANK_HI := Color(0.4, 0.17, 0.1)
const POST := Color(0.21, 0.085, 0.055)
const STRAP := Color(0.13, 0.115, 0.1)
const STRAP_HI := Color(0.3, 0.27, 0.22)
const BRASS := Color(0.4, 0.3, 0.15)
const BRASS_HI := Color(0.54, 0.42, 0.22)
const BOX := Color(0.11, 0.095, 0.08)
const BOX_HI := Color(0.36, 0.3, 0.23)
const SLIT := Color(0.025, 0.03, 0.03)
const GLINT := Color(0.42, 0.47, 0.44)

const OUTLINE := Color(0.075, 0.085, 0.07)
const RIM := Color(0.6, 0.66, 0.6)
const RIVET := Color(0.46, 0.49, 0.4)
const EARTH := Color(0.15, 0.13, 0.1)
const EARTH_DK := Color(0.085, 0.075, 0.06)
const EARTH_HI := Color(0.3, 0.26, 0.2)
const CONC := Color(0.27, 0.27, 0.25)
const CONC_HI := Color(0.4, 0.4, 0.37)
const CONC_DK := Color(0.13, 0.13, 0.12)
const BAG := Color(0.3, 0.28, 0.21)
const BAG_HI := Color(0.42, 0.39, 0.3)
const BAG_DK := Color(0.12, 0.11, 0.08)


func _init() -> void:
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT + "kit.json"))
	for vn: String in VARIANTS:
		var v: Dictionary = kit["tank"]["variants"][vn]
		var a: Dictionary = v["anchors"]
		var tp := Vector2(float(a["turret_pivot"][0]), float(a["turret_pivot"][1]))
		var sc := float(v.get("turret_scale", 1.0))
		var path := KIT + str(v["file"])
		var img := Image.load_from_file(path)
		img.convert(Image.FORMAT_RGBA8)
		turret_side(img, tp, sc)
		img.save_png(path)
		print("artfix: ", vn)
	var dg := Image.load_from_file(KIT + "enemies/dugin.png")
	dg.convert(Image.FORMAT_RGBA8)
	dugin(dg)
	dg.save_png(KIT + "enemies/dugin.png")
	for kind: String in ["light", "medium", "destroyer", "heavy"]:
		var e := Image.load_from_file(KIT + "enemies/%s.png" % kind)
		e.convert(Image.FORMAT_RGBA8)
		clean_tank(e)
		e.save_png(KIT + "enemies/%s.png" % kind)
	print("artfix: enemies")
	quit()


## A rect measured on the 3-rider moved to a variant whose turret pivot is `tp`, scaled `sc`.
func place(r: Rect2i, tp: Vector2, sc: float) -> Rect2i:
	var p := tp + (Vector2(r.position) - TP3) * sc
	var e := tp + (Vector2(r.end) - TP3) * sc
	return Rect2i(Vector2i(p.round()), Vector2i((e - p).round()))


func turret_side(img: Image, tp: Vector2, sc: float) -> void:
	var dx := roundi(HEAL_DX * sc)
	for blob: Rect2i in [BLOB_Y, BLOB_SHIELD]:
		var r := place(blob, tp, sc)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				img.set_pixel(x, y, img.get_pixel(x + dx, y))
	# The vision block where the "Y" was: an iron box, a brass rim, a dark slit with a glint.
	var yb := place(BLOB_Y, tp, sc)
	var bw := maxi(roundi(11 * sc), 8)
	var bh := maxi(roundi(7 * sc), 5)
	var bx := yb.position.x + (yb.size.x - bw) / 2
	var by := yb.position.y + roundi(5 * sc)
	box(img, Rect2i(bx, by, bw, bh))
	for x in range(bx + 2, bx + bw - 2):
		img.set_pixel(x, by + bh / 2, SLIT)
		img.set_pixel(x, by + bh / 2 - 1, SLIT if x > bx + 2 else GLINT)
	# A pistol port where the shield was: a small round plug in a brass ring.
	var sb := place(BLOB_SHIELD, tp, sc)
	var c := Vector2i(sb.position.x + sb.size.x / 2, sb.position.y + roundi(6 * sc))
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			var d := absi(ox) + absi(oy)
			if d > 3:
				continue
			var col := BRASS if d >= 2 else BOX
			if d >= 2 and (ox < 0 or oy < 0):
				col = BRASS_HI
			img.set_pixel(c.x + ox, c.y + oy, col)
	img.set_pixel(c.x, c.y, SLIT)
	crate(img, place(CRATE, tp, sc))


func box(img: Image, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			img.set_pixel(x, y, BRASS if edge else BOX)
	for x in range(r.position.x, r.end.x):
		img.set_pixel(x, r.position.y, BRASS_HI)
	for y in range(r.position.y + 1, r.end.y):
		img.set_pixel(r.position.x, y, BOX_HI)


## A planked crate: horizontal planks (a lit top pixel, a dark gap), corner posts, an iron strap
## down the middle with a brass buckle; the antenna's pixels above it untouched.
func crate(img: Image, r: Rect2i) -> void:
	var plank_h := 4
	var sx := r.position.x + r.size.x / 2 - 1
	for y in range(r.position.y, r.end.y):
		var ry := y - r.position.y
		var row := ry / plank_h
		var shade := 0.92 + 0.12 * float((row * 7) % 3) / 2.0
		for x in range(r.position.x, r.end.x):
			var rx := x - r.position.x
			var col := Color(PLANK.r * shade, PLANK.g * shade, PLANK.b * shade)
			if ry % plank_h == plank_h - 1:
				col = PLANK_GAP
			elif ry % plank_h == 0:
				col = PLANK_HI
			elif (rx * 5 + ry * 3) % 11 == 0:
				col = col.darkened(0.25)
			if rx <= 1 or rx >= r.size.x - 2:
				col = POST if rx in [0, r.size.x - 1] else POST.lightened(0.15)
			if ry == 0:
				col = PLANK_HI.lightened(0.2) if rx > 0 and rx < r.size.x - 1 else POST
			if ry == r.size.y - 1:
				col = PLANK_GAP
			if x == sx or x == sx + 1:
				col = STRAP_HI if x == sx else STRAP
			img.set_pixel(x, y, col)
	var buckle := r.position.y + r.size.y / 2 - 1
	for y in range(buckle, buckle + 3):
		img.set_pixel(sx - 1, y, BRASS)
		img.set_pixel(sx + 2, y, BRASS)
	img.set_pixel(sx - 1, buckle, BRASS_HI)
	img.set_pixel(sx, buckle, BRASS_HI)
	img.set_pixel(sx + 1, buckle, BRASS)
	img.set_pixel(sx, buckle + 2, BRASS)
	img.set_pixel(sx + 1, buckle + 2, BRASS)


## The dug-in tank's earthwork (the sprite faces left: the gun and the casemate's lip on the left).
func dugin(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var crest := 19
	for y in range(crest, h):
		for x in w:
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	# The berm's top per column: rising from the ground at the left, a crest, tapering at the right.
	for x in w:
		var top := h
		if x >= 14 and x < 30:
			top = h - roundi(float(x - 14) / 16.0 * float(h - crest + 1))
		elif x >= 30 and x < w - 12:
			top = crest - (1 if (x / 9) % 3 == 1 else 0)
		elif x >= w - 12:
			top = crest + roundi(float(x - (w - 12)) / 12.0 * 5.0)
		for y in range(maxi(top, 0), h):
			var d := y - top
			var col := EARTH
			if d == 0:
				col = EARTH_HI
			elif d == 1:
				col = EARTH.lightened(0.15)
			elif (x * 7 + y * 13) % 9 == 0:
				col = EARTH_DK
			elif y >= h - 2:
				col = EARTH_DK
			img.set_pixel(x, y, col)
	# The casemate's concrete lip in front of the turret: a sloped slab, lit top, dark front face.
	for y in range(crest - 1, h - 2):
		var x0 := 28 - (y - crest + 1) / 2
		for x in range(x0, 44):
			var col := CONC
			if y == crest - 1:
				col = CONC_HI
			elif x <= x0 + 1:
				col = CONC_DK
			elif (x + y) % 6 == 0:
				col = CONC.darkened(0.2)
			img.set_pixel(x, y, col)
	# A short row of sandbags on the crest behind the lip.
	var bx := 46
	while bx < 78:
		for yy in 3:
			for xx in 6:
				if (xx == 0 or xx == 5) and yy != 1:
					continue
				var col := BAG if yy == 1 else (BAG_HI if yy == 0 else BAG_DK)
				img.set_pixel(bx + xx, crest - 3 + yy, col)
		bx += 7


## A dark 1 px outline and the cold rim on top edges, a rivet row under the roof line (the paint
## itself kept as enemies.gd shaded it: quantising it to a ramp only turned its grain into speckle).
func clean_tank(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a < 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var q := img.duplicate() as Image
	for y in h:
		for x in w:
			if q.get_pixel(x, y).a < 0.5:
				continue
			var up := y == 0 or q.get_pixel(x, y - 1).a < 0.5
			var edge := up
			for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var n := Vector2i(x, y) + o
				if n.x < 0 or n.y >= h or n.x >= w or q.get_pixel(n.x, n.y).a < 0.5:
					edge = true
			if up:
				img.set_pixel(x, y, RIM)
			elif edge:
				img.set_pixel(x, y, OUTLINE)
	# Rivets: every 5 px along the row three below the roof line, on the lighter plates.
	for x in range(3, w - 3, 5):
		var top := -1
		for y in h:
			if q.get_pixel(x, y).a >= 0.5:
				top = y
				break
		if top < 0 or top + 3 >= h:
			continue
		if img.get_pixel(x, top + 3).a >= 0.5 and img.get_pixel(x, top + 3) != OUTLINE:
			img.set_pixel(x, top + 3, RIVET)
			img.set_pixel(x, top + 4, OUTLINE)
