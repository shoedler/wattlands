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


## How far the rider's lamp washes the room, 0 .. 1 of its full halo. The dynamo keeps its arc
## blue-white whatever the rider's colour, so only its lamp and badge take that colour.
func lamp_reach() -> float:
	return 1.0


## Where the room's own light comes from (room coordinates): its glow is centred there, falling to
## black in the corners. Subclasses return their cylinders, arc or firebox.
func light_source() -> Vector2:
	return rect.size * 0.5


# --- Drawing ---------------------------------------------------------------------------------


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, rect.size)
	draw_texture_rect(_wall, r, false)
	# The wall darkens toward its corners around the room's own light source, so the machine's glow
	# (an additive halo at light_source) is the only thing that lights it.
	var src := light_source()
	var reach := maxf(rect.size.x, rect.size.y) * 0.75
	var box := Rect2(src - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	var shade := TankProcTex.shade()
	var seen := box.intersection(r)
	if seen.has_area():
		var k := shade.get_size() / box.size
		var region := Rect2((seen.position - box.position) * k, seen.size * k)
		draw_texture_rect_region(shade, seen, region)
	var outside := TankPalette.with_alpha(TankPalette.BLACK, TankProcTex.SHADE_EDGE)
	if box.position.x > 0.0:
		draw_rect(Rect2(0, 0, minf(box.position.x, r.size.x), r.size.y), outside)
	if box.end.x < r.size.x:
		draw_rect(
			Rect2(maxf(box.end.x, 0.0), 0, r.size.x - maxf(box.end.x, 0.0), r.size.y), outside
		)
	_frame(self, r)


## The riveted frame, dark like the bulkheads (brief 3: the rooms are dark boxes marked by their own
## light): a two-pixel coal border with a black inner bevel, iron corner plates and dim rivets.
static func _frame(item: CanvasItem, r: Rect2) -> void:
	item.draw_rect(r, TankPalette.COAL, false, 2.0)
	item.draw_rect(r.grow(-2.0), TankPalette.BLACK, false, 1.0)
	item.draw_rect(Rect2(r.position.x + 2.0, r.end.y - 3.0, r.size.x - 4.0, 1.0), TankPalette.IRON)
	var plate := TankPalette.IRON
	for corner: Vector2 in [
		r.position,
		Vector2(r.end.x - 6.0, r.position.y),
		Vector2(r.position.x, r.end.y - 6.0),
		r.end - Vector2(6, 6)
	]:
		item.draw_rect(Rect2(corner, Vector2(6, 6)), plate)
		item.draw_rect(Rect2(corner + Vector2(2, 2), Vector2(1, 1)), TankPalette.STEEL)
	var x := r.position.x + 12.0
	while x < r.end.x - 10.0:
		item.draw_rect(Rect2(x, r.position.y + 1.0, 1, 1), TankPalette.STEEL_DARK)
		item.draw_rect(Rect2(x, r.end.y - 2.0, 1, 1), TankPalette.STEEL_DARK)
		x += 8.0
	var y := r.position.y + 12.0
	while y < r.end.y - 10.0:
		item.draw_rect(Rect2(r.position.x + 1.0, y, 1, 1), TankPalette.STEEL_DARK)
		item.draw_rect(Rect2(r.end.x - 2.0, y, 1, 1), TankPalette.STEEL_DARK)
		y += 8.0


func _paint_front(item: Node2D) -> void:
	paint_machinery_front(item)
	_paint_lamp(item)


## Engine-specific drawing above the machinery (gauges, jars, levers).
func paint_machinery_front(_item: Node2D) -> void:
	pass


## The rider's wall lamp and shape badge (BRIEF 3.9) as glass lenses in the diorama, not UI chips: a
## dark iron bezel ring, then the glass graded from a desaturated, darker rim (60% toward the bezel's
## iron) to a bright centre in the rider's colour, and one warm specular pixel at the upper left. The
## colour shows most through the additive halo (_lights) while in band; when not, the glass is dim.
func _paint_lamp(item: Node2D) -> void:
	var lp := anchor_local("lamp")
	var look := input.look if not input.look.is_empty() else Wl.slot_look(maxi(input.slot, 0))
	var col: Color = look.get("color", Color.WHITE)
	var on := lit()
	item.draw_line(lp + Vector2(0, -6), lp + Vector2(0, -4), TankPalette.STEEL_DARK, 1.0)
	item.draw_circle(lp, 3.5, TankPalette.BLACK)
	item.draw_arc(lp, 3.0, 0.0, TAU, 12, TankPalette.IRON, 1.0)
	item.draw_circle(lp, 2.5, _glass(col, on, 0.6))
	item.draw_circle(lp, 1.4, _glass(col, on, 0.0))
	if on:
		item.draw_rect(Rect2(lp.round() - Vector2(1, 1), Vector2(1, 1)), TankPalette.WHITE_WARM)
	var c := badge_pos()
	var k := (1.0 + 0.15 * pulse()) if on else 1.0
	var shape := str(look.get("shape", "circle"))
	var bezel := SlotChip.shape_points(shape, Rect2(c - Vector2(5, 5) * k, Vector2(10, 10) * k))
	item.draw_colored_polygon(bezel, TankPalette.BLACK)
	var ring := bezel.duplicate()
	ring.append(bezel[0])
	item.draw_polyline(ring, TankPalette.IRON, 1.0)
	var rim := SlotChip.shape_points(shape, Rect2(c - Vector2(4, 4) * k, Vector2(8, 8) * k))
	var core := SlotChip.shape_points(
		shape, Rect2(c - Vector2(2.3, 2.3) * k, Vector2(4.6, 4.6) * k)
	)
	if bool(look.get("hollow", false)):
		var closed := rim.duplicate()
		closed.append(rim[0])
		item.draw_colored_polygon(rim, Color(0.05, 0.06, 0.08, 0.9))
		item.draw_polyline(closed, _glass(col, on, 0.3), 1.0)
	else:
		item.draw_colored_polygon(rim, _glass(col, on, 0.6))
		item.draw_colored_polygon(core, _glass(col, on, 0.0))
	if on:
		var spec := (c - Vector2(2, 2) * k).round()
		item.draw_rect(
			Rect2(spec, Vector2(1, 1)), TankPalette.with_alpha(TankPalette.WHITE_WARM, 0.85)
		)


## Glass of colour `col`: toward the bezel's iron by `edge` (0 the centre .. 0.6 the rim), its
## saturation held down, dim when the lamp is off.
static func _glass(col: Color, on: bool, edge: float) -> Color:
	var g := Color.from_hsv(col.h, minf(col.s, 0.75), col.v)
	g = g.lerp(TankPalette.IRON, edge)
	if not on:
		g = TankPalette.darkened(g, 0.7)
	return TankPalette.with_alpha(g, 0.92 if on else 0.75)


## The shape badge's centre beside the lamp (room coordinates).
func badge_pos() -> Vector2:
	return anchor_local("lamp") + Vector2(10, 0)


func _lights() -> void:
	if hub == null or hub.lights == null:
		return
	var origin := hub.to_layer(rect.position)
	if lit():
		var look := input.look if not input.look.is_empty() else Wl.slot_look(maxi(input.slot, 0))
		var col: Color = look.get("color", Color.WHITE)
		var p := pulse()
		# A wide soft halo washing the dark room in the rider's colour (narrower where the engine's
		# own light must keep its colour: lamp_reach), and a tight hot core.
		var reach := lamp_reach()
		hub.lights.add(
			origin + anchor_local("lamp"), (50.0 + 18.0 * p) * reach, col, (0.3 + 0.25 * p) * reach
		)
		hub.lights.add(
			origin + anchor_local("lamp"), 9.0 + 3.0 * p, col.lerp(Color.WHITE, 0.4), 0.8
		)
		hub.lights.add(origin + badge_pos(), 7.0 + 2.0 * p, col, 0.45)
	# The engine's own light fills the room from its source and falls off before the corners.
	var power := 0.0 if input.unpowered else clampf(input.frac, 0.0, 1.2)
	if power > 0.02:
		hub.lights.add(
			origin + light_source(),
			rect.size.x * (0.42 if lit() else 0.34),
			tint(),
			(0.08 + 0.16 * power) * (1.25 if lit() else 1.0)
		)
	if flare_s > 0.0:
		var flare_look := (
			input.look if not input.look.is_empty() else Wl.slot_look(maxi(input.slot, 0))
		)
		var k := flare_s / FLARE_S
		var flare_color: Color = flare_look.get("color", Color.WHITE)
		hub.lights.add(
			origin + anchor_local("lamp"), (60.0 + 30.0 * k) * lamp_reach(), flare_color, 0.7 * k
		)
	engine_lights()
