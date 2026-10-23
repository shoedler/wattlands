class_name FishingFight
extends RefCounted
## The Fight (WORK ERG) and the Landing (WORK SIM 30 s), the same in Free Roam and workouts.
## Pure; FishingRules calls it.
##
## Fight: a cadence band (preferred + species offset + run shift - 10 x (1 - S), sliding at
## <= 3 rpm/s; low edge max(65, centre - 8), width 16 or 22 relaxed). Below the band strain fills
## at 1/6 per second, above it slack; the other drains at 1/12. Full strain snaps the line, full
## slack throws the hook: a same-species replacement hooks itself 5 s later (x 0.75 kg, never a
## trophy). In band the fish tires: dS/dt = -min(1.2, P / applied target) / T_nom; out of band
## it recovers at 0.25 / T_nom. Run k of n fires at S = 1 - (k + 1) / (n + 1); the pull scheduler
## sends every ERG change. Rescue, AFK, pause and stale telemetry stagger the fight: meters frozen,
## the fish swims out at 1 m/s, no requests, play resumes 10 s after the cause ends. The phase
## ends (end_phase) once S is 0 and the fish is within 10 m.
## Landing: the gaff meter fills while P >= 1.2 x FTP during the first 15 s: max(0, P - FTP) /
## (0.4 x FTP x 15 s); full = Trophy (x1.5 points). A last-run haptic (+3 % for 5 s, 3-6 s in)
## when allowed. Points = FishingConst.base_points(kg) x grade x hookup.

const EPS := 1e-6
## The gaff meter counts as full from here.
const GAFF_FULL := 0.999


static func begin(st: FishingState, r: FishingRiderState, out: FishingStepOut) -> void:
	FishingRules.set_action(r, FishingConst.A_FIGHT)
	var f := r.fish
	r.hook_set = false
	if r.next_slot >= r.slots.size():
		f.sp = FishingConst.SP_NONE
		r.fight_slot = -1
		return
	var slot := r.slots[r.next_slot]
	r.fight_slot = r.next_slot
	r.next_slot += 1
	r.fights_started += 1
	f.sp = slot.sp
	f.slot = slot.index
	f.s = 1.0
	var def_d := FishingRules.D_MAX_DEFAULT
	f.d_max = slot.d_max if slot.d_max > 0.0 else def_d
	f.d = clampf(absf(r.lure_dx), FishingConst.D_NEAR, f.d_max)
	f.hook_depth_m = maxf(slot.depth_m, 1.0)
	f.z = 1.0
	f.replacement = false
	f.scheduled = slot.scheduled
	f.runs_fired = 0
	f.run_active = false
	f.run_end_t = 0.0
	f.last_jump_t = -1000.0
	f.hooked_t = st.t
	f.replace_at_t = -1.0
	f.off_line = false
	f.kg = slot.kg
	r.target_sp = f.sp
	r.strain = 0.0
	r.slack = 0.0
	r.fight_t = 0.0
	r.landing_t = 0.0
	r.gaff = 0.0
	r.resolved = false
	r.fight_start_t = st.t
	r.hookup_count = 1
	for i in r.overlap_s.size():
		r.overlap_s[i] = 0.0
	r.band_center = _band_target(r, slot)
	_band_edges(r)
	FishingRules.publish(r, r.band_lo, r.band_hi, out)
	FishingPullScheduler.begin(r.pull, slot, st.t, r.ftp, r.pull_rng)
	FishingPullScheduler.set_staggered(r.pull, r.stagger_on, st.t)
	st.fish_started += 1
	st.expected_points += float(FishingConst.base_points(f.kg))
	out.events.append(FishingEvents.hookup(r.slot, f.sp, r.fights_started, slot.scheduled))


## The tension band's centre target: preferred + offset + run shift - 10 x (1 - S).
static func _band_target(r: FishingRiderState, slot: FishingPlanSlot) -> float:
	var c := r.preferred_rpm + slot.band_offset
	if r.fish.run_active:
		c += slot.run_band_shift
	return c - FishingConst.BAND_STAMINA_RPM * (1.0 - r.fish.s)


static func _band_edges(r: FishingRiderState) -> void:
	var w := FishingConst.BAND_WIDTH_RELAXED if r.relaxed_band else FishingConst.BAND_WIDTH
	r.band_lo = FishingRules.band_low(r.band_center, FishingConst.BAND_LOW_HALF)
	r.band_hi = r.band_lo + w


static func tick(
	st: FishingState, r: FishingRiderState, inp: FishingRiderInput, dt: float, out: FishingStepOut
) -> void:
	var f := r.fish
	if f.sp < 0 or r.fight_slot < 0:
		return
	var slot := r.slots[r.fight_slot]
	r.fight_t += dt
	r.fight_total_s += dt
	if f.off_line and st.t + EPS >= f.replace_at_t:
		_hook_replacement(r, out)
	var frozen := r.staggered
	if f.run_active and st.t + EPS >= f.run_end_t:
		f.run_active = false
	if not frozen:
		var max_step := FishingConst.BAND_SLIDE_RPM_S * dt
		r.band_center += clampf(_band_target(r, slot) - r.band_center, -max_step, max_step)
		_band_edges(r)
	FishingRules.publish(r, r.band_lo, r.band_hi, out)
	var below := r.cadence_ema < r.band_lo
	var above := r.cadence_ema > r.band_hi
	r.in_band = not below and not above
	if r.in_band:
		r.band_s += dt
	if frozen:
		f.d = minf(f.d_max, f.d + FishingConst.SWIM_OUT_MPS * dt)
		_skip_due_runs(f, slot)
	elif not f.off_line:
		if not r.cadence_stale:
			meters(r, below, above, dt)
		tire(r, slot, dt)
		if r.strain >= 1.0:
			_lose(st, r, true, out)
		elif r.slack >= 1.0:
			_lose(st, r, false, out)
		if not f.off_line:
			move_fish(f, slot, dt)
			_runs(st, r, slot, out)
	var dirs := FishingPullScheduler.step(r.pull, slot, st.t, r.ftp, r.pull_rng)
	if not r.stagger_on:
		for d: Variant in dirs:
			out.directives.append([r.peer, d])
	if not f.off_line and f.s <= 0.0 and f.d <= FishingConst.D_NEAR + EPS:
		FishingRules.request_end(r, inp, out)


## Strain fills at 1/6 per second below the band, slack above it; the other drains at 1/12.
static func meters(r: FishingRiderState, below: bool, above: bool, dt: float) -> void:
	var fill := dt / FishingConst.METER_FILL_S
	var drain := dt / FishingConst.METER_DRAIN_S
	if below:
		r.strain = minf(1.0, r.strain + fill)
		r.slack = maxf(0.0, r.slack - drain)
	elif above:
		r.slack = minf(1.0, r.slack + fill)
		r.strain = maxf(0.0, r.strain - drain)
	else:
		r.strain = maxf(0.0, r.strain - drain)
		r.slack = maxf(0.0, r.slack - drain)
	if r.strain > 1.0 - EPS:
		r.strain = 1.0
	if r.slack > 1.0 - EPS:
		r.slack = 1.0


## Tiring: in band dS/dt = -min(1.2, P / applied target) / T_nom; out of band +0.25 / T_nom.
static func tire(r: FishingRiderState, slot: FishingPlanSlot, dt: float) -> void:
	var t_nom := maxf(slot.t_nom_s, 1.0)
	if r.in_band:
		var ratio := r.power_w / r.applied_target_w if r.applied_target_w > 0.0 else 1.0
		r.fish.s -= minf(FishingConst.TIRE_MAX_RATIO, maxf(ratio, 0.0)) / t_nom * dt
	else:
		r.fish.s += FishingConst.RECOVER_RATE / t_nom * dt
	r.fish.s = clampf(r.fish.s, 0.0, 1.0)
	if r.fish.s < EPS:
		r.fish.s = 0.0


## d moves toward 10 + (d_max - 10) S (d_max on a run), <= 4 m/s out and <= 2 m/s in; z toward
## 0.25 + 0.75 S (1 on a run, the surface on a jump).
static func move_fish(f: FishingFishState, slot: FishingPlanSlot, dt: float) -> void:
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
	f.z += clampf(tz - f.z, -FishingConst.Z_RATE * dt, FishingConst.Z_RATE * dt)


## Run k (0-based) of n is due once S <= 1 - (k + 1) / (n + 1).
static func run_due(f: FishingFishState, slot: FishingPlanSlot) -> bool:
	var n := slot.run_count()
	var k := f.runs_fired
	return k < n and f.s <= 1.0 - float(k + 1) / float(n + 1) + EPS


static func _skip_due_runs(f: FishingFishState, slot: FishingPlanSlot) -> void:
	while run_due(f, slot):
		f.runs_fired += 1


## Fires the next run when due and no run is on; a jump also waits for its gap. A run the
## scheduler refuses counts as fired, with no event.
static func _runs(
	st: FishingState, r: FishingRiderState, slot: FishingPlanSlot, out: FishingStepOut
) -> void:
	var f := r.fish
	if f.run_active or not run_due(f, slot):
		return
	var jump := slot.run_kind == FishingSpeciesDef.RUN_JUMP
	if jump and FishingPullScheduler.run_blocked_by_gap(r.pull, slot, st.t):
		return
	var k := f.runs_fired
	var n := slot.run_count()
	f.runs_fired += 1
	if not FishingPullScheduler.start_run(r.pull, slot, k, st.t, r.ftp):
		return
	var dur := slot.run_dur_s(k)
	f.run_active = true
	f.run_end_t = st.t + dur
	if r.pull.run_active and r.pull.run_end_t > st.t:
		f.run_end_t = r.pull.run_end_t
	if jump:
		f.last_jump_t = st.t
		var leaps := slot.leaps[k] if k < slot.leaps.size() else 2
		out.events.append(FishingEvents.jump(r.slot, k + 1, n, dur, leaps))
	else:
		out.events.append(FishingEvents.run(r.slot, k + 1, n, dur))


static func _lose(st: FishingState, r: FishingRiderState, snap: bool, out: FishingStepOut) -> void:
	r.lost_lines += 1
	r.strain = 0.0
	r.slack = 0.0
	r.fish.off_line = true
	r.fish.replace_at_t = st.t + FishingConst.REPLACEMENT_DELAY_S
	out.events.append(FishingEvents.snap(r.slot) if snap else FishingEvents.thrown(r.slot))


static func _hook_replacement(r: FishingRiderState, out: FishingStepOut) -> void:
	var f := r.fish
	var slot := r.slots[r.fight_slot]
	f.off_line = false
	f.replace_at_t = -1.0
	f.replacement = true
	f.kg = slot.kg * FishingConst.REPLACEMENT_KG
	out.events.append(FishingEvents.replacement(r.slot, f.sp))


## The phase ended under the fight (end_phase, max_s, finished).
static func leave(r: FishingRiderState) -> void:
	FishingPullScheduler.end(r.pull)
	r.fish.run_active = false
	r.longest_fight_s = maxf(r.longest_fight_s, r.fight_t)


# --- Landing ---------------------------------------------------------------------------------


static func begin_landing(r: FishingRiderState, out: FishingStepOut) -> void:
	FishingRules.set_action(r, FishingConst.A_LAND)
	r.landing_t = 0.0
	r.gaff = 0.0
	r.resolved = false
	r.haptic_sent = false
	r.haptic_at_s = r.rng.range_f(FishingConst.HAPTIC_AT_MIN_S, FishingConst.HAPTIC_AT_MAX_S)
	r.in_band = false
	r.strain = 0.0
	r.slack = 0.0
	FishingRules.publish(r, 0.0, 0.0, out)
	if r.fish.sp < 0 or r.fight_slot < 0:
		r.resolved = true
		return
	if r.fish.off_line:
		_hook_replacement(r, out)
	r.fish.run_active = false
	out.events.append(FishingEvents.landing(r.slot, r.fish.sp))


static func tick_landing(
	st: FishingState, r: FishingRiderState, inp: FishingRiderInput, dt: float, out: FishingStepOut
) -> void:
	if r.fish.sp < 0:
		return
	var t0 := r.landing_t
	r.landing_t += dt
	r.fish.d = maxf(0.0, r.fish.d - FishingConst.ABOARD_MPS * dt)
	r.fish.z = maxf(0.0, r.fish.z - FishingConst.Z_RATE * dt)
	if t0 + EPS < FishingConst.GAFF_S and not r.resolved:
		r.gaff = minf(1.0, r.gaff + gaff_rate(r.power_w, r.ftp) * dt)
	if not r.haptic_sent and r.landing_t + EPS >= r.haptic_at_s:
		r.haptic_sent = true
		if haptic_allowed(r, inp):
			out.directives.append([r.peer, haptic_directive()])
	if not r.resolved and r.landing_t + EPS >= FishingConst.GAFF_S:
		land(st, r, out)


## The gaff meter's fill rate per second at power `p_w`: max(0, P - CP) / (0.4 x CP x 15 s),
## counted only while P >= 1.2 x FTP; CP = the rider's FTP.
static func gaff_rate(p_w: float, ftp: float) -> float:
	if ftp <= 0.0 or p_w < FishingConst.SPRINT_FTP_FRAC * ftp:
		return 0.0
	return maxf(0.0, p_w - ftp) / (FishingConst.GAFF_CP_FRAC * ftp * FishingConst.GAFF_S)


## The last-run haptic: never in the plan's first 300 s, to a rider who opted out, or in a
## stagger cause (rescue, AFK, pause, stale telemetry).
static func haptic_allowed(r: FishingRiderState, inp: FishingRiderInput) -> bool:
	return (
		r.haptics_on
		and not r.rescue_now
		and not r.afk
		and not inp.afk
		and not r.paused
		and not r.stale
		and inp.plan_elapsed_s + EPS >= FishingConst.HAPTIC_PLAN_MIN_S
	)


static func haptic_directive() -> Dictionary:
	return {
		"mode": Wl.SIM,
		"haptic": FishingConst.HAPTIC_PCT,
		"duration_s": FishingConst.HAPTIC_S,
		"reason": "last_run",
		"source": "fishing"
	}


## The Landing's phase ended: score the fish if the gaff window did not already.
static func leave_landing(st: FishingState, r: FishingRiderState, out: FishingStepOut) -> void:
	if not r.resolved:
		land(st, r, out)
	r.last_fight_len_s = r.fight_t + r.landing_t
	r.fight_budget_used_s += r.last_fight_len_s


## Scores the Landing's fish: Trophy when the gaff meter is full (never a replacement or a
## scheduled fish), else Landed; points = FishingConst.base_points(kg) x grade x hookup.
static func land(st: FishingState, r: FishingRiderState, out: FishingStepOut) -> void:
	r.resolved = true
	var f := r.fish
	if f.sp < 0 or r.fight_slot < 0:
		return
	if r.gaff >= GAFF_FULL:
		r.gaff = 1.0
	var trophy := r.gaff >= 1.0 and not f.replacement and not f.scheduled
	var grade := FishingConst.GRADE_TROPHY if trophy else FishingConst.GRADE_LANDED
	var hk := FishingConst.hookup_mult(r.hookup_count)
	var pts := roundi(
		FishingConst.base_points(f.kg) * (FishingConst.TROPHY_MULT if trophy else 1.0) * hk
	)
	out.events.append(FishingEvents.landed(r.slot, f.sp, grade, f.kg, pts, hk))
	r.points += pts
	r.fish_landed += 1
	if trophy:
		r.trophies += 1
	if f.kg > r.biggest_kg:
		r.biggest_kg = f.kg
		r.biggest_sp = f.sp
	r.longest_fight_s = maxf(r.longest_fight_s, r.fight_t)
	var sp_id: String = FishingConst.SPECIES[f.sp]
	if f.kg > float(r.records.get(sp_id, 0.0)) and not r.record_species.has(f.sp):
		r.record_species.append(f.sp)
		r.new_records += 1
	r.catches.append({"sp": f.sp, "kg": f.kg, "grade": grade, "fight_s": r.fight_t, "points": pts})
	st.team_points += pts
	st.team_fish += 1
	st.catches.append(r.slot)
	st.catches.append(f.sp)
	st.catches.append(roundi(f.kg * 10.0))
	st.catches.append(int(trophy))
	while st.catches.size() > 4 * FishingConst.CATCH_BOARD:
		st.catches.remove_at(0)
	if st.scheduled:
		st.expected_points += float(FishingConst.base_points(r.slots[r.fight_slot].kg)) * (hk - 1.0)


# --- Team (workouts) --------------------------------------------------------------------------


## Hookup level, and in workouts Double Hookups: a fight that overlaps n fights (its own
## included) for 10 s scores the n-fight multiplier; double_hookup goes out when an overlap
## reaches 10 s. Free Roam is competitive: no multiplier.
static func team_step(st: FishingState, dt: float, out: FishingStepOut) -> void:
	var fights := 0
	for r in st.riders:
		if r.action == FishingConst.A_FIGHT and r.fish.sp >= 0:
			fights += 1
	st.hookup_level = fights
	if st.roam or fights < 2:
		return
	var reached := 0
	var top := mini(fights, FishingConst.HOOKUP_MULT.size() - 1)
	for r in st.riders:
		if r.action != FishingConst.A_FIGHT or r.fish.sp < 0:
			continue
		for m in range(2, top + 1):
			r.overlap_s[m] += dt
			if r.overlap_s[m] + EPS >= FishingConst.HOOKUP_OVERLAP_S and r.hookup_count < m:
				r.hookup_count = m
				reached = maxi(reached, m)
	if reached >= 2:
		var slots: Array[int] = []
		for r in st.riders:
			if r.action == FishingConst.A_FIGHT and r.fish.sp >= 0:
				slots.append(r.slot)
		out.events.append(FishingEvents.double_hookup(slots, reached))
