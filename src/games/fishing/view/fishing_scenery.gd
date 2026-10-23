class_name FishingScenery
extends RefCounted
## The code-drawn ocean, side view, in art pixels of the 640 x 360 view: flat sky bands, cloud
## banks drifting in three parallax layers, haze islands on the horizon, the harbour town and
## the pier at the dock, the water column in flat bands that darken with depth, the sea floor
## from FishingWorld's profile (a hazier ridge behind it, kelp in the shallows), the abyss where
## the floor drops away and, past the roam map's end, the flat-earth edge: the ocean pours off
## in a waterfall into the void, wrapped in mist. paint_back() draws everything behind the fish
## and boats, paint_front() the surface crests and the water veil over the boats' keels.
## The camera is a world x (m) at the view's left edge. Depth maps to y with a square root over
## view_depth_m, the deepest floor in sight (the view eases it as the boat moves), so the floor
## always sits near the bottom: the shallows get the whole water column, and the colours, which
## follow the true depth, tell how deep the water is.

const W := 640
const H := 360
## The sea surface row and the scales: PX_PER_M across; the deepest floor in sight lands
## FLOOR_ROWS under the surface (y = SURF_Y + FLOOR_ROWS x sqrt(depth / view_depth_m)).
const SURF_Y := 118
const PX_PER_M := 2.0
const FLOOR_ROWS := 186
## view_depth_m's range: the shallowest water still gets this much, the abyss counts as ABYSS_M.
const VIEW_DEPTH_MIN_M := 3.0
const ABYSS_M := 700.0
## Water band tops (m), one SEA colour each.
const WATER_STEPS_M: Array[float] = [0.0, 6.0, 18.0, 40.0, 90.0, 170.0, 300.0, 470.0]
## Sky band tops (rows): SKY_0 from 0, SKY_1, SKY_2 down to the horizon.
const SKY_ROWS: Array[int] = [0, 40, 80]
## Cloud layers: parallax factor, drift (px/s), bank spacing (px), rows (top, bottom), colour.
const CLOUD_LAYERS: Array = [
	[0.02, 0.6, 230.0, 14, 46, 1],
	[0.05, 1.1, 300.0, 30, 70, 0],
	[0.1, 1.8, 380.0, 50, 92, 0],
]
## Haze islands on the horizon: [factor, spacing px, max height, colour index (HAZE_1 / HAZE_2)].
const ISLAND_LAYERS: Array = [[0.06, 520.0, 6, 0], [0.16, 760.0, 10, 1]]
## The town sits this far right of the dock at camera 0, scrolling at TOWN_FACTOR.
const TOWN_FACTOR := 0.3
const TOWN_X0 := 24.0
## The pier (world m, its left end) and the quay's top row above the surface.
const PIER_X_M := 6.0
const QUAY_TOP := 6
## The veil over the boats' keels: rows under the surface and its alpha.
const VEIL_ROWS := 9
const VEIL_ALPHA := 0.55
## The waterfall at the edge: its widest throw (px) at the view's bottom and the streak speed.
const FALL_THROW := 70.0
const FALL_SPEED := 70.0

var world: FishingWorld = null
## The depth the floor rows stand for (m): see the class comment and target_view_depth().
var view_depth_m: float = 40.0

static var _cache: Dictionary = {}


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


## The water colour at `depth_m`.
static func water_at(depth_m: float) -> Color:
	var i := 0
	for k in WATER_STEPS_M.size():
		if depth_m >= WATER_STEPS_M[k]:
			i = k
	return FishingPalette.SEA[i]


## How far toward the water colour a fish at `depth_m` is tinted (0 near the surface).
static func fog_at(depth_m: float) -> float:
	return clampf(0.1 + sqrt(maxf(depth_m, 0.0)) / 60.0, 0.1, 0.45)


## The floor colour at `depth_m`: sand in the shallows, then two steps darker than the water.
static func floor_at(depth_m: float) -> Color:
	if depth_m < 9.0:
		return FishingPalette.SAND_1
	if depth_m < 24.0:
		return FishingPalette.SAND_2
	var c := FishingPalette.darker(water_at(depth_m), 2)
	return FishingPalette.SEA_6 if c == FishingPalette.VOID or c == FishingPalette.SEA_7 else c


## The surface's crest height at world pixel `wx` and time `t`: 1 on a crest, else 0.
static func wave(wx: float, t: float) -> int:
	var v := sin(wx * 0.09 + t * 1.3) + 0.6 * sin(wx * 0.23 - t * 2.1)
	return 1 if v > 1.0 else 0


## The roam map's edge x (m) where the ocean pours off (INF on the endless map).
func edge_m() -> float:
	return world.length_m() if world != null else INF


## Everything behind the fish and boats, for camera `cam_m` at time `t` (s).
func paint_back(c: CanvasItem, cam_m: float, t: float) -> void:
	c.draw_texture(sky_texture(), Vector2.ZERO)
	_paint_clouds(c, cam_m, t)
	_paint_islands(c, cam_m)
	_paint_town(c, cam_m, t)
	_paint_water(c)
	_paint_floor(c, cam_m, 0.75, 0.82, true)
	_paint_floor(c, cam_m, 1.0, 1.0, false)
	_paint_kelp(c, cam_m, t)
	_paint_dock(c, cam_m)
	_paint_edge(c, cam_m, t)


## The surface crests and the veil over the keels (after the boats).
func paint_front(c: CanvasItem, cam_m: float, t: float) -> void:
	var ex := screen_x(edge_m(), cam_m)
	var right := int(clampf(ex, 0.0, float(W)))
	var veil := Color(FishingPalette.SEA_1, VEIL_ALPHA)
	if right > 0:
		c.draw_rect(Rect2(0, SURF_Y + 1, right, VEIL_ROWS), veil)
	var cam_px := cam_m * PX_PER_M
	for sx in right:
		var wx := float(sx) + cam_px
		if wave(wx, t) == 1:
			c.draw_rect(Rect2(sx, SURF_Y - 1, 1, 1), FishingPalette.SEA_1)
			if wave(wx + 3.0, t) == 0:
				c.draw_rect(Rect2(sx, SURF_Y, 1, 1), FishingPalette.CLOUD)
	_paint_mist(c, ex, t)


## The sky bands with a 2-row checker step between them (cached).
static func sky_texture() -> Texture2D:
	if not _cache.has("sky"):
		var img := Image.create_empty(W, SURF_Y, false, Image.FORMAT_RGBA8)
		for y in SURF_Y:
			var band := 0
			for k in SKY_ROWS.size():
				if y >= SKY_ROWS[k]:
					band = k
			for x in W:
				var b := band
				if band + 1 < SKY_ROWS.size() and y >= SKY_ROWS[band + 1] - 2 and (x + y) % 2 == 0:
					b = band + 1
				img.set_pixel(x, y, FishingPalette.SKY[b])
		_cache["sky"] = ImageTexture.create_from_image(img)
	return _cache["sky"]


## A white checker row pair (W x 2) the water bands' steps are drawn with, modulated.
static func checker_texture() -> Texture2D:
	if not _cache.has("checker"):
		var img := Image.create_empty(W, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in 2:
			for x in W:
				if (x + y) % 2 == 0:
					img.set_pixel(x, y, Color.WHITE)
		_cache["checker"] = ImageTexture.create_from_image(img)
	return _cache["checker"]


## The water column: one flat band per WATER_STEPS_M step (by true depth), each top edge a
## 2-row checker into the band above.
func _paint_water(c: CanvasItem) -> void:
	c.draw_rect(Rect2(0, SURF_Y, W, H - SURF_Y), FishingPalette.SEA[0])
	for k in range(1, WATER_STEPS_M.size()):
		var y := roundf(y_of_depth(WATER_STEPS_M[k]))
		if y >= float(H):
			break
		c.draw_rect(Rect2(0, y, W, float(H) - y), FishingPalette.SEA[k])
		c.draw_texture(checker_texture(), Vector2(0, y - 2), FishingPalette.SEA[k])


static func clear_cache() -> void:
	_cache.clear()


## A small integer hash (view decoration only; never game state).
static func hash2(a: int, b: int) -> int:
	var h := (a * 374761393 + b * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return h ^ (h >> 16)


func _paint_clouds(c: CanvasItem, cam_m: float, t: float) -> void:
	for li in CLOUD_LAYERS.size():
		var layer: Array = CLOUD_LAYERS[li]
		var off := cam_m * PX_PER_M * float(layer[0]) - t * float(layer[1])
		var spacing := float(layer[2])
		var col := FishingPalette.SKY_2 if int(layer[5]) == 1 else FishingPalette.CLOUD
		var k0 := floori(off / spacing) - 1
		for k in range(k0, k0 + ceili(float(W) / spacing) + 3):
			var h := hash2(k, li + 11)
			if h % 2 == 0:
				continue
			var bw := 40 + h % 140
			var x0 := float(k) * spacing + float((h >> 7) % 90) - off
			var y0 := int(layer[3]) + (h >> 11) % maxi(int(layer[4]) - int(layer[3]), 1)
			_bank(c, roundf(x0), y0, bw, h, col)


## One flat cloud bank: a wide bottom row and narrower rows stepping up, bottom on row `y0`.
func _bank(c: CanvasItem, x0: float, y0: int, bw: int, h: int, col: Color) -> void:
	var x := x0
	var w := float(bw)
	var j := 0
	while w >= 6.0 and j < 9:
		c.draw_rect(Rect2(x, y0 - j, w, 1), col)
		var cut_l := float(1 + hash2(h, j * 2) % 7)
		var cut_r := float(1 + hash2(h, j * 2 + 1) % 9)
		if j == 0:
			cut_l = 2.0
			cut_r = 3.0
		x += cut_l
		w -= cut_l + cut_r
		j += 1


func _paint_islands(c: CanvasItem, cam_m: float) -> void:
	for li in ISLAND_LAYERS.size():
		var layer: Array = ISLAND_LAYERS[li]
		var off := cam_m * PX_PER_M * float(layer[0])
		var spacing := float(layer[1])
		var col := FishingPalette.HAZE_1 if int(layer[3]) == 0 else FishingPalette.HAZE_2
		var k0 := floori(off / spacing) - 1
		for k in range(k0, k0 + ceili(float(W) / spacing) + 3):
			if k < 1:
				continue
			var h := hash2(k, li + 41)
			if h % 3 == 0:
				continue
			var iw := 24 + h % 70
			var ih := 2 + (h >> 5) % int(layer[2])
			var x0 := float(k) * spacing + float((h >> 9) % 200) - off
			for i in iw:
				var u := float(i) / float(iw)
				var hh := roundi(float(ih) * sqrt(maxf(sin(PI * u), 0.0)))
				if hh > 0:
					c.draw_rect(Rect2(roundf(x0) + i, SURF_Y - hh, 1, hh), col)


func _paint_town(c: CanvasItem, cam_m: float, t: float) -> void:
	var town := FishingSprites.frame("scenery_town")
	if town == null:
		return
	var x := roundf(TOWN_X0 - cam_m * PX_PER_M * TOWN_FACTOR)
	if x > float(W) or x + town.get_width() < 0.0:
		return
	c.draw_texture(town, Vector2(x, SURF_Y - town.get_height()))
	var gull := FishingSprites.frames("gull")
	if gull.is_empty():
		return
	for k in 3:
		var a := t * (0.35 + 0.1 * float(k)) + float(k) * 2.1
		var gx := screen_x(30.0 + 25.0 * float(k), cam_m) + cos(a) * 18.0
		var gy := 62.0 + float(k) * 9.0 + sin(a * 1.7) * 5.0
		var f := gull[floori(t * 3.0 + float(k)) % gull.size()]
		c.draw_texture(f, Vector2(roundf(gx), roundf(gy)))


## The floor silhouette (or a hazier ridge behind it: `ridge`) from the world's profile; the
## ridge samples at `factor` parallax and `depth_scale` of the depth.
func _paint_floor(
	c: CanvasItem, cam_m: float, factor: float, depth_scale: float, ridge: bool
) -> void:
	if world == null:
		return
	var x0 := cam_m * factor + (37.0 if ridge else 0.0)
	var x1 := x0 + float(W) / PX_PER_M
	var n := W / 4 + 1
	var depths := world.sample_floor(x0, x1, n)
	var edge := edge_m()
	for sx in W:
		var f := float(sx) / 4.0
		var i := mini(floori(f), n - 2)
		var a := depths[i]
		var b := depths[i + 1]
		if is_inf(a) or is_inf(b):
			continue
		var d := lerpf(a, b, f - float(i)) * depth_scale
		var y := floorf(y_of_depth(d))
		if y >= float(H):
			continue
		if not ridge and cam_m + float(sx) / PX_PER_M >= edge:
			continue
		var col := floor_at(d)
		if ridge:
			col = FishingPalette.darker(water_at(d), 1)
			if col == FishingPalette.VOID:
				col = FishingPalette.SEA_7
		c.draw_rect(Rect2(sx, y, 1, float(H) - y), col)
		if not ridge and d >= 24.0:
			c.draw_rect(Rect2(sx, y, 1, 1), FishingPalette.darker(col, -1))


## Kelp stalks in the shallows and on the reef: thin swaying lines in the floor's colour.
func _paint_kelp(c: CanvasItem, cam_m: float, t: float) -> void:
	if world == null:
		return
	var m0 := floori(cam_m / 3.0)
	for m in range(m0, m0 + ceili(float(W) / PX_PER_M / 3.0) + 1):
		var h := hash2(m, 97)
		if h % 4 != 0:
			continue
		var x_m := float(m) * 3.0 + float(h % 30) / 10.0
		var zone := world.zone_at(x_m)
		if zone != "shallows" and zone != "reef":
			continue
		var d := world.floor_depth_m(x_m)
		if is_inf(d):
			continue
		var base := Vector2(roundf(screen_x(x_m, cam_m)), floorf(y_of_depth(d)))
		var tall := 5 + (h >> 4) % 10
		var col := FishingPalette.darker(water_at(d), 2)
		if zone == "shallows":
			col = FishingPalette.SAND_2
		for j in tall:
			var sway := roundf(sin(t * 0.8 + float(j) * 0.5 + float(m)) * float(j) / 8.0)
			c.draw_rect(Rect2(base.x + sway, base.y - float(j), 1, 1), col)


## The quay left of the dock and the pier, both near and dark against the haze.
func _paint_dock(c: CanvasItem, cam_m: float) -> void:
	var qx := screen_x(0.0, cam_m)
	if qx > 0.0:
		var top := float(SURF_Y - QUAY_TOP)
		c.draw_rect(Rect2(0, top, qx, float(H) - top), FishingPalette.HAZE_2)
		c.draw_rect(Rect2(0, top, qx, 1), FishingPalette.CLOUD)
		c.draw_rect(Rect2(0, top + 1, qx, 1), FishingPalette.SKY_0)
		for y in range(int(top) + 6, H, 6):
			c.draw_rect(Rect2(0, y, qx, 1), FishingPalette.HAZE_1)
		for x in range(int(qx) - 14, -1, -40):
			c.draw_rect(Rect2(x, top - 3, 3, 3), FishingPalette.WOOD_3)
		c.draw_rect(Rect2(qx - 1, top, 1, float(H) - top), FishingPalette.SEA_3)
	var pier := FishingSprites.frame("scenery_pier")
	if pier == null:
		return
	var px := roundf(screen_x(PIER_X_M, cam_m))
	if px < float(W) and px + pier.get_width() > 0.0:
		var deck := FishingSprites.anchor("scenery_pier").y
		c.draw_texture(pier, Vector2(px, SURF_Y - 4 - deck))


## Past the edge: the sky runs on down into the void (with a few stars) and the ocean pours off.
func _paint_edge(c: CanvasItem, cam_m: float, t: float) -> void:
	var ex := screen_x(edge_m(), cam_m)
	if ex >= float(W):
		return
	var x0 := maxf(roundf(ex), 0.0)
	var ramp: Array[Color] = [
		FishingPalette.SKY_2,
		FishingPalette.HAZE_1,
		FishingPalette.HAZE_2,
		FishingPalette.SEA_3,
		FishingPalette.SEA_5,
		FishingPalette.SEA_7,
		FishingPalette.VOID,
	]
	var rows: Array[int] = [0, 6, 14, 26, 44, 70, 100]
	for i in ramp.size():
		var y := SURF_Y + rows[i]
		c.draw_rect(Rect2(x0, y, float(W) - x0, H - y), ramp[i])
	for k in 40:
		var h := hash2(k, 5)
		var sx := x0 + float(h % 640)
		var sy := float(SURF_Y + 60 + (h >> 10) % (H - SURF_Y - 60))
		if sx < float(W) and (floori(t * 0.7) + k) % 9 != 0:
			c.draw_rect(Rect2(sx, sy, 1, 1), FishingPalette.STEEL)
	# The falling sheet: from the lip (ex, SURF_Y) its front edge throws out with the fall.
	for y in range(SURF_Y, H):
		var fall := float(y - SURF_Y)
		var front := ex + 4.0 + minf(sqrt(fall) * 5.0, FALL_THROW)
		var back := ex + minf(sqrt(fall) * 2.6, FALL_THROW * 0.6)
		if front <= 0.0 or back >= float(W):
			continue
		c.draw_rect(
			Rect2(roundf(back), y, maxf(roundf(front) - roundf(back), 1.0), 1), _fall_col(fall)
		)
		for s in 7:
			var sx := roundf(lerpf(back, front, (float(s) + 0.5) / 7.0))
			var ph := int(fall - t * FALL_SPEED * (1.0 + 0.15 * float(s))) + s * 13
			if posmod(ph, 17) < 3:
				c.draw_rect(Rect2(sx, y, 1, 1), FishingPalette.CLOUD)


static func _fall_col(fall: float) -> Color:
	if fall < 30.0:
		return FishingPalette.SEA_1
	if fall < 110.0:
		return FishingPalette.SEA_2
	return FishingPalette.SEA_3


## Mist round the lip and along the fall: flat puffs in an ordered dither, drifting.
func _paint_mist(c: CanvasItem, ex: float, t: float) -> void:
	if ex >= float(W) + 30.0 or ex < -60.0:
		return
	for k in 12:
		var h := hash2(k, 77)
		var cx := ex - 10.0 + float(h % 70) + sin(t * 0.5 + float(k)) * 4.0
		var cy := float(SURF_Y - 4 + (h >> 6) % 120) - fmod(t * 3.0 + float(k) * 7.0, 20.0)
		var r := 3 + (h >> 12) % 6
		for dy in range(-r / 2, r / 2 + 1):
			var half := roundi(sqrt(maxf(float(r * r) - float(4 * dy * dy), 0.0)))
			for dx in range(-half, half + 1):
				var px := roundi(cx) + dx
				var py := roundi(cy) + dy
				var edge := (
					float(dx * dx) / float(maxi(half * half, 1)) + float(4 * dy * dy) / float(r * r)
				)
				if px >= 0 and px < W and DitherDissolve.visible_at(px, py, 0.35 + 0.6 * edge):
					c.draw_rect(Rect2(px, py, 1, 1), FishingPalette.CLOUD)
