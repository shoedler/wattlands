class_name GameHost
extends Node
## Owns a session around a game on one peer (BRIEF 3.6): plan validation, the sim clock,
## routing directives to each rider's governor, warm-up and cool-down, pause, rescue and AFK
## callbacks, telemetry, snapshots and events over the network, the ride recorder and its
## laps, and results. Runs in SOLO, HOST and CLIENT roles. Owned by sdk-runtime; public API
## frozen after W0. Runs with PROCESS_MODE_ALWAYS.
##
## Host/SOLO per fixed step: tick every local rider (own rider + bots) -> merge remote
## telemetry (stale > 3 s keeps age_s; dropped peers connected = false, power/cadence 0) ->
## local_intents + autopilot_intents -> InputFrame -> game.sim_step(dt, frame) -> phase
## tracking per rider (duration, max_s, end_phase, finished -> skip to cool-down) with
## EventBus.phase_started(peer, index) and `phase` messages -> snapshot at 10 Hz, roster at
## 2 Hz, batched events -> after the cool-down: results() -> `results` to all ->
## apply_progress on every peer -> results screen.
## Client per fixed step: tick its LocalRider, apply plan/phase/directive messages to it,
## send telemetry (with intents, gestures, acks) at 5 Hz, apply snapshots/events, call
## client_predict.
## Real-time play advances by SimClock.advance(wall delta) in _process; headless runs call
## step() directly (GameSimRunner).

## "setup", "running", "paused", "cooldown", "results", "ended".
signal state_changed(state: String)
signal session_finished(results: GameResults)

var ctx: GameContext = null
var game: GameModule = null
var clock: SimClock = null
## peer_id -> LocalRider for riders simulated on this machine.
var local_riders: Dictionary = {}
var state: String = "setup"


## Prepare a session. config keys:
##   game_id, content_id, seed (int), role (Wl.SOLO/HOST/CLIENT), players
##   (Array[PlayerSlot]), local_riders ({peer: LocalRider}, bots included on the host),
##   local_peer (int), net (WlNetSession or null for SOLO), bus (WlEventBus; default the
##   autoload), options (Dictionary), scaling_mode, sim_speed (float, default 1),
##   headless (bool: no view/HUD nodes), view_parent (Node), hud_parent (Node),
##   record_rides (bool, default true), report (bool: collect the run_game_sim report data).
## Returns "" on success or an error string (invalid plan, unknown game, ...).
func setup(_config: Dictionary) -> String:
	return "not implemented"


## Host/SOLO: build and validate plans, send session_start/plans, start the clock.
## Client: wait for session_start/plan messages.
func start() -> void:
	pass


## One fixed 0.05 s platform step (headless loops); _process uses the clock in real time.
func step() -> void:
	pass


func pause(_reason: String = "user") -> void:
	pass


func resume() -> void:
	pass


func is_paused() -> bool:
	return false


func is_finished() -> bool:
	return false


## The final results (null until available).
func final_results() -> GameResults:
	return null


## Each local rider's FIT path after the session ({peer: path}).
func fit_paths() -> Dictionary:
	return {}


## Data for the run_game_sim report (events, phases, directives requested/applied,
## 1 Hz traces, snapshot hashes and sizes); empty unless setup(report = true).
func report_data() -> Dictionary:
	return {}


## The view root returned by make_view (inside its PixelViewport for 2D), or null headless.
func view_root() -> Node:
	return null


func end_session(_reason: String) -> void:
	pass
