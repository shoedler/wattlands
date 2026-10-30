class_name SiegeCurtainCard
extends SiegeHudPanel
## The tar curtain beside the gate readout (docs/games/siege.md 3 HUD, top right): the curtain's
## HP as a big number (at least 48 px), a bar of it, and the litres left in the cauldrons. The
## gate's HP and the rider's gold are the kit readouts above and below it (READOUT_GATE,
## READOUT_GOLD, fed by the module).

const NUMBER_PX := WlTheme.KEY_NUMBER_MIN_PX

var caption_label: Label = null
var value_label: Label = null
var bar: ProgressBar = null
var cauldron_label: Label = null


func _init() -> void:
	super._init()
	name = "SiegeCurtainCard"
	var sb := WlTheme.panel_style()
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	# caption and cauldrons on one small line, the curtain's HP big under it, then its bar
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	caption_label = make_label(WlTheme.SMALL_PX - 4, WlTheme.TEXT_DIM)
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(caption_label)
	cauldron_label = make_label(WlTheme.SMALL_PX - 4, WlTheme.TEXT_DIM)
	top.add_child(cauldron_label)
	value_label = make_label(NUMBER_PX, WlTheme.TEXT, true)
	box.add_child(value_label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(0, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	custom_minimum_size = Vector2(200, 0)
	visible = false


func refresh() -> void:
	var s := state()
	if s == null:
		visible = false
		return
	visible = true
	var tx := strings()
	caption_label.text = tx.t("SIEGE_HUD_CURTAIN")
	value_label.text = SiegeHudModel.curtain_text(s)
	bar.value = clampf(s.tar.curtain_hp / maxf(s.curtain_max(), 1.0), 0.0, 1.0)
	cauldron_label.text = SiegeHudModel.cauldron_text(s, tx)
