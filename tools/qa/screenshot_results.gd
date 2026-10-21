class_name QaScreenshotResults
extends RefCounted
## tools/screenshot --app-screen=results: the params for the app's real results screen with a
## Workout-like GameResults (W4r2 R16, R26; BRIEF 3.6, 3.8, 7.8). Owned by qa; used by
## tools/qa/screenshot_main.gd. Every rider gets the display stats a real Workout session gives
## (grade, time in band, ten intervals, best 1/5/20 min, sprint peaks, sprints hit, in the order
## WorkoutResults adds them), a 16-character name and two unlocks; the local rider is peer 1,
## with two new unlocks and a real-length FIT path. With more than one rider the host-left
## notice shows too, so the shot is the tallest page a rider can get.


## The results screen params for `riders` riders (1 to 8).
static func params(riders: int) -> Dictionary:
	var n := clampi(riders, 1, QaScreenshotOptions.MAX_RESULTS_RIDERS)
	var r := GameResults.new()
	r.grade = "S"
	r.summary_key = "WORKOUT_RESULT_S"
	r.session_id = "screenshot/results/%d" % n
	var rows: Array[Dictionary] = []
	for i in n:
		rows.append({
			"peer_id": i + 1, "slot_index": i, "name": "Wilhelmina Fea %d" % (i + 1), "is_bot": false,
			"kj": 612.0 - 7.0 * i, "avg_power_w": 214.0 - 3.0 * i, "avg_ftp_pct": 86.0, "np_w": 231.0,
			"time_in_band_pct": 98.9 - i, "xp": 1321 - 11 * i, "unlocks": ["pennant_swallowtail", "pennant_star"],
			"stats": {
				"WORKOUT_STAT_GRADE": "S", "WORKOUT_STAT_TIB_PCT": 98.9,
				"WORKOUT_STAT_INTERVALS": "99 / 100 / 100 / 99 / 100 / 99 / 100 / 95 / 100 / 98",
				"WORKOUT_STAT_BEST_1M_W": 512, "WORKOUT_STAT_BEST_5M_W": 427, "WORKOUT_STAT_BEST_20M_W": 361,
				"WORKOUT_STAT_SPRINT_PEAK_W": 1302, "WORKOUT_STAT_SPRINT_PEAKS_W": "1284 / 1302 / 1277",
				"WORKOUT_STAT_SPRINTS_HIT": "3/3",
			},
		})
	r.rows = rows
	r.team = {"WORKOUT_STAT_GROUP_TIB_PCT": 98.4, "WORKOUT_STAT_RIDERS": n, "WORKOUT_STAT_GROUP_SPRINTS_HIT": 3 * n}
	return {
		"results": r, "game_id": "workout", "content_id": "vo2", "role": Wl.SOLO if n == 1 else Wl.HOST,
		"local_peer": 1, "unlocks": ["pennant_swallowtail", "pennant_star"],
		"fit_path": Paths.user_dir().path_join("rides/20261021T184934Z_workout.fit"),
		"summary": {"ride_id": "20261021T184934Z_workout"}, "host_left": n > 1,
	}


## "screenshot: results <n> riders, fit level <l>, page <h> px of <vp> px, lowest line y=<y>".
static func describe(s: AppResultsScreen) -> String:
	var lowest := 0.0
	for node in s.find_children("*", "Label", true, false):
		var l := node as Label
		if l.is_visible_in_tree() and l.text != "":
			lowest = maxf(lowest, l.get_global_rect().end.y)
	return "screenshot: results %d riders, fit level %d, page %.0f px of %.0f px, lowest line y=%.0f, cut lines %d" % [
		s.results.rows.size(), s.fit_level, s.page_height(), s.get_viewport_rect().size.y, lowest, s.cut_labels().size()]
