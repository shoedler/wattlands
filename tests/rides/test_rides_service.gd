extends GutTest
## WlRides (the Rides autoload's class) against server/mock_strava (BRIEF 3.8): uploads with
## EventBus states, the offline queue and its retry, queued-until-connected, auto-upload on
## ride_saved, the rides history and re-upload, the FTP and weight import (P1), disconnect,
## --strava-base, and the activity name. Each test uses a private WlRides and WlEventBus.

const MockRunner := preload("res://tests/rides/mock_strava_runner.gd")
const Util := preload("res://tests/rides/rides_test_util.gd")
const NOW := 1_800_000_000

var _mock: Node = null
var _mock_ok: bool = false
var _dir: String = ""
var _bus: WlEventBus = null
var _states: Array = []
var _strava: Array = []
var _saved: Array = []


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
	assert_true(_mock_ok, "mock_strava is running (node on PATH)")
	_dir = Paths.make_temp_dir("wattlands_rides_svc")
	Paths.set_override(_dir)
	_states = []
	_strava = []
	_saved = []
	_bus = WlEventBus.new()
	add_child_autofree(_bus)
	_bus.upload_state_changed.connect(func(id: String, s: String, d: String) -> void: _states.append([id, s, d]))
	_bus.strava_state_changed.connect(func(s: String, d: String) -> void: _strava.append([s, d]))
	_bus.ride_saved.connect(func(p: String, _s: Dictionary) -> void: _saved.append(p))
	if _mock_ok:
		await _mock.reset()
		await _mock.set_clock(NOW)
		await _mock.config({"processing_polls": 1})


func after_each() -> void:
	CmdLine.set_args(PackedStringArray(), false)
	Paths.set_override("")
	Util.remove_tree(_dir)


func _rides(pin_bases: bool = true) -> WlRides:
	var r := WlRides.new()
	r.auto_start = false
	r.events = _bus
	r.auto_upload_override = false
	add_child_autofree(r)
	r.client.now_func = func() -> int: return NOW
	r.client.poll_interval_s = 0.02
	r.client.backoff_s = 0.02
	if pin_bases:
		r.set_bases(_mock.api_base(), _mock.oauth_base())
	return r


func _connected() -> WlRides:
	var r := _rides()
	await r.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_true(r.strava_connected())
	return r


func _record(r: WlRides, game: String = "workout", start: int = NOW) -> RideRecorder:
	var rec := r.new_recorder() as RideRecorder
	rec.start(game, "e2e", start, 0.0)
	for i in 31:
		rec.record(float(i), 200.0, 90.0, 32.0)
	rec.stop(30.0)
	return rec


func _states_for(id: String) -> Array:
	var out: Array = []
	for s: Array in _states:
		if s[0] == id:
			out.append(s[1])
	return out


func test_new_recorder_is_a_ride_recorder() -> void:
	var r := _rides()
	var rec := r.new_recorder()
	assert_true(rec is RideRecorder)
	assert_not_null((rec as RideRecorder).utc_offset_s, "local time zone offset set")


func test_upload_reports_states_and_marks_the_ride() -> void:
	var r: WlRides = await _connected()
	assert_eq(_strava, [["connecting", ""], ["connected", ""]])
	var rec := _record(r)
	var path := r.save_ride(rec)
	assert_eq(_saved, [path], "ride_saved emitted")
	await r.upload(path, rec.summary())
	var id := rec.ride_id
	assert_eq(_states_for(id), ["uploading", "processing", "uploaded"])
	var act := int(_states.back()[2])
	assert_gt(act, 0, "detail is the activity id")
	var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
	assert_eq(s["upload"]["state"], "uploaded")
	assert_eq(int(s["upload"]["activity_id"]), act)
	var hist := r.rides()
	assert_eq(hist.size(), 1)
	assert_true(bool(hist[0]["uploaded"]))
	assert_eq(int(hist[0]["activity_id"]), act)
	assert_eq(hist[0]["fit_path"], path)
	await r.upload(path, rec.summary())
	assert_eq((await _mock.uploads()).size(), 1, "an uploaded ride isn't sent again")


func test_offline_upload_is_queued_and_retried() -> void:
	var r: WlRides = await _connected()
	var rec := _record(r)
	var path := r.save_ride(rec)
	r.set_bases("http://127.0.0.1:1/api/v3", _mock.oauth_base())
	r.client.request_timeout_s = 1.5
	await r.upload(path, rec.summary())
	assert_eq(_states_for(rec.ride_id).back(), "offline")
	assert_eq(r.queue_size(), 1)
	var qtext := FileAccess.get_file_as_string(Paths.upload_queue_path())
	assert_string_contains(qtext, rec.ride_id)
	var store: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Paths.strava_path()))
	assert_false(qtext.contains(str(store["access_token"])), "no token in the queue file")
	assert_false(qtext.contains(MockRunner.CLIENT_SECRET))
	assert_eq(r.rides()[0]["state"], "queued")
	# Next launch: a fresh WlRides reads the queue and retries it.
	var r2 := _rides()
	assert_eq(r2.queue_size(), 1, "the queue survives a restart")
	await r2.process_queue()
	assert_eq(_states_for(rec.ride_id).back(), "uploaded")
	assert_eq(r2.queue_size(), 0)
	assert_false(FileAccess.file_exists(Paths.upload_queue_path()))


func test_not_connected_queues_until_connect() -> void:
	var r := _rides()
	var rec := _record(r)
	var path := r.save_ride(rec)
	await r.upload(path, rec.summary())
	assert_eq(_states_for(rec.ride_id), ["queued"])
	assert_eq(r.queue_size(), 1)
	await r.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_eq(_states_for(rec.ride_id).back(), "uploaded", "connect retries the queue")
	assert_eq(r.queue_size(), 0)


func test_auto_upload_on_ride_saved() -> void:
	var r: WlRides = await _connected()
	r.auto_upload_override = true
	var rec := _record(r)
	r.save_ride(rec)
	await wait_until(func() -> bool: return _states_for(rec.ride_id).has("uploaded"), 10.0)
	assert_eq(_states_for(rec.ride_id).back(), "uploaded")
	assert_eq((await _mock.uploads()).size(), 1, "exactly one upload")


func test_no_auto_upload_when_off() -> void:
	var r: WlRides = await _connected()
	assert_false(r.auto_upload_enabled())
	var rec := _record(r)
	r.save_ride(rec)
	await wait_process_frames(5)
	assert_eq(_states_for(rec.ride_id), [])
	assert_eq((await _mock.uploads()).size(), 0)


func test_auto_upload_flag_from_the_command_line() -> void:
	var r := _rides()
	r.auto_upload_override = null
	CmdLine.set_args(PackedStringArray(["--strava-auto-upload"]))
	assert_true(r.auto_upload_enabled())
	CmdLine.set_args(PackedStringArray([]))
	assert_false(r.auto_upload_enabled(), "off by default")


func test_a_permanent_failure_leaves_the_queue() -> void:
	var r: WlRides = await _connected()
	var rec := _record(r)
	var path := r.save_ride(rec)
	var bytes := FileAccess.get_file_as_bytes(path)
	bytes[20] ^= 0xFF
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	await r.upload(path, rec.summary())
	assert_eq(_states_for(rec.ride_id).back(), "failed")
	assert_eq(r.queue_size(), 0, "retrying can't fix a corrupt file")
	var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".json"))
	assert_eq(s["upload"]["state"], "failed")


func test_a_transient_failure_stays_queued_with_attempts() -> void:
	var r: WlRides = await _connected()
	await _mock.fault("upload", 500, 2)
	var rec := _record(r)
	var path := r.save_ride(rec)
	await r.upload(path, rec.summary())
	assert_eq(_states_for(rec.ride_id).back(), "failed")
	assert_eq(r.queue_size(), 1)
	await r.process_queue()
	assert_eq(int(r.queue.get_entry(rec.ride_id)["attempts"]), 2)
	await r.process_queue()
	assert_eq(_states_for(rec.ride_id).back(), "uploaded")
	assert_eq(r.queue_size(), 0)


func test_a_queued_processing_upload_is_polled_not_resent() -> void:
	var r: WlRides = await _connected()
	r.client.poll_timeout_s = 0.1
	await _mock.config({"processing_polls": 1000})
	var rec := _record(r)
	var path := r.save_ride(rec)
	await r.upload(path, rec.summary())
	assert_eq(r.queue_size(), 1)
	assert_gt(int(r.queue.get_entry(rec.ride_id)["upload_id"]), 0)
	await _mock.config({"processing_polls": 0})
	await r.process_queue()
	assert_eq(_states_for(rec.ride_id).back(), "uploaded")
	assert_eq((await _mock.uploads()).size(), 1, "polled, not uploaded twice")


func test_history_newest_first_and_reupload() -> void:
	var r: WlRides = await _connected()
	var old := _record(r, "workout", NOW - 86400)
	var old_path := r.save_ride(old)
	var newer := _record(r, "siege", NOW)
	r.save_ride(newer)
	var hist := r.rides()
	assert_eq(hist.size(), 2)
	assert_eq((hist[0]["summary"] as Dictionary)["game_id"], "siege", "newest first")
	assert_false(bool(hist[1]["uploaded"]))
	await r.upload(old_path, old.summary())
	await r.reupload(old.ride_id)
	assert_eq(_states_for(old.ride_id).back(), "duplicate", "Strava already has it")
	assert_true(bool(r.rides()[1]["uploaded"]), "a duplicate counts as uploaded")
	await r.reupload("no-such-ride")
	assert_push_warning("no saved ride")


func test_disconnect() -> void:
	var r: WlRides = await _connected()
	await r.strava_disconnect()
	assert_false(r.strava_connected())
	assert_eq(r.strava_state(), "disconnected")
	assert_eq(_strava.back(), ["disconnected", ""])
	var store: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Paths.strava_path()))
	assert_false(store.has("client_secret") or store.has("refresh_token"))
	assert_true(r.strava_info().has("client_id"))
	assert_false(r.strava_info().has("client_secret"))


func test_connection_survives_a_restart() -> void:
	var r: WlRides = await _connected()
	assert_true(r.strava_connected())
	var r2 := _rides()
	assert_true(r2.strava_connected(), "tokens reloaded from strava.json")
	assert_eq(r2.strava_state(), "connected")


func test_import_ftp_and_weight() -> void:
	var r := _rides()
	await r.strava_connect_with_profile(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_true(r.client.has_scope("profile:read_all"))
	var p := RiderProfile.new()
	var res: Dictionary = await r.strava_import_athlete(p, true, true)
	assert_eq(res["applied"], ["ftp", "weight"])
	assert_eq(p.ftp_w, 250.0)
	assert_eq(p.cp_w, 250.0)
	assert_true(p.ftp_verified, "an imported FTP counts as verified")
	assert_eq(p.weight_kg, 72.5)
	var q := RiderProfile.new()
	var only: Dictionary = await r.strava_import_athlete(q, false, true)
	assert_eq(only["applied"], ["weight"])
	assert_eq(q.ftp_w, 200.0, "FTP untouched when not chosen")


func test_import_without_the_profile_scope_applies_nothing() -> void:
	var r: WlRides = await _connected()
	var p := RiderProfile.new()
	var res: Dictionary = await r.strava_import_athlete(p, true, true)
	assert_eq(res["applied"], [])
	assert_eq(p.ftp_w, 200.0)


func test_strava_base_points_both_bases_at_the_mock() -> void:
	CmdLine.set_args(PackedStringArray(["--strava-base=" + _mock.base()]))
	var r := _rides(false)
	r.reload()
	assert_eq(r.client.api_base, _mock.base() + "/api/v3")
	assert_eq(r.client.oauth_base, _mock.base() + "/oauth")
	await r.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_true(r.strava_connected(), "connects to the mock through --strava-base")
	assert_eq(StravaClient.bases_from_root("http://127.0.0.1:9/"), {"api": "http://127.0.0.1:9/api/v3", "oauth": "http://127.0.0.1:9/oauth"})


func test_startup_connects_from_the_command_line() -> void:
	CmdLine.set_args(PackedStringArray(["--strava-base=" + _mock.base(), "--strava-client-id=" + MockRunner.CLIENT_ID,
		"--strava-client-secret=" + MockRunner.CLIENT_SECRET]))
	var r := WlRides.new()
	r.events = _bus
	add_child_autofree(r)
	r.client.now_func = func() -> int: return NOW
	await wait_until(func() -> bool: return r.strava_connected(), 10.0)
	assert_true(r.strava_connected(), "scripted peers connect at start")


func test_activity_name_and_description() -> void:
	assert_eq(WlRides.activity_name({"game_id": "workout"}), "Wattlands: Workout")
	assert_eq(WlRides.activity_name({"game_id": "siege", "game_title": "Generator Siege"}), "Wattlands: Generator Siege")
	var d := WlRides.activity_description({"content_id": "easy30", "kj": 360.4, "avg_power_w": 199.6})
	assert_string_contains(d, "easy30")
	assert_string_contains(d, "360 kJ")
	assert_string_contains(d, "200 W")
