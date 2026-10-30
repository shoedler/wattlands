class_name SiegeWaveInfo
extends SiegeHudPanel
## The wave line under the timeline (docs/games/siege.md 3 HUD): one line of the enemies left by
## type ("Spearmen 33  Shield bearers 10  Chariots 8  +3 waiting") and, before it in orange, the
## most urgent warning (a Breach, boarders, a rush, a siege tower or a ram closing in, a rush
## coming, a failing gate). The timeline above already names the wave. Hidden while there is
## nothing to say.

const TEXT_PX := 22

var counts_label: Label = null
var warn_label: Label = null


func _init() -> void:
	super._init()
	name = "SiegeWaveInfo"
	var sb := WlTheme.panel_style()
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	warn_label = make_label(TEXT_PX, WlTheme.WARN, true)
	row.add_child(warn_label)
	counts_label = make_label(TEXT_PX, WlTheme.TEXT_DIM)
	counts_label.clip_text = true
	counts_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(counts_label)
	visible = false


func refresh() -> void:
	var s := state()
	if s == null:
		visible = false
		return
	var tx := strings()
	counts_label.text = "  ".join(SiegeHudModel.enemy_lines(s, tx))
	var w := SiegeHudModel.warning(s)
	warn_label.visible = not w.is_empty()
	warn_label.text = tx.t(w["key"], w["args"]) if not w.is_empty() else ""
	warn_label.modulate = Color(1, 0.55, 0.45) if int(w.get("level", 0)) >= 2 else Color.WHITE
	visible = counts_label.text != "" or warn_label.visible
