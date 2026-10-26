class_name FishingGame
extends GameModule
## Turbo Reel: sport fishing for 1-4 riders (plus bots) on one shared ocean, where the trainer is
## the rod and the pedals drive the boat. Free Roam (roam_*) is competitive: drive out, cast at
## the fish you see, fight them, most points wins. Workouts (base_60, threshold, e2e_2min) keep a
## plan on an endless map, co-op. This module wires the pure parts to the platform:
## FishingContent (content), FishingPreroll and FishingPlanBuilder (plans), FishingRules
## (simulation: FishingBoat, FishingFight, FishingAutopilot, FishingPullScheduler),
## FishingSnapshot (network), FishingResults (results, progress) and the view and HUD (loaded by
## path: VIEW_SCRIPT, HUD_SCRIPT). It never reaches the trainer except through ctx.directives.
##
## Host / SOLO, every tick: one reused FishingRiderInput per slot from the frame (intents
## normalized and rate-limited to INTENTS_PER_S per rider; the summary intent sets the rider's
## records, XP and look), FishingRules.step, then the FishingStepOut in its documented order:
## replans, directives, grades, bands (also kept as the rider's published band), power bands,
## end_phase, events (send_event, fx_event, event toasts), the rules' own toasts, finished (once).
## 1 Hz: teammate_status. Clients: apply_snapshot (then snapshot_applied for the view's
## interpolation), apply_event (ints cast, fx_event, the rider's own toasts), client_predict (only
## the local cadence marker).
##
## Event toasts: catches (landed or trophy) and double hookups go out from the host with peer 0
## and reach every peer; a rider's own ones (hookup, snap, thrown, replacement) are raised only by
## the peer whose rider it is: the host with ctx.local_peer, a client in apply_event.

## Every game event, on every rendering peer: the host and SOLO right where the event is sent,
## clients in apply_event (after FishingEvents.cast_ints). The view's effects and audio listen.
signal fx_event(event: Dictionary)
## Clients: a snapshot was applied to `state` (the view keeps its interpolation history).
signal snapshot_applied(tick: int)

const VIEW_SCRIPT := "res://src/games/fishing/view/fishing_view.gd"
const HUD_SCRIPT := "res://src/games/fishing/hud/fishing_hud.gd"

const TOAST_LANDED := "FISHING_TOAST_LANDED"
const TOAST_TROPHY := "FISHING_TOAST_TROPHY"
const TOAST_DOUBLE_HOOKUP := "FISHING_TOAST_DOUBLE_HOOKUP"
const TOAST_HOOKUP := "FISHING_TOAST_HOOKUP"
const TOAST_SNAP := "FISHING_TOAST_SNAP"
const TOAST_THROWN := "FISHING_TOAST_THROWN"
const TOAST_REPLACEMENT := "FISHING_TOAST_REPLACEMENT"
const TOAST_TIME_UP := "FISHING_TOAST_TIME_UP"
## Team-wide event toasts: the host sends them with peer 0.
const TEAM_EVENTS: Array[String] = [
	FishingEvents.LANDED, FishingEvents.DOUBLE_HOOKUP, FishingEvents.TIME_UP
]
## A rider's own event toasts: raised on that rider's peer only.
const OWN_EVENTS: Array[String] = [
	FishingEvents.HOOKUP,
	FishingEvents.SNAP,
	FishingEvents.THROWN,
	FishingEvents.REPLACEMENT,
]

## teammate_status text per action (FishingConst.A_*).
const STATUS_KEYS: Array[String] = [
	"FISHING_STATUS_DRIVE",
	"FISHING_STATUS_DRIFT",
	"FISHING_STATUS_MENU",
	"FISHING_STATUS_CAST",
	"FISHING_STATUS_WAIT",
	"FISHING_STATUS_FIGHT",
	"FISHING_STATUS_LAND",
	"FISHING_STATUS_HOME",
]
## The host refreshes the teammate chips once a second.
const STATUS_EVERY_TICKS := Wl.SIM_HZ

var content: FishingContent = null
var state: FishingState = null
## Each rider's pre-rolled workout slots, in slot order (Array[FishingPlanSlot] each; [] in
## Free Roam).
var slots: Array = []
## One reusable FishingRiderInput per slot, refilled every tick (no allocations per tick).
var _inputs: Array = []
## Per slot: the tick the intent rate window opened and the intents admitted in it.
var _rate_start: PackedInt32Array = PackedInt32Array()
var _rate_count: PackedInt32Array = PackedInt32Array()
## Highest look index per kind [line, canopy, trim, pennant] (summary intents are clamped to it).
var _cos_counts: Array[int] = [0, 0, 0, 0]
var _finished: bool = false
## The local rider's latest telemetry (host/SOLO: this tick's frame; clients: client_predict's
## `local`), null before the first tick: the view and HUD read exact cadence and power from it
## (heart rate is zeroed in game frames; the HUD has its own path for it).
var local_tm: Telemetry = null


## Every peer, first. Content goes through ctx.load_content_json so run_game_sim --override works.
func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	content = FishingContent.load_for(ctx, not ctx.is_authority())
	if not content.ok:
		return
	slots = []
	var strategies: Array[int] = []
	for p in ctx.players:
		slots.append(FishingPreroll.roll(content.trip, content.species, ctx.seed, p.slot_index))
		var strat := -1
		if p.is_bot and content.trip.is_roam():
			strat = ctx.rng.randi_range(0, FishingAutopilot.STRATEGIES.size() - 1)
		strategies.append(strat)
	state = FishingRules.new_state(content, ctx.players, ctx.seed, slots, strategies)
	_inputs = []
	for p in ctx.players:
		var inp := FishingRiderInput.new()
		inp.peer = p.peer_id
		inp.slot = p.slot_index
		_inputs.append(inp)
	_rate_start.resize(ctx.players.size())
	_rate_count.resize(ctx.players.size())
	_rate_start.fill(-1000000)
	_rate_count.fill(0)
	_cos_counts = FishingResults.cosmetic_counts(content)
	_send_summary()


## The local rider's summary, once per peer: total XP, species records and the equipped look go
## to the host for record XP, unlocks and the rider's look. The local rider wears its look at
## once; the host's copy arrives with the intent.
func _send_summary() -> void:
	var s := FishingResults.summary_from(ctx.progress, content)
	var cos: Array[int] = []
	cos.assign(s["cosmetics"])
	var intent := FishingIntents.summary(int(s["xp"]), s["records"], cos)
	var me := own_rider()
	if me != null:
		_apply_summary(me, FishingIntents.normalize(intent))
	if ctx.intents != null:
		ctx.intents.send(intent)


## The local rider (null before configure or for a peer outside the session).
func own_rider() -> FishingRiderState:
	if state == null or ctx == null:
		return null
	return state.rider_of_peer(ctx.local_peer)


## Host/SOLO: one plan per slot, bots included.
func build_effort_plans() -> Dictionary:
	var plans := {}
	if content == null or not content.ok:
		return plans
	for p in ctx.players:
		if content.trip.is_roam():
			plans[p.peer_id] = FishingPlanBuilder.roam(state.play_end_t)
		else:
			var reel := int(p.options.get("reel_pct", FishingConst.REEL_PCT_DEFAULT))
			plans[p.peer_id] = FishingPlanBuilder.build(content.trip, slots[p.slot_index], reel)
	return plans


## Host/SOLO, every 0.05 s of game time, through the cool-down too.
func sim_step(dt: float, frame: InputFrame) -> void:
	if state == null:
		return
	local_tm = frame.telemetry(ctx.local_peer)
	for inp: FishingRiderInput in _inputs:
		_fill_input(inp, frame)
	_apply(FishingRules.step(state, _inputs, dt))
	if frame.tick % STATUS_EVERY_TICKS == 0:
		_feed_status()


func _fill_input(inp: FishingRiderInput, frame: InputFrame) -> void:
	var tm := frame.telemetry(inp.peer)
	var ph := frame.phase_of(inp.peer)
	inp.has_phase = ph != null
	if tm != null:
		inp.power_w = tm.power_w
		inp.p_eff_w = tm.p_eff_w
		inp.cadence_rpm = tm.cadence_rpm
		inp.cadence_age_s = tm.cadence_age_s
		inp.age_s = tm.age_s
		inp.connected = tm.connected
		inp.applied_target_w = tm.applied_target_w
		inp.mode = tm.mode
		inp.rescue = tm.rescue
		inp.afk = tm.afk
		inp.paused = tm.paused
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
## (the excess is dropped). A summary is applied to the rider here and never reaches the rules.
func _admit(inp: FishingRiderInput, intents: Array, tick: int) -> Array:
	var i := inp.slot
	if i < 0 or i >= _rate_start.size():
		return []
	if tick - _rate_start[i] >= Wl.SIM_HZ:
		_rate_start[i] = tick
		_rate_count[i] = 0
	var out: Array = []
	for n: Dictionary in intents:
		if n["k"] == FishingIntents.SUMMARY:
			_apply_summary(state.rider(i), n)
			continue
		if _rate_count[i] >= FishingConst.INTENTS_PER_S:
			continue
		_rate_count[i] += 1
		out.append(n)
	return out


## A normalized summary intent into the rider: total XP, records (kg) and the look, clamped to
## the items cosmetics.json has.
func _apply_summary(r: FishingRiderState, n: Dictionary) -> void:
	if r == null or n.get("k", "") != FishingIntents.SUMMARY:
		return
	r.summary_xp = int(n["xp"])
	r.records.clear()
	var rec: Dictionary = n["rec"]
	for id: String in rec:
		r.records[id] = int(rec[id]) / 10.0
	var cos: Array = n["cos"]
	for k in mini(cos.size(), r.cosmetics.size()):
		r.cosmetics[k] = clampi(int(cos[k]), 0, _cos_counts[k])


## Applies one FishingStepOut in the documented order.
func _apply(out: FishingStepOut) -> void:
	for rp: Array in out.replans:
		ctx.directives.replan(int(rp[0]), rp[1])
	for d: Array in out.directives:
		ctx.directives.request(int(d[0]), EffortDirective.from_dict(d[1]))
	for g: Array in out.grades:
		ctx.directives.course_grade(int(g[0]), float(g[1]))
	for b: Array in out.bands:
		ctx.directives.cadence_band(int(b[0]), float(b[1]), float(b[2]))
	if ctx.hud != null:
		for pb: Array in out.power_bands:
			ctx.hud.power_band(int(pb[0]), float(pb[1]), float(pb[2]))
	for peer in out.end_phase:
		ctx.directives.end_phase(peer)
	for e: Dictionary in out.events:
		send_event(e)
		fx_event.emit(e)
		_host_toast(e)
	if ctx.hud != null:
		for t: Array in out.toasts:
			ctx.hud.toast(str(t[0]), t[1], int(t[2]))
	if out.finished != "" and not _finished:
		_finished = true
		finished.emit(out.finished)


## Host/SOLO: an event's toast for the right peers (team-wide: every peer; a rider's own: only
## when the rider is the host's own).
func _host_toast(e: Dictionary) -> void:
	if ctx.hud == null:
		return
	var type := str(e.get("type", ""))
	if TEAM_EVENTS.has(type):
		var tt := toast_for(e)
		if not tt.is_empty():
			ctx.hud.toast(str(tt[0]), tt[1], Wl.ALL_PEERS)
	elif OWN_EVENTS.has(type) and _is_own_rider(e):
		var tt := toast_for(e)
		if not tt.is_empty():
			ctx.hud.toast(str(tt[0]), tt[1], ctx.local_peer)


func _is_own_rider(e: Dictionary) -> bool:
	var r := state.rider(int(e.get("l", -1))) if state != null else null
	return r != null and r.peer == ctx.local_peer


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
		FishingEvents.HOOKUP:
			return [TOAST_HOOKUP, {"species": _species(int(e.get("sp", -1)))}]
		FishingEvents.SNAP:
			return [TOAST_SNAP, []]
		FishingEvents.THROWN:
			return [TOAST_THROWN, []]
		FishingEvents.REPLACEMENT:
			return [TOAST_REPLACEMENT, {"species": _species(int(e.get("sp", -1)))}]
		FishingEvents.TIME_UP:
			return [TOAST_TIME_UP, []]
	return []


func _rider_name(slot: int) -> String:
	var r := state.rider(slot) if state != null else null
	var p := ctx.player(r.peer) if r != null else null
	return p.name if p != null else ""


func _species(sp: int) -> String:
	return FishingResults.species_name(sp, content, ctx.strings)


## Host, 1 Hz: every rider's chip (in band = EMA cadence inside the published band; the text says
## what the rider is doing).
func _feed_status() -> void:
	if ctx.hud == null:
		return
	for r in state.riders:
		ctx.hud.teammate_status(
			r.peer, {"in_band": rider_in_band(r), "icon": "", "text": status_text(r)}
		)


## True while the rider's EMA cadence is inside its published band and play is on.
static func rider_in_band(r: FishingRiderState) -> bool:
	if r.rescue or r.is_afk() or r.cadence_stale or r.pub_hi <= 0:
		return false
	return r.cadence_ema >= r.pub_lo and r.cadence_ema <= r.pub_hi


## The chip text for a rider: the species in a fight or wait, else the action.
func status_text(r: FishingRiderState) -> String:
	var key: String = STATUS_KEYS[clampi(r.action, 0, STATUS_KEYS.size() - 1)]
	match r.action:
		FishingConst.A_FIGHT:
			return ctx.strings.t(key, [_species(r.fish.sp), roundi(r.fish.d)])
		FishingConst.A_LAND, FishingConst.A_CAST, FishingConst.A_WAIT:
			return ctx.strings.t(key, [_species(r.target_sp)])
	return ctx.strings.t(key)


## Autopilot runs inside the rules for every rider that plays as Autopilot (bots and Autopilot
## on), so nothing is returned here.
func autopilot_intents(_peer_id: int) -> Array:
	return []


func on_rescue(peer_id: int, active: bool) -> void:
	var r := state.rider_of_peer(peer_id) if state != null else null
	if r != null:
		r.rescue = active


func on_afk(peer_id: int, afk: bool) -> void:
	var r := state.rider_of_peer(peer_id) if state != null else null
	if r != null:
		r.afk = afk


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
	if FishingSnapshotSchema.check(snap) != "":
		push_warning("fishing: snapshot ignored: %s" % FishingSnapshotSchema.check(snap))
		return
	FishingSnapshot.apply(state, snap)
	snapshot_applied.emit(state.tick)


## Clients: every event once, in the host's order, before that tick's snapshot.
func apply_event(event: Dictionary) -> void:
	if ctx == null:
		return
	var e := FishingEvents.cast_ints(event)
	fx_event.emit(e)
	if state == null or ctx.hud == null:
		return
	if OWN_EVENTS.has(str(e.get("type", ""))) and _is_own_rider(e):
		var tt := toast_for(e)
		if not tt.is_empty():
			ctx.hud.toast(str(tt[0]), tt[1])


## Clients: only the local cadence marker moves ahead of the next snapshot; the host owns the
## boat, the meters and everything else.
func client_predict(dt: float, local: Telemetry) -> void:
	local_tm = local
	var r := own_rider()
	if r != null and local != null:
		var k := 1.0 - exp(-dt / FishingConst.CADENCE_TAU_S)
		r.cadence_ema += (local.cadence_rpm - r.cadence_ema) * k


func int_fields() -> Dictionary:
	return FishingEvents.int_fields()


func make_view() -> Node:
	var script: GDScript = load(VIEW_SCRIPT)
	if script == null:
		return Node2D.new()
	var view: Node = script.new()
	view.set("game", self)
	return view


func hud_spec() -> HudSpec:
	var script: GDScript = load(HUD_SCRIPT)
	if script == null:
		return HudSpec.new()
	return script.call("spec", self)


func results() -> GameResults:
	return FishingResults.build(state, ctx.stats, ctx.players, content, ctx.strings)


func apply_progress(res: GameResults, progress: ProgressStore) -> Array:
	return FishingResults.apply_progress(res, progress, ctx.local_peer, content, ctx.content_id)
