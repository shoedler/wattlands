class_name FishingMinimap
extends FishingHudControl
## The minimap strip along the top: the ocean in profile (zone colours along the surface, the
## water and the sea floor from FishingWorld.minimap, the harbour at the left, the world's edge
## at the right on the roam map; a window round the boats on the endless workout map) and one
## icon per rider at its x, in its slot colour, showing what it is doing (FishingHudModel.icon_of:
## driving, sprinting, waiting, fighting, landing, paused, away). The local rider's icon has a
## caret under it. Drawn in art pixels scaled to the rect (`ap` HUD px per art px).

## The rect in art px (FishingHud places it); rows: icons 0-9, the strip below.
const ART := Rect2i(4, 2, 412, 30)
const ICON_ROWS := 10
const CARET_ROWS := 3
## The void block at the roam map's right end (art px).
const EDGE_W := 5.0
## Endless map: the window's width (m) round the boats.
const WINDOW_M := 2400.0
const SAMPLES := 103

## The model of the last refresh (tests read it): the window, floor samples and the icons.
var x0: float = 0.0
var x1: float = 1.0
var floor_m: PackedFloat32Array = PackedFloat32Array()
var zones: Array[Dictionary] = []
## [{slot, x (0..1 along the strip), icon, local}]
var icons: Array[Dictionary] = []
var edge: bool = false
## The local view's window along the strip (0..1, from the view's camera; -1 without a view).
var window_a: float = -1.0
var window_b: float = -1.0
var _t: float = 0.0


static func make(p_game: FishingGame) -> FishingMinimap:
	var m := FishingMinimap.new()
	m.game = p_game
	m.name = "FishingMinimap"
	m.design_h = float(ART.size.y * 3)
	return m


## HUD px per art px.
func ap() -> float:
	return size.x / float(ART.size.x) if size.x > 0.0 else 3.0


func refresh() -> void:
	_t += get_process_delta_time()
	var st := game.state if game != null else null
	if st == null or st.world == null:
		return
	var w := st.world
	edge = not w.endless
	if w.endless:
		var lo := INF
		var hi := -INF
		for r in st.riders:
			lo = minf(lo, r.x_m)
			hi = maxf(hi, r.x_m)
		var mid := (lo + hi) * 0.5
		x0 = maxf(mid - WINDOW_M * 0.5, -100.0)
		x1 = x0 + maxf(WINDOW_M, hi - lo + 400.0)
	else:
		x0 = 0.0
		x1 = w.length_m()
	var mm := w.minimap(SAMPLES, x0, x1)
	floor_m = mm["floor"]
	zones.assign(mm["zones"])
	window_a = -1.0
	window_b = -1.0
	if game.has_meta(FishingView.META) and game.get_meta(FishingView.META) is FishingView:
		var cam: float = (game.get_meta(FishingView.META) as FishingView).cam_m
		var span := maxf(x1 - x0, 1.0)
		window_a = clampf((cam - x0) / span, 0.0, 1.0)
		var view_m := float(FishingScenery.W) / FishingScenery.PX_PER_M
		window_b = clampf((cam + view_m - x0) / span, 0.0, 1.0)
	icons.clear()
	var me := FishingHudModel.own_rider(game)
	for r in st.riders:
		(
			icons
			. append(
				{
					"slot": r.slot,
					"x": clampf((r.x_m - x0) / maxf(x1 - x0, 1.0), 0.0, 1.0),
					"icon": FishingHudModel.icon_of(FishingHudModel.shown_action(r)),
					"local": me != null and me.slot == r.slot,
				}
			)
		)


func _draw() -> void:
	if floor_m.is_empty():
		return
	var s := ap()
	var w := float(ART.size.x)
	var top := float(ICON_ROWS + 1)
	var h := float(ART.size.y) - top - CARET_ROWS
	var strip := Rect2(0, top * s, w * s, h * s)
	draw_rect(strip.grow(s), Color(FishingPalette.VOID, 0.55))
	draw_rect(strip, FishingPalette.SEA_1)
	var deepest := 1.0
	for d in floor_m:
		if not is_inf(d):
			deepest = maxf(deepest, d)
	var n := floor_m.size()
	for i in int(w):
		var u := float(i) / maxf(w - 1.0, 1.0)
		var d := floor_m[mini(roundi(u * float(n - 1)), n - 1)]
		var depth_rows := h - 2.0
		if is_inf(d):
			draw_rect(
				Rect2(i * s, (top + 3.0) * s, s, (depth_rows - 1.0) * s), FishingPalette.SEA_6
			)
			continue
		var fy := 3.0 + roundf(sqrt(d / deepest) * (depth_rows - 2.0))
		draw_rect(Rect2(i * s, (top + fy) * s, s, (h - fy) * s), FishingPalette.SEA_4)
	for z in zones:
		var a := clampf((float(z["x0"]) - x0) / (x1 - x0), 0.0, 1.0)
		var b := clampf((float(z["x1"]) - x0) / (x1 - x0), 0.0, 1.0)
		var zi := FishingWorld.ZONES.find(str(z["id"]))
		var col := FishingHudDraw.ZONE_COLOURS[clampi(
			zi, 0, FishingHudDraw.ZONE_COLOURS.size() - 1
		)]
		draw_rect(Rect2(roundf(a * w) * s, top * s, roundf((b - a) * w) * s, 3.0 * s), col)
	if window_b > window_a:
		var wa := roundf(window_a * w)
		var wb := maxf(roundf(window_b * w), wa + 1.0)
		var frame := Rect2(wa * s, top * s, (wb - wa) * s, h * s)
		draw_rect(frame, Color(FishingPalette.CLOUD, 0.8), false, maxf(s * 0.67, 1.0))
	if x0 <= 0.0:
		_dock(Vector2(0.0, top) * s, s)
	if edge:
		_edge(Vector2(w - EDGE_W, top) * s, s, h)
	for e in icons:
		_icon(e, s, w)


## The harbour: a little lighthouse at the strip's left end.
func _dock(at: Vector2, s: float) -> void:
	draw_rect(Rect2(at + Vector2(1, -5) * s, Vector2(2, 5) * s), FishingPalette.CLOUD)
	draw_rect(Rect2(at + Vector2(1, -6) * s, Vector2(2, 1) * s), FishingPalette.KEY_LIGHT)


## The edge as in the view: past the map's end only the starry void, the ocean pouring over
## its lip in a falling streak.
func _edge(at: Vector2, s: float, h: float) -> void:
	draw_rect(Rect2(at, Vector2(EDGE_W, h) * s), FishingPalette.VOID)
	for k in 2:
		var star := Vector2(2.0 + float(k), 3.0 + float(k) * 5.0)
		draw_rect(Rect2(at + star * s, Vector2.ONE * s), FishingPalette.STEEL)
	draw_rect(Rect2(at, Vector2(1, h) * s), FishingPalette.SEA_2)
	for k in 3:
		var y := fposmod(_t * 8.0 + float(k) * 5.0, h - 1.0)
		draw_rect(Rect2(at + Vector2(0, y) * s, Vector2(1, 2) * s), FishingPalette.CLOUD)


func _icon(e: Dictionary, s: float, w: float) -> void:
	var look := FishingHudModel.look(game, int(e["slot"]))
	var col: Color = look["color"]
	var size := FishingSprites.size_of(str(e["icon"]))
	var cx := clampf(roundf(float(e["x"]) * w), float(size.x) * 0.5, w - float(size.x) * 0.5)
	var at := Vector2(cx - float(size.x / 2), 0.0) * s
	var k := floori(_t * 4.0)
	FishingHudDraw.sprite(self, str(e["icon"]), k, at, s, col)
	draw_rect(Rect2(Vector2(cx, float(ICON_ROWS)) * s, Vector2(1, 1) * s), col)
	if bool(e["local"]):
		var y := float(ART.size.y - CARET_ROWS) + 0.5
		var tri := PackedVector2Array(
			[Vector2(cx - 2, y + 2) * s, Vector2(cx + 2, y + 2) * s, Vector2(cx, y) * s]
		)
		draw_colored_polygon(tri, WlTheme.TEXT)
