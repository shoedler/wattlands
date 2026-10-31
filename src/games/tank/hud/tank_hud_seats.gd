class_name TankHudSeats
extends TankHudCtl
## The seat panel, bottom middle (v3 brief "HUD": seat panel A, in place of v2's crew row): one card
## per seat in TankIds.SEATS order (Drive, Gun, Loader, Lights, Secondaries, Repairs), each a live
## machine window (TankMech, 112 x 64 art px: diesel, dynamo, steam, arc, the feed for the Secondaries
## and the rivet hammer for Repairs; one Image + ImageTexture per card, repainted every frame while
## manned) in a riveted frame with
## the seat's icon and name on a brass tab and a tiny ERG / SIM tag (the seat's trainer mode,
## TankHudModel.SEAT_MODE), and a footer: the rider's slot chip and name in their slot colour (cut
## with an ellipsis to fit), their watts, and a 2 px strip (green in band, blue under, red over).
##  - An empty seat is dark and cold (its machine at rest, painted once and tinted) and marked EMPTY.
##  - Your card has the bright frame and a YOU tab; while your trainer has not yet switched to your
##    seat's mode (0.3.1: a move lands at once, the trainer's ERG <-> SIM switch waits for BRIEF 4.5's
##    30 s) it shows the switch to come: "ERG in 12 s" (TankRiderState.mode_to, mode_wait_s), or "ERG
##    at stage end". The hint plate above it reads "< > seat  OK sit" (every seat, the Gun too),
##    "< > pick  OK sit" while the picker is open, or "auto seat" for an Autopilot rider (no picker;
##    TankHudSeatPicker). There is no seat lock.
##  - The picker's seat (TankGame.seat_picker) blinks amber with an arrow.
##  - The Gun and Loader cards carry the ready rack's three shell pips (the Loader's rack), the
##    Secondaries card its rounds a minute (TankFeedState.rpm) while manned, or "no target" while
##    its rider pedals with nothing in the guns' reach (TankHudModel.feed_label). The Repairs card
##    carries a 2 px hull bar while manned and "+0.4/s" (hull a second) while it works.
##  - A bot's card says BOT; a human may pick that seat (the picker counts it as free).
##  - Every tag on a card (ERG / SIM, the rate, the rack pips, the lock) sits on a solid plate with a
##    1 px rim, so the live machine behind never runs into its text.
## `phase` is the crank's revolutions, a CrankClock per card (on the wall clock so a client's 10 Hz
## snapshots still turn it smoothly); `power` is
## TankHudModel.power_ratio. The local rider's watts and cadence come from their telemetry.
##
## The cards dock left next to my numbers and run right up to the clear bottom-right corner on the
## canvas the HUD lays out (card_rects()): the Control's own rect is the part free on every canvas
## from 852 x 480 up, and on a wider canvas the row reaches left beyond it into the free space by my
## numbers. Where six full cards do not fit, the cards narrow and each window shows the middle of
## its machine. The hint plate stays over the seat row, clear of my numbers and of the tank's band.

const WIN := Vector2i(TankMech.W, TankMech.H)
const CARD_W := 100
const CARD_H := 90
const GAP := 5
const FRAME_Y := 4
## The hint plate: its height and its top above the cards' top.
const HINT_H := 12.0
const HINT_LIFT := 15.0
const TAB_H := 11.0
## A tab's text padding with its icon and, where even the short name leaves no room for it, without.
const TAB_PAD := 16.0
const TAB_PAD_BARE := 6.0
## A bot's tag: an abbreviation, like the ERG and SIM tags beside it.
const BOT_TAG := "BOT"
## The Repairs card's hull bar turns red under this share.
const HULL_LOW := 0.34
const SHELL := [".#.", "###", "###", "###", "###", "###", "###"]
const ARROW := ["#######", ".#####.", "..###..", "...#..."]
## The Secondaries' rate (cold blue-white, like their dial) and an empty room's tint.
const COLD := Color("#d6ecff")
const EMPTY_TINT := Color(0.34, 0.4, 0.5)

## The cards (TankHudModel.seat_cards) plus each manned rider's name and crank phase.
var cards: Array = []
## The Loader's ready rack and the bow guns' rounds a minute.
var rack: int = 0
var feed_rpm: float = 0.0
## The local rider's seat (empty without one): {engine, wait_s, mode_to, auto, usable, pick}.
var me: Dictionary = {}
var _img: Dictionary = {}
var _tex: Dictionary = {}
var _rest: Dictionary = {}
var _clocks: Dictionary = {}
var _wall: float = 0.0


func tick(delta: float) -> void:
	_wall += delta
	for c: Dictionary in cards:
		var key := str(c["engine"])
		if not _clocks.has(key):
			_clocks[key] = CrankClock.new()
		(_clocks[key] as CrankClock).advance(float(c["cad"]), delta)


func refresh() -> void:
	var local := {}
	if tm != null:
		local = {"w": tm.power_w, "cad": tm.cadence_rpm}
	var s := st()
	cards = TankHudModel.seat_cards(s, local_peer(), local)
	for c: Dictionary in cards:
		c["phase"] = phase_of(str(c["engine"]))
		if bool(c["empty"]):
			c["name"] = ""
			_paint_rest(str(c["engine"]))
		else:
			var r := s.rider_at(int(c["slot"]))
			c["name"] = rider_name(r) if r != null else ""
			_paint_window(c)
	rack = TankHudModel.rack(s)
	feed_rpm = TankHudModel.feed_rpm(s)
	me = local_seat()


## The local rider's seat: {engine, wait_s and mode_to (the trainer's switch to come), auto,
## usable (the picker may open), pick (the picker's seat)}; {} for a spectator.
func local_seat() -> Dictionary:
	var r := st().rider(local_peer())
	if r == null:
		return {}
	var picker: TankHudSeatPicker = game.seat_picker if game != null else null
	return {
		"engine": r.engine,
		"wait_s": r.mode_wait_s,
		"mode_to": r.mode_to,
		"auto": r.autopilot or r.is_bot,
		"usable": TankHudSeatPicker.usable(st(), r),
		"pick": picker.pick if picker != null else "",
	}


## The hint plate's string key for the local seat `m` (local_seat()); "" for none.
static func hint_key(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	if bool(m["auto"]):
		return "TANK_HUD_SEAT_AUTO"
	if str(m["pick"]) != "":
		return "TANK_HUD_SEAT_PICK"
	if bool(m["usable"]):
		return "TANK_HUD_SEAT_HINT"
	return ""


## The trainer's switch to come (`mode_to` "" for none): "ERG in 12 s", or "ERG at stage end" when
## it waits for the segment's end (wait_s < 0); "" for none.
func mode_text(mode_to: String, wait_s: float) -> String:
	if mode_to == "":
		return ""
	if wait_s < 0.0:
		return tx("TANK_HUD_MODE_AT_END", [mode_to])
	return tx("TANK_HUD_MODE_IN", [mode_to, ceili(wait_s - 1e-6)])


## The crank revolutions of `engine`'s card so far.
func phase_of(engine: String) -> float:
	var clock: CrankClock = _clocks.get(engine)
	return clock.revs if clock != null else 0.0


## The machine window's texture of `engine` (the live one while manned, the cold one at rest while
## empty; null before its first refresh).
func texture_of(engine: String) -> ImageTexture:
	for c: Dictionary in cards:
		if str(c["engine"]) == engine and bool(c["empty"]):
			return _rest.get(engine) as ImageTexture
	return _tex.get(engine) as ImageTexture


func _paint_window(c: Dictionary) -> void:
	var key := str(c["engine"])
	if not _img.has(key):
		_img[key] = Image.create_empty(WIN.x, WIN.y, false, Image.FORMAT_RGBA8)
	var img: Image = _img[key]
	var power := float(c["ratio"]) if not bool(c["reserve"]) else 0.5
	TankMech.paint_ex(
		img,
		str(c["mech"]),
		float(c["phase"]),
		power,
		_wall,
		slot_color(int(c["slot"])),
		float(c["cad"])
	)
	if not _tex.has(key):
		_tex[key] = ImageTexture.create_from_image(img)
	else:
		(_tex[key] as ImageTexture).update(img)


## An empty seat's window, painted once: its machine at rest, unlit, dark and cold.
func _paint_rest(engine: String) -> void:
	if _rest.has(engine):
		return
	var img := Image.create_empty(WIN.x, WIN.y, false, Image.FORMAT_RGBA8)
	var mech := str(TankHudModel.MECH[engine])
	TankMech.paint_ex(img, mech, 0.0, 0.0, 0.0, Color(0.3, 0.3, 0.3), 0.0)
	for y in WIN.y:
		for x in WIN.x:
			var l := img.get_pixel(x, y).get_luminance() * 0.9
			img.set_pixel(x, y, Color(l * EMPTY_TINT.r, l * EMPTY_TINT.g, l * EMPTY_TINT.b))
	_rest[engine] = ImageTexture.create_from_image(img)


## The cards' rects on an `art` canvas, in art px local to the seat panel's rect: docked left GAP
## after my numbers, never past GAP before the clear bottom-right corner (or the canvas edge),
## CARD_W wide where they fit, narrower where they do not.
static func card_rects(art: Vector2i) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := TankIds.SEATS.size()
	var own := TankHud.anchored(TankHud.LAYOUT["seats"], art)
	var mine := TankHud.anchored(TankHud.LAYOUT["mine"], art)
	var clear := TankHud.anchored(TankHud.CLEAR, art)
	var left := mini(mine.end.x + GAP, own.position.x)
	var right := mini(clear.position.x, art.x) - GAP
	var w := mini(CARD_W, floori(float(right - left - (n - 1) * GAP) / float(n)))
	for i in n:
		var x := left + i * (w + GAP) - own.position.x
		out.append(Rect2(x, own.size.y - CARD_H, w, CARD_H))
	return out


## The hint plate over the card `cr` (local art px), `w` wide, on an `art` canvas: centred on the
## card, kept over the seat row (never over my numbers or past the canvas).
static func hint_rect(cr: Rect2, w: float, art: Vector2i) -> Rect2:
	var own := TankHud.anchored(TankHud.LAYOUT["seats"], art)
	var mine := TankHud.anchored(TankHud.LAYOUT["mine"], art)
	var lo := float(mine.end.x + 2 - own.position.x)
	var hi := float(art.x - 2 - own.position.x) - w
	var x := clampf(roundf(cr.get_center().x - w * 0.5), lo, maxf(hi, lo))
	return Rect2(x, cr.position.y - HINT_LIFT, w, HINT_H)


func paint() -> void:
	var rs := card_rects(canvas())
	for i in mini(cards.size(), rs.size()):
		_card(cards[i], rs[i])
	for i in mini(cards.size(), rs.size()):
		if bool(cards[i]["local"]):
			_hint(rs[i])


func _card(c: Dictionary, r: Rect2) -> void:
	var engine := str(c["engine"])
	var empty := bool(c["empty"])
	var local := bool(c["local"])
	var picked := str(me.get("pick", "")) == engine
	var blink := int(floorf(_wall * 3.0)) % 2 == 0
	var edge := D.FRAME_HI if local else (D.FRAME_IN.lightened(0.15) if empty else D.FRAME)
	if picked:
		edge = D.FRAME_HI if blink else D.FRAME
	var cw := r.size.x
	# the window in its riveted frame
	var fr := Rect2(r.position.x, r.position.y + FRAME_Y, cw, WIN.y + 4)
	D.rect(self, fr, D.PANEL)
	var tex := texture_of(engine)
	if tex != null:
		var ww := minf(cw - 4.0, WIN.x)
		var src := Rect2(roundf((WIN.x - ww) * 0.5), 0, ww, WIN.y)
		draw_texture_rect_region(tex, Rect2(fr.position + Vector2(2, 2), src.size), src)
	if bool(c["reserve"]):
		D.text_shadow(self, fr.position.x + 6, fr.end.y - 13, tx("TANK_HUD_RESERVE"), D.DIM)
	D.frame(self, fr, edge)
	D.frame(self, fr.grow(-1), D.FRAME_IN)
	if local or picked:
		D.frame(self, fr.grow(1), Color(edge, 0.55))
	D.rivet(self, fr.position + Vector2(2, fr.size.y - 4))
	D.rivet(self, fr.end - Vector2(4, 4))
	var you_w := 0.0
	if local:
		var you := tx("TANK_HUD_YOU")
		you_w = D.text_w(you) + 8.0
		var yr := Rect2(r.end.x - 4.0 - you_w, r.position.y, you_w, TAB_H)
		D.rect(self, yr, D.AMBER)
		D.text(self, yr.position.x + 4, yr.position.y + 2, you, D.PANEL)
		_mode_wait(Vector2(fr.position.x + 4, fr.end.y - 15), str(c["mode_to"]), float(c["wait_s"]))
	_tab(engine, Vector2(r.position.x + 4, r.position.y), empty, cw - 8.0 - you_w - 2.0)
	_mode_tag(str(c["mode"]), Vector2(fr.end.x - 3, r.position.y + 13), empty)
	if engine in [TankIds.ENGINE_DYNAMO, TankIds.ENGINE_STEAM]:
		_rack_pips(Vector2(fr.end.x - 21, fr.end.y - 13))
	var fkey := ""
	if engine == TankIds.ENGINE_FEED and not empty:
		fkey = TankHudModel.feed_label(st(), float(c["cad"]))
	if engine == TankIds.ENGINE_REPAIR and not empty:
		_repair(fr, float(c["w"]))
	if bool(c["bot"]):
		_bot_tag(Vector2(fr.position.x + 3, r.position.y + 13))
	if fkey != "":
		var idle := fkey == "TANK_HUD_NO_TARGET"
		var rpm := tx(fkey) if idle else tx(fkey, [roundi(feed_rpm)])
		var tw := D.text_w(rpm) + 6.0
		var tr := Rect2(fr.end.x - 3.0 - tw, fr.end.y - 14, tw, 11)
		_plate(tr)
		D.text(self, tr.position.x + 3, tr.position.y + 2, rpm, D.DIM if idle else COLD)
	if picked:
		_arrival(fr, D.AMBER, -1)
	elif empty:
		D.text_shadow(self, fr.position.x + 6, fr.position.y + 26, tx("TANK_HUD_SEAT_EMPTY"), D.DIM)
	_footer(c, Rect2(r.position.x, fr.end.y - 1, cw, r.end.y - fr.end.y - 1), edge)


## The brass tab over the frame's top left: the seat's icon and name (its short name where the
## full one does not fit in `max_w`, without the icon beside YOU on the narrowest card), dull on an
## empty seat.
func _tab(engine: String, p: Vector2, empty: bool, max_w: float) -> void:
	var label := tx("TANK_HUD_TAB_" + engine.to_upper())
	if D.text_w(label) + TAB_PAD > max_w:
		label = tx("TANK_HUD_TAB_SHORT_" + engine.to_upper())
	var has_icon := D.text_w(label) + TAB_PAD <= max_w
	var tab := Rect2(p.x, p.y, D.text_w(label) + (TAB_PAD if has_icon else TAB_PAD_BARE), TAB_H)
	var col := D.FRAME if not empty else Color("#4a3b26")
	D.rect(self, tab, col)
	D.rect(self, Rect2(tab.position, Vector2(tab.size.x, 1)), D.RIVET_HI if not empty else D.FRAME)
	D.rect(self, Rect2(tab.position.x, tab.end.y - 1, tab.size.x, 1), Color("#4d3a20"))
	var ink := D.PANEL if not empty else Color("#a08a66")
	if has_icon:
		D.icon(self, engine, tab.position + Vector2(2, 2), ink)
	D.text(self, tab.position.x + (12 if has_icon else 3), tab.position.y + 2, label, ink)


## The footer: chip and name in the slot colour, the watts tinted by state, the band strip; an
## empty seat says so on a bare track.
func _footer(c: Dictionary, sr: Rect2, edge: Color) -> void:
	D.rect(self, sr, D.PANEL)
	D.frame(self, sr, edge)
	if bool(c["empty"]):
		D.pixels(self, D.SHAPES[2], sr.position + Vector2(4, 6), Color("#2a231b"))
		var e := tx("TANK_HUD_SEAT_EMPTY").to_lower()
		D.tall(self, sr.position.x + 12, sr.position.y + 4, e, Color("#6b5d48"))
		D.rect(self, Rect2(sr.position.x, sr.end.y - 1, sr.size.x, 2), D.TRACK)
		return
	var slot := int(c["slot"])
	var slot_col := slot_color(slot)
	var state := int(c["state"])
	var state_col := D.GOOD
	if state < 0:
		state_col = D.UNDER
	elif state > 0:
		state_col = D.OVER
	D.chip(self, slot, sr.position + Vector2(4, 6), slot_col)
	var wtxt := tx("TANK_HUD_WATTS_N", [roundi(float(c["w"]))])
	D.tall_r(self, sr.end.x - 5, sr.position.y + 4, wtxt, D.TEXT if state == 0 else state_col)
	var nm := fit_name(str(c["name"]), sr.size.x, wtxt)
	D.tall(self, sr.position.x + 12, sr.position.y + 4, nm, D.slot_text(slot_col))
	D.rect(self, Rect2(sr.position.x, sr.end.y - 1, sr.size.x, 2), state_col)


## The rider's name cut with an ellipsis to fit a card `card_w` wide beside its `watts` text.
static func fit_name(rider: String, card_w: float, watts: String) -> String:
	return D.fit_tall(rider, card_w - 12.0 - D.tall_w(watts) - 9.0)


## The seat's trainer mode (ERG or SIM) as a tiny dim tag in the window's top-right corner (right
## end at `p`), in the 5 x 7 stencil face.
func _mode_tag(mode: String, p: Vector2, empty: bool) -> void:
	var tw := D.text_w(mode) + 6.0
	var r := Rect2(p.x - tw, p.y, tw, 11)
	_plate(r)
	D.text(self, r.position.x + 3, r.position.y + 2, mode, Color("#6b5d48") if empty else D.DIM)


## The Repairs card: the hull's 2 px bar along the window's foot and, while it works, the rate on a
## plate over it, in the same style as the Secondaries' rate.
func _repair(fr: Rect2, w: float) -> void:
	var rp := TankHudModel.repair(st(), w)
	if rp.is_empty():
		return
	var frac := float(rp["hull"])
	var col := D.OVER if frac < HULL_LOW else D.BRASS
	D.bar(self, Rect2(fr.position.x + 6, fr.end.y - 4, fr.size.x - 12, 2), frac, col)
	if not bool(rp["working"]):
		return
	var txt := rate_text(float(rp["rate"]))
	var tw := D.text_w(txt) + 6.0
	var tr := Rect2(fr.end.x - 3.0 - tw, fr.end.y - 16, tw, 11)
	_plate(tr)
	D.text(self, tr.position.x + 3, tr.position.y + 2, txt, D.GOOD)


## The hull a second as the Repairs card shows it.
static func rate_text(rate: float) -> String:
	return "+%.1f/s" % rate


## A bot's tag at `p`, in the window's top-left corner.
func _bot_tag(p: Vector2) -> void:
	var r := Rect2(p, Vector2(D.text_w(BOT_TAG) + 6.0, 11))
	_plate(r)
	D.text(self, r.position.x + 3, r.position.y + 2, BOT_TAG, D.TEXT)


## A tag's backing plate: solid panel with a 1 px dark rim, so nothing behind shows through it.
func _plate(r: Rect2) -> void:
	D.rect(self, r, D.PANEL)
	D.frame(self, r, D.FRAME_IN)


## Your trainer's switch to come at `p` ("ERG in 12 s" on an amber plate with a bar of what is left
## of the 30 s); nothing when the trainer follows your seat.
func _mode_wait(p: Vector2, mode_to: String, wait_s: float) -> void:
	var txt := mode_text(mode_to, wait_s)
	if txt == "":
		return
	var tw := D.text_w(txt) + 6.0
	var r := Rect2(p, Vector2(tw, 11))
	D.rect(self, r, D.PANEL)
	D.frame(self, r, D.FRAME_IN.lightened(0.2))
	if wait_s > 0.0:
		var fill := roundf((tw - 4.0) * clampf(wait_s / TankConst.SWITCH_GAP_S, 0.0, 1.0))
		D.rect(self, Rect2(p.x + 2, p.y + 10, fill, 1), D.AMBER)
	D.text(self, p.x + 3, p.y + 2, txt, D.AMBER)


## The ready rack: three shells, lit while in the rack.
func _rack_pips(p: Vector2) -> void:
	_plate(Rect2(p - Vector2(2, 2), Vector2(18, 11)))
	for i in TankConst.RACK_MAX:
		var col := D.BRASS.lightened(0.2) if i < rack else Color("#3a3128")
		D.pixels(self, SHELL, p + Vector2(i * 5, 0), col)
		if i < rack:
			D.rect(self, Rect2(p + Vector2(i * 5 + 1, 0), Vector2(1, 1)), Color("#e07a3c"))


## A seat someone is about to take: the picker's (amber) or a pending move's (the mover's slot
## colour, with their chip): an arrow down into the window.
func _arrival(fr: Rect2, col: Color, slot: int) -> void:
	var c := Vector2(roundf(fr.get_center().x), fr.position.y + 22)
	D.rect(self, Rect2(c.x - 6, c.y - 3, 13, 12 if slot < 0 else 19), Color(D.PANEL, 0.8))
	D.pixels(self, ARROW, Vector2(c.x - 3, c.y), col)
	if slot >= 0:
		D.chip(self, slot, Vector2(c.x - 2, c.y + 10), col)


## The hint over your card: what the seat keys do now (hint_key()).
func _hint(cr: Rect2) -> void:
	var key := hint_key(me)
	if key == "":
		return
	var txt := tx(key)
	var live := key in ["TANK_HUD_SEAT_HINT", "TANK_HUD_SEAT_PICK"]
	var r := hint_rect(cr, D.text_w(txt) + 10.0, canvas())
	D.plate(self, r, D.FRAME_HI if live else D.FRAME, 0)
	D.text(self, r.position.x + 5, r.position.y + 3, txt, D.TEXT if live else D.DIM)
