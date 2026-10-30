class_name SiegeStripCell
extends PanelContainer
## One rider's cell in Siege's teammate strip (bottom centre): the slot's chip, the station the
## rider drives, raw watts and %FTP from the state (the snapshot's on a client), and markers:
## Overdrive on or recharging, rescue, AFK. The local rider's cell has an accent border.

## Four cells and their gaps fit between the corner stacks.
const SIZE := Vector2(240, 0)
const WATTS_PX := 24
const STATUS_PX := 20

var slot: int = 0
var chip: SlotChip = null
var target_label: Label = null
var od_label: Label = null
var status_label: Label = null
var watts_label: Label = null
var is_local: bool = false


func _init(p_slot: int = 0) -> void:
	slot = p_slot
	name = "Cell%d" % slot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = WlTheme.get_theme()
	add_theme_stylebox_override("panel", _style(false))
	custom_minimum_size = SIZE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	chip = SlotChip.new()
	chip.custom_minimum_size = Vector2(30, 30)
	chip.set_slot(slot)
	top.add_child(chip)
	target_label = SiegeHudPanel.make_label(WlTheme.LABEL_PX, WlTheme.TEXT, true)
	top.add_child(target_label)
	top.add_child(_spacer())
	od_label = SiegeHudPanel.make_label(WlTheme.SMALL_PX, WlTheme.ACCENT, true)
	top.add_child(od_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	watts_label = SiegeHudPanel.make_label(WATTS_PX, WlTheme.TEXT_DIM)
	bottom.add_child(watts_label)
	bottom.add_child(_spacer())
	status_label = SiegeHudPanel.make_label(STATUS_PX, WlTheme.WARN, true)
	bottom.add_child(status_label)


static func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func set_look(look: Dictionary) -> void:
	chip.set_look(look)


func set_local(on: bool) -> void:
	if on == is_local:
		return
	is_local = on
	add_theme_stylebox_override("panel", _style(on))


static func _style(local: bool) -> StyleBoxFlat:
	var border := WlTheme.ACCENT if local else WlTheme.PANEL_BORDER
	var sb := WlTheme.panel_style(WlTheme.PANEL, border, 4 if local else 2)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	return sb


## Fills the cell from `rider` (null: an empty wheel, the cell hides).
func show_rider(rider: SiegeRiderState, strings: GameStrings) -> void:
	visible = rider != null
	if rider == null:
		return
	target_label.text = strings.t(SiegeGame.station_key(rider.target))
	target_label.modulate = Color(1, 1, 1, 1.0 if rider.delivering() else 0.55)
	watts_label.text = "%d W  %d%%" % [roundi(rider.raw_w), SiegeHudModel.pct_ftp(rider)]
	od_label.text = ""
	match rider.od_state:
		SiegeIds.OD_ACTIVE, SiegeIds.OD_PENDING:
			od_label.text = "%s %d" % [strings.t("SIEGE_HUD_MARK_OD"), ceili(rider.od_s)]
		SiegeIds.OD_COOLDOWN:
			od_label.text = "%s ..." % strings.t("SIEGE_HUD_MARK_OD")
	var marks: Array[String] = []
	if rider.rescue:
		marks.append(strings.t("SIEGE_HUD_MARK_RESCUE"))
	if rider.afk or not rider.connected:
		marks.append(strings.t("SIEGE_HUD_MARK_AFK"))
	status_label.text = " ".join(marks)
	modulate.a = 0.6 if (rider.afk or not rider.connected) else 1.0
