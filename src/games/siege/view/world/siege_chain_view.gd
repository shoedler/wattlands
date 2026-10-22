class_name SiegeChainView
extends Node3D
## A rider's tower route (brief 3 "Routes"): a MultiMesh chain along the wall walk from the
## rider's wheel to the pad it feeds, in the rider's color and pattern (solid links, dashed
## groups, dotted beads, a double chain). It lights up over the 2 s reconnect (a lit front runs
## out from the wheel; the rest stays dim iron), then scrolls at the wheel's rim speed, so it is
## proportional to P_eff. It shows only while the rider routes to a tower; a generator route is
## the wheel's glowing shaft instead. Only reads SiegeRiderState.

const SPACING_M := 1.1
const CAPACITY := 400
const LATERAL_STEP_M := 0.4
const RECONNECT_S := 2.0
const START_Y := 5.4
## Groups of the dashed pattern: this many links on, then this many off.
const DASH_ON := 4
const DASH_OFF := 2

var slot: int = 0
var fort: SiegeFortBuilder = null
var chain: MultiMeshScatter = null
var pattern: String = "solid"
var color: Color = Color.WHITE
## The pad being drawn (0 = none) and its path in 3D.
var pad: int = 0
var path: PackedVector3Array = PackedVector3Array()
var path_length: float = 0.0
var scroll_m: float = 0.0
## 0..1: how much of the path is lit.
var lit: float = 0.0
var _cache: Dictionary = {}


func setup(p_slot: int, p_fort: SiegeFortBuilder, look: Dictionary) -> void:
	slot = p_slot
	fort = p_fort
	name = "Chain%d" % slot
	apply_look(look)
	chain = MultiMeshScatter.new()
	chain.name = "Links"
	var link := LowPolyMesh.new()
	link.use_surface(&"link", LowPolyMesh.unshaded_material())
	link.add_box(Vector3(0.34, 0.34, 0.9), Color.WHITE)
	link.add_box(Vector3(0.2, 0.55, 0.2), Color.WHITE, Transform3D(Basis(), Vector3(0, 0, 0.5)))
	chain.setup(link.build(), CAPACITY, true, false)
	chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chain)


func apply_look(look: Dictionary) -> void:
	color = look.get("color", Color.WHITE)
	pattern = str(look.get("pattern", "solid"))


## The 3D polyline of a route: the wheel's rim, then the wall walk to the pad, lifted onto the
## walls and offset sideways by slot so four chains side by side stay readable.
func build_path(to_pad: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var flat := fort.map.chain_path(slot, to_pad)
	if flat.size() < 2:
		return pts
	var n := flat.size()
	for i in n:
		var dir := Vector2.ZERO
		if i > 0:
			dir += (flat[i] - flat[i - 1]).normalized()
		if i < n - 1:
			dir += (flat[i + 1] - flat[i]).normalized()
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
		var side := Vector2(dir.y, -dir.x) * (float(slot) - 1.5) * LATERAL_STEP_M
		var p := flat[i] + (side if i > 0 else Vector2.ZERO)
		var y := START_Y if i == 0 else fort.chain_y_at(flat[i])
		pts.append(Vector3(p.x, y, p.y))
	return pts


static func polyline_length(pts: PackedVector3Array) -> float:
	var len_m := 0.0
	for i in range(1, pts.size()):
		len_m += pts[i - 1].distance_to(pts[i])
	return len_m


## Link placements along `pts`: transforms (facing along the path, alternate links rolled 90
## degrees) and each link's distance from the start. `offset` scrolls them (link n sits at
## offset + n x spacing, so a pattern scrolls with its links); `lateral` shifts them sideways
## (the second strand of a double chain).
static func layout(
	pts: PackedVector3Array, spacing: float, offset: float, lateral: float = 0.0
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if pts.size() < 2 or spacing <= 0.0:
		return out
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total := float(cum[cum.size() - 1])
	# Link n sits at offset + n x spacing; n counts from the start so patterns scroll with it.
	var idx := int(ceil(-offset / spacing))
	var d := offset + float(idx) * spacing
	var seg := 0
	while d <= total:
		while seg < pts.size() - 2 and float(cum[seg + 1]) < d:
			seg += 1
		var a := pts[seg]
		var b := pts[seg + 1]
		var seg_len := float(cum[seg + 1]) - float(cum[seg])
		var t := (d - float(cum[seg])) / seg_len if seg_len > 0.0 else 0.0
		var fwd := (b - a).normalized()
		var basis := Basis()
		if absf(fwd.dot(Vector3.UP)) < 0.999:
			basis = Basis.looking_at(fwd, Vector3.UP)
		if posmod(idx, 2) == 1:
			basis = basis * Basis(Vector3.BACK, PI * 0.5)
		var side := Vector3(fwd.z, 0.0, -fwd.x).normalized() * lateral
		out.append({"t": Transform3D(basis, a.lerp(b, t) + side), "d": d, "i": idx})
		d += spacing
		idx += 1
	return out


## Whether a link at index `i` shows in this pattern (dashed drops the off groups).
static func link_on(pat: String, i: int) -> bool:
	if pat == "dashed":
		return posmod(i, DASH_ON + DASH_OFF) < DASH_ON
	return true


## Reads the rider and advances the chain by `dt`.
func update(rider: SiegeRiderState, dt: float) -> void:
	var to_pad := 0
	if rider != null and SiegeIds.is_pad(rider.target) and rider.connected:
		to_pad = rider.target
	if to_pad != pad:
		pad = to_pad
		if pad == 0:
			path = PackedVector3Array()
			path_length = 0.0
		else:
			if not _cache.has(pad):
				_cache[pad] = build_path(pad)
			path = _cache[pad]
			path_length = polyline_length(path)
		scroll_m = 0.0
	if pad == 0 or path.size() < 2:
		chain.visible = false
		lit = 0.0
		return
	chain.visible = true
	lit = 1.0 - clampf(rider.reconnect_s / RECONNECT_S, 0.0, 1.0)
	if rider.reconnect_s <= 0.0 and not rider.afk:
		scroll_m += SiegeWheelMath.rim_speed(rider.p_eff_w) * dt
	_place()


func _place() -> void:
	var xforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var front := path_length * lit
	var dim := SiegePalette.CHAIN_DIM
	var strands: Array[float] = []
	if pattern == "double":
		strands.append_array([-0.4, 0.4])
	else:
		strands.append(0.0)
	var spacing := SPACING_M * (1.5 if pattern == "dotted" else 1.0)
	for lateral in strands:
		for item in layout(path, spacing, scroll_m, lateral):
			var i: int = item["i"]
			var dist: float = item["d"]
			if not link_on(pattern, i):
				continue
			if xforms.size() >= CAPACITY:
				break
			var t: Transform3D = item["t"]
			if pattern == "dotted":
				t = Transform3D(t.basis.scaled(Vector3(1.15, 1.15, 0.5)), t.origin)
			xforms.append(t)
			colors.append(color if dist <= front else dim)
	chain.set_instances(xforms, colors)
