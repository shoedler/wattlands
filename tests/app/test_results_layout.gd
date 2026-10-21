extends "res://tests/app/app_test_base.gd"
## The results screen with a real Workout row (W3 ZIH-1, PROF-5/ZIH-5, ZIH-8):
## - BRIEF 3.8/3.9: Upload to Strava and Continue stay on screen (pedal-scan selectable) and
##   BRIEF 3.3: the per-rider %FTP column too, however long a game's custom stats line is.
## - BRIEF 3.3: W/kg shows only for a rider who opted in (profile show_wkg).
## - GAME_SDK apply_progress: new unlocks show their names (<GAME_ID>_UNLOCK_<ID>).


## A Workout-like GameResults row (the stats keys and values a real Easy 30 produces).
func _workout_results() -> GameResults:
	var r := GameResults.new()
	r.grade = "S"
	r.summary_key = "WORKOUT_RESULT_S"
	var row := {
		"peer_id": 1,
		"name": "Ada",
		"kj": 192.0,
		"avg_power_w": 114.0,
		"avg_ftp_pct": 57.0,
		"np_w": 118.0,
		"time_in_band_pct": 99.0,
		"xp": 321,
		"stats":
		{
			"WORKOUT_STAT_GRADE": "S",
			"WORKOUT_STAT_TIB_PCT": 98.9,
			"WORKOUT_STAT_INTERVALS": "99 / 100 / 100 / 99 / 100 / 99 / 100 / 96",
			"WORKOUT_STAT_SPRINT_PEAK_W": 284,
			"WORKOUT_STAT_SPRINTS_HIT": "3/3",
		},
	}
	var rows: Array[Dictionary] = [row]
	r.rows = rows
	r.team = {
		"WORKOUT_STAT_GROUP_TIB_PCT": 98.9,
		"WORKOUT_STAT_RIDERS": 1,
		"WORKOUT_STAT_GROUP_SPRINTS_HIT": 3
	}
	return r


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out


func test_results_menu_and_ftp_column_fit_on_a_1080p_screen() -> void:
	fx.give_profile()
	fx.fake_rides().connected = true
	var s := (
		open_screen(
			AppResultsScreen.new(),
			{
				"results": _workout_results(),
				"fit_path": "user://rides/x.fit",
				"game_id": "workout",
				"content_id": "easy_30",
				"role": Wl.SOLO,
				"local_peer": 1,
			}
		)
		as AppResultsScreen
	)
	await wait_process_frames(3)
	var grid_w := s.rows_grid.get_combined_minimum_size().x
	# make_page: 48 px margins, a 48 px gap, a 640 px menu column.
	var budget := 1920.0 - 2.0 * AppStyle.MARGIN - 48.0 - 640.0
	assert_true(
		grid_w <= budget,
		"rows grid needs %.0f px, the content column has %.0f px at 1080p" % [grid_w, budget]
	)
	var vp_w := s.get_viewport_rect().size.x
	var col := s.find_child("MenuColumn", true, false) as Control
	assert_true(
		col.get_global_rect().end.x <= vp_w + 0.5,
		(
			"menu column x=%.0f..%.0f on a %.0f px wide screen"
			% [col.get_global_rect().position.x, col.get_global_rect().end.x, vp_w]
		)
	)
	var ftp_header := s.rows_grid.get_child(3) as Control
	assert_eq((ftp_header as Label).text, AppScreen.t("APP_COL_FTP"))
	assert_true(
		ftp_header.get_global_rect().end.x <= vp_w,
		(
			"%%FTP column header ends at x=%.0f (screen %.0f)"
			% [ftp_header.get_global_rect().end.x, vp_w]
		)
	)
	for id: String in ["upload", "continue"]:
		var row := menu(s).row(menu(s).index_of_id(id))
		assert_not_null(row, id)
		if row != null:
			assert_true(
				row.get_global_rect().end.x <= vp_w + 0.5,
				"%s row ends at x=%.0f" % [id, row.get_global_rect().end.x]
			)
	var stats := s.find_child("Stats1", true, false) as Label
	assert_not_null(stats, "the stats line is still shown")
	if stats != null:
		assert_true(stats.text.contains("284"), stats.text)
		# W4r2 R26: the stats lines run the full page width under the content and menu columns
		# (tests/app/test_results_fit.gd checks the whole page against 1080p).
		assert_true(
			stats.get_global_rect().end.x <= vp_w - AppStyle.MARGIN + 0.5,
			"the stats line wraps inside the page"
		)
		assert_true(
			stats.get_global_rect().position.y >= col.get_global_rect().end.y,
			"under the menu column, never across it"
		)


func test_results_show_wkg_when_the_rider_opted_in() -> void:
	var p := fx.give_profile()
	p.show_wkg = true
	p.weight_kg = 76.0
	var s := (
		open_screen(
			AppResultsScreen.new(),
			{
				"results": _workout_results(),
				"fit_path": "user://rides/x.fit",
				"game_id": "workout",
				"local_peer": 1,
			}
		)
		as AppResultsScreen
	)
	assert_not_null(s.wkg_label)
	assert_eq(s.wkg_label.text, AppScreen.t("APP_RESULTS_WKG").format(["1.5"]), "114 W / 76 kg")
	assert_true(_all_text(s).contains("W/kg"))


func test_results_show_no_wkg_without_the_opt_in() -> void:
	var p := fx.give_profile()
	p.show_wkg = false
	p.share_weight = true
	p.weight_kg = 76.0
	var s := (
		open_screen(
			AppResultsScreen.new(),
			{
				"results": _workout_results(),
				"fit_path": "user://rides/x.fit",
				"game_id": "workout",
				"local_peer": 1,
			}
		)
		as AppResultsScreen
	)
	assert_null(s.wkg_label)
	assert_false(_all_text(s).contains("W/kg"), "no W/kg for a rider who did not opt in")


func test_wkg_text_rule() -> void:
	var p := RiderProfile.new()
	p.weight_kg = 70.0
	var row := {"avg_power_w": 210.0}
	assert_eq(AppResultsScreen.wkg_text(row, p), "", "off by default")
	p.show_wkg = true
	assert_eq(AppResultsScreen.wkg_text(row, p), AppScreen.t("APP_RESULTS_WKG").format(["3.0"]))
	assert_eq(AppResultsScreen.wkg_text({}, p), "", "no local row")
	p.weight_kg = 0.0
	assert_eq(AppResultsScreen.wkg_text(row, p), "", "no weight")


func test_new_unlocks_show_their_names() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppResultsScreen.new(),
			{
				"results": _workout_results(),
				"game_id": "workout",
				"local_peer": 1,
				"unlocks": ["pennant_swallowtail", "pennant_star", "no_name_for_this"],
			}
		)
		as AppResultsScreen
	)
	var swallow := AppScreen.t("WORKOUT_UNLOCK_PENNANT_SWALLOWTAIL")
	assert_ne(swallow, "WORKOUT_UNLOCK_PENNANT_SWALLOWTAIL", "Workout's strings are loaded")
	assert_true(s.unlocks_label.text.contains(swallow), s.unlocks_label.text)
	assert_true(
		s.unlocks_label.text.contains(AppScreen.t("WORKOUT_UNLOCK_PENNANT_STAR")),
		s.unlocks_label.text
	)
	assert_false(
		s.unlocks_label.text.contains("pennant_swallowtail"), "no raw id when a name exists"
	)
	assert_true(
		s.unlocks_label.text.contains("no_name_for_this"), "an id without a name stays readable"
	)


func test_unlock_names_rule() -> void:
	var names := AppResultsScreen.unlock_names("workout", ["pennant_star", "SIEGE_BANNER_RED"])
	assert_eq(names[0], AppScreen.t("WORKOUT_UNLOCK_PENNANT_STAR"))
	assert_eq(
		names[1], AppScreen.t("SIEGE_BANNER_RED"), "an id that is a string key itself still works"
	)
	assert_eq(AppResultsScreen.unlock_names("", ["x"])[0], "x")
