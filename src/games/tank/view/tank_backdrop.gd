class_name TankBackdrop
extends Node2D
## The diorama's planes in depth (brief 3 "Layout", "Depth of field"), back to front: the sky 0.05
## with a cold moonlight behind its far smoke bank, a smoke ceiling and a nearer bank whose
## undersides the fires light, a far ridge 0.14, drifting smoke sheets, the hills 0.2 with fires
## burning on their crests, each sending up a billowing smoke column that widens into the clouds,
## the haze, the near plane 0.5 (fields, village, quarry, foundry town or depot, by segment; composed
## once without mirroring, NearPlane), the ground 1.0 (the tank's plane) with its road (wet ruts,
## puddles, cobbles in the village) and, in front of everything, the foreground 1.3: a dark,
## strongly blurred rubble bank under the bottom HUD band with sparse wreckage (stakes and wire, a
## shattered stump, a broken wall) rising out of it at the frame's edges. Every plane but the ground
## is pre-blurred once (TankBlur) and hazed; `front` holds the foreground and is added by the view
## above the tank. Scenery lights (burning farms, lit windows, foundry lamps, floodlights) are
## computed here as plain data from the plane's scroll. Nothing here creates a texture after load.

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
## Fire sites on the hills' slopes: HILL_FIRES candidate sites per hills tile, one per equal
## stretch. Each segment (set_segment) lights a seeded subset: one in every three neighbouring sites
## burns, some of the rest only smoulder and the others stay dark, so a screen shows one or two
## fires and no two gun lines put them at the same screen spots (polish round 6: the same three
## fires stood at the same x in every scene). Each sends up smoke that widens into the banks.
const HILL_FIRES := 6
## The hill fires' pictures, baked once: FIRE_VARIANTS irregular, asymmetric burning ruins (a
## broken gable, a collapsed barn, a hedge, a copse: each its own width, lean, height and ragged
## flame profile, never evenly spaced prongs on a bar), FIRE_FRAMES flicker frames each, plus one
## smouldering ember bed per variant; FIRE_W x FIRE_H px with the burning bed at FIRE_BED_Y.
## Blurred and hazed like the hills (FIRE_BLUR: the hills' own blur and haze, without darkening),
## so a fire is a soft glow on its ridge, never a pixel-sharp stamp on a blurred plane (polish
## round 6: a crisp three-prong stamp read as a crown).
const FIRE_VARIANTS := 8
const FIRE_FRAMES := 3
const FIRE_W := 44
const FIRE_H := 36
const FIRE_BED_Y := 29
const FIRE_BLUR := {"down": 4, "box_r": 0, "passes": 1, "haze": 0.2, "darken": 0.0}
const SMOKE_FACTOR := HILLS_FACTOR
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
## The moon behind the far smoke bank: a cold glow at MOON_POS on the sky's plane whose light the
## bank's thin edges let through (a moonlit cloud edge, never a disc).
const MOON_POS := Vector2(520.0, 46.0)
const MOON_PERIOD_PX := 1500.0
## Distant fires' glow on the near bank's undersides: one chance per this many bank px.
const GLOW_CELL_PX := 360.0
## The near plane's landmark (its strip's centre) stands at this screen x when a location starts.
const LANDMARK_X := 470.0
## The columns' smoke: dense soot at the base (silhouetted on the horizon's fire glow, which lights
## its underside), thinning into lit grey as it climbs into the dark sky.
const SMOKE_TONE := Color("#0f1012")
const SMOKE_TOP := Color("#35373b")
## Ash flecks: two-pixel grey flakes, never near-white specks.
const ASH_COLOR := Color("#525456")
## The foreground plane: FRONT_W x FRONT_H px whose bottom sits at FRONT_BOTTOM_Y. Its rubble bank
## stays under the bottom HUD band (its lumpy top at y FRONT_BANK_Y and below, polish round 5: a
## continuous bank at y 286-300 laid a black blanket over the ground line, the skirts, the enemies'
## hulls and the Behemoth's bogies); only a few wrecks spaced far apart rise out of it, to y ~250 at
## most. Built once, then blurred (FRONT_BLUR, about 5 art px) and darkened: an out-of-focus layer.
const FRONT_W := 2880
const FRONT_H := 96
const FRONT_BOTTOM_Y := 340.0
const FRONT_BANK_Y := 303.0
const FRONT_BLUR := {"down": 2, "box_r": 1, "passes": 2, "haze": 0.0, "darken": 0.25}
## The road on the ground plane: a ROAD_W x ROAD_H strip (tiling unmirrored) whose top is at
## ROAD_TOP_Y, so the ground line y 296 runs along its wet ruts.
const ROAD_TOP_Y := 286.0
const ROAD_W := 1280
const ROAD_H := 17
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
static var _crest: PackedInt32Array = PackedInt32Array()
static var _fire_sites: Array[int] = []
static var _fire_tex: Array[Texture2D] = []
static var _roads: Dictionary = {}

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
## The smoke ceiling strip.
var ceiling: ParallaxStrip = null
## Seconds of animation (the smoke columns, ash and embers drift with it; cosmetic only).
var time: float = 0.0
## The hill fires' halos and embers (additive), over their columns, under the near plane.
var horizon_lights: TankLights = null
## The moon's cold light behind the far smoke bank (additive).
var moon_light: TankLights = null
## The road painter on the ground plane (ruts, puddles, cobbles).
var road: TankPainter = null
## Times a near strip was swapped (tests).
var swaps: int = 0
## The segment the far planes are laid out for (set_segment), its salt for the hill fires, and the
## hills plane's extra scroll for it: each segment opens on its own stretch of hills, sky and smoke.
var segment_index: int = -999
var segment_salt: int = 0
var hills_offset: float = 0.0

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
	for style: String in ["mud", "cobbles", "slabs"]:
		road_texture(style)
	var sky_top := TankPainter.new()
	sky_top.name = "SkyTop"
	sky_top.painter = _paint_sky_top
	add_child(sky_top)
	sky = _strip("Sky", "bg_sky", "sky", SKY_FACTOR, SKY_TOP_Y, false)
	add_child(sky)
	moon_light = TankLights.new()
	moon_light.name = "MoonLight"
	add_child(moon_light)
	banks.append(_bank_strip(0))
	add_child(banks[0])
	far_ridge = ParallaxStrip.new()
	far_ridge.name = "FarRidge"
	far_ridge.texture = far_ridge_texture()
	far_ridge.factor = FAR_RIDGE_FACTOR
	far_ridge.position.y = FAR_RIDGE_BOTTOM_Y
	far_ridge.align_bottom = true
	far_ridge.cover_width = float(TankConst.SCREEN_W)
	far_ridge.auto_process = false
	add_child(far_ridge)
	# The pall over the upper sky and the nearer bank under it.
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
	# The horizon glowing with the fires beyond it, so the hills stand dark against it.
	var horizon := TankPainter.new()
	horizon.name = "HorizonGlow"
	horizon.painter = _paint_horizon
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	horizon.material = add
	add_child(horizon)
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
	# The hill fires and their columns stand in front of the haze, so each fire is seen burning
	# under its smoke.
	_smoke = TankPainter.new()
	_smoke.name = "SkySmoke"
	_smoke.painter = _paint_smoke
	add_child(_smoke)
	horizon_lights = TankLights.new()
	horizon_lights.name = "HorizonLights"
	add_child(horizon_lights)
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
	road = TankPainter.new()
	road.name = "Road"
	road.painter = _paint_road
	add_child(road)
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


## Lays the far planes out for segment `index` (the view calls it every frame; only a change does
## anything): a seeded salt picks which hill sites burn and how their smoke rises, and the sky, the
## smoke ceiling and banks, the far ridge and the hills each start at a seeded scroll, so the hull's
## x restarting at 0 in every segment never brings back the same picture (polish round 6: the gun
## lines all showed the same fires and columns at the same screen x).
func set_segment(index: int) -> void:
	if index == segment_index:
		return
	segment_index = index
	var k := index + 7
	segment_salt = cell_hash(k, 7411) % 65521
	hills_offset = float(cell_hash(k, 5023) % int(hills.period()))
	hills.offset_x = hills_offset
	far_ridge.offset_x = float(cell_hash(k, 5039) % FAR_RIDGE_W)
	sky.offset_x = float(cell_hash(k, 5051) % int(sky.period()))
	ceiling.offset_x = float(cell_hash(k, 5077) % int(ceiling.period()))
	for i in banks.size():
		banks[i].offset_x = float(cell_hash(k, 5101 + i) % BANK_W)


## The near strip's offset_x that puts a tile's centre (its landmark) at LANDMARK_X for camera x
## `cam_x` (0 .. tex_w).
static func landmark_offset(tex_w: float, cam_x: float) -> float:
	return fposmod(tex_w * 0.5 - LANDMARK_X - roundf(cam_x * NEAR_FACTOR), tex_w)


## Advances the hill fires' smoke, ash, embers, the fires' light on the clouds and the moonlight by
## `dt` seconds (cosmetic, view time).
func advance(dt: float) -> void:
	time += dt
	ceiling.tick(dt)
	for b in banks:
		b.tick(dt)
	moon_light.begin()
	var sky_scroll := _scroll_x * SKY_FACTOR + sky.offset_x
	var mx := fposmod(MOON_POS.x - sky_scroll + 300.0, MOON_PERIOD_PX) - 300.0
	moon_light.add(Vector2(mx, MOON_POS.y), 170.0, TankPalette.COLD, 0.16)
	moon_light.add(Vector2(mx, MOON_POS.y), 80.0, TankPalette.COLD_LIGHT, 0.14)
	moon_light.add(Vector2(mx + 4.0, MOON_POS.y + 2.0), 30.0, TankPalette.WHITE_COLD, 0.1)
	moon_light.end()
	horizon_lights.begin()
	cloud_glow.begin()
	for col in columns():
		var at: Vector2 = col["pos"]
		var sd := int(col["seed"])
		var flick := 0.85 + 0.15 * sin(time * 2.3 + float(sd % 17))
		var lean: float = col["lean"]
		if not bool(col["burning"]):
			# A smouldering ruin: a dull red glow under its thin smoke.
			horizon_lights.add(at + Vector2(0, -2), 16.0, TankPalette.RUST_LIGHT, 0.2 * flick)
			continue
		horizon_lights.add(at + Vector2(0, -4), 40.0, TankPalette.FIRE, 0.3 * flick)
		horizon_lights.add(at + Vector2(0, -3), 13.0, TankPalette.AMBER, 0.3 * flick)
		# The fire lights the underside of its own smoke above it.
		var lift := at + Vector2(lean * 0.06, -20.0)
		horizon_lights.add(lift, 22.0, TankPalette.RUST_LIGHT, 0.22 * flick)
		horizon_lights.add(at + Vector2(lean * 0.15, -38.0), 30.0, TankPalette.FIRE, 0.08 * flick)
		for k in 3:
			var u := fposmod(time * 0.11 + float(k) / 3.0 + float(sd % 7) * 0.1, 1.0)
			var e := at + Vector2(sin(u * 9.0 + float(k)) * 5.0 + u * 14.0, -6.0 - u * 60.0)
			horizon_lights.add(e, 2.0, TankPalette.AMBER, 0.6 * (1.0 - u))
		# The fire's light on the banks' undersides above it, where its column spreads into them.
		var rise: float = col["rise"]
		var top := at + Vector2(lean, -rise)
		cloud_glow.add(top + Vector2(-lean * 0.2, 34.0), 110.0, TankPalette.FIRE, 0.12 * flick)
		cloud_glow.add(top + Vector2(-lean * 0.4, 58.0), 60.0, TankPalette.RUST_LIGHT, 0.14 * flick)
	_distant_glows()
	horizon_lights.end()
	cloud_glow.end()
	_smoke.queue_redraw()
	_sheets.queue_redraw()


## Fires beyond the hills light the near smoke bank's undersides here and there: a broad, faint warm
## glow low in the bank every GLOW_CELL_PX or so (some cells dark), drifting with the bank and
## seeded per segment, so the upper sky has lit cloud undersides even where no hill fire burns in
## view (polish round 6: the top 40% of the frame was empty dark sky).
func _distant_glows() -> void:
	var scroll := banks[1].scroll()
	var first := int(floor((scroll - 240.0) / GLOW_CELL_PX))
	var last := int(floor((scroll + float(TankConst.SCREEN_W) + 240.0) / GLOW_CELL_PX))
	for c in range(first, last + 1):
		var h := cell_hash(c + segment_salt * 3, 6007)
		if h % 3 == 0:
			continue
		var at := Vector2(
			float(c) * GLOW_CELL_PX + float(h % 220) - scroll, 84.0 + float((h >> 8) % 44)
		)
		var k := 0.85 + 0.15 * sin(time * 0.7 + float(h % 23))
		cloud_glow.add(
			at, 120.0 + float((h >> 4) % 70), TankPalette.FIRE, (0.1 + 0.03 * float(h % 3)) * k
		)
		var under := at + Vector2(float((h >> 12) % 60) - 30.0, 16.0)
		cloud_glow.add(under, 54.0 + float((h >> 15) % 30), TankPalette.RUST_LIGHT, 0.14 * k)


## This frame's hill fire columns (smoke_columns for the camera and the segment's layout).
func columns() -> Array[Dictionary]:
	return smoke_columns(_scroll_x, float(TankConst.SCREEN_W), segment_salt, hills_offset)


## The hill fires' smoke columns for camera x `cam_x`, segment salt `salt` and hills offset `offset`
## (set_segment): [{"pos": Vector2 (the fire on the hills' slope, screen), "seed": int, "burning":
## bool (else it only smoulders), "variant": int (its picture, hill_fire_textures), "rise": float
## (px), "width": float (scale), "lean": float (px downwind at the top; now and then a little
## upwind)}]: one per lit fire site (hill_fire_sites, site_state) on every hills tile in view,
## placed as the mirrored hills strip draws that tile, with height, width and lean by hash (no RNG):
## some tall and thin, some short and broad, each bending its own way; a smouldering site sends up
## a thinner, shorter wisp.
static func smoke_columns(
	cam_x: float, width: float = 640.0, salt: int = 0, offset: float = 0.0
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var crest := hill_crest()
	var sites := hill_fire_sites()
	var w := float(crest.size())
	if w <= 0.0:
		return out
	var n := sites.size()
	var top := HILLS_BOTTOM_Y - float(TankBlur.plane("bg_hills_far", "hills").get_height())
	var scroll := roundf(cam_x * HILLS_FACTOR + offset)
	var i := int(floor(scroll / w)) - 1
	var x0 := float(i) * w - scroll
	while x0 < width + 160.0:
		var flipped := posmod(i, 2) == 1
		for k in n:
			var sx: int = sites[k]
			var x := x0 + (w - 1.0 - float(sx) if flipped else float(sx))
			if x < -160.0 or x > width + 160.0:
				continue
			var g := i * n + (n - 1 - k if flipped else k)
			var lit := site_state(g, salt)
			if lit == 0:
				continue
			var h := cell_hash(g * 31 + salt, 4517)
			var burning := lit == 2
			var lean := 8.0 + float((h >> 13) % 86)
			if (h >> 3) % 5 == 0:
				lean = -0.3 * lean
			var col := {
				"pos": Vector2(x, top + float(crest[sx]) + 3.0 + float((h >> 17) % 9)),
				"seed": h,
				"burning": burning,
				"variant": (h >> 21) % FIRE_VARIANTS,
				"rise": (95.0 + float((h >> 5) % 90)) * (1.0 if burning else 0.6),
				"width": (0.75 + float((h >> 9) % 8) * 0.09) * (1.0 if burning else 0.55),
				"lean": lean,
			}
			out.append(col)
		x0 += w
		i += 1
	return out


## Whether hill site `g` (its index along the hills, left to right) burns (2), smoulders (1) or is
## dark (0) for segment salt `salt`: of every three neighbouring sites one burns, at a place in the
## three picked by hash (so fires stand 160 to 800 hills px apart, one or two on a screen), and a
## third of the rest smoulder.
static func site_state(g: int, salt: int) -> int:
	var group := int(floor(float(g) / 3.0))
	if posmod(g, 3) == cell_hash(group + salt * 7, 3359) % 3:
		return 2
	return 1 if cell_hash(g + salt * 13, 3371) % 3 == 0 else 0


## The hill fires' pictures (FIRE_VARIANTS), baked and blurred once: index v * FIRE_FRAMES + f is
## variant v's flicker frame f, FIRE_VARIANTS * FIRE_FRAMES + v its smouldering bed.
static func hill_fire_textures() -> Array[Texture2D]:
	if not _fire_tex.is_empty():
		return _fire_tex
	var shapes: Array[Dictionary] = []
	for v in FIRE_VARIANTS:
		shapes.append(fire_shape(v))
	for v in FIRE_VARIANTS:
		for f in FIRE_FRAMES:
			_fire_tex.append(_baked_fire(shapes[v], f, false))
	for v in FIRE_VARIANTS:
		_fire_tex.append(_baked_fire(shapes[v], 0, true))
	return _fire_tex


static func _baked_fire(shape: Dictionary, frame: int, smoulder: bool) -> Texture2D:
	var img := hill_fire_image(shape, frame, smoulder)
	return ImageTexture.create_from_image(TankBlur.blurred_image(img, FIRE_BLUR, TankPalette.HAZE))


## Hill fire variant `v`'s shape: what burns ("gable": a house with one gable end standing, "barn":
## a long barn with its roof fallen in, "hedge": a hedgerow, "copse": a clump of trees beside a
## shed), the burning bed's width and place, where along it the flames stand tallest (never the
## middle: the mass is lopsided), their height, lean (px per px of height, downwind) and the salt
## of their ragged top.
static func fire_shape(v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (v + 3)
	var kinds: Array[String] = ["gable", "barn", "hedge", "copse"]
	var peak := rng.randf_range(0.16, 0.36)
	if v % 2 == 1:
		peak = 1.0 - peak
	return {
		"ruin": kinds[v % kinds.size()],
		"bed": rng.randi_range(9, 19),
		"cx": rng.randi_range(-4, 4),
		"peak": peak,
		"tall": rng.randi_range(7, 16),
		"lean": rng.randf_range(0.1, 0.55),
		"salt": rng.randi_range(1, 9999),
		"ruin_w": rng.randi_range(13, 22),
		"ruin_h": rng.randi_range(4, 8),
	}


## Variant `shape`'s picture before the blur (FIRE_W x FIRE_H): the burning ruin's silhouette
## standing on the hills (they are its ridge; the picture adds no ground of its own), and the fire, an
## irregular, lopsided mass: per column of its bed a height from a skewed envelope times a coarse
## noise (frame `frame` shifts the noise: the flicker), each row shifted downwind by the lean, amber
## low in its heart and orange above, with a loose lick here and there over the tips. Smouldering:
## a lumpy, unbroken bed of dull embers heaped off-centre, with no flames (never two separate
## dots, which read as eyes, nor an even bar).
static func hill_fire_image(shape: Dictionary, frame: int, smoulder: bool) -> Image:
	var img := Image.create(FIRE_W, FIRE_H, false, Image.FORMAT_RGBA8)
	var by := FIRE_BED_Y
	var salt := int(shape["salt"])
	var tall := float(shape["tall"])
	var lean := float(shape["lean"])
	var cx := FIRE_W / 2 + int(shape["cx"]) - int(lean * tall * 0.4)
	_ruin(img, str(shape["ruin"]), cx, int(shape["ruin_w"]), int(shape["ruin_h"]), salt)
	var bed := int(shape["bed"]) + (4 if smoulder else 0)
	var x0 := cx - bed / 2
	var peak := float(shape["peak"])
	var ph := float(frame) * 5.3
	for i in bed:
		var t := (float(i) + 0.5) / float(bed)
		var tp := t / peak * 0.5 if t < peak else 0.5 + (t - peak) / (1.0 - peak) * 0.5
		var env := pow(sin(PI * tp), 0.8)
		var nz := pnoise(float(i) + ph, float(frame) * 3.0, 2.3, 4096, salt)
		if smoulder:
			# A low, lumpy ember bed: unbroken along the bed row, heaped up off-centre where it is
			# hottest (never a flat bar of even height), mostly dull red, a hot pixel here and there.
			var heap := int(roundf(3.0 * env * nz))
			_put(img, x0 + i, by, TankPalette.with_alpha(TankPalette.RUST_LIGHT, 0.85))
			_put(img, x0 + i, by + 1, TankPalette.with_alpha(TankPalette.RUST, 0.6))
			for y in heap:
				var hot := nz > 0.62 and y == 0
				var c := TankPalette.FIRE if hot else TankPalette.RUST_LIGHT
				_put(img, x0 + i, by - 1 - y, TankPalette.with_alpha(c, 0.75 - 0.15 * float(y)))
			continue
		_put(img, x0 + i, by, TankPalette.FIRE)
		_put(img, x0 + i, by + 1, TankPalette.with_alpha(TankPalette.RUST, 0.85))
		var hh := tall * env * (0.3 + 0.7 * nz)
		hh += 2.5 * pnoise(float(i), ph, 1.1, 4096, salt + 1)
		var rows := int(roundf(hh))
		for y in rows:
			var k := float(y) / maxf(hh, 1.0)
			var wob := 0.7 * sin(float(y) * 0.8 + ph + float(i) * 1.7)
			var x := x0 + i + int(roundf(lean * float(y) + wob))
			var c := TankPalette.FIRE
			if k < 0.5 and t > 0.12 and t < 0.88:
				c = TankPalette.AMBER
			if k < 0.2 and absf(t - peak) < 0.14:
				c = TankPalette.GLOW_WARM
			var fade := 1.0 - 0.45 * smoothstep(0.6, 1.0, k)
			_put(img, x, by - 1 - y, TankPalette.with_alpha(c, fade))
		# Now and then a loose lick of flame over a tip.
		if rows > 3 and cell_hash(i * 5 + frame, salt) % 4 == 0:
			var lx := x0 + i + int(roundf(lean * float(rows + 2)))
			var ly := by - 2 - rows - cell_hash(i, salt + 3) % 2
			_put(img, lx, ly, TankPalette.with_alpha(TankPalette.FIRE, 0.7))
	return img


## The burning ruin's dark silhouette standing on the bed row FIRE_BED_Y around `cx`, `rw` x `rh`
## px, by `kind` (fire_shape); its upper edge catches the fire (rust). Ragged everywhere: no post,
## no bar, nothing symmetric.
static func _ruin(img: Image, kind: String, cx: int, rw: int, rh: int, salt: int) -> void:
	var by := FIRE_BED_Y
	var dark := Color("#17191c")
	var x0 := cx - rw / 2
	for i in rw:
		var t := (float(i) + 0.5) / float(rw)
		var jag := int(2.0 * pnoise(float(i), 1.0, 2.0, 512, salt + 7))
		var top := by - rh + jag
		match kind:
			"gable":
				# One gable end still standing at the left, the rest of the roof gone: broken walls.
				if t < 0.3:
					top = by - rh - int(5.0 * (1.0 - absf(t - 0.15) / 0.15)) + jag / 2
				else:
					top = by - rh + 2 + jag
			"barn":
				# A long barn, its roof sagging into the middle where it fell in.
				top = by - rh + int(3.5 * sin(t * PI)) + jag / 2
			"hedge":
				top = by - 2 - int(3.0 * pnoise(float(i), 2.0, 3.0, 512, salt + 9))
			"copse":
				# A low shed at the fire and a lumpy clump of tree crowns behind it to one side.
				top = by - rh + 2 + jag
				if t > 0.55:
					var u := (t - 0.55) / 0.45
					var crown := 7.0 * sin(u * PI) + 2.0 * pnoise(float(i), 3.0, 2.0, 512, salt)
					top = by - rh - int(crown)
		for y in range(top, by + 1):
			_put(img, x0 + i, y, dark)
		_put(img, x0 + i, top, TankPalette.RUST_DARK)


## Sets a pixel if it lies inside the image.
static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


## The hills plane's crest: per column of its (blurred) texture, the first row that is mostly
## opaque. Found once.
static func hill_crest() -> PackedInt32Array:
	if not _crest.is_empty():
		return _crest
	var img := TankBlur.plane("bg_hills_far", "hills").get_image()
	var out := PackedInt32Array()
	out.resize(img.get_width())
	for x in img.get_width():
		var y := 0
		while y < img.get_height() - 1 and img.get_pixel(x, y).a < 0.6:
			y += 1
		out[x] = y
	_crest = out
	return out


## Where the hill fires burn on a hills tile (texture x): in each of HILL_FIRES equal stretches
## (away from the stretch's ends, so a mirrored pair never burns side by side), a point on a slope
## a little below its highest summit (a farm on the hillside, never a fire crowning a peak).
static func hill_fire_sites() -> Array[int]:
	if not _fire_sites.is_empty():
		return _fire_sites
	var crest := hill_crest()
	var span := crest.size() / HILL_FIRES
	for k in HILL_FIRES:
		var lo := k * span + 40
		var hi := (k + 1) * span - 40
		var top := crest[lo]
		var bottom := crest[lo]
		for x in range(lo, hi):
			top = mini(top, crest[x])
			bottom = maxi(bottom, crest[x])
		var want := float(top) + 0.4 * float(bottom - top)
		var best := lo
		for x in range(lo, hi):
			if absf(float(crest[x]) - want) < absf(float(crest[best]) - want):
				best = x
		_fire_sites.append(best)
	return _fire_sites


## Scrolls every plane to the camera x (world art px).
func set_world_x(x: float) -> void:
	_scroll_x = x
	for s: ParallaxStrip in [sky, ceiling, far_ridge, hills, near, ground, banks[0], banks[1]]:
		if s.world_x != x:
			s.world_x = x
	road.queue_redraw()
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


## The hill fires' smoke columns: soft puffs rising from each fire, billowing side to side and
## widening steadily as they climb, soot lit warm at the foot and thinning into the clouds (no hard
## edge anywhere: two overlapping lobes per step, low alpha), the fire's blurred picture on its
## ridge under them (or a smouldering ruin under a thin grey wisp), and fine ash flecks falling
## through the sky.
func _paint_smoke(item: Node2D) -> void:
	var puff := TankProcTex.puff()
	for col in columns():
		var at: Vector2 = col["pos"]
		var sd := int(col["seed"])
		var rise: float = col["rise"]
		var wk: float = col["width"]
		var lean: float = col["lean"]
		var burning := bool(col["burning"])
		var dense := 1.0 if burning else 0.55
		var base := SMOKE_TONE if burning else TankPalette.darkened(TankPalette.SMOKE, 0.3)
		for k in SMOKE_PUFFS:
			var u := fposmod(
				time * 0.03 + float(k) / float(SMOKE_PUFFS) + float(sd % 11) * 0.09, 1.0
			)
			var size := (5.0 + 86.0 * pow(u, 1.25)) * wk
			var billow := sin(u * 7.0 + float(sd % 5) + time * 0.35) * (1.5 + 11.0 * u)
			var c := at + Vector2(pow(u, 1.7) * lean + billow, -4.0 - u * rise)
			var tone := base.lerp(SMOKE_TOP, smoothstep(0.1, 1.0, u))
			if burning:
				tone = tone.lerp(TankPalette.RUST, 0.55 * (1.0 - smoothstep(0.0, 0.3, u)))
			var a := 0.5 * dense * smoothstep(0.0, 0.07, u) * (1.0 - smoothstep(0.4, 1.0, u))
			var r := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
			item.draw_texture_rect(puff, r, false, TankPalette.with_alpha(tone, a))
			var side := 1.0 if (k * 7 + sd) % 3 != 0 else -1.0
			var lobe := size * (0.5 + 0.03 * float((sd + k) % 5))
			var lc := c + Vector2(side * size * 0.3, size * 0.08)
			var lr := Rect2(lc - Vector2(lobe, lobe) * 0.5, Vector2(lobe, lobe))
			item.draw_texture_rect(puff, lr, false, TankPalette.with_alpha(tone, a * 0.85))
		_hill_fire(item, col)
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


## Draws column `col`'s fire: its variant's blurred picture with the burning bed on the column's
## foot, a flicker frame at the site's own rate, scaled a little per site and mirrored when its
## smoke leans upwind (the flames lean with the smoke); a smouldering site shows its ember bed.
func _hill_fire(item: Node2D, col: Dictionary) -> void:
	var tex := hill_fire_textures()
	var sd := int(col["seed"])
	var v := int(col["variant"])
	var idx := FIRE_VARIANTS * FIRE_FRAMES + v
	if bool(col["burning"]):
		var rate := 4.0 + float(sd % 5)
		idx = v * FIRE_FRAMES + posmod(int(time * rate) + sd % 7, FIRE_FRAMES)
	var s := 0.8 + 0.1 * float((sd >> 7) % 4)
	var size := Vector2(FIRE_W, FIRE_H) * s
	var at: Vector2 = col["pos"]
	var pos := (at - Vector2(size.x * 0.5, float(FIRE_BED_Y) * s)).round()
	if float(col["lean"]) < 0.0:
		# Mirrored about its own middle (a negative rect width would draw it shifted).
		item.draw_set_transform(Vector2(pos.x + size.x, pos.y), 0.0, Vector2(-1.0, 1.0))
		item.draw_texture_rect(tex[idx], Rect2(Vector2.ZERO, size), false)
		item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		item.draw_texture_rect(tex[idx], Rect2(pos, size), false)


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


## The fire-lit band of sky along the horizon (additive, under the hills): clear at y 96, warmest
## at y 150 just under the hills' crest, so their silhouette reads dark against it.
func _paint_horizon(item: Node2D) -> void:
	var warm := TankPalette.RUST_LIGHT
	var clear := Color(warm.r, warm.g, warm.b, 0.0)
	var hot := Color(warm.r, warm.g, warm.b, 0.2)
	var low := Color(warm.r, warm.g, warm.b, 0.12)
	var w := float(TankConst.SCREEN_W)
	var pts := PackedVector2Array(
		[Vector2(0, 96), Vector2(w, 96), Vector2(w, 150), Vector2(0, 150)]
	)
	item.draw_polygon(pts, PackedColorArray([clear, clear, hot, hot]))
	pts = PackedVector2Array([Vector2(0, 150), Vector2(w, 150), Vector2(w, 200), Vector2(0, 200)])
	item.draw_polygon(pts, PackedColorArray([hot, hot, low, low]))


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
	var under_col := Color("#563b2d") if far else Color("#64402f")
	var crown_col := Color("#48515b") if far else Color("#323a40")
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
		# A long, ragged smear of fire along the slope (a distant burning hedge or farm), never a
		# round dot: each its own length, hottest off-centre.
		var fw := 7 + (f * 5) % 6
		var peak := fw / 4 + (f * 3) % (fw / 2)
		for dx in fw:
			var hot := cell_hash(dx + f * 31, 307)
			var t := 1.0 - absf(float(dx - peak)) / float(fw)
			img.set_pixel(fx + dx, fy, TankPalette.with_alpha(TankPalette.FIRE, 0.55 + 0.45 * t))
			var up := int(2.4 * t * t) + (1 if hot % 3 == 0 else 0)
			for k in up:
				var c := TankPalette.with_alpha(TankPalette.RUST_LIGHT, 0.8 - 0.2 * float(k))
				img.set_pixel(fx + dx, fy - 1 - k, c)
			if dx == peak:
				img.set_pixel(fx + dx, fy, TankPalette.AMBER)
	var blurred := TankBlur.blurred_image(img, TankBlur.PRESETS["hills"], TankPalette.HAZE)
	_ridge = ImageTexture.create_from_image(blurred)
	return _ridge


## The road for the current scroll and location (road_style), tiled unmirrored on the ground plane.
func _paint_road(item: Node2D) -> void:
	var tex := road_texture(road_style(near_id))
	var tw := float(ROAD_W)
	var scroll := roundf(_scroll_x * GROUND_FACTOR)
	var x := float(int(floor(scroll / tw))) * tw - scroll
	while x < float(TankConst.SCREEN_W):
		item.draw_texture(tex, Vector2(x, ROAD_TOP_Y))
		x += tw


## The road's look at near plane `id`: "cobbles" through the village, "slabs" on the depot's apron,
## else "mud".
static func road_style(id: String) -> String:
	match id:
		"bg_village_near":
			return "cobbles"
		"bg_depot_near":
			return "slabs"
	return "mud"


## The puddles on the road of `style` on screen for camera x `cam_x`: [Vector3(x0, x1, y)] (screen
## px, the water's surface row), for the view's reflections of the lamps and fires.
static func road_puddles(style: String, cam_x: float, width: float = 640.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	road_texture(style)
	var spans: Array = (_roads[style] as Array)[1]
	var tw := float(ROAD_W)
	var scroll := roundf(cam_x * GROUND_FACTOR)
	var i := int(floor(scroll / tw))
	var x := float(i) * tw - scroll
	while x < width:
		for sp: Vector3i in spans:
			var x0 := x + float(sp.x)
			var x1 := x + float(sp.y)
			if x1 > 0.0 and x0 < width:
				out.append(Vector3(x0, x1, ROAD_TOP_Y + float(sp.z)))
		x += tw
	return out


## The road strip of `style`, built once (ROAD_W x ROAD_H, tiling unmirrored: periodic noise): a
## ragged verge on top (no straight edge), then mud with two wet ruts along the ground line (their
## edges catching the cold sky), stones, and flooded stretches in the ruts; cobbles in rows with dark
## joints for "cobbles"; cracked concrete slabs with oil stains for "slabs". Its lowest rows fade
## into the ground plane under it.
static func road_texture(style: String) -> Texture2D:
	if _roads.has(style):
		return (_roads[style] as Array)[0]
	var w := ROAD_W
	var h := ROAD_H
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var salt := 900 + style.length() * 7
	var k1 := Color("#0f1012")
	var k2 := Color("#17181b")
	var k3 := Color("#202124")
	var k4 := Color("#2a2b2e")
	var k5 := Color("#353739")
	var k6 := Color("#424446")
	var water := Color("#121519")
	var sky := TankPalette.COLD_DARK
	var sheen := TankPalette.SLATE
	var ruts: Array[int] = [9, 13]
	for x in w:
		var fx := float(x)
		var edge := int(
			3.0 * pnoise(fx, 0.0, 7.0, w / 7, salt) + 1.5 * pnoise(fx, 1.0, 2.0, w / 2, salt)
		)
		for y in range(edge, h):
			var n := pnoise(fx, float(y), 3.0, w / 3, salt + 1)
			var c := TankPalette.MUD if n > 0.42 else TankPalette.MUD_DARK
			if n > 0.8:
				c = TankPalette.MUD_LIGHT
			if y <= edge + 1:
				c = TankPalette.OLIVE if Pen.bayer(x, y) < 0.5 else TankPalette.MUD_DARK
			match style:
				"cobbles":
					if y >= 5:
						var row := (y - 5) / 3
						var bx := (x + (row % 2) * 2) % 5
						var ry := (y - 5) % 3
						c = k5 if n > 0.5 else k4
						if ry == 0 and bx < 3:
							c = k6
						if bx == 4 or ry == 2:
							c = k2
				"slabs":
					if y >= 5:
						c = k4 if n > 0.35 else k3
						if y == 5:
							c = k5
						if (x + 7) % 26 == 0 or (x + 7) % 26 == 1 and y > 5:
							c = k2
						if pnoise(fx, float(y), 9.0, w / 9, salt + 5) > 0.78:
							c = k2
			var a := 1.0 if y < h - 4 else float(h - y) / 5.0
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
		# The ruts: a dark wet groove each, its far edge catching the cold sky now and then.
		if style != "slabs":
			for ry: int in ruts:
				var wob := int(pnoise(fx, float(ry), 40.0, w / 40, salt + 2) * 1.6)
				var y := ry + wob
				img.set_pixel(x, y, TankPalette.MUD_DARK if style == "mud" else k1)
				if pnoise(fx, float(ry), 4.0, w / 4, salt + 3) > 0.55:
					img.set_pixel(x, y - 1, sheen if style == "mud" else k5)
				if pnoise(fx, float(ry) + 2.0, 5.0, w / 5, salt + 4) > 0.6:
					img.set_pixel(x, y + 1, TankPalette.MUD_LIGHT if style == "mud" else k3)
	# Stones on the mud.
	if style == "mud":
		for i in w / 9:
			var sx := (i * 9 + cell_hash(i, salt) % 7) % w
			var sy := 4 + cell_hash(i, salt + 1) % (h - 8)
			img.set_pixel(sx, sy, k6)
			img.set_pixel(sx, sy + 1, k2)
	# Flooded stretches: in the ruts on mud and cobbles, oil-dark pools on the slabs.
	var spans: Array[Vector3i] = []
	var px := 30
	var j := 0
	while px < w - 60:
		var hsh := cell_hash(j, salt + 9)
		var pw := 14 + hsh % 30
		var row: int = ruts[hsh % 2] if style != "slabs" else 8 + hsh % 4
		for x in range(px, px + pw):
			var t := (float(x - px) + 0.5) / float(pw)
			var depth := 1 + int(2.0 * sin(t * PI))
			for d in depth:
				var c := water
				if d == 0:
					c = sky if Pen.bayer(x, row) < 0.75 else sheen
				img.set_pixel(x, row - 1 + d, c)
		spans.append(Vector3i(px, px + pw, row - 1))
		px += pw + 70 + (hsh >> 6) % 150
		j += 1
	var tex := ImageTexture.create_from_image(img)
	_roads[style] = [tex, spans]
	return tex


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


## The foreground, built once (FRONT_W x FRONT_H, tiling unmirrored): a rubble bank whose lumpy
## top runs at y FRONT_BANK_Y and below on screen (under the HUD band), with weeds and the generated
## debris strip's broken bricks along it, and six wrecks apart from each other rising out of it at
## the frame's lower edge: stakes strung with wire (every strand tied at both ends), two rubble
## heaps with a bent girder, a shattered tree stump, sandbags and a broken masonry wall corner.
## Between them the ground line stays clear. Near-black, then blurred hard and darkened
## (FRONT_BLUR): an out-of-focus layer, never a sharp silhouette. Nothing in it is a pole with a
## free wire, a cross or a figure.
static func front_texture() -> Texture2D:
	if _front != null:
		return _front
	var img := Image.create(FRONT_W, FRONT_H, false, Image.FORMAT_RGBA8)
	var pen := Pen.new(img)
	var ink := TankPalette.BLACK
	var ink2 := TankPalette.SOOT
	var lit := TankPalette.COAL
	var mound := int(FRONT_BANK_Y - (FRONT_BOTTOM_Y - float(FRONT_H)))
	# The generated debris strip's broken bricks along the bank (its lowest rows, three plain copies;
	# it tiles), not its tall stakes.
	var deb := TankPlaceholderArt.texture("fg_debris").get_image()
	if deb.is_compressed():
		deb.decompress()
	deb.convert(Image.FORMAT_RGBA8)
	var keep := mini(16, deb.get_height())
	deb = deb.get_region(Rect2i(0, deb.get_height() - keep, deb.get_width(), keep))
	for y in keep:
		for x in deb.get_width():
			var c := deb.get_pixel(x, y)
			if c.a > 0.0:
				deb.set_pixel(x, y, Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, c.a))
	var dx := 0
	while dx < FRONT_W:
		pen.blend(deb, dx, mound + 2)
		dx += deb.get_width()
	# The rubble bank: a lumpy top, solid below.
	for x in FRONT_W:
		var fx := float(x)
		var n := pnoise(fx, 0.0, 36.0, FRONT_W / 36, 811) * 0.65
		n += pnoise(fx, 0.0, 9.0, FRONT_W / 9, 812) * 0.35
		var ty := mound + int(6.0 * (1.0 - n))
		pen.col(x, ty, FRONT_H, ink)
		pen.px(x, ty, lit if Pen.bayer(x, 0) < 0.5 else ink2)
		pen.col(x, ty + 1, ty + 3, ink2)
		# Weeds out of the bank: clumps of thin blades, leaning.
		if pnoise(fx, 7.0, 5.0, FRONT_W / 5, 814) > 0.74 and x % 2 == 0:
			var bh := 2 + int(pnoise(fx, 8.0, 2.0, FRONT_W / 2, 815) * 6.0)
			var lean := 1 if pnoise(fx, 9.0, 3.0, FRONT_W / 3, 816) > 0.5 else -1
			for k in bh:
				pen.px(x + (lean * k) / 3, ty - 1 - k, ink2)
	_stakes(pen, 330, mound + 4, ink, lit)
	_girder_heap(pen, 790, mound + 3, ink, lit)
	_stump(pen, 1260, mound + 6, ink, lit)
	_sandbags(pen, 1700, mound + 3, ink, lit)
	_wall_corner(pen, 2120, mound + 6, ink, lit)
	_girder_heap(pen, 2560, mound + 4, ink, lit)
	var blurred := TankBlur.blurred_image(img, FRONT_BLUR, TankPalette.HAZE)
	_front = ImageTexture.create_from_image(blurred)
	return _front


## Five stakes of uneven height leaning out of the rubble, two strands of wire strung between them,
## each strand tied to a stake at both ends.
static func _stakes(pen: Pen, x: int, base: int, ink: Color, lit: Color) -> void:
	var tops: Array[Vector2] = []
	for k in 5:
		var sx := x + k * 19 + (k * k * 7) % 6
		var top := Vector2(sx + (k % 3) - 1, base - 28 - (k * 11) % 13)
		for t in 3:
			pen.line(Vector2(sx + t, base + 2), top + Vector2(t, 0), ink)
		pen.px(int(top.x) + 1, int(top.y), lit)
		tops.append(top)
	for strand in 2:
		for k in range(1, tops.size()):
			var off := Vector2(1, 5.0 + 9.0 * float(strand))
			pen.wire(tops[k - 1] + off, tops[k] + off, 3.0, ink)


## A heap of rubble and broken brick humped over the bank, a bent steel girder jutting out of it
## at a slant (thick, its upper edge lit), a few loose blocks at its foot.
static func _girder_heap(pen: Pen, x: int, base: int, ink: Color, lit: Color) -> void:
	var w := 58
	for i in w:
		var t := (float(i) + 0.5) / float(w)
		var hump := 14.0 * pow(sin(t * PI), 0.7) + 3.0 * pnoise(float(x + i), 3.0, 4.0, 4096, 821)
		var top := base - int(hump)
		pen.col(x + i, top, base + 2, ink)
		pen.px(x + i, top, lit if Pen.bayer(x + i, top) < 0.5 else ink)
	var a := Vector2(x + 18, base - 10)
	var b := Vector2(x + 44, base - 27)
	for k in 3:
		pen.line(a + Vector2(0, k), b + Vector2(0, k), ink)
	pen.line(a + Vector2(0, -1), b + Vector2(0, -1), lit)
	# The girder's torn end bends down a little.
	pen.line(b, b + Vector2(5, 3), ink)
	pen.line(b + Vector2(0, 1), b + Vector2(5, 4), ink)
	for k in 3:
		pen.rect(x - 4 + k * 23, base - 2 - k % 2, 4, 3, ink)


## Sandbags in three uneven courses, the top course half fallen, each bag a lumpy pillow.
static func _sandbags(pen: Pen, x: int, base: int, ink: Color, lit: Color) -> void:
	var courses: Array[Vector2i] = [Vector2i(0, 8), Vector2i(3, 7), Vector2i(9, 3)]
	for c in courses.size():
		var y := base - 5 * (c + 1)
		var n := courses[c].y
		for k in n:
			var bx := x + courses[c].x + k * 7 + (c % 2) * 3
			var bw := 7 + int(pnoise(float(bx), float(c), 2.0, 4096, 833) * 2.0)
			for i in bw:
				var t := (float(i) + 0.5) / float(bw)
				var hh := 3 + int(2.0 * sin(t * PI))
				pen.col(bx + i, y + 5 - hh, base + 2, ink)
				pen.px(bx + i, y + 5 - hh, lit if t > 0.3 and t < 0.7 else ink)


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
	# A broad trunk flaring into roots, snapped off in three splinters of different heights.
	for i in 22:
		var t := (float(i) + 0.5) / 22.0
		var flare := int(6.0 * pow(absf(t * 2.0 - 1.0), 3.0))
		var spike := 0
		if i >= 4 and i <= 6:
			spike = 14 - absi(i - 5) * 5
		elif i >= 11 and i <= 12:
			spike = 9 - (i - 11) * 4
		elif i >= 16 and i <= 17:
			spike = 5
		var top := base - 22 - spike + int(absf(sin(float(i) * 2.3)) * 3.0) + flare * 3
		pen.col(x + i, top, base + 2, ink)
		pen.px(x + i, top, lit)
	pen.line(Vector2(x + 15, base - 16), Vector2(x + 27, base - 22), ink)
	pen.line(Vector2(x + 15, base - 15), Vector2(x + 27, base - 21), ink)
	for r: int in [-1, 1]:
		var o := Vector2(x + 11 + r * 8, base - 3)
		pen.line(o, o + Vector2(r * 10, 5), ink)
		pen.line(o + Vector2(0, 1), o + Vector2(r * 10, 6), ink)


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
##   burning) on Poplar Road; cottages, orchards and a burning cottage at Kettle Ford; quarry benches
##   stepping down like a stair with a conveyor, spoil heaps, pines, lattice pylons with their wires
##   sagging from pylon to pylon along the whole flank and a burning sawmill at Quarry Ridge; brick
##   works with odd-sized windows, chimney stacks and a slag heap by the foundry town; hangars,
##   concrete bunkers, fuel tanks and floodlight masts with cold lamps at the depot (no gantry crane:
##   polish round 5, its crossbar on two legs read as a gallows).
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
		if style == "fields" or style == "village":
			field_bounds(pen, rng, lo, hi, hz, h)
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

	## Per-landmark repairs: the foundry's gantry crane goes (a crossbar on two legs with a block
	## under it reads as a gallows; polish round 5) and chimney stacks stand in its place; Poplar
	## Road's wire stakes along the field (thin dark uprights that read as tiny figures
	## at a distance) are smoothed into the field by a horizontal median.
	static func _fix_landmark(id: String, lm: Image, hz: int) -> void:
		var h := lm.get_height()
		if id == "bg_town_near" and lm.get_width() > 352 and h > 92:
			lm.fill_rect(Rect2i(272, 52, 25, 18), Color(0, 0, 0, 0))
			lm.fill_rect(Rect2i(297, 52, 52, 37), Color(0, 0, 0, 0))
			_casting_shed(Pen.new(lm), 317, 90)
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

	## The foundry's casting shed where its gantry stood: a gabled brick shed `x`..x+31 on `base`
	## with two windows, one lit, and two tapering stacks of different heights rising off its roof.
	static func _casting_shed(pen: Pen, x: int, base: int) -> void:
		var top := base - 13
		pen.rect(x, top, 31, 13, B2)
		pen.col(x, top, base, K2)
		pen.col(x + 30, top, base, R1)
		for r in 6:
			pen.rect(x - 1 + r * 2, top - 1 - r, 33 - r * 4, 1, K2)
			pen.px(x - 1 + r * 2, top - 1 - r, S0)
		pen.rect(x + 5, top + 4, 3, 3, GLOW)
		pen.px(x + 5, top + 6, AMBER)
		pen.rect(x + 20, top + 5, 4, 3, K1)
		for st: Vector3i in [Vector3i(x + 9, 52, 5), Vector3i(x + 23, 38, 4)]:
			for r in st.y:
				var y := top - 3 - r
				var w := st.z + (1 if r < st.y / 3 else 0)
				pen.rect(st.x, y, w, 1, R0)
				pen.px(st.x, y, K2)
				pen.px(st.x + w - 1, y, R1)
			pen.rect(st.x - 1, top - 2 - st.y, st.z + 2, 2, K3)
			pen.rect(st.x - 1, top - 2 - st.y, st.z + 2, 1, K4)

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
			"quarry": ["terraces", "sawmill", "pines", "terraces", "spoil", "sawmill"],
			"town": ["works", "chimneys", "slag", "works", "sheds", "chimneys"],
			"depot": ["hangar", "parked", "tanks", "mast", "bunker", "parked", "block", "hangar"],
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

	## The fields between the horizon and the plane's foot on the flanks (lo..hi): rows of hedgerows
	## at three depths (the far ones thin, low and paler, the near ones taller and dark), each broken
	## by field gates, with an oak or a poplar row standing in it now and then, and the fields
	## between them told apart by tone (stubble, plough, grass) instead of one ploughed stripe
	## pattern (polish round 6: the fields read as flat grey stripes).
	static func field_bounds(
		pen: Pen, rng: RandomNumberGenerator, lo: int, hi: int, hz: int, h: int
	) -> void:
		var rows: Array[int] = [hz + 9, hz + 9 + (h - hz) / 4, hz + 6 + (h - hz) / 2]
		var tones: Array[Color] = [B2, K3, O1, B3, K4]
		# The fields' tones: long patches between the hedgerow rows, faded in at their ends.
		for r in range(rows.size()):
			var y0 := rows[r] + 1
			var y1 := rows[r + 1] - 2 if r + 1 < rows.size() else h - 8
			var x := lo
			while x < hi:
				var fw := rng.randi_range(60, 170)
				var tone: Color = tones[rng.randi_range(0, tones.size() - 1)]
				var a := rng.randf_range(0.12, 0.3)
				for fx in range(x, mini(x + fw, hi)):
					var edge := minf(float(fx - x), float(x + fw - fx)) / 10.0
					var k := clampf(edge, 0.0, 1.0) * a
					for fy in range(y0, y1):
						if Pen.bayer(fx, fy) < k * 2.0:
							pen.px(fx, fy, tone)
				x += fw
		for r in rows.size():
			var base := rows[r]
			var near := float(r) / float(rows.size() - 1)
			var top_h := 2 + r
			var body := K3 if r == 0 else (K2 if r == 1 else K1)
			var rim := S0 if r == 0 else K3
			var x := lo + rng.randi_range(0, 30)
			while x < hi - 8:
				var run := rng.randi_range(50, 150)
				var x1 := mini(x + run, hi)
				for hx in range(x, x1):
					var n := TankMaterial.smooth_noise(hx, r * 7, 3.0 + near * 2.0, 41 + r)
					var hh := top_h + int(n * float(2 + r))
					pen.col(hx, base - hh, base + 1, body)
					pen.px(hx, base - hh, rim if Pen.bayer(hx, r) < 0.6 else body)
				# A hedgerow tree now and then: an oak, or a short row of poplars on the far rows.
				if rng.randf() < 0.55:
					var tx := rng.randi_range(x + 6, maxi(x + 7, x1 - 6))
					var tree_tones: Array[Color] = FAR_TREE if r == 0 else MID_TREE
					if r < 2 and rng.randf() < 0.5:
						for k in rng.randi_range(2, 4):
							poplar(
								pen,
								tx + k * 6,
								base,
								rng.randi_range(14, 22) + r * 4,
								5,
								tree_tones
							)
					else:
						oak(pen, rng, tx, base, rng.randi_range(6, 9) + r * 2, tree_tones)
				x = x1 + rng.randi_range(6, 18)

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
			"bunker":
				return bunker(pen, rng, x, base) if room >= 58 else 0
			"parked":
				return parked_tanks(pen, rng, x, base) if room >= 90 else 0
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
		for i in wd:
			var t := (float(i) + 0.5) / float(wd)
			var bed := 1 + int(2.0 * sin(t * PI))
			pen.col(x + i, y - bed + 1, y + 2, FIRE)
			# Ragged tongues: each column its own height, every few a tall licking spike leaning
			# downwind, so the fire never reads as a smooth glowing dome.
			var tall := 2.0 + 8.0 * sin(t * PI)
			var fh := int(tall * rng.randf_range(0.2, 0.75))
			if rng.randf() < 0.3:
				fh = int(tall * rng.randf_range(0.9, 1.3)) + 1
			for k in fh:
				var yy := y - bed - k
				var lean := k / 4
				var core := k < fh / 3 and t > 0.2 and t < 0.8
				pen.px(x + i + lean, yy, AMBER if core else FIRE)
		pen.px(x + wd / 2 + rng.randi_range(-2, 2), y, GLOW)

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
	## left, and on the right the rock cut in three or four tall benches stepping down like a stair,
	## each bench's ledge pale and lit, its riser a lit vertical face, the rock between mottled with
	## vertical joints (never horizontal stripes, which blur into a banded smear), scree at every
	## riser's foot, a conveyor on legs running down from the top bench to a hopper at the foot and a
	## hut with a lit window on a bench.
	static func terraces(
		pen: Pen, rng: RandomNumberGenerator, x: int, base: int, width: int
	) -> int:
		var benches := rng.randi_range(3, 4)
		var bh := rng.randi_range(10, 13)
		var ht := bh * benches
		var slope_w := int(float(width) * rng.randf_range(0.2, 0.26))
		var cut0 := x + slope_w
		var x_end := x + width
		var tread := maxi(int(float(x_end - cut0) / (float(benches) + 0.4)), 12)
		var salt := rng.randi_range(0, 999)
		for i in slope_w + 3:
			var t := minf(float(i) / float(slope_w), 1.0)
			var ty := base - int(float(ht) * smoothstep(0.0, 1.0, t))
			ty -= int(TankMaterial.smooth_noise(x + i, 0, 5.0, salt) * 3.0)
			pen.col(x + i, ty, base, B1)
			pen.px(x + i, ty, S0)
			pen.col(x + i, ty + 1, ty + 3, K3)
		var risers: Array[Vector2i] = []
		for cx in range(cut0, x_end):
			var step := mini((cx - cut0) / tread, benches - 1)
			var top := base - (benches - step) * bh
			var into := (cx - cut0) - step * tread
			for y in range(top, base):
				var depth := y - top
				var c := K4
				var n := TankMaterial.smooth_noise(cx, y, 2.5, salt + 7)
				if n > 0.68:
					c = K5
				elif n < 0.22:
					c = K3
				# Vertical joints in the face, a few px apart, fading out downward.
				var joint := TankMaterial.smooth_noise(cx, 0, 1.3, salt + 11)
				if joint > 0.8 and depth > 2 and depth < 9:
					c = K2
				if y > base - 5:
					c = K3 if Pen.bayer(cx, y) < 0.5 else K2
				if depth == 0:
					c = K8 if Pen.bayer(cx, y) < 0.55 else K7
				elif depth == 1:
					c = K6
				elif depth == 2:
					c = K5 if Pen.bayer(cx, y) < 0.5 else K4
				pen.px(cx, y, c)
			# The riser at the end of this bench: a lit vertical face, its foot in scree.
			if into == tread - 1 and step < benches - 1:
				risers.append(Vector2i(cx, top))
		for r in risers:
			pen.col(r.x, r.y, r.y + bh + 1, K7)
			pen.col(r.x - 1, r.y + 1, r.y + bh + 1, K6)
			# Scree heaped against the foot of the riser, on the bench below.
			var foot := r.y + bh
			for k in 6:
				pen.col(r.x + 1 + k, foot - (5 - k) / 2, foot, B2 if (k + r.x) % 3 else K5)
				pen.px(r.x + 1 + k, foot - (5 - k) / 2, B4)
		# The conveyor: a belt on legs from the top bench down to a hopper past the last riser.
		var c0 := Vector2(cut0 + tread / 2, base - ht - 3)
		var c1 := Vector2(x_end - 6, base - 13)
		pen.line(c0, c1, K1)
		pen.line(c0 + Vector2(0, 1), c1 + Vector2(0, 1), K3)
		var legs := int((c1.x - c0.x) / 11.0)
		for k in range(1, legs + 1):
			var lp := c0.lerp(c1, float(k) / float(legs + 1))
			var ground_y := base
			var ly := int(lp.y) + 2
			while ly < ground_y and pen.get_px(int(lp.x), ly).a < 0.5:
				ly += 1
			pen.col(int(lp.x), int(lp.y) + 2, ly, K1)
		pen.rect(int(c1.x) - 4, int(c1.y) + 1, 9, 6, K2)
		pen.rect(int(c1.x) - 4, int(c1.y) + 1, 9, 1, K5)
		pen.rect(int(c1.x) - 2, int(c1.y) + 7, 5, base - int(c1.y) - 7, K1)
		# A hut on the second bench with one lit window.
		var hx := cut0 + tread + 3
		var hy := base - (benches - 1) * bh
		pen.rect(hx, hy - 7, 11, 7, B1)
		pen.rect(hx - 1, hy - 8, 13, 1, K2)
		pen.rect(hx + 3, hy - 5, 2, 2, AMBER)
		var px := x + 2
		while px < cut0 + 4:
			var t := minf(float(px - x) / float(slope_w), 1.0)
			var ty := base - int(float(ht) * smoothstep(0.0, 1.0, t))
			pine(pen, px, ty + 2, rng.randi_range(12, 22), NEAR_TREE)
			px += rng.randi_range(4, 8)
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

	## Two or three windows of different sizes along a wall at uneven gaps and heights, some dark and
	## some lit only in their upper half (never an evenly spaced row of lit dots, which reads as a
	## dashed line or an LED strip).
	static func _window_groups(
		pen: Pen, rng: RandomNumberGenerator, x: int, y: int, width: int
	) -> void:
		var gx := x + rng.randi_range(0, 5)
		var groups := rng.randi_range(2, 3)
		for _g in groups:
			var ww := rng.randi_range(2, 5)
			var wh := rng.randi_range(2, 4)
			if gx + ww > x + width:
				break
			var gy := y + rng.randi_range(-1, 3)
			# Lit panes are warm white with one amber corner (so a window is never read as a fire).
			var roll := rng.randf()
			if roll < 0.4:
				pen.rect(gx, gy, ww, wh, K1)
			elif roll < 0.75:
				pen.rect(gx, gy, ww, wh, GLOW)
				pen.px(gx, gy + wh - 1, AMBER)
			else:
				pen.rect(gx, gy, ww, wh, K1)
				pen.rect(gx, gy, ww, (wh + 1) / 2, GLOW)
			gx += ww + rng.randi_range(5, 13)

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

	## Two or three tanks parked in a row on the apron, facing right like the player's: slab hulls
	## with a sloped glacis, a boxy turret, a short barrel, the running gear dark under a skirt, a
	## tarpaulin over the last one, and a lamp on a post throwing cold light over them.
	static func parked_tanks(pen: Pen, rng: RandomNumberGenerator, x: int, base: int) -> int:
		var cx := x
		var n := rng.randi_range(2, 3)
		for k in n:
			var hw := rng.randi_range(24, 32)
			var hh := rng.randi_range(6, 8)
			var top := base - hh - 3
			pen.rect(cx, base - 3, hw, 3, K1)
			for wx in range(cx + 2, cx + hw - 2, 4):
				pen.px(wx, base - 2, K3)
			for r in hh:
				var slope := maxi(0, r - hh + 4)
				pen.rect(cx, top + r, hw - 4 + slope, 1, K3 if r > 1 else K4)
			pen.rect(cx, top, hw - 4, 1, K5)
			if k == n - 1 and n > 2:
				# Under a tarpaulin: a soft rounded hump, no gun.
				for i in hw - 4:
					var t := (float(i) + 0.5) / float(hw - 4) * 2.0 - 1.0
					var bump := int(6.0 * sqrt(maxf(1.0 - t * t, 0.0)))
					pen.col(cx + i, top - bump, top, O1)
					pen.px(cx + i, top - bump, K5)
			else:
				var tw := rng.randi_range(10, 13)
				var tx := cx + hw / 2 - tw / 2 - 2
				pen.rect(tx, top - 5, tw, 5, K3)
				pen.rect(tx, top - 5, tw, 1, K5)
				pen.rect(tx + tw, top - 3, rng.randi_range(8, 12), 1, K2)
			cx += hw + rng.randi_range(5, 9)
		var lx := cx + 2
		pen.rect(lx, base - 22, 1, 22, K3)
		pen.rect(lx - 2, base - 23, 5, 1, K4)
		pen.rect(lx - 1, base - 22, 3, 1, COLD_LIGHT)
		return lx + 4 - x

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
