class_name FishingFallbackSprites
extends RefCounted
## Placeholder art (brief 3.4 step 5): every assets/fishing/art.json sprite except picker_card,
## drawn in code from the art.json palette with simple shapes, at the art.json size. Used when the
## art pipeline could not run (no FAL_KEY or WATTLANDS_ALLOW_ART), and by the view whenever a PNG
## is missing: `FishingFallbackSprites.image("fish_tuna")`.
## src/games/fishing/tools/fishing_write_fallback_sprites.gd writes these images (and their parts)
## to assets/fishing/sprites/ with a sprites.json in the pipeline's format.
##
## Rules the drawing keeps (the same review criteria as generated art): fish face left with the
## tail at the right edge, the boat's bow points right, the red key ramp (#e0413a / #9e2228) is
## used only on the boat's trim and canopy and the angler's cap and shirt (PaletteSwap), both
## reefs end flat at the right, and every pixel is a palette colour at alpha 255 or (0, 0, 0, 0).
## Character sprites get a 1 px dark navy outline. Pure and deterministic: variation comes from
## FishingRandom.mix32 of fixed integers, never from an RNG or the clock.

## The art.json palette, in order (tests/games/fishing/art checks that they match).
const PALETTE: PackedStringArray = [
	"#1a1f3a",
	"#23305c",
	"#0f2a4a",
	"#1f4e8c",
	"#2a74b8",
	"#3fa0d8",
	"#8fd6f5",
	"#c6ecfa",
	"#f7f9fb",
	"#e8f7fb",
	"#c9d1d9",
	"#b8c7d6",
	"#8a96a3",
	"#4b5563",
	"#f4e4b0",
	"#e3c27a",
	"#9a6236",
	"#5a3820",
	"#f2665a",
	"#f28c28",
	"#f6d33c",
	"#e8b730",
	"#9bd23c",
	"#3fae4a",
	"#23743a",
	"#2bb3a3",
	"#9b6be0",
	"#ef6fa6",
	"#f1c29a",
	"#c98e63",
	"#e0413a",
	"#9e2228",
]

# Palette indexes by role.
const NAVY := 0
const NAVY2 := 1
const DEEP := 2
const BLUE := 3
const MID := 4
const LIGHT := 5
const SKY := 6
const PALE := 7
const WHITE := 8
const OFF_WHITE := 9
const LGREY := 10
const BGREY := 11
const GREY := 12
const DGREY := 13
const SAND_PALE := 14
const SAND := 15
const BROWN := 16
const DBROWN := 17
const CORAL := 18
const ORANGE := 19
const YELLOW := 20
const GOLD := 21
const LIME := 22
const GREEN := 23
const DGREEN := 24
const TEAL := 25
const PURPLE := 26
const PINK := 27
const SKIN := 28
const TAN := 29
const KEY := 30
const KEY_DARK := 31

## The red key ramp PaletteSwap recolours (brief 3.3).
const KEY_COLORS: PackedStringArray = ["#e0413a", "#9e2228"]
## The only sprites that may use the key ramp (with picker_card, which is a whole scene).
const KEY_SPRITES: PackedStringArray = ["boat", "rig_angler"]

## Every sprite this class draws, with its art.json size (picker_card keeps its G0 placeholder).
const SIZES := {
	"boat": Vector2i(80, 32),
	"rig_bike": Vector2i(24, 16),
	"rig_angler": Vector2i(14, 12),
	"rig_crank": Vector2i(10, 10),
	"rig_reel": Vector2i(10, 10),
	"fish_mackerel": Vector2i(24, 8),
	"fish_mahi": Vector2i(40, 16),
	"fish_tuna": Vector2i(44, 16),
	"fish_marlin": Vector2i(64, 22),
	"gull_up": Vector2i(10, 8),
	"gull_down": Vector2i(10, 8),
	"bait_ball": Vector2i(32, 12),
	"sonar_mark": Vector2i(8, 5),
	"current_seam": Vector2i(48, 4),
	"splash": Vector2i(20, 12),
	"spray": Vector2i(32, 24),
	"catch_flash": Vector2i(24, 24),
	"trophy_badge": Vector2i(16, 16),
	"clouds": Vector2i(320, 24),
	"islands_far": Vector2i(256, 12),
	"island_palm": Vector2i(80, 24),
	"sun": Vector2i(12, 12),
	"wake": Vector2i(32, 6),
	"surface_strip": Vector2i(64, 6),
	"light_rays": Vector2i(128, 64),
	"reef_back": Vector2i(416, 28),
	"reef_front": Vector2i(416, 18),
	"sand_strip": Vector2i(64, 8),
}

## The art.json parts (x, y, w, h): the body is the left 75 %, the tail the rest.
const PARTS := {
	"fish_mackerel": {"body": Rect2i(0, 0, 18, 8), "tail": Rect2i(18, 0, 6, 8)},
	"fish_mahi": {"body": Rect2i(0, 0, 30, 16), "tail": Rect2i(30, 0, 10, 16)},
	"fish_tuna": {"body": Rect2i(0, 0, 33, 16), "tail": Rect2i(33, 0, 11, 16)},
	"fish_marlin": {"body": Rect2i(0, 0, 48, 22), "tail": Rect2i(48, 0, 16, 22)},
}

## Mounting points measured on these drawings (art pixels, origin top-left), for the view's rig:
## the boat's aft deck (where the bike's base sits) and rod-holder, the bike's bottom bracket
## (the crank hub), saddle top and handlebar, the angler's hip and hands, and each fish's mouth.
const MOUNTS := {
	"boat": {"deck": Vector2i(10, 18), "deck_end": Vector2i(40, 18), "waterline": Vector2i(0, 27)},
	"rig_bike": {"crank": Vector2i(9, 11), "saddle": Vector2i(8, 3), "bar": Vector2i(20, 3)},
	"rig_angler": {"hip": Vector2i(5, 10), "hands": Vector2i(12, 8)},
	"rig_crank": {"hub": Vector2i(5, 5)},
	"rig_reel": {"hub": Vector2i(5, 5), "sprocket": Vector2i(7, 7)},
	"fish_mackerel": {"mouth": Vector2i(1, 4)},
	"fish_mahi": {"mouth": Vector2i(1, 8)},
	"fish_tuna": {"mouth": Vector2i(1, 8)},
	"fish_marlin": {"mouth": Vector2i(0, 11)},
}


## True when this class draws `id`.
static func has(id: String) -> bool:
	return SIZES.has(id)


## The ids this class draws, in art.json order.
static func ids() -> PackedStringArray:
	return PackedStringArray(SIZES.keys())


## The sprite `id` at its art.json size (RGBA8), or null with push_error for an unknown id
## (picker_card included: it keeps its G0 placeholder PNG).
static func image(id: String) -> Image:
	if not SIZES.has(id):
		push_error("FishingFallbackSprites: no fallback drawing for %s" % id)
		return null
	var size: Vector2i = SIZES[id]
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match id:
		"boat":
			_boat(img)
		"rig_bike":
			_rig_bike(img)
		"rig_angler":
			_rig_angler(img)
		"rig_crank":
			_rig_crank(img)
		"rig_reel":
			_rig_reel(img)
		"fish_mackerel":
			_fish_mackerel(img)
		"fish_mahi":
			_fish_mahi(img)
		"fish_tuna":
			_fish_tuna(img)
		"fish_marlin":
			_fish_marlin(img)
		"gull_up":
			_gull(img, true)
		"gull_down":
			_gull(img, false)
		"bait_ball":
			_bait_ball(img)
		"sonar_mark":
			_sonar_mark(img)
		"current_seam":
			_foam(img, 11, 0.55)
		"splash":
			_splash(img)
		"spray":
			_spray(img)
		"catch_flash":
			_catch_flash(img)
		"trophy_badge":
			_trophy_badge(img)
		"clouds":
			_clouds(img)
		"islands_far":
			_islands_far(img)
		"island_palm":
			_island_palm(img)
		"sun":
			_sun(img)
		"wake":
			_foam(img, 23, 0.45)
		"surface_strip":
			_surface_strip(img)
		"light_rays":
			_light_rays(img)
		"reef_back":
			_reef_back(img)
		"reef_front":
			_reef_front(img)
		"sand_strip":
			_sand_strip(img)
	return img


## Part `part` of sprite `id` (the art.json rect), or null with push_error when it has none.
static func part(id: String, part_name: String) -> Image:
	if not PARTS.has(id) or not (PARTS[id] as Dictionary).has(part_name):
		push_error("FishingFallbackSprites: %s has no part %s" % [id, part_name])
		return null
	return image(id).get_region(PARTS[id][part_name])


# ---------------------------------------------------------------- drawing primitives


static func col(i: int) -> Color:
	return Color(PALETTE[i])


## A deterministic value in [0, 1) from two integers.
static func noise(a: int, b: int) -> float:
	return float(FishingRandom.mix32(a * 7919 + b * 104729 + 17) & 0xFFFF) / 65536.0


static func _px(img: Image, x: int, y: int, c: int) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col(c))


static func _opaque(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false
	return img.get_pixel(x, y).a > 0.5


## Sets (x, y) only where the sprite already has a pixel (details inside a silhouette).
static func _paint(img: Image, x: int, y: int, c: int) -> void:
	if _opaque(img, x, y):
		img.set_pixel(x, y, col(c))


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


## Recolours every opaque pixel inside the rect.
static func _paint_rect(img: Image, x: int, y: int, w: int, h: int, c: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_paint(img, xx, yy, c)


## A filled ellipse; (cx, cy) in pixel-edge coordinates (pixel x covers x..x+1).
static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: int) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


## A filled polygon: every pixel whose centre lies inside.
static func _poly(img: Image, pts: PackedVector2Array, c: int) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	for y in range(maxi(0, floori(r.position.y)), mini(img.get_height(), ceili(r.end.y) + 1)):
		for x in range(maxi(0, floori(r.position.x)), mini(img.get_width(), ceili(r.end.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_px(img, x, y, c)


## A 1 px line between pixel coordinates (Bresenham).
static func _line(img: Image, a: Vector2i, b: Vector2i, c: int) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		_px(img, p.x, p.y, c)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy


## The dark navy outline: every transparent pixel with an opaque 4-neighbour turns navy.
static func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if _opaque(src, x, y):
				continue
			if (
				_opaque(src, x - 1, y)
				or _opaque(src, x + 1, y)
				or _opaque(src, x, y - 1)
				or _opaque(src, x, y + 1)
			):
				img.set_pixel(x, y, col(NAVY))


## Recolours the opaque pixels below row `y0` (the belly of a fish) inside columns x0..x1.
static func _belly(img: Image, x0: int, x1: int, y0: int, c: int) -> void:
	_paint_rect(img, x0, y0, x1 - x0 + 1, img.get_height() - y0, c)


## A forked tail from the peduncle at x0 to the right edge, between rows top and bottom.
static func _tail(img: Image, x0: float, cy: float, top: float, bottom: float, c: int) -> void:
	var w := float(img.get_width())
	var notch := x0 + (w - x0) * 0.55
	_poly(
		img,
		PackedVector2Array(
			[
				Vector2(x0, cy - 1.5),
				Vector2(w, top),
				Vector2(w, top + 2.0),
				Vector2(notch, cy),
				Vector2(w, bottom - 2.0),
				Vector2(w, bottom),
				Vector2(x0, cy + 1.5),
			]
		),
		c
	)


# ---------------------------------------------------------------- the boat and the rig


static func _boat(img: Image) -> void:
	# Hull: deck at y 19, bow rising to the right, flat transom at the left.
	var hull := PackedVector2Array(
		[
			Vector2(6, 18),
			Vector2(64, 18),
			Vector2(79, 13),
			Vector2(76, 19),
			Vector2(68, 26),
			Vector2(60, 29),
			Vector2(10, 29),
			Vector2(6, 26),
		]
	)
	_poly(img, hull, WHITE)
	_paint_rect(img, 0, 24, 80, 3, OFF_WHITE)
	_paint_rect(img, 0, 27, 80, 3, BGREY)
	# The red trim stripe under the deck edge (key ramp), with its dark shade.
	_paint_rect(img, 0, 20, 80, 2, KEY)
	_paint_rect(img, 0, 22, 80, 1, KEY_DARK)
	# Outboard motor at the left stern.
	_rect(img, 1, 11, 6, 6, GREY)
	_rect(img, 2, 12, 4, 1, LGREY)
	_rect(img, 3, 17, 2, 10, DGREY)
	_rect(img, 2, 27, 4, 1, DGREY)
	# Canopy on two posts over the middle; the aft deck (x 8-28) stays empty for the bike.
	_rect(img, 32, 7, 1, 11, GREY)
	_rect(img, 54, 7, 1, 11, GREY)
	_rect(img, 29, 4, 30, 2, KEY)
	_rect(img, 29, 6, 30, 1, KEY_DARK)
	# Console and windscreen under the canopy, a bow rail.
	_rect(img, 46, 12, 8, 6, LGREY)
	_rect(img, 47, 12, 6, 2, SKY)
	_line(img, Vector2i(64, 16), Vector2i(74, 13), LGREY)
	_outline(img)


static func _rig_bike(img: Image) -> void:
	# Base plate bolted to the deck, with two feet.
	_rect(img, 3, 13, 18, 2, DGREY)
	_rect(img, 4, 12, 2, 1, GREY)
	_rect(img, 18, 12, 2, 1, GREY)
	# Seat post and saddle (rear, left), main tube, flywheel stand and handlebar (front, right).
	_line(img, Vector2i(7, 12), Vector2i(8, 5), LGREY)
	_line(img, Vector2i(8, 12), Vector2i(9, 5), LGREY)
	_rect(img, 5, 3, 6, 2, DGREY)
	_line(img, Vector2i(9, 9), Vector2i(15, 9), LGREY)
	_ellipse(img, 16.5, 10.0, 3.5, 3.5, GREY)
	_ellipse(img, 16.5, 10.0, 1.5, 1.5, LGREY)
	_line(img, Vector2i(17, 7), Vector2i(19, 3), LGREY)
	_rect(img, 18, 2, 4, 1, DGREY)
	_outline(img)


static func _rig_angler(img: Image) -> void:
	# Shirt (key ramp) with its shaded back, arms forward to the rod handle.
	_rect(img, 3, 6, 5, 5, KEY)
	_rect(img, 3, 6, 1, 5, KEY_DARK)
	_rect(img, 7, 7, 4, 1, SKIN)
	_rect(img, 11, 7, 2, 2, TAN)
	# Head, eye, and the cap with its brim to the right (key ramp).
	_ellipse(img, 6.0, 5.0, 2.0, 2.0, SKIN)
	_px(img, 7, 4, NAVY)
	_rect(img, 4, 1, 4, 2, KEY)
	_rect(img, 8, 2, 2, 1, KEY_DARK)
	_outline(img)


static func _rig_crank(img: Image) -> void:
	_ellipse(img, 5.0, 5.0, 2.6, 2.6, GREY)
	_line(img, Vector2i(5, 2), Vector2i(5, 8), DGREY)
	_rect(img, 3, 1, 4, 1, DGREY)
	_rect(img, 3, 8, 4, 1, DGREY)
	_px(img, 5, 5, LGREY)
	_outline(img)


static func _rig_reel(img: Image) -> void:
	_ellipse(img, 5.0, 5.0, 3.6, 3.6, GOLD)
	_line(img, Vector2i(5, 2), Vector2i(5, 8), GREY)
	_line(img, Vector2i(2, 5), Vector2i(8, 5), GREY)
	_px(img, 5, 5, DBROWN)
	_px(img, 7, 7, DGREY)
	_px(img, 8, 8, DGREY)
	_outline(img)


# ---------------------------------------------------------------- fish (facing left)


static func _fish_mackerel(img: Image) -> void:
	_ellipse(img, 10.5, 4.0, 9.0, 2.6, TEAL)
	_rect(img, 17, 3, 3, 2, TEAL)
	_belly(img, 0, 19, 4, LGREY)
	for x: int in [6, 9, 12, 15]:
		_paint(img, x, 2, BLUE)
		_paint(img, x + 1, 3, BLUE)
	_tail(img, 18.0, 4.0, 0.6, 7.4, TEAL)
	_px(img, 4, 3, NAVY)
	_outline(img)


static func _fish_mahi(img: Image) -> void:
	# Blunt high forehead at the left, long dorsal fin along the back.
	var body := PackedVector2Array(
		[
			Vector2(2, 7),
			Vector2(3, 4),
			Vector2(7, 2.5),
			Vector2(18, 3.5),
			Vector2(28, 6),
			Vector2(31, 8),
			Vector2(28, 10),
			Vector2(18, 12.5),
			Vector2(7, 13),
			Vector2(2, 11),
		]
	)
	_poly(img, body, GREEN)
	_poly(
		img,
		PackedVector2Array([Vector2(6, 2.5), Vector2(8, 1), Vector2(27, 4.5), Vector2(26, 6)]),
		LIME
	)
	_belly(img, 0, 31, 8, YELLOW)
	for i in 7:
		_paint(img, 8 + i * 3, 6 + (i % 2) * 2, LIGHT)
	_tail(img, 29.0, 8.0, 1.0, 15.0, GOLD)
	_px(img, 5, 6, NAVY)
	_outline(img)


static func _fish_tuna(img: Image) -> void:
	_ellipse(img, 17.5, 8.0, 15.5, 5.0, NAVY2)
	_rect(img, 31, 7, 3, 2, NAVY2)
	_belly(img, 0, 33, 8, LGREY)
	_paint_rect(img, 0, 8, 34, 1, BGREY)
	# Dorsal and anal fins, and the row of yellow finlets near the tail.
	_poly(img, PackedVector2Array([Vector2(16, 3.5), Vector2(19, 0.5), Vector2(22, 3.5)]), YELLOW)
	_poly(img, PackedVector2Array([Vector2(17, 12.5), Vector2(19, 15), Vector2(21, 12.5)]), YELLOW)
	for x: int in [24, 26, 28, 30]:
		_px(img, x, 3, YELLOW)
		_px(img, x, 12, YELLOW)
	_tail(img, 32.0, 8.0, 0.5, 15.5, NAVY2)
	_px(img, 5, 7, NAVY)
	_outline(img)


static func _fish_marlin(img: Image) -> void:
	# Bill at the left, sail-like dorsal fin, cobalt back, silver belly with faint stripes.
	_rect(img, 0, 11, 11, 1, GREY)
	_ellipse(img, 28.5, 12.0, 18.0, 5.0, BLUE)
	_rect(img, 45, 11, 4, 2, BLUE)
	_belly(img, 0, 48, 12, LGREY)
	_paint_rect(img, 0, 9, 48, 1, MID)
	for x: int in [20, 24, 28, 32, 36]:
		_paint(img, x, 12, SKY)
		_paint(img, x, 13, SKY)
	var sail := PackedVector2Array(
		[Vector2(14, 8), Vector2(17, 1), Vector2(26, 1.5), Vector2(36, 5), Vector2(41, 8)]
	)
	_poly(img, sail, BLUE)
	_poly(img, PackedVector2Array([Vector2(18, 7), Vector2(19, 3), Vector2(30, 6)]), MID)
	_poly(img, PackedVector2Array([Vector2(22, 15), Vector2(26, 20), Vector2(28, 15)]), BLUE)
	_tail(img, 47.0, 12.0, 0.5, 21.5, BLUE)
	_px(img, 13, 10, NAVY)
	_outline(img)


# ---------------------------------------------------------------- spots and effects


static func _gull(img: Image, up: bool) -> void:
	_ellipse(img, 5.0, 5.0, 3.0, 1.3, WHITE)
	_px(img, 8, 4, WHITE)
	_px(img, 9, 4, YELLOW)
	if up:
		_poly(img, PackedVector2Array([Vector2(3, 4.5), Vector2(1, 0.5), Vector2(6, 4.5)]), WHITE)
		_px(img, 1, 1, GREY)
	else:
		_poly(img, PackedVector2Array([Vector2(3, 5), Vector2(2, 8), Vector2(6, 5)]), WHITE)
		_px(img, 2, 7, GREY)
	_px(img, 7, 4, NAVY)
	_px(img, 1, 5, LGREY)


static func _bait_ball(img: Image) -> void:
	var colors: Array[int] = [LGREY, WHITE, BGREY]
	for y in img.get_height():
		for x in range(0, img.get_width() - 1, 2):
			var dx := (x + 1.0 - 16.0) / 15.0
			var dy := (y + 0.5 - 6.0) / 5.5
			if dx * dx + dy * dy > 1.0:
				continue
			var n := noise(x + (y % 2), y)
			if n < 0.55:
				var c: int = colors[int(n * 10.0) % 3]
				var ox := y % 2
				_px(img, x + ox, y, c)
				if n < 0.3:
					_px(img, x + ox + 1, y, MID)


static func _sonar_mark(img: Image) -> void:
	for x in 8:
		var y := roundi(0.3 * (x - 3.5) * (x - 3.5) - 0.2)
		_px(img, x, clampi(y, 0, 4), LIME)
		_px(img, x, clampi(y + 1, 0, 4), GREEN)


## A foam streak (current seam, wake): broken white rows around the middle.
static func _foam(img: Image, salt: int, density: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		var edge := absf(y + 0.5 - h * 0.5) / (h * 0.5)
		for x in w:
			var n := noise(x + salt * 1000, y)
			if n < density * (1.0 - edge * 0.6):
				_px(
					img,
					x,
					y,
					WHITE if n < density * 0.45 else (OFF_WHITE if n < density * 0.75 else PALE)
				)


static func _splash(img: Image) -> void:
	_poly(
		img,
		PackedVector2Array(
			[
				Vector2(3, 12),
				Vector2(5, 6),
				Vector2(7, 9),
				Vector2(9, 3),
				Vector2(11, 8),
				Vector2(13, 4),
				Vector2(15, 9),
				Vector2(17, 6),
				Vector2(18, 12),
			]
		),
		SKY
	)
	_paint_rect(img, 0, 0, 20, 7, WHITE)
	_paint_rect(img, 0, 10, 20, 2, WHITE)
	for p: Vector2i in [
		Vector2i(3, 2), Vector2i(7, 1), Vector2i(12, 0), Vector2i(16, 2), Vector2i(1, 5)
	]:
		_px(img, p.x, p.y, WHITE)


static func _spray(img: Image) -> void:
	_ellipse(img, 16.0, 21.5, 10.0, 2.5, WHITE)
	_ellipse(img, 16.0, 22.0, 6.0, 1.5, PALE)
	for k in 9:
		var ang := deg_to_rad(-150.0 + k * 15.0)
		var dir := Vector2(cos(ang), sin(ang))
		for s in 6:
			var r := 4.0 + s * 3.4 + noise(k, s) * 2.0
			var p := Vector2(16.0, 21.0) + dir * r
			var c := WHITE if s < 3 else (PALE if s < 5 else SKY)
			_px(img, floori(p.x), floori(p.y), c)
			if s < 2:
				_px(img, floori(p.x) + 1, floori(p.y), c)


static func _catch_flash(img: Image) -> void:
	_star(img, Vector2i(12, 12), 10, 3)
	_star(img, Vector2i(4, 5), 3, 1)
	_star(img, Vector2i(19, 18), 3, 1)
	_star(img, Vector2i(20, 4), 2, 1)


## A four-pointed glint: arms of length `arm`, a diamond core of radius `core`.
static func _star(img: Image, c: Vector2i, arm: int, core: int) -> void:
	for d in range(-arm, arm + 1):
		var shade := YELLOW if absi(d) * 2 <= arm else GOLD
		_px(img, c.x + d, c.y, shade)
		_px(img, c.x, c.y + d, shade)
	for y in range(-core, core + 1):
		for x in range(-core, core + 1):
			if absi(x) + absi(y) <= core:
				_px(img, c.x + x, c.y + y, YELLOW)
	_px(img, c.x, c.y, WHITE)


static func _trophy_badge(img: Image) -> void:
	_ellipse(img, 8.0, 8.5, 6.5, 6.5, BROWN)
	_ellipse(img, 8.0, 8.5, 5.5, 5.5, GOLD)
	# A leaping fish across the plaque, head up and to the left.
	_poly(
		img,
		PackedVector2Array(
			[
				Vector2(4, 6),
				Vector2(6, 4),
				Vector2(10, 7),
				Vector2(12, 11),
				Vector2(10, 10),
				Vector2(6, 8)
			]
		),
		YELLOW
	)
	_poly(img, PackedVector2Array([Vector2(11, 10), Vector2(13, 9), Vector2(13, 13)]), YELLOW)
	_px(img, 5, 5, NAVY)
	_px(img, 6, 6, WHITE)
	_outline(img)


# ---------------------------------------------------------------- backdrop strips


static func _clouds(img: Image) -> void:
	var h := img.get_height()
	for i in 6:
		var cx := 26.0 + i * 52.0 + noise(i, 1) * 10.0
		var s := 0.7 + noise(i, 2) * 0.5
		var base := float(h) - 2.0
		_ellipse(img, cx, base - 5.0 * s, 12.0 * s, 5.0 * s, WHITE)
		_ellipse(img, cx - 9.0 * s, base - 3.5 * s, 7.0 * s, 3.5 * s, WHITE)
		_ellipse(img, cx + 9.0 * s, base - 3.0 * s, 8.0 * s, 3.0 * s, WHITE)
		_ellipse(img, cx + 1.0 * s, base - 9.0 * s, 7.0 * s, 4.5 * s, WHITE)
	# Soft grey undersides and a pale band between them and the white tops.
	for y in h:
		for x in img.get_width():
			if not _opaque(img, x, y):
				continue
			if not _opaque(img, x, y + 1):
				img.set_pixel(x, y, col(LGREY))
			elif not _opaque(img, x, y + 2):
				img.set_pixel(x, y, col(PALE))


## Column heights of a row of smooth bumps: [[centre, half width, height], ...].
static func _bumps(x: float, bumps: Array) -> float:
	var h := 0.0
	for b: Array in bumps:
		var d := (x - float(b[0])) / float(b[1])
		if absf(d) < 1.0:
			h = maxf(h, float(b[2]) * (1.0 - d * d))
	return h


static func _islands_far(img: Image) -> void:
	var h := img.get_height()
	var bumps := [[50, 34, 10], [72, 18, 7], [150, 22, 6], [214, 30, 8], [234, 14, 5]]
	for x in img.get_width():
		var top := roundi(_bumps(x + 0.5, bumps))
		for y in range(h - top, h):
			_px(img, x, y, BGREY if y > h - top else LGREY)


static func _island_palm(img: Image) -> void:
	_ellipse(img, 40.0, 23.0, 26.0, 3.5, SAND)
	_ellipse(img, 40.0, 22.5, 22.0, 2.0, SAND_PALE)
	_ellipse(img, 26.0, 20.5, 6.0, 2.5, GREEN)
	_ellipse(img, 55.0, 20.5, 7.0, 2.5, DGREEN)
	_ellipse(img, 45.0, 21.0, 4.0, 2.0, GREEN)
	for t: Array in [[Vector2i(33, 21), Vector2i(37, 8)], [Vector2i(47, 21), Vector2i(51, 10)]]:
		var a: Vector2i = t[0]
		var b: Vector2i = t[1]
		_line(img, a, b, BROWN)
		_line(img, a + Vector2i(1, 0), b + Vector2i(1, 0), DBROWN)
		for f: Vector2i in [
			Vector2i(-7, 2), Vector2i(-5, -2), Vector2i(6, -2), Vector2i(8, 2), Vector2i(0, -4)
		]:
			_line(img, b, b + f, GREEN)
			_line(img, b + Vector2i(0, 1), b + f + Vector2i(0, 1), DGREEN)


static func _sun(img: Image) -> void:
	_ellipse(img, 6.0, 6.0, 5.5, 5.5, SAND_PALE)
	_ellipse(img, 6.0, 6.0, 4.5, 4.5, YELLOW)
	_px(img, 4, 4, WHITE)
	_px(img, 5, 4, WHITE)
	_px(img, 4, 5, WHITE)


static func _surface_strip(img: Image) -> void:
	var h := img.get_height()
	for x in img.get_width():
		var crest := roundi(1.5 + 1.2 * sin(TAU * x / 16.0))
		for y in range(crest, h):
			var c := LIGHT if y < h - 1 else MID
			if y == crest:
				c = WHITE if (x % 16) < 9 else PALE
			_px(img, x, y, c)


static func _light_rays(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bayer: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	for y in h:
		var fade := 1.0 - float(y) / float(h)
		for x in w:
			var u := fposmod(x + y * 0.5, 32.0)
			var width := 9.0 * (0.5 + 0.5 * fade)
			if u >= width:
				continue
			var thr := (float(bayer[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0
			if thr < fade * 0.55:
				_px(img, x, y, PALE if fade > 0.75 else SKY)


static func _reef_back(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var bumps: Array = []
	for i in 12:
		bumps.append(
			[18 + i * 32 + noise(i, 5) * 10.0, 14 + noise(i, 6) * 10.0, 10 + noise(i, 7) * 16.0]
		)
	for x in w:
		var top := _bumps(x + 0.5, bumps)
		# Flat at the right end (brief 3.4): taper to 2 px over the last 40 px.
		top = minf(top, lerpf(2.0, float(h), clampf((396.0 - x) / 40.0, 0.0, 1.0)))
		var t := maxi(2, roundi(top))
		for y in range(h - t, h):
			_px(img, x, y, DGREEN if y == h - t else DEEP)


static func _reef_front(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var flat_x := 380
	# Rocks.
	for i in 14:
		var cx := 12.0 + i * 27.0 + noise(i, 11) * 8.0
		if cx > flat_x - 6:
			continue
		var rx := 6.0 + noise(i, 12) * 6.0
		var ry := 3.0 + noise(i, 13) * 4.0
		_ellipse(img, cx, float(h), rx, ry, GREY)
		_ellipse(img, cx - 1.0, float(h) - 1.0, rx * 0.6, ry * 0.5, LGREY)
	# Pink branching coral, orange fans, green sea grass.
	for i in 26:
		var x := 6 + i * 14 + roundi(noise(i, 21) * 6.0)
		if x > flat_x:
			continue
		match i % 3:
			0:
				var top := h - 8 - roundi(noise(i, 22) * 7.0)
				_line(img, Vector2i(x, h - 1), Vector2i(x, top), PINK)
				_line(img, Vector2i(x, top + 3), Vector2i(x - 2, top + 1), PINK)
				_line(img, Vector2i(x, top + 5), Vector2i(x + 2, top + 2), PINK)
			1:
				_ellipse(img, x + 0.5, float(h) - 1.0, 4.0, 5.0 + noise(i, 23) * 3.0, ORANGE)
				_ellipse(img, x + 0.5, float(h) - 1.0, 2.0, 2.5, CORAL)
			_:
				for b in 3:
					var bx := x + b * 2
					var top2 := h - 6 - roundi(noise(i, 24 + b) * 8.0)
					for y in range(top2, h):
						_px(img, bx + int((y + b) % 4 == 0), y, GREEN if b != 1 else LIME)
	# The flat cap at the right end: low pebbles only.
	for x in range(flat_x, w):
		if noise(x, 31) < 0.35:
			_px(img, x, h - 1, GREY)
	_rect(img, 0, h - 1, flat_x, 1, DGREY)


static func _sand_strip(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	_rect(img, 0, 0, w, h, SAND_PALE)
	for x in w:
		var y := roundi(3.5 + 1.5 * sin(TAU * x / 16.0))
		_px(img, x, y, SAND)
		_px(img, x, (y + 4) % h, SAND)
	for p: Vector2i in [Vector2i(9, 6), Vector2i(30, 2), Vector2i(47, 7), Vector2i(58, 1)]:
		_px(img, p.x, p.y, WHITE if p.x % 2 == 1 else PINK)
