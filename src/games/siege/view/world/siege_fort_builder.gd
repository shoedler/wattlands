class_name SiegeFortBuilder
extends RefCounted
## The static fort of Castellum Rotae as merged LowPolyMeshes (brief 3 "Scene", docs/concept
## notes): plain block walls without masonry or crenellations, corner platforms, terracotta
## houses, marble pad plinths, the wheel frames, the bronze generator body and the shafts that
## join them. Everything here is built once; the moving parts (wheels, flywheel, gate, towers)
## are the other views' job.

const WHEEL_Y := 2.95
const WHEEL_DEPTH_M := 3.2
const CORNER_EXTRA_H := 1.6
const PLINTH_H := 0.6
const PLINTH_SIZE := 5.0
const GEN_RADIUS_M := 3.2
const GEN_BODY_TOP_Y := 4.1
const FLYWHEEL_Y := 4.55
const PLAQUE_TILT_DEG := 30.0
const PLAQUE_SIZE := Vector2(14.6, 5.0)
const PLAQUE_CENTER := Vector3(0.0, 10.8, -0.5)
const CHAIN_LIFT_M := 0.45
const GATE_DOOR_H := 4.4
## The pennant mast's local z on a wheel's frame (behind the wheel, away from the generator).
const MAST_Z := -2.35

var map: SiegeMap = null
var wall_h: float = 6.0
var wall_t: float = 2.5
var fort_half: Vector2 = Vector2(32.0, 26.0)
var gate_w: float = 6.0


func _init(p_map: SiegeMap = null) -> void:
	map = p_map
	if map != null:
		var fort: Dictionary = map.data.get("fort", {})
		wall_h = float(fort.get("wall_h_m", 6.0))
		wall_t = float(fort.get("wall_t_m", 2.5))
		fort_half = map.fort_size * 0.5
		gate_w = float((map.data.get("gate", {}) as Dictionary).get("width_m", 6.0))


## Y of the wall walk (where a pad on a wall sits and chains run).
func walk_y() -> float:
	return wall_h


## True for the four corner pads (they stand on corner platforms).
func is_corner_pad(pad: int) -> bool:
	return is_corner(map.pad_pos(pad))


func is_corner(p: Vector2) -> bool:
	return absf(absf(p.x) - fort_half.x) < 1.0 and absf(absf(p.y) - fort_half.y) < 1.0


## Y of the top of pad `pad`'s plinth, where its tower stands.
func pad_top_y(pad: int) -> float:
	return walk_y() + (CORNER_EXTRA_H if is_corner_pad(pad) else 0.0) + PLINTH_H


## Y a chain runs at on the wall walk for a wall-walk node at `p` (corner nodes sit on the
## corner platforms).
func chain_y_at(p: Vector2) -> float:
	return walk_y() + CHAIN_LIFT_M + (CORNER_EXTRA_H if is_corner(p) else 0.0)


## A wheel's yaw (about Y) so its local +Z points at the generator.
func wheel_yaw(slot: int) -> float:
	var d := map.generator_pos - map.wheel_pos(slot)
	return atan2(d.x, d.y)


func wheel_transform(slot: int) -> Transform3D:
	var p := map.wheel_pos(slot)
	return Transform3D(Basis(Vector3.UP, wheel_yaw(slot)), Vector3(p.x, 0.0, p.y))


## Everything that never moves, one LowPolyMesh (one draw call).
func build_static() -> LowPolyMesh:
	var lp := LowPolyMesh.new()
	_add_floor(lp)
	_add_walls(lp)
	_add_corner_platforms(lp)
	_add_plinths(lp)
	_add_houses(lp)
	var frame := _wheel_frame()
	for slot in 4:
		lp.append(frame, wheel_transform(slot))
		lp.append(_shaft(slot), wheel_transform(slot))
	_add_generator_body(lp)
	return lp


func _add_floor(lp: LowPolyMesh) -> void:
	lp.add_plane(
		Vector2(fort_half.x * 2.0 - wall_t, fort_half.y * 2.0 - wall_t),
		SiegePalette.MARBLE_SHADE,
		_at(0.0, 0.03, 0.0)
	)
	# A paler paving disc around the generator and a paving lane to the gate.
	lp.add_cylinder(
		7.4, 7.4, 0.1, 20, SiegePalette.MARBLE, _at(map.generator_pos.x, 0.06, map.generator_pos.y)
	)
	lp.add_box(
		Vector3(gate_w + 1.0, 0.08, fort_half.y - 6.0),
		SiegePalette.MARBLE,
		_at(0.0, 0.07, (fort_half.y + 6.0) * 0.5)
	)


func _add_walls(lp: LowPolyMesh) -> void:
	var w := LowPolyMesh.new()
	var hx := fort_half.x
	var hz := fort_half.y
	var m := SiegePalette.MARBLE
	var s := SiegePalette.MARBLE_SHADE
	w.add_box(Vector3(hx * 2.0, wall_h, wall_t), m, _at(0.0, wall_h * 0.5, -hz), s)
	w.add_box(Vector3(wall_t, wall_h, hz * 2.0), m, _at(-hx, wall_h * 0.5, 0.0), s)
	w.add_box(Vector3(wall_t, wall_h, hz * 2.0), m, _at(hx, wall_h * 0.5, 0.0), s)
	var seg := hx - gate_w * 0.5
	w.add_box(Vector3(seg, wall_h, wall_t), m, _at(-gate_w * 0.5 - seg * 0.5, wall_h * 0.5, hz), s)
	w.add_box(Vector3(seg, wall_h, wall_t), m, _at(gate_w * 0.5 + seg * 0.5, wall_h * 0.5, hz), s)
	# The lintel over the gate.
	w.add_box(
		Vector3(gate_w + 0.4, wall_h - GATE_DOOR_H, wall_t),
		m,
		_at(0.0, GATE_DOOR_H + (wall_h - GATE_DOOR_H) * 0.5, hz),
		s
	)
	w.darken_near_ground(0.0, 2.2, 0.28)
	lp.append(w)


func _add_corner_platforms(lp: LowPolyMesh) -> void:
	var tower := LowPolyMesh.new()
	var h := wall_h + CORNER_EXTRA_H
	tower.add_box(
		Vector3(8.0, h, 8.0), SiegePalette.MARBLE, _at(0.0, h * 0.5, 0.0), SiegePalette.MARBLE_SHADE
	)
	tower.add_box(
		Vector3(8.4, 0.5, 8.4),
		SiegePalette.MARBLE_SHADE,
		_at(0.0, h - 0.25, 0.0),
		SiegePalette.MARBLE
	)
	tower.darken_near_ground(0.0, 2.4, 0.3)
	for c: Vector2 in [
		Vector2(-fort_half.x, -fort_half.y),
		Vector2(fort_half.x, -fort_half.y),
		Vector2(-fort_half.x, fort_half.y),
		Vector2(fort_half.x, fort_half.y)
	]:
		lp.append(tower, _at(c.x, 0.0, c.y))


func _add_plinths(lp: LowPolyMesh) -> void:
	var plinth := LowPolyMesh.new()
	plinth.add_box(
		Vector3(PLINTH_SIZE, PLINTH_H, PLINTH_SIZE),
		SiegePalette.MARBLE,
		_at(0.0, PLINTH_H * 0.5, 0.0),
		SiegePalette.MARBLE_SHADE
	)
	for pad in range(1, SiegeIds.PAD_COUNT + 1):
		var p := map.pad_pos(pad)
		if not is_corner_pad(pad):
			# A bastion widens the wall under the pad.
			var side := absf(p.x) > fort_half.x - 1.0
			var size := (
				Vector3(wall_t + 1.8, wall_h, 5.6) if side else Vector3(5.6, wall_h, wall_t + 1.8)
			)
			lp.add_box(
				size, SiegePalette.MARBLE, _at(p.x, wall_h * 0.5, p.y), SiegePalette.MARBLE_SHADE
			)
		lp.append(plinth, _at(p.x, pad_top_y(pad) - PLINTH_H, p.y))


func _house(w: float, d: float, h: float, roof: Color, roof_dark: Color) -> LowPolyMesh:
	var house := LowPolyMesh.new()
	house.add_box(
		Vector3(w, h, d), SiegePalette.MARBLE, _at(0.0, h * 0.5, 0.0), SiegePalette.MARBLE_SHADE
	)
	var rh := d * 0.28
	house.add_wedge(
		Vector3(w + 0.6, rh, d * 0.55),
		roof_dark,
		Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, h + rh * 0.5, -d * 0.25))
	)
	house.add_wedge(Vector3(w + 0.6, rh, d * 0.55), roof, _at(0.0, h + rh * 0.5, d * 0.25))
	house.darken_near_ground(0.0, 1.6, 0.3)
	return house


func _add_houses(lp: LowPolyMesh) -> void:
	var barracks := _house(14.0, 7.0, 4.0, SiegePalette.TERRACOTTA_LIGHT, SiegePalette.TERRACOTTA)
	lp.append(barracks, _at(-21.0, 0.0, -19.0))
	lp.append(barracks, _at(21.0, 0.0, -19.0))
	var small := _house(9.0, 6.0, 3.4, SiegePalette.TERRACOTTA_LIGHT, SiegePalette.TERRACOTTA)
	lp.append(small, _at(-21.5, 0.0, 19.0))
	lp.append(small, _at(21.5, 0.0, 19.0))
	# Crates and barrels by the gate lane.
	var crates := LowPolyMesh.new()
	crates.add_box(Vector3(1.4, 1.2, 1.4), SiegePalette.WOOD, _at(0.0, 0.6, 0.0))
	crates.add_box(Vector3(1.1, 0.9, 1.1), SiegePalette.WOOD_DARK, _at(1.3, 0.45, 0.4))
	crates.add_cylinder(0.5, 0.5, 1.0, 7, SiegePalette.WOOD, _at(-1.1, 0.5, 0.2))
	crates.darken_near_ground(0.0, 0.8, 0.3)
	lp.append(crates, _at(-8.0, 0.0, 14.0))
	lp.append(crates, _at(8.5, 0.0, 13.0))


## One wheel's wooden frame in the wheel's local space (+Z toward the generator): a base
## platform and bearing posts either side of the hub.
func _wheel_frame() -> LowPolyMesh:
	var f := LowPolyMesh.new()
	f.add_box(Vector3(6.6, 0.45, 4.6), SiegePalette.WOOD_DARK, _at(0.0, 0.225, 0.0))
	for zs: float in [-1.0, 1.0]:
		var z := zs * (WHEEL_DEPTH_M * 0.5 + 0.35)
		var post_h := WHEEL_Y + 0.4
		f.add_box(Vector3(0.45, post_h, 0.45), SiegePalette.WOOD, _at(-0.6, post_h * 0.5, z))
		f.add_box(Vector3(0.45, post_h, 0.45), SiegePalette.WOOD, _at(0.6, post_h * 0.5, z))
		f.add_box(Vector3(1.8, 0.35, 0.6), SiegePalette.BRONZE_DARK, _at(0.0, WHEEL_Y, z))
	# The pennant mast stands at the back of the platform, clear of the wheel.
	f.add_cylinder(0.09, 0.09, 5.25, 5, SiegePalette.WOOD_DARK, _at(0.0, 3.075, MAST_Z))
	f.darken_near_ground(0.0, 1.0, 0.3)
	return f


## The shaft from a wheel hub to the generator, in the wheel's local space (+Z toward it): a
## bronze axle with gears at the mid-point and at the drum.
func _shaft(slot: int) -> LowPolyMesh:
	var s := LowPolyMesh.new()
	var dist := map.wheel_pos(slot).distance_to(map.generator_pos)
	var z0 := WHEEL_DEPTH_M * 0.5 + 0.2
	var z1 := dist - GEN_RADIUS_M - 0.2
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	s.add_cylinder(
		0.28,
		0.28,
		z1 - z0,
		8,
		SiegePalette.BRONZE_DARK,
		Transform3D(along, Vector3(0.0, WHEEL_Y, (z0 + z1) * 0.5))
	)
	for gz: float in [z0 + 0.4, z1 - 0.5, lerpf(z0, z1, 0.5)]:
		s.add_cylinder(
			1.0, 1.0, 0.45, 10, SiegePalette.BRONZE, Transform3D(along, Vector3(0.0, WHEEL_Y, gz))
		)
		for k in 10:
			var b := Basis(Vector3.BACK, TAU * float(k) / 10.0)
			s.add_box(
				Vector3(0.28, 0.5, 0.34),
				SiegePalette.BRONZE_DARK,
				Transform3D(b, b * Vector3(0.0, 1.05, 0.0) + Vector3(0.0, WHEEL_Y, gz))
			)
	s.add_box(Vector3(1.0, 1.0, 1.0), SiegePalette.PATINA, _at(0.0, WHEEL_Y, z1 + 0.35))
	return s


func _add_generator_body(lp: LowPolyMesh) -> void:
	var g := LowPolyMesh.new()
	g.add_cylinder(4.3, 4.3, 0.5, 16, SiegePalette.MARBLE_SHADE, _at(0.0, 0.25, 0.0))
	g.add_cylinder(
		GEN_RADIUS_M,
		GEN_RADIUS_M,
		GEN_BODY_TOP_Y - 0.5,
		16,
		SiegePalette.BRONZE,
		_at(0.0, (GEN_BODY_TOP_Y + 0.5) * 0.5, 0.0)
	)
	for by: float in [1.0, 2.3, 3.7]:
		g.add_cylinder(
			GEN_RADIUS_M + 0.12,
			GEN_RADIUS_M + 0.12,
			0.32,
			16,
			SiegePalette.BRONZE_DARK,
			_at(0.0, by, 0.0)
		)
	g.add_cylinder(0.9, 0.9, 0.7, 10, SiegePalette.PATINA, _at(0.0, GEN_BODY_TOP_Y + 0.15, 0.0))
	g.darken_near_ground(0.0, 1.4, 0.25)
	var gp := map.generator_pos
	lp.append(g, _at(gp.x, 0.0, gp.y))
	# Two posts carry the counter plaque above the drum.
	var posts := LowPolyMesh.new()
	var post_h := PLAQUE_CENTER.y - 2.3 - 0.5
	for sx: float in [-1.0, 1.0]:
		posts.add_box(
			Vector3(0.6, post_h, 0.6),
			SiegePalette.BRONZE_DARK,
			_at(sx * 4.0, post_h * 0.5 + 0.5, 0.0)
		)
	lp.append(posts, _at(gp.x, 0.0, gp.y + PLAQUE_CENTER.z))


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))
