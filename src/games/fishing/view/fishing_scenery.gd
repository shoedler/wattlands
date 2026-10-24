class_name FishingScenery
extends RefCounted
## The code-drawn ocean, side view, in art pixels of the 640 x 360 view, in big light flat
## fields with hard straight edges: one sky colour with a few flat cloud slabs drifting in
## parallax, haze islands and the harbour town on the horizon, the water column in four flat
## bands that step darker only in the deep (haze at the top, surface teal, then upper and mid
## teal far out), the sea floor from FishingWorld's profile in even 24 px runs (sage under a
## foam rim in the light water; under the dark water a deep-teal floor below an abyss line), the
## quay and the pier at the dock and, past the roam map's end, the flat-earth edge: the ocean
## pours over a square lip in a straight foam-edged column into a void one step darker than the
## sea, landing in a foam bank. paint_back() draws everything behind the fish and boats.
## The camera is a world x (m) at the view's left edge. Depth maps to y with a square root over
## view_depth_m, the deepest floor in sight (the view eases it as the boat moves), so the floor
## always sits near the bottom: the shallows get the whole water column, and the colours, which
## follow the true depth, tell how deep the water is.

const W := 640
const H := 360
## The sea surface row and the scales: PX_PER_M across; the deepest floor in sight lands
## FLOOR_ROWS under the surface (y = SURF_Y + FLOOR_ROWS x sqrt(depth / view_depth_m)).
const SURF_Y := 118
## The far water: a FAR_ROWS band above the surface row, up to the horizon. Other riders' boats
## float on it (FishingView.FAR_ROW_PX), so boats at the same x read as side by side.
const FAR_ROWS := 4
const HORIZON_Y := SURF_Y - FAR_ROWS
const PX_PER_M := 2.0
const FLOOR_ROWS := 186
## view_depth_m's range: the shallowest water still gets this much, the abyss counts as ABYSS_M.
const VIEW_DEPTH_MIN_M := 3.0
const ABYSS_M := 700.0
## Water band tops (m), one FishingPalette.SEA colour each: the shallows, the reef and the shelf
## stay in the two light bands; only the deep and the abyss step darker.
const WATER_STEPS_M: Array[float] = [0.0, 40.0, 200.0, 500.0]
## The floor's colour and its 2-row top line per water band (WATER_STEPS_M): sage under a foam
## rim (top-lit) in the light water, a deep-teal floor under an abyss line in the dark water.
const FLOOR_BANDS: Array[Color] = [
	FishingPalette.SAGE,
	FishingPalette.SAGE,
	FishingPalette.DEEP,
	FishingPalette.DEEP,
]
const RIM_BANDS: Array[Color] = [
	FishingPalette.FOAM,
	FishingPalette.FOAM,
	FishingPalette.ABYSS,
	FishingPalette.ABYSS,
]
## The floor is drawn in world-fixed runs this wide, each flat, its top on an even row.
const STEP_PX := 24
const RIM_ROWS := 2
## Cloud layers: parallax factor, drift (px/s), spacing (px), rows (top, bottom); all below the
## HUD's top panels.
const CLOUD_LAYERS: Array = [
	[0.02, 0.6, 340.0, 60, 72],
	[0.05, 1.1, 420.0, 76, 88],
	[0.1, 1.8, 520.0, 92, 104],
]
## Haze islands on the horizon: [factor, spacing px].
const ISLAND_LAYERS: Array = [[0.06, 460.0], [0.16, 700.0]]
## The town sits this far right of the dock at camera 0, scrolling at TOWN_FACTOR.
const TOWN_FACTOR := 0.3
const TOWN_X0 := 24.0
## The pier (world m, its left end) and the quay's top row above the surface.
const PIER_X_M := 6.0
const QUAY_TOP := 6
## The waterfall: the column's width and its lit foam edge (px), the lip's two square steps
## (width ahead of the edge per step, 2 rows each), and the row where it lands in a foam bank of
## three slabs spreading out into the void (reach beyond the column, top first).
const FALL_W := 22
const FALL_EDGE_W := 4
## The column's shaded inner side (px), against the sea.
const FALL_SIDE_W := 2
const FALL_LIP: Array[int] = [10, 4]
const FALL_LAND_Y := 298
const FALL_BANK: Array[int] = [16, 36, 64]

var world: FishingWorld = null
## The depth the floor rows stand for (m): see the class comment and target_view_depth().
var view_depth_m: float = 40.0


## Screen y of `depth_m` below the surface (INF stays INF).
func y_of_depth(depth_m: float) -> float:
	if is_inf(depth_m):
		return INF
	return float(SURF_Y) + float(FLOOR_ROWS) * sqrt(maxf(depth_m, 0.0) / view_depth_m)


## Depth (m) at screen row `y` (0 above the surface).
func depth_of_y(y: float) -> float:
	var u := maxf(y - float(SURF_Y), 0.0) / float(FLOOR_ROWS)
	return u * u * view_depth_m


## The view depth to ease toward for camera `cam_m`: the deepest floor in sight (ABYSS_M where
## the floor drops away), at least VIEW_DEPTH_MIN_M.
func target_view_depth(cam_m: float) -> float:
	if world == null:
		return view_depth_m
	var deepest := VIEW_DEPTH_MIN_M
	for d in world.sample_floor(cam_m, cam_m + float(W) / PX_PER_M, 17):
		deepest = maxf(deepest, ABYSS_M if is_inf(d) else d)
	return minf(deepest, ABYSS_M)


## Screen x of world `x_m` for camera `cam_m` (the world x at the left edge).
static func screen_x(x_m: float, cam_m: float) -> float:
	return (x_m - cam_m) * PX_PER_M


## The water band (FishingPalette.SEA index) at `depth_m` (0 above the surface).
static func band_at(depth_m: float) -> int:
	var i := 0
	for k in WATER_STEPS_M.size():
		if depth_m >= WATER_STEPS_M[k]:
			i = k
	return i


## The water colour at `depth_m`.
static func water_at(depth_m: float) -> Color:
	return FishingPalette.SEA[band_at(depth_m)]


## The floor colour at `depth_m` (its rim's colour with `rim`).
static func floor_at(depth_m: float, rim: bool = false) -> Color:
	return (RIM_BANDS if rim else FLOOR_BANDS)[band_at(depth_m)]


## The surface's lift at world pixel `wx` and time `t`: 1 on a swell, else 0 (the boats bob).
static func wave(wx: float, t: float) -> int:
	var v := sin(wx * 0.09 + t * 1.3) + 0.6 * sin(wx * 0.23 - t * 2.1)
	return 1 if v > 1.0 else 0


## The roam map's edge x (m) where the ocean pours off (INF on the endless map).
func edge_m() -> float:
	return world.length_m() if world != null else INF


## Everything behind the fish and boats, for camera `cam_m` at time `t` (s).
func paint_back(c: CanvasItem, cam_m: float, t: float) -> void:
	var cam_px := roundf(cam_m * PX_PER_M)
	c.draw_rect(Rect2(0, 0, W, HORIZON_Y), FishingPalette.SKY)
	_paint_clouds(c, cam_px, t)
	_paint_islands(c, cam_m)
	_paint_town(c, cam_m, t)
	_paint_water(c)
	_paint_floor(c, cam_m, cam_px)
	_paint_dock(c, cam_m)
	_paint_edge(c, cam_m)


## A small integer hash (view decoration only; never game state).
static func hash2(a: int, b: int) -> int:
	var h := (a * 374761393 + b * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return h ^ (h >> 16)


## The water bands from the horizon (the far water is the top band), each a flat field with a
## straight top; `steps` darker past the edge.
func _paint_water(c: CanvasItem, x0: float = 0.0, steps: int = 0) -> void:
	var w := float(W) - x0
	c.draw_rect(Rect2(x0, HORIZON_Y, w, H - HORIZON_Y), FishingPalette.SEA[0])
	for k in range(0 if steps > 0 else 1, WATER_STEPS_M.size()):
		var y := float(SURF_Y) if k == 0 else roundf(y_of_depth(WATER_STEPS_M[k]))
		if y >= float(H):
			break
		c.draw_rect(
			Rect2(x0, y, w, float(H) - y), FishingPalette.darker(FishingPalette.SEA[k], steps)
		)


func _paint_clouds(c: CanvasItem, cam_px: float, t: float) -> void:
	for li in CLOUD_LAYERS.size():
		var layer: Array = CLOUD_LAYERS[li]
		var off := roundf(cam_px * float(layer[0]) + t * float(layer[1]))
		var spacing := float(layer[2])
		var k0 := floori(off / spacing) - 1
		for k in range(k0, k0 + ceili(float(W) / spacing) + 3):
			var h := hash2(k, li + 11)
			if h % 2 == 0:
				continue
			var x0 := float(k) * spacing + float((h >> 7) % 120) - off
			var y0 := int(layer[3]) + 2 * (((h >> 11) % maxi(int(layer[4]) - int(layer[3]), 2)) / 2)
			_cloud(c, x0, y0, 32 + 8 * ((h >> 3) % 9), h)


## One flat cloud: a haze underside two rows deep, foam tiers stepping in above it by 2 or 4
## px per two rows; its bottom on row `y0`.
func _cloud(c: CanvasItem, x0: float, y0: int, w: int, h: int) -> void:
	c.draw_rect(Rect2(x0, y0 - 1, w, 2), FishingPalette.HAZE)
	var x := x0
	var ww := float(w)
	var tiers := 1 + (h >> 5) % 3
	for j in tiers:
		var cut_l := 2.0 * float(1 + (hash2(h, j * 2) % 2)) * (2.0 if j > 0 else 1.0)
		var cut_r := 2.0 * float(1 + (hash2(h, j * 2 + 1) % 2)) * (2.0 if j > 0 else 1.0)
		x += cut_l
		ww -= cut_l + cut_r
		if ww < 6.0:
			return
		c.draw_rect(Rect2(x, y0 - 3 - 2 * j, ww, 2), FishingPalette.FOAM)


## Haze islands: flat-topped tiers stepping in by 2 px per 2 rows, standing on the horizon.
func _paint_islands(c: CanvasItem, cam_m: float) -> void:
	var ex := screen_x(edge_m(), cam_m)
	for li in ISLAND_LAYERS.size():
		var layer: Array = ISLAND_LAYERS[li]
		var off := roundf(cam_m * PX_PER_M * float(layer[0]))
		var spacing := float(layer[1])
		var k0 := floori(off / spacing) - 1
		for k in range(k0, k0 + ceili(float(W) / spacing) + 3):
			if k < 1:
				continue
			var h := hash2(k, li + 41)
			if h % 3 == 0:
				continue
			var x := float(k) * spacing + float((h >> 9) % 200) - off
			var w := 24.0 + 8.0 * float(h % 9)
			for j in 1 + (h >> 5) % (3 + li):
				if w < 6.0:
					break
				var right := minf(x + w, ex)
				if right > x:
					c.draw_rect(
						Rect2(x, HORIZON_Y - 2 * (j + 1), right - x, 2), FishingPalette.HAZE
					)
				var cut := 2.0 * float(1 + hash2(h, j) % 3)
				x += cut
				w -= cut + 2.0 * float(1 + hash2(h, j + 7) % 3)


func _paint_town(c: CanvasItem, cam_m: float, t: float) -> void:
	var town := FishingSprites.frame("scenery_town")
	if town == null:
		return
	var x := roundf(TOWN_X0 - cam_m * PX_PER_M * TOWN_FACTOR)
	if x > float(W) or x + town.get_width() < 0.0:
		return
	c.draw_texture(town, Vector2(x, HORIZON_Y - town.get_height()))
	var gull := FishingSprites.frames("gull")
	if gull.is_empty():
		return
	for k in 3:
		var a := t * (0.3 + 0.08 * float(k)) + float(k) * 2.1
		var gx := screen_x(40.0 + 30.0 * float(k), cam_m) + cos(a) * 20.0
		var gy := 58.0 + float(k) * 10.0 + sin(a * 1.7) * 4.0
		var f := gull[floori(t * 2.5 + float(k)) % gull.size()]
		c.draw_texture(f, Vector2(roundf(gx), roundf(gy)))


## The floor in world-fixed STEP_PX runs from the world's profile, each flat with its top on an
## even row: a RIM_ROWS top line, then the floor colour of its top band down to the bottom.
func _paint_floor(c: CanvasItem, cam_m: float, cam_px: float) -> void:
	if world == null:
		return
	var edge_px := screen_x(edge_m(), cam_m)
	var j0 := floori(cam_px / float(STEP_PX))
	for j in range(j0, j0 + W / STEP_PX + 2):
		var sx := float(j * STEP_PX) - cam_px
		var x_m := (float(j * STEP_PX) + float(STEP_PX) * 0.5) / PX_PER_M
		var d := world.floor_depth_m(x_m)
		if is_inf(d) or sx >= edge_px:
			continue
		var y := 2.0 * floorf(y_of_depth(d) / 2.0)
		if y >= float(H):
			continue
		var right := minf(sx + float(STEP_PX), edge_px)
		var band := band_at(d)
		c.draw_rect(Rect2(sx, y, right - sx, float(H) - y), FLOOR_BANDS[band])
		c.draw_rect(Rect2(sx, y, right - sx, RIM_ROWS), RIM_BANDS[band])


## The quay left of the dock (a foam cap, a wood face, its wall sage under the water, bollards)
## and the pier.
func _paint_dock(c: CanvasItem, cam_m: float) -> void:
	var qx := roundf(screen_x(0.0, cam_m))
	if qx > 0.0:
		var top := float(SURF_Y - QUAY_TOP)
		c.draw_rect(Rect2(0, top, qx, 2), FishingPalette.FOAM)
		c.draw_rect(Rect2(0, top + 2, qx, float(QUAY_TOP) - 2.0), FishingPalette.WOOD)
		c.draw_rect(Rect2(0, SURF_Y, qx, H - SURF_Y), FishingPalette.SAGE)
		for x in range(int(qx) - 14, -1, -40):
			c.draw_rect(Rect2(x, top - 2, 2, 2), FishingPalette.SLATE)
	var pier := FishingSprites.frame("scenery_pier")
	if pier == null:
		return
	var px := roundf(screen_x(PIER_X_M, cam_m))
	if px < float(W) and px + pier.get_width() > 0.0:
		var deck := FishingSprites.anchor("scenery_pier").y
		c.draw_texture(pier, Vector2(px, SURF_Y - QUAY_TOP - deck))


## Past the edge: the void below the horizon repeats the sea's bands one step darker (the same
## haze strip on top, so the horizon runs on), and the ocean pours over a square two-step foam lip
## in a straight column (a shaded side, a haze face, a foam lit edge) that lands in a bank of foam
## slabs.
func _paint_edge(c: CanvasItem, cam_m: float) -> void:
	var ex := roundf(screen_x(edge_m(), cam_m))
	if ex >= float(W):
		return
	_paint_water(c, maxf(ex, 0.0), 1)
	var top := float(HORIZON_Y + 2 * FALL_LIP.size())
	var fw := float(FALL_W)
	c.draw_rect(Rect2(ex, top, fw - float(FALL_EDGE_W), FALL_LAND_Y - top), FishingPalette.HAZE)
	c.draw_rect(
		Rect2(ex + fw - float(FALL_EDGE_W), top, FALL_EDGE_W, FALL_LAND_Y - top),
		FishingPalette.FOAM
	)
	c.draw_rect(Rect2(ex, top, FALL_SIDE_W, FALL_LAND_Y - top), FishingPalette.UPPER)
	for k in FALL_LIP.size():
		var lead := float(FALL_LIP[k])
		c.draw_rect(Rect2(ex - lead, HORIZON_Y + 2 * k, lead + fw, 2), FishingPalette.FOAM)
	for k in FALL_BANK.size():
		var reach := float(FALL_BANK[k])
		var col := FishingPalette.FOAM if k < 2 else FishingPalette.HAZE
		c.draw_rect(Rect2(ex, FALL_LAND_Y + 2 * k, fw + reach, 2), col)
