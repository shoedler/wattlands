class_name WlApp
extends Node
## Autoload `App`: the app state machine and command-line entry (BRIEF 3.5, 3.9, 6).
## Owned by platform; public API frozen after W0. The app shell's main scene
## (src/app/main.tscn) listens to state_changed and shows the matching screen.
##
## States: "boot", "title", "first_run", "profile", "settings", "picker", "lobby",
## "session", "results", "quitting".
## Command line (CmdLine): --mock-trainer=<profile> uses a MockTrainer; --host creates a
## room; --join=<code> joins one; --game/--content/--seed choose the session; --autopilot
## sets Autopilot; --run-seconds quits after n seconds of platform time; --report writes a
## JSON report on exit; --profile-dir moves Paths.user_dir(). With --host or --join the app
## skips the menus (headless e2e peers) and starts as soon as the lobby is ready.
## Scripted peers (W2, docs/ARCHITECTURE.md "Scripted peers"): the app shell
## (src/app/scripted/) owns that flow. WlApp only reports is_scripted() and
## launch_options(), goes to the lobby state and shuts the riders down in quit(); it never
## hosts, joins, quits at --run-seconds on its own or writes the --report of a scripted
## peer (the shell's hard stop exits 2 and writes the full report).
## Processes whose main loop is not the app (GUT, tools/check_scripts.gd, the run_game_sim
## and screenshot drivers started with -s) never boot: WlApp stays in "boot", starts no
## trainer and never writes a report, so it can't overwrite a tool's report at the same path.
##
## Details (W1):
## - Boot runs only in the real app (a SceneTree without a script, so never under GUT,
##   check_scripts or a tool's -s driver): deferred from _ready, boot() calls
##   Settings.load_all(), TrainerService.start(), Rides.process_queue(), emits booted, then
##   goto("title"), or for a scripted peer goto("lobby", launch_options()); the app shell
##   drives the scripted flow from there. Tests call boot() on a private instance.
## - goto() accepts only the states above (push_error otherwise), sets state and params and
##   emits state_changed and EventBus.app_state_changed synchronously (a client's GameHost is
##   created in the same signal chain as session_start), and never leaves "quitting".
## - quit(code): goto("quitting"), emit quitting(code) (the app shell saves the ride and
##   writes the --report there), save any ride still recording, shut down every live
##   LocalRider through TrainerService.shutdown_all() (SIM flat, then Stop, BRIEF 4.6.9),
##   hand ticking back to the TrainerService (so the safe commands go out even if a GameHost
##   stops ticking), write a minimal --report if nobody wrote one, then get_tree().quit(code) - after
##   QUIT_GRACE_S of real time when a real trainer is connected, so the safe commands go
##   out. A window close request quits the same way; NOTIFICATION_CRASH and leaving the
##   tree without quit() shut the riders down at once.
## - (W4, NET-6) quit() while this peer hosts a room (NetSession role HOST, not offline, not
##   yet left) calls NetSession.leave() first, so the relay ends the room with host_left at
##   once (BRIEF 5.3, 5.5) instead of holding it 120 s as a dropped host; the tree then quits
##   after QUIT_GRACE_S of real time, so the relay transport can send the leave. A client
##   never leaves here: its saved reconnect token lets a restarted client rejoin.
## - --run-seconds=<n> (not scripted): an own SimClock (--sim-speed aware) quits with
##   run_seconds_exit_code (default 0) once n platform seconds have passed since boot;
##   exit_reason "run_seconds". The fallback --report is written for non-scripted runs only.

signal state_changed(state: String, params: Dictionary)
## Boot finished (settings loaded, trainer started, upload queue retried).
signal booted
## quit() started: save rides and write reports now, the trainer stack is still up.
signal quitting(exit_code: int)
## --run-seconds ran out; quit(run_seconds_exit_code) follows.
signal run_seconds_reached

const STATES: Array[String] = [
	"boot", "title", "first_run", "profile", "settings", "picker", "lobby", "session",
	"results", "quitting",
]
## Real seconds quit() waits with a real trainer connected (governor shutdown writes).
const QUIT_GRACE_S := 0.5

var state: String = "boot"
## Parameters of the current state (for example {"game_id": "workout"} for the lobby).
var params: Dictionary = {}
## Test and tool injections; null means the autoload.
var settings: WlSettings = null
var trainer_service: WlTrainerService = null
var rides: WlRides = null
var bus: WlEventBus = null
## The NetSession to leave on quit while hosting (W4); null means the autoload.
var net_session: WlNetSession = null
## Exit code when --run-seconds runs out (the app shell may set it for scripted peers).
var run_seconds_exit_code: int = 0
## Why the app quit: set it before quit(); "run_seconds" and "window_closed" are set here.
var exit_reason: String = ""
## The code passed to quit().
var exit_code: int = 0

var _booted: bool = false
var _quitting: bool = false
var _clock: SimClock = null
var _run_seconds: float = 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _is_app_main_loop():
		get_tree().set_auto_accept_quit(false)
		boot.call_deferred()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if exit_reason == "":
				exit_reason = "window_closed"
			quit(0)
		NOTIFICATION_CRASH:
			_shutdown_riders()


func _exit_tree() -> void:
	if _booted and not _quitting:
		_shutdown_riders()


func _process(delta: float) -> void:
	if not _booted or _quitting or _run_seconds <= 0.0 or _clock == null:
		return
	var n := _clock.advance(delta)
	for _i in n:
		_clock.step()
	if _clock.platform_time() + 1e-9 >= _run_seconds:
		if exit_reason == "":
			exit_reason = "run_seconds"
		run_seconds_reached.emit()
		quit(run_seconds_exit_code)


## Load settings, start the trainer, retry uploads, then show the title (or the lobby for a
## scripted peer). Runs once; the real app calls it deferred from _ready.
func boot() -> void:
	if _booted:
		return
	_booted = true
	var s := _settings()
	if s != null:
		s.load_all()
	var ts := _trainer_service()
	if ts != null:
		ts.start()
	var r := _rides()
	if r != null:
		r.process_queue()
	var spd := CmdLine.get_float("sim-speed", 1.0)
	_clock = SimClock.create(spd if spd > 0.0 else 1.0)
	# A scripted peer's hard stop is the app shell's (exit 2 and its full report).
	_run_seconds = 0.0 if is_scripted() else maxf(CmdLine.get_float("run-seconds", 0.0), 0.0)
	booted.emit()
	if is_scripted():
		goto("lobby", launch_options())
	else:
		goto("title")


func is_booted() -> bool:
	return _booted


func goto(new_state: String, p_params: Dictionary = {}) -> void:
	if not STATES.has(new_state):
		push_error("App: unknown state \"%s\"" % new_state)
		return
	if state == "quitting" and new_state != "quitting":
		push_warning("App: quitting; ignoring goto(\"%s\")" % new_state)
		return
	state = new_state
	params = p_params.duplicate(true)
	state_changed.emit(state, params.duplicate(true))
	var b := _bus()
	if b != null:
		b.app_state_changed.emit(state)


## True when started with --host or --join (automated or command-line sessions).
func is_scripted() -> bool:
	return CmdLine.has("host") or CmdLine.has("join")


## The session flags a scripted peer runs with: {scripted, role (Wl.HOST, Wl.CLIENT or ""),
## code (normalized --join code), game_id, content_id, seed, autopilot, mock_trainer,
## relay, wait_peers, run_seconds, report, sim_speed, e2e}.
func launch_options() -> Dictionary:
	var role := ""
	if CmdLine.has("host"):
		role = Wl.HOST
	elif CmdLine.has("join"):
		role = Wl.CLIENT
	var join := CmdLine.get_str("join", "")
	return {
		"scripted": is_scripted(),
		"role": role,
		"code": RoomCode.normalize(join) if join != "true" else "",
		"game_id": CmdLine.get_str("game", ""),
		"content_id": CmdLine.get_str("content", ""),
		"seed": CmdLine.get_int("seed", 0),
		"autopilot": CmdLine.get_bool("autopilot", false),
		"mock_trainer": CmdLine.get_str("mock-trainer", ""),
		"relay": CmdLine.get_str("relay", ""),
		"wait_peers": CmdLine.get_int("wait-peers", 0),
		"run_seconds": CmdLine.get_float("run-seconds", 0.0),
		"report": CmdLine.get_str("report", ""),
		"sim_speed": CmdLine.get_float("sim-speed", 1.0),
		"e2e": CmdLine.get_bool("e2e", false),
	}


## Platform seconds since boot on the App's own clock (what --run-seconds counts).
func platform_time() -> float:
	return _clock.platform_time() if _clock != null else 0.0


func is_quitting() -> bool:
	return _quitting


## Quit cleanly: governor shutdown on every local rider, ride saved, report written.
func quit(p_exit_code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	exit_code = p_exit_code
	goto("quitting", {"exit_code": p_exit_code})
	quitting.emit(p_exit_code)
	var left_room := _leave_hosted_room()
	_save_open_rides()
	var real_trainer := _real_trainer_connected()
	_shutdown_riders()
	# The service ticks the shut-down riders from here on, so the safe commands go out; the
	# riders are shut down first, so handing ticking back never re-sets one up.
	var ts := _trainer_service()
	if ts != null:
		ts.set_external_tick(false)
	_write_fallback_report()
	if (real_trainer or left_room) and is_inside_tree():
		get_tree().create_timer(QUIT_GRACE_S, true, false, true).timeout.connect(_quit_tree.bind(p_exit_code))
	else:
		_quit_tree(p_exit_code)


## Ends the process (tests override it).
func _quit_tree(code: int) -> void:
	if is_inside_tree():
		get_tree().quit(code)


func _shutdown_riders() -> int:
	var ts := _trainer_service()
	if ts != null:
		return ts.shutdown_all()
	var n := 0
	for r in LocalRider.live_riders():
		r.shutdown()
		n += 1
	return n


func _save_open_rides() -> void:
	for r in LocalRider.live_riders():
		if r.recorder != null and r.recorder.is_recording():
			r.finish_ride()


## NET-6: a host quitting the app leaves its room explicitly. True when it left one.
func _leave_hosted_room() -> bool:
	var n := _net()
	if n == null or n.offline or n.role != Wl.HOST:
		return false
	if n.state == WlNetSession.STATE_OFFLINE or n.state == WlNetSession.STATE_ERROR:
		return false
	n.leave()
	return true


func _real_trainer_connected() -> bool:
	var ts := _trainer_service()
	return ts != null and ts.device() != null and not ts.is_mock()


## A non-scripted run with --report=<path> and no report written yet gets a minimal one in
## the scripted-peer schema. A scripted peer's report is the app shell's alone.
func _write_fallback_report() -> void:
	if is_scripted():
		return
	var path := CmdLine.get_str("report", "")
	if path == "" or path == "true" or FileAccess.file_exists(path):
		return
	var opts := launch_options()
	var report := {
		"role": opts["role"], "peer_id": 0, "room": opts["code"], "game_id": opts["game_id"],
		"content_id": opts["content_id"], "exit_reason": exit_reason if exit_reason != "" else "quit",
		"exit_code": exit_code, "events": [], "directives": [], "trace": [], "fit_paths": [],
		"uploads": [], "desync_warnings": 0, "script_errors": 0,
		"final_state": {"app_state": state, "platform_time": platform_time()},
	}
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("App: can't write the report %s" % path)
		return
	f.store_string(JSON.stringify(report, "\t"))
	f.close()


func _is_app_main_loop() -> bool:
	return is_inside_tree() and get_tree().get_script() == null


func _settings() -> WlSettings:
	return settings if settings != null else AutoloadLookup.settings()


func _trainer_service() -> WlTrainerService:
	return trainer_service if trainer_service != null else AutoloadLookup.trainer_service()


func _rides() -> WlRides:
	return rides if rides != null else AutoloadLookup.rides()


func _bus() -> WlEventBus:
	return bus if bus != null else AutoloadLookup.bus()


func _net() -> WlNetSession:
	return net_session if net_session != null else AutoloadLookup.net()
