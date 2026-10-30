class_name SiegeRouteCard
extends SiegeHudPanel
## The route card (docs/games/siege.md 3 HUD, bottom right): the five stations, each with its
## riders' slot chips and its cap ("1/2"), the local rider's own station marked, the hot station
## (Autopilot's pick) starred, the 2 s coupling bar while a change reconnects, and four buttons
## that send the same route intents as the controls (previous, mine, next, hot). Hidden while
## the shop is open: the shop's list owns the directions then.

const CONNECT_S := 2.0
const BUTTON_SIZE := Vector2(92, 52)
const ROW_PX := 28
const CHIP := Vector2(24, 24)
## The control each button stands for (SiegeGame.local_intents maps it to the route target).
const ACTION_OF := {"prev": &"left", "mine": &"up", "next": &"right", "hot": &"down"}

var caption_label: Label = null
var connect_label: Label = null
var connect_bar: ProgressBar = null
var name_labels: Array[Label] = []
var cap_labels: Array[Label] = []
var chip_rows: Array[HBoxContainer] = []
var chips: Array[Array] = []
var buttons: Dictionary = {}
## The rows as of the last refresh (tests read them).
var rows: Array[Dictionary] = []


func _init() -> void:
	super._init()
	name = "SiegeRouteCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	caption_label = make_label(WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	box.add_child(caption_label)
	for id in SiegeIds.STATION_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var nl := make_label(ROW_PX, WlTheme.TEXT)
		nl.custom_minimum_size = Vector2(190, 0)
		row.add_child(nl)
		name_labels.append(nl)
		var cr := HBoxContainer.new()
		cr.add_theme_constant_override("separation", 3)
		cr.custom_minimum_size = Vector2(4 * (CHIP.x + 3), CHIP.y)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cr)
		chip_rows.append(cr)
		var row_chips: Array = []
		for k in 4:
			var c := SlotChip.new()
			c.custom_minimum_size = CHIP
			c.visible = false
			cr.add_child(c)
			row_chips.append(c)
		chips.append(row_chips)
		var cl := make_label(ROW_PX, WlTheme.TEXT_DIM)
		row.add_child(cl)
		cap_labels.append(cl)
	connect_label = make_label(WlTheme.LABEL_PX, WlTheme.ACCENT)
	box.add_child(connect_label)
	connect_bar = ProgressBar.new()
	connect_bar.show_percentage = false
	connect_bar.min_value = 0.0
	connect_bar.max_value = 1.0
	connect_bar.custom_minimum_size = Vector2(0, 14)
	connect_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(connect_bar)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	box.add_child(brow)
	for spec: Array in [
		["prev", "SIEGE_HUD_BTN_PREV"],
		["mine", "SIEGE_HUD_BTN_MINE"],
		["next", "SIEGE_HUD_BTN_NEXT"],
		["hot", "SIEGE_HUD_BTN_HOT"],
	]:
		var b := Button.new()
		b.name = "Btn_%s" % spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = BUTTON_SIZE
		b.add_theme_font_size_override("font_size", WlTheme.SMALL_PX)
		b.clip_text = true
		b.pressed.connect(_on_route_pressed.bind(str(spec[0])))
		brow.add_child(b)
		buttons[spec[0]] = b
		b.set_meta("text_key", spec[1])
	custom_minimum_size = Vector2(400, 0)
	visible = false


## Goes through the module's local_intents, the path the keyboard and the pad take, so a client
## also predicts the new route at once.
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
	if s == null or r == null or s.shop_open() or s.in_cooldown():
		visible = false
		return
	visible = true
	var tx := strings()
	caption_label.text = tx.t("SIEGE_HUD_ROUTE")
	rows = SiegeHudModel.station_rows(s, tx, r)
	for row: Dictionary in rows:
		var id := int(row["id"])
		var mark := "> " if bool(row["mine"]) else ("* " if bool(row["hot"]) else "  ")
		name_labels[id].text = mark + str(row["name"])
		var col := WlTheme.ACCENT if bool(row["mine"]) else WlTheme.TEXT
		name_labels[id].label_settings = WlTheme.label_settings(ROW_PX, col, bool(row["mine"]))
		cap_labels[id].text = tx.t("SIEGE_HUD_CAP", [row["count"], row["cap"]])
		cap_labels[id].modulate = WlTheme.WARN if bool(row["full"]) else Color.WHITE
		var slots: Array = row["riders"]
		for k in 4:
			var c: SlotChip = chips[id][k]
			c.visible = k < slots.size()
			if c.visible:
				c.set_slot(int(slots[k]))
				c.set_look(look_of(game, int(slots[k])))
	var connecting := r.reconnect_s > 0.0
	connect_label.visible = connecting
	connect_bar.visible = connecting
	if connecting:
		connect_label.text = tx.t("SIEGE_HUD_CONNECTING")
		connect_bar.value = 1.0 - clampf(r.reconnect_s / CONNECT_S, 0.0, 1.0)
	for key: String in buttons:
		var b: Button = buttons[key]
		b.text = tx.t(str(b.get_meta("text_key")))
