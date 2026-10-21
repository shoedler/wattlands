class_name LocalRider
extends Node
## One rider's trainer stack on this machine (BRIEF 4.1): TrainerDevice -> SafetyGovernor
## -> telemetry, with the GestureRecognizer, W' balance, speed model, effort scaling and the
## ride recorder. One per local human rider and one per bot (bots on the host, with a
## MockTrainer "erg:compliance=1.0" and no recorder). Owned by platform; public API frozen
## after W0. Runs with PROCESS_MODE_ALWAYS and advances only through tick(dt).
##
## Per tick: device.tick(dt) -> new samples feed gestures, W' balance (on raw power), the
## governor (rescue/coasting/warm-up) and the recorder (1 Hz); the speed model integrates
## P_eff on the current applied grade; the governor ticks; telemetry() reflects the latest
## state. Gestures and intents accumulate until taken (take_gestures/take_intents), so a
## 5 Hz telemetry send never loses one.

signal telemetry_updated(telemetry: Telemetry)
signal gesture_detected(gesture_name: StringName)
signal rescue_changed(active: bool)
signal afk_changed(afk: bool)
## Coasting 10 s in SOLO (4.6.4) or a stop_5s gesture: the GameHost pauses the game clock.
signal pause_requested(reason: String)
signal directive_applied(record: Dictionary)

var peer_id: int = 0
var profile: RiderProfile = null
var slot: PlayerSlot = null
var device: TrainerDevice = null
var governor: SafetyGovernor = null
var gestures: GestureRecognizer = null
var wbal: WBalance = null
var speed: SpeedModel = null
## Null for bots and when recording is off.
var recorder: RideRecorderApi = null
var is_bot: bool = false


## Build the stack. options: {multiplayer (bool), scaling_mode (String), record (bool),
## game_id, content_id, utc_start_unix (int), seed (int), skip_warmup (bool)}.
func setup(_peer_id: int, _profile: RiderProfile, _slot: PlayerSlot, _device: TrainerDevice, _options: Dictionary = {}) -> void:
	pass


## The validated plan (cool-down appended) for the governor.
func set_plan(_plan: EffortPlan) -> void:
	pass


## Enter plan phase `index` (the GameHost's phase tracking, or a client's `phase` message).
## Laps the recorder when the phase has lap = true or is the cool-down.
func start_phase(_index: int) -> void:
	pass


## A directive for this rider (from the host's DirectiveSink or a `directive` message).
## Returns the governor's applied record.
func apply_directive(_directive: EffortDirective) -> Dictionary:
	return {}


func apply_course_grade(_grade_pct: float) -> void:
	pass


## Published cadence band (HUD and MockTrainer band policy; 0, 0 clears).
func set_cadence_band(_lo_rpm: float, _hi_rpm: float) -> void:
	pass


## Published power band (HUD gauge in SIM and MockTrainer erg policy; 0, 0 clears).
func set_power_band(_lo_w: float, _hi_w: float) -> void:
	pass


func set_game_paused(_paused: bool) -> void:
	pass


## Virtual gear shift (+1/-1) through the governor.
func shift(_delta: int) -> void:
	pass


func panic() -> void:
	pass


## Advance by dt platform seconds.
func tick(_dt: float) -> void:
	pass


## Latest telemetry (a fresh object each call; gestures/intents not included).
func telemetry() -> Telemetry:
	return Telemetry.new()


## Gestures since the last call.
func take_gestures() -> Array[StringName]:
	return []


## Queue a game intent from this rider (ctx.intents.send, local_intents).
func push_intent(_intent: Dictionary) -> void:
	pass


## Intents since the last call.
func take_intents() -> Array:
	return []


## Directive acks since the last call (for Telemetry.acks).
func take_acks() -> Array:
	return []


## A FIT lap from the game's lap_marker.
func lap(_label: String) -> void:
	pass


## Stop the recorder and write the FIT and summary. Returns the FIT path or "".
func finish_ride() -> String:
	return ""


## Governor shutdown (SIM flat, then Stop) and device release.
func shutdown() -> void:
	pass
