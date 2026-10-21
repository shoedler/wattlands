class_name GameModule
extends Node
## The Game SDK contract every game implements (BRIEF 3.6). Frozen after W0.
## Games extend it by class name (`extends GameModule`), never by path.
##
## Life cycle on every peer:
##   configure(ctx) -> build_effort_plans() (host/SOLO; validated by the PlanValidator)
##   -> make_view() and hud_spec() -> the session runs -> results() (host/SOLO)
##   -> apply_progress(results, ctx.progress) on every peer -> results screen.
## On the host or in solo play the GameHost calls sim_step(dt, frame) every 0.05 s of
## game sim time, through the appended cool-down (frame.phase kind COOLDOWN; directives
## are ignored then). Clients get apply_snapshot (10 Hz) and apply_event, plus
## client_predict for their own rider. local_intents runs on every peer every tick.
##
## Rules must be deterministic: pure classes with step(state, inputs, dt), only ctx.rng,
## never wall-clock time. The view only reads state.

## A FIT lap at this point (the ride recorder also laps every plan phase with lap = true
## and the start of the cool-down, so games that set `lap` on their phases never emit this
## for them).
signal lap_marker(label: String)
## Optional and informational, for games whose riders share one phase sequence. The
## platform never relies on it and never emits it; per-rider phase changes come from the
## GameHost as EventBus.phase_started(peer_id, index) and frame.phase.
signal phase_changed(index: int)
## The game is over (for everyone). The platform skips every rider to the cool-down.
signal finished(reason: String)
## A game event for every client (BRIEF 5.5 `event`). Emit it with send_event(); the
## GameHost batches events (at most 10 messages per second), delivers them in order to
## every client's apply_event(), and never calls apply_event on the host. Every event is a
## JSON-safe Dictionary with a "type" key.
signal game_event(event: Dictionary)

var ctx: GameContext = null


## Called once per session on every peer before anything else.
func configure(p_ctx: GameContext) -> void:
	ctx = p_ctx


## Host/SOLO: {peer_id (int): EffortPlan} for every rider in ctx.players (bots included).
func build_effort_plans() -> Dictionary:
	return {}


## Host/SOLO: advance the game by `dt` (always Wl.SIM_DT) with every rider's latest
## telemetry and phase. Change trainer load only through ctx.directives.
func sim_step(_dt: float, _frame: InputFrame) -> void:
	pass


## Host/SOLO: intents for a bot or an Autopilot rider, merged into its telemetry intents.
## Autopilot never changes effort targets.
func autopilot_intents(_peer_id: int) -> Array:
	return []


## Host/SOLO: a rider entered or left rescue (BRIEF 4.6.3). A stagger, never a wipe.
func on_rescue(_peer_id: int, _active: bool) -> void:
	pass


## Host/SOLO: a rider went AFK (coasting > 10 s in multiplayer, or dropped) or came back.
func on_afk(_peer_id: int, _afk: bool) -> void:
	pass


## Every peer, every tick: turn the local rider's input actions and pedal gestures into
## game intents (each tagged as the game likes, for example {"k": "cast", "gesture": "surge"}).
## Gestures arrive apart from actions, so a game can tell a surge from a key press.
func local_intents(_actions: Array[StringName], _gestures: Array[StringName]) -> Array:
	return []


## Host: the compact, JSON-safe state for clients (sent at 10 Hz). Ints stay ints only
## if declared in int_fields().
func snapshot() -> Dictionary:
	return {}


## Client: apply the host's latest snapshot.
func apply_snapshot(_snapshot: Dictionary) -> void:
	pass


## Client: apply one game event (see game_event).
func apply_event(_event: Dictionary) -> void:
	pass


## Client: predict the local rider between snapshots from local telemetry.
func client_predict(_dt: float, _local: Telemetry) -> void:
	pass


## Optional: dotted paths of int fields for Protocol.decode(). Keys: "snapshot" and each
## event "type"; values: Array of paths, "[]" standing for every array element, e.g.
## {"snapshot": ["tick", "r[][]"], "kill": ["id", "slot"]}.
func int_fields() -> Dictionary:
	return {}


## The presentation root. A 2D game returns a Node2D (placed in a PixelViewport at
## game.json `pixel_base`), a 3D game a Node3D. The view only reads state.
func make_view() -> Node:
	return Node2D.new()


## Which HUD kit widgets show and where, plus the game's own Controls.
func hud_spec() -> HudSpec:
	return HudSpec.new()


## Host/SOLO, once the game finished or the plan ended: grade, rows, XP, unlocks.
func results() -> GameResults:
	return GameResults.new()


## Every peer, once: update the local rider's ctx.progress from the results and return
## the local rider's new unlocks (ids). The platform saves the store afterwards.
func apply_progress(_results: GameResults, _progress: ProgressStore) -> Array:
	return []


## Optional, any peer, before configure(): a preview of `content_id` for the lobby's
## session preview: {"title": String, "total_s": float, "lines": Array[String]} (for example
## the .zwo importer's clamp list, BRIEF 3.7). {} shows nothing extra.
func session_preview(_content_id: String) -> Dictionary:
	return {}


## Helper: emit a game event for every client (see game_event).
func send_event(event: Dictionary) -> void:
	game_event.emit(event)
