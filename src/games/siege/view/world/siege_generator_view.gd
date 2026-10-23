class_name SiegeGeneratorView
extends Node3D
## The bronze generator's moving parts (brief 3 "Generator"): the flywheel on the drum, spinning
## with the team's watts, and the counter plaque above it. Four Label3D digit drums and a "W"
## plate show the team's raw watts (state.team_w, a 1 s mean), rolling with a 0.4 s ease and
## clamped at 9999 (SiegeDrum). The digits are 3.4 m tall at the fort, about 50 px at 1080p with
## the miniature camera. The static drum body and the shafts are SiegeFortBuilder's.

const FONT_PX := 128
const PIXEL_SIZE := 0.037
## The digit pitch on the plaque (m) and where the first drum sits.
const DIGIT_PITCH_M := 2.72
const DIGIT_X0 := -5.2
const W_PLATE_X := 5.7
const WINDOW_SIZE := Vector2(2.5, 4.25)
## The cap height of a digit in metres (0.72 of the 4.74 m em).
const DIGIT_HEIGHT_M := 3.4
const IVORY := Color("#F4F0E4")
const FLY_SPIN_PER_KW := 1.5
const FLY_SPIN_MAX := 5.0

var fort: SiegeFortBuilder = null
var flywheel: Node3D = null
var plaque: Node3D = null
var drum := SiegeDrum.new()
## Per drum place (left to right): the label showing the current digit and the one rolling in.
var cur_labels: Array[Label3D] = []
var next_labels: Array[Label3D] = []
var w_label: Label3D = null
var spin: float = 0.0
var _first: bool = true


func setup(p_fort: SiegeFortBuilder) -> void:
	fort = p_fort
	name = "Generator"
	var gp := fort.map.generator_pos
	position = Vector3(gp.x, 0.0, gp.y)
	_build_flywheel()
	_build_plaque()


## The drum cap height in on-screen pixels at 1080p for a camera `distance_m` away that looks
## down `pitch_deg` with a vertical field of view of `fov_deg`; the plaque leans back by
## PLAQUE_TILT_DEG toward the camera, so only the difference of the two foreshortens it.
static func digit_px_at_1080p(distance_m: float, fov_deg: float, pitch_deg: float) -> float:
	var px_per_m := 1080.0 / (2.0 * distance_m * tan(deg_to_rad(fov_deg) * 0.5))
	var facing := cos(deg_to_rad(pitch_deg - SiegeFortBuilder.PLAQUE_TILT_DEG))
	return DIGIT_HEIGHT_M * px_per_m * maxf(facing, 0.0)


func _build_flywheel() -> void:
	flywheel = Node3D.new()
	flywheel.name = "Flywheel"
	flywheel.position = Vector3(0.0, SiegeFortBuilder.FLYWHEEL_Y, 0.0)
	var m := LowPolyMesh.new()
	m.add_ring(3.7, 0.9, 0.55, 18, SiegePalette.BRONZE)
	for k in 8:
		var b := Basis(Vector3.BACK, TAU * float(k) / 8.0)
		m.add_box(
			Vector3(0.34, 2.9, 0.34),
			SiegePalette.BRONZE_DARK,
			Transform3D(b, b * Vector3(0.0, 1.45, 0.0))
		)
	m.add_cylinder(
		0.9,
		0.9,
		0.9,
		10,
		SiegePalette.PATINA,
		Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	)
	var mi := m.make_instance("FlywheelMesh")
	mi.rotation.x = -PI * 0.5
	flywheel.add_child(mi)
	add_child(flywheel)


func _build_plaque() -> void:
	plaque = Node3D.new()
	plaque.name = "Plaque"
	plaque.position = SiegeFortBuilder.PLAQUE_CENTER
	plaque.rotation.x = -deg_to_rad(SiegeFortBuilder.PLAQUE_TILT_DEG)
	var size := SiegeFortBuilder.PLAQUE_SIZE
	var m := LowPolyMesh.new()
	m.add_box(Vector3(size.x, size.y, 0.5), SiegePalette.BRONZE_DARK, Transform3D.IDENTITY)
	m.add_box(
		Vector3(size.x + 0.5, 0.35, 0.7),
		SiegePalette.BRONZE,
		Transform3D(Basis(), Vector3(0.0, size.y * 0.5, 0.0))
	)
	m.add_box(
		Vector3(size.x + 0.5, 0.35, 0.7),
		SiegePalette.BRONZE,
		Transform3D(Basis(), Vector3(0.0, -size.y * 0.5, 0.0))
	)
	var window := SiegePalette.shade(SiegePalette.IRON, 0.35)
	for i in SiegeDrum.PLACES:
		m.add_box(
			Vector3(WINDOW_SIZE.x, WINDOW_SIZE.y, 0.2),
			window,
			Transform3D(Basis(), Vector3(DIGIT_X0 + DIGIT_PITCH_M * float(i), 0.0, 0.3))
		)
	m.add_box(
		Vector3(2.2, WINDOW_SIZE.y, 0.2),
		SiegePalette.BRONZE_DARK,
		Transform3D(Basis(), Vector3(W_PLATE_X, 0.0, 0.3))
	)
	plaque.add_child(m.make_instance("PlaqueBody"))
	for i in SiegeDrum.PLACES:
		var x := DIGIT_X0 + DIGIT_PITCH_M * float(i)
		cur_labels.append(_label("Digit%d" % i, Vector3(x, 0.0, 0.42), IVORY))
		next_labels.append(_label("DigitNext%d" % i, Vector3(x, 0.0, 0.42), IVORY))
	w_label = _label("WPlate", Vector3(W_PLATE_X, 0.0, 0.42), SiegePalette.MARBLE, 84)
	w_label.text = "W"
	add_child(plaque)


func _label(label_name: String, pos: Vector3, color: Color, px: int = FONT_PX) -> Label3D:
	var l := Label3D.new()
	l.name = label_name
	l.position = pos
	l.font = WlTheme.bold_font()
	l.font_size = px
	l.pixel_size = PIXEL_SIZE
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.text = ""
	plaque.add_child(l)
	return l


## Feeds the team's raw watts and advances the roll and the flywheel by `dt`.
func update(team_w: float, dt: float) -> void:
	if _first:
		drum.snap_to(team_w)
		_first = false
	drum.set_target_w(team_w)
	drum.step(dt)
	_show_drums()
	var rate := minf(team_w / 1000.0 * FLY_SPIN_PER_KW, FLY_SPIN_MAX)
	spin += rate * dt
	flywheel.rotation.y = spin


func _show_drums() -> void:
	var line := 3.7
	for i in SiegeDrum.PLACES:
		var place := SiegeDrum.PLACES - 1 - i
		var d := drum.drum_at(place)
		var roll := float(d["roll"])
		var cur := int(d["digit"])
		var nxt := int(d["next"])
		var cl := cur_labels[i]
		var nl := next_labels[i]
		cl.text = "" if cur < 0 else str(cur)
		nl.text = "" if (nxt < 0 or roll <= 0.0) else str(nxt)
		cl.position.y = roll * line * 0.5
		nl.position.y = (roll - 1.0) * line * 0.5
		cl.modulate.a = 1.0 - roll
		nl.modulate.a = roll


## What the four drums read now: the digit with the larger share on each drum, left to right
## (blank leading drums are skipped).
func labels_text() -> String:
	var s := ""
	for i in SiegeDrum.PLACES:
		var cl := cur_labels[i]
		var nl := next_labels[i]
		s += nl.text if (nl.text != "" and nl.modulate.a > cl.modulate.a) else cl.text
	return s
