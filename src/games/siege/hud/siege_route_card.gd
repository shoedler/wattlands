class_name SiegeRouteCard
extends SiegeHudPanel
## The routing card (brief 3 HUD, bottom right above the PANIC button): where the local rider's
## watts go now ("Generator" or "Tower 3 (Ballista)"), the 2 s connect bar while a change
## reconnects, and four buttons that send the same route intents as the controls: previous, the
## generator, next, and the hot tower. The buttons are for a mouse or a touch screen; the
## keyboard, pad and Autopilot do the same through local_intents().

const CONNECT_S := 2.0
const BUTTON_SIZE := Vector2(84, 56)
## The control each button stands for (SiegeGame.local_intents maps it to the route target).
const ACTION_OF := {
	"prev": &"left",
	"gen": &"up",
	"next": &"right",
	"hot": &"down",
}

var caption_label: Label = null
var target_label: Label = null
var connect_label: Label = null
var connect_bar: ProgressBar = null
var buttons: Dictionary = {}


func _init() -> void:
	super._init()
	name = "SiegeRouteCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	caption_label = make_label(WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	box.add_child(caption_label)
	target_label = make_label(WlTheme.BODY_PX, WlTheme.TEXT, true)
	box.add_child(target_label)
	connect_label = make_label(WlTheme.LABEL_PX, WlTheme.ACCENT)
	box.add_child(connect_label)
	connect_bar = ProgressBar.new()
	connect_bar.show_percentage = false
	connect_bar.min_value = 0.0
	connect_bar.max_value = 1.0
	connect_bar.custom_minimum_size = Vector2(0, 16)
	connect_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(connect_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for spec: Array in [
		["prev", "SIEGE_HUD_BTN_PREV", "prev"],
		["gen", "SIEGE_HUD_BTN_GEN", "gen"],
		["next", "SIEGE_HUD_BTN_NEXT", "next"],
		["hot", "SIEGE_HUD_BTN_HOT", "hot"],
	]:
		var b := Button.new()
		b.name = "Btn_%s" % spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = BUTTON_SIZE
		b.add_theme_font_size_override("font_size", WlTheme.LABEL_PX)
		b.pressed.connect(_on_route_pressed.bind(str(spec[2])))
		row.add_child(b)
		buttons[spec[0]] = b
		b.set_meta("text_key", spec[1])
	custom_minimum_size = Vector2(400, 0)
	visible = false


## Goes through the module's local_intents, the path the keyboard and the pad take, so a client
## also predicts the new route at once instead of waiting for the host's route event.
func _on_route_pressed(to: String) -> void:
	if game == null:
		return
	var actions: Array[StringName] = [ACTION_OF[to]]
	var gestures: Array[StringName] = []
	for intent: Dictionary in game.local_intents(actions, gestures):
		intent["via"] = SiegeIds.VIA_BUTTON
		send(intent)


func refresh() -> void:
	var s := state()
	var r := own_rider()
	if s == null or r == null:
		visible = false
		return
	visible = true
	var tx := strings()
	caption_label.text = tx.t("SIEGE_HUD_ROUTE")
	target_label.text = SiegeHudModel.target_long(s, tx, r.target)
	var connecting := r.reconnect_s > 0.0
	connect_label.visible = connecting
	connect_bar.visible = connecting
	if connecting:
		connect_label.text = tx.t("SIEGE_HUD_CONNECTING")
		connect_bar.value = 1.0 - clampf(r.reconnect_s / CONNECT_S, 0.0, 1.0)
	for key: String in buttons:
		var b: Button = buttons[key]
		b.text = tx.t(str(b.get_meta("text_key")))
		# The shop's list owns directions while it is open.
		b.disabled = s.shop_open() or s.in_cooldown()
