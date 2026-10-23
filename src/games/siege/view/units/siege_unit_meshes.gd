class_name SiegeUnitMeshes
extends RefCounted
## The little people and machines of Siege as LowPolyMeshes (brief 3 "Enemies" and "Wheels").
## Every mesh stands on y = 0 and faces -Z. Blocky and muted: cloth, leather and plain shields
## from the palette, never a player color. One MultiMesh per type draws a whole crowd.

const WORKER_HEIGHT_M := 1.75
const RAIDER_HEIGHT_M := 1.7
## Hit-point bar anchor heights above the ground for the types that show bars.
const BAR_HEIGHT_M := {2: 2.6, 3: 3.0, 4: 4.6}


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## A wheel worker: off-white tunic, bare head, two arms swinging at the sides.
static func worker() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	m.add_box(Vector3(0.17, 0.7, 0.2), SiegePalette.LEATHER, _at(-0.13, 0.35, 0.0))
	m.add_box(Vector3(0.17, 0.7, 0.2), SiegePalette.LEATHER, _at(0.13, 0.35, 0.0))
	m.add_box(Vector3(0.5, 0.72, 0.32), SiegePalette.TUNIC, _at(0.0, 1.06, 0.0))
	m.add_box(Vector3(0.13, 0.55, 0.15), SiegePalette.TUNIC, _at(-0.33, 1.1, 0.0))
	m.add_box(Vector3(0.13, 0.55, 0.15), SiegePalette.TUNIC, _at(0.33, 1.1, 0.0))
	m.add_sphere(0.19, 2, 6, SiegePalette.SKIN, _at(0.0, 1.57, 0.0))
	return m


## A Raider: spear, round shield and an iron cap.
static func raider() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	m.add_box(Vector3(0.17, 0.72, 0.2), SiegePalette.LEATHER, _at(-0.12, 0.36, 0.0))
	m.add_box(Vector3(0.17, 0.72, 0.2), SiegePalette.LEATHER, _at(0.12, 0.36, 0.0))
	m.add_box(Vector3(0.5, 0.7, 0.32), SiegePalette.CLOTH, _at(0.0, 1.07, 0.0))
	m.add_sphere(0.18, 2, 6, SiegePalette.SKIN, _at(0.0, 1.55, 0.0))
	m.add_cone(0.24, 0.24, 6, SiegePalette.IRON, _at(0.0, 1.7, 0.0))
	m.add_box(Vector3(0.07, 2.3, 0.07), SiegePalette.WOOD, _at(0.38, 1.15, -0.1))
	m.add_cone(0.08, 0.3, 4, SiegePalette.IRON, _at(0.38, 2.4, -0.1))
	m.add_cylinder(
		0.34,
		0.34,
		0.08,
		8,
		SiegePalette.SHIELD,
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.38, 1.05, -0.16))
	)
	return m


## A Shield wall: a roof and a front rank of plain shields, 2 x 4, standing on legs.
static func shield_wall() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	var pw := 0.92
	for ix in 4:
		var x := (float(ix) - 1.5) * pw
		# Two roof plates deep, one front plate standing.
		for iz in 2:
			var z := (float(iz) - 0.5) * 1.0
			m.add_box(
				Vector3(pw - 0.06, 0.1, 0.94),
				SiegePalette.SHIELD if (ix + iz) % 2 == 0 else SiegePalette.LEATHER,
				_at(x, 1.7, z)
			)
		m.add_box(Vector3(pw - 0.06, 0.95, 0.12), SiegePalette.SHIELD, _at(x, 1.15, -0.62))
		m.add_box(Vector3(0.18, 0.7, 0.2), SiegePalette.LEATHER, _at(x - 0.18, 0.35, -0.3))
		m.add_box(Vector3(0.18, 0.7, 0.2), SiegePalette.LEATHER, _at(x + 0.18, 0.35, -0.3))
		m.add_box(Vector3(0.18, 0.7, 0.2), SiegePalette.LEATHER, _at(x - 0.18, 0.35, 0.3))
		m.add_box(Vector3(0.18, 0.7, 0.2), SiegePalette.LEATHER, _at(x + 0.18, 0.35, 0.3))
		m.add_cone(0.2, 0.2, 5, SiegePalette.IRON, _at(x, 1.85, 0.2))
	m.add_box(Vector3(pw * 4.0, 0.1, 0.12), SiegePalette.WOOD_DARK, _at(0.0, 0.62, -0.62))
	return m


## A horseman: a blocky horse with a rider holding a spear.
static func horseman() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	var horse := SiegePalette.shade(SiegePalette.LEATHER, 0.28)
	var dark := SiegePalette.shade(SiegePalette.LEATHER, 0.45)
	m.add_box(Vector3(0.75, 0.8, 1.9), horse, _at(0.0, 1.2, 0.0))
	m.add_box(
		Vector3(0.32, 0.85, 0.5),
		horse,
		Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 1.65, -1.0))
	)
	m.add_box(Vector3(0.3, 0.32, 0.6), dark, _at(0.0, 1.95, -1.4))
	m.add_box(
		Vector3(0.12, 0.6, 0.12),
		dark,
		Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.0, 1.0, 1.05))
	)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.add_box(Vector3(0.18, 0.85, 0.2), dark, _at(sx * 0.26, 0.425, sz * 0.7))
	# The rider.
	m.add_box(Vector3(0.45, 0.65, 0.3), SiegePalette.CLOTH, _at(0.0, 2.0, 0.1))
	m.add_sphere(0.17, 2, 6, SiegePalette.SKIN, _at(0.0, 2.5, 0.1))
	m.add_cone(0.22, 0.22, 6, SiegePalette.IRON, _at(0.0, 2.64, 0.1))
	m.add_box(
		Vector3(0.07, 2.6, 0.07),
		SiegePalette.WOOD,
		Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0.45, 2.1, -0.3))
	)
	m.add_cylinder(
		0.3,
		0.3,
		0.08,
		8,
		SiegePalette.SHIELD,
		Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.5, 2.0, 0.0))
	)
	return m


## A battering ram: a roofed shed on four wheels with a log slung under the roof and crew legs
## showing along both sides.
static func ram() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	m.add_box(Vector3(2.9, 0.4, 5.6), SiegePalette.WOOD_DARK, _at(0.0, 0.95, 0.0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.add_cylinder(
				0.6,
				0.6,
				0.3,
				8,
				SiegePalette.IRON,
				Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.55, 0.6, sz * 1.9))
			)
	for sx: float in [-1.0, 1.0]:
		m.add_box(Vector3(0.2, 1.7, 0.2), SiegePalette.WOOD, _at(sx * 1.2, 1.9, -2.2))
		m.add_box(Vector3(0.2, 1.7, 0.2), SiegePalette.WOOD, _at(sx * 1.2, 1.9, 2.2))
		m.add_box(Vector3(0.12, 1.2, 5.0), SiegePalette.SHIELD, _at(sx * 1.3, 1.7, 0.0))
	m.add_box(Vector3(2.7, 0.1, 5.4), SiegePalette.WOOD_DARK, _at(0.0, 2.8, 0.0))
	m.add_wedge(
		Vector3(3.2, 0.9, 2.8),
		SiegePalette.WOOD,
		Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 3.3, -1.4 - 0.0))
	)
	m.add_wedge(Vector3(3.2, 0.9, 2.8), SiegePalette.WOOD, _at(0.0, 3.3, 1.4))
	m.add_cylinder(
		0.3, 0.3, 6.6, 7, SiegePalette.WOOD_DARK, Transform3D(along, Vector3(0.0, 1.9, -0.5))
	)
	m.add_cylinder(
		0.38, 0.3, 0.5, 7, SiegePalette.IRON, Transform3D(along, Vector3(0.0, 1.9, -3.9))
	)
	for sx: float in [-1.0, 1.0]:
		for iz in 3:
			m.add_box(
				Vector3(0.18, 0.72, 0.2),
				SiegePalette.LEATHER,
				_at(sx * 1.75, 0.36, -1.7 + float(iz) * 1.7)
			)
	return m


## A block bolt: a thin wooden shaft with an iron head, along -Z, 1.6 m long.
static func bolt() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	m.add_box(Vector3(0.1, 0.1, 1.4), SiegePalette.WOOD_DARK, _at(0.0, 0.0, 0.0))
	m.add_box(Vector3(0.16, 0.16, 0.3), SiegePalette.IRON, _at(0.0, 0.0, -0.8))
	return m


## A caltrop spike: a small iron cone.
static func spike() -> LowPolyMesh:
	var m := LowPolyMesh.new()
	m.add_cone(0.2, 0.7, 4, SiegePalette.IRON, _at(0.0, 0.35, 0.0))
	return m
