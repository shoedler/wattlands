class_name AppProfileScreen
extends AppFormScreen
## The rider profile (BRIEF 3.2), saved to profile.json through Settings on every change: name,
## menu color, units, weight (shared with the host only if opted in), the W/kg opt-in
## (RiderProfile.show_wkg: W/kg on the HUD and results, BRIEF 3.3; off by default and apart from
## sharing the weight), FTP (typing it marks it verified; CP follows FTP), W', preferred cadence,
## drivetrain, trainer difficulty, the SIM grade range, skip warm-up, Autopilot default.
## Haptics, Strava and pedal UI live in Settings.

const COLORS: Array[String] = ["#D55E00", "#0072B2", "#F0E442", "#009E73", "#CC79A7", "#56B4E9", "#E69F00", "#FFFFFF"]

var ftp_label: Label = null


func _build() -> void:
	make_form_page(t("APP_PROFILE_TITLE"))
	ftp_label = AppStyle.label("", AppStyle.FONT_NUMBER, AppStyle.TEXT)
	ftp_label.name = "FtpLine"
	content_box.add_child(ftp_label)
	content_box.add_child(AppStyle.paragraph(t("APP_PROFILE_HINT"), AppStyle.FONT_BODY))
	open_fields(profile_fields(), _back)
	_refresh_ftp()


func _back() -> void:
	goto("title")


func p() -> RiderProfile:
	return services.profile()


func save() -> void:
	if services.settings != null:
		services.settings.save_profile()
	if services.bus != null:
		services.bus.profile_changed.emit()
	_refresh_ftp()


func _refresh_ftp() -> void:
	if ftp_label != null:
		var v := t("APP_VERIFIED") if p().ftp_verified else t("APP_UNVERIFIED")
		ftp_label.text = "FTP %d W  %s" % [int(round(p().ftp_w)), v]


## The profile's FTP was typed in: verified, CP = FTP (BRIEF 3.2).
func set_ftp(w: float) -> void:
	p().ftp_w = w
	p().cp_w = w
	p().ftp_verified = true
	save()


func set_name_value(v: Variant) -> void:
	var n := str(v).strip_edges()
	if n != "":
		p().display_name = n
		save()


func set_color_value(v: Variant) -> void:
	p().color = Color.from_string(str(v), p().color)
	save()


func color_value() -> Variant:
	return "#" + p().color.to_html(false).to_upper()


## Set a profile property (typed like its current value) and save.
func set_prop(prop: String, v: Variant) -> void:
	var cur: Variant = p().get(prop)
	if cur is float:
		p().set(prop, float(v))
	elif cur is bool:
		p().set(prop, bool(v))
	elif cur is int:
		p().set(prop, int(v))
	else:
		p().set(prop, str(v))
	save()


func get_prop(prop: String) -> Variant:
	return p().get(prop)


func num_field(id: String, label_key: String, prop: String, lo: float, hi: float, step: float, unit: String) -> Dictionary:
	return {"id": id, "label": t(label_key), "type": "stepper", "min": lo, "max": hi, "step": step, "unit": unit,
		"get": get_prop.bind(prop), "set": _setter(prop)}


func toggle_field(id: String, label_key: String, prop: String) -> Dictionary:
	return {"id": id, "label": t(label_key), "type": "toggle", "get": get_prop.bind(prop), "set": _setter(prop)}


func choice_field(id: String, label_key: String, prop: String, choices: Array) -> Dictionary:
	return {"id": id, "label": t(label_key), "type": "choice", "choices": choices, "get": get_prop.bind(prop), "set": _setter(prop)}


## Callable(value) that sets `prop`.
func _setter(prop: String) -> Callable:
	return func(v: Variant) -> void: set_prop(prop, v)


func profile_fields() -> Array:
	var color_choices: Array = []
	for i in COLORS.size():
		color_choices.append([COLORS[i], t("APP_COLOR_%d" % i)])
	var ftp := num_field("ftp", "APP_FIELD_FTP", "ftp_w", 50.0, 600.0, 5.0, "W")
	ftp["set"] = func(v: Variant) -> void: set_ftp(float(v))
	var fields: Array = [
		{"id": "name", "label": t("APP_FIELD_NAME"), "type": "text", "rows": AppTextField.ROWS_NAME, "max_length": 16,
			"get": get_prop.bind("display_name"), "set": set_name_value},
		{"id": "color", "label": t("APP_FIELD_COLOR"), "type": "choice", "choices": color_choices,
			"get": color_value, "set": set_color_value},
		choice_field("units", "APP_FIELD_UNITS", "units", [["metric", t("APP_UNITS_METRIC")], ["imperial", t("APP_UNITS_IMPERIAL")]]),
		ftp,
		num_field("weight", "APP_FIELD_WEIGHT", "weight_kg", 30.0, 200.0, 1.0, "kg"),
		toggle_field("share_weight", "APP_FIELD_SHARE_WEIGHT", "share_weight"),
		toggle_field("show_wkg", "APP_FIELD_SHOW_WKG", "show_wkg"),
		num_field("wprime", "APP_FIELD_WPRIME", "wprime_j", 5000.0, 40000.0, 1000.0, "J"),
		num_field("cadence", "APP_FIELD_CADENCE", "preferred_cadence_rpm", 50.0, 120.0, 5.0, "rpm"),
		choice_field("drivetrain", "APP_FIELD_DRIVETRAIN", "drivetrain", [["cassette", t("APP_DRIVETRAIN_CASSETTE")], ["single_speed", t("APP_DRIVETRAIN_SINGLE")]]),
		num_field("difficulty", "APP_FIELD_DIFFICULTY", "difficulty_pct", 0.0, 100.0, 10.0, "%"),
		num_field("grade_min", "APP_FIELD_GRADE_MIN", "grade_min_pct", -10.0, 0.0, 1.0, "%"),
		num_field("grade_max", "APP_FIELD_GRADE_MAX", "grade_max_pct", 0.0, 16.0, 1.0, "%"),
		toggle_field("skip_warmup", "APP_FIELD_SKIP_WARMUP", "skip_warmup"),
		toggle_field("autopilot", "APP_FIELD_AUTOPILOT", "autopilot_default"),
		{"id": "back", "label": t("APP_BACK"), "type": "action", "run": _back},
	]
	return fields
