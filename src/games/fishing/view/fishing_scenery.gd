class_name FishingScenery
extends RefCounted
## The code-drawn ocean, side view, in art pixels of the view (`w` x `h`: 640 x 360 at the base,
## any flex size the PixelViewport gives; the view calls set_size() every frame), in big light
## flat fields with hard straight edges: one sky colour with a few flat cloud slabs drifting in
## parallax, haze islands and the harbour town on the horizon, the water column in four flat
## bands that step darker only in the deep (haze at the top, surface teal, then upper and mid
## teal far out), the sea floor (FishingFloor: terraces, drops, boulders, a back ridge, each
## zone's props and the map's landmarks), the quay and the pier at the dock and, past the roam
## map's end, the flat-earth edge: the ocean pours over a square lip in a straight foam-edged
## column into a void one step darker than the sea, landing in a foam bank. paint_back() draws
## everything behind the fish and boats.
## The camera is a world x (m) at the view's left edge. Depth maps to y with a square root over
## view_depth_m, the deepest floor in sight (the view retargets it with hysteresis as the boat
## moves), so the floor always sits near the bottom: the shallows get the whole water column,
## and the colours, which follow the true depth, tell how deep the water is.

## The base art size (game.json pixel_base).
const W := 640
const H := 360
## The sea surface row (the sky keeps its height at every art size) and the scales: PX_PER_M
## across; the deepest floor in sight lands floor_rows() under the surface (y = SURF_Y +
## floor_rows() x sqrt(depth / view_depth_m)): FLOOR_ROWS at the base height, always FLOOR_GAP
## rows clear of the bottom edge.
const SURF_Y := 118
## The far water: a FAR_ROWS band above the surface row, up to the horizon. Other riders' boats
## float on it (FishingView.FAR_ROW_PX), so boats at the same x read as side by side.
const FAR_ROWS := 16
const HORIZON_Y := SURF_Y - FAR_ROWS
const PX_PER_M := 2.0
const FLOOR_ROWS := 186
const FLOOR_GAP := H - SURF_Y - FLOOR_ROWS
## view_depth_m's range: the shallowest water still gets this much, the abyss counts as ABYSS_M.
const VIEW_DEPTH_MIN_M := 3.0
## The deepest floor in sight stands for this much more depth than it is (it lands higher).
const VIEW_MARGIN := 1.1
const ABYSS_M := 700.0
## Water band tops (m), one FishingPalette.SEA colour each, the same in every zone: haze just
## under the surface, then the teals stepping darker with depth. The surface itself is a 2-row
## foam line (SURFACE_ROWS), the only white band.
const WATER_STEPS_M: Array[float] = [0.0, 15.0, 120.0, 500.0]
const SURFACE_ROWS := 2
## The floor's colour and its rim per water band (FishingFloor draws the floor).
const FLOOR_BANDS: Array[Color] = FishingFloor.FLOOR_BANDS
const RIM_BANDS: Array[Color] = FishingFloor.RIM_BANDS
## The islands' sage tiers (the rest are haze).
const ISLAND_BASE_TIERS := 2
## Cloud layers: parallax factor, drift (px/s), spacing (px), rows (top, bottom); all below the
## HUD's top panels.
const CLOUD_LAYERS: Array = [
	[0.06, 0.6, 340.0, 74, 78],
	[0.12, 1.1, 420.0, 84, 90],
]
## Haze islands on the horizon: [factor, spacing px].
const ISLAND_LAYERS: Array = [[0.18, 460.0], [0.32, 700.0]]
## The town sits this far right of the dock at camera 0, scrolling at TOWN_FACTOR.
const TOWN_FACTOR := 0.4
const TOWN_X0 := -130.0
## The pier (world m, its left end) and the quay's top row above the surface.
const PIER_X_M := 6.0
const QUAY_TOP := 6
## The edge: the column's width and its lit foam strip (px), and the lip's two square steps (width ahead
## of the edge per step, 2 rows each). The ocean (the bands and the floor) runs on to the strip, the
## wall; past it one flat sky field.
const FALL_W := 10
const FALL_EDGE_W := 3
const FALL_LIP: Array[int] = [6, 2]

## The sea floor's terraces, ridge, props and landmarks.
var floor_art: FishingFloor = FishingFloor.new()
var world: FishingWorld = null:
	set(wd):
		world = wd
		floor_art.set_world(wd)
## The depth the floor rows stand for (m): see the class comment and target_view_depth().
var view_depth_m: float = 40.0
## The drawn size (art px).
var w: int = W
var h: int = H
## Screen x spans (Vector2(left, right)) the islands keep clear of: the boats (the view sets
## it every frame), so no island stands behind a hull or a rider.
var clear_x: Array[Vector2] = []
## Screen x spans of the fish on a line (the view sets it every frame): no plant stands in one, so
## no stalk ends under a big fish's belly.
var fish_x: Array[Vector2] = []


## Sets the drawn size (art px); the height never drops under the sky plus some water.
func set_size(size: Vector2i) -> void:
	w = maxi(size.x, 1)
	h = maxi(size.y, SURF_Y + FLOOR_GAP + 16)


func size() -> Vector2i:
	return Vector2i(w, h)


## The rows the deepest floor in sight lies under the surface at this height.
func floor_rows() -> float:
	return float(h - SURF_Y - FLOOR_GAP)


## Screen y of `depth_m` below the surface (INF stays INF).
func y_of_depth(depth_m: float) -> float:
	if is_inf(depth_m):
		return INF
	return float(SURF_Y) + floor_rows() * sqrt(maxf(depth_m, 0.0) / view_depth_m)


## Depth (m) at screen row `y` (0 above the surface).
func depth_of_y(y: float) -> float:
	var u := maxf(y - float(SURF_Y), 0.0) / floor_rows()
	return u * u * view_depth_m


## The view depth for camera `cam_m`: the deepest drawn floor in sight (FishingFloor's
## terraces; ABYSS_M where the floor drops away) times VIEW_MARGIN, so the floor stands clear of
## the bottom HUD, at least VIEW_DEPTH_MIN_M.
func target_view_depth(cam_m: float) -> float:
	if world == null:
		return view_depth_m
	var px := cam_m * PX_PER_M
	var deepest := floor_art.deepest_in(px, px + float(w))
	return clampf(deepest * VIEW_MARGIN, VIEW_DEPTH_MIN_M, ABYSS_M)


## The drawn floor's top row at world x (INF where the floor drops away).
func floor_y(x_m: float) -> float:
	return y_of_depth(floor_art.depth_at(x_m))


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
	var bottom := float(h)
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
	c.draw_rect(Rect2(0, 0, w, HORIZON_Y), FishingPalette.SKY)
	_paint_clouds(c, cam_px, t)
	_paint_islands(c, cam_m)
	_paint_town(c, cam_m, t)
	_paint_water(c)
	floor_art.paint(c, self, cam_m, t, screen_x(edge_m(), cam_m) + float(FALL_W - FALL_EDGE_W))
	_paint_dock(c, cam_m)
	_paint_edge(c, cam_m)


## A small integer hash (view decoration only; never game state).
static func hash2(a: int, b: int) -> int:
	var hh := (a * 374761393 + b * 668265263) & 0x7FFFFFFF
	hh = ((hh ^ (hh >> 13)) * 1274126177) & 0x7FFFFFFF
	return hh ^ (hh >> 16)


## The water bands from the horizon (the far water is the top band), each a flat field with a
## straight top, and the foam surface line; `steps` darker past the edge.
func _paint_water(c: CanvasItem, x0: float = 0.0, steps: int = 0) -> void:
	var ww := float(w) - x0
	c.draw_rect(Rect2(x0, HORIZON_Y, ww, h - HORIZON_Y), FishingPalette.SEA[0])
	for k in range(0 if steps > 0 else 1, WATER_STEPS_M.size()):
		var y := float(SURF_Y) if k == 0 else roundf(y_of_depth(WATER_STEPS_M[k]))
		if y >= float(h):
			break
		c.draw_rect(
			Rect2(x0, y, ww, float(h) - y), FishingPalette.darker(FishingPalette.SEA[k], steps)
		)
	if steps == 0:
		c.draw_rect(Rect2(x0, SURF_Y, ww, SURFACE_ROWS), FishingPalette.FOAM)


func _paint_clouds(c: CanvasItem, cam_px: float, t: float) -> void:
	for li in CLOUD_LAYERS.size():
		var layer: Array = CLOUD_LAYERS[li]
		var off := roundf(cam_px * float(layer[0]) + t * float(layer[1]))
		var spacing := float(layer[2])
		var k0 := floori(off / spacing) - 1
		for k in range(k0, k0 + ceili(float(w) / spacing) + 3):
			var hh := hash2(k, li + 11)
			if hh % 2 == 0:
				continue
			var x0 := float(k) * spacing + float((hh >> 7) % 120) - off
			var rows := maxi(int(layer[4]) - int(layer[3]), 2)
			var y0 := int(layer[3]) + 2 * (((hh >> 11) % rows) / 2)
			_cloud(c, x0, y0, 32 + 8 * ((hh >> 3) % 9), hh)


## One flat cloud: a haze underside two rows deep, foam tiers stepping in above it by 2 or 4
## px per two rows; its bottom on row `y0`.
func _cloud(c: CanvasItem, x0: float, y0: int, cw: int, hh: int) -> void:
	c.draw_rect(Rect2(x0, y0 - 1, cw, 2), FishingPalette.HAZE)
	var x := x0
	var ww := float(cw)
	var tiers := 1 + (hh >> 5) % 3
	for j in tiers:
		var cut_l := 2.0 * float(1 + (hash2(hh, j * 2) % 2)) * (2.0 if j > 0 else 1.0)
		var cut_r := 2.0 * float(1 + (hash2(hh, j * 2 + 1) % 2)) * (2.0 if j > 0 else 1.0)
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
		for k in range(k0, k0 + ceili(float(w) / spacing) + 3):
			if k < 1:
				continue
			var hh := hash2(k, li + 41)
			if hh % 3 == 0:
				continue
			var x := float(k) * spacing + float((hh >> 9) % 200) - off
			var iw := 24.0 + 8.0 * float(hh % 9)
			if _behind_boat(x, x + iw):
				continue
			for j in 1 + (hh >> 5) % (3 + li):
				if iw < 6.0:
					break
				var right := minf(x + iw, ex)
				if right > x:
					var land := (
						FishingPalette.SAGE if j < ISLAND_BASE_TIERS else FishingPalette.HAZE
					)
					c.draw_rect(Rect2(x, HORIZON_Y - 2 * (j + 1), right - x, 2), land)
					if j == 0:
						c.draw_rect(Rect2(x, HORIZON_Y - 1, right - x, 1), FishingPalette.FOAM)
				var cut := 2.0 * float(1 + hash2(hh, j) % 3)
				x += cut
				iw -= cut + 2.0 * float(1 + hash2(hh, j + 7) % 3)


## True when screen span `x0`..`x1` overlaps a span in clear_x.
func _behind_boat(x0: float, x1: float) -> bool:
	for span in clear_x:
		if x1 > span.x and x0 < span.y:
			return true
	return false


func _paint_town(c: CanvasItem, cam_m: float, t: float) -> void:
	var town := FishingSprites.frame("scenery_town")
	if town == null:
		return
	var x := roundf(TOWN_X0 - cam_m * PX_PER_M * TOWN_FACTOR)
	if x > float(w) or x + town.get_width() < 0.0:
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
	if px < float(w) and px + pier.get_width() > 0.0:
		var deck := FishingSprites.anchor("scenery_pier").y
		c.draw_texture(pier, Vector2(px, SURF_Y - QUAY_TOP - deck))


## Past the edge the ocean pours over a square two-step foam lip: the bands and the floor run on to
## the wall, a lit foam strip standing the full height of the view (its face is the ocean itself),
## and everything past it is one flat field of sky.
func _paint_edge(c: CanvasItem, cam_m: float) -> void:
	var ex := roundf(screen_x(edge_m(), cam_m))
	if ex >= float(w):
		return
	var fw := float(FALL_W)
	var lit := float(FALL_EDGE_W)
	var wall := ex + fw - lit
	var beyond := maxf(wall + lit, 0.0)
	c.draw_rect(
		Rect2(beyond, HORIZON_Y, float(w) - beyond, float(h) - HORIZON_Y), FishingPalette.SKY
	)
	var top := float(HORIZON_Y + 2 * FALL_LIP.size())
	c.draw_rect(Rect2(wall, top, lit, float(h) - top), FishingPalette.FOAM)
	for k in FALL_LIP.size():
		var lead := float(FALL_LIP[k])
		c.draw_rect(Rect2(ex - lead, HORIZON_Y + 2 * k, lead + fw, 2), FishingPalette.FOAM)
