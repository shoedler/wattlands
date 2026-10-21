extends GutTest
## GameResults, SessionStats and ProgressStore (BRIEF 3.6, 3.7).

var _dirs: Array[String] = []


func after_each() -> void:
	Paths.set_override("")
	CmdLine.set_args(PackedStringArray(), false)
	for d in _dirs:
		_remove_tree(d)
	_dirs.clear()


static func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _rt(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(parsed is Dictionary)
	return parsed if parsed is Dictionary else {}


func _players() -> Array[PlayerSlot]:
	var a := PlayerSlot.new()
	a.peer_id = 1
	a.name = "Host"
	a.apply_look(0)
	var b := Bots.make_slot(1, 1, 200.0)
	var out: Array[PlayerSlot] = [a, b]
	return out


# --- GameResults ----------------------------------------------------------------------


func test_session_stats_base_row() -> void:
	var row := SessionStats.new().base_row(1)
	for k: String in [
		"kj",
		"avg_power_w",
		"avg_ftp_pct",
		"np_w",
		"best_1m_w",
		"best_5m_w",
		"best_20m_w",
		"ride_s",
		"time_in_band_s",
		"time_in_band_pct"
	]:
		assert_true(row.has(k), k)
		assert_eq(row[k], 0.0)
	assert_eq(SessionStats.new().best_power(1, 60.0), 0.0)
	assert_eq(SessionStats.new().kj(1), 0.0)


func test_from_stats_builds_one_row_per_player() -> void:
	var r := GameResults.from_stats(SessionStats.new(), _players())
	assert_eq(r.rows.size(), 2)
	var host := r.row(1)
	assert_eq(host["peer_id"], 1)
	assert_eq(host["slot_index"], 0)
	assert_eq(host["name"], "Host")
	assert_false(host["is_bot"])
	assert_eq(host["xp"], 0)
	assert_eq(host["unlocks"], [])
	assert_eq(host["stats"], {})
	assert_eq(host["kj"], 0.0, "base rows from SessionStats")
	assert_true(host.has("time_in_band_pct"))
	var bot := r.row(-1)
	assert_eq(bot["name"], "Bot 1")
	assert_true(bot["is_bot"])
	assert_eq(bot["slot_index"], 1)
	assert_eq(r.row(99), {}, "unknown peer")
	assert_eq(r.grade, "D")


func test_from_stats_without_stats() -> void:
	var r := GameResults.from_stats(null, _players())
	assert_eq(r.rows.size(), 2)
	assert_eq(r.row(1)["xp"], 0)
	assert_false(r.row(1).has("kj"))


func test_grade_from_fraction_band_edges() -> void:
	assert_eq(GameResults.grade_from_fraction(1.0), "S")
	assert_eq(GameResults.grade_from_fraction(0.95), "S")
	assert_eq(GameResults.grade_from_fraction(0.9499), "A")
	assert_eq(GameResults.grade_from_fraction(0.90), "A")
	assert_eq(GameResults.grade_from_fraction(0.8999), "B")
	assert_eq(GameResults.grade_from_fraction(0.80), "B")
	assert_eq(GameResults.grade_from_fraction(0.7999), "C")
	assert_eq(GameResults.grade_from_fraction(0.65), "C")
	assert_eq(GameResults.grade_from_fraction(0.6499), "D")
	assert_eq(GameResults.grade_from_fraction(0.0), "D")
	assert_eq(GameResults.grade_from_fraction(-1.0), "D")


func test_results_round_trip() -> void:
	var r := GameResults.from_stats(SessionStats.new(), _players())
	r.grade = "A"
	r.score = 1234.5
	r.summary_key = "SIEGE_RESULTS_HELD"
	r.session_id = "s-42-abc"
	r.team = {"waves": 6.0, "title": "held"}
	var row := r.row(1)
	row["xp"] = 150
	row["unlocks"] = ["banner_red"]
	row["stats"] = {"towers": 4.0, "best": "north gate"}
	var d := r.to_dict()
	var back := GameResults.from_dict(_rt(d))
	assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(d))
	assert_eq(back.grade, "A")
	assert_eq(back.score, 1234.5)
	assert_eq(back.summary_key, "SIEGE_RESULTS_HELD")
	assert_eq(back.session_id, "s-42-abc")
	assert_eq(back.team["waves"], 6.0)
	var host := back.row(1)
	assert_true(typeof(host["peer_id"]) == TYPE_INT)
	assert_true(typeof(host["slot_index"]) == TYPE_INT)
	assert_true(typeof(host["xp"]) == TYPE_INT)
	assert_eq(host["xp"], 150)
	assert_eq(host["unlocks"], ["banner_red"])
	assert_eq(host["stats"]["best"], "north gate")
	assert_eq(back.row(-1)["name"], "Bot 1")


func test_results_from_empty_dict() -> void:
	var r := GameResults.from_dict({})
	assert_eq(r.grade, "D")
	assert_eq(r.rows.size(), 0)
	assert_eq(r.session_id, "")


# --- ProgressStore --------------------------------------------------------------------


func test_progress_store_open_set_add_save_reopen() -> void:
	var tmp := Paths.make_temp_dir("wattlands_progress_test")
	_dirs.append(tmp)
	Paths.set_override(tmp)
	var path := Paths.progress_path("fishing")
	assert_true(path.begins_with(tmp))
	var s := ProgressStore.open("fishing", path)
	assert_eq(s.game_id, "fishing")
	assert_eq(s.path, path)
	assert_eq(s.data, {})
	assert_false(s.has("xp"))
	assert_eq(s.get_value("xp", 7), 7)
	assert_null(s.get_value("missing"))
	s.set_value("log", ["marlin", "tuna"])
	s.set_value("best_kg", 312.5)
	assert_eq(s.add("xp", 40.0), 40.0, "missing counts as 0")
	assert_eq(s.add("xp", 2.5), 42.5)
	assert_true(s.has("xp"))
	assert_true(s.save())
	assert_true(FileAccess.file_exists(path))
	var again := ProgressStore.open("fishing", path)
	assert_eq(again.get_value("xp"), 42.5)
	assert_eq(again.get_value("best_kg"), 312.5)
	assert_eq(again.get_value("log"), ["marlin", "tuna"])
	assert_eq(again.add("xp", 1.0), 43.5)


func test_progress_store_creates_folders() -> void:
	var tmp := Paths.make_temp_dir("wattlands_progress_test")
	_dirs.append(tmp)
	var path := tmp.path_join("games/tank/deeper/progress.json")
	var s := ProgressStore.open("tank", path)
	s.set_value("unlocks", ["hull_grey"])
	assert_true(s.save())
	assert_eq(ProgressStore.open("tank", path).get_value("unlocks"), ["hull_grey"])


func test_progress_store_in_memory() -> void:
	var s := ProgressStore.open("siege", "")
	s.set_value("a", 1)
	assert_eq(s.get_value("a"), 1)
	assert_false(s.save(), "no path, nothing written")
