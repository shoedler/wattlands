extends GutTest
## W4 (RS-2; BRIEF 3.8 "keep failed or offline uploads in rides/upload_queue.json for the next
## launch", "a rider with auto-upload on gets it without a prompt"). An upload still running when
## the app quits (AppState.quit saves the open ride, ride_saved starts the auto-upload, and the
## tree quits in the same frame or 0.5 s later) used to be neither on Strava nor in the queue.
## Now the ride is queued before the first request and leaves the queue only when it settles.
## Freeing the WlRides node mid-upload stands in for the process exit (its HTTPRequests die with
## it). Adapted from the W3 proof build/w3/rides-strava/test_quit_during_upload.gd.

const MockRunner := preload("res://tests/rides/mock_strava_runner.gd")
const Util := preload("res://tests/rides/rides_test_util.gd")
const NOW := 1_800_000_000

var _mock: Node = null
var _mock_ok: bool = false
var _dir: String = ""
var _bus: WlEventBus = null


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
	assert_true(_mock_ok, "mock_strava is running")
	_dir = Paths.make_temp_dir("wattlands_quit_upload")
	Paths.set_override(_dir)
	_bus = WlEventBus.new()
	add_child_autofree(_bus)
	await _mock.reset()
	await _mock.set_clock(NOW)


func after_each() -> void:
	Paths.set_override("")
	Util.remove_tree(_dir)


func _rides() -> WlRides:
	var r := WlRides.new()
	r.auto_start = false
	r.events = _bus
	r.auto_upload_override = true
	add_child(r)
	r.client.now_func = func() -> int: return NOW
	r.client.poll_interval_s = 0.02
	r.set_bases(_mock.api_base(), _mock.oauth_base())
	return r


func _saved_ride(r: WlRides) -> Dictionary:
	var rec := r.new_recorder() as RideRecorder
	rec.start("workout", "e2e", NOW, 0.0)
	for i in 31:
		rec.record(float(i), 200.0, 90.0, 32.0)
	rec.stop(30.0)
	# What AppState.quit() does via LocalRider.finish_ride(): save + ride_saved (auto-upload).
	var path := r.save_ride(rec)
	return {"path": path, "ride_id": rec.ride_id}


func _quit(r: WlRides) -> void:
	remove_child(r)
	r.free()
	await get_tree().process_frame


func test_an_upload_interrupted_by_quit_is_retried_at_the_next_launch() -> void:
	var r1 := _rides()
	await r1.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_true(r1.strava_connected())
	var ride := _saved_ride(r1)
	assert_ne(str(ride["path"]), "")
	assert_true(r1.uploads_busy(), "the auto-upload is in flight")
	assert_eq(r1.queue_size(), 1, "queued before the first request")
	var e := r1.queue.get_entry(str(ride["ride_id"]))
	assert_eq(str(e["last_state"]), "uploading")
	assert_eq(int(e["attempts"]), 0, "starting an upload is no failed attempt")
	assert_eq(r1.rides()[0]["state"], "uploading", "the history shows it as uploading")
	await _quit(r1)
	# Next launch.
	var r2 := _rides()
	assert_eq(r2.queue_size(), 1, "the interrupted upload is in upload_queue.json")
	await r2.process_queue()
	var ups: Array = await _mock.uploads()
	assert_eq(ups.size(), 1, "the ride reaches Strava without a prompt")
	assert_eq(r2.queue_size(), 0, "and leaves the queue")
	var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(ride["path"]).get_basename() + ".json"))
	assert_true(str(s["upload"]["state"]) in ["uploaded", "duplicate"], str(s["upload"]))
	await _quit(r2)


## Cut short while Strava processes it: the upload id is already in the queue, so the next
## launch polls it instead of sending the FIT again.
func test_an_upload_cut_short_while_processing_is_polled_not_resent() -> void:
	var r1 := _rides()
	await r1.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	await _mock.config({"processing_polls": 1000})
	var ride := _saved_ride(r1)
	var rid := str(ride["ride_id"])
	var waited := 0
	while int(r1.queue.get_entry(rid).get("upload_id", 0)) <= 0 and waited < 600:
		await get_tree().process_frame
		waited += 1
	var e := r1.queue.get_entry(rid)
	assert_gt(int(e.get("upload_id", 0)), 0, "the upload id is stored as soon as Strava names it")
	assert_eq(str(e["last_state"]), "processing")
	await _quit(r1)
	await _mock.config({"processing_polls": 0})
	var r2 := _rides()
	await r2.process_queue()
	assert_eq(r2.queue_size(), 0)
	assert_eq((await _mock.uploads()).size(), 1, "polled, not uploaded twice")
	await _quit(r2)


func test_a_settled_upload_leaves_no_queue_entry() -> void:
	var r := _rides()
	await r.strava_connect(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	var ride := _saved_ride(r)
	await r.wait_uploads_idle()
	assert_eq(r.queue_size(), 0)
	assert_eq(r.rides()[0]["state"], "uploaded")
	assert_false(FileAccess.file_exists(Paths.upload_queue_path()), "no queue file left: %s" % str(ride))
	await _quit(r)
