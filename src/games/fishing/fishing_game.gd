class_name FishingGame
extends GameModule
## Big Game Fishing (docs/games/fishing.md): co-op sport fishing for 1-4 riders, where the trainer
## is the rod. This module wires the pure parts to the platform: FishingContent (content),
## FishingPreroll and FishingPlanBuilder (plans), FishingRules (simulation, with
## FishingPullScheduler inside), FishingSnapshot (network), FishingResults (results, progress),
## FishingView and FishingHud (presentation). It never reaches the trainer except through
## ctx.directives. fish-module owns this file.
##
## Host / SOLO, every tick: one reused FishingLaneInput per slot from the frame (intents
## normalized and rate-limited to INTENTS_PER_S per rider; the summary intent sets the lane's
## records, XP and look), FishingRules.step, then the FishingStepOut in its documented order:
## directives, bands (also kept as the lane's published band), end_phase, events (send_event,
## fx_event, event toasts), the rules' own toasts, finished (once). 1 Hz: teammate_status.
## Clients: apply_snapshot (and the interpolation history), apply_event (ints cast, fx_event,
## the rider's own toasts), client_predict (only the local cadence marker).
##
## Event toasts follow one rule (docs/decisions/fishing.md "Event toasts"): team-wide ones
## (landed or trophy, double hookup, frenzy) go out from the host with peer 0 and reach every peer,
## so clients never raise them; a rider's own ones (hookup, strike miss, snap, thrown,
## replacement) are raised only by the peer whose lane it is: the host with ctx.local_peer, a
## client in apply_event. The host never sends a rider's own toast to another peer, so nothing is
## shown twice. Toasts the rules return under an event toast key are dropped (the module owns
## those).

## Every game event, on every rendering peer: the host and SOLO right where the event is sent,
## clients in apply_event (after FishingEvents.cast_ints). The view's effects and audio listen.
signal fx_event(event: Dictionary)

const TOAST_LANDED := "FISHING_TOAST_LANDED"
const TOAST_TROPHY := "FISHING_TOAST_TROPHY"
const TOAST_DOUBLE_HOOKUP := "FISHING_TOAST_DOUBLE_HOOKUP"
const TOAST_FRENZY := "FISHING_TOAST_FRENZY"
const TOAST_HOOKUP := "FISHING_TOAST_HOOKUP"
const TOAST_STRIKE_MISS := "FISHING_TOAST_STRIKE_MISS"
const TOAST_SNAP := "FISHING_TOAST_SNAP"
const TOAST_THROWN := "FISHING_TOAST_THROWN"
const TOAST_REPLACEMENT := "FISHING_TOAST_REPLACEMENT"
## Every key the module raises from events (the rules' toasts under these keys are dropped).
const EVENT_TOAST_KEYS: Array[String] = [
	TOAST_LANDED,
	TOAST_TROPHY,
	TOAST_DOUBLE_HOOKUP,
	TOAST_FRENZY,
	TOAST_HOOKUP,
	TOAST_STRIKE_MISS,
	TOAST_SNAP,
	TOAST_THROWN,
	TOAST_REPLACEMENT,
]
## Team-wide event toasts: the host sends them with peer 0.
const TEAM_EVENTS: Array[String] = [
	FishingEvents.LANDED, FishingEvents.DOUBLE_HOOKUP, FishingEvents.FRENZY
]
## A rider's own event toasts: raised on that rider's peer only.
const OWN_EVENTS: Array[String] = [
	FishingEvents.HOOKUP,
	FishingEvents.STRIKE_MISS,
	FishingEvents.SNAP,
	FishingEvents.THROWN,
	FishingEvents.REPLACEMENT,
]

## teammate_status text per lane state (FishingConst.ST_*).
const STATUS_KEYS: Array[String] = [
	"FISHING_STATUS_RIDE_OUT",
	"FISHING_STATUS_PICK",
	"FISHING_STATUS_REEL",
	"FISHING_STATUS_REEL",
	"FISHING_STATUS_STRIKE",
	"FISHING_STATUS_FIGHT",
	"FISHING_STATUS_LANDING",
	"FISHING_STATUS_IDLE",
	"FISHING_STATUS_HOME",
]
## The host refreshes the teammate chips once a second.
const STATUS_EVERY_TICKS := Wl.SIM_HZ

var content: FishingContent = null
var state: FishingState = null
## Client interpolation of the other lanes (the view reads it).
var history: FishingSnapHistory = FishingSnapHistory.new()
## Each lane's pre-rolled slots, in slot order (Array[FishingPlanSlot] each).
var slots: Array = []
## One reusable FishingLaneInput per slot, refilled every tick (no allocations per tick).
var _inputs: Array = []
## Per slot: the tick the intent rate window opened and the intents admitted in it.
var _rate_start: PackedInt32Array = PackedInt32Array()
var _rate_count: PackedInt32Array = PackedInt32Array()
## Highest look index per kind [line, canopy, trim, pennant] (summary intents are clamped to it).
var _cos_counts: Array[int] = [0, 0, 0, 0]
var _finished: bool = false


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
	_rate_start.resize(ctx.players.size())
	_rate_count.resize(ctx.players.size())
	_rate_start.fill(-1000000)
	_rate_count.fill(0)
	_cos_counts = FishingResults.cosmetic_counts(content)
	_send_summary()


## The local rider's summary (brief 2.8), once per peer: total XP, species records and the
## equipped look go to the host for record XP, unlocks and the lane's look. The local lane wears
## its look at once; the host's copy arrives with the intent.
func _send_summary() -> void:
	var s := FishingResults.summary_from(ctx.progress, content)
	var cos: Array[int] = []
	cos.assign(s["cosmetics"])
	var intent := FishingIntents.summary(int(s["xp"]), s["records"], cos)
	var me := local_lane()
	if me != null:
		_apply_summary(me, FishingIntents.normalize(intent))
	if ctx.intents != null:
		ctx.intents.send(intent)


## The local rider's lane (null before configure or for a peer outside the session).
func local_lane() -> FishingLaneState:
	if state == null or ctx == null:
		return null
	return state.lane_of_peer(ctx.local_peer)


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
	if frame.tick % STATUS_EVERY_TICKS == 0:
		_feed_status()


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
	if tm != null and not tm.intents.is_empty():
		inp.intents = _admit(inp, FishingIntents.normalize_tick(tm.intents), frame.tick)
	elif not inp.intents.is_empty():
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


## This tick's normalized intents of one rider, at most INTENTS_PER_S in any one-second window
## (the excess is dropped). A summary is applied to the lane here (records, XP, the look clamped
## to cosmetics.json) and never reaches the rules.
func _admit(inp: FishingLaneInput, intents: Array, tick: int) -> Array:
	var i := inp.slot
	if i < 0 or i >= _rate_start.size():
		return []
	if tick - _rate_start[i] >= Wl.SIM_HZ:
		_rate_start[i] = tick
		_rate_count[i] = 0
	var out: Array = []
	for n: Dictionary in intents:
		if n["k"] == FishingIntents.SUMMARY:
			_apply_summary(state.lane(i), n)  # consumed here: the module clamps the look
			continue
		if _rate_count[i] >= FishingConst.INTENTS_PER_S:
			continue
		else:
			_rate_count[i] += 1
		out.append(n)
	return out


## A normalized summary intent into the lane: total XP, records (kg) and the look, clamped to
## the items cosmetics.json has.
func _apply_summary(l: FishingLaneState, n: Dictionary) -> void:
	if l == null or n.get("k", "") != FishingIntents.SUMMARY:
		return
	l.summary_xp = int(n["xp"])
	l.records.clear()
	var rec: Dictionary = n["rec"]
	for id: String in rec:
		l.records[id] = int(rec[id]) / 10.0
	var cos: Array = n["cos"]
	for k in mini(cos.size(), l.cosmetics.size()):
		l.cosmetics[k] = clampi(int(cos[k]), 0, _cos_counts[k])


## Applies one FishingStepOut in the documented order.
func _apply(out: FishingStepOut) -> void:
	for d: Array in out.directives:
		ctx.directives.request(int(d[0]), EffortDirective.from_dict(d[1]))
	for b: Array in out.bands:
		ctx.directives.cadence_band(int(b[0]), float(b[1]), float(b[2]))
		var bl := state.lane_of_peer(int(b[0]))
		if bl != null:
			bl.pub_lo = roundi(float(b[1]))
			bl.pub_hi = roundi(float(b[2]))
	for peer in out.end_phase:
		ctx.directives.end_phase(peer)
	for e: Dictionary in out.events:
		send_event(e)
		fx_event.emit(e)
		_host_toast(e)
	for t: Array in out.toasts:
		if EVENT_TOAST_KEYS.has(str(t[0])):
			continue
		ctx.hud.toast(str(t[0]), t[1], int(t[2]))
	if out.finished != "" and not _finished:
		_finished = true
		finished.emit(out.finished)


## Host/SOLO: an event's toast for the right peers (team-wide: every peer; a rider's own: only
## when the lane is the host's own rider, drawn on the host alone).
func _host_toast(e: Dictionary) -> void:
	if ctx.hud == null:
		return
	var type := str(e.get("type", ""))
	if TEAM_EVENTS.has(type):
		var tt := toast_for(e)
		if not tt.is_empty():
			ctx.hud.toast(str(tt[0]), tt[1], Wl.ALL_PEERS)
	elif OWN_EVENTS.has(type) and _is_local_lane(e):
		var tt := toast_for(e)
		if not tt.is_empty():
			ctx.hud.toast(str(tt[0]), tt[1], ctx.local_peer)


func _is_local_lane(e: Dictionary) -> bool:
	var l := state.lane(int(e.get("l", -1))) if state != null else null
	return l != null and l.peer == ctx.local_peer


## [key, args] of an event's toast, or [] for an event without one.
func toast_for(e: Dictionary) -> Array:
	var l := int(e.get("l", -1))
	match str(e.get("type", "")):
		FishingEvents.LANDED:
			var key := (
				TOAST_TROPHY
				if int(e.get("grade", 0)) == FishingConst.GRADE_TROPHY
				else TOAST_LANDED
			)
			var kg := "%.1f" % (int(e.get("kg", 0)) / 10.0)
			var pts := int(e.get("points", 0))
			return [
				key,
				{
					"name": _rider_name(l),
					"species": _species(int(e.get("sp", -1))),
					"kg": kg,
					"points": pts
				}
			]
		FishingEvents.DOUBLE_HOOKUP:
			var lvl := int(e.get("lvl", 2))
			var on := maxi((e.get("lanes", []) as Array).size(), lvl)
			var mult := "%.1f" % FishingConst.hookup_mult(lvl)
			return [TOAST_DOUBLE_HOOKUP, {"count": on, "mult": mult}]
		FishingEvents.FRENZY:
			return [TOAST_FRENZY, {"name": _rider_name(l)}]
		FishingEvents.HOOKUP:
			return [TOAST_HOOKUP, {"species": _species(int(e.get("sp", -1)))}]
		FishingEvents.STRIKE_MISS:
			return [TOAST_STRIKE_MISS, {"species": _species(int(e.get("sp", -1)))}]
		FishingEvents.SNAP:
			return [TOAST_SNAP, []]
		FishingEvents.THROWN:
			return [TOAST_THROWN, []]
		FishingEvents.REPLACEMENT:
			return [TOAST_REPLACEMENT, {"species": _species(int(e.get("sp", -1)))}]
	return []


func _rider_name(slot: int) -> String:
	var l := state.lane(slot) if state != null else null
	var p := ctx.player(l.peer) if l != null else null
	return p.name if p != null else ""


func _species(sp: int) -> String:
	return FishingResults.species_name(sp, content, ctx.strings)


## Host, 1 Hz: every rider's chip (in band = EMA cadence inside the published band; the text says
## what the lane is doing).
func _feed_status() -> void:
	if ctx.hud == null:
		return
	for l in state.lanes:
		ctx.hud.teammate_status(
			l.peer, {"in_band": lane_in_band(l), "icon": "", "text": status_text(l)}
		)


## True while the lane's EMA cadence is inside its published band and play is on.
static func lane_in_band(l: FishingLaneState) -> bool:
	if l.rescue or l.afk or l.stale or l.cadence_stale or l.pub_hi <= 0:
		return false
	return l.cadence_ema >= l.pub_lo and l.cadence_ema <= l.pub_hi


## The chip text for a lane: species and distance in a fight, the lure in a reel, else the state.
func status_text(l: FishingLaneState) -> String:
	var key: String = STATUS_KEYS[clampi(l.state, 0, STATUS_KEYS.size() - 1)]
	match l.state:
		FishingConst.ST_FIGHT:
			return ctx.strings.t(key, [_species(l.fish.sp), roundi(l.fish.d)])
		FishingConst.ST_LANDING, FishingConst.ST_STRIKE:
			return ctx.strings.t(key, [_species(l.fish.sp)])
		FishingConst.ST_CAST, FishingConst.ST_REEL:
			return ctx.strings.t(key, [roundi(l.lure_d)])
	return ctx.strings.t(key)


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


## Clients: every event once, in the host's order, before that tick's snapshot.
func apply_event(event: Dictionary) -> void:
	if ctx == null:
		return
	var e := FishingEvents.cast_ints(event)
	fx_event.emit(e)
	if state == null or ctx.hud == null:
		return
	if OWN_EVENTS.has(str(e.get("type", ""))) and _is_local_lane(e):
		var tt := toast_for(e)
		if not tt.is_empty():
			ctx.hud.toast(str(tt[0]), tt[1])


## Clients: only the local cadence marker moves ahead of the next snapshot; the host owns the
## meters and everything else.
func client_predict(dt: float, local: Telemetry) -> void:
	var l := local_lane()
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
	return FishingResults.build(state, ctx.stats, ctx.players, content, ctx.strings)


func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	return FishingResults.apply_progress(res, progress, ctx.local_peer, content, ctx.content_id)
