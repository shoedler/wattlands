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
const SMOKE_RISE_PX := 175.0
const SMOKE_PUFFS := 10
const ASH_FLECKS := 48
## The columns' smoke: warm umber at the base (fire-lit), grey at the top.
const SMOKE_TONE := Color("#43362e")
const SMOKE_TOP := Color("#3f4246")
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
	for s: ParallaxStrip in [sky, hills, near, ground, debris]:
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
## float, "color": Color, "intensity": float, "fire": bool, "seed": int}]. Pure and deterministic:
## each cell of the plane hashes to the same lights every time, with no RNG and no state.
static func scenery(id: String, cam_x: float, width: float = 640.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var scroll := roundf(cam_x * NEAR_FACTOR)
	var first := int(floor(scroll / CELL_PX)) - 1
	var last := int(floor((scroll + width) / CELL_PX)) + 1
	for cell in range(first, last + 1):
		var h := cell_hash(cell, id.hash())
		var x := float(cell) * CELL_PX + float(h % 100) * 1.2 - scroll + 15.0
		match id:
			"bg_fields_near":
				if h % 4 == 0:
					out.append(_light(x, 262.0, 46.0, TankPalette.FIRE, 0.55, true, h))
					out.append(_light(x, 258.0, 16.0, TankPalette.GLOW_WARM, 0.5, false, h))
				elif h % 4 == 1:
					out.append(_light(x, 256.0, 28.0, TankPalette.AMBER, 0.32, false, h))
			"bg_village_near":
				if h % 3 != 0:
					out.append(
						_light(x, 244.0 + float(h % 18), 30.0, TankPalette.AMBER, 0.38, false, h)
					)
					out.append(
						_light(
							x + 22.0,
							250.0 + float(h % 11),
							24.0,
							TankPalette.GLOW_WARM,
							0.32,
							false,
							h
						)
					)
				if h % 5 == 0:
					out.append(_light(x + 40.0, 262.0, 30.0, TankPalette.FIRE, 0.4, true, h))
			"bg_quarry_near":
				if h % 3 == 0:
					out.append(
						_light(
							x, 226.0 + float(h % 14), 24.0, TankPalette.COLD_LIGHT, 0.4, false, h
						)
					)
				if h % 6 == 1:
					out.append(_light(x, 268.0, 50.0, TankPalette.FIRE, 0.5, true, h))
			"bg_town_near":
				out.append(_light(x, 252.0, 40.0, TankPalette.AMBER, 0.4, false, h))
				out.append(_light(x + 55.0, 256.0, 32.0, TankPalette.GLOW_WARM, 0.32, false, h))
				if h % 5 == 0:
					out.append(_light(x + 20.0, 240.0, 64.0, TankPalette.FIRE, 0.35, true, h))
			"bg_depot_near":
				if h % 3 == 0:
					out.append(_light(x, 232.0, 36.0, TankPalette.COLD_LIGHT, 0.5, false, h))
				out.append(_light(x + 30.0, 258.0, 30.0, TankPalette.AMBER, 0.32, false, h))
	return out


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
			var size := 14.0 + u * 80.0
			var c := (
				at + Vector2(u * u * 60.0 + sin(u * 5.0 + float(sd % 5)) * 5.0, -u * SMOKE_RISE_PX)
			)
			# Smoke lit from below by its fire: warm umber low down, cooling to grey as it climbs and
			# thins; a step lighter than the cloud so the columns read against the dusk sky.
			var tone := SMOKE_TONE.lerp(SMOKE_TOP, u)
			var a := 0.9 * smoothstep(0.0, 0.08, u) * (1.0 - u * 0.55)
			var r := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
			item.draw_texture_rect(puff, r, false, Color(tone.r, tone.g, tone.b, a))
	for i in ASH_FLECKS:
		var h := cell_hash(i, 911)
		var x := (
			fposmod(float(h % 640) - time * (6.0 + float(h % 5)) - _scroll_x * 0.3, 660.0) - 10.0
		)
		var y := fposmod(float((h >> 9) % 240) + time * (4.0 + float((h >> 3) % 4)), 230.0) + 40.0
		var a := 0.25 + 0.25 * float(h % 3) / 2.0
		item.draw_rect(Rect2(floorf(x), floorf(y), 1, 1), Color(0.42, 0.42, 0.43, a))


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
	var clear := Color(warm.r, warm.g, warm.b, 0.0)
	var mid := Color(warm.r, warm.g, warm.b, 0.32)
	var bot := Color(TankPalette.HAZE.r, TankPalette.HAZE.g, TankPalette.HAZE.b, 0.45)
	var pts := PackedVector2Array(
		[Vector2(0, 196), Vector2(640, 196), Vector2(640, 236), Vector2(0, 236)]
	)
	item.draw_polygon(pts, PackedColorArray([clear, clear, mid, mid]))
	pts = PackedVector2Array(
		[Vector2(0, 236), Vector2(640, 236), Vector2(640, 300), Vector2(0, 300)]
	)
	item.draw_polygon(pts, PackedColorArray([mid, mid, bot, bot]))
