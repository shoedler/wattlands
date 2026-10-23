class_name SiegeTowerMeshes
extends RefCounted
## The three tower silhouettes (brief 3 "Towers"), each standing on y = 0 and firing toward -Z:
## the Ballista is a big bow frame, the Scorpion a small triple frame and the Caltrop thrower a
## sling arm. Upgrade levels show as 1-3 bronze bands round the wooden pedestal.

const PEDESTAL_H := 1.5


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## The mesh of `type` (SiegeIds.TOWER_*) at upgrade `level` (0..3).
static func build(type: int, level: int) -> LowPolyMesh:
	var m := LowPolyMesh.new()
	match type:
		SiegeIds.TOWER_BALLISTA:
			_ballista(m)
		SiegeIds.TOWER_SCORPION:
			_scorpion(m)
		SiegeIds.TOWER_CALTROP:
			_caltrop(m)
		_:
			return m
	_bands(m, level)
	m.darken_near_ground(0.0, 0.9, 0.22)
	return m


static func _pedestal(m: LowPolyMesh, radius: float) -> void:
	m.add_cylinder(
		radius, radius * 0.88, PEDESTAL_H, 8, SiegePalette.WOOD, _at(0.0, PEDESTAL_H * 0.5, 0.0)
	)
	m.add_cylinder(
		radius * 1.05,
		radius * 1.05,
		0.18,
		8,
		SiegePalette.WOOD_DARK,
		_at(0.0, PEDESTAL_H + 0.09, 0.0)
	)


static func _bands(m: LowPolyMesh, level: int) -> void:
	for i in clampi(level, 0, SiegeIds.MAX_TOWER_LEVEL):
		m.add_cylinder(
			1.14, 1.14, 0.16, 8, SiegePalette.BRONZE, _at(0.0, 0.32 + 0.4 * float(i), 0.0)
		)


## A big bow: a stock with a slider, two long limbs sweeping back to a string, a loaded bolt.
static func _ballista(m: LowPolyMesh) -> void:
	_pedestal(m, 1.05)
	var y := PEDESTAL_H + 0.55
	m.add_box(Vector3(0.34, 0.34, 3.8), SiegePalette.WOOD_DARK, _at(0.0, y, -0.3))
	m.add_box(Vector3(0.5, 0.5, 0.9), SiegePalette.BRONZE_DARK, _at(0.0, y, 0.0))
	m.add_box(Vector3(0.3, 0.9, 0.3), SiegePalette.WOOD_DARK, _at(0.0, y - 0.55, 0.0))
	for sx: float in [-1.0, 1.0]:
		# Limb: from the stock out to the side and slightly back.
		m.add_box(
			Vector3(2.4, 0.26, 0.28),
			SiegePalette.WOOD,
			Transform3D(Basis(Vector3.UP, sx * 0.28), Vector3(sx * 1.2, y, -0.45))
		)
		m.add_box(
			Vector3(0.9, 0.24, 0.26),
			SiegePalette.WOOD,
			Transform3D(Basis(Vector3.UP, sx * 0.75), Vector3(sx * 2.62, y, -0.1))
		)
		m.add_cylinder(0.2, 0.2, 0.5, 6, SiegePalette.BRONZE, _at(sx * 0.55, y, -0.35))
	# The string and a loaded bolt.
	m.add_box(Vector3(5.0, 0.07, 0.07), SiegePalette.LEATHER, _at(0.0, y + 0.02, 0.4))
	m.add_box(Vector3(0.1, 0.1, 2.6), SiegePalette.WOOD, _at(0.0, y + 0.26, -0.9))
	m.add_cone(
		0.13,
		0.4,
		4,
		SiegePalette.IRON,
		Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, y + 0.26, -2.3))
	)


## A small triple frame: three little bows stacked on one stock.
static func _scorpion(m: LowPolyMesh) -> void:
	_pedestal(m, 0.8)
	var y := PEDESTAL_H + 0.4
	m.add_box(Vector3(0.26, 0.26, 2.6), SiegePalette.WOOD_DARK, _at(0.0, y, -0.2))
	for i in 3:
		var yy := y + 0.28 + float(i) * 0.32
		var span := 1.6 - float(i) * 0.25
		m.add_box(Vector3(span, 0.16, 0.2), SiegePalette.WOOD, _at(0.0, yy, -0.1 - float(i) * 0.1))
		m.add_box(Vector3(0.08, 0.1, 1.9), SiegePalette.WOOD, _at(0.0, yy + 0.1, -0.9))
		m.add_cone(
			0.08,
			0.25,
			4,
			SiegePalette.IRON,
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, yy + 0.1, -1.95))
		)
	m.add_box(Vector3(0.14, 1.0, 0.14), SiegePalette.WOOD_DARK, _at(-0.6, y + 0.5, -0.1))
	m.add_box(Vector3(0.14, 1.0, 0.14), SiegePalette.WOOD_DARK, _at(0.6, y + 0.5, -0.1))


## A sling arm: an A-frame, a long throwing arm with a basket and a counterweight.
static func _caltrop(m: LowPolyMesh) -> void:
	_pedestal(m, 1.0)
	var y := PEDESTAL_H + 0.2
	for sx: float in [-1.0, 1.0]:
		m.add_box(
			Vector3(0.22, 2.4, 0.22),
			SiegePalette.WOOD_DARK,
			Transform3D(Basis(Vector3.BACK, sx * -0.22), Vector3(sx * 0.55, y + 1.2, 0.0))
		)
	m.add_cylinder(
		0.12,
		0.12,
		1.4,
		6,
		SiegePalette.BRONZE_DARK,
		Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, y + 2.3, 0.0))
	)
	# The arm: pivots on the axle, basket forward-up, counterweight back-down.
	var arm := Basis(Vector3.RIGHT, 0.6)
	m.add_box(
		Vector3(0.26, 0.26, 4.6),
		SiegePalette.WOOD,
		Transform3D(arm, Vector3(0.0, y + 2.3, 0.0) + arm * Vector3(0, 0, -0.9))
	)
	m.add_box(
		Vector3(1.0, 0.8, 1.0),
		SiegePalette.WOOD_DARK,
		Transform3D(arm, Vector3(0.0, y + 2.3, 0.0) + arm * Vector3(0, 0, 1.6))
	)
	m.add_box(
		Vector3(0.7, 0.35, 0.7),
		SiegePalette.LEATHER,
		Transform3D(arm, Vector3(0.0, y + 2.3, 0.0) + arm * Vector3(0, 0.1, -3.0))
	)
	m.add_sphere(0.28, 2, 5, SiegePalette.IRON, _at(0.0, y + 4.1, -2.4))
