extends "res://tests/app/app_test_base.gd"
## Profile flows (W3 PROF-1, PROF-3, PROF-6):
## - BRIEF 3.5: at launch a rider already pedaling gets the 5 s zero-touch start, although the
##   real App builds the title twice (main, then App's deferred boot).
## - BRIEF 3.2, 4.6.6: choices made in Settings before the profile existed (haptics opt-out,
##   auto-upload, pedal UI) survive both first-run paths.
## - BRIEF 3.2 units: imperial shows and edits the weight in lb (stored in kg).


## The real launch order: main._ready shows the title, then the App's deferred boot() calls
## goto("title") again (App._ready -> boot.call_deferred()).
func test_launch_with_real_app_boot_counts_a_running_stretch() -> void:
	fx.give_profile()
	fx.settings.set_value("last_game", "workout")
	var app := WlApp.new()
	app.settings = fx.settings
	app.trainer_service = fx.trainer
	app.rides = fx.rides
	app.bus = fx.bus
	fx.services.app = app
	add_child(app)
	_opened.append(app)
	var m := open_main()
	app.boot()
	var title := current_screen(m) as AppTitleScreen
	assert_not_null(title)
	assert_eq(fx.services.title_visits, 1, "one title visit at launch")
	assert_false(title.zero.need_fresh, "launch: a rider already pedaling gets the ride")
	for t in 7:
		title.feed_sample(sample(float(t), 150.0, 85.0))
	assert_eq(app.state, "session", "6 s of pedaling from launch starts the last-played game")


## Back on the title from another screen is a new visit (a fresh start is needed).
func test_title_after_a_menu_is_a_new_visit() -> void:
	fx.give_profile()
	fx.settings.set_value("last_game", "workout")
	var m := open_main()
	fx.services.goto("title")
	assert_eq(fx.services.title_visits, 1)
	fx.services.goto("settings")
	fx.services.goto("title")
	assert_eq(fx.services.title_visits, 2)
	assert_true((current_screen(m) as AppTitleScreen).zero.need_fresh, "after a menu: stop first, then 5 s")


func _opt_out_in_settings() -> void:
	var st := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	(st.haptics_fields()[0]["set"] as Callable).call(false)
	(st.haptics_fields()[1]["set"] as Callable).call(30.0)
	for f: Dictionary in st.strava_fields():
		if str(f.get("id", "")) == "auto_upload":
			(f["set"] as Callable).call(true)
	(st.pedal_fields()[1]["set"] as Callable).call(2.4)


func test_haptics_opt_out_made_before_the_first_run_survives_the_20_s_rule() -> void:
	assert_false(fx.settings.has_profile())
	var title0 := open_screen(AppTitleScreen.new()) as AppTitleScreen
	assert_true(menu(title0).ids().has("settings"), "Settings is offered before a profile exists")
	_opt_out_in_settings()
	assert_false(fx.settings.profile.haptics_on, "opted out in Settings")
	var title := open_screen(AppTitleScreen.new()) as AppTitleScreen
	for t in 21:
		title.feed_sample(sample(float(t), 140.0, 82.0))
	assert_eq(fx.app.state, "session")
	var p := fx.settings.profile
	assert_true(p.created)
	assert_eq(p.display_name, "Rider")
	assert_eq(p.ftp_w, 200.0)
	assert_false(p.ftp_verified, "FTP 200, unverified (BRIEF 3.5)")
	assert_false(p.haptics_on, "the haptics opt-out survives the first-run profile")
	assert_eq(p.haptic_intensity_pct, 30.0)
	assert_true(p.strava_auto_upload, "auto-upload choice survives too")
	assert_eq(p.scan_interval_s, 2.4, "and the pedal UI")


func test_haptics_opt_out_survives_the_first_run_form() -> void:
	_opt_out_in_settings()
	var fr := open_screen(AppFirstRunScreen.new()) as AppFirstRunScreen
	fr.finish()
	var p := fx.settings.profile
	assert_true(p.created)
	assert_false(p.haptics_on, "the first-run form keeps the haptics opt-out")
	assert_true(p.strava_auto_upload)
	assert_eq(p.ftp_w, 200.0)
	assert_false(p.ftp_verified)


func test_an_ftp_test_before_the_profile_keeps_its_ftp() -> void:
	var pre := fx.settings.profile
	pre.ftp_w = 236.0
	pre.cp_w = 236.0
	pre.ftp_verified = true
	var p := AppTitleScreen.create_first_run_profile(fx.services)
	assert_eq(p.ftp_w, 236.0, "a verified FTP is never replaced by the 200 W default")
	assert_true(p.ftp_verified)
	assert_eq(p.display_name, "Rider")


func test_first_run_copy_never_shares_the_object() -> void:
	var cur := RiderProfile.new()
	cur.haptics_on = false
	var copy := AppFirstRunScreen.first_run_copy(cur)
	assert_ne(copy, cur)
	assert_false(copy.haptics_on)
	assert_false(copy.created)


# --- units -------------------------------------------------------------------------------------

func _weight_field(ps: AppProfileScreen) -> Dictionary:
	for f: Dictionary in ps.profile_fields():
		if str(f.get("id", "")) == "weight":
			return f
	return {}


func test_imperial_units_change_the_weight_field() -> void:
	var p := fx.give_profile()
	p.units = "imperial"
	p.weight_kg = 70.0
	var ps := open_screen(AppProfileScreen.new()) as AppProfileScreen
	var weight := _weight_field(ps)
	assert_eq(str(weight.get("unit", "")), "lb", "imperial units edit the weight in lb")
	assert_eq(float(ps.field_value(weight)), 154.0, "70 kg = 154 lb")
	assert_true(menu(ps).text_of("weight").contains("154 lb"), menu(ps).text_of("weight"))
	ps.set_field(weight, 165.0)
	assert_almost_eq(p.weight_kg, 165.0 / AppStyle.LB_PER_KG, 0.001, "stored in kg")
	assert_eq(float(ps.field_value(weight)), 165.0, "and shown back in lb")


func test_switching_units_rebuilds_the_weight_field() -> void:
	var p := fx.give_profile()
	p.weight_kg = 70.0
	var ps := open_screen(AppProfileScreen.new()) as AppProfileScreen
	assert_true(menu(ps).text_of("weight").contains("70 kg"))
	ps.set_units("imperial")
	assert_eq(p.units, "imperial")
	assert_true(menu(ps).text_of("weight").contains("154 lb"), menu(ps).text_of("weight"))
	ps.set_units("metric")
	assert_true(menu(ps).text_of("weight").contains("70 kg"))


func test_weight_text_rule() -> void:
	assert_eq(AppStyle.weight_text(70.0, "metric"), "70 kg")
	assert_eq(AppStyle.weight_text(70.0, "imperial"), "154 lb")
	var f := AppFormScreen.weight_field("w", "W", "imperial", func() -> float: return 200.0, func(_kg: float) -> void: pass)
	assert_lte(float(f["max"]) / AppStyle.LB_PER_KG, AppStyle.WEIGHT_MAX_KG, "the lb range stays inside the kg range")
	assert_gte(float(f["min"]) / AppStyle.LB_PER_KG, AppStyle.WEIGHT_MIN_KG)
