class_name AppResultsScreen
extends AppScreen
## Results (BRIEF 3.6, 3.8): the GameResults grade, per-rider rows (kJ, average W and %FTP, NP,
## time in band, custom stats), team stats, XP and the local rider's new unlocks; where the ride
## was saved; Upload to Strava (pedal-scan selectable) and the auto-upload status from
## EventBus.upload_state_changed; Continue. With auto-upload on and Strava connected, the ride
## uploads without a prompt (once).
## params: results (GameResults), fit_path, summary (ride JSON summary), unlocks (Array),
## game_id, content_id, role, local_peer, host_left.

const DONE_STATES: Array[String] = ["uploaded", "duplicate"]
const BUSY_STATES: Array[String] = ["queued", "uploading", "processing"]

var results: GameResults = null
## False when the session ended without GameResults (shown without a grade).
var has_results: bool = false
var fit_path: String = ""
var summary: Dictionary = {}
var unlocks: Array = []
var upload_state: String = ""
var upload_detail: String = ""
var upload_requested: bool = false
var grade_label: Label = null
var xp_label: Label = null
var ride_label: Label = null
var upload_label: Label = null
var unlocks_label: Label = null
var rows_grid: GridContainer = null


func _build() -> void:
	var r: Variant = params.get("results", null)
	has_results = r is GameResults
	results = r as GameResults if has_results else GameResults.new()
	fit_path = str(params.get("fit_path", ""))
	var sv: Variant = params.get("summary", {})
	summary = (sv as Dictionary).duplicate(true) if sv is Dictionary else {}
	var uv: Variant = params.get("unlocks", [])
	unlocks = (uv as Array).duplicate(true) if uv is Array else []
	var gid := str(params.get("game_id", ""))
	var m: Dictionary = services.registry.manifest(gid) if services.registry != null and gid != "" else {}
	var title := t("APP_RESULTS_TITLE").format([str(m.get("title", gid))])
	if results.summary_key != "":
		title = t(results.summary_key)
	var page := make_page(title)
	var left: VBoxContainer = page["left"]
	var top := AppStyle.hbox(48)
	left.add_child(top)
	# A session that ended without results (the host left first) shows no grade, never a "D".
	var grade_text := results.grade if has_results else "—"
	grade_label = AppStyle.label(grade_text, AppStyle.FONT_GRADE, grade_color(results.grade) if has_results else AppStyle.TEXT_DIM)
	grade_label.name = "Grade"
	top.add_child(grade_label)
	var side := AppStyle.vbox(8)
	top.add_child(side)
	var me := results.row(int(params.get("local_peer", Wl.HOST_PEER)))
	xp_label = AppStyle.label(t("APP_RESULTS_XP").format([int(me.get("xp", 0))]), AppStyle.FONT_NUMBER, AppStyle.ACCENT)
	xp_label.name = "Xp"
	side.add_child(xp_label)
	if not me.is_empty():
		side.add_child(AppStyle.label(t("APP_RESULTS_ME").format([
			"%.0f" % float(me.get("kj", 0.0)), "%.0f" % float(me.get("avg_power_w", 0.0)),
			"%.0f" % float(me.get("time_in_band_pct", 0.0))]), AppStyle.FONT_NUMBER))
	unlocks_label = AppStyle.paragraph("", AppStyle.FONT_HEADING, AppStyle.GOOD)
	unlocks_label.name = "Unlocks"
	left.add_child(unlocks_label)
	if not unlocks.is_empty():
		unlocks_label.text = t("APP_RESULTS_UNLOCKS").format([", ".join(_strings(unlocks))])
	rows_grid = _build_rows()
	left.add_child(rows_grid)
	if not results.team.is_empty():
		left.add_child(AppStyle.paragraph(t("APP_RESULTS_TEAM").format([stats_text(results.team)]), AppStyle.FONT_BODY, AppStyle.TEXT))
	ride_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT_DIM)
	ride_label.name = "RideSaved"
	left.add_child(ride_label)
	upload_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT)
	upload_label.name = "UploadStatus"
	left.add_child(upload_label)
	if bool(params.get("host_left", false)):
		left.add_child(AppStyle.paragraph(t("APP_REFUSED_HOST_LEFT"), AppStyle.FONT_BODY, AppStyle.WARN))
	if services.bus != null:
		services.bus.upload_state_changed.connect(_on_upload_state)
		services.bus.ride_saved.connect(_on_ride_saved)
	push_menu(menu_items(), _on_pick, Callable(), 0)
	_refresh()
	if auto_upload_enabled():
		upload()


func _on_leave() -> void:
	if services.bus != null:
		if services.bus.upload_state_changed.is_connected(_on_upload_state):
			services.bus.upload_state_changed.disconnect(_on_upload_state)
		if services.bus.ride_saved.is_connected(_on_ride_saved):
			services.bus.ride_saved.disconnect(_on_ride_saved)


static func grade_color(grade: String) -> Color:
	match grade:
		"S", "A":
			return AppStyle.GOOD
		"B":
			return AppStyle.ACCENT
		"C":
			return AppStyle.WARN
	return AppStyle.BAD


func _build_rows() -> GridContainer:
	var g := GridContainer.new()
	g.name = "Rows"
	g.columns = 7
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 6)
	for key: String in ["APP_COL_RIDER", "APP_COL_KJ", "APP_COL_AVG_W", "APP_COL_FTP", "APP_COL_NP", "APP_COL_BAND", "APP_COL_XP"]:
		g.add_child(AppStyle.label(t(key), AppStyle.FONT_SMALL, AppStyle.TEXT_DIM))
	for row: Dictionary in results.rows:
		var name_text := str(row.get("name", ""))
		var row_unlocks: Array = row.get("unlocks", [])
		if not row_unlocks.is_empty():
			name_text += "  ★%d" % row_unlocks.size()
		g.add_child(AppStyle.label(name_text, AppStyle.FONT_BODY))
		g.add_child(AppStyle.label("%.0f" % float(row.get("kj", 0.0)), AppStyle.FONT_BODY))
		g.add_child(AppStyle.label("%.0f" % float(row.get("avg_power_w", 0.0)), AppStyle.FONT_BODY))
		g.add_child(AppStyle.label("%.0f%%" % float(row.get("avg_ftp_pct", 0.0)), AppStyle.FONT_BODY))
		g.add_child(AppStyle.label("%.0f" % float(row.get("np_w", 0.0)), AppStyle.FONT_BODY))
		g.add_child(AppStyle.label("%.0f%%" % float(row.get("time_in_band_pct", 0.0)), AppStyle.FONT_BODY))
		g.add_child(AppStyle.label(str(int(row.get("xp", 0))), AppStyle.FONT_BODY, AppStyle.ACCENT))
		var st: Variant = row.get("stats", {})
		if st is Dictionary and not (st as Dictionary).is_empty():
			var l := AppStyle.label(stats_text(st as Dictionary), AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
			g.add_child(l)
			for _i in g.columns - 1:
				g.add_child(Control.new())
	return g


## Custom stats as "key: value · key: value" (keys are string-table keys or plain names).
static func stats_text(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	var keys := stats.keys()
	keys.sort()
	for k: Variant in keys:
		var v: Variant = stats[k]
		var vt := ("%.0f" % float(v)) if (v is float and is_equal_approx(float(v), round(float(v)))) else str(v)
		parts.append("%s: %s" % [AppScreen.t(str(k)), vt])
	return " · ".join(parts)


static func _strings(arr: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for v: Variant in arr:
		out.append(AppScreen.t(str(v)))
	return out


func ride_id() -> String:
	return str(summary.get("ride_id", ""))


func strava_connected() -> bool:
	return services.rides != null and services.rides.strava_connected()


func auto_upload_enabled() -> bool:
	if services.rides == null or fit_path == "":
		return false
	return strava_connected() and (services.rides.auto_upload_enabled() or services.profile().strava_auto_upload)


func menu_items() -> Array:
	var items: Array = []
	if fit_path != "" and strava_connected():
		var busy := BUSY_STATES.has(upload_state)
		var done := DONE_STATES.has(upload_state)
		items.append({"id": "upload", "text": t("APP_RESULTS_UPLOAD"), "disabled": busy or done or upload_requested and upload_state == ""})
	items.append({"id": "continue", "text": t("APP_RESULTS_CONTINUE")})
	return items


func _on_pick(_index: int, id: Variant, _auto: bool) -> void:
	match str(id):
		"upload":
			upload()
		"continue":
			finish()


## Upload this ride to Strava (Rides queues it when offline).
func upload() -> void:
	if fit_path == "" or services.rides == null:
		return
	if upload_requested and not (upload_state in ["failed", "offline"]):
		return
	upload_requested = true
	var s := summary.duplicate(true)
	if not s.has("fit_path"):
		s["fit_path"] = fit_path
	services.rides.upload(fit_path, s)
	_refresh()


func finish() -> void:
	if services.net != null:
		services.net.leave()
	goto("title")


func _on_upload_state(rid: String, state: String, detail: String) -> void:
	if ride_id() != "" and rid != "" and rid != ride_id():
		return
	upload_state = state
	upload_detail = detail
	_refresh()


func _on_ride_saved(path: String, s: Dictionary) -> void:
	if fit_path == "":
		fit_path = path
		summary = s.duplicate(true)
		_refresh()
		if auto_upload_enabled():
			upload()


func _refresh() -> void:
	if ride_label != null:
		ride_label.text = t("APP_RESULTS_SAVED").format([fit_path]) if fit_path != "" else t("APP_RESULTS_NOT_SAVED")
	if upload_label != null:
		if not strava_connected():
			upload_label.text = t("APP_RESULTS_STRAVA_OFF")
		elif upload_state != "":
			upload_label.text = t("APP_UPLOAD_" + upload_state.to_upper()).format([upload_detail])
		elif upload_requested:
			upload_label.text = t("APP_UPLOAD_QUEUED").format([""])
		elif auto_upload_enabled():
			upload_label.text = t("APP_RESULTS_AUTO")
		else:
			upload_label.text = ""
	if not menus.is_empty():
		refresh_menu(menu_items(), menus[0])
