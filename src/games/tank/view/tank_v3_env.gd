class_name TankV3Env
extends RefCounted
## MOCK (Diesel Domestiques v3, background: spec item 4). Not for merging as is.
##
## The v3 world around the tank: a pine forest road at night (no people anywhere outside the tank),
## more blue-green, a much stronger tilt-shift baked into the planes at three strengths (moderate,
## strong, extreme; assets/tank/v3env/planes/<strength>/, baked by assets/tank/v3env/tools_src/
## env_planes.gd) plus a matching per-frame pass (TankDof), the occasional "little base" (a small
## fenced clearing with a bunker, a lamp, crates, drums and a gate barrier; no text, no people), and
## gentle bumps and slope shading on the road surface (visual only).
##
## Mock switches (environment variables, read once; the screenshot tool passes the environment on):
##   TANK_V3_ENV=0            the v2 world as shipped (every other switch then does nothing but the
##                            layering fix)
##   TANK_V3_TILT=moderate|strong|extreme   (default strong)
##   TANK_V3_LAYERFIX=0       the v2 light layering (world lamps drawn over the tank) for the
##                            before/after frame
##   TANK_V3_BASE_SX=<px>     one little base with its left end at this stage x (art px), for the
##                            hero frames; otherwise bases stand at their world places
##   TANK_V3_TANK=r4|r5       r3/r4: draw the tank builder's rebuilt tank (its round 4 or 5, a
##                            static composed sprite, assets/tank/v3env/tank_<r>.png; same anchors,
##                            r5 adds the rear searchlight) instead of the v2 tank, with
##                            its own lights (position lamps, headlight, searchlight, room bloom)
##   TANK_V3_GROUND_Y=<px>    r2: where the road line (the tank's and the enemies' ground) sits on
##                            the 960 x 540 base canvas (default GROUND_Y; v2 had 340). The whole
##                            stage drops by GROUND_Y - TankView.GROUND: the sky gains rows on top,
##                            the foreground loses them at the bottom, the HUD's world tags follow
##                            (they read the view's y_off). The one knob to place a new tank.

const DIR := "res://assets/tank/v3env/planes/"
## Back to front. layer: back (behind the world), road (the verge, with the road band over it),
## front (over the tank).
const PLANES: Array[Dictionary] = [
	{"name": "far", "y0": -80.0, "parallax": 0.04, "layer": "back"},
	{"name": "ridge", "y0": 0.0, "parallax": 0.12, "layer": "back"},
	{"name": "forest", "y0": 0.0, "parallax": 0.3, "layer": "back"},
	{"name": "verge", "y0": 296.0, "parallax": 1.0, "layer": "road"},
	{"name": "near", "y0": 356.0, "parallax": 1.0, "layer": "near"},
	{"name": "foreground", "y0": 344.0, "parallax": 1.35, "layer": "front"},
]
## The per-frame pass per strength: blur radius (art px) far from the band, its ramp, the band.
const DOF := {
	"moderate": {"max": 2.6, "ramp": 80.0, "band": Vector2(150, 360)},
	"strong": {"max": 4.0, "ramp": 60.0, "band": Vector2(150, 358)},
	"extreme": {"max": 6.5, "ramp": 44.0, "band": Vector2(152, 356)},
}
## r2 layout: the road line's default place on the 960 x 540 base (v2: TankView.GROUND = 340).
## Measured: the road band runs from GROUND_Y - 6 to GROUND_Y + 42 (its near edge wavy round
## GROUND_Y + 37), the near shoulder below it, the foreground from about GROUND_Y + 42 down.
const GROUND_Y := 385.0
## r2: the road band's depth (rows; v2's was TankWorldDraw.ROAD_H = 30): the gravel continues toward
## the viewer and fades under the near shoulder's wavy edge.
const ROAD3_H := 48
## The sky above the far plane on a taller canvas.
const SKY := Color(0.012, 0.03, 0.04)
## Little bases: world x (rules px) in a mission; in free roam one by the start and one at each
## strongpoint in the old village and quarry zones (now forest). Drawn in the travel frame (the
## world layers mirror them while the tank drives west).
const BASE_W := 236.0
const MISSION_BASES: Array[float] = [620.0]
## Road relief: the profile's tile (art px) and its gentle amplitude.
const RELIEF_W := 1920
const RELIEF_AMP := 3.6
## Colours (graded night).
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
const POST_HI := Color(0.22, 0.19, 0.15)
const WIRE := Color(0.32, 0.35, 0.34)
const PLANK := Color(0.2, 0.16, 0.11)
const PLANK_DK := Color(0.09, 0.075, 0.055)
const DRUM := Color(0.11, 0.14, 0.12)
const DRUM_HI := Color(0.22, 0.27, 0.23)
const IRON := Color(0.1, 0.105, 0.1)
const ARM_RED := Color(0.5, 0.13, 0.09)
const ARM_WHITE := Color(0.6, 0.62, 0.58)
const LAMP := Color(1.0, 0.7, 0.34)

## r3: the tank builder's r4 tank (tank3-tank: assets/tank/v3/tools_src/tank_r4.gd layout()):
## the sprite, its ground row (track bottom), where its local origin sits relative to the v2
## tank's top-left (TankView.TANK_POS; x as the tank builder placed it over this backdrop), and its
## anchors in sprite px.
const R4_FILE := "res://assets/tank/v3env/tank_%s.png"
## r5's two searchlights (tank3-tank: tank_r5.gd layout() details "searchlight" and
## "searchlight_rear", lens = at + lens offset): the turret's aimed forward 11 degrees down, the
## rear deck's aimed aft 13 degrees down (167 degrees) and always on (a work light); beam length,
## half angle, strength; a pool where each cone's axis meets the road (r5's light.gd).
const R5_SEARCH := [
	{
		"lens": Vector2(309.5, 65.5),
		"ang": 11.0,
		"len": 560.0,
		"half": 6.0,
		"a": 0.45,
		"always": false
	},
	{
		"lens": Vector2(98.0, 92.5),
		"ang": 167.0,
		"len": 220.0,
		"half": 8.0,
		"a": 0.4,
		"always": true
	},
]
const R4_GROUND := 209.0
const R4_DX := 12.0
const R4 := {
	"barrel_pivot": Vector2(350.1, 103.05),
	"gun_len": 90.5,
	"bow_gun_upper_pivot": Vector2(400.0, 126.9),
	"bow_gun_upper_len": 23.5,
	"bow_gun_lower_pivot": Vector2(430.2, 139.0),
	"bow_gun_lower_len": 22.0,
	"headlight": Vector2(456.5, 164.0),
	"searchlight": Vector2(308.5, 63.5),
	"lamp_red_rear": Vector2(31.5, 127.5),
	"lamp_red_front": Vector2(442.5, 149.5),
	"lamp_green": Vector2(105.5, 102.5),
	"exhaust": Vector2(40.0, 112.0),
	"turret_roof_commander_feet": Vector2(300.0, 76.0),
	"rear": Vector2(14.0, 209.0),
}
## r4's rooms (sprite px) and their bloom colours (the arc room cold).
const R4_ROOMS := {
	"drive": Rect2(89, 152, 92, 31),
	"loader": Rect2(181, 152, 69, 31),
	"gun": Rect2(250, 152, 43, 31),
	"lights": Rect2(293, 152, 43, 31),
	"sec": Rect2(361, 156, 30, 27),
	"quarters": Rect2(104, 125, 160, 24),
	"turret_drive": Rect2(268, 123, 67, 27),
}
## The body rects the HUD's world tags keep clear of (sprite px): the turret without the barrel,
## and the hull.
const R4_TURRET := Rect2(178, 56, 176, 58)
const R4_HULL := Rect2(8, 106, 460, 110)

static var _r4: Texture2D = null
static var _cfg: Dictionary = {}
static var _planes: Dictionary = {}
static var _road: Texture2D = null
static var _relief: Texture2D = null
static var _profile: PackedFloat32Array = PackedFloat32Array()


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var tilt := OS.get_environment("TANK_V3_TILT")
		if not DOF.has(tilt):
			tilt = "strong"
		var bsx := OS.get_environment("TANK_V3_BASE_SX")
		_cfg = {
			"on": OS.get_environment("TANK_V3_ENV") != "0",
			"tilt": tilt,
			"layer_fix": OS.get_environment("TANK_V3_LAYERFIX") != "0",
			"base_sx": float(bsx) if bsx.is_valid_float() else NAN,
			"ground_y": GROUND_Y,
			"r4": OS.get_environment("TANK_V3_TANK") in ["r4", "r5"],
			"tank": OS.get_environment("TANK_V3_TANK"),
		}
		var gy := OS.get_environment("TANK_V3_GROUND_Y")
		if gy.is_valid_float():
			_cfg["ground_y"] = float(gy)
	return _cfg


static func on() -> bool:
	return bool(cfg()["on"])


static func layer_fix() -> bool:
	return bool(cfg()["layer_fix"])


static func r4() -> bool:
	return on() and bool(cfg()["r4"])


## The r4 sprite's top-left on the stage for the view's tank origin (shake and lurch included).
static func r4_at(origin: Vector2) -> Vector2:
	return Vector2(origin.x + R4_DX, origin.y - TankView.TANK_POS.y + TankView.GROUND - R4_GROUND)


## An r4 anchor on the stage (sprite px + r4_at), or NAN when r4 has none by that name.
static func r4_anchor(origin: Vector2, name: String) -> Vector2:
	var key := name
	match name:
		"muzzle":
			var p: Vector2 = R4["barrel_pivot"]
			return r4_at(origin) + p + Vector2(float(R4["gun_len"]), 0)
		"bow_gun_upper_muzzle", "bow_gun_lower_muzzle":
			var k2 := name.replace("_muzzle", "")
			var p2: Vector2 = R4[k2 + "_pivot"]
			return r4_at(origin) + p2 + Vector2(float(R4[k2 + "_len"]), 0)
		"searchlight_turret_lens":
			key = "searchlight"
		"running_light_red_rear":
			key = "lamp_red_rear"
		"running_light_red_front":
			key = "lamp_red_front"
		"running_light_green_rear":
			key = "lamp_green"
	if not R4.has(key) or not R4[key] is Vector2:
		return Vector2(NAN, NAN)
	return r4_at(origin) + (R4[key] as Vector2)


static func r4_tex() -> Texture2D:
	if _r4 == null:
		var path := R4_FILE % str(cfg()["tank"])
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		_r4 = ImageTexture.create_from_image(img)
	return _r4


## r3: the r4 tank, static (no moving tracks in these frames), standing on the ground line.
static func draw_tank_r4(ci: CanvasItem, v: TankView) -> void:
	ci.draw_texture(r4_tex(), r4_at(v.origin).round())


## r3: r4's own lights on the tank light layer: the position lamps with halos, the headlight with
## its halo and beam, the turret searchlight's beam (dimmed with the arc as in v2), and a bloom of
## the lit rooms (the arc room cold).
static func draw_r4_lights(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var at := r4_at(v.origin)
	var blink := 0.75 + 0.25 * sin(v.time * 2.2)
	TankDraw.lamp(ci, at + (R4["lamp_red_rear"] as Vector2), TankLightDraw.RED, blink)
	TankDraw.lamp(ci, at + (R4["lamp_red_front"] as Vector2), TankLightDraw.RED, 0.9)
	TankDraw.lamp(ci, at + (R4["lamp_green"] as Vector2), TankLightDraw.GREEN, blink)
	var hk := 0.3 if state.hull.breakdown else 1.0
	var hl := at + (R4["headlight"] as Vector2)
	TankDraw.beam(
		ci, hl, deg_to_rad(9.0), 210.0, deg_to_rad(12.0), Color(1.0, 0.82, 0.52), 0.5 * hk
	)
	TankDraw.glow_at(ci, hl, 6.0, Color(1.0, 0.95, 0.8, hk))
	TankDraw.glow_at(ci, hl, 22.0, Color(1.0, 0.8, 0.5, 0.35 * hk))
	var sk := v.searchlight_k(state)
	if r5():
		for sd: Dictionary in R5_SEARCH:
			var k := 1.0 if bool(sd["always"]) else sk
			var lp: Vector2 = at + (sd["lens"] as Vector2)
			var ang := deg_to_rad(float(sd["ang"]) + 1.0 * sin(v.time * 0.45))
			var col := Color(1.0, 0.94, 0.78)
			TankDraw.beam(
				ci,
				lp,
				ang,
				float(sd["len"]),
				deg_to_rad(float(sd["half"])),
				col,
				float(sd["a"]) * k
			)
			TankDraw.glow_at(ci, lp, 9.0, Color(1.0, 0.95, 0.8, 0.9 * maxf(k, 0.3)))
			TankDraw.glow_at(ci, lp, 24.0, Color(1.0, 0.85, 0.6, 0.2 * k))
	else:
		_r4_searchlight(ci, at, sk, v.time)
	if state.hull.breakdown:
		return
	_room_bloom(ci, at, v.time)


static func r5() -> bool:
	return r4() and str(cfg()["tank"]) == "r5"


static func _r4_searchlight(ci: CanvasItem, at: Vector2, sk: float, time: float) -> void:
	var sl := at + (R4["searchlight"] as Vector2)
	var sweep := deg_to_rad(-11.0 + 3.0 * sin(time * 0.45))
	TankDraw.beam(ci, sl, sweep, 300.0, deg_to_rad(6.0), Color(1.0, 0.92, 0.75), 0.5 * sk)
	TankDraw.glow_at(ci, sl, 9.0, Color(1.0, 0.95, 0.8, 0.9 * maxf(sk, 0.3)))
	TankDraw.glow_at(ci, sl, 26.0, Color(1.0, 0.85, 0.6, 0.22 * sk))


static func _room_bloom(ci: CanvasItem, at: Vector2, time: float) -> void:
	for id: String in R4_ROOMS:
		var r: Rect2 = R4_ROOMS[id]
		var c := at + r.get_center()
		var col := Color(0.66, 0.82, 1.0) if id == "lights" else Color(1.0, 0.66, 0.34)
		var fl := 0.92 + 0.08 * sin(time * 3.0 + r.position.x)
		TankDraw.glow_at(ci, c, r.size.x * 0.75, Color(col.r, col.g, col.b, 0.1 * fl))
		TankDraw.glow_at(ci, c, r.size.x * 0.35, Color(col.r, col.g, col.b, 0.08 * fl))


## r3: the headlight's pool on the road and the rooms' spill, from r4's anchors (world light).
static func draw_r4_pools(ci: CanvasItem, v: TankView, broken: bool) -> void:
	var at := r4_at(v.origin)
	var hk := 0.3 if broken else 1.0
	var hl := at + (R4["headlight"] as Vector2)
	var g := TankView.GROUND
	TankLightDraw.ground_glow(
		ci, Vector2(hl.x + 160.0, g + 6.0), 125.0, Color(1.0, 0.75, 0.45, 0.4 * hk)
	)
	TankLightDraw.ground_glow(
		ci, Vector2(hl.x + 45.0, g + 3.0), 70.0, Color(1.0, 0.72, 0.42, 0.22 * hk)
	)
	if r5():
		# where each searchlight's cone axis meets the road: a warm oval pool (r5's light.gd)
		for sd: Dictionary in R5_SEARCH:
			var lp: Vector2 = at + (sd["lens"] as Vector2)
			var dv := Vector2.from_angle(deg_to_rad(float(sd["ang"])))
			var gy := at.y + R4_GROUND
			if dv.y > 0.01:
				var hit := lp + dv * ((gy - lp.y) / dv.y)
				TankLightDraw.ground_glow(ci, hit, 46.0, Color(1.0, 0.9, 0.72, 0.32))
	if broken:
		return
	for id: String in R4_ROOMS:
		var r: Rect2 = R4_ROOMS[id]
		var c := Color(0.66, 0.82, 1.0, 0.06) if id == "lights" else Color(1.0, 0.66, 0.36, 0.08)
		TankLightDraw.ground_glow(
			ci, Vector2(at.x + r.get_center().x, g + 6.0), r.size.x * 0.8 + 20.0, c
		)


## r3: the body rects the HUD keeps clear of, on the stage.
static func r4_rects(origin: Vector2) -> Array[Rect2]:
	var at := r4_at(origin)
	var out: Array[Rect2] = []
	for r: Rect2 in [R4_TURRET, R4_HULL]:
		out.append(Rect2(at + r.position, r.size))
	return out


## How far the stage drops below v2's layout (art px; 0 with the v2 world).
static func ground_drop() -> float:
	if not on():
		return 0.0
	return roundf(float(cfg()["ground_y"]) - TankView.GROUND)


static func tilt() -> String:
	return str(cfg()["tilt"])


static func dof() -> Dictionary:
	return DOF[tilt()]


## The planes of the chosen strength: name -> {tex, w, y0, parallax, layer}.
static func planes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := tilt()
	if not _planes.has(key):
		var rows: Array[Dictionary] = []
		for p in PLANES:
			var path := ProjectSettings.globalize_path(DIR + key + "/" + str(p["name"]) + ".png")
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				push_warning(
					"TankV3Env: missing %s (run assets/tank/v3env/tools_src/regen.sh)" % path
				)
				continue
			var row := p.duplicate()
			row["tex"] = ImageTexture.create_from_image(img)
			row["w"] = float(img.get_width())
			rows.append(row)
		_planes[key] = rows
	out.assign(_planes[key])
	return out


# --- Planes, road ------------------------------------------------------------------------------------------


static func draw_back(ci: CanvasItem, v: TankView) -> void:
	if v.y_off > 0.0:
		ci.draw_rect(Rect2(0, -v.y_off, v.canvas.x, v.y_off + 1.0), SKY)
	var ps := planes()
	for p in ps:
		if str(p["layer"]) == "back":
			TankWorldDraw.tile(ci, v, p)
	for p in ps:
		if str(p["layer"]) == "road":
			TankWorldDraw.tile(ci, v, p)
	var road := road_tex()
	var rx := -fposmod(v.plane_x * TankView.S, float(road.get_width()))
	while rx < v.canvas.x:
		ci.draw_texture(road, Vector2(roundf(rx), TankView.GROUND - TankWorldDraw.ROAD_TOP))
		rx += float(road.get_width())
	var rel := relief_tex()
	var lx := -fposmod(v.plane_x * TankView.S, float(RELIEF_W))
	while lx < v.canvas.x:
		ci.draw_texture(rel, Vector2(roundf(lx), TankView.GROUND - TankWorldDraw.ROAD_TOP - 4.0))
		lx += float(RELIEF_W)
	# r2: the near shoulder over the road band's near rows (grass and stones across the edge)
	for p in ps:
		if str(p["layer"]) == "near":
			TankWorldDraw.tile(ci, v, p)


static func draw_front(ci: CanvasItem, v: TankView) -> void:
	for p in planes():
		if str(p["layer"]) == "front":
			TankWorldDraw.tile(ci, v, p)
	var bottom := v.canvas.y - v.y_off
	if bottom > TankView.BASE.y:
		ci.draw_rect(
			Rect2(0, TankView.BASE.y - 1.0, v.canvas.x, bottom - TankView.BASE.y + 1.0),
			Color(0.008, 0.014, 0.016)
		)


## The road band (r2: ROAD3_H deep): v2's far rows, then more gravel toward the viewer (coarser
## pebbles, a faint third rut pair, a little darker), fading out under the near shoulder; all
## regraded blue-green (the light layer still warms it).
static func road_tex() -> Texture2D:
	if _road != null:
		return _road
	var v2 := TankWorldDraw.road_tex().get_image()
	var w := v2.get_width()
	var img := Image.create(w, ROAD3_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.blit_rect(v2, Rect2i(0, 0, w, 26), Vector2i.ZERO)
	for y in range(26, ROAD3_H):
		for x in w:
			var n := TankWorldDraw._tile_noise(x, y)
			var near := float(y - 26) / float(ROAD3_H - 26)
			var col := TankWorldDraw.GRAVEL_BASE.lerp(
				TankWorldDraw.GRAVEL_DK, n * 0.6 + near * 0.25
			)
			if y in [31, 32, 39]:
				col = col.lerp(TankWorldDraw.RUT, 0.3)
			var h := TankDraw.hash01(float(x) * 1.37 + float(y) * 91.7)
			if h > 0.94:
				col = TankWorldDraw.PEBBLE.lerp(TankWorldDraw.GRAVEL_BASE, n)
			var a := 1.0 - smoothstep(float(ROAD3_H - 7), float(ROAD3_H), float(y))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	for x in w:
		var h2 := TankDraw.hash01(float(x) * 4.13 + 9.0)
		if h2 > 0.9:
			var py := 27 + int(TankDraw.hash01(float(x) * 3.3) * 12.0)
			img.fill_rect(Rect2i(x, py, 2, 1), TankWorldDraw.PEBBLE)
			img.fill_rect(Rect2i(x, py + 1, 2, 1), TankWorldDraw.GRAVEL_SH)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				var l := c.r * 0.3 + c.g * 0.55 + c.b * 0.15
				var g := c.lerp(Color(l * 0.8, l * 0.98, l * 1.0, c.a), 0.55)
				g.a = c.a
				img.set_pixel(x, y, g)
	_road = ImageTexture.create_from_image(img)
	return _road


## The road's gentle profile (art px, up positive) at tile column `x` (0..RELIEF_W).
static func profile(x: int) -> float:
	if _profile.is_empty():
		_profile.resize(RELIEF_W)
		for i in RELIEF_W:
			var a := TAU * float(i) / float(RELIEF_W)
			_profile[i] = (
				RELIEF_AMP
				* (
					0.55 * sin(a * 3.0 + 0.7)
					+ 0.3 * sin(a * 7.0 + 2.2)
					+ 0.15 * sin(a * 17.0 + 0.4)
				)
			)
	return _profile[posmod(x, RELIEF_W)]


## The road's relief over the band (RELIEF_W x ROAD_H + 4, tileable): the far edge rising over
## crests (gravel) and sinking in dips (the verge's dark), slopes facing the light (left, the
## headlight's side) a little lighter and the others darker, dips damp and darker with a puddle
## catching the sky in the deepest ones, crests drier and paler.
static func relief_tex() -> Texture2D:
	if _relief != null:
		return _relief
	var top := TankWorldDraw.ROAD_TOP + 4
	var hh := ROAD3_H + 4
	var img := Image.create(RELIEF_W, hh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gravel := Color(0.1, 0.11, 0.1)
	var gravel_hi := Color(0.16, 0.17, 0.155)
	for x in RELIEF_W:
		var hgt := profile(x)
		var slope := profile(x + 6) - profile(x - 6)
		var lift := int(roundf(hgt))
		# far edge
		if lift > 0:
			for k in lift:
				var c := gravel if k < lift - 1 else gravel_hi
				img.set_pixel(x, top - 1 - k, c)
		elif lift < 0:
			for k in -lift:
				img.set_pixel(x, top + k, Color(0.02, 0.035, 0.03, 0.85))
		# slope light and dip shade across the band
		var lit := clampf(-slope * 0.1, 0.0, 0.16)
		var dark := clampf(slope * 0.1, 0.0, 0.2) + clampf(-hgt * 0.05, 0.0, 0.16)
		var dry := clampf(hgt * 0.03, 0.0, 0.08)
		for y in range(top + maxi(-lift, 0), hh - 4):
			var fade := 1.0 - float(y - top) / float(hh - top) * 0.4
			var c2 := Color(0, 0, 0, 0)
			if dark > 0.0:
				c2 = Color(0.0, 0.01, 0.012, dark * fade)
			if lit + dry > 0.0:
				c2 = Color(0.55, 0.6, 0.55, (lit + dry) * fade * 0.5)
			if c2.a > 0.0:
				img.set_pixel(x, y, c2)
		# a puddle in the deepest dips, along the ruts
		if hgt < -RELIEF_AMP * 0.72:
			var w := TankDraw.hash01(float(x / 9) * 1.7)
			if w > 0.35:
				for ry: int in [top + 5, top + 12]:
					img.set_pixel(x, ry, Color(0.2, 0.3, 0.32, 0.55))
					img.set_pixel(x, ry + 1, Color(0.06, 0.1, 0.11, 0.6))
	_relief = ImageTexture.create_from_image(img)
	return _relief


# --- Little bases ------------------------------------------------------------------------------------------


## The little bases on screen: their left ends (stage x).
static func bases(v: TankView, state: TankState) -> Array[float]:
	var out: Array[float] = []
	var bsx := float(cfg()["base_sx"])
	if not is_nan(bsx):
		out.append(bsx)
		return out
	if state.roam.active and state.roam_map != null:
		var map := state.roam_map
		var spots: Array[float] = [map.lo_m + 60.0]
		for m in map.strongpoints:
			if map.zone_at(m) in ["village", "quarry"]:
				spots.append(m)
		for m: float in spots:
			var cx := v.sx(v.travel_x(state, m))
			out.append(roundf(cx - BASE_W * 0.5))
	else:
		for wx in MISSION_BASES:
			out.append(roundf(v.sx(wx)))
	var vis: Array[float] = []
	for x in out:
		if x < v.canvas.x + 20.0 and x + BASE_W > -20.0:
			vis.append(x)
	return vis


## A little base at stage x `x0` on the road's far edge: a cleared earth bank, a fence of posts
## and wire with a gate, a sodded concrete bunker with a dark firing slit behind sandbags, a hooded
## lamp on a post, crates under a tarp, fuel drums, the gate's red and white barrier raised.
static func draw_base(ci: CanvasItem, x0: float) -> void:
	var g := TankView.GROUND - 5.0
	_bank(ci, x0, g)
	_fence(ci, x0, g, true)
	_bunker(ci, x0 + 26.0, g)
	_drums(ci, x0 + 98.0, g)
	_lamp_post(ci, x0 + 120.0, g)
	_crates(ci, x0 + 130.0, g)
	_barrier(ci, x0 + 182.0, g)
	_fence(ci, x0, g, false)


## The base's lights (stage px): the lamp and the bunker's slit.
static func base_lights(x0: float) -> Array[Dictionary]:
	var g := TankView.GROUND - 5.0
	return [
		{"p": Vector2(x0 + 121.0, g - 45.0), "kind": "lamp"},
		{"p": Vector2(x0 + 58.0, g - 15.0), "kind": "slit"},
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


## Posts every 13 px with three sagging wires and barbs; `back` draws the far run (behind the
## bunker), else the near posts at the ends, with the gate's gap left open.
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


## A low concrete pillbox: a sodded roof slab with grass, a lit-edge face, a dark firing slit,
## a sandbag wall in front of its foot.
static func _bunker(ci: CanvasItem, x: float, g: float) -> void:
	var w := 64.0
	var hgt := 22.0
	var body := PackedVector2Array(
		[
			Vector2(x, g),
			Vector2(x + 5.0, g - hgt),
			Vector2(x + w - 5.0, g - hgt),
			Vector2(x + w, g),
		]
	)
	ci.draw_polygon(body, PackedColorArray([CONC]))
	ci.draw_line(Vector2(x, g), Vector2(x + 5.0, g - hgt), CONC_HI, 1.0)
	ci.draw_rect(Rect2(x + w - 9.0, g - hgt, 4, hgt), CONC_DK)
	# pour lines and stains
	for k in 3:
		ci.draw_rect(Rect2(x + 6.0, g - 6.0 - float(k) * 6.0, w - 15.0, 1), Color(CONC_DK, 0.5))
	# roof slab, overhanging, sod and grass on top
	ci.draw_rect(Rect2(x + 1.0, g - hgt - 4.0, w - 2.0, 4), CONC_DK)
	ci.draw_rect(Rect2(x + 1.0, g - hgt - 4.0, w - 2.0, 1), CONC_HI)
	ci.draw_rect(Rect2(x + 4.0, g - hgt - 8.0, w - 8.0, 4), SOD)
	for i in int(w - 8.0):
		var h := TankDraw.hash01(x * 0.3 + float(i) * 1.7)
		if h > 0.45:
			var gh := 1.0 + roundf(h * 3.0)
			ci.draw_rect(Rect2(x + 4.0 + i, g - hgt - 8.0 - gh, 1, gh), SOD if h < 0.85 else SOD_HI)
	# the firing slit (dark, a faint warm line at its bottom from inside)
	ci.draw_rect(Rect2(x + 20.0, g - 16.0, 26, 4), Color(0.01, 0.012, 0.012))
	ci.draw_rect(Rect2(x + 20.0, g - 17.0, 26, 1), CONC_HI)
	ci.draw_rect(Rect2(x + 22.0, g - 13.0, 22, 1), Color(0.35, 0.22, 0.1))
	# sandbags along the foot
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
	# a cable box at its foot
	ci.draw_rect(Rect2(x - 2.0, g - 8.0, 6, 5), IRON)


static func _drums(ci: CanvasItem, x: float, g: float) -> void:
	for k in 2:
		var dx := x + float(k) * 7.0
		ci.draw_rect(Rect2(dx, g - 10.0, 6, 10), DRUM)
		ci.draw_rect(Rect2(dx, g - 10.0, 1, 10), DRUM_HI)
		ci.draw_rect(Rect2(dx, g - 10.0, 6, 1), DRUM_HI)
		for by: float in [0.3, 0.7]:
			ci.draw_rect(Rect2(dx, roundf(g - 10.0 * by), 6, 1), Color(0.03, 0.04, 0.035))


## Planked crates, one stack under a sagging tarp.
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


## The gate: a post with its red and white arm raised (painted stripes, no text), a counterweight.
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


# --- The base's light (the world light layer, behind the tank) ----------------------------------------------


static func draw_base_light(ci: CanvasItem, x0: float) -> void:
	for l in base_lights(x0):
		var p: Vector2 = l["p"]
		if str(l["kind"]) == "slit":
			TankDraw.glow_at(ci, p, 10.0, Color(1.0, 0.55, 0.25, 0.1))
			continue
		TankDraw.glow_at(ci, p, 5.0, Color(1.0, 0.86, 0.6, 0.8))
		TankDraw.glow_at(ci, p + Vector2(0, 14), 36.0, Color(LAMP.r, LAMP.g, LAMP.b, 0.24))
		# the hooded lamp's cone down onto the yard, and its pool
		TankDraw.beam(ci, p, PI * 0.5, 48.0, deg_to_rad(30.0), Color(1.0, 0.75, 0.42), 0.18)
		TankLightDraw.ground_glow(
			ci, Vector2(p.x, TankView.GROUND - 3.0), 52.0, Color(1.0, 0.68, 0.36, 0.3)
		)
