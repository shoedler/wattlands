class_name TankSteamRoom
extends TankRoomView
## The steam engine's room (brief 3 "Cutaway"): a boiler with a pressure gauge on its boss (zones at
## 40 / 100 / 150%), a firebox whose wide fire follows watts, the engine itself (a horizontal
## cylinder, piston rod, crosshead on its guides, connecting rod and a small flywheel turning once
## per pedal stroke, a steam puff from its drain cock and the deck vent on every stroke), a flyball
## regulator on the engine and a rack of brass shells. The shell cradle climbs the hoist rail with
## pressure to reach the main gun's breech at 100% (the rig draws the rail and the cradle).

const GAUGE_START_DEG := 135.0
const GAUGE_SWEEP_DEG := 270.0
const GAUGE_MAX_PCT := 150.0
const GAUGE_MARKS: Array[float] = [40.0, 100.0, 150.0]
const GAUGE_RADIUS := 6.5
## The gauge's ticks: every 37.5% of its 0 .. 150% sweep (five, the open quarter at the bottom).
const GAUGE_TICK_PCT := 37.5
## The cradle climbs / falls this fast (rail lengths per second).
const CRADLE_UP_PER_S := 0.7
const CRADLE_DOWN_PER_S := 1.6
## The regulator's spindle height (art px).
const GOV_H := 14.0
## The engine: cylinder size, flywheel radius, crank throw and connecting rod (art px).
const CYL_SIZE := Vector2(12, 6)
const WHEEL_R := 6.0
const CRANK_R := 2.5
const CONROD_PX := 9.0
## The gauge's dial face (pale, so the dark needle and ticks read), the fire's darkest ember, the
## brass case ramp and the projectile's steel.
const DIAL_FACE := Color("#6c7176")
const DIAL_LIT := Color("#878b8f")
const EMBER_DARK := Color("#3a1a10")
const BRASS_DARK := Color("#6b5842")
const BRASS_MID := Color("#a8864f")
const BRASS_PALE := Color("#d9b77a")
const OGIVE := Color("#565c62")

var boiler_pos: Vector2 = Vector2.ZERO
var gauge_pos: Vector2 = Vector2.ZERO
var flame: Sprite2D = null
var flyball: SlidingPart = null
var rack_pos: Vector2 = Vector2.ZERO
var rack_slots: Array[Rect2] = []
## The engine's cylinder top-left and flywheel centre (room coordinates).
var cyl_pos: Vector2 = Vector2.ZERO
var wheel_pos: Vector2 = Vector2.ZERO
## Pedal stroke phase 0 .. 1 and the strokes counted since the last take_stroke().
var stroke: float = 0.0
var pending_strokes: int = 0
## The shell cradle on the hoist rail, 0 (bottom) .. 1 (breech).
var cradle_t: float = 0.0
var loaded_was: bool = false
var latched_now: bool = false


func build() -> void:
	boiler_pos = anchor_local("boiler")
	# The gauge sits on the boiler's own gauge boss (rigs.json machinery.boiler.gauge_center).
	var gc: Array = (machinery.get("boiler", {}) as Dictionary).get("gauge_center", [20, 10])
	gauge_pos = boiler_pos + Vector2(float(gc[0]), float(gc[1]))
	rack_pos = anchor_local("shell_rack")
	cyl_pos = anchor_local("cylinder")
	wheel_pos = anchor_local("engine_flywheel")
	var rack_def: Dictionary = machinery.get("shell_rack", {})
	for s: Variant in rack_def.get("slots", []):
		var r := TankRigs.rect(s)
		rack_slots.append(Rect2(rack_pos + r.position, r.size))
	flyball = SlidingPart.new()
	flyball.name = "Flyball"
	flyball.mode = SlidingPart.Mode.RECIPROCATE
	flyball.axis = Vector2.UP
	flyball.travel_px = 2.0
	flyball.max_cps = 2.0
	flyball.auto_process = false
	flyball.position = anchor_local("flyball")
	# The regulator is drawn in code from this part's offset (paint_machinery_front): two balls on
	# arms over a vertical spindle standing on the engine (the generated sprite read as scales).
	add_child(flyball)
	var boiler := Sprite2D.new()
	boiler.name = "Boiler"
	boiler.texture = TankSprites.tex("boiler")
	boiler.centered = false
	boiler.position = boiler_pos
	# The boiler is drawn in code as a banded, riveted drum (paint_machinery_front): the generated
	# sprite washed into orange noise under the fire's light (round 5 scene critic).
	boiler.self_modulate = Color(1, 1, 1, 0)
	add_child(boiler)
	var box := Sprite2D.new()
	box.name = "Firebox"
	box.texture = TankSprites.tex("firebox")
	box.centered = false
	box.position = anchor_local("firebox")
	add_child(box)
	var fsize := TankSprites.size("firebox")
	flame = Sprite2D.new()
	flame.name = "Flame"
	flame.texture = TankSprites.tex("firebox_flame")
	flame.centered = false
	# firebox_flame is anchored bottom-centre: its origin is the middle of the flame's bottom edge.
	var fl := TankSprites.size("firebox_flame")
	flame.offset = Vector2(-fl.x * 0.5, -fl.y)
	flame.position = anchor_local("firebox") + Vector2(fsize.x * 0.5, fsize.y * 0.45)
	flame.self_modulate = Color(1.0, 0.9, 0.7, 0.9)
	# The fire is drawn in code across the open mouth (a coal bed and short tongues); this part
	# only carries the flame's size by watts (a single sprite flame read as a candle).
	flame.visible = false
	add_child(flame)


func animate(dt: float) -> void:
	var sp := input.speed()
	flyball.speed = sp
	flyball.tick(dt)
	if not input.unpowered:
		stroke += maxf(input.cadence, 0.0) / 60.0 * dt
		while stroke >= 1.0:
			stroke -= 1.0
			pending_strokes += 1
	var power := 0.0 if input.unpowered else clampf(input.frac, 0.0, 1.4)
	var flick := 0.88 + 0.12 * sin(lamp_phase * TAU * 4.0 + stroke * 11.0)
	flame.scale = Vector2(0.8 + 0.25 * power, (0.35 + 0.95 * power) * flick)
	flame.self_modulate.a = clampf(0.25 + 0.75 * power, 0.0, 1.0)
	_cradle(dt)


func _cradle(dt: float) -> void:
	var s := station as TankSteamState
	var target := 0.0
	if s != null:
		if s.loaded:
			target = 1.0
		elif s.cycling:
			target = 0.0
		else:
			target = clampf(s.pressure_pct / 100.0, 0.0, 1.0)
	latched_now = s != null and s.loaded and not loaded_was
	loaded_was = s != null and s.loaded
	var rate := CRADLE_UP_PER_S if target > cradle_t else CRADLE_DOWN_PER_S
	cradle_t = move_toward(cradle_t, target, rate * dt)


## True once per pedal stroke (the rig emits a steam puff for each).
func take_stroke() -> bool:
	if pending_strokes <= 0:
		return false
	pending_strokes = 0
	return true


## The chimney top in the hull frame (steam puffs rise from here).
func chimney_hull() -> Vector2:
	var cm: Array = (machinery.get("boiler", {}) as Dictionary).get("chimney", [30, 0])
	return rect.position + boiler_pos + Vector2(float(cm[0]), float(cm[1]))


func pressure_pct() -> float:
	var s := station as TankSteamState
	return s.pressure_pct if s != null else 0.0


## The gauge needle angle in radians for `pct` (0 .. 150).
static func gauge_angle(pct: float) -> float:
	return deg_to_rad(GAUGE_START_DEG + GAUGE_SWEEP_DEG * clampf(pct / GAUGE_MAX_PCT, 0.0, 1.0))


## The rider's lamp washes only part of the room, so the fire's own light keeps the gauge, boiler
## and engine readable (a full wash in a yellow rider's colour turned the dial into a pale disc).
func lamp_reach() -> float:
	return 0.6


## The open firebox lights the steam room.
func light_source() -> Vector2:
	return mouth_rect().get_center()


func engine_lights() -> void:
	var origin := hub.to_layer(rect.position)
	var power := 0.0 if input.unpowered else clampf(input.frac, 0.0, 1.4)
	if power > 0.02:
		var fb := origin + mouth_rect().get_center()
		hub.lights.add(fb, 34.0 + 26.0 * power, TankPalette.FIRE, 0.3 + 0.35 * power)
		hub.lights.add(fb, 10.0, TankPalette.GLOW_WARM, 0.4 * power)


func paint_machinery_front(item: Node2D) -> void:
	var power := 0.0 if input.unpowered else clampf(input.frac, 0.0, 1.4)
	_boiler(item, power)
	_firebox_mouth(item, power)
	_gauge(item)
	_engine(item, power)
	_governor(item)
	_rack(item)
	for r in rack_slots:
		_shell(item, r, power)


## The pressure gauge on the boiler's gauge boss (round 5 critic: it read as a face, then as a
## clock): a dark brass bezel with a lit upper arc on a short siphon stem, a grey dial face, five
## dark ticks on its 270 degree scale (open at the bottom, as a pressure gauge is), the red zone from
## 100% to 150% as a 2 px arc at the edge, and one long dark needle from the centre over a small
## brass hub. Nothing else crosses the face.
func _gauge(item: Node2D) -> void:
	var c := gauge_pos
	var r := GAUGE_RADIUS
	item.draw_rect(Rect2(c.x - 1.0, c.y + r, 3.0, 3.0), TankPalette.IRON_DARK)
	item.draw_rect(Rect2(c.x - 1.0, c.y + r, 1.0, 3.0), BRASS_DARK)
	item.draw_circle(c, r + 1.5, TankPalette.BLACK)
	item.draw_circle(c, r + 0.5, BRASS_DARK)
	item.draw_arc(c, r + 0.5, PI * 1.05, PI * 1.6, 8, BRASS_MID, 1.0)
	item.draw_circle(c, r - 0.5, DIAL_FACE)
	item.draw_arc(c, r - 1.5, PI * 1.1, PI * 1.45, 6, DIAL_LIT, 1.0)
	item.draw_arc(
		c,
		r - 1.0,
		gauge_angle(GAUGE_MARKS[1]),
		gauge_angle(GAUGE_MARKS[2]),
		8,
		TankPalette.FIRE,
		2.0
	)
	var pct_t := 0.0
	while pct_t <= GAUGE_MAX_PCT + 0.1:
		var d := Vector2.from_angle(gauge_angle(pct_t))
		item.draw_line(c + d * (r - 2.5), c + d * (r - 0.5), TankPalette.BLACK, 1.0)
		pct_t += GAUGE_TICK_PCT
	var s := station as TankSteamState
	var pct := s.pressure_pct if s != null else 0.0
	var nd := Vector2.from_angle(gauge_angle(pct))
	item.draw_line(c, c + nd * (r - 1.0), TankPalette.BLACK, 1.0)
	item.draw_circle(c, 1.2, TankPalette.BLACK)
	item.draw_rect(Rect2(c.round() - Vector2(1, 1), Vector2(1, 1)), TankPalette.BRASS)


## The boiler as a riveted horizontal drum on two saddles: shaded round from a lit top edge to a
## dark belly (the fire's light warming its lowest rows), dark rounded end caps, three riveted
## straps round it (clear of the gauge boss), a steam dome under the chimney and the chimney stub.
func _boiler(item: Node2D, power: float) -> void:
	var bp := boiler_pos
	var x0 := bp.x + 1.0
	var x1 := bp.x + TankSprites.size("boiler").x - 1.0
	var y0 := bp.y + 2.0
	var y1 := bp.y + 20.0
	var feet_y := bp.y + TankSprites.size("boiler").y - 2.0
	for fx: float in [x0 + 3.0, x1 - 7.0]:
		item.draw_rect(Rect2(fx, y1, 4.0, feet_y - y1), TankPalette.IRON_DARK)
		item.draw_rect(Rect2(fx, y1, 1.0, feet_y - y1), TankPalette.STEEL_DARK)
		item.draw_rect(Rect2(fx - 1.0, feet_y - 1.0, 6.0, 1.0), TankPalette.IRON)
	var ramp: Array[Color] = [
		TankPalette.STEEL_LIGHT,
		TankPalette.STEEL,
		TankPalette.STEEL_DARK,
		TankPalette.STEEL_DARK,
		TankPalette.IRON,
		TankPalette.IRON,
		TankPalette.IRON_DARK,
		TankPalette.IRON_DARK,
		TankPalette.COAL,
	]
	var rows := int(y1 - y0)
	for k in rows:
		var t := float(k) / maxf(float(rows - 1), 1.0)
		var col := ramp[mini(int(t * float(ramp.size())), ramp.size() - 1)]
		var inset := 1.0 if k == 0 or k == rows - 1 else 0.0
		item.draw_rect(Rect2(x0 + inset, y0 + float(k), x1 - x0 - inset * 2.0, 1.0), col)
	item.draw_rect(Rect2(x0 - 1.0, y0 + 1.0, 1.0, float(rows) - 2.0), TankPalette.BLACK)
	item.draw_rect(Rect2(x1, y0 + 1.0, 1.0, float(rows) - 2.0), TankPalette.BLACK)
	item.draw_rect(Rect2(x0 + 1.0, y0 - 1.0, x1 - x0 - 2.0, 1.0), TankPalette.BLACK)
	item.draw_rect(Rect2(x0 + 1.0, y1, x1 - x0 - 2.0, 1.0), TankPalette.BLACK)
	# End caps: a darker 2 px rim at each end with a lit upper corner.
	for ex: float in [x0, x1 - 2.0]:
		item.draw_rect(Rect2(ex, y0 + 1.0, 2.0, float(rows) - 2.0), TankPalette.IRON_DARK)
		item.draw_rect(Rect2(ex, y0 + 1.0, 2.0, 1.0), TankPalette.STEEL)
	# Straps with rivets, clear of the gauge boss.
	for sx: float in [x0 + 7.0, gauge_pos.x - GAUGE_RADIUS - 4.0, gauge_pos.x + GAUGE_RADIUS + 4.0]:
		item.draw_rect(Rect2(sx, y0, 1.0, float(rows)), TankPalette.COAL)
		item.draw_rect(Rect2(sx + 1.0, y0, 1.0, float(rows)), TankPalette.STEEL_DARK)
		var ry := y0 + 2.0
		while ry < y1 - 1.0:
			item.draw_rect(Rect2(sx + 1.0, ry, 1.0, 1.0), TankPalette.STEEL_PALE)
			ry += 4.0
	if power > 0.05:
		item.draw_rect(
			Rect2(x0 + 1.0, y1 - 2.0, x1 - x0 - 2.0, 2.0),
			TankPalette.with_alpha(TankPalette.FIRE, 0.3 * clampf(power, 0.0, 1.0))
		)
	# The steam dome and the chimney stub where the puffs leave.
	var cm := chimney_hull() - rect.position
	item.draw_rect(Rect2(cm.x - 1.0, cm.y, 3.0, y0 - cm.y), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(cm.x - 1.0, cm.y, 1.0, y0 - cm.y), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(cm.x - 2.0, cm.y, 5.0, 1.0), TankPalette.STEEL)
	var dx := x0 + 9.0
	item.draw_rect(Rect2(dx, y0 - 3.0, 5.0, 3.0), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(dx + 1.0, y0 - 4.0, 3.0, 1.0), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(dx, y0 - 3.0, 1.0, 3.0), TankPalette.STEEL)


## The firebox door open on a wide fire: the mouth glowing from a dark top to a hot bottom, a bed of
## coal lumps across its floor (dull red to amber by watts, flickering per lump) and short tongues
## of flame licking up from the bed, never one tall candle flame.
func _firebox_mouth(item: Node2D, power: float) -> void:
	var m := mouth_rect()
	item.draw_rect(m.grow(1.0), TankPalette.BLACK)
	var rows := int(m.size.y)
	for k in rows:
		var t := float(k) / maxf(float(rows - 1), 1.0)
		var col := EMBER_DARK.lerp(TankPalette.FIRE, t * t)
		var a := clampf(0.15 + power * (0.25 + 0.6 * t * t), 0.0, 1.0)
		item.draw_rect(
			Rect2(m.position.x, m.position.y + float(k), m.size.x, 1.0),
			TankPalette.with_alpha(col, a)
		)
	var bed_y := m.end.y - 2.0
	var tick := int(lamp_phase * 6.0 + stroke * 5.0)
	for i in int(m.size.x):
		var x := m.position.x + float(i)
		var h := _hash(i, tick)
		var lump := 1.0 + float(int(_hash(i, 99) * 2.0))
		var heat := clampf(power * (0.55 + 0.45 * h), 0.0, 1.0)
		var col := EMBER_DARK.lerp(TankPalette.FIRE, heat).lerp(TankPalette.AMBER, heat * heat)
		item.draw_rect(Rect2(x, bed_y + 2.0 - lump, 1.0, lump), col)
		if h > 0.8 and power > 0.3:
			item.draw_rect(Rect2(x, bed_y + 1.0, 1.0, 1.0), TankPalette.GLOW_WARM)
	if power <= 0.05:
		return
	# Tongues of flame across the bed (their height follows the flame part's scale, set by watts).
	var tall := flame.scale.y * 5.0
	var spots: Array[float] = [1.5, 4.0, 7.5, 9.5, 12.0]
	for k in spots.size():
		var x := m.position.x + roundf(minf(spots[k], m.size.x - 1.5))
		var fl := 0.35 + 0.65 * _hash(k + 7, tick)
		var ht := roundf(clampf(tall * fl, 1.0, m.size.y - 2.0))
		var lean := 1.0 if _hash(k + 3, tick) > 0.5 else 0.0
		var flame_pts := PackedVector2Array(
			[
				Vector2(x - 1.0, bed_y),
				Vector2(x + 2.0, bed_y),
				Vector2(x + 0.5 + lean, bed_y - ht),
			]
		)
		item.draw_colored_polygon(flame_pts, TankPalette.with_alpha(TankPalette.FIRE, 0.9))
		item.draw_line(
			Vector2(x + 0.5, bed_y),
			Vector2(x + 0.5 + lean * 0.5, bed_y - ht * 0.6),
			TankPalette.AMBER,
			1.0
		)
		item.draw_rect(Rect2(x, bed_y - 1.0, 1.0, 1.0), TankPalette.GLOW_WARM)


## The firebox's open mouth (room coordinates): a wide low opening across the door frame.
func mouth_rect() -> Rect2:
	var p := anchor_local("firebox")
	var sz := TankSprites.size("firebox")
	return Rect2(p.x + 3.0, p.y + roundf(sz.y * 0.3), sz.x - 6.0, roundf(sz.y * 0.45))


## The steam engine (the room's identity): a horizontal cylinder on the boiler with a valve chest
## and flanges, its piston rod driving a crosshead along two guide bars, a connecting rod to the
## crank pin of a small flywheel turning once per pedal stroke, and the drain cock under the
## cylinder's front end (the rig puffs steam there on every stroke).
func _engine(item: Node2D, power: float) -> void:
	var cy := cyl_pos
	var size := CYL_SIZE
	var mid := cy.y + size.y * 0.5
	# Valve chest and the stub pipe from the boiler.
	item.draw_rect(Rect2(cy.x - 3.0, cy.y - 2.0, 4.0, 2.0), TankPalette.IRON)
	item.draw_rect(Rect2(cy.x - 3.0, cy.y - 2.0, 4.0, 1.0), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(cy.x + 2.0, cy.y - 3.0, 8.0, 3.0), TankPalette.IRON)
	item.draw_rect(Rect2(cy.x + 2.0, cy.y - 3.0, 8.0, 1.0), TankPalette.STEEL_LIGHT)
	# The cylinder: a shaded drum with flanged ends and bolt heads.
	item.draw_rect(Rect2(cy, size), TankPalette.IRON)
	item.draw_rect(Rect2(cy.x, cy.y, size.x, 1.0), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(cy.x, cy.y + 1.0, size.x, 1.0), TankPalette.STEEL)
	item.draw_rect(Rect2(cy.x, cy.y + size.y - 1.0, size.x, 1.0), TankPalette.COAL)
	for fx: float in [cy.x, cy.x + size.x - 2.0]:
		item.draw_rect(Rect2(fx, cy.y - 1.0, 2.0, size.y + 2.0), TankPalette.STEEL_DARK)
		item.draw_rect(Rect2(fx, cy.y - 1.0, 2.0, 1.0), TankPalette.STEEL_PALE)
		item.draw_rect(Rect2(fx, cy.y + size.y, 2.0, 1.0), TankPalette.BLACK)
	# Lagging bands.
	for bx: float in [cy.x + 5.0, cy.x + 8.0]:
		item.draw_rect(Rect2(bx, cy.y, 1.0, size.y), TankPalette.IRON_DARK)
	var drain := drain_pos()
	item.draw_rect(Rect2(drain.x, drain.y - 1.0, 1.0, 2.0), TankPalette.STEEL)
	# The firebox's warm light catching the cylinder's lower edge.
	if power > 0.05:
		item.draw_rect(
			Rect2(cy.x, cy.y + size.y - 2.0, size.x, 1.0),
			TankPalette.with_alpha(TankPalette.FIRE, 0.25 * clampf(power, 0.0, 1.0))
		)
	# Guides, crosshead, rods.
	var g0 := cy.x + size.x + 1.0
	var g1 := wheel_pos.x - 4.0
	item.draw_rect(Rect2(g0, mid - 3.0, g1 - g0, 1.0), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(g0, mid + 2.0, g1 - g0, 1.0), TankPalette.STEEL_DARK)
	var pin := crank_pin()
	var xh := crosshead_x()
	item.draw_line(Vector2(cy.x + size.x, mid), Vector2(xh, mid), TankPalette.STEEL_PALE, 1.0)
	_flywheel(item, power)
	item.draw_line(Vector2(xh, mid), pin, TankPalette.STEEL, 2.0)
	item.draw_line(Vector2(xh, mid - 1.0), pin + Vector2(0, -1), TankPalette.STEEL_BRIGHT, 1.0)
	item.draw_rect(Rect2(xh - 1.5, mid - 2.0, 3.0, 4.0), TankPalette.STEEL_LIGHT)
	item.draw_rect(Rect2(xh - 1.5, mid - 2.0, 3.0, 1.0), TankPalette.SILVER)
	item.draw_circle(pin, 1.2, TankPalette.SILVER)


## The engine's small flywheel: a dark disc with a lit rim, four spokes turning with the crank and a
## steel hub; the fire's light catches its left side.
func _flywheel(item: Node2D, power: float) -> void:
	var c := wheel_pos
	var ang := crank_angle()
	item.draw_circle(c, WHEEL_R + 0.5, TankPalette.BLACK)
	item.draw_circle(c, WHEEL_R - 0.5, TankPalette.IRON)
	item.draw_arc(c, WHEEL_R - 1.0, PI * 1.1, PI * 1.85, 10, TankPalette.STEEL_LIGHT, 1.0)
	item.draw_circle(c, WHEEL_R - 2.0, TankPalette.COAL)
	for k in 4:
		var d := Vector2.from_angle(ang + TAU * float(k) / 4.0 + PI / 4.0)
		item.draw_line(c, c + d * (WHEEL_R - 1.5), TankPalette.IRON, 1.0)
	item.draw_circle(c, 1.8, TankPalette.STEEL)
	if power > 0.05:
		item.draw_arc(
			c,
			WHEEL_R - 0.5,
			PI * 0.6,
			PI * 1.3,
			10,
			TankPalette.with_alpha(TankPalette.FIRE, 0.25 + 0.3 * clampf(power, 0.0, 1.0)),
			1.0
		)


## The crank angle (radians): one turn per pedal stroke.
func crank_angle() -> float:
	return TAU * stroke


## The crank pin on the engine's flywheel (room coordinates).
func crank_pin() -> Vector2:
	return wheel_pos + Vector2.from_angle(crank_angle()) * CRANK_R


## The crosshead's x on its guides for the current crank angle (a connecting rod of CONROD_PX).
func crosshead_x() -> float:
	var pin := crank_pin()
	var mid := cyl_pos.y + CYL_SIZE.y * 0.5
	var dy := pin.y - mid
	return pin.x - sqrt(maxf(CONROD_PX * CONROD_PX - dy * dy, 0.0))


## The cylinder's drain cock (room coordinates): under its front end.
func drain_pos() -> Vector2:
	return cyl_pos + Vector2(CYL_SIZE.x - 3.0, CYL_SIZE.y + 1.0)


## The drain cock in the hull frame (the rig puffs steam here every stroke).
func drain_hull() -> Vector2:
	return rect.position + drain_pos()


## The flyball regulator standing on the engine's valve chest: a vertical spindle on a base plate, a
## cap, two arms hinged at the top whose balls swing out with the engine's
## speed and bob with the stroke, and a collar the lower links pull up the spindle. No crossbar.
func _governor(item: Node2D) -> void:
	var top := flyball.position
	var bob := flyball.offset()
	var spread := deg_to_rad(22.0 + 34.0 * clampf(input.speed(), 0.0, 1.0))
	var base_y := top.y + GOV_H
	item.draw_rect(Rect2(top.x - 3, base_y, 7, 2), TankPalette.IRON)
	item.draw_rect(Rect2(top.x - 3, base_y, 7, 1), TankPalette.STEEL_DARK)
	item.draw_line(top, Vector2(top.x, base_y), TankPalette.STEEL_DARK, 1.0)
	item.draw_rect(Rect2(top.x, top.y - 2, 1, 2), TankPalette.STEEL)
	var arm := 7.0
	var hinge := top + Vector2(0, 1)
	var collar_y := hinge.y + cos(spread) * arm * 1.4 - bob
	for side: float in [-1.0, 1.0]:
		var ball := hinge + Vector2(side * sin(spread), cos(spread)) * arm + Vector2(0, -bob * 0.5)
		item.draw_line(hinge, ball, TankPalette.STEEL_DARK, 1.0)
		item.draw_line(ball, Vector2(top.x, collar_y), TankPalette.IRON_DARK, 1.0)
		item.draw_circle(ball, 2.3, TankPalette.STEEL)
		item.draw_circle(ball + Vector2(0.4, 0.4), 1.4, TankPalette.STEEL_DARK)
		item.draw_rect(
			Rect2(ball.round() + Vector2(-1, -2), Vector2(1, 1)), TankPalette.STEEL_BRIGHT
		)
	item.draw_rect(Rect2(top.x - 1, collar_y - 1, 3, 2), TankPalette.STEEL)


## The shell rack: two dark posts, a base shelf and a steel retaining bar across the shells.
func _rack(item: Node2D) -> void:
	if rack_slots.is_empty():
		return
	var r := rack_slots[0]
	for s in rack_slots:
		r = r.merge(s)
	r = r.grow_individual(1.0, 0.0, 1.0, 2.0)
	for x: float in [r.position.x - 1.0, r.end.x]:
		item.draw_rect(Rect2(x, r.position.y + 3.0, 1, r.size.y - 3.0), TankPalette.IRON)
	item.draw_rect(Rect2(r.position.x - 1.0, r.end.y - 2.0, r.size.x + 2.0, 2), TankPalette.IRON)
	item.draw_rect(
		Rect2(r.position.x - 1.0, r.end.y - 2.0, r.size.x + 2.0, 1), TankPalette.STEEL_DARK
	)


## A shell standing in the rack: a brass case shaded round (dark brass at its right edge to a pale
## highlight column at its left third, glinting brighter when the fire flares), a copper driving
## band, then a darker steel projectile tapering to a rounded ogive nose with a lit flank; a steel
## retaining bar crosses the case. 1 px gaps between shells.
func _shell(item: Node2D, r: Rect2, power: float) -> void:
	var x := r.position.x
	var w := r.size.x
	var proj_h := roundf(r.size.y * 0.32)
	var case_top := r.position.y + proj_h
	var case_h := r.end.y - case_top
	var glint := clampf(power, 0.0, 1.2)
	var cols: Array[Color] = [BRASS_DARK, BRASS_MID, BRASS_PALE, BRASS_MID, BRASS_DARK]
	for i in int(w):
		var k := int(float(i) / maxf(w, 1.0) * float(cols.size()))
		var col := cols[mini(k, cols.size() - 1)]
		if col == BRASS_PALE:
			col = col.lerp(TankPalette.GLOW_WARM, 0.35 * glint)
		item.draw_rect(Rect2(x + float(i), case_top, 1.0, case_h), col)
	item.draw_rect(Rect2(x, r.end.y - 1.0, w, 1.0), BRASS_DARK.darkened(0.3))
	item.draw_rect(Rect2(x, case_top, w, 1.0), TankPalette.RUST)
	# The projectile and its ogive.
	var ptop := r.position.y
	var body := Rect2(x, ptop + 3.0, w, proj_h - 3.0)
	item.draw_rect(body, OGIVE)
	var nose := PackedVector2Array(
		[
			Vector2(x, ptop + 3.0),
			Vector2(x + w * 0.2, ptop + 1.0),
			Vector2(x + w * 0.5, ptop),
			Vector2(x + w * 0.8, ptop + 1.0),
			Vector2(x + w, ptop + 3.0),
		]
	)
	item.draw_colored_polygon(nose, OGIVE)
	item.draw_rect(Rect2(x + 1.0, ptop + 1.0, 1.0, proj_h - 1.0), OGIVE.lightened(0.35))
	item.draw_rect(Rect2(x + w - 1.0, ptop + 3.0, 1.0, proj_h - 3.0), OGIVE.darkened(0.4))
	# The retaining bar across the cases.
	var bar_y := case_top + roundf(case_h * 0.45)
	item.draw_rect(Rect2(x - 1.0, bar_y, w + 2.0, 2.0), TankPalette.IRON_DARK)
	item.draw_rect(Rect2(x - 1.0, bar_y, w + 2.0, 1.0), TankPalette.STEEL)


## A 0 .. 1 hash of two integers (no random numbers in the view's drawing).
static func _hash(a: int, b: int) -> float:
	var n := (a * 374761393 + b * 668265263) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	return float((n ^ (n >> 16)) & 0xFFFF) / 65536.0
