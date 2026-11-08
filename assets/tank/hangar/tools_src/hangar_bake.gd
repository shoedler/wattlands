extends SceneTree
## Bakes the Hangar's backdrop (docs/games/tank.md v1.1.0 "Hangar and Roll-out") into assets/tank/hangar/. All
## procedural, drawn on the pixel grid with the tank generators' helpers (assets/tank/v3/tools_src/px.gd): no fal, no
## source image. The picture is a night steel hangar in the forest's own cold greens and blues, unlit steel at the
## values the white ceiling bars light (TankHangar dims it with a dark overlay for the countdown):
##   room.png    480 x 440, tiling across: ceiling deck and girders, an overhead crane rail with a hook, pipes, a cable
##               tray, two high windows, corrugated back wall with a pilaster at each half, a hazard-striped base,
##               the concrete floor with its safety line. Stage y 0..440, the wall meets the floor at y 380.
##   end.png     130 x 440, the cut end wall the tank rolls out through: a section of thick wall with a doorway (the
##               void, 98 x 230, transparent), steel jambs, the door's housing over it, the floor slab under it.
##   door.png    18 x 230, the sliding door as it stands edge-on in the doorway: ribbed plates, hazard rim, two lamps.
##   gate.png    220 x 300 (stage y 100..400), the same doorway seen face on for the far panel: steel jambs, hazard
##               stripes, the housing over the opening (transparent 156 x 230) and the beacons' brackets.
##   shutter.png 32 x 8, one slat of the rolling shutter the far panel raises (tiled across the opening in code).
## Run: bash assets/tank/hangar/tools_src/hangar_bake.sh   Then: tools/godot.sh --headless --path . --import

const Px = preload("res://assets/tank/v3/tools_src/px.gd")

const OUT := "res://assets/tank/hangar/"
const ROOM_W := 480
const ROOM_H := 440
const FLOOR_Y := 380
const END_W := 130
const VOID_X0 := 16
const VOID_X1 := 114
const VOID_TOP := 150
const VOID_BOT := 380
const DOOR_W := 18
const GATE_W := 220
const GATE_H := 300
const GATE_Y0 := 100
const AP_X0 := 32
const AP_X1 := 188

const WALL := Color("#1d252b")
const WALL_HI := Color("#2b363d")
const WALL_LO := Color("#12181c")
const RIB_HI := Color("#35434b")
const RIVET := Color("#44545c")
const PIL := Color("#242e35")
const PIL_HI := Color("#3a4a53")
const PIL_LO := Color("#0e1316")
const DECK := Color("#0c1013")
const DECK_HI := Color("#1a2227")
const GIRDER := Color("#2a343a")
const GIRDER_HI := Color("#46565f")
const PIPE := Color("#2d3a40")
const PIPE_HI := Color("#4d616a")
const PIPE_LO := Color("#161d21")
const RUST := Color("#4a2c1a")
const HAZ_Y := Color("#9a7418")
const HAZ_K := Color("#0e1112")
const GLASS_TOP := Color("#0b1e2a")
const GLASS_LOW := Color("#14384a")
const MOON := Color("#4f8196")
const FLOOR := Color("#24292b")
const FLOOR_HI := Color("#39413f")
const FLOOR_LO := Color("#15191a")
const LINE_Y := Color("#80661a")
const CONC := Color("#222b2f")
const CONC_HI := Color("#34413f")
const CONC_LO := Color("#141a1d")
const LAMP_RED := Color("#d8352a")
const LAMP_AMB := Color("#e0a64a")


func _initialize() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	_room().save_png(dir + "room.png")
	_end().save_png(dir + "end.png")
	_door().save_png(dir + "door.png")
	_gate().save_png(dir + "gate.png")
	_shutter().save_png(dir + "shutter.png")
	print("hangar_bake: room, end, door, gate, shutter -> ", OUT)
	quit(0)


# --- Shared pieces ---------------------------------------------------------------------------------------


static func _noisy(c: Color, x: int, y: int, amp: float, s: int = 0) -> Color:
	var n := (Px.h2(x, y, s) - 0.5) * amp
	return Color(clampf(c.r + n, 0.0, 1.0), clampf(c.g + n, 0.0, 1.0), clampf(c.b + n, 0.0, 1.0), c.a)


## A hazard-striped box: diagonal bars of HAZ_Y and HAZ_K, `step` px a stripe, a dark outline.
static func _hazard(img: Image, r: Rect2i, step: int = 6) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var k := ((x + y) / step) % 2
			var c := HAZ_Y if k == 0 else HAZ_K
			Px.put(img, x, y, _noisy(c, x, y, 0.04, 3))
	Px.rect(img, Rect2i(r.position.x, r.position.y, r.size.x, 1), HAZ_K)
	Px.rect(img, Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), HAZ_K)


static func _rivet(img: Image, x: int, y: int, c: Color = RIVET) -> void:
	Px.put(img, x, y, c)
	Px.put(img, x + 1, y + 1, c.darkened(0.45))


## A steel plate with a lit top and left edge, a dark bottom and right, and a rivet in each corner.
static func _plate(img: Image, r: Rect2i, base: Color, rivets: bool = true) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			Px.put(img, x, y, _noisy(base, x, y, 0.035, 5))
	Px.rect(img, Rect2i(r.position.x, r.position.y, r.size.x, 1), base.lightened(0.28))
	Px.rect(img, Rect2i(r.position.x, r.position.y, 1, r.size.y), base.lightened(0.18))
	Px.rect(img, Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), base.darkened(0.5))
	Px.rect(img, Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), base.darkened(0.4))
	if rivets and r.size.x > 8 and r.size.y > 8:
		for p: Vector2i in [
			Vector2i(r.position.x + 2, r.position.y + 2),
			Vector2i(r.end.x - 4, r.position.y + 2),
			Vector2i(r.position.x + 2, r.end.y - 4),
			Vector2i(r.end.x - 4, r.end.y - 4)
		]:
			_rivet(img, p.x, p.y)


## A round lamp: a dark housing ring, a bright core.
static func _lamp(img: Image, c: Vector2i, r: int, core: Color) -> void:
	for y in range(-r - 1, r + 2):
		for x in range(-r - 1, r + 2):
			var d := Vector2(x, y).length()
			if d <= float(r) + 0.5:
				var k := clampf(1.0 - d / float(r), 0.0, 1.0)
				Px.put(img, c.x + x, c.y + y, core.lerp(Color.WHITE, k * 0.55))
			elif d <= float(r) + 1.6:
				Px.put(img, c.x + x, c.y + y, HAZ_K)


# --- room.png ------------------------------------------------------------------------------------------------


func _room() -> Image:
	var img := Px.blank(ROOM_W, ROOM_H)
	_room_wall(img)
	_room_ceiling(img)
	_room_pilasters(img)
	_room_windows(img)
	_room_pipes(img)
	_room_crane(img)
	_room_floor(img)
	return img


func _room_wall(img: Image) -> void:
	for y in range(0, FLOOR_Y):
		for x in ROOM_W:
			var c := WALL
			var m := x % 8
			if m == 0:
				c = RIB_HI
			elif m == 1:
				c = WALL_LO
			elif m == 5:
				c = WALL_HI
			# the panels darken toward their bottom edge, the light being up in the roof
			var k := float(y) / float(FLOOR_Y)
			c = c.darkened(k * 0.25)
			# a big soft stain of damp here and there
			var n := Px.vnoise(float(x), float(y), 46.0, 11)
			c = c.darkened(clampf(n - 0.55, 0.0, 0.45) * 0.5)
			Px.put(img, x, y, _noisy(c, x, y, 0.02, 2))
	# panel seams every 120 px and the two stiffening bands, riveted
	for sx in range(0, ROOM_W, 120):
		Px.rect(img, Rect2i(sx, 56, 2, FLOOR_Y - 56), WALL_LO)
		Px.rect(img, Rect2i(sx + 2, 56, 1, FLOOR_Y - 56), RIB_HI)
		for ry in range(60, FLOOR_Y - 6, 14):
			_rivet(img, sx + 4, ry)
	for by: int in [150, 296]:
		Px.rect(img, Rect2i(0, by, ROOM_W, 6), GIRDER)
		Px.rect(img, Rect2i(0, by, ROOM_W, 1), GIRDER_HI)
		Px.rect(img, Rect2i(0, by + 5, ROOM_W, 1), PIL_LO)
		for rx in range(3, ROOM_W, 16):
			_rivet(img, rx, by + 2)
	# rust runs under the bands
	for rx in range(0, ROOM_W, 5):
		var h := Px.h2(rx, 77, 6)
		if h > 0.72:
			var run := 4 + int(h * 18.0)
			for ry in run:
				Px.mix(img, rx, 156 + ry, RUST, 0.5 * (1.0 - float(ry) / float(run)))


func _room_ceiling(img: Image) -> void:
	for y in range(0, 44):
		for x in ROOM_W:
			var c := DECK
			if x % 40 == 0 or y % 22 == 0:
				c = DECK_HI.darkened(0.2)
			Px.put(img, x, y, _noisy(c, x, y, 0.025, 4))
	for rx in range(4, ROOM_W, 40):
		for ry: int in [4, 26]:
			_rivet(img, rx, ry, DECK_HI)
	# the girder under the deck, braced between the pilasters
	Px.rect(img, Rect2i(0, 44, ROOM_W, 12), GIRDER.darkened(0.25))
	Px.rect(img, Rect2i(0, 44, ROOM_W, 2), GIRDER_HI)
	Px.rect(img, Rect2i(0, 54, ROOM_W, 2), PIL_LO)
	for bx in range(0, ROOM_W, 40):
		Px.linef(img, Vector2(bx, 46), Vector2(bx + 40, 54), GIRDER.lightened(0.15))
		Px.linef(img, Vector2(bx + 40, 46), Vector2(bx, 54), GIRDER.lightened(0.05))
	for rx in range(2, ROOM_W, 20):
		_rivet(img, rx, 46, GIRDER_HI)
	# the eaves' shadow on the wall just below
	for y in range(56, 74):
		var a := 0.4 * (1.0 - float(y - 56) / 18.0)
		for x in ROOM_W:
			Px.mix(img, x, y, PIL_LO, a)


func _room_pilasters(img: Image) -> void:
	for px0: int in [0, 240]:
		for y in range(56, FLOOR_Y):
			for x in range(px0, px0 + 22):
				var c := PIL
				var d := x - px0
				if d < 2:
					c = PIL_HI
				elif d > 19:
					c = PIL_LO
				elif d == 10:
					c = PIL.darkened(0.15)
				Px.put(img, x, y, _noisy(c, x, y, 0.025, 8))
		for ry in range(62, FLOOR_Y - 18, 16):
			_rivet(img, px0 + 4, ry, PIL_HI)
			_rivet(img, px0 + 15, ry, PIL_HI)
		# the base is painted with hazard stripes up to a tank's wheel height
		_hazard(img, Rect2i(px0, FLOOR_Y - 22, 22, 22), 5)


func _room_windows(img: Image) -> void:
	for wx: int in [118, 362]:
		var r := Rect2i(wx, 92, 56, 40)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var t := float(y - r.position.y) / float(r.size.y)
				var c := GLASS_TOP.lerp(GLASS_LOW, t)
				# the moon's streaks across the glass
				var s := fposmod(float(x - r.position.x) * 0.9 + float(y - r.position.y) * 1.4, 26.0)
				if s < 3.0:
					c = c.lerp(MOON, 0.18 * (1.0 - t * 0.5))
				Px.put(img, x, y, _noisy(c, x, y, 0.02, 9))
		# frame, mullions, sill
		Px.rect(img, Rect2i(r.position.x - 2, r.position.y - 2, r.size.x + 4, 2), GIRDER_HI)
		Px.rect(img, Rect2i(r.position.x - 2, r.end.y, r.size.x + 4, 3), GIRDER)
		Px.rect(img, Rect2i(r.position.x - 2, r.position.y, 2, r.size.y), GIRDER)
		Px.rect(img, Rect2i(r.end.x, r.position.y, 2, r.size.y), PIL_LO)
		Px.rect(img, Rect2i(r.position.x + r.size.x / 2 - 1, r.position.y, 2, r.size.y), GIRDER)
		Px.rect(img, Rect2i(r.position.x, r.position.y + r.size.y / 2, r.size.x, 2), GIRDER)
		# moonlight leaning down the wall
		for y in range(r.end.y + 3, r.end.y + 40):
			var a := 0.1 * (1.0 - float(y - r.end.y) / 40.0)
			for x in range(r.position.x + 4, r.end.x - 4):
				Px.add(img, x + (y - r.end.y) / 3, y, MOON, a)


func _room_pipes(img: Image) -> void:
	# the long run under the girder, with flanges and brackets
	for x in ROOM_W:
		for y in range(64, 71):
			var k := float(y - 64) / 6.0
			var c := PIPE_HI if k < 0.2 else (PIPE if k < 0.7 else PIPE_LO)
			Px.put(img, x, y, c)
	for fx in range(18, ROOM_W, 80):
		Px.rect(img, Rect2i(fx, 62, 5, 11), PIPE.lightened(0.15))
		Px.rect(img, Rect2i(fx, 62, 5, 1), PIPE_HI)
		Px.rect(img, Rect2i(fx + 4, 62, 1, 11), PIPE_LO)
		Px.rect(img, Rect2i(fx + 1, 56, 2, 6), GIRDER)
	# a second, thin run with a valve and a drop
	Px.rect(img, Rect2i(0, 78, ROOM_W, 3), PIPE)
	Px.rect(img, Rect2i(0, 78, ROOM_W, 1), PIPE_HI)
	Px.rect(img, Rect2i(300, 78, 5, 70), PIPE)
	Px.rect(img, Rect2i(300, 78, 1, 70), PIPE_HI)
	Px.rect(img, Rect2i(297, 108, 11, 4), PIPE.lightened(0.2))
	for a in 8:
		var an := float(a) * TAU / 8.0
		Px.linef(img, Vector2(302.0, 110.0), Vector2(302.0 + cos(an) * 6.0, 110.0 + sin(an) * 6.0), PIPE_HI)
	# a cable tray: two rails and rungs
	Px.rect(img, Rect2i(0, 86, ROOM_W, 1), GIRDER_HI)
	Px.rect(img, Rect2i(0, 92, ROOM_W, 1), PIL_LO)
	for rx in range(0, ROOM_W, 6):
		Px.rect(img, Rect2i(rx, 87, 1, 5), PIPE_LO)


func _room_crane(img: Image) -> void:
	# an overhead crane's rail under the girder, a trolley and a chain with a hook hanging over the bay
	Px.rect(img, Rect2i(0, 98, ROOM_W, 5), GIRDER)
	Px.rect(img, Rect2i(0, 98, ROOM_W, 1), GIRDER_HI)
	Px.rect(img, Rect2i(0, 102, ROOM_W, 1), PIL_LO)
	var tx := 180
	_plate(img, Rect2i(tx, 92, 30, 14), PIL, true)
	Px.rect(img, Rect2i(tx + 3, 106, 5, 3), GIRDER_HI)
	Px.rect(img, Rect2i(tx + 22, 106, 5, 3), GIRDER_HI)
	_plate(img, Rect2i(tx + 8, 106, 14, 10), GIRDER, false)
	for k in 14:
		var ly := 116 + k * 4
		var c := PIPE_HI if k % 2 == 0 else PIPE
		Px.rect(img, Rect2i(tx + 14, ly, 3, 3), c)
		Px.rect(img, Rect2i(tx + 15, ly + 1, 1, 1), PIPE_LO)
	Px.rect(img, Rect2i(tx + 9, 172, 13, 5), GIRDER)
	Px.rect(img, Rect2i(tx + 9, 172, 13, 1), GIRDER_HI)
	for hy in range(177, 188):
		var u := float(hy - 177) / 11.0
		var half := int(5.0 * sin(u * PI * 0.9 + 0.2))
		Px.rect(img, Rect2i(tx + 15 - half, hy, 2 * half + 2, 1), PIPE_HI if hy % 2 == 0 else PIPE)


func _room_floor(img: Image) -> void:
	for y in range(FLOOR_Y, ROOM_H):
		for x in ROOM_W:
			var t := float(y - FLOOR_Y) / float(ROOM_H - FLOOR_Y)
			var c := FLOOR.lerp(FLOOR_LO, t * 0.8)
			var n := Px.vnoise(float(x), float(y), 30.0, 14)
			c = c.lerp(FLOOR_LO, clampf(n - 0.45, 0.0, 0.5))
			Px.put(img, x, y, _noisy(c, x, y, 0.03, 12))
	# the wall's foot: a lit edge and a dark skirting
	Px.rect(img, Rect2i(0, FLOOR_Y, ROOM_W, 1), FLOOR_HI)
	Px.rect(img, Rect2i(0, FLOOR_Y + 1, ROOM_W, 1), FLOOR_HI.darkened(0.3))
	# expansion joints, the dashed safety line, and the oil
	for jx in range(0, ROOM_W, 120):
		Px.rect(img, Rect2i(jx, FLOOR_Y + 2, 2, ROOM_H - FLOOR_Y - 2), FLOOR_LO)
		Px.rect(img, Rect2i(jx + 2, FLOOR_Y + 2, 1, ROOM_H - FLOOR_Y - 2), FLOOR_HI.darkened(0.2))
	for dx in range(0, ROOM_W, 24):
		Px.rect(img, Rect2i(dx, 417, 14, 3), LINE_Y)
		Px.rect(img, Rect2i(dx, 417, 14, 1), LINE_Y.lightened(0.2))
	for blot: Vector2 in [Vector2(70, 396), Vector2(310, 406), Vector2(420, 392)]:
		for y in range(-5, 6):
			for x in range(-16, 17):
				var d := Vector2(float(x) / 16.0, float(y) / 5.0).length()
				if d < 1.0 and Px.h2(int(blot.x) + x, int(blot.y) + y, 15) > 0.15 * d:
					Px.mix(img, int(blot.x) + x, int(blot.y) + y, PIL_LO, 0.55 * (1.0 - d))
	# a floor drain
	_plate(img, Rect2i(214, 398, 26, 10), FLOOR_LO, false)
	for gx in range(216, 238, 3):
		Px.rect(img, Rect2i(gx, 400, 1, 6), Color.BLACK)


# --- end.png ---------------------------------------------------------------------------------------------------


func _end() -> Image:
	var img := Px.blank(END_W, ROOM_H)
	# the wall in section: concrete with a diagonal hatch, so it reads as cut open
	for y in ROOM_H:
		for x in END_W:
			var c := CONC
			if (x + y) % 9 == 0:
				c = CONC_HI.darkened(0.25)
			var t := float(y) / float(ROOM_H)
			c = c.darkened(t * 0.3)
			Px.put(img, x, y, _noisy(c, x, y, 0.03, 21))
	# the hole: the doorway through the wall, clear
	var hole := Rect2i(VOID_X0, VOID_TOP, VOID_X1 - VOID_X0, VOID_BOT - VOID_TOP)
	for y in range(hole.position.y, hole.end.y):
		for x in range(hole.position.x, hole.end.x):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	# steel jambs on both sides of the void and the lintel plate over it, with their rivets
	for jx: int in [VOID_X0 - 6, VOID_X1]:
		_plate(img, Rect2i(jx, VOID_TOP - 6, 6, VOID_BOT - VOID_TOP + 6), GIRDER, false)
		for ry in range(VOID_TOP, VOID_BOT - 6, 12):
			_rivet(img, jx + 2, ry, GIRDER_HI)
	_plate(img, Rect2i(VOID_X0 - 6, VOID_TOP - 8, VOID_X1 - VOID_X0 + 12, 8), GIRDER, true)
	# the door's housing above, a box with a hazard front and a lamp each end
	_plate(img, Rect2i(VOID_X0 - 6, 84, VOID_X1 - VOID_X0 + 12, 58), PIL, true)
	_hazard(img, Rect2i(VOID_X0 - 2, 122, VOID_X1 - VOID_X0 + 4, 12), 6)
	_lamp(img, Vector2i(VOID_X0 + 6, 104), 4, LAMP_AMB.darkened(0.3))
	_lamp(img, Vector2i(VOID_X1 - 6, 104), 4, LAMP_AMB.darkened(0.3))
	for gx in range(VOID_X0 + 18, VOID_X1 - 14, 6):
		Px.rect(img, Rect2i(gx, 100, 3, 18), PIL_LO)
	# the section's left face: a steel edge pilaster, riveted and striped at its foot
	Px.rect(img, Rect2i(0, 0, 8, ROOM_H), PIL)
	Px.rect(img, Rect2i(0, 0, 2, ROOM_H), PIL_HI)
	Px.rect(img, Rect2i(7, 0, 1, ROOM_H), PIL_LO)
	for ry in range(4, 372, 16):
		_rivet(img, 3, ry, PIL_HI)
	_hazard(img, Rect2i(0, FLOOR_Y - 22, 8, 22), 5)
	# the floor slab through the doorway and the wall's lit top edge
	Px.rect(img, Rect2i(0, VOID_BOT, END_W, 3), FLOOR_HI)
	Px.rect(img, Rect2i(VOID_X0, VOID_BOT + 3, VOID_X1 - VOID_X0, 1), FLOOR_HI.darkened(0.3))
	Px.rect(img, Rect2i(0, 0, END_W, 2), CONC_HI)
	# the right edge, where the wall ends and the outdoors begins
	Px.rect(img, Rect2i(END_W - 4, 0, 4, ROOM_H), PIL)
	Px.rect(img, Rect2i(END_W - 4, 0, 1, ROOM_H), PIL_HI)
	Px.rect(img, Rect2i(END_W - 1, 0, 1, ROOM_H), PIL_LO)
	return img


# --- door.png ------------------------------------------------------------------------------------------------


func _door() -> Image:
	var h := VOID_BOT - VOID_TOP
	var img := Px.blank(DOOR_W, h)
	for y in h:
		for x in DOOR_W:
			var c := PIL.lightened(0.06)
			if y % 10 == 0:
				c = PIL_LO
			elif y % 10 == 1:
				c = PIL_HI
			if x < 2:
				c = PIL_HI
			elif x > DOOR_W - 3:
				c = PIL_LO
			Px.put(img, x, y, _noisy(c, x, y, 0.03, 31))
	for ry in range(5, h - 4, 20):
		_rivet(img, 3, ry, PIL_HI)
		_rivet(img, DOOR_W - 6, ry, PIL_HI)
	# the lower third is hazard-striped, a lamp near the top and one near the foot
	_hazard(img, Rect2i(0, h - 40, DOOR_W, 40), 6)
	Px.rect(img, Rect2i(0, h - 3, DOOR_W, 3), GIRDER_HI)
	_lamp(img, Vector2i(DOOR_W / 2, 20), 3, LAMP_AMB.darkened(0.25))
	_lamp(img, Vector2i(DOOR_W / 2, h - 50), 3, LAMP_RED.darkened(0.2))
	return img


# --- gate.png ------------------------------------------------------------------------------------------------


func _gate() -> Image:
	var img := Px.blank(GATE_W, GATE_H)
	# the wall face around the opening: the room's own steel
	for y in GATE_H:
		for x in GATE_W:
			var c := WALL
			var m := x % 8
			if m == 0:
				c = RIB_HI
			elif m == 1:
				c = WALL_LO
			c = c.darkened(float(y) / float(GATE_H) * 0.2)
			Px.put(img, x, y, _noisy(c, x, y, 0.02, 41))
	var ap_top := VOID_TOP - GATE_Y0
	var ap_h := VOID_BOT - VOID_TOP
	for y in range(ap_top, ap_top + ap_h):
		for x in range(AP_X0, AP_X1):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	# jambs: steel with riveted edges and hazard stripes on the inner side
	_plate(img, Rect2i(AP_X0 - 14, 0, 14, GATE_H), GIRDER, true)
	_plate(img, Rect2i(AP_X1, 0, 14, GATE_H), GIRDER, true)
	_hazard(img, Rect2i(AP_X0 - 6, ap_top, 6, ap_h), 6)
	_hazard(img, Rect2i(AP_X1, ap_top, 6, ap_h), 6)
	# the outer pilasters
	for px0: int in [0, GATE_W - 12]:
		_plate(img, Rect2i(px0, 0, 12, GATE_H), PIL, true)
	# the housing over the opening: a box with a hazard front and a lamp at each end
	_plate(img, Rect2i(AP_X0 - 14, 14, AP_X1 - AP_X0 + 28, ap_top - 14), PIL, true)
	_hazard(img, Rect2i(AP_X0 - 6, ap_top - 12, AP_X1 - AP_X0 + 12, 12), 6)
	_lamp(img, Vector2i(AP_X0 + 8, ap_top - 26), 5, LAMP_AMB.darkened(0.3))
	_lamp(img, Vector2i(AP_X1 - 8, ap_top - 26), 5, LAMP_AMB.darkened(0.3))
	for gx in range(AP_X0 + 26, AP_X1 - 22, 7):
		Px.rect(img, Rect2i(gx, ap_top - 40, 3, 20), PIL_LO)
	# a ledge for each beacon, high on the wall
	for bx: int in [AP_X0 - 20, AP_X1 + 20]:
		_plate(img, Rect2i(bx - 8, 24, 16, 6), GIRDER, false)
	# the floor under the opening
	Px.rect(img, Rect2i(AP_X0, ap_top + ap_h, AP_X1 - AP_X0, GATE_H - ap_top - ap_h), FLOOR)
	Px.rect(img, Rect2i(AP_X0, ap_top + ap_h, AP_X1 - AP_X0, 2), FLOOR_HI)
	return img


# --- shutter.png --------------------------------------------------------------------------------------------


func _shutter() -> Image:
	var img := Px.blank(32, 8)
	for y in 8:
		for x in 32:
			var c := PIL.lightened(0.04)
			if y == 0:
				c = PIL_HI
			elif y == 7:
				c = PIL_LO
			elif y == 6:
				c = PIL.darkened(0.2)
			Px.put(img, x, y, _noisy(c, x, y, 0.03, 51))
	for rx in [3, 19]:
		_rivet(img, rx, 3, PIL_HI)
	return img
