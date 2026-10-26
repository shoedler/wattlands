class_name HelpSeen
extends RefCounted
## Which games' help overlays (HudSpec.help) a profile has seen (v0.3.0): the GameHost opens a
## game's help once, the first time the rider starts a session of that game. Stored in
## Paths.help_seen_path() as {"games": [game ids]} (per profile: per Paths.user_dir()).
## Owned by platform.


## True when the help of `game_id` was shown to this profile before.
static func has(game_id: String, path: String = "") -> bool:
	return _read(_path(path)).has(game_id)


## Remember that this profile saw the help of `game_id`. Returns false when it can't be saved.
static func mark(game_id: String, path: String = "") -> bool:
	if game_id.is_empty():
		return false
	var p := _path(path)
	var games := _read(p)
	if games.has(game_id):
		return true
	games.append(game_id)
	games.sort()
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_warning("HelpSeen: could not write %s" % p)
		return false
	f.store_string(JSON.stringify({"games": games}, "\t"))
	f.close()
	return true


static func _path(path: String) -> String:
	return path if not path.is_empty() else Paths.help_seen_path()


static func _read(path: String) -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(path):
		return out
	var json := JSON.new()
	var d: Variant = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		d = json.data
	if not (d is Dictionary) or not ((d as Dictionary).get("games") is Array):
		push_warning('HelpSeen: %s is not {"games": [...]}; starting fresh' % path)
		return out
	for g: Variant in (d as Dictionary)["games"]:
		if g is String:
			out.append(g as String)
	return out
