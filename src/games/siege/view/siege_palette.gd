class_name SiegePalette
extends RefCounted
## The brief's palette (docs/games/siege.md section 3), as constants. Player colors
## (Wl.slot_look) are the only saturated hues: nothing here is saturated, and enemies never
## use a player color.

const TERRACOTTA := Color("#B5553A")
const TERRACOTTA_LIGHT := Color("#CF7A55")
const MARBLE := Color("#E8E2D4")
const MARBLE_SHADE := Color("#CFC6B4")
const BRONZE_DARK := Color("#8A6A3B")
const BRONZE := Color("#B98C46")
const PATINA := Color("#5F8F7B")
const OLIVE_DARK := Color("#48552B")
const OLIVE := Color("#66733A")
const OCHRE := Color("#C7A15A")
const DUST := Color("#DCC79C")
const HAZE := Color("#9BB3C7")
const HAZE_LIGHT := Color("#B9CCDA")
const LAKE := Color("#7F9DB4")
const WOOD := Color("#7A5333")
const WOOD_DARK := Color("#563A24")
const ROCK := Color("#8E8983")
const IRON := Color("#4A4A4E")
const CLOTH := Color("#6E5E4C")
const LEATHER := Color("#857A6B")
const SHIELD := Color("#7A6650")
## Worker tunics (off-white) and skin: muted, never a player color.
const TUNIC := Color("#E8E2D4")
const SKIN := Color("#B08F70")
## Faint ring of a Caltrop zone and the dim (unlit) chain.
const ZONE_RING := Color("#4A4A4E")
const CHAIN_DIM := Color("#5C5A58")


## `c` darkened toward black by `amount` (0..1).
static func shade(c: Color, amount: float) -> Color:
	return Color(c.r * (1.0 - amount), c.g * (1.0 - amount), c.b * (1.0 - amount), c.a)
