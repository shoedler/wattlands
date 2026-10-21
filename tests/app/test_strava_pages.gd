extends "res://tests/app/app_test_base.gd"
## The Strava parts of the app shell against the real Rides service and server/mock_strava
## (BRIEF 3.8 P1, W3 PROF-4 and RS-3):
## - Settings -> Strava: the opt-in FTP and weight import (connect with profile:read_all, pick
##   FTP and/or weight, import): an imported FTP is verified and CP follows it; the profile is
##   saved. Without profile access nothing changes.
## - Settings -> Rides history: picking a ride already on Strava re-uploads it (Strava answers
##   "duplicate"), where Rides.upload() would only report the stored state again.

const MockRunner := preload("res://tests/rides/mock_strava_runner.gd")
const NOW := 1_800_000_000

var _mock: MockRunner = null
var _mock_ok: bool = false


func before_all() -> void:
	_mock = MockRunner.new()
	add_child(_mock)
	_mock_ok = await _mock.start(NOW)


func after_all() -> void:
	if _mock != null:
		_mock.stop()
		remove_child(_mock)
		_mock.free()
		_mock = null


func before_each() -> void:
	super()
	assert_true(_mock_ok, "mock_strava is running (node on PATH)")
	if _mock_ok:
		await _mock.reset()
		await _mock.set_clock(NOW)
		await _mock.config({"processing_polls": 1})


## A real WlRides on the fixture's temp dir and event bus, pointed at the mock.
func _real_rides() -> WlRides:
	var r := WlRides.new()
	r.auto_start = false
	r.events = fx.bus
	r.auto_upload_override = false
	add_child_autofree(r)
	r.client.now_func = func() -> int: return NOW
	r.client.poll_interval_s = 0.02
	r.client.backoff_s = 0.02
	r.set_bases(_mock.api_base(), _mock.oauth_base())
	fx.services.rides = r
	return r


func _settings_on_strava() -> AppSettingsScreen:
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	confirm_pick(s, "strava")
	s.strava_client_id = MockRunner.CLIENT_ID
	s.strava_client_secret = MockRunner.CLIENT_SECRET
	s.refresh_fields()
	return s


func test_import_ftp_and_weight_from_strava() -> void:
	var p := fx.give_profile(200.0)
	p.ftp_verified = false
	p.weight_kg = 80.0
	var r := _real_rides()
	var s := _settings_on_strava()
	assert_true(menu(s).ids().has("import"), "the import is on the Strava page")
	assert_true(menu(s).is_disabled_id("import"), "it needs a connection first")
	assert_false(menu(s).is_disabled_id("connect_profile"))
	await s.strava_connect_profile()
	assert_true(r.strava_connected())
	assert_true(r.client.has_scope("profile:read_all"), "connected with profile access")
	assert_eq(s.strava_client_secret, "", "the secret is not kept on the page")
	assert_true(menu(s).is_disabled_id("connect_profile"), "already has profile access")
	s.edit_field(s.field_by_id("import_weight"))
	assert_true(s.import_weight)
	var saves_before := (fx.settings as Object).get("profile_saves") as int
	var res: Dictionary = await s.strava_import()
	assert_eq(res.get("applied", []), ["ftp", "weight"])
	assert_eq(p.ftp_w, 250.0, "Strava's FTP")
	assert_true(p.ftp_verified, "an imported FTP is verified (BRIEF 3.2)")
	assert_eq(p.cp_w, 250.0, "CP follows FTP")
	assert_eq(p.weight_kg, 72.5)
	assert_gt(
		(fx.settings as Object).get("profile_saves") as int, saves_before, "the profile was saved"
	)
	assert_true(s.status_label.text.contains("250"), s.status_label.text)


## W4r2 R20: leaving the page while GET /athlete runs (main.show_state: leave, remove,
## queue_free) still saves what Rides wrote into the live profile.
func test_leaving_the_page_mid_import_still_saves_it() -> void:
	var p := fx.give_profile(200.0)
	p.ftp_verified = false
	p.weight_kg = 80.0
	_real_rides()
	var s := _settings_on_strava()
	await s.strava_connect_profile()
	s.import_weight = true
	var saves_before := (fx.settings as Object).get("profile_saves") as int
	var changed: Array[int] = [0]
	fx.bus.profile_changed.connect(func() -> void: changed[0] += 1)
	s.strava_import()  # not awaited: the rider leaves the page while the request runs
	s.leave()
	remove_child(s)
	s.queue_free()
	for i in 120:
		await get_tree().process_frame
		if (fx.settings as Object).get("profile_saves") as int > saves_before:
			break
	assert_eq(p.ftp_w, 250.0, "Strava's FTP")
	assert_true(p.ftp_verified)
	assert_eq(p.weight_kg, 72.5)
	assert_gt(
		(fx.settings as Object).get("profile_saves") as int, saves_before, "the import was saved"
	)
	assert_eq(changed[0], 1, "profile_changed once")


func test_import_only_what_was_picked() -> void:
	var p := fx.give_profile(200.0)
	p.weight_kg = 80.0
	_real_rides()
	var s := _settings_on_strava()
	await s.strava_connect_profile()
	s.import_ftp = false
	s.import_weight = true
	var res: Dictionary = await s.strava_import()
	assert_eq(res.get("applied", []), ["weight"])
	assert_eq(p.ftp_w, 200.0, "FTP untouched when not picked")
	assert_eq(p.weight_kg, 72.5)


func test_import_without_profile_access_changes_nothing() -> void:
	var p := fx.give_profile(200.0)
	p.ftp_verified = false
	var r := _real_rides()
	await r.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	var s := _settings_on_strava()
	var res: Dictionary = await s.strava_import()
	assert_eq(res.get("applied", []), [])
	assert_eq(p.ftp_w, 200.0)
	assert_false(p.ftp_verified)
	assert_eq(s.import_result, AppScreen.t("APP_STRAVA_IMPORT_NONE"))


func test_rides_history_reuploads_a_ride_already_on_strava() -> void:
	fx.give_profile()
	var r := _real_rides()
	await r.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	var rec := r.new_recorder() as RideRecorder
	rec.start("workout", "e2e", NOW, 0.0)
	for i in 31:
		rec.record(float(i), 200.0, 90.0, 32.0)
	rec.stop(30.0)
	var path := r.save_ride(rec)
	await r.upload(path, rec.summary())
	assert_true(bool(r.rides()[0]["uploaded"]), "precondition: the ride is on Strava")
	var states: Array[String] = []
	fx.bus.upload_state_changed.connect(
		func(id: String, st: String, _d: String) -> void:
			if id == rec.ride_id:
				states.append(st)
	)
	var uploads_before := int(await _mock_upload_count())
	var s := open_screen(AppRidesScreen.new()) as AppRidesScreen
	assert_true(s.is_on_strava(0))
	s.upload(0)
	await r.wait_uploads_idle()
	assert_true(
		states.has("duplicate"),
		"Strava saw the ride again and calls it a duplicate: %s" % str(states)
	)
	assert_gt(int(await _mock_upload_count()), uploads_before, "a new upload reached Strava")


## How many uploads the mock received (its admin listing).
func _mock_upload_count() -> int:
	var list: Array = await _mock.uploads()
	return list.size()
