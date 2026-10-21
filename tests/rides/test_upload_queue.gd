extends GutTest
## UploadQueue (BRIEF 3.8): rides/upload_queue.json persists failed and offline uploads.

const Util := preload("res://tests/rides/rides_test_util.gd")

var _dir: String = ""


func before_each() -> void:
	_dir = Paths.make_temp_dir("wattlands_queue")
	Paths.set_override(_dir)


func after_each() -> void:
	Paths.set_override("")
	Util.remove_tree(_dir)


func test_default_path_is_under_rides() -> void:
	var q := UploadQueue.new()
	assert_eq(q.file_path(), Paths.upload_queue_path())
	assert_true(q.file_path().ends_with("rides/upload_queue.json"))


func test_put_get_remove_and_persist() -> void:
	var q := UploadQueue.new()
	q.load_file()
	assert_eq(q.size(), 0)
	q.put({"ride_id": "a", "fit_path": "/x/a.fit", "name": "A", "attempts": 1, "last_state": "offline"})
	q.put({"ride_id": "b", "fit_path": "/x/b.fit", "upload_id": 77})
	q.put({"ride_id": "a", "fit_path": "/x/a.fit", "attempts": 2, "last_state": "failed", "last_error": "server_error_500"})
	assert_eq(q.size(), 2, "put replaces by ride_id")
	assert_true(FileAccess.file_exists(Paths.upload_queue_path()))
	var q2 := UploadQueue.new()
	q2.load_file()
	assert_eq(q2.ride_ids(), ["a", "b"] as Array[String])
	assert_eq(int(q2.get_entry("a")["attempts"]), 2)
	assert_eq(q2.get_entry("a")["last_error"], "server_error_500")
	assert_eq(int(q2.get_entry("b")["upload_id"]), 77)
	q2.remove("a")
	q2.remove("missing")
	var q3 := UploadQueue.new()
	q3.load_file()
	assert_eq(q3.ride_ids(), ["b"] as Array[String])
	q3.remove("b")
	assert_false(FileAccess.file_exists(Paths.upload_queue_path()), "an empty queue leaves no file")


func test_entries_hold_only_known_keys() -> void:
	var q := UploadQueue.new()
	q.put({"ride_id": "a", "fit_path": "/x/a.fit", "access_token": "SECRET", "client_secret": "S"})
	var text := FileAccess.get_file_as_string(Paths.upload_queue_path())
	assert_false(text.contains("SECRET"), "unknown keys (tokens) never reach the queue file")
	assert_false(text.contains("client_secret"))
	q.remove("a")


func test_unreadable_file_is_set_aside() -> void:
	var p := Paths.upload_queue_path()
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var q := UploadQueue.new()
	q.load_file()
	assert_push_warning("unreadable")
	assert_eq(q.size(), 0)
	assert_true(FileAccess.file_exists(p + ".bad"))
	assert_false(FileAccess.file_exists(p), "moved aside, not left to warn on every launch")
	# A second bad file replaces the first one set aside.
	var f2 := FileAccess.open(p, FileAccess.WRITE)
	f2.store_string("[also bad")
	f2.close()
	q.load_file()
	assert_push_warning("unreadable")
	assert_false(FileAccess.file_exists(p), "set aside again although a .bad already existed")
	assert_eq(FileAccess.get_file_as_string(p + ".bad"), "[also bad")
	DirAccess.remove_absolute(p + ".bad")
