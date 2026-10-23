class_name TankRoomView
extends Node2D
## One cutaway engine room (brief 3, "Cutaway"): an opaque back wall at the room's rect from
## assets/tank/rigs.json with a code-drawn riveted frame, the engine's machinery on it, and a wall
## lamp in the rider's slot colour with their shape badge, pulsing at cadence while in band. The
## room is dark: it brightens with %FTP and glows when in band, so each engine's own light marks it.
## Subclasses (TankDieselRoom, TankBulwarkRoom, TankDynamoRoom, TankSteamRoom) build the machinery
## in build() and animate it in animate(); this base draws the wall, frame and lamp.
##
## Coordinates: the room node sits at its rect's top-left in the hull frame; its children use room
## coordinates, and anchor(key) / local(p) convert the rigs.json hull-frame points.

## How long a lamp flares when the crew changes stations.
const FLARE_S := 1.2
## Which room sprite shows the wall of `engine` ("room_<engine>").
const WALL_PREFIX := "room_"

var engine: String = ""
## The room's rect in the hull frame.
var rect: Rect2 = Rect2()
var def: Dictionary = {}
## rigs.json "machinery".
var machinery: Dictionary = {}
var hub: TankRigHub = null
var input: TankRoomInput = TankRoomInput.new()
## The station this room shows (set by the rig every frame; null before the first).
var station: TankStationState = null
## Front painter: gauges, jars, the lamp (above the machinery children).
var front: TankPainter = null
## Pulse phase in cycles (one cycle per pedal stroke).
var lamp_phase: float = 0.0
## Seconds left of the station-change flare (the lamp glows whatever the band).
var flare_s: float = 0.0

var _wall: Texture2D = null


func assemble(p_def: Dictionary, p_machinery: Dictionary, p_hub: TankRigHub) -> void:
	def = p_def
	machinery = p_machinery
	hub = p_hub
	engine = str(def.get("engine", ""))
	rect = TankRigs.rect(def.get("rect", [0, 0, 96, 48]))
	position = rect.position
	name = "Room_" + engine
	_wall = TankSprites.tex(WALL_PREFIX + engine)
	build()
	front = TankPainter.new()
	front.name = "Front"
	front.painter = _paint_front
	add_child(front)
	queue_redraw()


## A hull-frame anchor of the room def (Vector2.ZERO when absent).
func anchor(key: String) -> Vector2:
	return TankRigs.vec(def.get(key))


## Room coordinates of a hull-frame point.
func local(p: Vector2) -> Vector2:
	return p - rect.position


## Room coordinates of the anchor `key`.
func anchor_local(key: String) -> Vector2:
	return local(anchor(key))


## Feeds one frame: the rider's input, then the machinery and the lights.
func feed(p_input: TankRoomInput, dt: float) -> void:
	input = p_input
	var b := input.brightness()
	modulate = Color(b, b, b)
	# The lamp, jars and gauges are lights themselves: cancel the room's dimming for them.
	var inv := 1.0 / b
	front.modulate = Color(inv, inv, inv)
	lamp_phase = fposmod(lamp_phase + maxf(input.cadence, 0.0) / 60.0 * dt, 1.0)
	flare_s = maxf(0.0, flare_s - dt)
	animate(dt)
	_lights()
	front.queue_redraw()


## True while the lamp is lit: in band and powered.
func lit() -> bool:
	return input.in_band and not input.reserve and not input.unpowered


## The badge pulse 0 .. 1 (one beat per pedal stroke).
func pulse() -> float:
	return 0.5 + 0.5 * cos(TAU * lamp_phase)


## The glow tint of this engine's room.
func tint() -> Color:
	match engine:
		TankIds.ENGINE_DYNAMO:
			return TankPalette.COLD_LIGHT
		TankIds.ENGINE_STEAM:
			return TankPalette.FIRE
	return TankPalette.AMBER


# --- Virtual ---------------------------------------------------------------------------------


## Builds the machinery children (before the front painter is added).
func build() -> void:
	pass


## Animates the machinery for this frame's `input`.
func animate(_dt: float) -> void:
	pass


## Adds engine-specific halos (cylinders, arc, firebox) to the hub's light layer.
func engine_lights() -> void:
	pass


# --- Drawing ---------------------------------------------------------------------------------


func _draw() -> void:
	draw_texture_rect(_wall, Rect2(Vector2.ZERO, rect.size), false)
	_frame(self, Rect2(Vector2.ZERO, rect.size))


## The riveted frame: a two-pixel steel border, an inner shadow line, corner plates and rivets.
static func _frame(item: CanvasItem, r: Rect2) -> void:
	item.draw_rect(r, TankPalette.STEEL_DARK, false, 2.0)
	item.draw_rect(r.grow(-2.0), TankPalette.COAL, false, 1.0)
	var plate := TankPalette.STEEL
	for corner: Vector2 in [
		r.position,
		Vector2(r.end.x - 6.0, r.position.y),
		Vector2(r.position.x, r.end.y - 6.0),
		r.end - Vector2(6, 6)
	]:
		item.draw_rect(Rect2(corner, Vector2(6, 6)), plate)
		item.draw_rect(Rect2(corner + Vector2(2, 2), Vector2(1, 1)), TankPalette.STEEL_BRIGHT)
	var x := r.position.x + 12.0
	while x < r.end.x - 10.0:
		item.draw_rect(Rect2(x, r.position.y + 1.0, 1, 1), TankPalette.STEEL_BRIGHT)
		item.draw_rect(Rect2(x, r.end.y - 2.0, 1, 1), TankPalette.STEEL_BRIGHT)
		x += 10.0
	var y := r.position.y + 12.0
	while y < r.end.y - 10.0:
		item.draw_rect(Rect2(r.position.x + 1.0, y, 1, 1), TankPalette.STEEL_BRIGHT)
		item.draw_rect(Rect2(r.end.x - 2.0, y, 1, 1), TankPalette.STEEL_BRIGHT)
		y += 10.0


func _paint_front(item: Node2D) -> void:
	paint_machinery_front(item)
	_paint_lamp(item)


## Engine-specific drawing above the machinery (gauges, jars, levers).
func paint_machinery_front(_item: Node2D) -> void:
	pass


func _paint_lamp(item: Node2D) -> void:
	var lp := anchor_local("lamp")
	var look := input.look if not input.look.is_empty() else Wl.slot_look(maxi(input.slot, 0))
	var col: Color = look.get("color", Color.WHITE)
	var on := lit()
	item.draw_line(lp + Vector2(0, -6), lp + Vector2(0, -3), TankPalette.STEEL, 1.0)
	item.draw_circle(
		lp, 3.0, col.lerp(Color.WHITE, 0.35) if on else TankPalette.darkened(col, 0.72)
	)
	var c := lp + Vector2(10, 0)
	var k := (1.0 + 0.32 * pulse()) if on else 0.75
	var pts := SlotChip.shape_points(
		str(look.get("shape", "circle")), Rect2(c - Vector2(4, 4) * k, Vector2(8, 8) * k)
	)
	var closed := pts.duplicate()
	closed.append(pts[0])
	if bool(look.get("hollow", false)):
		item.draw_colored_polygon(pts, Color(0.05, 0.06, 0.08, 0.85))
		item.draw_polyline(closed, col if on else TankPalette.darkened(col, 0.6), 1.0)
	else:
		item.draw_colored_polygon(pts, col if on else TankPalette.darkened(col, 0.65))
		item.draw_polyline(closed, Color(0, 0, 0, 0.75), 1.0)


func _lights() -> void:
	if hub == null or hub.lights == null:
		return
	var origin := hub.to_layer(rect.position)
	if lit():
		var look := input.look if not input.look.is_empty() else Wl.slot_look(maxi(input.slot, 0))
		var col: Color = look.get("color", Color.WHITE)
		var p := pulse()
		hub.lights.add(origin + anchor_local("lamp"), 17.0 + 7.0 * p, col, 0.5 + 0.4 * p)
		hub.lights.add(
			origin + rect.size * 0.5,
			rect.size.x * 0.7,
			tint(),
			0.1 + 0.2 * clampf(input.frac, 0.0, 1.2)
		)
	if flare_s > 0.0:
		var flare_look := (
			input.look if not input.look.is_empty() else Wl.slot_look(maxi(input.slot, 0))
		)
		var k := flare_s / FLARE_S
		var flare_color: Color = flare_look.get("color", Color.WHITE)
		hub.lights.add(origin + anchor_local("lamp"), 26.0 + 14.0 * k, flare_color, 0.9 * k)
	engine_lights()
