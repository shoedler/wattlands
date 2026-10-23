class_name FishingGame
extends GameModule
## Big Game Fishing (docs/games/fishing.md): co-op sport fishing for 1-4 riders, where the trainer
## is the rod. This module wires the pure parts to the platform: FishingContent (content),
## FishingPreroll and FishingPlanBuilder (plans), FishingRules (simulation, with
## FishingPullScheduler inside), FishingSnapshot (network), FishingResults (results, progress),
## FishingView and FishingHud (presentation). It never reaches the trainer except through
## ctx.directives. G0 version; fish-module owns this file.

var content: FishingContent = null
var state: FishingState = null
## Client interpolation of the other lanes (the view reads it).
var history: FishingSnapHistory = FishingSnapHistory.new()
## Each lane's pre-rolled slots, in slot order (Array[FishingPlanSlot] each).
var slots: Array = []
## One reusable FishingLaneInput per slot, refilled every tick (no allocations per tick).
var _inputs: Array = []


## Every peer, first. Content goes through ctx.load_content_json so run_game_sim --override works.
func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	content = FishingContent.load_for(ctx, not ctx.is_authority())
	if not content.ok:
		return
	slots = []
	for p in ctx.players:
		slots.append(FishingPreroll.roll(content.trip, content.species, ctx.seed, p.slot_index))
	state = FishingRules.new_state(content, ctx.players, ctx.seed, slots)
	_inputs = []
	for p in ctx.players:
		var inp := FishingLaneInput.new()
		inp.peer = p.peer_id
		inp.slot = p.slot_index
		_inputs.append(inp)


## Host/SOLO: one plan per slot (no bots: game.json bots is false).
func build_effort_plans() -> Dictionary:
	var plans := {}
	if content == null or not content.ok:
		return plans
	for p in ctx.players:
		var reel := int(p.options.get("reel_pct", FishingConst.REEL_PCT_DEFAULT))
		plans[p.peer_id] = FishingPlanBuilder.build(content.trip, slots[p.slot_index], reel)
	return plans


## Host/SOLO, every 0.05 s of game time, through the cool-down too.
func sim_step(dt: float, frame: InputFrame) -> void:
	if state == null:
		return
	for inp: FishingLaneInput in _inputs:
		_fill_input(inp, frame)
	_apply(FishingRules.step(state, _inputs, dt))


func _fill_input(inp: FishingLaneInput, frame: InputFrame) -> void:
	var tm := frame.telemetry(inp.peer)
	var ph := frame.phase_of(inp.peer)
	inp.has_phase = ph != null
	if tm != null:
		inp.power_w = tm.power_w
		inp.cadence_rpm = tm.cadence_rpm
		inp.cadence_age_s = tm.cadence_age_s
		inp.age_s = tm.age_s
		inp.connected = tm.connected
		inp.applied_target_w = tm.applied_target_w
		inp.mode = tm.mode
		inp.rescue = tm.rescue
		inp.afk = tm.afk
		inp.intents = FishingIntents.normalize_tick(tm.intents) if not tm.intents.is_empty() else []
	else:
		inp.intents = []
	if ph != null:
		inp.phase_index = ph.index
		inp.phase_kind = ph.kind
		inp.phase_mode = ph.mode
		inp.phase_elapsed_s = ph.elapsed_s
		inp.phase_duration_s = ph.duration_s
		inp.phase_open_ended = ph.open_ended
		inp.phase_min_s = ph.min_s
		inp.phase_max_s = ph.max_s
		inp.phase_remaining_s = ph.remaining_s
		inp.plan_elapsed_s = ph.plan_elapsed_s
		inp.is_cooldown = ph.is_cooldown()


## Applies one FishingStepOut in the documented order.
func _apply(out: FishingStepOut) -> void:
	for d: Array in out.directives:
		ctx.directives.request(int(d[0]), EffortDirective.from_dict(d[1]))
	for b: Array in out.bands:
		ctx.directives.cadence_band(int(b[0]), float(b[1]), float(b[2]))
	for peer in out.end_phase:
		ctx.directives.end_phase(peer)
	for e: Dictionary in out.events:
		send_event(e)
	for t: Array in out.toasts:
		ctx.hud.toast(str(t[0]), t[1], int(t[2]))
	if out.finished != "":
		finished.emit(out.finished)


## Autopilot runs inside the rules for every lane that plays as Autopilot (bots, Autopilot on,
## and the zero-input fallback), so nothing is returned here (docs/decisions/fishing.md).
func autopilot_intents(_peer_id: int) -> Array:
	return []


func on_rescue(peer_id: int, active: bool) -> void:
	var l := state.lane_of_peer(peer_id) if state != null else null
	if l != null:
		l.rescue = active


func on_afk(peer_id: int, afk: bool) -> void:
	var l := state.lane_of_peer(peer_id) if state != null else null
	if l != null:
		l.afk = afk


## Every peer: the local rider's actions and gestures become intents, tagged by source.
func local_intents(actions: Array[StringName], gestures: Array[StringName]) -> Array:
	var out: Array = []
	if actions.has(&"left"):
		out.append(FishingIntents.spot(-1))
	if actions.has(&"right"):
		out.append(FishingIntents.spot(1))
	if gestures.has(Wl.G_SURGE):
		out.append(FishingIntents.confirm(FishingIntents.VIA_SURGE))
	elif actions.has(&"confirm"):
		out.append(FishingIntents.confirm(FishingIntents.VIA_ACTION))
	return out


func snapshot() -> Dictionary:
	return FishingSnapshot.encode(state) if state != null else {}


func apply_snapshot(snap: Dictionary) -> void:
	if state == null:
		return
	FishingSnapshot.apply(state, snap)
	history.push(state.t, state)


func apply_event(_event: Dictionary) -> void:
	pass


func client_predict(dt: float, local: Telemetry) -> void:
	var l := state.lane_of_peer(ctx.local_peer) if state != null else null
	if l != null and local != null:
		var k := 1.0 - exp(-dt / FishingConst.CADENCE_TAU_S)
		l.cadence_ema += (local.cadence_rpm - l.cadence_ema) * k


func int_fields() -> Dictionary:
	return FishingEvents.int_fields()


func make_view() -> Node:
	var view := FishingView.new()
	view.game = self
	return view


func hud_spec() -> HudSpec:
	return FishingHud.spec(self)


func results() -> GameResults:
	return FishingResults.build(state, ctx.stats, ctx.players, content)


func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	return FishingResults.apply_progress(res, progress, ctx.local_peer, content, ctx.content_id)
