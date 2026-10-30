class_name SiegeWaveInfo
extends SiegeHudPanel
## Wave info under the timeline (docs/games/siege.md 3 HUD): "Wave 2/3", the enemies left by
## type, the team's watts and the most urgent warning (a Breach, boarders, a rush, a siege tower
## or a ram closing in, a rush coming, a failing gate). Hidden while there is nothing to say.

var title_label: Label = null
var enemy_labels: Array[Label] = []
var warn_label: Label = null


func _init() -> void:
	super._init()
	name = "SiegeWaveInfo"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	title_label = make_label(WlTheme.MENU_PX, WlTheme.TEXT, true)
	box.add_child(title_label)
	for i in 2:
		var l := make_label(WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
		enemy_labels.append(l)
		box.add_child(l)
	warn_label = make_label(WlTheme.BODY_PX, WlTheme.WARN, true)
	box.add_child(warn_label)
	custom_minimum_size = Vector2(480, 0)
	visible = false


func refresh() -> void:
	var s := state()
	if s == null:
		visible = false
		return
	var tx := strings()
	# the timeline already names a break; the card speaks up there only for a warning
	var title := SiegeHudModel.wave_title(s, tx) if s.in_wave() or s.in_cooldown() else ""
	title_label.text = title
	title_label.visible = title != ""
	var lines := SiegeHudModel.enemy_lines(s, tx)
	for i in enemy_labels.size():
		enemy_labels[i].text = lines[i] if i < lines.size() else ""
		enemy_labels[i].visible = i < lines.size()
	var w := SiegeHudModel.warning(s)
	warn_label.visible = not w.is_empty()
	warn_label.text = tx.t(w["key"], w["args"]) if not w.is_empty() else ""
	warn_label.modulate = Color(1, 0.55, 0.45) if int(w.get("level", 0)) >= 2 else Color.WHITE
	visible = title != "" or not w.is_empty()
