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
	var machine_docs: Dictionary = doc.get("machines", {})
	for id: String in machine_docs:
		_check_machine("machines.%s" % id, machine_docs[id], all, errors)
	var loop_docs: Dictionary = doc.get("loops", {})
	for id: String in loop_docs:
		var entry: Dictionary = loop_docs[id]
		_check_bus("loops.%s.bus" % id, entry.get("bus", AudioBuses.SFX), errors)
		_check_layers("loops.%s.layers" % id, entry.get("layers", []), all, errors)
	var bed_docs: Dictionary = doc.get("beds", {})
	for id: String in bed_docs:
		_check_bed("beds.%s" % id, bed_docs[id], all, errors)
	var cue_docs: Dictionary = doc.get("cues", {})
	for id: String in cue_docs:
		_check_cue("cues.%s" % id, cue_docs[id], all, errors)
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
		if not all[id] is Dictionary:
			errors.append("%s: needs an object" % path)
			continue
		var sound: Dictionary = all[id]
		if not RATES.has(int(sound.get("rate", 0))):
			errors.append("%s.rate: %s is not 11025 or 22050" % [path, str(sound.get("rate"))])
		var ch := int(sound.get("ch", 0))
		if ch != 1 and ch != 2:
			errors.append("%s.ch: %s is not 1 or 2" % [path, str(sound.get("ch"))])
		var n := int(sound.get("variants", 1))
		if n < 1:
			errors.append("%s.variants: %d is below 1" % [path, n])
		if bool(sound.get("locked", false)) and str(sound.get("compress", "pcm")) != "pcm":
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
	var events: Array = machine.get("events", [])
	for i in events.size():
		_check_event("%s.events[%d]" % [path, i], events[i], all, errors)
	_check_layers(path + ".loops", machine.get("loops", []), all, errors)


static func _check_event(
	path: String, ev: Dictionary, all: Dictionary, errors: Array[String]
) -> void:
	var id := str(ev.get("sound", ""))
	if not all.has(id):
		errors.append("%s.sound: no sound '%s'" % [path, id])
	elif all[id] is Dictionary:
		var sound: Dictionary = all[id]
		if not bool(sound.get("locked", false)):
			errors.append("%s.sound: '%s' is not locked" % [path, id])
		if int(sound.get("ch", 1)) != 1:
			errors.append("%s.sound: '%s' is stereo, machines are mono" % [path, id])
	if not ev.get("at") is Array or (ev["at"] as Array).is_empty():
		errors.append("%s.at: needs a list of fractions" % path)
		return
	var ats: Array = ev["at"]
	var seen := {}
	for k in ats.size():
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
		var layer: Dictionary = layers[i]
		var id := str(layer.get("sound", ""))
		if not all.has(id):
			errors.append("%s[%d].sound: no sound '%s'" % [path, i, id])
		elif all[id] is Dictionary and not bool((all[id] as Dictionary).get("loop", false)):
			errors.append("%s[%d].sound: '%s' is not a loop" % [path, i, id])


static func _check_bed(
	path: String, bed: Dictionary, all: Dictionary, errors: Array[String]
) -> void:
	_check_layers(path + ".layers", bed.get("layers", []), all, errors)
	var spots: Array = bed.get("spots", [])
	for i in spots.size():
		var spot: Dictionary = spots[i]
		var id := str(spot.get("sound", ""))
		if not all.has(id):
			errors.append("%s.spots[%d].sound: no sound '%s'" % [path, i, id])


static func _check_cue(
	path: String, cue: Dictionary, all: Dictionary, errors: Array[String]
) -> void:
	var hits: Array = cue.get("hits", [])
	for i in hits.size():
		var hit: Dictionary = hits[i]
		var id := str(hit.get("sound", ""))
		if not all.has(id):
			errors.append("%s.hits[%d].sound: no sound '%s'" % [path, i, id])
		_check_bus("%s.hits[%d].bus" % [path, i], hit.get("bus", AudioBuses.SFX), errors)
	var ducks: Array = cue.get("duck", [])
	for i in ducks.size():
		var duck: Dictionary = ducks[i]
		var bus := str(duck.get("bus", ""))
		_check_bus("%s.duck[%d].bus" % [path, i], bus, errors)
		if bus == AudioBuses.UI:
			errors.append("%s.duck[%d].bus: UI is never ducked" % [path, i])


## A known bus: the four of AudioBuses, or one that exists on the server (the jitter bench's temporary bus).
static func _check_bus(path: String, bus: Variant, errors: Array[String]) -> void:
	var name_of := str(bus)
	if name_of == AudioBuses.MASTER:
		errors.append("%s: %s" % [path, BUS_MASTER_REFUSED])
	elif not AudioBuses.ALL.has(name_of) and AudioServer.get_bus_index(name_of) < 0:
		errors.append("%s: unknown bus '%s'" % [path, name_of])


## The run-time pool (SPEC_AUDIO 1.3): lead layers of one machine + `loops` + the largest bed must fit.
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
