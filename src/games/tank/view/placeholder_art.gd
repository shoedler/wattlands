class_name TankPlaceholderArt
extends RefCounted
## Procedural stand-ins for every sprite id in assets/tank/art.json (brief 3: "draws any missing
## sprite at its size from palette shapes and logs once"). Owner: artqa.
##
## The view asks texture(id) for every sprite; it returns the pixelated PNG from
## assets/tank/sprites/<id>.png when it exists, else a generated texture of the sprite's size,
## cached per id, with one log line per missing sprite. Nothing here writes a PNG: the placeholders
## live in memory only (an art pass with WATTLANDS_ALLOW_ART replaces them file by file).
##
## What the drawings are: readable silhouettes of the brief's subjects in the 32 colours of
## art.json and nothing else. Every pixel is fully transparent or one opaque palette colour, so a
## placeholder survives the same checks as a pixelated sprite. Tanks face right, enemies and the
## Behemoth face left, wheels and gears are face-on, rooms are opaque back walls with an empty
## middle, backdrops are periodic across their width (tile + mirror strips). Never people, text,
## numbers, flags, insignia or markings: only slabs, rivets, machinery, wreckage and scenery.
## Deterministic: all weathering comes from an integer hash of the pixel and the sprite id.
##
## tests/games/tank/art/ checks size, palette, opacity, silhouettes and the log-once rule;
## tests/games/tank/art/dump_placeholders.gd renders contact sheets for a look.

const ART_JSON := "res://assets/tank/art.json"
const SPRITES_DIR := "res://assets/tank/sprites"

# The 32 colours of art.json by role (tested to be exactly the palette).
const G0 := Color("#07080a")
const G1 := Color("#0f1012")
const G2 := Color("#17181b")
const G3 := Color("#202124")
const G4 := Color("#2a2b2e")
const G5 := Color("#353739")
const G6 := Color("#424446")
const G7 := Color("#525456")
const G8 := Color("#666869")
const G9 := Color("#808182")
const G10 := Color("#a3a4a4")
const G11 := Color("#cfd0cf")
const B0 := Color("#17130f")
const B1 := Color("#241d17")
const B2 := Color("#33291f")
const B3 := Color("#443628")
const B4 := Color("#574634")
const B5 := Color("#6b5842")
const O0 := Color("#59636c")
const O1 := Color("#3d3c33")
const O2 := Color("#4b5561")
const R0 := Color("#3a2a24")
const R1 := Color("#5a3a2e")
const R2 := Color("#7d4f3a")
const F0 := Color("#e8743a")
const F1 := Color("#ffb35c")
const F2 := Color("#ffd99a")
const F3 := Color("#fff3d6")
const C0 := Color("#2e3944")
const C1 := Color("#5d86a3")
const C2 := Color("#9fc4dd")
const C3 := Color("#e6f3fb")
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)

static var _art: Dictionary = {}
static var _cache: Dictionary = {}
static var _logged: Dictionary = {}


## The sprite's texture: the generated PNG when present, else a placeholder of its size.
static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := SPRITES_DIR.path_join(id + ".png")
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
		if tex != null and (fills_rect(id) or is_steel(id)):
			var img := tex.get_image()
			if fills_rect(id):
				img = filled_image(img, size_of(id))
			if is_steel(id):
				img = graded_steel(img)
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = ImageTexture.create_from_image(placeholder_image(id))
		if not _logged.has(id):
			_logged[id] = true
			print("tank: placeholder art for %s" % id)
	_cache[id] = tex
	return tex


## True for the sprites whose silhouette must fill their whole art.json rect because rigs.json
## places rooms, wheels and the turret on it: the hulls and the Behemoth's hull. The image model
## does not hold a 3.6:1 box exactly, so a generated hull is fitted to its rect at load
## (filled_image), never left short with a transparent gap.
static func fills_rect(id: String) -> bool:
	return id.begins_with("hull_") or id == "boss_hull"


## `src` cropped to its opaque bounds and fitted to `size` without stretching its plates: scaled
## (Lanczos) to the rect's height keeping its aspect, then widened by repeating a band of armour
## columns from the middle (the image model holds 3:1 at most, the hulls are 3.6:1), so rivet
## spacing stays true. Only a too-wide result is squeezed. Then put back on the palette: alpha
## thresholded at 0.5 and every opaque pixel snapped to the nearest palette colour, so the result
## passes the same checks as a pixelated sprite. A sprite that already fills its rect comes back
## unchanged.
static func filled_image(src: Image, size: Vector2i) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size == Vector2i.ZERO or (used.position == Vector2i.ZERO and used.size == size):
		return img
	img = img.get_region(used)
	var fit_w := maxi(1, roundi(float(used.size.x) * float(size.y) / float(used.size.y)))
	if fit_w != used.size.x or size.y != used.size.y:
		img.resize(fit_w, size.y, Image.INTERPOLATE_LANCZOS)
	if fit_w < size.x:
		img = widened(img, size.x)
	elif fit_w > size.x:
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var pal := palette()
	var seen := {}
	for y in size.y:
		for x in size.x:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				img.set_pixel(x, y, CLEAR)
				continue
			var key := c.to_rgba32() | 0xff
			if not seen.has(key):
				seen[key] = _nearest(c, pal)
			img.set_pixel(x, y, seen[key])
	return img


## `img` widened to `width` by repeating the band of columns just left of its middle (a hull's plain
## armour panels), so the ends (rear deck, glacis) keep their shape and nothing is stretched.
static func widened(img: Image, width: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var extra := width - w
	if extra <= 0:
		return img
	var mid := w / 2
	var band := clampi(mini(extra, mid), 1, maxi(mid, 1))
	var out := Image.create(width, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, mid, h), Vector2i.ZERO)
	var x := mid
	var left := extra
	while left > 0:
		var n := mini(band, left)
		out.blit_rect(img, Rect2i(mid - band, 0, n, h), Vector2i(x, 0))
		x += n
		left -= n
	out.blit_rect(img, Rect2i(mid, 0, w - mid, h), Vector2i(x, 0))
	return out


## True for the generated sprites whose steel is regraded at load (graded_steel): hulls, turrets,
## enemies, the Behemoth, rooms, props and the machinery bodies. Backdrops, flames, sparks, puffs
## and explosions keep their colours.
static func is_steel(id: String) -> bool:
	for prefix: String in ["hull_", "turret_", "enemy_", "boss_", "room_", "prop_"]:
		if id.begins_with(prefix):
			return true
	return (
		id
		in [
			"diesel_block",
			"gearbox",
			"dynamo_housing",
			"boiler",
			"firebox",
			"flywheel_large",
			"flywheel_small",
			"gear_large",
			"gear_medium",
			"road_wheel",
			"drive_sprocket",
			"idler_wheel",
			"shell_rack",
			"depot_gate",
		]
	)


## The art direction in the pipeline, not only in the prompts (brief 3: steel grey-black, lights
## the only near-saturated pixels): every opaque pixel of a steel sprite loses its saturation
## (HSV s <= 0.15 above value 0.25, so dark rust and mud survive as accents) and may not use a
## light colour (fire, lamp or arc); it snaps to the nearest remaining palette colour. Then one
## pass flattens low-contrast mottling: a pixel within one ramp step of its 3 x 3 median takes the
## median's colour, while rivets, seams and edges (higher contrast) stay.
static func graded_steel(src: Image) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var lights := light_colours()
	var keep: Array[Color] = []
	for p in palette():
		if not lights.has(p.to_rgba32()):
			keep.append(p)
	var remap := {}
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var key := c.to_rgba32()
			if not remap.has(key):
				remap[key] = _steel_colour(c, lights.has(key), keep)
			img.set_pixel(x, y, remap[key])
	return _flatten_mottling(img)


## The seven light colours of the palette (warm fire and lamp, cold arc) as RGBA32 keys.
static func light_colours() -> Dictionary:
	var out := {}
	for c: Color in [F0, F1, F2, F3, C1, C2, C3]:
		out[c.to_rgba32()] = true
	return out


static func _steel_colour(c: Color, is_light: bool, keep: Array[Color]) -> Color:
	var v := minf(c.v, 0.55) if is_light else c.v
	var s := c.s
	if v > 0.25 or is_light:
		s = minf(s, 0.15)
	var g := Color.from_hsv(c.h, s, v)
	return _nearest(g, keep)


static func _flatten_mottling(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := src.duplicate() as Image
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var lums: Array[float] = []
			var cols: Array[Color] = []
			var full := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n := src.get_pixel(x + dx, y + dy)
					if n.a < 0.5:
						full = false
						break
					lums.append(n.get_luminance())
					cols.append(n)
				if not full:
					break
			if not full:
				continue
			var sorted := lums.duplicate()
			sorted.sort()
			var med := lums.find(sorted[4])
			if absf(c.get_luminance() - lums[med]) < 0.055:
				out.set_pixel(x, y, cols[med])
	return out


static func _nearest(c: Color, pal: Array[Color]) -> Color:
	var best := pal[0]
	var best_d := INF
	for p in pal:
		var d := (
			(p.r - c.r) * (p.r - c.r) * 0.3
			+ (p.g - c.g) * (p.g - c.g) * 0.59
			+ (p.b - c.b) * (p.b - c.b) * 0.11
		)
		if d < best_d:
			best_d = d
			best = p
	return best


## The sprite's size in art px from art.json (16 x 16 for an unknown id).
static func size_of(id: String) -> Vector2i:
	var s: Dictionary = sprite_def(id)
	var size: Array = s.get("size", [16, 16])
	return Vector2i(int(size[0]), int(size[1]))


## The art.json entry of `id` ({} when unknown).
static func sprite_def(id: String) -> Dictionary:
	for s: Variant in _art_json().get("sprites", []):
		if s is Dictionary and str(s.get("id", "")) == id:
			return s
	return {}


## Every sprite id of art.json, in file order.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for s: Variant in _art_json().get("sprites", []):
		if s is Dictionary:
			out.append(str(s.get("id", "")))
	return out


## The palette of art.json as Colors.
static func palette() -> Array[Color]:
	var out: Array[Color] = []
	for c: Variant in _art_json().get("palette", []):
		out.append(Color(str(c)))
	return out


## True when art.json lists `id` as an opaque sprite (background "opaque": rooms, sky, ground,
## the picker card). Every other sprite is transparent around its subject.
static func is_opaque(id: String) -> bool:
	return str(sprite_def(id).get("background", "transparent")) == "opaque"


## True when the sprite is a tile strip (tile: true in art.json).
static func is_strip(id: String) -> bool:
	return bool(sprite_def(id).get("tile", false))


## A drawn placeholder at the sprite's size: the subject in palette colours, transparent around it
## unless art.json says opaque. An id art.json does not list gets a flat block with a frame.
static func placeholder_image(id: String) -> Image:
	var size := size_of(id)
	var c := Canvas.new(size.x, size.y)
	c.seed_value = absi(id.hash()) % 9973
	if not _draw(c, id):
		_block(c, id)
	return c.img


static func _art_json() -> Dictionary:
	if _art.is_empty() and FileAccess.file_exists(ART_JSON):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_JSON))
		_art = d if d is Dictionary else {}
	return _art


## Draws the sprite; false for an id the dispatcher does not know.
static func _draw(c: Canvas, id: String) -> bool:
	match id:
		"hull_bulwark", "hull_rampart", "hull_citadel":
			_hull(c, id == "hull_citadel")
		"turret_bulwark", "turret_rampart", "turret_citadel":
			_turret(c)
		"turret_secondary":
			_turret_secondary(c)
		"room_bulwark":
			_room(c, "bulwark")
		"room_diesel":
			_room(c, "diesel")
		"room_dynamo":
			_room(c, "dynamo")
		"room_steam":
			_room(c, "steam")
		"diesel_block":
			_diesel_block(c)
		"flywheel_large":
			_flywheel(c, 6)
		"flywheel_small":
			_flywheel(c, 5)
		"gear_large":
			_gear(c, 12, 4)
		"gear_medium":
			_gear(c, 8, 3)
		"gearbox":
			_gearbox(c)
		"dynamo_housing":
			_dynamo_housing(c)
		"dynamo_armature":
			_dynamo_armature(c)
		"spark":
			_spark(c)
		"boiler":
			_boiler(c)
		"firebox":
			_firebox(c)
		"firebox_flame", "fire_small":
			_flame(c)
		"flyball":
			_flyball(c)
		"steam_puff":
			_puff(c, G11, G10, G9, 3)
		"shell_rack":
			_shell_rack(c)
		"road_wheel":
			_road_wheel(c)
		"drive_sprocket":
			_sprocket(c)
		"idler_wheel":
			_idler(c)
		"enemy_light":
			_enemy_light(c)
		"enemy_medium":
			_enemy_medium(c)
		"enemy_heavy":
			_enemy_heavy(c)
		"enemy_destroyer":
			_enemy_destroyer(c)
		"enemy_dugin":
			_enemy_dugin(c)
		"boss_hull":
			_boss_hull(c)
		"boss_turret":
			_boss_turret(c, false)
		"boss_turret_broken":
			_boss_turret(c, true)
		"boss_bogie":
			_boss_bogie(c, false)
		"boss_bogie_broken":
			_boss_bogie(c, true)
		"prop_tank_traps":
			_tank_traps(c)
		"prop_wire":
			_wire(c)
		"prop_wreck_barricade":
			_wreck(c)
		"prop_crater":
			_crater(c)
		"prop_rubble":
			_rubble(c)
		"depot_gate":
			_depot_gate(c)
		"bg_sky":
			_sky(c)
		"bg_hills_far":
			_hills_far(c)
		"bg_fields_near":
			_fields(c)
		"bg_village_near":
			_village(c)
		"bg_quarry_near":
			_quarry(c)
		"bg_town_near":
			_town(c)
		"bg_depot_near":
			_depot_backdrop(c)
		"bg_ground":
			_ground(c)
		"fg_debris":
			_debris(c)
		"picker_card":
			_picker(c)
		"muzzle_flash":
			_muzzle_flash(c)
		"explosion_large":
			_explosion(c, 30.0)
		"explosion_small":
			_explosion(c, 14.0)
		"smoke_puff":
			_puff(c, G6, G5, G4, 2)
		"dirt_spray":
			_dirt_spray(c)
		_:
			return false
	if not is_opaque(id) and not is_strip(id):
		if id == "firebox" or id == "shell_rack":
			c.round_corners()
	if is_slab(id):
		_slab_grade(c)
	return true


## True for the steel and concrete sprites that get the soft top-lit slab shading (_slab_grade).
static func is_slab(id: String) -> bool:
	for prefix: String in ["hull_", "turret_", "enemy_", "boss_"]:
		if id.begins_with(prefix):
			return true
	return (
		id
		in [
			"prop_tank_traps",
			"prop_wreck_barricade",
			"prop_rubble",
			"depot_gate",
			"diesel_block",
			"gearbox",
			"dynamo_housing",
			"shell_rack",
		]
	)


## Soft top-lit shading without noise or outlines: every grey-ramp pixel steps along the ramp by its
## height in the sprite (top quarter one step lighter, then one, two and three steps darker), so
## plates read as a 4-step gradient from a lit top edge to a near-black bottom while seams and
## rivets keep their contrast. Black, the two brightest greys and every non-grey colour stay.
static func _slab_grade(c: Canvas) -> void:
	var ramp: Array[Color] = [G0, G1, G2, G3, G4, G5, G6, G7, G8, G9, G10, G11]
	var index := {}
	for i in ramp.size():
		index[ramp[i].to_rgba32()] = i
	var shifts: Array[int] = [1, -1, -2, -3]
	for y in c.h:
		var shift: int = shifts[clampi(4 * y / maxi(c.h, 1), 0, 3)]
		for x in c.w:
			var col := c.img.get_pixel(x, y)
			if col.a < 0.5:
				continue
			var k: int = index.get(col.to_rgba32(), -1)
			if k < 1 or k > 9:
				continue
			c.img.set_pixel(x, y, ramp[clampi(k + shift, 1, 9)])


## An id art.json does not list: a flat block with a frame (an unknown id never crashes).
static func _block(c: Canvas, id: String) -> void:
	var pal := palette()
	var fill := G6
	if pal.size() >= 8:
		fill = pal[(absi(id.hash()) % 6) + 4]
	c.fill(fill)
	c.frame(0, 0, c.w, c.h, G1)


# --- Shared pieces -------------------------------------------------------------------------------


## Rivet dots along a horizontal line: a light pixel with a dark one under it.
static func _rivets(
	c: Canvas, x0: int, x1: int, y: int, step: int, lit: Color, shade: Color
) -> void:
	var x := x0
	while x <= x1:
		c.px(x, y, lit)
		c.px(x, y + 1, shade)
		x += maxi(step, 1)


## Vertical plate seams every `step` px: a dark line with a light one beside it.
static func _seams(
	c: Canvas, x0: int, x1: int, y0: int, y1: int, step: int, dark: Color, lit: Color
) -> void:
	var x := x0
	while x <= x1:
		c.rect(x, y0, 1, y1 - y0, dark)
		c.rect(x + 1, y0, 1, y1 - y0, lit)
		x += maxi(step, 1)


## Rust streaks hanging from a row of rivets, deterministic.
static func _streaks(c: Canvas, x0: int, x1: int, y: int, max_len: int, col: Color) -> void:
	var x := x0
	while x <= x1:
		var n := c.noise(x, y, 5)
		if n < 0.45:
			var len_px := 2 + int(n * 2.0 * max_len)
			for k in len_px:
				if c.solid(x, y + k):
					c.px(x, y + k, col)
		x += 3


## A wheel face (rim, spokes, hub) shared by the flywheels.
static func _wheel(
	c: Canvas, r_out: float, r_in: float, spokes: int, rim: Color, spoke: Color
) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	c.disc(cx, cy, r_out, rim)
	c.disc(cx, cy, r_in, G2)
	for i in spokes:
		var a := TAU * i / spokes + 0.3
		c.thick_line(cx, cy, cx + cos(a) * (r_in + 1.0), cy + sin(a) * (r_in + 1.0), 1.6, spoke)
	c.disc(cx, cy, maxf(r_out * 0.22, 2.0), G8)
	c.disc(cx, cy, maxf(r_out * 0.1, 1.0), G2)


# --- Hulls and turrets -----------------------------------------------------------------------------


## A slab-sided riveted hull facing right: roof band, dark x-ray cutaway band where the rooms sit
## (y top .. top + 48), a flat skirt at the bottom (no wheels, tracks or turret), glacis at the front.
static func _hull(c: Canvas, mounts: bool) -> void:
	var w := c.w
	var h := c.h
	var top := 14 + (h - 72) / 2
	var bot := top + 48
	var outline_pts: Array[int] = [0, 14, 12, 0, w - 18, 0, w, 22, w, h, 0, h]
	c.poly(outline_pts, G5)
	# Roof plates with seams, riveted along the band's lower edge.
	c.rect(0, 0, w, top, G6)
	_seams(c, 22, w - 30, 1, top, 30, G4, G7)
	c.line(12, 0, w - 19, 0, G9)
	c.line(12, 1, w - 19, 1, G8)
	# The glacis: a lit slope and a dark seam behind it.
	c.line(w - 18, 0, w - 1, 22, G8)
	c.line(w - 19, 3, w - 5, 22, G4)
	c.line(0, 14, 12, 0, G7)
	# Skirts: flat bottom, plates every 24 px, a ledge above them.
	c.rect(0, bot, w, h - bot, G4)
	_seams(c, 10, w - 14, bot + 1, h, 24, G2, G6)
	c.rect(0, bot, w, 1, G8)
	c.rect(0, bot + 1, w, 1, G2)
	c.rect(0, h - 1, w, 1, G2)
	# The cutaway band: dark, framed, with the end walls.
	c.rect(6, top, w - 6 - 10, 48, G1)
	c.frame(6, top, w - 6 - 10, 48, G3)
	c.rect(6, top, 3, 48, G4)
	c.rect(w - 13, top, 3, 48, G4)
	c.rect(7, top + 1, w - 6 - 12, 2, G2)
	# Rivets above and below the band.
	_rivets(c, 14, w - 24, top - 5, 7, G9, G3)
	_rivets(c, 8, w - 10, bot + 5, 8, G8, G2)
	_streaks(c, 14, w - 24, top - 3, 5, R0)
	_streaks(c, 8, w - 10, bot + 7, 4, R0)
	# Soot on the roof, rust low down.
	c.speckle(0, 0, w, top, G3, 0.06, 1, true)
	c.speckle(0, bot, w, h - bot, R1, 0.08, 2, true)
	c.speckle(0, bot, w, h - bot, R0, 0.08, 3, true)
	# Rear: tow lugs and an exhaust grille on the roof.
	c.rect(1, 18, 4, 6, G4)
	c.rect(3, 19, 2, 4, G2)
	c.rect(30, 2, 14, 3, G2)
	for i in 4:
		c.rect(31 + i * 3, 2, 1, 3, G6)
	if mounts:
		_mount(c, 70)
		_mount(c, w - 56)
	var mask := Canvas.new(w, h)
	mask.poly(outline_pts, G5)
	c.clip_to(mask.img)


static func _mount(c: Canvas, x: int) -> void:
	c.rect(x, 0, 26, 6, G7)
	c.rect(x + 2, 1, 22, 3, G3)
	c.rect(x + 4, 1, 18, 1, G1)
	c.frame(x, 0, 26, 6, G5)
	c.line(x + 1, 0, x + 24, 0, G9)


## A boxy turret without its barrel, facing right: the mantlet sits at the right edge, 22 px above
## the bottom (the trunnion), the lowest 5 px are the ring skirt.
static func _turret(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	var bottom := h - 5
	# Ring skirt.
	c.rect(8, bottom, w - 20, 5, G4)
	c.rect(8, bottom, w - 20, 1, G8)
	# The body: a rear bustle, a flat roof, a stepped front.
	c.poly([3, bottom, 3, 12, 11, 2, w - 24, 2, w - 8, 10, w - 8, bottom], G6)
	c.rect(3, 8, 9, bottom - 8, G5)
	c.line(11, 2, w - 25, 2, G10)
	c.line(11, 3, w - 25, 3, G8)
	c.line(w - 24, 2, w - 9, 10, G9)
	c.line(3, 12, 11, 2, G8)
	# Side plates: seams and rivets.
	_seams(c, 16, w - 24, 8, bottom, 20, G3, G7)
	_rivets(c, 8, w - 12, 8, 6, G9, G3)
	_rivets(c, 8, w - 12, bottom - 4, 6, G8, G3)
	c.rect(3, bottom - 1, w - 11, 1, G3)
	# A hatch and a periscope box on the roof.
	var mid := w >> 1
	c.rect(mid - 14, 0, 12, 3, G7)
	c.rect(mid - 12, 0, 8, 1, G9)
	c.rect(mid + 6, 0, 8, 3, G5)
	c.rect(mid + 8, 1, 4, 1, G1)
	# Mantlet and bore at the right edge.
	var my := h - 22
	c.rect(w - 11, my - 8, 11, 16, G7)
	c.rect(w - 10, my - 7, 9, 14, G5)
	c.rect(w - 4, my - 3, 4, 6, G2)
	c.frame(w - 11, my - 8, 11, 16, G4)
	c.line(w - 11, my - 8, w - 2, my - 8, G9)
	c.speckle(0, 0, w, h, G3, 0.1, 1, true)
	c.speckle(0, 4, w, h - 8, R1, 0.05, 2, true)
	_streaks(c, 10, w - 14, 9, 4, R0)


static func _turret_secondary(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.poly([2, h - 2, 2, 7, 7, 1, w - 14, 1, w - 6, 6, w - 6, h - 2], G6)
	c.rect(2, h - 4, w - 8, 4, G4)
	c.line(7, 1, w - 14, 1, G10)
	c.line(w - 14, 1, w - 7, 6, G9)
	_rivets(c, 6, w - 10, 6, 5, G9, G3)
	var my := 8
	c.rect(w - 9, my - 5, 9, 10, G7)
	c.rect(w - 4, my - 2, 4, 4, G2)
	c.frame(w - 9, my - 5, 9, 10, G4)
	c.rect((w >> 1) - 5, 0, 8, 2, G8)
	c.speckle(0, 0, w, h, G3, 0.12, 1, true)


# --- Rooms (opaque back walls with an empty middle) -----------------------------------------------


static func _room(c: Canvas, kind: String) -> void:
	var w := c.w
	var h := c.h
	c.fill(G2)
	# Wall panels: a seam every 16 px, a darker middle band for the machinery.
	_seams(c, 7, w - 8, 6, h - 8, 16, G1, G3)
	c.rect(4, 12, w - 8, h - 24, G1 if kind != "steam" else B0)
	c.speckle(0, 0, w, h, G3, 0.06, 4, false)
	# Floor plate with a grating pattern, ceiling girder with a pipe.
	c.rect(0, h - 8, w, 8, G4)
	c.rect(0, h - 8, w, 1, G8)
	c.rect(0, h - 7, w, 1, G2)
	var x := 2
	while x < w - 2:
		c.rect(x, h - 5, 2, 3, G2)
		x += 5
	c.rect(0, 0, w, 6, G3)
	c.rect(0, 5, w, 1, G1)
	c.rect(2, 1, w - 4, 3, G6)
	c.rect(2, 1, w - 4, 1, G9)
	for i in range(8, w - 6, 18):
		c.rect(i, 0, 2, 6, G4)
	# Kind marks (each engine's own look at the edges, the middle stays empty).
	match kind:
		"diesel":
			c.rect(w - 9, 8, 5, h - 18, B2)
			c.rect(w - 9, 8, 1, h - 18, B4)
			c.speckle(4, 14, 20, 24, B1, 0.18, 6, false)
			c.speckle(4, h - 14, w - 8, 6, B2, 0.2, 7, false)
			c.rect(3, 9, 2, h - 20, R1)
		"dynamo":
			c.rect(w - 8, 8, 3, h - 18, C0)
			c.rect(w - 8, 8, 1, h - 18, C1)
			for i in 3:
				c.rect(w - 11, 10 + i * 3, 9, 1, C1)
			c.rect(4, 8, 3, h - 18, C0)
			c.rect(4, 8, 1, h - 18, C1)
			c.speckle(8, 10, w - 20, 10, G4, 0.1, 8, false)
		"steam":
			c.rect(w - 10, 8, 6, h - 18, R1)
			c.rect(w - 10, 8, 2, h - 18, R2)
			c.rect(5, 7, w - 20, 2, R0)
			c.disc(w - 7, 14, 3.0, R2)
			c.disc(w - 7, 14, 1.5, R0)
			c.speckle(0, 6, w, h - 12, R0, 0.12, 9, false)
		_:
			c.rect(w - 10, 8, 6, h - 18, B2)
			c.rect(w - 10, 8, 1, h - 18, B4)
			c.rect(4, 8, 6, h - 18, G4)
			c.rect(4, 8, 1, h - 18, G7)
			c.speckle(10, 12, w - 22, h - 24, B1, 0.12, 10, false)
	c.frame(0, 0, w, h, G1)
	c.frame(1, 1, w - 2, h - 2, G3)


# --- Machinery ----------------------------------------------------------------------------------------


## The diesel block: head cover, four empty cylinder windows ([6,6,8,10] ...), crankcase and sump.
static func _diesel_block(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(1, 1, w - 2, h - 2, G6)
	c.rect(1, 1, w - 2, 3, G8)
	c.rect(1, 1, w - 2, 1, G10)
	c.rect(0, h - 7, w, 7, G5)
	c.rect(4, h - 3, w - 8, 3, G3)
	c.rect(0, h - 7, w, 1, G8)
	for i in 4:
		var x := 6 + i * 12
		c.rect(x - 1, 5, 10, 12, G3)
		c.rect(x, 6, 8, 10, G0)
		c.rect(x, 6, 8, 1, G2)
		c.rect(x + 1, 15, 6, 1, G4)
		c.px(x - 2, 6, G9)
		c.px(x + 9, 6, G9)
		c.px(x - 2, 15, G9)
		c.px(x + 9, 15, G9)
	c.rect(2, 17, w - 4, 1, G3)
	c.rect(2, 18, w - 4, 1, G7)
	_rivets(c, 4, w - 6, 21, 6, G9, G3)
	c.rect(w - 6, 8, 4, 12, G4)
	c.rect(0, 9, 3, 10, G5)
	c.speckle(0, 0, w, h, G3, 0.12, 1, true)
	c.speckle(0, 0, w, h, B2, 0.07, 2, true)


static func _flywheel(c: Canvas, spokes: int) -> void:
	_wheel(c, c.w * 0.5 - 0.5, c.w * 0.5 - 4.0, spokes, G7, G9)
	var cx := c.w * 0.5
	c.disc(cx + c.w * 0.27, c.h * 0.5 - 1.0, 1.4, G2)
	c.ring(cx, c.h * 0.5, c.w * 0.5 - 0.5, c.w * 0.5 - 1.8, G9)


static func _gear(c: Canvas, teeth: int, tooth: int) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	var r := c.w * 0.5 - float(tooth) * 0.5
	c.disc(cx, cy, r, G7)
	for i in teeth:
		var a := TAU * i / teeth
		var tx := cx + cos(a) * (r + float(tooth) * 0.25)
		var ty := cy + sin(a) * (r + float(tooth) * 0.25)
		c.disc(tx, ty, float(tooth) * 0.5, G8)
	c.disc(cx, cy, r - 2.0, G6)
	c.ring(cx, cy, r - 2.0, r - 3.0, G9)
	c.disc(cx, cy, maxf(r * 0.3, 1.5), G2)
	c.px(int(cx - 1.0), int(cy - r * 0.55), G10)


## The Bulwark's three-way gearbox: a case with a lever window and three output stubs at
## [4,24], [16,2] and [30,14] (drive, turret, hoist).
static func _gearbox(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(3, 4, w - 8, h - 6, G6)
	c.rect(3, 4, w - 8, 2, G8)
	c.rect(3, 4, w - 8, 1, G10)
	c.rect(5, 9, w - 12, 9, G1)
	c.frame(5, 9, w - 12, 9, G4)
	c.rect(8, 12, w - 18, 2, G3)
	_rivets(c, 6, w - 8, h - 6, 6, G9, G3)
	c.rect(0, 22, 5, 5, G8)
	c.rect(0, 23, 5, 2, G10)
	c.rect(13, 0, 6, 5, G8)
	c.rect(14, 0, 4, 2, G10)
	c.rect(w - 5, 11, 5, 6, G8)
	c.rect(w - 5, 12, 5, 2, G10)
	c.speckle(0, 0, w, h, G3, 0.12, 2, true)


## The dynamo's casing: a barrel with cooling fins, end caps, a terminal box, and a round window
## (centre [20,14], radius 9) for the armature to show through.
static func _dynamo_housing(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(2, 3, w - 4, h - 5, G6)
	c.rect(2, 3, w - 4, 2, G8)
	c.rect(2, 3, w - 4, 1, G10)
	c.rect(0, 6, 4, h - 10, G7)
	c.rect(w - 4, 6, 4, h - 10, G7)
	for i in 6:
		c.rect(7 + i * 5, 4, 2, 3, G4)
		c.rect(7 + i * 5, h - 5, 2, 3, G4)
	c.rect(w - 14, 0, 9, 4, G5)
	c.rect(w - 13, 0, 7, 1, C2)
	c.disc(20.0, 14.0, 11.0, G3)
	c.disc(20.0, 14.0, 9.0, G0)
	c.ring(20.0, 14.0, 11.0, 9.5, C1)
	c.rect(4, 22, 6, 3, C0)
	c.rect(4, 22, 6, 1, C1)
	c.speckle(0, 0, w, h, G3, 0.12, 1, true)


## The rotor face-on: a disc with eight coil slots and a hub; the slots differ so it reads spinning.
static func _dynamo_armature(c: Canvas) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	c.disc(cx, cy, 9.5, G7)
	c.ring(cx, cy, 9.5, 8.5, G9)
	for i in 8:
		var a := TAU * i / 8.0
		var col := R2 if i % 2 == 0 else R1
		c.thick_line(
			cx + cos(a) * 3.0, cy + sin(a) * 3.0, cx + cos(a) * 7.5, cy + sin(a) * 7.5, 2.2, col
		)
	c.disc(cx, cy, 3.0, G9)
	c.disc(cx, cy, 1.4, G2)
	c.px(int(cx) + 4, int(cy) - 6, C2)


## A burst of cold arc light: a bright core, jagged arms.
static func _spark(c: Canvas) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	var arms: Array[float] = [0.2, 1.3, 2.4, 3.3, 4.4, 5.5]
	for i in arms.size():
		var a := arms[i]
		var len_px := 7.0 if i % 2 == 0 else 5.0
		var mx := cx + cos(a) * len_px * 0.5 + sin(a) * 1.4
		var my := cy + sin(a) * len_px * 0.5 - cos(a) * 1.4
		c.thick_line(cx, cy, mx, my, 1.0, C2)
		c.thick_line(mx, my, cx + cos(a) * len_px, cy + sin(a) * len_px, 1.0, C1)
	c.disc(cx, cy, 2.8, C0)
	c.disc(cx, cy, 2.4, C2)
	c.disc(cx, cy, 1.4, C3)


## The boiler: a riveted horizontal drum with straps, a steam dome, a gauge boss and a chimney
## stub ([30,0]); gauge centre [20,10] r 5.
static func _boiler(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	# Desaturated lagging (brief 3: the only orange in the room is the flame).
	c.rect(2, 6, w - 4, h - 8, B3)
	c.rect(0, 9, w, h - 14, B3)
	c.rect(2, 6, w - 4, 3, B4)
	c.rect(2, 6, w - 4, 1, G8)
	c.rect(2, h - 4, w - 4, 3, B2)
	for x: int in [8, 18, 28, 36]:
		c.rect(x, 6, 2, h - 8, G4)
		c.rect(x + 2, 6, 1, h - 8, G8)
	_rivets(c, 4, w - 4, 13, 5, G8, B2)
	c.rect(28, 0, 5, 7, G5)
	c.rect(28, 0, 5, 1, G9)
	c.rect(8, 2, 9, 5, B4)
	c.rect(8, 2, 9, 1, G9)
	c.disc(20.0, 11.0, 6.0, G4)
	c.disc(20.0, 11.0, 5.0, G11)
	c.disc(20.0, 11.0, 3.4, G2)
	c.px(20, 8, G10)
	c.px(21, 10, F0)
	c.speckle(0, 0, w, h, B2, 0.12, 3, true)


## The firebox door: an iron box with an open hatch; the flame sprite sits in the opening.
static func _firebox(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(0, 0, w, h, G5)
	c.rect(0, 0, w, 2, G8)
	c.rect(3, 4, w - 6, h - 7, G0)
	c.frame(3, 4, w - 6, h - 7, G7)
	c.rect(4, h - 5, w - 8, 2, R1)
	c.px(6, h - 4, F0)
	c.px(w - 8, h - 4, F0)
	c.px(9, h - 5, F1)
	c.rect(0, h - 3, w, 3, G3)
	_rivets(c, 2, w - 3, 2, 5, G9, G3)
	c.speckle(0, 0, w, h, R1, 0.1, 2, true)


## A flame: teardrop layers from orange to a white-hot core, standing on the sprite's bottom.
static func _flame(c: Canvas) -> void:
	var cx := c.w * 0.5
	var base := c.h - 1.0
	_flame_layer(c, cx, base, c.w * 0.36, c.h - 1.0, F0, 1.0)
	_flame_layer(c, cx, base, c.w * 0.27, c.h * 0.78, F1, 0.5)
	_flame_layer(c, cx, base, c.w * 0.17, c.h * 0.5, F2, 0.0)
	_flame_layer(c, cx, base, c.w * 0.09, c.h * 0.28, F3, 0.0)


static func _flame_layer(
	c: Canvas, cx: float, base: float, r: float, ht: float, col: Color, sway: float
) -> void:
	c.disc(cx, base - r + 1.0, r, col)
	c.poly([cx - r, base - r + 1.0, cx + sway, base + 1.0 - ht, cx + r, base - r + 1.0], col)


## A flyball governor: spindle, collar, two arms and balls, a base.
static func _flyball(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(7, 2, 2, h - 5, G8)
	c.rect(7, 2, 1, h - 5, G10)
	c.disc(8.0, 3.0, 2.0, G6)
	c.thick_line(8.0, 4.0, 3.0, 10.0, 1.0, G9)
	c.thick_line(8.0, 4.0, 13.0, 10.0, 1.0, G9)
	c.disc(3.0, 11.0, 2.6, G10)
	c.disc(13.0, 11.0, 2.6, G10)
	c.px(2, 10, G11)
	c.px(12, 10, G11)
	c.rect(6, 12, 4, 3, G5)
	c.rect(2, h - 4, w - 4, 4, G6)
	c.rect(2, h - 4, w - 4, 1, G9)


## A round, lumpy cloud of three shades (smoke or steam).
static func _puff(c: Canvas, light: Color, mid: Color, dark: Color, lumps: int) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	var r := c.w * 0.22
	for i in lumps + 2:
		var a := TAU * i / (lumps + 2) + 0.4
		c.disc(cx + cos(a) * r * 0.9, cy + sin(a) * r * 0.9, r, dark)
	c.disc(cx, cy, r * 1.1, dark)
	for i in lumps + 2:
		var a := TAU * i / (lumps + 2) + 0.4
		c.disc(cx + cos(a) * r * 0.6 - 0.5, cy + sin(a) * r * 0.6 - 0.5, r * 0.75, mid)
	c.disc(cx - 1.0, cy - 1.0, r * 0.8, light)


## The steam engine's shell rack: a frame with three upright shells (brass band, grey ogive).
static func _shell_rack(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(0, 0, w, h, G4)
	c.rect(1, 1, w - 2, h - 2, G2)
	c.frame(0, 0, w, h, G6)
	c.rect(0, h - 5, w, 5, G5)
	c.rect(0, h - 5, w, 1, G8)
	c.rect(0, 3, w, 2, G6)
	for i in 3:
		var x := 4 + i * 9
		c.rect(x, 12, 7, 24, B4)
		c.poly([x, 12, x + 1, 7, x + 3, 5, x + 4, 5, x + 6, 7, x + 7, 12], G9)
		c.rect(x + 1, 12, 1, 24, B5)
		c.rect(x, 17, 7, 2, R2)
		c.rect(x, 30, 7, 2, G7)
		c.px(x + 2, 8, G11)
	c.rect(0, 8, 2, h - 14, G7)
	c.rect(w - 2, 8, 2, h - 14, G7)
	_rivets(c, 3, w - 4, 1, 6, G9, G3)


# --- Running gear (face-on) -----------------------------------------------------------------------


static func _road_wheel(c: Canvas) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	c.disc(cx, cy, 8.8, G2)
	c.disc(cx, cy, 7.0, G6)
	c.ring(cx, cy, 7.0, 6.0, G8)
	for i in 6:
		var a := TAU * i / 6.0 + 0.2
		c.disc(cx + cos(a) * 4.4, cy + sin(a) * 4.4, 1.2, G2)
	c.disc(cx, cy, 2.4, G9)
	c.disc(cx, cy, 1.0, G2)
	c.px(int(cx) + 5, int(cy) - 5, G11)


static func _sprocket(c: Canvas) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	for i in 10:
		var a := TAU * i / 10.0
		c.disc(cx + cos(a) * 9.6, cy + sin(a) * 9.6, 1.9, G7)
	c.disc(cx, cy, 9.0, G6)
	c.ring(cx, cy, 9.0, 8.0, G8)
	for i in 5:
		var a := TAU * (i + 0.5) / 5.0
		c.disc(cx + cos(a) * 5.4, cy + sin(a) * 5.4, 1.9, G2)
	c.disc(cx, cy, 3.0, G9)
	c.disc(cx, cy, 1.3, G2)
	c.px(int(cx) + 6, int(cy) - 4, G10)


static func _idler(c: Canvas) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	c.disc(cx, cy, 9.6, G3)
	c.disc(cx, cy, 8.0, G6)
	c.ring(cx, cy, 8.0, 7.0, G9)
	for i in 4:
		var a := TAU * i / 4.0 + 0.5
		c.thick_line(cx, cy, cx + cos(a) * 6.5, cy + sin(a) * 6.5, 1.8, G4)
	c.disc(cx, cy, 3.4, G8)
	c.disc(cx, cy, 1.4, G2)
	c.px(int(cx) - 4, int(cy) - 5, G11)


# --- Enemies (facing left, the gun at the left edge) -----------------------------------------------


## A track unit: a belt outline with a row of small wheels, from x0 to x1 and y0 to y1.
static func _tracks(c: Canvas, x0: int, x1: int, y0: int, y1: int) -> void:
	var hgt := float(y1 - y0)
	c.rect(x0 + 2, y0, x1 - x0 - 3, y1 - y0, G2)
	c.disc(x0 + hgt * 0.5, y0 + hgt * 0.5, hgt * 0.5, G2)
	c.disc(x1 - hgt * 0.5, y0 + hgt * 0.5, hgt * 0.5, G2)
	c.rect(x0 + 3, y0, x1 - x0 - 5, 1, G4)
	var x := x0 + 5
	while x < x1 - 4:
		c.disc(x + 0.5, y0 + hgt * 0.5, maxf(hgt * 0.32, 1.5), G6)
		c.px(x, y0 + int(hgt * 0.5), G9)
		x += maxi(int(hgt), 5)
	c.rect(x0 + 3, y1 - 1, x1 - x0 - 5, 1, G0)


## A low wedge light tank: sloped front, a small turret, a thin long barrel at y 10.
static func _enemy_light(c: Canvas) -> void:
	_tracks(c, 6, 76, 33, 40)
	c.poly([4, 33, 14, 21, 70, 21, 76, 33], G5)
	c.line(14, 21, 70, 21, G9)
	c.line(4, 33, 14, 21, G7)
	c.rect(8, 28, 62, 3, G3)
	_rivets(c, 18, 66, 25, 7, G8, G3)
	# Turret and barrel.
	c.poly([32, 21, 36, 8, 56, 8, 62, 21], G6)
	c.line(36, 8, 56, 8, G10)
	c.rect(35, 11, 22, 6, G5)
	c.rect(2, 9, 34, 3, G4)
	c.rect(2, 9, 34, 1, G8)
	c.rect(0, 8, 4, 5, G3)
	c.rect(46, 4, 6, 4, G7)
	c.speckle(0, 0, 80, 40, R1, 0.1, 1, true)
	c.speckle(0, 0, 80, 40, G3, 0.08, 2, true)


## A tall slab medium: a boxy high turret over a squared hull, a skirt along the tracks.
static func _enemy_medium(c: Canvas) -> void:
	_tracks(c, 6, 100, 45, 52)
	c.poly([4, 45, 8, 28, 98, 28, 102, 45], G5)
	c.line(8, 28, 98, 28, G9)
	c.line(4, 45, 8, 28, G7)
	c.rect(8, 40, 90, 4, G3)
	_seams(c, 20, 90, 30, 40, 18, G3, G6)
	_rivets(c, 12, 94, 33, 7, G9, G3)
	# The tall slab turret.
	c.poly([38, 28, 40, 6, 86, 6, 88, 28], G6)
	c.rect(40, 6, 46, 3, G7)
	c.line(40, 6, 86, 6, G10)
	c.rect(42, 12, 42, 14, G5)
	_seams(c, 54, 80, 9, 27, 14, G3, G7)
	c.rect(60, 2, 12, 4, G7)
	c.rect(63, 3, 6, 1, G2)
	# The gun: a thick barrel and a mantlet, muzzle at (2, 14).
	c.rect(2, 12, 40, 4, G4)
	c.rect(2, 12, 40, 1, G8)
	c.rect(0, 11, 5, 6, G3)
	c.rect(34, 9, 8, 10, G7)
	c.speckle(0, 0, 104, 52, R1, 0.1, 1, true)
	c.speckle(0, 0, 104, 52, G3, 0.08, 2, true)


## A long twin-bogie heavy: two track units with a gap, a long slab hull, a broad turret.
static func _enemy_heavy(c: Canvas) -> void:
	_tracks(c, 6, 64, 53, 60)
	_tracks(c, 72, 130, 53, 60)
	c.poly([4, 52, 10, 34, 126, 34, 132, 52], G5)
	c.rect(60, 46, 16, 8, G2)
	c.line(10, 34, 126, 34, G9)
	c.line(4, 52, 10, 34, G7)
	c.rect(8, 46, 120, 3, G3)
	_seams(c, 22, 118, 36, 46, 22, G3, G6)
	_rivets(c, 14, 122, 40, 7, G9, G3)
	# A wide turret with a heavy mantlet and a long barrel to (0, 16).
	c.poly([40, 34, 46, 12, 98, 12, 106, 34], G6)
	c.line(46, 12, 98, 12, G10)
	c.rect(48, 17, 52, 15, G5)
	_seams(c, 60, 92, 14, 33, 16, G3, G7)
	c.rect(70, 8, 14, 4, G7)
	c.rect(72, 9, 10, 1, G2)
	c.rect(0, 14, 50, 5, G4)
	c.rect(0, 14, 50, 1, G8)
	c.rect(0, 13, 6, 7, G3)
	c.rect(38, 10, 10, 14, G7)
	c.rect(38, 10, 10, 1, G9)
	c.speckle(0, 0, 136, 60, R1, 0.1, 1, true)
	c.speckle(0, 0, 136, 60, G3, 0.08, 2, true)


## A turretless casemate destroyer: a long sloped casemate, a fixed gun to (0, 18), engine deck.
static func _enemy_destroyer(c: Canvas) -> void:
	_tracks(c, 6, 106, 37, 44)
	c.poly([4, 37, 8, 26, 108, 26, 108, 37], G5)
	c.line(8, 26, 108, 26, G8)
	c.rect(8, 33, 98, 3, G3)
	# The casemate: a sloped front rising to a flat roof.
	c.poly([20, 26, 38, 11, 88, 11, 90, 26], G6)
	c.line(38, 11, 88, 11, G10)
	c.line(20, 26, 38, 11, G9)
	c.rect(40, 15, 46, 9, G5)
	_seams(c, 50, 82, 12, 25, 16, G3, G7)
	# Engine deck louvres at the rear.
	c.rect(92, 20, 14, 6, G3)
	for i in 4:
		c.rect(93 + i * 3, 21, 1, 4, G6)
	# The fixed gun: mantlet at the casemate front, barrel to the left edge.
	c.rect(0, 17, 30, 3, G4)
	c.rect(0, 17, 30, 1, G8)
	c.rect(0, 16, 4, 5, G3)
	c.rect(24, 14, 10, 9, G7)
	c.rect(24, 14, 10, 1, G9)
	c.speckle(0, 0, 112, 44, R1, 0.1, 1, true)
	c.speckle(0, 0, 112, 44, G3, 0.08, 2, true)


## A dug-in gun behind a concrete revetment: a low turret ([8,0,32,14] is its hit box), the
## muzzle at (2, 8), concrete and an earth mound below and behind.
static func _enemy_dugin(c: Canvas) -> void:
	# The earth mound behind and the turret.
	c.poly([38, 14, 48, 12, 62, 18, 72, 24, 72, 36, 38, 36], B2)
	c.speckle(38, 12, 34, 24, B3, 0.2, 1, true)
	c.poly([10, 14, 12, 4, 20, 0, 34, 0, 40, 6, 40, 14], G6)
	c.line(20, 0, 34, 0, G10)
	c.line(12, 4, 20, 0, G9)
	c.rect(14, 8, 24, 4, G5)
	c.rect(2, 7, 14, 3, G4)
	c.rect(2, 7, 14, 1, G8)
	c.rect(0, 6, 4, 5, G3)
	# The concrete revetment: two flat tones, a chamfered top edge, a couple of chips; no marks.
	c.poly([0, 18, 4, 14, 56, 14, 56, 36, 0, 36], G6)
	c.poly([0, 18, 4, 14, 56, 14, 56, 17, 4, 17, 0, 21], G7)
	c.rect(0, 28, 56, 8, G5)
	c.poly([20, 14, 24, 14, 22, 16], CLEAR)
	c.poly([46, 14, 52, 14, 50, 17, 47, 16], G5)
	# Packed earth heaped in front along the ground.
	c.poly([0, 36, 6, 31, 30, 30, 50, 32, 60, 36], B1)


# --- The Behemoth --------------------------------------------------------------------------------------


## The hull of the super-heavy facing left: a huge slab, a lit sloped front, a turret seat on the
## roof (x 100..252), three bogie sockets at the bottom, and a secondary gun port at (10, 30).
static func _boss_hull(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.poly([0, 36, 14, 4, w - 6, 4, w, 16, w, h, 0, h], G5)
	c.rect(14, 4, w - 20, 5, G6)
	c.line(14, 4, w - 7, 4, G9)
	c.line(14, 5, w - 7, 5, G8)
	c.line(0, 36, 14, 4, G8)
	c.line(3, 36, 15, 8, G4)
	# Plate lines and rivets: a big riveted slab.
	_seams(c, 28, w - 16, 10, h - 18, 36, G3, G6)
	for y: int in [22, 48, 72]:
		c.rect(4, y, w - 8, 1, G3)
		_rivets(c, 8, w - 10, y + 2, 8, G8, G2)
	_streaks(c, 8, w - 10, 25, 7, R0)
	_streaks(c, 8, w - 10, 51, 6, R0)
	# The turret seat and its ring.
	c.rect(96, 4, 160, 4, G7)
	c.rect(98, 5, 156, 2, G3)
	# Bogie sockets: recessed bays along the bottom.
	for x: int in [16, 124, 232]:
		c.rect(x, h - 18, 72, 18, G2)
		c.rect(x, h - 18, 72, 2, G8)
		c.rect(x + 2, h - 14, 68, 2, G4)
		_rivets(c, x + 6, x + 66, h - 8, 10, G7, G1)
	# Secondary gun port at the front.
	c.rect(4, 26, 12, 8, G2)
	c.rect(2, 28, 10, 3, G4)
	c.rect(0, 27, 4, 5, G3)
	# Exhaust louvres on the rear roof.
	c.rect(w - 56, 10, 40, 12, G3)
	for i in 4:
		c.rect(w - 55, 11 + i * 3, 38, 1, G6)
	c.speckle(0, 0, w, h, R1, 0.05, 1, true)
	c.speckle(0, 0, w, h, G3, 0.07, 2, true)
	c.speckle(0, 0, w, h, R0, 0.04, 3, true)


## The Behemoth's turret (152 x 56, facing left, no barrel): slab sides, mantlet at the left; the
## broken one is split open, charred, with fire in the breach.
static func _boss_turret(c: Canvas, broken: bool) -> void:
	var w := c.w
	var h := c.h
	c.poly([4, h, 4, 22, 20, 4, w - 18, 4, w - 4, 18, w - 4, h], G6)
	c.rect(4, 14, w - 8, h - 14, G5)
	c.line(20, 4, w - 19, 4, G10)
	c.line(20, 5, w - 19, 5, G8)
	c.line(4, 22, 20, 4, G9)
	_seams(c, 30, w - 20, 8, h - 6, 28, G3, G7)
	_rivets(c, 12, w - 12, 12, 8, G9, G3)
	_rivets(c, 12, w - 12, h - 8, 8, G8, G3)
	c.rect(0, 22, 14, 22, G7)
	c.rect(0, 22, 14, 2, G9)
	c.rect(0, 28, 6, 10, G2)
	var mid := w >> 1
	c.rect(mid - 6, 0, 24, 5, G7)
	c.rect(mid - 2, 1, 16, 2, G2)
	c.speckle(0, 0, w, h, R1, 0.08, 1, true)
	c.speckle(0, 0, w, h, G3, 0.1, 2, true)
	if broken:
		# Charred, split open on top: a jagged breach with fire in it, torn plates.
		c.poly([60, 4, 70, 14, 76, 8, 86, 20, 96, 10, 104, 4], CLEAR)
		c.poly([62, 14, 74, 18, 88, 22, 96, 16, 100, 26, 66, 26], G0)
		c.blob(80.0, 23.0, 9.0, 3, 2, F0, 0.3, 1.0)
		c.blob(80.0, 24.0, 6.0, 3, 2, F1, 0.3, 1.0)
		c.blob(80.0, 25.0, 3.0, 3, 2, F2, 0.2, 1.0)
		c.speckle(0, 0, w, h, G1, 0.2, 4, true)
		c.speckle(40, 0, 80, 30, G0, 0.25, 5, true)
		c.line(30, 20, 44, 34, G0)
		c.line(110, 18, 120, 30, G0)
		c.poly([118, 4, 130, 2, 134, 10, 124, 12], G7)


## A bogie: a tracked unit 64 x 32 seen from the side (a belt around a row of wheels); broken: a
## shattered unit with a torn track, a gap and scorching.
static func _boss_bogie(c: Canvas, broken: bool) -> void:
	var w := c.w
	var h := c.h
	c.rect(8, 0, w - 16, 6, G5)
	c.rect(8, 0, w - 16, 1, G8)
	_rivets(c, 12, w - 12, 3, 8, G9, G3)
	c.rect(6, 6, w - 12, h - 6, G2)
	c.disc(11.0, 21.0, 10.0, G2)
	c.disc(w - 11.0, 21.0, 10.0, G2)
	c.rect(6, 6, w - 12, 2, G4)
	var x := 14
	while x < w - 10:
		c.disc(x + 0.5, 21.0, 6.0, G5)
		c.ring(x + 0.5, 21.0, 6.0, 5.0, G8)
		c.disc(x + 0.5, 21.0, 2.0, G9)
		c.disc(x + 0.5, 21.0, 0.8, G2)
		x += 12
	c.rect(6, h - 3, w - 12, 3, G1)
	if broken:
		# A gap in the belt, a dangling track end and scorching.
		c.rect(22, 8, 14, h - 8, CLEAR)
		c.poly([18, 12, 24, 14, 22, 24, 16, 26], CLEAR)
		c.line(36, 12, 44, 30, G1)
		c.line(22, 14, 18, 30, G1)
		c.speckle(0, 0, w, h, G0, 0.35, 4, true)
		c.speckle(0, 0, w, h, R0, 0.15, 5, true)
		c.px(30, 18, F1)
		c.px(29, 19, F0)
		c.px(31, 19, F0)
		c.poly([40, 22, 54, 26, 58, 32, 40, 32], G3)


# --- Props -----------------------------------------------------------------------------------------------


## Three angle-iron hedgehogs, each three crossed beams.
static func _tank_traps(c: Canvas) -> void:
	for i in 3:
		var cx := 11.0 + i * 21.0
		var cy := 13.0
		c.thick_line(cx - 8.0, cy + 9.0, cx + 8.0, cy - 9.0, 2.6, G6)
		c.thick_line(cx - 8.0, cy - 9.0, cx + 8.0, cy + 9.0, 2.6, G5)
		c.thick_line(cx - 10.0, cy, cx + 10.0, cy, 2.6, G7)
		c.thick_line(cx - 8.0, cy + 8.0, cx + 8.0, cy - 8.0, 1.0, G9)
		c.disc(cx, cy, 2.0, G4)
	c.speckle(0, 0, 64, 24, R1, 0.15, 1, true)
	c.speckle(0, 0, 64, 24, R2, 0.05, 2, true)


## Barbed wire: leaning stakes with coiled strands between them.
static func _wire(c: Canvas) -> void:
	for x: int in [4, 20, 36, 52, 60]:
		c.rect(x, 2, 2, 18, B3)
		c.rect(x, 2, 1, 18, B5)
	for k in 3:
		var y0 := 5 + k * 5
		for x in range(4, 60):
			var yy := y0 + int(round(sin(x * 0.9 + k) * 2.0))
			c.px(x, yy, G8)
			c.px(x + 1, yy + 1, G6)
		for t in range(8, 58, 8):
			c.px(t, y0 - 2 + (k % 2), G10)
			c.px(t + 1, y0 + 3, G10)
	c.rect(0, 18, 64, 2, B1)


## A burnt-out wreck used as a barricade: a slumped hull, a blown turret, charred plates, an ember.
static func _wreck(c: Canvas) -> void:
	c.poly([2, 32, 6, 14, 24, 8, 46, 10, 66, 16, 70, 32], G3)
	c.poly([14, 14, 20, 4, 40, 3, 44, 12], G4)
	c.poly([22, 10, 28, 6, 36, 6, 40, 10], G2)
	c.line(6, 14, 24, 8, G6)
	c.line(24, 8, 46, 10, G5)
	c.rect(4, 26, 62, 6, G1)
	for i in 6:
		c.disc(10.0 + i * 11.0, 27.0, 4.0, G2)
		c.disc(10.0 + i * 11.0, 27.0, 1.6, G5)
	# Twisted plate and a gun barrel pointing skyward.
	c.thick_line(40.0, 8.0, 56.0, 0.0, 2.4, G4)
	c.poly([44, 14, 56, 12, 60, 20, 46, 22], G5)
	c.speckle(0, 0, 72, 32, R1, 0.12, 1, true)
	c.speckle(0, 0, 72, 32, G1, 0.25, 2, true)
	c.px(30, 12, F0)
	c.px(31, 12, F1)
	c.px(30, 13, R2)


## A flooded crater: a mud lip, dark water with the lamps' reflections.
static func _crater(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.ellipse(w * 0.5, h - 6.0, w * 0.5 - 1.0, 6.0, B2)
	c.ellipse(w * 0.5, h - 5.0, w * 0.5 - 4.0, 4.4, B1)
	c.ellipse(w * 0.5, h - 5.0, w * 0.5 - 7.0, 3.2, C0)
	c.ellipse(w * 0.5, h - 6.0, w * 0.5 - 12.0, 1.8, G3)
	c.hline(14, 22, h - 7, C1)
	c.hline(26, 32, h - 6, C2)
	c.px(20, h - 5, C3)
	c.px(30, h - 7, F1)
	c.px(36, h - 5, F0)
	c.speckle(0, 0, w, h, B3, 0.2, 1, true)
	c.rect(0, h - 3, w, 3, B1)
	c.speckle(0, h - 3, w, 3, B2, 0.3, 2, true)


## A heap of rubble: broken masonry blocks and twisted rebar.
static func _rubble(c: Canvas) -> void:
	c.poly([0, 16, 4, 10, 12, 6, 22, 4, 30, 8, 36, 12, 40, 16], G5)
	c.poly([6, 16, 10, 8, 18, 6, 24, 10, 28, 16], G6)
	c.poly([20, 16, 24, 8, 30, 8, 34, 16], G4)
	c.line(4, 10, 12, 6, G9)
	c.line(12, 6, 22, 4, G8)
	c.thick_line(26.0, 8.0, 34.0, 0.0, 1.0, G8)
	c.thick_line(18.0, 6.0, 14.0, 0.0, 1.0, G7)
	c.speckle(0, 0, 40, 16, G3, 0.2, 1, true)
	c.speckle(0, 0, 40, 16, R1, 0.12, 2, true)
	c.speckle(0, 0, 40, 16, G9, 0.06, 3, true)


## The depot gate: two brutalist concrete pylons, a lintel, a heavy steel door half open, lamps.
static func _depot_gate(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	# Pylons.
	c.rect(0, 14, 34, h - 14, G6)
	c.rect(w - 34, 14, 34, h - 14, G6)
	c.rect(0, 14, 34, 3, G8)
	c.rect(w - 34, 14, 34, 3, G8)
	for x: int in [4, w - 20]:
		c.rect(x, 30, 14, 40, G5)
		c.rect(x, 30, 14, 2, G4)
	c.rect(17, 18, 1, h - 18, G4)
	c.rect(w - 18, 18, 1, h - 18, G4)
	c.speckle(0, 14, w, h - 14, G5, 0.2, 1, true)
	c.speckle(0, 14, w, h - 14, G8, 0.06, 2, true)
	# The lintel: a deep beam across the top with a weathered face.
	c.rect(8, 2, w - 16, 20, G5)
	c.rect(8, 2, w - 16, 3, G9)
	c.rect(8, 5, w - 16, 1, G7)
	c.rect(8, 20, w - 16, 2, G3)
	_seams(c, 28, w - 28, 6, 20, 28, G4, G6)
	c.speckle(8, 2, w - 16, 20, G4, 0.2, 3, true)
	# The opening: dark, a half-open steel door on the left, bars across the right.
	c.rect(34, 22, w - 68, h - 22, G0)
	c.rect(34, 22, 38, h - 22, G5)
	c.rect(34, 22, 38, 2, G8)
	_seams(c, 38, 70, 26, h, 10, G3, G6)
	_rivets(c, 38, 70, 30, 8, G9, G3)
	_rivets(c, 38, 70, 90, 8, G9, G3)
	for i in 6:
		c.rect(80 + i * 6, 26, 2, h - 26, G3)
	c.rect(34, h - 10, w - 68, 10, G4)
	# Lamps above the door: warm glow.
	for x: int in [48, w - 54]:
		c.rect(x, 22, 6, 4, G4)
		c.rect(x + 1, 25, 4, 3, F2)
		c.rect(x + 2, 25, 2, 2, F3)
		c.px(x, 28, F0)
		c.px(x + 5, 28, F0)
	c.rect(0, h - 4, w, 4, G3)


# --- Backdrops (periodic across their width) -------------------------------------------------------------


## A ridge height at x, periodic over `period` px: a few integer-frequency sines.
static func _ridge(x: int, period: int, base: float, amp: float, phase: float) -> float:
	var u := TAU * x / period
	return (
		base
		+ amp * sin(u * 2.0 + phase)
		+ amp * 0.55 * sin(u * 5.0 + phase * 2.3)
		+ amp * 0.3 * sin(u * 11.0 + phase * 0.7)
	)


## A pine: a stack of triangles; (x, base_y) is the foot, `ht` the height.
static func _pine(c: Canvas, x: int, base_y: int, ht: int, col: Color, light: Color) -> void:
	var tiers := maxi(ht / 7, 2)
	for i in tiers:
		var y_top := base_y - ht + i * (ht - 4) / tiers
		var half := 2 + (i + 1) * maxi(ht / 9, 2) / 2 + i
		var y_bot := y_top + ht / tiers + 4
		c.poly([x, y_top, x + half, y_bot, x - half, y_bot], col)
		c.line(x, y_top, x - half + 1, y_bot, light)
	c.rect(x - 1, base_y - 3, 2, 3, col)


## A poplar: a tall narrow leaf crown on a thin trunk.
static func _poplar(c: Canvas, x: int, base_y: int, ht: int, col: Color, light: Color) -> void:
	c.ellipse(x, base_y - ht * 0.55, 3.6, ht * 0.5, col)
	c.px(x - 2, int(base_y - ht * 0.6), light)
	c.px(x - 2, int(base_y - ht * 0.4), light)
	c.rect(x, base_y - 6, 1, 6, col)


## A pitched-roof house with lit windows. (x, base_y) is the bottom left; `lit` the share of
## windows with a lamp.
static func _house(
	c: Canvas,
	x: int,
	base_y: int,
	w: int,
	ht: int,
	roof: int,
	wall: Color,
	roof_col: Color,
	lit: float
) -> void:
	c.rect(x, base_y - ht, w, ht, wall)
	c.poly([x - 2, base_y - ht, x + w * 0.5, base_y - ht - roof, x + w + 2, base_y - ht], roof_col)
	c.line(x - 2, base_y - ht, int(x + w * 0.5), base_y - ht - roof, G6)
	c.rect(x + w - 8, base_y - ht - roof + 4, 3, 7, wall)
	var wx := x + 4
	while wx < x + w - 4:
		var wy := base_y - ht + 5
		while wy < base_y - 8:
			var on := c.noise(wx, wy, 9) < lit
			c.rect(wx, wy, 3, 4, F1 if on else G1)
			if on:
				c.px(wx + 1, wy + 1, F2)
			wy += 11
		wx += 8


## A warm glow: dithered rust tones around a fire, strongest at the middle (only on solid pixels).
static func _glow(c: Canvas, cx: float, cy: float, r: float) -> void:
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length() / r
			if d >= 1.0:
				continue
			var level := (1.0 - d) * (1.0 - d)
			if level > 0.08 and c.solid(x, y):
				var col := R0
				if level > 0.55:
					col = R2
				elif level > 0.25:
					col = R1
				c.px(x, y, col)


## A cold glow (blue-white lamps): sparse dither of the cold dark tones.
static func _cold_glow(c: Canvas, cx: float, cy: float, r: float) -> void:
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length() / r
			if d >= 1.0:
				continue
			var level := (1.0 - d) * (1.0 - d)
			if level > 0.1 and c.solid(x, y):
				c.px(x, y, C0 if level < 0.45 else C1)


## A fire: flame tongues on a base, hot colours.
static func _fire(c: Canvas, x: int, base_y: int, s: float) -> void:
	c.blob(x, base_y - 5.0 * s, 5.0 * s, 3, 2, F0, 0.3, 1.5)
	c.blob(x, base_y - 4.0 * s, 3.6 * s, 3, 2, F1, 0.3, 1.5)
	c.blob(x, base_y - 2.8 * s, 2.0 * s, 3, 2, F2, 0.2, 1.3)


## A smoke column rising from (x, y): dark grey puffs getting wider as they climb.
static func _smoke_column(c: Canvas, x: int, y: int, ht: int, col: Color, col2: Color) -> void:
	var py := y
	var r := 3.0
	var drift := 0.0
	while py > y - ht:
		c.blob(x + drift, py, r, 3, 3, col, 0.3, 1.0)
		c.blob(x + drift - 1.0, py - 1.0, r * 0.6, 3, 3, col2, 0.3, 1.0)
		py -= int(r * 1.2)
		r += 0.9
		drift += 0.8


static func _sky(c: Canvas) -> void:
	var bands: Array[Color] = [G1, G2, G3, G4, G5, R0, R1, R2]
	c.gradient_v(0, 0, c.w, c.h, bands)
	# Smoke banks: dithered dark clouds across the sky.
	for i in 14:
		var cx := c.noise(i, 1, 21) * c.w
		var cy := 20.0 + c.noise(i, 2, 21) * 140.0
		var rx := 40.0 + c.noise(i, 3, 21) * 70.0
		var col := G2 if cy < 100.0 else G3
		c.ellipse_dither(cx, cy, rx, 6.0 + c.noise(i, 4, 21) * 10.0, col)
	# A pale moon behind the smoke, and a few stars.
	c.ellipse_dither(110.0, 36.0, 28.0, 20.0, G4)
	c.disc(110.0, 36.0, 10.0, G5)
	c.disc(110.0, 36.0, 8.0, G6)
	c.disc(107.0, 34.0, 3.0, G7)
	for i in 40:
		c.px(int(c.noise(i, 7, 22) * c.w), int(c.noise(i, 8, 22) * 60.0), G5)


static func _hills_far(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	# Two ridges, the far one pale and low in contrast, the near one darker with woods on top.
	for x in w:
		var y1 := int(_ridge(x, w, 52.0, 9.0, 0.6))
		c.rect(x, y1, 1, h - y1, G4)
		var y2 := int(_ridge(x, w, 74.0, 10.0, 2.4))
		c.rect(x, y2, 1, h - y2, G3)
	for x in range(6, w, 9):
		var y2 := int(_ridge(x, w, 74.0, 10.0, 2.4))
		var tall := 8 + int(c.noise(x, 1, 31) * 10.0)
		_pine(c, x, y2 + 2, tall, G2, G3)
	for x in range(20, w, 53):
		var y1 := int(_ridge(x, w, 52.0, 9.0, 0.6))
		_pine(c, x, y1 + 2, 10, G3, G4)
	# Smoke columns from burning farms, and a few warm points.
	for x: int in [180, 470, 760]:
		var y2 := int(_ridge(x, w, 74.0, 10.0, 2.4))
		_smoke_column(c, x, y2 - 2, 46, G5, G6)
		c.px(x, y2 - 1, F0)
		c.px(x + 1, y2, F1)
	c.rect(0, h - 10, w, 10, G2)


static func _fields(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	# Fields in receding strips, furrows, and a hedgerow along the front.
	c.rect(0, 92, w, h - 92, B1)
	for i in 6:
		c.rect(0, 92 + i * 8, w, 4, O1 if i % 2 == 0 else B1)
	for x in range(0, w, 3):
		c.px(x, 100 + (x * 7) % 31, O2)
	# Hedgerow: bumpy dark band with leaf speckle.
	for x in w:
		var top := 80 + int(_ridge(x, w, 4.0, 3.0, 1.1) + c.noise(x / 3, 1, 33) * 4.0)
		c.rect(x, top, 1, 96 - top, G2)
		if c.noise(x, 2, 33) < 0.18:
			c.px(x, top + 2, O1)
	c.rect(0, 94, w, 3, B1)
	# Poplars along the road, left half; a lone row right.
	for x in range(20, 500, 29):
		_poplar(c, x, 94, 58 + int(c.noise(x, 3, 34) * 24.0), G2, O1)
	for x in range(700, 940, 34):
		_poplar(c, x, 94, 54 + int(c.noise(x, 3, 34) * 20.0), G3, O1)
	# Fence posts.
	for x in range(0, w, 17):
		c.rect(x, 96, 2, 7, B3)
	c.rect(0, 98, w, 1, B3)
	# The burning farmstead.
	_glow(c, 600.0, 60.0, 56.0)
	_house(c, 575, 96, 44, 22, 14, G3, B1, 0.2)
	c.rect(618, 80, 24, 16, O1)
	c.poly([616, 80, 630, 70, 644, 80], B1)
	_fire(c, 592, 70, 1.5)
	_fire(c, 606, 68, 1.2)
	_fire(c, 634, 74, 1.0)
	_smoke_column(c, 596, 52, 46, G4, G5)
	_smoke_column(c, 632, 60, 40, G4, G5)
	_house(c, 780, 96, 30, 18, 10, G3, B1, 0.5)
	c.rect(0, h - 6, w, 6, G2)


static func _village(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(0, 104, w, h - 104, G2)
	# Orchard trees on the left.
	for x in range(10, 220, 24):
		c.rect(x, 86, 2, 14, B1)
		c.disc(x + 1.0, 80.0, 9.0, O1)
		c.disc(x - 3.0, 83.0, 6.0, O1)
		c.disc(x + 5.0, 82.0, 6.0, G3)
	# Houses along the street.
	var hx := 230
	var i := 0
	while hx < 740:
		var hw := 30 + int(c.noise(i, 1, 41) * 18.0)
		var ht := 26 + int(c.noise(i, 2, 41) * 22.0)
		_house(c, hx, 104, hw, ht, 12 + int(c.noise(i, 3, 41) * 6.0), G3, G2, 0.55)
		hx += hw + 6 + int(c.noise(i, 4, 41) * 6.0)
		i += 1
	# The church: nave, tower, spire, lit windows.
	c.rect(430, 62, 22, 42, G4)
	c.rect(452, 76, 34, 28, G3)
	c.poly([426, 62, 441, 20, 456, 62], G2)
	c.line(441, 20, 427, 62, G5)
	c.rect(440, 4, 2, 18, G5)
	c.rect(436, 8, 10, 1, G5)
	c.rect(437, 70, 8, 12, G1)
	c.rect(439, 72, 4, 8, F1)
	c.rect(440, 73, 2, 6, F2)
	c.rect(458, 84, 4, 8, F1)
	c.rect(470, 84, 4, 8, F1)
	c.poly([450, 76, 468, 66, 488, 76], G2)
	# The stone bridge: a wall with an arch over dark water.
	c.rect(760, 86, 170, 18, G5)
	c.rect(760, 86, 170, 3, G7)
	for x in range(764, 928, 9):
		c.rect(x, 90, 1, 12, G4)
	for r in range(0, 12, 4):
		c.rect(760, 90 + r, 170, 1, G4)
	c.ellipse(845.0, 104.0, 28.0, 17.0, G1)
	c.rect(817, 104, 56, 10, G1)
	c.hline(822, 868, 108, C0)
	c.hline(830, 850, 110, C1)
	c.px(838, 106, C2)
	c.rect(0, h - 10, w, 10, G3)
	# Cobbles at the bottom.
	for y in range(h - 10, h, 3):
		for x in range(y % 6, w, 7):
			c.rect(x, y, 4, 2, G4)
	# A fire on a roof.
	_glow(c, 330.0, 80.0, 30.0)
	_fire(c, 338, 78, 1.2)
	_smoke_column(c, 338, 66, 40, G4, G5)


static func _quarry(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(0, 112, w, h - 112, G2)
	# Pine woods on the left third and right end.
	for x in range(4, 330, 11):
		_pine(c, x, 112, 36 + int(c.noise(x, 1, 51) * 30.0), G2, G3)
	for x in range(880, 960, 12):
		_pine(c, x, 112, 34 + int(c.noise(x, 1, 51) * 24.0), G2, G3)
	# The terraced quarry: stepped rock faces rising to the right.
	for s in 6:
		var x0 := 340 + s * 46
		var y0 := 104 - s * 14
		c.rect(x0, y0, 62, 112 - y0, G5 if s % 2 == 0 else G4)
		c.rect(x0, y0, 62, 3, G8)
		c.rect(x0, y0 + 3, 62, 1, G3)
		c.speckle(x0, y0, 62, 112 - y0, G6, 0.1, s + 1, true)
		c.speckle(x0, y0, 62, 112 - y0, G3, 0.12, s + 7, true)
	# Pylons with sagging wires.
	var pylons: Array[int] = [90, 360, 640, 900]
	for px_x in pylons:
		_pylon(c, px_x, 112, 70)
	for k in pylons.size() - 1:
		_wires(c, pylons[k], pylons[k + 1], 112 - 62)
	# The sawmill burning below: a long shed with a stack and fire.
	c.rect(600, 82, 90, 30, G3)
	c.poly([596, 82, 630, 70, 694, 82], G2)
	c.rect(676, 56, 8, 30, G4)
	_glow(c, 640.0, 86.0, 52.0)
	_fire(c, 624, 86, 1.6)
	_fire(c, 650, 84, 1.3)
	_fire(c, 678, 54, 1.0)
	for x in range(606, 686, 12):
		c.rect(x, 96, 5, 7, F1)
		c.px(x + 1, 97, F2)
	_smoke_column(c, 640, 70, 50, G4, G5)
	c.rect(0, h - 8, w, 8, G3)


## A lattice pylon: an A-frame with cross braces and two cross-arms.
static func _pylon(c: Canvas, x: int, base_y: int, ht: int) -> void:
	c.line(x - 9, base_y, x - 1, base_y - ht, G4)
	c.line(x + 9, base_y, x + 1, base_y - ht, G4)
	c.line(x - 8, base_y, x + 1, base_y - ht, G3)
	c.line(x + 8, base_y, x - 1, base_y - ht, G3)
	for k in range(1, 6):
		var y := base_y - k * ht / 6
		c.hline(x - 8 + k, x + 8 - k, y, G4)
	c.hline(x - 14, x + 14, base_y - ht + 8, G4)
	c.hline(x - 10, x + 10, base_y - ht + 18, G4)


static func _wires(c: Canvas, x0: int, x1: int, y: int) -> void:
	for dy: int in [8, 18]:
		var span := x1 - x0 - 28
		for i in span:
			var u := float(i) / span
			var sag := int(round(sin(u * PI) * 5.0))
			c.px(x0 + 14 + i, y + dy + sag, G3)


static func _town(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(0, 108, w, h - 108, G2)
	# Sawtooth foundry roofs and long sheds.
	var x := 8
	var i := 0
	while x < w - 90:
		var sw := 60 + int(c.noise(i, 1, 61) * 40.0)
		c.rect(x, 78, sw, 30, G3)
		for k in range(0, sw - 12, 16):
			c.poly([x + k, 78, x + k, 62, x + k + 14, 78], G4)
			c.line(x + k, 62, x + k + 14, 78, G6)
		for k in range(0, sw - 8, 12):
			var hot := c.noise(i, k, 62) < 0.45
			c.rect(x + 4 + k, 88, 6, 8, F0 if hot else G1)
			if hot:
				c.rect(x + 5 + k, 89, 4, 4, F1)
				c.px(x + 6 + k, 90, F2)
		x += sw + 8 + int(c.noise(i, 2, 61) * 10.0)
		i += 1
	# Tall chimneys with smoke and a flame on top.
	for cx: int in [150, 330, 560, 790]:
		c.rect(cx, 16, 8, 94, G4)
		c.rect(cx, 16, 2, 94, G6)
		c.rect(cx - 1, 14, 10, 3, G5)
		for y in range(26, 100, 12):
			c.rect(cx, y, 8, 1, G3)
		_fire(c, cx + 4, 14, 1.0)
		_smoke_column(c, cx + 4, 8, 14, G4, G5)
	# Lamp posts with warm halos along the street.
	for lx in range(40, w, 70):
		c.rect(lx, 82, 1, 26, G5)
		c.rect(lx - 2, 80, 6, 3, G6)
		c.rect(lx - 1, 82, 4, 2, F2)
		c.px(lx, 82, F3)
		_glow(c, lx + 1.0, 83.0, 12.0)
	# The town gate in the middle: two stone posts and an arch.
	c.rect(400, 70, 18, 40, G5)
	c.rect(458, 70, 18, 40, G5)
	c.rect(396, 66, 26, 5, G7)
	c.rect(454, 66, 26, 5, G7)
	c.rect(418, 70, 40, 8, G4)
	c.rect(418, 78, 40, 30, G1)
	c.rect(0, h - 8, w, 8, G3)


static func _depot_backdrop(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.rect(0, 108, w, h - 108, G2)
	# A forest ring behind.
	for x in range(2, w, 10):
		_pine(c, x, 108, 30 + int(c.noise(x, 1, 71) * 28.0), G2, G3)
	# Brutalist concrete blocks with slit windows and flat roofs: [x, width, height].
	var blocks: Array = [
		[40, 90, 40], [170, 130, 56], [380, 100, 36], [560, 140, 62], [800, 110, 44]
	]
	for b: Array in blocks:
		var bx: int = b[0]
		var bw: int = b[1]
		var bh: int = b[2]
		c.rect(bx, 108 - bh, bw, bh, G5)
		c.rect(bx, 108 - bh, bw, 3, G8)
		c.rect(bx, 108 - bh + 3, bw, 1, G3)
		_seams(c, bx + 18, bx + bw - 10, 108 - bh + 4, 108, 30, G4, G6)
		for sx in range(bx + 8, bx + bw - 10, 14):
			c.rect(sx, 108 - bh + 10, 8, 2, G1)
			c.rect(sx, 108 - bh + 22, 8, 2, F1 if c.noise(sx, bx, 72) < 0.3 else G1)
		c.speckle(bx, 108 - bh, bw, bh, G4, 0.2, 3, true)
	# Floodlight towers with cold lamps.
	for tx: int in [140, 520, 740]:
		c.rect(tx, 36, 2, 72, G4)
		c.line(tx - 5, 108, tx, 50, G4)
		c.line(tx + 7, 108, tx + 1, 50, G4)
		c.rect(tx - 7, 32, 16, 5, G6)
		c.rect(tx - 6, 36, 14, 2, C2)
		c.rect(tx - 4, 37, 10, 1, C3)
		_cold_glow(c, tx + 1.0, 38.0, 22.0)
	# Chain-link fence along the front.
	for x in range(0, w, 14):
		c.rect(x, 96, 1, 14, G4)
	c.rect(0, 96, w, 1, G5)
	c.rect(0, 108, w, 1, G4)
	for x in range(0, w, 3):
		c.px(x, 100 + (x % 6), G3)
	c.rect(0, h - 8, w, 8, G3)


static func _ground(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	c.fill(B2)
	# Layers from the grass verge at the top to the mud of the road.
	c.rect(0, 0, w, 6, B1)
	for x in w:
		if c.noise(x, 1, 81) < 0.6:
			c.px(x, 5 + int(c.noise(x, 2, 81) * 2.0), O1)
	c.rect(0, 6, w, 14, B3)
	c.rect(0, 20, w, 30, B2)
	c.rect(0, 50, w, h - 50, B1)
	# Ruts along the road and puddles that catch the lamps.
	for x in w:
		var rut := 24 + int(round(sin(TAU * x / w * 6.0) * 1.5))
		c.px(x, rut, B1)
		c.px(x, rut + 1, B0)
		c.px(x, rut + 12, B1)
		c.px(x, rut + 13, B3)
	for p in range(0, w, 130):
		var py := 30 + int(c.noise(p, 3, 82) * 14.0)
		var pw := 22.0 + c.noise(p, 4, 82) * 14.0
		c.ellipse(p + 40.0, py, pw, 3.0, C0)
		c.hline(p + 30, p + 46, py - 1, C1)
		c.px(p + 38, py, C2)
	c.speckle(0, 0, w, h, B4, 0.12, 5, false)
	c.speckle(0, 0, w, h, B0, 0.1, 6, false)


static func _debris(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	# Dark foreground silhouettes: grass blades, posts, wire, barrels, chunks of masonry.
	for x in range(0, w, 2):
		var ht := 4 + int(c.noise(x, 1, 91) * 10.0)
		if c.noise(x, 2, 91) < 0.7:
			c.rect(x, h - ht, 1, ht, G0)
	for x in range(16, w, 78):
		var ht := 22 + int(c.noise(x, 3, 91) * 14.0)
		c.rect(x, h - ht, 3, ht, G0)
		c.rect(x - 4, h - ht + 4, 11, 1, G0)
		c.line(x + 3, h - ht + 4, x + 40, h - ht + 9, G0)
	for x in range(45, w, 130):
		c.rect(x, h - 18, 10, 18, G1)
		c.rect(x, h - 18, 10, 2, G3)
		c.rect(x, h - 11, 10, 1, G0)
	for x in range(70, w, 110):
		c.poly([x, h, x + 6, h - 12, x + 16, h - 6, x + 24, h], G0)
		c.poly([x + 8, h, x + 12, h - 8, x + 18, h], G2)
	c.rect(0, h - 3, w, 3, G0)


## The picker card: the Citadel in cutaway rolling right along a country road past a burning
## village at dusk.
static func _picker(c: Canvas) -> void:
	var w := c.w
	var h := c.h
	var bands: Array[Color] = [G1, G2, G3, G4, R0, R1, R2, F0]
	c.gradient_v(0, 0, w, 150, bands)
	# Far hills and a burning village behind the tank.
	for x in w:
		var y := int(_ridge(x, w, 90.0, 6.0, 0.9))
		c.rect(x, y, 1, 160 - y, G3)
	for x in range(8, 140, 20):
		_pine(c, x, 92, 26 + int(c.noise(x, 3, 95) * 14.0), G2, G3)
	var hx := 150
	var i := 0
	while hx < 310:
		var hw := 20 + int(c.noise(i, 1, 95) * 10.0)
		_house(c, hx, 90, hw, 18 + int(c.noise(i, 2, 95) * 8.0), 8, G2, G1, 0.5)
		hx += hw + 4
		i += 1
	_glow(c, 230.0, 70.0, 64.0)
	_fire(c, 205, 76, 1.8)
	_fire(c, 240, 74, 1.4)
	_smoke_column(c, 210, 62, 50, G4, G5)
	_smoke_column(c, 246, 60, 44, G4, G5)
	# The road.
	c.rect(0, 150, w, h - 150, B2)
	c.rect(0, 150, w, 4, B1)
	c.rect(0, 160, w, 20, B1)
	c.ellipse(60.0, 172.0, 24.0, 3.0, C0)
	c.hline(48, 64, 171, C1)
	c.speckle(0, 152, w, h - 152, B3, 0.1, 2, false)
	_picker_citadel(c, 12, 84)


static func _picker_citadel(c: Canvas, x: int, y: int) -> void:
	# Tracks: a belt along the bottom, road wheels, the sprocket and the idler.
	c.rect(x + 8, y + 70, 272, 22, G2)
	c.disc(x + 10.0, y + 81.0, 11.0, G2)
	c.disc(x + 278.0, y + 81.0, 11.0, G2)
	c.rect(x + 8, y + 70, 272, 1, G4)
	var wheel := Canvas.new(18, 18)
	_road_wheel(wheel)
	for k in 11:
		c.blit(wheel.img, x + int(22.0 + k * 24.4) - 9, y + 72, false)
	var spr := Canvas.new(22, 22)
	_sprocket(spr)
	c.blit(spr.img, x - 1, y + 67, false)
	var idl := Canvas.new(20, 20)
	_idler(idl)
	c.blit(idl.img, x + 268, y + 68, false)
	# The hull and its three rooms, the machinery inside them.
	var hull := Canvas.new(288, 80)
	hull.seed_value = 11
	_hull(hull, true)
	hull.outline(G1)
	c.blit(hull.img, x, y, false)
	var rooms: Array = [[12, "diesel", 96], [112, "dynamo", 80], [196, "steam", 88]]
	for r: Array in rooms:
		var room := Canvas.new(int(r[2]), 48)
		room.seed_value = 13
		_room(room, str(r[1]))
		c.blit(room.img, x + int(r[0]), y + 18, false)
	var diesel := Canvas.new(56, 32)
	_diesel_block(diesel)
	c.blit(diesel.img, x + 20, y + 30, false)
	var fly := Canvas.new(36, 36)
	_flywheel(fly, 6)
	c.blit(fly.img, x + 68, y + 28, false)
	var dyn := Canvas.new(40, 28)
	_dynamo_housing(dyn)
	c.blit(dyn.img, x + 120, y + 34, false)
	var arm := Canvas.new(20, 20)
	_dynamo_armature(arm)
	c.blit(arm.img, x + 130, y + 38, false)
	var boiler := Canvas.new(40, 32)
	_boiler(boiler)
	c.blit(boiler.img, x + 202, y + 32, false)
	var fb := Canvas.new(20, 16)
	_firebox(fb)
	c.blit(fb.img, x + 212, y + 50, false)
	var fl := Canvas.new(16, 16)
	_flame(fl)
	c.blit(fl.img, x + 214, y + 50, false)
	# Each room's lamp: warm, cold, warm.
	c.disc(x + 62.0, y + 24.0, 3.0, F1)
	c.disc(x + 152.0, y + 24.0, 3.0, C2)
	c.disc(x + 240.0, y + 24.0, 3.0, F1)
	# The turret and its level barrel.
	var tur := Canvas.new(120, 44)
	tur.seed_value = 14
	_turret(tur)
	tur.outline(G1)
	c.blit(tur.img, x + 104, y - 40, false)
	c.rect(x + 224, y - 24, 48, 4, G5)
	c.rect(x + 224, y - 24, 48, 1, G9)
	c.rect(x + 270, y - 26, 4, 8, G4)
	# Exhaust smoke from the rear.
	_smoke_column(c, x + 28, y - 4, 40, G4, G5)


# --- Effects -----------------------------------------------------------------------------------------------


## A muzzle flash pointing right: a bright cone with a star at the muzzle end of the sprite (left).
static func _muzzle_flash(c: Canvas) -> void:
	var cy := c.h * 0.5
	c.poly([2, cy, 10, cy - 7, 31, cy - 2, 31, cy + 2, 10, cy + 7], F0)
	c.poly([2, cy, 10, cy - 5, 28, cy - 1, 28, cy + 1, 10, cy + 5], F1)
	c.poly([3, cy, 10, cy - 3, 24, cy, 10, cy + 3], F2)
	c.poly([4, cy, 10, cy - 1, 18, cy, 10, cy + 1], F3)
	# Spikes up and down and a few sparks.
	c.thick_line(8.0, cy, 13.0, cy - 9.0, 1.2, F1)
	c.thick_line(8.0, cy, 13.0, cy + 9.0, 1.2, F1)
	c.thick_line(6.0, cy, 4.0, cy - 8.0, 1.0, F0)
	c.thick_line(6.0, cy, 4.0, cy + 8.0, 1.0, F0)
	c.px(26, int(cy) - 5, F1)
	c.px(28, int(cy) + 4, F0)
	c.px(20, int(cy) + 8, F1)


## A fireball: a lumpy hot body in four layers with a dark smoke rim and flying sparks.
static func _explosion(c: Canvas, r: float) -> void:
	var cx := c.w * 0.5
	var cy := c.h * 0.5
	c.blob(cx, cy, r, 7, 11, G4, 0.28, 1.0)
	c.blob(cx, cy, r * 0.88, 7, 11, F0, 0.3, 1.0)
	c.blob(cx + 1.0, cy - 1.0, r * 0.66, 6, 13, F1, 0.3, 1.0)
	c.blob(cx, cy - 1.0, r * 0.42, 5, 17, F2, 0.25, 1.0)
	c.blob(cx, cy - 1.0, r * 0.2, 4, 19, F3, 0.2, 1.0)
	for i in 14:
		var a := c.noise(i, 1, 101) * TAU
		var d := r * (0.85 + c.noise(i, 2, 101) * 0.18)
		c.px(int(cx + cos(a) * d), int(cy + sin(a) * d), F1 if i % 2 == 0 else F0)
	c.speckle(0, 0, c.w, c.h, G3, 0.1, 3, true)


## A dirt spray: a fan of clods thrown up and to the right.
static func _dirt_spray(c: Canvas) -> void:
	var ox := 4.0
	var oy := c.h - 2.0
	for i in 16:
		var a := -0.2 - c.noise(i, 1, 111) * 1.3
		var d := 6.0 + c.noise(i, 2, 111) * 22.0
		var x := ox + cos(a) * d
		var y := oy + sin(a) * d * 0.9 + d * d * 0.012
		var col := B4 if i % 3 == 0 else (B3 if i % 3 == 1 else B2)
		c.disc(x, y, 1.4 + c.noise(i, 3, 111) * 1.8, col)
	for i in 6:
		c.px(int(ox + 6.0 + i * 3.0), int(oy - 2.0 - (i % 3)), B5)
	c.ellipse(ox + 5.0, oy, 7.0, 2.0, B2)


# --- Drawing surface ------------------------------------------------------------------------------------------


## An Image with bounds-checked drawing primitives. No palette knowledge: callers pass colours.
class Canvas:
	extends RefCounted
	const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

	var img: Image = null
	var w: int = 1
	var h: int = 1
	var seed_value: int = 0

	func _init(p_w: int, p_h: int) -> void:
		w = maxi(p_w, 1)
		h = maxi(p_h, 1)
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)

	func fill(col: Color) -> void:
		img.fill(col)

	func inside(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h

	func px(x: int, y: int, col: Color) -> void:
		if inside(x, y):
			img.set_pixel(x, y, col)

	func solid(x: int, y: int) -> bool:
		return inside(x, y) and img.get_pixel(x, y).a > 0.5

	## An ordered-dither threshold in (0, 1) for the pixel.
	func bayer(x: int, y: int) -> float:
		return (float(BAYER[(y & 3) * 4 + (x & 3)]) + 0.5) / 16.0

	## A deterministic hash of the pixel and `salt` in [0, 1), different per sprite.
	func noise(x: int, y: int, salt: int = 0) -> float:
		var n := (x * 374761393 + y * 668265263 + (salt + seed_value) * 1274126177) & 0x7FFFFFFF
		n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
		n = n ^ (n >> 16)
		return float(n & 0xFFFF) / 65536.0

	func rect(x: int, y: int, rw: int, rh: int, col: Color) -> void:
		if rw > 0 and rh > 0:
			img.fill_rect(Rect2i(x, y, rw, rh), col)

	func frame(x: int, y: int, rw: int, rh: int, col: Color) -> void:
		rect(x, y, rw, 1, col)
		rect(x, y + rh - 1, rw, 1, col)
		rect(x, y, 1, rh, col)
		rect(x + rw - 1, y, 1, rh, col)

	func hline(x0: int, x1: int, y: int, col: Color) -> void:
		rect(mini(x0, x1), y, absi(x1 - x0) + 1, 1, col)

	func line(x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
		var dx := absi(x1 - x0)
		var dy := -absi(y1 - y0)
		var sx := 1 if x0 < x1 else -1
		var sy := 1 if y0 < y1 else -1
		var err := dx + dy
		var x := x0
		var y := y0
		for _i in 4096:
			px(x, y, col)
			if x == x1 and y == y1:
				break
			var e2 := 2 * err
			if e2 >= dy:
				err += dy
				x += sx
			if e2 <= dx:
				err += dx
				y += sy

	## A line `width` px thick, drawn as discs along the segment.
	func thick_line(x0: float, y0: float, x1: float, y1: float, width: float, col: Color) -> void:
		var steps := maxi(int(maxf(absf(x1 - x0), absf(y1 - y0)) * 2.0), 1)
		for i in steps + 1:
			var t := float(i) / steps
			disc(lerpf(x0, x1, t), lerpf(y0, y1, t), width * 0.5, col)

	## A filled disc (pixel centres within `r` of (cx, cy), grid coordinates).
	func disc(cx: float, cy: float, r: float, col: Color) -> void:
		ellipse(cx, cy, r, r, col)

	func ellipse(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
		if rx <= 0.0 or ry <= 0.0:
			return
		for y in range(maxi(int(floor(cy - ry)), 0), mini(int(ceil(cy + ry)), h - 1) + 1):
			for x in range(maxi(int(floor(cx - rx)), 0), mini(int(ceil(cx + rx)), w - 1) + 1):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0:
					img.set_pixel(x, y, col)

	## A dithered soft ellipse: denser near the middle.
	func ellipse_dither(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
		for y in range(maxi(int(floor(cy - ry)), 0), mini(int(ceil(cy + ry)), h - 1) + 1):
			for x in range(maxi(int(floor(cx - rx)), 0), mini(int(ceil(cx + rx)), w - 1) + 1):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				var d2 := dx * dx + dy * dy
				if d2 <= 0.6:
					img.set_pixel(x, y, col)

	func ring(cx: float, cy: float, r_out: float, r_in: float, col: Color) -> void:
		for y in range(maxi(int(floor(cy - r_out)), 0), mini(int(ceil(cy + r_out)), h - 1) + 1):
			for x in range(maxi(int(floor(cx - r_out)), 0), mini(int(ceil(cx + r_out)), w - 1) + 1):
				var d2 := (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy)
				if d2 <= r_out * r_out and d2 >= r_in * r_in:
					img.set_pixel(x, y, col)

	## A lumpy round shape: radius r x (1 + lump/2 x sin(lobes x angle + phase)); `stretch` > 1
	## makes it taller than wide.
	func blob(
		cx: float,
		cy: float,
		r: float,
		lobes: int,
		phase: int,
		col: Color,
		lump: float,
		stretch: float
	) -> void:
		var ry := r * stretch
		var y0 := maxi(int(floor(cy - ry * 1.4)), 0)
		var y1 := mini(int(ceil(cy + ry * 1.4)), h - 1)
		var x0 := maxi(int(floor(cx - r * 1.4)), 0)
		var x1 := mini(int(ceil(cx + r * 1.4)), w - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var dx := x + 0.5 - cx
				var dy := (y + 0.5 - cy) / stretch
				var a := atan2(dy, dx)
				var lim := r * (1.0 + lump * 0.5 * sin(a * lobes + phase + seed_value * 0.01))
				if dx * dx + dy * dy <= lim * lim:
					img.set_pixel(x, y, col)

	## A filled polygon from flat [x0, y0, x1, y1, ...] (even-odd, sampled at pixel centres).
	func poly(flat: Array, col: Color) -> void:
		var n := flat.size() / 2
		if n < 3:
			return
		var y_min := h
		var y_max := -1
		for i in n:
			y_min = mini(y_min, int(floor(float(flat[i * 2 + 1]))))
			y_max = maxi(y_max, int(ceil(float(flat[i * 2 + 1]))))
		for y in range(maxi(y_min, 0), mini(y_max, h - 1) + 1):
			var yc := y + 0.5
			var xs: Array[float] = []
			for i in n:
				var ax := float(flat[i * 2])
				var ay := float(flat[i * 2 + 1])
				var bx := float(flat[((i + 1) % n) * 2])
				var by := float(flat[((i + 1) % n) * 2 + 1])
				if (ay <= yc and by > yc) or (by <= yc and ay > yc):
					xs.append(ax + (yc - ay) / (by - ay) * (bx - ax))
			xs.sort()
			var k := 0
			while k + 1 < xs.size():
				var xa := int(round(xs[k]))
				var xb := int(round(xs[k + 1]))
				if xb > xa:
					rect(xa, y, xb - xa, 1, col)
				k += 2

	## Weathering without per-pixel noise: sparse soft streaks of `col` running down in the rect
	## (soot, rust or damp), 2 px wide and 2-7 px long, on about `density` / 2 of the column pairs;
	## on_solid keeps them off transparent pixels.
	func speckle(
		x: int, y: int, rw: int, rh: int, col: Color, density: float, salt: int, on_solid: bool
	) -> void:
		var y_end := mini(y + rh, h)
		var xx := maxi(x, 0)
		while xx < mini(x + rw, w):
			if noise(xx, 0, salt) < density * 0.5:
				var y0 := y + int(noise(xx, 1, salt) * float(rh) * 0.8)
				var n := 2 + int(noise(xx, 2, salt) * 6.0)
				for k in n:
					var yy := y0 + k
					if yy < 0 or yy >= y_end:
						break
					for dx in 2:
						if xx + dx < w and (not on_solid or solid(xx + dx, yy)):
							img.set_pixel(xx + dx, yy, col)
			xx += 2

	## A vertical banded gradient through `cols` over the rect (flat steps, no dither).
	func gradient_v(x: int, y: int, rw: int, rh: int, cols: Array[Color]) -> void:
		var n := cols.size()
		if n < 2 or rh < 1:
			if n > 0:
				rect(x, y, rw, rh, cols[0])
			return
		for yy in rh:
			var f := float(yy) / maxf(rh - 1, 1) * (n - 1)
			var col: Color = cols[clampi(int(round(f)), 0, n - 1)]
			for xx in rw:
				px(x + xx, y + yy, col)

	## Darkens the rim: every solid pixel with a transparent 4-neighbour inside the image becomes
	## `col`. Pixels on the image border stay (a sprite meant to touch the edge keeps it).
	func outline(col: Color) -> void:
		var marks: Array[Vector2i] = []
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a < 0.5:
					continue
				for d: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					var nx := x + d.x
					var ny := y + d.y
					if inside(nx, ny) and img.get_pixel(nx, ny).a < 0.5:
						marks.append(Vector2i(x, y))
						break
		for m in marks:
			img.set_pixel(m.x, m.y, col)

	## Clears the four corner pixels (a boxy sprite that should not fill its frame).
	func round_corners() -> void:
		for p: Vector2i in [
			Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)
		]:
			img.set_pixel(p.x, p.y, Color(0.0, 0.0, 0.0, 0.0))

	## Erases every pixel where `mask` is transparent.
	func clip_to(mask: Image) -> void:
		for y in h:
			for x in w:
				if mask.get_pixel(x, y).a < 0.5:
					img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	## Draws `src` at (x, y), optionally mirrored; transparent pixels leave the canvas alone.
	func blit(src: Image, x: int, y: int, flip: bool) -> void:
		var s := src
		if flip:
			s = src.duplicate()
			s.flip_x()
		img.blend_rect(s, Rect2i(0, 0, s.get_width(), s.get_height()), Vector2i(x, y))
