class_name TankSteamRoom
extends TankRoomView
## The steam engine's room (brief 3 "Cutaway"): a boiler with a gauge needle (40 / 100 / 150% marks),
## a firebox whose flame follows watts, a flyball that bobs with the stroke, a puff of steam from
## the chimney on every pedal stroke, and a shell rack. The shell cradle climbs the hoist rail with
## pressure to reach the breech at 100% (the rig draws the rail and the cradle from cradle_t).

const GAUGE_START_DEG := 135.0
const GAUGE_SWEEP_DEG := 270.0
const GAUGE_MAX_PCT := 150.0
const GAUGE_MARKS: Array[float] = [40.0, 100.0, 150.0]
const GAUGE_RADIUS := 6.0
## The cradle climbs / falls this fast (rail lengths per second).
const CRADLE_UP_PER_S := 0.7
const CRADLE_DOWN_PER_S := 1.6
## The regulator's spindle height (art px).
const GOV_H := 18.0

var boiler_pos: Vector2 = Vector2.ZERO
var gauge_pos: Vector2 = Vector2.ZERO
var flame: Sprite2D = null
var flyball: SlidingPart = null
var rack_pos: Vector2 = Vector2.ZERO
var rack_slots: Array[Rect2] = []
## Pedal stroke phase 0 .. 1 and the strokes counted since the last take_stroke().
var stroke: float = 0.0
var pending_strokes: int = 0
## The shell cradle on the hoist rail, 0 (bottom) .. 1 (breech).
var cradle_t: float = 0.0
var loaded_was: bool = false
var latched_now: bool = false


func build() -> void:
	boiler_pos = anchor_local("boiler")
	gauge_pos = anchor_local("gauge")
	rack_pos = anchor_local("shell_rack")
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
	flyball.position = Vector2(3, 3)
	# The regulator is drawn in code from this part's offset (paint_machinery_front): two balls on
	# arms over a vertical spindle (the generated sprite read as a pair of scales).
	add_child(flyball)
	var boiler := Sprite2D.new()
	boiler.name = "Boiler"
	boiler.texture = TankSprites.tex("boiler")
	boiler.centered = false
	boiler.position = boiler_pos
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


## The open firebox lights the steam room.
func light_source() -> Vector2:
	return anchor_local("firebox") + TankSprites.size("firebox") * 0.5


func engine_lights() -> void:
	var origin := hub.to_layer(rect.position)
	var power := 0.0 if input.unpowered else clampf(input.frac, 0.0, 1.4)
	if power > 0.02:
		var fb := origin + anchor_local("firebox") + TankSprites.size("firebox") * 0.5
		hub.lights.add(fb, 34.0 + 26.0 * power, TankPalette.FIRE, 0.3 + 0.35 * power)
		hub.lights.add(fb, 12.0, TankPalette.GLOW_WARM, 0.45 * power)


func paint_machinery_front(item: Node2D) -> void:
	var c := gauge_pos
	item.draw_circle(c, GAUGE_RADIUS + 1.0, TankPalette.STEEL)
	item.draw_circle(c, GAUGE_RADIUS, TankPalette.COAL)
	for mark in GAUGE_MARKS:
		var a := gauge_angle(mark)
		var d := Vector2(cos(a), sin(a))
		var col := (
			TankPalette.COLD_LIGHT
			if mark < 100.0
			else (TankPalette.AMBER if mark < 150.0 else TankPalette.FIRE)
		)
		item.draw_line(c + d * (GAUGE_RADIUS - 2.5), c + d * (GAUGE_RADIUS - 0.5), col, 1.0)
	var s := station as TankSteamState
	var pct := s.pressure_pct if s != null else 0.0
	var na := gauge_angle(pct)
	var nd := Vector2(cos(na), sin(na))
	item.draw_line(
		c,
		c + nd * (GAUGE_RADIUS - 1.0),
		TankPalette.WHITE_WARM if pct <= 100.0 else TankPalette.FIRE,
		1.0
	)
	item.draw_circle(c, 1.0, TankPalette.STEEL_BRIGHT)
	_governor(item)
	_rack(item)
	for r in rack_slots:
		_shell(item, r)


## The flyball regulator: a vertical spindle on a base plate, a cap, two arms hinged at the top whose
## balls swing out with the engine's speed and bob with the stroke, and a collar the lower links
## pull up the spindle. No crossbar.
func _governor(item: Node2D) -> void:
	var top := flyball.position + Vector2(8, 2)
	var bob := flyball.offset()
	var spread := deg_to_rad(22.0 + 34.0 * clampf(input.speed(), 0.0, 1.0))
	var base_y := top.y + GOV_H
	item.draw_rect(Rect2(top.x - 3, base_y, 7, 2), TankPalette.IRON)
	item.draw_rect(Rect2(top.x - 3, base_y, 7, 1), TankPalette.STEEL_DARK)
	item.draw_line(top, Vector2(top.x, base_y), TankPalette.STEEL_DARK, 1.0)
	item.draw_rect(Rect2(top.x, top.y - 2, 1, 2), TankPalette.STEEL)
	var arm := 8.0
	var hinge := top + Vector2(0, 1)
	var collar_y := hinge.y + cos(spread) * arm * 1.4 - bob
	for side: float in [-1.0, 1.0]:
		var ball := hinge + Vector2(side * sin(spread), cos(spread)) * arm + Vector2(0, -bob * 0.5)
		item.draw_line(hinge, ball, TankPalette.STEEL_DARK, 1.0)
		item.draw_line(ball, Vector2(top.x, collar_y), TankPalette.IRON_DARK, 1.0)
		item.draw_circle(ball, 2.6, TankPalette.STEEL)
		item.draw_circle(ball + Vector2(0.4, 0.4), 1.6, TankPalette.STEEL_DARK)
		item.draw_rect(
			Rect2(ball.round() + Vector2(-1, -2), Vector2(1, 1)), TankPalette.STEEL_BRIGHT
		)
	item.draw_rect(Rect2(top.x - 1, collar_y - 1, 3, 2), TankPalette.STEEL)


## The shell rack: two dark posts and two straps holding the shells upright.
func _rack(item: Node2D) -> void:
	var r := Rect2(rack_pos, TankSprites.size("shell_rack"))
	for x: float in [r.position.x + 1.0, r.end.x - 3.0]:
		item.draw_rect(Rect2(x, r.position.y + 4.0, 2, r.size.y - 4.0), TankPalette.IRON_DARK)
		item.draw_rect(Rect2(x, r.position.y + 4.0, 1, r.size.y - 4.0), TankPalette.IRON)
	for y: float in [r.position.y + 16.0, r.end.y - 6.0]:
		item.draw_rect(Rect2(r.position.x + 1.0, y, r.size.x - 2.0, 2), TankPalette.IRON_DARK)
		item.draw_rect(Rect2(r.position.x + 1.0, y, r.size.x - 2.0, 1), TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2), TankPalette.IRON)


## A shell standing in the rack: a dull brass casing (no yellow: only lights are saturated) with a
## lit left edge and a darker base rim, a driving band, and a steel projectile with an ogive nose
## (a rounded 5 px taper, not a spike).
static func _shell(item: Node2D, r: Rect2) -> void:
	var x := r.position.x
	var w := r.size.x
	var body := Rect2(x, r.position.y + 12.0, w, r.size.y - 12.0)
	item.draw_rect(body, TankPalette.MUD_LIGHT)
	item.draw_rect(Rect2(x + 1.0, body.position.y, 1, body.size.y), TankPalette.MUD_PALE)
	item.draw_rect(Rect2(x, body.end.y - 3, w, 3), TankPalette.MUD)
	var proj := Rect2(x, r.position.y + 7.0, w, 5.0)
	item.draw_rect(proj, TankPalette.STEEL_DARK)
	item.draw_rect(Rect2(x + 1.0, proj.position.y, 1, proj.size.y), TankPalette.STEEL)
	item.draw_rect(Rect2(x, proj.end.y - 1.0, w, 1), TankPalette.CLAY)
	var y := proj.position.y
	var nose := PackedVector2Array(
		[
			Vector2(x, y),
			Vector2(x + 0.5, y - 2.0),
			Vector2(x + w * 0.3, y - 4.0),
			Vector2(x + w * 0.5, y - 5.0),
			Vector2(x + w * 0.7, y - 4.0),
			Vector2(x + w - 0.5, y - 2.0),
			Vector2(x + w, y),
		]
	)
	item.draw_colored_polygon(nose, TankPalette.STEEL_DARK)
	item.draw_line(Vector2(x + 1.0, y - 1.0), Vector2(x + w * 0.4, y - 4.0), TankPalette.STEEL, 1.0)
