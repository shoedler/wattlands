class_name AppRidesScreen
extends AppScreen
## Rides history (BRIEF 3.8, P1; Settings -> Rides): every saved ride, newest first, with its
## upload state. Picking a ride opens its actions: upload it to Strava, or re-upload one already
## on Strava (Rides.reupload, even when it was marked uploaded: a ride deleted on Strava goes up
## again; W3 RS-3), and "Copy title" and "Copy description", which put exactly the Strava
## activity name and description (WlRides.activity_name / activity_description of the saved
## summary) on the clipboard for a manual upload; the copies work without Strava. The page also
## shows, once, the folder the rides are saved in (Paths.rides_dir(), an absolute OS path) with
## a "Copy folder path" item. Every copy confirms with a short notice (COPIED_S). Pedal-scan
## selectable.

## How long the "copied" notice stays.
const COPIED_S := 3.0

var rides: Array = []
var states: Dictionary = {}
## Why the last upload of ride i failed (the detail of a "failed" upload state).
var reasons: Dictionary = {}
var status_label: Label = null
## "Rides are saved in: <path>" (small, dim).
var folder_label: Label = null
## The confirmation after a copy ("Title copied"); empty when none.
var copied_label: Label = null
var list_box: VBoxContainer = null
## (text: String) -> void: puts text on the clipboard (tests swap it for a recorder).
var clipboard_set: Callable = DisplayServer.clipboard_set
## The ride whose actions are open (-1: the list).
var open_ride: int = -1
var _copied_left_s: float = 0.0


func _build() -> void:
	var page := make_page(t("APP_RIDES_TITLE"))
	# One row per ride: the list scrolls and keeps the highlighted ride in view.
	(page["footer"] as Control).visible = false
	scroll_menu_column(page["right"] as Control)
	var left: VBoxContainer = page["left"]

	status_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT)
	status_label.name = "Status"
	left.add_child(status_label)
	folder_label = AppStyle.paragraph(
		t("APP_RIDES_FOLDER").format([rides_folder()]), AppStyle.FONT_SMALL, AppStyle.TEXT_DIM
	)
	folder_label.name = "Folder"
	left.add_child(folder_label)
	copied_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.ACCENT)
	copied_label.name = "Copied"
	left.add_child(copied_label)
	list_box = AppStyle.vbox(6)
	left.add_child(list_box)
	if services.bus != null:
		services.bus.upload_state_changed.connect(_on_upload_state)
	reload()
	push_menu(menu_items(), _on_pick, _back)


func _on_leave() -> void:
	if services.bus != null and services.bus.upload_state_changed.is_connected(_on_upload_state):
		services.bus.upload_state_changed.disconnect(_on_upload_state)


func _tick(dt: float) -> void:
	if _copied_left_s > 0.0:
		_copied_left_s -= dt
		if _copied_left_s <= 0.0:
			copied_label.text = ""


func reload() -> void:
	rides = services.rides.rides() if services.rides != null else []
	status_label.text = (
		t("APP_RIDES_NONE")
		if rides.is_empty()
		else (t("APP_RIDES_HINT") if strava_connected() else t("APP_RESULTS_STRAVA_OFF"))
	)


## The folder the rides are saved in, as an absolute OS path.
static func rides_folder() -> String:
	return ProjectSettings.globalize_path(Paths.rides_dir())


func strava_connected() -> bool:
	return services.rides != null and services.rides.strava_connected()


func ride_text(i: int) -> String:
	var r: Dictionary = rides[i]
	var s: Dictionary = r.get("summary", {})
	var when := str(s.get("utc_start", ""))
	var game := str(s.get("game_id", ""))
	var dur := AppStyle.duration_text(float(s.get("duration_s", 0.0)))
	var state := str(states.get(i, ""))
	if failure_text(i) != "":
		state = ""
	elif state == "":
		state = t("APP_RIDES_UPLOADED") if bool(r.get("uploaded", false)) else ""
	else:
		state = t("APP_UPLOAD_" + state.to_upper()).format([""]).strip_edges()
	return ("%s  %s  %s  %s" % [when, game, dur, state]).strip_edges()


## "Upload failed: <reason>" when the last upload of ride `i` failed (this visit, or the one
## saved in its summary), else "". Shown on the row's second line, which scrolls when long.
func failure_text(i: int) -> String:
	var reason := ""
	if states.has(i):
		if str(states[i]) != "failed":
			return ""
		reason = str(reasons.get(i, ""))
	else:
		var r: Dictionary = rides[i]
		if str(r.get("state", "")) != "failed":
			return ""
		var up: Variant = (r.get("summary", {}) as Dictionary).get("upload", {})
		reason = str((up as Dictionary).get("error", "")) if up is Dictionary else ""
	return t("APP_UPLOAD_FAILED").format([reason]).strip_edges()


## The list: one row per ride, then "Copy folder path" and Back.
func menu_items() -> Array:
	var items: Array = []
	for i in rides.size():
		var item := {"id": i, "text": ride_text(i)}
		var failure := failure_text(i)
		if failure != "":
			item["detail"] = failure
		items.append(item)
	items.append({"id": "copy_folder", "text": t("APP_RIDES_COPY_FOLDER")})
	items.append({"id": "back", "text": t("APP_BACK")})
	return items


## Ride `i`'s actions: upload (or re-upload; needs Strava), copy title, copy description, Back.
func ride_items(i: int) -> Array:
	var upload_key := "APP_RIDES_REUPLOAD" if is_on_strava(i) else "APP_RIDES_UPLOAD"
	return [
		{"id": "upload", "text": t(upload_key), "disabled": not strava_connected()},
		{"id": "copy_title", "text": t("APP_RIDES_COPY_TITLE")},
		{"id": "copy_description", "text": t("APP_RIDES_COPY_DESCRIPTION")},
		{"id": "back", "text": t("APP_BACK")},
	]


func _on_pick(_index: int, id: Variant, _auto: bool) -> void:
	match str(id):
		"back":
			_back()
		"copy_folder":
			copy_folder_path()
		_:
			open_actions(int(id))


## Show ride `i`'s actions.
func open_actions(i: int) -> void:
	if i < 0 or i >= rides.size():
		return
	open_ride = i
	push_menu(ride_items(i), _on_ride_pick, _close_actions)


func _on_ride_pick(_index: int, id: Variant, _auto: bool) -> void:
	var i := open_ride
	match str(id):
		"upload":
			_close_actions()
			upload(i)
		"copy_title":
			copy_title(i)
		"copy_description":
			copy_description(i)
		_:
			_close_actions()


## Back from a ride's actions to the list, with that ride highlighted.
func _close_actions() -> void:
	if open_ride < 0:
		return
	var i := open_ride
	open_ride = -1
	pop_menu()
	refresh_menu(menu_items())
	var m := active_menu()
	if m != null:
		m.set_highlight(i)


## The Strava activity name of ride `i` ("" without a ride).
func ride_title(i: int) -> String:
	if i < 0 or i >= rides.size():
		return ""
	return WlRides.activity_name((rides[i] as Dictionary).get("summary", {}))


## The Strava activity description of ride `i` ("" without a ride).
func ride_description(i: int) -> String:
	if i < 0 or i >= rides.size():
		return ""
	return WlRides.activity_description((rides[i] as Dictionary).get("summary", {}))


func copy_title(i: int) -> void:
	_copy(ride_title(i), "APP_RIDES_COPIED_TITLE")


func copy_description(i: int) -> void:
	_copy(ride_description(i), "APP_RIDES_COPIED_DESCRIPTION")


func copy_folder_path() -> void:
	_copy(rides_folder(), "APP_RIDES_COPIED_FOLDER")


func _copy(text: String, notice_key: String) -> void:
	if text.is_empty():
		return
	if clipboard_set.is_valid():
		clipboard_set.call(text)
	copied_label.text = t(notice_key)
	_copied_left_s = COPIED_S


## Upload (or re-upload) ride `i` to Strava.
func upload(i: int) -> void:
	if i < 0 or i >= rides.size() or services.rides == null:
		return
	var r: Dictionary = rides[i]
	var s: Dictionary = (r.get("summary", {}) as Dictionary).duplicate(true)
	var path := str(r.get("fit_path", s.get("fit_path", "")))
	if path == "":
		return
	states[i] = "queued"
	var rid := str(s.get("ride_id", ""))
	if is_on_strava(i) and rid != "":
		services.rides.reupload(rid)
	else:
		services.rides.upload(path, s)
	_refresh_list()


## True when ride `i` is already on Strava (uploaded, or a duplicate Strava already had).
func is_on_strava(i: int) -> bool:
	if i < 0 or i >= rides.size():
		return false
	var r: Dictionary = rides[i]
	var up: Variant = (r.get("summary", {}) as Dictionary).get("upload", {})
	var st := str(r.get("state", (up as Dictionary).get("state", "") if up is Dictionary else ""))
	return bool(r.get("uploaded", false)) or st == "uploaded" or st == "duplicate"


func _on_upload_state(ride_id: String, state: String, detail: String) -> void:
	for i in rides.size():
		var s: Dictionary = (rides[i] as Dictionary).get("summary", {})
		if str(s.get("ride_id", "")) == ride_id:
			states[i] = state
			reasons[i] = detail if state == "failed" else ""
	_refresh_list()


## Refresh the ride list, also while a ride's actions cover it.
func _refresh_list() -> void:
	if not menus.is_empty():
		refresh_menu(menu_items(), menus[0])


func _back() -> void:
	goto("settings")
