class_name FishingPalette
extends RefCounted
## Turbo Reel's palette: one cool hue family (green-grey to teal-blue) in eight value steps from
## the foam white down to the abyss teal (LADDER: sky and water in one ramp, nothing darker than
## ABYSS), the seabed sage, the wood and hull slates, one warm accent (brass, flags) and three
## more desaturated player colours for the caps and pennants. The sprites (FishingArtGrids), the
## code-drawn scenery (FishingScenery) and the HUD panels use only these.

const FOAM := Color("#ebf2e7")
const SKY := Color("#cedfd2")
const HAZE := Color("#b6d7cf")
const SURFACE := Color("#91c2c2")
const UPPER := Color("#6fa3a6")
const MID := Color("#4b858f")
const DEEP := Color("#2c6778")
const ABYSS := Color("#1c4d65")
const SAGE := Color("#a7bfb3")
const WOOD := Color("#627179")
const SLATE := Color("#4e5c67")
## The single warm accent (brass, the first player's colour).
const ACCENT := Color("#c98a5e")
const PLAYER_SLATE := Color("#7f9cbf")
const PLAYER_MOSS := Color("#9fb07a")
const PLAYER_PLUM := Color("#a68aa8")

## Every palette colour (the art test checks the sprites against it).
const ALL: Array[Color] = [
	FOAM,
	SKY,
	HAZE,
	SURFACE,
	UPPER,
	MID,
	DEEP,
	ABYSS,
	SAGE,
	WOOD,
	SLATE,
	ACCENT,
	PLAYER_SLATE,
	PLAYER_MOSS,
	PLAYER_PLUM,
]
## Light to dark: the sky and the water in one ramp. Fish and hints shift along it with depth.
const LADDER: Array[Color] = [FOAM, SKY, HAZE, SURFACE, UPPER, MID, DEEP, ABYSS]
## The water from the surface down (one flat band each); the deep teal and the abyss are kept
## for the deep floor, its line and the subjects.
const SEA: Array[Color] = [HAZE, SURFACE, UPPER, MID]
## Player colours by slot: the cap and the pennant, nothing else.
const PLAYERS: Array[Color] = [ACCENT, PLAYER_SLATE, PLAYER_MOSS, PLAYER_PLUM]
## The line above the water (the rod's colour; under water FishingView.line_in_band()).
const LINE := SLATE
## HUD: panels, text, secondary text, bars on their track; colour only for alerts.
const HUD_PANEL := Color(0.10980392, 0.30196078, 0.39607843, 0.85)
const HUD_TEXT := FOAM
const HUD_DIM := HAZE
const HUD_BAR := SURFACE
const HUD_TRACK := DEEP
const HUD_ALERT := ACCENT


## The colour `steps` LADDER steps darker than `c` (lighter when negative; clamped at the ends;
## c itself when it is not in LADDER).
static func darker(c: Color, steps: int = 1) -> Color:
	var i := LADDER.find(c)
	if i < 0:
		return c
	return LADDER[clampi(i + steps, 0, LADDER.size() - 1)]


## The player colour of `slot`.
static func player(slot: int) -> Color:
	return PLAYERS[posmod(slot, PLAYERS.size())]


## A "#rrggbb" value as a colour, `fallback` when it is not one.
static func color_of(value: String, fallback: Color) -> Color:
	if value.begins_with("#") and Color.html_is_valid(value):
		return Color(value)
	return fallback
