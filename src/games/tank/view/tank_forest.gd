class_name TankForest
extends RefCounted
## The v3 world around the tank (docs/games/tank.md v3 "World"): a pine forest road at night, bluer
## and greener, with a moderate tilt-shift baked into the planes (TankRig.planes: far sky and
## mountains, a misty ridge, the forest along the road, the verge, the near shoulder, the dark
## foreground; assets/tank/v3/tools_src/env_planes.gd); the road band (gravel, ruts and pebbles,
## regraded blue-green) following the relief (TankGround) with its slopes lit and its dips shaded;
## the soft near shoulder over its near rows; and the little bases (a fenced clearing with a
## bunker, a hooded lamp, crates, drums and a raised barrier; no text, no people) at the depot
## start, at gun lines where one fits, and at the free-roam start and strongpoints. Free-roam zones
## are forest variants (each zone tints the forest planes, cross-faded at their edges) and base
## clearings. Stage px; the Back layer is never mirrored.

## The night sky above the far plane on a taller canvas.
const SKY := Color(0.012, 0.03, 0.04)
const BOTTOM := Color(0.008, 0.014, 0.016)
## The road band: its texture's size, the rows above the road line it starts at, the strip's step.
const ROAD_W := 480
const ROAD_H := 48
const ROAD_TOP := 6
const STRIP_STEP := 4.0
## The relief's light: slopes facing the headlight's side lighter, the others and the dips darker.
const SLOPE_LIGHT := 2.5
const DIP_SHADE := 0.05
## Little bases: their width (art px), the depot's left end (rules px from the segment's start),
## a gun line's (rules px), and the free-roam start's metre.
const BASE_W := 236.0
const DEPOT_BASE_X := 180.0
const GUN_LINE_BASE_X := 560.0
const ROAM_START_M := 60.0
## The forest variants: zone id -> the forest planes' tint.
const ZONE_TINT := {
	TankIds.ZONE_FOREST: Color(1, 1, 1),
	TankIds.ZONE_MEADOW: Color(1.08, 1.12, 1.04),
	TankIds.ZONE_QUARRY: Color(0.98, 1.0, 1.06),
	TankIds.ZONE_VILLAGE: Color(1.1, 1.02, 0.94),
	TankIds.ZONE_LAKE: Color(0.92, 1.02, 1.14),
}
## Free roam: the zone tints cross-fade over this many metres either side of a zone's edge.
const ZONE_BLEND_M := 60.0
const ROAD_BASE := Color(0.145, 0.125, 0.1)
const ROAD_DK := Color(0.12, 0.11, 0.09)
const ROAD_SH := Color(0.06, 0.05, 0.04)
const PEBBLE := Color(0.3, 0.26, 0.2)
const RUT := Color(0.08, 0.07, 0.055)
const TUFT := Color(0.16, 0.18, 0.1)
const EARTH := Color(0.07, 0.072, 0.064)
const EARTH_HI := Color(0.13, 0.14, 0.125)
const CONC := Color(0.17, 0.185, 0.18)
const CONC_HI := Color(0.27, 0.3, 0.29)
const CONC_DK := Color(0.07, 0.08, 0.08)
const SOD := Color(0.04, 0.075, 0.055)
const SOD_HI := Color(0.09, 0.15, 0.11)
const BAG := Color(0.2, 0.2, 0.165)
const BAG_DK := Color(0.08, 0.085, 0.07)
const POST := Color(0.12, 0.1, 0.08)
const WIRE := Color(0.32, 0.35, 0.34)
const PLANK := Color(0.2, 0.16, 0.11)
const PLANK_DK := Color(0.09, 0.075, 0.055)
const DRUM := Color(0.11, 0.14, 0.12)
const DRUM_HI := Color(0.22, 0.27, 0.23)
const IRON := Color(0.1, 0.105, 0.1)
const ARM_RED := Color(0.5, 0.13, 0.09)
const ARM_WHITE := Color(0.6, 0.62, 0.58)
const LAMP := Color(1.0, 0.7, 0.34)

static var _road: Texture2D = null

# --- Planes and the road ----------------------------------------------------------------------------------


static func draw_back(ci: CanvasItem, v: TankView) -> void:
	var top := -v.y_off - 4.0
	var far_top := INF
	for p in v.rig.planes:
		if str(p["name"]) == "far":
			far_top = float(p["y0"])
	if far_top > top:
		ci.draw_rect(Rect2(0, top, v.canvas.x, minf(far_top, 600.0) - top + 1.0), SKY)
	var tint := forest_tint(v, v.game.state)
	for p in v.rig.planes:
		if str(p["layer"]) == "back":
			tile(ci, v, p, tint if str(p["name"]) in ["forest", "ridge"] else Color.WHITE)
	for p2 in v.rig.planes:
		if str(p2["layer"]) == "road":
			tile(ci, v, p2)
	road_strip(ci, v)
	for p3 in v.rig.planes:
		if str(p3["layer"]) == "near":
			tile(ci, v, p3)


static func draw_front(ci: CanvasItem, v: TankView) -> void:
	for p in v.rig.planes:
		if str(p["layer"]) == "front":
			tile(ci, v, p)
	var bottom := v.canvas.y - v.y_off + 4.0
	if bottom > TankView.BASE.y:
		ci.draw_rect(
			Rect2(0, TankView.BASE.y - 1.0, v.canvas.x, bottom - TankView.BASE.y + 1.0), BOTTOM
		)


## A plane tiled across the canvas at its parallax (scrolled by TankView.plane_x), tinted `mod`.
static func tile(ci: CanvasItem, v: TankView, p: Dictionary, mod: Color = Color.WHITE) -> void:
	var w: float = p["w"]
	var x := -fposmod(v.plane_x * TankView.S * float(p["parallax"]), w)
	var tex: Texture2D = p["tex"]
	while x < v.canvas.x:
		ci.draw_texture(tex, Vector2(roundf(x), float(p["y0"])), mod)
		x += w


## The forest planes' tint: the free-roam zone's variant (cross-faded at a zone's edge), else none.
static func forest_tint(v: TankView, state: TankState) -> Color:
	if state == null or not state.roam.active or state.roam_map == null:
		return Color.WHITE
	return forest_tint_at(state.roam_map, v.map_m)


## The forest variant's tint at map metre `m`, cross-faded over ZONE_BLEND_M either side of a zone's
## edge.
static func forest_tint_at(map: TankRoamMap, m: float) -> Color:
	var i := map.zone_index_at(m)
	if i < 0:
		return Color.WHITE
	var z: Dictionary = map.zones[i]
	var c: Color = ZONE_TINT.get(str(z["id"]), Color.WHITE)
	var from := float(z["from_m"])
	var to := float(z["to_m"])
	if i > 0 and m - from < ZONE_BLEND_M:
		var prev: Color = ZONE_TINT.get(str(map.zones[i - 1]["id"]), Color.WHITE)
		return prev.lerp(c, 0.5 + 0.5 * (m - from) / ZONE_BLEND_M)
	if i < map.zones.size() - 1 and to - m < ZONE_BLEND_M:
		var nxt: Color = ZONE_TINT.get(str(map.zones[i + 1]["id"]), Color.WHITE)
		return c.lerp(nxt, 0.5 - 0.5 * (to - m) / ZONE_BLEND_M)
	return c


## The road band as a strip following the relief: the gravel texture scrolled with the road, each
## column raised by the ground's lift, slopes facing left (the headlight's side) a little lighter,
## the others and the dips darker.
static func road_strip(ci: CanvasItem, v: TankView) -> void:
	var tex := road_tex()
	var tw := float(tex.get_width())
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var world0 := v.plane_x * TankView.S
	var x := -STRIP_STEP
	var prev_lift := v.ground.lift(x)
	while x < v.canvas.x + STRIP_STEP:
		var x1 := x + STRIP_STEP
		var l0 := prev_lift
		var l1 := v.ground.lift(x1)
		prev_lift = l1
		var c := _shade(l0, l1)
		var base := verts.size()
		var t0 := TankView.GROUND - ROAD_TOP - roundf(l0)
		var t1 := TankView.GROUND - ROAD_TOP - roundf(l1)
		verts.append_array(
			PackedVector2Array(
				[Vector2(x, t0), Vector2(x1, t1), Vector2(x1, t1 + ROAD_H), Vector2(x, t0 + ROAD_H)]
			)
		)
		var u0 := (world0 + x) / tw
		var u1 := (world0 + x1) / tw
		uvs.append_array(
			PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])
		)
		cols.append_array(PackedColorArray([c, c, c, c]))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		x = x1
	RenderingServer.canvas_item_add_triangle_array(
		ci.get_canvas_item(),
		idx,
		verts,
		cols,
		uvs,
		PackedInt32Array(),
		PackedFloat32Array(),
		tex.get_rid()
	)


static func _shade(l0: float, l1: float) -> Color:
	var slope := (l1 - l0) / STRIP_STEP
	var k := 1.0 + clampf(slope * SLOPE_LIGHT, -0.2, 0.18) - clampf(-l0 * DIP_SHADE, 0.0, 0.2)
	k += clampf(l0 * 0.02, 0.0, 0.08)
	return Color(k, k, k, 1.0)


## The road band's texture (tileable, ROAD_W x ROAD_H): night gravel with pebbles and two pairs of
## ruts, tufts along its far edge, fading in at the top and out under the near shoulder; regraded
## blue-green (the light layer warms it).
static func road_tex() -> Texture2D:
	if _road != null:
		return _road
	var img := Image.create(ROAD_W, ROAD_H, false, Image.FORMAT_RGBA8)
	for y in ROAD_H:
		for x in ROAD_W:
			var n := _noise(x, y)
			var near := clampf(float(y - 26) / float(ROAD_H - 26), 0.0, 1.0)
			var col := ROAD_BASE.lerp(ROAD_DK, n * 0.6 + near * 0.25)
			var ry := y - ROAD_TOP
			if ry in [5, 6, 12, 13] or y in [31, 32, 39]:
				col = col.lerp(RUT, 0.55 if y < 26 else 0.3)
			var h := TankDraw.hash01(float(x) * 1.37 + float(y) * 91.7)
			if h > 0.93:
				col = PEBBLE.lerp(ROAD_BASE, n)
			elif h > 0.9:
				col = ROAD_DK
			var a := clampf(float(y) / float(ROAD_TOP), 0.0, 1.0)
			a *= 1.0 - smoothstep(float(ROAD_H - 7), float(ROAD_H), float(y))
			var l := col.r * 0.3 + col.g * 0.55 + col.b * 0.15
			col = col.lerp(Color(l * 0.8, l * 0.98, l * 1.0), 0.55)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	for x2 in ROAD_W:
		var h2 := TankDraw.hash01(float(x2) * 7.31 + 3.0)
		if h2 > 0.82:
			var py := (
				ROAD_TOP + 1 + int(TankDraw.hash01(float(x2) * 2.9) * float(ROAD_H - ROAD_TOP - 12))
			)
			img.set_pixel(x2, py, PEBBLE)
			img.set_pixel(x2, py + 1, ROAD_SH)
		if h2 < 0.1:
			for k in int(2 + h2 * 30.0):
				img.set_pixel(x2, ROAD_TOP - k, TUFT if k % 2 == 0 else TUFT.darkened(0.3))
	_road = ImageTexture.create_from_image(img)
	return _road


## Seamless value noise over the road texture (0..1), tiling every ROAD_W px.
static func _noise(x: int, y: int) -> float:
	var s := 0.0
	for o: Vector2 in [Vector2(23.0, 0.9), Vector2(7.0, 0.55), Vector2(3.0, 0.3)]:
		var cells := int(float(ROAD_W) / o.x)
		var fx := float(x) / float(ROAD_W) * cells
		var i0 := floori(fx)
		var t := fx - i0
		var a := TankDraw.hash01(float(posmod(i0, cells)) * 3.3 + floorf(y / 3.0) * 17.0 + o.x)
		var b := TankDraw.hash01(float(posmod(i0 + 1, cells)) * 3.3 + floorf(y / 3.0) * 17.0 + o.x)
		s += lerpf(a, b, t * t * (3.0 - 2.0 * t)) * o.y
	return clampf(s / 1.75, 0.0, 1.0)


# --- Little bases -------------------------------------------------------------------------------------------


## The little bases on screen: their left ends (travel-frame stage x). The depot's at its start; a
## gun line's ahead where no enemy stands in front of it; free roam's at the start and at each
## strongpoint.
static func bases(v: TankView, state: TankState) -> Array[float]:
	var out: Array[float] = []
	if state.roam.active and state.roam_map != null:
		var map := state.roam_map
		var spots: Array[float] = [map.lo_m + ROAM_START_M]
		for m in map.strongpoints:
			spots.append(m)
		for m2: float in spots:
			out.append(roundf(v.sx(v.travel_x(state, m2)) - BASE_W * 0.5))
	elif state.seg.seg == TankIds.SEG_DEPOT:
		out.append(roundf(v.sx(DEPOT_BASE_X)))
	elif state.seg.seg == TankIds.SEG_GUN_LINE:
		var x0 := roundf(v.sx(GUN_LINE_BASE_X))
		var r := Rect2(x0, TankView.GROUND - 60.0, BASE_W, 60.0)
		var free := true
		for id: int in v.enemy_rects:
			if int(v.lanes.get(id, 0)) >= 1 and (v.enemy_rects[id] as Rect2).intersects(r):
				free = false
		if free:
			out.append(x0)
	var vis: Array[float] = []
	for x in out:
		if x < v.canvas.x + 20.0 and x + BASE_W > -20.0:
			vis.append(x)
	return vis


## The road line (stage y) a base at `x0` stands on: the relief at its middle, on the far edge.
static func base_ground(v: TankView, x0: float) -> float:
	return roundf(v.ground_y(x0 + BASE_W * 0.5)) - 5.0


## A little base at stage x `x0`: a cleared earth bank, a fence of posts and wire with a gate, a
## sodded concrete bunker with a dark firing slit behind sandbags, a hooded lamp on a post, crates
## under a tarp, fuel drums, the gate's red and white barrier raised.
static func draw_base(ci: CanvasItem, v: TankView, x0: float) -> void:
	var g := base_ground(v, x0)
	_bank(ci, x0, g)
	_fence(ci, x0, g, true)
	_bunker(ci, x0 + 26.0, g)
	_drums(ci, x0 + 98.0, g)
	_lamp_post(ci, x0 + 120.0, g)
	_crates(ci, x0 + 130.0, g)
	_barrier(ci, x0 + 182.0, g)
	_fence(ci, x0, g, false)


## The base's lights (stage px): the lamp and the bunker's slit.
static func base_lights(v: TankView, x0: float) -> Array[Dictionary]:
	var g := base_ground(v, x0)
	return [
		{"p": Vector2(x0 + 121.0, g - 45.0), "kind": "lamp", "g": g},
		{"p": Vector2(x0 + 58.0, g - 15.0), "kind": "slit", "g": g},
	]


static func _bank(ci: CanvasItem, x0: float, g: float) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var u := float(i) / float(n)
		var x := x0 - 14.0 + u * (BASE_W + 28.0)
		var hgt := 5.0 * sin(u * PI) + 1.5 * TankDraw.hash01(x0 * 0.1 + i)
		pts.append(Vector2(roundf(x), roundf(g + 2.0 - hgt)))
	var top := pts.duplicate()
	pts.append(Vector2(x0 + BASE_W + 14.0, g + 5.0))
	pts.append(Vector2(x0 - 14.0, g + 5.0))
	ci.draw_polygon(pts, PackedColorArray([EARTH]))
	ci.draw_polyline(top, EARTH_HI, 1.0)


static func _fence(ci: CanvasItem, x0: float, g: float, back: bool) -> void:
	var gate := Vector2(x0 + 172.0, x0 + 206.0)
	var y_base := g - (3.0 if back else -1.0)
	var col := POST.darkened(0.35) if back else POST
	var wire := Color(WIRE, 0.55) if back else WIRE
	var xs: Array[float] = []
	var x := x0
	while x <= x0 + BASE_W:
		if x < gate.x or x > gate.y:
			xs.append(x)
		x += 13.0
	if not back:
		xs = [x0, gate.x - 4.0, gate.y + 2.0, x0 + BASE_W]
	for px in xs:
		var hgt := 17.0 if back else 21.0
		ci.draw_rect(Rect2(px, y_base - hgt, 2, hgt), col)
		ci.draw_rect(Rect2(px, y_base - hgt, 1, hgt), col.lightened(0.25))
	if back:
		for k in 3:
			var wy := y_base - 5.0 - float(k) * 5.0
			for i in xs.size() - 1:
				var a := xs[i]
				var b := xs[i + 1]
				if b - a > 20.0:
					continue
				for xx in range(int(a) + 2, int(b)):
					var u := (float(xx) - a) / (b - a)
					var sag := roundf(sin(u * PI) * 1.2)
					ci.draw_rect(Rect2(xx, wy + sag, 1, 1), wire)
					if (xx + k * 3) % 6 == 0:
						ci.draw_rect(Rect2(xx, wy + sag - 1.0, 1, 1), wire)


static func _bunker(ci: CanvasItem, x: float, g: float) -> void:
	var w := 64.0
	var hgt := 22.0
	var body := PackedVector2Array(
		[Vector2(x, g), Vector2(x + 5.0, g - hgt), Vector2(x + w - 5.0, g - hgt), Vector2(x + w, g)]
	)
	ci.draw_polygon(body, PackedColorArray([CONC]))
	ci.draw_line(Vector2(x, g), Vector2(x + 5.0, g - hgt), CONC_HI, 1.0)
	ci.draw_rect(Rect2(x + w - 9.0, g - hgt, 4, hgt), CONC_DK)
	for k in 3:
		ci.draw_rect(Rect2(x + 6.0, g - 6.0 - float(k) * 6.0, w - 15.0, 1), Color(CONC_DK, 0.5))
	ci.draw_rect(Rect2(x + 1.0, g - hgt - 4.0, w - 2.0, 4), CONC_DK)
	ci.draw_rect(Rect2(x + 1.0, g - hgt - 4.0, w - 2.0, 1), CONC_HI)
	ci.draw_rect(Rect2(x + 4.0, g - hgt - 8.0, w - 8.0, 4), SOD)
	for i in int(w - 8.0):
		var h := TankDraw.hash01(x * 0.3 + float(i) * 1.7)
		if h > 0.45:
			var gh := 1.0 + roundf(h * 3.0)
			ci.draw_rect(Rect2(x + 4.0 + i, g - hgt - 8.0 - gh, 1, gh), SOD if h < 0.85 else SOD_HI)
	ci.draw_rect(Rect2(x + 20.0, g - 16.0, 26, 4), Color(0.01, 0.012, 0.012))
	ci.draw_rect(Rect2(x + 20.0, g - 17.0, 26, 1), CONC_HI)
	ci.draw_rect(Rect2(x + 22.0, g - 13.0, 22, 1), Color(0.35, 0.22, 0.1))
	for row in 2:
		var y := g - 4.0 - float(row) * 4.0
		var bx := x - 6.0 + float(row % 2) * 3.0
		while bx < x + w + 4.0 - float(row) * 8.0:
			if row == 1 and bx > x + 12.0 and bx < x + 50.0:
				bx += 7.0
				continue
			ci.draw_rect(Rect2(bx, y, 6, 4), BAG)
			ci.draw_rect(Rect2(bx, y, 6, 1), BAG.lightened(0.18))
			ci.draw_rect(Rect2(bx + 5.0, y, 1, 4), BAG_DK)
			bx += 7.0


static func _lamp_post(ci: CanvasItem, x: float, g: float) -> void:
	ci.draw_rect(Rect2(x, g - 44.0, 2, 44), IRON)
	ci.draw_rect(Rect2(x, g - 44.0, 1, 44), IRON.lightened(0.2))
	ci.draw_rect(Rect2(x - 4.0, g - 47.0, 10, 3), Color(0.04, 0.045, 0.045))
	ci.draw_rect(Rect2(x - 4.0, g - 47.0, 10, 1), IRON.lightened(0.3))
	ci.draw_rect(Rect2(x - 2.0, g - 44.0, 6, 1), LAMP)
	ci.draw_rect(Rect2(x - 2.0, g - 8.0, 6, 5), IRON)


static func _drums(ci: CanvasItem, x: float, g: float) -> void:
	for k in 2:
		var dx := x + float(k) * 7.0
		ci.draw_rect(Rect2(dx, g - 10.0, 6, 10), DRUM)
		ci.draw_rect(Rect2(dx, g - 10.0, 1, 10), DRUM_HI)
		ci.draw_rect(Rect2(dx, g - 10.0, 6, 1), DRUM_HI)
		for by: float in [0.3, 0.7]:
			ci.draw_rect(Rect2(dx, roundf(g - 10.0 * by), 6, 1), Color(0.03, 0.04, 0.035))


static func _crates(ci: CanvasItem, x: float, g: float) -> void:
	_planked(ci, Rect2(x, g - 12.0, 15, 12))
	_planked(ci, Rect2(x + 15.0, g - 10.0, 12, 10))
	_planked(ci, Rect2(x + 4.0, g - 21.0, 11, 9))
	var tarp := PackedVector2Array(
		[
			Vector2(x + 28.0, g),
			Vector2(x + 30.0, g - 15.0),
			Vector2(x + 38.0, g - 18.0),
			Vector2(x + 47.0, g - 14.0),
			Vector2(x + 49.0, g),
		]
	)
	ci.draw_polygon(tarp, PackedColorArray([Color(0.08, 0.1, 0.075)]))
	ci.draw_line(Vector2(x + 30.0, g - 15.0), Vector2(x + 38.0, g - 18.0), SOD_HI, 1.0)
	ci.draw_line(Vector2(x + 38.0, g - 18.0), Vector2(x + 39.0, g), Color(0.04, 0.05, 0.04), 1.0)


static func _planked(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, PLANK)
	var y := r.position.y + 3.0
	while y < r.end.y - 1.0:
		ci.draw_rect(Rect2(Vector2(r.position.x, y), Vector2(r.size.x, 1)), PLANK_DK)
		y += 3.0
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), PLANK.lightened(0.25))
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), PLANK_DK)
	ci.draw_rect(Rect2(Vector2(r.end.x - 1.0, r.position.y), Vector2(1, r.size.y)), PLANK_DK)


static func _barrier(ci: CanvasItem, x: float, g: float) -> void:
	ci.draw_rect(Rect2(x, g - 20.0, 3, 21), IRON)
	ci.draw_rect(Rect2(x, g - 20.0, 1, 21), IRON.lightened(0.25))
	var pivot := Vector2(x + 1.0, g - 18.0)
	var d := Vector2.from_angle(deg_to_rad(-58.0))
	for i in 8:
		var a := pivot + d * float(i) * 5.0
		var b := pivot + d * float(i + 1) * 5.0
		ci.draw_line(a, b, ARM_RED if i % 2 == 0 else ARM_WHITE, 2.0)
	ci.draw_rect(
		Rect2((pivot - d * 6.0 - Vector2(2, 2)).round(), Vector2(4, 4)), IRON.darkened(0.4)
	)


## The base's light on the world light layer (behind the tank): the lamp, its cone and pool, the
## slit's faint glow.
static func draw_base_light(ci: CanvasItem, v: TankView, x0: float) -> void:
	for l in base_lights(v, x0):
		var p: Vector2 = l["p"]
		if str(l["kind"]) == "slit":
			TankDraw.glow_at(ci, p, 10.0, Color(1.0, 0.55, 0.25, 0.1))
			continue
		TankDraw.glow_at(ci, p, 5.0, Color(1.0, 0.86, 0.6, 0.8))
		TankDraw.glow_at(ci, p + Vector2(0, 14), 36.0, Color(LAMP.r, LAMP.g, LAMP.b, 0.24))
		TankDraw.beam(ci, p, PI * 0.5, 48.0, deg_to_rad(30.0), Color(1.0, 0.75, 0.42), 0.18)
		TankLightDraw.ground_glow(
			ci, Vector2(p.x, float(l["g"]) + 2.0), 52.0, Color(1.0, 0.68, 0.36, 0.3)
		)
