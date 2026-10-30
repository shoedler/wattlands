class_name SiegeRig
extends RefCounted
## A tiny driver for the pure Siege rules in tests: real content, real plans (with the platform's
## cool-down appended), a state and a tick counter. Riders ride `power_pct` of their planned
## target unless `power_w` overrides a peer; `intents` (peer -> normalized intents) go in on the
## next step only; `rescue` / `afk` hold the safety flags.

const F := preload("res://tests/games/siege/siege_fakes.gd")

var content: SiegeContent
var slots: Array[PlayerSlot]
var plans: Dictionary
var state: SiegeState
var tick: int = 0
var events: Array[Dictionary] = []
var power_pct: float = 100.0
var power_w: Dictionary = {}
## peer -> P_eff W override (default: power x the slot's p_eff_per_w).
var p_eff: Dictionary = {}
var intents: Dictionary = {}
var rescue: Dictionary = {}
var afk: Dictionary = {}
var connected: Dictionary = {}


func _init(
	shift: String = "short",
	humans: int = 1,
	bots: int = 0,
	rng_seed: int = 7,
	scaling: String = Wl.FAIR_FTP,
	content_patch: Callable = Callable()
) -> void:
	var files := SiegeContent.read_files()
	if content_patch.is_valid():
		content_patch.call(files)
	content = SiegeContent.from_dicts(files, shift)
	slots = F.make_slots(humans, bots)
	plans = {}
	for p in slots:
		plans[p.peer_id] = F.with_cooldown(SiegePlanBuilder.build(content.shift, p, shift))
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	state = SiegeRules.new_state(content, slots, scaling, rng)


## Plan time (s) at which phase `index` starts.
func phase_start(index: int) -> float:
	return F.phase_start(plans[slots[0].peer_id], index)


## Jumps the clock to `t` seconds (the next step sees whatever phase that is).
func goto(t: float) -> void:
	tick = roundi(t / Wl.SIM_DT)


## Steps `seconds` of game time (at least one tick); returns the events raised meanwhile.
func run(seconds: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i in maxi(roundi(seconds / Wl.SIM_DT), 1):
		out.append_array(step())
	return out


## One tick; the events are also appended to `events`.
func step() -> Array[Dictionary]:
	var out := SiegeRules.step(state, inputs(), Wl.SIM_DT)
	tick += 1
	intents = {}
	events.append_array(out)
	return out


func inputs() -> SiegeInputs:
	var f := InputFrame.new()
	f.tick = tick
	f.t = tick * Wl.SIM_DT
	for p in slots:
		var ph := F.phase_at(plans[p.peer_id], f.t)
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.power_w = float(
			power_w.get(p.peer_id, ph.planned_pct / 100.0 * p.ftp * power_pct / 100.0)
		)
		tm.p_eff_w = float(p_eff.get(p.peer_id, tm.power_w * p.p_eff_per_w))
		tm.cadence_rpm = 90.0
		tm.connected = bool(connected.get(p.peer_id, true))
		f.players[p.peer_id] = tm
		f.phase[p.peer_id] = ph
	return SiegeInputs.from_frame(f, slots, plans, intents, rescue, afk)


## The events of `type` raised so far (or in `list`).
func of_type(type: String, list: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events if list.is_empty() else list:
		if e["type"] == type:
			out.append(e)
	return out


## Sends one intent for `peer` on the next step.
func send(peer: int, raw: Dictionary) -> void:
	var list: Array = intents.get(peer, [])
	list.append(SiegeIntents.normalize(raw))
	intents[peer] = list


func rider(peer: int = 1) -> SiegeRiderState:
	return state.rider(peer)


## Jumps to `into_s` seconds into phase `index` and steps once (the state enters the phase).
func enter(index: int, into_s: float = 0.0) -> void:
	goto(phase_start(index) + into_s)
	step()


## Puts `peer` on `target` at once (no reconnect) and ends its zero-input fallbacks, so only the
## test's own intents move it.
func put(peer: int, target: int) -> void:
	var r := state.rider(peer)
	r.target = target
	r.reconnect_s = 0.0
	r.route_fallback = false
	r.shop_fallback = false


## Ends the zero-input fallbacks of every human, so Autopilot neither routes nor shops for them
## and only the test's own intents (and `put`) move the riders. Bots stay on Autopilot.
func manual() -> SiegeRig:
	for r in state.riders:
		if not r.is_bot:
			r.route_fallback = false
			r.shop_fallback = false
	return self


## A live enemy placed at `prog_m` (lateral `lat`); hp < 0: the type's full HP.
func spawn(type: int, prog_m: float, lat: float = 0.0, hp: float = -1.0) -> SiegeEnemyState:
	return SiegeKit.enemy(state, type, prog_m, lat, hp)
