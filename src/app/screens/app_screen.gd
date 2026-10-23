class_name AppScreen
extends Control
## Base of every app-shell screen (BRIEF 3.5, 3.9). A screen shows one active pedal-scan menu
## (a PedalScanList) at a time, kept on a stack for sub-menus (option values, steppers, the
## on-screen keyboard). Input reaches only the active menu: the screen listens to InputRouter's
## actions and gestures and feeds them with feed_action()/feed_gesture(), and drives its scan
## timer with tick(dt), so several lists never react to one surge.
## Pedal navigation is opt-in (Settings, BRIEF 3.5): with it on, focus cycles every scan interval
## (profile setting, 1.6 s), surge picks, coast backs out and a surge feedback graph shows the
## power a surge needs; with it off every menu answers the keyboard and controller only.
## Confirm and back pick and back out; up and down move focus either way.
## Each tick the active menu learns the local rider's trainer mode (local_trainer_mode()): in
## ERG coast never means back (BRIEF 3.5), so its hint says "keep pedaling" (UI_SCAN_HINT_ERG)
## and a coast doesn't back out. Only the mode is passed: menus never ERG-auto-pick here.
## surge_graph is the page's live power graph (make_page); it shows with pedal navigation.

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
## The ScrollContainer around the menu holder when the page's menu column scrolls
## (scroll_menu_column); null on the screens whose menus always fit.
var menu_scroll: ScrollContainer = null
## The surge feedback graph under the page (make_page): on while pedal navigation is.
var surge_graph: WlSurgeGraph = null
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


## The app is quitting: stop for good without leaving (leave() would hand ticking back and
## re-set the menu rider up before App.quit shuts it down). No more input, ticks or _process
## in this screen or any node under it (a GameHost or the FTP test's rider clock), whatever
## their process_mode. The screen stays on show until the tree quits.
func freeze() -> void:
	_disconnect_input()
	auto_process = false
	propagate_call("set_process", [false])
	propagate_call("set_physics_process", [false])


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
		m.set_local_mode(local_trainer_mode())
		m.tick(dt)
	if surge_graph != null and is_instance_valid(surge_graph):
		surge_graph.tick(dt)
	_tick(dt)


## The trainer mode of the rider the menus follow ("ERG", "SIM", "OFF"; "" when unknown): the
## InputRouter's attached rider. The session screen answers with its own local rider.
func local_trainer_mode() -> String:
	if services != null and services.input != null:
		return services.input.local_mode()
	return ""


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


## Make `column` (a page's menu column, before the first push_menu) hold the menus in a vertical
## ScrollContainer (BRIEF 3.9, every screen works with pedal-scan): a menu taller than the column
## scrolls inside it, and the active menu's highlighted row (with the scan hint under the last
## row) is kept fully in view on every highlight change, by scan, keyboard or controller, and
## again whenever the menus' layout changes. A menu that fits never scrolls and sits at the top
## of the column as before. Returns the ScrollContainer (also menu_scroll).
func scroll_menu_column(column: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "MenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var holder := AppStyle.vbox(8)
	holder.name = "Menus"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	set_menu_holder(holder)
	menu_scroll = scroll
	# Deferred: a Container ignores queue_sort() while it emits sort_children, so a scroll set from
	# inside that signal would never move the menus.
	scroll.sort_children.connect(follow_highlight, CONNECT_DEFERRED)
	holder.sort_children.connect(follow_highlight, CONNECT_DEFERRED)
	return scroll


## Scroll menu_scroll so the active menu's highlighted row is fully in view; on the last row the
## scan hint under it too. Positions are the menus' own layout (the active menu is the holder's
## only visible child), so it holds for any scroll. Does nothing without scroll_menu_column.
func follow_highlight() -> void:
	if menu_scroll == null or not is_instance_valid(menu_scroll):
		return
	var m := active_menu()
	if m == null or not is_instance_valid(m):
		return
	var row := m.row(m.highlighted())
	if row == null:
		return
	var top := m.position.y + row.position.y
	var bottom := top + row.size.y
	if m.highlighted() == m.item_count() - 1:
		bottom = m.position.y + m.size.y
	var panel := menu_scroll.get_theme_stylebox("panel")
	var view_h := menu_scroll.size.y - (panel.get_minimum_size().y if panel != null else 0.0)
	if view_h <= 0.0:
		return  # Not laid out yet: its sort_children calls this again.
	var at := menu_scroll.scroll_vertical
	if bottom - float(at) > view_h:
		at = ceili(bottom - view_h)
	if top < float(at):
		at = floori(top)
	if at != menu_scroll.scroll_vertical:
		menu_scroll.scroll_vertical = at


func active_menu() -> PedalScanList:
	return menus[menus.size() - 1] if not menus.is_empty() else null


## Push a pedal-scan menu. items: [{"id", "text", "disabled"?, "detail"?}]. pick(index, id,
## auto) runs on a pick; back() on coast/back (default: pop this menu, or nothing on the root).
func push_menu(
	items: Array, pick: Callable, back: Callable = Callable(), highlight: int = -1
) -> PedalScanList:
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
	list.set_local_mode(local_trainer_mode())
	list.set_items(items)
	if highlight >= 0:
		list.set_highlight(highlight)
	list.item_chosen.connect(_on_item_chosen.bind(list))
	list.backed_out.connect(_on_backed_out.bind(list))
	list.highlight_changed.connect(_on_highlight_changed.bind(list))
	if menu_scroll != null:
		# Rows built or refreshed get their positions when the list sorts them.
		list.sort_children.connect(follow_highlight, CONNECT_DEFERRED)
	_scroll_to_new_menu()
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
	if (
		keep >= 0
		and keep < items.size()
		and not bool((items[keep] as Dictionary).get("disabled", false))
	):
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
	_scroll_to_new_menu()


## A menu was pushed or uncovered: with scroll_menu_column, the column starts at the top of that
## menu and then scrolls only as far as its highlighted row needs (follow_highlight).
func _scroll_to_new_menu() -> void:
	if menu_scroll == null or not is_instance_valid(menu_scroll):
		return
	menu_scroll.scroll_vertical = 0
	follow_highlight()


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
		if (
			(ta == TYPE_STRING or ta == TYPE_STRING_NAME)
			and (tb == TYPE_STRING or tb == TYPE_STRING_NAME)
		):
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
	list.pedal_nav = pedal_nav_enabled()
	list.scanning = scanning_enabled()
	list.erg_auto_confirm = false


## Pedal navigation on (BRIEF 3.5, opt-in): InputRouter.pedal_nav_active() decides (the rider's
## Settings toggle, or Autopilot as their default); without a router, the profile's flags. Off:
## menus ignore surge and coast and never scan. Screens may override (a session's Autopilot).
func pedal_nav_enabled() -> bool:
	if services != null and services.input != null:
		return services.input.pedal_nav_active()
	var p := services.profile() if services != null else RiderProfile.new()
	return p.pedal_nav or p.autopilot_default


## Menus scan (focus cycles by itself): pedal navigation on. The title holds its first item
## while the zero-touch countdown runs.
func scanning_enabled() -> bool:
	return pedal_nav_enabled()


## While the field's LineEdit has keyboard focus, routed actions (WASD, Space...) stay out of
## the menus (WlInputRouter drops key presses then); Enter submits the field. A screen whose
## keys must keep working there takes the focus off the field first (the join page does for Esc
## and the arrows, W4r2 R27).
func watch_text_focus(field: AppTextField) -> void:
	if field == null or field.line_edit == null:
		return
	field.line_edit.focus_entered.connect(func() -> void: text_focus = true)
	field.line_edit.focus_exited.connect(func() -> void: text_focus = false)
	field.tree_exiting.connect(func() -> void: text_focus = false)


## Apply the scan state and pedal navigation to every open menu and the graph (Settings toggles
## it live).
func set_scanning(on: bool) -> void:
	var nav := pedal_nav_enabled()
	for m in menus:
		m.pedal_nav = nav
		m.scanning = on
	if surge_graph != null:
		surge_graph.enabled = nav


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
	if list != active_menu():
		return
	if services != null:
		services.play_sound("ui_move")
	follow_highlight()


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
	surge_graph = WlSurgeGraph.new()
	surge_graph.real_time = false
	surge_graph.enabled = pedal_nav_enabled()
	surge_graph.size_flags_horizontal = Control.SIZE_SHRINK_END
	surge_graph.custom_minimum_size = Vector2(640, 132)
	root.add_child(surge_graph)

	return {"root": root, "title": title, "left": left_col, "right": right_col, "footer": footer}
