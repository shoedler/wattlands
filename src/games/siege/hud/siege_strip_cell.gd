class_name SiegeStripCell
extends PanelContainer
## One rider's cell in Siege's own strip (bottom centre, above the kit's teammate strip): the
## slot's chip, the routing target as an icon with its name, the rider's raw watts and %FTP
## from the snapshot, and markers: Overdrive on or recharging, rescue, AFK. The raw W and %FTP
## come from the state's rider row (the host's own values, the snapshot's on a client), so a
## client's strip is as fresh as the 10 Hz snapshot.

const SIZE := Vector2(260, 0)

var slot: int = 0
var chip: SlotChip = null
var icon: SiegeTargetIcon = null
var target_label: Label = null
var marker_label: Label = null
var watts_label: Label = null


func _init(p_slot: int = 0) -> void:
	slot = p_slot
	name = "Cell%d" % slot
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = WlTheme.get_theme()
	add_theme_stylebox_override("panel", WlTheme.panel_style())
	custom_minimum_size = SIZE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	chip = SlotChip.new()
	chip.custom_minimum_size = Vector2(34, 34)
	chip.set_slot(slot)
	top.add_child(chip)
	icon = SiegeTargetIcon.new()
	top.add_child(icon)
	target_label = SiegeHudPanel.make_label(WlTheme.BODY_PX, WlTheme.TEXT, true)
	top.add_child(target_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	marker_label = SiegeHudPanel.make_label(WlTheme.SMALL_PX, WlTheme.WARN, true)
	top.add_child(marker_label)
	watts_label = SiegeHudPanel.make_label(WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	col.add_child(watts_label)


## Sets the chip's look (the session's color and pattern for the slot).
func set_look(look: Dictionary) -> void:
	chip.set_look(look)


## Fills the cell from `rider` (null: an empty wheel, the cell shows nothing).
func show_rider(rider: SiegeRiderState, strings: GameStrings, color: Color) -> void:
	visible = rider != null
	if rider == null:
		return
	var dim := not rider.delivering()
	icon.set_target(rider.target, color, dim)
	target_label.text = SiegeHudModel.target_short(strings, rider.target)
	watts_label.text = "%d W  %d%%" % [roundi(rider.raw_w), SiegeHudModel.pct_ftp(rider)]
	var marks: Array[String] = []
	match rider.od_state:
		SiegeIds.OD_ACTIVE, SiegeIds.OD_PENDING:
			marks.append("%s %d" % [strings.t("SIEGE_HUD_MARK_OD"), ceili(rider.od_s)])
		SiegeIds.OD_COOLDOWN:
			marks.append("%s ..." % strings.t("SIEGE_HUD_MARK_OD"))
	if rider.rescue:
		marks.append(strings.t("SIEGE_HUD_MARK_RESCUE"))
	if rider.afk or not rider.connected:
		marks.append(strings.t("SIEGE_HUD_MARK_AFK"))
	marker_label.text = " ".join(marks)
	modulate.a = 0.6 if (rider.afk or not rider.connected) else 1.0
