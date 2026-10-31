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


## Pole height (art px) for a slot, staggered so pennants at one spot stay readable.
static func pole_height(slot_index: int) -> float:
	return 16.0 + 5.0 * float(posmod(slot_index, 4)) + (2.0 if posmod(slot_index, 8) >= 4 else 0.0)


## The pennant marker as filled polygons in paint order, relative to the pole foot (y up
## is negative). `look`: Wl.slot_look() keys (color, shape, pattern, hollow). `opts`:
## {style: "" or a WorkoutProgress pennant id, bot, local, in_band, rescue, afk}.
static func pennant_shapes(
	look: Dictionary, slot_index: int, opts: Dictionary = {}
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var h := pole_height(slot_index)
	var color: Color = look.get("color", WHITE)
	if bool(opts.get("afk", false)):
		color = GREY
	elif bool(opts.get("rescue", false)):
		color = color.lerp(GREY, 0.55)
	var top := -h
	var flag: PackedVector2Array
	var style := str(opts.get("style", ""))
	if bool(opts.get("rescue", false)) or bool(opts.get("afk", false)):
		# Drooping flag hanging along the pole.
		flag = PackedVector2Array([Vector2(1, top), Vector2(5, top), Vector2(2, top + 12)])
	elif bool(opts.get("bot", false)):
		flag = PackedVector2Array(
			[Vector2(1, top), Vector2(11, top), Vector2(11, top + 7), Vector2(1, top + 7)]
		)
	elif style == "pennant_swallowtail":
		flag = PackedVector2Array(
			[
				Vector2(1, top),
				Vector2(14, top),
				Vector2(10, top + 4),
				Vector2(14, top + 8),
				Vector2(1, top + 8)
			]
		)
	else:
		flag = PackedVector2Array([Vector2(1, top), Vector2(14, top + 4), Vector2(1, top + 8)])
	if (
		bool(opts.get("in_band", false))
		and not bool(opts.get("rescue", false))
		and not bool(opts.get("afk", false))
	):
		out.append({"points": _grow(flag, 1.5), "color": GLOW})
	out.append(
		{
			"points":
			PackedVector2Array(
				[Vector2(0, top - 1), Vector2(1, top - 1), Vector2(1, 0), Vector2(0, 0)]
			),
			"color": POLE
		}
	)
	out.append({"points": _grow(flag, 0.8), "color": GOLD if style == "pennant_gold" else OUTLINE})
	out.append({"points": flag, "color": color})
	var dark := color.darkened(0.45)
	match str(look.get("pattern", "solid")):
		"dashed":
			out.append({"points": _rect(4, top + 2, 1, 4), "color": dark})
			out.append({"points": _rect(8, top + 3, 1, 2), "color": dark})
		"dotted":
			out.append({"points": _rect(3, top + 3, 2, 2), "color": dark})
			out.append({"points": _rect(7, top + 3, 2, 2), "color": dark})
		"double":
			var second := PackedVector2Array(
				[Vector2(1, top + 10), Vector2(10, top + 13), Vector2(1, top + 16)]
			)
			out.append({"points": _grow(second, 0.8), "color": OUTLINE})
			out.append({"points": second, "color": color})
	if style == "pennant_chevron":
		out.append(
			{
				"points":
				PackedVector2Array(
					[
						Vector2(3, top + 2),
						Vector2(6, top + 4),
						Vector2(3, top + 6),
						Vector2(4, top + 4)
					]
				),
				"color": WHITE
			}
		)
	elif style == "pennant_star":
		out.append({"points": _star(Vector2(5, top + 4), 2.6, 1.1), "color": WHITE})
	elif style == "pennant_bolt":
		out.append(
			{
				"points":
				PackedVector2Array(
					[
						Vector2(6, top + 1),
						Vector2(4, top + 4),
						Vector2(6, top + 4),
						Vector2(4, top + 7),
						Vector2(8, top + 3),
						Vector2(6, top + 3)
					]
				),
				"color": GOLD
			}
		)
	# Shape badge at the pole top.
	var c := Vector2(0.5, top - 4.0)
	var badge := shape_points(str(look.get("shape", "circle")), c, 3.0)
	out.append(
		{
			"points": shape_points(str(look.get("shape", "circle")), c, 4.2),
			"color": OUTLINE if not bool(look.get("hollow", false)) else color
		}
	)
	out.append(
		{"points": badge, "color": HOLLOW_FILL if bool(look.get("hollow", false)) else color}
	)
	if bool(opts.get("local", false)):
		out.append(
			{
				"points":
				PackedVector2Array(
					[Vector2(-2.5, top - 12), Vector2(3.5, top - 12), Vector2(0.5, top - 9)]
				),
				"color": WHITE
			}
		)
	return out


## A filled shape for the badge: circle, triangle, square or diamond.
static func shape_points(shape: String, c: Vector2, r: float) -> PackedVector2Array:
	match shape:
		"triangle":
			return PackedVector2Array(
				[c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)]
			)
		"square":
			var s := r * 0.85
			return PackedVector2Array(
				[c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(s, s), c + Vector2(-s, s)]
			)
		"diamond":
			return PackedVector2Array(
				[c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]
			)
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _grow(pts: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var out := PackedVector2Array()
	for p in pts:
		var d := p - c
		out.append(p + d.normalized() * by if d.length() > 0.0 else p)
	return out


static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
	)


static func _star(c: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		var r := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
