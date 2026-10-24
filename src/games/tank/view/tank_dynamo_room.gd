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
## The bus bar's copper (dull, lit edge).
const COPPER := Color("#a8714a")
const COPPER_DARK := Color("#5a3a2e")

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
	# The rotor is drawn crisp in code (paint_machinery_front) from this part's angle: the generated
	# 20 px armature read as a blurry blob under its own glow.
	armature.self_modulate = Color(1, 1, 1, 0)
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


## The rider's lamp lights only its own corner: the room's colour is the arc's cold blue-white.
func lamp_reach() -> float:
	return 0.32


## The armature's arc lights the dynamo room.
func light_source() -> Vector2:
	return armature_pos


## How strongly the brushes arc this frame, 0 .. 1.3 (0 without power or stalled).
func arc_power() -> float:
	return 0.0 if input.unpowered or stalled() else clampf(input.frac, 0.0, 1.3)


## Which brush arcs now (0 upper left, 1 upper right) and how bright, 0.3 .. 1: a cheap hash of the
## armature's turn, so the flicker follows the machine and needs no random numbers.
func arc_flicker() -> Vector2:
	var n := int(armature.revolutions() * 23.0 + lamp_phase * 7.0)
	var h := (n * 73856093) & 0x7fffffff
	return Vector2(float(h % 2), 0.3 + 0.7 * float((h >> 4) % 8) / 7.0)


## The tip of brush `i` (room coordinates): on the armature's rim, upper left or upper right.
func brush_tip(i: int) -> Vector2:
	var a := deg_to_rad(-140.0 if i == 0 else -40.0)
	var r := TankSprites.size("dynamo_armature").x * 0.5 - 0.5
	return armature_pos + Vector2(cos(a), sin(a)) * r


func engine_lights() -> void:
	var origin := hub.to_layer(rect.position)
	var arc := arc_power()
	if arc > 0.02:
		var fl := arc_flicker()
		var tip := brush_tip(int(fl.x))
		# The room's cold fill comes from above the rotor (the brushes), wide and soft, so the rotor
		# itself stays crisp and dark instead of washing out into a white blob.
		hub.lights.add(
			origin + armature_pos + Vector2(0, -12), 34.0 + 14.0 * arc, TankPalette.COLD, 0.2 * arc
		)
		# The brush arc is the room's hot cold light: a tight white-blue core on the sparking brush.
		var out := (tip - armature_pos).normalized()
		hub.lights.add(
			origin + tip + out * 2.0, 12.0 + 5.0 * arc, TankPalette.COLD_LIGHT, 0.45 * arc * fl.y
		)
		hub.lights.add(origin + tip + out, 3.5, TankPalette.WHITE_COLD, 0.6 * fl.y)
	for i in jars.size():
		var lv := jar_level(i)
		if lv > 0.05:
			var lvl_y := jars[i].end.y - jars[i].size.y * lv + 1.0
			hub.lights.add(
				origin + Vector2(jars[i].get_center().x, lvl_y), 7.0, TankPalette.COLD, 0.28 * lv
			)


## Capacitor jars as glass cylinders (brief 3: the bank): a dark cap with a terminal post, a rounded
## glass shoulder, a lit glass edge and a dark one, and inside the charge glowing a soft cold blue up
## to the bank's level with a brighter meniscus and a highlight streak, so the three read as lit
## jars of a battery and not as flat bars.
func paint_machinery_front(item: Node2D) -> void:
	_rotor(item)
	_paint_brushes(item)
	for i in jars.size():
		_jar(item, jars[i], jar_level(i), stalled())
	_wiring(item)


## The bank wired to the machine: a copper bus bar across the jars' terminal posts, a strap down to
## every post, and a heavy insulated cable sagging from the bar to the upper brush's holder on the
## armature, its copper lugs bright where it bolts on.
func _wiring(item: Node2D) -> void:
	if jars.is_empty():
		return
	var bar_y := jars[0].position.y - 5.0
	var x0 := jars[0].position.x + floorf(jars[0].size.x * 0.5) - 1.0
	var last := jars[jars.size() - 1]
	var x1 := last.position.x + floorf(last.size.x * 0.5) + 1.0
	for j in jars:
		var tx := j.position.x + floorf(j.size.x * 0.5) - 1.0
		item.draw_rect(Rect2(tx, bar_y, 2.0, 2.0), COPPER_DARK)
	item.draw_rect(Rect2(x0 - 1.0, bar_y - 1.0, x1 - x0 + 2.0, 2.0), COPPER_DARK)
	item.draw_rect(Rect2(x0 - 1.0, bar_y - 1.0, x1 - x0 + 2.0, 1.0), COPPER)
	var holder := brush_tip(1) + (brush_tip(1) - armature_pos).normalized() * 5.0
	var from := Vector2(x0 - 1.0, bar_y)
	var mid := (from + holder) * 0.5 + Vector2(0, 3)
	var cable := PackedVector2Array([from, mid.lerp(from, 0.4) + Vector2(0, 1), mid, holder])
	item.draw_polyline(cable, TankPalette.BLACK, 3.0)
	item.draw_polyline(cable, COPPER_DARK, 2.0)
	item.draw_polyline(cable, COPPER, 1.0)
	for lug: Vector2 in [from, holder]:
		item.draw_rect(Rect2(lug.round() - Vector2(1, 1), Vector2(2, 2)), COPPER)


static func _jar(item: Node2D, jar: Rect2, lv: float, dim: bool) -> void:
	var x := jar.position.x
	var y := jar.position.y
	var w := jar.size.x
	var h := jar.size.y
	# Glass body with a rounded shoulder (its top corners cut).
	item.draw_rect(Rect2(x, y + 2, w, h - 2), TankPalette.COLD_DARK)
	item.draw_rect(Rect2(x + 1, y + 1, w - 2, 1), TankPalette.COLD_DARK)
	var fill_h := roundf((h - 3.0) * lv)
	if fill_h > 0.0:
		var a := 0.22 if dim else 0.55
		var fr := Rect2(x + 1, y + h - 1 - fill_h, w - 2, fill_h)
		item.draw_rect(fr, TankPalette.with_alpha(TankPalette.COLD, a))
		item.draw_rect(
			Rect2(fr.position, Vector2(fr.size.x, 1)),
			TankPalette.with_alpha(TankPalette.COLD_LIGHT, a + 0.2)
		)
		item.draw_rect(
			Rect2(x + 1, fr.position.y + 1, 1, maxf(fill_h - 2.0, 0.0)),
			TankPalette.with_alpha(TankPalette.WHITE_COLD, a * 0.45)
		)
	# Glass edges: lit on the left, dark on the right; a dark foot.
	item.draw_rect(Rect2(x, y + 2, 1, h - 3), TankPalette.with_alpha(TankPalette.SLATE, 0.9))
	item.draw_rect(Rect2(x + w - 1, y + 2, 1, h - 3), TankPalette.COAL)
	item.draw_rect(Rect2(x, y + h - 1, w, 1), TankPalette.IRON_DARK)
	# The cap and its terminal.
	item.draw_rect(Rect2(x, y - 1, w, 2), TankPalette.IRON)
	item.draw_rect(Rect2(x, y - 1, w, 1), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(x + floorf(w * 0.5) - 1, y - 3, 2, 2), TankPalette.STEEL)


## The armature as a crisp rotor on the tank's plane (round 5 critic: a grey blob): a black rim, a
## laminated iron core carrying eight copper winding coils (a dull bar with a lit edge each, dark
## slots between them) turning with the machine, then a steel commutator ring whose six bright bars
## turn with it, and a steel shaft end. Copper on dark iron makes the rotation read at a glance; a
## cold catch-light runs round the rim under the brushes while it arcs.
func _rotor(item: Node2D) -> void:
	var c := armature_pos
	var ang := armature.angle()
	var r := TankSprites.size("dynamo_armature").x * 0.5 - 1.5
	item.draw_circle(c, r + 0.5, TankPalette.BLACK)
	item.draw_circle(c, r - 0.5, TankPalette.IRON_DARK)
	for k in 8:
		var a := ang + TAU * float(k) / 8.0
		var d := Vector2.from_angle(a)
		var side := Vector2.from_angle(a + PI * 0.5)
		item.draw_line(c + d * 3.5, c + d * (r - 1.0), COPPER_DARK, 2.0)
		item.draw_line(c + d * 3.5 - side * 0.5, c + d * (r - 1.0) - side * 0.5, COPPER, 1.0)
		var slot := Vector2.from_angle(a + TAU / 16.0)
		item.draw_line(c + slot * 3.5, c + slot * (r - 0.5), TankPalette.BLACK, 1.0)
	item.draw_arc(c, r - 0.5, 0.0, TAU, 20, TankPalette.STEEL_DARK, 1.0)
	item.draw_circle(c, 3.2, TankPalette.BLACK)
	item.draw_circle(c, 2.6, TankPalette.STEEL_DARK)
	for k in 6:
		var d := Vector2.from_angle(ang * 1.0 + TAU * float(k) / 6.0 + 0.3)
		item.draw_line(c + d * 1.2, c + d * 2.8, TankPalette.SILVER, 1.0)
	item.draw_rect(Rect2(c.round() - Vector2(1, 1), Vector2(2, 2)), TankPalette.STEEL_LIGHT)
	var arc := arc_power()
	if arc > 0.02:
		item.draw_arc(
			c,
			r,
			deg_to_rad(-150.0),
			deg_to_rad(-30.0),
			10,
			TankPalette.with_alpha(TankPalette.COLD_LIGHT, clampf(0.4 + 0.4 * arc, 0.0, 0.85)),
			1.0
		)


## The brush gear: two dark brush arms bearing on the armature's rim, and a flickering 1-3 px arc
## from one brush to the armature while the dynamo is powered (the room's main cold light).
func _paint_brushes(item: Node2D) -> void:
	for i in 2:
		var tip := brush_tip(i)
		var out := (tip - armature_pos).normalized()
		var root := tip + out * 5.0
		item.draw_line(root, tip + out * 1.0, TankPalette.IRON_DARK, 2.0)
		item.draw_line(
			root + Vector2(0, -1), tip + out * 1.0 + Vector2(0, -1), TankPalette.STEEL_DARK, 1.0
		)
		item.draw_rect(Rect2(root - Vector2(1.5, 1.5), Vector2(3, 3)), TankPalette.IRON)
	var arc := arc_power()
	if arc <= 0.02:
		return
	var fl := arc_flicker()
	var tip := brush_tip(int(fl.x))
	var inward := (armature_pos - tip).normalized()
	var side := Vector2(-inward.y, inward.x)
	var len_px := 1.0 + 2.0 * fl.y
	var mid := tip + inward * len_px * 0.5 + side * (1.0 if fl.y > 0.6 else -1.0)
	var pts := PackedVector2Array([tip, mid, tip + inward * len_px])
	var a := clampf(0.5 + 0.5 * arc, 0.0, 1.0) * fl.y
	item.draw_polyline(pts, TankPalette.with_alpha(TankPalette.COLD_LIGHT, a), 1.0)
	item.draw_rect(
		Rect2(tip.round() - Vector2(1, 1), Vector2(1, 1)),
		TankPalette.with_alpha(TankPalette.WHITE_COLD, a)
	)
