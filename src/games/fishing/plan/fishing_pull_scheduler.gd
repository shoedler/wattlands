class_name FishingPullScheduler
extends RefCounted
## The Fight's ERG directives (brief 2.3 "Load changes"): pull changes, runs and jumps, pauses,
## all pure over one lane's FishingPullState (no clock, no global RNG: randomness comes only from
## the lane's pull stream). fish-plan owns this file. FishingRules calls, for one lane:
##   init_lane(ps, seed, slot_index)            once, in new_state: seeds ps.rng (STREAM_PULL)
##   begin(ps, slot, t, ftp_w, ps.rng)          at the Fight's start
##   run_blocked_by_gap(ps, slot, t) -> bool    before start_run: true = not yet, retry later
##   start_run(ps, slot, k, t, ftp_w) -> bool   when run k (0-based) comes due (false: skipped)
##   set_staggered(ps, active, t)               when a rescue or AFK starts or ends (any state)
##   step(ps, slot, t, ftp_w, ps.rng) -> Array  every Fight tick: EffortDirective dictionaries
##   end(ps)                                    at the Fight's end
##
## Every directive is {"mode": "ERG", "target_pct", "duration_s", "reason": "pull" | "run" |
## "jump", "source": "fishing"}, with target_pct inside [slot.range_lo, slot.range_hi] and
## <= 110 %. Rules (brief 2.3):
## - Pull change: every 8-16 s a new multiplier m in [-a, +a]: target = base x (1 + m) (<= 105 %,
##   or the range top for a slot with hold_above_105: the giant grouper's 105-110 % pull),
##   ramped as >= 6 steps 0.5 s apart, each with duration_s 0 (held until replaced). The ramp is
##   stretched so no step raises the target by more than 25 W/s x 0.5 s at the rider's FTP.
## - Run or jump: the same ramp up to the run's peak, but every step carries duration_s = the
##   seconds left to the run's scheduled end, so each step replaces the last with the same expiry
##   and at that end the governor reverts the target to the phase's planned target, the base pull,
##   at once, even when a rescue or AFK cut the ramp short. The next pull change starts from base.
## - At most one write every 0.5 s (BRIEF 4.5: 2 writes/s), whatever its source.
## - Above 105 %: a run whose peak is above 105 % reserves its whole length (ramp included); a run
##   that would pass 30 s, or push the fight past 90 s, is held to 105 %.
## - Pauses: the pull-change clock is stopped from a run's start to its scheduled end, and from a
##   stagger's start until 10 s after its end; it then restarts with a fresh 8-16 s interval. A
##   pull ramp in progress is dropped when a run or a stagger starts, so no pull change lands
##   inside a run, a rescue or AFK. No request at all is sent while staggered.
## - One run at a time: run_blocked_by_gap() is true while a run is active and, for jumps, until
##   run_min_gap_s after the previous jump's start (90 s); the rules retry on later ticks.

const EPS := 1.0e-6
const SOURCE := "fishing"
const REASON_PULL := "pull"
## The most a ramp step may raise the target, in watts (25 W/s x 0.5 s).
const STEP_MAX_W := FishingConst.RAMP_MAX_W_PER_S * FishingConst.RAMP_STEP_S


## Seeds the lane's pull stream. FishingRules calls it once per lane in new_state and passes
## ps.rng as the `rng` argument of begin() and step().
static func init_lane(ps: FishingPullState, seed: int, slot_index: int) -> void:
	ps.rng = FishingRandom.derive(seed, slot_index, FishingRandom.STREAM_PULL)


## The Fight starts at game time `t` with the phase's planned target at slot.base_pct.
static func begin(
	ps: FishingPullState, slot: FishingPlanSlot, t: float, _ftp_w: float, rng: FishingRandom
) -> void:
	ps.base_pct = slot.base_pct
	ps.target_pct = slot.base_pct
	ps.expiry_t = 0.0
	ps.queue.clear()
	ps.run_active = false
	ps.run_end_t = 0.0
	ps.run_k = -1
	ps.run_start_t = -1.0e9
	ps.run_peak_pct = 0.0
	ps.last_run_start_t = -1.0e9
	ps.above_105_run_s = 0.0
	ps.above_105_fight_s = 0.0
	ps.runs_started = 0
	ps.runs_skipped = 0
	ps.sent = 0
	ps.next_change_t = t + _interval(rng)
	ps.clock_fresh = ps.staggered or t < ps.paused_until_t - EPS


## True while run k may not start yet: a run is still active, or (jumps) the previous jump started
## less than slot.run_min_gap_s ago. The rules retry on later ticks; S keeps falling meanwhile.
static func run_blocked_by_gap(ps: FishingPullState, slot: FishingPlanSlot, t: float) -> bool:
	if ps.run_active and t < ps.run_end_t - EPS:
		return true
	if slot.run_min_gap_s > 0.0 and t - ps.last_run_start_t < slot.run_min_gap_s - EPS:
		return true
	return false


## Starts run k (0-based) now and returns true; while staggered the run is skipped (false) and the
## rules count it as fired with no event. The run ends at t + its pre-rolled length.
static func start_run(
	ps: FishingPullState, slot: FishingPlanSlot, k: int, t: float, ftp_w: float
) -> bool:
	if ps.staggered:
		ps.runs_skipped += 1
		return false
	if k < 0 or k >= slot.run_count():
		push_warning("fishing: run %d of %d does not exist; skipped" % [k, slot.run_count()])
		ps.runs_skipped += 1
		return false
	_expire(ps, t)
	var dur := slot.run_dur_s(k)
	var hi := _range_hi(slot)
	var peak := clampf(slot.run_peak_pct(k), slot.range_lo, hi)
	if slot.max_s > PlanValidator.LONG_PHASE_S:
		peak = minf(peak, FishingConst.LONG_PHASE_CAP_PCT)
	if peak > FishingConst.LONG_PHASE_CAP_PCT:
		var over_run := dur > FishingConst.RUN_MAX_ABOVE_105_S + EPS
		var over_fight := ps.above_105_fight_s + dur > FishingConst.FIGHT_MAX_ABOVE_105_S + EPS
		if over_run or over_fight:
			peak = FishingConst.LONG_PHASE_CAP_PCT
	ps.queue.clear()
	ps.run_active = true
	ps.run_k = k
	ps.run_start_t = t
	ps.last_run_start_t = t
	ps.run_end_t = t + dur
	ps.run_peak_pct = peak
	ps.above_105_run_s = dur if peak > FishingConst.LONG_PHASE_CAP_PCT else 0.0
	ps.above_105_fight_s += ps.above_105_run_s
	ps.clock_fresh = true
	ps.runs_started += 1
	var t0 := maxf(t, ps.last_send_t + FishingConst.RAMP_STEP_S)
	_queue_ramp(ps, ps.target_pct, peak, ramp_steps(ps.target_pct, peak, ftp_w), t0, true)
	return true


## A rescue or AFK started (active true) or ended (false) at game time t. While staggered nothing
## is sent and a ramp in progress is dropped (a run's last step still expires at the run's end);
## the pull-change clock restarts 10 s after the end with a fresh interval.
static func set_staggered(ps: FishingPullState, active: bool, t: float) -> void:
	if active:
		if not ps.staggered:
			ps.staggered = true
			ps.queue.clear()
			ps.clock_fresh = true
	elif ps.staggered:
		ps.staggered = false
		ps.clock_fresh = true
		ps.paused_until_t = maxf(ps.paused_until_t, t + FishingConst.PULL_RESUME_AFTER_STAGGER_S)


## The directives due this tick (at most one). The returned Array is reused by the next step() of
## this lane: copy what you keep.
static func step(
	ps: FishingPullState, slot: FishingPlanSlot, t: float, ftp_w: float, rng: FishingRandom
) -> Array:
	var out := ps._out
	out.clear()
	_expire(ps, t)
	if ps.run_active and t >= ps.run_end_t - EPS:
		ps.run_active = false
		ps.queue.clear()
		ps.clock_fresh = true
	if ps.staggered:
		ps.clock_fresh = true
		return out
	if ps.run_active or t < ps.paused_until_t - EPS:
		ps.clock_fresh = true
	elif ps.clock_fresh:
		ps.clock_fresh = false
		ps.next_change_t = t + _interval(rng)
	elif ps.queue.is_empty() and t >= ps.next_change_t - EPS:
		_pull_change(ps, slot, t, ftp_w, rng)
	if ps.queue.is_empty() or t < ps.queue[0] - EPS:
		return out
	if t < ps.last_send_t + FishingConst.RAMP_STEP_S - EPS:
		return out
	var target := clampf(ps.queue[1], slot.range_lo, _range_hi(slot))
	var is_run := ps.queue[2] > 0.5
	ps.queue.pop_front()
	ps.queue.pop_front()
	ps.queue.pop_front()
	var dur := 0.0
	if is_run:
		dur = snappedf(ps.run_end_t - t, Wl.SIM_DT)
		if dur < Wl.SIM_DT - EPS:
			ps.queue.clear()
			return out
	var reason := slot.run_kind if is_run else REASON_PULL
	(
		out
		. append(
			{
				"mode": Wl.ERG,
				"target_pct": target,
				"duration_s": dur,
				"reason": reason,
				"source": SOURCE,
			}
		)
	)
	ps.target_pct = target
	ps.expiry_t = t + dur if is_run else 0.0
	ps.last_send_t = t
	ps.sent += 1
	return out


## The Fight ended (landing, or the platform at max_s): nothing more is sent.
static func end(ps: FishingPullState) -> void:
	ps.queue.clear()
	ps.run_active = false
	ps.expiry_t = 0.0
	ps.clock_fresh = false


## Ramp steps from `from_pct` to `to_pct` at FTP `ftp_w`: at least 6, more when a step would raise
## the target by more than 12.5 W (25 W/s at 0.5 s apart).
static func ramp_steps(from_pct: float, to_pct: float, ftp_w: float) -> int:
	var up_w := maxf(0.0, to_pct - from_pct) * maxf(ftp_w, 1.0) / 100.0
	return maxi(FishingConst.RAMP_STEPS, ceili(up_w / STEP_MAX_W - EPS))


## The highest target this slot's directives may take: its range top, never above 110 %.
static func _range_hi(slot: FishingPlanSlot) -> float:
	return minf(slot.range_hi, FishingConst.SELF_CAP_PCT)


static func _interval(rng: FishingRandom) -> float:
	return rng.range_f(FishingConst.PULL_CHANGE_MIN_S, FishingConst.PULL_CHANGE_MAX_S)


## The governor's expiry: a run step's channel reverts to the planned target (the base pull).
static func _expire(ps: FishingPullState, t: float) -> void:
	if ps.expiry_t > 0.0 and t >= ps.expiry_t - EPS:
		ps.target_pct = ps.base_pct
		ps.expiry_t = 0.0


static func _pull_change(
	ps: FishingPullState, slot: FishingPlanSlot, t: float, ftp_w: float, rng: FishingRandom
) -> void:
	var a := slot.change_pct / 100.0
	var m := rng.range_f(-a, a)
	var hi := _range_hi(slot)
	if not slot.hold_above_105:
		hi = minf(hi, FishingConst.LONG_PHASE_CAP_PCT)
	var to := clampf(ps.base_pct * (1.0 + m), slot.range_lo, maxf(hi, slot.range_lo))
	var n := ramp_steps(ps.target_pct, to, ftp_w)
	var t0 := maxf(t, ps.last_send_t + FishingConst.RAMP_STEP_S)
	_queue_ramp(ps, ps.target_pct, to, n, t0, false)
	var last_due := t0 + FishingConst.RAMP_STEP_S * float(n - 1)
	ps.next_change_t = maxf(t + _interval(rng), last_due + FishingConst.RAMP_STEP_S)


static func _queue_ramp(
	ps: FishingPullState, from_pct: float, to_pct: float, n: int, t0: float, run: bool
) -> void:
	for i in n:
		var due := t0 + FishingConst.RAMP_STEP_S * float(i)
		if run and due >= ps.run_end_t - EPS:
			break
		ps.queue.append(due)
		ps.queue.append(lerpf(from_pct, to_pct, float(i + 1) / float(n)))
		ps.queue.append(1.0 if run else 0.0)
