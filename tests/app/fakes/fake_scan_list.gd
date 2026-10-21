extends PedalScanList
## The real PedalScanList (ui-hud) with read-only probes for the app-shell tests. It adds no
## member that shadows the real class, so the lists the screens drive behave exactly like the
## ones in the app (BRIEF 3.5): focus cycles over enabled items every scan_interval_s while
## scanning; surge or confirm picks the highlighted item; coast (never in ERG) or back backs out;
## up/down move focus and pause scanning; with erg_auto_confirm the highlighted item is picked
## after two full cycles. `picks` records every pick as [index, id, via].

var picks: Array = []


func _init() -> void:
	super()
	sounds = false
	item_picked.connect(_record_pick)


## The text of the item with `id` ("" when missing).
func text_of(id: Variant) -> String:
	for it: Variant in items():
		if AppScreen.same_id((it as Dictionary).get("id"), id):
			return str((it as Dictionary).get("text", ""))
	return ""


func index_of_id(id: Variant) -> int:
	var list := items()
	for i in list.size():
		if AppScreen.same_id((list[i] as Dictionary).get("id"), id):
			return i
	return -1


func is_disabled_id(id: Variant) -> bool:
	return not is_item_enabled(index_of_id(id))


func ids() -> Array:
	var out: Array = []
	for it: Variant in items():
		out.append((it as Dictionary).get("id"))
	return out


func _record_pick(index: int, id: Variant, via: String) -> void:
	picks.append([index, id, via])
