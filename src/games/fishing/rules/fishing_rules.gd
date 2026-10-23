class_name FishingRules
extends RefCounted
## Big Game Fishing's pure rules (brief 2.4, 2.5): step(state, inputs, dt) at 0.05 s. Each
## rider's phase comes from frame.phase (FishingLaneInput); randomness only from each lane's
## FishingRandom streams (derived from ctx.seed); every trainer change, band, phase end, event and
## toast goes out in a FishingStepOut for the module to apply. No ctx, no Nodes, no clock.
##
## Lane states by phase: WARMUP -> RIDE_OUT (practice band, tips); RECOVERY (the Reel) -> PICK,
## CAST, REEL, STRIKE, or IDLE (nothing more to catch); WORK ERG -> FIGHT; WORK SIM -> LANDING;
## COOLDOWN -> HOME. The hot path allocates nothing per tick except what it emits.

const TOAST_STRIKE := "FISHING_TOAST_STRIKE"
const TIP_PREFIX := "FISHING_TIP_"
const TIP_KEYS := 6
## d_max by species index (mackerel, mahi, tuna, marlin).
const D_MAX := [40.0, 80.0, 120.0, 200.0]

## Tolerance for float clocks and meter sums (300 ticks of 0.05 s).
const _EPS := 1e-6
## The gaff meter counts as full from here.
const _GAFF_FULL := 0.999
## Depth change rate (unit / s) toward the fish's target depth.
const _Z_RATE := 0.5
## In the Landing the fish comes aboard at this speed (m / s).
const _ABOARD_MPS := 2.0

## Scratch for drawing hint spot types (reused; the rules run on one thread).
static var _pool: Array[int] = []


## The trip's starting state on every peer. `slots` holds each lane's pre-rolled
## Array[FishingPlanSlot], in slot order.
static func new_state(
	content: FishingContent, players: Array[PlayerSlot], seed: int, slots: Array
) -> FishingState:
	var st := FishingState.new()
	var trip := content.trip
	st.trip_id = trip.id
	st.trip_kind = trip.kind
	st.scheduled = trip.is_scheduled()
	st.k_rmin = trip.k_rmin
	st.trip_total_s = FishingPlanBuilder.trip_length_s(trip)
	if st.scheduled:
		st.fishing_end_t = st.trip_total_s
	else:
		st.fishing_end_t = trip.ride_out_s + trip.fishing_s
		st.fight_budget_s = trip.fight_cap_frac * trip.fishing_s
	st.overrun_end_t = st.fishing_end_t + FishingConst.LAST_CALL_OVERRUN_S
	_load_area(st, content)
	for p in players:
		var l := FishingLaneState.new()
		l.slot = p.slot_index
		l.peer = p.peer_id
		l.is_bot = p.is_bot
		l.ftp = p.ftp
		l.preferred_rpm = p.preferred_cadence_rpm
		l.relaxed_band = bool(p.options.get("relaxed_band", false))
		l.reel_pct = trip.reel_target(int(p.options.get("reel_pct", FishingConst.REEL_PCT_DEFAULT)))
		l.haptics_on = p.haptics_on
		l.autopilot = p.autopilot or p.is_bot
		l.phase_index = -1
		l.rng = FishingRandom.derive(seed, p.slot_index, FishingRandom.STREAM_LANE)
		l.pull_rng = FishingRandom.derive(seed, p.slot_index, FishingRandom.STREAM_PULL)
		FishingPullScheduler.init_lane(l.pull, seed, p.slot_index)
		if p.slot_index < slots.size():
			l.slots.assign(slots[p.slot_index])
		st.lanes.append(l)
	return st


static func _load_area(st: FishingState, content: FishingContent) -> void:
	st.area_spots = content.spot_types()
	st.area_affinity.clear()
	for i in st.area_spots.size():
		for sp in FishingConst.SPECIES.size():
			st.area_affinity.append(content.affinity(st.area_spots[i], sp))
	var dr: Variant = content.area.get("distance_m", [])
	if dr is Array and (dr as Array).size() == 2:
		st.spot_d_lo = float(dr[0])
		st.spot_d_hi = float(dr[1])


static func step(state: FishingState, inputs: Array, dt: float) -> FishingStepOut:
	var out := FishingStepOut.new()
	state.tick += 1
	state.t = state.tick * dt
	for inp: FishingLaneInput in inputs:
		var l := state.lane(inp.slot)
		if l == null or not inp.has_phase:
			continue
		_step_lane(state, l, inp, dt, out)
	_team_step(state, dt, out)
	_check_end(state, out)
	return out


# --- One lane ------------------------------------------------------------------------------


static func _step_lane(
	st: FishingState, l: FishingLaneState, inp: FishingLaneInput, dt: float, out: FishingStepOut
) -> void:
	_read_inputs(l, inp, dt)
	# Intents: the fallback, the summary, and this tick's confirm and spot moves.
	var confirm := false
	var spot_dir := 0
	for raw: Variant in inp.intents:
		if not raw is Dictionary:
			continue
		var it: Dictionary = raw
		if FishingIntents.is_deliberate(it):
			l.fallback = false
		match str(it.get("k", "")):
			FishingIntents.CONFIRM:
				confirm = true
			FishingIntents.SPOT:
				spot_dir += int(it.get("dir", 0))
			FishingIntents.SUMMARY:
				_store_summary(l, it)
	if inp.phase_index != l.phase_index:
		_leave(st, l, out)
		l.phase_index = inp.phase_index
		l.phase_kind = inp.phase_kind
		_enter(st, l, _zone_of(inp), out)
	else:
		l.state_t += dt
	_update_stagger(st, l, inp)
	match l.state:
		FishingConst.ST_RIDE_OUT:
			_tick_ride_out(l, out)
		FishingConst.ST_FIGHT:
			_tick_fight(st, l, inp, dt, out)
		FishingConst.ST_LANDING:
			_tick_landing(st, l, inp, dt, out)
		FishingConst.ST_HOME:
			pass
		_:
			_tick_reel(st, l, inp, dt, confirm, spot_dir, out)


static func _read_inputs(l: FishingLaneState, inp: FishingLaneInput, dt: float) -> void:
	l.power_w = inp.power_w
	l.applied_target_w = inp.applied_target_w
	if not l.ema_ready:
		l.cadence_ema = inp.cadence_rpm
		l.ema_ready = true
	else:
		var k := 1.0 - exp(-dt / FishingConst.CADENCE_TAU_S)
		l.cadence_ema += (inp.cadence_rpm - l.cadence_ema) * k
	l.cadence_stale = inp.cadence_age_s > FishingConst.STALE_S
	l.stale = inp.age_s > FishingConst.STALE_S or not inp.connected
	l.rescue_now = l.rescue or inp.rescue


## The rider's summary intent: total XP, species records (kg x 10 on the wire) and the equipped
## cosmetics. Only the first one counts.
static func _store_summary(l: FishingLaneState, it: Dictionary) -> void:
	if l.summary_received:
		return
	l.summary_received = true
	l.summary_xp = maxi(int(it.get("xp", 0)), 0)
	var rec: Variant = it.get("rec", {})
	if rec is Dictionary:
		for k: Variant in rec:
			if FishingConst.SPECIES.has(str(k)):
				l.records[str(k)] = maxf(float(rec[k]), 0.0) / 10.0
	var cos: Variant = it.get("cos", [])
	if cos is Array:
		for i in mini((cos as Array).size(), l.cosmetics.size()):
			l.cosmetics[i] = maxi(int(cos[i]), 0)


## The lane state family a phase puts the lane in (the Reel's sub-states start at PICK).
static func _zone_of(inp: FishingLaneInput) -> int:
	if inp.is_cooldown or inp.phase_kind == Wl.COOLDOWN:
		return FishingConst.ST_HOME
	match inp.phase_kind:
		Wl.WARMUP:
			return FishingConst.ST_RIDE_OUT
		Wl.WORK:
			return FishingConst.ST_LANDING if inp.phase_mode == Wl.SIM else FishingConst.ST_FIGHT
	return FishingConst.ST_PICK


static func _set_state(l: FishingLaneState, s: int) -> void:
	l.state = s
	l.state_t = 0.0


## Finishes whatever the lane was doing in the phase that just ended.
static func _leave(st: FishingState, l: FishingLaneState, out: FishingStepOut) -> void:
	match l.state:
		FishingConst.ST_FIGHT:
			FishingPullScheduler.end(l.pull)
			l.fish.run_active = false
			l.longest_fight_s = maxf(l.longest_fight_s, l.fight_t)
		FishingConst.ST_LANDING:
			if not l.resolved:
				_land(st, l, out)
			l.last_fight_len_s = l.fight_t + l.landing_t
			l.fight_budget_used_s += l.last_fight_len_s
	l.end_sent = false


static func _enter(st: FishingState, l: FishingLaneState, zone: int, out: FishingStepOut) -> void:
	match zone:
		FishingConst.ST_HOME:
			_set_state(l, FishingConst.ST_HOME)
			# The cool-down clears every band itself and refuses directives.
			l.pub_lo = 0
			l.pub_hi = 0
			l.in_band = false
			l.hook_set = false
		FishingConst.ST_RIDE_OUT:
			_set_state(l, FishingConst.ST_RIDE_OUT)
			l.tip_n = 0
		FishingConst.ST_FIGHT:
			_begin_fight(st, l, out)
		FishingConst.ST_LANDING:
			_begin_landing(l, out)
		_:
			_begin_reel(st, l)


## Rescue, AFK and stale telemetry stagger the lane; play resumes 10 s after the cause ends.
## Every edge goes to the pull scheduler whatever the lane state (its API: "any state"), so a
## stagger that outlives a Fight never leaves it staggered, and one that ends in the Reel still
## pauses the next Fight's pull clock until 10 s after it ended.
static func _update_stagger(st: FishingState, l: FishingLaneState, inp: FishingLaneInput) -> void:
	var cause := l.rescue_now or l.afk or inp.afk or l.stale
	if cause and not l.stagger_on:
		l.stagger_on = true
		l.staggered = true
		l.resume_t = 0.0
		FishingPullScheduler.set_staggered(l.pull, true, st.t)
	elif not cause and l.stagger_on:
		l.stagger_on = false
		l.resume_t = st.t + FishingConst.STAGGER_RESUME_S
		FishingPullScheduler.set_staggered(l.pull, false, st.t)
	if l.staggered and not l.stagger_on and st.t + _EPS >= l.resume_t:
		l.staggered = false
		l.resume_t = 0.0


## Publishes a band when its rounded edges change.
static func _publish(l: FishingLaneState, lo: float, hi: float, out: FishingStepOut) -> void:
	var ilo := roundi(lo)
	var ihi := roundi(hi)
	if ilo == l.pub_lo and ihi == l.pub_hi:
		return
	l.pub_lo = ilo
	l.pub_hi = ihi
	out.bands.append([l.peer, ilo, ihi])


## A band's low edge (brief 2.3, 4.6.3 check): never under 65 rpm, above the 45 rpm rescue
## trigger, whatever the rider's preferred cadence (a profile allows 30-160 rpm).
static func band_low(centre: float, half: float) -> float:
	return maxf(FishingConst.BAND_LOW_MIN, centre - half)


## Publishes a fixed-width band around `centre` (ride out practice, lure, idle): low edge
## max(65, centre - half), high edge low + 2 x half; in band = the EMA cadence inside it.
static func _publish_fixed(
	l: FishingLaneState, centre: float, half: float, out: FishingStepOut
) -> void:
	var lo := band_low(centre, half)
	var hi := lo + 2.0 * half
	_publish(l, lo, hi, out)
	l.in_band = l.cadence_ema >= lo and l.cadence_ema <= hi


static func _toast(l: FishingLaneState, key: String, out: FishingStepOut) -> void:
	if not l.is_bot:
		out.toasts.append([key, [], l.peer])


# --- Ride out --------------------------------------------------------------------------------


static func _tick_ride_out(l: FishingLaneState, out: FishingStepOut) -> void:
	_publish_fixed(l, l.preferred_rpm, FishingConst.PRACTICE_HALF, out)
	if l.state_t + _EPS >= FishingConst.TIP_EVERY_S * float(l.tip_n + 1):
		_toast(l, TIP_PREFIX + str(l.tip_n % TIP_KEYS + 1), out)
		l.tip_n += 1


# --- Reel: pick, cast, reel, strike ---------------------------------------------------------


static func _begin_reel(st: FishingState, l: FishingLaneState) -> void:
	l.reel_t = 0.0
	l.rebite_t = -1.0
	l.hook_set = false
	l.sched_bit = false
	l.lure_d = 0.0
	l.spot_type = -1
	l.spot_strength = 0.0
	l.r_min_s = maxf(FishingConst.R_MIN_S, st.k_rmin * l.last_fight_len_s)
	l.fish.sp = FishingConst.SP_NONE
	l.fish.off_line = false
	l.fish.replacement = false
	l.fish.run_active = false
	l.fight_slot = -1
	l.strain = 0.0
	l.slack = 0.0
	l.gaff = 0.0
	if l.next_slot < l.slots.size():
		_set_state(l, FishingConst.ST_PICK)
		_new_hints(st, l)
	else:
		_go_idle(l)


static func _go_idle(l: FishingLaneState) -> void:
	_set_state(l, FishingConst.ST_IDLE)
	l.selected = -1
	l.hints.clear()


## Draws HINTS_PER_CAST of the area's spot types at seeded distances, strength = affinity for the
## next slot's species x U[0.7, 1]; sorted by distance (left to right on screen).
static func _new_hints(st: FishingState, l: FishingLaneState) -> void:
	var n_area := st.area_spots.size()
	var n := mini(FishingConst.HINTS_PER_CAST, n_area)
	var sp := l.slots[l.next_slot].sp if l.next_slot < l.slots.size() else 0
	var n_sp := FishingConst.SPECIES.size()
	_pool.resize(n_area)
	for i in n_area:
		_pool[i] = i
	l.hints.resize(3 * n)
	for i in n:
		var j := l.rng.range_i(i, n_area - 1)
		var pos := _pool[j]
		_pool[j] = _pool[i]
		_pool[i] = pos
		var d := l.rng.range_f(st.spot_d_lo, st.spot_d_hi)
		var aff := st.area_affinity[pos * n_sp + clampi(sp, 0, n_sp - 1)]
		var s := aff * l.rng.range_f(FishingConst.STRENGTH_JITTER_LO, 1.0)
		var k := i
		while k > 0 and l.hints[3 * (k - 1) + 1] > d:
			l.hints[3 * k] = l.hints[3 * (k - 1)]
			l.hints[3 * k + 1] = l.hints[3 * (k - 1) + 1]
			l.hints[3 * k + 2] = l.hints[3 * (k - 1) + 2]
			k -= 1
		l.hints[3 * k] = float(st.area_spots[pos])
		l.hints[3 * k + 1] = d
		l.hints[3 * k + 2] = s
	l.selected = 0
	l.scan_t = 0.0
	l.scan_pause_t = 0.0
	l.pick_t = 0.0


static func _tick_reel(
	st: FishingState,
	l: FishingLaneState,
	inp: FishingLaneInput,
	dt: float,
	confirm: bool,
	spot_dir: int,
	out: FishingStepOut
) -> void:
	l.reel_t += dt
	if l.state == FishingConst.ST_IDLE or l.next_slot >= l.slots.size():
		if l.state != FishingConst.ST_IDLE:
			_go_idle(l)
		_tick_idle(l, dt, out)
		return
	if l.hook_set:
		_request_end(l, inp, out)
		return
	var slot := l.slots[l.next_slot]
	if not st.scheduled and l.state != FishingConst.ST_STRIKE and _no_more_bites(st, l, slot):
		_go_idle(l)
		_tick_idle(l, dt, out)
		return
	_publish_fixed(l, l.preferred_rpm + slot.band_offset, FishingConst.LURE_HALF, out)
	if st.scheduled and not l.sched_bit and not inp.phase_open_ended:
		if inp.phase_remaining_s <= FishingConst.SCHEDULED_BITE_LEAD_S + _EPS:
			_scheduled_bite(l, slot, out)
			return
	match l.state:
		FishingConst.ST_PICK:
			_tick_pick(st, l, dt, confirm, spot_dir, out)
		FishingConst.ST_CAST:
			if l.state_t + _EPS >= FishingConst.CAST_S:
				_set_state(l, FishingConst.ST_REEL)
		FishingConst.ST_REEL:
			_tick_lure(st, l, dt, out)
			if l.state == FishingConst.ST_REEL and not st.scheduled:
				_bite_check(st, l, slot, dt, out)
		FishingConst.ST_STRIKE:
			_tick_strike(st, l, inp, slot, confirm, out)


static func _tick_idle(l: FishingLaneState, dt: float, out: FishingStepOut) -> void:
	_publish_fixed(l, l.preferred_rpm, FishingConst.PRACTICE_HALF, out)
	if l.lure_d > 0.0:
		l.lure_d = maxf(0.0, l.lure_d - _lure_speed(l) * dt)


static func _lure_speed(l: FishingLaneState) -> float:
	return FishingConst.LURE_MPS * maxf(l.cadence_ema, 0.0) / FishingConst.LURE_REF_RPM


## Free and Base: true when no bite can come any more in this Reel (fishing over or last call at
## the earliest possible bite), so the lane reels out quietly.
static func _no_more_bites(st: FishingState, l: FishingLaneState, slot: FishingPlanSlot) -> bool:
	if st.t + _EPS >= st.fishing_end_t:
		return true
	var earliest := st.t + maxf(0.0, l.r_min_s - l.reel_t)
	return last_call_blocks(st, l, slot, earliest)


## Last call (brief 2.4): a bite at game time `at` is refused when the fight's max_s + 30 s would
## end more than 5 min after fishing ends, or when the fight time used + T_nom + 30 s would pass
## fight_cap_frac x fishing_s.
static func last_call_blocks(
	st: FishingState, l: FishingLaneState, slot: FishingPlanSlot, at: float
) -> bool:
	if at + slot.max_s + FishingConst.SLOT_GAP_S > st.overrun_end_t + _EPS:
		return true
	return l.fight_budget_used_s + slot.budget_s() > st.fight_budget_s + _EPS


static func _tick_pick(
	st: FishingState,
	l: FishingLaneState,
	dt: float,
	confirm: bool,
	spot_dir: int,
	out: FishingStepOut
) -> void:
	if l.hint_count() == 0:
		_new_hints(st, l)
	var n := l.hint_count()
	if l.auto_plays():
		_cast(l, FishingAutopilot.pick(l.hints), out)
		return
	if spot_dir != 0:
		l.selected = posmod(l.selected + spot_dir, n)
		l.scan_pause_t = FishingConst.SCAN_PAUSE_S
		l.scan_t = 0.0
		l.pick_t = 0.0
	if confirm:
		_cast(l, l.selected, out)
		return
	l.pick_t += dt
	if l.scan_pause_t > 0.0:
		l.scan_pause_t = maxf(0.0, l.scan_pause_t - dt)
	else:
		l.scan_t += dt
		if l.scan_t + _EPS >= FishingConst.SCAN_INTERVAL_S:
			l.scan_t -= FishingConst.SCAN_INTERVAL_S
			l.selected = posmod(l.selected + 1, n)
	if l.pick_t + _EPS >= auto_confirm_s(n):
		_cast(l, l.selected, out)


## A pick auto-confirms after two full scan cycles without input.
static func auto_confirm_s(hints: int) -> float:
	return FishingConst.AUTO_CONFIRM_CYCLES * hints * FishingConst.SCAN_INTERVAL_S


static func _cast(l: FishingLaneState, i: int, out: FishingStepOut) -> void:
	i = clampi(i, 0, l.hint_count() - 1)
	l.selected = i
	l.spot_type = int(l.hints[3 * i])
	l.lure_d = l.hints[3 * i + 1]
	l.spot_strength = l.hints[3 * i + 2]
	_set_state(l, FishingConst.ST_CAST)
	out.events.append(FishingEvents.cast(l.slot, i, l.spot_type, l.lure_d))


static func _tick_lure(
	st: FishingState, l: FishingLaneState, dt: float, out: FishingStepOut
) -> void:
	l.lure_d -= _lure_speed(l) * dt
	if l.lure_d <= FishingConst.RECAST_D:
		l.lure_d = FishingConst.RECAST_D
		_set_state(l, FishingConst.ST_PICK)
		_new_hints(st, l)
		if l.auto_plays():
			_cast(l, FishingAutopilot.pick(l.hints), out)


## The bite hazard per second (brief 2.4): (0.35 + 0.65 strength) / 90 in the lure band, a
## quarter outside it, x2 in a Frenzy; 0 before R_min and while staggered.
static func bite_hazard(st: FishingState, l: FishingLaneState) -> float:
	if l.staggered or l.reel_t + _EPS < l.r_min_s:
		return 0.0
	var h := (
		(FishingConst.HAZARD_BASE + FishingConst.HAZARD_STRENGTH * l.spot_strength)
		/ FishingConst.HAZARD_DIV_S
	)
	if not l.in_band:
		h *= FishingConst.HAZARD_OUT_OF_BAND
	if st.t < l.frenzy_until_t:
		h *= FishingConst.FRENZY_MULT
	return h


## Bites while reeling: a missed fish's re-bite, the forced bite at R_min + 240 s, or the hazard.
static func _bite_check(
	st: FishingState, l: FishingLaneState, slot: FishingPlanSlot, dt: float, out: FishingStepOut
) -> void:
	if l.staggered:
		return
	if l.rebite_t >= 0.0:
		if st.t + _EPS >= l.rebite_t:
			_bite(l, slot, out)
		return
	if l.reel_t + _EPS < l.r_min_s:
		return
	if l.reel_t + _EPS >= l.r_min_s + FishingConst.FORCED_BITE_AFTER_S:
		_bite(l, slot, out)
		return
	if l.rng.unit() < bite_hazard(st, l) * dt:
		_bite(l, slot, out)


static func _bite(l: FishingLaneState, slot: FishingPlanSlot, out: FishingStepOut) -> void:
	l.rebite_t = -1.0
	_set_state(l, FishingConst.ST_STRIKE)
	out.events.append(FishingEvents.bite(l.slot, slot.sp))
	if not l.autopilot:
		_toast(l, TOAST_STRIKE, out)


## Scheduled trips: the bite comes 4 s before the fixed Reel ends and the fish hooks itself (the
## plan's Fight starts on its own when the Reel ends).
static func _scheduled_bite(
	l: FishingLaneState, slot: FishingPlanSlot, out: FishingStepOut
) -> void:
	if l.state == FishingConst.ST_PICK and l.hint_count() > 0:
		var i := FishingAutopilot.pick(l.hints) if l.auto_plays() else l.selected
		i = clampi(i, 0, l.hint_count() - 1)
		l.spot_type = int(l.hints[3 * i])
		l.lure_d = l.hints[3 * i + 1]
		l.spot_strength = l.hints[3 * i + 2]
	l.sched_bit = true
	l.hook_set = true
	l.rebite_t = -1.0
	_set_state(l, FishingConst.ST_STRIKE)
	out.events.append(FishingEvents.bite(l.slot, slot.sp))
	out.events.append(FishingEvents.strike_ok(l.slot, slot.sp))


## The 4 s strike prompt: a confirm (any via) sets the hook, Autopilot and the zero-input fallback
## at 0.5 s; a miss loses the fish and the same species bites again 20-40 s later.
static func _tick_strike(
	st: FishingState,
	l: FishingLaneState,
	inp: FishingLaneInput,
	slot: FishingPlanSlot,
	confirm: bool,
	out: FishingStepOut
) -> void:
	var auto_now := l.auto_plays() and l.state_t + _EPS >= FishingConst.AUTOPILOT_STRIKE_S
	if confirm or auto_now:
		l.hook_set = true
		out.events.append(FishingEvents.strike_ok(l.slot, slot.sp))
		_request_end(l, inp, out)
	elif l.state_t + _EPS >= FishingConst.STRIKE_WINDOW_S:
		out.events.append(FishingEvents.strike_miss(l.slot, slot.sp))
		l.rebite_t = st.t + l.rng.range_f(FishingConst.REBITE_MIN_S, FishingConst.REBITE_MAX_S)
		_set_state(l, FishingConst.ST_REEL)


## Ends the lane's open-ended phase, once and only after its min_s.
static func _request_end(l: FishingLaneState, inp: FishingLaneInput, out: FishingStepOut) -> void:
	if l.end_sent or not inp.phase_open_ended:
		return
	if inp.phase_elapsed_s + _EPS < inp.phase_min_s:
		return
	l.end_sent = true
	out.end_phase.append(l.peer)


# --- Fight -----------------------------------------------------------------------------------


static func _begin_fight(st: FishingState, l: FishingLaneState, out: FishingStepOut) -> void:
	_set_state(l, FishingConst.ST_FIGHT)
	var f := l.fish
	l.hook_set = false
	if l.next_slot >= l.slots.size():
		f.sp = FishingConst.SP_NONE
		l.fight_slot = -1
		return
	var slot := l.slots[l.next_slot]
	l.fight_slot = l.next_slot
	l.next_slot += 1
	l.fights_started += 1
	f.sp = slot.sp
	f.slot = slot.index
	f.s = 1.0
	f.d_max = d_max_of(slot.sp)
	f.d = minf(l.lure_d, f.d_max) if l.lure_d > 0.0 else 0.5 * f.d_max
	f.z = 0.5
	f.strength = clampf(l.spot_strength, 0.0, 1.0)
	f.replacement = false
	f.scheduled = slot.scheduled
	f.runs_fired = 0
	f.run_active = false
	f.run_end_t = 0.0
	f.last_jump_t = -1000.0
	f.hooked_t = st.t
	f.replace_at_t = -1.0
	f.off_line = false
	f.kg = slot.kg * (1.0 + FishingConst.KG_STRENGTH * f.strength)
	l.strain = 0.0
	l.slack = 0.0
	l.fight_t = 0.0
	l.landing_t = 0.0
	l.gaff = 0.0
	l.resolved = false
	l.fight_start_t = st.t
	l.hookup_count = 1
	for i in l.overlap_s.size():
		l.overlap_s[i] = 0.0
	l.band_center = _band_target(l, slot)
	_band_edges(l)
	_publish(l, l.band_lo, l.band_hi, out)
	FishingPullScheduler.begin(l.pull, slot, st.t, l.ftp, l.pull_rng)
	# Already in step with every stagger edge; re-asserted so the Fight starts from the lane's state.
	FishingPullScheduler.set_staggered(l.pull, l.stagger_on, st.t)
	st.fish_started += 1
	st.expected_points += float(base_points(f.kg))
	out.events.append(FishingEvents.hookup(l.slot, f.sp, l.fights_started, slot.scheduled))
	if st.scheduled or st.lanes.size() < 2:
		return
	# Frenzy: every other reeling rider's hazard doubles for 60 s (it counts once they pass
	# R_min). Lanes in a fight, a strike or idle could not bite within it anyway.
	var reeling := false
	for o in st.lanes:
		if o != l and o.state >= FishingConst.ST_PICK and o.state <= FishingConst.ST_REEL:
			o.frenzy_until_t = st.t + FishingConst.FRENZY_S
			reeling = true
	if reeling:
		out.events.append(FishingEvents.frenzy(l.slot))


## The species' farthest distance (40, 80, 120, 200 m, mackerel to marlin).
static func d_max_of(sp: int) -> float:
	return float(D_MAX[sp]) if sp >= 0 and sp < D_MAX.size() else 80.0


## The tension band's centre target: preferred + offset + run shift - 10 x (1 - S).
static func _band_target(l: FishingLaneState, slot: FishingPlanSlot) -> float:
	var c := l.preferred_rpm + slot.band_offset
	if l.fish.run_active:
		c += slot.run_band_shift
	return c - FishingConst.BAND_STAMINA_RPM * (1.0 - l.fish.s)


## Low edge max(65, centre - 8); width 16 (22 relaxed).
static func _band_edges(l: FishingLaneState) -> void:
	var w := FishingConst.BAND_WIDTH_RELAXED if l.relaxed_band else FishingConst.BAND_WIDTH
	l.band_lo = band_low(l.band_center, FishingConst.BAND_LOW_HALF)
	l.band_hi = l.band_lo + w


static func _tick_fight(
	st: FishingState, l: FishingLaneState, inp: FishingLaneInput, dt: float, out: FishingStepOut
) -> void:
	var f := l.fish
	if f.sp < 0 or l.fight_slot < 0:
		return
	var slot := l.slots[l.fight_slot]
	l.fight_t += dt
	l.fight_total_s += dt
	if f.off_line and st.t + _EPS >= f.replace_at_t:
		_hook_replacement(l, out)
	var frozen := l.staggered
	if f.run_active and st.t + _EPS >= f.run_end_t:
		f.run_active = false
	# The centre slides toward its target at <= 3 rpm/s; frozen in a stagger.
	if not frozen:
		var max_step := FishingConst.BAND_SLIDE_RPM_S * dt
		l.band_center += clampf(_band_target(l, slot) - l.band_center, -max_step, max_step)
		_band_edges(l)
	_publish(l, l.band_lo, l.band_hi, out)
	var below := l.cadence_ema < l.band_lo
	var above := l.cadence_ema > l.band_hi
	l.in_band = not below and not above
	if l.in_band:
		l.band_s += dt
	if frozen:
		f.d = minf(f.d_max, f.d + FishingConst.SWIM_OUT_MPS * dt)
		_skip_due_runs(f, slot)
	elif not f.off_line:
		if not l.cadence_stale:
			_meters(l, below, above, dt)
		_tire(l, slot, dt)
		if l.strain >= 1.0:
			_lose(st, l, true, out)
		elif l.slack >= 1.0:
			_lose(st, l, false, out)
		if not f.off_line:
			_move_fish(f, slot, dt)
			_runs(st, l, slot, out)
	var dirs := FishingPullScheduler.step(l.pull, slot, st.t, l.ftp, l.pull_rng)
	if not l.stagger_on:
		for d: Variant in dirs:
			out.directives.append([l.peer, d])
	if not f.off_line and f.s <= 0.0 and f.d <= FishingConst.D_NEAR + _EPS:
		_request_end(l, inp, out)


## Strain fills at 1/6 per second below the band, slack above it; the other drains at 1/12.
static func _meters(l: FishingLaneState, below: bool, above: bool, dt: float) -> void:
	var fill := dt / FishingConst.METER_FILL_S
	var drain := dt / FishingConst.METER_DRAIN_S
	if below:
		l.strain = minf(1.0, l.strain + fill)
		l.slack = maxf(0.0, l.slack - drain)
	elif above:
		l.slack = minf(1.0, l.slack + fill)
		l.strain = maxf(0.0, l.strain - drain)
	else:
		l.strain = maxf(0.0, l.strain - drain)
		l.slack = maxf(0.0, l.slack - drain)
	if l.strain > 1.0 - _EPS:
		l.strain = 1.0
	if l.slack > 1.0 - _EPS:
		l.slack = 1.0


## Tiring: in band dS/dt = -min(1.2, P / applied target) / T_nom; out of band +0.25 / T_nom.
static func _tire(l: FishingLaneState, slot: FishingPlanSlot, dt: float) -> void:
	var t_nom := maxf(slot.t_nom_s, 1.0)
	if l.in_band:
		var ratio := l.power_w / l.applied_target_w if l.applied_target_w > 0.0 else 1.0
		l.fish.s -= minf(FishingConst.TIRE_MAX_RATIO, maxf(ratio, 0.0)) / t_nom * dt
	else:
		l.fish.s += FishingConst.RECOVER_RATE / t_nom * dt
	l.fish.s = clampf(l.fish.s, 0.0, 1.0)
	if l.fish.s < _EPS:
		l.fish.s = 0.0


## d moves toward 10 + (d_max - 10) S (d_max on a run), <= 4 m/s out and <= 2 m/s in; z toward
## 0.25 + 0.75 S (1 on a run, the surface on a jump).
static func _move_fish(f: FishingFishState, slot: FishingPlanSlot, dt: float) -> void:
	var td := FishingConst.D_NEAR + (f.d_max - FishingConst.D_NEAR) * f.s
	if f.run_active:
		td = f.d_max
	if td > f.d:
		f.d = minf(td, f.d + FishingConst.D_OUT_MPS * dt)
	else:
		f.d = maxf(td, f.d - FishingConst.D_IN_MPS * dt)
	var tz := FishingConst.Z_BASE + (1.0 - FishingConst.Z_BASE) * f.s
	if f.run_active:
		tz = 0.0 if slot.run_kind == FishingSpeciesDef.RUN_JUMP else 1.0
	f.z += clampf(tz - f.z, -_Z_RATE * dt, _Z_RATE * dt)


## Run k (0-based) of n is due once S <= 1 - (k + 1) / (n + 1).
static func run_due(f: FishingFishState, slot: FishingPlanSlot) -> bool:
	var n := slot.run_count()
	var k := f.runs_fired
	return k < n and f.s <= 1.0 - float(k + 1) / float(n + 1) + _EPS


## A run that comes due during a stagger is skipped (counted fired, no event).
static func _skip_due_runs(f: FishingFishState, slot: FishingPlanSlot) -> void:
	while run_due(f, slot):
		f.runs_fired += 1


## Fires the next run when it is due and no run is on; a jump also waits for its gap. A run the
## scheduler refuses counts as fired, with no event.
static func _runs(
	st: FishingState, l: FishingLaneState, slot: FishingPlanSlot, out: FishingStepOut
) -> void:
	var f := l.fish
	if f.run_active or not run_due(f, slot):
		return
	var jump := slot.run_kind == FishingSpeciesDef.RUN_JUMP
	if jump and FishingPullScheduler.run_blocked_by_gap(l.pull, slot, st.t):
		return
	var k := f.runs_fired
	var n := slot.run_count()
	f.runs_fired += 1
	if not FishingPullScheduler.start_run(l.pull, slot, k, st.t, l.ftp):
		return
	var dur := slot.run_dur_s(k)
	f.run_active = true
	f.run_end_t = st.t + dur
	if l.pull.run_active and l.pull.run_end_t > st.t:
		f.run_end_t = l.pull.run_end_t
	if jump:
		f.last_jump_t = st.t
		var leaps := slot.leaps[k] if k < slot.leaps.size() else 2
		out.events.append(FishingEvents.jump(l.slot, k + 1, n, dur, leaps))
	else:
		out.events.append(FishingEvents.run(l.slot, k + 1, n, dur))


## A snap (strain) or a thrown hook (slack): the fish is lost and the meters reset; a
## same-species replacement hooks itself 5 s later, keeping S and the pull schedule.
static func _lose(st: FishingState, l: FishingLaneState, snap: bool, out: FishingStepOut) -> void:
	l.lost_lines += 1
	l.strain = 0.0
	l.slack = 0.0
	l.fish.off_line = true
	l.fish.replace_at_t = st.t + FishingConst.REPLACEMENT_DELAY_S
	out.events.append(FishingEvents.snap(l.slot) if snap else FishingEvents.thrown(l.slot))


static func _hook_replacement(l: FishingLaneState, out: FishingStepOut) -> void:
	var f := l.fish
	var slot := l.slots[l.fight_slot]
	f.off_line = false
	f.replace_at_t = -1.0
	f.replacement = true
	f.kg = slot.kg * (1.0 + FishingConst.KG_STRENGTH * f.strength) * FishingConst.REPLACEMENT_KG
	out.events.append(FishingEvents.replacement(l.slot, f.sp))


# --- Landing ---------------------------------------------------------------------------------


static func _begin_landing(l: FishingLaneState, out: FishingStepOut) -> void:
	_set_state(l, FishingConst.ST_LANDING)
	l.landing_t = 0.0
	l.gaff = 0.0
	l.resolved = false
	l.haptic_sent = false
	l.haptic_at_s = l.rng.range_f(FishingConst.HAPTIC_AT_MIN_S, FishingConst.HAPTIC_AT_MAX_S)
	l.in_band = false
	l.strain = 0.0
	l.slack = 0.0
	if l.pub_lo != 0 or l.pub_hi != 0:
		l.pub_lo = 0
		l.pub_hi = 0
		out.bands.append([l.peer, 0, 0])
	if l.fish.sp < 0 or l.fight_slot < 0:
		l.resolved = true
		return
	if l.fish.off_line:
		_hook_replacement(l, out)
	l.fish.run_active = false
	out.events.append(FishingEvents.landing(l.slot, l.fish.sp))


static func _tick_landing(
	st: FishingState, l: FishingLaneState, inp: FishingLaneInput, dt: float, out: FishingStepOut
) -> void:
	if l.fish.sp < 0:
		return
	var t0 := l.landing_t
	l.landing_t += dt
	l.fish.d = maxf(0.0, l.fish.d - _ABOARD_MPS * dt)
	l.fish.z = maxf(0.0, l.fish.z - _Z_RATE * dt)
	if t0 + _EPS < FishingConst.GAFF_S and not l.resolved:
		l.gaff = minf(1.0, l.gaff + gaff_rate(l.power_w, l.ftp) * dt)
	if not l.haptic_sent and l.landing_t + _EPS >= l.haptic_at_s:
		l.haptic_sent = true
		if haptic_allowed(l, inp):
			out.directives.append([l.peer, haptic_directive()])
	if not l.resolved and l.landing_t + _EPS >= FishingConst.GAFF_S:
		_land(st, l, out)


## The gaff meter's fill rate per second at power `p_w` (brief 2.4, BRIEF 3.5): max(0, P - CP) /
## (0.4 x CP x 15 s), counted only while P >= 1.2 x FTP; CP = the rider's FTP.
static func gaff_rate(p_w: float, ftp: float) -> float:
	if ftp <= 0.0 or p_w < FishingConst.SPRINT_FTP_FRAC * ftp:
		return 0.0
	return maxf(0.0, p_w - ftp) / (FishingConst.GAFF_CP_FRAC * ftp * FishingConst.GAFF_S)


## The last-run haptic (brief 2.7): never in the plan's first 300 s, in rescue, or to a rider who
## opted out.
static func haptic_allowed(l: FishingLaneState, inp: FishingLaneInput) -> bool:
	return (
		l.haptics_on
		and not l.rescue_now
		and inp.plan_elapsed_s + _EPS >= FishingConst.HAPTIC_PLAN_MIN_S
	)


static func haptic_directive() -> Dictionary:
	return {
		"mode": Wl.SIM,
		"haptic": FishingConst.HAPTIC_PCT,
		"duration_s": FishingConst.HAPTIC_S,
		"reason": "last_run",
		"source": "fishing"
	}


## round(20 x sqrt(kg)): a fish's points before grade and hookup.
static func base_points(kg: float) -> int:
	return roundi(FishingConst.POINTS_PER_SQRT_KG * sqrt(maxf(kg, 0.0)))


## Scores the Landing's fish: Trophy when the gaff meter is full (never a replacement or a
## scheduled fish), else Landed; points = round(20 sqrt(kg)) x grade x hookup.
static func _land(st: FishingState, l: FishingLaneState, out: FishingStepOut) -> void:
	l.resolved = true
	var f := l.fish
	if f.sp < 0 or l.fight_slot < 0:
		return
	if l.gaff >= _GAFF_FULL:
		l.gaff = 1.0
	var trophy := l.gaff >= 1.0 and not f.replacement and not f.scheduled
	var grade := FishingConst.GRADE_TROPHY if trophy else FishingConst.GRADE_LANDED
	var hk := FishingConst.hookup_mult(l.hookup_count)
	var pts := roundi(base_points(f.kg) * (FishingConst.TROPHY_MULT if trophy else 1.0) * hk)
	out.events.append(FishingEvents.landed(l.slot, f.sp, grade, f.kg, pts, hk))
	l.points += pts
	l.fish_landed += 1
	if trophy:
		l.trophies += 1
	if f.kg > l.biggest_kg:
		l.biggest_kg = f.kg
		l.biggest_sp = f.sp
	l.longest_fight_s = maxf(l.longest_fight_s, l.fight_t)
	var sp_id: String = FishingConst.SPECIES[f.sp]
	if f.kg > float(l.records.get(sp_id, 0.0)) and not l.record_species.has(f.sp):
		l.record_species.append(f.sp)
		l.new_records += 1
	l.catches.append({"sp": f.sp, "kg": f.kg, "grade": grade, "fight_s": l.fight_t, "points": pts})
	st.team_points += pts
	st.team_fish += 1
	st.catches.append(l.slot)
	st.catches.append(f.sp)
	st.catches.append(grade)
	while st.catches.size() > 3 * FishingConst.CATCH_BOARD:
		st.catches.remove_at(0)
	if st.scheduled:
		# The shared schedule overlaps the fights: expected points carry each fish's hookup bonus.
		var slot := l.slots[l.fight_slot]
		var started_kg := slot.kg * (1.0 + FishingConst.KG_STRENGTH * f.strength)
		st.expected_points += float(base_points(started_kg)) * (hk - 1.0)


# --- Team --------------------------------------------------------------------------------------


## Hookup level and Double Hookups: a fight that overlaps n fights (its own included) for 10 s
## scores the n-fight multiplier; double_hookup goes out when an overlap reaches 10 s.
static func _team_step(st: FishingState, dt: float, out: FishingStepOut) -> void:
	var fights := 0
	for l in st.lanes:
		if l.state == FishingConst.ST_FIGHT and l.fish.sp >= 0:
			fights += 1
	st.hookup_level = fights
	if fights < 2:
		return
	var reached := 0
	var top := mini(fights, FishingConst.HOOKUP_MULT.size() - 1)
	for l in st.lanes:
		if l.state != FishingConst.ST_FIGHT or l.fish.sp < 0:
			continue
		for m in range(2, top + 1):
			l.overlap_s[m] += dt
			if l.overlap_s[m] + _EPS >= FishingConst.HOOKUP_OVERLAP_S and l.hookup_count < m:
				l.hookup_count = m
				reached = maxi(reached, m)
	if reached >= 2:
		var lanes: Array[int] = []
		for l in st.lanes:
			if l.state == FishingConst.ST_FIGHT and l.fish.sp >= 0:
				lanes.append(l.slot)
		out.events.append(FishingEvents.double_hookup(lanes, reached))


## Free and Base: once fishing time is up and no lane has a fish on (Fight, Landing, a strike
## prompt or a set hook waiting for its Fight), the trip is over (once).
static func _check_end(st: FishingState, out: FishingStepOut) -> void:
	if st.scheduled or st.trip_over or st.t + _EPS < st.fishing_end_t:
		return
	for l in st.lanes:
		if l.in_fight() or l.state == FishingConst.ST_STRIKE or l.hook_set:
			return
	st.trip_over = true
	out.events.append(FishingEvents.trip_over())
	out.finished = "trip_over"
