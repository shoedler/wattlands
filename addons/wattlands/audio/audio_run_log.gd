class_name AudioRunLog
extends Node
## What the players of a real run took, for a run nothing else can look inside: an exported exe runs no outside script,
## and the owner plays the exe. With --audio-log=<path> a kit attaches one of these. It reads the kit's pools once a frame,
## as tools/audio/live_mix.gd does, and writes <path> as JSON every WRITE_EVERY_S and when it leaves the tree:
##   exported: whether this is an export template; driver, silent, seconds;
##   starts: by file, how many players took it, how many still played a frame later, on which buses;
##   voiceless, crowd_voiceless, flight_starts, stolen: the kit's own counts.
## --audio-capture also writes <path without .json>_master.wav, Master before its volume and limiter. --mute-master takes
## Master to -80 dB: the captures sit before the volume, so an automated run on a real driver stays unheard.

const WRITE_EVERY_S := 10.0
const MUTED_DB := -80.0
const PEAK := 32767.0

var kit: GameAudioKit = null
var path: String = ""
var starts: Dictionary = {}
var seconds: float = 0.0

var _capture: AudioEffectCapture = null
var _samples := PackedByteArray()
var _serials: Dictionary = {}
var _fresh: Array[Array] = []
var _since_write: float = 0.0


## A kit's own, if the command line asks for one.
static func attach_if_asked(p_kit: GameAudioKit) -> void:
	if not CmdLine.has("audio-log"):
		return
	var log_node := AudioRunLog.new()
	log_node.kit = p_kit
	log_node.path = CmdLine.get_str("audio-log", "")
	log_node.name = "AudioRunLog"
	p_kit.add_child(log_node)
	if CmdLine.has("audio-capture"):
		log_node.start_capture()
	if CmdLine.has("mute-master"):
		AudioServer.set_bus_volume_db(0, MUTED_DB)


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	seconds += delta
	poll()
	_drain()
	_since_write += delta
	if _since_write >= WRITE_EVERY_S:
		_since_write = 0.0
		write()


func _exit_tree() -> void:
	write()
	if _capture != null:
		_drain()
		_write_wav(path.trim_suffix(".json") + "_master.wav")
		var master := 0
		for e in AudioServer.get_bus_effect_count(master):
			if AudioServer.get_bus_effect(master, e) == _capture:
				AudioServer.remove_bus_effect(master, e)
				break
		_capture = null


func start_capture() -> void:
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, _capture, 0)


## New grants since the last frame, and whether last frame's still play.
func poll() -> void:
	for e: Array in _fresh:
		if e[0].player.playing or e[0].player.get_playback_position() > 0.0:
			starts[e[1]]["playing"] = int(starts[e[1]]["playing"]) + 1
	_fresh.clear()
	for key: String in kit._pools:
		for v: Variant in kit._pools[key]:
			var was := int(_serials.get(v.get_instance_id(), 0))
			if v.serial == was:
				continue
			_serials[v.get_instance_id()] = v.serial
			if v.player.stream == null:
				continue
			var stem := str(v.player.stream.resource_path).get_file().get_basename()
			var s: Dictionary = starts.get(stem, {"n": 0, "playing": 0, "pool": key, "buses": {}})
			s["n"] = int(s["n"]) + 1
			var bus := str(v.player.bus)
			s["buses"][bus] = int(s["buses"].get(bus, 0)) + 1
			starts[stem] = s
			_fresh.append([v, stem])


func report() -> Dictionary:
	return {
		"exported": OS.has_feature("template"),
		"driver": AudioServer.get_driver_name(),
		"silent": kit.silent,
		"seconds": snappedf(seconds, 0.01),
		"starts": starts,
		"voiceless": kit.voiceless,
		"crowd_voiceless": kit.crowd_voiceless,
		"flight_starts": kit.flight_starts,
		"stolen": kit.stolen,
	}


func write() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("AudioRunLog: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(report(), " "))
	f.close()


func _drain() -> void:
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var frames := _capture.get_buffer(n)
	var at := _samples.size()
	_samples.resize(at + n * 4)
	for k in n:
		_samples.encode_s16(at + k * 4, int(clampf(frames[k].x, -1.0, 1.0) * PEAK))
		_samples.encode_s16(at + k * 4 + 2, int(clampf(frames[k].y, -1.0, 1.0) * PEAK))


func _write_wav(file: String) -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		push_warning("AudioRunLog: cannot write %s" % file)
		return
	var rate := int(AudioServer.get_mix_rate())
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + _samples.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(_samples.size())
	f.store_buffer(_samples)
	f.close()
