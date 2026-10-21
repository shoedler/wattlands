class_name AppScriptedScreen
extends AppScreen
## What a windowed scripted peer shows (the e2e harness usually runs headless): the game's view
## and HUD layers for the GameHost, plus one status line (role, room, state). No menus.

var view_layer: Control = null
var hud_layer: Control = null
var status_label: Label = null


func _build() -> void:
	add_child(AppStyle.background(Color.BLACK))
	view_layer = Control.new()
	view_layer.name = "View"
	view_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_layer)
	hud_layer = Control.new()
	hud_layer.name = "Hud"
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_layer)
	status_label = AppStyle.label(t("APP_SCRIPTED"), AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
	status_label.name = "Status"
	status_label.position = Vector2(24, 16)
	add_child(status_label)


func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
