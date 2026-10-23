class_name SiegeHeadlessSim
extends RefCounted
## Brief 4's rules-level simulation: steps the pure rules (SiegeRules.step) with synthetic riders
## and no platform, GameHost, ctx or scene. Tests use it for T2, the Breach and Overdrive cases
## and S8 (tests/games/siege/sim/test_siege_rules_sim.gd).
##
## What it plays, per tick (0.05 s, the platform's sim clock):
##   - each rider's plan comes from SiegePlanBuilder.build_all (the wave offset in the slot's
##     options) with the platform's cool-down appended (SiegeFakes.with_cooldown), and its
##     InputFrame phase from SiegeFakes.phase_at;
##   - a synthetic rider rides its planned ERG target x compliance (no lag, no fatigue), 0 W for
##     a `zero` rider (AFK after afk_after_s, like the HOST's 10 s coasting rule), or
##     `od_pct` % of FTP while its Overdrive is ACTIVE (the governor's SIM block; MockTrainer's
##     `sim_pct`);
##   - intents go through SiegeIntentLimiter like on the host: `route` (a pad number, "gen",
##     "hot") is sent once at tick 0 (a deliberate route ends the Autopilot routing fallback);
##     `surge_every_s` sends an overdrive intent via "surge" every N seconds, `action_at` via
##     "action" at the given game times; any extra intents come from `intents_at`;
##   - after the step, Overdrive requests are answered like the module would: accepted with a
##     fresh directive id (SiegeOverdrive.on_request_result), or refused with `od_refuse`.
##
## Synthetic riders send no manual route or buy intents, so (as in run_game_sim) the rules'
## Autopilot routes and shops for them unless `route` is set.
##
## Everything is observable afterwards: `events_log` (every event with its game time), `stats`
## (enemy and queue maxima, the largest snapshot, earnings in wave phases), `state`.

const DT := Wl.SIM_DT


class Rider:
	extends RefCounted
	var ftp: float = 200.0
	var verified: bool = true
	## The wave offset player option (-10..+5).
	var offset: int = 0
	var bot: bool = false
	## Fraction of the planned ERG target that is ridden (MockTrainer's compliance).
	var compliance: float = 1.0
	## 0 W from t = 0; AFK after afk_after_s.
	var zero: bool = false
	var afk_after_s: float = 10.0
	## "" (Autopilot decides), "gen", "hot" or a pad number as a string: one route intent at tick 0.
	var route: String = ""
	## > 0: an overdrive intent via "surge" every N s (the surge profile), first at N.
	var surge_every_s: float = 0.0
	## Overdrive intents via "action" (ability_1) at these game times.
	var action_at: Array[float] = []
	## One manual (non-auto) buy intent at tick 1 ends the Autopilot shop fallback, so the rider
	## buys nothing on its own (the refused repair costs nothing).
	var manual_shop: bool = false
	## % FTP ridden while Overdrive is ACTIVE (the sim_pct of the surge profile).
	var od_pct: float = 130.0
	## [[from_s, to_s]]: the rider is in rescue (on_rescue true) in these windows.
	var rescue_windows: Array = []
	## game tick -> Array of raw intents to send on that tick.
	var intents_at: Dictionary = {}
	## -1: derive from the scaling mode (FAIR_FTP: 250 / FTP).
	var p_eff_per_w: float = -1.0
	## Optional Callable(t: float, planned_w: float) -> float replacing the ridden power.
	var power_fn: Callable = Callable()

	## A rider from a Dictionary of the fields above.
	static func make(spec: Dictionary = {}) -> Rider:
		var r := Rider.new()
		for k: String in spec:
			if k == "action_at":
				r.action_at.assign(spec[k])
			elif k in r:
				r.set(k, spec[k])
			else:
				push_error("SiegeHeadlessSim.Rider: unknown field %s" % k)
		return r


class Logged:
	extends RefCounted
	var t: float = 0.0
	var tick: int = 0
	var event: Dictionary = {}


var content: SiegeContent = null
var shift_id: String = ""
var slots: Array[PlayerSlot] = []
var riders: Array[Rider] = []
var plans: Dictionary = {}
var state: SiegeState = null
var tick: int = 0
## Every event the rules (and the Overdrive request answers) returned, in order.
var events_log: Array[Logged] = []
## Seconds of the plan with the cool-down appended.
var total_s: float = 0.0
## Answer Overdrive requests with this refusal reason ("" accepts them).
var od_refuse: String = ""
## Take a snapshot size every N ticks (0: never); the encode costs time.
var snapshot_every: int = 2

var stats: Dictionary = {
	"max_alive": 0,
	"max_queue": 0,
	"max_snapshot_bytes": 0,
	"snapshots": 0,
	"spawned": false,
	"wave_seconds": 0.0,
	"od_directives": 0,
	"steps": 0,
}
## peer -> denarii earned (generator + bounties) while the phase role was a wave.
var wave_earned: Dictionary = {}
## peer -> [generator, bounty] denarii earned while the phase role was a wave.
var wave_earned_parts: Dictionary = {}

var _limiter := SiegeIntentLimiter.new()
var _next_surge: Dictionary = {}
var _next_directive_id: int = 1
var _prev_earned: Dictionary = {}
var _afk_since: Dictionary = {}

# --- construction --------------------------------------------------------------------------------


## `specs`: one Dictionary (or Rider) per rider, slot order. `opts`: {"patches": {file: merge
## patch}, "seed": int, "scaling_mode": String, "snapshot_every": int, "od_refuse": String}.
static func create(p_shift_id: String, specs: Array, opts: Dictionary = {}) -> SiegeHeadlessSim:
	var sim := SiegeHeadlessSim.new()
	sim.shift_id = p_shift_id
	var files := patched_files(opts.get("patches", {}))
	sim.content = SiegeContent.from_dicts(files, p_shift_id)
	if not sim.content.ok():
		push_error("SiegeHeadlessSim content: %s" % [sim.content.errors])
	var mode: String = str(opts.get("scaling_mode", Wl.FAIR_FTP))
	for i in specs.size():
		var spec: Variant = specs[i]
		var r: Rider = spec if spec is Rider else Rider.make(spec)
		sim.riders.append(r)
		sim.slots.append(_slot(i, r, mode))
	sim.plans = {}
	var built := SiegePlanBuilder.build_all(sim.content.shift, sim.slots, p_shift_id)
	for peer: int in built:
		sim.plans[peer] = SiegeFakes.with_cooldown(built[peer])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	sim.state = SiegeRules.new_state(sim.content, sim.slots, mode, rng)
	sim.snapshot_every = int(opts.get("snapshot_every", 2))
	sim.od_refuse = str(opts.get("od_refuse", ""))
	var first: EffortPlan = sim.plans[sim.slots[0].peer_id]
	for i in first.size():
		sim.total_s += first.phase(i).duration_s
	for s in sim.slots:
		sim.wave_earned[s.peer_id] = 0.0
		sim.wave_earned_parts[s.peer_id] = [0.0, 0.0]
		sim._prev_earned[s.peer_id] = [0.0, 0.0]
	for i in sim.riders.size():
		if sim.riders[i].surge_every_s > 0.0:
			sim._next_surge[sim.slots[i].peer_id] = sim.riders[i].surge_every_s
	return sim


static func _slot(i: int, r: Rider, mode: String) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.is_bot = r.bot
	s.peer_id = -(i + 1) if r.bot else i + 1
	s.name = "Bot %d" % (i + 1) if r.bot else "Rider %d" % (i + 1)
	s.apply_look(i)
	s.ftp = r.ftp
	s.ftp_verified = r.verified or r.bot
	# Humans ride by hand (Autopilot off): zero-input fallbacks still start on, and a deliberate
	# route / buy intent ends them. Bots are Autopilot's anyway.
	s.autopilot = false
	s.scaling_mode = mode
	s.p_eff_per_w = r.p_eff_per_w
	if r.p_eff_per_w < 0.0:
		s.p_eff_per_w = 1.0 if mode == Wl.RAW else 250.0 / r.ftp
	s.options = {"wave_offset": 0 if r.bot else r.offset}
	return s


## A Rider.power_fn that always rides `w` raw watts.
static func const_w(w: float) -> Callable:
	return func(_t: float, _planned: float) -> float: return w


## N riders of one kind, FTP 200 + 20 x slot unless the spec sets one.
static func team(n: int, spec: Dictionary = {}) -> Array:
	var out: Array = []
	for i in n:
		var d := spec.duplicate()
		if not d.has("ftp"):
			d["ftp"] = 200.0 + 20.0 * i
		out.append(d)
	return out


## The content files with JSON-merge-patches applied ({file key: patch}; null deletes a key,
## objects merge, anything else replaces).
static func patched_files(patches: Dictionary) -> Dictionary:
	var files := SiegeContent.read_files()
	for k: String in patches:
		files[k] = merge_patch(files[k], patches[k])
	return files


static func merge_patch(target: Variant, patch: Variant) -> Variant:
	if not (patch is Dictionary):
		return patch
	var out: Dictionary = (target as Dictionary).duplicate(true) if target is Dictionary else {}
	for k: Variant in patch:
		if patch[k] == null:
			out.erase(k)
		else:
			out[k] = merge_patch(out.get(k), patch[k])
	return out


## A copy of the shifts.json shift `shift` with shorter phases, for fast sims. `o`: warmup_s,
## build_s, break_s (replace those phases' durations), wave_s (every wave), max_waves (later
## waves and the breaks before them are dropped). Rushes that no longer fit are dropped.
static func trimmed_shift(shift: Dictionary, o: Dictionary) -> Dictionary:
	var out := (shift as Dictionary).duplicate(true)
	var phases: Array = []
	var waves := 0
	var max_waves := int(o.get("max_waves", 99))
	for p: Dictionary in shift["phases"]:
		var ph := p.duplicate(true)
		match str(ph["role"]):
			SiegeIds.ROLE_WARMUP_WAVE:
				ph["duration_s"] = float(o.get("warmup_s", ph["duration_s"]))
			SiegeIds.ROLE_BUILD_BREAK:
				ph["duration_s"] = float(o.get("build_s", ph["duration_s"]))
			SiegeIds.ROLE_BREAK:
				ph["duration_s"] = float(o.get("break_s", ph["duration_s"]))
			SiegeIds.ROLE_WAVE:
				waves += 1
				if waves > max_waves:
					break
				ph["duration_s"] = float(o.get("wave_s", ph["duration_s"]))
				if ph.has("rushes_at_s"):
					var keep: Array = []
					for r: Variant in ph["rushes_at_s"]:
						if float(r) + 30.0 <= float(ph["duration_s"]) - 60.0:
							keep.append(r)
					if keep.is_empty():
						ph.erase("rushes_at_s")
					else:
						ph["rushes_at_s"] = keep
		phases.append(ph)
	# A break right before a dropped wave goes too.
	while not phases.is_empty() and str(phases.back()["role"]) == SiegeIds.ROLE_BREAK:
		phases.pop_back()
	out["phases"] = phases
	var total := 0.0
	for ph: Dictionary in phases:
		total += float(ph["duration_s"])
	out["total_s"] = total
	return out


## {"shifts": {id: trimmed shift}} patch for SiegeHeadlessSim.create, keeping the shift's id.
static func trim_patch(shift_id: String, o: Dictionary) -> Dictionary:
	var shifts: Dictionary = SiegeContent.read_files()["shifts"]
	return {"shifts": {shift_id: trimmed_shift(shifts[shift_id], o)}}


# --- running -------------------------------------------------------------------------------------


## Game time of the next tick.
func now() -> float:
	return tick * DT


func finished() -> bool:
	return now() >= total_s


## Runs until game time `t_end` (or the end of the plan with its cool-down).
func run_until(t_end: float) -> void:
	var end_tick := ceili(minf(t_end, total_s) / DT - 1e-9)
	while tick < end_tick:
		step()


func run_all() -> void:
	run_until(total_s)


## Runs until `pred` (Callable() -> bool, checked after every step) holds or the plan ends.
## True when it held.
func run_while_not(pred: Callable) -> bool:
	while not finished():
		step()
		if pred.call():
			return true
	return false


## One tick: build the inputs, SiegeRules.step, answer the Overdrive requests, record.
func step() -> Array[Dictionary]:
	var t := now()
	var inputs := _inputs(t)
	var events := SiegeRules.step(state, inputs, DT)
	for peer in state.take_od_requests():
		if od_refuse != "":
			events.append_array(SiegeOverdrive.on_request_result(state, peer, false, 0, od_refuse))
		else:
			var id := _next_directive_id
			_next_directive_id += 1
			stats["od_directives"] += 1
			events.append_array(SiegeOverdrive.on_request_result(state, peer, true, id, ""))
	for e in events:
		var lg := Logged.new()
		lg.t = t
		lg.tick = tick
		lg.event = e
		events_log.append(lg)
	_record(t)
	tick += 1
	return events


func _inputs(t: float) -> SiegeInputs:
	var frame := InputFrame.new()
	frame.tick = tick
	frame.t = t
	var intents := {}
	var rescue := {}
	var afk := {}
	for i in riders.size():
		var r := riders[i]
		var p := slots[i]
		var rs := state.rider(p.peer_id)
		var ph := SiegeFakes.phase_at(plans[p.peer_id], t)
		var planned_w := ph.planned_pct / 100.0 * p.ftp
		var od_on := rs != null and rs.od_state == SiegeIds.OD_ACTIVE
		var w := planned_w * r.compliance
		if od_on:
			w = r.od_pct / 100.0 * p.ftp
		if r.zero:
			w = 0.0
		if r.power_fn.is_valid():
			w = float(r.power_fn.call(t, planned_w))
		var tm := Telemetry.new()
		tm.peer_id = p.peer_id
		tm.t = t
		tm.mode = Wl.SIM if od_on else Wl.ERG
		tm.power_w = w
		tm.p_eff_w = w * p.p_eff_per_w
		tm.ftp_pct = w / p.ftp * 100.0
		tm.cadence_rpm = 0.0 if w <= 0.0 else 90.0
		tm.phase_index = ph.index
		frame.players[p.peer_id] = tm
		frame.phase[p.peer_id] = ph
		intents[p.peer_id] = _raw_intents(i, t)
		rescue[p.peer_id] = _in_window(r.rescue_windows, t)
		if r.zero:
			if not _afk_since.has(p.peer_id):
				_afk_since[p.peer_id] = t
			afk[p.peer_id] = t - float(_afk_since[p.peer_id]) >= r.afk_after_s
		else:
			afk[p.peer_id] = false
	var filtered := {}
	for peer: int in intents:
		filtered[peer] = _limiter.filter(peer, tick, intents[peer])
	return SiegeInputs.from_frame(frame, slots, plans, filtered, rescue, afk)


func _raw_intents(i: int, t: float) -> Array:
	var r := riders[i]
	var peer := slots[i].peer_id
	var out: Array = []
	if tick == 0 and r.route != "":
		out.append(SiegeIntents.route(int(r.route) if r.route.is_valid_int() else r.route))
	if tick == 1 and r.manual_shop:
		out.append(SiegeIntents.buy(SiegeIds.ITEM_REPAIR))
	if _next_surge.has(peer) and t >= float(_next_surge[peer]) - 1e-9:
		out.append(SiegeIntents.overdrive(SiegeIds.VIA_SURGE))
		_next_surge[peer] = float(_next_surge[peer]) + r.surge_every_s
	for at in r.action_at:
		if tick == roundi(at / DT):
			out.append(SiegeIntents.overdrive(SiegeIds.VIA_ACTION))
	for raw: Variant in r.intents_at.get(tick, []):
		out.append(raw)
	return out


static func _in_window(windows: Array, t: float) -> bool:
	for w: Variant in windows:
		if t >= float(w[0]) and t < float(w[1]):
			return true
	return false


func _record(_t: float) -> void:
	stats["steps"] += 1
	var alive := state.enemies.size()
	stats["max_alive"] = maxi(stats["max_alive"], alive)
	stats["max_queue"] = maxi(stats["max_queue"], state.queue.size())
	if alive > 0 or state.next_enemy_id > 1:
		stats["spawned"] = true
	if snapshot_every > 0 and tick % snapshot_every == 0:
		var bytes := SiegeSnapshotSchema.byte_size(SiegeSnapshot.encode(state))
		stats["max_snapshot_bytes"] = maxi(stats["max_snapshot_bytes"], bytes)
		stats["snapshots"] += 1
	var in_wave := state.role == SiegeIds.ROLE_WAVE
	if in_wave:
		stats["wave_seconds"] += DT
	for rs in state.riders:
		var prev: Array = _prev_earned[rs.peer]
		var dg := rs.gen_denarii - float(prev[0])
		var db := rs.bounty_denarii - float(prev[1])
		if in_wave:
			wave_earned[rs.peer] += dg + db
			wave_earned_parts[rs.peer][0] += dg
			wave_earned_parts[rs.peer][1] += db
		prev[0] = rs.gen_denarii
		prev[1] = rs.bounty_denarii


# --- queries -------------------------------------------------------------------------------------


## True when any enemy ever existed (the G0 combat stub spawns nothing; tests that need the
## real combat guard on this).
func combat_ran() -> bool:
	return bool(stats["spawned"])


## Every logged event of `type`, in order.
func events_of(type: String) -> Array[Logged]:
	var out: Array[Logged] = []
	for lg in events_log:
		if str(lg.event.get("type", "")) == type:
			out.append(lg)
	return out


## The logged events of `type` whose game time is in [t0, t1).
func events_between(type: String, t0: float, t1: float) -> Array[Logged]:
	return events_of(type).filter(func(lg: Logged) -> bool: return lg.t >= t0 and lg.t < t1)


## Game time at which phase `index` starts.
func phase_start(index: int) -> float:
	return SiegeFakes.phase_start(plans[slots[0].peer_id], index)


## Phase indexes whose role is `role`, in order.
func phases_of(role: String) -> Array[int]:
	var out: Array[int] = []
	var plan: EffortPlan = plans[slots[0].peer_id]
	for i in plan.size():
		if str(plan.phase(i).meta.get("role", "")) == role:
			out.append(i)
	return out


## Duration of phase `index`.
func phase_duration(index: int) -> float:
	return (plans[slots[0].peer_id] as EffortPlan).phase(index).duration_s


## Wave-time denarii per minute of `peer`'s earnings (generator + bounties) in wave phases.
func earned_per_wave_minute(peer: int) -> float:
	var minutes := float(stats["wave_seconds"]) / 60.0
	return float(wave_earned[peer]) / minutes if minutes > 0.0 else 0.0


## Every logged event as one JSON string (determinism checks).
func events_json() -> String:
	var all: Array = []
	for lg in events_log:
		all.append([lg.tick, lg.event])
	return JSON.stringify(all)


## SiegeScore.compute(state).
func score() -> Dictionary:
	return SiegeScore.compute(state)
