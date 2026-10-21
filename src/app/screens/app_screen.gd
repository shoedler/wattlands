class_name AppScreen
extends Control
## Base of every app-shell screen (BRIEF 3.5, 3.9). A screen shows one active pedal-scan menu
## (a PedalScanList) at a time, kept on a stack for sub-menus (option values, steppers, the
## on-screen keyboard). Input reaches only the active menu: the screen listens to InputRouter's
## actions and gestures and feeds them with feed_action()/feed_gesture(), and drives its scan
## timer with tick(dt), so several lists never react to one surge.
## Pedal-scan: focus cycles every scan interval (profile setting, 1.6 s); surge or confirm picks;
## coast or back backs out; up and down move focus. Keyboard and controller work the same way.

## Emitted when the screen asks to leave (tests watch it; screens call services.goto).
signal leaving(state: String)

var services: AppServices = null
var params: Dictionary = {}
## False in tests: time advances only through tick(dt).
var auto_process: bool = true
## The menu stack (top = active).
var menus: Array[PedalScanList] = []
## Per menu: {"pick": Callable(index, id, auto), "back": Callable(), "items": Array}.
var _menu_info: Array[Dictionary] = []
var _menu_holder: Control = null
var _connected: bool = false
## Set while a text field owns the keyboard (routed actions then go only to back/confirm).
var text_focus: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Called by the main scene once the screen is in the tree.
func enter(p_params: Dictionary = {}) -> void:
	params = p_params
	_connect_input()
	_build()


## Called before the screen is freed: disconnect everything external.
func leave() -> void:
	_disconnect_input()
	_on_leave()


func _exit_tree() -> void:
	_disconnect_input()


## Override: build the screen's Controls and its first menu.
func _build() -> void:
	pass


## Override: release external connections.
func _on_leave() -> void:
	pass


## Override: per-tick logic (dt in seconds).
func _tick(_dt: float) -> void:
	pass


## Override: return true when the screen consumed the action itself.
func _handle_action(_action: StringName) -> bool:
	return false


## Override: return true when the screen consumed the gesture itself.
func _handle_gesture(_gesture: StringName) -> bool:
	return false


func _process(delta: float) -> void:
	if auto_process:
		tick(delta)


func tick(dt: float) -> void:
	var m := active_menu()
	if m != null:
		m.tick(dt)
	_tick(dt)


## Route an action (keyboard, controller, on-screen) to the screen, then to the active menu.
func feed_action(action: StringName) -> void:
	if text_focus and action != &"back" and action != &"confirm":
		return
	if _handle_action(action):
		return
	var m := active_menu()
	if m != null:
		m.feed_action(action)


## Route a pedal gesture to the screen, then to the active menu.
func feed_gesture(gesture: StringName) -> void:
	if _handle_gesture(gesture):
		return
	var m := active_menu()
	if m != null:
		m.feed_gesture(gesture)


func goto(state: String, p: Dictionary = {}) -> void:
	leaving.emit(state)
	if services != null:
		services.goto(state, p)


# --- menus ---------------------------------------------------------------------------------

## The container menus are placed in (created on first use if the screen set none).
func menu_holder() -> Control:
	if _menu_holder == null:
		_menu_holder = AppStyle.vbox(8)
		_menu_holder.custom_minimum_size = Vector2(620, 0)
		add_child(_menu_holder)
	return _menu_holder


func set_menu_holder(holder: Control) -> void:
	_menu_holder = holder


func active_menu() -> PedalScanList:
	return menus[menus.size() - 1] if not menus.is_empty() else null


## Push a pedal-scan menu. items: [{"id", "text", "disabled"?, "detail"?}]. pick(index, id,
## auto) runs on a pick; back() on coast/back (default: pop this menu, or nothing on the root).
func push_menu(items: Array, pick: Callable, back: Callable = Callable(), highlight: int = -1) -> PedalScanList:
	var list := services.make_scan_list() if services != null else PedalScanList.new()
	list.listen_to_input = false
	list.set_process(false)
	# The screen plays the ui_move/ui_confirm/ui_back cues through services (one cue per event);
	# the list's own Sfx cues would double them.
	list.sounds = false
	list.name = "Menu%d" % menus.size()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var prev := active_menu()
	if prev != null:
		prev.visible = false
	menu_holder().add_child(list)
	# After _ready: the screen drives the scan timer (tick) and feeds input, never the list itself.
	list.set_process(false)
	list.listen_to_input = false
	menus.append(list)
	_menu_info.append({"pick": pick, "back": back, "items": items.duplicate(true)})
	_configure_list(list)
	list.set_items(items)
	if highlight >= 0:
		list.set_highlight(highlight)
	list.item_chosen.connect(_on_item_chosen.bind(list))
	list.backed_out.connect(_on_backed_out.bind(list))
	list.highlight_changed.connect(_on_highlight_changed.bind(list))
	return list


## Replace the active menu's items in place (keeps the highlight when possible).
func refresh_menu(items: Array, list: PedalScanList = null) -> void:
	var m := list if list != null else active_menu()
	if m == null:
		return
	var i := menus.find(m)
	if i < 0:
		return
	if items == _menu_info[i]["items"]:
		return
	var keep := m.highlighted()
	_menu_info[i]["items"] = items.duplicate(true)
	m.set_items(items)
	if keep >= 0 and keep < items.size() and not bool((items[keep] as Dictionary).get("disabled", false)):
		m.set_highlight(keep)


func pop_menu() -> void:
	if menus.is_empty():
		return
	var m: PedalScanList = menus.pop_back()
	_menu_info.pop_back()
	if is_instance_valid(m):
		m.get_parent().remove_child(m)
		m.queue_free()
	var top := active_menu()
	if top != null:
		top.visible = true


## Pop every menu above the root.
func pop_to_root() -> void:
	while menus.size() > 1:
		pop_menu()


## Remove every menu (before rebuilding a screen page).
func clear_menus() -> void:
	while not menus.is_empty():
		pop_menu()


func menu_items_of(list: PedalScanList = null) -> Array:
	var m := list if list != null else active_menu()
	var i := menus.find(m)
	return _menu_info[i]["items"] if i >= 0 else []


## Index of the item with `id` in the active menu, or -1.
func item_index(id: Variant, list: PedalScanList = null) -> int:
	var items := menu_items_of(list)
	for i in items.size():
		if same_id((items[i] as Dictionary).get("id"), id):
			return i
	return -1


## Item ids may mix ints and Strings (rides by index plus "back"); never compare across types.
static func same_id(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var num_a := ta == TYPE_INT or ta == TYPE_FLOAT
	var num_b := tb == TYPE_INT or tb == TYPE_FLOAT
	if num_a and num_b:
		return a == b
	if ta != tb:
		if (ta == TYPE_STRING or ta == TYPE_STRING_NAME) and (tb == TYPE_STRING or tb == TYPE_STRING_NAME):
			return str(a) == str(b)
		return false
	return a == b


## Pick the item with `id` in the active menu as if confirmed (on-screen buttons, tests).
func pick_id(id: Variant) -> bool:
	var i := item_index(id)
	if i < 0:
		return false
	var m := active_menu()
	m.set_highlight(i)
	m.feed_action(&"confirm")
	return true


## Apply the profile's pedal-UI settings to a list.
func _configure_list(list: PedalScanList) -> void:
	var p := services.profile() if services != null else RiderProfile.new()
	list.scan_interval_s = clampf(p.scan_interval_s, 0.5, 10.0)
	list.scanning = scanning_enabled()
	list.erg_auto_confirm = false


## Pedal-scan on (BRIEF 3.5): InputRouter.pedal_ui_active() decides (Autopilot or pedal UI on,
## or no input device used yet); without a router, the profile's pedal UI or Autopilot flag.
## Screens may override.
func scanning_enabled() -> bool:
	if services != null and services.input != null:
		return services.input.pedal_ui_active()
	var p := services.profile() if services != null else RiderProfile.new()
	return p.pedal_ui or p.autopilot_default


## While the field's LineEdit has keyboard focus, routed actions (WASD, Space...) stay out of
## the menus; Esc and Enter still work.
func watch_text_focus(field: AppTextField) -> void:
	if field == null or field.line_edit == null:
		return
	field.line_edit.focus_entered.connect(func() -> void: text_focus = true)
	field.line_edit.focus_exited.connect(func() -> void: text_focus = false)
	field.tree_exiting.connect(func() -> void: text_focus = false)


func set_scanning(on: bool) -> void:
	for m in menus:
		m.scanning = on


func _on_item_chosen(index: int, id: Variant, auto: bool, list: PedalScanList) -> void:
	if list != active_menu():
		return
	var i := menus.find(list)
	if i < 0:
		return
	if services != null:
		services.play_sound("ui_confirm")
	var pick: Callable = _menu_info[i]["pick"]
	if pick.is_valid():
		pick.call(index, id, auto)


func _on_backed_out(list: PedalScanList) -> void:
	if list != active_menu():
		return
	var i := menus.find(list)
	if i < 0:
		return
	if services != null:
		services.play_sound("ui_back")
	var back: Callable = _menu_info[i]["back"]
	if back.is_valid():
		back.call()
	elif menus.size() > 1:
		pop_menu()


func _on_highlight_changed(_index: int, list: PedalScanList) -> void:
	if list == active_menu() and services != null:
		services.play_sound("ui_move")


# --- input ---------------------------------------------------------------------------------

func _connect_input() -> void:
	if _connected or services == null or services.input == null:
		return
	services.input.action.connect(_on_router_action)
	services.input.gesture.connect(_on_router_gesture)
	_connected = true


func _disconnect_input() -> void:
	if not _connected or services == null or services.input == null:
		_connected = false
		return
	if services.input.action.is_connected(_on_router_action):
		services.input.action.disconnect(_on_router_action)
	if services.input.gesture.is_connected(_on_router_gesture):
		services.input.gesture.disconnect(_on_router_gesture)
	_connected = false


func _on_router_action(action: StringName) -> void:
	feed_action(action)


func _on_router_gesture(gesture: StringName) -> void:
	feed_gesture(gesture)


# --- helpers ---------------------------------------------------------------------------------

## Translated text.
static func t(key: String, args: Variant = []) -> String:
	var s := String(TranslationServer.translate(key))
	if args is Array and not (args as Array).is_empty():
		return s.format(args)
	if args is Dictionary and not (args as Dictionary).is_empty():
		return s.format(args)
	return s


## A standard page: background, margins, a title row, a content row (left) and the menu column
## (right). Returns {"root", "title", "left", "right", "footer"}.
func make_page(title_text: String) -> Dictionary:
	add_child(AppStyle.background())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, AppStyle.MARGIN)
	add_child(margin)
	var root := AppStyle.vbox(24)
	margin.add_child(root)
	var title := AppStyle.label(title_text, AppStyle.FONT_HEADING, AppStyle.TEXT)
	title.name = "Title"
	root.add_child(title)
	var row := AppStyle.hbox(48)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)
	var left_col := AppStyle.vbox(16)
	left_col.name = "Content"
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_col)
	var right_col := AppStyle.vbox(8)
	right_col.name = "MenuColumn"
	right_col.custom_minimum_size = Vector2(640, 0)
	row.add_child(right_col)
	set_menu_holder(right_col)
	var footer := AppStyle.label("", AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
	footer.name = "Footer"
	root.add_child(footer)
	return {"root": root, "title": title, "left": left_col, "right": right_col, "footer": footer}
