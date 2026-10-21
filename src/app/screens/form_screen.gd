class_name AppFormScreen
extends AppScreen
## A screen of editable fields on pedal-scan (profile, first run, settings). Each field is one
## menu item "Label: value"; picking it edits it in place:
##   toggle   flips at once
##   choice   opens the list of choices
##   stepper  opens − / + steps (numbers stay >= 48 px in the field's value display)
##   text     opens an AppTextField with the on-screen keyboard (typing works too)
##   action   runs a callback (sub-pages, connect buttons)
##   info     a read-only line (skipped by the scan)
## Field: {id, label (text), type, get: Callable -> Variant, set: Callable(value),
##   choices: [[value, text]], min, max, step, unit, decimals, rows (text), secret, max_length,
##   enabled: Callable -> bool, run: Callable (action), value_text: Callable(value) -> String}

var content_box: VBoxContainer = null
var value_label: Label = null
var text_field: AppTextField = null
var keyboard: AppKeyboard = null
var _fields_by_menu: Dictionary = {}
var _editing: Dictionary = {}


## A page with the title, a content column and the menu column; returns the page dict.
func make_form_page(title_text: String) -> Dictionary:
	var page := make_page(title_text)
	content_box = page["left"]
	value_label = AppStyle.label("", AppStyle.FONT_NUMBER, AppStyle.ACCENT)
	value_label.name = "Value"
	content_box.add_child(value_label)
	return page


## A weight stepper in the rider's units (BRIEF 3.2 units): kg in steps of 1 (metric) or lb in
## steps of 1 (imperial, 67-440 lb), always stored in kg through `set_kg` (W3 PROF-6).
static func weight_field(id: String, label: String, units: String, get_kg: Callable, set_kg: Callable) -> Dictionary:
	if units == "imperial":
		return {"id": id, "label": label, "type": "stepper", "step": 1.0, "unit": "lb",
			"min": ceilf(AppStyle.WEIGHT_MIN_KG * AppStyle.LB_PER_KG), "max": floorf(AppStyle.WEIGHT_MAX_KG * AppStyle.LB_PER_KG),
			"get": func() -> Variant: return roundf(float(get_kg.call()) * AppStyle.LB_PER_KG),
			"set": func(v: Variant) -> void: set_kg.call(clampf(float(v) / AppStyle.LB_PER_KG, AppStyle.WEIGHT_MIN_KG, AppStyle.WEIGHT_MAX_KG))}
	return {"id": id, "label": label, "type": "stepper", "step": 1.0, "unit": "kg",
		"min": AppStyle.WEIGHT_MIN_KG, "max": AppStyle.WEIGHT_MAX_KG,
		"get": func() -> Variant: return float(get_kg.call()), "set": func(v: Variant) -> void: set_kg.call(float(v))}


## Push a list of fields as a menu. back: what coast/back does (default: pop, or nothing).
func open_fields(fields: Array, back: Callable = Callable(), highlight: int = -1) -> PedalScanList:
	var list := push_menu(items_for(fields), _on_field_pick, back, highlight)
	_fields_by_menu[list.get_instance_id()] = fields
	return list


func fields_of(list: PedalScanList) -> Array:
	if list == null:
		return []
	return _fields_by_menu.get(list.get_instance_id(), [])


func items_for(fields: Array) -> Array:
	var items: Array = []
	for f: Dictionary in fields:
		var enabled := true
		var en: Variant = f.get("enabled", null)
		if en is Callable and (en as Callable).is_valid():
			enabled = bool((en as Callable).call())
		var typ := str(f.get("type", "action"))
		items.append({"id": f.get("id"), "text": field_text(f), "disabled": not enabled or typ == "info"})
	return items


func field_text(f: Dictionary) -> String:
	var label := str(f.get("label", ""))
	var typ := str(f.get("type", "action"))
	if typ == "action":
		return label
	var v: Variant = field_value(f)
	if typ == "info":
		return label if v == null else "%s: %s" % [label, str(v)]
	return "%s: %s" % [label, value_text(f, v)]


func field_value(f: Dictionary) -> Variant:
	var g: Variant = f.get("get", null)
	if g is Callable and (g as Callable).is_valid():
		return (g as Callable).call()
	return null


func value_text(f: Dictionary, v: Variant) -> String:
	var vt: Variant = f.get("value_text", null)
	if vt is Callable and (vt as Callable).is_valid():
		return str((vt as Callable).call(v))
	match str(f.get("type", "")):
		"toggle":
			return t("APP_ON") if bool(v) else t("APP_OFF")
		"choice":
			for c: Variant in f.get("choices", []):
				if c is Array and (c as Array).size() >= 2 and str((c as Array)[0]) == str(v):
					return str((c as Array)[1])
			return str(v)
		"stepper":
			var dec := int(f.get("decimals", 0))
			var num := ("%." + str(dec) + "f") % float(v)
			var unit := str(f.get("unit", ""))
			return (num + " " + unit).strip_edges()
		"text":
			if bool(f.get("secret", false)):
				return "••••••" if str(v) != "" else "—"
			return str(v) if str(v) != "" else "—"
	return str(v)


func set_field(f: Dictionary, v: Variant) -> void:
	var s: Variant = f.get("set", null)
	if s is Callable and (s as Callable).is_valid():
		(s as Callable).call(v)


## Rebuild the texts of every visible field list.
func refresh_fields() -> void:
	for m in menus:
		var fields := fields_of(m)
		if not fields.is_empty():
			refresh_menu(items_for(fields), m)


func field_by_id(id: Variant, list: PedalScanList = null) -> Dictionary:
	for f: Dictionary in fields_of(list if list != null else active_menu()):
		if AppScreen.same_id(f.get("id"), id):
			return f
	return {}


func _on_field_pick(index: int, _id: Variant, _auto: bool) -> void:
	var fields := fields_of(active_menu())
	if index < 0 or index >= fields.size():
		return
	edit_field(fields[index])


## Start editing a field (as if it was picked).
func edit_field(f: Dictionary) -> void:
	_editing = f
	match str(f.get("type", "action")):
		"toggle":
			set_field(f, not bool(field_value(f)))
			refresh_fields()
		"choice":
			var items: Array = []
			var hl := 0
			var cur := str(field_value(f))
			var choices: Array = f.get("choices", [])
			for i in choices.size():
				var c: Array = choices[i]
				if str(c[0]) == cur:
					hl = i
				items.append({"id": i, "text": str(c[1])})
			push_menu(items, _on_choice_pick, Callable(), hl)
		"stepper":
			_show_value(f)
			push_menu(_stepper_items(f), _on_step_pick, _close_editor, 2)
		"text":
			_open_text(f)
		"action":
			var run: Variant = f.get("run", null)
			if run is Callable and (run as Callable).is_valid():
				(run as Callable).call()


func _on_choice_pick(index: int, _id: Variant, _auto: bool) -> void:
	var choices: Array = _editing.get("choices", [])
	if index >= 0 and index < choices.size():
		set_field(_editing, (choices[index] as Array)[0])
	pop_menu()
	refresh_fields()


func _stepper_items(f: Dictionary) -> Array:
	var step := float(f.get("step", 1.0))
	var dec := int(f.get("decimals", 0))
	var unit := str(f.get("unit", ""))
	var st := (("%." + str(dec) + "f") % step + " " + unit).strip_edges()
	return [
		{"id": "value", "text": field_text(f), "disabled": true},
		{"id": "dec", "text": "− " + st},
		{"id": "inc", "text": "+ " + st},
		{"id": "dec5", "text": "− 5 × " + st},
		{"id": "inc5", "text": "+ 5 × " + st},
		{"id": "done", "text": t("APP_KEY_DONE")},
	]


## The stepped value: clamped to [min, max] and snapped to `decimals`.
static func stepped(f: Dictionary, v: float, steps: int) -> float:
	var step := float(f.get("step", 1.0))
	var lo := float(f.get("min", -INF))
	var hi := float(f.get("max", INF))
	var dec := int(f.get("decimals", 0))
	var nv := clampf(v + step * steps, lo, hi)
	var mul := pow(10.0, dec)
	return round(nv * mul) / mul


func _on_step_pick(_index: int, id: Variant, _auto: bool) -> void:
	var v := float(field_value(_editing))
	match str(id):
		"dec":
			v = stepped(_editing, v, -1)
		"inc":
			v = stepped(_editing, v, 1)
		"dec5":
			v = stepped(_editing, v, -5)
		"inc5":
			v = stepped(_editing, v, 5)
		"done":
			_close_editor()
			return
	set_field(_editing, v)
	_show_value(_editing)
	refresh_menu(_stepper_items(_editing))


func _close_editor() -> void:
	pop_menu()
	if value_label != null:
		value_label.text = ""
	refresh_fields()


func _show_value(f: Dictionary) -> void:
	if value_label != null:
		value_label.text = field_text(f)


func _open_text(f: Dictionary) -> void:
	if text_field != null and is_instance_valid(text_field):
		text_field.queue_free()
	var rows: Array[String] = []
	for r: Variant in f.get("rows", AppTextField.ROWS_NAME):
		rows.append(str(r))
	text_field = AppTextField.make_text(str(f.get("label", "")), rows, int(f.get("max_length", 64)), bool(f.get("secret", false)))
	text_field.name = "TextEntry"
	if content_box != null:
		content_box.add_child(text_field)
	else:
		add_child(text_field)
	text_field.set_value(str(field_value(f)))
	text_field.submitted.connect(_on_text_done)
	watch_text_focus(text_field)
	keyboard = AppKeyboard.create(self, text_field)
	keyboard.on_done = _on_text_done
	keyboard.on_cancel = _close_text
	keyboard.open()


func _on_text_done(value: String) -> void:
	set_field(_editing, value)
	_close_text()


func _close_text() -> void:
	if keyboard != null and keyboard.is_open():
		while active_menu() != null and active_menu() != keyboard.root_menu:
			pop_menu()
		pop_menu()
	keyboard = null
	if text_field != null and is_instance_valid(text_field):
		text_field.queue_free()
	text_field = null
	text_focus = false
	refresh_fields()
