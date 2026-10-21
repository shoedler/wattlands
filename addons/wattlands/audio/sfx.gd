class_name WlSfx
extends Node
## Autoload `Sfx` (BRIEF 3.9 audio): sound effects from credited CC0 packs if downloaded,
## otherwise synthesized at runtime, plus an optional cadence metronome. Owned by ui-hud;
## public API frozen after W0. Silent (no errors) in headless runs.
## Built-in effect names: "ui_move", "ui_confirm", "ui_back", "toast", "warning", "rescue",
## "phase", "countdown", "lap", "results", "coin", "hit", "boom", "whoosh", "click".
## Games register their own synthesized or loaded streams with register().
##
## No CC0 pack ships in this build (docs/decisions/ui-hud.md): every built-in is synthesized
## by SfxSynth the first time it is played. A game's register() replaces a built-in of the
## same name. synth(..., loop = true) returns a looping clip whose pitch a game may change
## live (an AudioStreamPlayer's pitch_scale), for hums, rumbles and whines.
## The metronome clicks once per pedal stroke (60 / rpm seconds) while on; the GameHost
## feeds it the local rider's cadence band centre, else the preferred cadence, when the
## profile's metronome setting is on.

const BUILTIN_NAMES: Array[String] = [
	"ui_move", "ui_confirm", "ui_back", "toast", "warning", "rescue", "phase", "countdown",
	"lap", "results", "coin", "hit", "boom", "whoosh", "click",
]
const POOL_SIZE := 8
const METRONOME_SOUND := "click"
const METRONOME_DB := -8.0

## Added to every play() volume.
var master_db: float = 0.0
## Count plays but make no sound.
var muted: bool = false
## The name and count of plays (tests, debugging).
var last_played: String = ""
var play_count: int = 0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _metro_on: bool = false
var _metro_rpm: float = 0.0
var _metro_t: float = 0.0
var _metro_clicks: int = 0
var _warned: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	tick(delta)


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := get_stream(sound)
	if s == null:
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("Sfx: unknown sound '%s'" % sound)
		return
	last_played = sound
	play_count += 1
	if muted or not is_inside_tree():
		return
	var p := _free_player()
	p.stream = s
	p.volume_db = volume_db + master_db
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()


## Add a named effect (an AudioStream, e.g. a game's own synthesized clip).
func register(sound: String, stream: AudioStream) -> void:
	if sound.is_empty() or stream == null:
		push_error("Sfx: register needs a name and a stream (got '%s', %s)" % [sound, stream])
		return
	_streams[sound] = stream


func has_sound(sound: String) -> bool:
	return _streams.has(sound) or BUILTIN_NAMES.has(sound)


## The stream registered or built in under `sound` (built-ins are synthesized on first use);
## null if unknown.
func get_stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	if BUILTIN_NAMES.has(sound):
		var s := SfxSynth.builtin(sound)
		_streams[sound] = s
		return s
	return null


## Cadence metronome at `rpm` (one click per pedal stroke); rpm <= 0 stops it.
func set_metronome(rpm: float, on: bool) -> void:
	_metro_rpm = maxf(rpm, 0.0)
	var was_on := _metro_on
	_metro_on = on and _metro_rpm > 0.0
	if not _metro_on:
		_metro_t = 0.0
	elif not was_on:
		_metro_t = 0.0


func metronome_on() -> bool:
	return _metro_on


func metronome_rpm() -> float:
	return _metro_rpm


## Clicks played since this node started (tests).
func metronome_clicks() -> int:
	return _metro_clicks


## Advance the metronome by dt seconds (_process calls it with the frame delta).
func tick(dt: float) -> void:
	if not _metro_on or dt <= 0.0:
		return
	_metro_t += dt
	var interval := 60.0 / _metro_rpm
	while _metro_t >= interval - 1e-6:
		_metro_t -= interval
		_metro_clicks += 1
		play(METRONOME_SOUND, METRONOME_DB)


## A short synthesized tone/noise clip (games can use it for their own effects).
## kind: "sine", "square", "saw", "noise"; envelope seconds.
func synth(kind: String, freq_hz: float, duration_s: float, attack_s: float = 0.005, release_s: float = 0.05, loop: bool = false) -> AudioStream:
	if not SfxSynth.KINDS.has(kind):
		push_error("Sfx: unknown synth kind '%s' (use %s)" % [kind, ", ".join(SfxSynth.KINDS)])
		return null
	if duration_s <= 0.0 or duration_s > 30.0:
		push_error("Sfx: synth duration %.3f s out of range (0, 30]" % duration_s)
		return null
	return SfxSynth.tone(kind, freq_hz, duration_s, attack_s, release_s, loop)


## Stop every playing effect (the metronome keeps its setting).
func stop_all() -> void:
	for p in _players:
		p.stop()


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	if _players.size() < POOL_SIZE:
		var np := AudioStreamPlayer.new()
		np.name = "Player%d" % _players.size()
		add_child(np)
		_players.append(np)
		return np
	var p := _players[_next_player % _players.size()]
	_next_player += 1
	return p
