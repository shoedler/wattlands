extends RefCounted
## Shared checks for fish-plan's tests and the opt-in sweep (brief 2.3, 4.1): plan properties of
## one rider's pre-roll and plans, and the pull scheduler driven by a fake fight loop against a
## model of the governor's ERG channel. Every check returns failure strings ([] = pass), so the
## GUT tests and tests/games/fishing/plan/sweep/fishing_plan_sweep.gd share them. Pure: no clock,
## no global RNG.

const CONTENT := "res://content/fishing"
## Workouts (pre-rolled plans); Free Roam plans grow at each bite (roam_failures).
const TRIPS := ["base_60", "threshold", "e2e_2min"]
const ROAM_TRIPS := ["roam_10", "roam_20", "roam_30", "roam_45", "roam_60"]
const REEL_PCTS := [50, 55, 60, 65, 70]
const FTPS := [100.0, 200.0, 300.0, 400.0, 500.0]
const DT := 0.05
const EPS := 1.0e-4
## A Fight starts at this game time in the fake loop (any time works; not tick 0).
const FIGHT_T0 := 600.0
## The most a directive may raise the channel: 25 W/s x 0.5 s.
const STEP_MAX_W := 12.5
## Forced first bite: R_min (120 s) + 240 s into fishing (brief 2.4).
const FORCED_FIRST_BITE_S := 360.0


## The governor's ERG target channel for one rider in one Fight (SDK 8): a request replaces it;
## a request with duration_s > 0 expires back to the phase's planned target (the base pull).
## Rescue and AFK only override the applied target, never the channel.
class Gov:
	var base: float = 0.0
	var value: float = 0.0
	var expiry: float = INF

	func _init(base_pct: float) -> void:
		base = base_pct
		value = base_pct

	## Applies expiry at game time t; true when the channel expired on this call.
	func advance(t: float) -> bool:
		if t >= expiry - 1.0e-6:
			value = base
			expiry = INF
			return true
		return false

	func request(t: float, d: Dictionary) -> void:
		value = float(d["target_pct"])
		var dur := float(d["duration_s"])
		expiry = t + dur if dur > 0.0 else INF


## Content, parsed and validated like FishingContent.load_for (the trip and every species).
static func content(trip_id: String) -> FishingContent:
	var c := FishingContent.new()
	c.parse(
		_json("species.json"),
		_json("trips/%s.json" % trip_id),
		_json("map.json"),
		_json("cosmetics.json")
	)
	return c


static func _json(rel: String) -> Variant:
	var path := CONTENT.path_join(rel)
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Every plan property of one rider (brief 2.3, 4.1) for every reel_pct in `reel_pcts`.
static func plan_failures(
	c: FishingContent, seed: int, rider: int, reel_pcts: Array = REEL_PCTS
) -> Array[String]:
	var f: Array[String] = []
	var trip := c.trip
	var at := "%s seed %d rider %d" % [trip.id, seed, rider]
	var slots := FishingPreroll.roll(trip, c.species, seed, rider)
	if slots.is_empty():
		f.append("%s: no slots" % at)
		return f
	var top := trip.top_pct if trip.top_pct > 0.0 else FishingConst.SELF_CAP_PCT
	var used := 0.0
	for s in slots:
		used += s.budget_s()
		f.append_array(slot_failures(c, s, top, "%s slot %d" % [at, s.index]))
	if not trip.is_scheduled():
		var cap := trip.fight_cap_frac * trip.fishing_s
		if used > cap + EPS:
			f.append("%s: T_nom + 30 s sum %.1f > cap %.1f" % [at, used, cap])
		var first := slots[0]
		var end_s := FORCED_FIRST_BITE_S + first.max_s + FishingConst.LANDING_S
		if end_s > trip.fishing_s + FishingConst.LAST_CALL_OVERRUN_S + EPS:
			f.append("%s: first slot %s fails last call" % [at, first.species])
		if first.budget_s() > cap + EPS:
			f.append("%s: first slot over the fight budget" % at)
		for s in slots:
			if not trip.species_weights.has(s.species):
				f.append("%s: slot %d species %s not in the trip" % [at, s.index, s.species])
	for reel in reel_pcts:
		f.append_array(_plan_shape_failures(trip, slots, int(reel), "%s reel %d" % [at, reel]))
	return f


## One slot against the species table and the 4.6 checks of brief 2.3.
static func slot_failures(
	c: FishingContent, s: FishingPlanSlot, top: float, at: String
) -> Array[String]:
	var f: Array[String] = []
	var def: FishingSpeciesDef = c.species.get(s.species)
	if def == null or s.sp != FishingConst.species_index(s.species):
		f.append("%s: unknown species %s" % [at, s.species])
		return f
	if s.range_lo < 50.0 - EPS or s.range_hi > FishingConst.SELF_CAP_PCT + EPS:
		f.append("%s: range [%.2f, %.2f] outside 50-110" % [at, s.range_lo, s.range_hi])
	if s.range_hi > top + EPS:
		f.append("%s: range top %.2f above the trip top %.0f" % [at, s.range_hi, top])
	if s.base_pct < s.range_lo - EPS or s.base_pct > s.range_hi + EPS:
		f.append("%s: base %.2f outside its range" % [at, s.base_pct])
	var a := s.change_pct / 100.0
	if s.range_lo < s.base_pct * (1.0 - a) - EPS or s.range_hi < s.base_pct * (1.0 + a) - EPS:
		if s.range_hi < top - EPS:
			f.append("%s: range narrower than base +- a" % at)
	if s.max_s > PlanValidator.LONG_PHASE_S and s.range_hi > FishingConst.LONG_PHASE_CAP_PCT + EPS:
		f.append("%s: range top %.2f > 105 in a phase over 300 s" % [at, s.range_hi])
	var want_min := maxf(floorf(FishingConst.FIGHT_MIN_FRAC * s.t_nom_s), FishingConst.FIGHT_MIN_S)
	if absf(s.min_s - want_min) > EPS:
		f.append("%s: min_s %.1f != max(floor(0.8 T_nom), 30)" % [at, s.min_s])
	if s.min_s > s.t_nom_s / FishingConst.TIRE_MAX_RATIO + EPS or s.min_s <= 0.0:
		f.append("%s: min_s %.1f above the fastest landing" % [at, s.min_s])
	if s.max_s < s.t_nom_s - EPS:
		f.append("%s: max_s below T_nom" % at)
	var runs_above := 0.0
	for k in s.run_count():
		var dur := s.run_dur_s(k)
		var peak := s.run_peak_pct(k)
		if dur > FishingConst.RUN_MAX_ABOVE_105_S + EPS or dur <= 0.0:
			f.append("%s: run %d length %.2f" % [at, k, dur])
		if peak > s.range_hi + EPS:
			f.append("%s: run %d peak %.2f above the range" % [at, k, peak])
		if peak > FishingConst.LONG_PHASE_CAP_PCT + EPS:
			runs_above += dur
			if def.max_run_peak(s.base_pct) <= FishingConst.LONG_PHASE_CAP_PCT + EPS:
				f.append("%s: %s run above 105 %%" % [at, s.species])
	if runs_above > FishingConst.FIGHT_MAX_ABOVE_105_S + EPS:
		f.append("%s: %.1f s above 105 %% in one fight" % [at, runs_above])
	if s.scheduled:
		return f
	if s.w < -EPS or s.w > 1.0 + EPS:
		f.append("%s: w %.3f" % [at, s.w])
	var t_nom := def.t_nom_lo + 0.8 * s.w * (def.t_nom_hi - def.t_nom_lo)
	if absf(s.t_nom_s - t_nom) > EPS:
		f.append("%s: T_nom %.2f != lo + 0.8 w (hi - lo)" % [at, s.t_nom_s])
	var want_base := minf(lerpf(def.pull_lo, def.pull_hi, s.w), top)
	if absf(s.base_pct - want_base) > EPS and not s.hold_above_105:
		f.append("%s: base %.2f != lo + w (hi - lo)" % [at, s.base_pct])
	if absf(s.max_s - def.max_s) > EPS:
		f.append("%s: max_s %.0f != species max_s" % [at, s.max_s])
	f.append_array(_run_failures(def, s, top, at))
	return f


## Runs against the species table: count, kind, peaks (absolute or base x factor, capped) and
## lengths; jumps also leaps, the 115 s spacing cap and the gap.
static func _run_failures(
	def: FishingSpeciesDef, s: FishingPlanSlot, top: float, at: String
) -> Array[String]:
	var f: Array[String] = []
	var n := s.run_count()
	var hi := def.runs_hi
	if def.run_kind == FishingSpeciesDef.RUN_JUMP:
		hi = mini(hi, floori(s.t_nom_s / FishingConst.JUMP_SPACING_S))
	if def.run_kind == FishingSpeciesDef.RUN_NONE and n != 0:
		f.append("%s: %s with runs" % [at, s.species])
	if n > hi or (n > 0 and s.run_kind != def.run_kind):
		f.append("%s: %s runs %d (max %d)" % [at, s.species, n, hi])
	if n == 0 and def.run_kind == FishingSpeciesDef.RUN_RUN and def.runs_lo > 0:
		f.append("%s: %s rolled no runs" % [at, s.species])
	var cap := top
	if s.max_s > PlanValidator.LONG_PHASE_S:
		cap = minf(cap, FishingConst.LONG_PHASE_CAP_PCT)
	for k in n:
		var pk := s.run_peak_pct(k)
		var lo := minf(def.run_peak(s.base_pct, 0.0), cap)
		var hi_pk := minf(def.max_run_peak(s.base_pct), cap)
		if pk < lo - EPS or pk > hi_pk + EPS:
			f.append("%s: %s peak %.2f outside [%.2f, %.2f]" % [at, s.species, pk, lo, hi_pk])
		if s.run_dur_s(k) < def.run_s_lo - 0.05 - EPS or s.run_dur_s(k) > def.run_s_hi + EPS:
			f.append("%s: run %d length %.2f outside the species range" % [at, k, s.run_dur_s(k)])
	if s.run_kind == FishingSpeciesDef.RUN_JUMP:
		if s.leaps.size() != n or absf(s.run_min_gap_s - def.run_min_gap_s) > EPS:
			f.append("%s: leaps or gap" % at)
		for k in s.leaps.size():
			if s.leaps[k] < def.leaps_lo or s.leaps[k] > def.leaps_hi:
				f.append("%s: leaps %d" % [at, s.leaps[k]])
	return f


static func _plan_shape_failures(
	trip: FishingTripDef, slots: Array[FishingPlanSlot], reel_pct: int, at: String
) -> Array[String]:
	var f: Array[String] = []
	var plan := FishingPlanBuilder.build(trip, slots, reel_pct)
	var res := PlanValidator.validate(plan)
	if not bool(res["ok"]):
		f.append("%s: rejected: %s" % [at, "; ".join(res["errors"])])
	if not (res["warnings"] as Array).is_empty():
		f.append("%s: warnings: %s" % [at, "; ".join(res["warnings"])])
	var expect := 1 + 3 * slots.size() + (0 if trip.is_scheduled() else 1)
	if plan.phases.size() != expect:
		f.append("%s: %d phases, expected %d" % [at, plan.phases.size(), expect])
		return f
	var ride := plan.phases[0]
	if ride.kind != Wl.WARMUP or not ride.lap or absf(ride.duration_s - trip.ride_out_s) > EPS:
		f.append("%s: ride out phase" % at)
	var reel_target := float(trip.reel_target(reel_pct))
	for i in slots.size():
		var s := slots[i]
		var reel := plan.phases[1 + 3 * i]
		var fight := plan.phases[2 + 3 * i]
		var land := plan.phases[3 + 3 * i]
		f.append_array(_reel_failures(trip, reel, reel_target, s.reel_s, "%s reel %d" % [at, i]))
		var label := FishingPlanBuilder.fight_label(s.species)
		var fight_ok := (
			fight.kind == Wl.WORK
			and fight.mode == Wl.ERG
			and fight.open_ended
			and fight.lap
			and fight.label == label
			and absf(fight.target_pct - s.base_pct) < EPS
			and absf(fight.min_s - s.min_s) < EPS
			and absf(fight.max_s - s.max_s) < EPS
			and fight.range_pct.size() == 2
			and absf(float(fight.range_pct[0]) - s.range_lo) < EPS
			and absf(float(fight.range_pct[1]) - s.range_hi) < EPS
		)
		if not fight_ok:
			f.append("%s: fight phase %d %s" % [at, i, fight.to_dict()])
		var land_ok := (
			land.mode == Wl.SIM
			and land.grade_source == Wl.GRADE_FLAT
			and not land.lap
			and absf(land.duration_s - FishingConst.LANDING_S) < EPS
			and not land.open_ended
		)
		if not land_ok:
			f.append("%s: landing phase %d" % [at, i])
	if not trip.is_scheduled():
		var tail := plan.phases[plan.phases.size() - 1]
		f.append_array(_reel_failures(trip, tail, reel_target, 0.0, "%s trailing reel" % at))
	return f


static func _reel_failures(
	trip: FishingTripDef, p: PlanPhase, target: float, fixed_s: float, at: String
) -> Array[String]:
	var f: Array[String] = []
	if p.kind != Wl.RECOVERY or p.mode != Wl.ERG or not p.lap or absf(p.target_pct - target) > EPS:
		f.append("%s: not a lap RECOVERY ERG at %.0f" % [at, target])
	if trip.is_scheduled():
		if p.open_ended or absf(p.duration_s - fixed_s) > EPS:
			f.append("%s: scheduled Reel must be fixed at %.0f s" % [at, fixed_s])
		return f
	if not p.open_ended or absf(p.min_s - FishingConst.REEL_MIN_S) > EPS:
		f.append("%s: open-ended Reel with min_s 120" % at)
	if p.min_s > FishingConst.R_MIN_S + EPS:
		f.append("%s: Reel min_s after the earliest bite" % at)
	var need := trip.fishing_s + FishingConst.LAST_CALL_OVERRUN_S + FishingConst.LANDING_S
	if p.max_s < need - EPS:
		f.append("%s: Reel max_s %.0f < fishing + overrun %.0f" % [at, p.max_s, need])
	if absf(p.duration_s - FishingConst.REEL_NOMINAL_S) > EPS:
		f.append("%s: Reel nominal %.0f" % [at, p.duration_s])
	return f


## A slot for `species` drawn like a Free Roam bite (nothing accrued above 105 %) or, on a trip
## with a top_pct, like the Base pre-roll.
static func species_slot(c: FishingContent, species: String, seed: int) -> FishingPlanSlot:
	var rng := FishingRandom.derive(seed, 7, FishingRandom.STREAM_PREROLL)
	var def: FishingSpeciesDef = c.species[species]
	if c.trip.top_pct > 0.0:
		var top := FishingPreroll._top(def, c.trip.top_pct)
		return FishingPreroll._build(def, 0, rng.unit(), rng, top)
	return FishingPreroll.roam_slot(def, rng.unit(), 0, rng, 0.0)


## A Free Roam rider's plan grown over `bites` random bites (species drawn from `species`, sizes
## from the seed), exactly like FishingRules: roam_slot with the rider's accrual, then the
## spliced fight_tail. Every step must validate with no warnings, and no fight phase longer than
## 300 s may pass 105 % (BRIEF 4.6.1).
static func roam_failures(
	c: FishingContent, seed: int, species: Array, bites: int = 8
) -> Array[String]:
	var f: Array[String] = []
	var play := c.trip.minutes * 60.0
	var plan := PlanValidator.finalize(FishingPlanBuilder.roam(play))
	if plan == null:
		f.append("%s: the starting plan is rejected" % c.trip.id)
		return f
	var rng := FishingRandom.derive(seed, 3, 9)
	var acc := 0.0
	var index := 1
	var t := FishingConst.WARMUP_S
	for b in bites:
		var id: String = species[rng.range_i(0, species.size() - 1)]
		var def: FishingSpeciesDef = c.species[id]
		var slot := FishingPreroll.roam_slot(def, rng.unit(), b, rng, acc)
		if slot.range_hi > FishingConst.LONG_PHASE_CAP_PCT + 1.0e-6:
			acc += slot.max_s
		var at := "%s seed %d bite %d %s" % [c.trip.id, seed, b, id]
		if slot.max_s > PlanValidator.LONG_PHASE_S and slot.range_hi > 105.0 + EPS:
			f.append("%s: above 105 %% in a phase over 300 s" % at)
		t += rng.range_f(5.0, 200.0)
		var tail := FishingPlanBuilder.fight_tail(slot, FishingPlanBuilder.roam_max_s(play, t))
		var whole := PlanValidator.spliced(plan, index, tail)
		var res := PlanValidator.validate(whole)
		if not bool(res["ok"]):
			f.append("%s: rejected: %s" % [at, "; ".join(res["errors"])])
			return f
		if not (res["warnings"] as Array).is_empty():
			f.append("%s: warnings: %s" % [at, "; ".join(res["warnings"])])
		plan = PlanValidator.finalize(whole)
		index += 3
		t += slot.max_s + FishingConst.LANDING_S
	return f


## One Fight of `slot` through the pure scheduler with a fake fight loop (brief 2.4 tiring: S
## falls at ratio / T_nom in band and recovers at 0.25 / T_nom out of band; run k of n fires at
## S = 1 - k / (n + 1); a stagger freezes S until 10 s after it ends and skips runs that come due).
## `staggers`: [[start_s, length_s], ...] relative to the Fight start. Returns
## {"fails": Array[String], "sent": int, "runs": int, "pulls": int, "above105": float}.
static func run_fight(
	slot: FishingPlanSlot, seed: int, ftp: float, staggers: Array = []
) -> Dictionary:
	var f: Array[String] = []
	var at := "%s seed %d ftp %.0f" % [slot.species, seed, ftp]
	var loop_rng := FishingRandom.derive(seed, 31, 17)
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, seed, slot.index)
	var t0 := FIGHT_T0
	FishingPullScheduler.begin(ps, slot, t0, ftp, ps.rng)
	var gov := Gov.new(slot.base_pct)
	var n := slot.run_count()
	var s_left := 1.0
	var next_k := 0
	var ratio := 1.0
	var in_band := true
	var seg_end := 0.0
	var st_i := 0
	var st_on := false
	var st_end := -1.0
	var frozen_until := -1.0
	var run_end := -1.0
	var run_sent := false
	var run_above := 0.0
	var fight_above := 0.0
	var last_send := -1.0e9
	var pulls := 0
	var sent := 0
	var runs := 0
	var tick := 0
	while true:
		tick += 1
		var el := tick * DT
		var t := t0 + el
		if st_i < staggers.size() and not st_on and el >= float(staggers[st_i][0]) - 1.0e-6:
			st_on = true
			st_end = el + float(staggers[st_i][1])
			FishingPullScheduler.set_staggered(ps, true, t)
		elif st_on and el >= st_end - 1.0e-6:
			st_on = false
			st_i += 1
			frozen_until = st_end + FishingConst.STAGGER_RESUME_S
			FishingPullScheduler.set_staggered(ps, false, t)
		var frozen := st_on or el < frozen_until - 1.0e-6
		if el >= seg_end:
			seg_end = el + 5.0
			in_band = loop_rng.unit() < 0.85
			ratio = loop_rng.range_f(0.85, 1.2)
		if not frozen:
			if in_band:
				s_left -= DT * ratio / slot.t_nom_s
			else:
				s_left = minf(1.0, s_left + DT * FishingConst.RECOVER_RATE / slot.t_nom_s)
		while next_k < n and s_left <= 1.0 - float(next_k + 1) / float(n + 1):
			if st_on:
				if FishingPullScheduler.start_run(ps, slot, next_k, t, ftp):
					f.append("%s: run started while staggered" % at)
				next_k += 1
				continue
			if frozen or FishingPullScheduler.run_blocked_by_gap(ps, slot, t):
				break
			if not FishingPullScheduler.start_run(ps, slot, next_k, t, ftp):
				f.append("%s: run %d refused outside a stagger" % [at, next_k])
			next_k += 1
			runs += 1
			if run_end > 0.0 and run_above > FishingConst.RUN_MAX_ABOVE_105_S + DT:
				f.append("%s: %.2f s above 105 %% in one run" % [at, run_above])
			run_end = ps.run_end_t
			run_sent = false
			run_above = 0.0
		var dirs := FishingPullScheduler.step(ps, slot, t, ftp, ps.rng)
		if gov.advance(t) and run_sent and absf(t - run_end) > DT + 1.0e-6:
			f.append("%s: a run step expired at %.2f, not at its run end %.2f" % [at, t, run_end])
		if run_end > 0.0 and t >= run_end - 1.0e-6 and run_sent:
			if absf(gov.value - slot.base_pct) > EPS and dirs.is_empty():
				f.append("%s: run ended at %.2f but the channel holds %.2f" % [at, t, gov.value])
			run_sent = false
		var in_run := run_end > 0.0 and t < run_end - 1.0e-6
		var paused := st_on or (st_end >= 0.0 and el < st_end + 10.0 - 1.0e-6)
		for d: Dictionary in dirs:
			sent += 1
			f.append_array(_directive_failures(slot, d, t, gov, last_send, ftp, at))
			var reason := str(d.get("reason", ""))
			if st_on:
				f.append("%s: a request at %.2f during a stagger" % [at, el])
			if reason == "pull":
				pulls += 1
				if in_run:
					f.append("%s: a pull change at %.2f inside a run" % [at, el])
				if paused:
					f.append("%s: a pull change at %.2f inside a stagger or its 10 s" % [at, el])
			elif in_run:
				run_sent = true
				if absf(t + float(d["duration_s"]) - run_end) > DT + 1.0e-6:
					f.append("%s: a run step expires off its run's end" % at)
			else:
				f.append("%s: a %s step outside its run" % [at, reason])
			gov.request(t, d)
			last_send = t
		if gov.value > FishingConst.LONG_PHASE_CAP_PCT + 1.0e-6 and slot.hold_above_105:
			fight_above += DT
		elif gov.value > FishingConst.LONG_PHASE_CAP_PCT + 1.0e-6:
			fight_above += DT
			if in_run:
				run_above += DT
			else:
				f.append("%s: above 105 %% outside a run at %.2f" % [at, el])
		if (s_left <= 0.0 and el >= slot.min_s) or el >= slot.max_s - 1.0e-6:
			break
	FishingPullScheduler.end(ps)
	if run_above > FishingConst.RUN_MAX_ABOVE_105_S + DT:
		f.append("%s: %.2f s above 105 %% in one run" % [at, run_above])
	if fight_above > FishingConst.FIGHT_MAX_ABOVE_105_S + DT and not slot.hold_above_105:
		f.append("%s: %.2f s above 105 %% in the fight" % [at, fight_above])
	if fight_above > PlanValidator.LIMIT_105_S + DT:
		f.append("%s: %.2f s above 105 %%, more than BRIEF 4.6.1 allows" % [at, fight_above])
	return {"fails": f, "sent": sent, "runs": runs, "pulls": pulls, "above105": fight_above}


## One directive against brief 2.3: shape, range, caps, spacing and the 25 W/s ramp limit.
static func _directive_failures(
	slot: FishingPlanSlot,
	d: Dictionary,
	t: float,
	gov: Gov,
	last_send: float,
	ftp: float,
	at: String
) -> Array[String]:
	var f: Array[String] = []
	var keys := ["mode", "target_pct", "duration_s", "reason", "source"]
	if d.size() != keys.size() or not d.has_all(keys):
		f.append("%s: directive keys %s" % [at, d.keys()])
		return f
	var reason := str(d["reason"])
	if d["mode"] != "ERG" or d["source"] != "fishing" or not reason in ["pull", "run", "jump"]:
		f.append("%s: directive %s" % [at, d])
	var x := float(d["target_pct"])
	if x < slot.range_lo - 1.0e-6 or x > slot.range_hi + 1.0e-6 or x > 110.0 + 1.0e-6:
		f.append("%s: target %.3f outside [%.3f, %.3f]" % [at, x, slot.range_lo, slot.range_hi])
	var dur := float(d["duration_s"])
	if (reason == "pull") != (dur == 0.0) or dur < 0.0:
		f.append("%s: %s with duration_s %.2f" % [at, reason, dur])
	if reason != "pull" and reason != slot.run_kind:
		f.append("%s: reason %s for a %s slot" % [at, reason, slot.run_kind])
	if t - last_send < FishingConst.RAMP_STEP_S - 1.0e-6:
		f.append("%s: two writes %.2f s apart" % [at, t - last_send])
	var up_w := (x - gov.value) * ftp / 100.0
	if up_w > STEP_MAX_W + 1.0e-6:
		f.append("%s: a step up of %.2f W (> 25 W/s)" % [at, up_w])
	return f


## A rescue or AFK (`stagger_s` long) that starts right after ramp step `step_j` of run 0 (-1:
## before its first step goes out), the run started once a first pull change has settled.
## Checks: no request during the stagger; from the run's scheduled end on (or once the stagger is
## over) the channel holds the base pull until the next pull change, which starts from base and
## comes >= 8 s after the run's end and >= 18 s after the stagger's end. A run cut before its first
## step never reached the trainer: the channel then keeps the pre-run pull instead.
static func stagger_failures(
	slot: FishingPlanSlot, seed: int, ftp: float, step_j: int, stagger_s: float, kind: String
) -> Array[String]:
	var f: Array[String] = []
	var at := (
		"%s %s seed %d ftp %.0f step %d len %.0f"
		% [slot.species, kind, seed, ftp, step_j, stagger_s]
	)
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, seed, slot.index)
	var t0 := FIGHT_T0
	FishingPullScheduler.begin(ps, slot, t0, ftp, ps.rng)
	var gov := Gov.new(slot.base_pct)
	var run_end := -1.0
	var run_steps := 0
	var st_start := -1.0
	var st_end := -1.0
	var last_send := -1.0e9
	var first_after := -1.0
	var pre_run := 0.0
	var tick := 0
	var horizon := 1.0e9
	while true:
		tick += 1
		var t := t0 + tick * DT
		if t > horizon:
			break
		if run_end < 0.0 and ps.sent >= FishingConst.RAMP_STEPS and ps.queue.is_empty():
			if not FishingPullScheduler.start_run(ps, slot, 0, t, ftp):
				f.append("%s: run refused" % at)
				return f
			run_end = ps.run_end_t
			pre_run = gov.value
			if step_j < 0:
				st_start = t
				FishingPullScheduler.set_staggered(ps, true, t)
		elif run_end < 0.0 and t - t0 > 60.0:
			f.append("%s: no pull change settled in 60 s" % at)
			return f
		if st_start >= 0.0 and st_end < 0.0 and t >= st_start + stagger_s - 1.0e-6:
			st_end = t
			FishingPullScheduler.set_staggered(ps, false, t)
			horizon = maxf(run_end, st_end) + 40.0
		var dirs := FishingPullScheduler.step(ps, slot, t, ftp, ps.rng)
		gov.advance(t)
		var settled := run_end > 0.0 and t >= run_end - 1.0e-6
		if st_start >= 0.0:
			settled = settled and st_end >= 0.0
		var expect := slot.base_pct if run_steps > 0 else pre_run
		if settled and first_after < 0.0 and dirs.is_empty():
			if absf(gov.value - expect) > EPS:
				f.append("%s: channel %.2f, not %.2f, at %.2f" % [at, gov.value, expect, t - t0])
		for d: Dictionary in dirs:
			f.append_array(_directive_failures(slot, d, t, gov, last_send, ftp, at))
			if st_start >= 0.0 and st_end < 0.0:
				f.append("%s: a request during the %s" % [at, kind])
			if str(d["reason"]) != "pull":
				run_steps += 1
				if run_steps - 1 == step_j and st_start < 0.0:
					st_start = t
			elif run_end > 0.0:
				if t < run_end + FishingConst.PULL_CHANGE_MIN_S - 1.0e-6:
					f.append("%s: a pull change %.2f s after the run's end" % [at, t - run_end])
				if st_end < 0.0 or t < st_end + 18.0 - 1.0e-6:
					f.append("%s: a pull change too soon after the %s" % [at, kind])
				if first_after < 0.0:
					first_after = t
					if absf(gov.value - expect) > EPS:
						f.append("%s: the pull change after the run starts off base" % at)
			gov.request(t, d)
			last_send = t
		if st_start == t:
			FishingPullScheduler.set_staggered(ps, true, t)
	if st_start < 0.0 or st_end < 0.0:
		f.append("%s: the stagger never started (run steps %d)" % [at, run_steps])
	if first_after < 0.0:
		f.append("%s: no pull change after the run and the %s" % [at, kind])
	return f


## How many ramp steps run 0 of `slot` sends with no stagger, in the stagger_failures setup.
static func run_step_count(slot: FishingPlanSlot, seed: int, ftp: float) -> int:
	var ps := FishingPullState.new()
	FishingPullScheduler.init_lane(ps, seed, slot.index)
	FishingPullScheduler.begin(ps, slot, FIGHT_T0, ftp, ps.rng)
	var run_end := -1.0
	var steps := 0
	for tick in range(1, 4000):
		var t := FIGHT_T0 + tick * DT
		if run_end < 0.0 and ps.sent >= FishingConst.RAMP_STEPS and ps.queue.is_empty():
			FishingPullScheduler.start_run(ps, slot, 0, t, ftp)
			run_end = ps.run_end_t
		for d: Dictionary in FishingPullScheduler.step(ps, slot, t, ftp, ps.rng):
			if str(d["reason"]) != "pull":
				steps += 1
		if run_end > 0.0 and t >= run_end:
			break
	return steps
