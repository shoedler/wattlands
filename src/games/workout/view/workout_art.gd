class_name WorkoutArt
extends RefCounted
## Workout's drawn-in-code geometry on the 960 x 540 art grid: the whip pennant (slot color + shape +
## pattern, BRIEF 3.9) and the zone colors of the interval blocks. All sprites and world planes come
## from src/games/workout/art/bake.mjs through assets/workout/kit.json (WorkoutKit).
##
## Pennant geometry is a list of filled polygons in paint order ({points, color}), so the
## view draws it with draw_colored_polygon.

const W := 960
const H := 540

const POLE := Color("#2b2b30")
const OUTLINE := Color("#1e1e24")
const HOLLOW_FILL := Color("#f4f2ea")
const GLOW := Color("#fff3a8")
const GREY := Color("#8a8a8a")
const WHITE := Color("#ffffff")
const GOLD := Color("#e8b923")
const CLOTH_LIGHT := Color("#fff4d6")
const FLAG_LEN := 8
## A flag as columns: Vector3i(x, y from the flag's top, height).
const PLAIN_FLAG: Array[Vector3i] = [
	Vector3i(1, 0, 6),
	Vector3i(2, 0, 6),
	Vector3i(3, 0, 5),
	Vector3i(4, 1, 4),
	Vector3i(5, 1, 3),
	Vector3i(6, 2, 2),
	Vector3i(7, 2, 2),
	Vector3i(8, 2, 1),
]
const SWALLOWTAIL_FLAG: Array[Vector3i] = [
	Vector3i(1, 0, 6),
	Vector3i(2, 0, 6),
	Vector3i(3, 0, 6),
	Vector3i(4, 0, 6),
	Vector3i(5, 0, 6),
	Vector3i(6, 0, 2),
	Vector3i(6, 4, 2),
	Vector3i(7, 0, 2),
	Vector3i(7, 4, 2),
	Vector3i(8, 0, 1),
	Vector3i(8, 5, 1),
]
const BOT_FLAG: Array[Vector3i] = [
	Vector3i(1, 0, 6),
	Vector3i(2, 0, 6),
	Vector3i(3, 0, 6),
	Vector3i(4, 0, 6),
	Vector3i(5, 0, 6),
	Vector3i(6, 0, 6),
	Vector3i(7, 0, 6),
]
## A flag at rest: limp cloth down the pole, far longer than it is wide, with an uneven hem.
const HANGING_FLAG: Array[Vector3i] = [
	Vector3i(1, 0, 14),
	Vector3i(2, 0, 16),
	Vector3i(3, 0, 15),
	Vector3i(4, 1, 11),
]
const SECOND_FLAG: Array[Vector3i] = [
	Vector3i(1, 0, 4),
	Vector3i(2, 0, 4),
	Vector3i(3, 0, 3),
	Vector3i(4, 1, 2),
	Vector3i(5, 1, 1),
]

## Interval block colors by planned % FTP.
const ZONE_RECOVERY := Color("#8fa3b8")
const ZONE_ENDURANCE := Color("#4fa36a")
const ZONE_TEMPO := Color("#e3c04a")
const ZONE_THRESHOLD := Color("#e88a3a")
const ZONE_VO2 := Color("#d4553f")
const ZONE_SPRINT := Color("#b45fc4")
## A FREE phase longer than a sprint (an imported FreeRide): free riding, no target.
const ZONE_FREE := Color("#a3b0a0")
const ZONE_COURSE := Color("#4f8fc4")
const ZONE_COOLDOWN := Color("#6f8296")


static func zone_color(pct: float) -> Color:
	if pct < 56.0:
		return ZONE_RECOVERY
	if pct < 76.0:
		return ZONE_ENDURANCE
	if pct < 91.0:
		return ZONE_TEMPO
	if pct <= 105.0:
		return ZONE_THRESHOLD
	return ZONE_VO2


## Block color for a phase of the timeline.
static func phase_color(p: PlanPhase) -> Color:
	if p.kind == Wl.COOLDOWN:
		return ZONE_COOLDOWN
	if p.kind == Wl.FREE:
		return ZONE_SPRINT if WorkoutSession.is_sprint(p) else ZONE_FREE
	if p.mode == Wl.SIM:
		return ZONE_COURSE
	return zone_color(maxf(p.target_pct, p.ramp_to_pct if p.has_ramp() else 0.0))


# --- pennants ----------------------------------------------------------------------


## Pole height (art px) for a slot, staggered so pennants at one spot stay readable. The whip rises
## from the rear axle to about head height, so its small flag flies clear of the rider's own back.
static func pole_height(slot_index: int) -> int:
	return 28 + 4 * posmod(slot_index, 4) + (2 if posmod(slot_index, 8) >= 4 else 0)


## The pennant as whole-pixel rects in paint order, relative to the pole foot (up is negative, x runs
## along the flag), so the view draws it on the art grid. `look`: Wl.slot_look() keys (color, shape,
## pattern, hollow). `opts`: {style: "" or a WorkoutProgress pennant id, bot, in_band, rescue, afk}.
static func pennant_shapes(
	look: Dictionary, slot_index: int, opts: Dictionary = {}
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var h := pole_height(slot_index)
	var color: Color = look.get("color", WHITE)
	var hanging := bool(opts.get("rescue", false)) or bool(opts.get("afk", false))
	if bool(opts.get("afk", false)):
		color = GREY
	elif bool(opts.get("rescue", false)):
		color = color.lerp(GREY, 0.55)
	var style := str(opts.get("style", ""))
	var top := -h
	_add(out, 0, top - 1, 1, h + 1, POLE)
	var edge := GOLD if style == "pennant_gold" else OUTLINE
	if bool(opts.get("in_band", false)) and not hanging:
		_add(out, 1, top - 1, FLAG_LEN - 3, 1, GLOW)
	var dark := color.darkened(0.45)
	var pattern := str(look.get("pattern", "solid"))
	if hanging:
		_limp_cloth(out, top, color, edge)
		_limp_pattern(out, pattern, top, dark)
	else:
		_cloth(out, _flag_columns(bool(opts.get("bot", false)), style), top, color, edge)
		match pattern:
			"dashed":
				_add(out, 3, top + 2, 1, 2, dark)
				_add(out, 5, top + 2, 1, 2, dark)
			"dotted":
				_add(out, 2, top + 2, 1, 1, dark)
				_add(out, 4, top + 3, 1, 1, dark)
			"double":
				_cloth(out, SECOND_FLAG, top + 7, color, edge)
	_emblem(out, style, top)
	var fill := color.lerp(HOLLOW_FILL, 0.3) if hanging else HOLLOW_FILL
	_badge(
		out, str(look.get("shape", "circle")), top - 6, color, bool(look.get("hollow", false)), fill
	)
	return out


## The flag's columns: Vector3i(x, y from the flag's top, height).
static func _flag_columns(bot: bool, style: String) -> Array[Vector3i]:
	if bot:
		return BOT_FLAG
	return SWALLOWTAIL_FLAG if style == "pennant_swallowtail" else PLAIN_FLAG


## A cloth in three tones: lit from above with a warm top pixel, a cooler shadow on the underside, and
## a dark line under it only, so it holds against the fields without an outline around it.
static func _cloth(
	out: Array[Dictionary], cols: Array[Vector3i], top: int, color: Color, edge: Color
) -> void:
	var hi := color.lerp(CLOTH_LIGHT, 0.34)
	var shade := Color(color.r * 0.62, color.g * 0.64, color.b * 0.74)
	for c in cols:
		var y := top + c.y
		_add(out, c.x, y, 1, c.z, color)
		if c.z >= 2:
			_add(out, c.x, y, 1, 1, hi)
		if c.z >= 4:
			_add(out, c.x, y + c.z - 2, 1, 2, shade)
		elif c.z >= 3:
			_add(out, c.x, y + c.z - 1, 1, 1, shade)
		_add(out, c.x, y + c.z, 1, 1, edge)


## Limp cloth, folds running down it: a lit column, a fold, a body and a shaded outer edge, a warm pixel
## where it is tied to the pole and a dark hem under each column.
static func _limp_cloth(out: Array[Dictionary], top: int, color: Color, edge: Color) -> void:
	var hi := color.lerp(CLOTH_LIGHT, 0.34)
	var shade := Color(color.r * 0.62, color.g * 0.64, color.b * 0.74)
	var tones: Array[Color] = [color, shade, color, shade]
	for i in HANGING_FLAG.size():
		var c := HANGING_FLAG[i]
		var y := top + c.y
		_add(out, c.x, y, 1, c.z, tones[i])
		_add(out, c.x, y, 1, 1, hi)
		_add(out, c.x, y + c.z, 1, 1, edge)


## The slot's pattern across the limp cloth, always on the cloth.
static func _limp_pattern(out: Array[Dictionary], pattern: String, top: int, dark: Color) -> void:
	match pattern:
		"dashed":
			_add(out, 1, top + 4, 3, 1, dark)
			_add(out, 1, top + 9, 3, 1, dark)
		"dotted":
			_add(out, 2, top + 3, 1, 1, dark)
			_add(out, 3, top + 7, 1, 1, dark)
			_add(out, 2, top + 11, 1, 1, dark)
		"double":
			_add(out, 1, top + 6, 4, 1, dark)
			_add(out, 1, top + 8, 4, 1, dark)


## A progression emblem, a few pixels on the flag.
static func _emblem(out: Array[Dictionary], style: String, top: int) -> void:
	match style:
		"pennant_chevron":
			_add(out, 2, top + 1, 1, 1, WHITE)
			_add(out, 3, top + 2, 1, 1, WHITE)
			_add(out, 2, top + 3, 1, 1, WHITE)
		"pennant_star":
			_add(out, 3, top + 1, 1, 3, WHITE)
			_add(out, 2, top + 2, 3, 1, WHITE)
		"pennant_bolt":
			_add(out, 3, top + 1, 1, 2, GOLD)
			_add(out, 2, top + 2, 1, 2, GOLD)


## The slot's shape at the pole's top, 5 px across; a hollow slot is its ring around a pale centre.
static func _badge(
	out: Array[Dictionary], shape: String, y: int, color: Color, hollow: bool, fill: Color
) -> void:
	var rows := badge_rows(shape)
	for r in rows.size():
		var half := rows[r]
		_add(out, -half, y + r, half * 2 + 1, 1, color)
	if hollow:
		for r in range(1, rows.size() - 1):
			if rows[r] >= 2:
				_add(out, 1 - rows[r], y + r, rows[r] * 2 - 1, 1, fill)
	var last := rows.size() - 1
	_add(out, -rows[last], y + last + 1, rows[last] * 2 + 1, 1, OUTLINE)


## A shape's half-widths, row by row: circle, triangle, square or diamond.
static func badge_rows(shape: String) -> Array[int]:
	match shape:
		"triangle":
			return [0, 1, 1, 2, 2]
		"square":
			return [2, 2, 2, 2]
		"diamond":
			return [0, 1, 2, 1, 0]
	return [1, 2, 2, 2, 1]


static func _add(out: Array[Dictionary], x: int, y: int, w: int, h: int, color: Color) -> void:
	(
		out
		. append(
			{
				"points":
				PackedVector2Array(
					[
						Vector2(x, y),
						Vector2(x + w, y),
						Vector2(x + w, y + h),
						Vector2(x, y + h),
					]
				),
				"color": color,
			}
		)
	)
