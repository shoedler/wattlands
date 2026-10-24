class_name TankBulwarkRoom
extends TankDieselRoom
## The Bulwark's one room (brief 3 "Cutaway"): the diesel machinery plus the three-way gearbox, laid
## out block | flywheel | gearbox so the three read apart. The gearbox is a dark casing behind three
## large output gears drawn in code, well apart, their teeth on the diesel's side catching its amber
## light; only the active output spins and its teeth and hub are lit, the idle ones stay dark. A
## steel lever with a small lit tip points at its position (Drive, Turret or Hoist; Drive is "Dig" at
## a gun line) and moves across during a one-second shift. The hoist's progress toward the next heavy
## shell is the cradle climbing the hoist rail to the breech (the rig draws it from hoist_fill()).

## The output gears: radius, teeth.
const GEAR_R := 6.5
const GEAR_TEETH := 9

const OUTPUT_KEYS: Array[String] = ["drive", "turret", "hoist"]
## The kilojoules a heavy shell needs (content: tanks.json gearbox.hoist_j; the card shows it too).
const DEFAULT_HOIST_J := 4000.0

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


## The lever: a riveted pivot plate with three detent notches (one toward each output, the engaged
## one lit amber), a 2 px rod with a lit top edge from the pivot to the output it points at, and a
## knob with a lit pixel at its tip.
func _lever(item: Node2D, active: int) -> void:
	# The drawn rod stops short of the output it points at, so its knob stands clear of the gear.
	var full := lever_tip() - pivot
	var tip := pivot + full.normalized() * clampf(full.length() - 3.0, 6.0, 11.0)
	item.draw_circle(pivot, 4.5, TankPalette.BLACK)
	item.draw_arc(pivot, 4.0, 0.0, TAU, 16, TankPalette.STEEL_DARK, 1.0)
	for i in outputs.size():
		var dir := (outputs[i] - pivot).normalized()
		var notch := (pivot + dir * 4.0).round()
		var col := TankPalette.AMBER if i == active else TankPalette.STEEL_DARK
		item.draw_rect(Rect2(notch - Vector2(0.5, 0.5), Vector2(1, 1)), col)
	var d := tip - pivot
	var n := Vector2(-d.y, d.x).normalized()
	if n.y > 0.0:
		n = -n
	item.draw_line(pivot, tip, TankPalette.STEEL, 2.0)
	item.draw_line(pivot + n, tip + n, TankPalette.STEEL_BRIGHT, 1.0)
	item.draw_rect(Rect2(pivot.round() - Vector2(1, 1), Vector2(3, 3)), TankPalette.STEEL)
	item.draw_rect(Rect2(pivot.round(), Vector2(1, 1)), TankPalette.COAL)
	var k := tip.round()
	item.draw_rect(Rect2(k - Vector2(2, 2), Vector2(4, 4)), TankPalette.BLACK)
	item.draw_rect(Rect2(k - Vector2(1, 1), Vector2(3, 3)), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(k - Vector2(1, 1), Vector2(2, 1)), TankPalette.SILVER)
	if active >= 0:
		item.draw_rect(Rect2(k, Vector2(1, 1)), TankPalette.AMBER)


## One output gear at `c` turned by `ang`. Only the engaged gear is lit: a warm rim, amber teeth and
## a lit hub; the idle ones stay dark iron with no amber anywhere, so the active output reads at once.
func _gear(item: Node2D, c: Vector2, ang: float, on: bool) -> void:
	var body := TankPalette.STEEL_DARK if on else TankPalette.IRON_DARK
	var tooth := TankPalette.AMBER if on else TankPalette.IRON
	item.draw_circle(c, GEAR_R + 1.5, TankPalette.BLACK)
	item.draw_circle(c, GEAR_R - 0.5, body)
	for k in GEAR_TEETH:
		var d := Vector2.from_angle(ang + TAU * float(k) / float(GEAR_TEETH))
		item.draw_line(c + d * (GEAR_R - 1.0), c + d * (GEAR_R + 1.5), tooth, 2.0)
	if on:
		item.draw_arc(c, GEAR_R - 0.5, PI * 0.7, PI * 1.5, 10, TankPalette.FIRE, 1.0)
	item.draw_arc(c, GEAR_R - 2.0, 0.0, TAU, 16, TankPalette.COAL, 1.0)
	item.draw_circle(c, 2.0, TankPalette.STEEL if on else TankPalette.IRON)
	var spoke := Vector2.from_angle(ang) * 3.5
	item.draw_line(c - spoke, c + spoke, TankPalette.COAL, 1.0)
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
