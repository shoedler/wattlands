class_name TankHangar
extends RefCounted
## The Hangar and the Roll-out's first seconds (docs/games/tank.md v1.1.0): the near stage's backdrop is a
## steel hangar instead of the forest road, the hull sits on a mechanic's stand with its tracks spinning in
## the air, white ceiling bars light it, and in the last TankConst.HANGAR_COUNTDOWN_S the bars go dark, two
## red beacons turn, the hull is lowered and the door at the end wall opens. The Roll-out drives out through
## that door and the hangar slides away behind. In the far panel the same hangar stands face on: its gate
## wall with the rolling shutter that opens, sliding off at the far parallax once the tank rolls.
##
## Art: assets/tank/hangar/ (baked by tools_src/hangar_bake.gd); the bars, beacons, stand, shutter and the
## dark overlay are drawn in code. Everything reads the state only (the segment, its elapsed seconds, the
## hull's x) so a client draws the same thing the host does. World x is in art px with the hull at rest at 0
## (stage x = world x - (plane_x + REAR) x S).

const ROOM := "res://assets/tank/hangar/room.png"
const END := "res://assets/tank/hangar/end.png"
const DOOR := "res://assets/tank/hangar/door.png"
const GATE := "res://assets/tank/hangar/gate.png"
const SHUTTER := "res://assets/tank/hangar/shutter.png"

## The tile's size and where the wall meets the floor (stage y); the tank stands in front of it at GROUND.
const ROOM_W := 480.0
const ROOM_H := 440.0
const FLOOR_Y := 380.0
## The end wall: its left edge at hull rest (stage x, at the base canvas; end_origin on any other), its width, the
## doorway's x range and y range in it.
const END_X := 548.0
## How far in from the near panel's edge the wall stands, and the least room it keeps past the tank's nose.
const END_FROM_EDGE := 74.0
const END_NOSE_GAP := 480.0
const END_W := 130.0
const VOID_X0 := 16.0
const VOID_X1 := 114.0
const VOID_TOP := 150.0
const VOID_BOT := 380.0
const DOOR_W := 98.0
const DOOR_H := VOID_BOT - VOID_TOP
## The face-on gate in the far panel: its size, its stage y, the opening's x range in it, the facade's
## half width about the gate.
const GATE_W := 220.0
const GATE_H := 300.0
const GATE_Y0 := 100.0
const AP_X0 := 32.0
const AP_X1 := 188.0
const FACADE_HALF := 250.0
## How far the stand lifts the hull (art px) and its look.
const STAND_LIFT := 26.0
## The ceiling bars: stage y, size, world x of the first and the pitch between them.
const BAR_Y := 28.0
const BAR_W := 100.0
const BAR_H := 8.0
const BAR_X0 := 40.0
const BAR_PITCH := 150.0
## The countdown's beats (s from its start): the bars dim, the beacons start, the hull is lowered, the door
## rises. Everything is done at the countdown's end (TankConst.HANGAR_COUNTDOWN_S).
const DIM_S := Vector2(0.0, 1.5)
const BEACON_S := Vector2(0.3, 1.2)
const LOWER_S := Vector2(1.0, 5.0)
const DOOR_S := Vector2(4.0, 10.0)
## In the Roll-out the beacons keep turning while the hangar is still on screen and fade out over these seconds.
const ROLL_BEACON_S := Vector2(7.0, 11.0)
const BEACON_Y := 112.0
const BEACON_RPM := 50.0
const WHITE := Color(0.9, 0.96, 1.0)
const BAR_OFF := Color(0.1, 0.12, 0.14)
const RED := Color(1.0, 0.18, 0.1)
const STAND_YELLOW := Color(0.6, 0.45, 0.1)
const STAND_DK := Color(0.07, 0.07, 0.07)
const STAND_STEEL := Color(0.17, 0.2, 0.22)

static var _tex: Dictionary = {}


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) as Texture2D
	return _tex[path]


static func smooth(span: Vector2, t: float) -> float:
	return smoothstep(span.x, span.y, t)


# --- The look -------------------------------------------------------------------------------------------------


## What the hangar looks like this frame: {on, dark (0..1, the bars off), beacon (0..1), lift (px), door (0..1
## open), end_x (stage x of the end wall), far_x (the far gate's centre in panel px), far_on}. `on` is false
## outside the Hangar and the Roll-out's first seconds, once the end wall has slid off the stage.
static func look(v: TankView, state: TankState) -> Dictionary:
	var off := {"on": false, "far_on": false, "dark": 0.0, "beacon": 0.0, "lift": 0.0, "door": 0.0}
	if state == null or state.roam.active:
		return off
	var seg := state.seg.seg
	if seg != TankIds.SEG_HANGAR and seg != TankIds.SEG_ROLLOUT:
		return off
	var out := off.duplicate()
	var left := TankSegments.hangar_countdown_s(state)
	if seg == TankIds.SEG_HANGAR:
		var cd := TankConst.HANGAR_COUNTDOWN_S - left if left >= 0.0 else -1.0
		out["lift"] = STAND_LIFT
		if cd >= 0.0:
			out["dark"] = smooth(DIM_S, cd)
			out["beacon"] = smooth(BEACON_S, cd)
			out["lift"] = STAND_LIFT * (1.0 - smooth(LOWER_S, cd))
			out["door"] = smooth(DOOR_S, cd)
	else:
		out["dark"] = 1.0
		out["door"] = 1.0
		out["beacon"] = 1.0 - smooth(ROLL_BEACON_S, state.seg.elapsed_s)
	var shift := (v.plane_x + float(TankConst.REAR_SCREEN_X)) * TankView.S
	out["end_x"] = end_origin(v) - shift
	out["world_shift"] = shift
	out["on"] = float(out["end_x"]) + END_W > -8.0
	var slide := v.hull_x * TankView.S * TankFarPanel.PLANE_PARALLAX
	out["far_x"] = v.far.far_w * 0.5 - slide if v.far != null else 0.0
	out["far_on"] = float(out["far_x"]) + FACADE_HALF > -8.0
	return out


## The end wall's left edge at hull rest on this canvas: a fixed distance in from the near panel's edge (a wider canvas
## shows more room), never closer than END_NOSE_GAP to the tank's left (its nose).
static func end_origin(v: TankView) -> float:
	return maxf(TankFarMap.near_end_x(v.canvas.x) - END_FROM_EDGE, v.tank_pos.x + END_NOSE_GAP)


## True while the hangar covers the near stage at stage x `x` (the world drawn there is the hangar's).
static func covers_x(lk: Dictionary, x: float) -> bool:
	return bool(lk.get("on", false)) and x < float(lk["end_x"]) + END_W


# --- Tiles ----------------------------------------------------------------------------------------------------


## The room tile's rows `src_y .. src_y + h` drawn at stage y `dst_y` across stage x `x0 .. x1`, the tile's x
## origin at `phase0` (it repeats every ROOM_W), clipped at both ends.
static func tile_span(
	ci: CanvasItem,
	t: Texture2D,
	x0: float,
	x1: float,
	phase0: float,
	src_y: float,
	h: float,
	dst_y: float
) -> void:
	if t == null or x1 <= x0 or h <= 0.0:
		return
	var w := float(t.get_width())
	var x := x0
	var src_x := fposmod(x0 - phase0, w)
	while x < x1:
		var span := minf(w - src_x, x1 - x)
		ci.draw_texture_rect_region(
			t, Rect2(roundf(x), dst_y, ceilf(span), h), Rect2(src_x, src_y, ceilf(span), h)
		)
		x += span
		src_x = 0.0


## The foreground plane (or any tiled plane) is clipped to stage x >= `x_min`: the hangar's end wall hides it.
static func clip_x(lk: Dictionary) -> float:
	if not bool(lk.get("on", false)):
		return -INF
	return float(lk["end_x"]) + END_W


# --- The near stage ---------------------------------------------------------------------------------------------


## The hangar over the outdoors (drawn after the planes and the road): the room across the stage up to the end
## wall, the end wall with its doorway and the door in it, the dark overlay of the countdown.
static func draw_back(ci: CanvasItem, v: TankView, lk: Dictionary) -> void:
	var room := tex(ROOM)
	var end := tex(END)
	if room == null or end == null:
		return
	var top := -v.y_off - 4.0
	var end_x: float = lk["end_x"]
	var shift: float = lk["world_shift"]
	var x_to := minf(end_x, v.canvas.x)
	if top < 0.0:
		ci.draw_rect(Rect2(-8, top, x_to + 8.0, -top), Color(0.04, 0.05, 0.06))
	tile_span(ci, room, -8.0, x_to, -shift, 0.0, ROOM_H, 0.0)
	var bottom := v.canvas.y - v.y_off + 4.0
	if bottom > ROOM_H:
		ci.draw_rect(
			Rect2(-8, ROOM_H - 1.0, x_to + 8.0, bottom - ROOM_H + 1.0), Color(0.05, 0.06, 0.06)
		)
	ci.draw_texture(end, Vector2(roundf(end_x), 0.0))
	if bottom > ROOM_H:
		ci.draw_rect(
			Rect2(roundf(end_x), ROOM_H - 1.0, END_W, bottom - ROOM_H + 1.0),
			Color(0.05, 0.06, 0.06)
		)
	_door(ci, end_x, float(lk["door"]))
	_bars(ci, v, lk)
	var dark: float = lk["dark"]
	if dark > 0.0:
		var shade := Color(0.0, 0.01, 0.03, 0.58 * dark)
		# The night shows through what the door has left open (it rises from the floor).
		var gap := roundf(DOOR_H * float(lk["door"]))
		var hole := Rect2(end_x + VOID_X0, VOID_BOT - gap, VOID_X1 - VOID_X0, gap)
		_overlay_except(ci, Rect2(-8, top, end_x + END_W + 8.0, bottom - top), hole, shade)
	_beacons(ci, v, lk, false)


static func _door(ci: CanvasItem, end_x: float, open: float) -> void:
	var t := tex(DOOR)
	if t == null:
		return
	var shown := roundf(DOOR_H * (1.0 - open))
	if shown <= 0.0:
		return
	var x := roundf(end_x + VOID_X0)
	ci.draw_texture_rect_region(
		t, Rect2(x, VOID_TOP, DOOR_W, shown), Rect2(0, DOOR_H - shown, DOOR_W, shown)
	)


## `rect` darkened except `hole` (the doorway: the night outside stays as it is).
static func _overlay_except(ci: CanvasItem, rect: Rect2, hole: Rect2, c: Color) -> void:
	var h := hole.intersection(rect)
	if h.size == Vector2.ZERO:
		ci.draw_rect(rect, c)
		return
	ci.draw_rect(Rect2(rect.position, Vector2(h.position.x - rect.position.x, rect.size.y)), c)
	ci.draw_rect(
		Rect2(Vector2(h.end.x, rect.position.y), Vector2(rect.end.x - h.end.x, rect.size.y)), c
	)
	ci.draw_rect(
		Rect2(
			Vector2(h.position.x, rect.position.y),
			Vector2(h.size.x, h.position.y - rect.position.y)
		),
		c
	)
	ci.draw_rect(Rect2(Vector2(h.position.x, h.end.y), Vector2(h.size.x, rect.end.y - h.end.y)), c)


## Stage x of each ceiling bar's left end this frame.
static func bar_xs(lk: Dictionary, canvas_w: float, limit_x: float) -> Array[float]:
	var out: Array[float] = []
	var shift: float = lk["world_shift"]
	var n := floori((shift - 20.0) / BAR_PITCH)
	while true:
		var x := BAR_X0 + float(n) * BAR_PITCH - shift
		if x > minf(canvas_w, limit_x - BAR_W):
			break
		if x + BAR_W > -4.0:
			out.append(x)
		n += 1
	return out


static func _bars(ci: CanvasItem, v: TankView, lk: Dictionary) -> void:
	var dark: float = lk["dark"]
	for x in bar_xs(lk, v.canvas.x, float(lk["end_x"]) - 8.0):
		_bar(ci, Vector2(roundf(x), BAR_Y), dark)


## One bar fixture: a dark housing, the tube white when lit and grey when dark.
static func _bar(ci: CanvasItem, at: Vector2, dark: float) -> void:
	ci.draw_rect(
		Rect2(at + Vector2(-2, -2), Vector2(BAR_W + 4.0, BAR_H + 4.0)), Color(0.03, 0.04, 0.05)
	)
	ci.draw_rect(Rect2(at + Vector2(-2, -2), Vector2(BAR_W + 4.0, 1.0)), Color(0.22, 0.28, 0.32))
	var tube := WHITE.lerp(BAR_OFF, dark)
	ci.draw_rect(Rect2(at, Vector2(BAR_W, BAR_H)), tube)
	ci.draw_rect(
		Rect2(at + Vector2(2, 2), Vector2(BAR_W - 4.0, BAR_H - 4.0)),
		Color.WHITE.lerp(BAR_OFF, dark)
	)
	for k in 5:
		ci.draw_rect(
			Rect2(at + Vector2(float(k) * 25.0 + 12.0, 0), Vector2(1, BAR_H)),
			Color(0.0, 0.0, 0.0, 0.18)
		)


# --- The beacons ------------------------------------------------------------------------------------------------


## World x (art px) of the two beacons on the near wall: one near the tank's rear, one by the end wall.
static func beacon_world_x(lk: Dictionary) -> Array[float]:
	return [96.0, float(lk["end_x"]) + float(lk["world_shift"]) - 46.0]


static func _beacons(ci: CanvasItem, v: TankView, lk: Dictionary, light: bool) -> void:
	var k: float = lk["beacon"]
	var shift: float = lk["world_shift"]
	for wx in beacon_world_x(lk):
		var p := Vector2(roundf(wx - shift), BEACON_Y)
		if p.x < -40.0 or p.x > float(lk["end_x"]):
			continue
		if light:
			_beacon_light(ci, v, p, k)
		else:
			_beacon_body(ci, p, k)


## The housing and the red dome: dim when off, bright on its turn.
static func _beacon_body(ci: CanvasItem, p: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(p + Vector2(-7, 4), Vector2(14, 4)), Color(0.07, 0.08, 0.09))
	ci.draw_rect(Rect2(p + Vector2(-7, 4), Vector2(14, 1)), Color(0.28, 0.34, 0.38))
	var dome := Color(0.28, 0.06, 0.05).lerp(Color(1.0, 0.25, 0.14), k)
	ci.draw_rect(Rect2(p + Vector2(-5, -5), Vector2(10, 9)), Color(0.04, 0.03, 0.03))
	ci.draw_rect(Rect2(p + Vector2(-4, -4), Vector2(8, 8)), dome)
	ci.draw_rect(Rect2(p + Vector2(-3, -3), Vector2(2, 3)), Color(1, 1, 1, 0.35 * k + 0.1))


static func _beacon_light(ci: CanvasItem, v: TankView, p: Vector2, k: float) -> void:
	if k <= 0.0:
		return
	var ang := v.time * BEACON_RPM / 60.0 * TAU
	TankDraw.glow_at(ci, p, 14.0, Color(RED.r, RED.g, RED.b, 0.75 * k))
	TankDraw.glow_at(ci, p, 44.0, Color(RED.r, RED.g, RED.b, 0.14 * k))
	for side in 2:
		_sweep(ci, p, ang + float(side) * PI, 210.0, 0.17 * k)


## A narrow red wedge from `p` along `ang`, bright near the lens and gone at its far end.
static func _sweep(ci: CanvasItem, p: Vector2, ang: float, len: float, a: float) -> void:
	var half := deg_to_rad(11.0)
	var d0 := Vector2.from_angle(ang - half)
	var d1 := Vector2.from_angle(ang + half)
	var clear := Color(RED.r, RED.g, RED.b, 0.0)
	var mid := Color(RED.r, RED.g, RED.b, a * 0.55)
	ci.draw_polygon(
		PackedVector2Array([p, p + d0 * len * 0.5, p + d1 * len * 0.5]),
		PackedColorArray([Color(RED.r, RED.g, RED.b, a), mid, mid])
	)
	ci.draw_polygon(
		PackedVector2Array([p + d0 * len * 0.5, p + d0 * len, p + d1 * len, p + d1 * len * 0.5]),
		PackedColorArray([mid, clear, clear, mid])
	)


# --- The stand ------------------------------------------------------------------------------------------------------


## The mechanic's stand under the hull on the world layer: two trestles under the track run with a jack each,
## standing on the floor and holding the hull `lift` px up; they shorten as the hull is lowered.
static func draw_stand(ci: CanvasItem, v: TankView, lk: Dictionary) -> void:
	var lift: float = lk["lift"]
	if lift <= 0.5:
		return
	var dark: float = lk["dark"]
	var k := 1.0 - 0.55 * dark
	for sprite_x: float in [120.0, 372.0]:
		var x := roundf(v.tank_pos.x + sprite_x)
		var floor_y := roundf(v.ground_y(x))
		var top := floor_y - roundf(lift)
		_trestle(ci, x, floor_y, top, k)


static func _trestle(ci: CanvasItem, x: float, floor_y: float, top: float, k: float) -> void:
	var yellow := STAND_YELLOW * k
	var steel := STAND_STEEL * k
	var dk := STAND_DK
	yellow.a = 1.0
	steel.a = 1.0
	# the foot plate, two legs splayed to the cradle, the jack's piston between them
	ci.draw_rect(Rect2(x - 22.0, floor_y - 2.0, 44.0, 3.0), dk)
	ci.draw_rect(Rect2(x - 21.0, floor_y - 2.0, 42.0, 1.0), steel.lightened(0.3))
	var h := floor_y - top
	for side: float in [-1.0, 1.0]:
		var foot := Vector2(x + side * 18.0, floor_y - 2.0)
		var head := Vector2(x + side * 9.0, top + 4.0)
		ci.draw_line(foot, head, dk, 4.0)
		ci.draw_line(
			foot + Vector2(side * -0.5, 0.0), head + Vector2(side * -0.5, 0.0), yellow, 2.0
		)
	ci.draw_rect(Rect2(x - 3.0, top + 6.0, 6.0, maxf(h - 8.0, 1.0)), dk)
	ci.draw_rect(Rect2(x - 2.0, top + 6.0, 2.0, maxf(h - 8.0, 1.0)), steel.lightened(0.35))
	# the cradle pad the track run rests on
	ci.draw_rect(Rect2(x - 20.0, top + 1.0, 40.0, 4.0), dk)
	ci.draw_rect(Rect2(x - 19.0, top + 1.0, 38.0, 2.0), yellow)
	ci.draw_rect(Rect2(x - 19.0, top + 1.0, 38.0, 1.0), yellow.lightened(0.3))


# --- Light ---------------------------------------------------------------------------------------------------------


## The additive light behind the tank: the bars' cones and their pools on the floor while lit, the beacons'
## sweeps while they turn.
static func draw_light(ci: CanvasItem, v: TankView, lk: Dictionary) -> void:
	var lit := 1.0 - float(lk["dark"])
	if lit > 0.0:
		for x in bar_xs(lk, v.canvas.x, float(lk["end_x"]) - 8.0):
			_cone(ci, x, lit)
	_beacons(ci, v, lk, true)
	var k: float = lk["beacon"]
	if k > 0.0:
		var pulse := 0.5 + 0.5 * sin(v.time * BEACON_RPM / 60.0 * TAU)
		ci.draw_rect(
			Rect2(-8, 0, float(lk["end_x"]) + END_W, FLOOR_Y + 60.0),
			Color(RED.r, RED.g, RED.b, 0.025 * k * (0.5 + pulse))
		)


static func _cone(ci: CanvasItem, x: float, lit: float) -> void:
	var c0 := Color(0.72, 0.86, 1.0, 0.1 * lit)
	var clear := Color(0.72, 0.86, 1.0, 0.0)
	var mid := Color(0.72, 0.86, 1.0, 0.035 * lit)
	ci.draw_polygon(
		PackedVector2Array(
			[
				Vector2(x, BAR_Y + BAR_H + 1.0),
				Vector2(x + BAR_W, BAR_Y + BAR_H + 1.0),
				Vector2(x + BAR_W + 60.0, 220.0),
				Vector2(x - 60.0, 220.0)
			]
		),
		PackedColorArray([c0, c0, mid, mid])
	)
	ci.draw_polygon(
		PackedVector2Array(
			[
				Vector2(x - 60.0, 220.0),
				Vector2(x + BAR_W + 60.0, 220.0),
				Vector2(x + BAR_W + 120.0, FLOOR_Y + 4.0),
				Vector2(x - 120.0, FLOOR_Y + 4.0)
			]
		),
		PackedColorArray([mid, mid, clear, clear])
	)
	TankDraw.glow_at(
		ci, Vector2(x + BAR_W * 0.5, BAR_Y + BAR_H * 0.5), 58.0, Color(0.8, 0.9, 1.0, 0.18 * lit)
	)
	TankDraw.soft_at(
		ci, Vector2(x + BAR_W * 0.5, FLOOR_Y + 14.0), 80.0, Color(0.7, 0.85, 1.0, 0.07 * lit)
	)


# --- The far panel ---------------------------------------------------------------------------------------------------


## The hangar seen face on, over the far panel's night: the facade (the room's wall and ceiling) around the
## gate, the rolling shutter over the opening and the bars. `ci` is the panel's Back layer; stage y.
static func draw_far(ci: CanvasItem, far: TankFarPanel, lk: Dictionary) -> void:
	if not bool(lk.get("far_on", false)):
		return
	var room := tex(ROOM)
	var gate := tex(GATE)
	if room == null or gate == null:
		return
	var gx: float = lk["far_x"]
	var fl := roundf(gx - FACADE_HALF)
	var fr := roundf(gx + FACADE_HALF)
	var gl := roundf(gx - GATE_W * 0.5)
	var gr := gl + GATE_W
	var bottom := float(far.size.y) - far._y_off + TankFarPanel.OVERDRAW
	var top := -far._y_off - TankFarPanel.OVERDRAW
	# the facade either side of the gate, above it and under it, then the gate itself
	tile_span(ci, room, fl, gl, fl, 0.0, ROOM_H, 0.0)
	tile_span(ci, room, gr, fr, fl, 0.0, ROOM_H, 0.0)
	tile_span(ci, room, gl, gr, fl, 0.0, GATE_Y0, 0.0)
	tile_span(ci, room, gl, gr, fl, GATE_Y0 + GATE_H, ROOM_H - GATE_Y0 - GATE_H, GATE_Y0 + GATE_H)
	ci.draw_texture(gate, Vector2(gl, GATE_Y0))
	if top < 0.0:
		ci.draw_rect(Rect2(fl, top, fr - fl, -top), Color(0.04, 0.05, 0.06))
	if bottom > ROOM_H:
		ci.draw_rect(
			Rect2(fl, ROOM_H - 1.0, fr - fl, bottom - ROOM_H + 1.0), Color(0.05, 0.06, 0.06)
		)
	# the end pilasters
	ci.draw_texture_rect_region(room, Rect2(fr - 22.0, 0, 22, ROOM_H), Rect2(0, 0, 22, ROOM_H))
	_shutter(ci, gl + AP_X0, float(lk["door"]))
	var dark: float = lk["dark"]
	for n in 3:
		var bx := fl + 40.0 + float(n) * BAR_PITCH + 10.0
		if bx + BAR_W > fr - 20.0:
			continue
		_bar(ci, Vector2(roundf(bx), BAR_Y), dark)
	if dark > 0.0:
		var shade := Color(0.0, 0.01, 0.03, 0.58 * dark)
		var hole := Rect2(gl + AP_X0, VOID_TOP, AP_X1 - AP_X0, VOID_BOT - VOID_TOP)
		_overlay_except(ci, Rect2(fl, top, fr - fl, bottom - top), hole, shade)
	for side: float in [-1.0, 1.0]:
		_beacon_body(
			ci, Vector2(gx + side * (GATE_W * 0.5 - 12.0), GATE_Y0 + 20.0), float(lk["beacon"])
		)


static func _shutter(ci: CanvasItem, x: float, open: float) -> void:
	var t := tex(SHUTTER)
	if t == null:
		return
	var w := AP_X1 - AP_X0
	var shown := roundf((VOID_BOT - VOID_TOP) * (1.0 - open))
	if shown <= 0.0:
		return
	var y := VOID_TOP
	while y < VOID_TOP + shown:
		var hh := minf(8.0, VOID_TOP + shown - y)
		tile_span(ci, t, x, x + w, x, 0.0, hh, y)
		y += 8.0
	# the shutter's bottom bar, hazard-striped
	var by := VOID_TOP + shown - 8.0
	for i in int(w / 6.0) + 1:
		var c := Color(0.6, 0.45, 0.09) if i % 2 == 0 else Color(0.05, 0.06, 0.06)
		ci.draw_rect(Rect2(x + float(i) * 6.0, by, minf(6.0, w - float(i) * 6.0), 8.0), c)


## The far panel's additive light: the bars' glow and the beacons' wedges.
static func draw_far_light(ci: CanvasItem, far: TankFarPanel, lk: Dictionary) -> void:
	if not bool(lk.get("far_on", false)):
		return
	var gx: float = lk["far_x"]
	var fl := roundf(gx - FACADE_HALF)
	var fr := roundf(gx + FACADE_HALF)
	var lit := 1.0 - float(lk["dark"])
	if lit > 0.0:
		for n in 3:
			var bx := fl + 40.0 + float(n) * BAR_PITCH + 10.0
			if bx + BAR_W > fr - 20.0:
				continue
			_cone(ci, roundf(bx), lit)
	var k: float = lk["beacon"]
	if k > 0.0:
		var ang := far.v.time * BEACON_RPM / 60.0 * TAU
		for side: float in [-1.0, 1.0]:
			var p := Vector2(gx + side * (GATE_W * 0.5 - 12.0), GATE_Y0 + 20.0)
			TankDraw.glow_at(ci, p, 12.0, Color(RED.r, RED.g, RED.b, 0.75 * k))
			TankDraw.glow_at(ci, p, 40.0, Color(RED.r, RED.g, RED.b, 0.14 * k))
			for s in 2:
				_sweep(ci, p, ang + float(s) * PI + (0.6 if side > 0.0 else 0.0), 170.0, 0.17 * k)
