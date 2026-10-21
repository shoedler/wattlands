class_name AppFirstRunScreen
extends AppFormScreen
## First run (BRIEF 3.2, 3.5): create the local rider profile (no accounts). A name, the FTP
## (typing it marks it verified; otherwise 200 W, unverified, scaled by 0.85 for ERG targets)
## and the weight. "Start riding" saves profile.json and returns to the title, whose menus then
## run on pedal-scan. A rider who never touches anything gets the same profile from the title
## screen's 20 s zero-touch rule instead.

var draft: RiderProfile = null
var ftp_touched: bool = false


func _build() -> void:
	draft = RiderProfile.new()
	make_form_page(t("APP_FIRST_RUN_TITLE"))
	content_box.add_child(AppStyle.paragraph(t("APP_FIRST_RUN_INTRO"), AppStyle.FONT_BODY, AppStyle.TEXT))
	open_fields(fields(), _back)


func scanning_enabled() -> bool:
	return true


func fields() -> Array:
	return [
		{"id": "name", "label": t("APP_FIELD_NAME"), "type": "text", "rows": AppTextField.ROWS_NAME, "max_length": 16,
			"get": func() -> Variant: return draft.display_name, "set": set_name_value},
		{"id": "ftp", "label": t("APP_FIELD_FTP"), "type": "stepper", "min": 50.0, "max": 600.0, "step": 5.0, "unit": "W",
			"get": func() -> Variant: return draft.ftp_w, "set": set_ftp,
			"value_text": ftp_text},
		{"id": "weight", "label": t("APP_FIELD_WEIGHT"), "type": "stepper", "min": 30.0, "max": 200.0, "step": 1.0, "unit": "kg",
			"get": func() -> Variant: return draft.weight_kg, "set": func(v: Variant) -> void: draft.weight_kg = float(v)},
		{"id": "done", "label": t("APP_FIRST_RUN_DONE"), "type": "action", "run": finish},
		{"id": "back", "label": t("APP_BACK"), "type": "action", "run": _back},
	]


func set_name_value(v: Variant) -> void:
	var n := str(v).strip_edges()
	if n != "":
		draft.display_name = n


func set_ftp(v: Variant) -> void:
	draft.ftp_w = float(v)
	draft.cp_w = draft.ftp_w
	draft.ftp_verified = true
	ftp_touched = true


func ftp_text(v: Variant) -> String:
	var s := "%d W" % int(round(float(v)))
	return s if ftp_touched else s + " " + t("APP_UNVERIFIED")


## Save the profile and return to the title.
func finish() -> void:
	draft.created = true
	if services.settings != null:
		services.settings.profile = draft
		services.settings.save_profile()
	if services.bus != null:
		services.bus.profile_changed.emit()
	goto("title")


func _back() -> void:
	goto("title")
