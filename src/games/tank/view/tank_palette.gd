class_name TankPalette
extends RefCounted
## The art.json palette as named colours for everything the view draws in code (barrels, pistons,
## chains, frames, needles, the berm, tracers, glows). Greys, muted browns and olives are the
## world; the warm and cold lights are the only near-saturated colours (brief 3, "Light").

# --- Greys (steel, soot) ---------------------------------------------------------------------
const BLACK := Color("#07080a")
const SOOT := Color("#0f1012")
const COAL := Color("#17181b")
const IRON_DARK := Color("#202124")
const IRON := Color("#2a2b2e")
const STEEL_DARK := Color("#353739")
const STEEL := Color("#424446")
const STEEL_LIGHT := Color("#525456")
const STEEL_PALE := Color("#666869")
const STEEL_BRIGHT := Color("#808182")
const SILVER := Color("#a3a4a4")
const PEARL := Color("#cfd0cf")

# --- Earth, rust ------------------------------------------------------------------------------
const MUD_DARK := Color("#241d17")
const MUD := Color("#33291f")
const MUD_LIGHT := Color("#443628")
const MUD_PALE := Color("#574634")
const CLAY := Color("#6b5842")
const OLIVE := Color("#3d3c33")
const SLATE := Color("#4b5561")
const RUST_DARK := Color("#3a2a24")
const RUST := Color("#5a3a2e")
const RUST_LIGHT := Color("#7d4f3a")

# --- Lights: warm (fire, lamps) and cold (arc, moonlit steel) ----------------------------------
const FIRE := Color("#e8743a")
const AMBER := Color("#ffb35c")
const GLOW_WARM := Color("#ffd99a")
const WHITE_WARM := Color("#fff3d6")
const COLD_DARK := Color("#2e3944")
const COLD := Color("#5d86a3")
const COLD_LIGHT := Color("#9fc4dd")
const WHITE_COLD := Color("#e6f3fb")

## The haze and smoke colour distant planes fade toward.
const HAZE := Color("#2b2f34")
## Powder smoke, exhaust and wreck smoke (lit from within by nearby glows, never pure black).
const SMOKE := Color("#3a3d41")
const SMOKE_LIGHT := Color("#666869")
const STEAM := Color("#cfd0cf")
const BRASS := Color("#b08a3c")

## Colour per shell type (tracer core): see TankIds.SHELL_*.
const TRACER := {
	TankIds.SHELL_LIGHT: Color("#ffd99a"),
	TankIds.SHELL_HEAVY: Color("#ffb35c"),
	TankIds.SHELL_OVER: Color("#e6f3fb"),
	TankIds.SHELL_BOW: Color("#ffd99a"),
	TankIds.SHELL_ENEMY: Color("#e8743a"),
	TankIds.SHELL_BOSS_MAIN: Color("#e8743a"),
}


## `c` with its alpha replaced.
static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## `c` darkened toward black by `k` (0 keeps it, 1 is black), alpha kept.
static func darkened(c: Color, k: float) -> Color:
	var f := 1.0 - clampf(k, 0.0, 1.0)
	return Color(c.r * f, c.g * f, c.b * f, c.a)
