class_name UploadQueue
extends RefCounted
## Failed and offline Strava uploads, kept in rides/upload_queue.json (BRIEF 3.8) and retried
## by WlRides.process_queue() at launch and after connecting. Holds no tokens or secrets:
## only ride ids, file paths, the activity name and description, and retry bookkeeping.
##
## Entry: {ride_id, fit_path, name, description, attempts, last_state, last_error,
##         upload_id (0 = not created on Strava yet; else poll it instead of re-uploading)}

const VERSION := 1
## An entry is dropped (and its ride marked "failed") after this many failed attempts. Only
## real failures count (counts_as_attempt()): an offline attempt (no connectivity) or one
## while not connected never does, so an offline upload stays queued for every next launch
## (BRIEF 3.8).
const MAX_ATTEMPTS := 8
## Upload states that never count toward MAX_ATTEMPTS: "queued" (not connected to Strava
## yet) and "offline" (the network or Strava can't be reached).
const UNCOUNTED_STATES: Array[String] = ["queued", "offline"]

## The queue file ("" = Paths.upload_queue_path(), resolved on each load and save).
var path: String = ""
var items: Array[Dictionary] = []


func file_path() -> String:
	return path if path != "" else Paths.upload_queue_path()


## Reads the queue file; a missing file is an empty queue, an unreadable one is kept aside
## as upload_queue.json.bad and the queue starts empty.
func load_file() -> void:
	items.clear()
	var p := file_path()
	if not FileAccess.file_exists(p):
		return
	var parsed: Variant = StravaClient.parse_json(FileAccess.get_file_as_string(p))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("items", null) is Array):
		push_warning("UploadQueue: unreadable %s; starting empty" % p)
		if FileAccess.file_exists(p + ".bad"):
			DirAccess.remove_absolute(p + ".bad")
		DirAccess.rename_absolute(p, p + ".bad")
		return
	for it: Variant in (parsed as Dictionary)["items"]:
		if it is Dictionary and str((it as Dictionary).get("ride_id", "")) != "":
			items.append(_normalized(it))


func save_file() -> bool:
	var p := file_path()
	var dir := p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if items.is_empty():
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		return true
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("UploadQueue: can't write %s" % tmp)
		return false
	f.store_string(JSON.stringify({"version": VERSION, "items": items}, "  "))
	f.close()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	return DirAccess.rename_absolute(tmp, p) == OK


func size() -> int:
	return items.size()


func has(ride_id: String) -> bool:
	return index_of(ride_id) >= 0


func index_of(ride_id: String) -> int:
	for i in items.size():
		if str(items[i].get("ride_id", "")) == ride_id:
			return i
	return -1


func get_entry(ride_id: String) -> Dictionary:
	var i := index_of(ride_id)
	return items[i].duplicate(true) if i >= 0 else {}


## Adds or replaces the entry for entry.ride_id and saves.
func put(entry: Dictionary) -> void:
	var e := _normalized(entry)
	var i := index_of(str(e["ride_id"]))
	if i >= 0:
		items[i] = e
	else:
		items.append(e)
	save_file()


func remove(ride_id: String) -> void:
	var i := index_of(ride_id)
	if i >= 0:
		items.remove_at(i)
		save_file()


## True when an upload attempt that ended in `state` counts toward MAX_ATTEMPTS: a real
## failure ("failed": an error response, a processing error or timeout), not "queued" or
## "offline".
static func counts_as_attempt(state: String) -> bool:
	return not UNCOUNTED_STATES.has(state)


func ride_ids() -> Array[String]:
	var out: Array[String] = []
	for it in items:
		out.append(str(it["ride_id"]))
	return out


static func _normalized(d: Dictionary) -> Dictionary:
	return {
		"ride_id": str(d.get("ride_id", "")),
		"fit_path": str(d.get("fit_path", "")),
		"name": str(d.get("name", "")),
		"description": str(d.get("description", "")),
		"attempts": int(d.get("attempts", 0)),
		"last_state": str(d.get("last_state", "queued")),
		"last_error": str(d.get("last_error", "")),
		"upload_id": int(d.get("upload_id", 0)),
	}
