class_name AppRidesScreen
extends AppScreen
## Rides history (BRIEF 3.8, P1; Settings -> Rides): every saved ride, newest first, with its
## upload state; picking one uploads (or re-uploads) it to Strava. Pedal-scan selectable.

var rides: Array = []
var states: Dictionary = {}
var status_label: Label = null
var list_box: VBoxContainer = null


func _build() -> void:
	var page := make_page(t("APP_RIDES_TITLE"))
	var left: VBoxContainer = page["left"]
	status_label = AppStyle.paragraph("", AppStyle.FONT_BODY, AppStyle.TEXT)
	status_label.name = "Status"
	left.add_child(status_label)
	list_box = AppStyle.vbox(6)
	left.add_child(list_box)
	if services.bus != null:
		services.bus.upload_state_changed.connect(_on_upload_state)
	reload()
	push_menu(menu_items(), _on_pick, _back)


func _on_leave() -> void:
	if services.bus != null and services.bus.upload_state_changed.is_connected(_on_upload_state):
		services.bus.upload_state_changed.disconnect(_on_upload_state)


func reload() -> void:
	rides = services.rides.rides() if services.rides != null else []
	status_label.text = t("APP_RIDES_NONE") if rides.is_empty() else (t("APP_RIDES_HINT") if strava_connected() else t("APP_RESULTS_STRAVA_OFF"))


func strava_connected() -> bool:
	return services.rides != null and services.rides.strava_connected()


func ride_text(i: int) -> String:
	var r: Dictionary = rides[i]
	var s: Dictionary = r.get("summary", {})
	var when := str(s.get("utc_start", ""))
	var game := str(s.get("game_id", ""))
	var dur := AppStyle.duration_text(float(s.get("duration_s", 0.0)))
	var state := str(states.get(i, ""))
	if state == "":
		state = t("APP_RIDES_UPLOADED") if bool(r.get("uploaded", false)) else ""
	else:
		state = t("APP_UPLOAD_" + state.to_upper()).format([""]).strip_edges()
	return ("%s  %s  %s  %s" % [when, game, dur, state]).strip_edges()


func menu_items() -> Array:
	var items: Array = []
	for i in rides.size():
		items.append({"id": i, "text": ride_text(i), "disabled": not strava_connected()})
	items.append({"id": "back", "text": t("APP_BACK")})
	return items


func _on_pick(_index: int, id: Variant, _auto: bool) -> void:
	if str(id) == "back":
		_back()
		return
	upload(int(id))


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
	services.rides.upload(path, s)
	refresh_menu(menu_items())


func _on_upload_state(ride_id: String, state: String, _detail: String) -> void:
	for i in rides.size():
		var s: Dictionary = (rides[i] as Dictionary).get("summary", {})
		if str(s.get("ride_id", "")) == ride_id:
			states[i] = state
	refresh_menu(menu_items())


func _back() -> void:
	goto("settings")
