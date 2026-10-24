class_name TankDynamoRoom
extends TankRoomView
## The dynamo's room (brief 3 "Cutaway"): a housing around a spinning armature that throws cold blue
## sparks by watts, and three capacitor jars that show the bank (the first jar fills first). A shaft
## from the armature to the turret ring turns while the turret slews (the rig draws it). The
## armature's light is the cold arc: blue-white, the only cold source inside the tank. In the
## Rampart (no steam engine) the dynamo also runs the hoist: the rig draws a rail and a cradle in
## the rear bay and a chain from the armature to its foot; hoist_t is the cradle on that rail.

const BANK_MAX := 100.0
## The cradle falls back down the rail this fast (rail lengths per second) once the shot is fired.
const HOIST_DOWN_PER_S := 1.5
const HOIST_UP_PER_S := 1.0

var armature: SpinningPart = null
var jars: Array[Rect2] = []
var armature_pos: Vector2 = Vector2.ZERO
## The Rampart's hoist (set by the rig): the cradle on the rail, 0 (foot) .. 1 (breech), and whether
## a shell sits in the breech. The hoist's length is the largest hoist_s seen at its start.
var has_hoist: bool = false
var hoist_t: float = 0.0
var breech_loaded: bool = false
var _hoist_total: float = 0.001
var _hoist_prev: float = 0.0


func build() -> void:
	var housing := Sprite2D.new()
	housing.name = "Housing"
	housing.texture = TankSprites.tex("dynamo_housing")
	housing.centered = false
	housing.position = anchor_local("dynamo_housing")
	add_child(housing)
	armature_pos = anchor_local("armature")
	armature = SpinningPart.new()
	armature.name = "Armature"
	armature.texture = TankSprites.tex("dynamo_armature")
	armature.position = armature_pos
	armature.max_rpm = 240.0
	armature.inertia_s = 0.25
	armature.snap_steps = 16
	armature.auto_process = false
	add_child(armature)
	for j: Variant in def.get("capacitor_jars", []):
		var r := TankRigs.rect(j)
		jars.append(Rect2(local(r.position), r.size))


func animate(dt: float) -> void:
	armature.speed = input.speed()
	armature.tick(dt)
	if has_hoist:
		_hoist(dt)


func _hoist(dt: float) -> void:
	var left := hoist_s()
	if left > _hoist_prev + 1e-6:
		_hoist_total = maxf(left, 0.001)
	_hoist_prev = left
	if left > 0.0:
		hoist_t = clampf(1.0 - left / _hoist_total, 0.0, 1.0)
		return
	var target := 1.0 if breech_loaded else 0.0
	var rate := HOIST_UP_PER_S if target > hoist_t else HOIST_DOWN_PER_S
	hoist_t = move_toward(hoist_t, target, rate * dt)


## Seconds left of the hoist lifting a heavy shell (0 idle).
func hoist_s() -> float:
	var d := station as TankDynamoState
	return d.hoist_s if d != null else 0.0


## The hoist is lifting a shell now (its chain turns).
func hoisting() -> bool:
	return has_hoist and hoist_s() > 0.0 and not input.unpowered


## The bank 0 .. 100 (full before the first snapshot).
func bank() -> float:
	var d := station as TankDynamoState
	return d.bank if d != null else BANK_MAX


## How full jar `i` is, 0 .. 1: the bank fills them in order, a third each.
func jar_level(i: int) -> float:
	var per := BANK_MAX / float(maxi(jars.size(), 1))
	return clampf((bank() - float(i) * per) / per, 0.0, 1.0)


func stalled() -> bool:
	var d := station as TankDynamoState
	return d != null and d.stalled


## The armature's centre in the hull frame (the rig emits sparks there).
func armature_hull_pos() -> Vector2:
	return rect.position + armature_pos


func engine_lights() -> void:
	var origin := hub.to_layer(rect.position)
	var arc := 0.0 if input.unpowered or stalled() else clampf(input.frac, 0.0, 1.3)
	if arc > 0.02:
		var flicker := 0.8 + 0.2 * sin(lamp_phase * TAU * 3.0 + armature.revolutions() * 9.0)
		hub.lights.add(
			origin + armature_pos, 36.0 + 26.0 * arc, TankPalette.COLD_LIGHT, 0.4 * arc * flicker
		)
	for i in jars.size():
		var lv := jar_level(i)
		if lv > 0.05:
			hub.lights.add(
				origin + jars[i].position + Vector2(jars[i].size.x * 0.5, 4.0),
				8.0,
				TankPalette.COLD,
				0.3 * lv
			)


## Capacitor jars as dark glass (#2e3944) in a dull steel cage; only the charge column glows, a
## soft cold blue at about half alpha with a brighter meniscus, so the jars read as lights and not
## as saturated blue surfaces (brief 3: lights are the only near-saturated pixels).
func paint_machinery_front(item: Node2D) -> void:
	for i in jars.size():
		var jar := jars[i]
		item.draw_rect(jar, TankPalette.COLD_DARK)
		var lv := jar_level(i)
		var h := roundf(jar.size.y * lv)
		if h > 0.0:
			var fill := Rect2(jar.position.x + 1.0, jar.end.y - h, jar.size.x - 2.0, h)
			var col := TankPalette.COLD
			var a := 0.2 if stalled() else 0.5
			item.draw_rect(fill, TankPalette.with_alpha(col, a))
			item.draw_rect(
				Rect2(fill.position, Vector2(fill.size.x, 1)),
				TankPalette.with_alpha(TankPalette.COLD_LIGHT, a + 0.15)
			)
		item.draw_rect(jar, TankPalette.IRON, false, 1.0)
		item.draw_rect(
			Rect2(jar.position.x - 1, jar.position.y - 2, jar.size.x + 2, 2), TankPalette.STEEL_DARK
		)
		item.draw_rect(
			Rect2(jar.position.x - 1, jar.position.y - 2, jar.size.x + 2, 1), TankPalette.STEEL
		)
