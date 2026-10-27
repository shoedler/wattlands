class_name TankHudCrew
extends TankHudCtl
## The crew row, bottom middle (brief 3.6): one card per rider in room order (state.stations,
## rear to front = left to right), each a live engine window (TankMech, 112 x 64 art px, one
## Image + ImageTexture per card, repainted every frame) in a riveted frame with the engine's name
## on a brass tab, and a footer: the rider's slot chip and name in their slot colour (cut with an
## ellipsis to fit), their watts, and a 2 px strip: green in band, blue under, red over. The local
## rider's card has the bright frame and a YOU tab. `phase` is the crank's revolutions, the
## integral of the rider's cadence (rpm / 60 per second, on the wall clock so a client's 10 Hz
## snapshots still turn it smoothly; TankMech turns each part at its own ratio of it); `power` is
## TankHudModel.power_ratio. The local rider's watts and cadence come from their telemetry.
##
## The cards dock left next to my numbers and run right up to the clear bottom-right corner on
## the canvas the HUD lays out (card_rects()): the Control's own rect is the part that is free on
## every canvas from 852 x 480 up, and on a wider canvas the row reaches left beyond it into the
## free space by my numbers. Where four full cards do not fit (852 px wide), the cards narrow and
## each window shows the middle of its engine.

const WIN := Vector2i(TankMech.W, TankMech.H)
const CARD_W := 116
const CARD_H := 90
const GAP := 6
const FRAME_Y := 4
const FOOT_H := 18

var cards: Array = []
var _img: Dictionary = {}
var _tex: Dictionary = {}
var _phase: Dictionary = {}
var _wall: float = 0.0


func tick(delta: float) -> void:
	_wall += delta
	for c: Dictionary in cards:
		var key := str(c["engine"])
		_phase[key] = float(_phase.get(key, 0.0)) + float(c["cad"]) / 60.0 * delta


func refresh() -> void:
	var local := {}
	if tm != null:
		local = {"w": tm.power_w, "cad": tm.cadence_rpm}
	cards = TankHudModel.crew_cards(st(), local_peer(), local)
	for c: Dictionary in cards:
		var r := st().rider(int(c["peer"]))
		c["name"] = rider_name(r) if r != null else ""
		c["phase"] = float(_phase.get(str(c["engine"]), 0.0))
		_paint_window(c)


## The crank revolutions of `engine`'s card so far.
func phase_of(engine: String) -> float:
	return float(_phase.get(engine, 0.0))


## The engine window's texture of `engine` (null before its first refresh).
func texture_of(engine: String) -> ImageTexture:
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


## The cards' rects for `n` riders on an `art` canvas, in art px local to the crew rect: docked
## left GAP after my numbers, never past GAP before the clear bottom-right corner (or the canvas
## edge), CARD_W wide where they fit, narrower where they do not.
static func card_rects(n: int, art: Vector2i) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if n <= 0:
		return out
	var own := TankHud.anchored(TankHud.LAYOUT["crew"], art)
	var mine := TankHud.anchored(TankHud.LAYOUT["mine"], art)
	var clear := TankHud.anchored(TankHud.CLEAR, art)
	var left := mini(mine.end.x + GAP, own.position.x)
	var right := mini(clear.position.x, art.x) - GAP
	var w := mini(CARD_W, floori(float(right - left - (n - 1) * GAP) / float(n)))
	for i in n:
		var x := left + i * (w + GAP) - own.position.x
		out.append(Rect2(x, own.size.y - CARD_H, w, CARD_H))
	return out


func paint() -> void:
	var rs := card_rects(cards.size(), canvas())
	for i in cards.size():
		_card(cards[i], rs[i])


func _card(c: Dictionary, r: Rect2) -> void:
	var local := bool(c["local"])
	var slot := int(c["slot"])
	var slot_col := slot_color(slot)
	var edge := D.FRAME_HI if local else D.FRAME
	var cw := r.size.x
	# the window in its riveted frame
	var fr := Rect2(r.position.x, r.position.y + FRAME_Y, cw, WIN.y + 4)
	D.rect(self, fr, D.PANEL)
	var tex := texture_of(str(c["engine"]))
	if tex != null:
		var ww := minf(cw - 4.0, WIN.x)
		var src := Rect2(roundf((WIN.x - ww) * 0.5), 0, ww, WIN.y)
		draw_texture_rect_region(tex, Rect2(fr.position + Vector2(2, 2), src.size), src)
	if bool(c["reserve"]):
		D.text_shadow(self, fr.position.x + 6, fr.end.y - 13, tx("TANK_HUD_RESERVE"), D.DIM)
	D.frame(self, fr, edge)
	D.frame(self, fr.grow(-1), D.FRAME_IN)
	if local:
		D.frame(self, fr.grow(1), Color(D.FRAME_HI, 0.55))
	D.rivet(self, fr.position + Vector2(2, fr.size.y - 4))
	D.rivet(self, fr.end - Vector2(4, 4))
	_tab(str(c["engine"]), Vector2(r.position.x + 4, r.position.y))
	if local:
		var you := tx("TANK_HUD_YOU")
		var yw := D.text_w(you) + 8.0
		var yr := Rect2(r.end.x - 4.0 - yw, r.position.y, yw, 11)
		D.rect(self, yr, D.AMBER)
		D.text(self, yr.position.x + 4, yr.position.y + 2, you, D.PANEL)
	else:
		D.rivet(self, Vector2(fr.end.x - 4, fr.position.y + 2))
	_footer(c, Rect2(r.position.x, fr.end.y - 1, cw, r.end.y - fr.end.y - 1), slot, slot_col, edge)


## The rider's name cut with an ellipsis to fit a card `card_w` wide beside its `watts` text.
static func fit_name(rider: String, card_w: float, watts: String) -> String:
	return D.fit_tall(rider, card_w - 12.0 - D.tall_w(watts) - 9.0)


## The brass name tab over the frame's top left: the engine's icon and name.
func _tab(eng: String, p: Vector2) -> void:
	var label := tx("TANK_HUD_ENG_" + eng.to_upper()).to_upper()
	var tab := Rect2(p.x, p.y, D.text_w(label) + 16.0, 11)
	D.rect(self, tab, D.FRAME)
	D.rect(self, Rect2(tab.position, Vector2(tab.size.x, 1)), D.RIVET_HI)
	D.rect(self, Rect2(tab.position.x, tab.end.y - 1, tab.size.x, 1), Color("#4d3a20"))
	D.icon(self, eng, tab.position + Vector2(2, 2), D.PANEL)
	D.text(self, tab.position.x + 12, tab.position.y + 2, label, D.PANEL)


## The footer: chip and name in the slot colour, the watts tinted by state, the band strip.
func _footer(c: Dictionary, sr: Rect2, slot: int, slot_col: Color, edge: Color) -> void:
	D.rect(self, sr, D.PANEL)
	D.frame(self, sr, edge)
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
	D.rect(self, Rect2(sr.position.x, sr.end.y + 1 - 2, sr.size.x, 2), state_col)
