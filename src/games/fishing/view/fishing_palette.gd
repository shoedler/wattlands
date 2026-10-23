class_name FishingPalette
extends RefCounted
## Big Game Fishing's palette (assets/fishing/art.json, at most 32 colours) and the code-drawn
## backdrops built from it (brief 3.3 "code draws"): sky and water as bands with a 4 x 4 ordered
## dither, the three day-cycle sky variants, and the dithered cover that keeps the HUD zone pure
## sky gradient. Images are built once per size and variant and cached; the view only draws them.

const NAVY := Color("#1a1f3a")
const NAVY_2 := Color("#23305c")
const DEEP := Color("#0f2a4a")
const SEA_3 := Color("#1f4e8c")
const SEA_2 := Color("#2a74b8")
const SEA_1 := Color("#3fa0d8")
const SKY_1 := Color("#8fd6f5")
const SKY_0 := Color("#c6ecfa")
const WHITE := Color("#f7f9fb")
const FOAM := Color("#e8f7fb")
const GREY_1 := Color("#c9d1d9")
const GREY_2 := Color("#b8c7d6")
const GREY_3 := Color("#8a96a3")
const GREY_4 := Color("#4b5563")
const SAND_1 := Color("#f4e4b0")
const SAND_2 := Color("#e3c27a")
const WOOD_1 := Color("#9a6236")
const WOOD_2 := Color("#5a3820")
const CORAL := Color("#f2665a")
const ORANGE := Color("#f28c28")
const YELLOW := Color("#f6d33c")
const GOLD := Color("#e8b730")
const LIME := Color("#9bd23c")
const GREEN := Color("#3fae4a")
const GREEN_D := Color("#23743a")
const TEAL := Color("#2bb3a3")
const VIOLET := Color("#9b6be0")
const PINK := Color("#ef6fa6")
const SKIN_1 := Color("#f1c29a")
const SKIN_2 := Color("#c98e63")
## The PaletteSwap key ramp (light, dark): boat trim and canopy, the angler's cap and shirt.
const KEY_LIGHT := Color("#e0413a")
const KEY_DARK := Color("#9e2228")

## Default line colour (cosmetic index 0) and the fishing line under strain.
const LINE := Color("#f7f9fb")

## Day cycle: three sky variants top to horizon (morning, midday, golden afternoon).
const SKY_VARIANTS: Array = [
	[Color("#3fa0d8"), Color("#8fd6f5"), Color("#c6ecfa"), Color("#f4e4b0")],
	[Color("#2a74b8"), Color("#3fa0d8"), Color("#8fd6f5"), Color("#c6ecfa")],
	[Color("#2a74b8"), Color("#8fd6f5"), Color("#f1c29a"), Color("#f28c28")],
]
## Water bands from the surface down.
const WATER: Array = [Color("#3fa0d8"), Color("#2a74b8"), Color("#1f4e8c"), Color("#0f2a4a")]
## The HUD zone cover's dithered left edge (art pixels).
const COVER_EDGE := 8

const BAYER4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _cache: Dictionary = {}


## Colour stops `stops` across `h` rows, ordered-dithered between neighbours; `w` columns.
static func gradient(w: int, h: int, stops: Array, alpha_edge: int = 0) -> Image:
	var img := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	var n := stops.size()
	for y in img.get_height():
		var f := float(y) / float(maxi(img.get_height() - 1, 1)) * float(n - 1)
		var i := mini(floori(f), n - 1)
		var frac := f - float(i)
		for x in img.get_width():
			var b := BAYER4[(y & 3) * 4 + (x & 3)]
			var c: Color = stops[mini(i + 1, n - 1)] if int(frac * 16.0) > b else stops[i]
			if x < alpha_edge and (x * 16) / maxi(alpha_edge, 1) <= b:
				c = Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)
	return img


## The sky of a lane `h` rows tall in day-cycle variant `variant` (0..2), full width.
static func sky_texture(h: int, variant: int) -> Texture2D:
	var key := "sky_%d_%d" % [h, variant]
	if not _cache.has(key):
		var stops: Array = SKY_VARIANTS[clampi(variant, 0, SKY_VARIANTS.size() - 1)]
		_cache[key] = ImageTexture.create_from_image(gradient(FishingConst.PIXEL_W, h, stops))
	return _cache[key]


## The HUD zone's sky cover: the same gradient from x HUD_X - COVER_EDGE to the right edge, its
## first COVER_EDGE columns dithered out, so clouds and islands fade before the zone.
static func sky_cover_texture(h: int, variant: int) -> Texture2D:
	var key := "cover_%d_%d" % [h, variant]
	if not _cache.has(key):
		var stops: Array = SKY_VARIANTS[clampi(variant, 0, SKY_VARIANTS.size() - 1)]
		var w := FishingConst.PIXEL_W - FishingConst.HUD_X + COVER_EDGE
		_cache[key] = ImageTexture.create_from_image(gradient(w, h, stops, COVER_EDGE))
	return _cache[key]


## Water and reef rows of a lane: `h` rows from the surface strip's bottom to the lane bottom.
static func water_texture(h: int) -> Texture2D:
	var key := "water_%d" % h
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(gradient(FishingConst.PIXEL_W, h, WATER))
	return _cache[key]


## The deck bar's planks (640 x 24).
static func deck_texture() -> Texture2D:
	var key := "deck"
	if not _cache.has(key):
		var img := Image.create_empty(
			FishingConst.PIXEL_W, FishingConst.DECK_H, false, Image.FORMAT_RGBA8
		)
		img.fill(WOOD_1)
		for x in FishingConst.PIXEL_W:
			img.set_pixel(x, 0, SAND_2)
			img.set_pixel(x, FishingConst.DECK_H - 1, NAVY)
			img.set_pixel(x, FishingConst.DECK_H - 2, WOOD_2)
			img.set_pixel(x, 11, WOOD_2)
		for x in range(37, FishingConst.PIXEL_W, 74):
			for y in range(1, 11):
				img.set_pixel(x, y, WOOD_2)
		for x in range(0, FishingConst.PIXEL_W, 74):
			for y in range(12, FishingConst.DECK_H - 2):
				img.set_pixel(x, y, WOOD_2)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## The day-cycle variant (0..2) at game time `t` of a trip `total_s` long: thirds of the trip.
static func day_variant(t: float, total_s: float) -> int:
	if total_s <= 0.0:
		return 1
	return clampi(floori(t / total_s * 3.0), 0, 2)


## Progress 0..1 of the 2 s dithered wipe into the variant that started last (1 = done).
static func wipe_progress(t: float, total_s: float, wipe_s: float = 2.0) -> float:
	var v := day_variant(t, total_s)
	if v == 0 or total_s <= 0.0:
		return 1.0
	var since := t - float(v) * total_s / 3.0
	return clampf(since / maxf(wipe_s, 0.001), 0.0, 1.0)


## Sun position fraction (0 rising left .. 1 setting right) at game time t.
static func sun_fraction(t: float, total_s: float) -> float:
	return clampf(t / total_s, 0.0, 1.0) if total_s > 0.0 else 0.5


## A "#rrggbb" cosmetic value as a colour, `fallback` when it is not one.
static func color_of(value: String, fallback: Color) -> Color:
	if value.begins_with("#") and Color.html_is_valid(value):
		return Color(value)
	return fallback


## The key ramp as PaletteSwap takes it.
static func keys() -> PackedColorArray:
	return PackedColorArray([KEY_LIGHT, KEY_DARK])


static func clear_cache() -> void:
	_cache.clear()
