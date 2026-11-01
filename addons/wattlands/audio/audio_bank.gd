class_name AudioBank
extends RefCounted
## One game's audio.json (SPEC_AUDIO 1.5): recipes and runtime data, so the offline preview and the game read the same
## numbers. Validated at load; every error names its key path. Only `schema`, `game` and `sounds` are required.
const SCHEMA := 1
const RATES: Array[int] = [11025, 22050]
const BUS_MASTER_REFUSED := "Master is for the platform's safety prompts"
const DEFAULT_MIX := {
	"other_db": -10.0,
	"other_doubling_db": -3.0,
	"other_min_gap_s": 0.06,
	"machine_voices": 16,
	"sfx_voices": 16,
	"spot_voices": 6,
	"crowd_voices": 0,
	"max_loop_players": 24,
}
var dir: String = ""
var game_id: String = ""
var mix: Dictionary = {}
var sounds: Dictionary = {}
var machines: Dictionary = {}
var loops: Dictionary = {}
var beds: Dictionary = {}
var cues: Dictionary = {}

var _streams: Dictionary = {}
var _warned: Dictionary = {}


## Null plus push_error naming the key path on any error.
static func load_bank(path: String) -> AudioBank:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("AudioBank: cannot open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		var where := "%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()]
		push_error("AudioBank: " + where)
		return null
	if not json.data is Dictionary:
		push_error("AudioBank: %s is not a JSON object" % path)
		return null
	var repeated := duplicate_keys(text)
	if not repeated.is_empty():
		push_error("AudioBank: %s: duplicate id: %s" % [path, ", ".join(repeated)])
		return null
	return from_dict(json.data, path.get_base_dir())


## The same validation, no file read.
static func from_dict(doc: Dictionary, p_dir: String) -> AudioBank:
	var errors := validate(doc)
	if not errors.is_empty():
		push_error("AudioBank: %s: %s" % [p_dir, "; ".join(errors)])
		return null
	var bank := AudioBank.new()
	bank.dir = p_dir
	bank.game_id = str(doc["game"])
	bank.mix = DEFAULT_MIX.duplicate()
	bank.mix.merge(doc.get("mix", {}), true)
	bank.sounds = doc["sounds"]
	bank.machines = doc.get("machines", {})
	bank.loops = doc.get("loops", {})
	bank.beds = doc.get("beds", {})
	bank.cues = doc.get("cues", {})
	return bank


## Every problem with `doc`, each naming its key path; [] when it is good.
static func validate(doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var schema: Variant = doc.get("schema")
	if not (schema is float or schema is int) or int(schema) != SCHEMA:
		errors.append("schema: unknown schema %s" % str(schema))
	if not doc.get("game") is String or str(doc.get("game")).is_empty():
		errors.append("game: needs a name")
	if not doc.get("sounds") is Dictionary:
		errors.append("sounds: needs an object")
		return errors
	for block: String in ["mix", "machines", "loops", "beds", "cues"]:
		if doc.has(block) and not doc[block] is Dictionary:
			errors.append("%s: needs an object" % block)
			return errors
	var all: Dictionary = doc["sounds"]
	_check_sounds(all, errors)
	_check_numbers("mix", doc.get("mix", {}), DEFAULT_MIX.keys(), errors)
	var machine_docs: Dictionary = doc.get("machines", {})
	for id: String in machine_docs:
		var path := "machines.%s" % id
		if _is_object(path, machine_docs[id], errors):
			_check_machine(path, machine_docs[id], all, errors)
	var loop_docs: Dictionary = doc.get("loops", {})
	for id: String in loop_docs:
		var path := "loops.%s" % id
		if not _is_object(path, loop_docs[id], errors):
			continue
		var entry: Dictionary = loop_docs[id]
		_check_bus(path + ".bus", entry.get("bus", AudioBuses.SFX), errors)
		_check_layers(path + ".layers", _list_at(entry, "layers", path, errors), all, errors)
	var bed_docs: Dictionary = doc.get("beds", {})
	for id: String in bed_docs:
		var path := "beds.%s" % id
		if _is_object(path, bed_docs[id], errors):
			_check_bed(path, bed_docs[id], all, errors)
	var cue_docs: Dictionary = doc.get("cues", {})
	for id: String in cue_docs:
		var path := "cues.%s" % id
		if _is_object(path, cue_docs[id], errors):
			_check_cue(path, cue_docs[id], all, errors)
	if errors.is_empty():
		_check_loop_budget(doc, errors)
	return errors


## Object keys that appear twice in one object of JSON `text`, as key paths. JSON.parse keeps only the last of them.
static func duplicate_keys(text: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Dictionary] = []  # {"seen": {}, "name": path} per open object, {} per open array
	var pending := ""
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == '"':
			var end := i + 1
			while end < n and text[end] != '"':
				end += 2 if text[end] == "\\" else 1
			var token := text.substr(i + 1, end - i - 1)
			i = end + 1
			var next := i
			while next < n and " \t\r\n".contains(text[next]):
				next += 1
			if next < n and text[next] == ":" and not stack.is_empty() and stack[-1].has("seen"):
				var seen: Dictionary = stack[-1]["seen"]
				var path := str(stack[-1]["name"]) + token
				if seen.has(token):
					out.append(path)
				seen[token] = true
				pending = path + "."
			continue
		if c == "{":
			stack.append({"seen": {}, "name": pending})
		elif c == "[":
			stack.append({"name": pending})
		elif c == "}" or c == "]":
			stack.pop_back()
		i += 1
	return out


## Takes precedence over the file; the bench and kit tests have no WAV of their own.
func set_stream(sound_id: String, variant: int, s: AudioStream) -> void:
	_streams[_key(sound_id, posmod(variant, variants(sound_id)))] = s


func variants(sound_id: String) -> int:
	var sound: Dictionary = sounds.get(sound_id, {})
	return maxi(int(sound.get("variants", 1)), 1)


func is_locked(sound_id: String) -> bool:
	var sound: Dictionary = sounds.get(sound_id, {})
	return bool(sound.get("locked", false))


## Lazy; dir/<id>.wav, or dir/<id>_<variant+1>.wav when variants > 1. `variant` wraps, so a running count round-robins.
func stream(sound_id: String, variant: int = 0) -> AudioStream:
	var n := variants(sound_id)
	var v := posmod(variant, n)
	var key := _key(sound_id, v)
	if _streams.has(key):
		return _streams[key]
	var stem := sound_id if n <= 1 else "%s_%d" % [sound_id, v + 1]
	var path := "%s/%s.wav" % [dir, stem]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null and not _warned.has(path):
		_warned[path] = true
		push_warning("AudioBank: no sound at %s" % path)
	_streams[key] = s
	return s


func _key(sound_id: String, variant: int) -> String:
	return "%s#%d" % [sound_id, variant]


static func _check_sounds(all: Dictionary, errors: Array[String]) -> void:
	var files := {}
	for id: String in all:
		var path := "sounds.%s" % id
		if not _is_object(path, all[id], errors):
			continue
		var sound: Dictionary = all[id]
		if not RATES.has(_int_of(sound.get("rate"), 0)):
			errors.append("%s.rate: %s is not 11025 or 22050" % [path, str(sound.get("rate"))])
		var ch := _int_of(sound.get("ch"), 0)
		if ch != 1 and ch != 2:
			errors.append("%s.ch: %s is not 1 or 2" % [path, str(sound.get("ch"))])
		var n := _int_of(sound.get("variants", 1), 0)
		if n < 1:
			errors.append("%s.variants: %s is not 1 or more" % [path, str(sound.get("variants"))])
		for key: String in ["locked", "loop"]:
			if sound.has(key) and not sound[key] is bool:
				errors.append("%s.%s: needs true or false" % [path, key])
		if _flag(sound, "locked") and str(sound.get("compress", "pcm")) != "pcm":
			errors.append("%s.compress: a locked sound stays PCM, its seek must be exact" % path)
		var stems: Array[String] = [id]
		if n > 1:
			stems.clear()
			for v in n:
				stems.append("%s_%d" % [id, v + 1])
		for stem: String in stems:
			if files.has(stem):
				errors.append(
					"%s: duplicate id: %s.wav also belongs to %s" % [path, stem, files[stem]]
				)
			files[stem] = id


static func _check_machine(
	path: String, machine: Dictionary, all: Dictionary, errors: Array[String]
) -> void:
	_check_bus(path + ".bus", machine.get("bus", AudioBuses.MACHINES), errors)
	var events := _list_at(machine, "events", path, errors)
	for i in events.size():
		var at_path := "%s.events[%d]" % [path, i]
		if _is_object(at_path, events[i], errors):
			_check_event(at_path, events[i], all, errors)
	_check_layers(path + ".loops", _list_at(machine, "loops", path, errors), all, errors)


static func _check_event(
	path: String, ev: Dictionary, all: Dictionary, errors: Array[String]
) -> void:
	var id := str(ev.get("sound", ""))
	if not all.has(id):
		errors.append("%s.sound: no sound '%s'" % [path, id])
	elif all[id] is Dictionary:
		var sound: Dictionary = all[id]
		if not _flag(sound, "locked"):
			errors.append("%s.sound: '%s' is not locked" % [path, id])
		if _int_of(sound.get("ch", 1), 1) != 1:
			errors.append("%s.sound: '%s' is stereo, machines are mono" % [path, id])
	_check_numbers(path, ev, ["db", "priority"], errors)
	_check_curves(path, ev, errors)
	_list_at(ev, "pitch_table", path, errors)
	if not ev.get("at") is Array or (ev["at"] as Array).is_empty():
		errors.append("%s.at: needs a list of fractions" % path)
		return
	var ats: Array = ev["at"]
	var seen := {}
	for k in ats.size():
		if not _is_number(ats[k]):
			errors.append("%s.at[%d]: needs a number" % [path, k])
			continue
		var at := float(ats[k])
		if at < 0.0 or at >= 1.0:
			errors.append("%s.at[%d]: %s is outside [0, 1)" % [path, k, str(at)])
		if seen.has(at):
			errors.append("%s.at[%d]: duplicate id: %s appears twice" % [path, k, str(at)])
		seen[at] = true


static func _check_layers(
	path: String, layers: Array, all: Dictionary, errors: Array[String]
) -> void:
	for i in layers.size():
		var at_path := "%s[%d]" % [path, i]
		if not _is_object(at_path, layers[i], errors):
			continue
		var layer: Dictionary = layers[i]
		var id := str(layer.get("sound", ""))
		if not all.has(id):
			errors.append("%s.sound: no sound '%s'" % [at_path, id])
		elif all[id] is Dictionary and not _flag(all[id], "loop"):
			errors.append("%s.sound: '%s' is not a loop" % [at_path, id])
		_check_numbers(at_path, layer, ["db", "min_rpm", "slew_s"], errors)
		_check_curves(at_path, layer, errors)


static func _check_bed(
	path: String, bed: Dictionary, all: Dictionary, errors: Array[String]
) -> void:
	_check_layers(path + ".layers", _list_at(bed, "layers", path, errors), all, errors)
	_check_numbers(path, bed, ["spot_min_gap_s"], errors)
	var spots := _list_at(bed, "spots", path, errors)
	for i in spots.size():
		var at_path := "%s.spots[%d]" % [path, i]
		if not _is_object(at_path, spots[i], errors):
			continue
		var spot: Dictionary = spots[i]
		var id := str(spot.get("sound", ""))
		if not all.has(id):
			errors.append("%s.sound: no sound '%s'" % [at_path, id])
		_check_numbers(at_path, spot, ["burst_gap_s"], errors)
		_check_curves(at_path, spot, errors)
		for key: String in ["gap_s", "db", "pitch", "burst"]:
			if spot.has(key) and not _is_number_or_range(spot[key]):
				errors.append("%s.%s: needs a number or a [lo, hi] range" % [at_path, key])


static func _check_cue(
	path: String, cue: Dictionary, all: Dictionary, errors: Array[String]
) -> void:
	_check_numbers(path, cue, ["other_db"], errors)
	var hits := _list_at(cue, "hits", path, errors)
	for i in hits.size():
		var at_path := "%s.hits[%d]" % [path, i]
		if not _is_object(at_path, hits[i], errors):
			continue
		var hit: Dictionary = hits[i]
		var id := str(hit.get("sound", ""))
		if not all.has(id):
			errors.append("%s.sound: no sound '%s'" % [at_path, id])
		_check_bus(at_path + ".bus", hit.get("bus", AudioBuses.SFX), errors)
		_check_numbers(at_path, hit, ["db", "pitch", "priority", "delay_s"], errors)
		if hit.has("flight"):
			_check_flight(at_path + ".flight", hit["flight"], all.get(id, {}), errors)
	var ducks := _list_at(cue, "duck", path, errors)
	for i in ducks.size():
		var at_path := "%s.duck[%d]" % [path, i]
		if not _is_object(at_path, ducks[i], errors):
			continue
		var duck: Dictionary = ducks[i]
		var bus := str(duck.get("bus", ""))
		_check_bus(at_path + ".bus", bus, errors)
		if bus == AudioBuses.UI:
			errors.append("%s.bus: UI is never ducked" % at_path)
		_check_numbers(at_path, duck, ["db", "attack_s", "release_s"], errors)


## A flight runs a looping sound for as long as its projectile flies, so the sound must be a loop.
static func _check_flight(
	path: String, flight: Variant, sound: Variant, errors: Array[String]
) -> void:
	if not _is_object(path, flight, errors):
		return
	if not (sound is Dictionary and bool((sound as Dictionary).get("loop", false))):
		errors.append("%s: its sound must be a loop" % path)
	for key: String in ["gain", "pitch"]:
		if (flight as Dictionary).has(key) and not ((flight as Dictionary)[key] is Array):
			errors.append("%s.%s: needs a list of [u, value] points" % [path, key])


## A known bus: the four of AudioBuses, or one that exists on the server (the jitter bench's temporary bus).
static func _check_bus(path: String, bus: Variant, errors: Array[String]) -> void:
	var name_of := str(bus)
	if name_of == AudioBuses.MASTER:
		errors.append("%s: %s" % [path, BUS_MASTER_REFUSED])
	elif not AudioBuses.ALL.has(name_of) and AudioServer.get_bus_index(name_of) < 0:
		errors.append("%s: unknown bus '%s'" % [path, name_of])


## The run-time pool (SPEC_AUDIO 1.3): lead layers of one machine + `loops` + the largest bed must fit. Reads only a
## doc whose shapes have passed.
static func _check_loop_budget(doc: Dictionary, errors: Array[String]) -> void:
	var mix_doc: Dictionary = doc.get("mix", {})
	var limit := int(mix_doc.get("max_loop_players", DEFAULT_MIX["max_loop_players"]))
	var fixed := 0
	var loop_docs: Dictionary = doc.get("loops", {})
	for id: String in loop_docs:
		var entry: Dictionary = loop_docs[id]
		fixed += (entry.get("layers", []) as Array).size()
	var largest_bed := 0
	var bed_docs: Dictionary = doc.get("beds", {})
	for id: String in bed_docs:
		var bed: Dictionary = bed_docs[id]
		largest_bed = maxi(largest_bed, (bed.get("layers", []) as Array).size())
	var machine_docs: Dictionary = doc.get("machines", {})
	for id: String in machine_docs:
		var machine: Dictionary = machine_docs[id]
		var total: int = (machine.get("loops", []) as Array).size() + fixed + largest_bed
		if total > limit:
			errors.append("machines.%s.loops: %d loop players exceed %d" % [id, total, limit])


## db_by and pitch_by are lists of curves and `when` is an object, on an event, a layer or a spot.
static func _check_curves(path: String, item: Dictionary, errors: Array[String]) -> void:
	for key: String in ["db_by", "pitch_by"]:
		var curves := _list_at(item, key, path, errors)
		for i in curves.size():
			_is_object("%s.%s[%d]" % [path, key, i], curves[i], errors)
	if item.has("when"):
		_is_object(path + ".when", item["when"], errors)


static func _check_numbers(
	path: String, item: Dictionary, keys: Array, errors: Array[String]
) -> void:
	for key: String in keys:
		if item.has(key) and not _is_number(item[key]):
			errors.append("%s.%s: needs a number" % [path, key])


## True when `value` is an object; else an error naming `path`.
static func _is_object(path: String, value: Variant, errors: Array[String]) -> bool:
	if value is Dictionary:
		return true
	errors.append("%s: needs an object" % path)
	return false


## `block[key]` when it is a list, [] when it is absent; else an error naming the key, and [].
static func _list_at(block: Dictionary, key: String, path: String, errors: Array[String]) -> Array:
	var value: Variant = block.get(key, [])
	if value is Array:
		return value
	errors.append("%s.%s: needs a list" % [path, key])
	return []


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


static func _is_number_or_range(value: Variant) -> bool:
	if value is Array:
		var range_of: Array = value
		return range_of.size() == 2 and _is_number(range_of[0]) and _is_number(range_of[1])
	return _is_number(value)


## A number as an int; `fallback` for anything else, which then fails the check that reads it.
static func _int_of(value: Variant, fallback: int) -> int:
	return int(value) if _is_number(value) else fallback


static func _flag(block: Dictionary, key: String) -> bool:
	var value: Variant = block.get(key, false)
	return value is bool and value
