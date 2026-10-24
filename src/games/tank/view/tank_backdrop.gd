class_name TankBackdrop
extends Node2D
## The diorama's sprite planes in depth (brief 3 "Layout", "Depth of field"): sky 0.05, far hills 0.2,
## the near plane 0.5 (fields, village, quarry, foundry town or depot, by segment), the ground 1.0
## (the tank's plane) and, in front of everything, blurred and darkened debris 1.3. Every plane
## except the ground is pre-blurred once (TankBlur) and hazed; `front` holds the debris and is
## added by the view above the tank. All strips alternate normal and flipped copies
## (ParallaxStrip.mirror_alternate) so the edges meet. Scenery lights (burning farms, lit windows,
## foundry lamps, floodlights) are computed here as plain data from the plane's scroll.

const SKY_FACTOR := 0.05
const HILLS_FACTOR := 0.2
const NEAR_FACTOR := 0.5
const GROUND_FACTOR := 1.0
const DEBRIS_FACTOR := 1.3
## The sky sprite hangs this far down so its fire-lit cloud base meets the horizon behind the hills;
## above it SkyTop continues the sprite's top row up to y 0 (under the HUD band).
const SKY_TOP_Y := 10.0
const HILLS_BOTTOM_Y := 252.0
const NEAR_BOTTOM_Y := 292.0
const GROUND_TOP_Y := 290.0
## The debris plane's bottom: its silhouette tops reach y 286-300, just above the bottom HUD panels,
## so the blurred, darkened foreground reads as its own depth layer in front of the road.
const DEBRIS_BOTTOM_Y := 324.0
## Distant smoke columns rising off the horizon fires (a plane between the sky and the hills).
const SMOKE_FACTOR := 0.12
const SMOKE_CELL_PX := 210.0
const SMOKE_BASE_Y := 214.0
const SMOKE_RISE_PX := 200.0
const SMOKE_PUFFS := 14
const ASH_FLECKS := 40
## The columns' smoke: dense soot at the base (silhouetted on the horizon's fire glow, which lights
## its underside), thinning into lit grey as it climbs into the dark sky.
const SMOKE_TONE := Color("#141517")
const SMOKE_TOP := Color("#4a4d52")
## Ash flecks: two-pixel grey flakes, never near-white specks.
const ASH_COLOR := Color("#525456")
## Tall blurred wreckage passing close to the lens (front plane): its strip width and height.
const FRONT_JUNK_W := 2200
const FRONT_JUNK_H := 76
## Scenery lights repeat every cell of this many plane px.
const CELL_PX := 150.0
const FALLBACK_NEAR := "bg_fields_near"
const NEAR_IDS: Array[String] = [
	"bg_fields_near", "bg_village_near", "bg_quarry_near", "bg_town_near", "bg_depot_near"
]

var sky: ParallaxStrip = null
var hills: ParallaxStrip = null
var near: ParallaxStrip = null
var ground: ParallaxStrip = null
## Halos of the near plane's lights (fires, windows, lamps): drawn over the near plane, under the ground.
var scenery_lights: TankLights = null
var debris: ParallaxStrip = null
## Tall wreckage silhouettes in the foreground (stakes, a twisted girder, a broken wheel), passing now
## and then, heavily blurred and near-black, so the debris plane reads above the bottom HUD.
var junk: ParallaxStrip = null
## Holds the debris: the view parents it above the world.
var front: Node2D = null
var near_id: String = ""
## Times a near strip was swapped (tests).
var swaps: int = 0

## Seconds of animation (the smoke columns, ash and embers drift with it; cosmetic only).
var time: float = 0.0
## The horizon fires' halos and embers (additive), drawn over the sky, under the smoke and hills.
var horizon_lights: TankLights = null
var _smoke: TankPainter = null
var _scroll_x: float = 0.0
var _sky_top_color: Color = Color(0, 0, 0, 0)


func _init() -> void:
	name = "Backdrop"
	# Every near plane is blurred now, once, so a segment change later is only a texture swap.
	for id in NEAR_IDS:
		TankBlur.plane(id, "near")
	var sky_top := TankPainter.new()
	sky_top.name = "SkyTop"
	sky_top.painter = _paint_sky_top
	add_child(sky_top)
	sky = _strip("Sky", "bg_sky", "sky", SKY_FACTOR, SKY_TOP_Y, false)
	add_child(sky)
	horizon_lights = TankLights.new()
	horizon_lights.name = "HorizonLights"
	add_child(horizon_lights)
	_smoke = TankPainter.new()
	_smoke.name = "SkySmoke"
	_smoke.painter = _paint_smoke
	add_child(_smoke)
	hills = _strip("Hills", "bg_hills_far", "hills", HILLS_FACTOR, HILLS_BOTTOM_Y, true)
	add_child(hills)
	# The haze band lies over the hills and under the near plane: aerial perspective in smoke.
	var haze := TankPainter.new()
	haze.name = "HazeBand"
	haze.painter = _paint_haze
	add_child(haze)
	near = _strip("Near", FALLBACK_NEAR, "near", NEAR_FACTOR, NEAR_BOTTOM_Y, true)
	near_id = FALLBACK_NEAR
	add_child(near)
	scenery_lights = TankLights.new()
	scenery_lights.name = "SceneryLights"
	add_child(scenery_lights)
	ground = _strip("Ground", "bg_ground", "ground", GROUND_FACTOR, GROUND_TOP_Y, false)
	add_child(ground)
	front = Node2D.new()
	front.name = "Front"
	debris = _strip("Debris", "fg_debris", "debris", DEBRIS_FACTOR, DEBRIS_BOTTOM_Y, true)
	front.add_child(debris)
	junk = ParallaxStrip.new()
	junk.name = "Junk"
	junk.texture = front_junk()
	junk.factor = DEBRIS_FACTOR
	junk.position.y = DEBRIS_BOTTOM_Y + 16.0
	junk.align_bottom = true
	junk.cover_width = float(TankConst.SCREEN_W)
	junk.auto_process = false
	front.add_child(junk)


## Shows the near plane `id` (one of NEAR_IDS; anything else falls back to the fields). Blurs it on
## first use only.
func set_near(id: String) -> void:
	var want := id if NEAR_IDS.has(id) else FALLBACK_NEAR
	if want == near_id:
		return
	near_id = want
	near.texture = TankBlur.plane(want, "near")
	swaps += 1


## Advances the distant smoke, ash and horizon embers by `dt` seconds (cosmetic, view time).
func advance(dt: float) -> void:
	time += dt
	horizon_lights.begin()
	for col in smoke_columns(_scroll_x):
		var at: Vector2 = col["pos"]
		var flick := 0.85 + 0.15 * sin(time * 2.3 + float(int(col["seed"]) % 17))
		horizon_lights.add(at + Vector2(0, 4), 70.0, TankPalette.FIRE, 0.2 * flick)
		horizon_lights.add(at + Vector2(0, 6), 24.0, TankPalette.AMBER, 0.28 * flick)
		for k in 3:
			var u := fposmod(time * 0.11 + float(k) / 3.0 + float(int(col["seed"]) % 7) * 0.1, 1.0)
			var e := at + Vector2(sin(u * 9.0 + float(k)) * 6.0 + u * 18.0, -u * 90.0)
			horizon_lights.add(e, 2.0, TankPalette.AMBER, 0.7 * (1.0 - u))
	horizon_lights.end()
	_smoke.queue_redraw()


## The distant smoke columns for camera x `cam_x`: [{"pos": Vector2 (base, screen), "seed": int}],
## one in every other cell of SMOKE_CELL_PX on the SMOKE_FACTOR plane, by hash (no RNG).
static func smoke_columns(cam_x: float, width: float = 640.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scroll := cam_x * SMOKE_FACTOR
	var first := int(floor(scroll / SMOKE_CELL_PX)) - 1
	var last := int(floor((scroll + width) / SMOKE_CELL_PX)) + 1
	for cell in range(first, last + 1):
		var h := cell_hash(cell, 4517)
		if h % 3 == 0:
			continue
		var x := float(cell) * SMOKE_CELL_PX + float(h % 140) - scroll + 30.0
		out.append({"pos": Vector2(x, SMOKE_BASE_Y + float(h % 9)), "seed": h})
	return out


## Scrolls every plane to the camera x (world art px).
func set_world_x(x: float) -> void:
	_scroll_x = x
	for s: ParallaxStrip in [sky, hills, near, ground, debris, junk]:
		if s.world_x != x:
			s.world_x = x


## The near plane id for the state: the current segment's `backdrop`, or the cool-down's by outcome.
static func backdrop_id(state: TankState) -> String:
	var c := state.content
	if c == null:
		return FALLBACK_NEAR
	var segs := c.segments()
	var idx := state.seg.phase_index
	if idx < 0:
		idx = 0
	if idx >= segs.size():
		var cool: Dictionary = c.mission().get("cooldown", {})
		var key := (
			"backdrop_withdrawn"
			if state.outcome == TankIds.OUTCOME_WITHDRAWN
			else "backdrop_victory"
		)
		return str(cool.get(key, FALLBACK_NEAR))
	return str((segs[idx] as Dictionary).get("backdrop", FALLBACK_NEAR))


## Scenery lights of the near plane `id` for camera x `cam_x`: [{"pos": Vector2 (screen), "radius":
## float, "color": Color, "intensity": float, "fire": bool, "seed": int}]. The lights are the ones
## painted into the strip (strip_lights: its lit windows, lamps and burning houses), placed on every
## tile the plane draws (normal and flipped copies alternate, as ParallaxStrip draws them), so each
## halo sits on its window. Pure and deterministic: no RNG and no state beyond the cached scan.
static func scenery(id: String, cam_x: float, width: float = 640.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lights := strip_lights(id)
	var size := TankPlaceholderArt.size_of(id)
	var tex_w := float(size.x)
	var top := NEAR_BOTTOM_Y - float(size.y)
	var scroll := roundf(cam_x * NEAR_FACTOR)
	var first := int(floor((scroll - 100.0) / tex_w))
	var last := int(floor((scroll + width + 100.0) / tex_w))
	for i in range(first, last + 1):
		var left := float(i) * tex_w - scroll
		var flipped := posmod(i, 2) == 1
		for k in lights.size():
			var l: Dictionary = lights[k]
			var p: Vector2 = l["p"]
			var x := left + (tex_w - p.x if flipped else p.x)
			var seed_value := (i & 0xffff) * 4096 + k
			var col: Color = l["color"]
			var lt := _light(x, top + p.y, l["radius"], col, l["intensity"], l["fire"], seed_value)
			out.append(lt)
	return out


static var _strip_lights: Dictionary = {}


## The lights painted into near strip `id` as the view draws it, found once: light-coloured pixels
## (fire, lamp and arc colours of the palette) gathered in 16 px cells, each cell one light at its
## pixels' centre: [{"p": Vector2 (strip px), "radius", "color", "intensity", "fire"}]. Fire colours
## in a larger patch are a burning building ("fire": flames and smoke); a few lit pixels are a window
## or lamp. The depot's lamps are electric floodlights (cold).
static func strip_lights(id: String) -> Array[Dictionary]:
	if _strip_lights.has(id):
		return _strip_lights[id]
	var out: Array[Dictionary] = []
	var img := TankPlaceholderArt.texture(id).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var kinds := {}
	for c: Color in [TankPalette.FIRE, TankPalette.AMBER]:
		kinds[_rgb_key(c)] = 0
	for c: Color in [TankPalette.GLOW_WARM, TankPalette.WHITE_WARM]:
		kinds[_rgb_key(c)] = 1
	for c: Color in [TankPalette.COLD, TankPalette.COLD_LIGHT, TankPalette.WHITE_COLD]:
		kinds[_rgb_key(c)] = 2
	var cells := {}
	for y in h:
		for x in w:
			var o := (y * w + x) * 4
			if data[o + 3] < 128:
				continue
			var key := (data[o] << 16) | (data[o + 1] << 8) | data[o + 2]
			if not kinds.has(key):
				continue
			var kind: int = kinds[key]
			var ck := (y / 16) * 1000 + x / 16
			if not cells.has(ck):
				cells[ck] = PackedFloat32Array([0, 0, 0, 0, 0, 0])
			var cell: PackedFloat32Array = cells[ck]
			cell[0] += x
			cell[1] += y
			cell[2] += 1.0
			cell[3 + kind] += 1.0
			cells[ck] = cell
	var keys := cells.keys()
	keys.sort()
	for ck: int in keys:
		var cell: PackedFloat32Array = cells[ck]
		var n := cell[2]
		var fire := cell[3] >= 6.0 and cell[3] * 2.0 >= n
		var color := TankPalette.AMBER if n > 2.0 else TankPalette.GLOW_WARM
		if fire:
			color = TankPalette.FIRE
		if cell[5] > cell[3] + cell[4] or id == "bg_depot_near":
			color = TankPalette.COLD_LIGHT
		var radius := clampf(10.0 + 4.0 * sqrt(n), 12.0, 40.0) * (1.3 if fire else 1.0)
		var lt := {
			"p": Vector2(cell[0] / n, cell[1] / n),
			"radius": radius,
			"color": color,
			"intensity": clampf(0.2 + 0.03 * n, 0.22, 0.5),
			"fire": fire,
		}
		out.append(lt)
	_strip_lights[id] = out
	return out


static func _rgb_key(c: Color) -> int:
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


static func _light(
	x: float, y: float, radius: float, color: Color, intensity: float, fire: bool, seed_value: int
) -> Dictionary:
	return {
		"pos": Vector2(x, y),
		"radius": radius,
		"color": color,
		"intensity": intensity,
		"fire": fire,
		"seed": seed_value,
	}


static func cell_hash(cell: int, salt: int) -> int:
	return (cell * 73856093 ^ salt * 19349663) & 0x7fffffff


func _strip(
	node_name: String, sprite_id: String, preset: String, factor: float, y: float, bottom: bool
) -> ParallaxStrip:
	var s := ParallaxStrip.new()
	s.name = node_name
	s.texture = TankBlur.plane(sprite_id, preset)
	s.factor = factor
	s.position.y = y
	s.align_bottom = bottom
	s.mirror_alternate = true
	s.cover_width = float(TankConst.SCREEN_W)
	s.auto_process = false
	return s


## The smoke columns (soft puffs rising, widening and drifting downwind, warm at the base where the
## fire lights them, fading into the cloud) and fine ash flecks falling through the sky.
func _paint_smoke(item: Node2D) -> void:
	var puff := TankProcTex.puff()
	for col in smoke_columns(_scroll_x):
		var at: Vector2 = col["pos"]
		var sd := int(col["seed"])
		for k in SMOKE_PUFFS:
			var u := fposmod(
				time * 0.035 + float(k) / float(SMOKE_PUFFS) + float(sd % 11) * 0.09, 1.0
			)
			var size := 18.0 + u * 110.0
			var c := (
				at + Vector2(u * u * 60.0 + sin(u * 5.0 + float(sd % 5)) * 5.0, -u * SMOKE_RISE_PX)
			)
			# Smoke lit from below by its fire: warm umber low down, cooling to grey as it climbs and
			# thins; a step lighter than the cloud so the columns read against the dusk sky.
			var tone := SMOKE_TONE.lerp(SMOKE_TOP, sqrt(u))
			var a := 0.95 * smoothstep(0.0, 0.06, u) * (1.0 - u * 0.6)
			var r := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
			item.draw_texture_rect(puff, r, false, Color(tone.r, tone.g, tone.b, a))
	for i in ASH_FLECKS:
		var h := cell_hash(i, 911)
		var x := (
			fposmod(float(h % 640) - time * (6.0 + float(h % 5)) - _scroll_x * 0.3, 660.0) - 10.0
		)
		var y := fposmod(float((h >> 9) % 240) + time * (4.0 + float((h >> 3) % 4)), 230.0) + 40.0
		var a := 0.3 + 0.18 * float(h % 3) / 2.0
		var flake := Vector2(2, 1) if (h >> 5) % 2 == 0 else Vector2(1, 2)
		item.draw_rect(
			Rect2(floorf(x), floorf(y), flake.x, flake.y), TankPalette.with_alpha(ASH_COLOR, a)
		)


## Above the sky sprite: the mean colour of its top row, so the sky has no edge under the HUD.
func _paint_sky_top(item: Node2D) -> void:
	if _sky_top_color.a == 0.0:
		_sky_top_color = top_row_color(TankBlur.plane("bg_sky", "sky").get_image())
	item.draw_rect(Rect2(0, 0, TankConst.SCREEN_W, SKY_TOP_Y + 1.0), _sky_top_color)


## The mean opaque colour of an image's top row (black for an empty one).
static func top_row_color(img: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for x in img.get_width():
		var c := img.get_pixel(x, 0)
		if c.a > 0.5:
			sum += Color(c.r, c.g, c.b, 1.0)
			n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n, 1.0) if n > 0 else Color.BLACK


## Smoke lying in the valleys: clear at y 196, a fire-warmed haze at the horizon (y 236), then the
## cool haze colour toward the ground. Translucent, so the hills show through as distant shapes.
func _paint_haze(item: Node2D) -> void:
	var warm := TankPalette.HAZE.lerp(TankPalette.RUST, 0.35)
	var cool := Color("#3a3f45")
	var clear := Color(cool.r, cool.g, cool.b, 0.0)
	var band := Color(cool.r, cool.g, cool.b, 0.2)
	var mid := Color(warm.r, warm.g, warm.b, 0.36)
	var bot := Color(TankPalette.HAZE.r, TankPalette.HAZE.g, TankPalette.HAZE.b, 0.45)
	# A lighter band of smoky haze behind the turrets (y 140-200), so the dark steel's top edges
	# stand against it, warming toward the horizon fires.
	var pts := PackedVector2Array(
		[Vector2(0, 132), Vector2(640, 132), Vector2(640, 190), Vector2(0, 190)]
	)
	item.draw_polygon(pts, PackedColorArray([clear, clear, band, band]))
	pts = PackedVector2Array(
		[Vector2(0, 190), Vector2(640, 190), Vector2(640, 236), Vector2(0, 236)]
	)
	item.draw_polygon(pts, PackedColorArray([band, band, mid, mid]))
	pts = PackedVector2Array(
		[Vector2(0, 236), Vector2(640, 236), Vector2(640, 300), Vector2(0, 300)]
	)
	item.draw_polygon(pts, PackedColorArray([mid, mid, bot, bot]))


static var _junk: Texture2D = null


## The front plane's tall wreckage, built once: near-black stakes, a twisted girder and a broken
## wheel in two clusters along a wide transparent strip, blurred and darkened by the debris preset.
static func front_junk() -> Texture2D:
	if _junk != null:
		return _junk
	var img := Image.create(FRONT_JUNK_W, FRONT_JUNK_H, false, Image.FORMAT_RGBA8)
	var ink := TankPalette.BLACK
	var hh := float(FRONT_JUNK_H)
	for base_x: float in [120.0, 1380.0]:
		# Three leaning stakes of different heights.
		for k in 3:
			var x := base_x + float(k) * 11.0 + float(k * k) * 3.0
			var ht := hh - 6.0 - float(k) * 9.0
			_junk_line(img, Vector2(x, hh), Vector2(x + 4.0 - float(k) * 3.0, hh - ht), 3.0, ink)
		# A twisted girder leaning out of the rubble.
		var g0 := Vector2(base_x + 46.0, hh)
		var g1 := Vector2(base_x + 70.0, hh - 40.0)
		var g2 := Vector2(base_x + 98.0, hh - 52.0)
		_junk_line(img, g0, g1, 5.0, ink)
		_junk_line(img, g1, g2, 4.0, ink)
		# A broken wheel half buried: a thick rim with two spokes left.
		var c := Vector2(base_x + 132.0, hh - 6.0)
		for i in 40:
			var a := PI + PI * float(i) / 39.0
			var d := Vector2.from_angle(a)
			_junk_line(img, c + d * 15.0, c + d * 12.0, 2.0, ink)
		_junk_line(img, c, c + Vector2.from_angle(-2.2) * 13.0, 2.0, ink)
		_junk_line(img, c, c + Vector2.from_angle(-0.7) * 13.0, 2.0, ink)
		# A rubble mound joining them to the ground.
		for x in range(int(base_x) - 10, int(base_x) + 160):
			var t := float(x - int(base_x) + 10) / 170.0
			var top := hh - 4.0 - 6.0 * sin(t * PI) - 2.0 * sin(float(x) * 0.7)
			for y in range(int(top), FRONT_JUNK_H):
				img.set_pixel(x, y, ink)
	var blurred := TankBlur.blurred_image(img, TankBlur.PRESETS["debris"], TankPalette.HAZE)
	_junk = ImageTexture.create_from_image(blurred)
	return _junk


static func _junk_line(img: Image, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var n := int(ceil(a.distance_to(b))) + 1
	var r := int(ceil(width * 0.5))
	for i in n:
		var p := a.lerp(b, float(i) / float(maxi(n - 1, 1)))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if Vector2(dx, dy).length() > width * 0.5:
					continue
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)
