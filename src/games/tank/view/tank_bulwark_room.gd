class_name TankBulwarkRoom
extends TankDieselRoom
## The Bulwark's one room (brief 3 "Cutaway"): the diesel machinery plus the three-way gearbox. A
## lever points at its position (Drive, Turret or Hoist; Drive is "Dig" at a gun line) and moves
## across during a one-second shift; only the active output shaft spins, and a hoist bar shows the
## kilojoules lifted toward the next heavy shell.

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
		var on := i == active
		item.draw_rect(
			Rect2(outputs[i] + Vector2(-1, 9), Vector2(3, 2)),
			TankPalette.AMBER if on else TankPalette.STEEL_DARK
		)
	var tip := lever_tip()
	item.draw_line(pivot, tip, TankPalette.STEEL_BRIGHT, 2.0)
	item.draw_circle(pivot, 2.5, TankPalette.STEEL_LIGHT)
	item.draw_circle(tip, 2.0, TankPalette.AMBER if active >= 0 else TankPalette.STEEL_PALE)
	if outputs.size() >= 3:
		var bar := Rect2(outputs[2] + Vector2(9, -9), Vector2(3, 18))
		item.draw_rect(bar, TankPalette.COAL)
		var h := bar.size.y * hoist_fill()
		item.draw_rect(Rect2(bar.position.x, bar.end.y - h, bar.size.x, h), TankPalette.AMBER)
		item.draw_rect(bar, TankPalette.STEEL, false, 1.0)
