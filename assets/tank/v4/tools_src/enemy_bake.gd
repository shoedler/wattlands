extends SceneTree
## Bakes the enemies' kit (SPEC_TANK 5.1, 5.3, 5.4) from enemy_layouts.gd with the tank's own generator
## (assets/tank/v3/tools_src: px, gear, hull, finish), so the enemies are built the way our tank is:
##   enemies.png    one atlas, nearest, lossless (every enemy batches): per kind the hull (`base`), the
##                  skirts over the track (`front`), the white silhouettes (`sil`, the view's haze and
##                  flash), the charred `wreck`, the turret, the gun, the wheel sheets over their symmetry
##                  and the track shoe (lit over unlit rows, as v3's track.png)
##   enemies.json   every rect and anchor TankEnemyKit and TankEnemyDraw read
##   bushes.png     the roadside bushes the near threats burst from
##   far_ground.png the far panel's ground, 1024 x 170, tiling, soft at its top and bottom
## All procedural: no fal, no source image. Run: bash assets/tank/v4/tools_src/enemy_bake.sh

const Px = preload("res://assets/tank/v3/tools_src/px.gd")
const Gear = preload("res://assets/tank/v3/tools_src/gear.gd")
const Hull = preload("res://assets/tank/v3/tools_src/hull.gd")
const Finish = preload("res://assets/tank/v3/tools_src/finish.gd")
const Layouts = preload("res://assets/tank/v4/tools_src/enemy_layouts.gd")

const OUT := "res://assets/tank/v4/"
const ATLAS_W := 2048
const GUTTER := 1
const OUTLINE := Color("#0b0806")
## The contact shadow's rows, top to bottom, and how far it reaches past the sprite each side.
const SHADOW_ROWS: Array[float] = [0.9, 0.9, 0.8, 0.62, 0.42, 0.25, 0.12]
const SHADOW_PAD := 4

## The enemy palette (SPEC_TANK 5.3): the hull ramp and its lights, the gear's steels, the moon's rims.
## Every opaque enemy pixel snaps onto it by value, so no warm colour of the shared details survives.
const COLD: Array[Color] = [
	Color("#0b0806"),
	Color("#0a0c0b"),
	Color("#0d100e"),
	Color("#111512"),
	Color("#161b17"),
	Color("#1b211c"),
	Color("#212722"),
	Color("#272e28"),
	Color("#2d352e"),
	Color("#343c34"),
	Color("#3b443b"),
	Color("#444d43"),
	Color("#4d574b"),
	Color("#596355"),
	Color("#66705f"),
	Color("#74806f"),
	Color("#8c9584"),
	Color("#b0b8aa"),
	# the moon's edge: a colder step, only near the top edges
	Color("#46555a"),
	Color("#5c6e75"),
]
## The one saturated hue on an enemy: slit and lamp glass.
const SLIT_CORE := Color("#d8fff4")
const SLIT_GLOW := Color("#7fe0d0")
const GLASS_DARK := Color("#0f1a1c")
## Our tank's night: every enemy picture's ramp falls by NIGHT_K (the hero's armour is L 17-30), and from
## FALL_FROM of the way from the deck to the road it keeps falling to FALL_LOW of that, so a plate has no
## single value from deck to skirt and the lower third sinks to near the outline. Only the moon rim, put on
## afterwards, keeps its value.
const NIGHT_K := 0.66
const WHEEL_K := 0.66
const GUN_K := 0.72
const FALL_FROM := 0.4
const FALL_LOW := 0.26
## The moon reaches a top edge only with open sky over it for this many rows.
const RIM_CLEAR := 5
## Fastener heads after the night: as bright as the hero's (#86683f, L 107), and the grimed ones. Colours of
## their own, off the ramp, so a head can be told from a plate.
const RIV_LIT := Color("#656f63")
const RIV_DIM := Color("#454e44")
const BURN: Array[Color] = [Color("#0d0a08"), Color("#1c1410"), Color("#2b1e16"), Color("#3f2a1c")]
const BURN_LIP := Color("#6a4628")
const HOLE := Color("#050403")
const ASH := Color("#57504a")

## Wheel sheets are shared between kinds of one radius; key -> [Image, frames, period, size].
var _sheets: Dictionary = {}
var _parts: Array = []
var _lum_cold: Array[float] = []


func _init() -> void:
	for c in COLD:
		_lum_cold.append(_lum(c))
	var kinds := {}
	var layouts: Dictionary = Layouts.all()
	for k: String in layouts:
		kinds[k] = _bake_kind(k, layouts[k])
		print("baked %s" % k)
	var atlas := _pack()
	_rects(kinds)
	atlas.save_png(ProjectSettings.globalize_path(OUT + "enemies.png"))
	var manifest := {
		"note": "The v4 enemies (assets/tank/v4/tools_src/enemy_bake.gd). Sprite px, origin top-left.",
		"atlas": "enemies.png",
		"kinds": kinds,
	}
	manifest["bushes"] = _bushes()
	manifest["far_ground"] = _far_ground()
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + "enemies.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, " ", false))
	f.close()
	print("atlas %d x %d" % [atlas.get_width(), atlas.get_height()])
	print("bake done")
	quit()


# --- one kind ----------------------------------------------------------------------------------------------


func _bake_kind(id: String, L: Dictionary) -> Dictionary:
	var sz: Vector2i = L["size"]
	var row := {
		"size": [sz.x, sz.y],
		"ground": float(L["ground"]),
		"faces": int(L["faces"]),
		"slits": L.get("slits", []),
		"lamps": L.get("lamps", []),
		"exhaust": _v(L["exhaust"]),
		"hit_centre": _v(L["hit_centre"]),
	}
	var hull := _hull_image(id, L)
	var base: Image = hull["base"]
	var front: Image = hull["front"]
	var turret_img: Image = null
	if L.has("turret_parts"):
		turret_img = _turret_image(L)
		_turret_shadow(base, turret_img)
		_snap(base)
	_slits(base, L, false)
	_slits(front, L, 2)
	if turret_img != null:
		_slits(turret_img, L, 1)
		_turret_row(row, L, turret_img)
	var gun_img := _gun_row(row, L)
	_gear_row(row, L)
	row["base"] = _add(_crop_keep(base), Vector2i.ZERO)
	if not front.is_invisible():
		row["front"] = _add(front, Vector2i.ZERO)
	# the silhouettes: hull and gear at rest; the turret has its own, for when it traverses
	var whole := _rest_picture(L, base, front, null, null)
	row["sil"] = _add(_silhouette(whole), Vector2i.ZERO)
	if turret_img != null:
		row["turret"]["sil"] = _add(_silhouette(turret_img.get_region(turret_img.get_used_rect())), Vector2i.ZERO)
	var wreck := _wreck(L, base, front, turret_img, gun_img)
	row["wreck"] = _add(wreck["img"], Vector2i.ZERO)
	row["wreck_sil"] = _add(_silhouette(wreck["img"]), Vector2i.ZERO)
	row["wreck_fires"] = wreck["fires"]
	var first: Array = (wreck["fires"] as Array)[0]
	row["wreck_fire"] = [first[0], first[1]]
	row["shadow"] = _add(_shadow(sz.x), Vector2i.ZERO)
	row["shadow_at"] = [-SHADOW_PAD, float(L["ground"]) - 2.0]
	if L.has("furnace"):
		var fr: Rect2i = L["furnace"]
		row["furnace"] = [fr.position.x, fr.position.y, fr.size.x, fr.size.y]
	if L.has("bogies"):
		_bogies(row, L)
	return row


## Hull and skirts: Hull.build on the layout, the belly's arms and springs behind where the wheels ride,
## recon's arches, the weathering, the moon, the palette.
func _hull_image(id: String, L: Dictionary) -> Dictionary:
	var sz: Vector2i = L["size"]
	var parts: Array = []
	parts.append_array(L["parts"])
	parts.append_array(L.get("front_parts", []))
	var details: Array = []
	details.append_array(L["details"])
	details.append_array(L.get("front_details", []))
	var HL := {"enemy": true, "size": sz, "parts": parts, "details": details}
	var B := Hull.build(HL)
	var img: Image = B["img"]
	var front: Image = B["front"]
	_belly(img, L)
	_posts(img, L)
	_arches(img, L)
	_spare(img, L)
	_net(img, L)
	_mount(img, L)
	_furnace(img, L)
	_ports(img, L)
	if L.has("secondary"):
		_secondary(img, L)
	_skirt_hangers(img, front)
	var span := _span(L)
	# finish.gd's speckle pass takes single bright pixels, so the rivets go on after it, last of all
	img = _finish(img, sz)
	_wear_fasteners(img, int(L.get("seed", 3)))
	_weather(img, B["mask"], sz, int(L.get("seed", 3)))
	_snap(img)
	_night(img, span.x, span.y)
	_moon_rim(img)
	_rivet_seams(img, L["parts"], L["details"], span)
	if not front.is_invisible():
		front = _finish(front, sz)
		_wear_fasteners(front, 6)
		_weather(front, PackedByteArray(), sz, 5)
		_snap(front)
		_night(front, span.x, span.y)
		_under_overhang(front)
		_rivet_seams(front, L.get("front_parts", []), L.get("front_details", []), span)
	if id == "destroyer":
		var g: Vector2i = L["glint"]
		Px.rect(img, Rect2i(g.x - 2, g.y - 1, 5, 4), OUTLINE)
		Px.rect(img, Rect2i(g.x - 1, g.y, 3, 2), GLASS_DARK)
		Px.put(img, g.x, g.y, SLIT_GLOW)
	return {"base": img, "front": front}


## The rows the night falls over: the hull's deck to the road.
func _span(L: Dictionary) -> Vector2i:
	var top := int(L["ground"])
	for part: Dictionary in L["parts"]:
		top = mini(top, Px.poly_bounds(part["poly"]).position.y)
	return Vector2i(top, int(L.get("night_low", L["ground"])))


func _finish(img: Image, sz: Vector2i) -> Image:
	var fl := {
		"rooms": {}, "shaft": Rect2i(), "rackwin": Rect2i(), "breechwin": Rect2i(), "boxwin": Rect2i(), "boxwin2": Rect2i(),
		"cuts": [], "crate": Rect2i(), "plaques": [], "details": [], "gear": {"skirt_y": sz.y},
	}
	return Finish.apply(img, fl)["img"]


func _turret_image(L: Dictionary) -> Image:
	var sz: Vector2i = L["size"]
	var TL := {"enemy": true, "size": sz, "parts": L["turret_parts"], "details": L.get("turret_details", [])}
	var B := Hull.build(TL)
	var img: Image = _finish(B["img"], sz)
	_wear_fasteners(img, 8)
	_weather(img, B["mask"], sz, 9)
	_snap(img)
	var span := _span(L)
	_night(img, span.x, span.y)
	_moon_rim(img)
	_rivet_seams(img, L["turret_parts"], L.get("turret_details", []), span)
	return img


func _turret_row(row: Dictionary, L: Dictionary, img: Image) -> void:
	var bb := img.get_used_rect()
	var cut := img.get_region(bb)
	var r := _add(cut, Vector2i.ZERO)
	row["turret"] = {"rect": r, "at": [bb.position.x, bb.position.y], "pivot": [float(L["pivot_x"]), float(bb.end.y)]}


## A soft 2 px cast shadow on the deck under the turret's lower edge.
func _turret_shadow(base: Image, turret: Image) -> void:
	var w := base.get_width()
	var h := base.get_height()
	for x in w:
		var low := -1
		for y in range(h - 1, -1, -1):
			if turret.get_pixel(x, y).a > 0.5:
				low = y
				break
		if low < 0:
			continue
		for k in 3:
			var y2 := low + 1 + k
			if y2 < h and base.get_pixel(x, y2).a > 0.5 and not _keeps(base.get_pixel(x, y2)):
				Px.mix(base, x, y2, COLD[2], 0.55 - 0.15 * k)


# --- hull furniture ----------------------------------------------------------------------------------------


## Behind the wheels: a dark belly, a trailing arm and a coil spring for each road wheel (as v3's
## Gear.draw_back), baked: the wheels move a few px over them.
func _belly(img: Image, L: Dictionary) -> void:
	var g: Dictionary = L["gear"]
	var wheels: Array = g["wheels"]
	if wheels.is_empty():
		return
	var top := 1e9
	var low := -1e9
	var x0 := 1e9
	var x1 := -1e9
	for w: Dictionary in wheels:
		var r := float(w["r"])
		top = minf(top, float(w["y"]) - r)
		low = maxf(low, float(w["y"]))
		x0 = minf(x0, float(w["x"]) - r)
		x1 = maxf(x1, float(w["x"]) + r)
	# the belly band between the hull's plates and the wheels' hubs
	for y in range(int(top) - 1, int(low) + 1):
		for x in range(int(x0) + 1, int(x1)):
			var k := float(y - top) / maxf(low - top, 1.0)
			Px.put(img, x, y, COLD[1] if k > 0.4 or (x + y) % 3 else COLD[3])
	for w2: Dictionary in wheels:
		if bool(w2.get("far", false)):
			continue
		var r2 := float(w2["r"])
		var c := Vector2(float(w2["x"]), float(w2["y"]))
		var stop := c + Vector2(2.5, -r2 - 4.0)
		var n := maxi(ceili(c.distance_to(stop)), 1)
		for k2 in n + 1:
			var q := c.lerp(stop, float(k2) / n) + Vector2(1, 0)
			Px.put(img, floori(q.x), floori(q.y), COLD[12] if k2 % 2 == 0 else COLD[3])
			Px.put(img, floori(q.x) + 1, floori(q.y), COLD[7] if k2 % 2 == 0 else COLD[3])
		var piv := c + Vector2(-r2 + 0.5, -r2 * 0.6)
		Px.linef(img, c + Vector2(0, 1), piv + Vector2(0, 1), COLD[3])
		Px.linef(img, c, piv, COLD[8])
		Px.put(img, floori(piv.x), floori(piv.y), COLD[12])


## Skirt hangers: a short bright strap from each plate's top up into the hull behind it.
func _skirt_hangers(img: Image, front: Image) -> void:
	if front.is_invisible():
		return
	var bb := front.get_used_rect()
	var x := bb.position.x + 4
	while x < bb.end.x - 2:
		if front.get_pixel(x, bb.position.y + 1).a > 0.5:
			for y in range(bb.position.y - 3, bb.position.y):
				Px.put(img, x, y, COLD[12])
				Px.put(img, x + 1, y, COLD[1])
		x += 13


## Thin posts for the recon car's bedstead aerial.
func _posts(img: Image, L: Dictionary) -> void:
	for p: Array in L.get("posts", []):
		var x := int(p[0])
		for y in range(int(p[1]), int(p[2]) + 1):
			Px.put(img, x, y, COLD[11])


## The recon car's wheel arches: a dark mouth in the hull with a lit lip above it.
func _arches(img: Image, L: Dictionary) -> void:
	for a: Dictionary in L.get("arches", []):
		var c: Vector2 = a["c"]
		var r := float(a["r"])
		var ri := ceili(r) + 2
		for y in range(int(c.y) - ri, int(c.y) + 3):
			for x in range(int(c.x) - ri, int(c.x) + ri + 1):
				if img.get_pixel(x, y).a < 0.5:
					continue
				var rho := Vector2(x + 0.5, y + 0.5).distance_to(c)
				if rho < r:
					Px.put(img, x, y, COLD[1])
				elif rho < r + 1.0:
					Px.put(img, x, y, COLD[14])
				elif rho < r + 2.0:
					Px.put(img, x, y, OUTLINE)


func _spare(img: Image, L: Dictionary) -> void:
	if L.has("spare"):
		var s: Dictionary = L["spare"]
		_tyre(img, s["c"], float(s["r"]), 0.3)


## The destroyer's rolled net: a lumpy bundle on the deck, ropes every few px.
func _net(img: Image, L: Dictionary) -> void:
	if not L.has("net"):
		return
	var r: Rect2i = L["net"]["rect"]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var lump := 1.0 + sin(x * 0.9) * 0.8
			if float(y - r.position.y) < lump and Px.h2(x, 3, 91) < 0.8:
				continue
			var v := float(y - r.position.y) / r.size.y
			var col: Color = COLD[10] if v < 0.3 else (COLD[7] if v < 0.7 else COLD[4])
			if (x + y * 2) % 4 == 0:
				col = COLD[3]
			if (x - r.position.x) % 9 == 4:
				col = COLD[13]
			Px.put(img, x, y, col)
	for x2 in range(r.position.x, r.end.x):
		Px.put(img, x2, r.end.y, COLD[1])


## The destroyer's ball mount in the bow plate.
func _mount(img: Image, L: Dictionary) -> void:
	if not L.has("mount"):
		return
	var c: Vector2 = L["mount"]["c"]
	var r := float(L["mount"]["r"])
	for y in range(floori(c.y - r) - 1, ceili(c.y + r) + 2):
		for x in range(floori(c.x - r) - 1, ceili(c.x + r) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rho := d.length()
			if rho > r + 0.8:
				continue
			var lit := (-d.y * 0.8 - d.x * 0.3) / maxf(rho, 0.01)
			if rho > r:
				Px.put(img, x, y, OUTLINE)
			elif rho > r - 1.2:
				Px.put(img, x, y, COLD[13] if lit > 0.2 else COLD[4])
			else:
				Px.put(img, x, y, COLD[10] if lit > 0.4 else (COLD[7] if lit > -0.2 else COLD[4]))
	for k in 8:
		var a := TAU * k / 8.0
		var q := c + Vector2(cos(a), sin(a)) * (r - 0.6)
		Px.put(img, floori(q.x), floori(q.y), COLD[16])


## The Behemoth's furnace vent: bars over a dark mouth (draw_light adds the cold glow).
func _furnace(img: Image, L: Dictionary) -> void:
	if not L.has("furnace"):
		return
	var r: Rect2i = L["furnace"]
	Px.rect(img, r.grow(1), OUTLINE)
	Px.rect(img, r, GLASS_DARK)
	for x in range(r.position.x, r.end.x):
		if (x - r.position.x) % 4 == 3:
			for y in range(r.position.y, r.end.y):
				Px.put(img, x, y, COLD[10])
	for y2 in range(r.position.y + 2, r.end.y):
		for x2 in range(r.position.x, r.end.x):
			if (x2 - r.position.x) % 4 != 3:
				Px.put(img, x2, y2, SLIT_GLOW.darkened(0.55 + 0.1 * (r.end.y - y2)))


## The Behemoth's bow secondary, on its sponson.
func _secondary(img: Image, L: Dictionary) -> void:
	var s: Dictionary = L["secondary"]
	var o: Vector2 = s["pivot"]
	var ln := float(s["len"])
	Px.profile(img, o, PI, [
		[-2.0, 6.0, 2.6, 2.4, COLD[12], COLD[8], COLD[3]],
		[6.0, ln, 1.3, 1.3, COLD[12], COLD[8], COLD[3]],
		[ln - 3.0, ln, 1.8, 1.8, COLD[13], COLD[9], COLD[3]],
	], OUTLINE)


## Rivets one per 7-9 px along every seam and round each plated part's edge (Hull.build rivets only some
## plates): one bright head, its shadow down-right, never quite on a ruled line. A cast part takes only the
## seams it lists. Never on a detail, never doubling one already there.
func _rivet_seams(img: Image, parts: Array, details: Array, span: Vector2i) -> void:
	var skip: Array[Rect2i] = []
	for d: Dictionary in details:
		if d.has("rect"):
			skip.append((d["rect"] as Rect2i).grow(3))
		elif d.has("at"):
			skip.append(Rect2i(Vector2i(d["at"]) - Vector2i(5, 5), Vector2i(11, 11)))
	for part: Dictionary in parts:
		var poly: PackedVector2Array = part["poly"]
		var bb := Px.poly_bounds(poly)
		var step := int(part.get("rivet", 8))
		for sx: int in part.get("seams_x", []):
			var y := bb.position.y + 2
			while y < bb.end.y - 1:
				_rivet(img, poly, Vector2i(sx + 2 + _jog(sx, y), y), skip, span)
				y += _pace(step, sx, y)
		for sy: int in part.get("seams_y", []):
			var x := bb.position.x + 2
			while x < bb.end.x - 1:
				_rivet(img, poly, Vector2i(x, sy + 2 + _jog(x, sy)), skip, span)
				x += _pace(step, x, sy)
		if bool(part.get("cast", false)):
			continue
		var x2 := bb.position.x + 3
		while x2 < bb.end.x - 2:
			var top := -1
			var low := -1
			for y2 in range(bb.position.y, bb.end.y):
				if Px.in_poly(Vector2(x2 + 0.5, y2 + 0.5), poly):
					if top < 0:
						top = y2
					low = y2
			if top >= 0:
				_rivet(img, poly, Vector2i(x2, top + 3), skip, span)
				if low - top > 8:
					_rivet(img, poly, Vector2i(x2, low - 3), skip, span)
			x2 += _pace(step, x2, top)


## The next rivet's distance: 7, 8 or 9 px about the seam's step.
func _pace(step: int, a: int, b: int) -> int:
	var k := Px.h2(a, b, 41)
	return step - 1 if k < 0.3 else (step + 1 if k > 0.7 else step)


## A hand-set rivet sits a pixel off its line now and then.
func _jog(a: int, b: int) -> int:
	return 1 if Px.h2(a, b, 43) > 0.86 else 0


## One head on the finished picture. Grime takes some, in patches, and dims others; the road's dark dims the
## low ones. A head left bright may weep a short dark streak.
func _rivet(img: Image, poly: PackedVector2Array, p: Vector2i, skip: Array[Rect2i], span: Vector2i) -> void:
	for r in skip:
		if r.has_point(p):
			return
	for q: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
		if not Px.in_poly(Vector2(p + q) + Vector2(0.5, 0.5), poly):
			return
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if Px.inside(img, p.x + dx, p.y + dy) and _is_head(img.get_pixel(p.x + dx, p.y + dy)):
				return
	var grime := Px.vnoise(p.x, p.y, 11.0, 49)
	var roll := Px.h2(p.x, p.y, 47)
	if roll < 0.09 or (grime > 0.74 and roll < 0.55):
		return
	var k := _night_k(p.y, span.x, span.y)
	var dim := roll < 0.34 or grime > 0.62 or k < 0.42
	Px.put(img, p.x, p.y, RIV_DIM if dim else RIV_LIT)
	Px.put(img, p.x + 1, p.y + 1, COLD[1])
	if not dim and Px.h2(p.x, p.y, 51) > 0.5:
		var ln := 2 + floori(Px.h2(p.y, p.x, 53) * 5.0)
		for i in ln:
			var y := p.y + 2 + i
			if Px.inside(img, p.x, y) and Px.in_poly(Vector2(p.x + 0.5, y + 0.5), poly):
				var c := img.get_pixel(p.x, y)
				if not _keeps(c):
					img.set_pixel(p.x, y, _ramp_of(_lum(c) * (0.6 + 0.4 * float(i) / ln)))


func _is_head(c: Color) -> bool:
	return c.is_equal_approx(RIV_LIT) or c.is_equal_approx(RIV_DIM)


## Grime on the fasteners: in patches the heads are gone, under it they are dim; the rest keep their light.
func _wear_fasteners(img: Image, seed: int) -> void:
	var src := img.duplicate() as Image
	for y in src.get_height():
		for x in src.get_width():
			if not src.get_pixel(x, y).is_equal_approx(Hull.RIV_HI_EN):
				continue
			# finish.gd snaps its moonlit edges onto the same colour: a run or a top edge is no head
			if _in_run(src, x, y):
				img.set_pixel(x, y, COLD[12])
				continue
			var grime := Px.vnoise(x, y, 13.0, seed + 31)
			var r := Px.h2(x, y, seed + 32)
			if r < 0.08 or (grime > 0.68 and r < 0.5):
				# gone, and its shadow with it
				img.set_pixel(x, y, src.get_pixel(maxi(x - 1, 0), y))
				if Px.inside(img, x + 1, y + 1):
					img.set_pixel(x + 1, y + 1, src.get_pixel(x, mini(y + 1, src.get_height() - 1)))
			elif r < 0.34 or grime > 0.58:
				img.set_pixel(x, y, RIV_DIM)


func _in_run(src: Image, x: int, y: int) -> bool:
	for q: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if Px.inside(src, x + q.x, y + q.y) and src.get_pixel(x + q.x, y + q.y).is_equal_approx(Hull.RIV_HI_EN):
			return true
	return y < 2 or src.get_pixel(x, y - 2).a < 0.5


## The night on a finished, snapped picture (see NIGHT_K). Slit glass keeps its light; a head stays a head
## until the road's dark takes it.
func _night(img: Image, top: int, low: int) -> void:
	for y in img.get_height():
		var k := _night_k(y, top, low)
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or _is_glass(c):
				continue
			var head := c.is_equal_approx(Hull.RIV_HI_EN)
			if head or c.is_equal_approx(RIV_DIM):
				if k > 0.36:
					img.set_pixel(x, y, RIV_LIT if head and k > 0.5 else RIV_DIM)
				else:
					img.set_pixel(x, y, COLD[5])
				continue
			if c.is_equal_approx(OUTLINE):
				continue
			var d := 0.003 if (x + y) % 2 == 0 else -0.003
			img.set_pixel(x, y, _ramp_of(_lum(c) * k + d))


## The ramp's factor at a row.
func _night_k(y: int, top: int, low: int) -> float:
	var t := clampf(float(y - top) / maxf(float(low - top), 1.0), 0.0, 1.0)
	if t <= FALL_FROM:
		return NIGHT_K
	return NIGHT_K * lerpf(1.0, FALL_LOW, (t - FALL_FROM) / (1.0 - FALL_FROM))


## The night with no fall: a wheel sheet, a gun, a picture that moves over its rows.
func _night_flat(img: Image, k: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and not _is_glass(c) and not c.is_equal_approx(OUTLINE):
				img.set_pixel(x, y, _ramp_of(_lum(c) * k))


## The value's nearest step of the ramp proper (no moon, no heads, not the outline's own black).
func _ramp_of(l: float) -> Color:
	var best := 1
	var bd := INF
	for i in range(1, 16):
		var d := absf(_lum_cold[i] - l)
		if d < bd:
			bd = d
			best = i
	return COLD[best]


## The moon: its colder rim one row under an outline with open sky above it, in broken runs, a few pixels of
## it brighter. Nothing under an overhang gets any.
func _moon_rim(img: Image) -> void:
	var src := img.duplicate() as Image
	var w := src.get_width()
	var h := src.get_height()
	for x in w:
		for y in range(1, h - 1):
			if src.get_pixel(x, y).a < 0.5 or src.get_pixel(x, y - 1).a > 0.5:
				continue
			var open := true
			for k in range(2, RIM_CLEAR + 1):
				if y - k >= 0 and src.get_pixel(x, y - k).a > 0.5:
					open = false
					break
			if not open or Px.vnoise(x, y, 5.0, 7) < 0.42:
				continue
			var ry := y + 1
			var under := src.get_pixel(x, ry)
			if under.a > 0.5 and not _keeps(under):
				img.set_pixel(x, ry, COLD[19] if Px.h2(x / 2, y, 7) > 0.72 else COLD[18])


## A skirt hangs under the hull's overhang: no moon on it, its top rows in the hull's shade.
func _under_overhang(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for x in w:
		for y in range(1, h - 2):
			if src.get_pixel(x, y).a > 0.5 and src.get_pixel(x, y - 1).a < 0.5:
				img.set_pixel(x, y + 1, COLD[2])
				if not _keeps(src.get_pixel(x, y + 2)) and src.get_pixel(x, y + 2).a > 0.5:
					img.set_pixel(x, y + 2, COLD[3] if (x + y) % 2 == 0 else src.get_pixel(x, y + 2))


## The Behemoth's portholes: a riveted ring round dark glass; the odd one catches the moon.
func _ports(img: Image, L: Dictionary) -> void:
	for p: Array in L.get("ports", []):
		var c := Vector2i(int(p[0]), int(p[1]))
		Px.rect(img, Rect2i(c.x - 2, c.y - 2, 5, 5), OUTLINE)
		Px.rect(img, Rect2i(c.x - 1, c.y - 2, 3, 1), COLD[13])
		Px.rect(img, Rect2i(c.x - 2, c.y - 1, 1, 3), COLD[10])
		Px.rect(img, Rect2i(c.x - 1, c.y - 1, 3, 3), GLASS_DARK)
		if (c.x + c.y) % 3 == 0:
			Px.put(img, c.x - 1, c.y - 1, COLD[18])


## Weathering (Hull.build leaves it out on enemies): streaks running down from fasteners, grime low on
## each plate's run, and pale dust on upward faces. Tones of the cold ramp only.
func _weather(img: Image, _mask: PackedByteArray, sz: Vector2i, seed: int) -> void:
	var src := img.duplicate() as Image
	for y in sz.y:
		for x in sz.x:
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			# grime: the lower part of every run of plate darkens in a dither
			var depth := 0
			for k in range(1, 14):
				if y + k >= sz.y or src.get_pixel(x, y + k).a < 0.5:
					break
				depth = k
			var grime := Px.vnoise(x, y, 9.0, seed) * 0.5 + (1.0 - clampf(depth / 8.0, 0.0, 1.0)) * 0.55
			if grime > 0.62 and Px.h2(x, y, seed + 1) < (grime - 0.5) * 1.5:
				Px.mix(img, x, y, COLD[2], 0.55)
			# dust on what faces up
			if y > 0 and src.get_pixel(x, y - 1).a < 0.5 and Px.h2(x, y, seed + 2) > 0.8:
				continue
			# a streak under a bright fastener
			if c.is_equal_approx(Hull.RIV_HI_EN) and Px.h2(x, y, seed + 3) > 0.55:
				var ln := 3 + floori(Px.h2(y, x, seed + 4) * 9.0)
				for k2 in ln:
					var yy := y + 2 + k2
					if yy < sz.y and src.get_pixel(x, yy).a > 0.5:
						Px.mix(img, x, yy, COLD[1], 0.8 * (1.0 - float(k2) / ln))
			# worn bare in patches: a pale scuff where the noise says, never on the darkest seams
			if _lum(c) > 0.1 and Px.vnoise(x, y, 5.0, seed + 5) > 0.74 and Px.h2(x, y, seed + 6) > 0.72:
				Px.mix(img, x, y, COLD[13], 0.5)


func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.55 + c.b * 0.15


## Every opaque pixel onto the cold palette by value (slit colours stay).
func _snap(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				if c.a > 0.0:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if _keeps(c):
				continue
			img.set_pixel(x, y, _cold_of(c))


func _is_glass(c: Color) -> bool:
	return c.is_equal_approx(SLIT_CORE) or c.is_equal_approx(SLIT_GLOW) or c.is_equal_approx(GLASS_DARK)


func _keeps(c: Color) -> bool:
	return (
		_is_glass(c) or c.is_equal_approx(RIV_LIT) or c.is_equal_approx(RIV_DIM) or c.is_equal_approx(Hull.RIV_HI_EN)
	)


func _cold_of(c: Color) -> Color:
	var l := _lum(c)
	var best := COLD[0]
	var bd := INF
	var moonish := c.b > c.g * 1.08 and c.b > c.r * 1.08 and l > 0.25
	for i in COLD.size():
		var is_moon := i >= 18
		# the heads' colour is only ever a head's
		if is_moon != moonish or i == 16:
			continue
		var d := absf(_lum_cold[i] - l)
		if d < bd:
			bd = d
			best = COLD[i]
	return best


## The slits on a picture: a hood above, the glass with its bright core.
func _slits(img: Image, L: Dictionary, layer: Variant) -> void:
	var want := int(layer) if not (layer is bool) else 0
	for s: Array in L.get("slits", []):
		if int(s[3]) != want:
			continue
		var x := int(s[0])
		var y := int(s[1])
		var w := int(s[2])
		Px.rect(img, Rect2i(x - 1, y - 2, w + 2, 1), COLD[9])
		Px.rect(img, Rect2i(x - 1, y - 1, w + 2, 1), OUTLINE)
		Px.rect(img, Rect2i(x, y, w, 1), SLIT_GLOW)
		Px.rect(img, Rect2i(x + w / 2, y, maxi(w / 3, 1), 1), SLIT_CORE)
		Px.rect(img, Rect2i(x - 1, y + 1, w + 2, 1), OUTLINE)
	for lamp: Array in L.get("lamps", []):
		if want != 0:
			continue
		var lx := int(lamp[0])
		var ly := int(lamp[1])
		Px.rect(img, Rect2i(lx - 2, ly - 3, 5, 2), COLD[8])
		Px.rect(img, Rect2i(lx - 2, ly - 1, 4, 4), OUTLINE)
		Px.rect(img, Rect2i(lx - 1, ly, 3, 2), SLIT_GLOW)
		Px.put(img, lx + 1, ly, SLIT_CORE)


# --- gun ---------------------------------------------------------------------------------------------------


func _gun_row(row: Dictionary, L: Dictionary) -> Image:
	var g: Dictionary = L["gun"]
	var ln := float(g["len"])
	var style := str(g.get("style", "cannon"))
	var hw := 2.0 if style == "mg" else (3.0 if style == "cannon" else 4.0)
	if ln >= 90.0 or style == "big":
		hw = 5.0
	var o := Vector2(0.0, ceilf(hw) + 2.0)
	var h := int(o.y) * 2 + 1
	var img := Px.blank(int(ceil(ln)) + 3, h)
	var lit := COLD[15]
	var a := COLD[12]
	var b := COLD[8]
	var c := COLD[3]
	if style == "mg":
		Px.profile(img, o, 0.0, [
			[0.0, ln * 0.45, 1.6, 1.4, a, b, c],
			[ln * 0.45, ln, 0.9, 0.9, a, b, c],
			[ln - 2.0, ln, 1.3, 1.3, lit, b, c],
		], OUTLINE)
	elif style == "cannon":
		var bh := hw * 0.5
		Px.profile(img, o, 0.0, [
			[0.0, ln * 0.3, bh + 0.8, bh + 0.5, a, b, c],
			[ln * 0.3, ln * 0.8, bh, bh * 0.9, a, b, c],
			[ln * 0.3 - 1.0, ln * 0.3, bh + 0.9, bh + 0.9, lit, a, c],
			[ln * 0.8, ln - 1.0, bh, bh, a, b, c],
			[ln - 2.0, ln, bh + 0.6, bh + 0.6, lit, a, c],
		], OUTLINE)
	elif style == "big":
		# the heavy's: a thick tube and a great double-baffle brake, the biggest thing on its outline
		Px.profile(img, o, 0.0, [
			[0.0, ln * 0.26, 3.2, 2.7, a, b, c],
			[ln * 0.26, ln - 13.0, 2.0, 1.8, a, b, c],
			[ln * 0.5 - 1.0, ln * 0.5 + 1.0, 3.0, 3.0, lit, a, c],
			[ln - 13.0, ln - 9.0, 4.4, 4.4, lit, a, c],
			[ln - 9.0, ln - 6.0, 1.8, 1.8, c, c, c],
			[ln - 6.0, ln, 4.4, 4.4, lit, a, c],
		], OUTLINE)
	else:
		var bh2 := hw * 0.5
		Px.profile(img, o, 0.0, [
			[0.0, ln * 0.28, bh2 + 1.0, bh2 + 0.7, a, b, c],
			[ln * 0.28, ln * 0.62, bh2 + 0.1, bh2 * 0.95, a, b, c],
			[ln * 0.62 - 1.0, ln * 0.62 + 1.0, bh2 + 1.0, bh2 + 1.0, lit, a, c],
			[ln * 0.62 + 1.0, ln - 8.0, bh2 * 0.9, bh2 * 0.85, a, b, c],
			[ln - 8.0, ln - 5.0, bh2 + 1.6, bh2 + 1.6, lit, a, c],
			[ln - 5.0, ln - 3.0, bh2 * 0.6, bh2 * 0.6, c, c, c],
			[ln - 3.0, ln, bh2 + 1.6, bh2 + 1.6, lit, a, c],
		], OUTLINE)
	_snap(img)
	_night_flat(img, GUN_K)
	var tr: Vector2 = g["trunnion"]
	var face := float(L["faces"])
	var r := _add(img, Vector2i.ZERO)
	var sil := _add(_silhouette(img), Vector2i.ZERO)
	row["gun"] = {"rect": r, "sil": sil, "trunnion": [tr.x, tr.y], "len": ln, "origin": [o.x, o.y]}
	if g.has("elev"):
		row["gun"]["elev"] = g["elev"]
	row["muzzle_at_0"] = [tr.x + face * ln, tr.y]
	if L.has("secondary"):
		var s: Dictionary = L["secondary"]
		row["secondary_muzzle"] = [(s["pivot"] as Vector2).x - float(s["len"]), (s["pivot"] as Vector2).y]
	return img


# --- running gear ------------------------------------------------------------------------------------------


func _gear_row(row: Dictionary, L: Dictionary) -> void:
	var g: Dictionary = L["gear"]
	var out := {"T": float(g["T"]), "up": float(g["up"]), "droop": float(g["droop"])}
	var wheels: Array = []
	for w: Dictionary in g["wheels"]:
		var e := {"x": w["x"], "y": w["y"], "r": w["r"]}
		if bool(w.get("far", false)):
			e["far"] = true
		wheels.append(e)
	out["wheels"] = wheels
	var rollers: Array = []
	for r2: Dictionary in g.get("rollers", []):
		rollers.append({"c": _v(r2["c"]), "r": r2["r"]})
	out["rollers"] = rollers
	var sheets := {}
	var w0: Dictionary = g["wheels"][0]
	if bool(g.get("tyres", false)):
		sheets["road"] = _tyre_sheet(float(w0["r"]))
	else:
		var holes := 6.0 if float(w0["r"]) > 5.0 else 3.0
		sheets["road"] = _sheet("road", float(w0["r"]), 12, TAU / holes)
		if g.has("sprocket"):
			var sp: Dictionary = g["sprocket"]
			out["sprocket"] = {"c": _v(sp["c"]), "r": sp["r"]}
			sheets["sprocket"] = _sheet("sprocket", float(sp["r"]), 12, TAU / 5.0)
		if g.has("idler"):
			var idl: Dictionary = g["idler"]
			out["idler"] = {"c": _v(idl["c"]), "r": idl["r"]}
			sheets["idler"] = _sheet("idler", float(idl["r"]), 12, TAU / 4.0)
		var rl: Array = g.get("rollers", [])
		if L.has("bogies"):
			rl = (L["bogies"][0] as Dictionary)["rollers"]
			var s0: Dictionary = (L["bogies"][0] as Dictionary)["sprocket"]
			sheets["sprocket"] = _sheet("sprocket", float(s0["r"]), 12, TAU / 5.0)
		if not rl.is_empty():
			sheets["roller"] = _sheet("roller", float((rl[0] as Dictionary)["r"]), 6, TAU / 3.0)
		row["track"] = _track(float(g["T"]), float(L["pitch"]))
	row["gear"] = out
	row["sheets"] = sheets


func _sheet(kind: String, r: float, frames: int, period: float) -> Dictionary:
	var key := "%s|%.1f" % [kind, r]
	var half := ceili(r) + (4 if kind == "sprocket" else 2)
	var size := half * 2
	if not _sheets.has(key):
		var img := Px.blank(size * frames, size)
		for k in frames:
			var one := Px.blank(size, size)
			_wheel(one, Vector2(half, half), r, period * k / frames, kind)
			img.blend_rect(one, Rect2i(0, 0, size, size), Vector2i(k * size, 0))
		_snap(img)
		_night_flat(img, WHEEL_K)
		_sheets[key] = _add(img, Vector2i.ZERO)
	return {"rect": _sheets[key], "frames": frames, "period": period, "size": size, "r": r}


## The small wheels' own drawing (Gear.draw_wheel is tuned for the tank's 12 px and up; at 4-10 px its
## bolt ring reads as a glyph): a tyre or a toothed rim, a lit rim, a dished web with holes that show the
## turn, a hub. kind: road, sprocket, idler, roller. Lit from the top left, as everything is.
func _wheel(img: Image, c: Vector2, r: float, ang: float, kind: String) -> void:
	var ext := r + (2.5 if kind == "sprocket" else 1.0)
	var holes := 6 if r > 5.0 else 3
	if kind == "sprocket":
		holes = 5
	elif kind == "idler":
		holes = 4
	for y in range(floori(c.y - ext) - 1, ceili(c.y + ext) + 1):
		for x in range(floori(c.x - ext) - 1, ceili(c.x + ext) + 1):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rho := d.length()
			if rho > ext:
				continue
			var phi := atan2(d.y, d.x) - ang
			var lit := (-d.y * 0.8 - d.x * 0.3) / maxf(rho, 0.01)
			var col := Color(0, 0, 0, 0)
			if kind == "sprocket" and rho > r:
				var tv := cos(10.0 * phi)
				if tv > 0.25 + (rho - r) * 0.2:
					# lighter than the belt behind them, so the engagement reads
					col = OUTLINE if rho > r + 1.8 else (COLD[15] if lit > -0.3 else COLD[11])
				elif rho < r + 0.8:
					col = OUTLINE
			elif rho > r + 0.7:
				continue
			elif rho > r:
				col = OUTLINE
			elif kind == "roller":
				col = (COLD[13] if lit > 0.2 else COLD[8]) if rho > 0.8 else COLD[3]
			elif kind == "road" and rho > r - 1.2:
				col = COLD[6] if lit > 0.35 else COLD[2]
			elif rho > r - (2.3 if kind == "road" else 1.6):
				if kind == "sprocket":
					col = COLD[11] if lit > 0.15 else (COLD[7] if lit > -0.5 else COLD[4])
				else:
					col = COLD[14] if lit > 0.15 else (COLD[9] if lit > -0.5 else COLD[6])
			elif rho < maxf(r * 0.3, 1.5):
				# the hub, the brightest thing on a wheel: even a little wheel shows it
				col = COLD[4] if rho < 0.7 else (COLD[14] if lit > -0.2 else COLD[11])
			else:
				col = COLD[7] if lit > 0.1 else COLD[4]
				# the holes (or, on a little wheel, a dark dimple): they carry the rotation
				var ha := fposmod(phi, TAU / holes)
				ha = minf(ha, TAU / holes - ha)
				var hr := r * 0.58
				var q := Vector2(hr * ha, rho - hr)
				if q.length() < maxf(r * 0.17, 0.9):
					col = COLD[1]
				elif q.length() < maxf(r * 0.17, 0.9) + 0.8 and lit < 0.0:
					col = COLD[9]
			if col.a > 0.0:
				Px.put(img, x, y, col)


func _tyre_sheet(r: float) -> Dictionary:
	var frames := 10
	var period := TAU / 5.0
	var key := "tyre|%.1f" % r
	var half := ceili(r) + 2
	var size := half * 2
	if not _sheets.has(key):
		var img := Px.blank(size * frames, size)
		for k in frames:
			var one := Px.blank(size, size)
			_tyre(one, Vector2(half, half), r, period * k / frames)
			img.blend_rect(one, Rect2i(0, 0, size, size), Vector2i(k * size, 0))
		_snap(img)
		_night_flat(img, WHEEL_K)
		_sheets[key] = _add(img, Vector2i.ZERO)
	return {"rect": _sheets[key], "frames": frames, "period": period, "size": size, "r": r}


## A spoked tyre: dark rubber with tread notches, a pale rim, five spokes round a hub.
func _tyre(img: Image, c: Vector2, r: float, ang: float) -> void:
	for y in range(floori(c.y - r) - 2, ceili(c.y + r) + 2):
		for x in range(floori(c.x - r) - 2, ceili(c.x + r) + 2):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rho := d.length()
			if rho > r + 0.7:
				continue
			var phi := atan2(d.y, d.x) - ang
			var lit := (-d.y * 0.8 - d.x * 0.3) / maxf(rho, 0.01)
			var col := Color(0, 0, 0, 0)
			if rho > r:
				col = OUTLINE if cos(10.0 * phi) > -0.3 else Color(0, 0, 0, 0)
			elif rho > r - 1.6:
				col = COLD[4] if lit > 0.4 else COLD[1]
				if cos(10.0 * phi) > 0.6:
					col = COLD[6] if lit > 0.2 else COLD[3]
			elif rho > r - 2.6:
				col = COLD[14] if lit > 0.1 else COLD[8]
			elif rho < 1.2:
				col = COLD[16]
			elif rho < 2.0:
				col = COLD[9]
			else:
				var sp := fposmod(phi, TAU / 5.0)
				sp = minf(sp, TAU / 5.0 - sp) * rho
				col = (COLD[12] if lit > 0.0 else COLD[8]) if sp < 0.9 else COLD[1]
			if col.a > 0.0:
				Px.put(img, x, y, col)


## One track shoe as bake.gd _track paints it, with the enemy's colours: `sub_u` samples per px along,
## 2 per px across, the lit rows over the unlit ones.
func _track(thick: float, pitch: float) -> Dictionary:
	var key := "track|%.1f|%.1f" % [thick, pitch]
	var sub_u := 4
	var rows := int((thick + 4.0) * 2.0)
	if not _sheets.has(key):
		var img := Px.blank(int(pitch * sub_u), rows * 2)
		var horn0 := pitch * 0.35
		var horn1 := horn0 + 1.6
		var gr0 := pitch * 0.25
		var gr1 := gr0 + maxf(pitch * 0.45, 1.6)
		for lit_i in 2:
			var lit := lit_i == 0
			# the belt is dark iron: a dull light on what faces up, almost none on the sides and the lower run
			var hi: Color = COLD[10] if lit else COLD[5]
			var mid: Color = COLD[8] if lit else COLD[4]
			var low: Color = COLD[6] if lit else COLD[3]
			var body: Color = COLD[4] if lit else COLD[2]
			var joint: Color = COLD[1]
			for iv in rows:
				var dd := -2.0 + (iv + 0.5) * 0.5
				for iu in img.get_width():
					var u := (iu + 0.5) / sub_u
					var horn := u >= horn0 and u < horn1
					var grouser := u >= gr0 and u < gr1
					var col := Color(0, 0, 0, 0)
					var outl := false
					if dd < -1.0:
						outl = horn
					elif dd < 0.0:
						if horn:
							col = mid if lit else low
						else:
							outl = true
					elif dd < 1.0:
						if lit:
							col = hi if u < 1.0 else (low if u > pitch - 1.0 else joint)
						else:
							col = hi if u < 1.0 else (low if u < pitch - 1.5 else joint)
					elif dd < thick - 1.0:
						col = joint if u < 0.7 else (low if lit else body)
						if dd < 2.0 and u >= 0.7 and u < 1.5:
							col = mid
					elif dd < thick:
						col = joint if u < 0.7 else (mid if lit else low)
					elif dd < thick + 1.0:
						if grouser:
							col = hi if lit else mid
						else:
							outl = true
					else:
						outl = grouser
					if col.a == 0.0 and outl:
						col = OUTLINE
					img.set_pixel(iu, lit_i * rows + iv, col)
		_sheets[key] = _add(img, Vector2i.ZERO)
	return {"rect": _sheets[key], "sub_u": sub_u, "rows": rows, "dd0": -2.0, "row_px": 0.5, "lit_ny": -0.35, "pitch": pitch}


# --- the Behemoth's bogies -----------------------------------------------------------------------------------


func _bogies(row: Dictionary, L: Dictionary) -> void:
	var out: Array = []
	var seed := 60
	for b: Dictionary in L["bogies"]:
		seed += 1
		var fr: Rect2i = b["frame"]
		var sz: Vector2i = L["size"]
		var part := {
			"poly": Layouts.P([fr.position.x, fr.position.y, fr.end.x, fr.position.y, fr.end.x + 2, fr.end.y, fr.position.x - 2, fr.end.y]),
			"seams_x": [fr.position.x + fr.size.x / 3, fr.position.x + 2 * fr.size.x / 3],
			"split": false, "seed": seed, "rivet": 8, "tone": 0.04,
		}
		var B := Hull.build({"enemy": true, "size": sz, "parts": [part], "details": []})
		var img: Image = _finish(B["img"], sz)
		_weather(img, B["mask"], sz, seed)
		_snap(img)
		var span := _span(L)
		_night(img, span.x, span.y)
		_under_overhang(img)
		_rivet_seams(img, [part], [], span)
		var bb := img.get_used_rect()
		var rect := _add(img.get_region(bb), Vector2i.ZERO)
		# wrecked: the frame charred, the wheels baked on it, the track fallen off, gaps torn
		var w := Px.blank(sz.x, sz.y)
		for wh: Dictionary in b["wheels"]:
			var c := Vector2(float(wh["x"]), float(wh["y"]) + 1.0)
			_wheel(w, c, float(wh["r"]), Px.h2(int(c.x), 4, seed) * TAU, "road")
		var sp: Dictionary = b["sprocket"]
		_wheel(w, (sp["c"] as Vector2) + Vector2(0, 2), float(sp["r"]), 0.4, "sprocket")
		_night_flat(w, WHEEL_K)
		w.blend_rect(img, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
		_fallen_track(w, b, seed)
		var mid := float(fr.position.x + fr.size.x / 2)
		var soot: Array[Vector3] = [Vector3(mid, float(fr.position.y + 4), 22.0)]
		_char(w, seed, soot)
		var wb := w.get_used_rect()
		var wrect := _add(w.get_region(wb), Vector2i.ZERO)
		var wh_out: Array = []
		for wh2: Dictionary in b["wheels"]:
			wh_out.append({"x": wh2["x"], "y": wh2["y"], "r": wh2["r"]})
		var rl: Array = []
		for r2: Dictionary in b["rollers"]:
			rl.append({"c": _v(r2["c"]), "r": r2["r"]})
		out.append({
			"rect": rect, "at": [bb.position.x, bb.position.y], "wrecked": wrect, "wrecked_at": [wb.position.x, wb.position.y],
			"x_offset": b["x_offset"], "wheels": wh_out, "rollers": rl, "sprocket": {"c": _v(sp["c"]), "r": sp["r"]},
		})
	row["bogies"] = out


## A thrown track: most of the run lies in one heavy length on the road under the bogie, a loose shoe or two
## beside it. Not a dashed line.
func _fallen_track(img: Image, b: Dictionary, seed: int) -> void:
	var wheels: Array = b["wheels"]
	var w0: Dictionary = wheels[0]
	var y := int(w0["y"]) + int(w0["r"]) + 2
	var x0 := int(w0["x"]) - 16
	_shoes_lying(img, x0, 11, y, 6.0, seed)
	_shoes_lying(img, x0 + 78, 2, y + 1, 6.0, seed + 1)


## A length of track lying on the road: `n` shoes end to end, a dark joint between them, kinked a row up or
## down where it fell.
func _shoes_lying(img: Image, x0: int, n: int, y: int, pitch: float, seed: int) -> void:
	var yy := y
	var p := int(pitch)
	for i in n:
		if i > 0 and Px.h2(i, 5, seed) > 0.72:
			yy = clampi(yy + (1 if Px.h2(i, 6, seed) > 0.5 else -1), y - 1, y + 1)
		var xi := x0 + i * p
		Px.rect(img, Rect2i(xi, yy, p, 2), COLD[9])
		Px.rect(img, Rect2i(xi, yy, p - 1, 1), COLD[12])
		Px.rect(img, Rect2i(xi + p - 1, yy, 1, 2), COLD[1])
		Px.rect(img, Rect2i(xi, yy + 2, p, 1), OUTLINE)


# --- pictures ------------------------------------------------------------------------------------------------


## The whole vehicle at rest, composed as the view composes it (for the silhouette and the wreck).
func _rest_picture(L: Dictionary, base: Image, front: Image, turret: Image, gun: Image) -> Image:
	var sz: Vector2i = L["size"]
	var img := Px.blank(sz.x, sz.y)
	img.blend_rect(base, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	var g: Dictionary = L["gear"]
	var run := Px.blank(sz.x, sz.y)
	if bool(g.get("tyres", false)):
		for w: Dictionary in g["wheels"]:
			if bool(w.get("far", false)):
				_tyre(run, Vector2(float(w["x"]), float(w["y"])), float(w["r"]), 0.2)
		for w2: Dictionary in g["wheels"]:
			if not bool(w2.get("far", false)):
				_tyre(run, Vector2(float(w2["x"]), float(w2["y"])), float(w2["r"]), 0.2)
	elif L.has("bogies"):
		for b: Dictionary in L["bogies"]:
			var sp: Dictionary = b["sprocket"]
			_rest_run(run, L, sp, null, b["rollers"], b["wheels"])
	else:
		_rest_run(run, L, g["sprocket"], g["idler"], g["rollers"], g["wheels"])
	_night_flat(run, WHEEL_K)
	img.blend_rect(run, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	img.blend_rect(front, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	if turret != null:
		img.blend_rect(turret, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	if gun != null:
		img.blend_rect(gun, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	return img


## One track run at rest: the belt round its circles, clockwise on screen from the leftmost end wheel.
func _rest_run(img: Image, L: Dictionary, sp: Dictionary, idl: Variant, rollers: Array, wheels: Array) -> void:
	var circles: Array = []
	var ends: Array = [sp]
	if idl != null:
		ends.append(idl)
	ends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["c"] as Vector2).x < (b["c"] as Vector2).x)
	circles.append({"c": ends[0]["c"], "r": float(ends[0]["r"]) + 0.5})
	for r2: Dictionary in rollers:
		circles.append({"c": r2["c"], "r": float(r2["r"]) + 0.5})
	if ends.size() > 1:
		circles.append({"c": ends[1]["c"], "r": float(ends[1]["r"]) + 0.5})
	for i in range(wheels.size() - 1, -1, -1):
		var w: Dictionary = wheels[i]
		circles.append({"c": Vector2(float(w["x"]), float(w["y"])), "r": float(w["r"]) + 0.5})
	Gear.draw_track(img, Gear.belt(circles), 0.0, float(L["gear"]["T"]), true)
	for w3: Dictionary in wheels:
		_wheel(img, Vector2(float(w3["x"]), float(w3["y"])), float(w3["r"]), 0.2, "road")
	for r3: Dictionary in rollers:
		_wheel(img, r3["c"], float(r3["r"]), 0.2, "roller")
	if idl != null:
		_wheel(img, idl["c"], float(idl["r"]), 0.2, "idler")
	_wheel(img, sp["c"], float(sp["r"]), 0.2, "sprocket")


## The picture's solid shape in white, every hole it encloses filled (the gaps between the wheels inside the
## belt too): the haze and the flash lay over it and leave no specks.
func _silhouette(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var q: Vector2i = stack.pop_back()
		if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or outside[q.y * w + q.x] == 1:
			continue
		if src.get_pixel(q.x, q.y).a > 0.5:
			continue
		outside[q.y * w + q.x] = 1
		stack.append(q + Vector2i(1, 0))
		stack.append(q + Vector2i(-1, 0))
		stack.append(q + Vector2i(0, 1))
		stack.append(q + Vector2i(0, -1))
	var o := Px.blank(w, h)
	for y2 in h:
		for x2 in w:
			if outside[y2 * w + x2] == 0:
				o.set_pixel(x2, y2, Color.WHITE)
	return o


## The ground's shade under a kind `w` wide: a soft dark bar, its rows thinning below the belt and its ends
## breaking up, baked so it batches on the one atlas.
func _shadow(w: int) -> Image:
	var sw := w + SHADOW_PAD * 2
	var o := Px.blank(sw, SHADOW_ROWS.size())
	for y in SHADOW_ROWS.size():
		var inset := y * 3
		for x in range(inset, sw - inset):
			var edge := minf(float(x - inset), float(sw - inset - 1 - x)) / 7.0
			var a: float = SHADOW_ROWS[y] * clampf(edge, 0.25, 1.0)
			o.set_pixel(x, y, Color(0.012, 0.014, 0.014, floorf(a * 8.0) / 8.0))
	return o


## The wreck: base, wheels, skirts on one picture; the turret knocked askew and the gun drooped 8 degrees
## (both RotSprite); bites out of the top edge, torn holes, plate tears, the track broken and thrown, burnt
## onto the burn ramp from the fires outward. {img, fires: [[x, y, flame height], ...]}.
func _wreck(L: Dictionary, base: Image, front: Image, turret: Image, gun: Image) -> Dictionary:
	var sz: Vector2i = L["size"]
	var seed := sz.x
	var img := _rest_picture(L, base, front, null, null)
	_throw_shoes(img, L, seed)
	var over := Px.blank(sz.x, sz.y)
	var g: Dictionary = L["gun"]
	var face := float(L["faces"])
	var tr: Vector2 = g["trunnion"]
	var knock := Vector2(-2.0 * face, 2.0)
	var flipped := gun.duplicate() as Image
	if face < 0.0:
		flipped.flip_x()
	var gh := float(gun.get_height()) * 0.5
	var piv := Vector2(0, gh) if face > 0.0 else Vector2(flipped.get_width(), gh)
	Px.rotate_rotsprite(Px.rotsprite_prep(flipped), face * deg_to_rad(8.0), piv, over, tr + knock)
	img.blend_rect(over, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	if turret != null:
		var tb := Px.blank(sz.x, sz.y)
		var pv := Vector2(float(L["pivot_x"]), float(turret.get_used_rect().end.y))
		Px.rotate_rotsprite(Px.rotsprite_prep(turret), face * deg_to_rad(-5.0), pv, tb, pv + knock)
		img.blend_rect(tb, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
	_bites(img, seed)
	var fires: Array[Vector3] = []
	var out: Array = []
	for f: Array in L["fires"]:
		var x := int(f[0])
		var top := _top_of(img, x)
		fires.append(Vector3(x, top + 2, float(f[1])))
		out.append([float(x), float(top + 2), float(f[1])])
	_char(img, seed, fires)
	return {"img": img, "fires": out}


## The first opaque row of a column (or of the nearest one that has any).
func _top_of(img: Image, x: int) -> int:
	for o: int in [0, 1, -1, 2, -2, 4, -4, 8, -8]:
		var cx := clampi(x + o, 0, img.get_width() - 1)
		for y in img.get_height():
			if img.get_pixel(cx, y).a > 0.5:
				return y
	return 0


## The track broke: one length of the lower run is gone and the wheels stand bare over it; that length lies on
## the road in a heavy kinked piece, a loose shoe further off.
func _throw_shoes(img: Image, L: Dictionary, seed: int) -> void:
	var gr := int(L["ground"])
	var w := img.get_width()
	var thick := float(L["gear"]["T"])
	if thick <= 0.0:
		return
	var x0 := int(lerpf(w * 0.18, w * 0.5, Px.h2(1, 2, seed)))
	var ln := int(w * (0.18 + 0.14 * Px.h2(1, 3, seed)))
	for x in range(x0, x0 + ln):
		for y in range(gr - ceili(thick) - 1, gr + 4):
			if Px.inside(img, x, y):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var pitch := float(L.get("pitch", 4.0))
	var n := maxi(int(float(ln) * 0.8 / pitch), 3)
	_shoes_lying(img, x0 - int(float(ln) * 0.2), n, gr, pitch, seed)
	_shoes_lying(img, x0 + ln + int(w * 0.09), 1, gr + 1, pitch, seed + 1)


## Bites out of the silhouette's top edge.
func _bites(img: Image, seed: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bb := img.get_used_rect()
	for k in 2 + w / 70:
		var bx := bb.position.x + int(Px.h2(k, 7, seed) * bb.size.x)
		var top := -1
		for y0 in range(bb.position.y, bb.end.y):
			if img.get_pixel(clampi(bx, 0, w - 1), y0).a > 0.5:
				top = y0
				break
		if top < 0:
			continue
		var rb := 2.0 + Px.h2(k, 8, seed) * (2.0 + w / 60.0)
		for y1 in range(top - 1, mini(top + ceili(rb) + 1, h)):
			for x1 in range(maxi(int(bx - rb) - 1, 0), mini(int(bx + rb) + 2, w)):
				var q := Vector2(x1 - bx, (y1 - top) * 1.3).length() + Px.h2(x1, y1, seed + 11) * 1.8
				if q < rb:
					img.set_pixel(x1, y1, Color(0, 0, 0, 0))


## The burn. Soot spreads from each fire, further upward: near one the plates are black; away from it they
## keep their seams and fasteners in burnt browns; ash lies only on the cool upward faces. Holes of different
## kinds (punched, gashed, burst), each torn out irregularly, then the mouths the fires come out of.
func _char(img: Image, seed: int, fires: Array[Vector3]) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bb := img.get_used_rect()
	var src := img.duplicate() as Image
	var reach := maxf(float(bb.size.x) * 0.2, 9.0)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var soot := 0.0
			for f in fires:
				var dv := Vector2(x - f.x, (y - f.y) * (0.5 if y < f.y else 1.2))
				soot = maxf(soot, exp(-dv.length() / (reach * (0.5 + f.z / 36.0))))
			# low down the burn is dirt: what is near the road loses its light first
			var low := smoothstep(0.55, 1.0, float(y - bb.position.y) / float(maxi(bb.size.y, 1)))
			var v := _lum(c) * lerpf(4.2, 2.4, low) + 0.1 - soot * 0.6
			v += (Px.vnoise(x, y, 2.5, seed) - 0.5) * 0.14 + (Px.vnoise(x, y, 8.0, seed + 1) - 0.5) * 0.1
			var col: Color = BURN[clampi(floori(v * BURN.size()), 0, BURN.size() - 1)]
			if y > 0 and src.get_pixel(x, y - 1).a < 0.5:
				if soot < 0.35 and Px.h2(x, y, seed + 3) > 0.7:
					col = ASH
				else:
					col = BURN[1] if soot > 0.5 else BURN[3]
			img.set_pixel(x, y, col)
	# holes: one big, the others smaller and of other kinds
	for k2 in 2 + w / 45:
		var c2 := Vector2(
			bb.position.x + Px.h2(k2, 1, seed) * bb.size.x, bb.position.y + bb.size.y * (0.22 + Px.h2(k2, 2, seed) * 0.46)
		)
		var big := 1.0 if k2 == 0 else (0.45 + 0.5 * Px.h2(k2, 3, seed))
		var kind := posmod(k2 + seed, 3)
		_hole(img, src, c2, (1.5 + w / 60.0) * big + 0.6, kind, seed + k2 * 7, false)
	for f2 in fires:
		_hole(img, src, Vector2(f2.x, f2.y + f2.z * 0.1), maxf(f2.z * 0.2, 1.6), 2, seed + int(f2.x), true)
	# plate tears: short splits, a lit bent lip on them
	for k3 in 1 + w / 50:
		var tx := bb.position.x + Px.h2(k3, 4, seed) * bb.size.x
		var ty := bb.position.y + bb.size.y * (0.25 + Px.h2(k3, 5, seed) * 0.45)
		var ln := 4 + int(Px.h2(k3, 6, seed) * w * 0.07)
		var slope := (Px.h2(k3, 9, seed) - 0.5) * 1.4
		for i in ln:
			var x3 := int(tx) + i
			var y3 := int(ty + i * slope + (Px.h2(i, k3, seed) - 0.5) * 1.4)
			if Px.inside(img, x3, y3) and src.get_pixel(x3, y3).a > 0.5:
				img.set_pixel(x3, y3, HOLE)
				if i % 2 == 0 and Px.inside(img, x3, y3 - 1) and src.get_pixel(x3, y3 - 1).a > 0.5:
					img.set_pixel(x3, y3 - 1, BURN[3])


## One torn hole. kind 0 a punched entry with petals of plate bent back, 1 a long gash along a slant, 2 a
## burst, ragged all round. A burning one's lower lip is lit by what is inside it; a cold one has no glow.
func _hole(img: Image, src: Image, c: Vector2, r: float, kind: int, seed: int, burning: bool) -> void:
	var dir := Vector2.from_angle(Px.h2(seed, 1, 23) * PI)
	var stretch := 2.4 if kind == 1 else (1.2 if kind == 2 else 1.0)
	var lobes := 5.0 if kind == 0 else 3.0
	var ragged := 0.35 if kind == 0 else (0.15 if kind == 1 else 0.5)
	var span := ceili(r * stretch * 1.6) + 2
	for y in range(int(c.y) - span, int(c.y) + span + 1):
		for x in range(int(c.x) - span, int(c.x) + span + 1):
			if not Px.inside(img, x, y) or src.get_pixel(x, y).a < 0.5:
				continue
			var v := Vector2(x + 0.5, y + 0.5) - c
			var a := v.dot(dir) / stretch
			var b := v.dot(dir.orthogonal()) * (stretch * 0.6 if stretch > 1.5 else 1.0)
			var ang := atan2(b, a)
			var rim := r * (1.0 + ragged * sin(ang * lobes + float(seed)) + ragged * 0.6 * sin(ang * 7.0 + seed * 0.7))
			rim += (Px.h2(x, y, seed + 2) - 0.5) * 0.8
			var rho := Vector2(a, b).length()
			if rho < rim - 0.8:
				img.set_pixel(x, y, HOLE if Px.h2(x, y, seed + 3) > 0.25 else BURN[0])
			elif rho < rim:
				img.set_pixel(x, y, BURN[0])
			elif rho < rim + 1.1 and Px.h2(x, y, seed + 4) > 0.3:
				var bent := v.dot(Vector2(-0.6, -0.8)) > 0.0
				if burning and not bent:
					img.set_pixel(x, y, BURN_LIP)
				elif bent:
					img.set_pixel(x, y, BURN[3])


func _crop_keep(img: Image) -> Image:
	return img


# --- the atlas -----------------------------------------------------------------------------------------------


## Registers a picture for the atlas; returns its slot (an index the row holds until _rects()).
func _add(img: Image, _o: Vector2i) -> Array:
	var slot := [0, 0, img.get_width(), img.get_height()]
	_parts.append({"img": img, "slot": slot})
	return slot


## A shelf packer, tallest first, 1 px gutter.
func _pack() -> Image:
	var order := _parts.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["img"] as Image).get_height() > (b["img"] as Image).get_height())
	var x := 0
	var y := 0
	var shelf := 0
	for e: Dictionary in order:
		var im: Image = e["img"]
		if x + im.get_width() > ATLAS_W:
			x = 0
			y += shelf + GUTTER
			shelf = 0
		var s: Array = e["slot"]
		s[0] = x
		s[1] = y
		x += im.get_width() + GUTTER
		shelf = maxi(shelf, im.get_height())
	var hh := y + shelf
	var atlas := Px.blank(ATLAS_W, hh)
	for e2: Dictionary in order:
		var s2: Array = e2["slot"]
		atlas.blit_rect(e2["img"], Rect2i(0, 0, s2[2], s2[3]), Vector2i(s2[0], s2[1]))
	assert(hh <= 2048, "the atlas outgrew 2048")
	return atlas


## The slots are arrays filled in place by _pack; nothing to do but keep them plain ints.
func _rects(_kinds: Dictionary) -> void:
	pass


func _v(p: Variant) -> Array:
	var q: Vector2 = Vector2(p)
	return [q.x, q.y]


# --- the bushes ------------------------------------------------------------------------------------------------


const LEAF: Array[Color] = [
	Color("#050a0b"), Color("#081010"), Color("#0c1614"), Color("#111d1a"), Color("#172620"), Color("#1f3027"), Color("#2a3d30"),
]
const LEAF_MOON := Color("#46605f")


## Six bushes, foot at the bottom centre: leaf clumps lit from the top left, a moonlit crown.
func _bushes() -> Dictionary:
	var sizes := [Vector2i(44, 26), Vector2i(64, 36), Vector2i(36, 22), Vector2i(82, 44), Vector2i(54, 40), Vector2i(72, 30)]
	var total := 0
	for s: Vector2i in sizes:
		total += s.x + 2
	var sheet := Px.blank(total, 46)
	var rects: Array = []
	var x := 0
	var seed := 201
	for s2: Vector2i in sizes:
		var one := _bush(s2, seed)
		seed += 13
		var used := one.get_used_rect()
		sheet.blit_rect(one, used, Vector2i(x, 46 - used.size.y))
		rects.append([x, 46 - used.size.y, used.size.x, used.size.y])
		x += used.size.x + 2
	sheet.save_png(ProjectSettings.globalize_path(OUT + "bushes.png"))
	return {"atlas": "bushes.png", "rects": rects}


func _bush(sz: Vector2i, seed: int) -> Image:
	var img := Px.blank(sz.x, sz.y)
	var val := PackedFloat32Array()
	val.resize(sz.x * sz.y)
	val.fill(-1.0)
	var clumps := 6 + sz.x / 8
	# back clumps first; each is a dome of leaf speckle
	for k in clumps:
		var fx := Px.h2(k, 1, seed)
		var cx := 3.0 + fx * (sz.x - 6.0)
		var span := 1.0 - absf(fx - 0.5) * 1.5
		var r := (sz.y * 0.2 + Px.h2(k, 3, seed) * sz.y * 0.16) * (0.6 + 0.4 * span)
		var cy := sz.y - r * 0.7 - Px.h2(k, 2, seed) * (sz.y * 0.55) * span
		for y in range(maxi(int(cy - r) - 1, 0), mini(int(cy + r) + 2, sz.y)):
			for x in range(maxi(int(cx - r) - 1, 0), mini(int(cx + r) + 2, sz.x)):
				var d := Vector2(x + 0.5 - cx, (y + 0.5 - cy) * 1.15)
				var rho := d.length() / r
				var edge := 1.0 - 0.28 * Px.vnoise(x, y, 2.0, seed + 5)
				if rho > edge:
					continue
				var v := 0.42 + (-d.y * 0.7 - d.x * 0.35) / r * 0.4 + (float(k) / clumps) * 0.14
				v += (Px.vnoise(x, y, 2.2, seed + k) - 0.5) * 0.55
				val[y * sz.x + x] = v
	for y2 in sz.y:
		for x2 in sz.x:
			var v2 := val[y2 * sz.x + x2]
			if v2 < -0.5:
				continue
			# the base sinks into the dark verge
			v2 -= pow(float(y2) / sz.y, 3.0) * 0.5
			var col := Px.dither(LEAF, clampf(v2, 0.0, 1.0), x2, y2)
			var up_clear := y2 == 0 or val[(y2 - 1) * sz.x + x2] < -0.5
			if up_clear and Px.h2(x2, y2, seed + 8) > 0.3:
				col = LEAF_MOON if Px.h2(x2, y2, seed + 9) > 0.55 else LEAF[6]
			elif _is_rim(val, sz, x2, y2):
				col = LEAF[0]
			img.set_pixel(x2, y2, col)
	return img


func _is_rim(val: PackedFloat32Array, sz: Vector2i, x: int, y: int) -> bool:
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
		var q := Vector2i(x, y) + o
		if q.x < 0 or q.y < 0 or q.x >= sz.x or q.y >= sz.y or val[q.y * sz.x + q.x] < -0.5:
			return true
	return false


# --- the far panel's ground ------------------------------------------------------------------------------------


const GROUND: Array[Color] = [
	Color("#07090a"), Color("#0a0d0d"), Color("#0e1211"), Color("#121715"), Color("#171c19"), Color("#1c221e"), Color("#232a24"), Color("#2c342c"),
]
const GROUND_W := 1024
const GROUND_H := 170


## A periodic value noise (period GROUND_W in x, so the band tiles).
func _pnoise(x: float, y: float, cells: int, seed: int) -> float:
	var cell := float(GROUND_W) / cells
	var fx := x / cell
	var fy := y / cell
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := lerpf(Px.h2(posmod(ix, cells), iy, seed), Px.h2(posmod(ix + 1, cells), iy, seed), tx)
	var b := lerpf(Px.h2(posmod(ix, cells), iy + 1, seed), Px.h2(posmod(ix + 1, cells), iy + 1, seed), tx)
	return lerpf(a, b, ty)


## The long lens's field: the far treeline's dark soft at the top (fading out, so the forest shows through),
## moonlit churned earth where the enemy stands (rows 40..100), two old track ruts that wander and rejoin
## round the band, stones and grass, the foreground soft and dark. Tiles in x.
func _far_ground() -> String:
	var img := Px.blank(GROUND_W, GROUND_H)
	var ruts: Array[PackedFloat32Array] = []
	for k in 3:
		var line := PackedFloat32Array()
		line.resize(GROUND_W)
		for x0 in GROUND_W:
			var t := TAU * x0 / GROUND_W
			line[x0] = 52.0 + k * 17.0 + 3.5 * sin(t * (2 + k) + k) + 2.0 * sin(t * (7 - k) + 2.0 * k)
		ruts.append(line)
	for y in GROUND_H:
		var fy := float(y) / GROUND_H
		for x in GROUND_W:
			var v := 0.3
			v += (_pnoise(x, y * 3.0, 32, 301) - 0.5) * 0.35
			v += (_pnoise(x, y * 2.0, 128, 302) - 0.5) * 0.3
			v += (_pnoise(x, y * 1.0, 512, 304) - 0.5) * 0.18
			# moonlit where the enemy stands
			v += 0.2 * exp(-pow((fy - 0.42) / 0.2, 2.0))
			for line2 in ruts:
				var dy := float(y) - line2[x]
				if dy >= 0.0 and dy < 2.0:
					v -= 0.2
				elif dy >= -1.0 and dy < 0.0:
					v += 0.14
			v -= smoothstep(0.62, 1.0, fy) * 0.42
			img.set_pixel(x, y, Px.dither(GROUND, clampf(v, 0.0, 1.0), x, y))
	for k2 in 420:
		var tx := int(Px.h2(k2, 1, 305) * GROUND_W)
		var ty := 26 + int(Px.h2(k2, 2, 305) * 120.0)
		if Px.h2(k2, 3, 305) < 0.72:
			var n := 2 + int(Px.h2(k2, 4, 305) * 4.0)
			for j in n:
				var hh := 1 + int(Px.h2(k2, j + 5, 305) * 3.0)
				for yy in hh:
					_put_wrap(img, tx + j, ty - yy, GROUND[6 if yy == hh - 1 else 3])
		else:
			_put_wrap(img, tx, ty, GROUND[7])
			_put_wrap(img, tx + 1, ty, GROUND[5])
			_put_wrap(img, tx, ty + 1, GROUND[1])
			_put_wrap(img, tx + 1, ty + 1, GROUND[0])
	var soft := _soften(img, 34, 5)
	soft = _soften_bottom(soft, GROUND_H - 40, 3)
	for y2 in 14:
		var a := floorf((float(y2) + 1.0) / 14.0 * 8.0) / 8.0
		for x2 in GROUND_W:
			var c := soft.get_pixel(x2, y2)
			c.a = a
			soft.set_pixel(x2, y2, c)
	soft.save_png(ProjectSettings.globalize_path(OUT + "far_ground.png"))
	return "far_ground.png"


func _put_wrap(img: Image, x: int, y: int, c: Color) -> void:
	if y >= 0 and y < GROUND_H:
		img.set_pixel(posmod(x, GROUND_W), y, c)


## Box blur rising towards row 0 (the depth of field baked in the top `rows`), then a fade to dark.
func _soften(img: Image, rows: int, rad: int) -> Image:
	var out := img.duplicate() as Image
	for y in rows:
		var k := 1.0 - float(y) / rows
		var r := maxi(roundi(rad * k * 2.0), 1)
		for x in GROUND_W:
			var c := Color(0, 0, 0, 1)
			var n := 0.0
			for o in range(-r, r + 1):
				var q := img.get_pixel(posmod(x + o, GROUND_W), y)
				c.r += q.r
				c.g += q.g
				c.b += q.b
				n += 1.0
			c = Color(c.r / n, c.g / n, c.b / n, 1.0)
			out.set_pixel(x, y, c.darkened(0.25 * k))
	return out


func _soften_bottom(img: Image, from_y: int, rad: int) -> Image:
	var out := img.duplicate() as Image
	for y in range(from_y, GROUND_H):
		var k := float(y - from_y) / (GROUND_H - from_y)
		var r := maxi(roundi(rad * k * 2.0), 1)
		for x in GROUND_W:
			var c := Color(0, 0, 0, 1)
			var n := 0.0
			for o in range(-r, r + 1):
				var q := img.get_pixel(posmod(x + o, GROUND_W), y)
				c.r += q.r
				c.g += q.g
				c.b += q.b
				n += 1.0
			out.set_pixel(x, y, Color(c.r / n, c.g / n, c.b / n, 1.0).darkened(0.3 * k))
	return out
