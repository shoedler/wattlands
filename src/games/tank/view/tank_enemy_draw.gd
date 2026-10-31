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

## The night's haze: a dark cold blue, so far kinds lose contrast without lifting past the tank's armour.
const HAZE := Color(0.15, 0.18, 0.22)
## The veil's alpha for a pose's haze: nothing up close, steep across the field's 0.12..0.5, nearly all at 1.
const HAZE_FROM := 0.08
const HAZE_SLOPE := 1.5
const HAZE_MAX := 0.92
const FLASH := Color(1.0, 1.0, 0.9)
const SLIT := Color(0.5, 0.88, 0.82)
const SLIT_CORE := Color(0.85, 1.0, 0.96)
## A wreck's fire, the one warm thing an enemy shows: hot at its core, red at its edge.
const FIRE_CORE := Color(1.0, 0.95, 0.68)
const FIRE := Color(1.0, 0.66, 0.16)
const FIRE_EDGE := Color(0.94, 0.27, 0.05)
## A flame's flicker steps this many times a second (pixel art: no smooth wobble).
const FIRE_STEPS := 12.0
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


## Additive slit and lamp glows.
static func draw_light(
	ci: CanvasItem, kit: TankEnemyKit, kind: String, foot: Vector2, pose: Dictionary
) -> void:
	var row := kit.kind(kind)
	if not row.has("base"):
		return
	var k := 1.0 - clampf(float(pose.get("dim", 0.0)), 0.0, 1.0)
	k *= 1.0 - 0.5 * clampf(float(pose.get("haze", 0.0)), 0.0, 1.0)
	if bool(pose.get("wrecked", false)):
		_fire(ci, row, foot, pose)
		return
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
	_set_xf(ci, xf)
	for lamp: Array in row.get("lamps", []):
		var c := Vector2(float(lamp[0]), float(lamp[1]))
		ci.draw_rect(Rect2(c + Vector2(-3, -2), Vector2(7, 6)), SLIT * (0.14 * k))
		ci.draw_rect(Rect2(c + Vector2(-1, 0), Vector2(3, 2)), SLIT * (0.6 * k))
		ci.draw_rect(Rect2(c + Vector2(1, 0), Vector2(1, 1)), SLIT_CORE * k)
	if row.has("furnace"):
		var fr := TankEnemyKit.rect_of(row["furnace"])
		var fl := 0.75 + 0.25 * sin(float(pose.get("time", 0.0)) * 7.0)
		ci.draw_rect(fr.grow(3.0), SLIT * (0.1 * k * fl))
		ci.draw_rect(fr, SLIT * (0.4 * k * fl))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


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
	_track(ci, tex, row, _belt_cached(key, circles), travel, tint)
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
		_sheet(ci, tex, sheets["sprocket"], Vector2(sp.x, sp.y), travel / sp.z, tint)


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
		_track(ci, tex, row, _belt_cached("bogie%d" % i, circles), travel, tint)
		for k2 in n:
			_sheet(ci, tex, sheets["road"], wc[k2], travel / bw[k2].z, tint)
		for r2 in rl:
			_sheet(ci, tex, sheets["roller"], Vector2(r2.x, r2.y), travel / r2.z, tint)
		_sheet(ci, tex, sheets["sprocket"], Vector2(sp.x, sp.y), travel / sp.z, tint)
		ci.draw_texture_rect_region(tex, _at(b["at"], b["rect"]), b["rect"], tint)


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
static func _fire(ci: CanvasItem, row: Dictionary, foot: Vector2, pose: Dictionary) -> void:
	var fires: Array = row.get("wreck_fires", [])
	if fires.is_empty():
		return
	var d := 1.0 - clampf(float(pose.get("dim", 0.0)), 0.0, 1.0)
	d *= 1.0 - 0.45 * clampf(float(pose.get("haze", 0.0)), 0.0, 1.0)
	var t := floorf(float(pose.get("time", 0.0)) * FIRE_STEPS) / FIRE_STEPS
	_set_xf(ci, _flat(row, foot, pose))
	for i in fires.size():
		var f: Array = fires[i]
		_flame(
			ci,
			Vector2(float(f[0]), float(f[1])),
			float(f[2]),
			t + float(i) * 1.37,
			foot.x + i * 13.0,
			d
		)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## One tongue of fire `height` px tall, standing on `at`: stepped rows, wide at the foot, licking to one side,
## its edge red, then orange, a yellow-white core low down. `a` is the fire's strength, never its colour.
static func _flame(
	ci: CanvasItem, at: Vector2, height: float, t: float, seed: float, a: float
) -> void:
	var row_h := maxf(floorf(height / 12.0), 1.0)
	var rows := int(height / row_h)
	var breathe := 0.82 + 0.18 * sin(t * 13.0 + seed)
	var w0 := maxf(height * 0.46, 3.0)
	# its glow on what is round it
	_glow(ci, at - Vector2(0.0, height * 0.35), height * 0.8, FIRE_EDGE, 0.09 * a * breathe)
	_glow(ci, at - Vector2(0.0, height * 0.3), height * 0.45, FIRE, 0.14 * a * breathe)
	for k in rows:
		var u := float(k) / float(rows)
		if u > breathe:
			break
		var y := at.y + 1.0 - float(k + 1) * row_h
		var lick := roundf(sin(t * 7.0 + seed + float(k) * 0.55) * u * height * 0.2)
		var w := roundf(w0 * pow(1.0 - u, 0.7) * (0.85 + 0.15 * sin(t * 17.0 + float(k) + seed)))
		if w < 1.0:
			continue
		var x := at.x + lick
		ci.draw_rect(
			Rect2(x - roundf(w * 0.5), y, w, row_h),
			Color(FIRE_EDGE.r, FIRE_EDGE.g, FIRE_EDGE.b, a * (1.0 - u * 0.45))
		)
		var mid := roundf(w * 0.66)
		if mid >= 1.0 and u < 0.8:
			ci.draw_rect(
				Rect2(x - roundf(mid * 0.5), y, mid, row_h), Color(FIRE.r, FIRE.g, FIRE.b, a)
			)
		var core := roundf(w * 0.34)
		if core >= 1.0 and u < 0.55:
			ci.draw_rect(
				Rect2(x - roundf(core * 0.5), y, core, row_h),
				Color(FIRE_CORE.r, FIRE_CORE.g, FIRE_CORE.b, a)
			)


## A soft round glow in stepped rows.
static func _glow(ci: CanvasItem, c: Vector2, r: float, col: Color, a: float) -> void:
	var step := maxf(ceilf(r / 5.0), 1.0)
	var y := -r
	while y < r:
		var mid := y + step * 0.5
		var half := roundf(sqrt(maxf(r * r - mid * mid, 0.0)))
		if half >= 1.0:
			ci.draw_rect(
				Rect2(roundf(c.x) - half, roundf(c.y + y), half * 2.0, step),
				Color(col.r, col.g, col.b, a)
			)
		y += step


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
