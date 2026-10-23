class_name TankDynamoRoom
extends TankRoomView
## The dynamo's room (brief 3 "Cutaway"): a housing around a spinning armature that throws cold blue
## sparks by watts, and three capacitor jars that show the bank (the first jar fills first). A shaft
## from the armature to the turret ring turns while the turret slews (the rig draws it). The
## armature's light is the cold arc: blue-white, the only cold source inside the tank.

const BANK_MAX := 100.0

var armature: SpinningPart = null
var jars: Array[Rect2] = []
var armature_pos: Vector2 = Vector2.ZERO


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
			origin + armature_pos, 14.0 + 12.0 * arc, TankPalette.COLD_LIGHT, 0.45 * arc * flicker
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


func paint_machinery_front(item: Node2D) -> void:
	for i in jars.size():
		var jar := jars[i]
		item.draw_rect(
			jar,
			Color(TankPalette.COLD_DARK.r, TankPalette.COLD_DARK.g, TankPalette.COLD_DARK.b, 0.55)
		)
		var lv := jar_level(i)
		var h := roundf(jar.size.y * lv)
		if h > 0.0:
			var fill := Rect2(jar.position.x, jar.end.y - h, jar.size.x, h)
			item.draw_rect(
				fill,
				TankPalette.darkened(TankPalette.COLD, 0.35) if stalled() else TankPalette.COLD
			)
			item.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)), TankPalette.WHITE_COLD)
		item.draw_rect(jar, TankPalette.STEEL_LIGHT, false, 1.0)
		item.draw_rect(
			Rect2(jar.position.x - 1, jar.position.y - 2, jar.size.x + 2, 2),
			TankPalette.STEEL_BRIGHT
		)
