extends PedalScanList
## Test double of PedalScanList with the documented behaviour (BRIEF 3.5, ui-hud's contract):
## focus cycles over enabled items every scan_interval_s while scanning; surge or confirm picks
## the highlighted item; coast (never with erg_auto_confirm) or back backs out; up/down move;
## with erg_auto_confirm the highlighted item is picked after two full cycles.

var items: Array = []
var picks: Array = []
var _hl: int = -1
var _t: float = 0.0
var _auto_t: float = 0.0


func set_items(p_items: Array) -> void:
	items = p_items.duplicate(true)
	if _hl < 0 or _hl >= items.size() or _disabled(_hl):
		_hl = _first_enabled()


func highlighted() -> int:
	return _hl


func set_highlight(index: int) -> void:
	if index >= 0 and index < items.size():
		_hl = index
		highlight_changed.emit(index)


func feed_gesture(gesture_name: StringName) -> void:
	match gesture_name:
		&"surge":
			_pick("surge")
		&"coast":
			if not erg_auto_confirm:
				backed_out.emit()


func feed_action(action_name: StringName) -> void:
	match action_name:
		&"confirm":
			_pick("action")
		&"back":
			backed_out.emit()
		&"up":
			_move(-1)
		&"down":
			_move(1)


func tick(dt: float) -> void:
	if items.is_empty():
		return
	if scanning:
		_t += dt
		while _t >= scan_interval_s - 1e-9:
			_t -= scan_interval_s
			_move(1)
	if erg_auto_confirm:
		_auto_t += dt
		if _auto_t >= 2.0 * items.size() * scan_interval_s:
			_auto_t = 0.0
			_pick("auto")


## The text of the item with `id` ("" when missing).
func text_of(id: Variant) -> String:
	for it: Variant in items:
		if AppScreen.same_id((it as Dictionary).get("id"), id):
			return str((it as Dictionary).get("text", ""))
	return ""


func index_of_id(id: Variant) -> int:
	for i in items.size():
		if AppScreen.same_id((items[i] as Dictionary).get("id"), id):
			return i
	return -1


func is_disabled_id(id: Variant) -> bool:
	var i := index_of_id(id)
	return i < 0 or _disabled(i)


func ids() -> Array:
	var out: Array = []
	for it: Variant in items:
		out.append((it as Dictionary).get("id"))
	return out


func _disabled(i: int) -> bool:
	return bool((items[i] as Dictionary).get("disabled", false))


func _first_enabled() -> int:
	for i in items.size():
		if not _disabled(i):
			return i
	return -1


func _move(d: int) -> void:
	if items.is_empty():
		return
	var i := _hl
	for _n in items.size():
		i = posmod(i + d, items.size())
		if not _disabled(i):
			_hl = i
			highlight_changed.emit(i)
			return


func _pick(via: String) -> void:
	if _hl < 0 or _hl >= items.size() or _disabled(_hl):
		return
	var id: Variant = (items[_hl] as Dictionary).get("id")
	picks.append([_hl, id, via])
	item_chosen.emit(_hl, id, via == "auto")
	item_picked.emit(_hl, id, via)
