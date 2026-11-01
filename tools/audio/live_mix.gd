extends SceneTree
## Records what a real session really plays: the real GameHost, game module, view and GameAudioKit, on the real audio
## server, with no hand-fed cue. Not part of run_tests. The offline preview scores the bank; this hears the game.
##   tools/godot.sh --path . --timeout=600 --audio-driver Dummy -s tools/audio/live_mix.gd -- \
##       --game=siege --content=short --bots=3 --seed=1 --skip-s=60 --run-s=240 --out=build/audio_live/siege
## --audio-driver Dummy keeps the speakers out of it: Godot still mixes in real time, and an AudioEffectCapture at the
## head of each bus takes what reaches it. Master's capture is the whole mix with the ducks in, before the limiter; the
## others sit before their bus volume, so they are the bus without its ducks. <out>_limited.wav is Master after its
## limiter, what a rider hears. --skip-s runs that much sim in the first frames, before anything is recorded. Writes
## <out>.json and <out>_<bus>.wav (stereo 32-bit float: a capture must not clip what the limiter would have caught):
##   cues: every game `cue` the view would hear, by kind; shots by shot kind, projectiles counted;
##   played: every start the kit recorded, by sound, with the level it asked for;
##   voices: per pool the most and the mean playing at once, frames at the cap; voiceless, thinned, stolen;
##   flight_log: each flight as it started: [time, sound, seconds, db, 1 if the rider's own, pitch];
##   voice_starts: what really reached a player, read off the pools once a frame, by file: starts, how many were still
##   playing a frame later, the buses and the player level; lost if a player was re-granted inside one frame;
##   start_log: each of those: [time, file, bus, level, pitch, the cue's tag_var];
##   arrows: arrows landed and struck by SiegeShotSounds and by the host's station.hits (Siege only).
## --app runs the app itself: the main scene, its autoloads, a solo quick start on the session screen with a mock
## trainer, the same screen a rider sees. Without it the session is GameSimRunner's, with --bots riders.
## --mute-master takes Master to -80 dB, for a run on a real driver (--audio-driver WASAPI) nobody may hear: the
## captures sit before the volume, so they read the same. Use it: the Dummy driver mixes in chunks of 4096 frames,
## 93 ms, so every voice started inside one begins on the same sample and a crowd of short sounds piles up.
## A window opens, because a headless kit stays silent by design (GameAudioKit._quiet_run).

const BUSES: Array[String] = ["Master", "Machines", "Ambience", "Sfx", "UI"]
const LIMITED := "Limited"
const SIM_DT := 0.05
const SETTLE_FRAMES := 30
const MUTED_DB := -80.0

var _runner: GameSimRunner = null
var _host: GameHost = null
var _main: Node = null
var _app_mode: bool = false
var _temp_profile: String = ""
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
var _chunks: Dictionary = {}
var _frames_captured: int = 0
var _limited: AudioEffectCapture = null
var _cues: Dictionary = {}
var _shots: Dictionary = {}
var _played: Dictionary = {}
var _played_log: Array[Array] = []
var _cue_log: Array[Array] = []
var _flight_log: Array[Array] = []
var _flights_seen: Dictionary = {}
var _pool_max: Dictionary = {}
var _pool_sum: Dictionary = {}
var _pool_full: Dictionary = {}
var _voice_frames: int = 0
var _skip_voiceless: int = 0
var _skip_thinned: int = 0
var _skip_flights: int = 0
var _serials: Dictionary = {}
var _fresh: Array[Array] = []
var _voice_starts: Dictionary = {}
var _start_log: Array[Array] = []
var _bus_db: Dictionary = {}
var _skip_landed: Dictionary = {}
var _skip_struck: Dictionary = {}
var _skip_hits: int = 0
var _skip_crowd_voiceless: int = 0
var _skip_stolen: Dictionary = {}


func _init() -> void:
	# Runs before the autoloads start: an app run must not touch the rider's real profile.
	if CmdLine.has("app") and not CmdLine.has("profile-dir"):
		_temp_profile = Paths.make_temp_dir("wattlands_live_mix")
		Paths.set_override(_temp_profile)


func _process(delta: float) -> bool:
	if _done:
		return true
	if not _started:
		_started = true
		_begin()
		return false
	if _app_mode and _host == null:
		_host = _app_session()
		if _host == null:
			return false
		_game = _host.game
		_connect_game()
	if _host == null:
		return false
	_frames += 1
	if _frames == 1 and _skip_s > 0.0:
		for _i in roundi(_skip_s / SIM_DT):
			_step()
	if not _app_mode:
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
			_skip_crowd_voiceless = _kit.crowd_voiceless
			_skip_stolen = _kit.stolen.duplicate()
			_mark_arrows()
			_mark_voices()
			_add_captures()
		return false
	_t += delta
	# The log first: what started this frame starts after what is already captured.
	_drain_played()
	_count_starts()
	_drain_captures()
	_count_voices()
	if _t >= _run_s or _host.is_finished():
		_finish()
	return false


## --station keeps the local rider's wheel on one station (Siege only, the recording's own business): a game's level
## depends on whose shots are the rider's.
func _step() -> void:
	if _station >= 0 and _game != null and _game.get("state") != null:
		var me: Variant = _game.state.rider(_host.ctx.local_peer)
		if me != null:
			me.target = _station
			me.route_fallback = false
	if _app_mode:
		_host.step()
	else:
		_runner.step()


func _begin() -> void:
	_out = CmdLine.get_str("out", "build/audio_live/session")
	_run_s = CmdLine.get_float("run-s", 240.0)
	_skip_s = CmdLine.get_float("skip-s", 0.0)
	_station = CmdLine.get_int("station", -1)
	_mute_master()
	if CmdLine.has("app"):
		_begin_app()
		return
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
	_host = _runner.host
	_game = _host.game
	_connect_game()


func _connect_game() -> void:
	if _game != null and _game.has_signal("cue"):
		_game.connect("cue", _on_cue)


## The rider's way in, less the menus: the main scene and the solo quick start the title screen would make.
func _begin_app() -> void:
	_app_mode = true
	var packed := load(str(ProjectSettings.get_setting("application/run/main_scene", "")))
	_main = (packed as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	_mute_master()
	var trainer := root.get_node_or_null(^"TrainerService") as WlTrainerService
	trainer.use_mock(CmdLine.get_str("rider", "erg:compliance=1.0"))
	var settings := root.get_node_or_null(^"Settings") as WlSettings
	if not settings.has_profile():
		settings.create_profile("Rider")
	var gid := CmdLine.get_str("game", "siege")
	HelpSeen.mark(gid)
	var app := root.get_node_or_null(^"App") as WlApp
	app.goto(
		"session",
		{
			"role": Wl.SOLO,
			"game_id": gid,
			"content_id": CmdLine.get_str("content", "short"),
			"quick": true
		}
	)


## The app's boot sets Master from Settings, so an app run calls this twice.
func _mute_master() -> void:
	if CmdLine.has("mute-master"):
		AudioServer.set_bus_volume_db(0, MUTED_DB)


func _app_session() -> GameHost:
	var s := _main.get("screen") as AppSessionScreen
	if s == null or s.host == null or s.host.game == null or s.host.clock == null:
		return null
	return s.host


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
		_chunks[bus] = [] as Array[PackedByteArray]
	# Master's limiter is on its bus already, so a capture added last hears what comes out of it.
	_limited = AudioEffectCapture.new()
	_limited.buffer_length = 2.0
	AudioServer.add_bus_effect(0, _limited)
	_captures[LIMITED] = _limited
	_chunks[LIMITED] = [] as Array[PackedByteArray]


func _drain_captures() -> void:
	for bus: String in _captures:
		var cap: AudioEffectCapture = _captures[bus]
		var n := cap.get_frames_available()
		if n <= 0:
			continue
		(_chunks[bus] as Array[PackedByteArray]).append(cap.get_buffer(n).to_byte_array())
		if bus == "Master":
			_frames_captured += n


func _drain_played() -> void:
	for i in _kit.played.size():
		var id := _kit.played[i]
		var e: Dictionary = _played.get(id, {"n": 0, "db": _kit.played_db[i]})
		e["n"] = int(e["n"]) + 1
		_played[id] = e
		_played_log.append([_captured_s(), id, snappedf(_kit.played_db[i], 0.1)])
	_kit.clear_played()
	for f: GameAudioKit.Flight in _kit._flights:
		if _flights_seen.has(f.get_instance_id()):
			continue
		_flights_seen[f.get_instance_id()] = true
		(
			_flight_log
			. append(
				[
					snappedf(_captured_s() - f.t, 0.001),
					f.sound,
					snappedf(f.dur, 0.001),
					snappedf(f.db, 0.1),
					1 if f.lead else 0,
					snappedf(f.pitch, 0.001),
				]
			)
		)


## Where the recording has got to. The log uses this and not the frame clock: a capture starts a mix step or two after
## its frame, and a log 50 ms off puts every onset in the wrong frame of a level plot.
func _captured_s() -> float:
	return snappedf(float(_frames_captured) / AudioServer.get_mix_rate(), 0.001)


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


## Before the recording: the voices' grants and the arrows so far don't count.
func _mark_voices() -> void:
	for key: String in _kit._pools:
		for v: Variant in _kit._pools[key]:
			_serials[v.get_instance_id()] = v.serial


func _mark_arrows() -> void:
	var sounds: Variant = _siege_shots()
	if sounds == null:
		return
	_skip_landed = sounds.landed_count.duplicate()
	_skip_struck = sounds.struck_count.duplicate()
	_skip_hits = _game.state.station(SiegeIds.STATION_ARROWS).hits


func _siege_shots() -> Variant:
	var host_view: Node = _host.view_root() if _host != null else null
	return _find_shots(host_view) if host_view != null else null


func _find_shots(n: Node) -> Variant:
	if n is SiegeAudio:
		return n._shots
	for c in n.get_children(true):
		var found: Variant = _find_shots(c)
		if found != null:
			return found
	return null


## What really reached a player, once a frame. A grant this frame is looked at again on the next one, to see that it
## plays: GameAudioKit's own log says a start was asked for, this says a player took it.
func _count_starts() -> void:
	for e: Array in _fresh:
		var v: Variant = e[0]
		var s: Dictionary = _voice_starts[e[1]]
		if v.player.playing or v.player.get_playback_position() > 0.0:
			s["playing"] = int(s["playing"]) + 1
	_fresh.clear()
	var sfx := AudioServer.get_bus_index("Sfx")
	for key: String in _kit._pools:
		for v: Variant in _kit._pools[key]:
			var was := int(_serials.get(v.get_instance_id(), 0))
			if v.serial == was:
				continue
			_serials[v.get_instance_id()] = v.serial
			var stem := str(v.player.stream.resource_path).get_file().get_basename()
			var s: Dictionary = _voice_starts.get(stem, _new_start(key))
			s["n"] = int(s["n"]) + 1
			s["lost"] = int(s["lost"]) + v.serial - was - 1
			var bus := str(v.player.bus)
			s["buses"][bus] = int(s["buses"].get(bus, 0)) + 1
			s["db_min"] = minf(float(s["db_min"]), v.player.volume_db)
			s["db_max"] = maxf(float(s["db_max"]), v.player.volume_db)
			_voice_starts[stem] = s
			_fresh.append([v, stem])
			var tag: Variant = v.get("tag")
			(
				_start_log
				. append(
					[
						_captured_s(),
						stem,
						bus,
						snappedf(v.player.volume_db, 0.1),
						snappedf(v.player.pitch_scale, 0.001),
						int(tag) if tag != null else 0,
					]
				)
			)
	var db := AudioServer.get_bus_volume_db(sfx)
	_bus_db["n"] = int(_bus_db.get("n", 0)) + 1
	_bus_db["sfx_min"] = minf(float(_bus_db.get("sfx_min", 99.0)), db)
	_bus_db["sfx_sum"] = float(_bus_db.get("sfx_sum", 0.0)) + db


func _stolen_since() -> Dictionary:
	var out := {}
	for key: String in _kit.stolen:
		var n := int(_kit.stolen[key]) - int(_skip_stolen.get(key, 0))
		if n > 0:
			out[key] = n
	return out


static func _new_start(key: String) -> Dictionary:
	return {
		"n": 0, "playing": 0, "lost": 0, "pool": key, "buses": {}, "db_min": 99.0, "db_max": -99.0
	}


func _arrows_report() -> Dictionary:
	var sounds: Variant = _siege_shots()
	if sounds == null:
		return {}
	return {
		"landed": int(sounds.landed_count.get("arrow", 0)) - int(_skip_landed.get("arrow", 0)),
		"struck": int(sounds.struck_count.get("arrow", 0)) - int(_skip_struck.get("arrow", 0)),
		"station_hits": _game.state.station(SiegeIds.STATION_ARROWS).hits - _skip_hits,
	}


func _finish() -> void:
	_done = true
	_drain_captures()
	_drain_played()
	_count_starts()
	var rate := int(AudioServer.get_mix_rate())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	for bus: String in _chunks:
		_write_wav("%s_%s.wav" % [_out, bus.to_lower()], _chunks[bus], rate)
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
		"crowd_voiceless": _kit.crowd_voiceless - _skip_crowd_voiceless,
		"stolen": _stolen_since(),
		"flight_starts": _kit.flight_starts - _skip_flights,
		"thinned": _kit.thinned - _skip_thinned,
		"cue_log": _cue_log,
		"played_log": _played_log,
		"flight_log": _flight_log,
		"app": _app_mode,
		"voice_starts": _voice_starts,
		"start_log": _start_log,
		"arrows": _arrows_report(),
		"sfx_bus_db":
		{
			"min": _bus_db.get("sfx_min", 0.0),
			"mean": float(_bus_db.get("sfx_sum", 0.0)) / maxf(float(_bus_db.get("n", 1)), 1.0),
			"user": AudioBuses.user_db("Sfx"),
		},
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
	_host.end_session("timeout")
	if _runner != null:
		_runner.cleanup()
	if _temp_profile != "":
		print("live_mix: temp profile %s" % _temp_profile)
	quit(0)


func _write_wav(path: String, chunks: Array[PackedByteArray], rate: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("live_mix: cannot write %s" % path)
		return
	var size := 0
	for c in chunks:
		size += c.size()
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
