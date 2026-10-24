class_name FishingFloor
extends RefCounted
## The sea floor, drawn in art pixels by FishingScenery: no long gentle slopes. The world's
## profile becomes flat terraces of a whole number of CELL_PX world cells with sheer drops
## between them (cells merge while their rows stay within the zone's merge height, up to a
## seeded length), blocky stepped boulders on the terraces, a back ridge behind them (one step
## lighter than the floor, scrolling at RIDGE_FACTOR), the zone's biome props and the map's
## landmarks as set pieces. Everything is seeded by world cell and deterministic (decoration
## only, never game state); every shape is flat top-lit planes in whole pixels.
## Colours by the water band just above a terrace (FishingScenery.WATER_STEPS_M): the floor two
## steps darker than that water (sage in the shallows), its 2-row rim a step lighter than the
## water, the ridge between them; props use the same band's colours (PROP_* below).

const CELL_PX := 16
## Terraces are worked out per block of cells (merging never crosses a block edge).
const BLOCK_CELLS := 48
## Per zone (FishingWorld.ZONES): the most a terrace's rows may vary before it drops, at the
## block's own view depth, and the longest terraces (cells) the seed picks from.
const MERGE_ROWS: Array[float] = [6.0, 8.0, 10.0, 12.0, 18.0, 22.0]
const TERRACE_CELLS: Array[int] = [4, 6, 8, 10, 14]
## Per zone, how far (a share of its depth) each terrace is seeded up or down from the true
## floor, so the floor climbs and drops in terraces instead of following a gentle slope.
const RELIEF: Array[float] = [0.05, 0.16, 0.32, 0.26, 0.2, 0.14]
## The floor, its rim, the ridge, the dark prop shade and the plant colour per water band.
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
const PLANT_BANDS: Array[Color] = [
	FishingPalette.UPPER,
	FishingPalette.SAGE,
	FishingPalette.SAGE,
	FishingPalette.SAGE,
]
const RIM_ROWS := 2
## A water band edge this close above a terrace would leave a sliver of the next band.
const SLIVER_ROWS := 2
## The back ridge: its parallax factor, its column width, its height steps, the noise's wave
## length (px of the ridge) and how high it rises over the mean floor in sight (px).
const RIDGE_FACTOR := 0.7
const RIDGE_COL_PX := 8
const RIDGE_STEP_PX := 2
const RIDGE_WAVE_PX := 90.0
const RIDGE_RISE_MIN := 6
const RIDGE_RISE_MAX := 28
## Props: symbolic grids, bottom row on the terrace top. f floor, r rim, d dark, p plant, s
## slate, o wood, b bone (sky), a accent, x abyss, w the water.
const PROPS := {
	"mooring": ["..ss..", ".s..s.", "dddddd", "dddddd", "dddddd"],
	"chain": ["ss.ss.ss.ss"],
	"anchor": ["..s..", ".sss.", "..s..", "..s..", "s.s.s", ".sss."],
	"crate": ["oooooo", "oooooo", "ssssss", "oooooo", "oooooo"],
	"shell": ["rr", "rr"],
	"starfish": [".a.", "aaa", "a.a"],
	"fan":
	[
		"...ppppp...",
		".ppppppppp.",
		"ppppppppppp",
		"ppppppppppp",
		".ppppppppp.",
		"...ppppp...",
		".....p.....",
		".....p.....",
		"....ddd....",
	],
	"brain": ["..rrrrrr..", ".rrrrrrrr.", "rrrrrrrrrr", "ffffffffff", "dddddddddd"],
	"branch":
	[
		"pp....pp...",
		"pp....pp.pp",
		"pp.pp.pp.pp",
		"pppp..pppp.",
		".ppp...pp..",
		"..ppppppp..",
		"....ppp....",
		"....ppp....",
	],
	"anemone": ["r..r..r", "rr.rr.r", "rrrrrrr", ".ddddd."],
	"arch":
	[
		"..rrrrrrrrrr..",
		".ffffffffffff.",
		"ffffffffffffff",
		"fff........fff",
		"fff........fff",
		"ddd........ddd",
	],
	"cave": ["..xxxx..", ".xxxxxx.", "xxxxxxxx", "xxxxxxxx"],
	"bones": ["b...b...b...b", "bb..bb..bb..b", "bbbbbbbbbbbbb"],
}
## Each zone's props in seed order (a terrace cell with a prop picks one).
const BIOME: Array = [
	["mooring", "crate", "anchor", "chain", "crate"],
	["grass", "shell", "grass", "starfish", "ripples", "grass"],
	["fan", "brain", "branch", "anemone", "arch", "brain"],
	["kelp", "ledge", "kelp", "kelp", "ledge"],
	["bones", "cave", "ledge", "bones"],
	["basalt", "basalt", "ledge"],
]
## The BIOME props drawn by code rather than from PROPS.
const DRAWN_PROPS: Array[String] = ["grass", "kelp", "basalt", "ripples", "ledge", "cave"]
## One cell in PROP_ONE_IN carries a prop; one terrace in BOULDER_ONE_IN a boulder.
const PROP_ONE_IN := 3
const BOULDER_ONE_IN := 2

var world: FishingWorld = null
## block index -> terraces [{"c0", "c1" (cells, end exclusive), "d" (m, INF: none)}].
var _blocks: Dictionary = {}


func set_world(w: FishingWorld) -> void:
	world = w
	_blocks.clear()


## The terraces overlapping world px [px0, px1]: [{"x0", "x1" (world px), "d" (m), "zone"}].
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
		var ref: float = rows.call(depths[k])
		var lo := ref
		var hi := ref
		k += 1
		while k < BLOCK_CELLS and k - start < most and not is_inf(depths[k]):
			var r: float = rows.call(depths[k])
			if maxf(hi, r) - minf(lo, r) > MERGE_ROWS[zone]:
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


## Draws the floor for camera `cam_m` at time `t` (s); nothing at or past `edge_px` (screen).
func paint(c: CanvasItem, sc: FishingScenery, cam_m: float, t: float, edge_px: float) -> void:
	if world == null:
		return
	var cam_px := roundf(cam_m * FishingScenery.PX_PER_M)
	var shown: Array[Dictionary] = []
	for tr in terraces_in(cam_px - 64.0, cam_px + float(FishingScenery.W) + 64.0):
		if is_inf(float(tr["d"])):
			continue
		var top := 2.0 * roundf(sc.y_of_depth(float(tr["d"])) * 0.5)
		var band := FishingScenery.band_at(sc.depth_of_y(top - 1.0 - float(SLIVER_ROWS)))
		var sx0 := float(tr["x0"]) - cam_px
		var sx1 := minf(float(tr["x1"]) - cam_px, edge_px)
		if sx1 <= sx0 or top >= float(FishingScenery.H):
			continue
		var e := tr.duplicate()
		e.merge({"sx0": sx0, "sx1": sx1, "top": top, "band": band})
		shown.append(e)
	_paint_ridge(c, sc, cam_px, shown, edge_px)
	for e in shown:
		_paint_terrace(c, e)
	for e in shown:
		_paint_props(c, e, t)
	_paint_landmarks(c, sc, cam_m, shown, edge_px)


## The top row of the terrace drawn at screen x (INF where none is).
static func top_at(shown: Array[Dictionary], sx: float) -> float:
	for e in shown:
		if sx >= float(e["sx0"]) and sx < float(e["sx1"]):
			return float(e["top"])
	return INF


func _paint_terrace(c: CanvasItem, e: Dictionary) -> void:
	var sx0 := float(e["sx0"])
	var w := float(e["sx1"]) - sx0
	var top := float(e["top"])
	var band := int(e["band"])
	var h := float(FishingScenery.H) - top
	c.draw_rect(Rect2(sx0, top - SLIVER_ROWS, w, SLIVER_ROWS), FishingPalette.SEA[band])
	c.draw_rect(Rect2(sx0, top, w, h), FLOOR_BANDS[band])
	c.draw_rect(Rect2(sx0, top, w, RIM_ROWS), RIM_BANDS[band])


## The back ridge: a hill line behind the terraces, scrolling at RIDGE_FACTOR, in
## RIDGE_COL_PX columns whose heights follow smooth seeded noise in RIDGE_STEP_PX steps, standing
## on the mean floor in sight; each row in its water band's ridge colour.
func _paint_ridge(
	c: CanvasItem, sc: FishingScenery, cam_px: float, shown: Array[Dictionary], edge_px: float
) -> void:
	if shown.is_empty():
		return
	var base := 0.0
	for e in shown:
		base += float(e["top"])
	base /= float(shown.size())
	var off := roundf(cam_px * RIDGE_FACTOR)
	var k0 := floori(off / float(RIDGE_COL_PX))
	for k in range(k0, k0 + FishingScenery.W / RIDGE_COL_PX + 2):
		var sx0 := float(k * RIDGE_COL_PX) - off
		var sx1 := minf(sx0 + float(RIDGE_COL_PX), edge_px)
		if sx1 <= sx0:
			continue
		var u := noise(float(k * RIDGE_COL_PX) / RIDGE_WAVE_PX, 23)
		var rise := lerpf(float(RIDGE_RISE_MIN), float(RIDGE_RISE_MAX), u)
		var top := base - float(RIDGE_STEP_PX) * roundf(rise / float(RIDGE_STEP_PX))
		for band in FishingScenery.WATER_STEPS_M.size():
			var rows := sc.band_rows(band)
			var y0 := maxf(top, rows.x)
			if rows.y > y0:
				c.draw_rect(Rect2(sx0, y0, sx1 - sx0, rows.y - y0), RIDGE_BANDS[band])


## Smooth seeded value noise in 0..1 at `u` (cosine-eased between whole-number knots).
static func noise(u: float, salt: int) -> float:
	var i := floori(u)
	var f := u - float(i)
	var a := float(FishingScenery.hash2(i, salt) % 1000) / 999.0
	var b := float(FishingScenery.hash2(i + 1, salt) % 1000) / 999.0
	return lerpf(a, b, 0.5 - 0.5 * cos(f * PI))


## The prop colours for water band `band`.
static func legend(band: int) -> Dictionary:
	return {
		"f": FLOOR_BANDS[band],
		"r": RIM_BANDS[band],
		"d": DARK_BANDS[band],
		"p": PLANT_BANDS[band],
		"s": FishingPalette.SLATE,
		"o": FishingPalette.WOOD,
		"b": FishingPalette.SKY,
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


func _paint_props(c: CanvasItem, e: Dictionary, t: float) -> void:
	var band := int(e["band"])
	var lg := legend(band)
	var top := float(e["top"])
	var zone := int(e["zone"])
	var cells := (int(e["sx1"] - e["sx0"]) + CELL_PX - 1) / CELL_PX
	var c0 := int(e["c0"])
	if cells >= 3 and FishingScenery.hash2(c0, 5) % BOULDER_ONE_IN == 0:
		_boulder(c, e, lg, c0)
	var kinds: Array = BIOME[clampi(zone, 0, BIOME.size() - 1)]
	for k in cells:
		var cell := c0 + k
		var h := FishingScenery.hash2(cell, 13)
		if h % PROP_ONE_IN != 0:
			continue
		var x := float(e["sx0"]) + float(k * CELL_PX) + float((h >> 4) % 8)
		if x + 12.0 > float(e["sx1"]):
			continue
		var kind: String = kinds[(h >> 8) % kinds.size()]
		_prop(c, kind, x, top, lg, h, t)


## A blocky boulder on terrace `e`: two or three tiers stepping in a side, each with a lit
## top row and a dark right face.
func _boulder(c: CanvasItem, e: Dictionary, lg: Dictionary, seed: int) -> void:
	var h := FishingScenery.hash2(seed, 31)
	var w := 12.0 + 2.0 * float(h % 9)
	var span := float(e["sx1"]) - float(e["sx0"]) - w
	if span < 4.0:
		return
	var x := float(e["sx0"]) + 2.0 + float(((h >> 5) % maxi(int(span) - 2, 1)) & ~1)
	var y := float(e["top"])
	var tiers := 2 + (h >> 9) % 2
	for k in tiers:
		var th := 4.0 + 2.0 * float((h >> (11 + k)) % 2)
		var inset := 2.0 * float(k) + 2.0 * float((h >> (14 + k)) % 2) * float(k)
		var tw := w - 2.0 * inset
		if tw < 4.0:
			break
		c.draw_rect(Rect2(x + inset, y - th, tw, th), lg["f"])
		c.draw_rect(Rect2(x + inset + tw - 2.0, y - th, 2.0, th), lg["d"])
		c.draw_rect(Rect2(x + inset, y - th, tw, 1.0), lg["r"])
		y -= th


func _prop(
	c: CanvasItem, kind: String, x: float, top: float, lg: Dictionary, h: int, t: float
) -> void:
	match kind:
		"grass":
			_column(c, x, top, 9 + 3 * (h % 4), 2, lg["p"], h, t)
			_column(c, x + 3.0, top, 12 + 3 * ((h >> 3) % 3), 2, lg["p"], h + 1, t)
			_column(c, x + 6.0, top, 6 + 3 * ((h >> 5) % 3), 2, lg["p"], h + 2, t)
		"kelp":
			_column(c, x, top, 36 + 12 * (h % 5), 2, lg["p"], h, t, 9)
			_column(c, x + 9.0, top, 24 + 9 * ((h >> 4) % 5), 2, lg["p"], h + 3, t, 9)
		"basalt":
			for k in 3:
				var hh := 6.0 + 4.0 * float((h >> (k * 3)) % 4)
				var bx := x + float(k * 4)
				c.draw_rect(Rect2(bx, top - hh, 4.0, hh), lg["f"])
				c.draw_rect(Rect2(bx, top - hh, 4.0, 1.0), lg["r"])
		"ripples":
			for k in 3:
				c.draw_rect(Rect2(x + float(k * 6), top + 4.0 + float(k % 2) * 2.0, 4, 1), lg["r"])
		"ledge":
			var w := 10.0 + 2.0 * float(h % 5)
			c.draw_rect(Rect2(x, top - 4.0, w, 4.0), lg["f"])
			c.draw_rect(Rect2(x, top - 4.0, w, 1.0), lg["r"])
			c.draw_rect(Rect2(x + w - 4.0, top - 2.0, 4.0, 2.0), lg["d"])
		"cave":
			stamp(c, PROPS["cave"], x, top + 9.0, lg)
		_:
			if PROPS.has(kind):
				stamp(c, PROPS[kind], x, top - 1.0, lg)


## A swaying plant `tall` px high from the floor at `top`: a `w` px stalk in 3-row segments,
## each leaning whole pixels further with the sway, a drooping 4 px blade every `blade` rows on
## alternating sides (none when `blade` is 0).
static func _column(
	c: CanvasItem,
	x: float,
	top: float,
	tall: int,
	w: int,
	col: Color,
	h: int,
	t: float,
	blade: int = 0
) -> void:
	var segs := maxi(tall / 3, 1)
	var phase := float(h % 17) * 0.37
	var lean := sin(t * 1.2 + phase)
	for k in segs:
		var dx := roundf(lean * float(k) / float(segs) * 3.0)
		var y := top - float((k + 1) * 3)
		c.draw_rect(Rect2(x + dx, y, float(w), 3.0), col)
		if blade > 0 and k > 0 and (k * 3) % blade == 0:
			var left := (k * 3 / blade) % 2 == 0
			var bx := x + dx - 4.0 if left else x + dx + float(w)
			c.draw_rect(Rect2(bx, y, 4.0, 1.0), col)
			c.draw_rect(Rect2(bx + (0.0 if left else 2.0), y + 1.0, 2.0, 1.0), col)


## The map's landmarks in sight as set pieces on the floor (the lighthouse on its breakwater at
## the surface).
func _paint_landmarks(
	c: CanvasItem, sc: FishingScenery, cam_m: float, shown: Array[Dictionary], edge_px: float
) -> void:
	if not world.has_method("landmarks"):
		return
	var view_m := float(FishingScenery.W) / FishingScenery.PX_PER_M
	for lm: Dictionary in world.call("landmarks", cam_m - 80.0, cam_m + view_m + 80.0):
		var sx := roundf(FishingScenery.screen_x(float(lm["x_m"]), cam_m))
		if sx >= edge_px:
			continue
		var kind := str(lm["kind"])
		if kind == "lighthouse":
			_lighthouse(c, sx, float(FishingScenery.SURF_Y))
			continue
		var top := top_at(shown, clampf(sx, 0.0, 639.0))
		if is_inf(top):
			continue
		var band := FishingScenery.band_at(sc.depth_of_y(top - 1.0 - float(SLIVER_ROWS)))
		var lg := legend(band)
		match kind:
			"wreck":
				_wreck(c, sx, top, lg)
			"reef_arch":
				_arch(c, sx, top, lg)
			"whale_bones":
				_bones(c, sx, top, lg)


## The harbour lighthouse on its breakwater, the surface on row `surf`: slate blocks with a
## wood top straddling the surface, a sage tower stepping in as it rises with two brass bands, a
## slate gallery, the foam lamp and a slate roof.
static func _lighthouse(c: CanvasItem, cx: float, surf: float) -> void:
	c.draw_rect(Rect2(cx - 22.0, surf - 3.0, 44.0, 6.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 22.0, surf - 3.0, 44.0, 1.0), FishingPalette.WOOD)
	for k in 3:
		c.draw_rect(Rect2(cx - 18.0 + 14.0 * float(k), surf - 1.0, 2.0, 2.0), FishingPalette.WOOD)
	var y := surf - 3.0
	for k in 3:
		var w := 10.0 - 2.0 * float(k)
		c.draw_rect(Rect2(cx - w * 0.5, y - 10.0, w, 10.0), FishingPalette.SAGE)
		if k < 2:
			c.draw_rect(Rect2(cx - w * 0.5, y - 7.0, w, 3.0), FishingPalette.ACCENT)
		y -= 10.0
	c.draw_rect(Rect2(cx - 6.0, y - 2.0, 12.0, 2.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 2.0, y - 6.0, 4.0, 4.0), FishingPalette.FOAM)
	c.draw_rect(Rect2(cx - 3.0, y - 6.0, 1.0, 4.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx + 2.0, y - 6.0, 1.0, 4.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 4.0, y - 8.0, 8.0, 2.0), FishingPalette.SLATE)
	c.draw_rect(Rect2(cx - 2.0, y - 10.0, 4.0, 2.0), FishingPalette.SLATE)


## The old wreck lying level, half sunk into the floor at `top`: a long hull with a stepped bow
## and a broken stern, a deckhouse with dark windows, two snapped masts, a gash showing water.
static func _wreck(c: CanvasItem, cx: float, top: float, lg: Dictionary) -> void:
	var x := cx - 56.0
	var deck := top - 18.0
	c.draw_rect(Rect2(x, deck, 100.0, 24.0), lg["f"])
	for k in 4:
		c.draw_rect(
			Rect2(
				x + 100.0 + 2.0 * float(k), deck + 2.0 + 4.0 * float(k), 2.0, 22.0 - 4.0 * float(k)
			),
			lg["f"]
		)
	c.draw_rect(Rect2(x - 4.0, deck + 6.0, 4.0, 18.0), lg["f"])
	c.draw_rect(Rect2(x, deck, 100.0, 2.0), lg["r"])
	c.draw_rect(Rect2(x, deck + 10.0, 108.0, 2.0), lg["d"])
	c.draw_rect(Rect2(x + 58.0, deck - 12.0, 24.0, 12.0), lg["f"])
	c.draw_rect(Rect2(x + 58.0, deck - 12.0, 24.0, 2.0), lg["r"])
	for k in 3:
		c.draw_rect(Rect2(x + 61.0 + 7.0 * float(k), deck - 7.0, 4.0, 3.0), lg["w"])
	c.draw_rect(Rect2(x + 24.0, deck - 30.0, 3.0, 30.0), lg["d"])
	c.draw_rect(Rect2(x + 21.0, deck - 24.0, 9.0, 2.0), lg["d"])
	c.draw_rect(Rect2(x + 88.0, deck - 16.0, 3.0, 16.0), lg["d"])
	c.draw_rect(Rect2(x + 34.0, deck + 4.0, 10.0, 6.0), lg["w"])
	c.draw_rect(Rect2(x + 38.0, deck + 10.0, 4.0, 4.0), lg["w"])
	for k in 5:
		c.draw_rect(Rect2(x + 8.0 + 9.0 * float(k), deck + 4.0, 2.0, 2.0), lg["w"])


## The great reef arch on the floor at `top`: two stepped pillars and a lintel with a lit top,
## coral heads crowning it.
static func _arch(c: CanvasItem, cx: float, top: float, lg: Dictionary) -> void:
	var x := cx - 34.0
	c.draw_rect(Rect2(x, top - 34.0, 68.0, 12.0), lg["f"])
	c.draw_rect(Rect2(x + 4.0, top - 38.0, 60.0, 4.0), lg["f"])
	c.draw_rect(Rect2(x + 4.0, top - 38.0, 60.0, 1.0), lg["r"])
	c.draw_rect(Rect2(x, top - 34.0, 4.0, 1.0), lg["r"])
	c.draw_rect(Rect2(x + 64.0, top - 34.0, 4.0, 1.0), lg["r"])
	for side in 2:
		var px := x + (0.0 if side == 0 else 52.0)
		c.draw_rect(Rect2(px, top - 22.0, 16.0, 22.0), lg["f"])
		c.draw_rect(Rect2(px + (12.0 if side == 0 else 0.0), top - 22.0, 4.0, 22.0), lg["d"])
	c.draw_rect(Rect2(x + 16.0, top - 22.0, 36.0, 2.0), lg["d"])
	stamp(c, PROPS["fan"], x + 6.0, top - 39.0, lg)
	stamp(c, PROPS["brain"], x + 30.0, top - 39.0, lg)
	stamp(c, PROPS["branch"], x + 48.0, top - 39.0, lg)


## The whale's bones on the floor at `top`: a skull block, a spine and ribs falling off in height.
static func _bones(c: CanvasItem, cx: float, top: float, lg: Dictionary) -> void:
	var x := cx - 40.0
	c.draw_rect(Rect2(x, top - 10.0, 14.0, 10.0), lg["b"])
	c.draw_rect(Rect2(x + 2.0, top - 6.0, 4.0, 3.0), lg["w"])
	c.draw_rect(Rect2(x + 14.0, top - 4.0, 66.0, 2.0), lg["b"])
	for k in 9:
		var rh := 16.0 - 1.5 * float(k)
		var rx := x + 18.0 + 7.0 * float(k)
		c.draw_rect(Rect2(rx, top - 4.0 - roundf(rh), 2.0, roundf(rh)), lg["b"])
		c.draw_rect(Rect2(rx + 2.0, top - 4.0 - roundf(rh), 2.0, 2.0), lg["b"])
