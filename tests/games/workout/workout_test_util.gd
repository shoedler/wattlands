extends RefCounted
## Test helpers for Workout (preloaded; not a test script). Builds contexts, players, a fake
## HUD feed, synthetic InputFrames that follow a timeline, and a driver that rides a whole
## session through WorkoutGame.sim_step with synthetic riders.

const DT := 0.05
const CONTENT_DIR := "res://content/workout"


## Records every ctx.hud call: [{"fn": name, ...args}].
class FakeHud:
	extends HudFeed
	var calls: Array[Dictionary] = []

	func power_band(peer: int, lo_w: float, hi_w: float) -> void:
		calls.append({"fn": "power_band", "peer": peer, "lo": lo_w, "hi": hi_w})

	func teammate_status(peer: int, status: Dictionary) -> void:
		calls.append({"fn": "teammate_status", "peer": peer, "status": status})

	func toast(key: String, args: Variant = [], peer: int = 0) -> void:
		calls.append({"fn": "toast", "key": key, "args": args, "peer": peer})

	func banner(key: String, args: Variant = [], seconds: float = 3.0, peer: int = 0) -> void:
		calls.append({"fn": "banner", "key": key, "args": args, "seconds": seconds, "peer": peer})

	func readout(id: String, text: String) -> void:
		calls.append({"fn": "readout", "id": id, "text": text})

	func of(fn: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for c in calls:
			if c["fn"] == fn:
				out.append(c)
		return out


## A SessionStats double with fixed rows (for the ctx.stats precedence test).
class FixedStats:
	extends SessionStats
	var rows: Dictionary = {}

	func base_row(peer: int) -> Dictionary:
		var row := super.base_row(peer)
		if rows.has(peer):
			for k: Variant in rows[peer].keys():
				row[k] = rows[peer][k]
		return row


## Registers Workout's strings with the TranslationServer, as the GameRegistry does at
## startup. Returns the Translation to pass to unregister_strings().
static func register_strings() -> Translation:
	var tr := load("res://content/workout/strings.en.translation") as Translation
	if tr != null:
		TranslationServer.add_translation(tr)
	return tr


static func unregister_strings(tr: Translation) -> void:
	if tr != null:
		TranslationServer.remove_translation(tr)


## Humans get peers 1..n, bots -1..-m after them (slot order).
static func players(humans: int, bots: int = 0, ftp: float = 200.0) -> Array[PlayerSlot]:
	var out: Array[PlayerSlot] = []
	for i in humans:
		var s := PlayerSlot.new()
		s.peer_id = i + 1
		s.name = "Rider %d" % (i + 1)
		s.apply_look(i)
		s.ftp = ftp
		s.ftp_verified = true
		s.p_eff_per_w = 250.0 / ftp
		out.append(s)
	for j in bots:
		out.append(Bots.make_slot(j + 1, humans + j, ftp))
	return out


static func ctx(
	content_id: String,
	p_players: Array[PlayerSlot],
	role: String = Wl.SOLO,
	local_peer: int = 1,
	seed_value: int = 7
) -> GameContext:
	var c := GameContext.new()
	c.game_id = "workout"
	c.content_id = content_id
	c.players = p_players
	c.role = role
	c.local_peer = local_peer
	c.seed = seed_value
	c.rng = SeededRng.make(seed_value)
	c.directives = DirectiveSink.new()
	c.hud = FakeHud.new()
	c.intents = IntentSink.new()
	c.strings = GameStrings.new()
	c.progress = ProgressStore.open("workout", "")
	c.game_dir = "res://src/games/workout"
	c.content_dir = CONTENT_DIR
	c.assets_dir = "res://assets/workout"
	return c


static func game(
	content_id: String, p_players: Array[PlayerSlot], role: String = Wl.SOLO, local_peer: int = 1
) -> WorkoutGame:
	var g := WorkoutGame.new()
	g.configure(ctx(content_id, p_players, role, local_peer))
	return g


## Tick at which each phase of `timeline` starts (and the total as the last entry).
static func phase_ticks(timeline: Array[PlanPhase]) -> Array[int]:
	var out: Array[int] = []
	var t := 0.0
	for p in timeline:
		out.append(int(round(t / DT)))
		t += p.duration_s
	out.append(int(round(t / DT)))
	return out


static func phase_state(timeline: Array[PlanPhase], starts: Array[int], tick: int) -> PhaseState:
	var idx := 0
	while idx + 1 < timeline.size() and tick >= starts[idx + 1]:
		idx += 1
	var p := timeline[idx]
	var ps := PhaseState.new()
	ps.index = idx
	ps.kind = p.kind
	ps.mode = p.mode
	ps.elapsed_s = float(tick - starts[idx]) * DT
	ps.duration_s = p.duration_s
	ps.label = p.label
	ps.planned_pct = p.planned_pct_at(ps.elapsed_s) if p.mode == Wl.ERG else 0.0
	ps.remaining_s = maxf(p.duration_s - ps.elapsed_s, 0.0)
	ps.count = timeline.size()
	ps.plan_elapsed_s = float(tick) * DT
	return ps


## A compliant rider: ERG at the planned target (unverified factor applied), Rolling road at
## 90% FTP, sprints at 140% FTP for the first 10 s, cadence 90.
static func compliant(slot: PlayerSlot, p: PlanPhase, ps: PhaseState) -> Dictionary:
	var factor := 1.0 if slot.ftp_verified else 0.85
	if p.mode == Wl.ERG:
		var target := int(floor(ps.planned_pct / 100.0 * slot.ftp * factor))
		return {
			"power_w": float(target),
			"cadence_rpm": 90.0,
			"mode": Wl.ERG,
			"applied_target_w": target
		}
	if p.kind == Wl.FREE:
		var pw := 1.4 * slot.ftp if ps.elapsed_s < 10.0 else 0.8 * slot.ftp
		return {"power_w": pw, "cadence_rpm": 95.0, "mode": Wl.SIM, "applied_target_w": 0}
	return {"power_w": 0.9 * slot.ftp, "cadence_rpm": 88.0, "mode": Wl.SIM, "applied_target_w": 0}


static func telemetry(slot: PlayerSlot, values: Dictionary, tick: int) -> Telemetry:
	var t := Telemetry.new()
	t.peer_id = slot.peer_id
	t.t = float(tick) * DT
	t.power_w = float(values.get("power_w", 0.0))
	t.cadence_rpm = float(values.get("cadence_rpm", 0.0))
	t.p_eff_w = t.power_w * slot.p_eff_per_w
	t.ftp_pct = t.power_w / slot.ftp * 100.0
	t.mode = str(values.get("mode", Wl.ERG))
	t.applied_target_w = int(values.get("applied_target_w", 0))
	t.applied_grade_pct = float(values.get("applied_grade_pct", 0.0))
	t.rescue = bool(values.get("rescue", false))
	t.afk = bool(values.get("afk", false))
	t.connected = bool(values.get("connected", true))
	return t


## Rides `g` through its whole timeline (cool-down included unless stop_tick >= 0).
## `rider_fn(slot, phase, phase_state, tick) -> Dictionary` overrides the compliant rider.
## Returns every event the game emitted, in order.
static func ride(
	g: WorkoutGame, rider_fn: Callable = Callable(), stop_tick: int = -1
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var collect := func(e: Dictionary) -> void: events.append(e)
	g.game_event.connect(collect)
	var timeline := g.state.phases
	var starts := phase_ticks(timeline)
	var end_tick := starts[starts.size() - 1] if stop_tick < 0 else stop_tick
	for tick in end_tick:
		var frame := InputFrame.new()
		frame.tick = tick
		frame.t = float(tick) * DT
		for slot in g.ctx.players:
			var ps := phase_state(timeline, starts, tick)
			var p := timeline[ps.index]
			var values: Dictionary = (
				rider_fn.call(slot, p, ps, tick) if rider_fn.is_valid() else compliant(slot, p, ps)
			)
			frame.players[slot.peer_id] = telemetry(slot, values, tick)
			frame.phase[slot.peer_id] = ps
		g.sim_step(DT, frame)
	g.game_event.disconnect(collect)
	return events


## Every event of `type` in `events`.
static func of_type(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if str(e.get("type", "")) == type:
			out.append(e)
	return out


## Protocol.apply_int_fields semantics (docs/OWNERSHIP.md PR1) for the round-trip test:
## dotted paths, "[]" every array element, "{}" every dictionary value; only numeric leaves
## at a matched path are converted.
static func apply_int_fields(data: Variant, paths: Array) -> Variant:
	var out: Variant = data
	for path: Variant in paths:
		out = _convert(out, _tokens(str(path)))
	return out


static func _tokens(path: String) -> Array[String]:
	var out: Array[String] = []
	for part in path.split("."):
		var name := part
		var suffix := ""
		while name.ends_with("[]") or name.ends_with("{}"):
			suffix = name.substr(name.length() - 2) + suffix
			name = name.substr(0, name.length() - 2)
		if name != "":
			out.append(name)
		var i := 0
		while i < suffix.length():
			out.append(suffix.substr(i, 2))
			i += 2
	return out


static func _convert(node: Variant, tokens: Array[String]) -> Variant:
	if tokens.is_empty():
		if node is float and is_equal_approx(node, round(node)):
			return int(node)
		return node
	var head := tokens[0]
	var rest: Array[String] = []
	rest.assign(tokens.slice(1))
	if head == "[]":
		if node is Array:
			var arr: Array = node
			for i in arr.size():
				arr[i] = _convert(arr[i], rest)
		return node
	if head == "{}":
		if node is Dictionary:
			var d: Dictionary = node
			for k: Variant in d.keys():
				d[k] = _convert(d[k], rest)
		return node
	if node is Dictionary and (node as Dictionary).has(head):
		node[head] = _convert(node[head], rest)
	return node
