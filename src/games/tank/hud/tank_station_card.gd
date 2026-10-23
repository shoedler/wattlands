class_name TankStationCard
extends TankHudPanel
## The station card (brief 3 HUD): what the local rider's own engine needs at a glance. Diesel:
## speed, distance to the halt line, the berm (at a gun line) or the Ram window. Dynamo: the bank,
## its ERG target and the barrel's elevation. Steam: the pressure dial with the 40 / 100 / 150%
## marks, the loaded shell and the Overpressure window. Bulwark: the lever with its auto marker, the
## hoist's progress and the speed. Three cells of 232 x 168 design px (1080p) in the 232 x 56 art
## px rect; the key numbers are 56 px at 1080p, above the 48 px minimum. With the Bulwark the lever
## cell can be clicked to move the lever (a button intent through ctx.intents).

const KEY_PX := 56.0
const LABEL_PX := 24.0
const SMALL_PX := 22.0
## The lever's position labels: small enough for "Turret" in a 70 px box at 1080p.
const LEVER_PX := 20.0
const MARGIN := 12.0
const GAP := 8.0
const LOW_FRAC := 0.2
const LEVER_ORDER: Array[int] = [TankIds.LEVER_DRIVE, TankIds.LEVER_TURRET, TankIds.LEVER_HOIST]
const LEVER_WORDS: Array[String] = ["drive", "turret", "hoist"]


func _init() -> void:
	super._init()
	name = "TankStationCard"
	design_size = Vector2(696, 168)


func compute(state: TankState) -> Dictionary:
	return TankHudModel.card(state, local_peer())


func refresh() -> void:
	super.refresh()
	# Only the Bulwark's lever cell takes clicks; every other card lets the mouse through.
	var want := (
		Control.MOUSE_FILTER_STOP
		if str(model.get("kind", "")) == TankIds.ENGINE_BULWARK
		else Control.MOUSE_FILTER_IGNORE
	)
	if mouse_filter != want:
		mouse_filter = want


## The width of one of the three cells in design px.
static func cell_w() -> float:
	return (696.0 - 2.0 * MARGIN - 2.0 * GAP) / 3.0


## The rect of cell `i` (0..2) in design px.
static func cell_rect(i: int) -> Rect2:
	return Rect2(Vector2(MARGIN + float(i) * (cell_w() + GAP), 8.0), Vector2(cell_w(), 152.0))


## The click rect of lever position `i` in the Bulwark's lever cell, in design px.
static func lever_rect(i: int) -> Rect2:
	var c := cell_rect(0)
	var w := floorf((c.size.x - 2.0 * 6.0) / 3.0)
	return Rect2(
		Vector2(c.position.x + float(i) * (w + 6.0), c.position.y + 46.0), Vector2(w, 56.0)
	)


func _gui_input(event: InputEvent) -> void:
	if str(model.get("kind", "")) != TankIds.ENGINE_BULWARK or game == null or game.ctx == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var p := mb.position / k()
	for i in 3:
		if lever_rect(i).has_point(p):
			game.ctx.intents.send(TankIntents.lever(LEVER_WORDS[i], TankIds.VIA_BUTTON))
			accept_event()
			return


func _draw() -> void:
	var kind := str(model.get("kind", "none"))
	if kind == "none":
		return
	panel()
	match kind:
		TankIds.ENGINE_DIESEL:
			_diesel()
		TankIds.ENGINE_DYNAMO:
			_dynamo()
		TankIds.ENGINE_STEAM:
			_steam()
		TankIds.ENGINE_BULWARK:
			_bulwark()
	if bool(model.get("reserve", false)):
		text(
			Vector2(0, 6),
			tr_key("TANK_CARD_RESERVE"),
			LABEL_PX,
			WlTheme.WARN,
			696.0 - MARGIN,
			HORIZONTAL_ALIGNMENT_RIGHT
		)


# --- Cells --------------------------------------------------------------------------------------------------


## A cell: the label at the top, the key number centred, an optional bar at the bottom.
func _cell(
	i: int,
	label: String,
	value: String,
	bar_frac: float = -1.0,
	fill: Color = WlTheme.ACCENT,
	unit: String = ""
) -> void:
	var c := cell_rect(i)
	text(c.position + Vector2(4, 0), label, LABEL_PX, WlTheme.TEXT_DIM, c.size.x - 8.0)
	var vw := text_width(value, KEY_PX)
	var uw := text_width(unit, SMALL_PX) + 6.0 if unit != "" else 0.0
	var x := c.position.x + (c.size.x - vw - uw) * 0.5
	text(Vector2(x, c.position.y + 30.0), value, KEY_PX, WlTheme.TEXT)
	if unit != "":
		text(Vector2(x + vw + 6.0, c.position.y + 62.0), unit, SMALL_PX, WlTheme.TEXT_DIM)
	if bar_frac >= 0.0:
		bar(Rect2(c.position + Vector2(4, 108), Vector2(c.size.x - 8.0, 28)), bar_frac, fill)


func _diesel() -> void:
	var m := model
	_speed_cells(m)
	if bool(m.get("show_berm", false)):
		var frac := float(m["berm"]) / maxf(float(m["berm_max"]), 1.0)
		_cell(2, tr_key("TANK_CARD_BERM"), "%d" % roundi(float(m["berm"])), frac, WlTheme.ACCENT)
	else:
		_ram_cell(2)


## Speed and the distance to the halt line (the diesel's cells 0 and 1).
func _speed_cells(m: Dictionary) -> void:
	_cell(
		0,
		tr_key("TANK_CARD_SPEED"),
		"%d" % roundi(float(m.get("speed_kmh", 0.0))),
		-1.0,
		WlTheme.ACCENT,
		"km/h"
	)
	var halt := float(m.get("halt_m", -1.0))
	_cell(
		1,
		tr_key("TANK_CARD_TO_HALT"),
		("%d" % ceili(halt)) if halt >= 0.0 else "-",
		-1.0,
		WlTheme.ACCENT,
		"m" if halt >= 0.0 else ""
	)


## The Ram: the open window counts down, the cooldown recharges, and a full bar with a check mark
## means it is ready. The label is the prompt's own words, so no extra strings are needed.
func _ram_cell(i: int) -> void:
	var m := model
	var label := tr_key("TANK_PROMPT_RAM")
	if float(m.get("ram_s", 0.0)) > 0.0:
		_cell(i, label, "%d" % ceili(float(m["ram_s"])), float(m["ram_frac"]), WlTheme.GLOW, "s")
	elif float(m.get("ram_cd_s", 0.0)) > 0.0:
		var recharge := 1.0 - float(m["ram_cd_frac"])
		_cell(i, label, "%d" % ceili(float(m["ram_cd_s"])), recharge, WlTheme.ACCENT, "s")
	else:
		_cell(i, label, "", 1.0, WlTheme.GLOW)
		var c := cell_rect(i)
		var mid := Vector2(c.position.x + c.size.x * 0.5, c.position.y + 62.0)
		line(mid + Vector2(-22, 0), mid + Vector2(-6, 18), WlTheme.GLOW, 9.0)
		line(mid + Vector2(-6, 18), mid + Vector2(26, -22), WlTheme.GLOW, 9.0)


func _dynamo() -> void:
	var m := model
	var frac := float(m["bank_frac"])
	_cell(
		0,
		tr_key("TANK_CARD_BANK"),
		"%d" % roundi(float(m["bank"])),
		frac,
		WlTheme.WARN if frac < LOW_FRAC else WlTheme.ACCENT
	)
	_cell(
		1,
		tr_key("TANK_CARD_TARGET"),
		"%d" % roundi(float(m["target_pct"])),
		-1.0,
		WlTheme.ACCENT,
		"%"
	)
	_barrel_cell(2, m)
	if bool(m.get("stalled", false)):
		text(
			Vector2(0, 6),
			tr_key("TANK_TOAST_DYNAMO_STALLED"),
			LABEL_PX,
			WlTheme.WARN,
			696.0 - MARGIN,
			HORIZONTAL_ALIGNMENT_RIGHT
		)


## The barrel's elevation as a line from a pivot, an arrow for the facing and the angle in degrees.
func _barrel_cell(i: int, m: Dictionary) -> void:
	var c := cell_rect(i)
	var elev := float(m.get("elev_deg", 0.0))
	var facing := float(m.get("facing", 1))
	var pivot := c.position + Vector2(c.size.x * 0.5 - facing * 34.0, 100.0)
	var a := deg_to_rad(elev)
	var tip := pivot + Vector2(cos(a) * facing, -sin(a)) * 64.0
	line(pivot + Vector2(-facing * 14.0, 10.0), pivot, WlTheme.TEXT_DIM, 8.0)
	line(pivot, tip, WlTheme.TEXT, 8.0)
	var head := PackedVector2Array(
		[tip + Vector2(facing * 14.0, 0.0), tip + Vector2(0, -9), tip + Vector2(0, 9)]
	)
	polygon(head, WlTheme.ACCENT)
	line(
		Vector2(c.position.x + 6.0, 118.0), Vector2(c.end.x - 6.0, 118.0), WlTheme.PANEL_BORDER, 2.0
	)
	text(
		Vector2(c.position.x, 124.0),
		"%d°" % roundi(elev),
		32.0,
		WlTheme.TEXT,
		c.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _steam() -> void:
	var m := model
	_dial(cell_rect(0), m)
	var shell := str(m.get("shell", ""))
	_cell(1, tr_key("TANK_CARD_SHELL"), tr_key(shell) if shell != "" else "-", -1.0, WlTheme.ACCENT)
	var c := cell_rect(2)
	if float(m.get("window_s", 0.0)) > 0.0:
		_cell(
			2,
			tr_key("TANK_SHELL_OVER"),
			"%d" % ceili(float(m["window_s"])),
			float(m["window_frac"]),
			WlTheme.GLOW,
			"s"
		)
	elif bool(m.get("over", false)):
		_cell(
			2,
			tr_key("TANK_SHELL_OVER"),
			"%d" % roundi(float(m["pressure"])),
			float(m["over_frac"]),
			WlTheme.GLOW,
			"%"
		)
	else:
		text(
			c.position + Vector2(4, 0),
			tr_key("TANK_SHELL_OVER"),
			LABEL_PX,
			WlTheme.TEXT_DIM,
			c.size.x - 8.0
		)
		text(
			Vector2(c.position.x, c.position.y + 30.0),
			"-",
			KEY_PX,
			WlTheme.TEXT_DIM,
			c.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)


## The pressure dial: a half circle 0 .. 150% with marks at 40 (light shell), 100 (heavy shell) and
## 150 (Overpressure), a needle, and the pressure as the key number.
func _dial(c: Rect2, m: Dictionary) -> void:
	text(
		c.position + Vector2(4, 0),
		tr_key("TANK_CARD_PRESSURE"),
		LABEL_PX,
		WlTheme.TEXT_DIM,
		c.size.x - 8.0
	)
	var centre := Vector2(c.position.x + c.size.x * 0.5, c.position.y + 92.0)
	var r := 56.0
	var pts := PackedVector2Array()
	for s in 33:
		var a := PI + PI * float(s) / 32.0
		pts.append((centre + Vector2(cos(a), sin(a)) * r) * k())
	draw_polyline(pts, WlTheme.PANEL_BORDER, maxf(2.0, 8.0 * k()))
	var frac := float(m.get("dial_frac", 0.0))
	var fill := PackedVector2Array()
	var steps := maxi(2, int(ceilf(32.0 * frac)) + 1)
	for s in steps:
		var a := PI + PI * frac * float(s) / float(steps - 1)
		fill.append((centre + Vector2(cos(a), sin(a)) * r) * k())
	draw_polyline(
		fill,
		WlTheme.WARN if float(m.get("pressure", 0.0)) > 100.0 else WlTheme.ACCENT,
		maxf(2.0, 8.0 * k())
	)
	for mark: float in TankHudModel.STEAM_MARKS:
		var a := PI + PI * mark / TankHudModel.STEAM_DIAL_MAX
		var d := Vector2(cos(a), sin(a))
		line(centre + d * (r - 14.0), centre + d * (r + 8.0), WlTheme.TEXT, 4.0)
		text(
			centre + d * (r + 18.0) - Vector2(18.0 if mark > 99.0 else 12.0, 12.0),
			"%d" % int(mark),
			20.0,
			WlTheme.TEXT_DIM
		)
	var na := PI + PI * frac
	line(centre, centre + Vector2(cos(na), sin(na)) * (r - 6.0), WlTheme.TEXT, 5.0)
	text(
		Vector2(c.position.x, c.position.y + 96.0),
		"%d" % roundi(float(m.get("pressure", 0.0))),
		KEY_PX,
		WlTheme.TEXT,
		c.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _bulwark() -> void:
	var m := model
	_lever_cell(m)
	var hf := float(m.get("hoist_frac", 0.0))
	_cell(1, tr_key("TANK_CARD_HOIST"), "%d" % roundi(hf * 100.0), hf, WlTheme.ACCENT, "%")
	var halt := float(m.get("halt_m", -1.0))
	var unit := "km/h"
	_cell(
		2,
		tr_key("TANK_CARD_SPEED"),
		"%d" % roundi(float(m.get("speed_kmh", 0.0))),
		-1.0,
		WlTheme.ACCENT,
		unit
	)
	if halt >= 0.0:
		var c := cell_rect(2)
		text(
			Vector2(c.position.x, c.position.y + 108.0),
			"%d m" % ceili(halt),
			32.0,
			WlTheme.TEXT_DIM,
			c.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	elif bool(m.get("show_berm", false)):
		var c2 := cell_rect(2)
		var bf := float(m["berm"]) / maxf(float(m["berm_max"]), 1.0)
		bar(Rect2(c2.position + Vector2(4, 108), Vector2(c2.size.x - 8.0, 28)), bf, WlTheme.ACCENT)


## The lever: three positions side by side, the current one filled, an arrow while it moves, and
## the auto marker (a ring with the auto-lever label) when the auto-lever is in charge.
func _lever_cell(m: Dictionary) -> void:
	var c := cell_rect(0)
	text(
		c.position + Vector2(4, 0),
		tr_key("TANK_CARD_LEVER"),
		LABEL_PX,
		WlTheme.TEXT_DIM,
		c.size.x - 8.0
	)
	var cur := int(m.get("lever", 0))
	var to := int(m.get("lever_to", cur))
	var moving := float(m.get("move_s", 0.0)) > 0.0
	for i in 3:
		var r := lever_rect(i)
		var pos := LEVER_ORDER[i]
		var on := pos == cur and not moving
		var target := moving and pos == to
		rect(r, WlTheme.ACCENT if on else Color(1, 1, 1, 0.08))
		frame(r, WlTheme.GLOW if target else WlTheme.PANEL_BORDER, 3.0 if target else 2.0)
		var key := (
			"TANK_LEVER_DIG"
			if (pos == TankIds.LEVER_DRIVE and bool(m.get("dig", false)))
			else TankIds.LEVER_LABELS[pos]
		)
		var label_color := Color(0.05, 0.06, 0.08) if on else WlTheme.TEXT
		var label_at := r.position + Vector2(0, 10)
		text(
			label_at,
			tr_key(key),
			LEVER_PX,
			label_color,
			r.size.x,
			HORIZONTAL_ALIGNMENT_CENTER,
			not on
		)
		# The rack's tick under the box: a filled triangle under the current position.
		if on:
			var mid := r.position.x + r.size.x * 0.5
			polygon(
				PackedVector2Array(
					[
						Vector2(mid - 8.0, r.end.y + 14.0),
						Vector2(mid + 8.0, r.end.y + 14.0),
						Vector2(mid, r.end.y + 4.0)
					]
				),
				WlTheme.GLOW
			)
	if bool(m.get("auto", false)):
		var ring := Vector2(c.position.x + 14.0, c.end.y - 14.0)
		draw_arc(ring * k(), 9.0 * k(), 0.0, TAU, 20, WlTheme.GLOW, maxf(2.0, 3.0 * k()))
		text(
			Vector2(c.position.x + 30.0, c.end.y - 28.0),
			tr_key("TANK_LEVER_AUTO"),
			SMALL_PX,
			WlTheme.GLOW,
			c.size.x - 36.0
		)
