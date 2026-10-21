extends "res://tests/app/app_test_base.gd"
## The results page fits a 1080p screen with every line on it (W4r2 R16, R26; BRIEF 3.8 "the
## auto-upload status", 3.9 readability; the page never scrolls). Worst realistic case for each
## rider count from 1 to 8: Workout's real Easy 30 stats (best 1/5/20 min and every sprint peak,
## W4 WO-2), 16-character names, Strava connected with "Uploaded" and its activity URL, a
## real-length FIT path, two new unlocks, W/kg on and the host-left notice.
## Also: custom and team stats keep the game's order (W4r2 R18).

var _old_size: Vector2i = Vector2i.ZERO


func before_each() -> void:
	super.before_each()
	_old_size = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)


func after_each() -> void:
	super.after_each()
	get_tree().root.size = _old_size


## The display stats WorkoutResults.build gives a rider, in its order: the most intervals a
## shipped Workout session has (VO2, 10), strong best powers and four-digit sprint peaks.
static func _workout_stats() -> Dictionary:
	return {
		"WORKOUT_STAT_GRADE": "S",
		"WORKOUT_STAT_TIB_PCT": 98.9,
		"WORKOUT_STAT_INTERVALS": "99 / 100 / 100 / 99 / 100 / 99 / 100 / 95 / 100 / 98",
		"WORKOUT_STAT_BEST_1M_W": 512,
		"WORKOUT_STAT_BEST_5M_W": 427,
		"WORKOUT_STAT_BEST_20M_W": 361,
		"WORKOUT_STAT_SPRINT_PEAK_W": 1302,
		"WORKOUT_STAT_SPRINT_PEAKS_W": "1284 / 1302 / 1277",
		"WORKOUT_STAT_SPRINTS_HIT": "3/3",
	}


static func _results(n: int, stats: Dictionary = {}) -> GameResults:
	var r := GameResults.new()
	r.grade = "S"
	r.summary_key = "WORKOUT_RESULT_S"
	var rows: Array[Dictionary] = []
	for i in n:
		(
			rows
			. append(
				{
					"peer_id": i + 1,
					"name": "Wilhelmina Fea %d" % (i + 1),
					"kj": 1192.0,
					"avg_power_w": 314.0,
					"avg_ftp_pct": 107.0,
					"np_w": 335.0,
					"time_in_band_pct": 99.0,
					"xp": 1321,
					"unlocks": ["pennant_swallowtail", "pennant_star"],
					"stats": stats.duplicate() if not stats.is_empty() else _workout_stats(),
				}
			)
		)
	r.rows = rows
	r.team = {
		"WORKOUT_STAT_GROUP_TIB_PCT": 98.9,
		"WORKOUT_STAT_RIDERS": n,
		"WORKOUT_STAT_GROUP_SPRINTS_HIT": 3 * n
	}
	return r


func _open_results(n: int, local_peer: int = 1, stats: Dictionary = {}) -> AppResultsScreen:
	var p := fx.give_profile()
	p.show_wkg = true
	p.weight_kg = 76.0
	fx.fake_rides().connected = true
	var s := (
		open_screen(
			AppResultsScreen.new(),
			{
				"results": _results(n, stats),
				"game_id": "workout",
				"content_id": "easy_30",
				"fit_path":
				"C:/Users/Wilhelmina/AppData/Roaming/Wattlands/rides/20261021T184934Z_workout.fit",
				"summary": {"ride_id": "r1"},
				"role": Wl.SOLO if n == 1 else Wl.CLIENT,
				"local_peer": local_peer,
				"unlocks": ["pennant_swallowtail", "pennant_star"],
				"host_left": n > 1,
			}
		)
		as AppResultsScreen
	)
	s._on_upload_state("r1", "uploaded", "https://www.strava.com/activities/12345678901")
	return s


## Every visible Label with text that ends outside the screen (or inside the bottom margin).
func _off_screen(s: Control) -> Array[String]:
	var out: Array[String] = []
	var vp := s.get_viewport_rect()
	var limit := Rect2(vp.position, Vector2(vp.size.x, vp.size.y - AppStyle.MARGIN + 0.5))
	for n in s.find_children("*", "Label", true, false):
		var l := n as Label
		if not l.is_visible_in_tree() or l.text == "":
			continue
		var r := l.get_global_rect()
		if not limit.encloses(r):
			out.append(
				(
					"%s '%s' x=%.0f..%.0f y=%.0f..%.0f"
					% [l.name, l.text.left(40), r.position.x, r.end.x, r.position.y, r.end.y]
				)
			)
	return out


## Wait until the page settled on its fit steps (one per frame at most).
func _settle(s: AppResultsScreen) -> void:
	await wait_process_frames(AppResultsScreen.FIT_CAP_MORE + 3)


func _check_fits(n: int) -> AppResultsScreen:
	var s := _open_results(n)
	await _settle(s)
	assert_eq(s.get_viewport_rect().size, Vector2(1920, 1080))
	var off := _off_screen(s)
	assert_eq(
		off,
		[] as Array[String],
		"%d rider(s): every line on a 1080p screen: %s" % [n, "; ".join(off)]
	)
	assert_true(
		s.page_height() <= 1080.0,
		"%d rider(s): the page needs %.0f px of 1080" % [n, s.page_height()]
	)
	assert_eq(
		s.cut_labels(),
		[] as Array[Label],
		"%d rider(s): Workout's stats fit uncut (fit level %d)" % [n, s.fit_level]
	)
	for l: Label in [s.upload_label, s.ride_label, s.unlocks_label, s.grade_label, s.xp_label]:
		assert_true(
			l.is_visible_in_tree() and l.text != "", "%d rider(s): %s is shown" % [n, l.name]
		)
	assert_eq(
		s.upload_label.text,
		AppScreen.t("APP_UPLOAD_UPLOADED").format(["https://www.strava.com/activities/12345678901"])
	)
	var gone := s.find_child("HostLeft", true, false) as Label
	if n > 1:
		assert_true(gone != null and gone.is_visible_in_tree(), "the host-left notice")
	var team := s.find_child("Team", true, false) as Label
	assert_true(team != null and team.is_visible_in_tree(), "the team line")
	var mine := s.find_child("Stats1", true, false) as Label
	assert_true(
		mine != null and mine.is_visible_in_tree(), "%d rider(s): the local rider's stats" % n
	)
	if mine != null:
		assert_true(mine.text.contains("1284 / 1302 / 1277"), "in full")
	# Every rider's row is in the grid (7 columns: the header plus one line per rider).
	assert_eq(s.rows_grid.get_child_count(), 7 * (n + 1), "%d rider(s): a grid row per rider" % n)
	for c in s.rows_grid.get_children():
		assert_true((c as Control).is_visible_in_tree())
	for id: String in ["upload", "continue"]:
		var row := menu(s).row(menu(s).index_of_id(id))
		assert_not_null(row, id)
		if row != null:
			assert_true(
				row.get_global_rect().end.y <= 1080.0 - AppStyle.MARGIN, "%s row on screen" % id
			)
	gut.p("%d rider(s): fit level %d, page %.0f px" % [n, s.fit_level, s.page_height()])
	return s


func test_one_rider_fits_1080p() -> void:
	var s: AppResultsScreen = await _check_fits(1)
	assert_eq(s.fit_level, 0, "solo keeps the big grade")


func test_two_riders_fit_1080p() -> void:
	var s: AppResultsScreen = await _check_fits(2)
	assert_lt(s.fit_level, AppResultsScreen.FIT_OWN_STATS, "both riders' stats")
	assert_true((s.find_child("Stats2", true, false) as Label).is_visible_in_tree())


func test_three_riders_fit_1080p() -> void:
	await _check_fits(3)


func test_four_riders_fit_1080p() -> void:
	await _check_fits(4)


func test_five_riders_fit_1080p() -> void:
	await _check_fits(5)


func test_six_riders_fit_1080p() -> void:
	await _check_fits(6)


func test_eight_riders_fit_1080p() -> void:
	var s: AppResultsScreen = await _check_fits(8)
	assert_gte(
		AppStyle.font_size_of(s.grade_label),
		AppStyle.KEY_NUMBER_MIN,
		"the grade stays a key number"
	)
	assert_gte(AppStyle.font_size_of(s.xp_label), AppStyle.KEY_NUMBER_MIN)


func test_more_than_three_riders_show_the_local_riders_stats() -> void:
	var s := _open_results(4, 3)
	assert_gte(s.fit_level, AppResultsScreen.FIT_OWN_STATS, "starts compact")
	assert_true(
		(s.find_child("Stats3", true, false) as Control).is_visible_in_tree(),
		"the local rider's stats"
	)
	for peer in [1, 2, 4]:
		assert_false(
			(s.find_child("Stats%d" % peer, true, false) as Control).is_visible_in_tree(),
			"rider %d's stats are on their own results screen" % peer
		)


func test_very_long_stats_still_fit_cut_with_an_ellipsis() -> void:
	# A .zwo with 200 intervals: the stats line alone would need a dozen lines.
	var st := _workout_stats()
	var iv: PackedStringArray = []
	for i in 200:
		iv.append(str(95 + i % 6))
	st["WORKOUT_STAT_INTERVALS"] = " / ".join(iv)
	var s := _open_results(2, 1, st)
	await _settle(s)
	assert_eq(_off_screen(s), [] as Array[String], "every line on screen")
	assert_true(s.page_height() <= 1080.0, "the page needs %.0f px" % s.page_height())
	assert_gte(s.fit_level, AppResultsScreen.FIT_CAP_TEXT)
	var mine := s.find_child("Stats1", true, false) as Label
	assert_true(s.cut_labels().has(mine), "the stats line is cut")
	assert_eq(mine.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "with an ellipsis")
	assert_true(
		s.upload_label.is_visible_in_tree() and s.cut_labels().find(s.upload_label) < 0,
		"the upload status stays whole"
	)


func test_a_longer_upload_status_later_checks_the_fit_again() -> void:
	var s := _open_results(2)
	s._on_upload_state("r1", "queued", "")
	await _settle(s)
	var before := s.fit_level
	(
		s
		. _on_upload_state(
			"r1",
			"failed",
			"the Strava server answered 500 Internal Server Error: please try again later from the rides page"
		)
	)
	await _settle(s)
	assert_gte(s.fit_level, before)
	assert_eq(_off_screen(s), [] as Array[String])
	assert_true(s.page_height() <= 1080.0)


func test_stats_keep_the_games_order() -> void:
	var text := AppResultsScreen.stats_text(_workout_stats())
	var order: Array[int] = []
	for key: String in [
		"WORKOUT_STAT_GRADE",
		"WORKOUT_STAT_TIB_PCT",
		"WORKOUT_STAT_INTERVALS",
		"WORKOUT_STAT_BEST_1M_W",
		"WORKOUT_STAT_BEST_5M_W",
		"WORKOUT_STAT_BEST_20M_W",
		"WORKOUT_STAT_SPRINT_PEAK_W",
		"WORKOUT_STAT_SPRINT_PEAKS_W",
		"WORKOUT_STAT_SPRINTS_HIT"
	]:
		var at := text.find(AppScreen.t(key) + ":")
		assert_gte(at, 0, key)
		order.append(at)
	var sorted := order.duplicate()
	sorted.sort()
	assert_eq(
		order, sorted, "best 1, 5 and 20 min in that order, as WorkoutResults adds them: %s" % text
	)
	assert_true(
		(
			text.find(AppScreen.t("WORKOUT_STAT_BEST_5M_W"))
			< text.find(AppScreen.t("WORKOUT_STAT_BEST_20M_W"))
		)
	)


func test_stats_order_survives_the_protocol() -> void:
	# The host sends GameResults to clients in a results event; JSON keeps the key order there.
	var r := _results(1)
	var wire := JSON.stringify(r.to_dict(), "", false, true)
	var back := GameResults.from_dict(JSON.parse_string(wire) as Dictionary)
	assert_eq(
		AppResultsScreen.stats_text(back.rows[0]["stats"]),
		AppResultsScreen.stats_text(_workout_stats())
	)
	assert_eq(
		(back.team as Dictionary).keys(),
		["WORKOUT_STAT_GROUP_TIB_PCT", "WORKOUT_STAT_RIDERS", "WORKOUT_STAT_GROUP_SPRINTS_HIT"]
	)
