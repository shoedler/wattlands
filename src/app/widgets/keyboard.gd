class_name AppKeyboard
extends RefCounted
## On-screen keyboard for an AppTextField, driven by a screen's pedal-scan menus (BRIEF 3.5:
## "offer a controller on-screen keyboard"). Row-column scanning keeps it quick with one switch:
## the first menu lists the rows plus Delete, Done and Cancel (and any extra items, such as
## recent rooms); picking a row opens that row's characters; picking a character types it and
## returns to the rows. Controller and keyboard users move with up/down and confirm.

const ID_DELETE := "kb:delete"
const ID_DONE := "kb:done"
const ID_CANCEL := "kb:cancel"
const ID_UP := "kb:up"

var screen: AppScreen = null
var field: AppTextField = null
var on_done: Callable
var on_cancel: Callable
## Extra root items [{"id", "text", ...}] and their handler (id) -> void.
var extra_items: Array = []
var on_extra: Callable
var done_text_key: String = "APP_KEY_DONE"
var root_menu: PedalScanList = null
var _row_open: bool = false


static func create(p_screen: AppScreen, p_field: AppTextField) -> AppKeyboard:
	var k := AppKeyboard.new()
	k.screen = p_screen
	k.field = p_field
	return k


## Push the rows menu on the screen.
func open() -> void:
	root_menu = screen.push_menu(root_items(), _on_root_pick, _on_root_back)
	if not field.changed.is_connected(_on_field_changed):
		field.changed.connect(_on_field_changed)


func is_open() -> bool:
	return root_menu != null and is_instance_valid(root_menu) and screen.menus.has(root_menu)


func root_items() -> Array:
	var items: Array = []
	for i in field.rows.size():
		items.append({"id": "kb:row:%d" % i, "text": spaced(field.rows[i])})
	items.append({"id": ID_DELETE, "text": AppScreen.t("APP_KEY_DELETE"), "disabled": field.value() == ""})
	items.append({"id": ID_DONE, "text": AppScreen.t(done_text_key), "disabled": not field.is_complete()})
	for e: Variant in extra_items:
		items.append(e)
	items.append({"id": ID_CANCEL, "text": AppScreen.t("APP_BACK")})
	return items


## "ABC" -> "A B C" (spaces shown as a visible mark).
static func spaced(row: String) -> String:
	var parts: PackedStringArray = []
	for ch in row:
		parts.append("␣" if ch == " " else ch)
	return " ".join(parts)


func refresh() -> void:
	if is_open():
		screen.refresh_menu(root_items(), root_menu)


func _on_field_changed(_text: String) -> void:
	if not _row_open:
		refresh()


func _on_root_pick(_index: int, id: Variant, _auto: bool) -> void:
	var sid := str(id)
	if sid.begins_with("kb:row:"):
		_open_row(int(sid.substr(7)))
	elif sid == ID_DELETE:
		field.backspace()
		refresh()
	elif sid == ID_DONE:
		if field.is_complete() and on_done.is_valid():
			on_done.call(field.value())
	elif sid == ID_CANCEL:
		_on_root_back()
	elif on_extra.is_valid():
		on_extra.call(id)


func _on_root_back() -> void:
	if on_cancel.is_valid():
		on_cancel.call()


func _open_row(row: int) -> void:
	if row < 0 or row >= field.rows.size():
		return
	var items: Array = []
	for ch in field.rows[row]:
		var text := AppScreen.t("APP_KEY_SPACE") if ch == " " else ch
		items.append({"id": "kb:ch:" + ch, "text": text})
	items.append({"id": ID_UP, "text": AppScreen.t("APP_BACK")})
	_row_open = true
	screen.push_menu(items, _on_char_pick, _close_row)


func _on_char_pick(_index: int, id: Variant, _auto: bool) -> void:
	var sid := str(id)
	if sid.begins_with("kb:ch:"):
		field.append_char(sid.substr(6))
	_close_row()


func _close_row() -> void:
	if _row_open:
		_row_open = false
		screen.pop_menu()
		refresh()
