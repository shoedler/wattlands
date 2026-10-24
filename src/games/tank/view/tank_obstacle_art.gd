class_name TankObstacleArt
extends RefCounted
## Code-drawn obstacles for TankRowLayer (brief 3: wire on stakes; lines are code-drawn). The image
## model turned both into glyph-like strokes (bare stakes reading "| . / . |", hedgehogs reading
## "Xx"), so the view draws them as line work in palette colours, varied per obstacle by a hash of
## its id (no RNG, the same obstacle always looks the same):
## - tank traps: one cluster of Czech hedgehogs seen in 3/4 from a little above. Each hedgehog is three
##   mutually square beams through one point, stood on three feet (the cube's diagonal upright), turned
##   by its own yaw and projected, so its six arms differ in angle and apparent length; the beams are
##   drawn far to near, the near ones lighter with a lit top face and a dark underside, the upper arms
##   cut to unequal lengths. Base plates sit on the ground under a cast shadow and a mud mound. The
##   rear one stands 4 px higher at 70% scale and overlaps the front one, so the pair is one heap, never
##   two characters side by side on one baseline;
## - wire: four dark leaning stakes with a sagging concertina coil of overlapping loops between them.
## Every row carries "of": the sprite id it stands in for (tests, effects).

const BEAM_PX := 22.0
const OF_TRAPS := "prop_tank_traps"


## Appends the rows of a tank-trap obstacle whose left edge is at screen x `x0`, `w` px wide: three
## hedgehogs at three depths (70%, 85% and full size, each a few px lower and nearer), overlapping
## into one heap, with mud banked up in front over their feet.
static func traps(rows: Array[Dictionary], x0: float, w: float, id: int) -> void:
	var ground := float(TankConst.GROUND_Y)
	var span := maxf(w, 40.0)
	var h := _hash(id, 31)
	var s0 := 1.0 + 0.15 * _u(h, 5)
	var fx := x0 + span * (0.3 + 0.1 * _u(h, 2))
	var step := BEAM_PX * s0 * (0.38 + 0.1 * _u(h, 1))
	var dirn := 1.0 if _u(h, 9) > 0.5 else -1.0
	_heap(rows, Vector2(fx + dirn * step, ground + 2.0), step * 1.4 + 16.0)
	_hedgehog(rows, Vector2(fx + dirn * step * 1.9, ground - 5.0), s0 * 0.7, h >> 3, 0.55)
	_hedgehog(rows, Vector2(fx + dirn * step, ground - 2.0), s0 * 0.85, h >> 11, 0.75)
	_hedgehog(rows, Vector2(fx, ground + 1.0), s0, h >> 7, 1.0)
	# Mud banked up in front of the feet (drawn over them): the heap is one mass, not three glyphs.
	_bank(rows, Vector2(fx + dirn * step * 0.8, ground + 3.0), step * 1.3 + 12.0, h)


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


## One hedgehog standing on the ground at `foot` (the middle of its three feet): see the header.
static func _hedgehog(
	rows: Array[Dictionary], foot: Vector2, scale: float, h: int, light: float
) -> void:
	var len_px := BEAM_PX * scale
	var yaw := deg_to_rad(15.0 + 70.0 * _u(h, 1))
	var pitch := deg_to_rad(34.0)
	var k := 1.0 - light
	# The three beam directions: square to each other, each rising at 35.3 degrees (cube axes stood
	# on a corner), 120 degrees apart around the vertical. y up, z away from the viewer.
	var beams: Array[Dictionary] = []
	var centre_h := len_px * 0.5 * 0.577
	for i in 3:
		var az := yaw + TAU * float(i) / 3.0
		var d := Vector3(0.816 * cos(az), 0.577, 0.816 * sin(az))
		var up_len := len_px * (0.38 + 0.2 * _u(h, 2 + i))
		var a3 := Vector3(0, centre_h, 0) - d * len_px * 0.5
		var b3 := Vector3(0, centre_h, 0) + d * up_len
		beams.append({"a": a3, "b": b3, "z": (a3.z + b3.z) * 0.5, "d": d})
	beams.sort_custom(_far_first)
	# The cast shadow: a flat dark ellipse under the feet, offset away from the fires.
	var sh := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		sh.append(foot + Vector2(2.0 + cos(a) * len_px * 0.62, 1.0 + sin(a) * 2.0))
	rows.append(
		{
			"t": "poly",
			"pts": sh,
			"c": TankPalette.with_alpha(TankPalette.BLACK, 0.55),
			"of": OF_TRAPS
		}
	)
	var w := 5.0 if scale >= 0.95 else (4.0 if scale >= 0.8 else 3.0)
	for n in beams.size():
		var bm: Dictionary = beams[n]
		var pa := _project(bm["a"], foot, pitch)
		var pb := _project(bm["b"], foot, pitch)
		# Nearer beams are lighter; the one pointing most at the viewer is foreshortened by the
		# projection and drawn last, its cut end square on to the eye.
		var depth_k := float(n) / 2.0
		var face := TankPalette.darkened(TankPalette.IRON.lerp(TankPalette.STEEL_DARK, depth_k), k)
		var lit := TankPalette.darkened(
			TankPalette.STEEL_DARK.lerp(TankPalette.STEEL_LIGHT, depth_k), k
		)
		var dark := TankPalette.darkened(TankPalette.COAL, k)
		_beam(rows, pa, pb, w, face, lit, dark)
		var end := pb.round()
		rows.append(_rect(Rect2(end - Vector2(1, 1), Vector2(3, 3)), dark))
		rows.append(_rect(Rect2(end - Vector2(1, 1), Vector2(2, 1)), lit))
		# A base plate on the ground under each foot.
		var fp := pa.round()
		rows.append(_rect(Rect2(fp + Vector2(-2, 0), Vector2(5, 1)), dark))
		var rust := TankPalette.darkened(TankPalette.RUST_DARK, k)
		var mid := pa.lerp(pb, 0.55)
		rows.append(_line(mid, mid + Vector2(0, 3.0), 1.0, rust))
	# The riveted gusset plate where the beams cross hides the crossing point.
	var hub := _project(Vector3(0, centre_h, 0), foot, pitch).round()
	var g := maxf(3.0, roundf(5.0 * scale))
	var gr := Rect2(hub - Vector2(g, g) * 0.5, Vector2(g, g)).abs()
	rows.append(_rect(gr, TankPalette.darkened(TankPalette.IRON, k)))
	rows.append(
		_rect(Rect2(gr.position, Vector2(g, 1)), TankPalette.darkened(TankPalette.STEEL, k))
	)
	rows.append(
		_rect(
			Rect2(gr.end - Vector2(1, 1), Vector2(1, 1)), TankPalette.darkened(TankPalette.BLACK, k)
		)
	)


static func _far_first(p: Dictionary, q: Dictionary) -> bool:
	return float(p["z"]) > float(q["z"])


## Screen position of hedgehog point `p` (y up, z away) standing at `foot`, seen `pitch` from above.
static func _project(p: Vector3, foot: Vector2, pitch: float) -> Vector2:
	return foot + Vector2(p.x, -p.y * cos(pitch) - p.z * sin(pitch))


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
	return {"t": "rect", "r": r, "c": c, "of": OF_TRAPS}


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


## Mud banked up in front of the hedgehogs' feet: a lumpy wet bank 5-7 px high with a lit crest and
## a few clods, drawn over the feet.
static func _bank(rows: Array[Dictionary], at: Vector2, half_w: float, h: int) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		var bump := 4.0 + 2.5 * sin(t * PI) + 1.5 * sin(t * 11.0 + float(h % 7))
		pts.append(at + Vector2(-half_w + 2.0 * half_w * t, -bump * sin(t * PI) - 0.5))
	pts.append(at + Vector2(half_w, 2.0))
	pts.append(at + Vector2(-half_w, 2.0))
	rows.append({"t": "poly", "pts": pts, "c": TankPalette.MUD, "of": OF_TRAPS})
	var crest := PackedVector2Array()
	for i in range(1, 8):
		crest.append(pts[i])
	rows.append(
		{"t": "polyline", "pts": crest, "w": 1.0, "c": TankPalette.MUD_LIGHT, "of": OF_TRAPS}
	)
	for k in 3:
		var cx := at.x - half_w * 0.6 + half_w * 0.6 * float(k) + float((h >> k) % 5)
		rows.append(
			_rect(Rect2(Vector2(cx, at.y - 2.0).round(), Vector2(2, 1)), TankPalette.MUD_DARK)
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
