class_name FishingFloor
extends RefCounted
## The sea floor, drawn in art pixels by FishingScenery: no long gentle slopes. The world's
## profile becomes flat terraces of a seeded whole number of CELL_PX world cells (lengths off any
## regular grid) with sheer drops between them; every terrace longer than a piece is broken into
## pieces raised or notched a few pixels (outcrops and notches), and every drop shows a darker
## side plane on the higher piece's edge under a lit lip. Behind them a back ridge of flat-topped
## mesas scrolls at RIDGE_FACTOR; some drops are clean 1:2 or 1:4 slopes and some pieces carry
## low mounds, narrow deep pieces are pits; on them each zone's prop clusters (FishingProps: one
## big piece and small ones per cluster), caves cut into the deep's cliffs, one tall ledged cliff
## where the floor drops into the abyss and the map's landmarks as set pieces. The harbour is a flat quay shelf with
## one dredged drop. Everything is seeded by world position and deterministic (decoration only,
## never game state).
## Colours by the water band just above a piece (FishingScenery.WATER_STEPS_M): the floor two
## steps darker than that water (sage in the shallows), its 2-row rim a step lighter than the
## water, the ridge between them; legend() gives the props their colours.

const CELL_PX := 8
## Terraces are worked out per block of cells (merging never crosses a block edge).
const BLOCK_CELLS := 96
## Per zone (FishingWorld.ZONES): the most a terrace's rows may vary before it drops, at the
## block's own view depth, and the terrace lengths (cells) the seed picks from.
const MERGE_ROWS: Array[float] = [999.0, 8.0, 10.0, 12.0, 18.0, 22.0, 16.0]
const TERRACE_CELLS: Array[int] = [7, 9, 11, 13, 15, 17, 21, 25]
## Per zone, how far (a share of its depth) each terrace is seeded up or down from the true
## floor, so the floor climbs and drops in terraces instead of following a gentle slope.
const RELIEF: Array[float] = [0.0, 0.16, 0.32, 0.26, 0.2, 0.14, 0.24]
## The harbour: a quay shelf this deep out to DOCK_DROP_M, then the dredged channel.
const DOCK_SHELF_M := 2.6
const DOCK_CHANNEL_M := 5.4
const DOCK_DROP_M := 330.0
## Pieces: a terrace is cut into pieces PIECE_MIN..PIECE_MIN + PIECE_SPAN px long, each raised or
## lowered by a seeded PIECE_DY (px; the first stays level).
const PIECE_MIN := 22
const PIECE_SPAN := 26
const PIECE_DY: Array[int] = [0, -2, -4, 2, -6, 0, 4, -2]
## The floor, its rim, the ridge, the dark side planes, the plant stem and blade, the coral and
## the bones per water band.
const FLOOR_BANDS: Array[Color] = [
	FishingPalette.SAGE,
	FishingPalette.MID,
	FishingPalette.DEEP,
	FishingPalette.ABYSS,
]
const RIM_BANDS: Array[Color] = [
	FishingPalette.SKY,
	FishingPalette.HAZE,
	FishingPalette.SURFACE,
	FishingPalette.UPPER,
]
const RIDGE_BANDS: Array[Color] = [
	FishingPalette.SURFACE,
	FishingPalette.UPPER,
	FishingPalette.MID,
	FishingPalette.DEEP,
]
const DARK_BANDS: Array[Color] = [
	FishingPalette.UPPER,
	FishingPalette.DEEP,
	FishingPalette.ABYSS,
	FishingPalette.ABYSS,
]
const STEM_BANDS: Array[Color] = [
	FishingPalette.UPPER,
	FishingPalette.MID,
	FishingPalette.DEEP,
	FishingPalette.ABYSS,
]
const BLADE_BANDS: Array[Color] = [
	FishingPalette.SURFACE,
	FishingPalette.UPPER,
	FishingPalette.MID,
	FishingPalette.DEEP,
]
const CORAL_BANDS: Array[Color] = [
	FishingPalette.SAGE,
	FishingPalette.SAGE,
	FishingPalette.MID,
	FishingPalette.DEEP,
]
const BONE_BANDS: Array[Color] = [
	FishingPalette.SKY,
	FishingPalette.HAZE,
	FishingPalette.MID,
	FishingPalette.DEEP,
]
const RIM_ROWS := 2
## A water band edge this close above a piece would leave a sliver of the next band.
const SLIVER_ROWS := 2
## A drop's side plane is 2 px wide, 3 from this height.
const SIDE_WIDE_PX := 12.0
## The back ridge: its parallax factor, its mesas' widths (px of the ridge), their heights over
## the mean floor in sight (px) and the shoulder step at each side.
const RIDGE_FACTOR := 0.7
const RIDGE_MESA_MIN := 40
const RIDGE_MESA_SPAN := 64
const RIDGE_HEIGHTS: Array[int] = [8, 14, 20, 26, 12, 18]
const RIDGE_SHOULDER := 6
## In the deep and the abyss the ridge stands this much lower (the dark water is tall there).
const RIDGE_DEEP_SCALE := 0.5
## Prop clusters: one per CLUSTER_PX of world px (where a piece has room), the big piece and up
## to two small ones beside it; in the harbour one cluster in MOORING_ONE_IN is a mooring.
const CLUSTER_PX := 44
const MOORING_ONE_IN := 5
## Drops of RAMP_MIN..RAMP_MAX px are, by seed, clean slopes instead (1 px down per RAMP_RUNS
## px), laid on the lower piece where it has room; pieces at least MOUND_MIN_PX long carry, by
## seed, a low mound with 1:2 sides.
const RAMP_MIN := 4.0
const RAMP_MAX := 14.0
const RAMP_RUNS: Array[int] = [2, 4]
const MOUND_MIN_PX := 44.0
## A piece at most PIT_MAX_PX long and PIT_MIN_PX under both neighbours is a pit: one flat
## interior a step darker than their floor, no rim, their floor as its walls.
const PIT_MAX_PX := 64.0
const PIT_MIN_PX := 8.0
## A piece narrower than this sunk between two higher ones fills up to the higher (no slots).
const NARROW_PX := 24.0
## A pit's floor lies at most this far under its lower rim.
const PIT_DEEPEST_PX := 12.0
## Neighbouring pieces closer in height than this share the first one's colours (no colour seam
## on a flat run).
const SEAM_PX := 6.0
## A piece's own band shows as a cap this many rows deep over the floor's body colour, ending in
## a slope CAP_SLOPE px in per row where the next piece's band differs.
const CAP_ROWS := 12
const CAP_SLOPE := 2
## A pit's dark floor: a cap this deep, sloping in at both ends.
const PIT_CAP_ROWS := 4
## The abyss cliff: from the last piece, a ledge ABYSS_LEDGES[0] px wide ABYSS_DROPS[0] px down,
## a second one, then one tall face to the bottom.
const ABYSS_LEDGES: Array[float] = [20.0, 5.0]
const ABYSS_DROPS: Array[float] = [26.0, 40.0]
## Deep cliffs at least this high get a cave mouth.
const CAVE_DROP_PX := 18.0

var world: FishingWorld = null
## Screen x spans of the fish on a line this frame (FishingScenery.fish_x): plants stay out of them.
var fish_x: Array[Vector2] = []

## block index -> terraces [{"c0", "c1" (cells, end exclusive), "d" (m, INF: none), "zone"}].
var _blocks: Dictionary = {}


func set_world(w: FishingWorld) -> void:
	world = w
	_blocks.clear()


## The terraces overlapping world px [px0, px1]: [{"x0", "x1" (world px), "d" (m), "zone", "c0"}].
func terraces_in(px0: float, px1: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	var b0 := floori(px0 / float(CELL_PX * BLOCK_CELLS))
	var b1 := floori(px1 / float(CELL_PX * BLOCK_CELLS))
	for b in range(b0, b1 + 1):
		for t: Dictionary in _block(b):
			var x0 := float(int(t["c0"]) * CELL_PX)
			var x1 := float(int(t["c1"]) * CELL_PX)
			if x1 > px0 and x0 < px1:
				out.append({"x0": x0, "x1": x1, "d": t["d"], "zone": t["zone"], "c0": t["c0"]})
	return out


func _block(b: int) -> Array:
	if _blocks.has(b):
		return _blocks[b]
	var c0 := b * BLOCK_CELLS
	var depths: Array[float] = []
	var vd := FishingScenery.VIEW_DEPTH_MIN_M
	for k in BLOCK_CELLS:
		var x_m := (float((c0 + k) * CELL_PX) + float(CELL_PX) * 0.5) / FishingScenery.PX_PER_M
		var d := world.floor_depth_m(maxf(x_m, 0.0))
		if world.zone_index_at(x_m) <= 0 and not is_inf(d):
			d = DOCK_SHELF_M if x_m < DOCK_DROP_M else DOCK_CHANNEL_M
		depths.append(d)
		vd = maxf(vd, FishingScenery.ABYSS_M if is_inf(d) else d)
	vd = minf(vd, FishingScenery.ABYSS_M)
	var rows := func(d: float) -> float: return float(FishingScenery.FLOOR_ROWS) * sqrt(d / vd)
	var out: Array = []
	var k := 0
	while k < BLOCK_CELLS:
		var cell := c0 + k
		var x_m := float(cell * CELL_PX) / FishingScenery.PX_PER_M
		var zone := maxi(world.zone_index_at(x_m), 0)
		var start := k
		if is_inf(depths[k]):
			while k < BLOCK_CELLS and is_inf(depths[k]):
				k += 1
			out.append({"c0": cell, "c1": c0 + k, "d": INF, "zone": zone})
			continue
		var most := TERRACE_CELLS[FishingScenery.hash2(cell, 71) % TERRACE_CELLS.size()]
		if zone == 0:
			most = BLOCK_CELLS
		var ref: float = rows.call(depths[k])
		var lo := ref
		var hi := ref
		k += 1
		while k < BLOCK_CELLS and k - start < most and not is_inf(depths[k]):
			var r: float = rows.call(depths[k])
			if maxf(hi, r) - minf(lo, r) > MERGE_ROWS[zone] or (zone == 0 and r != ref):
				break
			lo = minf(lo, r)
			hi = maxf(hi, r)
			k += 1
		var mid := (lo + hi) * 0.5 / float(FishingScenery.FLOOR_ROWS)
		var u := float(FishingScenery.hash2(cell, 97) % 1000) / 999.0
		var d := mid * mid * vd * (1.0 + RELIEF[zone] * (2.0 * u - 1.0))
		out.append({"c0": cell, "c1": c0 + k, "d": maxf(d, 1.0), "zone": zone})
	_blocks[b] = out
	return out


## The deepest terrace over world px [px0, px1] (m; ABYSS_M where the floor drops away).
func deepest_in(px0: float, px1: float) -> float:
	var out := 0.0
	for t in terraces_in(px0, px1):
		out = maxf(out, FishingScenery.ABYSS_M if is_inf(float(t["d"])) else float(t["d"]))
	return out


## The drawn floor's depth (m) at world x (INF where none is): the terrace there.
func depth_at(x_m: float) -> float:
	var px := x_m * FishingScenery.PX_PER_M
	for t in terraces_in(px, px + 1.0):
		if px >= float(t["x0"]) and px < float(t["x1"]):
			return float(t["d"])
	return INF


## Terrace `t`'s pieces as Vector3(world x0, world x1, dy px): cut every PIECE_MIN..+PIECE_SPAN px
## (a short tail joins the piece before it), raised or lowered by seed; the harbour stays flat.
static func pieces(t: Dictionary) -> Array[Vector3]:
	var x0 := float(t["x0"])
	var x1 := float(t["x1"])
	var out: Array[Vector3] = []
	if int(t["zone"]) == 0:
		out.append(Vector3(x0, x1, 0.0))
		return out
	var x := x0
	var k := 0
	while x < x1:
		var h := FishingScenery.hash2(int(x), 41)
		var w := float(PIECE_MIN + h % PIECE_SPAN)
		var end := minf(x + w, x1)
		if x1 - end < float(PIECE_MIN) * 0.5:
			end = x1
		var dy := 0.0 if k == 0 else float(PIECE_DY[(h >> 6) % PIECE_DY.size()])
		out.append(Vector3(x, end, dy))
		x = end
		k += 1
	return out


## Draws the floor for camera `cam_m` at time `t` (s); nothing at or past `edge_px` (screen).
func paint(c: CanvasItem, sc: FishingScenery, cam_m: float, t: float, edge_px: float) -> void:
	fish_x = sc.fish_x
	if world == null:
		return
	var cam_px := roundf(cam_m * FishingScenery.PX_PER_M)
	var shown := profile(sc, cam_px, edge_px)
	_paint_ridge(c, sc, cam_px, shown, minf(edge_px, floor_end(shown, cam_px, sc.w)))
	var body := body_band(shown)
	for i in shown.size():
		var left := int(shown[i - 1]["band"]) if i > 0 else -1
		var right := int(shown[i + 1]["band"]) if i + 1 < shown.size() else -1
		_paint_piece(c, shown[i], sc.h, body, left, right)
	var taken := _paint_drops(c, shown)
	for e in shown:
		_paint_mound(c, e, taken)
	for e in shown:
		_paint_props(c, e, t, cam_px, taken)
	_paint_abyss_drop(c, sc, cam_px, shown, edge_px)
	_paint_landmarks(c, sc, cam_m, shown, edge_px)


## The pieces in sight, left to right: [{"sx0", "sx1" (screen), "top", "band", "zone", "x0"
## (world px), "c0"}], each top on an even row.
func profile(sc: FishingScenery, cam_px: float, edge_px: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tr in terraces_in(cam_px - 64.0, cam_px + float(sc.w) + 64.0):
		if is_inf(float(tr["d"])):
			continue
		var base := 2.0 * roundf(sc.y_of_depth(float(tr["d"])) * 0.5)
		for p in pieces(tr):
			var sx0 := p.x - cam_px
			var sx1 := minf(p.y - cam_px, edge_px)
			if sx1 <= sx0:
				continue
			var top := base + p.z
			if top >= float(sc.h):
				continue
			var band := FishingScenery.band_at(sc.depth_of_y(top - 1.0 - float(SLIVER_ROWS)))
			(
				out
				. append(
					{
						"sx0": sx0,
						"sx1": sx1,
						"top": top,
						"band": band,
						"zone": tr["zone"],
						"x0": p.x,
						"c0": tr["c0"],
						"pit": -1,
						"pit_top": 0.0,
					}
				)
			)
	# a sliver of a piece sunk between two higher ones would be a slot: it fills up to the higher
	for i in range(1, out.size() - 1):
		var a := out[i - 1]
		var e := out[i]
		var b := out[i + 1]
		var hi := a if float(a["top"]) <= float(b["top"]) else b
		var sunk := float(e["top"]) > maxf(float(a["top"]), float(b["top"]))
		if float(e["sx1"]) - float(e["sx0"]) < NARROW_PX and sunk:
			e["top"] = hi["top"]
			e["band"] = hi["band"]
	for i in range(1, out.size() - 1):
		var a := out[i - 1]
		var e := out[i]
		var b := out[i + 1]
		var w := float(e["sx1"]) - float(e["sx0"])
		var deep_a := float(e["top"]) - float(a["top"]) >= PIT_MIN_PX
		var deep_b := float(e["top"]) - float(b["top"]) >= PIT_MIN_PX
		var joined := float(a["sx1"]) == float(e["sx0"]) and float(e["sx1"]) == float(b["sx0"])
		if joined and deep_a and deep_b and w <= PIT_MAX_PX:
			var hi := a if float(a["top"]) <= float(b["top"]) else b
			e["pit"] = hi["band"]
			e["pit_top"] = maxf(float(a["top"]), float(b["top"]))
	for i in range(1, out.size()):
		var prev := out[i - 1]
		var e := out[i]
		if absf(float(e["top"]) - float(prev["top"])) < SEAM_PX:
			e["band"] = prev["band"]
	return out


## The screen x where the floor in sight drops away into the abyss (INF when it does not).
func floor_end(shown: Array[Dictionary], cam_px: float, view_w: int = FishingScenery.W) -> float:
	if shown.is_empty():
		return INF
	var sx := float(shown[-1]["sx1"])
	if sx < float(view_w) and is_inf(depth_at((sx + cam_px + 1.0) / FishingScenery.PX_PER_M)):
		return sx
	return INF


## The top row of the floor drawn at screen x (INF where none is).
static func top_at(shown: Array[Dictionary], sx: float) -> float:
	for e in shown:
		if sx >= float(e["sx0"]) and sx < float(e["sx1"]):
			return float(e["top"])
	return INF


## The floor's body colour under every piece's cap: the darkest band's floor in sight, so
## biomes change only along the floor's top (never in a column down to the frame's bottom).
static func body_band(shown: Array[Dictionary]) -> int:
	var out := 0
	for e in shown:
		out = maxi(out, int(e["band"]))
	return out


## Piece `e`: the water sliver over it, the body fill (band `body`) down to the bottom, its own
## band's floor as a CAP_ROWS cap under its lit rim; where a neighbour's band (`left`, `right`;
## -1 none) differs, the cap ends in a 1:2 slope (CAP_SLOPE px in per row down) instead of a
## vertical seam. A pit's dark floor is a cap too.
func _paint_piece(
	c: CanvasItem, e: Dictionary, view_h: int, body: int, left: int, right: int
) -> void:
	var sx0 := float(e["sx0"])
	var w := float(e["sx1"]) - sx0
	var top := float(e["top"])
	var band := int(e["band"])
	if int(e["pit"]) >= 0:
		var floor_y := minf(top, float(e["pit_top"]) + PIT_DEEPEST_PX)
		c.draw_rect(Rect2(sx0, floor_y, w, float(view_h) - floor_y), FLOOR_BANDS[body])
		for r in PIT_CAP_ROWS:
			var inset := float(r * CAP_SLOPE)
			if w - 2.0 * inset > 0.0:
				var row := Rect2(sx0 + inset, floor_y + float(r), w - 2.0 * inset, 1.0)
				c.draw_rect(row, DARK_BANDS[int(e["pit"])])
		return
	c.draw_rect(Rect2(sx0, top - SLIVER_ROWS, w, SLIVER_ROWS), FishingPalette.SEA[band])
	c.draw_rect(Rect2(sx0, top, w, float(view_h) - top), FLOOR_BANDS[body])
	if band != body:
		for r in CAP_ROWS:
			var a := float(r * CAP_SLOPE) if left >= 0 and left != band else 0.0
			var b := float(r * CAP_SLOPE) if right >= 0 and right != band else 0.0
			if w - a - b > 0.0:
				c.draw_rect(Rect2(sx0 + a, top + float(r), w - a - b, 1.0), FLOOR_BANDS[band])
	c.draw_rect(Rect2(sx0, top, w, RIM_ROWS), RIM_BANDS[band])


## Every drop between neighbouring pieces (none into a pit, whose walls are its neighbours'
## floor): a clean slope by seed where the lower piece has room (ramp()), else a darker side
## plane down the higher piece's edge (2 px, 3 on tall drops) under a 1 px lit lip reaching over
## it, and a cave mouth in the deep's tall cliffs. Returns the screen spans the slopes cover.
func _paint_drops(c: CanvasItem, shown: Array[Dictionary]) -> Array[Vector2]:
	var taken: Array[Vector2] = []
	for i in range(1, shown.size()):
		var a := shown[i - 1]
		var b := shown[i]
		if float(b["sx0"]) != float(a["sx1"]) or int(a["pit"]) >= 0 or int(b["pit"]) >= 0:
			continue
		var drop := float(b["top"]) - float(a["top"])
		if absf(drop) < 2.0:
			continue
		var hi := a if drop > 0.0 else b
		var lo := b if drop > 0.0 else a
		var edge := float(a["sx1"])
		var span := ramp(c, edge, hi, lo, drop > 0.0)
		if span != Vector2.ZERO:
			taken.append(span)
			continue
		var lo_top := float(lo["top"])
		var hi_top := float(hi["top"])
		var band := int(hi["band"])
		var sw := 3.0 if absf(drop) >= SIDE_WIDE_PX else 2.0
		var x := edge - sw if drop > 0.0 else edge
		var face := lo_top - hi_top - float(RIM_ROWS)
		if face > 0.0:
			c.draw_rect(Rect2(x, hi_top + RIM_ROWS, sw, face), DARK_BANDS[band])
		var lip_x := edge if drop > 0.0 else edge - 1.0
		c.draw_rect(Rect2(lip_x, hi_top, 1.0, 1.0), RIM_BANDS[band])
		if int(hi["zone"]) == 4 and absf(drop) >= CAVE_DROP_PX:
			var cx := edge - sw - 22.0 if drop > 0.0 else edge + sw + 2.0
			_cave(c, cx, hi_top + 4.0)
	return taken


## The drop at screen x `edge` from piece `hi` down to piece `lo` (on the right when `right`)
## as a clean slope laid on `lo`, 1 px down per RAMP_RUNS px, with a lit 2-row top: when its seed
## picks a slope and `lo` has room. Returns the span it covers (Vector2.ZERO: none drawn).
func ramp(c: CanvasItem, edge: float, hi: Dictionary, lo: Dictionary, right: bool) -> Vector2:
	var run := ramp_run(hi, lo)
	if run == 0:
		return Vector2.ZERO
	var drop := float(lo["top"]) - float(hi["top"])
	var length := drop * float(run)
	if float(lo["sx1"]) - float(lo["sx0"]) < length + 6.0:
		return Vector2.ZERO
	var band := int(hi["band"])
	var hi_top := float(hi["top"])
	for k in int(length):
		var x := edge + float(k) if right else edge - 1.0 - float(k)
		var y := hi_top + floorf(float(k) / float(run))
		c.draw_rect(Rect2(x, y, 1.0, float(lo["top"]) - y + 2.0), FLOOR_BANDS[band])
		c.draw_rect(Rect2(x, y, 1.0, RIM_ROWS), RIM_BANDS[band])
	return Vector2(edge, edge + length) if right else Vector2(edge - length, edge)


## The slope's run (px per row down) the seed picks for the drop from piece `hi` to `lo`, 0 for
## a sheer drop: seeded by the two pieces' world x, never by the camera, so it holds still as the
## view scrolls.
static func ramp_run(hi: Dictionary, lo: Dictionary) -> int:
	var drop := float(lo["top"]) - float(hi["top"])
	if drop < RAMP_MIN or drop > RAMP_MAX:
		return 0
	var h := FishingScenery.hash2(int(float(hi["x0"]) + float(lo["x0"])), 61)
	if h % 2 == 0:
		return 0
	return RAMP_RUNS[(h >> 3) % RAMP_RUNS.size()]


## A low mound on piece `e` by seed (where no slope lies): a flat top MOUND rows high stepping
## out 2 px a side per row (1:2 sides), lit on top and along its slopes. Adds its span to
## `taken`.
func _paint_mound(c: CanvasItem, e: Dictionary, taken: Array[Vector2]) -> void:
	var sx0 := float(e["sx0"])
	var sx1 := float(e["sx1"])
	if int(e["pit"]) >= 0 or sx1 - sx0 < MOUND_MIN_PX:
		return
	var h := FishingScenery.hash2(int(float(e["x0"])), 67)
	if h % 3 != 0:
		return
	var rows := 4 + 2 * ((h >> 2) % 2)
	var top_w := 8.0 + 2.0 * float((h >> 4) % 4)
	var base_w := top_w + 4.0 * float(rows - 1)
	if base_w > sx1 - sx0 - 8.0:
		return
	var x0 := sx0 + 4.0 + float(((h >> 7) % maxi(int(sx1 - sx0 - 8.0 - base_w), 1)) & ~1)
	for span in taken:
		if x0 < span.y and x0 + base_w > span.x:
			return
	var band := int(e["band"])
	var top := float(e["top"])
	for r in rows:
		var w := top_w + 4.0 * float(r)
		var x := x0 + (base_w - w) * 0.5
		var y := top - float(rows - r)
		c.draw_rect(Rect2(x, y, w, 1.0), FLOOR_BANDS[band])
		var lit := 1.0 if r == 0 else 2.0
		c.draw_rect(Rect2(x, y, lit if r > 0 else w, 1.0), RIM_BANDS[band])
		if r > 0:
			c.draw_rect(Rect2(x + w - 2.0, y, 2.0, 1.0), RIM_BANDS[band])
	taken.append(Vector2(x0, x0 + base_w))


## A cave mouth 20 x 12 px cut into a cliff face, its top left at (x, y).
static func _cave(c: CanvasItem, x: float, y: float) -> void:
	var widths: Array[int] = [8, 14, 18, 20, 20, 20, 20, 20, 20, 20, 20, 20]
	for k in widths.size():
		var w := float(widths[k])
		c.draw_rect(Rect2(x + (20.0 - w) * 0.5, y + float(k), w, 1.0), FishingPalette.ABYSS)


## The back ridge: flat-topped mesas behind the floor, scrolling at RIDGE_FACTOR, standing on the
## mean floor in sight, each with a shoulder step half its height at both sides; each row in its
## water band's ridge colour.
func _paint_ridge(
	c: CanvasItem, sc: FishingScenery, cam_px: float, shown: Array[Dictionary], edge_px: float
) -> void:
	if shown.is_empty():
		return
	var base := 0.0
	for e in shown:
		base += float(e["top"])
	base = 2.0 * roundf(base / float(shown.size()) * 0.5)
	var scale := RIDGE_DEEP_SCALE if int(shown[0]["zone"]) >= 4 else 1.0
	var off := roundf(cam_px * RIDGE_FACTOR)
	var span := RIDGE_MESA_MIN + RIDGE_MESA_SPAN
	var k := floori(off / float(span)) - 1
	var x := float(k * span)
	while x - off < float(sc.w):
		var h := FishingScenery.hash2(k, 29)
		var w := float(RIDGE_MESA_MIN + h % RIDGE_MESA_SPAN)
		var tall := float(RIDGE_HEIGHTS[(h >> 7) % RIDGE_HEIGHTS.size()]) * scale
		var sx := x - off
		_ridge_mesa(c, sc, sx, minf(sx + w, edge_px), base - tall, h)
		x += float(span)
		k += 1


## One mesa of the back ridge from screen x `sx0` to `sx1`, its top on row `top`: a flat top
## with a lit edge, then shoulders stepping out 2 px per 2 rows (both sides; by seed one side
## steps in a shelf half way down), each row in its water band's ridge colour.
func _ridge_mesa(
	c: CanvasItem, sc: FishingScenery, sx0: float, sx1: float, top: float, seed_h: int
) -> void:
	var y0 := 2.0 * roundf(top * 0.5)
	var w := sx1 - sx0
	var steps := mini(RIDGE_SHOULDER / 2 + 1, int(w / 8.0))
	var shelf := (seed_h >> 3) % 2 == 0
	for s in steps + 1:
		var inset := 2.0 * float(steps - s)
		var y := y0 + 2.0 * float(s)
		var a := sx0 + inset + (float(RIDGE_SHOULDER) if shelf and s == 0 else 0.0)
		var b := sx1 - inset
		var bottom := y + 2.0 if s < steps else float(sc.h)
		_ridge_rect(c, sc, a, b, y, bottom)
	var lit := y0
	for band in FishingScenery.WATER_STEPS_M.size():
		var rows := sc.band_rows(band)
		if lit >= rows.x and lit < rows.y:
			var inset0 := 2.0 * float(steps)
			var a0 := sx0 + inset0 + (float(RIDGE_SHOULDER) if shelf else 0.0)
			if sx1 - inset0 > a0:
				c.draw_rect(Rect2(a0, lit, sx1 - inset0 - a0, 1.0), RIM_BANDS[band])


func _ridge_rect(
	c: CanvasItem, sc: FishingScenery, sx0: float, sx1: float, top: float, bottom: float
) -> void:
	if sx1 <= sx0:
		return
	for band in FishingScenery.WATER_STEPS_M.size():
		var rows := sc.band_rows(band)
		var y0 := maxf(top, rows.x)
		var y1 := minf(bottom, rows.y)
		if y1 > y0:
			c.draw_rect(Rect2(sx0, y0, sx1 - sx0, y1 - y0), RIDGE_BANDS[band])


## The prop colours for water band `band` (see FishingProps); in the darkest band the props'
## rock is the deep teal, so it reads on the abyss floor.
static func legend(band: int) -> Dictionary:
	return {
		"f": FLOOR_BANDS[band] if band < 3 else FishingPalette.DEEP,
		"r": RIM_BANDS[band],
		"d": DARK_BANDS[band],
		"ps": STEM_BANDS[band],
		"pb": BLADE_BANDS[band],
		"c": CORAL_BANDS[band],
		"b": BONE_BANDS[band],
		"s": FishingPalette.SLATE,
		"o": FishingPalette.WOOD,
		"a": FishingPalette.ACCENT,
		"x": FishingPalette.ABYSS,
		"w": FishingPalette.SEA[band],
	}


## Grid `rows` with its bottom row's left end at (x, bottom), colours from `lg`, in row runs.
static func stamp(c: CanvasItem, rows: Array, x: float, bottom: float, lg: Dictionary) -> void:
	var top := bottom - float(rows.size() - 1)
	for y in rows.size():
		var row: String = rows[y]
		var i := 0
		while i < row.length():
			var ch := row[i]
			var j := i
			while j < row.length() and row[j] == ch:
				j += 1
			if lg.has(ch):
				c.draw_rect(Rect2(x + float(i), top + float(y), float(j - i), 1.0), lg[ch])
			i = j


## The clusters on piece `e`: one per CLUSTER_PX of world px whose seeded spot falls on it with
## room to spare and off the slopes and mounds in `taken`, each the zone's big piece
## (FishingProps.BIG) and up to two small ones.
func _paint_props(
	c: CanvasItem, e: Dictionary, t: float, cam_px: float, taken: Array[Vector2]
) -> void:
	if int(e["pit"]) >= 0:
		return
	var zone := clampi(int(e["zone"]), 0, FishingProps.BIG.size() - 1)
	var lg := legend(int(e["band"]))
	lg["surf"] = float(FishingScenery.SURF_Y)
	var top := float(e["top"])
	var wx0 := float(e["sx0"]) + cam_px
	var wx1 := float(e["sx1"]) + cam_px
	var s0 := floori(wx0 / float(CLUSTER_PX))
	var s1 := floori(wx1 / float(CLUSTER_PX))
	for s in range(s0, s1 + 1):
		var h := FishingScenery.hash2(s, 13 + zone)
		var wx := float(s * CLUSTER_PX) + float(h % 16)
		if wx < wx0 + 2.0 or wx > wx1 - 8.0:
			continue
		var x := wx - cam_px
		var blocked := false
		for span in taken:
			if x < span.y + 2.0 and x + 28.0 > span.x:
				blocked = true
		if blocked:
			continue
		var bigs: Array = FishingProps.BIG[zone]
		var smalls: Array = FishingProps.SMALL[zone]
		var big: String = bigs[(h >> 4) % bigs.size()]
		if zone == 0 and FishingScenery.hash2(s, 7) % MOORING_ONE_IN == 0:
			big = "mooring"
		var w := 0.0
		if not plant_under_fish(big, x):
			w = FishingProps.draw(c, big, x, top, lg, h, t)
		for k in 1 + (h >> 9) % 2:
			var hs := FishingScenery.hash2(s * 3 + k, 59)
			var small: String = smalls[hs % smalls.size()]
			var sx := x + w + 2.0 + float(hs % 4) if k == 0 else x - 10.0 - float(hs % 4)
			if sx < float(e["sx0"]) - 2.0 or sx + 4.0 > float(e["sx1"]):
				continue
			if not plant_under_fish(small, sx):
				FishingProps.draw(c, small, sx, top, lg, hs, t)


## True when prop `kind` is a plant and a fish on a line stands over its x (a stalk would end under
## the belly): about 40 px wide.
func plant_under_fish(kind: String, x: float) -> bool:
	if not FishingProps.PLANTS.has(kind):
		return false
	for span in fish_x:
		if x < span.y + 4.0 and x + 40.0 > span.x:
			return true
	return false


## Where the floor drops away into the abyss: one tall cliff from the last piece, broken by two
## ledges of unequal width (ABYSS_LEDGES, lit on top only), its faces in the dark side plane.
func _paint_abyss_drop(
	c: CanvasItem, sc: FishingScenery, cam_px: float, shown: Array[Dictionary], edge_px: float
) -> void:
	if shown.is_empty():
		return
	var last := shown[-1]
	var x := floor_end(shown, cam_px, sc.w)
	if x >= edge_px:
		return
	var y := float(last["top"])
	var bottom := float(sc.h)
	for k in ABYSS_LEDGES.size():
		var lg := legend(FishingScenery.band_at(sc.depth_of_y(y - 1.0)))
		var ny := minf(y + ABYSS_DROPS[k], bottom)
		c.draw_rect(Rect2(x - 2.0, y + RIM_ROWS, 2.0, ny - y - RIM_ROWS), lg["d"])
		if ny >= bottom:
			return
		var w := ABYSS_LEDGES[k]
		var ll := legend(FishingScenery.band_at(sc.depth_of_y(ny - 1.0)))
		c.draw_rect(Rect2(x, ny, w, bottom - ny), ll["f"])
		c.draw_rect(Rect2(x, ny, w, RIM_ROWS), ll["r"])
		x += w
		y = ny
	var lf := legend(FishingScenery.band_at(sc.depth_of_y(y - 1.0)))
	c.draw_rect(Rect2(x - 2.0, y + RIM_ROWS, 2.0, bottom - y - RIM_ROWS), lf["d"])


## The map's landmarks in sight as set pieces on the floor (the lighthouse on its breakwater at
## the surface).
func _paint_landmarks(
	c: CanvasItem, sc: FishingScenery, cam_m: float, shown: Array[Dictionary], edge_px: float
) -> void:
	if not world.has_method("landmarks"):
		return
	var view_m := float(sc.w) / FishingScenery.PX_PER_M
	for lm: Dictionary in world.call("landmarks", cam_m - 80.0, cam_m + view_m + 80.0):
		var sx := roundf(FishingScenery.screen_x(float(lm["x_m"]), cam_m))
		if sx >= edge_px:
			continue
		var kind := str(lm["kind"])
		if kind == "lighthouse":
			FishingProps.lighthouse(c, sx, float(FishingScenery.SURF_Y))
			continue
		var top := top_at(shown, clampf(sx, 0.0, float(sc.w - 1)))
		if is_inf(top):
			continue
		var band := FishingScenery.band_at(sc.depth_of_y(top - 1.0 - float(SLIVER_ROWS)))
		var lg := legend(band)
		match kind:
			"wreck":
				FishingProps.wreck(c, sx, top, lg)
			"reef_arch":
				FishingProps.arch(c, sx, top, lg)
			"whale_bones":
				FishingProps.bones(c, sx, top, lg)
