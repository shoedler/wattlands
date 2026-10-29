class_name TankBody
extends SubViewport
## The v3 tank as one sprite (docs/games/tank.md v3 "The tank, in the view"): a SubViewport the size
## of the r6 sprite (plus PAD) that draws the tank unrotated, in sprite px, every frame; the view
## then draws its texture rotated as a whole (nearest) onto the terrain. Back to front:
##   Back   the dark underside, the suspension arms and springs, the track (one baked shoe mapped
##          along the belt round the idler, the return rollers, the sprocket and the road wheels,
##          its links moving with `travel`), the idler, the road wheels (each at its own suspension
##          centre `wheels`), the return rollers
##   Shade  the skirt's deep shadow over the running gear (multiplied)
##   Front  the base art with the live rooms (TankInterior's texture), the turret block mirrored
##          about its pivot by `turret_sx` (a traverse), the searchlights' lit lenses while they
##          burn, the sprocket, the main gun at `elev_deg` with its recoil, the bow guns tilted to
##          `bow_elev_deg` with their kick
##   Dim    the rooms' backup lighting (multiplied): every room and window dimmed toward
##          BACKUP_DIM by `backup` (0 the warm lamps .. 1 the Lights seat unpowered); the machines
##          and the riders still read
## The view sets the fields each frame; this node only draws them.

const PAD := 8
## Belt samples along the wheels' arcs (px).
const ARC_DS := 1.5
const ARM_DARK := Color("#1a130d")
const ARM_MID := Color("#3a2c1e")
const ARM_LIT := Color("#6a5236")
## The rooms under their backup lighting (a multiply): dimmer and a little red, still readable.
const BACKUP_DIM := Color(0.6, 0.47, 0.44)

var rig: TankRig = null
## The rooms' live texture (TankInterior.tex), else the base.
var interior: Texture2D = null
## Road wheel centres (sprite px), in kit order.
var wheels: Array[Vector2] = []
## Track travel (px; positive: the top run moves forward).
var travel: float = 0.0
var elev_deg: float = 0.0
var recoil: float = 0.0
## The turret's horizontal scale about its pivot: 1 forward .. -1 facing the rear.
var turret_sx: float = 1.0
var bow_elev_deg: float = 2.0
var bow_kick: Array[float] = [0.0, 0.0]
var search_lit: bool = false
var rear_lit: bool = false
## The rooms' backup lighting (0..1).
var backup: float = 0.0

var _back: Node2D = null
var _shade: Node2D = null
var _front: Node2D = null
var _dim: Node2D = null


func _init(p_rig: TankRig) -> void:
	rig = p_rig
	name = "TankBody"
	transparent_bg = true
	disable_3d = true
	size = Vector2i(rig.size) + Vector2i(PAD * 2, PAD * 2)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	for w in rig.wheels:
		wheels.append(Vector2(w.x, w.y))
	_back = _layer("Back")
	_back.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_shade = _layer("Shade")
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_shade.material = mul
	_front = _layer("Front")
	_dim = _layer("Dim")
	var dim_mul := CanvasItemMaterial.new()
	dim_mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_dim.material = dim_mul
	_dim.draw.connect(_draw_dim)
	_back.draw.connect(_draw_back)
	_shade.draw.connect(_draw_shade)
	_front.draw.connect(_draw_front)


func _layer(n: String) -> Node2D:
	var l := Node2D.new()
	l.name = n
	l.position = Vector2(PAD, PAD)
	add_child(l)
	return l


## Redraws the three layers with the fields as set.
func refresh() -> void:
	_back.queue_redraw()
	_shade.queue_redraw()
	_front.queue_redraw()
	_dim.queue_redraw()


## The turret's transform (sprite px): mirrored and squeezed about its pivot.
func turret_xf() -> Transform2D:
	var px := rig.turret_pivot_x
	return Transform2D(Vector2(turret_sx, 0), Vector2(0, 1), Vector2(px * (1.0 - turret_sx), 0))


## The main gun's transform (sprite px): the bore along +x from the trunnion at the elevation,
## pulled back by the recoil, on the turret.
func barrel_xf() -> Transform2D:
	var ang := -deg_to_rad(elev_deg)
	var d := Vector2(cos(ang), sin(ang))
	return turret_xf() * Transform2D(ang, rig.trunnion - d * recoil)


## Bow gun `k`'s transform (sprite px): along its tilt from its pivot, kicked back.
func bow_xf(k: int, kicked: bool) -> Transform2D:
	var ang := -deg_to_rad(bow_elev_deg)
	var d := Vector2(cos(ang), sin(ang))
	var piv: Vector2 = rig.bow[k]["pivot"]
	return Transform2D(ang, piv - d * (bow_kick[k] if kicked else 0.0))


# --- Back: the running gear ------------------------------------------------------------------------------


func _draw_back() -> void:
	var ci := _back
	var g := rig.gear
	var us: Dictionary = g.get("underside", {})
	var ur := TankRig.rect(us.get("rect", [44, 176, 368, 28]))
	var split := float(us.get("split_y", 198))
	ci.draw_rect(
		Rect2(ur.position, Vector2(ur.size.x, split - ur.position.y)),
		Color(str(us.get("top", "#0a0705")))
	)
	ci.draw_rect(
		Rect2(Vector2(ur.position.x, split), Vector2(ur.size.x, ur.end.y - split)),
		Color(str(us.get("bottom", "#070504")))
	)
	_arms(ci)
	_track(ci)
	var idl: Dictionary = g["idler"]
	_sheet(ci, "idler", TankRig.vec(idl["c"]), travel / float(idl["r"]))
	for i in mini(wheels.size(), rig.wheels.size()):
		_sheet(ci, "road", wheels[i], travel / rig.wheels[i].z)
	for rl: Dictionary in g.get("rollers", []):
		_sheet(ci, "roller", TankRig.vec(rl["c"]), travel / float(rl["r"]))


## A gear sheet's frame for `ang` centred on `c`.
func _sheet(ci: CanvasItem, kind: String, c: Vector2, ang: float) -> void:
	var s: Dictionary = rig.sheets.get(kind, {})
	if s.is_empty() or s["tex"] == null:
		return
	var n := int(s["frames"])
	var period := float(s["period"])
	var sz := float(s["size"])
	var f := clampi(floori(fposmod(ang, period) / period * float(n)), 0, n - 1)
	var at := (c - Vector2(sz, sz) * 0.5).round()
	ci.draw_texture_rect_region(
		s["tex"], Rect2(at, Vector2(sz, sz)), Rect2(float(f) * sz, 0, sz, sz)
	)


## The trailing arm from each hub to its pivot on the hull and the coil spring above the hub.
func _arms(ci: CanvasItem) -> void:
	for i in mini(wheels.size(), rig.wheels.size()):
		var w := rig.wheels[i]
		var c := wheels[i]
		var piv := Vector2(w.x - w.z + 0.5, w.y - w.z * 0.6)
		var stop := Vector2(w.x + 2.5, w.y - w.z - 7.0)
		var n := maxi(ceili(c.distance_to(stop)), 1)
		for k in n + 1:
			var q := c.lerp(stop, float(k) / n) + Vector2(1, 0)
			_px(ci, Vector2(floorf(q.x), floorf(q.y)), ARM_LIT if k % 2 == 0 else ARM_DARK)
			_px(ci, Vector2(floorf(q.x) + 1.0, floorf(q.y)), ARM_MID if k % 2 == 0 else ARM_DARK)
		_line(ci, c + Vector2(0, 1), piv + Vector2(0, 1), ARM_DARK)
		_line(ci, c, piv, ARM_MID)
		_px(ci, Vector2(floorf(piv.x), floorf(piv.y)), ARM_LIT)


static func _px(ci: CanvasItem, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(p, Vector2.ONE), c)


## A one-pixel line (Bresenham on floored ends, as the generator draws).
static func _line(ci: CanvasItem, a: Vector2, b: Vector2, c: Color) -> void:
	var x := floori(a.x)
	var y := floori(a.y)
	var x1 := floori(b.x)
	var y1 := floori(b.y)
	var dx := absi(x1 - x)
	var dy := -absi(y1 - y)
	var sx := 1 if x < x1 else -1
	var sy := 1 if y < y1 else -1
	var err := dx + dy
	while true:
		_px(ci, Vector2(x, y), c)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


## The belt round the idler, the rollers, the sprocket and the road wheels (gear.gd belt(): a wheel
## the belt would wrap concavely gets no arc), as {pts: [[p, n, s]], len}; straight runs are one
## step each.
func belt() -> Dictionary:
	var g := rig.gear
	var circles: Array[Vector3] = []
	var idl: Dictionary = g["idler"]
	circles.append(_circle(TankRig.vec(idl["c"]), float(idl["r"])))
	for rl: Dictionary in g.get("rollers", []):
		circles.append(_circle(TankRig.vec(rl["c"]), float(rl["r"])))
	var sp: Dictionary = g["sprocket"]
	circles.append(_circle(TankRig.vec(sp["c"]), float(sp["r"])))
	for i in range(mini(wheels.size(), rig.wheels.size()) - 1, -1, -1):
		circles.append(_circle(wheels[i], rig.wheels[i].z))
	return belt_of(circles, ARC_DS)


static func _circle(c: Vector2, r: float) -> Vector3:
	return Vector3(c.x, c.y, r + 0.5)


static func belt_of(circles: Array[Vector3], ds: float) -> Dictionary:
	var n := circles.size()
	var nrm: Array[Vector2] = []
	for i in n:
		var a := circles[i]
		var b := circles[(i + 1) % n]
		var d := Vector2(b.x - a.x, b.y - a.y)
		var dl := maxf(d.length(), 0.001)
		var cv := clampf((a.z - b.z) / dl, -1.0, 1.0)
		nrm.append((d / dl).rotated(-acos(cv)))
	var pts: Array = []
	var s := 0.0
	for i in n:
		var cc := Vector2(circles[i].x, circles[i].y)
		var r := circles[i].z
		var n0 := nrm[(i - 1 + n) % n]
		var n1 := nrm[i]
		var a0 := n0.angle()
		var da := fposmod(n1.angle() - a0, TAU)
		if da > PI * 1.6:
			da = 0.0
		var steps := maxi(ceili(da * r / ds), 1)
		for k in steps:
			var a := a0 + da * float(k) / float(steps)
			var nv := Vector2(cos(a), sin(a))
			pts.append([cc + nv * r, nv, s])
			s += da * r / float(steps)
		var p0: Vector2 = cc + n1 * r
		var nx := circles[(i + 1) % n]
		var p1: Vector2 = Vector2(nx.x, nx.y) + n1 * nx.z
		pts.append([p0, n1, s])
		s += p0.distance_to(p1)
	return {"pts": pts, "len": s}


## The track: the baked shoe mapped along the belt (u: links, moving with `travel`; v: from the
## inner guide horns out to the grousers), the top run's lit rows where the belt faces up.
func _track(ci: CanvasItem) -> void:
	if rig.track_tex == null:
		return
	var b := belt()
	var pts: Array = b["pts"]
	var total := float(b["len"])
	if pts.size() < 3 or total <= 0.0:
		return
	var pitch := total / roundf(total / float(rig.gear.get("pitch", 7.0)))
	var dd0 := float(rig.track.get("dd0", -2.0))
	var dd1 := dd0 + float(rig.track.get("rows", 18)) * float(rig.track.get("row_px", 0.5))
	var lit_ny := float(rig.track.get("lit_ny", -0.35))
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var m := pts.size()
	for i in m:
		var e0: Array = pts[i]
		var e1: Array = pts[(i + 1) % m]
		var p0: Vector2 = e0[0]
		var n0: Vector2 = e0[1]
		var p1: Vector2 = e1[0]
		var n1: Vector2 = e1[1]
		var s0 := float(e0[2])
		var s1 := float(e1[2]) if i + 1 < m else total
		var u0 := (s0 - travel) / pitch
		var u1 := u0 + (s1 - s0) / pitch
		var v0 := 0.0 if n0.y < lit_ny else 0.5
		var base := verts.size()
		verts.append_array(
			PackedVector2Array([p0 + n0 * dd0, p0 + n0 * dd1, p1 + n1 * dd1, p1 + n1 * dd0])
		)
		uvs.append_array(
			PackedVector2Array(
				[Vector2(u0, v0), Vector2(u0, v0 + 0.5), Vector2(u1, v0 + 0.5), Vector2(u1, v0)]
			)
		)
		cols.append_array(PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	RenderingServer.canvas_item_add_triangle_array(
		ci.get_canvas_item(),
		idx,
		verts,
		cols,
		uvs,
		PackedInt32Array(),
		PackedFloat32Array(),
		rig.track_tex.get_rid()
	)


# --- Shade: the skirt's shadow ----------------------------------------------------------------------------


func _draw_shade() -> void:
	var sk: Dictionary = rig.gear.get("skirt_shade", {})
	var x0 := float(sk.get("x0", 20))
	var x1 := float(sk.get("x1", 445))
	var y0 := float(sk.get("y0", 180))
	var y1 := float(sk.get("y1", 200))
	var k := float(sk.get("from", 0.3))
	var dark := Color(k, k, k, 1.0)
	_shade.draw_polygon(
		PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		PackedColorArray([dark, dark, Color.WHITE, Color.WHITE])
	)


# --- Front: the hull, the rooms, the turret, the guns ------------------------------------------------------


func _draw_front() -> void:
	var ci := _front
	var tex: Texture2D = interior if interior != null else rig.base_tex
	if tex == null:
		return
	var w := rig.size.x
	var h := rig.size.y
	var tr := rig.turret_rect
	for r: Rect2 in [
		Rect2(0, 0, tr.position.x, h),
		Rect2(tr.position.x, tr.end.y, tr.size.x, h - tr.end.y),
		Rect2(tr.end.x, 0, w - tr.end.x, h),
	]:
		ci.draw_texture_rect_region(tex, r, r)
	if rear_lit and rig.lit_rear_tex != null:
		ci.draw_texture(rig.lit_rear_tex, rig.lit_rear_at)
	ci.draw_set_transform_matrix(turret_xf())
	ci.draw_texture_rect_region(tex, tr, tr)
	if search_lit and rig.lit_tex != null:
		ci.draw_texture(rig.lit_tex, rig.lit_at)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var sp: Dictionary = rig.gear["sprocket"]
	_sheet(ci, "sprocket", TankRig.vec(sp["c"]), travel / float(sp["r"]))
	if rig.barrel_tex != null:
		ci.draw_set_transform_matrix(barrel_xf())
		ci.draw_texture(rig.barrel_tex, -rig.barrel_origin)
	for k in rig.bow.size():
		var b: Dictionary = rig.bow[k]
		ci.draw_set_transform_matrix(bow_xf(k, true))
		ci.draw_texture(b["tex"], -(b["origin"] as Vector2))
		ci.draw_set_transform_matrix(bow_xf(k, false))
		if rig.ball_tex != null:
			ci.draw_texture(rig.ball_tex, -rig.ball_origin)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# --- Dim: the rooms' backup lighting ------------------------------------------------------------------------


## The colour the Dim layer multiplies the rooms by at `k` (0..1 backup).
static func backup_tint(k: float) -> Color:
	return Color.WHITE.lerp(BACKUP_DIM, clampf(k, 0.0, 1.0))


func _draw_dim() -> void:
	if backup <= 0.0:
		return
	var c := backup_tint(backup)
	var tr := rig.turret_rect
	var rects: Array = rig.rooms.values() + rig.windows.values()
	for r: Rect2 in rects:
		if tr.encloses(r):
			_dim.draw_set_transform_matrix(turret_xf())
		_dim.draw_rect(r, c)
		_dim.draw_set_transform_matrix(Transform2D.IDENTITY)
