class_name PedalScanList
extends VBoxContainer
## A pedal-scan (single-switch scanning) list for menus, game shops and pickers (BRIEF 3.5,
## 3.9). Owned by ui-hud; public API frozen after W0.
## With scanning on, focus cycles through the enabled items every `scan_interval_s`
## (default 1.6 s, the profile setting); `surge` (or confirm) picks the highlighted item and
## `coast` (or back) backs out. Keyboard/controller up/down move focus and stop scanning for
## 10 s. With erg_auto_confirm on (picks shown during ERG phases), the highlighted item is
## picked automatically after two full scan cycles; such picks report auto = true.
## Time advances in _process (PROCESS_MODE_ALWAYS) or through tick(dt) in headless tests.
##
## Details:
## - Disabled items are skipped by scanning and by focus moves and can't be picked.
## - Left and right move focus like up and down (horizontal pickers such as Fishing's spots).
## - Auto-confirm: after auto_confirm_after_s() = 2 x enabled items x scan_interval_s without
##   input, whether scanning is on or not. Any input (focus move, pick) restarts that count,
##   and so does a pick, so a list left open auto-picks again two cycles later. With scanning
##   on and no input, two full cycles bring the highlight back to where it started, so the
##   auto-pick lands on the item highlighted when the count began (put the recommended item
##   first).
## - `coast` never backs out while the local rider is in ERG (set_local_mode or, with
##   follow_local_mode, the InputRouter's attached rider, read on every tick). With no mode
##   known, erg_auto_confirm on counts as ERG (a game that sets it from Telemetry.mode).
## - With listen_to_input on, the list follows InputRouter.menu_input while it is visible.

## index, the item's id, and whether the pick was an ERG auto-confirm.
signal item_chosen(index: int, id: Variant, auto: bool)
## The same pick with its source: "action" (keyboard/controller confirm), "surge" (pedal
## gesture) or "auto" (ERG auto-confirm). Emitted together with item_chosen.
signal item_picked(index: int, id: Variant, via: String)
signal backed_out
signal highlight_changed(index: int)

## Seconds a focus move pauses scanning.
const MANUAL_PAUSE_S := 10.0
const MIN_INTERVAL_S := 0.2

var scan_interval_s: float = 1.6
var scanning: bool = true
var erg_auto_confirm: bool = false
## In sessions: erg_auto_confirm follows the local rider's trainer mode (on while in ERG).
## Auto-confirm fires after two full cycles in ERG even with scanning off.
var follow_local_mode: bool = false
## Follow InputRouter actions and gestures automatically (off in headless tests).
var listen_to_input: bool = true:
	set(value):
		listen_to_input = value
		_update_listening()

## _process advances the timers while the list is visible (tests turn it off and call tick).
var real_time: bool = true
## Play Sfx cues (ui_move on highlight changes, ui_confirm on picks, ui_back on back).
var sounds: bool = true
## Show the hint line under the items (how to pick; the ERG auto-pick countdown).
var show_hint: bool = true:
	set(value):
		show_hint = value
		if _hint != null:
			_hint.visible = value
## The router to follow; null means the InputRouter autoload.
var router: WlInputRouter = null
## Item text size in 1080p pixels (>= 32 for reading at 3 m).
var item_font_px: int = WlTheme.MENU_PX

var _items: Array[Dictionary] = []
var _rows: Array[PanelContainer] = []
var _markers: Array[Label] = []
var _hint: Label = null
var _highlight: int = -1
var _scan_t: float = 0.0
var _manual_pause_left: float = 0.0
var _auto_t: float = 0.0
var _local_mode: String = ""
var _listening_to: WlInputRouter = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", WlTheme.GAP_PX)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var s := tree.root.get_node_or_null("Settings") as WlSettings
		if s != null and s.profile != null and s.profile.scan_interval_s > 0.0:
			scan_interval_s = s.profile.scan_interval_s


func _ready() -> void:
	_ensure_hint()
	_update_listening()


func _exit_tree() -> void:
	_disconnect_router()


func _process(delta: float) -> void:
	if not real_time or not is_visible_in_tree():
		return
	tick(delta)


## items: [{"id": Variant, "text": String (key or text), "disabled": bool (optional),
## "icon": Texture2D (optional), "detail": String (optional)}].
func set_items(items: Array) -> void:
	_items.clear()
	for it: Variant in items:
		if it is Dictionary:
			_items.append((it as Dictionary).duplicate())
		else:
			_items.append({"id": it, "text": str(it)})
	_rebuild_rows()
	_scan_t = 0.0
	_auto_t = 0.0
	_manual_pause_left = 0.0
	var first := _next_enabled(-1, 1)
	_highlight = -2
	_apply_highlight(first, false)


## The items as given to set_items (copies).
func items() -> Array:
	return _items.duplicate(true)


func item_count() -> int:
	return _items.size()


func is_item_enabled(index: int) -> bool:
	return index >= 0 and index < _items.size() and not bool(_items[index].get("disabled", false))


## Enable or disable one item (a shop item the rider can no longer afford).
func set_item_disabled(index: int, disabled: bool) -> void:
	if index < 0 or index >= _items.size():
		push_error("PedalScanList: no item %d" % index)
		return
	_items[index]["disabled"] = disabled
	_style_row(index)
	if disabled and index == _highlight:
		_apply_highlight(_next_enabled(index, 1), true)
	elif not disabled and _highlight < 0:
		_apply_highlight(index, true)


func highlighted() -> int:
	return _highlight


## The highlighted item's id (null when nothing is highlighted).
func highlighted_id() -> Variant:
	if _highlight < 0 or _highlight >= _items.size():
		return null
	return _items[_highlight].get("id")


func set_highlight(index: int) -> void:
	if not is_item_enabled(index):
		push_warning("PedalScanList: can't highlight item %d (missing or disabled)" % index)
		return
	_scan_t = 0.0
	_apply_highlight(index, true)


## Feed a gesture or action by hand (headless tests, game-specific routing).
func feed_gesture(gesture_name: StringName) -> void:
	if gesture_name == Wl.G_SURGE:
		_pick("surge")
	elif gesture_name == Wl.G_COAST:
		if not _in_erg():
			_back()


func feed_action(action_name: StringName) -> void:
	match String(action_name):
		"confirm":
			_pick("action")
		"back":
			_back()
		"up", "left":
			_manual_move(-1)
		"down", "right":
			_manual_move(1)


## Advance the scan timer (headless tests; _process calls it in real time). With
## follow_local_mode on, it first reads the InputRouter's attached rider's trainer mode.
func tick(dt: float) -> void:
	if follow_local_mode:
		var r := _router()
		if r != null and r.attached_rider() != null:
			set_local_mode(r.local_mode())
	if dt <= 0.0 or _items.is_empty():
		return
	var n := _enabled_count()
	if n == 0:
		_auto_t = 0.0
		return
	var interval := maxf(scan_interval_s, MIN_INTERVAL_S)
	var scan_active := scanning
	if _manual_pause_left > 0.0:
		_manual_pause_left = maxf(0.0, _manual_pause_left - dt)
		scan_active = false
	if scan_active:
		_scan_t += dt
		while _scan_t >= interval - 1e-6:
			_scan_t -= interval
			_apply_highlight(_next_enabled(_highlight, 1), true)
	if erg_auto_confirm:
		_auto_t += dt
		if _auto_t >= auto_confirm_after_s() - 1e-6:
			_pick("auto")
	else:
		_auto_t = 0.0
	_update_hint()


## The trainer mode of the local rider ("ERG", "SIM", ...). With follow_local_mode on,
## erg_auto_confirm follows it.
func set_local_mode(mode: String) -> void:
	_local_mode = mode
	if follow_local_mode:
		erg_auto_confirm = mode == Wl.ERG
	_update_hint()


## Seconds without input after which the highlighted item is auto-picked (ERG).
func auto_confirm_after_s() -> float:
	return 2.0 * float(maxi(1, _enabled_count())) * maxf(scan_interval_s, MIN_INTERVAL_S)


## Seconds left until the ERG auto-pick (INF when auto-confirm is off).
func auto_confirm_left_s() -> float:
	if not erg_auto_confirm or _enabled_count() == 0:
		return INF
	return maxf(0.0, auto_confirm_after_s() - _auto_t)


## Seconds left of the scanning pause after a focus move.
func scan_paused_left_s() -> float:
	return _manual_pause_left


## The row Control of item `index` (null if out of range).
func row(index: int) -> Control:
	if index < 0 or index >= _rows.size():
		return null
	return _rows[index]


# --- internals ---------------------------------------------------------------------------

func _pick(via: String) -> void:
	if not is_item_enabled(_highlight):
		return
	var index := _highlight
	var id: Variant = _items[index].get("id")
	_auto_t = 0.0
	_play("ui_confirm")
	item_chosen.emit(index, id, via == "auto")
	item_picked.emit(index, id, via)


func _back() -> void:
	_auto_t = 0.0
	_play("ui_back")
	backed_out.emit()


func _manual_move(step: int) -> void:
	_auto_t = 0.0
	_scan_t = 0.0
	_manual_pause_left = MANUAL_PAUSE_S
	if _enabled_count() == 0:
		return
	_apply_highlight(_next_enabled(_highlight, step), true)


func _apply_highlight(index: int, emit: bool) -> void:
	if index == _highlight:
		return
	var old := _highlight
	_highlight = index
	if old >= 0:
		_style_row(old)
	if index >= 0:
		_style_row(index)
	if emit:
		_play("ui_move", -12.0)
	highlight_changed.emit(index)


func _next_enabled(from: int, step: int) -> int:
	var n := _items.size()
	if n == 0:
		return -1
	var i := from
	for _k in n:
		i = posmod(i + step, n)
		if is_item_enabled(i):
			return i
	return -1


func _enabled_count() -> int:
	var c := 0
	for i in _items.size():
		if is_item_enabled(i):
			c += 1
	return c


## The local rider is in ERG: its mode says so, or (mode unknown) the list is set up for an
## ERG pick (erg_auto_confirm on), so `coast` never backs out of a pick shown during ERG.
func _in_erg() -> bool:
	if _local_mode.is_empty():
		return erg_auto_confirm
	return _local_mode == Wl.ERG


func _play(sound: String, volume_db: float = -6.0) -> void:
	if not sounds or not is_inside_tree():
		return
	var sfx := get_node_or_null("/root/Sfx") as WlSfx
	if sfx != null:
		sfx.play(sound, volume_db)


# --- input -----------------------------------------------------------------------------------

func _router() -> WlInputRouter:
	if router != null:
		return router
	if is_inside_tree():
		return get_node_or_null("/root/InputRouter") as WlInputRouter
	return null


func _update_listening() -> void:
	if not is_inside_tree():
		return
	var want: WlInputRouter = _router() if listen_to_input else null
	if want == _listening_to:
		return
	_disconnect_router()
	if want != null:
		want.menu_input.connect(_on_menu_input)
		_listening_to = want


func _disconnect_router() -> void:
	if _listening_to != null and is_instance_valid(_listening_to):
		if _listening_to.menu_input.is_connected(_on_menu_input):
			_listening_to.menu_input.disconnect(_on_menu_input)
	_listening_to = null


func _on_menu_input(action_name: StringName, via: String) -> void:
	if not is_visible_in_tree():
		return
	match via:
		"action":
			feed_action(action_name)
		"surge":
			feed_gesture(Wl.G_SURGE)
		"coast":
			feed_gesture(Wl.G_COAST)


# --- view ------------------------------------------------------------------------------------

func _ensure_hint() -> void:
	if _hint != null:
		return
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.label_settings = WlTheme.label_settings(WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = show_hint
	add_child(_hint)
	_update_hint()


func _rebuild_rows() -> void:
	for r in _rows:
		remove_child(r)
		r.free()
	_rows.clear()
	_markers.clear()
	_ensure_hint()
	for i in _items.size():
		var it := _items[i]
		var panel := PanelContainer.new()
		panel.name = "Item%d" % i
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		panel.add_child(hb)
		var marker := Label.new()
		marker.name = "Marker"
		marker.text = ">"
		marker.label_settings = WlTheme.label_settings(item_font_px, WlTheme.ACCENT, true)
		marker.custom_minimum_size = Vector2(item_font_px * 0.8, 0)
		hb.add_child(marker)
		var icon: Variant = it.get("icon", null)
		if icon is Texture2D:
			var tex := TextureRect.new()
			tex.texture = icon
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.custom_minimum_size = Vector2(item_font_px * 1.5, item_font_px * 1.5)
			hb.add_child(tex)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)
		var text := Label.new()
		text.name = "Text"
		text.text = str(it.get("text", str(it.get("id", ""))))
		text.label_settings = WlTheme.label_settings(item_font_px)
		vb.add_child(text)
		var detail := str(it.get("detail", ""))
		if not detail.is_empty():
			var d := Label.new()
			d.name = "Detail"
			d.text = detail
			d.label_settings = WlTheme.label_settings(WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
			vb.add_child(d)
		add_child(panel)
		move_child(panel, i)
		_rows.append(panel)
		_markers.append(marker)
		_style_row(i)


func _style_row(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	var enabled := is_item_enabled(i)
	var hi := i == _highlight
	var sb: StyleBoxFlat
	if hi:
		sb = WlTheme.panel_style(Color(0.13, 0.2, 0.26, 0.95), WlTheme.ACCENT, 6)
	else:
		sb = WlTheme.panel_style()
	_rows[i].add_theme_stylebox_override("panel", sb)
	_rows[i].modulate = Color.WHITE if enabled else WlTheme.DISABLED
	_markers[i].modulate.a = 1.0 if hi else 0.0


func _update_hint() -> void:
	if _hint == null:
		return
	if erg_auto_confirm and _enabled_count() > 0:
		_hint.text = tr("UI_SCAN_AUTO_IN").format([ceili(auto_confirm_left_s())])
	elif _in_erg():
		_hint.text = tr("UI_SCAN_HINT_ERG")
	else:
		_hint.text = tr("UI_SCAN_HINT")
