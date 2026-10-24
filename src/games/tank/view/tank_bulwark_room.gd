class_name TankBulwarkRoom
extends TankDieselRoom
## The Bulwark's one room (brief 3 "Cutaway"): the diesel machinery plus the three-way gearbox, laid
## out block | flywheel | gearbox so the three read apart. The gearbox is a dark casing with three
## output gears drawn in code as solid toothed wheels, each on its own shaft leaving the box (down
## to the drive chain, up to the turret ring, right to the hoist rail; the rig draws the shafts).
## Only the engaged gear spins, in lit steel with a warm rim and hub; the idle ones stay dark iron.
## A 2 px steel lever about 14 px long with an amber knob stands on a quadrant plate with three
## notches at the gearbox's front, leaning left for Drive ("Dig" at a gun line), upright for Turret
## and right for Hoist, and swings across during a one-second shift. The hoist's progress toward
## the next heavy shell is the cradle climbing the hoist rail to the breech (the rig draws it).

## The output gears: radius (to the tooth roots), teeth, tooth height.
const GEAR_R := 5.5
const GEAR_TEETH := 8
const TOOTH_PX := 2.0
## The lever: length, and its angle (degrees, 0 = right, -90 = up) at Drive, Turret and Hoist.
const LEVER_PX := 14.0
const LEVER_DEG: Array[float] = [-125.0, -90.0, -55.0]

const OUTPUT_KEYS: Array[String] = ["drive", "turret", "hoist"]
## The kilojoules a heavy shell needs (content: tanks.json gearbox.hoist_j; the card shows it too).
const DEFAULT_HOIST_J := 4000.0
## The lever knob's amber.
const KNOB := Color("#ffb35c")

var gearbox_pos: Vector2 = Vector2.ZERO
var pivot: Vector2 = Vector2.ZERO
var outputs: Array[Vector2] = []
var gears: Array[SpinningPart] = []
var hoist_full_j: float = DEFAULT_HOIST_J


func build_more() -> void:
	gearbox_pos = anchor_local("gearbox")
	pivot = anchor_local("lever_pivot")
	var box := Sprite2D.new()
	box.name = "Gearbox"
	box.texture = TankSprites.tex("gearbox")
	box.centered = false
	box.position = gearbox_pos
	# The casing sits back in the dark, so the gears in front of it separate.
	box.self_modulate = Color(0.45, 0.45, 0.48)
	add_child(box)
	var outs: Dictionary = def.get("outputs", {})
	for i in OUTPUT_KEYS.size():
		var o := local(TankRigs.vec(outs.get(OUTPUT_KEYS[i])))
		outputs.append(o)
		var g := SpinningPart.new()
		g.name = "Output_" + OUTPUT_KEYS[i]
		g.texture = TankSprites.tex("gear_medium")
		g.position = o
		g.max_rpm = 120.0
		g.ratio = 1.0 if i != 1 else -1.0
		g.inertia_s = 0.2
		g.snap_steps = 16
		g.auto_process = false
		# The gear itself is drawn in code (paint_more) from this part's angle.
		g.self_modulate = Color(1, 1, 1, 0)
		add_child(g)
		gears.append(g)


func animate_more(dt: float) -> void:
	var active := active_output()
	for i in gears.size():
		gears[i].speed = input.speed() if i == active else 0.0
		gears[i].tick(dt)


## The lever position whose shaft is driven now (0 drive, 1 turret, 2 hoist), -1 while the lever
## moves or the room has no power.
func active_output() -> int:
	var g := station as TankGearboxState
	if g == null or g.move_s > 0.0 or input.unpowered:
		return -1
	return clampi(g.lever, 0, 2)


## The lever tip in room coordinates: at its position, or between two while it shifts.
func lever_tip() -> Vector2:
	var g := station as TankGearboxState
	if g == null or outputs.size() < 3:
		return pivot
	var a := outputs[clampi(g.lever, 0, 2)]
	var b := outputs[clampi(g.lever_to, 0, 2)]
	return a.lerp(b, clampf(1.0 - g.move_s, 0.0, 1.0)) if g.move_s > 0.0 else a


## The hoist bar fill 0 .. 1.
func hoist_fill() -> float:
	var g := station as TankGearboxState
	return clampf(g.hoist_j / hoist_full_j, 0.0, 1.0) if g != null else 0.0


func paint_more(item: Node2D) -> void:
	var active := active_output()
	for i in outputs.size():
		_gear(item, outputs[i], gears[i].angle() if i < gears.size() else 0.0, i == active)
	_lever(item, active)


## The lever's angle in radians: at its position, or swinging between two during a shift.
func lever_angle() -> float:
	var g := station as TankGearboxState
	if g == null:
		return deg_to_rad(LEVER_DEG[1])
	var a := LEVER_DEG[clampi(g.lever, 0, 2)]
	var b := LEVER_DEG[clampi(g.lever_to, 0, 2)]
	var t := clampf(1.0 - g.move_s, 0.0, 1.0) if g.move_s > 0.0 else 0.0
	return deg_to_rad(lerpf(a, b, t))


## The drawn lever's knob (room coordinates).
func knob_pos() -> Vector2:
	return pivot + Vector2.from_angle(lever_angle()) * LEVER_PX


## The lever on its quadrant: a dark iron quadrant plate (an arc band round the pivot) with three
## notches, the engaged one lit amber; a 2 px steel rod with a lit edge from a bolted pivot boss to
## an amber knob, so the lever's lean (left Drive, up Turret, right Hoist) reads at a glance.
func _lever(item: Node2D, active: int) -> void:
	var a0 := deg_to_rad(LEVER_DEG[0] - 14.0)
	var a1 := deg_to_rad(LEVER_DEG[2] + 14.0)
	item.draw_arc(pivot, 8.5, a0, a1, 12, TankPalette.BLACK, 5.0)
	item.draw_arc(pivot, 8.5, a0, a1, 12, TankPalette.STEEL_DARK, 3.0)
	item.draw_arc(pivot, 10.0, a0, a1, 12, TankPalette.STEEL_LIGHT, 1.0)
	for i in 3:
		var d := Vector2.from_angle(deg_to_rad(LEVER_DEG[i]))
		var notch := (pivot + d * 8.5).round()
		var col := TankPalette.AMBER if i == active else TankPalette.SOOT
		item.draw_rect(Rect2(notch - Vector2(1, 1), Vector2(2, 2)), col)
	var tip := knob_pos()
	var d := (tip - pivot).normalized()
	var n := Vector2(-d.y, d.x)
	if n.x > 0.0:
		n = -n
	item.draw_line(pivot, tip, TankPalette.BLACK, 4.0)
	item.draw_line(pivot, tip, TankPalette.STEEL_PALE, 2.0)
	item.draw_line(pivot + n * 0.5, tip + n * 0.5, TankPalette.PEARL, 1.0)
	item.draw_rect(Rect2(pivot.round() - Vector2(2, 2), Vector2(4, 4)), TankPalette.IRON)
	item.draw_rect(Rect2(pivot.round() - Vector2(2, 2), Vector2(4, 1)), TankPalette.STEEL)
	item.draw_rect(Rect2(pivot.round() - Vector2(1, 1), Vector2(1, 1)), TankPalette.STEEL_PALE)
	var k := tip.round()
	item.draw_circle(k, 3.0, TankPalette.BLACK)
	item.draw_circle(k, 2.2, KNOB if active >= 0 else KNOB.darkened(0.45))
	item.draw_rect(Rect2(k - Vector2(1, 1), Vector2(1, 1)), TankPalette.GLOW_WARM)


## One output gear at `c` turned by `ang`: a solid toothed wheel (GEAR_TEETH square teeth on a
## round body, a dark web ring and a hub with a keyway that shows it turning). The engaged gear is
## lit steel with a warm rim on the side facing the diesel and a lit hub; idle gears are dark iron.
## No rays, no starburst: the teeth are part of the silhouette.
func _gear(item: Node2D, c: Vector2, ang: float, on: bool) -> void:
	var body := TankPalette.STEEL if on else TankPalette.IRON
	var edge := TankPalette.STEEL_PALE if on else TankPalette.STEEL_DARK
	var outline := PackedVector2Array()
	var n := GEAR_TEETH * 4
	for k in n:
		var a := ang + TAU * float(k) / float(n)
		var tooth := (k % 4) < 2
		outline.append(c + Vector2.from_angle(a) * (GEAR_R + (TOOTH_PX if tooth else 0.0)))
	var rim := outline.duplicate()
	rim.append(outline[0])
	item.draw_colored_polygon(outline, body)
	item.draw_polyline(rim, TankPalette.BLACK, 1.0)
	item.draw_arc(c, GEAR_R - 0.5, PI * 1.05, PI * 1.6, 8, edge, 1.0)
	item.draw_arc(c, GEAR_R - 2.0, 0.0, TAU, 16, TankPalette.COAL, 1.0)
	if on:
		item.draw_arc(
			c,
			GEAR_R + 0.5,
			PI * 0.65,
			PI * 1.35,
			10,
			TankPalette.with_alpha(TankPalette.FIRE, 0.8),
			1.0
		)
	item.draw_circle(c, 2.0, TankPalette.STEEL if on else TankPalette.IRON)
	var key := Vector2.from_angle(ang)
	item.draw_line(c, c + key * 2.0, TankPalette.BLACK, 1.0)
	if on:
		item.draw_rect(Rect2(c.round() + Vector2(-1, -1), Vector2(1, 1)), TankPalette.GLOW_WARM)


## The engaged gear glows warm (on top of the diesel's cylinder light).
func engine_lights() -> void:
	super.engine_lights()
	var active := active_output()
	if active < 0 or active >= outputs.size():
		return
	var at := hub.to_layer(rect.position + outputs[active])
	hub.lights.add(at, 14.0, TankPalette.AMBER, 0.35 + 0.25 * clampf(glow, 0.0, 1.0))
