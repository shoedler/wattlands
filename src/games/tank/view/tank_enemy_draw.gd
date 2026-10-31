class_name TankEnemyDraw
extends RefCounted
## v4: draws one enemy from the kit (SPEC_TANK 5.4), live parts as our tank's: the hull on TankSuspension's
## pure functions, the road wheels each on the ground under it, the track's shoes mapped one by one along
## TankBody.belt_of, the wheels' frames by travel, the turret squeezed about its pivot as TankBody.turret_xf,
## the gun along its elevation, recoiling. One atlas, nearest. `foot` is the stage point under the sprite's
## middle at its ground row.
## pose: {travel: float, turret_sx: float (1 to the kind's front, -1 back), elev_deg: float, recoil: float,
##        dim: float, haze: float, flash: float, ground: Callable (x -> stage y) or null, wrecked: bool,
##        bogies_wrecked: Array[bool], flip: bool, time: float}
## Layer order: the ground's shadow, hull, track, wheels, sprocket, skirts, then the veil (haze and flash) on
## that, the gun and its veil, the turret and its veil, so no part is veiled twice. Far kinds are drawn with
## their bow to the left, near kinds to the right; `flip` mirrors about foot.x.

## The night's haze: the far air of the game's own frame (sky #081519, ridges #0e2429, hue about 192), so far kinds
## fade into what is behind them. Dark, so a far kind sinks into the night and keeps its blacks: hull, turret and
## running gear still part by value at the far panel's scale, never a pale ghost.
const HAZE := Color(0.04, 0.072, 0.082)
## The veil's alpha for a pose's haze: nothing up close, steady across the field's 0.12..0.5. It stops at half, so the
## farthest kind keeps its plate seams.
const HAZE_FROM := 0.08
const HAZE_SLOPE := 1.1
const HAZE_MAX := 0.5
const FLASH := Color(1.0, 1.0, 0.9)
const SLIT := Color(0.5, 0.88, 0.82)
const SLIT_CORE := Color(0.85, 1.0, 0.96)
## The warmth beside the cold slits, so the enemy lives in our tank's night: engine vents, a hatch's lit crack, the
## exhaust's glow and the Behemoth's furnace. Light only: the atlas stays cold.
const WARM := Color(1.0, 0.5, 0.18)
const WARM_CORE := Color(1.0, 0.8, 0.46)
## How a vent and the exhaust burn, and the spill on the plates round them.
const VENT_K := 0.5
const VENT_SPILL := 0.3
## A lit hatch is a little room: amber deepening from its top row to its sill (added to the dark the atlas paints inside
## its frame), one dim warm row on the frame's lower edge and one on the plate under it.
const HATCH_TOP := Color(0.19, 0.06, 0.0)
const HATCH_SILL := Color(0.68, 0.31, 0.07)
const HATCH_EDGE := Color(0.2, 0.1, 0.035)
const HATCH_PLATE := Color(0.11, 0.055, 0.02)
const EXHAUST_K := 0.7
const EXHAUST_SPILL := 0.34
## A near threat's dark outline.
const HALO := Color(0.012, 0.014, 0.014)
const HALO_AT: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
## A wreck's fire: hot at its core, red at its edge.
const FIRE_CORE := Color(1.0, 0.95, 0.68)
const FIRE := Color(1.0, 0.66, 0.16)
const FIRE_EDGE := Color(0.94, 0.27, 0.05)
## A flame's flicker steps this many times a second (pixel art: no smooth wobble).
const FIRE_STEPS := 12.0
## The torn mouth a fire comes out of (enemy_bake.gd tears it to these numbers): radius and depth under the fire's
## row, each a share of the flame's height.
const MOUTH_K := 0.13
const MOUTH_MIN := 1.6
const MOUTH_DROP := 0.05
## Below this share of a fire's height its tongues are one body: no dark counter opens in it.
const FIRE_BODY := 0.7
## Far-side wheels of the recon car sit in shadow.
const FAR_WHEEL := Color(0.5, 0.55, 0.52)
## The mean of an enemy's albedo: how much a part's tint must lift to read as hazed.
const ALBEDO := Color(0.1, 0.115, 0.1)
## Hull rotations under this stay flat: nearest sampling of a hair's tilt only makes the rows jag.
const ROT_SNAP := 0.012
## The hull's bob over the wheels: rows of bob, and its period in px of travel.
const BOB_PX := 0.6
const BOB_TRAVEL := 19.0

static var _belts: Dictionary = {}


static func draw(
	ci: CanvasItem, kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary
) -> void:
	var tex := kit.texture()
	var row := kit.kind(kind)
	if tex == null or not row.has("base"):
		return
	var veil := _veil(pose)
	var halo := float(pose.get("halo", 0.0))
	if halo > 0.0 and not bool(pose.get("wrecked", false)):
		_halo(ci, tex, row, foot, pose, halo)
	if bool(pose.get("wrecked", false)):
		_set_xf(ci, _flat(row, foot, pose))
		_shadow(ci, tex, row, pose)
		ci.draw_texture_rect_region(tex, _at(Vector2.ZERO, row["wreck"]), row["wreck"], _tint(pose))
		if veil.a > 0.0:
			ci.draw_texture_rect_region(
				tex, _at(Vector2.ZERO, row["wreck_sil"]), row["wreck_sil"], veil
			)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var hull := hull_pose(row, foot, pose)
	var xf: Transform2D = hull["stage"]
	_set_xf(ci, xf)
	_shadow(ci, tex, row, pose)
	var tint := _tint(pose)
	ci.draw_texture_rect_region(tex, _at(Vector2.ZERO, row["base"]), row["base"], tint)
	if row.has("bogies"):
		_bogies(ci, tex, row, hull, pose, tint)
	else:
		_gear(ci, tex, kind, row, row["gear"], hull["wheels"], pose, tint)
	if row.has("front"):
		ci.draw_texture_rect_region(tex, _at(Vector2.ZERO, row["front"]), row["front"], tint)
	if veil.a > 0.0:
		ci.draw_texture_rect_region(tex, _at(Vector2.ZERO, row["sil"]), row["sil"], veil)
	var txf := turret_xf(row, pose)
	_set_xf(ci, xf * _gun_xf(row, pose, txf))
	var g: Dictionary = row["gun"]
	var grect: Rect2 = g["rect"]
	var gat := Rect2(-(g["origin"] as Vector2), grect.size)
	ci.draw_texture_rect_region(tex, gat, grect, tint)
	if veil.a > 0.0:
		ci.draw_texture_rect_region(tex, gat, g["sil"], veil)
	if row.has("turret"):
		var t: Dictionary = row["turret"]
		_set_xf(ci, xf * txf)
		ci.draw_texture_rect_region(tex, _at(t["at"], t["rect"]), t["rect"], tint)
		if veil.a > 0.0:
			ci.draw_texture_rect_region(tex, _at(t["at"], t["sil"]), t["sil"], veil)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## A dark line round the whole sprite (pose.halo its alpha): so near threats in a crowd part from one another.
static func _halo(
	ci: CanvasItem, tex: Texture2D, row: Dictionary, foot: Vector2, pose: Dictionary, a: float
) -> void:
	var xf: Transform2D = hull_pose(row, foot, pose)["stage"]
	var txf := turret_xf(row, pose)
	var col := Color(HALO.r, HALO.g, HALO.b, a)
	var g: Dictionary = row["gun"]
	var gsil: Rect2 = g["sil"]
	var gat := Rect2(-(g["origin"] as Vector2), gsil.size)
	var gxf := _gun_xf(row, pose, txf)
	for d: Vector2 in HALO_AT:
		var shift := Transform2D(0.0, d)
		_set_xf(ci, shift * xf)
		ci.draw_texture_rect_region(tex, _at(Vector2.ZERO, row["sil"]), row["sil"], col)
		_set_xf(ci, shift * xf * gxf)
		ci.draw_texture_rect_region(tex, gat, gsil, col)
		if row.has("turret"):
			var t: Dictionary = row["turret"]
			_set_xf(ci, shift * xf * txf)
			ci.draw_texture_rect_region(tex, _at(t["at"], t["sil"]), t["sil"], col)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Additive slit and lamp glows.
static func draw_light(
	ci: CanvasItem, kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary
) -> void:
	var row := kit.kind(kind)
	if not row.has("base"):
		return
	if bool(pose.get("wrecked", false)):
		_fire(ci, kit.texture(), row, foot, pose)
		return
	var k := light_k(pose)
	var hull := hull_pose(row, foot, pose)
	var xf: Transform2D = hull["stage"]
	var txf := xf * turret_xf(row, pose)
	for s: Array in row.get("slits", []):
		var on_turret := s.size() > 3 and int(s[3]) == 1
		_set_xf(ci, txf if on_turret else xf)
		var r := Rect2(float(s[0]), float(s[1]), float(s[2]), 1.0)
		ci.draw_rect(r.grow_individual(1.0, 1.0, 1.0, 1.0), SLIT * (0.16 * k))
		ci.draw_rect(r, SLIT * (0.55 * k))
		ci.draw_rect(
			Rect2(r.position.x + floorf(r.size.x * 0.5), r.position.y, 1.0, 1.0), SLIT_CORE * k
		)
	_warm_lights(ci, kit.texture(), row, xf, txf, k, float(pose.get("time", 0.0)))
	_set_xf(ci, xf)
	for lamp: Array in row.get("lamps", []):
		var c := Vector2(float(lamp[0]), float(lamp[1]))
		ci.draw_rect(Rect2(c + Vector2(-3, -2), Vector2(7, 6)), SLIT * (0.14 * k))
		ci.draw_rect(Rect2(c + Vector2(-1, 0), Vector2(3, 2)), SLIT * (0.6 * k))
		ci.draw_rect(Rect2(c + Vector2(1, 0), Vector2(1, 1)), SLIT_CORE * k)
	if row.has("furnace"):
		_furnace(ci, kit.texture(), row, k, float(pose.get("time", 0.0)))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## The vents' slats and spill, the hatches' cracks and the exhaust, a slow unsteady burn as an engine's.
static func _warm_lights(
	ci: CanvasItem,
	tex: Texture2D,
	row: Dictionary,
	xf: Transform2D,
	txf: Transform2D,
	k: float,
	time: float
) -> void:
	var glow: Rect2 = row.get("glow", Rect2())
	var t := floorf(time * FIRE_STEPS) / FIRE_STEPS
	var breath := 0.86 + 0.14 * sin(t * 5.3) * sin(t * 2.1)
	for v: Array in row.get("vents", []):
		_set_xf(ci, txf if int(v[4]) == 1 else xf)
		var r := Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
		if tex != null and glow.size.x > 0.0:
			var c := r.get_center()
			_glow(ci, tex, glow, c, r.size.x * 0.9 + 4.0, WARM, VENT_SPILL * k * breath)
		var y := r.position.y
		while y < r.end.y:
			ci.draw_rect(Rect2(r.position.x, y, r.size.x, 1.0), WARM * (VENT_K * k * breath))
			y += 2.0
	for h: Array in row.get("hatches", []):
		_set_xf(ci, txf if int(h[4]) == 1 else xf)
		_hatch(ci, Rect2(float(h[0]), float(h[1]), float(h[2]), float(h[3])), k * breath)
	var ex: Variant = row.get("exhaust")
	if ex is Vector2:
		_set_xf(ci, xf)
		var at: Vector2 = ex
		var fl := 0.72 + 0.28 * sin(t * 11.0 + at.x)
		if tex != null and glow.size.x > 0.0:
			var rad := 5.0 + float(row["size"].x) * 0.035
			_glow(ci, tex, glow, at, rad, WARM, EXHAUST_SPILL * k * fl)
		ci.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 2)), WARM * (EXHAUST_K * k * fl))
		ci.draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 1)), WARM_CORE * (EXHAUST_K * k * fl))


## A lit hatch: its rows of amber, from its top to its sill, its spill on the frame's low edge and the plate under it.
static func _hatch(ci: CanvasItem, hr: Rect2, k: float) -> void:
	var inner := hr.grow(-1.0)
	var n := int(inner.size.y)
	for i in n:
		var u := float(i) / maxf(float(n - 1), 1.0)
		var c := HATCH_TOP.lerp(HATCH_SILL, u)
		var row := Rect2(inner.position + Vector2(0.0, float(i)), Vector2(inner.size.x, 1.0))
		ci.draw_rect(row, Color(c.r, c.g, c.b, k))
	var edge := Rect2(hr.position.x, hr.end.y - 1.0, hr.size.x, 1.0)
	ci.draw_rect(edge, Color(HATCH_EDGE.r, HATCH_EDGE.g, HATCH_EDGE.b, k))
	var plate := Rect2(hr.position.x + 1.0, hr.end.y, hr.size.x - 2.0, 1.0)
	ci.draw_rect(plate, Color(HATCH_PLATE.r, HATCH_PLATE.g, HATCH_PLATE.b, k))


## A fire on a hull still alive (a Behemoth's smashed bogie): the wreck's stepped flame at `at`, a warm pool on the
## plates beside it. Identity transform; `seed_v` keeps two fires apart.
static func burn(
	ci: CanvasItem,
	kit: TankEnemyKit,
	kind: String,
	at: Vector2,
	height: float,
	time: float,
	seed_v: float
) -> void:
	var t := floorf(time * FIRE_STEPS) / FIRE_STEPS
	var breathe := 0.82 + 0.18 * sin(t * 13.0 + seed_v)
	var glow: Rect2 = kit.kind(kind).get("glow", Rect2())
	var tex := kit.texture()
	if tex != null and glow.size.x > 0.0:
		_glow(ci, tex, glow, at + Vector2(0.0, 1.0), height * 1.2, FIRE_EDGE, 0.26 * breathe)
	_flame(ci, at, height, t, seed_v, 1.0)


## A hurt enemy's bar, `y` its top: a dark framed track with its share of red, centred over the rect.
static func hp_bar(ci: CanvasItem, r: Rect2, y: float, hp: float, hp_max: float) -> void:
	if hp_max <= 0.0 or hp >= hp_max:
		return
	var w := roundf(r.size.x * 0.4)
	var x := roundf(r.position.x + r.size.x * 0.3)
	ci.draw_rect(Rect2(x - 1.0, y - 1.0, w + 2.0, 4.0), Color(0.012, 0.012, 0.01, 0.92))
	ci.draw_rect(Rect2(x, y, w, 2.0), Color(0.16, 0.13, 0.11))
	var fill := roundf(w * clampf(hp / hp_max, 0.0, 1.0))
	ci.draw_rect(Rect2(x, y, fill, 2.0), Color(0.72, 0.28, 0.18))


## The Behemoth's furnace: white-hot in the gaps between the louvre's bars, each gap at its own
## heat, a soft steady spill on the plate under it. Only the core flickers. The transform is already set.
static func _furnace(
	ci: CanvasItem, tex: Texture2D, row: Dictionary, k: float, time: float
) -> void:
	var fr := TankEnemyKit.rect_of(row["furnace"])
	var glow: Rect2 = row.get("glow", Rect2())
	if tex != null and glow.size.x > 0.0:
		var under := fr.position + Vector2(fr.size.x * 0.5, fr.size.y + 2.0)
		_glow(ci, tex, glow, under, fr.size.x * 0.75, WARM, 0.42 * k)
	var t := floorf(time * FIRE_STEPS) / FIRE_STEPS
	var gaps := furnace_gaps(fr)
	for i in gaps.size():
		var heat := furnace_heat(i)
		var gap: Rect2 = gaps[i]
		ci.draw_rect(gap, WARM * (0.6 * k))
		var fl := 0.82 + 0.18 * sin(t * 9.0 + float(i) * 2.1)
		var hot := Rect2(gap.position.x, gap.end.y - 2.0, gap.size.x, 2.0)
		ci.draw_rect(hot, WARM_CORE * (heat * k * fl))


## The furnace louvre's open gaps: its bars stand every 4th px (enemy_bake.gd _furnace).
static func furnace_gaps(fr: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x := 0.0
	while x < fr.size.x:
		var w := minf(3.0, fr.size.x - x)
		out.append(Rect2(fr.position.x + x, fr.position.y, w, fr.size.y))
		x += 4.0
	return out


## A gap's heat: no two side by side alike; the fire is not even behind the bars.
static func furnace_heat(i: int) -> float:
	return [0.62, 1.0, 0.78, 0.92, 0.55, 0.85][i % 6]


## The strength of the slits and lamps in a pose: dimmed and hazed with the rest, and gone under a hit's flash,
## which lights the whole shape.
static func light_k(pose: Dictionary) -> float:
	var k := 1.0 - clampf(float(pose.get("dim", 0.0)), 0.0, 1.0)
	k *= 1.0 - 0.5 * clampf(float(pose.get("haze", 0.0)), 0.0, 1.0)
	return k * (1.0 - clampf(float(pose.get("flash", 0.0)), 0.0, 1.0))


## Where a shot leaves the gun, on the stage.
static func muzzle(kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary) -> Vector2:
	var row := kit.kind(kind)
	if not row.has("gun"):
		return _muzzle_stub(row, foot, pose)
	var hull := hull_pose(row, foot, pose)
	var g: Dictionary = row["gun"]
	var txf := turret_xf(row, pose)
	var gxf := _gun_xf(row, pose, txf)
	return (hull["stage"] as Transform2D) * (gxf * Vector2(float(g["len"]), 0.0))


## The gun's bore as drawn: [breech, muzzle] on the stage (the far panel's firing mark runs along it).
static func bore(
	kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary
) -> Array[Vector2]:
	var row := kit.kind(kind)
	var mz := muzzle(kit, kind, foot, pose)
	if not row.has("gun"):
		return [mz + Vector2(10, 0), mz]
	var stage: Transform2D = hull_pose(row, foot, pose)["stage"]
	return [stage * _gun_xf(row, pose, turret_xf(row, pose)) * Vector2.ZERO, mz]


## A sprite point of the kind's hull on the stage: V's exhaust anchor (row "exhaust"), the Behemoth's bow
## secondary (row "secondary_muzzle"), its hit centre.
static func point(
	kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary, sprite_px: Vector2
) -> Vector2:
	var row := kit.kind(kind)
	if not row.has("gun"):
		return foot
	return (hull_pose(row, foot, pose)["stage"] as Transform2D) * sprite_px


## The gun's angle as it will be drawn (a casemate gun stops at its mount's limits).
static func clamp_elev(row: Dictionary, elev_deg: float) -> float:
	var g: Dictionary = row.get("gun", {})
	if g.has("elev"):
		var lim: Vector2 = g["elev"]
		return clampf(elev_deg, lim.x, lim.y)
	return elev_deg


# --- Pose ----------------------------------------------------------------------------------------------------


## The hull with the sprite's ground centre on `foot`, level.
static func _flat(row: Dictionary, foot: Vector2, pose: Dictionary) -> Transform2D:
	var size: Vector2 = row["size"]
	var ground_row := float(row["ground"])
	var xf := Transform2D(0.0, foot.round() - Vector2(size.x * 0.5, ground_row).floor())
	return _mirror(foot) * xf if bool(pose.get("flip", false)) else xf


static func _mirror(foot: Vector2) -> Transform2D:
	var at := roundf(foot.x)
	return Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(2.0 * at, 0))


## {stage (sprite -> stage), wheels (sprite px)} for the pose: on `pose.ground` the hull fits the ground
## under its wheels, each wheel follows it within its travel, and the springs lift the hull.
static func hull_pose(row: Dictionary, foot: Vector2, pose: Dictionary) -> Dictionary:
	var g: Dictionary = row["gear"]
	var rest: Array[Vector3] = g["wheels"]
	var size: Vector2 = row["size"]
	var ground_row := float(row["ground"])
	var flip := bool(pose.get("flip", false))
	var travel := float(pose.get("travel", 0.0))
	var bob := roundf(BOB_PX * sin(travel / BOB_TRAVEL * TAU))
	var src: Variant = pose.get("ground")
	var at := foot.round()
	if not (src is Callable) or not (src as Callable).is_valid():
		var xf0 := Transform2D(
			0.0, at - Vector2(size.x * 0.5, ground_row).floor() - Vector2(0, bob)
		)
		var stage0 := _mirror(foot) * xf0 if flip else xf0
		var wc0: Array[Vector2] = []
		for w in rest:
			wc0.append(Vector2(w.x, w.y + bob))
		return {"stage": stage0, "wheels": wc0}
	var ground: Callable = src
	if flip:
		var mx := 2.0 * roundf(foot.x)
		var orig: Callable = src
		ground = func(x: float) -> float: return float(orig.call(mx - x))
	var fit := TankSuspension.fit(rest, size, foot.x, ground)
	var rot := float(fit["rot"])
	if absf(rot) < ROT_SNAP:
		rot = 0.0
	var fat: Vector2 = (fit["at"] as Vector2).round()
	var xf1 := TankSuspension.xform(size, ground_row, fat, rot, 0.0)
	var wc1 := TankSuspension.wheel_centres(
		rest, xf1, ground, float(g["T"]), float(g["up"]), float(g["droop"])
	)
	var lift := roundf(TankSuspension.lift_of(rest, wc1)) + bob
	var xf2 := TankSuspension.xform(size, ground_row, fat, rot, lift)
	var wc2 := TankSuspension.wheel_centres(
		rest, xf2, ground, float(g["T"]), float(g["up"]), float(g["droop"])
	)
	for i in wc2.size():
		wc2[i] = wc2[i].round()
	return {"stage": _mirror(foot) * xf2 if flip else xf2, "wheels": wc2}


## The turret's transform (sprite px): mirrored and squeezed about its pivot (TankBody.turret_xf).
static func turret_xf(row: Dictionary, pose: Dictionary) -> Transform2D:
	if not row.has("turret"):
		return Transform2D.IDENTITY
	var sx := float(pose.get("turret_sx", 1.0))
	var px := float((row["turret"]["pivot"] as Vector2).x)
	return Transform2D(Vector2(sx, 0), Vector2(0, 1), Vector2(px * (1.0 - sx), 0))


## The gun's transform (gun sprite px, bore along +x from the trunnion): at its elevation, pulled back by
## the recoil, on the turret. A left-facing kind's gun is the same sprite reflected.
static func _gun_xf(row: Dictionary, pose: Dictionary, txf: Transform2D) -> Transform2D:
	var g: Dictionary = row["gun"]
	var f := float(row["faces"])
	var a := deg_to_rad(clamp_elev(row, float(pose.get("elev_deg", 0.0))))
	var d := Vector2(f * cos(a), -sin(a))
	var n := Vector2(f * sin(a), cos(a))
	var o: Vector2 = (g["trunnion"] as Vector2) - d * float(pose.get("recoil", 0.0))
	return txf * Transform2D(d, n, o)


static func _set_xf(ci: CanvasItem, xf: Transform2D) -> void:
	ci.draw_set_transform_matrix(xf)


static func _at(p: Vector2, src: Rect2) -> Rect2:
	return Rect2(p, src.size)


# --- Tint ----------------------------------------------------------------------------------------------------


## The parts' modulate: darkened by `dim`, lifted and cooled towards the haze colour (the veils flatten
## what this cannot).
static func _tint(pose: Dictionary) -> Color:
	var d := 1.0 - clampf(float(pose.get("dim", 0.0)), 0.0, 1.0)
	var h := clampf(float(pose.get("haze", 0.0)), 0.0, 1.0)
	return Color(
		d * ((1.0 - h) + 0.45 * h * HAZE.r / ALBEDO.r),
		d * ((1.0 - h) + 0.45 * h * HAZE.g / ALBEDO.g),
		d * ((1.0 - h) + 0.45 * h * HAZE.b / ALBEDO.b)
	)


## The veil over each part's silhouette: the distance flattens the contrast, a hit lights the whole shape.
## Alpha 0 when there is neither.
static func _veil(pose: Dictionary) -> Color:
	var h := clampf(
		(clampf(float(pose.get("haze", 0.0)), 0.0, 1.0) - HAZE_FROM) * HAZE_SLOPE, 0.0, HAZE_MAX
	)
	var fl := clampf(float(pose.get("flash", 0.0)), 0.0, 1.0)
	if h <= 0.004 and fl <= 0.004:
		return Color(0, 0, 0, 0)
	var d := 1.0 - clampf(float(pose.get("dim", 0.0)), 0.0, 1.0)
	var col := HAZE.lerp(FLASH, fl / maxf(fl + h, 0.001))
	return Color(col.r * d, col.g * d, col.b * d, 1.0 - (1.0 - h) * (1.0 - fl))


## The kind's shadow on the ground under its belt, thinning with the haze. The transform is already set.
static func _shadow(ci: CanvasItem, tex: Texture2D, row: Dictionary, pose: Dictionary) -> void:
	if not row.has("shadow"):
		return
	var k := 1.0 - 0.6 * clampf(float(pose.get("haze", 0.0)), 0.0, 1.0)
	var r: Rect2 = row["shadow"]
	ci.draw_texture_rect_region(tex, Rect2(row["shadow_at"], r.size), r, Color(1, 1, 1, k))


# --- Running gear --------------------------------------------------------------------------------------------


static func _gear(
	ci: CanvasItem,
	tex: Texture2D,
	kind: String,
	row: Dictionary,
	g: Dictionary,
	wheels: Array,
	pose: Dictionary,
	tint: Color
) -> void:
	var travel := float(pose.get("travel", 0.0)) * float(row["faces"])
	var sheets: Dictionary = row["sheets"]
	var rest: Array[Vector3] = g["wheels"]
	if not row.has("track"):
		# no belt: the recon car's tyres, the far side in shadow first
		var far: Array[bool] = g["far"]
		var shade := Color(tint.r * FAR_WHEEL.r, tint.g * FAR_WHEEL.g, tint.b * FAR_WHEEL.b, tint.a)
		for pass_i in 2:
			for i in rest.size():
				if far[i] == (pass_i == 0):
					var a := travel / rest[i].z
					_sheet(ci, tex, sheets["road"], wheels[i], a, shade if far[i] else tint)
		return
	var circles := belt_circles(g, wheels)
	var key := "%s" % kind
	var belt := _belt_cached(key, circles)
	_track(ci, tex, row, belt, travel, tint)
	if g.has("idler"):
		var idl: Vector3 = g["idler"]
		_sheet(ci, tex, sheets["idler"], Vector2(idl.x, idl.y), travel / idl.z, tint)
	for i2 in rest.size():
		_sheet(ci, tex, sheets["road"], wheels[i2], travel / rest[i2].z, tint)
	var rl: Array[Vector3] = g["rollers"]
	for r in rl:
		_sheet(ci, tex, sheets["roller"], Vector2(r.x, r.y), travel / r.z, tint)
	if g.has("sprocket"):
		var sp: Vector3 = g["sprocket"]
		var a2 := sprocket_angle(belt, sp, travel)
		_sheet(ci, tex, sheets["sprocket"], Vector2(sp.x, sp.y), a2, tint)


## The Behemoth: each bogie its own run; a wrecked one is a charred sprite with its track thrown.
static func _bogies(
	ci: CanvasItem, tex: Texture2D, row: Dictionary, hull: Dictionary, pose: Dictionary, tint: Color
) -> void:
	var wrecked: Array = pose.get("bogies_wrecked", [])
	var bogies: Array = row["bogies"]
	var wheels: Array = hull["wheels"]
	var travel := float(pose.get("travel", 0.0)) * float(row["faces"])
	var sheets: Dictionary = row["sheets"]
	var first := 0
	for i in bogies.size():
		var b: Dictionary = bogies[i]
		var bw: Array[Vector3] = b["wheels"]
		var n := bw.size()
		if i < wrecked.size() and bool(wrecked[i]):
			ci.draw_texture_rect_region(tex, _at(b["wrecked_at"], b["wrecked"]), b["wrecked"], tint)
			first += n
			continue
		var wc: Array = wheels.slice(first, first + n)
		first += n
		var circles: Array[Vector3] = []
		var sp: Vector3 = b["sprocket"]
		circles.append(_circle(Vector2(sp.x, sp.y), sp.z))
		var rl: Array[Vector3] = b["rollers"]
		for r in rl:
			circles.append(_circle(Vector2(r.x, r.y), r.z))
		for k in range(n - 1, -1, -1):
			circles.append(_circle(wc[k], bw[k].z))
		var belt := _belt_cached("bogie%d" % i, circles)
		_track(ci, tex, row, belt, travel, tint)
		for k2 in n:
			_sheet(ci, tex, sheets["road"], wc[k2], travel / bw[k2].z, tint)
		for r2 in rl:
			_sheet(ci, tex, sheets["roller"], Vector2(r2.x, r2.y), travel / r2.z, tint)
		ci.draw_texture_rect_region(tex, _at(b["at"], b["rect"]), b["rect"], tint)
		# the sprocket stands whole in front of the bogie's frame
		var a3 := sprocket_angle(belt, sp, travel)
		_sheet(ci, tex, sheets["sprocket"], Vector2(sp.x, sp.y), a3, tint)


## The belt's circles, clockwise on screen from the leftmost end wheel: the return rollers left to right,
## the rightmost end wheel, the road wheels right to left.
static func belt_circles(g: Dictionary, wheels: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var sp: Vector3 = g["sprocket"]
	var idl: Vector3 = g["idler"]
	var left := sp if sp.x < idl.x else idl
	var right := idl if sp.x < idl.x else sp
	out.append(_circle(Vector2(left.x, left.y), left.z))
	var rl: Array[Vector3] = g["rollers"]
	for r in rl:
		out.append(_circle(Vector2(r.x, r.y), r.z))
	out.append(_circle(Vector2(right.x, right.y), right.z))
	var rest: Array[Vector3] = g["wheels"]
	for i in range(wheels.size() - 1, -1, -1):
		out.append(_circle(wheels[i], rest[i].z))
	return out


static func _circle(c: Vector2, r: float) -> Vector3:
	return Vector3(c.x, c.y, r + 0.5)


## TankBody.belt_of, kept while the circles stand still (most far enemies on flat ground).
static func _belt_cached(key: String, circles: Array[Vector3]) -> Dictionary:
	var e: Dictionary = _belts.get(key, {})
	if e.get("circles", []) == circles:
		return e
	var b := TankBody.belt_of(circles, TankBody.ARC_DS)
	b["circles"] = circles
	_belts[key] = b
	return b


## The sprocket's angle at `travel`: it turns with the belt on its pitch circle, a tooth in the shoe's gap where
## tooth and belt meet (`_track` puts a gap at `travel` + k pitch along the belt).
static func sprocket_angle(b: Dictionary, sp: Vector3, travel: float) -> float:
	var c := Vector2(sp.x, sp.y)
	var rp := sp.z + 0.5
	var pts: Array = b["pts"]
	var top := c - Vector2(0.0, rp)
	var best := INF
	var at: Array = pts[0]
	for e: Array in pts:
		var d := (e[0] as Vector2).distance_squared_to(top)
		if d < best:
			best = d
			at = e
	var th := ((at[0] as Vector2) - c).angle()
	return th + (travel - float(at[2])) / rp


## A wheel's sheet frame for angle `ang`, centred on `c`.
static func _sheet(
	ci: CanvasItem, tex: Texture2D, s: Dictionary, c: Vector2, ang: float, tint: Color
) -> void:
	var sz := float(s["size"])
	var f := frame_of(s, ang)
	var r: Rect2 = s["rect"]
	ci.draw_texture_rect_region(
		tex,
		Rect2((c - Vector2(sz, sz) * 0.5).round(), Vector2(sz, sz)),
		Rect2(r.position + Vector2(float(f) * sz, 0.0), Vector2(sz, sz)),
		tint
	)


## A wheel sheet's frame for the angle (over its symmetry).
static func frame_of(s: Dictionary, ang: float) -> int:
	var n: int = s["frames"]
	var period := float(s["period"])
	return clampi(floori(fposmod(ang, period) / period * float(n)), 0, n - 1)


## The track: one quad per shoe along the belt, moving with `travel` (positive: the top run moves right),
## each mapped onto the shoe's lit or unlit rows by which way it faces. One triangle array per belt.
static func _track(
	ci: CanvasItem, tex: Texture2D, row: Dictionary, b: Dictionary, travel: float, tint: Color
) -> void:
	var tr: Dictionary = row["track"]
	var pts: Array = b["pts"]
	var total := float(b["len"])
	if pts.size() < 3 or total <= 0.0:
		return
	var count := maxi(roundi(total / float(tr["pitch"])), 3)
	var pitch := total / count
	var dd0 := float(tr["dd0"])
	var dd1 := dd0 + float(tr["rows"]) * float(tr["row_px"])
	var lit_ny := float(tr["lit_ny"])
	var rect: Rect2 = tr["rect"]
	var ts := Vector2(tex.get_size())
	var u0 := rect.position.x / ts.x
	var u1 := rect.end.x / ts.x
	var vt := rect.position.y / ts.y
	var vm := (rect.position.y + rect.size.y * 0.5) / ts.y
	var vb := rect.end.y / ts.y
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(count * 4)
	uvs.resize(count * 4)
	cols.resize(count * 4)
	idx.resize(count * 6)
	cols.fill(tint)
	var shift := fposmod(travel, pitch)
	var prev := along(pts, total, shift, 0)
	for k in count:
		var nxt := along(pts, total, shift + pitch * float(k + 1), prev[2])
		var p0: Vector2 = prev[0]
		var n0: Vector2 = prev[1]
		var p1: Vector2 = nxt[0]
		var n1: Vector2 = nxt[1]
		var v0 := vt if n0.y < lit_ny else vm
		var v1 := vm if n0.y < lit_ny else vb
		var j := k * 4
		verts[j] = p0 + n0 * dd0
		verts[j + 1] = p0 + n0 * dd1
		verts[j + 2] = p1 + n1 * dd1
		verts[j + 3] = p1 + n1 * dd0
		uvs[j] = Vector2(u0, v0)
		uvs[j + 1] = Vector2(u0, v1)
		uvs[j + 2] = Vector2(u1, v1)
		uvs[j + 3] = Vector2(u1, v0)
		var i := k * 6
		idx[i] = j
		idx[i + 1] = j + 1
		idx[i + 2] = j + 2
		idx[i + 3] = j
		idx[i + 4] = j + 2
		idx[i + 5] = j + 3
		prev = nxt
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


## The belt's point and outward normal at arc length `s` (wrapping), from the sample `cursor` on:
## [point, normal, the sample index to go on from].
static func along(pts: Array, total: float, s: float, cursor: int) -> Array:
	var m := pts.size()
	var want := fposmod(s, total)
	var i := cursor if cursor < m and float((pts[cursor] as Array)[2]) <= want else 0
	while i + 1 < m and float((pts[i + 1] as Array)[2]) <= want:
		i += 1
	var a: Array = pts[i]
	var b: Array = pts[(i + 1) % m]
	var s0 := float(a[2])
	var s1 := float(b[2]) if i + 1 < m else total
	var t := (want - s0) / maxf(s1 - s0, 0.001)
	var p := (a[0] as Vector2).lerp(b[0], t)
	var n := (a[1] as Vector2).lerp(b[1], t).normalized()
	return [p, n, i]


# --- Light ---------------------------------------------------------------------------------------------------


## The wreck's fires, each its flame out of its torn mouth, sized with the kind.
static func _fire(
	ci: CanvasItem, tex: Texture2D, row: Dictionary, foot: Vector2, pose: Dictionary
) -> void:
	var fires: Array = row.get("wreck_fires", [])
	if fires.is_empty():
		return
	var d := 1.0 - clampf(float(pose.get("dim", 0.0)), 0.0, 1.0)
	d *= 1.0 - 0.45 * clampf(float(pose.get("haze", 0.0)), 0.0, 1.0)
	var t := floorf(float(pose.get("time", 0.0)) * FIRE_STEPS) / FIRE_STEPS
	_set_xf(ci, _flat(row, foot, pose))
	var glow: Rect2 = row.get("glow", Rect2())
	for i in fires.size():
		var f: Array = fires[i]
		var height := float(f[2])
		var at := Vector2(float(f[0]), float(f[1]) + mouth_drop(height))
		var seed := foot.x + i * 13.0
		var breathe := 0.82 + 0.18 * sin((t + float(i) * 1.37) * 13.0 + seed)
		# its glow on what is round it, from the mouth: strongest on the plate it lights, nothing at its edge
		if tex != null and glow.size.x > 0.0:
			_glow(ci, tex, glow, at, height * 1.25, FIRE_EDGE, 0.34 * d * breathe)
			_glow(
				ci,
				tex,
				glow,
				at - Vector2(0.0, height * 0.2),
				height * 0.6,
				FIRE,
				0.3 * d * breathe
			)
		_flame(ci, at, height, t + float(i) * 1.37, seed, d)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## The fire's tongues for its height: one on the small kinds, up to three of unequal height on the large.
static func tongues_of(height: float) -> int:
	return 1 if height < 9.0 else (2 if height < 22.0 else 3)


## The radius of the torn mouth a fire of `height` px comes out of.
static func mouth_r(height: float) -> float:
	return maxf(height * MOUTH_K, MOUTH_MIN)


## How far below the fire's row its mouth's centre lies.
static func mouth_drop(height: float) -> float:
	return height * MOUTH_DROP


## A fire `height` px tall out of the mouth centred on `at`: its body and tongues, its foot in the mouth, an ember or
## two above.
static func _flame(
	ci: CanvasItem, at: Vector2, height: float, t: float, seed: float, a: float
) -> void:
	var base := at.round() + Vector2(0.0, 1.0)
	var edge := Color(FIRE_EDGE.r, FIRE_EDGE.g, FIRE_EDGE.b, a)
	var mid := Color(FIRE.r, FIRE.g, FIRE.b, a)
	var core := Color(FIRE_CORE.r, FIRE_CORE.g, FIRE_CORE.b, a)
	for row: Array in flame_rows(height, t, seed):
		var y := base.y + float(row[0])
		var rh := float(row[1])
		var u := float(row[2])
		var col := edge
		col.a = a * (1.0 - u * 0.45)
		for sp: Vector2 in row[3]:
			ci.draw_rect(Rect2(base.x + sp.x, y, sp.y, rh), col)
			var m := roundf(sp.y * 0.66)
			if m >= 1.0 and u < 0.8:
				ci.draw_rect(Rect2(base.x + sp.x + roundf((sp.y - m) * 0.5), y, m, rh), mid)
			var c := roundf(sp.y * 0.26)
			if c >= 1.0 and u < 0.42:
				ci.draw_rect(Rect2(base.x + sp.x + roundf((sp.y - c) * 0.5), y, c, rh), core)
	# its lower edge, uneven: the foot's columns run on down into the mouth, each its own length
	var half := flame_foot(height) * 0.5
	var step_t := floorf(t * 6.0)
	for x in range(-int(half), int(half)):
		var drop := flame_drop(x, step_t, seed, height)
		if drop > 0.0:
			ci.draw_rect(Rect2(base.x + float(x), base.y, 1.0, drop), mid)
	var n := tongues_of(height)
	if n > 1:
		for e in n - 1:
			# embers climb off the tip, each on its own clock
			var v := fposmod(t * (0.9 + 0.3 * float(e)) + seed * 0.37 + float(e) * 0.41, 1.0)
			var q := (
				at
				+ Vector2(
					roundf(sin(v * 5.0 + seed + float(e)) * height * 0.18 + float(e) * 3.0 - 1.0),
					-roundf(height * (0.86 + 0.5 * v))
				)
			)
			var ec := FIRE if v < 0.5 else FIRE_EDGE
			ci.draw_rect(Rect2(q, Vector2.ONE), Color(ec.r, ec.g, ec.b, a * (1.0 - v * 0.7)))


## A flame's width at its foot: it fits inside its mouth, whatever its height.
static func flame_foot(height: float) -> float:
	return maxf(floorf(mouth_r(height) * 2.0), 2.0)


## How far a column of the foot runs on below the flame's bottom row, into the mouth.
static func flame_drop(x: int, step_t: float, seed: float, height: float) -> float:
	var k := fposmod(sin(float(x) * 12.9 + seed * 7.1 + step_t * 3.3) * 43758.5, 1.0)
	return floorf(k * (minf(mouth_r(height), 3.0) + 1.0))


## One fire's rows, foot first: [dy (px from the foot, up is negative), row height, u (0 at the foot, 1 at the top),
## spans (Vector2: left of the mouth's centre, width)]. The foot is no wider than its mouth; the flame widens over the
## next 2-4 rows, holds, then each tongue tears away to its tip, its two edges broken each on its own beat. Below
## FIRE_BODY of the height the tongues are one span, so no dark counter opens in the body; only their tips part. Pure.
static func flame_rows(height: float, t: float, seed: float) -> Array:
	var n := tongues_of(height)
	var row_h := maxf(floorf(height / 14.0), 1.0)
	var rows := int(height / row_h)
	var belly_rows := clampi(rows / 4, 2, 4)
	var foot := flame_foot(height)
	var torn := minf(height * 0.07, 2.0)
	var out: Array = []
	for k in rows:
		var spans: Array[Vector2] = []
		var u := float(k) / float(rows)
		for i in n:
			var share: float = [1.0, 0.88, 0.62][i]
			var side: float = [0.0, -1.0, 1.0][i]
			var tseed := seed + float(i) * 5.3
			var tt := t + float(i) * 0.7
			var v := u / share
			if v > 0.82 + 0.18 * sin(tt * 13.0 + tseed):
				continue
			var belly := maxf(height * 0.46 * share, foot)
			if k == 0:
				spans.append(Vector2(-roundf(foot * 0.5), foot))
				continue
			var w := lerpf(foot, belly, float(k) / float(belly_rows))
			var beat := floorf(tt * 6.0)
			var lick := sin(tt * 7.0 + tseed + float(k) * 0.55) * v * height * 0.1
			# a side tongue stays in the body and only leans out towards its tip
			var lean := side * height * 0.24 * pow(maxf(v - 0.35, 0.0) / 0.65, 1.5)
			var l_edge := 0.0
			var r_edge := 0.0
			if k >= belly_rows:
				var taper := (
					float(k - belly_rows) / maxf(float(rows) * share - float(belly_rows), 1.0)
				)
				w = (
					belly
					* pow(maxf(1.0 - taper, 0.0), 0.62)
					* (0.88 + 0.12 * sin(tt * 17.0 + float(k) + tseed))
				)
				l_edge = roundf(sin(float(k) * 2.4 + tseed * 1.7 + beat) * torn)
				r_edge = roundf(sin(float(k) * 1.7 + tseed * 3.1 + beat * 2.0) * torn)
			var left := roundf(lick + lean - w * 0.5) + l_edge
			var right := roundf(lick + lean + w * 0.5) + r_edge
			if right - left < (2.0 if height >= 14.0 else 1.0):
				continue
			spans.append(Vector2(left, right - left))
		if spans.is_empty():
			continue
		out.append([-float(k + 1) * row_h, row_h, u, _flame_spans(spans, u)])
	return out


## A row's spans: below FIRE_BODY one span round them all.
static func _flame_spans(spans: Array[Vector2], u: float) -> Array[Vector2]:
	if u >= FIRE_BODY or spans.size() < 2:
		return spans
	var left := INF
	var right := -INF
	for sp in spans:
		left = minf(left, sp.x)
		right = maxf(right, sp.x + sp.y)
	var one: Array[Vector2] = [Vector2(left, right - left)]
	return one


## A soft glow: the atlas's falloff, scaled, so it has no steps and no edge. The colour's alpha is its strength.
static func _glow(
	ci: CanvasItem, tex: Texture2D, src: Rect2, c: Vector2, r: float, col: Color, a: float
) -> void:
	ci.draw_texture_rect_region(
		tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), src, Color(col.r, col.g, col.b, a)
	)


# --- No kit --------------------------------------------------------------------------------------------------


## Without a bake (the row has only its size): the sprite's own numbers are all there is.
static func _muzzle_stub(row: Dictionary, foot: Vector2, pose: Dictionary) -> Vector2:
	var size: Vector2 = row["size"]
	var sx := float(row["faces"]) * float(pose.get("turret_sx", 1.0))
	if bool(pose.get("flip", false)):
		sx = -sx
	var length := size.x * 0.5 - float(pose.get("recoil", 0.0))
	var rad := deg_to_rad(float(pose.get("elev_deg", 0.0)))
	return foot - Vector2(0.0, size.y * 0.8) + Vector2(sx * cos(rad), -sin(rad)) * length
