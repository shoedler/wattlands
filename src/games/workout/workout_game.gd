class_name WorkoutGame
extends GameModule
## Workout, the reference game (BRIEF 3.7): a group interval ride. Everyone rides the same
## timeline at their own % FTP: ERG intervals, FREE sprints on SIM flat with virtual gears,
## and Rolling road, one SIM phase on a procedural course. The plan does all the trainer
## work, so Workout sends no directives; it scores compliance (time in band), sprints and
## ride statistics, feeds the HUD and draws a side-scrolling ride view.
##
## Host/SOLO: WorkoutRules.step() advances the state each 0.05 s; its events go to clients
## (send_event) and become banners and toasts. Clients rebuild the state from snapshots and
## predict their own marker. Rules live in rules/, the HUD layout in hud/, the view in view/.

const GAME_ID := "workout"
## A snapshot carries the timeline every this many snapshots (2 s at 10 Hz), so a client
## that can't read the content itself (a .zwo only the host has) still gets it.
const TIMELINE_EVERY := 20

var session: WorkoutSession = null
var state: WorkoutState = WorkoutState.new()
## peer -> true while Workout has a power band published for that rider.
var _band_peers: Dictionary = {}
## peer -> the in-band value last sent with teammate_status.
var _status_sent: Dictionary = {}
var _snapshots: int = 0


func configure(p_ctx: GameContext) -> void:
	super.configure(p_ctx)
	session = WorkoutSession.load_for(ctx, not ctx.is_authority())
	state = WorkoutState.create(session, ctx.players)
	_band_peers.clear()
	_status_sent.clear()
	_snapshots = 0


## The same %FTP plan for every rider (bots included); the PlanValidator appends the
## cool-down. Returns {} when the session failed to load (its error was logged).
func build_effort_plans() -> Dictionary:
	var plans := {}
	if session == null:
		push_error("WorkoutGame: no valid session for content %s" % (ctx.content_id if ctx != null else ""))
		return plans
	for slot in ctx.players:
		plans[slot.peer_id] = session.build_plan()
	return plans


func sim_step(dt: float, frame: InputFrame) -> void:
	var events := WorkoutRules.step(state, frame, dt)
	for e in events:
		send_event(e)
		_announce(e)
	_hud_tick()


## Autopilot has nothing to choose in a session (BRIEF 3.7).
func autopilot_intents(_peer_id: int) -> Array:
	return []


## A stagger: the rider is out of band while rescued (until on_rescue(peer, false)); nothing
## else changes.
func on_rescue(peer_id: int, active: bool) -> void:
	var r := state.rider(peer_id)
	if r != null:
		r.rescue_cb = active
		r.rescue = active


## A stagger: the slot stays and keeps its scores; it is out of band while AFK (until
## on_afk(peer, false)).
func on_afk(peer_id: int, afk: bool) -> void:
	var r := state.rider(peer_id)
	if r != null:
		r.afk_cb = afk
		r.afk = afk or not r.connected


## Workout reads no input: everything is pedaling.
func local_intents(_actions: Array[StringName], _gestures: Array[StringName]) -> Array:
	return []


func snapshot() -> Dictionary:
	_snapshots += 1
	return WorkoutSnapshot.encode(state, (_snapshots - 1) % TIMELINE_EVERY == 0)


func apply_snapshot(snap: Dictionary) -> void:
	WorkoutSnapshot.apply(state, snap)
	var r := state.rider(ctx.local_peer) if ctx != null else null
	if r != null and ctx.hud != null:
		ctx.hud.readout(WorkoutHud.READOUT_TIB, WorkoutHud.pct_text(float(r.snap_tib_permille) / 1000.0))


func apply_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		WorkoutRules.EV_INTERVAL_START:
			state.phase_index = maxi(state.phase_index, int(event.get("i", -1)))
		WorkoutRules.EV_INTERVAL_END:
			state.last_interval = event.duplicate(true)
		WorkoutRules.EV_SPRINT:
			state.last_sprint = event.duplicate(true)


func client_predict(dt: float, local: Telemetry) -> void:
	if ctx != null:
		WorkoutRules.predict(state, ctx.local_peer, dt, local)


func int_fields() -> Dictionary:
	return {
		"snapshot": WorkoutSnapshot.INT_FIELDS.duplicate(),
		WorkoutRules.EV_INTERVAL_START: ["i"],
		WorkoutRules.EV_INTERVAL_END: ["i", "r[][]"],
		WorkoutRules.EV_SPRINT: ["i", "r[][]"],
	}


func make_view() -> Node:
	var view := WorkoutRideView.new()
	view.bind(self)
	return view


func hud_spec() -> HudSpec:
	return WorkoutHud.spec()


func results() -> GameResults:
	var players: Array[PlayerSlot] = []
	var stats: SessionStats = null
	if ctx != null:
		players = ctx.players
		stats = ctx.stats
	return WorkoutResults.build(state, stats, players)


func apply_progress(p_results: GameResults, progress: ProgressStore) -> Array:
	return WorkoutProgress.apply(p_results, progress, ctx.local_peer if ctx != null else 0)


## The lobby preview: total length and one line per phase, plus a .zwo's clamps.
func session_preview(content_id: String) -> Dictionary:
	var s := WorkoutSession.load_id(content_id, true)
	return s.preview() if s != null else {}


## The rider whose view this peer shows.
func view_peer() -> int:
	if ctx != null and state.riders.has(ctx.local_peer):
		return ctx.local_peer
	return state.order[0] if not state.order.is_empty() else 0


## The local rider's equipped pennant style ("" for the plain one).
func view_pennant() -> String:
	return WorkoutProgress.equipped(ctx.progress if ctx != null else null)


# --- host-side HUD -----------------------------------------------------------------


func _announce(e: Dictionary) -> void:
	if ctx == null or ctx.hud == null:
		return
	var index := int(e.get("i", -1))
	match str(e.get("type", "")):
		WorkoutRules.EV_INTERVAL_START:
			_publish_bands(index)
			var b := WorkoutHud.interval_banner(state, index, ctx.strings if ctx.strings != null else GameStrings.new())
			if not b.is_empty():
				ctx.hud.banner(str(b["key"]), b["args"], WorkoutHud.BANNER_S)
		WorkoutRules.EV_INTERVAL_END:
			var p := state.phase(index)
			if p == null or p.kind != Wl.WORK:
				return
			for row: Array in e.get("r", []):
				var peer := int(row[0])
				if _is_human(peer):
					ctx.hud.toast("WORKOUT_TOAST_INTERVAL_DONE", {"label": _t(p.label), "pct": int(round(float(row[1]) / 10.0))}, peer)
		WorkoutRules.EV_SPRINT:
			for row: Array in e.get("r", []):
				var peer := int(row[0])
				if not _is_human(peer):
					continue
				var key := "WORKOUT_TOAST_SPRINT_HIT" if int(row[3]) == 1 else "WORKOUT_TOAST_SPRINT_PEAK"
				ctx.hud.toast(key, {"w": int(row[1])}, peer)


## Power bands in SIM phases (BRIEF 3.6 power_band): Rolling road 76-105% FTP, sprints
## after the warm-up 120-160% FTP. Entering an ERG phase clears a band Workout set.
func _publish_bands(index: int) -> void:
	var p := state.phase(index)
	if p == null or p.kind == Wl.COOLDOWN:
		return
	for peer: int in state.order:
		var r := state.rider(peer)
		var band := WorkoutHud.band_for(state, index, r)
		if not band.is_empty():
			ctx.hud.power_band(peer, float(band[0]), float(band[1]))
			_band_peers[peer] = true
		elif _band_peers.get(peer, false):
			ctx.hud.power_band(peer, 0.0, 0.0)
			_band_peers.erase(peer)


func _hud_tick() -> void:
	if ctx == null or ctx.hud == null:
		return
	var next := state.phase(state.phase_index + 1)
	if WorkoutSession.is_sprint(next) and not state.sprint_warned.has(state.phase_index + 1):
		var left := state.phase_start_s(state.phase_index + 1) - state.plan_t
		if left <= WorkoutHud.SPRINT_WARN_S:
			state.sprint_warned[state.phase_index + 1] = true
			ctx.hud.toast("WORKOUT_TOAST_SPRINT_SOON", {"s": int(ceil(maxf(left, 0.0)))})
	var periodic := state.tick % WorkoutHud.STATUS_EVERY_TICKS == 0
	for peer: int in state.order:
		var r := state.rider(peer)
		if periodic or not _status_sent.has(peer) or bool(_status_sent[peer]) != r.in_band:
			_status_sent[peer] = r.in_band
			ctx.hud.teammate_status(peer, {"in_band": r.in_band, "icon": "", "text": WorkoutHud.pct_text(r.tib_fraction())})
	if state.tick % WorkoutHud.READOUT_EVERY_TICKS == 0:
		var me := state.rider(ctx.local_peer)
		if me != null:
			ctx.hud.readout(WorkoutHud.READOUT_TIB, WorkoutHud.pct_text(me.tib_fraction()))


func _is_human(peer: int) -> bool:
	var slot := ctx.player(peer)
	return slot != null and not slot.is_bot


func _t(key: String) -> String:
	return ctx.strings.t(key) if ctx.strings != null else key
