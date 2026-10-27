class_name TankHullDraw
extends RefCounted
## The tank (docs/games/tank.md 3.2-3.4), drawn by TankView's "Tank" layer in stage px: the barrel
## behind the hull at the gun's elevation (-12 .. +30 degrees) and traverse, recoiling with each
## shot; the variant cut from the reference; the running gear moving with the distance driven; the
## machines in the station rooms in sync with their riders (TankRoomMachines); the crew
## (TankCrew); the enamel plaques with their slot-coloured lamps; a breakdown's dead rooms.

const PLAQUE := Color(0.3, 0.22, 0.12)
const PLAQUE_HI := Color(0.5, 0.38, 0.2)
const PLAQUE_SIDE := Color(0.42, 0.32, 0.17)
const ENAMEL := Color(0.075, 0.065, 0.055)
const ENGRAVE := Color(0.4, 0.32, 0.2)
const BEZEL := Color(0.16, 0.12, 0.08)
const GLASS_OFF := Color(0.2, 0.18, 0.16)
## The engines' glyphs, engraved in the plaques (7 x 7; no text).
const GLYPHS := {
	"diesel": ["...#...", "..###..", ".#####.", ".#####.", "#######", ".#####.", "..###.."],
	"bulwark": ["#######", "#..#..#", "#..#..#", "#######", "#..#..#", "#..#..#", "#######"],
	"steam": [".#..#..", "..#..#.", ".#..#..", ".......", "#######", "#.....#", "#######"],
	"dynamo": ["....##.", "...##..", "..##...", ".#####.", "...##..", "..##...", ".##...."],
	"arc": ["#.....#", "#.###.#", "##...##", "#.....#", "#..#..#", "#.###.#", "#.....#"],
}


static func draw(ci: CanvasItem, v: TankView, state: TankState) -> void:
	var tv := v.kit.variant(v.variant)
	if tv.is_empty():
		return
	var o := v.origin
	_barrel(ci, v, tv)
	ci.draw_texture(tv["hull"], o)
	_running_gear(ci, v, o)
	var machine_rooms := {}
	for e: String in ["diesel", "steam", "dynamo", TankView.ENGINE_ARC]:
		if v.room_rects.has(e):
			machine_rooms[e] = v.room_rects[e]
	TankRoomMachines.draw(ci, o, machine_rooms, v.phases, v.powers, v.time)
	var info := {
		"cad": v.cadences,
		"steam_phase": v.machine_phase(TankIds.ENGINE_STEAM),
		"solo": v.variant == "tank_1rider",
		"breakdown": state.hull.breakdown,
		"recoil": v.recoil,
		"dt": v.dt,
	}
	for a in v.crew.actors(v.kit.spec(v.variant), info):
		TankCrew.draw_actor(ci, v.kit, a, o)
	_plaques(ci, v, state, o)
	if state.hull.breakdown:
		for room: Dictionary in v.kit.rooms(v.variant):
			var r := TankKit.rect_of(room)
			ci.draw_rect(Rect2(o + r.position, r.size), Color(0, 0, 0, 0.45))


## The barrel (drawn behind the hull art; it pivots at the turret's front), mirrored and foreshortened
## through a traverse.
static func _barrel(ci: CanvasItem, v: TankView, tv: Dictionary) -> void:
	var tex: Texture2D = tv.get("barrel", null)
	if tex == null:
		return
	var piv := v.barrel_pivot()
	var ang := v.barrel_angle()
	var sx := v.barrel_dir
	var xf := Transform2D(ang * signf(sx) if sx != 0.0 else 0.0, piv)
	xf = xf.scaled_local(Vector2(sx if absf(sx) > 0.05 else 0.05, 1.0))
	ci.draw_set_transform_matrix(xf)
	var off: Vector2 = tv["barrel_off"] + Vector2(-v.recoil * 4.0, 0)
	ci.draw_texture(tex, off)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Wheels: a rim highlight turning with the distance driven, the sprocket's teeth, the lower track
## run creeping backwards.
static func _running_gear(ci: CanvasItem, v: TankView, o: Vector2) -> void:
	var anchors: Dictionary = v.kit.spec(v.variant).get("anchors", {})
	var rw: Dictionary = anchors.get("road_wheel_line", {})
	if rw.is_empty():
		return
	var travel := (v.cam_x + float(TankConst.REAR_SCREEN_X)) * TankView.S
	var ang := travel / float(rw.get("wheel_radius", 8))
	var y := float(rw["y"])
	for cx: float in rw.get("wheel_centres_x", []):
		for k in 2:
			var a := ang + PI * k + cx * 0.1
			var p := o + Vector2(cx, y) + Vector2(cos(a), sin(a)) * 5.0
			ci.draw_rect(Rect2(p.round(), Vector2(1, 1)), Color(0.62, 0.5, 0.36, 0.9))
	var sp := TankKit.vec(anchors.get("drive_sprocket_centre", [0, 0]))
	for k2 in 4:
		var a2 := ang * 0.43 + TAU * k2 / 4.0
		var p2 := o + sp + Vector2(cos(a2), sin(a2)) * 12.0
		ci.draw_rect(Rect2(p2.round(), Vector2(2, 2)), Color(0.55, 0.44, 0.3, 0.9))
	var gy := float(rw["ground_contact_y"]) - 4.0
	var x0 := float(rw["x_from"]) - 6.0
	var x1 := float(rw["x_to"]) + 6.0
	var x := x0 + 6.0 - fposmod(travel, 6.0)
	while x < x1:
		ci.draw_rect(
			Rect2((o + Vector2(x, gy)).round(), Vector2(2, 1)), Color(0.42, 0.34, 0.26, 0.55)
		)
		x += 6.0


## Where a room's plaque sits (variant px): under the room's icon_chip_at.
static func plaque_at(room: Dictionary) -> Vector2:
	return TankKit.vec(room["icon_chip_at"]).round() + Vector2(1, 3)


static func plaque_lamp(room: Dictionary) -> Vector2:
	return plaque_at(room) + Vector2(4.5, -2.0)


## The station plaques: a dark enamel plate in a brass rim with the engine's glyph, and above it a
## 3 x 2 px lamp in the rider's slot colour (lit while in band, a dull glass otherwise).
static func _plaques(ci: CanvasItem, v: TankView, state: TankState, o: Vector2) -> void:
	for room: Dictionary in v.kit.rooms(v.variant):
		if not room.has("icon_chip_at"):
			continue
		var eng := str(room["engine"])
		var r := v.rider_of(eng)
		var p := (o + plaque_at(room)).round()
		ci.draw_rect(Rect2(p, Vector2(9, 9)), PLAQUE)
		ci.draw_rect(Rect2(p, Vector2(9, 1)), PLAQUE_HI)
		ci.draw_rect(Rect2(p + Vector2(0, 1), Vector2(1, 8)), PLAQUE_SIDE)
		ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(7, 7)), ENAMEL)
		var glyph := "bulwark" if v.variant == "tank_1rider" else eng
		var rows: Array = GLYPHS.get(glyph, [])
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "#":
					ci.draw_rect(Rect2(p + Vector2(1 + x, 1 + y), Vector2(1, 1)), ENGRAVE)
		var lp := (o + plaque_lamp(room)).floor() - Vector2(1, 0)
		ci.draw_rect(Rect2(lp - Vector2(1, 1), Vector2(5, 3)), BEZEL)
		var col := GLASS_OFF
		var lit := r != null and r.in_band and not state.hull.breakdown
		if r != null:
			col = slot_color(r) if lit else slot_color(r).darkened(0.65)
		ci.draw_rect(Rect2(lp, Vector2(3, 2)), col)
		if lit:
			ci.draw_rect(Rect2(lp + Vector2(1, 0), Vector2(1, 1)), col.lightened(0.5))


static func slot_color(r: TankRiderState) -> Color:
	return Wl.SLOT_COLORS[posmod(r.slot, Wl.SLOT_COLORS.size())]
