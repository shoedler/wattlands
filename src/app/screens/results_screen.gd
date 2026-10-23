class_name AppResultsScreen
extends AppScreen
## Results (BRIEF 3.6, 3.8): the GameResults grade, per-rider rows (kJ, average W and %FTP, NP,
## time in band), each rider's custom stats as a wrapped line (so a long stats line never widens
## the grid, W3 ZIH-1), team stats, XP and the local rider's new unlocks (named by
## <GAME_ID>_UNLOCK_<ID> when the game has that string, else the id; W3 ZIH-8); the local rider's
## average W/kg when they opted in (profile show_wkg, computed here from the local weight and never
## sent; BRIEF 3.3, W3 PROF-5); where the ride was saved; Upload to Strava (pedal-scan selectable)
## and the auto-upload status from EventBus.upload_state_changed; Continue. With auto-upload on
## and Strava connected, the ride uploads without a prompt (once).
##
## The page never scrolls, so it must fit the screen (1080p) with every line on it, the upload
## status included, for 1 to 8 riders (W4r2 R16, R26):
## - The menu column holds the menu, then the upload status and the host-left notice. The
##   content column holds the grade with the local rider's summary and new unlocks, and the rows
##   grid. The custom stats lines, the team line and where the ride was saved run the full page
##   width under both columns.
## - Fit steps, applied in order while the page is taller than the screen (checked once per
##   frame after a layout change, so a long upload status re-checks too; fit_level):
##   1 FIT_COMPACT_TOP: a smaller grade (FONT_NUMBER), the XP beside it, a smaller summary;
##   2 FIT_OWN_STATS: only the local rider's custom stats line (the grid still shows every
##     rider's kJ, W, %FTP, NP, time in band and XP; each rider's own screen has their stats);
##   3 FIT_SMALL_GRID: the grid's rows in FONT_SMALL;
##   4 FIT_CAP_TEXT: the stats line at most 3 lines and the team line 1, ending in an ellipsis;
##   5 FIT_CAP_MORE: every wrapped line at most 1 or 2 lines.
##   A page with more than ROOMY_MAX_RIDERS rows starts at FIT_OWN_STATS. Workout's real stats fit
##   uncut from 1 to 8 riders; the caps only bite on very long stats (a .zwo with dozens of
##   intervals).
## Custom and team stats keep the game's order (the Dictionary's insertion order, which the
## protocol keeps too; W4r2 R18).
## params: results (GameResults), fit_path, summary (ride JSON summary), unlocks (Array),
## game_id, content_id, role, local_peer, host_left, autopilot (the rider rode the session on
## Autopilot: the menu scans, BRIEF 3.5).

const DONE_STATES: Array[String] = ["uploaded", "duplicate"]
const BUSY_STATES: Array[String] = ["queued", "uploading", "processing"]
## Pages with more rows than this start at FIT_OWN_STATS.
const ROOMY_MAX_RIDERS := 3
const FIT_COMPACT_TOP := 1
const FIT_OWN_STATS := 2
const FIT_SMALL_GRID := 3
const FIT_CAP_TEXT := 4
const FIT_CAP_MORE := 5

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
## The riders' custom stats lines (one wrapped paragraph per rider with stats).
var stats_box: VBoxContainer = null
## The local rider's average W/kg (only when opted in).
var wkg_label: Label = null
## How many fit steps the page uses (0: none; see the header).
var fit_level: int = 0
var local_peer: int = Wl.HOST_PEER
var _page_root: Control = null
var _top: HBoxContainer = null
var _side: VBoxContainer = null
var _me_label: Label = null
var _team_label: Label = null
var _host_left_label: Label = null
var _fit_armed: bool = false


func _build() -> void:
	var r: Variant = params.get("results", null)
	has_results = r is GameResults
	results = r as GameResults if has_results else GameResults.new()
	fit_path = str(params.get("fit_path", ""))
	var sv: Variant = params.get("summary", {})
	summary = (sv as Dictionary).duplicate(true) if sv is Dictionary else {}
	var uv: Variant = params.get("unlocks", [])
	unlocks = (uv as Array).duplicate(true) if uv is Array else []
	local_peer = int(params.get("local_peer", Wl.HOST_PEER))
	var gid := str(params.get("game_id", ""))
	var m: Dictionary = (
		services.registry.manifest(gid) if services.registry != null and gid != "" else {}
	)
	var title := t("APP_RESULTS_TITLE").format([str(m.get("title", gid))])
	if results.summary_key != "":
		title = t(results.summary_key)
	var page := make_page(title)
	_page_root = page["root"]
	var left: VBoxContainer = page["left"]
	var right: VBoxContainer = page["right"]
	var footer: Control = page["footer"]
	# The details follow the columns directly, and the page has no footer line.
	(left.get_parent() as Control).size_flags_vertical = Control.SIZE_FILL
	footer.visible = false
	_top = AppStyle.hbox(48)
	_top.name = "Top"
	left.add_child(_top)
	# A session that ended without results (the host left first) shows no grade, never a "D".
	var grade_text := results.grade if has_results else "—"
	grade_label = AppStyle.label(
		grade_text,
		AppStyle.FONT_GRADE,
		grade_color(results.grade) if has_results else AppStyle.TEXT_DIM
	)
	grade_label.name = "Grade"
	_top.add_child(grade_label)
	_side = AppStyle.vbox(8)
	_side.name = "Side"
	# The side column takes the rest of the row, so its wrapped lines never push the page wider.
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(_side)
	var me := results.row(local_peer)
	xp_label = AppStyle.label(
		t("APP_RESULTS_XP").format([int(me.get("xp", 0))]), AppStyle.FONT_NUMBER, AppStyle.ACCENT
	)
	xp_label.name = "Xp"
	_side.add_child(xp_label)
	if not me.is_empty():
		_me_label = AppStyle.paragraph(
			t("APP_RESULTS_ME").format(
				[
					"%.0f" % float(me.get("kj", 0.0)),
					"%.0f" % float(me.get("avg_power_w", 0.0)),
					"%.0f" % float(me.get("time_in_band_pct", 0.0))
				]
			),
			AppStyle.FONT_NUMBER,
			AppStyle.TEXT
		)
		_me_label.name = "MeLine"
		_side.add_child(_me_label)
		var wkg := wkg_text(me, services.profile())
		if wkg != "":
			wkg_label = AppStyle.label(wkg, AppStyle.FONT_HEADING, AppStyle.ACCENT)
			wkg_label.name = "Wkg"
			_side.add_child(wkg_label)
	unlocks_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.GOOD)
	unlocks_label.name = "Unlocks"
	_side.add_child(unlocks_label)
	if not unlocks.is_empty():
		unlocks_label.text = t("APP_RESULTS_UNLOCKS").format(
			[", ".join(unlock_names(gid, unlocks))]
		)
	unlocks_label.visible = unlocks_label.text != ""
	rows_grid = _build_rows()
	left.add_child(rows_grid)
	# The menu column: the menu, then the upload status and the host-left notice.
	var menu_slot := AppStyle.vbox(8)
	menu_slot.name = "MenuSlot"
	right.add_child(menu_slot)
	set_menu_holder(menu_slot)
	var status := AppStyle.vbox(12)
	status.name = "Status"
	right.add_child(status)
	upload_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT)
	upload_label.name = "UploadStatus"
	status.add_child(upload_label)
	if bool(params.get("host_left", false)):
		_host_left_label = AppStyle.paragraph(
			t("APP_REFUSED_HOST_LEFT"), AppStyle.FONT_BODY, AppStyle.WARN
		)
		_host_left_label.name = "HostLeft"
		status.add_child(_host_left_label)
	# The details: the full page width under both columns.
	var details := AppStyle.vbox(8)
	details.name = "Details"
	_page_root.add_child(details)
	_page_root.move_child(details, footer.get_index())
	stats_box = _build_stats()
	details.add_child(stats_box)
	if not results.team.is_empty():
		_team_label = AppStyle.paragraph(
			t("APP_RESULTS_TEAM").format([stats_text(results.team)]),
			AppStyle.FONT_BODY,
			AppStyle.TEXT
		)
		_team_label.name = "Team"
		details.add_child(_team_label)
	ride_label = AppStyle.paragraph("", AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
	ride_label.name = "RideSaved"
	details.add_child(ride_label)
	set_fit_level(FIT_OWN_STATS if results.rows.size() > ROOMY_MAX_RIDERS else 0)
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


## Pedal navigation on (BRIEF 3.5): the session's Autopilot (params.autopilot, from the session
## screen) counts as well as InputRouter.pedal_nav_active().
func pedal_nav_enabled() -> bool:
	return bool(params.get("autopilot", false)) or super.pedal_nav_enabled()


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
	for key: String in [
		"APP_COL_RIDER",
		"APP_COL_KJ",
		"APP_COL_AVG_W",
		"APP_COL_FTP",
		"APP_COL_NP",
		"APP_COL_BAND",
		"APP_COL_XP"
	]:
		g.add_child(AppStyle.label(t(key), AppStyle.FONT_SMALL, AppStyle.TEXT_DIM))
	for row: Dictionary in results.rows:
		var name_text := str(row.get("name", ""))
		var row_unlocks: Array = row.get("unlocks", [])
		if not row_unlocks.is_empty():
			name_text += "  ★%d" % row_unlocks.size()
		g.add_child(AppStyle.label(name_text, AppStyle.FONT_BODY))
		g.add_child(AppStyle.label("%.0f" % float(row.get("kj", 0.0)), AppStyle.FONT_BODY))
		g.add_child(AppStyle.label("%.0f" % float(row.get("avg_power_w", 0.0)), AppStyle.FONT_BODY))
		g.add_child(
			AppStyle.label("%.0f%%" % float(row.get("avg_ftp_pct", 0.0)), AppStyle.FONT_BODY)
		)
		g.add_child(AppStyle.label("%.0f" % float(row.get("np_w", 0.0)), AppStyle.FONT_BODY))
		g.add_child(
			AppStyle.label("%.0f%%" % float(row.get("time_in_band_pct", 0.0)), AppStyle.FONT_BODY)
		)
		g.add_child(AppStyle.label(str(int(row.get("xp", 0))), AppStyle.FONT_BODY, AppStyle.ACCENT))
	return g


## One wrapped line per rider with custom stats: "Ada · Grade: S · In band (%): 99 · ...". From
## FIT_OWN_STATS on only the local rider's line shows.
func _build_stats() -> VBoxContainer:
	var box := AppStyle.vbox(6)
	box.name = "RowStats"
	for row: Dictionary in results.rows:
		var st: Variant = row.get("stats", {})
		if st is Dictionary and not (st as Dictionary).is_empty():
			var l := AppStyle.paragraph(
				"%s · %s" % [str(row.get("name", "")), stats_text(st as Dictionary)],
				AppStyle.FONT_SMALL,
				AppStyle.TEXT_DIM
			)
			l.name = "Stats%d" % int(row.get("peer_id", 0))
			box.add_child(l)
	return box


# --- fitting the screen ----------------------------------------------------------------------


## Apply the fit steps up to `level` (0..FIT_CAP_MORE) and check the fit again next frame.
func set_fit_level(level: int) -> void:
	fit_level = clampi(level, 0, FIT_CAP_MORE)
	var compact := fit_level >= FIT_COMPACT_TOP
	_font(grade_label, AppStyle.FONT_NUMBER if compact else AppStyle.FONT_GRADE)
	_font(xp_label, AppStyle.FONT_HEADING if compact else AppStyle.FONT_NUMBER)
	_font(_me_label, AppStyle.FONT_BODY if compact else AppStyle.FONT_NUMBER)
	_font(wkg_label, AppStyle.FONT_BODY if compact else AppStyle.FONT_HEADING)
	# Compact: the XP sits between the grade and the summary instead of above the summary.
	var xp_parent: Node = _top if compact else _side
	if xp_label.get_parent() != xp_parent:
		xp_label.get_parent().remove_child(xp_label)
		xp_parent.add_child(xp_label)
		xp_parent.move_child(xp_label, 1 if compact else 0)
	xp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_FILL
	grade_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_FILL
	for l: Node in stats_box.get_children():
		(l as Control).visible = fit_level < FIT_OWN_STATS or l.name == "Stats%d" % local_peer
	var small_grid := fit_level >= FIT_SMALL_GRID
	rows_grid.add_theme_constant_override("v_separation", 2 if small_grid else 6)
	var cells := rows_grid.get_children()
	for i in range(rows_grid.columns, cells.size()):
		_font(cells[i] as Label, AppStyle.FONT_SMALL if small_grid else AppStyle.FONT_BODY)
	var caps := {}
	if fit_level >= FIT_CAP_MORE:
		caps = {
			"stats": 1, "team": 1, "upload": 2, "unlocks": 1, "host_left": 1, "ride": 1, "me": 1
		}
	elif fit_level >= FIT_CAP_TEXT:
		caps = {"stats": 3, "team": 1}
	for l: Node in stats_box.get_children():
		_cap(l as Label, int(caps.get("stats", -1)))
	_cap(_team_label, int(caps.get("team", -1)))
	_cap(upload_label, int(caps.get("upload", -1)))
	_cap(unlocks_label, int(caps.get("unlocks", -1)))
	_cap(_host_left_label, int(caps.get("host_left", -1)))
	_cap(ride_label, int(caps.get("ride", -1)))
	_cap(_me_label, int(caps.get("me", -1)))
	_arm_fit()


## The page's height with its margins, from the current layout.
func page_height() -> float:
	if _page_root == null:
		return 0.0
	return _page_root.get_combined_minimum_size().y + 2.0 * AppStyle.MARGIN


func fits_screen() -> bool:
	return page_height() <= get_viewport_rect().size.y + 0.5


## The visible labels that wrap and may be cut by a cap (a cut line ends in an ellipsis).
func _wrapped_labels() -> Array[Label]:
	var out: Array[Label] = []
	for l: Label in [
		_me_label, upload_label, unlocks_label, _host_left_label, _team_label, ride_label
	]:
		if l != null:
			out.append(l)
	for l: Node in stats_box.get_children():
		out.append(l as Label)
	return out


## Labels whose text is cut by a cap right now (none on a page that fits uncut).
func cut_labels() -> Array[Label]:
	var out: Array[Label] = []
	for l in _wrapped_labels():
		if (
			l.is_visible_in_tree()
			and l.max_lines_visible >= 0
			and l.get_line_count() > l.max_lines_visible
		):
			out.append(l)
	return out


func _arm_fit() -> void:
	if _fit_armed or not is_inside_tree():
		return
	_fit_armed = true
	get_tree().process_frame.connect(_check_fit, CONNECT_ONE_SHOT)


## One frame after a layout change: take the next fit step while the page is too tall.
func _check_fit() -> void:
	_fit_armed = false
	if not is_inside_tree() or _page_root == null:
		return
	if not fits_screen() and fit_level < FIT_CAP_MORE:
		set_fit_level(fit_level + 1)


static func _font(l: Label, size: int) -> void:
	if l != null:
		l.add_theme_font_size_override("font_size", size)


## At most `lines` lines (-1: all), the last one ending in an ellipsis when text is cut. Only a
## capped label trims: an uncapped wrapping label with an overrun behavior has no minimum height.
static func _cap(l: Label, lines: int) -> void:
	if l != null:
		l.max_lines_visible = lines
		l.text_overrun_behavior = (
			TextServer.OVERRUN_TRIM_ELLIPSIS if lines >= 0 else TextServer.OVERRUN_NO_TRIMMING
		)


## "2.8 W/kg" for the local row when the rider opted in (show_wkg) and has a weight; "" otherwise.
static func wkg_text(row: Dictionary, profile: RiderProfile) -> String:
	if row.is_empty() or profile == null or not profile.show_wkg or profile.weight_kg <= 0.0:
		return ""
	var w := float(row.get("avg_power_w", 0.0))
	return AppScreen.t("APP_RESULTS_WKG").format(["%.1f" % (w / profile.weight_kg)])


## The display names of unlock ids: <GAME_ID>_UNLOCK_<ID> when that string exists (as content
## labels use <GAME_ID>_CONTENT_<CID>), else the id itself (or its own string key).
static func unlock_names(game_id: String, ids: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for v: Variant in ids:
		var id := str(v)
		var key := "%s_UNLOCK_%s" % [game_id.to_upper(), id.to_upper()]
		var named := String(TranslationServer.translate(key)) if game_id != "" else key
		out.append(named if named != key else AppScreen.t(id))
	return out


## Custom stats as "key: value · key: value" in the game's order (keys are string-table keys
## or plain names). GDScript Dictionaries keep insertion order, and so does the protocol
## (JSON without sorted keys), so a client shows the host's order (W4r2 R18).
static func stats_text(stats: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: Variant in stats.keys():
		var v: Variant = stats[k]
		var vt := (
			("%.0f" % float(v))
			if (v is float and is_equal_approx(float(v), round(float(v))))
			else str(v)
		)
		parts.append("%s: %s" % [AppScreen.t(str(k)), vt])
	return " · ".join(parts)


func ride_id() -> String:
	return str(summary.get("ride_id", ""))


func strava_connected() -> bool:
	return services.rides != null and services.rides.strava_connected()


func auto_upload_enabled() -> bool:
	if services.rides == null or fit_path == "":
		return false
	return (
		strava_connected()
		and (services.rides.auto_upload_enabled() or services.profile().strava_auto_upload)
	)


func menu_items() -> Array:
	var items: Array = []
	if fit_path != "" and strava_connected():
		var busy := BUSY_STATES.has(upload_state)
		var done := DONE_STATES.has(upload_state)
		items.append(
			{
				"id": "upload",
				"text": t("APP_RESULTS_UPLOAD"),
				"disabled": busy or done or upload_requested and upload_state == ""
			}
		)
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
		ride_label.text = (
			t("APP_RESULTS_SAVED").format([fit_path])
			if fit_path != ""
			else t("APP_RESULTS_NOT_SAVED")
		)
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
	# A longer status (the activity URL) can make the page too tall: check the fit again.
	_arm_fit()
