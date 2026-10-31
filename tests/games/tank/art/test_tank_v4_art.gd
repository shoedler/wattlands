extends GutTest
## The v4 enemies' kit (assets/tank/v4, baked by tools_src/enemy_bake.gd; SPEC_TANK 5.1 to 5.4): the manifest
## is sound, every kind has its frozen size and its parts on the one atlas, the running gear sits on the
## ground, the palette keeps its discipline (cold, slit glows the only saturated colour, at most 40 colours a
## kind and 90 in the atlas without the wrecks), the rivets keep the tank's density, the enemies sit in the
## tank's night (their ramp at its armour, the low rows dark, the moon only on open top edges), the belts are
## quieter than the hulls, the kinds' outlines differ, wrecks are burnt and torn and burn to their size, the
## bushes and the far ground are what the view expects. No test needs a display.

const DIR := "res://assets/tank/v4/"
const COLD_OUTLINE := Color("#0b0806")
const SLIT_CORE := Color("#d8fff4")
const SLIT_GLOW := Color("#7fe0d0")
## Fastener heads: lit, and dimmed by grime. Colours nothing but a head uses.
const RIV_LIT := Color("#656f63")
const RIV_DIM := Color("#454e44")
## The moon's rim (enemy_bake.gd COLD 18, 19).
const MOON: Array[Color] = [Color("#46555a"), Color("#5c6e75")]
## The hero's armour: tank_base.png at its rear plates, its roof and its nose (mean L, 0..255).
const HERO_ARMOUR_L := 30.0
## Every kind's fewest heads on hull and skirts, and on the turret (SPEC_TANK 5.2: "low riveted box", ...).
const MIN_HEADS := {
	"tankette": [4, 1],
	"recon": [14, 2],
	"light": [8, 2],
	"medium": [20, 10],
	"heavy": [30, 18],
	"destroyer": [20, 0],
	"behemoth": [120, 24],
}

var _kit: TankEnemyKit
var _atlas: Image


func before_all() -> void:
	_kit = TankEnemyKit.shared()
	_atlas = _kit.texture().get_image()
	_atlas.convert(Image.FORMAT_RGBA8)


## Every rect of a kind's row but the wrecks': {name: Rect2}.
func _live_rects(k: String) -> Dictionary:
	var row := _kit.kind(k)
	var out := {"base": row["base"], "gun": row["gun"]["rect"]}
	if row.has("front"):
		out["front"] = row["front"]
	if row.has("turret"):
		out["turret"] = row["turret"]["rect"]
	for s: String in row["sheets"]:
		out["sheet_" + s] = row["sheets"][s]["rect"]
	if row.has("track"):
		out["track"] = row["track"]["rect"]
	for b: Dictionary in row.get("bogies", []):
		out["bogie%d" % int(b["x_offset"])] = b["rect"]
	return out


func _colours_of(rects: Array, into: Dictionary) -> void:
	for r: Rect2 in rects:
		var ri := Rect2i(r)
		for y in range(ri.position.y, ri.end.y):
			for x in range(ri.position.x, ri.end.x):
				var c := _atlas.get_pixel(x, y)
				if c.a > 0.5:
					into[c.to_html(false)] = true


func test_the_manifest_is_sound() -> void:
	var m := TankEnemyKit.load_manifest()
	assert_false(m.is_empty(), "enemies.json parses")
	assert_eq(TankEnemyKit.check(m), [] as Array[String])
	assert_eq(str(m["atlas"]), "enemies.png")
	assert_lte(_atlas.get_width(), 2048)
	assert_lte(_atlas.get_height(), 2048)
	var imp := FileAccess.get_file_as_string(DIR + "enemies.png.import")
	assert_true(imp.contains("compress/mode=0"), "the atlas stays lossless")
	assert_true(imp.contains("mipmaps/generate=false"), "no mipmaps on pixel art")
	assert_true(
		FileAccess.file_exists(DIR + "tools_src/.gdignore"), "the tools stay out of the import"
	)


func test_every_kind_has_its_frozen_size_and_parts_inside_the_atlas() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(_atlas.get_size()))
	for k: String in TankEnemyKit.SIZES:
		var frozen: Array = TankEnemyKit.SIZES[k]
		var row := _kit.kind(k)
		assert_eq(row["size"], Vector2(float(frozen[0]), float(frozen[1])), k)
		assert_eq(int(row["faces"]), int(frozen[2]), k)
		assert_eq((row["base"] as Rect2).size, row["size"], "%s base" % k)
		assert_eq((row["wreck"] as Rect2).size, row["size"], "%s wreck" % k)
		assert_eq((row["sil"] as Rect2).size, row["size"], "%s silhouette" % k)
		var rects := _live_rects(k)
		for n: String in rects:
			assert_true(bounds.encloses(rects[n]), "%s %s inside the atlas" % [k, n])
		assert_true(row.has("muzzle_at_0"), k)
		assert_true(row.has("exhaust"), k)
		assert_true(row.has("hit_centre"), k)
		assert_false((row["slits"] as Array).is_empty(), "%s has slits" % k)


## SPEC_TANK 5.2's table.
func test_the_running_gear_of_each_kind_matches_the_table() -> void:
	var table := {
		"tankette": [3, 4.0, 2.0],
		"recon": [6, 6.0, 0.0],
		"light": [4, 5.5, 2.5],
		"medium": [6, 6.0, 3.0],
		"heavy": [8, 7.0, 4.0],
		"destroyer": [7, 6.0, 3.0],
		"behemoth": [15, 7.0, 4.0],
	}
	for k: String in table:
		var row := _kit.kind(k)
		var g: Dictionary = row["gear"]
		var wheels: Array[Vector3] = g["wheels"]
		assert_eq(wheels.size(), table[k][0], "%s wheels" % k)
		assert_eq(float(g["T"]), table[k][2], "%s track" % k)
		for w in wheels:
			assert_eq(w.z, table[k][1], "%s wheel radius" % k)
			if not bool(g["far"][wheels.find(w)]):
				assert_eq(
					w.y + w.z + float(g["T"]), float(row["ground"]), "%s rests on the ground" % k
				)
	assert_false(_kit.kind("recon").has("track"), "the recon car runs on tyres")
	assert_eq((_kit.kind("behemoth")["bogies"] as Array).size(), 3, "three bogies")
	assert_false(_kit.kind("destroyer").has("turret"), "a casemate")


func test_shoes_are_real_shoes() -> void:
	for k: String in ["tankette", "light", "medium", "heavy", "destroyer", "behemoth"]:
		var tr: Dictionary = _kit.kind(k)["track"]
		var rect := Rect2i(tr["rect"])
		assert_eq(rect.size.x, int(float(tr["pitch"]) * int(tr["sub_u"])), k)
		assert_eq(rect.size.y, int(tr["rows"]) * 2, "%s: lit over unlit rows" % k)
		# the shoe has a dark gap at its joint and a lighter grouser: separate links, not a band
		var mid := rect.position.y + int(tr["rows"]) / 2
		var seen := {}
		for x in range(rect.position.x, rect.end.x):
			seen[_atlas.get_pixel(x, mid).to_html()] = true
		assert_gt(seen.size(), 1, "%s: one shoe is not one flat colour" % k)


func test_the_palette_stays_within_its_discipline() -> void:
	var atlas_all := {}
	for k: String in TankEnemyKit.SIZES:
		var one := {}
		var rects: Array = _live_rects(k).values()
		_colours_of(rects, one)
		_colours_of(rects, atlas_all)
		assert_lte(one.size(), 40, "%s: at most 40 opaque colours" % k)
		assert_gte(one.size(), 8, "%s: not a flat fill" % k)
	assert_lte(atlas_all.size(), 90, "at most 90 in the atlas without the wrecks")


func test_nothing_warm_on_a_live_enemy_and_only_the_slits_are_saturated() -> void:
	for k: String in TankEnemyKit.SIZES:
		var cols := {}
		_colours_of(_live_rects(k).values(), cols)
		for h: String in cols:
			var c := Color(h)
			if c.is_equal_approx(COLD_OUTLINE):
				continue
			assert_false(c.r > c.g + 0.012 and c.r > c.b + 0.012, "%s: %s is warm" % [k, h])
			if c.s > 0.42 and c.v > 0.3:
				assert_true(
					c.is_equal_approx(SLIT_CORE) or c.is_equal_approx(SLIT_GLOW),
					"%s: %s is saturated and no slit" % [k, h]
				)


func test_each_kind_shows_its_slit_glow() -> void:
	for k: String in TankEnemyKit.SIZES:
		var cols := {}
		_colours_of(_live_rects(k).values(), cols)
		assert_true(cols.has(SLIT_GLOW.to_html(false)), "%s: the slits glow" % k)


static func _luma(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0


## Every head in a picture's rect, in its own px.
func _heads(r: Rect2) -> Array[Vector2i]:
	var ri := Rect2i(r)
	var out: Array[Vector2i] = []
	for y in ri.size.y:
		for x in ri.size.x:
			var c := _atlas.get_pixel(ri.position.x + x, ri.position.y + y)
			if c.a > 0.5 and (c.is_equal_approx(RIV_LIT) or c.is_equal_approx(RIV_DIM)):
				out.append(Vector2i(x, y))
	return out


## The gaps along the rows of heads: each head's distance to the next on (about) its row, when near enough to
## be on the same seam.
static func _seam_gaps(heads: Array[Vector2i]) -> Array[int]:
	var gaps: Array[int] = []
	for a in heads:
		var best := 1 << 20
		for b in heads:
			if b.x > a.x and absi(b.y - a.y) <= 1:
				best = mini(best, b.x - a.x)
		if best <= 12:
			gaps.append(best)
	return gaps


## One rivet per 7-9 px along a seam, on every kind and on its turret; some dimmed by grime, some gone.
func test_the_rivets_keep_the_tanks_density_on_every_kind() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var hull := _heads(row["base"])
		if row.has("front"):
			hull.append_array(_heads(row["front"]))
		for b: Dictionary in row.get("bogies", []):
			hull.append_array(_heads(b["rect"]))
		assert_gte(hull.size(), int(MIN_HEADS[k][0]), "%s: heads on the hull" % k)
		var gaps := _seam_gaps(hull)
		gaps.sort()
		assert_false(gaps.is_empty(), "%s: heads on a seam" % k)
		if gaps.is_empty():
			continue
		assert_between(gaps[gaps.size() / 2], 6, 10, "%s: the median gap along a seam" % k)
		if row.has("turret"):
			var on_turret := _heads(row["turret"]["rect"])
			assert_gte(on_turret.size(), int(MIN_HEADS[k][1]), "%s: heads on the turret" % k)
		var lit := 0
		for q in hull:
			var r := Rect2i(row["base"])
			if _atlas.get_pixel(r.position.x + q.x, r.position.y + q.y).is_equal_approx(RIV_LIT):
				lit += 1
		if hull.size() >= 20:
			var share := float(lit) / float(hull.size())
			assert_between(
				share, 0.05, 0.85, "%s: grime dims some, not all (%.2f lit)" % [k, share]
			)


## Not a sewing machine's line: the Behemoth's long rows have gaps where grime took heads.
func test_the_rows_of_heads_are_broken() -> void:
	var heads := _heads(_kit.kind("behemoth")["base"])
	var gaps := _seam_gaps(heads)
	var spread := {}
	for g in gaps:
		spread[g] = true
	assert_gte(spread.size(), 3, "gaps of several lengths along the rows")
	var off_line := 0
	for a in heads:
		for b in heads:
			if b.x > a.x and b.x - a.x <= 12 and absi(b.y - a.y) == 1:
				off_line += 1
				break
	assert_gt(off_line, 0, "a hand-set rivet sits off its line now and then")


# --- The tank's night -------------------------------------------------------------------------------------


## An opaque part's mean L over its rows [y0, y1) (the rect's own px).
func _mean_l(r: Rect2, y0: int, y1: int) -> float:
	var ri := Rect2i(r)
	var total := 0.0
	var n := 0
	for y in range(y0, mini(y1, ri.size.y)):
		for x in ri.size.x:
			var c := _atlas.get_pixel(ri.position.x + x, ri.position.y + y)
			if c.a > 0.5:
				total += _luma(c)
				n += 1
	return total / maxf(float(n), 1.0)


func test_the_enemies_sit_at_the_tanks_armour_value() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var whole := int((row["size"] as Vector2).y)
		assert_lte(
			_mean_l(row["base"], 0, whole), HERO_ARMOUR_L, "%s: base at or under the armour" % k
		)
		if row.has("turret"):
			var t: Rect2 = row["turret"]["rect"]
			assert_lte(
				_mean_l(t, 0, int(t.size.y)),
				HERO_ARMOUR_L + 5.0,
				"%s: the turret, nearer the moon" % k
			)


## A plate's value falls from the deck to the road: the hull's low rows are darker than its deck.
func test_the_low_rows_fall_towards_the_outline() -> void:
	for k: String in ["light", "medium", "heavy", "destroyer", "behemoth"]:
		var row := _kit.kind(k)
		var ground := int(row["ground"])
		var low_r: Rect2 = row["front"] if row.has("front") else row["base"]
		var top_of := _first_row(row["base"])
		var deck := _mean_l(row["base"], top_of, top_of + (ground - top_of) / 4)
		var bottom_start := top_of + (ground - top_of) * 3 / 5
		var low := _mean_l(low_r, bottom_start, ground)
		assert_lt(low, deck * 0.8, "%s: low rows %.1f under the deck's %.1f" % [k, low, deck])


func _first_row(r: Rect2) -> int:
	var ri := Rect2i(r)
	for y in ri.size.y:
		for x in ri.size.x:
			if _atlas.get_pixel(ri.position.x + x, ri.position.y + y).a > 0.5:
				return y
	return 0


## No moon on a skirt or a bogie frame: they hang under the overhang. On the hull it runs broken.
func test_the_moon_only_reaches_open_top_edges() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var under: Array = []
		if row.has("front"):
			under.append(row["front"])
		for b: Dictionary in row.get("bogies", []):
			under.append(b["rect"])
		for r: Rect2 in under:
			var cols := {}
			_colours_of([r], cols)
			for m in MOON:
				assert_false(cols.has(m.to_html(false)), "%s: no moon under the hull" % k)
		var ri := Rect2i(row["base"])
		var longest := 0
		for y in ri.size.y:
			var run := 0
			for x in ri.size.x:
				var c := _atlas.get_pixel(ri.position.x + x, ri.position.y + y)
				if c.is_equal_approx(MOON[0]) or c.is_equal_approx(MOON[1]):
					run += 1
					longest = maxi(longest, run)
				else:
					run = 0
		assert_lt(
			longest, ri.size.x / 2, "%s: a broken rim, not a ruled line (%d px)" % [k, longest]
		)


# --- Running gear -----------------------------------------------------------------------------------------


## The p95 L of an opaque rect.
func _p95_l(r: Rect2) -> float:
	var ri := Rect2i(r)
	var ls: Array[float] = []
	for y in range(ri.position.y, ri.end.y):
		for x in range(ri.position.x, ri.end.x):
			var c := _atlas.get_pixel(x, y)
			if c.a > 0.5:
				ls.append(_luma(c))
	ls.sort()
	return ls[int(ls.size() * 0.95)] if not ls.is_empty() else 0.0


## The belt is the quietest band: the top run at the hero's track (p95 71), the lower run almost nothing.
func test_the_belt_is_quiet_and_grimy_low_down() -> void:
	for k: String in ["tankette", "light", "medium", "heavy", "destroyer", "behemoth"]:
		var tr: Rect2 = _kit.kind(k)["track"]["rect"]
		var half := tr.size.y * 0.5
		var lit := _p95_l(Rect2(tr.position, Vector2(tr.size.x, half)))
		var unlit := _p95_l(Rect2(tr.position + Vector2(0, half), Vector2(tr.size.x, half)))
		assert_lte(lit, 71.0, "%s: the shoes' light under the hero's track" % k)
		assert_lte(unlit, 34.0, "%s: the lower run almost dark" % k)


## Road wheels about the hero's (p95 77 on the lineup), a hub on every wheel, sprocket teeth
## lighter than the belt behind them.
func test_wheels_show_a_hub_and_teeth_stand_off_the_belt() -> void:
	for k: String in ["tankette", "light", "medium", "heavy", "destroyer", "behemoth"]:
		var row := _kit.kind(k)
		var road: Dictionary = row["sheets"]["road"]
		assert_lte(_p95_l(road["rect"]), 80.0, "%s: road wheels" % k)
		var sz := int(float(road["size"]))
		var r0 := Rect2i(road["rect"])
		var centre := _atlas.get_pixel(r0.position.x + sz / 2 + 1, r0.position.y + sz / 2 - 1)
		var rim_l := _luma(_atlas.get_pixel(r0.position.x + 1, r0.position.y + sz / 2))
		assert_gt(_luma(centre), rim_l + 10.0, "%s: the hub stands out of the wheel" % k)
		var tr: Rect2 = row["track"]["rect"]
		var belt := _p95_l(Rect2(tr.position, Vector2(tr.size.x, tr.size.y * 0.5)))
		assert_gt(_p95_l(row["sheets"]["sprocket"]["rect"]), belt, "%s: teeth over the belt" % k)


## The tankette's wheels stand clear of its hull, which ends above them.
func test_the_tankette_is_a_box_above_its_wheels() -> void:
	var row := _kit.kind("tankette")
	assert_false(row.has("front"), "nothing hangs over its wheels")
	var wheels: Array[Vector3] = row["gear"]["wheels"]
	var wheel_top := int(wheels[0].y - wheels[0].z)
	var hull := _mean_l(row["base"], _first_row(row["base"]), wheel_top - 3)
	var belly := _mean_l(row["base"], wheel_top + 1, int(row["ground"]))
	assert_lt(
		belly, hull * 0.7, "dark behind the wheels: %.1f under the hull's %.1f" % [belly, hull]
	)


# --- Silhouettes ------------------------------------------------------------------------------------------


## The filled shape's top edge over `n` columns of the sprite's width, as a share of its height (hull and turret
## at rest): what the kind's outline is, at any scale.
func _top_profile(k: String, n: int) -> PackedFloat32Array:
	var row := _kit.kind(k)
	var size: Vector2 = row["size"]
	var sil := Rect2i(row["sil"])
	var ground := float(row["ground"])
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var x := int((float(i) + 0.5) / float(n) * size.x)
		var top := ground
		for y in int(size.y):
			if _atlas.get_pixel(sil.position.x + x, sil.position.y + y).a > 0.5:
				top = float(y)
				break
		if row.has("turret"):
			var at: Vector2 = row["turret"]["at"]
			var ts := Rect2i(row["turret"]["sil"])
			var tx := x - int(at.x)
			if tx >= 0 and tx < ts.size.x:
				for ty in ts.size.y:
					if _atlas.get_pixel(ts.position.x + tx, ts.position.y + ty).a > 0.5:
						top = minf(top, at.y + float(ty))
						break
		out[i] = 1.0 - top / ground
	return out


## Light, medium and heavy must not be one recipe at three sizes: their outlines differ with the scale taken
## away (the far panel has none to go by).
func test_the_kinds_outlines_differ_with_the_scale_taken_away() -> void:
	var kinds: Array[String] = ["light", "medium", "heavy", "destroyer"]
	var profiles := {}
	for k in kinds:
		profiles[k] = _top_profile(k, 48)
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var a: PackedFloat32Array = profiles[kinds[i]]
			var b: PackedFloat32Array = profiles[kinds[j]]
			var d := 0.0
			for c in a.size():
				d += absf(a[c] - b[c])
			d /= float(a.size())
			assert_gt(d, 0.05, "%s vs %s: %.3f" % [kinds[i], kinds[j], d])


## The veils lie on every part: the gun has its own silhouette, and a silhouette has no holes in it.
func test_the_silhouettes_are_solid_and_the_gun_has_one() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		assert_true(row["gun"].has("sil"), "%s: the gun takes the haze" % k)
		assert_eq((row["gun"]["sil"] as Rect2).size, (row["gun"]["rect"] as Rect2).size, k)
		assert_eq((row["wreck_sil"] as Rect2).size, row["size"], "%s: the wreck takes the haze" % k)
		var s := Rect2i(row["sil"])
		var w := s.size.x
		var h := s.size.y
		var seen := PackedByteArray()
		seen.resize(w * h)
		var stack: Array[Vector2i] = []
		for x in w:
			stack.append(Vector2i(x, 0))
			stack.append(Vector2i(x, h - 1))
		for y in h:
			stack.append(Vector2i(0, y))
			stack.append(Vector2i(w - 1, y))
		while not stack.is_empty():
			var q: Vector2i = stack.pop_back()
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen[q.y * w + q.x] == 1:
				continue
			if _atlas.get_pixel(s.position.x + q.x, s.position.y + q.y).a > 0.5:
				continue
			seen[q.y * w + q.x] = 1
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				stack.append(q + o)
		var holes := 0
		for y2 in h:
			for x2 in w:
				var solid := _atlas.get_pixel(s.position.x + x2, s.position.y + y2).a > 0.5
				holes += int(not solid and seen[y2 * w + x2] == 0)
		assert_eq(holes, 0, "%s: no specks under the veil" % k)


## Each kind has a contact shadow on the atlas, dark, soft at its lowest rows, wider than the sprite.
func test_every_kind_has_a_contact_shadow() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var r := Rect2i(row["shadow"])
		assert_gt(float(r.size.x), (row["size"] as Vector2).x, k)
		var top := 0.0
		var low := 0.0
		for x in r.size.x:
			top = maxf(top, _atlas.get_pixel(r.position.x + x, r.position.y).a)
			low = maxf(low, _atlas.get_pixel(r.position.x + x, r.end.y - 1).a)
		assert_gt(top, 0.7, "%s: dark at the belt" % k)
		assert_lt(low, 0.3, "%s: thin below" % k)
		assert_almost_eq((row["shadow_at"] as Vector2).y, float(row["ground"]) - 2.0, 0.01, k)


func test_no_lone_pixel_floats_off_a_silhouette() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var rects: Array = [row["base"]]
		if row.has("turret"):
			rects.append(row["turret"]["rect"])
		for r: Rect2 in rects:
			var ri := Rect2i(r)
			var lone := 0
			for y in range(ri.position.y, ri.end.y):
				for x in range(ri.position.x, ri.end.x):
					if _atlas.get_pixel(x, y).a < 0.5:
						continue
					var n := 0
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var q := Vector2i(x + dx, y + dy)
							if (dx != 0 or dy != 0) and ri.has_point(q):
								n += int(_atlas.get_pixel(q.x, q.y).a > 0.5)
					lone += int(n == 0)
			assert_eq(lone, 0, "%s: no stray pixels" % k)


func test_plates_are_not_a_flat_fill() -> void:
	for k: String in TankEnemyKit.SIZES:
		var ri := Rect2i(_kit.kind(k)["base"])
		var hist := {}
		var total := 0
		for y in range(ri.position.y, ri.end.y):
			for x in range(ri.position.x, ri.end.x):
				var c := _atlas.get_pixel(x, y)
				if c.a > 0.5:
					hist[c.to_html(false)] = int(hist.get(c.to_html(false), 0)) + 1
					total += 1
		var top := 0
		for h: String in hist:
			top = maxi(top, int(hist[h]))
		assert_lt(float(top) / float(total), 0.5, "%s: no colour rules the hull" % k)


func test_wrecks_are_burnt_and_torn() -> void:
	for k: String in TankEnemyKit.SIZES:
		var row := _kit.kind(k)
		var w := Rect2i(row["wreck"])
		var s := Rect2i(row["sil"])
		var hist := {}
		var gone := 0
		for y in w.size.y:
			for x in w.size.x:
				var c := _atlas.get_pixel(w.position.x + x, w.position.y + y)
				if c.a > 0.5:
					hist[c.to_html(false)] = true
				elif _atlas.get_pixel(s.position.x + x, s.position.y + y).a > 0.5:
					gone += 1
		assert_lte(hist.size(), 8, "%s: the burn ramp and its lips, no more" % k)
		assert_gt(gone, 4, "%s: bites gone from the shape" % k)
		assert_false(hist.has(SLIT_GLOW.to_html(false)), "%s: dead slits" % k)
		assert_true(hist.has("0d0a08") or hist.has("1c1410"), "%s: charred" % k)
		assert_true(row.has("wreck_fire"), "%s burns somewhere" % k)


## A flame scales with the kind: the Behemoth's is several times the tankette's, and it burns in more places.
func test_the_fires_scale_with_the_kind() -> void:
	var tallest := {}
	for k: String in TankEnemyKit.SIZES:
		var fires: Array = _kit.kind(k)["wreck_fires"]
		assert_false(fires.is_empty(), k)
		var top := 0.0
		for f: Array in fires:
			top = maxf(top, float(f[2]))
		tallest[k] = top
	assert_gte(float(tallest["behemoth"]), 4.0 * float(tallest["tankette"]))
	assert_gt(float(tallest["heavy"]), float(tallest["light"]))
	assert_gte((_kit.kind("behemoth")["wreck_fires"] as Array).size(), 3)


## The holes differ: not one disc stamped about. The wreck's near-black mouths are of many widths.
func test_a_wrecks_holes_are_not_stamped() -> void:
	var r := Rect2i(_kit.kind("behemoth")["wreck"])
	var runs := {}
	for y in r.size.y:
		var run := 0
		for x in r.size.x:
			var c := _atlas.get_pixel(r.position.x + x, r.position.y + y)
			if c.a > 0.5 and c.is_equal_approx(Color("#050403")):
				run += 1
			else:
				if run >= 2:
					runs[run] = true
				run = 0
	assert_gte(runs.size(), 4, "mouths of several widths")


## Soot spreads from the fire: the plates round a fire are darker than those far from one.
func test_the_char_spreads_from_the_fire() -> void:
	var row := _kit.kind("heavy")
	var r := Rect2i(row["wreck"])
	var f: Array = (row["wreck_fires"] as Array)[0]
	var near := _mean_box(r, Vector2i(int(f[0]), int(f[1]) + 6), 8)
	var far := _mean_box(r, Vector2i(25, 40), 8)
	assert_lt(near, far, "near the fire %.1f, far from it %.1f" % [near, far])


func _mean_box(r: Rect2i, c: Vector2i, half: int) -> float:
	var total := 0.0
	var n := 0
	for y in range(c.y - half, c.y + half):
		for x in range(c.x - half, c.x + half):
			if x < 0 or y < 0 or x >= r.size.x or y >= r.size.y:
				continue
			var q := _atlas.get_pixel(r.position.x + x, r.position.y + y)
			if q.a > 0.5:
				total += _luma(q)
				n += 1
	return total / maxf(float(n), 1.0)


func test_the_behemoths_bogies_each_have_a_wrecked_sprite() -> void:
	var bogies: Array = _kit.kind("behemoth")["bogies"]
	var seen := {}
	for b: Dictionary in bogies:
		assert_gt((b["wrecked"] as Rect2).size.x, (b["rect"] as Rect2).size.x * 0.8)
		seen[b["x_offset"]] = true
		assert_eq((b["wheels"] as Array).size(), 5, "five road wheels")
		assert_eq((b["sprocket"] as Vector3).z, 10.0, "sprocket r 10")
	assert_eq(seen.size(), 3)
	assert_true(_kit.kind("behemoth").has("secondary_muzzle"), "the bow secondary")
	assert_true(_kit.kind("behemoth").has("furnace"), "the furnace vent")


func test_the_bushes_are_feet_down_on_their_sheet() -> void:
	assert_not_null(_kit.bushes())
	var rects := _kit.bush_rects()
	assert_gte(rects.size(), 4)
	var img := _kit.bushes().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var bounds := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	for r in rects:
		assert_true(bounds.encloses(r), "a bush inside its sheet")
		var ri := Rect2i(r)
		var low := 0
		for x in range(ri.position.x, ri.end.x):
			low += int(img.get_pixel(x, ri.end.y - 1).a > 0.5)
		assert_gt(low, 0, "its foot is on the rect's bottom row")
		var top := 0
		for x2 in range(ri.position.x, ri.end.x):
			top += int(img.get_pixel(x2, ri.position.y).a > 0.5)
		assert_lt(top, ri.size.x / 2, "a crown, not a block")


func test_the_far_ground_tiles_and_goes_soft_at_its_top() -> void:
	var tex := _kit.far_ground()
	assert_not_null(tex)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	assert_eq(img.get_size(), Vector2i(1024, 170))
	var seam := 0.0
	var inner := 0.0
	for y in range(40, 130):
		seam += _diff(img.get_pixel(1023, y), img.get_pixel(0, y))
		inner += _diff(img.get_pixel(500, y), img.get_pixel(501, y))
	assert_lt(seam, inner * 1.6, "the band's seam is no louder than any other column pair")
	assert_lt(img.get_pixel(100, 0).a, 0.3, "its top fades out")
	assert_eq(img.get_pixel(100, 60).a, 1.0, "the enemies' band is solid")
	var band := 0.0
	var foot := 0.0
	for x in range(0, 1024, 4):
		band += img.get_pixel(x, 68).v
		foot += img.get_pixel(x, 165).v
	assert_gt(band, foot, "the moon on the enemies' band, the foreground dark")


static func _diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func test_a_broken_manifest_is_caught() -> void:
	assert_eq(TankEnemyKit.check({}), ["no kinds"] as Array[String])
	assert_eq(TankEnemyKit.check({"kinds": {}}).size(), 9, "7 kinds, bushes, far_ground")
	var kinds := {}
	for k: String in TankEnemyKit.SIZES:
		kinds[k] = {"size": [1, 1]}
	assert_eq(TankEnemyKit.check({"kinds": kinds}), ["no bushes", "no far_ground"] as Array[String])
