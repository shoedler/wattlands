class_name SiegeGateView
extends Node3D
## The gate in the south wall (brief 3 "Gate"): two dark wooden leaves that gain iron bands with
## each Iron-bands upgrade and lose planks at 66% and 33% of the gate's HP. On a Breach the
## leaves burst open in a puff of CPUParticles3D dust and swing shut again when the gate is
## restored. Only reads the state.

const PLANKS_PER_LEAF := 6
const OPEN_ANGLE := 1.45
const OPEN_RATE := 5.0
const DUST_AMOUNT := 48

var fort: SiegeFortBuilder = null
var left: MeshInstance3D = null
var right: MeshInstance3D = null
var dust: CPUParticles3D = null
## Planks lost (0 above 66%, 1 up to 66%, 2 up to 33%) and iron bands drawn.
var tier: int = -1
var bands: int = -1
var open_amount: float = 0.0
var breached: bool = false
var bursts: int = 0


func setup(p_fort: SiegeFortBuilder) -> void:
	fort = p_fort
	name = "Gate"
	position = Vector3(0.0, 0.0, fort.fort_half.y + fort.wall_t * 0.2)
	left = MeshInstance3D.new()
	left.name = "LeafLeft"
	left.position = Vector3(-fort.gate_w * 0.5, 0.0, 0.0)
	right = MeshInstance3D.new()
	right.name = "LeafRight"
	right.position = Vector3(fort.gate_w * 0.5, 0.0, 0.0)
	add_child(left)
	add_child(right)
	dust = CPUParticles3D.new()
	dust.name = "BreachDust"
	dust.position = Vector3(0.0, 2.0, 1.2)
	dust.amount = DUST_AMOUNT
	dust.lifetime = 1.8
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.emitting = false
	dust.direction = Vector3(0.0, 0.5, 1.0)
	dust.spread = 55.0
	dust.gravity = Vector3(0.0, -2.2, 0.0)
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 7.0
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.4
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.7, 0.7)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(SiegePalette.DUST, 0.9))
	ramp.set_color(1, Color(SiegePalette.DUST, 0.0))
	dust.color_ramp = ramp
	dust.scale_amount_curve = _dust_curve()
	dust.mesh = bm
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	_rebuild(0, 0)


## The dust puffs swell and then thin out.
static func _dust_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(0.4, 1.0))
	c.add_point(Vector2(1.0, 1.6))
	return c


## Planks lost at `hp_frac` (gate HP / max): 0 above 66%, 1 above 33%, else 2.
static func tier_for(hp_frac: float) -> int:
	if hp_frac > 0.66:
		return 0
	if hp_frac > 0.33:
		return 1
	return 2


func _leaf_mesh(side: float, lost: int, iron: int) -> ArrayMesh:
	var m := LowPolyMesh.new()
	var leaf_w := fort.gate_w * 0.5
	var pw := leaf_w / float(PLANKS_PER_LEAF)
	var door_h := SiegeFortBuilder.GATE_DOOR_H - 0.1
	for i in PLANKS_PER_LEAF:
		# The leaf extends from its hinge toward the gate's middle: x = -side * ...
		var x := -side * (pw * (float(i) + 0.5))
		var plank_no := i + (0 if side < 0.0 else PLANKS_PER_LEAF)
		var broken := (
			(lost >= 1 and plank_no in [1, 4, 8]) or (lost >= 2 and plank_no in [3, 6, 10])
		)
		var h := door_h * (0.28 if broken else 1.0)
		var col := (
			SiegePalette.WOOD_DARK
			if i % 2 == 0
			else SiegePalette.shade(SiegePalette.WOOD_DARK, 0.12)
		)
		m.add_box(Vector3(pw - 0.06, h, 0.4), col, Transform3D(Basis(), Vector3(x, h * 0.5, 0.0)))
	for b in iron:
		var y := 1.3 + 1.35 * float(b)
		m.add_box(
			Vector3(leaf_w, 0.28, 0.5),
			SiegePalette.IRON,
			Transform3D(Basis(), Vector3(-side * leaf_w * 0.5, y, 0.0))
		)
	m.add_box(
		Vector3(leaf_w, 0.2, 0.46),
		SiegePalette.WOOD,
		Transform3D(Basis(), Vector3(-side * leaf_w * 0.5, door_h - 0.1, 0.0))
	)
	m.darken_near_ground(0.0, 1.5, 0.25)
	return m.build()


func _rebuild(new_tier: int, new_bands: int) -> void:
	tier = new_tier
	bands = new_bands
	left.mesh = _leaf_mesh(-1.0, tier, bands)
	right.mesh = _leaf_mesh(1.0, tier, bands)


## Reads the gate state: planks by HP, bands by upgrade, the doors open during a Breach.
func update(state: SiegeState, dt: float) -> void:
	var frac := clampf(state.gate_hp / maxf(state.gate_max, 1.0), 0.0, 1.0)
	var new_tier := tier_for(frac)
	var new_bands := clampi(state.iron_bands, 0, 2)
	if new_tier != tier or new_bands != bands:
		_rebuild(new_tier, new_bands)
	var now_breached := state.breach_s > 0.0
	if now_breached and not breached:
		bursts += 1
		dust.restart()
		dust.emitting = true
	breached = now_breached
	var goal := 1.0 if breached else 0.0
	open_amount = move_toward(open_amount, goal, OPEN_RATE * dt)
	left.rotation.y = -OPEN_ANGLE * open_amount
	right.rotation.y = OPEN_ANGLE * open_amount
