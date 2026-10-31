extends SceneTree
## Records what a real session really plays: the real GameHost, game module, view and GameAudioKit, on the real audio
## server, with no hand-fed cue. Not part of run_tests. The offline preview scores the bank; this hears the game.
##   tools/godot.sh --path . --timeout=600 --audio-driver Dummy -s tools/audio/live_mix.gd -- \
##       --game=siege --content=short --bots=3 --seed=1 --skip-s=60 --run-s=240 --out=build/audio_live/siege
## --audio-driver Dummy keeps the speakers out of it: Godot still mixes in real time, and an AudioEffectCapture at the
## head of each bus takes what reaches it. Master's capture is the whole mix with the ducks in, before the limiter; the
## others sit before their bus volume, so they are the bus without its ducks. --skip-s runs that much sim in the first
## frames, before anything is recorded. Writes <out>.json and <out>_<bus>.wav (stereo 16-bit):
##   cues: every game `cue` the view would hear, by kind; shots by shot kind, projectiles counted;
##   played: every start the kit recorded, by sound, with the level it asked for;
##   voices: per pool the most and the mean playing at once, frames at the cap; voiceless and thinned.
## A window opens, because a headless kit stays silent by design (GameAudioKit._quiet_run).

const BUSES: Array[String] = ["Master", "Machines", "Ambience", "Sfx", "UI"]
const SIM_DT := 0.05
const SETTLE_FRAMES := 30
const PEAK := 32767.0

var _runner: GameSimRunner = null
var _kit: GameAudioKit = null
var _game: Node = null
var _out: String = ""
var _run_s: float = 240.0
var _skip_s: float = 0.0
var _station: int = -1
var _accum: float = 0.0
var _t: float = 0.0
var _frames: int = 0
var _recording: bool = false
var _started: bool = false
var _done: bool = false
var _captures: Dictionary = {}
var _samples: Dictionary = {}
var _cues: Dictionary = {}
var _shots: Dictionary = {}
var _played: Dictionary = {}
var _played_log: Array[Array] = []
var _cue_log: Array[Array] = []
var _pool_max: Dictionary = {}
var _pool_sum: Dictionary = {}
var _pool_full: Dictionary = {}
var _voice_frames: int = 0
var _skip_voiceless: int = 0
var _skip_thinned: int = 0
var _skip_flights: int = 0


func _process(delta: float) -> bool:
	if _done:
		return true
	if not _started:
		_started = true
		_begin()
		return false
	if _runner == null:
		return false
	_frames += 1
	if _frames == 1 and _skip_s > 0.0:
		for _i in roundi(_skip_s / SIM_DT):
			_step()
	_accum += delta
	while _accum >= SIM_DT:
		_accum -= SIM_DT
		_step()
	if _kit == null:
		_kit = _find_kit(root)
	if not _recording:
		if _kit != null and _frames > SETTLE_FRAMES:
			_recording = true
			_kit.clear_played()
			_skip_voiceless = _kit.voiceless
			_skip_thinned = _kit.thinned
			_skip_flights = _kit.flight_starts
			_add_captures()
		return false
	_t += delta
	# The log first: what started this frame starts after what is already captured.
	_drain_played()
	_drain_captures()
	_count_voices()
	if _t >= _run_s or _runner.host.is_finished():
		_finish()
	return false


## --station keeps the local rider's wheel on one station (Siege only, the recording's own business): a game's level
## depends on whose shots are the rider's.
func _step() -> void:
	if _station >= 0 and _game != null and _game.get("state") != null:
		var me: Variant = _game.state.rider(_runner.host.ctx.local_peer)
		if me != null:
			me.target = _station
			me.route_fallback = false
	_runner.step()


func _begin() -> void:
	_out = CmdLine.get_str("out", "build/audio_live/session")
	_run_s = CmdLine.get_float("run-s", 240.0)
	_skip_s = CmdLine.get_float("skip-s", 0.0)
	_station = CmdLine.get_int("station", -1)
	var args := PackedStringArray(
		[
			"--game=" + CmdLine.get_str("game", "siege"),
			"--content=" + CmdLine.get_str("content", "short"),
			"--players=1",
			"--bots=%d" % CmdLine.get_int("bots", 3),
			"--seed=%d" % CmdLine.get_int("seed", 1),
			"--rider=" + CmdLine.get_str("rider", "erg:compliance=1.0"),
			"--autopilot=all",
			"--sim-speed=1",
		]
	)
	var parsed := GameSimRunner.parse_args(args)
	if parsed.has("error"):
		push_error(str(parsed["error"]))
		quit(2)
		_done = true
		return
	parsed["headless"] = false
	_runner = GameSimRunner.new()
	root.add_child(_runner)
	var err := _runner.setup(parsed)
	if err != "":
		push_error(err)
		quit(3)
		_done = true
		return
	_game = _runner.host.game
	if _game != null and _game.has_signal("cue"):
		_game.connect("cue", _on_cue)


func _on_cue(kind: String, data: Dictionary) -> void:
	if not _recording:
		return
	_cues[kind] = int(_cues.get(kind, 0)) + 1
	_cue_log.append([_captured_s(), kind, int(data.get("kind", -1)), int(data.get("n", 0))])
	if kind == "shot":
		var key := str(int(data.get("kind", -1)))
		var s: Dictionary = _shots.get(key, {"events": 0, "projectiles": 0})
		s["events"] = int(s["events"]) + 1
		s["projectiles"] = int(s["projectiles"]) + int(data.get("n", 1))
		_shots[key] = s


func _find_kit(n: Node) -> GameAudioKit:
	if n is GameAudioKit:
		return n
	for c in n.get_children(true):
		var found := _find_kit(c)
		if found != null:
			return found
	return null


func _add_captures() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 2.0
		AudioServer.add_bus_effect(i, cap, 0)
		_captures[bus] = cap
		_samples[bus] = PackedByteArray()


func _drain_captures() -> void:
	for bus: String in _captures:
		var cap: AudioEffectCapture = _captures[bus]
		var n := cap.get_frames_available()
		if n <= 0:
			continue
		var frames := cap.get_buffer(n)
		var out: PackedByteArray = _samples[bus]
		var at := out.size()
		out.resize(at + n * 4)
		for k in n:
			out.encode_s16(at + k * 4, int(clampf(frames[k].x, -1.0, 1.0) * PEAK))
			out.encode_s16(at + k * 4 + 2, int(clampf(frames[k].y, -1.0, 1.0) * PEAK))
		_samples[bus] = out


func _drain_played() -> void:
	for i in _kit.played.size():
		var id := _kit.played[i]
		var e: Dictionary = _played.get(id, {"n": 0, "db": _kit.played_db[i]})
		e["n"] = int(e["n"]) + 1
		_played[id] = e
		_played_log.append([_captured_s(), id, snappedf(_kit.played_db[i], 0.1)])
	_kit.clear_played()


## Where the recording has got to. The log uses this and not the frame clock: a capture starts a mix step or two after
## its frame, and a log 50 ms off puts every onset in the wrong frame of a level plot.
func _captured_s() -> float:
	var bytes: PackedByteArray = _samples.get("Master", PackedByteArray())
	return snappedf(float(bytes.size()) / 4.0 / AudioServer.get_mix_rate(), 0.001)


func _count_voices() -> void:
	_voice_frames += 1
	for key: String in _kit._pools:
		var pool: Array = _kit._pools[key]
		var on := 0
		for v: Variant in pool:
			if v.player.playing:
				on += 1
		_pool_max[key] = maxi(int(_pool_max.get(key, 0)), on)
		_pool_sum[key] = int(_pool_sum.get(key, 0)) + on
		if on >= _kit._pool_cap(key):
			_pool_full[key] = int(_pool_full.get(key, 0)) + 1


func _finish() -> void:
	_done = true
	_drain_captures()
	_drain_played()
	var rate := int(AudioServer.get_mix_rate())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	for bus: String in _samples:
		_write_wav("%s_%s.wav" % [_out, bus.to_lower()], _samples[bus], rate)
	var voices := {}
	for key: String in _pool_max:
		voices[key] = {
			"max": _pool_max[key],
			"mean": snappedf(float(_pool_sum[key]) / maxf(float(_voice_frames), 1.0), 0.01),
			"frames_full": int(_pool_full.get(key, 0)),
			"cap": _kit._pool_cap(key),
		}
	var report := {
		"seconds": snappedf(_t, 0.01),
		"driver": AudioServer.get_driver_name(),
		"mix_rate": rate,
		"silent": _kit.silent,
		"cues": _cues,
		"shots": _shots,
		"played": _played,
		"voices": voices,
		"voiceless": _kit.voiceless - _skip_voiceless,
		"flight_starts": _kit.flight_starts - _skip_flights,
		"thinned": _kit.thinned - _skip_thinned,
		"cue_log": _cue_log,
		"played_log": _played_log,
	}
	var f := FileAccess.open(_out + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, " "))
		f.close()
	print(
		(
			"live_mix: %.0f s on %s, %d cues, %d starts, %d voiceless -> %s.json"
			% [_t, report["driver"], _cue_log.size(), _played_log.size(), report["voiceless"], _out]
		)
	)
	_runner.host.end_session("timeout")
	_runner.cleanup()
	quit(0)


func _write_wav(path: String, data: PackedByteArray, rate: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("live_mix: cannot write %s" % path)
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(2)
	f.store_32(rate)
	f.store_32(rate * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
