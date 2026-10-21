class_name HudLayer
extends CanvasLayer
## The in-session HUD (BRIEF 3.9): builds the kit widgets and the game's Controls from a
## HudSpec, at native resolution above the game view. Owned by ui-hud; public API frozen
## after W0. Readable from 3 m: key numbers >= 48 px at 1080p.
## It reads from the session's WlEventBus (power_band_changed, cadence_band_changed,
## roster_changed, toast_requested, banner_requested, readout_changed, rescue_changed,
## phase_started) and from update() calls the GameHost makes every tick for the local rider.

## Build widgets for `spec`. `pixel_viewport` maps 2D Rect2i positions (art pixels) through
## its integer scale and letterbox offset; null for 3D games.
func build(_spec: HudSpec, _ctx: GameContext, _pixel_viewport: PixelViewport = null) -> void:
	pass


## Per-tick local data: the local rider's telemetry, current phase, and plan (timeline).
func update(_telemetry: Telemetry, _phase: PhaseState, _plan: EffortPlan) -> void:
	pass


## A HudFeed that draws on this layer only (the GameHost wraps it with network routing).
func local_feed() -> HudFeed:
	return HudFeed.new()


## Show the kit's warm-up or rescue banner state.
func set_safety_state(_warmup_active: bool, _rescue: bool, _paused: bool) -> void:
	pass
