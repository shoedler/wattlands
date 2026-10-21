class_name WlEventBus
extends Node
## Cross-module signals (BRIEF 6: EventBus signals instead of cross-module node paths).
## Contract, frozen after W0; additive changes only. The autoload `EventBus` is an
## instance of this class; in-process multi-peer simulations give each peer its own
## instance through GameContext.events, so signals never mix between peers.
## Peer ids are ints (host 1, clients 2.., bots negative). Runs with PROCESS_MODE_ALWAYS.

# --- App and profile ---------------------------------------------------------
## App state machine moved: "title", "first_run", "profile", "settings", "picker",
## "lobby", "session", "results", "quitting".
signal app_state_changed(state: String)
signal profile_changed
signal settings_changed(key: String)

# --- Input ---------------------------------------------------------------------
## A rebindable input action fired (Wl.ACTIONS), keyboard, controller or pedal-scan.
signal action_pressed(action: StringName)
## A pedal gesture fired for the local rider (Wl.GESTURES).
signal gesture(gesture_name: StringName)
## Panic (Backspace held 1 s, View+Menu, or UI): the governor goes safe at once.
signal panic_requested

# --- Trainer -------------------------------------------------------------------
## Trainer connection status: TrainerDevice.STATUS_* plus a human-readable detail.
signal trainer_status_changed(status: String, detail: String)
## Another app (Zwift, the Wahoo app) may hold control (Request Control 0x05 or status 0xFF).
signal trainer_control_lost(detail: String)
## The local rider's governor state changed: {mode, applied_target_w, applied_grade_pct,
## clamped_by, rescue, coasting, warmup, paused, gear}.
signal governor_status(peer_id: int, status: Dictionary)

# --- Network -------------------------------------------------------------------
## "offline", "connecting", "hosting", "joined", "reconnecting", "error".
signal net_state_changed(state: String, detail: String)
## The host's lobby_state changed (the full lobby_state message payload).
signal lobby_changed(lobby: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int, reason: String)
## The server or host refused or ended the session: "session_in_progress",
## "version_mismatch", "room_not_found", "room_full", "host_left", ...
signal session_refused(reason: String)

# --- Session (GameHost) -----------------------------------------------------------
## "lobby", "starting", "running", "paused", "cooldown", "results", "ended".
signal session_state_changed(state: String)
## A rider's plan phase started (by duration, max_s, end_phase or finished).
signal phase_started(peer_id: int, index: int)
## The game emitted finished(reason), or the plan ran out.
signal game_finished(reason: String)
signal rescue_changed(peer_id: int, active: bool)
signal afk_changed(peer_id: int, afk: bool)
## Solo pause (coasting rule 4.6.4, stop_5s, pause action) or resume.
signal paused_changed(paused: bool, reason: String)
## What a rider's governor did with a directive: {id, kind, requested: {...},
## applied: {...}, clamped_by: [...], refused: bool, reason: String, t: float}.
signal directive_applied(peer_id: int, record: Dictionary)
signal cadence_band_changed(peer_id: int, lo_rpm: float, hi_rpm: float)
signal power_band_changed(peer_id: int, lo_w: float, hi_w: float)
## The 5.5 roster arrived or changed (keyed by int peer id).
signal roster_changed(roster: Dictionary)
signal toast_requested(key: String, args: Variant)
signal banner_requested(key: String, args: Variant, seconds: float)
signal readout_changed(id: String, text: String)
signal results_ready(results: GameResults)
## The local rider's new unlocks after apply_progress.
signal unlocks_ready(unlocks: Array)
signal lap_marked(label: String)

# --- Rides and Strava --------------------------------------------------------------
## A ride was saved: FIT path and the JSON summary.
signal ride_saved(fit_path: String, summary: Dictionary)
## "queued", "uploading", "processing", "uploaded", "duplicate", "failed", "offline".
signal upload_state_changed(ride_id: String, state: String, detail: String)
## "disconnected", "connecting", "connected", "error".
signal strava_state_changed(state: String, detail: String)


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
