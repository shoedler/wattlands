class_name ProgressStore
extends RefCounted
## Per-rider, per-game progression (`ctx.progress`, BRIEF 3.6): catch logs, unlocks, XP.
## Contract, frozen after W0. A local JSON file under
## Paths.user_dir()/games/<game id>/progress.json. It never goes to the host or the relay
## unless the game sends a summary itself.

var game_id: String = ""
var path: String = ""
var data: Dictionary = {}


## Opens (or creates in memory) the store at `p_path`.
static func open(p_game_id: String, p_path: String) -> ProgressStore:
	var s := ProgressStore.new()
	s.game_id = p_game_id
	s.path = p_path
	if p_path != "" and FileAccess.file_exists(p_path):
		var text := FileAccess.get_file_as_string(p_path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			s.data = parsed
		else:
			push_warning("ProgressStore: unreadable %s, starting empty" % p_path)
	return s


func has(key: String) -> bool:
	return data.has(key)


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func set_value(key: String, value: Variant) -> void:
	data[key] = value


## Adds `amount` to a numeric value (missing counts as 0) and returns the new total.
func add(key: String, amount: float) -> float:
	var total := float(data.get(key, 0)) + amount
	data[key] = total
	return total


## Writes the store to disk (creating folders). Returns false on failure.
func save() -> bool:
	if path == "":
		return false
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			push_warning("ProgressStore: cannot create %s" % dir)
			return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("ProgressStore: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true
