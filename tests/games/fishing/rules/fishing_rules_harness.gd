extends RefCounted
## Drives FishingRules like the GameHost would, without the platform runtime: one plan per rider
## (FishingPlanBuilder plus the validator's cool-down; Free Roam replans splice like the
## DirectiveRouter and swap in at the next phase change), a per-rider phase clock (fixed phases end
## by duration, open-ended ones by end_phase after min_s or at max_s, finished jumps every rider
## to the cool-down), synthetic telemetry from a tiny rider model, and logs of everything the rules
## return. Tests preload it (no class_name).

const DT := 0.05
const CONTENT := "res://content/fishing"

var content: FishingContent
var state: FishingState
var players: Array[PlayerSlot] = []
var plans: Array[EffortPlan] = []
var slots: Array = []
var inputs: Array = []
var seed: int = 7

# --- Phase clock, per rider ---------------------------------------------------------------
var ph_index: Array[int] = []
var ph_elapsed: Array[float] = []
var plan_elapsed: Array[float] = []
var _end_req: Array[bool] = []
var _pending_plan: Array = []

# --- Rider model, per rider ----------------------------------------------------------------
## Constant cadence, or (follow_band) the published band's centre + band_offset (90 without one).
var cadence: Array[float] = []
var follow_band: Array[bool] = []
var band_offset: Array[float] = []
## Power in ERG as % of the applied target; in the Landing landing_w watts; in other SIM phases
## (driving, the menu, the cool-down) drive_w watts. P_eff = power x 250 / FTP (FAIR_FTP).
var power_pct: Array[float] = []
var landing_w: Array[float] = []
var drive_w: Array[float] = []
var rescue: Array[bool] = []
var afk: Array[bool] = []
var paused: Array[bool] = []
var age_s: Array[float] = []
var cadence_age_s: Array[float] = []
var connected: Array[bool] = []
## Raw intents for the next step only.
var pending: Array = []
## The ERG target a directive set (% FTP; -1 = the plan's), reset at each phase change.
var target_pct: Array[float] = []

# --- Logs ----------------------------------------------------------------------------------
var events: Array = []
var event_t: Array[float] = []
var directives: Array = []
var bands: Array = []
var grades: Array = []
var power_bands: Array = []
var replans: Array = []
var toasts: Array = []
## [t, peer, phase index that ended]
var ended: Array = []
var finished: String = ""
var finished_count: int = 0
var last_out: FishingStepOut = null
## Contract breaks the harness saw (end_phase before min_s, invalid replans, plan warnings, bad
## content); tests assert it empty.
var violations: Array[String] = []


static func json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(CONTENT.path_join(path)))


static func load_content(content_id: String) -> FishingContent:
	var trip: Variant = json("trips/%s.json" % content_id)
	var map_file := FishingTripDef.map_file_of(trip)
	return FishingContent.new().parse(
		json("species.json"), trip, json(map_file), json("cosmetics.json")
	)


## A workout slot of `species_id` with T_nom `t_nom`, `runs` runs (or jumps) and weight `kg`.
static func make_slot(
	c: FishingContent, species_id: String, index: int, t_nom: float, runs: int = 0, kg: float = -1.0
) -> FishingPlanSlot:
	var def: FishingSpeciesDef = c.species[species_id]
	var s := FishingPlanSlot.new()
	s.index = index
	s.species = species_id
	s.sp = FishingConst.species_index(species_id)
	s.w = 0.5
	s.base_pct = minf((def.pull_lo + def.pull_hi) / 2.0, 105.0 if def.max_s > 300.0 else 110.0)
	s.change_pct = def.change_pct
	s.t_nom_s = t_nom
	s.min_s = maxf(floorf(FishingConst.FIGHT_MIN_FRAC * t_nom), FishingConst.FIGHT_MIN_S)
	s.max_s = def.max_s
	s.run_kind = def.run_kind if runs > 0 else FishingSpeciesDef.RUN_NONE
	var top := 0.0
	for k in runs:
		var peak := minf(def.run_peak(s.base_pct, 0.5), 105.0 if def.max_s > 300.0 else 110.0)
		s.runs.append((def.run_s_lo + def.run_s_hi) / 2.0)
		s.runs.append(peak)
		top = maxf(top, peak)
		if def.run_kind == FishingSpeciesDef.RUN_JUMP:
			s.leaps.append(2 + k % 2)
	s.run_band_shift = def.run_band_shift
	s.run_min_gap_s = def.run_min_gap_s
	var a := s.change_pct / 100.0
	s.range_lo = s.base_pct * (1.0 - a)
	s.range_hi = minf(maxf(s.base_pct * (1.0 + a), top), 110.0)
	s.band_offset = def.band_offset
	s.kg = kg if kg > 0.0 else (def.kg_lo + def.kg_hi) / 2.0
	s.d_max = def.d_max
	s.depth_m = FishingConst.TROLL_DEPTH_M
	return s


## Sets up `content_id` with `riders` riders. `rider_slots` (Array of Array[FishingPlanSlot])
## overrides a workout's pre-roll; `bots` of the riders (the last ones) are bots with strategies
## `strategies` (one per bot; default "mixed").
func setup(
	content_id: String,
	riders: int = 1,
	p_seed: int = 7,
	rider_slots: Array = [],
	bots: int = 0,
	strategies: Array[int] = []
) -> void:
	seed = p_seed
	content = load_content(content_id)
	if not content.ok:
		violations.append("content: %s" % [content.errors])
	var strat: Array[int] = []
	for i in riders:
		var p := PlayerSlot.new()
		var bot := i >= riders - bots
		p.peer_id = -(i + 1) if bot else i + 1
		p.slot_index = i
		p.name = "Rider %d" % (i + 1)
		p.ftp = 200.0 + 20.0 * i
		p.ftp_verified = true
		p.preferred_cadence_rpm = 90.0
		p.haptics_on = true
		p.is_bot = bot
		p.autopilot = bot
		p.options = {"reel_pct": FishingConst.REEL_PCT_DEFAULT, "relaxed_band": false}
		players.append(p)
		var bi := i - (riders - bots)
		strat.append((strategies[bi] if bi < strategies.size() else 2) if bot else -1)
		var ls: Array[FishingPlanSlot] = []
		if i < rider_slots.size():
			ls.assign(rider_slots[i])
		else:
			ls = FishingPreroll.roll(content.trip, content.species, seed, i)
		slots.append(ls)
		cadence.append(90.0)
		follow_band.append(false)
		band_offset.append(0.0)
		power_pct.append(100.0)
		landing_w.append(0.0)
		drive_w.append(p.ftp)
		rescue.append(false)
		afk.append(false)
		paused.append(false)
		age_s.append(0.0)
		cadence_age_s.append(0.0)
		connected.append(true)
		pending.append([])
		target_pct.append(-1.0)
		ph_index.append(0)
		ph_elapsed.append(0.0)
		plan_elapsed.append(0.0)
		_end_req.append(false)
		_pending_plan.append(null)
		var inp := FishingRiderInput.new()
		inp.peer = p.peer_id
		inp.slot = i
		inputs.append(inp)
	rebuild(strat)


## (Re)builds plans and the rules state from players and slots (after changing a PlayerSlot).
func rebuild(strategies: Array[int] = []) -> void:
	plans.clear()
	state = FishingRules.new_state(content, players, seed, slots, strategies)
	for i in players.size():
		var plan: EffortPlan
		if content.trip.is_roam():
			plan = FishingPlanBuilder.roam(state.play_end_t)
		else:
			plan = FishingPlanBuilder.build(
				content.trip, slots[i], int(players[i].options.get("reel_pct", 60))
			)
		var res := PlanValidator.validate(plan)
		if not bool(res["ok"]) or not (res["warnings"] as Array).is_empty():
			violations.append("plan %d: %s %s" % [i, res["errors"], res["warnings"]])
		plans.append(PlanValidator.finalize(plan))


func rider(i: int = 0) -> FishingRiderState:
	return state.riders[i]


func phase(i: int = 0) -> PlanPhase:
	return plans[i].phase(ph_index[i])


func send(i: int, intent: Dictionary) -> void:
	(pending[i] as Array).append(intent)


func step() -> FishingStepOut:
	for i in players.size():
		_fill(i)
	var out := FishingRules.step(state, inputs, DT)
	last_out = out
	for rp: Array in out.replans:
		var i := _index_of(int(rp[0]))
		replans.append([state.t, rp[0], rp[1]])
		var whole := PlanValidator.spliced(plans[i], ph_index[i], rp[1])
		var res := PlanValidator.validate(whole)
		if not bool(res["ok"]) or not (res["warnings"] as Array).is_empty():
			violations.append("t %.2f: replan %s %s" % [state.t, res["errors"], res["warnings"]])
		else:
			_pending_plan[i] = PlanValidator.finalize(whole)
	for e: Dictionary in out.events:
		events.append(e)
		event_t.append(state.t)
	for d: Array in out.directives:
		directives.append([state.t, d[0], d[1]])
		var dd: Dictionary = d[1]
		if dd.has("target_pct"):
			target_pct[_index_of(int(d[0]))] = float(dd["target_pct"])
	for b: Array in out.bands:
		bands.append([state.t, b[0], b[1], b[2]])
	for g: Array in out.grades:
		var gi := _index_of(int(g[0]))
		var ph := phase(gi)
		if ph.mode != Wl.SIM or ph.grade_source != Wl.GRADE_GAME:
			violations.append("t %.2f: course grade outside a game phase" % state.t)
		grades.append([state.t, g[0], g[1]])
	for pb: Array in out.power_bands:
		power_bands.append([state.t, pb[0], pb[1], pb[2]])
	for t: Array in out.toasts:
		toasts.append([state.t, t[0], t[1], t[2]])
	for peer in out.end_phase:
		var i := _index_of(peer)
		var ph := phase(i)
		if not ph.open_ended or ph_elapsed[i] + 1e-6 < ph.min_s:
			violations.append("t %.2f: end_phase for peer %d before min_s" % [state.t, peer])
		else:
			_end_req[i] = true
	if out.finished != "":
		finished = out.finished
		finished_count += 1
		for i in players.size():
			if plans[i].phase(ph_index[i]).kind != Wl.COOLDOWN:
				ended.append([state.t, players[i].peer_id, ph_index[i]])
				_swap_plan(i)
				_goto(i, plans[i].cooldown_index())
	for i in players.size():
		_advance(i)
	return out


func _index_of(peer: int) -> int:
	for i in players.size():
		if players[i].peer_id == peer:
			return i
	return -1


func _fill(i: int) -> void:
	var inp: FishingRiderInput = inputs[i]
	var ph := phase(i)
	var p := players[i]
	inp.has_phase = true
	inp.phase_index = ph_index[i]
	inp.phase_kind = ph.kind
	inp.phase_mode = ph.mode
	inp.phase_elapsed_s = ph_elapsed[i]
	inp.phase_duration_s = ph.duration_s
	inp.phase_open_ended = ph.open_ended
	inp.phase_min_s = ph.min_s
	inp.phase_max_s = ph.max_s
	var end := ph.max_s if ph.open_ended else ph.duration_s
	inp.phase_remaining_s = maxf(end - ph_elapsed[i], 0.0)
	inp.plan_elapsed_s = plan_elapsed[i]
	inp.is_cooldown = ph.kind == Wl.COOLDOWN
	inp.mode = ph.mode
	if ph.mode == Wl.ERG:
		var pct := target_pct[i] if target_pct[i] >= 0.0 else ph.planned_pct_at(ph_elapsed[i])
		inp.applied_target_w = roundf(pct / 100.0 * p.ftp)
		inp.power_w = inp.applied_target_w * power_pct[i] / 100.0
	elif ph.kind == Wl.WORK:
		inp.applied_target_w = 0.0
		inp.power_w = landing_w[i]
	else:
		inp.applied_target_w = 0.0
		inp.power_w = drive_w[i]
	if paused[i]:
		inp.power_w = 0.0
	inp.p_eff_w = inp.power_w * FishingConst.P_EFF_REF_W / p.ftp
	var r := rider(i)
	if follow_band[i] and (r.pub_lo != 0 or r.pub_hi != 0):
		inp.cadence_rpm = (r.pub_lo + r.pub_hi) / 2.0 + band_offset[i]
	elif follow_band[i]:
		inp.cadence_rpm = 90.0 + band_offset[i]
	else:
		inp.cadence_rpm = cadence[i]
	inp.rescue = rescue[i]
	inp.afk = afk[i]
	inp.paused = paused[i]
	inp.age_s = age_s[i]
	inp.cadence_age_s = cadence_age_s[i]
	inp.connected = connected[i]
	inp.intents = FishingIntents.normalize_tick(pending[i])
	pending[i] = []


func _advance(i: int) -> void:
	var ph := phase(i)
	ph_elapsed[i] += DT
	plan_elapsed[i] += DT
	if ph.kind == Wl.COOLDOWN:
		return
	var done := _end_req[i]
	if ph.open_ended:
		done = done or ph_elapsed[i] + 1e-6 >= ph.max_s
	else:
		done = ph_elapsed[i] + 1e-6 >= ph.duration_s
	if done:
		if _end_req[i]:
			ended.append([state.t, players[i].peer_id, ph_index[i]])
		_swap_plan(i)
		_goto(i, ph_index[i] + 1)


func _swap_plan(i: int) -> void:
	if _pending_plan[i] != null:
		plans[i] = _pending_plan[i]
		_pending_plan[i] = null


func _goto(i: int, index: int) -> void:
	ph_index[i] = mini(index, plans[i].size() - 1)
	ph_elapsed[i] = 0.0
	_end_req[i] = false
	target_pct[i] = -1.0


## Steps for `seconds` of game time.
func run(seconds: float) -> void:
	for _k in roundi(seconds / DT):
		step()


## Steps until `cond.call()` is true (checked after each step) or `max_s` passes; true if met.
func run_until(cond: Callable, max_s: float) -> bool:
	for _k in roundi(max_s / DT):
		step()
		if cond.call():
			return true
	return false


## Steps until rider `i` is in action `a`.
func run_to_action(i: int, a: int, max_s: float) -> bool:
	return run_until(func() -> bool: return rider(i).action == a, max_s)


## Steps until rider `i` is in a phase of `kind` (and `mode`, when given), plus one step so the
## rules have entered it.
func run_to_phase(i: int, kind: String, max_s: float, mode: String = "") -> bool:
	var ok := run_until(
		func() -> bool: return phase(i).kind == kind and (mode == "" or phase(i).mode == mode),
		max_s
	)
	if ok:
		step()
	return ok


func events_of(type: String, l: int = -1) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e["type"] == type and (l < 0 or int(e.get("l", -1)) == l):
			out.append(e)
	return out


## Game time of the n-th (0-based) event of `type` on rider `l` (-1 any), or -1.
func time_of(type: String, l: int = -1, n: int = 0) -> float:
	var seen := 0
	for k in events.size():
		var e: Dictionary = events[k]
		if e["type"] == type and (l < 0 or int(e.get("l", -1)) == l):
			if seen == n:
				return event_t[k]
			seen += 1
	return -1.0
