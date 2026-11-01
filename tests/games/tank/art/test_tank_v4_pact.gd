extends GutTest
## The Foundry Pact's art direction, held in numbers (docs/decisions/tank.md, "the enemies' art"). L is display luma,
## 0..255. The hero's own measures are in the comments: tank_base.png, exterior. No test needs a display.
## The frame checks (the far panel's values, naming the kinds, the squint) are judged on frames; what a number can hold
## of them is here: the medium's hull on the atlas, no block of warm light, the marks clear of every light.

const LAYOUTS := "res://assets/tank/v4/tools_src/enemy_layouts.gd"
const PAINT := "res://assets/tank/v4/tools_src/enemy_paint.gd"
const SLIT_CORE := Color("#d8fff4")
const SLIT_GLOW := Color("#7fe0d0")
const GLASS_DARK := Color("#0f1a1c")
const OUTLINE := Color("#040504")
const BONE := Color("#a8ad9c")
const GREY: Array[Color] = [
	Color("#0c100f"), Color("#151b19"), Color("#202825"), Color("#2d3733"), Color("#434f48")
]
const YELLOW: Array[Color] = [
	Color("#16160d"), Color("#26251a"), Color("#39371f"), Color("#4f4c30")
]
const GRIME: Array[Color] = [Color("#1b1a10"), Color("#2c2a17")]
const CHIP := Color("#4a4f4c")
const MOON: Array[Color] = [Color("#46555a"), Color("#5c6e75")]
const HEADS: Array[Color] = [Color("#505b4f"), Color("#384139"), Color("#262c27")]
## The hero's armour: R - B over its exterior.
const HERO_R_MINUS_B := 18.0
## What may not move: the telegraph and the firing mark read these. Kind: [muzzle_at_0, trunnion, len, pivot x, exhaust,
## hit centre].
const FIXED := {
	"tankette": [Vector2(50, 3.5), Vector2(36, 3.5), 14.0, 28.0, Vector2(2, 8), Vector2(28, 10)],
	"recon": [Vector2(74, 6), Vector2(52, 6), 22.0, 44.0, Vector2(3, 18), Vector2(40, 16)],
	"light": [Vector2(-4, 5), Vector2(30, 5), 34.0, 43.0, Vector2(90, 16), Vector2(46, 18)],
	"medium": [Vector2(-13, 13), Vector2(33, 13), 46.0, 66.0, Vector2(122, 28), Vector2(62, 30)],
	"heavy": [Vector2(-14, 15), Vector2(52, 15), 66.0, 96.0, Vector2(156, 13), Vector2(84, 38)],
	"destroyer": [Vector2(-32, 25), Vector2(28, 25), 60.0, -1.0, Vector2(141, 24), Vector2(76, 28)],
	"behemoth": [Vector2(4, 29), Vector2(100, 29), 96.0, 165.0, Vector2(240, 12), Vector2(150, 80)],
}

var _kit: TankEnemyKit
var _atlas: Image


func before_all() -> void:
	_kit = TankEnemyKit.shared()
	_atlas = _kit.texture().get_image()
	_atlas.convert(Image.FORMAT_RGBA8)


static func _luma(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0


static func _is_any(c: Color, list: Array[Color]) -> bool:
	for q in list:
		if c.is_equal_approx(q):
			return true
	return false


func _opaque(r: Rect2) -> Array[Color]:
	var ri := Rect2i(r)
	var out: Array[Color] = []
	for y in range(ri.position.y, ri.end.y):
		for x in range(ri.position.x, ri.end.x):
			var c := _atlas.get_pixel(x, y)
			if c.a > 0.5:
				out.append(c)
	return out


## The painted hull: hull and skirts above the wheels, the outline aside.
func _hull(k: String) -> Array[Color]:
	var row := _kit.kind(k)
	var base := Rect2i(row["base"])
	var front := Rect2i(row["front"]) if row.has("front") else Rect2i()
	var wheels: Array[Vector3] = row["gear"]["wheels"]
	var top := 1 << 20
	for w in wheels:
		top = mini(top, int(w.y - w.z) - 1)
	var out: Array[Color] = []
	for y in top:
		for x in base.size.x:
			var c := _atlas.get_pixel(base.position.x + x, base.position.y + y)
			if front.has_area():
				var f := _atlas.get_pixel(front.position.x + x, front.position.y + y)
				if f.a > 0.5:
					c = f
			if c.a > 0.5 and not c.is_equal_approx(OUTLINE):
				out.append(c)
	return out


## Check 1. The hero: L p50 13-27, p95 45-80, floor 0-3. No opaque pixel over L 110 but the slit's glass and the
## stencil's bone: the mark is meant to read at 852 x 480, and on the Pact's own plate it is the one pale thing.
func test_each_hull_sits_in_the_heros_values() -> void:
	for k: String in TankEnemyKit.SIZES:
		var ls: Array[float] = []
		var top := 0.0
		for c in _opaque(_kit.kind(k)["base"]):
			var l := _luma(c)
			ls.append(l)
			if not _is_any(c, [SLIT_CORE, SLIT_GLOW, BONE] as Array[Color]):
				top = maxf(top, l)
		ls.sort()
		assert_lte(ls[int(ls.size() * 0.05)], 5.0, "%s: p5" % k)
		assert_between(ls[ls.size() / 2], 15.0, 28.0, "%s: p50" % k)
		assert_lte(ls[int(ls.size() * 0.95)], 80.0, "%s: p95" % k)
		assert_lte(top, 110.0, "%s: nothing above the moon's rim" % k)


## Check 2. Steps of L >= 8 per 10 px along the rows, the measure the hero's 3.0-4.2 was taken with.
func test_each_hull_holds_its_detail() -> void:
	for k: String in TankEnemyKit.SIZES:
		var r := Rect2i(_kit.kind(k)["base"])
		var steps := 0
		var pairs := 0
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x - 1):
				var a := _atlas.get_pixel(x, y)
				var b := _atlas.get_pixel(x + 1, y)
				if a.a > 0.5 and b.a > 0.5:
					pairs += 1
					steps += int(absf(_luma(a) - _luma(b)) >= 8.0)
		assert_gte(10.0 * steps / float(pairs), 2.0, "%s: steps per 10 px" % k)


func _heads_of(r: Rect2) -> Array[Vector2i]:
	var ri := Rect2i(r)
	var out: Array[Vector2i] = []
	for y in ri.size.y:
		for x in ri.size.x:
			var c := _atlas.get_pixel(ri.position.x + x, ri.position.y + y)
			if c.a > 0.5 and _is_any(c, HEADS):
				out.append(Vector2i(x, y))
	return out


## Check 3. The hero: 0.7-2.0 heads per 100 px, median gap 5-7. The Pact's are sparser and further apart.
func test_the_rivets_are_the_pacts() -> void:
	for k: String in TankEnemyKit.SIZES:
		var r: Rect2 = _kit.kind(k)["base"]
		var heads := _heads_of(r)
		var per := 100.0 * heads.size() / float(_opaque(r).size())
		assert_between(per, 0.7, 1.5, "%s: heads per 100 px" % k)
		var gaps: Array[int] = []
		for a in heads:
			var best := 1 << 20
			for b in heads:
				if b.x > a.x and absi(b.y - a.y) <= 1:
					best = mini(best, b.x - a.x)
			if best <= 12:
				gaps.append(best)
		gaps.sort()
		assert_between(gaps[gaps.size() / 2], 6, 8, "%s: the median gap" % k)


## Check 4, over the painted hull. The destroyer hides under its dark yellow.
func test_field_grey_and_dark_yellow_on_every_hull() -> void:
	for k: String in TankEnemyKit.SIZES:
		var hull := _hull(k)
		var yellow := 0
		var grey := 0
		for c in hull:
			yellow += int(_is_any(c, YELLOW))
			grey += int(_is_any(c, GREY))
		var share := float(yellow) / float(hull.size())
		assert_gt(grey, 0, "%s: grey" % k)
		assert_gt(yellow, 0, "%s: yellow" % k)
		if k == "destroyer":
			assert_gte(float(yellow) / float(yellow + grey), 0.55, "the destroyer: mostly yellow")
			assert_gte(share, 0.45, "the destroyer: %.2f of its hull" % share)
		else:
			assert_between(share, 0.14, 0.35, "%s: %.2f dark yellow" % [k, share])


## Check 5, on the atlas: the opposite side reads cold beside our warm hull.
func test_the_mediums_hull_is_cold_beside_ours() -> void:
	var hull := _hull("medium")
	var rb := 0.0
	for c in hull:
		rb += (c.r - c.b) * 255.0
	rb /= float(hull.size())
	assert_between(rb, -6.0, 3.0, "R - B")
	assert_lte(rb, HERO_R_MINUS_B - 15.0, "at least 15 under the hero's")


## Check 6. Warmth lives in vents, the exhaust and the furnace: a lit block would mimic our tank's windows. Vents burn
## on every other row, so a slat of 3 rows or fewer is no block.
func test_no_block_of_warm_light() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		assert_eq((row["hatches"] as Array).size(), 0, "%s: every hatch is a shut door" % k)
		for v: Array in row["vents"]:
			assert_lte(int(v[3]), 3, "%s: a vent %s is a few slats" % [k, v])
		assert_eq(row.has("furnace"), k == "behemoth", "%s: only the Behemoth has a furnace" % k)
		for s: Array in row["slits"]:
			assert_lte(int(s[2]), 4, "%s: a slit %s is no LED" % [k, s])


## The palette: no hue of the old one-ramp faction, the bright rim gone. Every live picture.
func test_every_live_pixel_is_on_the_palette() -> void:
	var allowed: Array[Color] = [OUTLINE, CHIP, BONE, SLIT_CORE, SLIT_GLOW, GLASS_DARK]
	allowed.append_array(GREY)
	allowed.append_array(YELLOW)
	allowed.append_array(GRIME)
	allowed.append_array(MOON)
	allowed.append_array(HEADS)
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var rects: Array = [row["base"], row["gun"]["rect"], row["sheets"]["road"]["rect"]]
		if row.has("front"):
			rects.append(row["front"])
		if row.has("turret"):
			rects.append(row["turret"]["rect"])
		var seen := {}
		for r: Rect2 in rects:
			for c in _opaque(r):
				seen[c.to_html(false)] = c
		for h: String in seen:
			assert_true(_is_any(seen[h], allowed), "%s: %s is off the palette" % [k, h])


## A plate's value stays on its ramp: the yellow ramp is no grey one renamed, and the grey keeps its green-blue lean.
func test_the_two_paints_keep_their_hues() -> void:
	for c in YELLOW:
		assert_gt(c.g * 255.0 - c.b * 255.0, 8.0, "%s leans yellow" % c.to_html(false))
		assert_lte((c.r - c.g) * 255.0, 3.01, "%s is not warm" % c.to_html(false))
	for c2 in GREY:
		assert_gte(c2.b, c2.r, "%s leans cold" % c2.to_html(false))


## A wreck keeps its form: under the burn's black more than half of it still shows, its top colour on edges only.
func test_a_wreck_keeps_its_form() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var all := _opaque(row["wreck"])
		var black := 0
		var top := 0
		var bone := 0
		for c in all:
			black += int(c.is_equal_approx(Color("#0d0a08")))
			top += int(c.is_equal_approx(Color("#3f2a1c")))
			bone += int(c.is_equal_approx(BONE))
		assert_lte(float(black) / float(all.size()), 0.55, "%s: soot" % k)
		assert_lt(float(top) / float(all.size()), 0.15, "%s: top edges only" % k)
		assert_eq(bone, 0, "%s: the mark is burnt out" % k)


## Trunnion, gun, pivot, anchors: the telegraph and the firing mark read these.
func test_the_fixed_points_did_not_move() -> void:
	for k: String in FIXED:
		var row := _kit.kind(k)
		var f: Array = FIXED[k]
		assert_eq(row["muzzle_at_0"], f[0], "%s: muzzle" % k)
		assert_eq(row["gun"]["trunnion"], f[1], "%s: trunnion" % k)
		assert_eq(float(row["gun"]["len"]), f[2], "%s: gun length" % k)
		if row.has("turret"):
			assert_eq((row["turret"]["pivot"] as Vector2).x, f[3], "%s: pivot" % k)
		assert_eq(row["exhaust"], f[4], "%s: exhaust" % k)
		assert_eq(row["hit_centre"], f[5], "%s: hit centre" % k)
	assert_eq(_kit.kind("behemoth")["secondary_muzzle"], Vector2(-10, 89), "the bow secondary")
	var lamp: Array = (_kit.kind("recon")["lamps"] as Array)[0]
	assert_eq([int(lamp[0]), int(lamp[1])], [74, 21], "the recon's lamp")


## A wheel with four holes turns its web into a cross on a sprite this small.
func test_no_idler_turns_on_four_holes() -> void:
	for k: String in TankEnemyKit.SIZES:
		var sheets: Dictionary = _kit.kind(k)["sheets"]
		if sheets.has("idler"):
			var holes := TAU / float(sheets["idler"]["period"])
			assert_ne(roundi(holes), 4, "%s: its idler" % k)


# --- the marks ----------------------------------------------------------------------------------------------------


## A stencil's rect, in sprite px.
static func _mark_rect(d: Dictionary) -> Rect2i:
	if str(d["kind"]) == "mark":
		return Rect2i(d["at"], Vector2i(int(d["size"]) + 2, int(d["size"]) + 2))
	var tall := int(d.get("tall", 5))
	var wide := 5 if tall == 7 else 3
	var n := str(d["text"]).length()
	return Rect2i(d["at"], Vector2i(n * wide + n - 1, tall))


## Every stencil on a kind with what it must stay clear of, in one list per picture.
func _stencils(lay: Dictionary) -> Array:
	var out: Array = []
	for key: String in ["details", "front_details", "turret_details"]:
		for d: Dictionary in lay.get(key, []):
			if str(d["kind"]) in ["mark", "digits"]:
				out.append([key, d])
	return out


## Number codes the far right uses, read in both directions: `flip` and a turret's traverse mirror a number's order.
## 101 is no code: it was the number of a real SS heavy tank battalion, and the heavy is Tiger-like.
const FORBIDDEN_CODES: Array[String] = ["18", "81", "88", "101"]


static func _codes_in(text: String) -> Array[String]:
	var out: Array[String] = []
	for code in FORBIDDEN_CODES:
		if text.contains(code) or text.reverse().contains(code):
			out.append(code)
	return out


func test_no_number_is_a_code() -> void:
	assert_eq(
		_codes_in("18"), ["18", "81"] as Array[String], "the check itself: 18 reads both ways"
	)
	assert_eq(_codes_in("081"), ["18", "81"] as Array[String], "inside a longer one too")
	assert_eq(_codes_in("88"), ["88"] as Array[String])
	assert_eq(_codes_in("101"), ["101"] as Array[String], "the same read mirrored")
	assert_eq(_codes_in("1011"), ["101"] as Array[String], "and inside a longer one, either way")
	assert_eq(_codes_in("808"), [] as Array[String])
	var lay: Dictionary = load(LAYOUTS).all()
	var seen := 0
	for k: String in lay:
		for e: Array in _stencils(lay[k]):
			var d: Dictionary = e[1]
			if str(d["kind"]) == "digits":
				seen += 1
				assert_eq(_codes_in(str(d["text"])), [] as Array[String], "%s: %s" % [k, d["text"]])
	assert_gte(seen, 5, "every number on the kit was read")


## What a stencil's rect holds on the atlas as bone, in sprite px of its picture: [rows of "#" and "."].
func _bone_rows(k: String, key: String, box: Rect2i) -> Array[String]:
	var row := _kit.kind(k)
	var at := Vector2i.ZERO
	var pic := Rect2i(row["base"])
	if key == "front_details":
		pic = Rect2i(row["front"])
	elif key == "turret_details":
		pic = Rect2i(row["turret"]["rect"])
		at = Vector2i(row["turret"]["at"] as Vector2)
	var out: Array[String] = []
	for y in box.size.y:
		var line := ""
		for x in box.size.x:
			var q := pic.position + box.position - at + Vector2i(x, y)
			line += "#" if _atlas.get_pixelv(q).is_equal_approx(BONE) else "."
		out.append(line)
	return out


## Reads digit glyphs off bone rows, left to right, a clear column between them.
static func _read_digits(rows: Array[String], table: Dictionary) -> String:
	var wide := (rows[0] as String).length()
	var one: int = (table["0"][0] as String).length()
	var text := ""
	var x := 0
	while x + one <= wide:
		var glyph: Array = []
		for r in rows:
			glyph.append(r.substr(x, one))
		var found := "?"
		for ch: String in table:
			if table[ch] == glyph:
				found = ch
		text += found
		x += one + 1
	return text


## The drawn number, as painted and as a flip or a traverse shows it: the pixels themselves, read back mirrored.
func test_a_mirrored_number_reads_as_no_code() -> void:
	var paint: Variant = load(PAINT)
	var lay: Dictionary = load(LAYOUTS).all()
	for k: String in lay:
		for e: Array in _stencils(lay[k]):
			var d: Dictionary = e[1]
			if str(d["kind"]) != "digits":
				continue
			var table: Dictionary = (
				paint.DIGITS_5X7 if int(d.get("tall", 5)) == 7 else paint.DIGITS_3X5
			)
			var rows := _bone_rows(k, e[0], _mark_rect(d))
			assert_eq(_read_digits(rows, table), str(d["text"]), "%s: as painted" % k)
			var mirrored: Array[String] = []
			for r in rows:
				mirrored.append(r.reverse())
			var flipped := _read_digits(mirrored, table)
			assert_eq(flipped, str(d["text"]).reverse(), "%s: as a flip shows it" % k)
			assert_eq(
				_codes_in(flipped), [] as Array[String], "%s: flipped reads %s" % [k, flipped]
			)


## No cross: the centre of every mark is the plate behind it, at every size, and the diamond is hollow all through.
func test_a_mark_is_a_hollow_diamond() -> void:
	var lay: Dictionary = load(LAYOUTS).all()
	var seen := 0
	for k: String in lay:
		for e: Array in _stencils(lay[k]):
			var d: Dictionary = e[1]
			if str(d["kind"]) != "mark":
				continue
			seen += 1
			var size := int(d["size"])
			var at: Vector2i = d["at"]
			var pad_y := 0 if size == 3 else 1
			var rows := _bone_rows(k, e[0], Rect2i(at, Vector2i(size + 2, size + pad_y * 2)))
			var r := size / 2
			for y in rows.size():
				for x in (rows[y] as String).length():
					var m := absi(x - r - 1) + absi(y - r - pad_y)
					var bone := (rows[y] as String)[x] == "#"
					assert_eq(
						bone, m == r, "%s: mark px (%d, %d): only its ring is bone" % [k, x, y]
					)
	assert_eq(seen, 4, "tankette, medium, destroyer, Behemoth")


## Only 0, 1 and 8: a turret's traverse and `flip` mirror them, and each reads the same mirrored.
func test_the_numbers_survive_a_mirror() -> void:
	var paint: Variant = load(PAINT)
	for table: Dictionary in [paint.DIGITS_3X5, paint.DIGITS_5X7]:
		assert_eq(table.keys(), ["0", "1", "8"], "the digits a mirror leaves alone")
		for ch: String in table:
			for row: String in table[ch]:
				assert_eq(row, row.reverse(), "%s mirrors onto itself" % ch)
	var lay: Dictionary = load(LAYOUTS).all()
	for k: String in lay:
		for e: Array in _stencils(lay[k]):
			var d: Dictionary = e[1]
			if str(d["kind"]) == "digits":
				for ch2 in str(d["text"]):
					assert_true(ch2 in ["0", "1", "8"], "%s: %s" % [k, d["text"]])


## The kinds carry what the direction gave them.
func test_each_kind_wears_its_marks() -> void:
	var want := {
		"tankette": [3, ""],
		"recon": [0, "10"],
		"light": [0, "80"],
		"medium": [5, "808"],
		"heavy": [0, "110"],
		"destroyer": [5, ""],
		"behemoth": [9, "808"],
	}
	var lay: Dictionary = load(LAYOUTS).all()
	for k: String in want:
		var mark := 0
		var text := ""
		for e: Array in _stencils(lay[k]):
			var d: Dictionary = e[1]
			if str(d["kind"]) == "mark":
				mark = int(d["size"])
			else:
				text = str(d["text"])
		assert_eq(mark, int(want[k][0]), "%s: the mark" % k)
		assert_eq(text, str(want[k][1]), "%s: the number" % k)


## A mark touches no slit, vent or hatch, and the Behemoth's stays inside the 286 px panel, which clips 7 px a side.
func test_the_marks_are_clear_of_every_light() -> void:
	var lay: Dictionary = load(LAYOUTS).all()
	for k: String in lay:
		var one: Dictionary = lay[k]
		for e: Array in _stencils(one):
			var on_turret := str(e[0]) == "turret_details"
			var box := _mark_rect(e[1])
			for s: Array in one["slits"]:
				if (int(s[3]) == 1) != on_turret:
					continue
				var glass := Rect2i(int(s[0]) - 2, int(s[1]) - 2, int(s[2]) + 4, 5)
				assert_false(box.intersects(glass), "%s: %s on a slit" % [k, box])
			for d: Dictionary in one.get(e[0], []):
				if str(d["kind"]) in ["louvre", "hatch"]:
					var other: Rect2i = d["rect"]
					assert_false(
						box.intersects(other.grow(1)), "%s: %s on a %s" % [k, box, d["kind"]]
					)
				elif str(d["kind"]) == "vent":
					var at: Vector2i = d["at"]
					var vent := Rect2i(at - Vector2i(3, 3), Vector2i(7, 5))
					assert_false(box.intersects(vent), "%s: %s on a vent" % [k, box])
			if k == "behemoth":
				assert_between(box.position.x, 140, 190, "the Behemoth's stencils in the panel")
				assert_between(box.end.x, 140, 190, "the Behemoth's stencils in the panel")
