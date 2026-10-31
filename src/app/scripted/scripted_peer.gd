class_name AppScriptedPeer
extends Node
## A scripted peer for the end-to-end test (docs/ARCHITECTURE.md "Scripted peers (end-to-end
## test contract)"; tools/e2e/run.mjs drives it). Started with --host or --join=<code>, it skips
## every menu: hosts or joins through NetSession and the relay, sends player_info, readies up,
## plays the session with Autopilot, waits for the results, saves the FIT, performs the Strava
## auto-upload if configured, writes the --report JSON and quits (0 on success).
## Stdout, one line per event: WATTLANDS_ROOM <code> (host, as soon as the room exists),
## WATTLANDS_PEER <peer id>, WATTLANDS_STATE <session state>, WATTLANDS_DONE <reason>.
## Exit codes: 0 complete; 1 error (bad flags, no game, no trainer, setup, Strava, upload, FIT);
## 2 --run-seconds hard stop; 3 refused (session_in_progress, version_mismatch, missing_game,
## room_not_found, room_full, rate_limited); 4 the host left before the results.
## A client restarted with the same --profile-dir and --join reuses the saved reconnect token
## (NetSession): the host's plan/phase/snapshot for the running session opens it again and a new
## FIT starts from the rejoin.

signal done(reason: String, code: int)

const EXIT_OK := 0
const EXIT_ERROR := 1
const EXIT_TIMEOUT := 2
const EXIT_REFUSED := 3
const EXIT_HOST_LEFT := 4
## Waits, in platform seconds.
const UPLOAD_TIMEOUT_S := 150.0
const STRAVA_CONNECT_TIMEOUT_S := 90.0
const HOST_GRACE_S := 2.0
const TRACE_PERIOD_S := 1.0
## Event types in `event` batches that the platform itself sends (not game events). The
## GameHost prefixes its own with PLATFORM_EVENT_PREFIX ("wl.phase_started", "wl.lap_marker",
## "wl.finished"); the bare names are kept for older hosts.
const PLATFORM_EVENT_TYPES: Array[String] = [
	"phase_started",
	"phase",
	"phase_changed",
	"game_phase_changed",
	"results",
	"session_end",
	"session_state"
]
const PLATFORM_EVENT_PREFIX := "wl."
const WL_PHASE_STARTED := "wl.phase_started"

var services: AppServices = null
var config: AppScriptedConfig = null
var report: AppScriptedReport = AppScriptedReport.new()
var log_watch: AppLogWatch = null
## Install AppLogWatch with OS.add_logger (off in tests).
var install_logger: bool = true
## Prints one stdout line (tests capture it).
var out: Callable
## Where the GameHost puts the view and HUD in windowed runs (null: headless).
var view_parent: Node = null
var hud_parent: Node = null
var headless: bool = true
## False in tests: time advances only through step(dt).
var auto_process: bool = true

## "boot", "connecting", "lobby", "session", "results", "uploading", "closing", "done".
var phase: String = "boot"
## Platform seconds since start (sim-speed aware).
var clock: float = 0.0
var host: GameHost = null
var launcher: AppSessionLauncher = null
var session_config: Dictionary = {}
var local_peer: int = 0
var room: String = ""
var game_id: String = ""
var content_id: String = ""
var results: GameResults = null
var fit_path: String = ""
var ride_summary: Dictionary = {}
var strava_state: String = ""
var upload_requested: bool = false
## The latest upload state seen for this ride (Rides may start an upload by itself).
var upload_seen_state: String = ""
var upload_seen_detail: String = ""
var upload_deadline: float = -1.0
var strava_deadline: float = -1.0
var close_at: float = -1.0
var last_state: String = ""
var last_snapshot: Variant = null
## The newest `event` batch seq recorded (a batch is never recorded twice).
var _event_seq_seen: int = 0
var exit_code: int = -1
var exit_reason: String = ""
var _next_trace_t: float = 0.0
var _connected: bool = false


func _init() -> void:
	out = _print_line


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


static func _print_line(line: String) -> void:
	print(line)


## Begin: validate the flags, prepare the profile, trainer and Strava, then host or join.
func start() -> void:
	report.role = config.role if config != null else ""
	if config == null or not config.is_valid():
		var why := "; ".join(config.errors) if config != null else "no config"
		finish("error:flags: " + why, EXIT_ERROR)
		return
	if install_logger:
		log_watch = AppLogWatch.new()
		OS.add_logger(log_watch)
	if services.settings != null:
		services.settings.load_all()
	var profile := services.profile()
	if not profile.created:
		profile = AppTitleScreen.create_first_run_profile(services)
	if config.autopilot:
		profile.autopilot_default = true
	if config.strava_auto_upload:
		profile.strava_auto_upload = true
	if services.trainer != null:
		if services.trainer.device() == null:
			services.trainer.start()
		if services.trainer.device() == null:
			services.trainer.use_mock(config.mock_trainer if config.mock_trainer != "" else "erg")
	_connect_signals()
	if config.wants_strava_connect() and services.rides != null:
		if services.rides.strava_connected():
			strava_state = "connected"
		else:
			strava_state = "connecting"
			strava_deadline = STRAVA_CONNECT_TIMEOUT_S
			services.rides.strava_connect(config.strava_client_id, config.strava_client_secret)
	var net := services.net
	if net == null:
		finish("error:no_net", EXIT_ERROR)
		return
	phase = "connecting"
	if config.role == Wl.HOST:
		game_id = config.game_id
		if services.registry == null or not services.registry.has_game(game_id):
			finish("error:unknown_game:" + game_id, EXIT_ERROR)
			return
		var m := services.registry.manifest(game_id)
		content_id = AppLobbyModel.scripted_content(m, config.content_id, config.e2e)
		# One of the game's contents, or <scheme>:<value> for a scheme it lists (zwo:<path>).
		if not WlGameRegistry.content_allowed(m, content_id):
			finish("error:unknown_content:" + content_id, EXIT_ERROR)
			return
		_send_player_info(game_id)
		net.host_room(AppLobbyModel.max_players(m))
	else:
		_send_player_info("")
		net.join_room(config.join_code)


func _process(delta: float) -> void:
	if auto_process:
		step(delta * (config.sim_speed if config != null else 1.0))


## Advance platform time by dt seconds and run the checks that depend on it.
func step(dt: float) -> void:
	if phase == "done":
		return
	clock += dt
	if config != null and config.run_seconds > 0.0 and clock >= config.run_seconds:
		finish("run_seconds", EXIT_TIMEOUT)
		return
	match phase:
		"lobby":
			if config.role == Wl.HOST:
				try_start()
		"session":
			if clock >= _next_trace_t:
				_next_trace_t = clock + TRACE_PERIOD_S
				sample_trace()
		"uploading":
			_check_upload()
		"closing":
			if clock >= close_at:
				finish("complete", EXIT_OK)
	if (
		strava_state == "connecting"
		and services.rides != null
		and services.rides.strava_connected()
	):
		strava_state = "connected"
	if strava_state == "connecting" and strava_deadline >= 0.0 and clock >= strava_deadline:
		finish("error:strava_connect_timeout", EXIT_ERROR)


# --- signals -----------------------------------------------------------------------------------


func _connect_signals() -> void:
	if _connected:
		return
	_connected = true
	var net := services.net
	if net != null:
		net.state_changed.connect(_on_net_state)
		net.lobby_changed.connect(_on_lobby_changed)
		net.refused.connect(_on_refused)
		net.game_message.connect(_on_game_message)
	var bus := services.bus
	if bus != null:
		bus.session_state_changed.connect(_on_session_state)
		bus.phase_started.connect(_on_phase_started)
		bus.directive_applied.connect(_on_directive_applied)
		bus.results_ready.connect(_on_results_ready)
		bus.ride_saved.connect(_on_ride_saved)
		bus.upload_state_changed.connect(_on_upload_state)
		bus.strava_state_changed.connect(_on_strava_state)
	var app := services.app
	if app != null:
		# WlApp counts --run-seconds too and quits on its own (platform); its quit must end
		# like ours (exit 2, report, DONE line), whichever clock runs out first.
		app.run_seconds_exit_code = EXIT_TIMEOUT
		app.quitting.connect(_on_app_quitting)


func _disconnect_signals() -> void:
	if not _connected:
		return
	_connected = false
	var app := services.app
	if app != null and app.quitting.is_connected(_on_app_quitting):
		app.quitting.disconnect(_on_app_quitting)
	var net := services.net
	if net != null:
		for pair: Array in [
			[net.state_changed, _on_net_state],
			[net.lobby_changed, _on_lobby_changed],
			[net.refused, _on_refused],
			[net.game_message, _on_game_message]
		]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
	var bus := services.bus
	if bus != null:
		for pair: Array in [
			[bus.session_state_changed, _on_session_state],
			[bus.phase_started, _on_phase_started],
			[bus.directive_applied, _on_directive_applied],
			[bus.results_ready, _on_results_ready],
			[bus.ride_saved, _on_ride_saved],
			[bus.upload_state_changed, _on_upload_state],
			[bus.strava_state_changed, _on_strava_state]
		]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])


## App.quit() started outside this driver (--run-seconds on the App's clock, a window close):
## finish now, so the report and the DONE line are written before the tree quits.
func _on_app_quitting(code: int) -> void:
	if phase == "done":
		return
	var why := (
		services.app.exit_reason
		if services.app != null and services.app.exit_reason != ""
		else "quit"
	)
	finish(why, EXIT_TIMEOUT if why == "run_seconds" else code)


func _on_net_state(state: String, detail: String) -> void:
	var net := services.net
	match state:
		"hosting":
			if config.role != Wl.HOST or phase != "connecting":
				return
			room = net.room_code
			local_peer = net.local_peer if net.local_peer > 0 else Wl.HOST_PEER
			out.call("WATTLANDS_ROOM %s" % room)
			out.call("WATTLANDS_PEER %d" % local_peer)
			_setup_host_lobby()
			_enter_lobby()
		"joined":
			if config.role != Wl.CLIENT or phase != "connecting":
				return
			room = net.room_code if net.room_code != "" else config.join_code
			local_peer = net.local_peer
			out.call("WATTLANDS_PEER %d" % local_peer)
			_send_player_info(str(net.lobby.get("game_id", "")))
			net.set_ready(true)
			_enter_lobby()
		"error":
			if phase == "connecting" or phase == "lobby":
				finish("error:net:%s" % detail, EXIT_ERROR)


func _enter_lobby() -> void:
	phase = "lobby"
	report.room = room
	report.peer_id = local_peer
	set_state("lobby")
	if services.app != null:
		services.app.goto("lobby", {"scripted": true})
	if config.role == Wl.HOST:
		try_start()


func _setup_host_lobby() -> void:
	var net := services.net
	var m := services.registry.manifest(game_id)
	net.set_game(game_id, str(m.get("version", "")), content_id)
	var sc := (
		str(services.settings.get_value("scaling_mode", Wl.FAIR_FTP))
		if services.settings != null
		else Wl.FAIR_FTP
	)
	net.set_scaling(sc if Wl.SCALING_MODES.has(sc) else Wl.FAIR_FTP)
	net.set_setting("options", AppLobbyModel.resolve_game_options(services.registry, game_id, {}))
	if bool(m.get("bots", false)):
		net.set_setting("bot_ftp", services.profile().ftp_w)
	_send_player_info(game_id)
	net.set_ready(true)


func _send_player_info(gid: String) -> void:
	var popts: Dictionary = {}
	if gid != "" and services.registry != null and services.registry.has_game(gid):
		popts = AppLobbyModel.resolve_player_options(services.registry, gid, {})
	var sc := str(services.net.lobby.get("scaling", Wl.FAIR_FTP))
	var st := services.trainer.status() if services.trainer != null else ""
	services.net.set_local_player_info(
		AppLobbyModel.player_info(
			services.profile(), sc, popts, AppLobbyModel.installed_games(services.registry), st
		)
	)


func _on_lobby_changed(lobby: Dictionary) -> void:
	if config.role == Wl.CLIENT and phase == "lobby":
		var problem := AppLobbyModel.game_problem(services.registry, lobby)
		if problem != "":
			finish("refused:" + problem, EXIT_REFUSED)
			return
		var gid := str(lobby.get("game_id", ""))
		if gid != "" and gid != game_id:
			game_id = gid
			_send_player_info(gid)
		if not AppLobbyModel.is_ready(lobby, local_peer):
			services.net.set_ready(true)
	elif config.role == Wl.HOST and phase == "lobby":
		try_start()


## Host: start once --wait-peers humans (including this one) are in the lobby and all ready.
## Returns true when the session started.
func try_start() -> bool:
	if phase != "lobby" or config.role != Wl.HOST:
		return false
	var net := services.net
	var humans := AppLobbyModel.humans(net.lobby_slots())
	if humans.size() < config.wait_peers or not net.all_ready():
		return false
	var params := {"game_id": game_id, "content_id": content_id}
	launch(Wl.HOST, params)
	return true


func _on_refused(reason: String) -> void:
	if phase == "done":
		return
	if results != null or phase in ["results", "uploading", "closing"]:
		return
	if reason == "host_left":
		finish("host_left", EXIT_HOST_LEFT)
	else:
		finish("refused:" + reason, EXIT_REFUSED)


func _on_game_message(from: int, data: Dictionary) -> void:
	var type := str(data.get("type", ""))
	if config.role != Wl.CLIENT:
		return
	match type:
		"session_start":
			if phase == "lobby":
				launch(Wl.CLIENT, {"session_start": data.duplicate(true)})
		"plan", "phase", "snapshot":
			# A broadcast can beat the lobby to a restarted client; the host's catch-up follows it.
			if phase == "lobby" and str(services.net.lobby.get("game_id", "")) != "":
				launch(
					Wl.CLIENT,
					{"rejoin": true, "replay": [{"from": from, "data": data.duplicate(true)}]}
				)
			if type == "snapshot":
				last_snapshot = data.get("state", null)
		"event":
			_record_event_batch(data)


## A client records the shared sequence (docs/ARCHITECTURE.md: phase_started per rider and game
## events, in the host's emission order) straight from the host's `event` batches: each
## "wl.phase_started" becomes a phase_started for that rider, other platform events ("wl.*")
## are skipped, everything else is a game event. The host's own bus.phase_started and its game's
## game_event signal produce the same sequence on the host (see _on_phase_started).
func _record_event_batch(data: Dictionary) -> void:
	var seq := int(data.get("seq", 0))
	if seq > 0:
		if seq <= _event_seq_seen:
			return
		_event_seq_seen = seq
	for ev: Variant in data.get("events", []):
		if not (ev is Dictionary):
			continue
		var e: Dictionary = ev
		var t := str(e.get("type", ""))
		if t == WL_PHASE_STARTED:
			report.add_event(
				clock, "phase_started", int(e.get("peer", 0)), {"index": int(e.get("index", 0))}
			)
		elif t.begins_with(PLATFORM_EVENT_PREFIX) or PLATFORM_EVENT_TYPES.has(t):
			continue
		else:
			_record_game_event(e)


# --- session -----------------------------------------------------------------------------------


## Create and start the GameHost (HOST or CLIENT) through AppSessionLauncher.
func launch(role: String, params: Dictionary) -> void:
	if phase != "lobby":
		return
	phase = "session"
	var p := params.duplicate(true)
	p["sim_speed"] = config.sim_speed
	p["realtime"] = auto_process
	if config.has_seed:
		p["seed"] = config.seed
	launcher = AppSessionLauncher.create(services)
	session_config = launcher.build_config(role, p, view_parent, hud_parent, headless)
	if session_config.is_empty():
		phase = "setup_failed"
		finish("error:" + launcher.error, EXIT_ERROR)
		return
	game_id = str(session_config.get("game_id", ""))
	content_id = str(session_config.get("content_id", ""))
	local_peer = int(session_config.get("local_peer", local_peer))
	if role == Wl.HOST:
		services.net.mark_started()
	if services.app != null:
		services.app.goto("session", {"scripted": true, "role": role})
	host = services.make_game_host()
	host.name = "GameHost"
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(host)
	var err := host.setup(session_config)
	if err != "":
		phase = "setup_failed"
		finish("error:setup:" + err, EXIT_ERROR)
		return
	host.state_changed.connect(_on_host_state)
	host.session_finished.connect(_on_session_finished)
	if role == Wl.HOST and host.game != null:
		host.game.game_event.connect(_record_game_event)
	var rider := local_rider()
	if rider != null:
		rider.directive_applied.connect(_on_local_directive)
	_next_trace_t = clock
	services.set_menu_ticking(false)
	host.start()
	for r in AppSessionLauncher.replay_messages(p, services.net):
		services.net.game_message.emit(int(r["from"]), r["data"])


func local_rider() -> LocalRider:
	var riders: Dictionary = session_config.get("local_riders", {})
	return riders.get(local_peer, null)


## One 1 Hz trace entry from the local rider's governor status (telemetry as a fallback).
func sample_trace() -> void:
	var rider := local_rider()
	if rider == null:
		return
	var st: Dictionary = {}
	if rider.governor != null:
		st = rider.governor.status()
	if st.is_empty():
		var tm := rider.telemetry()
		st = {
			"mode": tm.mode,
			"applied_target_w": tm.applied_target_w,
			"applied_grade_pct": tm.applied_grade_pct,
			"clamped_by": tm.clamped_by,
			"rescue": tm.rescue,
			"afk": tm.afk,
			"applied_pct": 0.0,
			"warmup_active": false
		}
		if rider.slot != null and rider.slot.ftp > 0.0:
			st["applied_pct"] = 100.0 * float(tm.applied_target_w) / rider.slot.ftp
	report.add_trace(clock, st)


func set_state(state: String) -> void:
	if state == "" or state == last_state:
		return
	if last_state == "results" and state == "ended":
		# The GameHost tears down after the results (a client getting session_end while it still
		# uploads): the session reached its results, which is what final_state reports.
		return
	last_state = state
	out.call("WATTLANDS_STATE %s" % state)
	report.add_event(clock, "session_state", local_peer, {"state": state})


func _on_host_state(state: String) -> void:
	set_state(state)


func _on_session_state(state: String) -> void:
	set_state(state)


## The host records phase_started from its bus, in the order its event batches carry them; a
## client records them from those batches (_record_event_batch), so its own phase message, which
## arrives earlier, does not reorder the shared sequence.
func _on_phase_started(peer: int, index: int) -> void:
	if config != null and config.role == Wl.CLIENT:
		return
	report.add_event(clock, "phase_started", peer, {"index": index})


func _record_game_event(event: Dictionary) -> void:
	report.add_event(
		clock,
		"game_event",
		Wl.HOST_PEER,
		{"event_type": str(event.get("type", "")), "event": event.duplicate(true)}
	)


func _on_directive_applied(peer: int, record: Dictionary) -> void:
	report.add_directive(peer, record)


func _on_local_directive(record: Dictionary) -> void:
	report.add_directive(local_peer, record)


func _on_results_ready(r: GameResults) -> void:
	if results == null and r != null:
		results = r


func _on_ride_saved(path: String, summary: Dictionary) -> void:
	fit_path = path
	ride_summary = summary.duplicate(true)
	report.add_fit(path)


func _on_session_finished(r: GameResults) -> void:
	if phase != "session":
		return
	if r != null:
		results = r
	if results == null:
		# The session ended without GameResults (aborted, host gone): the run failed.
		finish("error:no_results", EXIT_ERROR)
		return
	report.add_event(
		clock,
		"results",
		local_peer,
		{
			"grade": results.grade if results != null else "",
			"session_id": results.session_id if results != null else ""
		}
	)
	set_state("results")
	phase = "results"
	_collect_fit()
	_after_results()


## The FIT of the local rider: the GameHost's, a ride_saved path, or finish the ride here.
func _collect_fit() -> void:
	if host != null and is_instance_valid(host):
		var paths := host.fit_paths()
		for k: Variant in paths.keys():
			if int(k) == local_peer and str(paths[k]) != "":
				fit_path = str(paths[k])
				report.add_fit(fit_path)
	if fit_path == "":
		var rider := local_rider()
		if rider != null and rider.recorder != null and rider.recorder.is_recording():
			fit_path = rider.finish_ride()
			report.add_fit(fit_path)
	if ride_summary.is_empty():
		ride_summary = AppSessionScreen.read_summary(local_rider(), fit_path)


func _after_results() -> void:
	if fit_path == "":
		finish("error:no_fit", EXIT_ERROR)
		return
	if config.strava_auto_upload:
		phase = "uploading"
		upload_deadline = clock + UPLOAD_TIMEOUT_S
		_check_upload()
		return
	_complete()


func _check_upload() -> void:
	if phase != "uploading":
		return
	if upload_seen_state in ["uploaded", "duplicate"]:
		report.add_upload(upload_seen_state, activity_id_from(upload_seen_detail))
		_complete()
		return
	if upload_seen_state in ["failed", "offline"]:
		report.add_upload(upload_seen_state, null)
		finish("error:upload_" + upload_seen_state, EXIT_ERROR)
		return
	if clock >= upload_deadline:
		report.add_upload("timeout", null)
		finish("error:upload_timeout", EXIT_ERROR)
		return
	if upload_requested:
		return
	if services.rides == null:
		finish("error:no_rides", EXIT_ERROR)
		return
	if not services.rides.strava_connected():
		# Wait only while a connect started by --strava-client-id/secret is still running;
		# --strava-auto-upload without a connection (none saved, none asked for) fails at once.
		if strava_state == "error" or strava_state != "connecting":
			finish("error:strava_not_connected", EXIT_ERROR)
		return
	upload_requested = true
	var s := ride_summary.duplicate(true)
	if not s.has("fit_path"):
		s["fit_path"] = fit_path
	services.rides.upload(fit_path, s)


func _on_upload_state(ride_id: String, state: String, detail: String) -> void:
	var want := str(ride_summary.get("ride_id", ""))
	if want != "" and ride_id != "" and ride_id != want:
		return
	if phase == "done":
		return
	upload_seen_state = state
	upload_seen_detail = detail
	upload_requested = true
	_check_upload()


## The Strava activity id in an upload detail ("12345", "activity 12345"), or null.
static func activity_id_from(detail: String) -> Variant:
	var digits := ""
	for ch in detail:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	return (
		int(digits) if digits != "" and digits.length() < 19 else (digits if digits != "" else null)
	)


func _on_strava_state(state: String, _detail: String) -> void:
	strava_state = state
	if state == "error" and config != null and config.wants_strava_connect() and phase != "done":
		finish("error:strava_connect", EXIT_ERROR)
	elif state == "connected" and phase == "uploading":
		_check_upload()


## Success: the host lingers HOST_GRACE_S so its last messages (results) reach the clients.
func _complete() -> void:
	if config.role == Wl.HOST:
		phase = "closing"
		close_at = clock + HOST_GRACE_S
	else:
		finish("complete", EXIT_OK)


# --- finish ------------------------------------------------------------------------------------


## Write the report, print WATTLANDS_DONE and quit with `code` (once).
func finish(reason: String, code: int) -> void:
	if phase == "done":
		return
	var was_session := phase == "session"
	phase = "done"
	if was_session and host != null and is_instance_valid(host) and not host.is_finished():
		host.end_session(reason)
	if host != null:
		_collect_fit()
	exit_reason = reason
	exit_code = code
	report.exit_reason = reason
	report.peer_id = local_peer
	report.room = room
	report.game_id = game_id
	report.content_id = content_id
	if log_watch != null:
		var c := log_watch.counts()
		report.script_errors = int(c["script_errors"])
		report.desync_warnings = int(c["desync_warnings"])
		report.errors = int(c["errors"])
	report.final_state = final_state()
	_disconnect_signals()
	if services.net != null and config != null and config.enabled:
		services.net.leave()
	if log_watch != null:
		OS.remove_logger(log_watch)
	done.emit(reason, code)
	services.quit(code, _write_and_announce)


func _write_and_announce() -> void:
	if config != null and config.report_path != "":
		report.write(config.report_path)
	out.call("WATTLANDS_DONE %s" % exit_reason)


func final_state() -> Dictionary:
	var st := {
		"phase_reached": last_state,
		"game_id": game_id,
		"content_id": content_id,
		"local_peer": local_peer,
		"room": room,
		"fit_path": fit_path
	}
	if results != null:
		st["grade"] = results.grade
		st["results"] = results.to_dict()
	var rider := local_rider()
	if rider != null:
		var tm := rider.telemetry()
		st["phase_index"] = tm.phase_index
		st["distance_m"] = tm.distance_m
	if (
		config != null
		and config.role == Wl.HOST
		and host != null
		and is_instance_valid(host)
		and host.game != null
	):
		# The last snapshot the clients got; calling game.snapshot() again would build a newer
		# one (Workout adds its timeline to every 20th) and advance the game's own count.
		var sent := host.last_snapshot()
		st["snapshot"] = sent.duplicate(true) if not sent.is_empty() else host.game.snapshot()
	elif last_snapshot != null:
		st["snapshot"] = last_snapshot
	return st
