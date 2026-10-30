class_name SiegeRouteCard
extends Control
## The route card (docs/games/siege.md 3 HUD), a compact column at the right edge: the five
## stations, each row with its icon, its name and its cap as pips (filled in the colour of each
## rider on it, hollow for the room left), the local rider's station marked, the hot station
## (Autopilot's pick) starred, and the 2 s coupling bar while the local rider's change
## reconnects. Routing itself stays on the controls (left / right / up / down, swap). Hidden while
## the shop is open (the shop's list owns the directions then) and in the cool-down.

const CONNECT_S := 2.0
const CAPTION_PX := 20
const ROW_PX := 22
const ROW_H := 36.0
const PIP_R := 8.0
const PAD := 10.0
const SIZE := Vector2(260, 236)

var game: SiegeGame = null
## The rows and the coupling fill (0..1, -1 when not coupling) as of the last refresh.
var rows: Array[Dictionary] = []
var coupling: float = -1.0
var _looks: Array[Dictionary] = []


func _init() -> void:
	name = "SiegeRouteCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	visible = false


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var s := game.state if game != null else null
	var r := SiegeHudModel.own_rider(game)
	if s == null or r == null or s.shop_open() or s.in_cooldown():
		visible = false
		return
	visible = true
	rows = SiegeHudModel.station_rows(s, SiegeHudModel.strings_of(game), r)
	coupling = 1.0 - clampf(r.reconnect_s / CONNECT_S, 0.0, 1.0) if r.reconnect_s > 0.0 else -1.0
	_looks.clear()
	for slot in 4:
		_looks.append(SiegeHudPanel.look_of(game, slot))
	queue_redraw()


func _draw() -> void:
	if rows.is_empty():
		return
	var font := WlTheme.font()
	var w := size.x
	draw_style_box(WlTheme.panel_style(), Rect2(Vector2.ZERO, size))
	var tx := SiegeHudModel.strings_of(game)
	var cap_y := PAD + CAPTION_PX
	draw_string(
		font,
		Vector2(PAD, cap_y),
		tx.t("SIEGE_HUD_ROUTE"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		CAPTION_PX,
		WlTheme.TEXT_DIM
	)
	if coupling >= 0.0:
		var bx := w * 0.45
		var bar := Rect2(bx, cap_y - 12, w - bx - PAD, 10)
		draw_rect(bar, WlTheme.BAR_BG)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * coupling, bar.size.y)), WlTheme.ACCENT)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y := cap_y + 8.0 + i * ROW_H
		var mine := bool(row["mine"])
		if mine:
			draw_rect(Rect2(4, y, w - 8, ROW_H - 4), Color(WlTheme.ACCENT, 0.22))
			draw_rect(Rect2(4, y, 4, ROW_H - 4), WlTheme.ACCENT)
		_icon(
			int(row["id"]),
			Vector2(PAD + 10, y + ROW_H * 0.45),
			WlTheme.ACCENT if mine else WlTheme.TEXT_DIM
		)
		var label := str(row["name"]) + (" *" if bool(row["hot"]) and not mine else "")
		var col := WlTheme.TEXT if mine else Color(WlTheme.TEXT, 0.85)
		draw_string(
			font,
			Vector2(PAD + 26, y + ROW_H * 0.66),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			w - 120,
			ROW_PX,
			col
		)
		_pips(row, Vector2(w - PAD - PIP_R, y + ROW_H * 0.45))


## The cap as pips from the right edge leftwards: riders' colours first, then hollow room.
func _pips(row: Dictionary, right: Vector2) -> void:
	var cap := int(row["cap"])
	var slots: Array = row["riders"]
	for k in cap:
		var c := right - Vector2((cap - 1 - k) * (PIP_R * 2.0 + 4.0), 0)
		if k < slots.size():
			var col: Color = WlTheme.TEXT
			if int(slots[k]) < _looks.size():
				col = _looks[int(slots[k])]["color"]
			draw_circle(c, PIP_R, col)
			draw_arc(c, PIP_R, 0.0, TAU, 16, WlTheme.OUTLINE, 2.0)
		else:
			draw_arc(c, PIP_R - 1.0, 0.0, TAU, 16, WlTheme.TEXT_DIM, 2.0)


## A small glyph per station (shape, not colour, tells them apart).
func _icon(id: int, c: Vector2, col: Color) -> void:
	match id:
		SiegeIds.STATION_MINE:
			draw_colored_polygon(
				PackedVector2Array([c + Vector2(-7, 6), c + Vector2(0, -7), c + Vector2(7, 6)]), col
			)
		SiegeIds.STATION_BALLISTA:
			draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), col, 3.0)
			draw_line(c + Vector2(4, -5), c + Vector2(8, 0), col, 3.0)
			draw_line(c + Vector2(4, 5), c + Vector2(8, 0), col, 3.0)
		SiegeIds.STATION_ONAGER:
			draw_circle(c, 6.0, col)
		SiegeIds.STATION_ARROWS:
			for k in 3:
				draw_line(c + Vector2(-7 + k * 6, 6), c + Vector2(-3 + k * 6, -6), col, 2.0)
		_:
			draw_rect(Rect2(c - Vector2(6, 4), Vector2(12, 10)), col)
			draw_line(c + Vector2(-2, -4), c + Vector2(-2, -8), col, 2.0)
