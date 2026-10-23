class_name SiegeTerrain
extends RefCounted
## The hill under Castellum Rotae: a flat plateau under the fort that falls away in faceted
## ground, with rock faces on the steep facets and dust roads laid on top (brief 3 "Scene").
## Deterministic from the map's terrain seed. height_at() answers with the faceted mesh's own
## surface (triangle interpolation over the same grid), so roads, enemies and trees sit exactly
## on what is drawn.

const HALF_M := 270.0
## The hill is centred a little south of the fort so the plaza stays on the plateau.
const CENTER := Vector2(0.0, 6.0)
const ROAD_HALF_M := 2.7
const ROAD_LIFT_M := 0.1

var plateau_y: float = 0.0
var plateau_r: float = 48.0
var drop_m: float = 18.0
var hill_r: float = 150.0
var facet_m: float = 8.0
var seed_value: int = 41
var cells: int = 68
var _h: PackedFloat32Array = PackedFloat32Array()
var _built: bool = false


static func from_map(map: SiegeMap) -> SiegeTerrain:
	var t := SiegeTerrain.new()
	if map != null:
		var d: Dictionary = map.data.get("terrain", {})
		t.plateau_y = float(d.get("plateau_y", 0.0))
		t.plateau_r = maxf(float(d.get("plateau_radius_m", 46.0)), 40.0) + 2.0
		t.drop_m = float(d.get("hill_drop_m", 18.0))
		t.hill_r = float(d.get("hill_radius_m", 150.0))
		t.facet_m = maxf(float(d.get("facet_m", 8.0)), 4.0)
		t.seed_value = int(d.get("seed", 41))
	t.cells = maxi(int(round(2.0 * HALF_M / t.facet_m)), 8)
	t.build_heights()
	return t


## The smooth height function the facets sample.
func raw_height(x: float, z: float) -> float:
	var d := Vector2(x - CENTER.x, z - CENTER.y).length()
	var u := clampf((d - plateau_r) / maxf(hill_r - plateau_r, 1.0), 0.0, 1.0)
	var s := u * u * (3.0 - 2.0 * u)
	var far := clampf((d - hill_r) / 160.0, 0.0, 1.0)
	var ph := float(seed_value) * 0.37
	var ridges := (
		5.5 * sin(x * 0.043 + ph) * cos(z * 0.051 - ph * 0.7)
		+ 3.2 * sin(x * 0.097 + z * 0.061 + ph * 1.3)
		+ 2.6 * cos(x * 0.15 - z * 0.12 + ph * 0.4)
		+ 2.4 * sin(x * 0.23 + ph * 2.1) * cos(z * 0.21 - ph)
	)
	var h := plateau_y - drop_m * s + ridges * clampf(s * 1.6, 0.0, 1.0)
	return h - far * 6.0 + far * 4.0 * sin(x * 0.03 + z * 0.02)


func build_heights() -> void:
	var n := cells + 1
	_h.resize(n * n)
	for iz in n:
		for ix in n:
			var p := _vertex_xz(ix, iz)
			_h[iz * n + ix] = raw_height(p.x, p.y)
	_built = true


func cell_size() -> float:
	return 2.0 * HALF_M / float(cells)


func _vertex_xz(ix: int, iz: int) -> Vector2:
	var cs := cell_size()
	return Vector2(-HALF_M + float(ix) * cs, -HALF_M + float(iz) * cs)


func vertex_height(ix: int, iz: int) -> float:
	var n := cells + 1
	return _h[clampi(iz, 0, cells) * n + clampi(ix, 0, cells)]


## The ground height at (x, z): the faceted mesh's surface (the same diagonals as
## LowPolyMesh.add_grid), flat outside the grid.
func height_at(x: float, z: float) -> float:
	if not _built:
		build_heights()
	var cs := cell_size()
	var gx := clampf((x + HALF_M) / cs, 0.0, float(cells) - 0.0001)
	var gz := clampf((z + HALF_M) / cs, 0.0, float(cells) - 0.0001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	var h00 := vertex_height(ix, iz)
	var h10 := vertex_height(ix + 1, iz)
	var h01 := vertex_height(ix, iz + 1)
	var h11 := vertex_height(ix + 1, iz + 1)
	if (ix + iz) % 2 == 0:
		# Diagonal p00-p11: triangles (p00, p10, p11) and (p00, p11, p01).
		if fx >= fz:
			return h00 + (h10 - h00) * fx + (h11 - h10) * fz
		return h00 + (h11 - h01) * fx + (h01 - h00) * fz
	# Diagonal p10-p01: triangles (p00, p10, p01) and (p10, p11, p01).
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


## The terrain mesh: one grid, flat-shaded, ochre with dry-grass patches and grey rock on the
## steep facets.
func add_to(lp: LowPolyMesh) -> void:
	lp.add_grid(
		Vector2(2.0 * HALF_M, 2.0 * HALF_M),
		Vector2i(cells, cells),
		height_at_local,
		SiegePalette.OCHRE,
		facet_color
	)


## add_grid's height callback (local grid coordinates are world x, z).
func height_at_local(x: float, z: float) -> float:
	var cs := cell_size()
	var ix := clampi(int(round((x + HALF_M) / cs)), 0, cells)
	var iz := clampi(int(round((z + HALF_M) / cs)), 0, cells)
	return vertex_height(ix, iz)


## A facet's color from its centre and normal.
func facet_color(center: Vector3, normal: Vector3) -> Color:
	var n := (
		sin(center.x * 0.21 + float(seed_value)) * cos(center.z * 0.17)
		+ 0.5 * sin(center.x * 0.05 - center.z * 0.08)
	)
	var jitter := 0.06 * sin(center.x * 1.7 + center.z * 2.3)
	var base := SiegePalette.OCHRE
	if n > 0.7:
		base = SiegePalette.OCHRE.lerp(SiegePalette.OLIVE, 0.4)
	elif n < -0.8:
		base = SiegePalette.OCHRE.lerp(SiegePalette.DUST, 0.45)
	var steep := clampf((0.94 - normal.y) * 10.0, 0.0, 1.0)
	var col := base.lerp(SiegePalette.ROCK, steep)
	if steep > 0.0:
		col = col.darkened(0.12 * steep)
	return Color(
		clampf(col.r + jitter, 0.0, 1.0),
		clampf(col.g + jitter, 0.0, 1.0),
		clampf(col.b + jitter, 0.0, 1.0)
	)


## Dust road ribbons over the ground along every map road, plus the gate plaza disc.
func add_roads_to(lp: LowPolyMesh, map: SiegeMap) -> void:
	for road in map.road_count():
		var length := map.road_length(road)
		var steps := int(ceil(length / 2.0))
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in steps + 1:
			var prog := minf(float(i) * 2.0, length)
			var c := map.point_at(road, prog)
			var dir := map.dir_at(road, minf(prog, length - 0.01))
			var side := Vector2(dir.y, -dir.x) * ROAD_HALF_M
			var a := c + side
			var b := c - side
			var pl := Vector3(a.x, height_at(a.x, a.y) + ROAD_LIFT_M, a.y)
			var pr := Vector3(b.x, height_at(b.x, b.y) + ROAD_LIFT_M, b.y)
			if i > 0:
				lp.add_quad(prev_l, pl, pr, prev_r, SiegePalette.DUST, Vector3.UP)
			prev_l = pl
			prev_r = pr
	var pc := map.plaza_center
	var r := map.plaza_radius_m
	var y := height_at(pc.x, pc.y) + ROAD_LIFT_M
	var ring_pts: Array[Vector3] = []
	for k in 20:
		var a := TAU * float(k) / 20.0
		ring_pts.append(Vector3(pc.x + cos(a) * r, y, pc.y + sin(a) * r))
	for k in 20:
		lp.add_triangle(
			Vector3(pc.x, y, pc.y),
			ring_pts[k],
			ring_pts[(k + 1) % 20],
			SiegePalette.DUST,
			Vector3.UP
		)
