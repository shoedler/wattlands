class_name WorkoutRules
extends RefCounted
## Workout's rules (BRIEF 3.7): pure and deterministic, step(state, inputs, dt) at the
## platform's fixed 0.05 s. No wall clock, no randomness, no side effects outside `state`:
## the returned events are what the GameModule sends to clients and turns into HUD calls.
##
## In band:
##   ERG phases: power within +-5% of the applied target (telemetry applied_target_w;
##     before the governor reports one, the planned target x the unverified factor);
##   SIM WORK phases (Rolling road): power within the session band (76-105% FTP);
##   FREE sprints (SIM flat, virtual gears): cadence >= 60 rpm.
## A rider in rescue, AFK or disconnected is out of band (a stagger: no other penalty).
## Time in band counts per interval and for the session; the cool-down is not counted.
## Sprints are scored with WorkoutSprintTracker (SprintRule's 1.2 x FTP threshold).
## Each rider's speed and distance come from SpeedModel with P_eff (BRIEF 3.11) on the
## course grade in course phases and flat otherwise; they only drive the view.
##
## Events (each a JSON-safe Dictionary with "type"):
##   {"type": "interval_start", "i": index}
##   {"type": "interval_end", "i": index, "r": [[peer, tib_permille], ...]}
##   {"type": "sprint", "i": index, "r": [[peer, peak_w, best_ds, hit 0/1], ...]}

const ERG_TOLERANCE := 0.05
const SPRINT_MIN_CADENCE_RPM := 60.0
const UNVERIFIED_FACTOR := 0.85
const EV_INTERVAL_START := "interval_start"
const EV_INTERVAL_END := "interval_end"
const EV_SPRINT := "sprint"


## Advances `state` by dt with the riders' telemetry and phases in `inputs` (the frame).
## Returns the events of this step, in order.
static func step(state: WorkoutState, inputs: InputFrame, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.tick = inputs.tick
	var lead := _lead_phase(state, inputs)
	if lead != null:
		state.plan_t = lead.plan_elapsed_s if lead.plan_elapsed_s > 0.0 else state.phase_start_s(lead.index) + lead.elapsed_s
		if lead.index != state.phase_index:
			var prev := state.phase_index
			if prev >= 0:
				events.append(_interval_end(state, prev))
				var sprint_event := _sprint_event(state, prev)
				if not sprint_event.is_empty():
					events.append(sprint_event)
			state.phase_index = lead.index
			events.append({"type": EV_INTERVAL_START, "i": lead.index})
	for peer: int in state.order:
		var r := state.rider(peer)
		var tel: Telemetry = inputs.telemetry(peer)
		var ps: PhaseState = inputs.phase_of(peer)
		if tel == null:
			continue
		_step_rider(state, r, tel, ps, dt)
	return events


static func _lead_phase(state: WorkoutState, inputs: InputFrame) -> PhaseState:
	var lead: PhaseState = null
	for peer: int in state.order:
		var ps: PhaseState = inputs.phase_of(peer)
		if ps == null or ps.index < 0:
			continue
		if lead == null or ps.index > lead.index:
			lead = ps
	return lead


static func _step_rider(state: WorkoutState, r: WorkoutRiderState, tel: Telemetry, ps: PhaseState, dt: float) -> void:
	r.power_w = tel.power_w
	r.cadence_rpm = tel.cadence_rpm
	r.connected = tel.connected
	r.afk = tel.afk or not tel.connected
	r.rescue = tel.rescue
	var index := ps.index if ps != null else -1
	if index != r.phase_index:
		_finish_sprint(r)
		r.phase_index = index
		r.course_d = 0.0
	var p := state.phase(index)
	var grade := 0.0
	if state.is_course_phase(index) and state.course != null:
		grade = state.course.grade_at(r.course_d)
	var before := r.speed.distance_m
	r.speed.step(dt, tel.p_eff_w, grade)
	if state.is_course_phase(index):
		r.course_d += r.speed.distance_m - before
	r.stats.add(tel.power_w, dt)
	if p == null:
		r.in_band = false
		return
	r.in_band = in_band(p, ps, tel, r, state.band_pct)
	if p.kind == Wl.FREE:
		if r.sprint == null or r.sprint.phase_index != index:
			r.sprint = WorkoutSprintTracker.create(r.ftp, index)
		r.sprint.update(tel.power_w, dt)
	if p.kind != Wl.COOLDOWN:
		r.add_interval_time(index, r.in_band, dt)


## Is the rider in band right now? (See the class comment.)
static func in_band(p: PlanPhase, ps: PhaseState, tel: Telemetry, r: WorkoutRiderState, band_pct: Array) -> bool:
	if tel == null or not tel.connected or tel.afk or tel.rescue:
		return false
	if p.mode == Wl.ERG:
		var target := float(tel.applied_target_w) if tel.mode == Wl.ERG else 0.0
		if target <= 0.0:
			var planned := ps.planned_pct if ps != null and ps.planned_pct > 0.0 else p.planned_pct_at(ps.elapsed_s if ps != null else 0.0)
			target = planned / 100.0 * r.ftp * (1.0 if r.ftp_verified else UNVERIFIED_FACTOR)
		return erg_in_band(tel.power_w, target)
	if p.kind == Wl.FREE:
		return sprint_in_band(tel.cadence_rpm)
	return sim_in_band(tel.power_w, r.ftp, band_pct)


## ERG: power within +-5% of the target (inclusive).
static func erg_in_band(power_w: float, target_w: float) -> bool:
	if target_w <= 0.0:
		return false
	return absf(power_w - target_w) <= ERG_TOLERANCE * target_w + 1e-9


## SIM WORK (Rolling road): power within [lo, hi] % FTP (inclusive).
static func sim_in_band(power_w: float, ftp_w: float, band_pct: Array) -> bool:
	if ftp_w <= 0.0 or band_pct.size() != 2:
		return false
	var pct := power_w / ftp_w * 100.0
	return pct >= float(band_pct[0]) - 1e-9 and pct <= float(band_pct[1]) + 1e-9


## FREE sprints: cadence >= 60 rpm.
static func sprint_in_band(cadence_rpm: float) -> bool:
	return cadence_rpm >= SPRINT_MIN_CADENCE_RPM


static func _finish_sprint(r: WorkoutRiderState) -> void:
	if r.sprint == null:
		return
	r.sprints.append(r.sprint.result())
	r.sprint = null


static func _interval_end(state: WorkoutState, index: int) -> Dictionary:
	var rows: Array = []
	for peer: int in state.order:
		var r := state.rider(peer)
		rows.append([peer, int(round(r.interval_fraction(index) * 1000.0))])
	return {"type": EV_INTERVAL_END, "i": index, "r": rows}


## The sprint results of phase `index` for every rider ({} if it was no sprint). Riders
## still inside that phase (lagging by a tick) are finished here too.
static func _sprint_event(state: WorkoutState, index: int) -> Dictionary:
	var p := state.phase(index)
	if p == null or p.kind != Wl.FREE:
		return {}
	var rows: Array = []
	for peer: int in state.order:
		var r := state.rider(peer)
		if r.sprint != null and r.sprint.phase_index == index:
			_finish_sprint(r)
		var res := sprint_result(r, index)
		if res.is_empty():
			res = {"peak_w": 0, "best_s": 0.0, "hit": false}
		rows.append([peer, int(res["peak_w"]), int(round(float(res["best_s"]) * 10.0)), 1 if bool(res["hit"]) else 0])
	return {"type": EV_SPRINT, "i": index, "r": rows}


static func sprint_result(r: WorkoutRiderState, index: int) -> Dictionary:
	for s in r.sprints:
		if int(s["i"]) == index:
			return s
	return {}


## Group score: the average session time in band over every rider, 0..1.
static func group_fraction(state: WorkoutState) -> float:
	if state.order.is_empty():
		return 0.0
	var sum := 0.0
	for peer: int in state.order:
		sum += state.rider(peer).tib_fraction()
	return sum / float(state.order.size())


## Client prediction of the local rider between snapshots (marker position only).
static func predict(state: WorkoutState, peer: int, dt: float, local: Telemetry) -> void:
	var r := state.rider(peer)
	if r == null or local == null:
		return
	var grade := 0.0
	if state.is_course_phase(r.phase_index) and state.course != null:
		grade = state.course.grade_at(r.course_d)
	var before := r.speed.distance_m
	r.speed.step(dt, local.p_eff_w, grade)
	if state.is_course_phase(r.phase_index):
		r.course_d += r.speed.distance_m - before
	state.plan_t += dt
