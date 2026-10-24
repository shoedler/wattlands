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
	var gov := Sprite2D.new()
	gov.texture = TankSprites.tex(TankSprites.flyball_id())
	gov.centered = false
	flyball.add_child(gov)
	add_child(flyball)
	var boiler := Sprite2D.new()
	boiler.name = "Boiler"
	boiler.texture = TankSprites.tex("boiler")
	boiler.centered = false
	boiler.position = boiler_pos
	add_child(boiler)
	var rack := Sprite2D.new()
	rack.name = "ShellRack"
	rack.texture = TankSprites.tex("shell_rack")
	rack.centered = false
	rack.position = rack_pos
	add_child(rack)
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


func engine_lights() -> void:
	var origin := hub.to_layer(rect.position)
	var power := 0.0 if input.unpowered else clampf(input.frac, 0.0, 1.4)
	if power > 0.02:
		var fb := origin + anchor_local("firebox") + TankSprites.size("firebox") * 0.5
		hub.lights.add(fb, 34.0 + 26.0 * power, TankPalette.FIRE, 0.3 + 0.35 * power)
		hub.lights.add(fb, 12.0, TankPalette.GLOW_WARM, 0.45 * power)


func paint_machinery_front(item: Node2D) -> void:
	var c := gauge_pos
	item.draw_circle(c, GAUGE_RADIUS + 1.0, TankPalette.STEEL_LIGHT)
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
	for r in rack_slots:
		_shell(item, r)


## A shell standing in the rack: steel body, brass base, nose.
static func _shell(item: Node2D, r: Rect2) -> void:
	var body := Rect2(r.position + Vector2(0, 7), Vector2(r.size.x, r.size.y - 7))
	item.draw_rect(body, TankPalette.SLATE)
	item.draw_rect(Rect2(body.position.x, body.end.y - 4, body.size.x, 4), TankPalette.BRASS)
	item.draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(r.position.x, r.position.y + 7),
				Vector2(r.position.x + r.size.x * 0.5, r.position.y),
				Vector2(r.end.x, r.position.y + 7)
			]
		),
		TankPalette.STEEL_PALE
	)
