class_name AudioRunLog
extends Node
## What the players of a real run took, for a run nothing else can look inside: an exported exe runs no outside script,
## and the owner plays the exe. With --audio-log=<path> a kit attaches one of these. It reads the kit's pools once a
## frame, as tools/audio/live_mix.gd does, and writes <path> as JSON every WRITE_EVERY_S and when it leaves the tree:
##   exported: whether this is an export template; driver, silent, seconds;
##   starts: by file, how many players took it, how many still played a frame later, on which buses;
##   voiceless, crowd_voiceless, flight_starts, stolen: the kit's own counts.
## --audio-capture also writes <path without .json>_master.wav, Master before its limiter as 32-bit float, so nothing
## is clipped that the limiter would have caught, and _limited.wav, after it, what a rider hears. --mute-master takes
## Master to -80 dB: the captures sit before the volume, so an automated run on a real driver stays unheard.

const WRITE_EVERY_S := 10.0
const MUTED_DB := -80.0

var kit: GameAudioKit = null
var path: String = ""
var starts: Dictionary = {}
var seconds: float = 0.0

var _capture: AudioEffectCapture = null
var _limited: AudioEffectCapture = null
var _chunks: Array[PackedByteArray] = []
var _limited_chunks: Array[PackedByteArray] = []
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
		_write_wav(path.trim_suffix(".json") + "_master.wav", _chunks)
		_write_wav(path.trim_suffix(".json") + "_limited.wav", _limited_chunks)
		for e in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
			var fx := AudioServer.get_bus_effect(0, e)
			if fx == _capture or fx == _limited:
				AudioServer.remove_bus_effect(0, e)
		_capture = null
		_limited = null


func start_capture() -> void:
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, _capture, 0)
	_limited = AudioEffectCapture.new()
	_limited.buffer_length = 2.0
	AudioServer.add_bus_effect(0, _limited)


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
	for pair: Array in [[_capture, _chunks], [_limited, _limited_chunks]]:
		var n: int = pair[0].get_frames_available()
		if n > 0:
			pair[1].append(pair[0].get_buffer(n).to_byte_array())


## 32-bit float, little endian.
func _write_wav(file: String, chunks: Array[PackedByteArray]) -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		push_warning("AudioRunLog: cannot write %s" % file)
		return
	var size := 0
	for c in chunks:
		size += c.size()
	var rate := int(AudioServer.get_mix_rate())
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + size)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(3)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 8)
	f.store_16(8)
	f.store_16(32)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(size)
	for c in chunks:
		f.store_buffer(c)
	f.close()
