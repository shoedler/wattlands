class_name TankObstacleArt
extends RefCounted
## Code-drawn obstacles for TankRowLayer (brief 3: wire on stakes; lines are code-drawn). The image
## model turned both into glyph-like strokes (bare stakes reading "| . / . |", hedgehogs reading
## "Xx"), so the view draws them as line work in palette colours, varied per obstacle by a hash of
## its id (no RNG, the same obstacle always looks the same):
## - tank traps: two Czech hedgehogs at different depths (the back one smaller, higher and darker),
##   each three thick beams of which one points at the viewer and is drawn short and dark, so the
##   shape is never a clean X; scale 80-120%, tilt up to 10 degrees, on a small mud heap, rust-streaked;
## - wire: four dark leaning stakes with a sagging concertina coil of overlapping loops between them.
## Every row carries "of": the sprite id it stands in for (tests, effects).

const BEAM_PX := 20.0


## Appends the rows of a tank-trap obstacle whose left edge is at screen x `x0`, `w` px wide.
static func traps(rows: Array[Dictionary], x0: float, w: float, id: int) -> void:
	var ground := float(TankConst.GROUND_Y)
	var span := maxf(w, 40.0)
	var h := _hash(id, 31)
	# The back hedgehog first (smaller, higher, darker), then the front one.
	var back_x := x0 + span * (0.62 + 0.1 * _u(h, 1))
	var front_x := x0 + span * (0.3 + 0.1 * _u(h, 2))
	_hedgehog(rows, Vector2(back_x, ground - 15.0), 0.95 + 0.15 * _u(h, 3), h >> 3, 0.55)
	_heap(rows, Vector2(back_x, ground - 3.0), 10.0 + 3.0 * _u(h, 6))
	_hedgehog(rows, Vector2(front_x, ground - 10.0), 1.15 + 0.25 * _u(h, 5), h >> 7, 1.0)
	_heap(rows, Vector2(front_x + 2.0, ground + 2.0), 14.0 + 4.0 * _u(h, 4))


## Appends the rows of a wire obstacle (stakes and a concertina coil).
static func wire(rows: Array[Dictionary], x0: float, w: float, id: int) -> void:
	var ground := float(TankConst.GROUND_Y) + 1.0
	var span := maxf(w, 48.0)
	var h := _hash(id, 57)
	var stakes: Array[Vector2] = []
	for i in 4:
		var x := x0 + 4.0 + (span - 8.0) * float(i) / 3.0 + (_u(h, 10 + i) - 0.5) * 6.0
		var ht := 13.0 + 5.0 * _u(h, 20 + i)
		var lean := (_u(h, 30 + i) - 0.5) * 6.0
		var top := Vector2(x + lean, ground - ht)
		stakes.append(top)
		rows.append(_line(Vector2(x, ground), top, 2.0, TankPalette.MUD_DARK, "prop_wire"))
		rows.append(
			_line(
				Vector2(x - 1.0, ground - 1.0),
				top + Vector2(-1, 0),
				1.0,
				TankPalette.MUD,
				"prop_wire"
			)
		)
	# The coil: overlapping loops along the run, each a slightly different size, so they tangle into
	# one sagging mesh instead of a row of letters.
	var coil_x := x0 + 4.0
	var k := 0
	while coil_x < x0 + span - 4.0:
		var r := 4.5 + 1.5 * _u(h, 40 + k)
		var t := (coil_x - x0) / span
		var sag := sin(t * PI * 3.0) * 1.5
		var c := Vector2(coil_x, ground - 7.0 - r * 0.6 + sag)
		var col := TankPalette.IRON if k % 3 != 1 else TankPalette.RUST_DARK
		rows.append(_loop(c, r + 1.0, r, 0.15 * float(k % 4), col))
		coil_x += 2.6 + 1.2 * _u(h, 60 + k)
		k += 1
	# Two strands strung over the stake tops.
	for s in 2:
		var pts := PackedVector2Array()
		for top in stakes:
			pts.append(top + Vector2(0, 2.0 + 4.0 * float(s)))
		rows.append(
			{"t": "polyline", "pts": pts, "w": 1.0, "c": TankPalette.STEEL_DARK, "of": "prop_wire"}
		)


static func _hedgehog(
	rows: Array[Dictionary], c: Vector2, scale: float, h: int, light: float
) -> void:
	var len_px := BEAM_PX * scale
	var tilt := deg_to_rad((_u(h, 1) - 0.5) * 36.0)
	var k := 1.0 - light
	var face := TankPalette.darkened(TankPalette.IRON, k)
	var lit := TankPalette.darkened(TankPalette.STEEL_DARK, k)
	var shadow := TankPalette.darkened(TankPalette.COAL, k)
	var rust := TankPalette.darkened(TankPalette.RUST_DARK, k)
	var w := 4.0 if scale >= 0.9 else 3.0
	# The beam pointing at the viewer: short and darkest, its cut end square on to the eye.
	# It splays the silhouette into three legs, so the hedgehog never reads as a letter X.
	var fore := Vector2(0.34, -0.42).rotated(tilt) * len_px
	_beam(rows, c - fore * 0.75, c + fore * 0.8, w + 1.0, shadow, face, shadow)
	var end := (c + fore * 0.8).round()
	rows.append(_rect(Rect2(end - Vector2(2, 2), Vector2(5, 5)), shadow))
	rows.append(_rect(Rect2(end - Vector2(1, 1), Vector2(3, 3)), face))
	rows.append(_rect(Rect2(end - Vector2(1, 1), Vector2(3, 1)), lit))
	# The two beams across the picture plane: heavy angle-iron with a lit top flange and a dark web,
	# crossing off centre with unequal reaches and flanged ends (chunky, never thin strokes).
	var a := Vector2.from_angle(deg_to_rad(-62.0) + tilt)
	var b := Vector2.from_angle(deg_to_rad(-128.0) + tilt)
	var ra := len_px * (0.5 + 0.1 * _u(h, 2))
	var rb := len_px * (0.36 + 0.1 * _u(h, 3))
	for beam: Array in [[b, rb, 0.75], [a, ra, 0.9]]:
		var d: Vector2 = beam[0]
		var r: float = beam[1]
		var p0 := c - d * r * float(beam[2])
		var p1 := c + d * r
		_beam(rows, p0, p1, w, face, lit, shadow)
		rows.append(_line(c + d * 3.0, c + d * 3.0 + Vector2(0, 4.0), 1.0, rust))
	rows.append(_rect(Rect2((c - Vector2(2, 1)).round(), Vector2(4, 3)), shadow))


## One thick beam from `a` to `b`: a dark web, a face, a lit top edge and flanged ends.
static func _beam(
	rows: Array[Dictionary], a: Vector2, b: Vector2, w: float, face: Color, lit: Color, dark: Color
) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	if n.y > 0.0:
		n = -n
	rows.append(_line(a - n, b - n, w, dark))
	rows.append(_line(a, b, w - 1.0, face))
	rows.append(_line(a + n * (w * 0.5 - 0.5), b + n * (w * 0.5 - 0.5), 1.0, lit))
	for p: Vector2 in [a, b]:
		rows.append(_line(p - n * (w * 0.5 + 1.0), p + n * (w * 0.5 + 1.0), 2.0, dark))


static func _rect(r: Rect2, c: Color) -> Dictionary:
	return {"t": "rect", "r": r, "c": c, "of": "prop_tank_traps"}


static func _heap(rows: Array[Dictionary], at: Vector2, half_w: float) -> void:
	var pts := PackedVector2Array(
		[
			at + Vector2(-half_w, 0),
			at + Vector2(-half_w * 0.5, -3.0),
			at + Vector2(0, -4.0),
			at + Vector2(half_w * 0.6, -2.5),
			at + Vector2(half_w, 0),
		]
	)
	rows.append({"t": "poly", "pts": pts, "c": TankPalette.MUD_DARK, "of": "prop_tank_traps"})
	rows.append(
		{
			"t": "polyline",
			"pts": PackedVector2Array([pts[1], pts[2], pts[3]]),
			"w": 1.0,
			"c": TankPalette.MUD,
			"of": "prop_tank_traps"
		}
	)


static func _line(
	a: Vector2, b: Vector2, w: float, c: Color, of: String = "prop_tank_traps"
) -> Dictionary:
	return {"t": "line", "a": a, "b": b, "w": w, "c": c, "of": of}


## One loop of the coil: an ellipse of radii (rx, ry) seen a little from the side (phase skews it).
static func _loop(c: Vector2, rx: float, ry: float, phase: float, col: Color) -> Dictionary:
	var pts := PackedVector2Array()
	for i in 13:
		var a := TAU * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * rx * 0.55 + sin(a) * phase * rx, sin(a) * ry))
	return {"t": "polyline", "pts": pts, "w": 1.0, "c": col, "of": "prop_wire"}


static func _hash(id: int, salt: int) -> int:
	return (id * 73856093 ^ salt * 19349663) & 0x7fffffff


## A deterministic 0 .. 1 value from hash `h` and slot `k`.
static func _u(h: int, k: int) -> float:
	return float(((h ^ (k * 83492791)) * 2654435761 >> 7) & 1023) / 1023.0
