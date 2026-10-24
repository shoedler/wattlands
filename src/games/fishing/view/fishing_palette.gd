class_name FishingPalette
extends RefCounted
## Turbo Reel's palette: 32 muted colours in a few cohesive ramps (sky and haze, sea by depth,
## sand, wood, cream, brass, the key reds the slot colour replaces, skin, steel and three fish
## accents). The hand-authored sprites (FishingArtGrids) use only these; the code-drawn scenery
## (FishingScenery) draws flat bands from the same ramps, so every scene reads as one style.

const CLOUD := Color("#eef2ea")
const SKY_2 := Color("#e0eae1")
const SKY_1 := Color("#d0dfd8")
const SKY_0 := Color("#c0d4cf")
const HAZE_1 := Color("#a7c5c2")
const HAZE_2 := Color("#8bb0b1")
const SEA_1 := Color("#72a4a8")
const SEA_2 := Color("#5b8f96")
const SEA_3 := Color("#4a7b84")
const SEA_4 := Color("#3b6773")
const SEA_5 := Color("#2f5562")
const SEA_6 := Color("#254452")
const SEA_7 := Color("#1b3441")
const VOID := Color("#121f29")
const SAND_1 := Color("#b2b796")
const SAND_2 := Color("#8da38e")
const WOOD_1 := Color("#a37f5a")
const WOOD_2 := Color("#735a42")
const WOOD_3 := Color("#4b3d31")
const CREAM := Color("#c9c3ae")
const BRASS_1 := Color("#e6c47a")
const BRASS_2 := Color("#c09a50")
const BRASS_3 := Color("#8a6c38")
## The key ramp (light, dark): the rider's jersey and the hull stripe; PaletteSwap paints the
## slot colour over them.
const KEY_LIGHT := Color("#c8573f")
const KEY_DARK := Color("#8f3b30")
const SKIN_1 := Color("#deb08f")
const SKIN_2 := Color("#ad7f62")
const STEEL := Color("#8e9a9a")
const NAVY := Color("#2f4a6a")
const BLUE := Color("#7e9fc4")
const GREEN := Color("#8ea85c")
const GLOW := Color("#d8f0c0")

## Every palette colour, in ramp order (the art test checks the sprites against it).
const ALL: Array[Color] = [
	CLOUD,
	SKY_2,
	SKY_1,
	SKY_0,
	HAZE_1,
	HAZE_2,
	SEA_1,
	SEA_2,
	SEA_3,
	SEA_4,
	SEA_5,
	SEA_6,
	SEA_7,
	VOID,
	SAND_1,
	SAND_2,
	WOOD_1,
	WOOD_2,
	WOOD_3,
	CREAM,
	BRASS_1,
	BRASS_2,
	BRASS_3,
	KEY_LIGHT,
	KEY_DARK,
	SKIN_1,
	SKIN_2,
	STEEL,
	NAVY,
	BLUE,
	GREEN,
	GLOW,
]
## Sky from the top of the view down to the horizon.
const SKY: Array[Color] = [SKY_0, SKY_1, SKY_2]
## Water from the surface down to the abyss.
const SEA: Array[Color] = [SEA_1, SEA_2, SEA_3, SEA_4, SEA_5, SEA_6, SEA_7, VOID]
## The fishing line above the water.
const LINE := CLOUD


## The water colour at `u` (0 at the surface, 1 at the deepest shown water), one flat ramp step.
static func sea_at(u: float) -> Color:
	var i := clampi(floori(clampf(u, 0.0, 1.0) * float(SEA.size())), 0, SEA.size() - 1)
	return SEA[i]


## The colour `steps` ramp steps darker than `c` along SEA (c itself when it is not in SEA).
static func darker(c: Color, steps: int = 1) -> Color:
	var i := SEA.find(c)
	if i < 0:
		return c
	return SEA[clampi(i + steps, 0, SEA.size() - 1)]


## The key ramp as PaletteSwap takes it.
static func keys() -> PackedColorArray:
	return PackedColorArray([KEY_LIGHT, KEY_DARK])


## A "#rrggbb" value as a colour, `fallback` when it is not one.
static func color_of(value: String, fallback: Color) -> Color:
	if value.begins_with("#") and Color.html_is_valid(value):
		return Color(value)
	return fallback
