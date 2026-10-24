class_name TankBackdrop
extends Node2D
## The diorama's planes in depth (brief 3 "Layout", "Depth of field"), back to front: the sky 0.05
## with a far smoke bank drifting over it, searchlights and the horizon fires, the distant smoke
## columns 0.12 rising into the smoke ceiling and a nearer bank whose undersides the fires light, a
## far ridge 0.14, drifting smoke sheets, the hills 0.2, the haze, the near plane 0.5 (fields,
## village, quarry, foundry town or depot, by segment; composed once without mirroring, NearPlane),
## the ground 1.0 (the tank's plane) and, in front of everything, the foreground wreckage 1.3: dark,
## strongly blurred rubble, stakes, weeds and wrecks breaking the frame's lower edge. Every plane
## but the ground is pre-blurred once (TankBlur) and hazed; `front` holds the foreground and is added
## by the view above the tank. Scenery lights (burning farms, lit windows, foundry lamps,
## floodlights) are computed here as plain data from the plane's scroll. Nothing here creates a
## texture after load.

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
## Distant smoke columns rising off the horizon fires (a plane between the sky and the hills). Each
## column has its own height, width and lean downwind (smoke_columns), so no two read alike.
const SMOKE_FACTOR := 0.12
const SMOKE_CELL_PX := 170.0
const SMOKE_BASE_Y := 214.0
const SMOKE_PUFFS := 30
const ASH_FLECKS := 40
## The smoke ceiling: a dark, lumpy pall hanging over the upper sky (lit warm on its underside by the
## fires), so the sky above the turrets is not an empty grey field. Built once, blurred like the sky.
const CEILING_FACTOR := 0.08
const CEILING_W := 960
const CEILING_H := 130
const CEILING_DRIFT_PX_S := 1.6
## Two banks of billowing smoke filling the upper third in depth (the scene critic, round 3: the top
## 40% was empty dark sky): a far, hazier bank behind the columns and a nearer, darker one in front
## of their tops, each with lumpy undersides lit warm where fires burn below. [factor, drift px/s,
## top y, salt]. Built once at a quarter size and scaled up (soft), tiled unmirrored.
const BANK_W := 1600
const BANK_H := 128
const BANKS := [[0.03, 1.1, 34.0, 11], [0.09, 2.6, 18.0, 23]]
## A far ridge of wooded hills behind the hills plane, so the land climbs to y ~115.
const FAR_RIDGE_FACTOR := 0.14
const FAR_RIDGE_W := 1280
const FAR_RIDGE_H := 92
const FAR_RIDGE_BOTTOM_Y := 200.0
## Smoke sheets drifting low over the hills: long soft streaks, warmer the lower they hang.
const SHEET_FACTOR := 0.22
const SHEET_PERIOD_PX := 1180.0
const SHEETS := 6
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
## The foreground plane: FRONT_W x FRONT_H px whose bottom sits at FRONT_BOTTOM_Y, so its rubble
## tops reach y 286-300 (just above the bottom HUD) and its tallest wrecks rise to y ~250. Built
## once, then blurred (FRONT_BLUR, about 5 art px) and darkened: an out-of-focus layer.
const FRONT_W := 2880
const FRONT_H := 96
const FRONT_BOTTOM_Y := 340.0
const FRONT_BLUR := {"down": 2, "box_r": 1, "passes": 2, "haze": 0.0, "darken": 0.2}
## In front of the tank's hull (hull_span), the foreground above FRONT_CUT_Y fades to FRONT_FADE so
## a wreck passing (or stopping) there never hides the engine rooms; the fade ramps over 12 px.
const FRONT_CUT_Y := 280.0
const FRONT_FADE := 0.28
## Scenery lights repeat every cell of this many plane px.
const CELL_PX := 150.0
const FALLBACK_NEAR := "bg_fields_near"
const NEAR_IDS: Array[String] = [
	"bg_fields_near", "bg_village_near", "bg_quarry_near", "bg_town_near", "bg_depot_near"
]

static var _front: Texture2D = null
static var _ceiling: Texture2D = null
static var _ridge: Texture2D = null
static var _banks: Dictionary = {}
static var _strip_lights: Dictionary = {}

var sky: ParallaxStrip = null
var hills: ParallaxStrip = null
var near: ParallaxStrip = null
var ground: ParallaxStrip = null
## The far ridge behind the hills.
var far_ridge: ParallaxStrip = null
## The two smoke banks (far, near).
var banks: Array[ParallaxStrip] = []
## Halos of the near plane's lights (fires, windows, lamps): drawn over the near plane, under the ground.
var scenery_lights: TankLights = null
## The fires' light on the near smoke bank's underside (additive, over the bank).
var cloud_glow: TankLights = null
## The foreground plane's painter (in `front`).
var front_plane: TankPainter = null
## Holds the foreground: the view parents it above the world.
var front: Node2D = null
## The screen x range the tank's hull covers (set by the view each frame); empty for none.
var hull_span: Vector2 = Vector2.ZERO
var near_id: String = ""
## The near strip's extra scroll (ParallaxStrip.offset_x) that put its landmark at LANDMARK_X when
## the location started; the scenery lights use the same offset.
var near_offset: float = 0.0
## The smoke ceiling strip and the searchlights painter.
var ceiling: ParallaxStrip = null
## Seconds of animation (the smoke columns, ash and embers drift with it; cosmetic only).
var time: float = 0.0
## The horizon fires' halos and embers (additive), drawn over the sky, under the smoke and hills.
var horizon_lights: TankLights = null
## Times a near strip was swapped (tests).
var swaps: int = 0

var _beams: TankPainter = null
var _near_placed: bool = false
var _smoke: TankPainter = null
var _sheets: TankPainter = null
var _scroll_x: float = 0.0
var _sky_top_color: Color = Color(0, 0, 0, 0)


func _init() -> void:
	name = "Backdrop"
	# Every near plane is composed and blurred now, once (and its lights found), so a segment change
	# later is only a texture swap.
	for id in NEAR_IDS:
		NearPlane.texture(id)
		strip_lights(id)
	var sky_top := TankPainter.new()
	sky_top.name = "SkyTop"
	sky_top.painter = _paint_sky_top
	add_child(sky_top)
	sky = _strip("Sky", "bg_sky", "sky", SKY_FACTOR, SKY_TOP_Y, false)
	add_child(sky)
	banks.append(_bank_strip(0))
	add_child(banks[0])
	_beams = TankPainter.new()
	_beams.name = "Searchlights"
	_beams.painter = _paint_beams
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beams.material = add
	add_child(_beams)
	# The far ridge stands in front of the far bank and the searchlights' feet; the columns rise in
	# front of it from behind the hills.
	far_ridge = ParallaxStrip.new()
	far_ridge.name = "FarRidge"
	far_ridge.texture = far_ridge_texture()
	far_ridge.factor = FAR_RIDGE_FACTOR
	far_ridge.position.y = FAR_RIDGE_BOTTOM_Y
	far_ridge.align_bottom = true
	far_ridge.cover_width = float(TankConst.SCREEN_W)
	far_ridge.auto_process = false
	add_child(far_ridge)
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
	banks.append(_bank_strip(1))
	add_child(banks[1])
	cloud_glow = TankLights.new()
	cloud_glow.name = "CloudGlow"
	add_child(cloud_glow)
	hills = _strip("Hills", "bg_hills_far", "hills", HILLS_FACTOR, HILLS_BOTTOM_Y, true)
	add_child(hills)
	_sheets = TankPainter.new()
	_sheets.name = "SmokeSheets"
	_sheets.painter = _paint_sheets
	add_child(_sheets)
	# The haze band lies over the hills and under the near plane: aerial perspective in smoke.
	var haze := TankPainter.new()
	haze.name = "HazeBand"
	haze.painter = _paint_haze
	add_child(haze)
	near = _strip("Near", FALLBACK_NEAR, "near", NEAR_FACTOR, NEAR_BOTTOM_Y, true)
	near.texture = NearPlane.texture(FALLBACK_NEAR)
	near.mirror_alternate = false
	near_id = FALLBACK_NEAR
	add_child(near)
	scenery_lights = TankLights.new()
	scenery_lights.name = "SceneryLights"
	add_child(scenery_lights)
	ground = _strip("Ground", "bg_ground", "ground", GROUND_FACTOR, GROUND_TOP_Y, false)
	add_child(ground)
	front = Node2D.new()
	front.name = "Front"
	front_plane = TankPainter.new()
	front_plane.name = "Foreground"
	front_plane.painter = _paint_front
	front.add_child(front_plane)
	front_texture()


## Shows the near plane `id` (one of NEAR_IDS; anything else falls back to the fields). With the
## camera x `cam_x`, a new location (and the first one shown) is placed so its landmark stands at
## LANDMARK_X, in front of the tank, as the location starts (the quarry is in view at Stage 3's
## start, not behind the tank); the plane then scrolls on from there.
func set_near(id: String, cam_x: float = NAN) -> void:
	var want := id if NEAR_IDS.has(id) else FALLBACK_NEAR
	if want != near_id:
		near_id = want
		near.texture = NearPlane.texture(want)
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


## Advances the distant smoke, ash, embers and the fires' light on the clouds by `dt` seconds
## (cosmetic, view time).
func advance(dt: float) -> void:
	time += dt
	ceiling.tick(dt)
	for b in banks:
		b.tick(dt)
	_beams.queue_redraw()
	horizon_lights.begin()
	cloud_glow.begin()
	for col in smoke_columns(_scroll_x):
		var at: Vector2 = col["pos"]
		var sd := int(col["seed"])
		var flick := 0.85 + 0.15 * sin(time * 2.3 + float(sd % 17))
		horizon_lights.add(at + Vector2(0, 4), 70.0, TankPalette.FIRE, 0.2 * flick)
		horizon_lights.add(at + Vector2(0, 6), 24.0, TankPalette.AMBER, 0.28 * flick)
		for k in 3:
			var u := fposmod(time * 0.11 + float(k) / 3.0 + float(sd % 7) * 0.1, 1.0)
			var e := at + Vector2(sin(u * 9.0 + float(k)) * 6.0 + u * 18.0, -u * 90.0)
			horizon_lights.add(e, 2.0, TankPalette.AMBER, 0.7 * (1.0 - u))
		# The fire's light caught on the banks' undersides above it (and the column's lee side).
		var lean: float = col["lean"]
		cloud_glow.add(at + Vector2(lean * 0.55, -118.0), 92.0, TankPalette.FIRE, 0.13 * flick)
		cloud_glow.add(at + Vector2(lean * 0.3, -82.0), 54.0, TankPalette.RUST_LIGHT, 0.16 * flick)
	horizon_lights.end()
	cloud_glow.end()
	_smoke.queue_redraw()
	_sheets.queue_redraw()


## The distant smoke columns for camera x `cam_x`: [{"pos": Vector2 (base, screen), "seed": int,
## "rise": float (px), "width": float (scale), "lean": float (px downwind at the top)}], one in most
## cells of SMOKE_CELL_PX on the SMOKE_FACTOR plane, by hash (no RNG): some tall and thin, some
## short and broad, each bending its own way downwind.
static func smoke_columns(cam_x: float, width: float = 640.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scroll := cam_x * SMOKE_FACTOR
	var first := int(floor(scroll / SMOKE_CELL_PX)) - 1
	var last := int(floor((scroll + width) / SMOKE_CELL_PX)) + 1
	for cell in range(first, last + 1):
		var h := cell_hash(cell, 4517)
		if h % 3 == 0:
			continue
		var x := float(cell) * SMOKE_CELL_PX + float(h % 120) - scroll + 25.0
		var col := {
			"pos": Vector2(x, SMOKE_BASE_Y + float(h % 9)),
			"seed": h,
			"rise": 130.0 + float((h >> 5) % 110),
			"width": 0.75 + float((h >> 9) % 8) * 0.09,
			"lean": 15.0 + float((h >> 13) % 90),
		}
		out.append(col)
	return out


## Scrolls every plane to the camera x (world art px).
func set_world_x(x: float) -> void:
	_scroll_x = x
	for s: ParallaxStrip in [sky, ceiling, far_ridge, hills, near, ground, banks[0], banks[1]]:
		if s.world_x != x:
			s.world_x = x
	front_plane.queue_redraw()


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
## painted into the composed plane (strip_lights: its lit windows, lamps and burning houses), placed
## on every tile the plane draws (it tiles unmirrored), so each halo sits on its window. Pure and
## deterministic: no RNG and no state beyond the cached scan.
static func scenery(
	id: String, cam_x: float, width: float = 640.0, offset: float = 0.0
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lights := strip_lights(id)
	var size := NearPlane.image(_near_or_fallback(id)).get_size()
	var tex_w := float(size.x)
	var top := NEAR_BOTTOM_Y - float(size.y)
	var scroll := roundf(cam_x * NEAR_FACTOR + offset)
	var first := int(floor((scroll - 100.0) / tex_w))
	var last := int(floor((scroll + width + 100.0) / tex_w))
	for i in range(first, last + 1):
		var left := float(i) * tex_w - scroll
		for k in lights.size():
			var l: Dictionary = lights[k]
			var p: Vector2 = l["p"]
			var x := left + p.x
			if x < -100.0 or x > width + 100.0:
				continue
			var seed_value := (i & 0xffff) * 4096 + k
			var col: Color = l["color"]
			var lt := _light(x, top + p.y, l["radius"], col, l["intensity"], l["fire"], seed_value)
			out.append(lt)
	return out


## The lights painted into near plane `id` as the view draws it, found once: light-coloured pixels
## (fire, lamp and arc colours of the palette) gathered in 16 px cells, each cell one light at its
## pixels' centre: [{"p": Vector2 (plane px), "radius", "color", "intensity", "fire"}]. Fire colours
## in a larger patch are a burning building ("fire": flames and smoke); a few lit pixels are a window
## or lamp. The depot's lamps are electric floodlights (cold).
static func strip_lights(id: String) -> Array[Dictionary]:
	if _strip_lights.has(id):
		return _strip_lights[id]
	var out: Array[Dictionary] = []
	var img := NearPlane.image(_near_or_fallback(id))
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


static func _near_or_fallback(id: String) -> String:
	return id if NEAR_IDS.has(id) else FALLBACK_NEAR


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


func _bank_strip(index: int) -> ParallaxStrip:
	var spec: Array = BANKS[index]
	var s := ParallaxStrip.new()
	s.name = "SmokeBank%d" % index
	s.texture = smoke_bank(index)
	s.factor = float(spec[0])
	s.drift_px_s = float(spec[1])
	s.position.y = float(spec[2])
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
		var rise: float = col["rise"]
		var wk: float = col["width"]
		var lean: float = col["lean"]
		for k in SMOKE_PUFFS:
			var u := fposmod(
				time * 0.035 + float(k) / float(SMOKE_PUFFS) + float(sd % 11) * 0.09, 1.0
			)
			# Narrow where it clears the hills, widening as it climbs: a pillar, not a hanging blot.
			var size := (9.0 + 78.0 * pow(u, 1.5)) * wk
			var bend := u * u * lean + sin(u * 5.0 + float(sd % 5)) * 5.0
			var c := at + Vector2(bend, -u * rise)
			# A black pillar: opaque soot at the base, lit from below by its fire, thinning near the
			# top into the smoke banks. Two puffs per step, the inner one denser, keep the column's
			# edge crisp instead of a soft smudge.
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


## Smoke sheets lying low over the hills: long, thin, soft streaks drifting downwind, cool grey high
## up and warmed by the fires near the horizon.
func _paint_sheets(item: Node2D) -> void:
	var puff := TankProcTex.puff()
	var scroll := _scroll_x * SHEET_FACTOR + time * 3.2
	for i in SHEETS:
		var h := cell_hash(i, 2203)
		var y := 150.0 + float(h % 56)
		var w := 170.0 + float((h >> 6) % 160)
		var hh := 9.0 + float((h >> 11) % 8)
		var x := fposmod(float((h >> 3) % 1000) - scroll * (0.8 + 0.05 * float(i)), SHEET_PERIOD_PX)
		x -= w
		var k := clampf((y - 150.0) / 56.0, 0.0, 1.0)
		var tone := TankPalette.SMOKE.lerp(TankPalette.RUST, 0.25 * k)
		var a := 0.12 + 0.08 * float(h % 3) / 2.0
		for rep in 2:
			var rx := x + float(rep) * SHEET_PERIOD_PX
			if rx > float(TankConst.SCREEN_W) or rx + w < 0.0:
				continue
			item.draw_texture_rect(
				puff, Rect2(rx, y - hh * 0.5, w, hh), false, TankPalette.with_alpha(tone, a)
			)
			item.draw_texture_rect(
				puff,
				Rect2(rx + w * 0.2, y - hh * 0.3, w * 0.6, hh * 0.6),
				false,
				TankPalette.with_alpha(tone, a * 0.8)
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


## A value noise in [0, 1) that repeats every `period` cells along x (so a strip built from it tiles
## without a seam or a mirror).
static func pnoise(x: float, y: float, cell: float, period: int, salt: int) -> float:
	var fx := x / cell
	var fy := y / cell
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - float(ix)
	var ty := fy - float(iy)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var x0 := posmod(ix, period)
	var x1 := posmod(ix + 1, period)
	var a := _lattice(x0, iy, salt)
	var b := _lattice(x1, iy, salt)
	var c := _lattice(x0, iy + 1, salt)
	var d := _lattice(x1, iy + 1, salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


static func _lattice(x: int, y: int, salt: int) -> float:
	var n := (x * 374761393 + y * 668265263 + salt * 1274126177) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65536.0


## Smoke bank `index` (BANKS), built once at a quarter of its size and scaled up smooth: billowing
## masses in a band with lumpy tops and undersides, dark above, their undersides lit warm (more
## where fires burn below), their crowns catching a little cold sky light. Tiles unmirrored.
static func smoke_bank(index: int) -> Texture2D:
	if _banks.has(index):
		return _banks[index]
	var salt := int((BANKS[index] as Array)[3])
	var far := index == 0
	var lw := BANK_W / 4
	var lh := BANK_H / 4
	var img := Image.create(lw, lh, false, Image.FORMAT_RGBA8)
	var top_col := Color("#1d1e21") if far else Color("#121315")
	var mid_col := Color("#2a2c30") if far else Color("#1d1e21")
	var under_col := Color("#4a3429") if far else Color("#5a3a2c")
	var crown_col := Color("#3c434c") if far else Color("#2e3439")
	var max_a := 0.78 if far else 0.9
	for x in lw:
		var fx := float(x)
		var t_edge := (
			2.0 + 8.0 * pnoise(fx, 0.0, 25.0, 16, salt) + 3.0 * pnoise(fx, 0.0, 6.25, 64, salt + 1)
		)
		var b_edge := 14.0 + 11.0 * pnoise(fx, 9.0, 20.0, 20, salt + 2)
		b_edge += 4.0 * pnoise(fx, 9.0, 5.0, 80, salt + 3)
		var warm := pnoise(fx, 4.0, 50.0, 8, salt + 4)
		for y in lh:
			var fy := float(y)
			var m := (
				smoothstep(t_edge - 3.0, t_edge + 3.0, fy)
				* (1.0 - smoothstep(b_edge - 2.0, b_edge + 1.0, fy))
			)
			if m <= 0.0:
				continue
			var d := (
				0.6 * pnoise(fx, fy, 12.5, 32, salt + 5) + 0.4 * pnoise(fx, fy, 6.25, 64, salt + 6)
			)
			var a := m * smoothstep(0.12, 0.48, d) * max_a
			var col := top_col.lerp(mid_col, d)
			var under := smoothstep(b_edge - 7.0, b_edge - 0.5, fy)
			col = col.lerp(under_col, under * (0.08 + 0.92 * warm * warm))
			var crown := 1.0 - smoothstep(t_edge, t_edge + 3.0, fy)
			col = col.lerp(crown_col, crown * 0.5)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	img.resize(BANK_W, BANK_H, Image.INTERPOLATE_CUBIC)
	var tex := ImageTexture.create_from_image(img)
	_banks[index] = tex
	return tex


## The far ridge, built once: two wooded ridges in cold haze, the back one paler, their crests
## ragged with tree tops, a few fires glowing on the slopes; blurred like the hills. Tiles
## unmirrored (periodic noise).
static func far_ridge_texture() -> Texture2D:
	if _ridge != null:
		return _ridge
	var w := FAR_RIDGE_W
	var h := FAR_RIDGE_H
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var back := Color("#383c43")
	var back_lo := Color("#2c3036")
	var front := Color("#2a2d33")
	var front_lo := Color("#1f2226")
	for x in w:
		var fx := float(x)
		var tb := (
			10.0 + 26.0 * pnoise(fx, 0.0, 160.0, 8, 301) + 8.0 * pnoise(fx, 0.0, 40.0, 32, 302)
		)
		tb += 2.0 * pnoise(fx, 0.0, 2.5, 512, 303)
		var tf := (
			34.0 + 30.0 * pnoise(fx, 5.0, 128.0, 10, 304) + 7.0 * pnoise(fx, 5.0, 32.0, 40, 305)
		)
		tf += 2.5 * pnoise(fx, 5.0, 2.0, 640, 306)
		var yb := int(tb)
		var yf := int(tf)
		for y in range(yb, h):
			var k := float(y - yb) / float(h - yb)
			img.set_pixel(x, y, back.lerp(back_lo, k))
		for y in range(yf, h):
			var k := float(y - yf) / float(h - yf)
			img.set_pixel(x, y, front.lerp(front_lo, k))
	for f in 4:
		var fx := 140 + f * 310 + (f * 97) % 60
		var fy := 0
		while fy < h - 1 and img.get_pixel(fx, fy).a < 0.5:
			fy += 1
		fy = mini(fy + 6 + f * 3, h - 3)
		for dy in range(-1, 2):
			for dx in range(-2, 3):
				img.set_pixel(fx + dx, fy + dy, TankPalette.FIRE)
		img.set_pixel(fx, fy, TankPalette.AMBER)
		img.set_pixel(fx + 1, fy, TankPalette.AMBER)
	var blurred := TankBlur.blurred_image(img, TankBlur.PRESETS["hills"], TankPalette.HAZE)
	_ridge = ImageTexture.create_from_image(blurred)
	return _ridge


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
		var near_c := Color(col.r, col.g, col.b, 0.1)
		var far_c := Color(col.r, col.g, col.b, 0.0)
		item.draw_polygon(pts, PackedColorArray([near_c, near_c, far_c, far_c]))
		var core := PackedVector2Array(
			[base - n * 0.5, base + n * 0.5, base + d * 120.0 + n * 4.0, base + d * 120.0 - n * 4.0]
		)
		var hot := Color(col.r, col.g, col.b, 0.1)
		item.draw_polygon(core, PackedColorArray([hot, hot, far_c, far_c]))


## The foreground's tiles for the current scroll, drawn as column bands: in front of the hull
## (hull_span, ramped over 12 px at each side) the part above FRONT_CUT_Y fades to FRONT_FADE.
func _paint_front(item: Node2D) -> void:
	var tex := front_texture()
	var tw := float(FRONT_W)
	var top := FRONT_BOTTOM_Y - float(FRONT_H)
	var cut := clampf(FRONT_CUT_Y - top, 0.0, float(FRONT_H))
	var scroll := roundf(_scroll_x * DEBRIS_FACTOR)
	var bands := front_bands(hull_span)
	var i := int(floor(scroll / tw))
	var x := float(i) * tw - scroll
	while x < float(TankConst.SCREEN_W):
		for band in bands:
			var x0 := maxf(band.x, x)
			var x1 := minf(band.y, x + tw)
			if x1 <= x0:
				continue
			var sx := x0 - x
			var bw := x1 - x0
			var lower := Rect2(sx, cut, bw, float(FRONT_H) - cut)
			item.draw_texture_rect_region(tex, Rect2(x0, top + cut, bw, lower.size.y), lower)
			var upper := Rect2(sx, 0.0, bw, cut)
			var mod := Color(1, 1, 1, band.z)
			item.draw_texture_rect_region(tex, Rect2(x0, top, bw, cut), upper, mod)
		x += tw


## The foreground's column bands for a hull span: [Vector3(x0, x1, alpha of the upper part)],
## covering the screen; full alpha away from the hull, FRONT_FADE over it, ramping in between.
static func front_bands(span: Vector2) -> Array[Vector3]:
	var w := float(TankConst.SCREEN_W) + 2.0
	if span.y <= span.x:
		return [Vector3(-2.0, w, 1.0)]
	var a := span.x
	var b := span.y
	return [
		Vector3(-2.0, a - 12.0, 1.0),
		Vector3(a - 12.0, a - 6.0, lerpf(1.0, FRONT_FADE, 0.35)),
		Vector3(a - 6.0, a, lerpf(1.0, FRONT_FADE, 0.7)),
		Vector3(a, b, FRONT_FADE),
		Vector3(b, b + 6.0, lerpf(1.0, FRONT_FADE, 0.7)),
		Vector3(b + 6.0, b + 12.0, lerpf(1.0, FRONT_FADE, 0.35)),
		Vector3(b + 12.0, w, 1.0),
	]


## The foreground, built once (FRONT_W x FRONT_H, tiling unmirrored): a continuous rubble bank whose
## lumpy top runs along y 286-300 on screen with weeds standing out of it, the generated debris strip
## (stakes and broken bricks) along it, and four different wrecks spaced unevenly: a burnt-out
## vehicle body on its side, girders leaning out of rubble with stakes and wire strung between them
## (every wire tied at both ends), a broken masonry wall corner and a shattered tree stump.
## Near-black, then blurred hard and darkened (FRONT_BLUR): an out-of-focus layer, never a sharp
## silhouette. Nothing in it is a pole with a free wire, a cross or a figure.
static func front_texture() -> Texture2D:
	if _front != null:
		return _front
	var img := Image.create(FRONT_W, FRONT_H, false, Image.FORMAT_RGBA8)
	var pen := Pen.new(img)
	var ink := TankPalette.BLACK
	var ink2 := TankPalette.SOOT
	var lit := TankPalette.COAL
	var mound := 44
	# The generated debris strip's broken bricks and stake stubs along the bank (its lower rows, three
	# plain copies; it tiles), not its tall stakes, which read as a far skyline once blurred.
	var deb := TankPlaceholderArt.texture("fg_debris").get_image()
	if deb.is_compressed():
		deb.decompress()
	deb.convert(Image.FORMAT_RGBA8)
	var keep := mini(22, deb.get_height())
	deb = deb.get_region(Rect2i(0, deb.get_height() - keep, deb.get_width(), keep))
	var dy := mound + 10 - keep
	for y in keep:
		for x in deb.get_width():
			var c := deb.get_pixel(x, y)
			if c.a > 0.0:
				deb.set_pixel(x, y, Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, c.a))
	var dx := 0
	while dx < FRONT_W:
		pen.blend(deb, dx, dy)
		dx += deb.get_width()
	# The rubble bank: a lumpy top with gaps, solid below.
	for x in FRONT_W:
		var fx := float(x)
		var n := pnoise(fx, 0.0, 36.0, FRONT_W / 36, 811) * 0.65
		n += pnoise(fx, 0.0, 9.0, FRONT_W / 9, 812) * 0.35
		var dip := smoothstep(0.62, 0.8, pnoise(fx, 3.0, 90.0, FRONT_W / 90, 813)) * 10.0
		var ty := int(float(mound - 2) + 12.0 * (1.0 - n) + dip)
		pen.col(x, ty, FRONT_H, ink)
		pen.px(x, ty, lit if Pen.bayer(x, 0) < 0.5 else ink2)
		pen.col(x, ty + 1, ty + 3, ink2)
		# Weeds out of the bank: clumps of thin blades, leaning.
		if pnoise(fx, 7.0, 5.0, FRONT_W / 5, 814) > 0.72 and x % 2 == 0:
			var bh := 3 + int(pnoise(fx, 8.0, 2.0, FRONT_W / 2, 815) * 7.0)
			var lean := 1 if pnoise(fx, 9.0, 3.0, FRONT_W / 3, 816) > 0.5 else -1
			for k in bh:
				pen.px(x + (lean * k) / 3, ty - 1 - k, ink2)
	_hulk(pen, 260, mound + 4, ink, lit)
	_girders(pen, 980, mound + 6, ink, lit)
	_wall_corner(pen, 1690, mound + 6, ink, lit)
	_stump(pen, 2330, mound + 6, ink, lit)
	var blurred := TankBlur.blurred_image(img, FRONT_BLUR, TankPalette.HAZE)
	_front = ImageTexture.create_from_image(blurred)
	return _front


## A burnt-out vehicle body lying on its side: a long rounded box with a hollow wheel arch and a
## torn opening, half sunk in the rubble.
static func _hulk(pen: Pen, x: int, base: int, ink: Color, lit: Color) -> void:
	var w := 74
	var ht := 26
	for i in w:
		var t := float(i) / float(w - 1)
		var round_k := 1.0 - pow(absf(t * 2.0 - 1.0), 6.0)
		var top := base - int(float(ht) * (0.55 + 0.45 * round_k))
		pen.col(x + i, top, base + 2, ink)
		pen.px(x + i, top, lit)
	for i in 14:
		for j in 9:
			if Vector2(i - 7, j).length() < 7.5:
				pen.px(x + 18 + i, base - 9 + j, TankPalette.SOOT)
	pen.rect(x + 40, base - 20, 16, 7, TankPalette.SOOT)
	for k in 6:
		pen.px(x + 40 + k * 3, base - 21 - (k % 2), ink)


## Girders leaning out of the rubble side by side (never crossing) and stakes with two strands of
## wire strung between them, each strand tied to a stake at both ends.
static func _girders(pen: Pen, x: int, base: int, ink: Color, lit: Color) -> void:
	for g in 2:
		var a := Vector2(x + g * 16, base + 2)
		var b := Vector2(x + 26 + g * 18, base - 40 + g * 12)
		for k in 4:
			pen.line(a + Vector2(k, 0), b + Vector2(k, 0), ink)
		pen.line(b + Vector2(0, -1), b + Vector2(3, -1), lit)
	var tops: Array[Vector2] = []
	for k in 4:
		var sx := x + 70 + k * 21 + (k * k) % 5
		var top := Vector2(sx + (k % 2), base - 26 - (k * 7) % 9)
		pen.line(Vector2(sx, base + 2), top, ink)
		pen.line(Vector2(sx + 1, base + 2), top + Vector2(1, 0), ink)
		tops.append(top)
	for strand in 2:
		for k in range(1, tops.size()):
			var off := Vector2(0, 4.0 + 8.0 * float(strand))
			pen.wire(tops[k - 1] + off, tops[k] + off, 4.0, ink)


## A broken masonry wall corner: a stepped, jagged top with a window gap, rubble at its foot.
static func _wall_corner(pen: Pen, x: int, base: int, ink: Color, lit: Color) -> void:
	var w := 46
	for i in w:
		var step := 44 - (i / 7) * 5 - int(absf(sin(float(i) * 1.9)) * 4.0)
		var top := base - maxi(step, 8)
		pen.col(x + i, top, base + 2, ink)
		pen.px(x + i, top, lit)
	pen.rect(x + 12, base - 30, 8, 11, TankPalette.SOOT)
	pen.rect(x + 12, base - 30, 8, 1, ink)


## A shattered tree stump: a thick trunk with a splintered top, one broken branch stub and roots.
static func _stump(pen: Pen, x: int, base: int, ink: Color, lit: Color) -> void:
	for i in 10:
		var splinter := int(absf(sin(float(i) * 2.3)) * 9.0)
		var top := base - 44 + splinter
		pen.col(x + i, top, base + 2, ink)
		pen.px(x + i, top, lit)
	pen.line(Vector2(x + 9, base - 28), Vector2(x + 20, base - 37), ink)
	pen.line(Vector2(x + 9, base - 27), Vector2(x + 20, base - 36), ink)
	for r: int in [-1, 1]:
		pen.line(Vector2(x + 5, base - 3), Vector2(x + 5 + r * 12, base + 2), ink)
		pen.line(Vector2(x + 5, base - 2), Vector2(x + 5 + r * 12, base + 3), ink)


# --- Composed planes --------------------------------------------------------------------------------


## A wrap-around drawing surface for planes that tile without mirroring: x is taken modulo the
## image's width, so a shape drawn across the right edge continues at the left and the plane's two
## edges always meet. Organic shapes (trees, heaps, rock) are drawn as row spans and shaded in three
## tones by `shape`: a sky-lit rim on every top edge, the body, and a darker foot.
class Pen:
	extends RefCounted
	const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

	var img: Image = null
	var w: int = 1
	var h: int = 1

	func _init(p_img: Image) -> void:
		img = p_img
		w = img.get_width()
		h = img.get_height()

	## An ordered-dither threshold in (0, 1).
	static func bayer(x: int, y: int) -> float:
		return (float(BAYER[(y & 3) * 4 + (x & 3)]) + 0.5) / 16.0

	func px(x: int, y: int, c: Color) -> void:
		if y >= 0 and y < h:
			img.set_pixel(posmod(x, w), y, c)

	func get_px(x: int, y: int) -> Color:
		return img.get_pixel(posmod(x, w), clampi(y, 0, h - 1))

	## Rows [y0, y1) of column x.
	func col(x: int, y0: int, y1: int, c: Color) -> void:
		var a := maxi(y0, 0)
		var b := mini(y1, h)
		if b > a:
			img.fill_rect(Rect2i(posmod(x, w), a, 1, b - a), c)

	func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		for i in rw:
			col(x + i, y, y + rh, c)

	## `src` alpha-blended over the surface with its left edge at x (wrapping).
	func blend(src: Image, x: int, y: int) -> void:
		var r := Rect2i(Vector2i.ZERO, src.get_size())
		var x0 := posmod(x, w)
		img.blend_rect(src, r, Vector2i(x0, y))
		if x0 + r.size.x > w:
			img.blend_rect(src, r, Vector2i(x0 - w, y))

	## A line one px wide (wrapping).
	func line(a: Vector2, b: Vector2, c: Color) -> void:
		var n := int(ceil(maxf(absf(b.x - a.x), absf(b.y - a.y)))) + 1
		for i in n:
			var p := a.lerp(b, float(i) / float(maxi(n - 1, 1)))
			px(int(floor(p.x)), int(floor(p.y)), c)

	## A wire hanging between a and b with `sag` px of droop at its middle (a parabola).
	func wire(a: Vector2, b: Vector2, sag: float, c: Color) -> void:
		var n := int(ceil(absf(b.x - a.x))) + 1
		var prev := a
		for i in range(1, n + 1):
			var t := float(i) / float(n)
			var p := a.lerp(b, t) + Vector2(0, 4.0 * sag * t * (1.0 - t))
			line(prev, p, c)
			prev = p

	## A shape given as row spans: `spans[i]` = Vector2i(left, right) (inclusive, absolute x; right <
	## left skips the row) of row `top + i`. Shaded in `tones` = [foot, body, lit, rim]: the rim on
	## every pixel with nothing of the shape above it, a dithered lit band under it, the body, and the
	## foot dithering in over the lowest third; the leftmost pixel of a row takes the foot tone, the
	## rightmost of the upper rows the lit one (the fires are low and ahead).
	func shape(top: int, spans: Array[Vector2i], tones: Array[Color]) -> void:
		var n := spans.size()
		for i in n:
			var s: Vector2i = spans[i]
			var y := top + i
			if s.y < s.x or y < 0 or y >= h:
				continue
			var t := float(i) / float(maxi(n - 1, 1))
			var above := spans[i - 1] if i > 0 else Vector2i(1, 0)
			var above2 := spans[i - 2] if i > 1 else Vector2i(1, 0)
			for x in range(s.x, s.y + 1):
				var c: Color = tones[1]
				if x < above.x or x > above.y:
					c = tones[3] if bayer(x, y) < 0.6 else tones[2]
				elif x < above2.x or x > above2.y:
					c = tones[2] if bayer(x, y) < 0.7 else tones[1]
				elif x == s.x:
					c = tones[0]
				elif x == s.y and t < 0.6:
					c = tones[2]
				elif t > 0.62 and bayer(x, y) < (t - 0.62) * 3.2:
					c = tones[0]
				px(x, y, c)


## A location's near plane, composed once at load (the scene critic, round 3: the flanks were one
## generated band mirrored, so each half reflected the other, with flat one-tone cut-outs beside a
## richly shaded landmark, a rectangular edge where the landmark's reeds met them, and gallows-like
## gantries at the depot). The plane is W px wide and tiles without mirroring:
## - the generated landmark segment (TankPlaceholderArt.STRIP_SEGMENTS) once, centred, its two ends
##   faded over FEATHER px into the flanks, so no band ends in a straight vertical edge;
## - the flanks' ground, hedges and reeds continue the landmark's own plain end bands: PATCH_W px
##   patches cut at seeded offsets (some flipped) and cross-faded over PATCH_BLEND px, so the texture
##   has no mirror axis and nothing repeats within a screen;
## - on the flanks the location again, every silhouette shaded in three tones (Pen.shape) and placed
##   from a seeded RNG with jittered gaps: poplar rows, oak and pine clumps and farmsteads (one
##   burning) on Poplar Road; cottages, orchards and a burning cottage at Kettle Ford; terraced rock
##   faces, spoil heaps, pines, lattice pylons with their wires sagging from pylon to pylon along the
##   whole flank and a burning timber shed at Quarry Ridge; brick works with irregular lit window
##   groups, chimney stacks and a slag heap by the foundry town; hangars, concrete bunkers, fuel
##   tanks, a long-span gantry crane (trolley and hook high under the girder, nothing hanging) and
##   floodlight masts with cold lamps at the depot.
## Lit windows, lamps and fires use the palette's light colours, so TankBackdrop.strip_lights gives
## them halos (and the fires flames and smoke). Deterministic: a fixed seed per id.
class NearPlane:
	extends RefCounted
	const W := 1920
	const FEATHER := 24
	const PATCH_W := 44
	const PATCH_BLEND := 14
	## Flank props keep this far from the landmark's faded ends.
	const MARGIN := 30

	const K0 := Color("#07080a")
	const K1 := Color("#0f1012")
	const K2 := Color("#17181b")
	const K3 := Color("#202124")
	const K4 := Color("#2a2b2e")
	const K5 := Color("#353739")
	const K6 := Color("#424446")
	const K7 := Color("#525456")
	const K8 := Color("#666869")
	const S0 := Color("#2e3944")
	const S1 := Color("#4b5561")
	const S2 := Color("#59636c")
	const B0 := Color("#17130f")
	const B1 := Color("#241d17")
	const B2 := Color("#33291f")
	const B3 := Color("#443628")
	const B4 := Color("#574634")
	const R0 := Color("#3a2a24")
	const R1 := Color("#5a3a2e")
	const R2 := Color("#7d4f3a")
	const O1 := Color("#3d3c33")
	const FIRE := Color("#e8743a")
	const AMBER := Color("#ffb35c")
	const GLOW := Color("#ffd99a")
	const COLD := Color("#5d86a3")
	const COLD_LIGHT := Color("#9fc4dd")

	const NEAR_TREE: Array[Color] = [K1, K2, K3, S0]
	const MID_TREE: Array[Color] = [K2, K3, K4, S0]
	const FAR_TREE: Array[Color] = [K3, K4, K5, S1]
	const ROCK: Array[Color] = [K3, K5, K6, K7]
	const SPOIL: Array[Color] = [B1, B2, K4, K5]
	const SLAG: Array[Color] = [K1, K2, K3, K4]

	static var _images: Dictionary = {}
	static var _textures: Dictionary = {}

	## The plane as the view draws it: composed, then blurred and hazed (TankBlur "near"). Built once.
	static func texture(id: String) -> Texture2D:
		if _textures.has(id):
			return _textures[id]
		var img := TankBlur.blurred_image(image(id), TankBlur.PRESETS["near"], TankPalette.HAZE)
		var tex := ImageTexture.create_from_image(img)
		_textures[id] = tex
		return tex

	## The composed plane before the blur (its lights are scanned from this). Built once.
	static func image(id: String) -> Image:
		if _images.has(id):
			return _images[id]
		var img := compose(id)
		_images[id] = img
		return img

	## [segment end m, plain band width at its end, plain band width at its start] of the source.
	static func segment_of(id: String, src_w: int) -> Array:
		var seg: Array = TankPlaceholderArt.STRIP_SEGMENTS.get(id, [])
		if seg.size() >= 3 and int(seg[0]) <= src_w:
			return seg
		return [src_w, 60, 60]

	## The generated strip as made (its landmark segment from x 0), or the placeholder.
	static func source(id: String) -> Image:
		var path := TankPlaceholderArt.SPRITES_DIR.path_join(id + ".png")
		var img: Image = null
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				img = tex.get_image()
		if img == null:
			img = TankPlaceholderArt.texture(id).get_image()
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		return img

	## The horizon row of the source: the median top of its plain end bands' columns.
	static func horizon(src: Image, seg: Array) -> int:
		var h := src.get_height()
		var m := int(seg[0])
		var cols: Array[int] = []
		for x in range(0, mini(int(seg[2]), m)):
			cols.append(x)
		for x in range(maxi(m - int(seg[1]), 0), m):
			cols.append(x)
		var tops: Array[int] = []
		for x in cols:
			for y in h:
				if src.get_pixel(x, y).a > 0.5:
					tops.append(y)
					break
		if tops.is_empty():
			return h * 2 / 3
		tops.sort()
		return clampi(tops[tops.size() / 2], 30, h - 16)

	static func compose(id: String) -> Image:
		var src := source(id)
		var h := src.get_height()
		var seg := segment_of(id, src.get_width())
		var m := int(seg[0])
		var hz := horizon(src, seg)
		var img := Image.create(W, h, false, Image.FORMAT_RGBA8)
		var pen := Pen.new(img)
		var rng := RandomNumberGenerator.new()
		rng.seed = absi(id.hash()) + 77
		var style := str(TankStripArt.FILLER_STYLE.get(id, "fields"))
		var l0 := (W - m) / 2
		var l1 := l0 + m
		# The flank runs from the landmark's right end round the seam to its left end.
		var lo := l1 + MARGIN
		var hi := l0 + W - MARGIN
		_far_layer(pen, rng, style, lo, hi, hz)
		_ground(pen, rng, src, seg, l1 - FEATHER - PATCH_BLEND, l0 + W + FEATHER + PATCH_BLEND)
		_near_layer(pen, rng, style, lo, hi, hz)
		var lm := src.get_region(Rect2i(0, 0, m, h))
		_fix_landmark(id, lm, hz)
		_feather(lm, FEATHER)
		pen.blend(lm, l0, 0)
		return img

	## The flanks' ground: the plain end bands of the source in cross-faded patches.
	static func _ground(
		pen: Pen, rng: RandomNumberGenerator, src: Image, seg: Array, f0: int, f1: int
	) -> void:
		var h := src.get_height()
		var m := int(seg[0])
		var bands: Array[Vector2i] = []
		var ql := mini(int(seg[2]), m)
		var qr := mini(int(seg[1]), m)
		if ql >= 16:
			bands.append(Vector2i(0, ql))
		if qr >= 16:
			bands.append(Vector2i(m - qr, m))
		if bands.is_empty():
			bands.append(Vector2i(0, mini(m, 64)))
		var x := f0
		var first := true
		while x < f1:
			var band: Vector2i = bands[rng.randi_range(0, bands.size() - 1)]
			var bw := band.y - band.x
			var pw := mini(PATCH_W, bw)
			var sx := band.x + rng.randi_range(0, maxi(bw - pw, 0))
			var patch := src.get_region(Rect2i(sx, 0, pw, h))
			if rng.randf() < 0.5:
				patch.flip_x()
			if not first:
				_feather_left(patch, mini(PATCH_BLEND, pw / 2))
			pen.blend(patch, x, 0)
			first = false
			x += pw - PATCH_BLEND

	## Alpha ramps in over the leftmost `n` columns (0 at the edge).
	static func _feather_left(img: Image, n: int) -> void:
		for x in n:
			var k := (float(x) + 0.5) / float(n)
			for y in img.get_height():
				var c := img.get_pixel(x, y)
				if c.a > 0.0:
					c.a *= k
					img.set_pixel(x, y, c)

	## Alpha ramps in over `n` columns at both ends (smoothstep).
	static func _feather(img: Image, n: int) -> void:
		var w := img.get_width()
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			var k := t * t * (3.0 - 2.0 * t)
			for x: int in [i, w - 1 - i]:
				for y in img.get_height():
					var c := img.get_pixel(x, y)
					if c.a > 0.0:
						c.a *= k
						img.set_pixel(x, y, c)

	## Per-landmark repairs: the foundry's gantry crane loses its hanging cable and bucket (a
	## crossbar with a block hanging on a line reads as a gallows) and gets a trolley tight under the
	## girder; Poplar Road's wire stakes along the field (thin dark uprights that read as tiny figures
	## at a distance) are smoothed into the field by a horizontal median.
	static func _fix_landmark(id: String, lm: Image, hz: int) -> void:
		var h := lm.get_height()
		if id == "bg_town_near" and lm.get_width() > 320 and h > 92:
			lm.fill_rect(Rect2i(300, 69, 17, 19), Color(0, 0, 0, 0))
			lm.fill_rect(Rect2i(302, 68, 13, 3), K2)
			lm.fill_rect(Rect2i(302, 68, 13, 1), K4)
			lm.fill_rect(Rect2i(307, 71, 2, 1), K1)
		elif id == "bg_fields_near":
			var src := lm.duplicate() as Image
			var lights := TankPlaceholderArt.light_colours()
			for y in range(hz + 6, mini(hz + 20, h)):
				for x in range(3, lm.get_width() - 3):
					if lights.has(src.get_pixel(x, y).to_rgba32()):
						continue
					var row: Array[Color] = []
					for dx in range(-3, 4):
						row.append(src.get_pixel(x + dx, y))
					row.sort_custom(_darker)
					lm.set_pixel(x, y, row[3])

	static func _darker(a: Color, b: Color) -> bool:
		return a.v < b.v

	# --- Placement -------------------------------------------------------------------------------

	## The far layer behind the hedges: hazy tree clumps all along the flank (and the quarry's ridge
	## and pylon line).
	static func _far_layer(
		pen: Pen, rng: RandomNumberGenerator, style: String, lo: int, hi: int, hz: int
	) -> void:
		if style == "quarry":
			ridge(pen, rng, lo, hi, hz)
		var x := lo + rng.randi_range(0, 30)
		while x < hi - 10:
			var n := rng.randi_range(2, 6)
			for _k in n:
				if x >= hi - 6:
					break
				if style == "quarry" or style == "depot":
					pine(pen, x, hz + 1, rng.randi_range(14, 24), FAR_TREE)
					x += rng.randi_range(4, 7)
				elif rng.randf() < 0.45:
					poplar(pen, x, hz + 1, rng.randi_range(22, 34), rng.randi_range(5, 7), FAR_TREE)
					x += rng.randi_range(5, 8)
				else:
					oak(pen, rng, x, hz + 1, rng.randi_range(10, 15), FAR_TREE)
					x += rng.randi_range(9, 14)
			x += rng.randi_range(24, 90)
		if style == "quarry":
			pylon_line(pen, rng, lo, hi, hz + 2)

	## The near layer: the location's buildings and works between clumps of trees, each scene picked
	## from a shuffled bag so neighbours differ.
	static func _near_layer(
		pen: Pen, rng: RandomNumberGenerator, style: String, lo: int, hi: int, hz: int
	) -> void:
		var bags := {
			"fields": ["farm", "poplars", "oaks", "burning_farm", "pines", "poplars", "poplars"],
			"village": ["cottages", "orchard", "burning_cottage", "cottages", "oaks", "poplars"],
			"quarry": ["terraces", "pines", "sawmill", "spoil", "terraces", "pines"],
			"town": ["works", "chimneys", "slag", "works", "sheds", "chimneys"],
			"depot": ["hangar", "tanks", "crane", "bunker", "mast", "block", "pines", "tanks"],
		}
		var bag: Array = bags.get(style, bags["fields"])
		var order: Array = []
		var x := lo + rng.randi_range(4, 20)
		var base := hz + 5
		while x < hi - 30:
			if order.is_empty():
				order = bag.duplicate()
				for i in range(order.size() - 1, 0, -1):
					var j := rng.randi_range(0, i)
					var tmp: Variant = order[i]
					order[i] = order[j]
					order[j] = tmp
			var kind := str(order.pop_back())
			var used := _scene(pen, rng, kind, x, base + rng.randi_range(-1, 2), hi - x)
			x += used + rng.randi_range(14, 56)

	## Draws one scene of `kind` from x on `base` within `room` px; returns its width (0 if it did
	## not fit).
	static func _scene(
		pen: Pen, rng: RandomNumberGenerator, kind: String, x: int, base: int, room: int
	) -> int:
		match kind:
			"poplars":
				return _row_of(pen, rng, "poplar", x, base, mini(room, rng.randi_range(44, 96)))
			"oaks":
				return _row_of(pen, rng, "oak", x, base, mini(room, rng.randi_range(36, 76)))
			"pines":
				return _row_of(pen, rng, "pine", x, base, mini(room, rng.randi_range(40, 96)))
			"orchard":
				return _row_of(pen, rng, "orchard", x, base, mini(room, rng.randi_range(44, 76)))
			"farm":
				return farmstead(pen, rng, x, base, false) if room >= 90 else 0
			"burning_farm":
				return farmstead(pen, rng, x, base, true) if room >= 90 else 0
			"cottages":
				return cottages(pen, rng, x, base, false) if room >= 80 else 0
			"burning_cottage":
				return cottages(pen, rng, x, base, true) if room >= 80 else 0
			"terraces":
				if room < 110:
					return 0
				return terraces(pen, rng, x, base, mini(room, rng.randi_range(110, 180)))
			"spoil":
				return heap(pen, rng, x, base, rng.randi_range(40, 64), SPOIL) if room >= 64 else 0
			"slag":
				return heap(pen, rng, x, base, rng.randi_range(40, 60), SLAG) if room >= 60 else 0
			"sawmill":
				return sawmill(pen, rng, x, base) if room >= 96 else 0
			"works":
				return works(pen, rng, x, base) if room >= 100 else 0
			"sheds":
				return sheds(pen, rng, x, base) if room >= 64 else 0
			"chimneys":
				return chimneys(pen, rng, x, base) if room >= 40 else 0
			"hangar":
				return hangar(pen, rng, x, base) if room >= 116 else 0
			"block":
				return block(pen, rng, x, base) if room >= 70 else 0
			"tanks":
				return fuel_tanks(pen, rng, x, base) if room >= 70 else 0
			"crane":
				return gantry_crane(pen, rng, x, base) if room >= 124 else 0
			"bunker":
				return bunker(pen, rng, x, base) if room >= 58 else 0
			"mast":
				return floodlight_mast(pen, rng, x, base) if room >= 20 else 0
		return 0

	## A clump of trees of one kind across `width` px, uneven in height and spacing, on a low hedge.
	static func _row_of(
		pen: Pen, rng: RandomNumberGenerator, kind: String, x: int, base: int, width: int
	) -> int:
		var cx := x + 3
		while cx < x + width - 3:
			var b := base + rng.randi_range(-1, 1)
			match kind:
				"poplar":
					poplar(pen, cx, b, rng.randi_range(38, 62), rng.randi_range(7, 10), NEAR_TREE)
					cx += rng.randi_range(6, 13)
				"pine":
					pine(pen, cx, b, rng.randi_range(24, 44), NEAR_TREE)
					cx += rng.randi_range(6, 10)
				"orchard":
					oak(pen, rng, cx, b, rng.randi_range(9, 13), MID_TREE)
					cx += rng.randi_range(12, 17)
				_:
					oak(pen, rng, cx, b, rng.randi_range(14, 22), NEAR_TREE)
					cx += rng.randi_range(12, 20)
		hedge(pen, x - 2, x + width + 2, base)
		return width

	# --- Trees and ground ----------------------------------------------------------------------------

	## A Lombardy poplar on `base`: a spindle `wd` px wide at a third of its height, ragged at the edge.
	static func poplar(pen: Pen, x: int, base: int, ht: int, wd: int, tones: Array[Color]) -> void:
		var spans: Array[Vector2i] = []
		for i in ht:
			var r := ht - 1 - i
			if r < 2:
				spans.append(Vector2i(x, x))
				continue
			var t := float(r) / float(ht)
			var hw := (
				float(wd) * 0.5 * (0.55 + 0.45 * t / 0.3)
				if t < 0.3
				else float(wd) * 0.5 * pow(1.0 - (t - 0.3) / 0.7, 0.8)
			)
			hw += (TankMaterial.smooth_noise(x, r, 3.0, 5) - 0.5) * 1.6
			spans.append(Vector2i(roundi(float(x) - hw), roundi(float(x) + hw)))
		pen.shape(base - ht, spans, tones)
		pen.col(x, base - 2, base, B0)

	## A pine: three stacked tiers narrowing to a point, each tier's upper edge sky-lit.
	static func pine(pen: Pen, x: int, base: int, ht: int, tones: Array[Color]) -> void:
		var half := maxf(3.0, float(ht) * 0.27)
		var spans: Array[Vector2i] = []
		for i in ht:
			var r := ht - 1 - i
			if r < 1:
				spans.append(Vector2i(x, x))
				continue
			var t := float(r) / float(ht)
			var tier := fposmod(t * 3.0, 1.0)
			var hw := half * (1.0 - t * 0.78) * (0.5 + 0.5 * (1.0 - tier))
			hw += (TankMaterial.smooth_noise(x, r, 2.0, 9) - 0.5) * 1.0
			spans.append(Vector2i(roundi(float(x) - hw), roundi(float(x) + hw)))
		pen.shape(base - ht, spans, tones)

	## A broad tree (oak, orchard) of canopy radius `r`: five to seven overlapping lobes with a ragged
	## edge on a short trunk.
	static func oak(
		pen: Pen, rng: RandomNumberGenerator, x: int, base: int, r: int, tones: Array[Color]
	) -> void:
		var trunk := maxi(2, r / 3)
		var lobes: Array[Vector3] = []
		var n := rng.randi_range(5, 7)
		for _k in n:
			var lr := float(r) * rng.randf_range(0.32, 0.5)
			var a := rng.randf_range(PI, TAU)
			var d := rng.randf_range(0.2, 0.62) * float(r)
			var lx := float(x) + cos(a) * d * 1.25
			var ly := float(base - trunk) - float(r) * 0.55 + sin(a) * d * 0.75
			lobes.append(Vector3(lx, ly, lr))
		var top := base
		var bottom := 0
		for l in lobes:
			top = mini(top, int(floor(l.y - l.z)))
			bottom = maxi(bottom, int(ceil(l.y + l.z)))
		bottom = mini(bottom, base - trunk + 1)
		var spans: Array[Vector2i] = []
		for y in range(top, bottom + 1):
			var a := 1 << 20
			var b := -(1 << 20)
			for l in lobes:
				var dy := float(y) + 0.5 - l.y
				if absf(dy) <= l.z:
					var dx := sqrt(l.z * l.z - dy * dy)
					a = mini(
						a, roundi(l.x - dx + (TankMaterial.smooth_noise(x, y, 1.6, 13) - 0.5) * 2.4)
					)
					b = maxi(
						b,
						roundi(
							l.x + dx + (TankMaterial.smooth_noise(x + 9, y, 1.6, 13) - 0.5) * 2.4
						)
					)
			spans.append(Vector2i(a, b))
		pen.shape(top, spans, tones)
		pen.col(x, base - trunk, base, B0)
		pen.col(x + 1, base - trunk + 1, base, K1)

	## A low hedge from x0 to x1 on `base`, lumpy, its crowns sky-lit.
	static func hedge(pen: Pen, x0: int, x1: int, base: int) -> void:
		for hx in range(x0, x1):
			var hh := 2 + int(TankMaterial.smooth_noise(hx, 0, 4.0, 31) * 3.0)
			pen.col(hx, base - hh, base + 1, K2)
			pen.px(hx, base - hh, K3 if Pen.bayer(hx, 1) < 0.6 else S0)

	## A dome-shaped heap `wd` px wide (spoil, slag) in `tones`.
	static func heap(
		pen: Pen, rng: RandomNumberGenerator, x: int, base: int, wd: int, tones: Array[Color]
	) -> int:
		var hh := float(wd) * rng.randf_range(0.26, 0.34)
		var top := base - ceili(hh)
		var spans: Array[Vector2i] = []
		for y in range(top, base + 1):
			var k := clampf((float(base) - float(y)) / hh, 0.0, 1.0)
			var half := float(wd) * 0.5 * sqrt(1.0 - k * k)
			half += (TankMaterial.smooth_noise(x, y, 3.0, 17) - 0.5) * 2.0
			var mid := float(x) + float(wd) * 0.5 - k * float(wd) * 0.12
			spans.append(Vector2i(roundi(mid - half), roundi(mid + half)))
		pen.shape(top, spans, tones)
		if tones == SLAG:
			# Molten slag tipped down one flank: a short glowing trickle.
			var gx := x + wd / 2 + rng.randi_range(2, maxi(wd / 4, 2))
			for k in 4:
				pen.px(gx + k, top + 3 + k * 2, FIRE if k > 0 else AMBER)
				pen.px(gx + k, top + 4 + k * 2, FIRE)
		return wd

	# --- Buildings ----------------------------------------------------------------------------------

	## A house `bw` x `wh` px of walls on `base` at x, gable end on with its ridge `rh` px above the
	## eaves: the wall shaded (eave shadow, a darker foot), a dark roof with a sky-lit rim, a chimney
	## and windows (`lit` 0..1 of them glowing).
	static func house(
		pen: Pen,
		rng: RandomNumberGenerator,
		x: int,
		base: int,
		bw: int,
		wh: int,
		rh: int,
		wall: Color,
		lit: float
	) -> void:
		var top := base - wh
		pen.rect(x, top, bw, wh, wall)
		pen.rect(x, top, bw, 1, K2)
		pen.rect(x, base - 2, bw, 2, wall.darkened(0.3))
		pen.col(x, top, base, K2)
		pen.col(x + bw - 1, top + 1, base - 2, wall.lightened(0.12))
		for r in rh:
			var inset := int(float(r) * float(bw + 2) * 0.5 / float(rh))
			var y := top - 1 - r
			pen.rect(x - 1 + inset, y, bw + 2 - inset * 2, 1, K2)
			pen.px(x - 1 + inset, y, S0)
			pen.px(x + bw - inset, y, K4)
		pen.rect(x - 1, top - 1, bw + 2, 1, K1)
		if rng.randf() < 0.8:
			var cx := x + bw - 4 - rng.randi_range(0, 2)
			pen.rect(cx, top - rh + 1, 2, rh - 1, R0)
			pen.rect(cx, top - rh, 3, 1, K4)
		var wx := x + 2
		while wx < x + bw - 3:
			var c := K1
			if rng.randf() < lit:
				c = AMBER if rng.randf() < 0.7 else GLOW
			pen.rect(wx, top + 3, 2, 3 if wh > 11 else 2, c)
			wx += rng.randi_range(4, 8)

	## A long barn seen from its side: plank walls under a long low roof.
	static func barn(pen: Pen, x: int, base: int, bw: int, wh: int) -> void:
		var top := base - wh
		pen.rect(x, top, bw, wh, B1)
		var k := x + 2
		while k < x + bw - 1:
			pen.col(k, top + 1, base, B0)
			k += 3
		pen.rect(x, base - 2, bw, 2, B0)
		for r in 5:
			pen.rect(x - 2 + r, top - 1 - r, bw + 4 - r * 2, 1, K2)
		pen.rect(x + 3, top - 6, bw - 6, 1, K4)
		pen.px(x + 3, top - 6, S0)
		pen.rect(x + bw / 2 - 3, base - 7, 6, 7, K1)

	## Flames through a burnt-open roof: a glowing fire bed and ragged tongues of uneven height,
	## tallest in the middle, with charred rafters across it, in the palette's fire colours
	## (TankBackdrop.strip_lights makes it a burning building).
	static func fire_in_roof(pen: Pen, rng: RandomNumberGenerator, x: int, y: int, wd: int) -> void:
		var salt := rng.randi_range(0, 999)
		for i in wd:
			var t := (float(i) + 0.5) / float(wd)
			var bed := 1 + int(2.0 * sin(t * PI))
			pen.col(x + i, y - bed + 1, y + 2, FIRE)
			var tall := 2.0 + 7.0 * sin(t * PI)
			var fh := int(tall * (0.4 + 0.6 * TankMaterial.smooth_noise(x + i, 0, 1.7, salt)))
			for k in fh:
				var yy := y - bed - k
				if k == fh - 1 and Pen.bayer(x + i, yy) < 0.5:
					continue
				var core := k < fh / 2 and t > 0.25 and t < 0.75
				pen.px(x + i, yy, AMBER if core else FIRE)
		pen.rect(x + wd / 2 - 1, y, 3, 1, GLOW)
		pen.px(x + wd / 3, y - 1, K1)
		pen.px(x + wd * 2 / 3, y - 2, K1)

	## Poplar Road's farmstead: a farmhouse, a barn (its roof burning when `burning`) and a tree.
	static func farmstead(
		pen: Pen, rng: RandomNumberGenerator, x: int, base: int, burning: bool
	) -> int:
		oak(pen, rng, x + 8, base - 1, rng.randi_range(13, 18), MID_TREE)
		var hw := rng.randi_range(20, 28)
		var wh := rng.randi_range(12, 15)
		house(pen, rng, x + 5, base, hw, wh, rng.randi_range(9, 12), K4, 0.6)
		var bx := x + hw + rng.randi_range(9, 14)
		var bw := rng.randi_range(32, 44)
		var bh := rng.randi_range(12, 15)
		barn(pen, bx, base, bw, bh)
		if burning:
			fire_in_roof(pen, rng, bx + bw / 3, base - bh - 3, rng.randi_range(11, 15))
		hedge(pen, x - 4, bx + bw + 6, base + 2)
		return bx + bw + 6 - x

	## Kettle Ford's outskirts: two to four cottages of different sizes behind a stone wall, one of
	## them burning when `burning`.
	static func cottages(
		pen: Pen, rng: RandomNumberGenerator, x: int, base: int, burning: bool
	) -> int:
		var cx := x
		var n := rng.randi_range(2, 4)
		var fire_at := rng.randi_range(0, n - 1) if burning else -1
		for k in n:
			var bw := rng.randi_range(15, 24)
			var wh := rng.randi_range(10, 15)
			var rh := rng.randi_range(8, 12)
			var wall := [K4, B2, K5][k % 3] as Color
			house(pen, rng, cx, base - 1, bw, wh, rh, wall, 0.5)
			if k == fire_at:
				fire_in_roof(pen, rng, cx + 2, base - 1 - wh - 3, bw - 4)
			cx += bw + rng.randi_range(3, 10)
		pen.rect(x - 4, base - 4, cx - x + 4, 4, K4)
		pen.rect(x - 4, base - 4, cx - x + 4, 1, K5)
		for sx in range(x - 4, cx, 4):
			pen.px(sx + rng.randi_range(0, 2), base - 2, K3)
		return cx - x

	## The quarry's terraced face cut into a dark hill: the hill's natural slope with pines on the
	## left, and on the right the rock stepped down in benches, each band of rock lit along its ledge
	## and shadowed under the ledge above, mottled and cracked, with a chute from the top to the foot
	## and a hut with a lit window on a bench.
	static func terraces(
		pen: Pen, rng: RandomNumberGenerator, x: int, base: int, width: int
	) -> int:
		var ht := rng.randi_range(32, 48)
		var benches := rng.randi_range(4, 6)
		var bh := maxi(ht / benches, 5)
		ht = bh * benches
		var slope_w := int(float(width) * rng.randf_range(0.2, 0.28))
		var cut0 := x + slope_w
		var bd := maxi((width - slope_w) / (benches + 1), 7)
		var x_end := x + width
		var salt := rng.randi_range(0, 999)
		for i in slope_w + 3:
			var t := minf(float(i) / float(slope_w), 1.0)
			var ty := base - int(float(ht) * smoothstep(0.0, 1.0, t))
			ty -= int(TankMaterial.smooth_noise(x + i, 0, 5.0, salt) * 3.0)
			pen.col(x + i, ty, base, B1)
			pen.px(x + i, ty, S0)
			pen.col(x + i, ty + 1, ty + 3, K3)
		for cx in range(cut0, x_end):
			var k_top := mini(benches - 1, ceili(float(x_end - cx) / float(bd)) - 1)
			var top := base - (k_top + 1) * bh
			top += int(TankMaterial.smooth_noise(cx, k_top, 2.5, salt + 3) * 2.2)
			for y in range(top, base):
				var ry := (base - 1 - y) % bh
				var c := K4
				if y == top:
					c = K7 if Pen.bayer(cx, y) < 0.5 else K6
				elif ry == bh - 1:
					c = K6
				elif ry >= bh - 3:
					c = K5
				elif ry <= 1:
					c = K2
				var n := TankMaterial.smooth_noise(cx, y, 3.0, salt + 7)
				if n > 0.7 and y != top:
					c = K3
				elif n < 0.18 and ry > 1 and y != top:
					c = K5
				pen.px(cx, y, c)
			# A riser where the bench above ends, lit by the fires ahead, its foot in shadow.
			if (x_end - cx) % bd == 0 and k_top < benches - 1:
				pen.col(cx, top, top + bh, K5)
				pen.col(cx - 1, top + 1, top + bh, K3)
		for _c in width / 12:
			var kx := rng.randi_range(cut0 + 2, x_end - 4)
			var ky := rng.randi_range(base - ht + 3, base - 4)
			pen.col(kx, ky, ky + rng.randi_range(2, 4), K3)
		var px := x + 2
		while px < cut0 + bd - 2:
			var t := minf(float(px - x) / float(slope_w), 1.0)
			var ty := base - int(float(ht) * smoothstep(0.0, 1.0, t))
			pine(pen, px, ty + 2, rng.randi_range(12, 22), NEAR_TREE)
			px += rng.randi_range(4, 8)
		var c0 := Vector2(x_end - (benches - 1) * bd - 4, base - ht + 2)
		var c1 := Vector2(x_end - 3, base - 2)
		pen.line(c0, c1, K2)
		pen.line(c0 + Vector2(0, 1), c1 + Vector2(0, 1), K3)
		var hx := x_end - 2 * bd + 2
		var hy := base - 2 * bh
		pen.rect(hx, hy - 7, 11, 7, B1)
		pen.rect(hx - 1, hy - 8, 13, 1, K2)
		pen.rect(hx + 4, hy - 5, 2, 2, AMBER)
		return width

	## A timber sawmill burning: a long plank shed, its roof fallen in over a third of its length and
	## fire inside, log stacks beside it.
	static func sawmill(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var bw := rng.randi_range(54, 70)
		var wh := rng.randi_range(11, 14)
		barn(pen, x + 20, base, bw, wh)
		fire_in_roof(pen, rng, x + 20 + bw / 2 - 4, base - wh - 3, rng.randi_range(14, 18))
		pen.rect(x + 25, base - 7, 2, 3, AMBER)
		for k in 3:
			var lx := x + 1 + k * 6
			var lh := 3 - absi(k - 1)
			pen.rect(lx - 1, base - 3 - lh * 2, 7, 3 + lh * 2, B2)
			for e in range(lx, lx + 5, 2):
				pen.px(e, base - 2 - lh, B4)
		hedge(pen, x + 18, x + bw + 26, base + 2)
		return bw + 26

	## Two or three brick works of different roofs (sawtooth, gabled, flat) with irregular groups of
	## lit and dark windows and one glowing furnace door.
	static func works(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var cx := x
		var n := rng.randi_range(2, 3)
		var door_at := rng.randi_range(0, n - 1)
		for k in n:
			var bw := rng.randi_range(28, 46)
			var wh := rng.randi_range(14, 24)
			var top := base - wh
			pen.rect(cx, top, bw, wh, B2 if k % 2 == 0 else R0)
			pen.col(cx, top, base, K2)
			pen.col(cx + bw - 1, top, base, R1)
			pen.rect(cx, base - 2, bw, 2, B1)
			match (k + rng.randi_range(0, 2)) % 3:
				0:
					for t in bw / 8:
						for r in 6:
							pen.rect(cx + t * 8 + r, top - 1 - r, 8 - r, 1, K2)
						pen.px(cx + t * 8, top - 6, S0)
				1:
					for r in 8:
						pen.rect(cx - 1 + r * 2, top - 1 - r, bw + 2 - r * 4, 1, K2)
						pen.px(cx - 1 + r * 2, top - 1 - r, S0)
				_:
					pen.rect(cx - 1, top - 2, bw + 2, 2, K3)
					pen.rect(cx - 1, top - 2, bw + 2, 1, K4)
			_window_groups(pen, rng, cx + 3, top + 4, bw - 6)
			if wh > 19:
				_window_groups(pen, rng, cx + 3, top + 11, bw - 6)
			if k == door_at:
				var dx := cx + rng.randi_range(3, bw - 9)
				pen.rect(dx, base - 8, 6, 8, FIRE)
				pen.rect(dx + 1, base - 7, 4, 7, AMBER)
				pen.rect(dx + 2, base - 4, 2, 4, GLOW)
			cx += bw + rng.randi_range(0, 4)
		return cx - x

	## Two or three groups of window panes of different widths along a wall, some panes dark.
	static func _window_groups(
		pen: Pen, rng: RandomNumberGenerator, x: int, y: int, width: int
	) -> void:
		var gx := x + rng.randi_range(0, 4)
		var groups := rng.randi_range(2, 3)
		for _g in groups:
			var panes := rng.randi_range(1, 4)
			if gx + panes * 3 > x + width:
				break
			var gy := y + rng.randi_range(0, 2)
			for p in panes:
				var c := K1
				var roll := rng.randf()
				if roll < 0.55:
					c = AMBER
				elif roll < 0.7:
					c = GLOW
				pen.rect(gx + p * 3, gy, 2, 2 + rng.randi_range(0, 1), c)
			gx += panes * 3 + rng.randi_range(4, 9)

	## Low sheds and a rail wagon by the works.
	static func sheds(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var bw := rng.randi_range(26, 36)
		var wh := rng.randi_range(9, 12)
		pen.rect(x, base - wh, bw, wh, K3)
		pen.col(x + bw - 1, base - wh, base, K4)
		for r in 4:
			pen.rect(x - 1 + r, base - wh - 1 - r, bw + 2 - r * 2, 1, K2)
		pen.rect(x + 2, base - wh - 4, bw - 4, 1, S0)
		_window_groups(pen, rng, x + 2, base - wh + 3, bw - 4)
		var wx := x + bw + rng.randi_range(5, 9)
		pen.rect(wx, base - 9, 20, 6, B2)
		pen.rect(wx, base - 9, 20, 1, B3)
		pen.rect(wx - 1, base - 3, 22, 1, K2)
		for k: int in [3, 6, 13, 16]:
			pen.rect(wx + k, base - 2, 2, 2, K1)
		return wx + 22 - x

	## One to three brick chimney stacks of different heights, tapering, each with a cap band.
	static func chimneys(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var cx := x + 2
		var n := rng.randi_range(1, 3)
		for _k in n:
			var sh := rng.randi_range(40, 70)
			var sw := rng.randi_range(4, 6)
			for r in sh:
				var y := base - 1 - r
				var w := sw + (1 if r < sh / 3 else 0)
				pen.rect(cx, y, w, 1, R0)
				pen.px(cx, y, K2)
				pen.px(cx + w - 1, y, R1)
			pen.rect(cx - 1, base - sh, sw + 2, 2, K3)
			pen.rect(cx - 1, base - sh, sw + 2, 1, K4)
			for b in range(base - sh + 6, base - 4, 9):
				pen.rect(cx, b, sw, 1, B1)
			cx += sw + rng.randi_range(7, 16)
		pen.rect(x - 2, base - 7, cx - x + 2, 7, B2)
		pen.rect(x - 2, base - 8, cx - x + 2, 1, K2)
		return cx - x

	# --- The depot --------------------------------------------------------------------------------

	## A long hangar: a curved roof over a concrete wall with rain streaks, a dark door with light
	## under it and a caged lamp above.
	static func hangar(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var bw := rng.randi_range(80, 116)
		var wh := rng.randi_range(12, 16)
		var rh := rng.randi_range(10, 14)
		var top := base - wh
		for i in bw:
			var t := (float(i) + 0.5) / float(bw) * 2.0 - 1.0
			var ry := int(float(rh) * sqrt(maxf(1.0 - t * t, 0.0)))
			pen.col(x + i, top - ry, top, K3)
			pen.px(x + i, top - ry, S1 if t < 0.2 else K5)
			pen.px(x + i, top - ry + 1, K4)
			if i % 6 == 3:
				pen.col(x + i, top - ry + 2, top, K2)
		pen.rect(x, top, bw, wh, K5)
		for sx in range(x + 1, x + bw - 1, 3):
			pen.col(sx + rng.randi_range(0, 1), top + 1, top + rng.randi_range(3, wh - 3), K4)
		pen.rect(x, base - 2, bw, 2, K3)
		pen.col(x, top, base, K3)
		var dw := mini(bw / 3, 34)
		var dx := x + rng.randi_range(6, bw - dw - 6)
		pen.rect(dx, top + 2, dw, wh - 2, K1)
		pen.rect(dx, base - 1, dw, 1, AMBER)
		pen.rect(dx + dw / 2, top - 1, 1, 1, AMBER)
		pen.rect(dx + dw / 2 - 1, top - 2, 3, 1, K2)
		return bw

	## Two or three fuel tanks: upright cylinders shaded across their curve, with ring bands and a
	## pipe joining their feet.
	static func fuel_tanks(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var cx := x
		var n := rng.randi_range(2, 3)
		var tones: Array[Color] = [K2, K3, K4, K5, K6, K5, K4]
		for _k in n:
			var tw := rng.randi_range(14, 22)
			var th := rng.randi_range(15, 26)
			for i in tw:
				var t := float(i) / float(tw - 1)
				var ti := clampi(int(t * float(tones.size() - 1) + 0.5), 0, tones.size() - 1)
				var dome := int(3.0 * sqrt(maxf(1.0 - pow(t * 2.0 - 1.0, 2.0), 0.0)))
				pen.col(cx + i, base - th - dome, base, tones[ti])
				pen.px(cx + i, base - th - dome, S1 if t > 0.3 and t < 0.7 else K5)
			for b in range(base - th + 4, base - 1, 6):
				pen.rect(cx, b, tw, 1, K3)
			cx += tw + rng.randi_range(3, 8)
		pen.rect(x, base - 3, cx - x, 1, K3)
		pen.rect(x, base - 2, cx - x, 1, K4)
		return cx - x

	## A long-span gantry crane: an A-frame of two splayed legs at each end, a trussed girder over
	## them, a trolley riding under the girder with its hook drawn up tight beneath it (nothing hangs
	## below), a cab with a lit window at one end, rails and crates on the ground.
	static func gantry_crane(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var span := rng.randi_range(84, 108)
		var ht := rng.randi_range(42, 54)
		var gy := base - ht
		for ex: int in [x + 7, x + 7 + span]:
			for side: int in [-1, 1]:
				var foot := Vector2(ex + side * 7, base)
				var head := Vector2(ex + side, gy + 5)
				pen.line(foot, head, K3)
				pen.line(foot + Vector2(1, 0), head + Vector2(1, 0), K4 if side > 0 else K3)
			pen.rect(ex - 4, base - ht / 2, 9, 1, K3)
		pen.rect(x, gy, span + 15, 5, K3)
		pen.rect(x, gy, span + 15, 1, K5)
		pen.rect(x, gy + 4, span + 15, 1, K2)
		var zx := x + 1
		var up := true
		while zx < x + span + 12:
			pen.line(Vector2(zx, gy + (1 if up else 3)), Vector2(zx + 3, gy + (3 if up else 1)), K2)
			zx += 3
			up = not up
		var tx := x + 7 + int(float(span) * rng.randf_range(0.25, 0.7))
		pen.rect(tx, gy + 5, 8, 4, K2)
		pen.rect(tx, gy + 5, 8, 1, K4)
		pen.rect(tx + 3, gy + 9, 2, 1, K1)
		pen.px(tx + 5, gy + 10, K1)
		pen.rect(x + span + 3, gy + 5, 7, 6, K3)
		pen.rect(x + span + 5, gy + 7, 2, 2, AMBER)
		pen.rect(x - 2, base - 1, span + 20, 1, K4)
		var bx := tx - rng.randi_range(4, 12)
		pen.rect(bx, base - 6, 8, 6, B2)
		pen.rect(bx + 9, base - 5, 7, 5, B1)
		pen.rect(bx, base - 6, 8, 1, B3)
		return span + 16

	## A concrete bunker: a low chamfered block half buried in earth, a dark firing slit with a lit
	## lip under it.
	static func bunker(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var bw := rng.randi_range(34, 48)
		var bh := rng.randi_range(12, 16)
		for i in bw:
			var ch := mini(mini(i, bw - 1 - i), 4)
			var top := base - bh + 4 - ch
			pen.col(x + i, top, base, K5 if i < bw - 4 else K4)
			pen.px(x + i, top, S1)
		var sx := x + rng.randi_range(6, bw - 20)
		pen.rect(sx, base - bh + 6, 14, 2, K0)
		pen.rect(sx, base - bh + 8, 14, 1, K6)
		for e: Vector2i in [Vector2i(x - 9, 11), Vector2i(x + bw - 4, 13)]:
			for i in e.y:
				var t := float(i) / float(e.y)
				var eh := int(6.0 * sin(t * PI))
				pen.col(e.x + i, base - eh, base, B1)
				pen.px(e.x + i, base - eh, B2)
		return bw + 9

	## A floodlight mast: a tapering lattice mast with zigzag bracing and a head frame of cold lamps.
	static func floodlight_mast(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var ht := rng.randi_range(56, 70)
		var top := base - ht
		pen.line(Vector2(x - 3, base), Vector2(x, top), K3)
		pen.line(Vector2(x + 3, base), Vector2(x + 1, top), K4)
		var y := base - 3
		var left := true
		while y > top + 3:
			var k := float(base - y) / float(ht)
			var hw := 3.0 * (1.0 - k) + 0.5
			var a := Vector2(x + 0.5 - hw if left else x + 0.5 + hw, y)
			var b := Vector2(x + 0.5 + hw if left else x + 0.5 - hw, y - 5)
			pen.line(a, b, K3)
			y -= 5
			left = not left
		pen.rect(x - 5, top - 1, 12, 2, K3)
		pen.rect(x - 5, top - 3, 12, 2, K2)
		for k in 4:
			pen.px(x - 4 + k * 3, top - 2, COLD_LIGHT)
			pen.px(x - 3 + k * 3, top - 2, COLD)
		return 14

	## A dark ridge the quarry is cut into, rising and falling behind the near flank with far pines
	## along its crest.
	static func ridge(pen: Pen, rng: RandomNumberGenerator, lo: int, hi: int, hz: int) -> void:
		var salt := rng.randi_range(0, 999)
		for x in range(lo - 20, hi + 20):
			var fade := clampf(float(mini(x - lo + 20, hi + 20 - x)) / 40.0, 0.0, 1.0)
			var n := TankMaterial.smooth_noise(x, 0, 70.0, salt) * 0.7
			n += TankMaterial.smooth_noise(x, 0, 19.0, salt + 1) * 0.3
			var rise := int(fade * (6.0 + 26.0 * n))
			if rise <= 1:
				continue
			var ty := hz + 2 - rise
			pen.col(x, ty, hz + 3, K3)
			pen.px(x, ty, S0 if Pen.bayer(x, ty) < 0.5 else K4)
			pen.px(x, ty + 1, K4)
			if rise > 10 and TankMaterial.smooth_noise(x, 3, 6.0, salt + 2) > 0.62:
				pen.col(x, ty - 3, ty, K3)
				pen.px(x, ty - 4, K4)

	## A massive concrete block of the depot: a tall flat-roofed tower with slit windows, a lower
	## wing, rain streaks, a dark door under a caged amber lamp.
	static func block(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var bw := rng.randi_range(26, 40)
		var bh := rng.randi_range(26, 40)
		var top := base - bh
		var ww := rng.randi_range(16, 26)
		var wh := bh / 2
		pen.rect(x + bw, base - wh, ww, wh, K4)
		pen.rect(x + bw, base - wh, ww, 1, K5)
		pen.rect(x + bw + 3, base - wh + 4, ww - 6, 1, K1)
		pen.rect(x, top, bw, bh, K5)
		for sx in range(x + 1, x + bw - 1, 2):
			if rng.randf() < 0.55:
				pen.col(sx, top + 2, top + rng.randi_range(5, bh - 4), K4)
		pen.col(x, top, base, K3)
		pen.col(x + bw - 1, top, base, K6)
		pen.rect(x - 1, top - 2, bw + 2, 2, K4)
		pen.rect(x - 1, top - 2, bw + 2, 1, S1)
		for r in range(top + 5, base - 10, 7):
			pen.rect(x + 4, r, bw - 8, 1, K1)
		var lx := x + bw / 2
		pen.rect(lx - 3, base - 8, 6, 8, K1)
		pen.rect(lx - 1, base - 11, 3, 1, K2)
		pen.px(lx, base - 10, AMBER)
		pen.px(lx - 1, base - 10, K2)
		pen.px(lx + 1, base - 10, K2)
		return bw + ww

	# --- Power line -----------------------------------------------------------------------------------

	## Lattice pylons every 120-160 px from lo to hi with three conductors sagging from each pylon to
	## the next (none hangs free: the line starts and ends at a pylon).
	static func pylon_line(
		pen: Pen, rng: RandomNumberGenerator, lo: int, hi: int, base: int
	) -> void:
		var xs: Array[int] = []
		var x := lo + rng.randi_range(10, 40)
		while x < hi - 10:
			xs.append(x)
			x += rng.randi_range(120, 160)
		var tips: Array[Array] = []
		for px in xs:
			tips.append(pylon(pen, px, base, rng.randi_range(52, 62)))
		for i in range(1, xs.size()):
			var a: Array = tips[i - 1]
			var b: Array = tips[i]
			for k in a.size():
				pen.wire(a[k], b[k], rng.randf_range(7.0, 10.0), K2)

	## One lattice pylon `ht` px tall on `base`: two legs converging to a waist, zigzag bracing, a
	## wide lower arm and a short upper arm. Returns its three conductor points.
	static func pylon(pen: Pen, x: int, base: int, ht: int) -> Array:
		var top := base - ht
		var waist := top + 12
		pen.line(Vector2(x - 7, base), Vector2(x - 1, waist), K3)
		pen.line(Vector2(x + 7, base), Vector2(x + 1, waist), K4)
		pen.line(Vector2(x - 1, waist), Vector2(x, top), K3)
		pen.line(Vector2(x + 1, waist), Vector2(x + 1, top), K4)
		var y := base - 4
		var left := true
		while y > waist + 2:
			var k := float(base - y) / float(base - waist)
			var hw := 7.0 * (1.0 - k) + 1.0 * k
			var a := Vector2(x - hw if left else x + hw, y)
			var b := Vector2(x + hw if left else x - hw, y - 6)
			pen.line(a, b, K3)
			y -= 6
			left = not left
		pen.rect(x - 9, waist, 19, 1, K3)
		pen.rect(x - 6, top + 4, 13, 1, K3)
		pen.px(x - 9, waist + 1, K5)
		pen.px(x + 9, waist + 1, K5)
		pen.px(x + 6, top + 5, K5)
		return [Vector2(x - 9, waist + 2), Vector2(x + 9, waist + 2), Vector2(x + 6, top + 6)]
