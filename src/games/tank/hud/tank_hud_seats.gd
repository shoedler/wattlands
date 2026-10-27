class_name TankHudSeats
extends TankHudCtl
## MOCK (Diesel Domestiques v3, HUD: spec item 5). Not for merging as is.
##
## The seat panel for the one 5-seat tank: Drive (diesel), Gun (dynamo), Loader (steam), Lights
## (arc) and Secondaries (a crank-driven twin belt feed). Who sits where in slot colours, empty
## seats dark, your seat marked (bright frame, YOU tab), the 60 s switch lock as a small timer on
## your seat, and the switch hint ("< > move  OK sit") once the lock is off. Two layouts:
##   A  "seat row": replaces the v2 crew row. Five seat cards, each a live machine window (the v2
##      engine windows; the belt feed is new), empty seats shown dark and cold. Loader and Gun
##      carry the ready rack's three shell pips, the Secondaries its rounds a minute (2 x cadence).
##   B  "seat board": a compact board of five sockets docked on top of my numbers; the v2 crew row
##      of engine windows stays as it is (one card per rider).
## Seats come from state.stations (diesel/bulwark -> Drive, dynamo -> Gun, steam -> Loader, arc ->
## Lights) unless TANK_V3_SEATS overrides them ("<slot per seat>", -1 empty, in seat order, e.g.
## "0,1,-1,-1,2"). TANK_V3_LOCK=<s> sets your lock's seconds left (default: a cycle on sim time),
## TANK_V3_RACK=<0..3> the ready rack. TANK_V3_HUD=A|B picks the layout (TankHud.spec).

const SEATS: Array[Dictionary] = [
	{"id": "drive", "label": "DRIVE", "short": "DRV", "mech": "diesel", "icon": "diesel"},
	{"id": "gun", "label": "GUN", "short": "GUN", "mech": "dynamo", "icon": "dynamo"},
	{"id": "loader", "label": "LOADER", "short": "LDR", "mech": "steam", "icon": "steam"},
	{"id": "lights", "label": "LIGHTS", "short": "LGT", "mech": "arc", "icon": "arc"},
	{"id": "secondaries", "label": "SECONDARY", "short": "SEC", "mech": "feed", "icon": "feed"},
]
const ENGINE_SEAT := {"diesel": 0, "bulwark": 0, "dynamo": 1, "steam": 2, "arc": 3}
const LOCK_S := 60.0
## Layout A: the cards (art px), docked GAP after my numbers like the v2 crew row.
const CARD_W := 100
const CARD_H := 90
const GAP := 5
const FRAME_Y := 4
const WIN := Vector2i(TankMech.W, TankMech.H)
## Layout B: the board (art px of its own rect).
const BOARD := Vector2i(222, 38)
const SOCK := Vector2i(41, 21)
const FEED_ICON := ["..#.#..", ".##.##.", ".##.##.", ".##.##.", ".##.##.", ".......", "#######"]
const LOCK_ICON := [".###.", "#...#", "#####", "##.##", "#####"]
const SHELL := [".#.", "###", "###", "###", "###", "###", "###"]
const COLD := Color("#d6ecff")

## "A" or "B".
var layout: String = "A"
var seats: Array = []
var lock_left: float = 0.0
var rack: int = 2
var _img: Dictionary = {}
var _tex: Dictionary = {}
var _phase: Dictionary = {}
var _wall: float = 0.0


func tick(delta: float) -> void:
	_wall += delta
	for s: Dictionary in seats:
		var key := str(s["id"])
		_phase[key] = float(_phase.get(key, 0.0)) + float(s.get("cad", 0.0)) / 60.0 * delta


## Slot per seat (-1 empty): TANK_V3_SEATS, else from the stations.
static func seat_slots(state: TankState) -> Array[int]:
	var out: Array[int] = [-1, -1, -1, -1, -1]
	var env := OS.get_environment("TANK_V3_SEATS")
	if env != "":
		var parts := env.split(",")
		for i in mini(parts.size(), 5):
			out[i] = int(parts[i])
		return out
	for st in state.stations:
		if ENGINE_SEAT.has(st.engine) and st.slot >= 0:
			out[int(ENGINE_SEAT[st.engine])] = st.slot
	return out


## The seat a slot sits in (-1 none).
static func seat_of(state: TankState, slot: int) -> int:
	var ss := seat_slots(state)
	return ss.find(slot)


## The ready rack (0..3): TANK_V3_RACK, else 2.
static func rack_of(_state: TankState) -> int:
	var e := OS.get_environment("TANK_V3_RACK")
	return clampi(int(e), 0, 3) if e.is_valid_int() else 2


## The secondaries' rider's cadence (0 when the seat is empty).
static func secondaries_cad(state: TankState) -> float:
	var slot := seat_slots(state)[4]
	var r := state.rider_at(slot) if slot >= 0 else null
	return r.cadence_rpm if r != null else 0.0


func refresh() -> void:
	var s := st()
	var ss := seat_slots(s)
	var me := local_rider()
	seats = []
	for i in SEATS.size():
		var d: Dictionary = SEATS[i].duplicate()
		d["slot"] = ss[i]
		var r := s.rider_at(ss[i]) if ss[i] >= 0 else null
		d["empty"] = r == null
		if r != null:
			var is_local := me != null and r.peer == me.peer
			var w := r.raw_w
			var cad := r.cadence_rpm
			if is_local and tm != null:
				w = tm.power_w
				cad = tm.cadence_rpm
			var ratio := TankHudModel.power_ratio(r, w)
			d["name"] = rider_name(r)
			d["w"] = w
			d["cad"] = cad
			d["ratio"] = ratio
			d["state"] = TankHudModel.band_state(r.in_band, ratio)
			d["local"] = is_local
		else:
			d["cad"] = 0.0
			d["ratio"] = 0.0
			d["local"] = false
		d["phase"] = float(_phase.get(str(d["id"]), 0.0))
		seats.append(d)
		if layout == "A":
			_paint_window(d)
	var e := OS.get_environment("TANK_V3_LOCK")
	if e.is_valid_float():
		lock_left = clampf(float(e), 0.0, LOCK_S)
	else:
		lock_left = maxf(LOCK_S - fposmod(s.t + 20.0, 90.0), 0.0)
	rack = rack_of(s)


# --- Machine windows (layout A) ------------------------------------------------------------------------------


func _paint_window(d: Dictionary) -> void:
	var key := str(d["id"])
	if not _img.has(key):
		_img[key] = Image.create_empty(WIN.x, WIN.y, false, Image.FORMAT_RGBA8)
	var img: Image = _img[key]
	var empty := bool(d["empty"])
	var power := 0.0 if empty else float(d["ratio"])
	var col := slot_color(int(d["slot"])) if not empty else Color(0.3, 0.3, 0.3)
	if str(d["mech"]) == "feed":
		paint_feed(img, float(d["phase"]), power, _wall, col)
	else:
		TankMech.paint_ex(img, str(d["mech"]), float(d["phase"]), power, _wall, col, d["cad"])
	if empty:
		# a dark, cold room: the machine at rest, no lamp
		for y in WIN.y:
			for x in WIN.x:
				var c := img.get_pixel(x, y)
				var l := c.get_luminance() * 0.3
				img.set_pixel(x, y, Color(l * 0.8, l * 0.95, l * 1.1))
	if not _tex.has(key):
		_tex[key] = ImageTexture.create_from_image(img)
	else:
		(_tex[key] as ImageTexture).update(img)


## The Secondaries' machine (new, a mock painter in the v2 engine windows' palette): a riveted
## room, a crank flywheel turning with the rider's crank and a connecting rod cycling the twin
## bolts (2 rounds a revolution), two linked brass cartridge belts climbing from their ammo boxes
## into the feed tray, a round counter, the room lamp's warm pool in the slot colour while manned,
## and the bolts' flash at the wall.
static func paint_feed(img: Image, phase: float, power: float, t: float, slot: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var lit := clampf(power, 0.0, 1.2)
	# room: dark plates with seams and rivets
	img.fill(TankMech.WALL_DK)
	for y in range(0, h - 6):
		for x in w:
			var c := TankMech.WALL
			if y % 21 == 0 or x % 37 == 0:
				c = TankMech.SOOT
			elif y % 21 == 1 or x % 37 == 1:
				c = TankMech.WALL_LT
			elif (y % 21 == 3 or y % 21 == 18) and x % 6 == 3:
				c = TankMech.IRON[3]
			img.set_pixel(x, y, c)
	img.fill_rect(Rect2i(0, h - 6, w, 6), TankMech.IRON[0])
	img.fill_rect(Rect2i(0, h - 6, w, 1), TankMech.IRON[2])
	# ammo boxes
	for bx: int in [56, 82]:
		img.fill_rect(Rect2i(bx, h - 19, 22, 13), TankMech.OLIVE[1])
		img.fill_rect(Rect2i(bx, h - 19, 22, 1), TankMech.OLIVE[3])
		img.fill_rect(Rect2i(bx, h - 7, 22, 1), TankMech.OLIVE[0])
		img.fill_rect(Rect2i(bx + 9, h - 15, 4, 2), TankMech.STEEL[2])
	# the feed tray and the twin breeches through the wall
	img.fill_rect(Rect2i(52, 5, 60, 10), TankMech.STEEL[1])
	img.fill_rect(Rect2i(52, 5, 60, 1), TankMech.STEEL[3])
	img.fill_rect(Rect2i(52, 14, 60, 1), TankMech.STEEL[0])
	for gy: int in [7, 11]:
		img.fill_rect(Rect2i(94, gy, 18, 2), TankMech.IRON[1])
		img.fill_rect(Rect2i(94, gy, 18, 1), TankMech.IRON[3])
	# the bolts: they slide back and forth twice a revolution
	var bolt := int(roundf(3.0 * (0.5 + 0.5 * cos(phase * TAU * 2.0))))
	for gy: int in [7, 11]:
		img.fill_rect(Rect2i(84 + bolt, gy, 8, 2), TankMech.BRASS[2])
	# two linked belts: cartridges every 4 px, moving 2 rounds per revolution
	var shift := fposmod(phase * 8.0, 4.0)
	for k in 2:
		var x0 := 63 + k * 26
		var y := float(h - 20)
		while y > 14.0:
			var yy := int(roundf(y - shift))
			if yy > 14 and yy < h - 20:
				var xx := x0 + int((float(h - 20) - y) * 0.22)
				img.fill_rect(Rect2i(xx - 1, yy, 7, 3), TankMech.IRON[0])
				img.fill_rect(Rect2i(xx, yy, 5, 2), TankMech.BRASS[2])
				img.set_pixel(xx, yy, TankMech.BRASS[4])
				img.set_pixel(xx + 5, yy, TankMech.COPPER[2])
				img.set_pixel(xx + 5, yy + 1, TankMech.COPPER[1])
			y -= 4.0
	# the crank flywheel and the rod to the bolts
	var c := Vector2(24, 38)
	var r := 15.0
	for y in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			var d := Vector2(x, y).distance_to(c)
			if d <= r and d > r - 3.0:
				var up := y < c.y - 3
				img.set_pixel(x, y, TankMech.IRON[3] if up else TankMech.IRON[1])
				if d > r - 1.0 and up:
					img.set_pixel(x, y, TankMech.IRON[4])
			elif d <= 4.0:
				img.set_pixel(x, y, TankMech.BRASS[1] if d > 2.5 else TankMech.BRASS[3])
	var a := phase * TAU
	for s in 5:
		var dir := Vector2.from_angle(a + s * TAU / 5.0)
		for k in range(4, int(r) - 2):
			var p := (c + dir * k).round()
			img.set_pixel(int(p.x), int(p.y), TankMech.IRON[2])
	var pin := (c + Vector2.from_angle(a) * (r - 5.0)).round()
	var rod_end := Vector2(84 + bolt, 13)
	var n := int(pin.distance_to(rod_end))
	for i in n:
		var p2 := pin.lerp(rod_end, float(i) / maxf(n, 1)).round()
		img.set_pixel(int(p2.x), int(p2.y), TankMech.STEEL[3])
		img.set_pixel(int(p2.x), int(p2.y) + 1, TankMech.STEEL[1])
	img.fill_rect(Rect2i(int(pin.x) - 1, int(pin.y) - 1, 3, 3), TankMech.BRASS[3])
	# the round counter (three drums)
	img.fill_rect(Rect2i(6, 6, 22, 11), TankMech.IRON[0])
	img.fill_rect(Rect2i(6, 6, 22, 1), TankMech.IRON[2])
	for i in 3:
		img.fill_rect(Rect2i(9 + i * 6, 8, 5, 7), TankMech.PAPER.darkened(0.15 * float(i)))
		var dg := int(fposmod(phase * 2.0 / pow(10.0, 2 - i), 10.0))
		img.fill_rect(Rect2i(10 + i * 6, 9 + dg % 4, 3, 1), TankMech.NEEDLE)
	# the lamp and its warm pool while manned
	if lit > 0.05:
		var lamp := TankMech.WARM.lerp(slot, 0.15)
		for y in h - 6:
			for x in w:
				var dd := Vector2(x, y).distance_to(Vector2(42, 0))
				var k2 := clampf(1.0 - dd / 70.0, 0.0, 1.0) * 0.35 * lit
				if k2 > 0.0:
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(lamp, k2))
		img.fill_rect(Rect2i(39, 0, 6, 2), lamp.lightened(0.5))
		img.fill_rect(Rect2i(38, 2, 8, 1), TankMech.IRON[1])
		if fposmod(phase * 2.0, 1.0) < 0.3:
			img.fill_rect(Rect2i(108, 6, 4, 4), Color(1.0, 0.85, 0.5))
			img.fill_rect(Rect2i(108, 10, 4, 4), Color(1.0, 0.78, 0.42))
	if t < 0.0:
		img.set_pixel(0, 0, Color.BLACK)


# --- Paint -------------------------------------------------------------------------------------------------


func paint() -> void:
	if seats.is_empty():
		return
	if layout == "B":
		_board()
	else:
		_row()


## Layout A: five seat cards docked after my numbers, the hint over your card.
func card_rects() -> Array[Rect2]:
	var art := canvas()
	var own := TankHud.anchored(art_rect, art)
	var mine := TankHud.anchored(TankHud.LAYOUT["mine"], art)
	var clear := TankHud.anchored(TankHud.CLEAR, art)
	var left := mine.end.x + GAP
	var right := mini(clear.position.x, art.x) - GAP
	var n := SEATS.size()
	var w := mini(CARD_W, floori(float(right - left - (n - 1) * GAP) / float(n)))
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(left + i * (w + GAP) - own.position.x, own.size.y - CARD_H, w, CARD_H))
	return out


func _row() -> void:
	var rs := card_rects()
	for i in seats.size():
		_card(seats[i], rs[i])
	for i in seats.size():
		if bool(seats[i]["local"]):
			_hint(rs[i])


func _card(d: Dictionary, r: Rect2) -> void:
	var empty := bool(d["empty"])
	var local := bool(d["local"])
	var edge := D.FRAME_HI if local else (D.FRAME_IN.lightened(0.15) if empty else D.FRAME)
	var cw := r.size.x
	var fr := Rect2(r.position.x, r.position.y + FRAME_Y, cw, WIN.y + 4)
	D.rect(self, fr, D.PANEL)
	var tex := _tex.get(str(d["id"])) as ImageTexture
	if tex != null:
		var ww := minf(cw - 4.0, WIN.x)
		var src := Rect2(roundf((WIN.x - ww) * 0.5), 0, ww, WIN.y)
		draw_texture_rect_region(tex, Rect2(fr.position + Vector2(2, 2), src.size), src)
	D.frame(self, fr, edge)
	D.frame(self, fr.grow(-1), D.FRAME_IN)
	if local:
		D.frame(self, fr.grow(1), Color(D.FRAME_HI, 0.55))
	D.rivet(self, fr.position + Vector2(2, fr.size.y - 4))
	D.rivet(self, fr.end - Vector2(4, 4))
	_tab(d, Vector2(r.position.x + 4, r.position.y), empty)
	if local:
		var you := tx("TANK_HUD_YOU")
		var yw := D.text_w(you) + 8.0
		var yr := Rect2(r.end.x - 4.0 - yw, r.position.y, yw, 11)
		D.rect(self, yr, D.AMBER)
		D.text(self, yr.position.x + 4, yr.position.y + 2, you, D.PANEL)
		_lock(Vector2(fr.position.x + 4, fr.end.y - 15))
	if str(d["id"]) in ["loader", "gun"]:
		_rack_pips(Vector2(fr.end.x - 21, fr.end.y - 13), true)
	if str(d["id"]) == "secondaries" and not empty:
		var rpm := "%d/min" % roundi(2.0 * float(d["cad"]))
		var tw := D.text_w(rpm) + 6.0
		var tr := Rect2(fr.end.x - 3.0 - tw, fr.end.y - 14, tw, 11)
		D.rect(self, tr, Color(D.PANEL, 0.85))
		D.text(self, tr.position.x + 3, tr.position.y + 2, rpm, COLD)
	if empty:
		D.text_shadow(self, fr.position.x + 6, fr.position.y + 26, "EMPTY", D.DIM)
	_footer(d, Rect2(r.position.x, fr.end.y - 1, cw, r.end.y - fr.end.y - 1), edge)


func _tab(d: Dictionary, p: Vector2, empty: bool) -> void:
	var label := str(d["label"])
	var tab := Rect2(p.x, p.y, D.text_w(label) + 16.0, 11)
	var col := D.FRAME if not empty else Color("#4a3b26")
	D.rect(self, tab, col)
	D.rect(self, Rect2(tab.position, Vector2(tab.size.x, 1)), D.RIVET_HI if not empty else D.FRAME)
	D.rect(self, Rect2(tab.position.x, tab.end.y - 1, tab.size.x, 1), Color("#4d3a20"))
	var ink := D.PANEL if not empty else Color("#a08a66")
	_icon(str(d["icon"]), tab.position + Vector2(2, 2), ink)
	D.text(self, tab.position.x + 12, tab.position.y + 2, label, ink)


func _icon(name: String, p: Vector2, col: Color) -> void:
	if name == "feed":
		D.pixels(self, FEED_ICON, p, col)
	else:
		D.icon(self, name, p, col)


func _footer(d: Dictionary, sr: Rect2, edge: Color) -> void:
	D.rect(self, sr, D.PANEL)
	D.frame(self, sr, edge)
	if bool(d["empty"]):
		D.pixels(self, D.SHAPES[2], sr.position + Vector2(4, 6), Color("#2a231b"))
		D.tall(self, sr.position.x + 12, sr.position.y + 4, "empty", Color("#6b5d48"))
		D.rect(self, Rect2(sr.position.x, sr.end.y - 1, sr.size.x, 2), D.TRACK)
		return
	var slot := int(d["slot"])
	var slot_col := slot_color(slot)
	var state := int(d["state"])
	var state_col := D.GOOD
	if state < 0:
		state_col = D.UNDER
	elif state > 0:
		state_col = D.OVER
	D.chip(self, slot, sr.position + Vector2(4, 6), slot_col)
	var wtxt := tx("TANK_HUD_WATTS_N", [roundi(float(d["w"]))])
	D.tall_r(self, sr.end.x - 5, sr.position.y + 4, wtxt, D.TEXT if state == 0 else state_col)
	var nm := D.fit_tall(str(d["name"]), sr.size.x - 12.0 - D.tall_w(wtxt) - 9.0)
	D.tall(self, sr.position.x + 12, sr.position.y + 4, nm, D.slot_text(slot_col))
	D.rect(self, Rect2(sr.position.x, sr.end.y - 1, sr.size.x, 2), state_col)


## Your seat's switch lock: a padlock and the seconds left, or an open lamp once you may move.
func _lock(p: Vector2) -> void:
	var txt := D.clock(lock_left) if lock_left > 0.0 else "MOVE OK"
	var tw := D.text_w(txt) + 16.0
	var r := Rect2(p, Vector2(tw, 11))
	D.rect(self, r, Color(D.PANEL, 0.88))
	D.frame(self, r, D.FRAME_IN.lightened(0.2))
	var col := D.AMBER if lock_left > 0.0 else D.GOOD
	D.pixels(self, LOCK_ICON, p + Vector2(3, 3), col)
	if lock_left > 0.0:
		# the lock's ring: how much of the 60 s is left
		var fill := roundf((tw - 4.0) * lock_left / LOCK_S)
		D.rect(self, Rect2(p.x + 2, p.y + 10, fill, 1), col)
	D.text(self, p.x + 11, p.y + 2, txt, col)


## The ready rack: three shells, lit while loaded.
func _rack_pips(p: Vector2, plate: bool) -> void:
	if plate:
		D.rect(self, Rect2(p - Vector2(2, 2), Vector2(18, 11)), Color(D.PANEL, 0.85))
	for i in 3:
		var col := D.BRASS.lightened(0.2) if i < rack else Color("#3a3128")
		D.pixels(self, SHELL, p + Vector2(i * 5, 0), col)
		if i < rack:
			D.rect(self, Rect2(p + Vector2(i * 5 + 1, 0), Vector2(1, 1)), Color("#e07a3c"))


## The hint over your card (layout A): "< > move  OK sit" once the lock is off, else the wait.
func _hint(cr: Rect2) -> void:
	var txt := "< > move  OK sit" if lock_left <= 0.0 else "seat locked"
	var tw := D.text_w(txt) + 10.0
	var x := clampf(cr.get_center().x - tw * 0.5, cr.position.x - 40.0, cr.end.x + 40.0 - tw)
	var r := Rect2(roundf(x), cr.position.y - 15, tw, 12)
	D.plate(self, r, D.FRAME_HI if lock_left <= 0.0 else D.FRAME, 0)
	D.text(self, r.position.x + 5, r.position.y + 3, txt, D.TEXT if lock_left <= 0.0 else D.DIM)


# --- Layout B: the seat board -------------------------------------------------------------------------------


func _board() -> void:
	D.plate(self, Rect2(Vector2.ZERO, BOARD))
	for i in seats.size():
		_socket(seats[i], Rect2(4 + i * (SOCK.x + 2), 3, SOCK.x, SOCK.y))
	D.rect(self, Rect2(4, 25, BOARD.x - 8, 1), D.FRAME_IN)
	var me := -1
	for i in seats.size():
		if bool(seats[i]["local"]):
			me = i
	var y := 28.0
	if me >= 0 and lock_left > 0.0:
		D.pixels(self, LOCK_ICON, Vector2(6, y + 1), D.AMBER)
		var t := "SWITCH IN " + D.clock(lock_left)
		D.text(self, 14, y, t, D.AMBER)
		var bw := 48.0
		var bx := 16.0 + D.text_w(t) + 4.0
		D.bar(self, Rect2(bx, y + 2, bw, 3), lock_left / LOCK_S, D.AMBER)
	elif me >= 0:
		D.text(self, 6, y, "< > move  OK sit", D.TEXT)
	D.text_r(self, BOARD.x - 26, y, "RACK", D.DIM)
	_rack_pips(Vector2(BOARD.x - 21, y - 1), false)


func _socket(d: Dictionary, r: Rect2) -> void:
	var empty := bool(d["empty"])
	var local := bool(d["local"])
	D.rect(self, r, Color("#0e0c09") if empty else D.PANEL_LIFT)
	var edge := D.FRAME_HI if local else (D.FRAME_IN.lightened(0.15) if empty else D.FRAME)
	D.frame(self, r, edge)
	var ink := Color("#5c4e3a") if empty else D.AMBER
	_icon(str(d["icon"]), r.position + Vector2(3, 3), ink)
	D.text(self, r.position.x + 12, r.position.y + 3, str(d["short"]), ink if empty else D.TEXT)
	if empty:
		D.rect(self, Rect2(r.position.x + 3, r.end.y - 6, r.size.x - 6, 3), Color("#1d1912"))
		return
	var col := slot_color(int(d["slot"]))
	D.chip(self, int(d["slot"]), Vector2(r.end.x - 8, r.position.y + 3), col)
	D.rect(self, Rect2(r.position.x + 3, r.end.y - 6, r.size.x - 6, 3), col)
	var state := int(d["state"])
	var sc := D.GOOD if state == 0 else (D.UNDER if state < 0 else D.OVER)
	D.rect(self, Rect2(r.position.x + 3, r.end.y - 3, r.size.x - 6, 1), sc)
	if local:
		D.frame(self, r.grow(1), Color(D.FRAME_HI, 0.5))
		D.rect(self, Rect2(r.get_center().x - 2, r.position.y - 3, 5, 2), D.AMBER)
