extends GutTest
## The ui-hud module's user strings (BRIEF 6; docs/OWNERSHIP.md 1.2): every UI_* key the code
## uses is in content/strings/ui.csv and translates, the file has the "keys,en" header, one
## row per key and no game prefixes, and the controls-screen labels never show a raw key.

const CSV_PATH := "res://content/strings/ui.csv"
const SOURCE_DIRS: Array[String] = ["res://addons/wattlands/ui", "res://addons/wattlands/audio"]
const GAME_PREFIXES: Array[String] = ["WORKOUT_", "SIEGE_", "TANK_", "FISHING_", "_TEMPLATE_"]


func _gd_files(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_gd_files(dir.path_join(d), out)


func _csv_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return rows
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		rows.append(row)
	return rows


func test_csv_is_well_formed() -> void:
	var rows := _csv_rows()
	assert_gt(rows.size(), 10)
	if rows.is_empty():
		return
	assert_eq(Array(rows[0]), ["keys", "en"], "header")
	var seen: Dictionary = {}
	for i in range(1, rows.size()):
		var row := rows[i]
		assert_eq(row.size(), 2, "row %d has a key and an English text: %s" % [i, row])
		var key := row[0]
		assert_false(seen.has(key), "%s appears once" % key)
		seen[key] = true
		assert_true(key.begins_with("UI_"), "%s uses the module prefix" % key)
		for p in GAME_PREFIXES:
			assert_false(key.begins_with(p), "%s has no game prefix" % key)
		if row.size() == 2:
			assert_false(row[1].strip_edges().is_empty(), "%s has text" % key)


func test_every_ui_key_in_the_code_is_in_ui_csv() -> void:
	var re := RegEx.create_from_string('"(UI_[A-Z0-9_]*[A-Z0-9])"')
	var files: Array[String] = []
	for d in SOURCE_DIRS:
		_gd_files(d, files)
	assert_gt(files.size(), 10)
	var keys: Dictionary = {}
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			keys[m.get_string(1)] = path
	assert_gt(keys.size(), 30)
	for k: String in keys.keys():
		assert_ne(tr(k), k, "%s (used in %s) translates" % [k, keys[k]])
	for kind in Wl.PHASE_KINDS:
		assert_ne(
			tr("UI_KIND_" + kind), "UI_KIND_" + kind, "the timeline's kind fallback for %s" % kind
		)


func test_binding_labels_are_never_raw_keys() -> void:
	InputBindings.ensure_actions()
	for a: StringName in Wl.ACTIONS:
		for e in InputBindings.events_of(a):
			var label := InputBindings.describe(e)
			assert_false(label.is_empty(), "%s has a label" % a)
			assert_false(label.begins_with("UI_"), "%s: %s" % [a, label])
	var odd := InputEventJoypadButton.new()
	odd.button_index = JOY_BUTTON_PADDLE1
	assert_eq(InputBindings.describe(odd), tr("UI_INPUT_BUTTON").format([int(JOY_BUTTON_PADDLE1)]))
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_RIGHT_Y
	axis.axis_value = -1.0
	assert_eq(InputBindings.describe(axis), tr("UI_INPUT_RS_UP"))
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(InputBindings.describe(mouse), tr("UI_INPUT_MOUSE").format([2]))
