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
const FAR_ROWS := 16
const HORIZON_Y := SURF_Y - FAR_ROWS
const PX_PER_M := 2.0
const FLOOR_ROWS := 186
## view_depth_m's range: the shallowest water still gets this much, the abyss counts as ABYSS_M.
const VIEW_DEPTH_MIN_M := 3.0
const ABYSS_M := 700.0
## Water band tops (m), one FishingPalette.SEA colour each, the same in every zone: haze just
## under the surface, then the teals stepping darker with depth. The surface itself is a 2-row
## foam line (SURFACE_ROWS), the only white band.
const WATER_STEPS_M: Array[float] = [0.0, 15.0, 120.0, 500.0]
const SURFACE_ROWS := 2
## The floor's colour and its lit 2-row top rim per band of the water just above its top row
## (WATER_STEPS_M), so every step shows its rim: the floor a step darker than that water (sage
## in the shallows), the rim a step lighter (sky over the shallows' haze, never the surface's
## foam).
const FLOOR_BANDS: Array[Color] = [
	FishingPalette.SAGE,
	FishingPalette.UPPER,
	FishingPalette.MID,
	FishingPalette.DEEP,
]
const RIM_BANDS: Array[Color] = [
	FishingPalette.SKY,
	FishingPalette.HAZE,
	FishingPalette.SURFACE,
	FishingPalette.UPPER,
]
## The floor in sight is fitted with one staircase: treads of a whole number of STEP_PX columns,
## risers of FLOOR_RISERS px, the pair whose slope matches best; when the staircase strays more
## than FLOOR_FIT_PX from the true floor (a shelf break in sight) each column takes its own row.
const FLOOR_RISERS: Array[int] = [2, 4, 6]
const FLOOR_TREADS: Array[int] = [1, 2, 3, 4, 5, 6, 8, 10, 12]
const FLOOR_FIT_PX := 6.0
## The floor is drawn in world-fixed runs this wide, each flat, its top on an even row.
const STEP_PX := 24
const RIM_ROWS := 2
## The islands' sage tiers (the rest are haze).
const ISLAND_BASE_TIERS := 2
## Cloud layers: parallax factor, drift (px/s), spacing (px), rows (top, bottom); all below the
## HUD's top panels.
const CLOUD_LAYERS: Array = [
	[0.02, 0.6, 340.0, 74, 78],
	[0.05, 1.1, 420.0, 84, 90],
]
## Haze islands on the horizon: [factor, spacing px].
const ISLAND_LAYERS: Array = [[0.06, 460.0], [0.16, 700.0]]
## The town sits this far right of the dock at camera 0, scrolling at TOWN_FACTOR.
const TOWN_FACTOR := 0.3
const TOWN_X0 := -130.0
## The pier (world m, its left end) and the quay's top row above the surface.
const PIER_X_M := 6.0
const QUAY_TOP := 6
## Past the edge: air (the sky, a haze mist band over the pool) down to the pool's surface, then
## the pool's water one step darker than the sea's bands.
const MIST_Y := 286
const POOL_Y := 300
## The waterfall: the column's width and its lit foam strip (px), the lip's two square steps
## (width ahead of the edge per step, 2 rows each) and the foam slabs where it lands in the pool
## (reach beyond the column, top first).
const FALL_W := 10
const FALL_EDGE_W := 3
const FALL_LIP: Array[int] = [6, 2]
const FALL_BANK: Array[int] = [6, 14, 24]

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


## The rows water band `k` covers on screen as Vector2(top, bottom) (the top band starts under
## the foam line; the deepest runs to the bottom).
func band_rows(k: int) -> Vector2:
	var top := float(SURF_Y + SURFACE_ROWS) if k == 0 else roundf(y_of_depth(WATER_STEPS_M[k]))
	var bottom := float(H)
	if k + 1 < WATER_STEPS_M.size():
		bottom = minf(bottom, roundf(y_of_depth(WATER_STEPS_M[k + 1])))
	return Vector2(top, bottom)


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
## straight top, and the foam surface line; `steps` darker past the edge.
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
	if steps == 0:
		c.draw_rect(Rect2(x0, SURF_Y, w, SURFACE_ROWS), FishingPalette.FOAM)


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


## Islands: flat-topped tiers stepping in by 2 px per 2 rows, standing on the horizon on a row
## of foam surf; the lowest ISLAND_BASE_TIERS are sage land, the higher ones haze.
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
					var land := (
						FishingPalette.SAGE if j < ISLAND_BASE_TIERS else FishingPalette.HAZE
					)
					c.draw_rect(Rect2(x, HORIZON_Y - 2 * (j + 1), right - x, 2), land)
					if j == 0:
						c.draw_rect(Rect2(x, HORIZON_Y - 1, right - x, 1), FishingPalette.FOAM)
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


## The floor in world-fixed STEP_PX columns from the world's profile, as one even staircase
## (floor_rows()): a RIM_ROWS top line, then the floor colour of its band down to the bottom.
func _paint_floor(c: CanvasItem, cam_m: float, cam_px: float) -> void:
	if world == null:
		return
	var edge_px := screen_x(edge_m(), cam_m)
	var cols := floor_rows(cam_px)
	for col: Vector3 in cols:
		var sx := col.x
		var y := col.y
		if sx >= edge_px or y >= float(H):
			continue
		var right := minf(sx + float(STEP_PX), edge_px)
		var band := int(col.z)
		c.draw_rect(Rect2(sx, y, right - sx, float(H) - y), FLOOR_BANDS[band])
		c.draw_rect(Rect2(sx, y, right - sx, RIM_ROWS), RIM_BANDS[band])


## The floor columns in sight as (screen x, top row, band): staircases fitted to the true floor
## (in each, every tread the same whole number of columns and every riser the same height), the
## longest that stays within FLOOR_FIT_PX first, so a shelf break is a flat shelf and a drop.
func floor_rows(cam_px: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var wx: Array[float] = []
	var ys: Array[float] = []
	var j0 := floori(cam_px / float(STEP_PX))
	for j in range(j0, j0 + W / STEP_PX + 2):
		var x_m := (float(j * STEP_PX) + float(STEP_PX) * 0.5) / PX_PER_M
		var d := world.floor_depth_m(x_m)
		if is_inf(d):
			continue
		out.append(Vector3(float(j * STEP_PX) - cam_px, y_of_depth(d), band_at(d)))
		wx.append(float(j * STEP_PX))
		ys.append(out[-1].y)
	var i0 := 0
	var rhythm: Array[int] = []
	while i0 < out.size():
		var rows: Array[float] = []
		var i1 := out.size()
		for treads: Array[int] in [rhythm, FLOOR_TREADS]:
			if treads.is_empty():
				continue
			i1 = out.size()
			while i1 - i0 >= 3:
				var fit := _fit(wx.slice(i0, i1), ys.slice(i0, i1), treads)
				if not fit.is_empty():
					rows.assign(fit["rows"])
					if rhythm.is_empty() and int(fit["tread"]) > 0:
						rhythm = [int(fit["tread"])]
					break
				i1 -= 1
			if not rows.is_empty():
				break
		if rows.is_empty():
			i1 = i0 + 1
			rows = [2.0 * floorf(ys[i0] / 2.0)]
		for k in rows.size():
			out[i0 + k].y = rows[k]
			out[i0 + k].z = band_at(depth_of_y(rows[k] - 1.0))
		i0 = i1
	return out


## The staircase rows for columns at world px `wx` (left edges) with true rows `ys`, or [] when
## none fits.
static func _fit_stairs(wx: Array[float], ys: Array[float]) -> Array[float]:
	var fit := _fit(wx, ys, FLOOR_TREADS)
	var rows: Array[float] = []
	if not fit.is_empty():
		rows.assign(fit["rows"])
	return rows


## _fit_stairs() with the treads (in STEP_PX columns) it may pick: {"rows", "tread"} (tread 0
## for a flat run) or {}.
## floor_rows() keeps the first staircase's tread for the rest of the view where it fits, so the
## floor keeps one rhythm.
static func _fit(wx: Array[float], ys: Array[float], treads: Array[int]) -> Dictionary:
	var n := wx.size()
	if n < 3 or wx[-1] - wx[0] != float((n - 1) * STEP_PX):
		return {}
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += wx[i]
		my += ys[i]
	mx /= float(n)
	my /= float(n)
	var sxy := 0.0
	var sxx := 0.0
	for i in n:
		sxy += (wx[i] - mx) * (ys[i] - my)
		sxx += (wx[i] - mx) * (wx[i] - mx)
	var slope := sxy / sxx if sxx > 0.0 else 0.0
	var best_r := 0
	var best_l := treads[0]
	var best_err := absf(slope)
	for r in FLOOR_RISERS:
		for t in treads:
			var err := absf(float(r) / float(t * STEP_PX) - absf(slope))
			if err < best_err:
				best_err = err
				best_r = r
				best_l = t
	var tread := float(best_l * STEP_PX)
	var dir := signf(slope)
	var k0 := floori(wx[0] / tread)
	var y0 := 2.0 * roundf((my + slope * ((float(k0) + 0.5) * tread - mx)) / 2.0)
	var rows: Array[float] = []
	for i in n:
		var k := floori(wx[i] / tread)
		var y := y0 + dir * float(best_r * (k - k0))
		if absf(y - ys[i]) > FLOOR_FIT_PX:
			return {}
		rows.append(y)
	return {"rows": rows, "tread": best_l if best_r > 0 else 0}


## The quay left of the dock (a foam cap and a wood face on posts going into the water, bollards
## on the cap) and the pier.
func _paint_dock(c: CanvasItem, cam_m: float) -> void:
	var qx := roundf(screen_x(0.0, cam_m))
	if qx > 0.0:
		var top := float(SURF_Y - QUAY_TOP)
		c.draw_rect(Rect2(0, top, qx, 2), FishingPalette.FOAM)
		c.draw_rect(Rect2(0, top + 2, qx, 2), FishingPalette.WOOD)
		for x in range(int(qx) - 6, -1, -16):
			c.draw_rect(Rect2(x, top + 4, 2, 2), FishingPalette.SLATE)
			c.draw_rect(Rect2(x, SURF_Y + SURFACE_ROWS, 2, 8), FishingPalette.UPPER)
		for x in range(int(qx) - 14, -1, -40):
			c.draw_rect(Rect2(x, top - 2, 2, 2), FishingPalette.SLATE)
	var pier := FishingSprites.frame("scenery_pier")
	if pier == null:
		return
	var px := roundf(screen_x(PIER_X_M, cam_m))
	if px < float(W) and px + pier.get_width() > 0.0:
		var deck := FishingSprites.anchor("scenery_pier").y
		c.draw_texture(pier, Vector2(px, SURF_Y - QUAY_TOP - deck))


## Past the edge the ocean pours over a square two-step foam lip and drops through air (the sky
## running on down, a haze mist band) in a straight two-plane column (a haze face, a foam lit
## strip) into a pool, one step darker than the sea, with foam slabs where it lands.
func _paint_edge(c: CanvasItem, cam_m: float) -> void:
	var ex := roundf(screen_x(edge_m(), cam_m))
	if ex >= float(W):
		return
	var x0 := maxf(ex, 0.0)
	var w := float(W) - x0
	c.draw_rect(Rect2(x0, HORIZON_Y, w, MIST_Y - HORIZON_Y), FishingPalette.SKY)
	c.draw_rect(Rect2(x0, MIST_Y, w, POOL_Y - MIST_Y), FishingPalette.HAZE)
	c.draw_rect(Rect2(x0, POOL_Y, w, H - POOL_Y), FishingPalette.SURFACE)
	var top := float(HORIZON_Y + 2 * FALL_LIP.size())
	var fw := float(FALL_W)
	var lit := float(FALL_EDGE_W)
	c.draw_rect(Rect2(ex, top, fw - lit, POOL_Y - top), FishingPalette.HAZE)
	c.draw_rect(Rect2(ex + fw - lit, top, lit, POOL_Y - top), FishingPalette.FOAM)
	for k in FALL_LIP.size():
		var lead := float(FALL_LIP[k])
		c.draw_rect(Rect2(ex - lead, HORIZON_Y + 2 * k, lead + fw, 2), FishingPalette.FOAM)
	for k in FALL_BANK.size():
		var reach := float(FALL_BANK[k])
		c.draw_rect(Rect2(ex, POOL_Y - 2 + 2 * k, fw + reach, 2), FishingPalette.FOAM)
