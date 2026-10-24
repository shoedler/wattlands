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
const SMOKE_RISE_PX := 215.0
const SMOKE_PUFFS := 18
const ASH_FLECKS := 40
## The smoke ceiling: a dark, lumpy pall hanging over the upper sky (lit warm on its underside by the
## fires), so the sky above the turrets is not an empty grey field. Built once, blurred like the sky.
const CEILING_FACTOR := 0.08
const CEILING_W := 960
const CEILING_H := 130
const CEILING_DRIFT_PX_S := 1.6
## Searchlights sweeping slowly beyond the hills (cold light, additive), on the hills' plane.
const BEAM_CELL_PX := 760.0
const BEAM_LEN_PX := 250.0
## The near plane's landmark (its strip's centre) stands at this screen x when a location starts.
const LANDMARK_X := 470.0
## The columns' smoke: dense soot at the base (silhouetted on the horizon's fire glow, which lights
## its underside), thinning into lit grey as it climbs into the dark sky.
const SMOKE_TONE := Color("#0f1012")
const SMOKE_TOP := Color("#35373b")
## Ash flecks: two-pixel grey flakes, never near-white specks.
const ASH_COLOR := Color("#525456")
## Tall blurred wreckage passing close to the lens (front plane): its strip width and height.
const FRONT_JUNK_W := 2700
const FRONT_JUNK_H := 92
## The junk's blur: softer than the debris strip's so its silhouettes still read above the HUD.
const JUNK_BLUR := {"down": 2, "box_r": 1, "passes": 2, "haze": 0.0, "darken": 0.25}
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
## The near strip's extra scroll (ParallaxStrip.offset_x) that put its landmark at LANDMARK_X when
## the location started; the scenery lights use the same offset.
var near_offset: float = 0.0
## The smoke ceiling strip and the searchlights painter.
var ceiling: ParallaxStrip = null
var _beams: TankPainter = null
var _near_placed: bool = false
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
	_beams = TankPainter.new()
	_beams.name = "Searchlights"
	_beams.painter = _paint_beams
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beams.material = add
	add_child(_beams)
	horizon_lights = TankLights.new()
	horizon_lights.name = "HorizonLights"
	add_child(horizon_lights)
	_smoke = TankPainter.new()
	_smoke.name = "SkySmoke"
	_smoke.painter = _paint_smoke
	add_child(_smoke)
	# The pall over the upper sky, in front of the columns that rise into it.
	ceiling = ParallaxStrip.new()
	ceiling.name = "SmokeCeiling"
	ceiling.texture = smoke_ceiling()
	ceiling.factor = CEILING_FACTOR
	ceiling.mirror_alternate = true
	ceiling.cover_width = float(TankConst.SCREEN_W)
	ceiling.drift_px_s = CEILING_DRIFT_PX_S
	ceiling.auto_process = false
	add_child(ceiling)
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
	junk.position.y = DEBRIS_BOTTOM_Y + 18.0
	junk.align_bottom = true
	junk.cover_width = float(TankConst.SCREEN_W)
	junk.auto_process = false
	front.add_child(junk)


## Shows the near plane `id` (one of NEAR_IDS; anything else falls back to the fields). Blurs it on
## first use only. With the camera x `cam_x`, a new location (and the first one shown) is placed so
## its landmark stands at LANDMARK_X, in front of the tank, as the location starts (the quarry is in
## view at Stage 3's start, not behind the tank); the plane then scrolls on from there.
func set_near(id: String, cam_x: float = NAN) -> void:
	var want := id if NEAR_IDS.has(id) else FALLBACK_NEAR
	if want != near_id:
		near_id = want
		near.texture = TankBlur.plane(want, "near")
		swaps += 1
		_near_placed = false
	if not _near_placed and not is_nan(cam_x):
		_near_placed = true
		near_offset = landmark_offset(float(near.texture.get_width()), cam_x)
		near.offset_x = near_offset


## The near strip's offset_x that puts a tile's centre (its landmark) at LANDMARK_X for camera x
## `cam_x` (0 .. tex_w).
static func landmark_offset(tex_w: float, cam_x: float) -> float:
	return fposmod(tex_w * 0.5 - LANDMARK_X - roundf(cam_x * NEAR_FACTOR), tex_w)


## Advances the distant smoke, ash and horizon embers by `dt` seconds (cosmetic, view time).
func advance(dt: float) -> void:
	time += dt
	ceiling.tick(dt)
	_beams.queue_redraw()
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
		if h % 4 == 0:
			continue
		var x := float(cell) * SMOKE_CELL_PX + float(h % 140) - scroll + 30.0
		out.append({"pos": Vector2(x, SMOKE_BASE_Y + float(h % 9)), "seed": h})
	return out


## Scrolls every plane to the camera x (world art px).
func set_world_x(x: float) -> void:
	_scroll_x = x
	for s: ParallaxStrip in [sky, ceiling, hills, near, ground, debris, junk]:
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
static func scenery(
	id: String, cam_x: float, width: float = 640.0, offset: float = 0.0
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lights := strip_lights(id)
	var size := TankPlaceholderArt.size_of(id)
	var tex_w := float(size.x)
	var top := NEAR_BOTTOM_Y - float(size.y)
	var scroll := roundf(cam_x * NEAR_FACTOR + offset)
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
			# Narrow where it clears the hills, widening as it climbs: a pillar, not a hanging blot.
			var size := 9.0 + 78.0 * pow(u, 1.5)
			var c := (
				at + Vector2(u * u * 60.0 + sin(u * 5.0 + float(sd % 5)) * 5.0, -u * SMOKE_RISE_PX)
			)
			# A black pillar: opaque soot at the base (alpha >= 0.8 over the lower half), lit from
			# below by its fire, thinning only near the top into the smoke ceiling. Two puffs per
			# step, the inner one denser, keep the column's edge crisp instead of a soft smudge.
			var tone := SMOKE_TONE.lerp(SMOKE_TOP, u * u)
			var a := 0.98 * smoothstep(0.0, 0.05, u) * (1.0 - smoothstep(0.5, 1.0, u) * 0.75)
			var r := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
			item.draw_texture_rect(puff, r, false, Color(tone.r, tone.g, tone.b, a * 0.8))
			var core := r.grow(-size * 0.22)
			item.draw_texture_rect(puff, core, false, Color(tone.r, tone.g, tone.b, a))
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
static var _ceiling: Texture2D = null


## The smoke ceiling, built once: a dark pall over the top of the sky whose lower edge hangs in
## lumps (a sum of slow waves and a coarse value noise) down to about y 60-120, its underside lit a
## little warm by the fires below; blurred with the sky's preset. Its two edges meet when mirrored.
static func smoke_ceiling() -> Texture2D:
	if _ceiling != null:
		return _ceiling
	var w := CEILING_W
	var h := CEILING_H
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := Color("#0b0c0e")
	var under := Color("#1e1d1e").lerp(TankPalette.RUST, 0.18)
	for x in w:
		var u := float(x) / float(w) * TAU
		var edge := (
			78.0 + 16.0 * sin(u * 2.0 + 0.7) + 9.0 * sin(u * 5.0 + 1.9) + 5.0 * sin(u * 13.0 + 0.3)
		)
		for y in h:
			var lump := (
				0.5 + 0.5 * sin(float(x) * 0.09 + float(y) * 0.21) * sin(float(y) * 0.13 - u)
			)
			var e := edge + (lump - 0.5) * 14.0
			var a := 1.0 - smoothstep(e - 26.0, e + 6.0, float(y))
			if a <= 0.0:
				continue
			var k := clampf(float(y) / maxf(e, 1.0), 0.0, 1.0)
			var col := top.lerp(under, k * k)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * 0.88))
	var blurred := TankBlur.blurred_image(img, TankBlur.PRESETS["sky"], TankPalette.HAZE)
	_ceiling = ImageTexture.create_from_image(blurred)
	return _ceiling


## The searchlight beams for camera x `cam_x`: [{"base": Vector2, "angle": float (radians, -PI/2 is
## straight up)}], one in every other cell of BEAM_CELL_PX on the hills' plane, by hash, sweeping
## slowly with `t` seconds.
static func beams(cam_x: float, t: float, width: float = 640.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scroll := cam_x * HILLS_FACTOR
	var first := int(floor(scroll / BEAM_CELL_PX)) - 1
	var last := int(floor((scroll + width) / BEAM_CELL_PX)) + 1
	for cell in range(first, last + 1):
		var h := cell_hash(cell, 7741)
		if h % 2 == 1:
			continue
		var x := float(cell) * BEAM_CELL_PX + float(h % 400) + 120.0 - scroll
		var sweep := sin(t * (0.11 + float(h % 5) * 0.02) + float(h % 13))
		var ang := -PI * 0.5 + deg_to_rad(28.0) * sweep + deg_to_rad(float(h % 21) - 10.0)
		out.append({"base": Vector2(x, HILLS_BOTTOM_Y - 46.0 - float(h % 9)), "angle": ang})
	return out


## Cold searchlight beams: a narrow wedge from behind the hills fading out into the smoke ceiling.
func _paint_beams(item: Node2D) -> void:
	var col := TankPalette.COLD_LIGHT
	for b in beams(_scroll_x, time):
		var base: Vector2 = b["base"]
		var d := Vector2.from_angle(float(b["angle"]))
		var n := Vector2(-d.y, d.x)
		var tip := base + d * BEAM_LEN_PX
		var pts := PackedVector2Array(
			[base - n * 1.5, base + n * 1.5, tip + n * 17.0, tip - n * 17.0]
		)
		var near := Color(col.r, col.g, col.b, 0.1)
		var far := Color(col.r, col.g, col.b, 0.0)
		item.draw_polygon(pts, PackedColorArray([near, near, far, far]))
		var core := PackedVector2Array(
			[base - n * 0.5, base + n * 0.5, base + d * 120.0 + n * 4.0, base + d * 120.0 - n * 4.0]
		)
		var hot := Color(col.r, col.g, col.b, 0.1)
		item.draw_polygon(core, PackedColorArray([hot, hot, far, far]))


## The front plane's tall wreckage, built once: two clusters 1350 px apart along a wide transparent
## strip (so a cluster is in view about two thirds of the time while the tank moves), each a leaning
## shell-broken telegraph pole with its crossbar and a dangling wire, stakes with sagging barbed wire
## between them, a twisted girder, a broken wheel and a rubble mound. Near-black (#0f1012) and
## blurred at load (JUNK_BLUR), so it reads as an out-of-focus layer in front of the road whose tops
## rise to y 270-300, above the bottom HUD band and below the engine rooms.
static func front_junk() -> Texture2D:
	if _junk != null:
		return _junk
	var img := Image.create(FRONT_JUNK_W, FRONT_JUNK_H, false, Image.FORMAT_RGBA8)
	var ink := TankPalette.SOOT
	var hh := float(FRONT_JUNK_H)
	for ci in 2:
		var base_x := 140.0 + float(ci) * 1350.0
		var mirror := ci == 1
		var sx := -1.0 if mirror else 1.0
		var ox := base_x + (150.0 if mirror else 0.0)
		# The telegraph pole, leaning, with a crossbar and a wire hanging off it.
		var p0 := Vector2(ox + sx * 10.0, hh)
		var p1 := Vector2(ox + sx * 20.0, hh - 72.0)
		_junk_line(img, p0, p1, 4.0, ink)
		var bar := p1.lerp(p0, 0.08)
		_junk_line(img, bar + Vector2(-9, 1), bar + Vector2(9, -1), 2.0, ink)
		var wire := PackedVector2Array()
		for k in 12:
			var t := float(k) / 11.0
			wire.append(bar + Vector2(sx * (9.0 + t * 40.0), t * t * 34.0 + sin(t * PI) * 6.0))
		for k in range(1, wire.size()):
			_junk_line(img, wire[k - 1], wire[k], 1.0, ink)
		# Stakes with two sagging strands of barbed wire between them.
		var tops: Array[Vector2] = []
		for k in 4:
			var x := ox + sx * (48.0 + float(k) * 17.0 + float(k * k))
			var ht := 42.0 + float((k * 7 + ci * 3) % 4) * 5.0
			var top := Vector2(x + sx * (float(k % 2) * 3.0 - 1.0), hh - ht)
			_junk_line(img, Vector2(x, hh), top, 3.0, ink)
			tops.append(top)
		for strand in 2:
			for k in range(1, tops.size()):
				var a := tops[k - 1] + Vector2(0, 3.0 + 7.0 * float(strand))
				var b := tops[k] + Vector2(0, 3.0 + 7.0 * float(strand))
				var prev := a
				for q in range(1, 9):
					var t := float(q) / 8.0
					var p := a.lerp(b, t) + Vector2(0, sin(t * PI) * 4.0)
					_junk_line(img, prev, p, 1.0, ink)
					prev = p
		# A twisted girder leaning out of the rubble.
		var g0 := Vector2(ox + sx * 125.0, hh)
		var g1 := Vector2(ox + sx * 140.0, hh - 40.0)
		var g2 := Vector2(ox + sx * 162.0, hh - 52.0)
		_junk_line(img, g0, g1, 5.0, ink)
		_junk_line(img, g1, g2, 4.0, ink)
		# A broken wheel half buried: a thick rim with two spokes left.
		var c := Vector2(ox + sx * 182.0, hh - 6.0)
		for i in 40:
			var a := PI + PI * float(i) / 39.0
			var d := Vector2.from_angle(a)
			_junk_line(img, c + d * 15.0, c + d * 12.0, 2.0, ink)
		_junk_line(img, c, c + Vector2.from_angle(-2.2) * 13.0, 2.0, ink)
		_junk_line(img, c, c + Vector2.from_angle(-0.7) * 13.0, 2.0, ink)
		# A rubble mound joining them to the ground.
		var x_lo := int(minf(ox - sx * 10.0, ox + sx * 205.0))
		var x_hi := int(maxf(ox - sx * 10.0, ox + sx * 205.0))
		for x in range(x_lo, x_hi):
			var t := float(x - x_lo) / float(x_hi - x_lo)
			var top := hh - 5.0 - 7.0 * sin(t * PI) - 2.0 * sin(float(x) * 0.7)
			for y in range(int(top), FRONT_JUNK_H):
				img.set_pixel(x, y, ink)
	var blurred := TankBlur.blurred_image(img, JUNK_BLUR, TankPalette.HAZE)
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
