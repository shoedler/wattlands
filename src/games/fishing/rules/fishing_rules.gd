class_name FishingRules
extends RefCounted
## Turbo Reel's pure rules: step(state, inputs, dt) at 0.05 s. Each rider's phase comes from
## frame.phase (FishingRiderInput); randomness only from each rider's FishingRandom streams
## (derived from ctx.seed); every trainer change, band, replan, phase end, event and toast goes
## out in a FishingStepOut for the module to apply. No ctx, no Nodes, no clock.
##
## Free Roam, per rider (phases from FishingPlanBuilder.roam):
##   DRIVE  the prop is engaged: P_eff drives the boat (FishingBoat); the trainer is in SIM with
##          the course grade 0.5 % + 2 (v / 15 m/s)^2 (<= 3 %). P_eff under 20 % FTP-equivalent (or
##          Autopilot reaching its stop) frees the prop: DRIFT. Driving into the edge or the dock
##          wall stops the boat: MENU.
##   DRIFT  the boat brakes (about 3 s from cruise); P_eff >= 20 % engages the prop again (not
##          for Autopilot); stopped (|v| < 0.3 m/s): MENU.
##   MENU   the light menu: cast at one of the fish on offer here (hints drawn from the zone's
##          species), drive on, turn around. Left/right + confirm; pedal_nav riders also scan, pick
##          with a surge, and auto-confirm after two scan cycles; Autopilot picks after 1 s.
##          Pedaling >= 80 % for 2 s drives on (not for Autopilot).
##   CAST   the wobbler dives to the fish (1.5 s + depth / 60 m/s, <= 8 s); confirm reels in.
##   WAIT   the lure band (preferred + species offset +- 8 rpm); a bite comes with hazard
##          1 / 25 s in band (a quarter outside), never in the first 5 s, forced at 90 s; never
##          in the drive-out, before the Roam phase's min_s, after time-up or while staggered.
##          The bite builds the fight (FishingPreroll.roam_slot), replans the rest of the plan
##          (FishingPlanBuilder.fight_tail) and ends the Roam phase; confirm reels in.
##   FIGHT, LAND   FishingFight. The Landing's end leads to the next Roam: MENU with fresh hints.
## Time-up: no new bites (lines come in), fights may finish; finished("trip_over") once no fight
## is on, or at time-up + 5 min.
##
## Workouts (FishingPlanBuilder.build): Ride out = DRIVE; each Troll phase = the boat drives with
## the lure out (CAST, then WAIT); the plan's fish bites (Base: after R_min with the hazard
## (0.35 + 0.65 x 0.7) / 90 s in band, forced at R_min + 240 s, refused by last call; Threshold
## and e2e: 4 s before the fixed Troll ends) and hooks itself; Fight and Landing as above; Base
## ends with finished("trip_over") once fishing time is up and no fight is on.
## Cool-down: HOME (Free Roam: heading for the dock). Rescue, AFK, pause and stale telemetry
## stagger the rider (FishingFight); a paused boat drifts.

## The dock berths: slot 0 at BERTH_X0_M, each next slot BERTH_M further out (a boat is about
## 36 m long in the view, so neighbours keep a clear gap at the start).
const BERTH_X0_M := 10.0
const BERTH_M := 42.0
const TIP_PREFIX := "FISHING_TIP_"
const D_MAX_DEFAULT := 60.0
const EPS := 1e-6


## The session's starting state on every peer. `slots` holds each rider's pre-rolled workout
## Array[FishingPlanSlot] in slot order ([] each in Free Roam); `strategies` each bot's strategy
## index (-1 for humans).
static func new_state(
	content: FishingContent,
	players: Array[PlayerSlot],
	seed: int,
	slots: Array,
	strategies: Array[int] = []
) -> FishingState:
	var st := FishingState.new()
	var trip := content.trip
	st.trip_id = trip.id
	st.trip_kind = trip.kind
	st.roam = trip.is_roam()
	st.scheduled = trip.is_scheduled()
	st.k_rmin = trip.k_rmin
	st.species = content.species
	if st.roam:
		st.world = FishingWorld.from_map(content.map, seed)
		st.play_end_t = trip.minutes * 60.0
		st.overtime_end_t = st.play_end_t + FishingConst.OVERTIME_S
		st.total_s = st.play_end_t
	else:
		st.world = FishingWorld.endless_for(seed)
		st.total_s = FishingPlanBuilder.trip_length_s(trip)
		if st.scheduled:
			st.play_end_t = st.total_s
		else:
			st.play_end_t = trip.ride_out_s + trip.fishing_s
			st.fight_budget_s = trip.fight_cap_frac * trip.fishing_s
		st.overtime_end_t = st.play_end_t + FishingConst.LAST_CALL_OVERRUN_S
	for p in players:
		var r := FishingRiderState.new()
		r.slot = p.slot_index
		r.peer = p.peer_id
		r.is_bot = p.is_bot
		r.ftp = p.ftp
		r.preferred_rpm = p.preferred_cadence_rpm
		r.relaxed_band = bool(p.options.get("relaxed_band", false))
		r.reel_pct = trip.reel_target(int(p.options.get("reel_pct", FishingConst.REEL_PCT_DEFAULT)))
		r.haptics_on = p.haptics_on
		r.autopilot = p.autopilot or p.is_bot
		r.pedal_nav = p.pedal_nav
		r.strategy = strategies[p.slot_index] if p.slot_index < strategies.size() else -1
		r.x_m = start_x(p.slot_index)
		r.furthest_x_m = r.x_m
		r.rng = FishingRandom.derive(seed, p.slot_index, FishingRandom.STREAM_LANE)
		r.pull_rng = FishingRandom.derive(seed, p.slot_index, FishingRandom.STREAM_PULL)
		FishingPullScheduler.init_lane(r.pull, seed, p.slot_index)
		if p.slot_index < slots.size():
			r.slots.assign(slots[p.slot_index])
		st.riders.append(r)
	return st


## Every boat starts at the dock in its own berth, BERTH_M apart in slot order.
static func start_x(slot: int) -> float:
	return BERTH_X0_M + BERTH_M * float(slot)


static func step(state: FishingState, inputs: Array, dt: float) -> FishingStepOut:
	var out := FishingStepOut.new()
	state.tick += 1
	state.t = state.tick * dt
	for inp: FishingRiderInput in inputs:
		var r := state.rider(inp.slot)
		if r == null or not inp.has_phase:
			continue
		_step_rider(state, r, inp, dt, out)
	FishingFight.team_step(state, dt, out)
	_check_end(state, out)
	return out


# --- One rider -------------------------------------------------------------------------------


static func _step_rider(
	st: FishingState, r: FishingRiderState, inp: FishingRiderInput, dt: float, out: FishingStepOut
) -> void:
	_read_inputs(r, inp, dt)
	var confirm := false
	var spot_dir := 0
	for raw: Variant in inp.intents:
		if not raw is Dictionary:
			continue
		var it: Dictionary = raw
		match str(it.get("k", "")):
			FishingIntents.CONFIRM:
				if str(it.get("via", "")) != FishingIntents.VIA_SURGE or r.pedal_nav:
					confirm = true
			FishingIntents.SPOT:
				spot_dir += int(it.get("dir", 0))
			FishingIntents.SUMMARY:
				_store_summary(r, it)
	if inp.phase_index != r.phase_index:
		_leave(st, r, out)
		r.phase_index = inp.phase_index
		r.phase_kind = inp.phase_kind
		r.grade_sent = NAN
		_enter(st, r, inp, out)
	else:
		r.state_t += dt
	_update_stagger(st, r)
	if inp.is_cooldown or inp.phase_kind == Wl.COOLDOWN:
		pass
	elif inp.phase_kind == Wl.WORK:
		if inp.phase_mode == Wl.SIM:
			FishingFight.tick_landing(st, r, inp, dt, out)
		else:
			FishingFight.tick(st, r, inp, dt, out)
	elif st.roam:
		_tick_roam(st, r, inp, dt, confirm, spot_dir, out)
	elif inp.phase_kind == Wl.RECOVERY:
		_tick_troll(st, r, inp, dt, out)
	else:
		_tips(r, out)
	FishingBoat.step(r, r.p_eff_w, _thrust_on(st, r), st.world.edge_x_m(), dt)
	if st.roam:
		_grade(st, r, inp, out)
	if r.is_bot:
		_bot_power(r, out)


static func _read_inputs(r: FishingRiderState, inp: FishingRiderInput, dt: float) -> void:
	r.power_w = inp.power_w
	r.p_eff_w = inp.p_eff_w
	r.applied_target_w = inp.applied_target_w
	if not r.ema_ready:
		r.cadence_ema = inp.cadence_rpm
		r.ema_ready = true
	else:
		var k := 1.0 - exp(-dt / FishingConst.CADENCE_TAU_S)
		r.cadence_ema += (inp.cadence_rpm - r.cadence_ema) * k
	r.cadence_stale = inp.cadence_age_s > FishingConst.STALE_S
	r.stale = inp.age_s > FishingConst.STALE_S or not inp.connected
	r.rescue_now = r.rescue or inp.rescue
	r.afk_tm = inp.afk
	r.paused = inp.paused


## A summary intent (the module applies the real one itself; this path serves rules-only runs):
## total XP, species records (kg x 10) and cosmetics. Only the first counts.
static func _store_summary(r: FishingRiderState, it: Dictionary) -> void:
	if r.summary_received:
		return
	r.summary_received = true
	r.summary_xp = maxi(int(it.get("xp", 0)), 0)
	var rec: Variant = it.get("rec", {})
	if rec is Dictionary:
		for k: Variant in rec:
			if FishingConst.SPECIES.has(str(k)):
				r.records[str(k)] = maxf(float(rec[k]), 0.0) / 10.0
	var cos: Variant = it.get("cos", [])
	if cos is Array:
		for i in mini((cos as Array).size(), r.cosmetics.size()):
			r.cosmetics[i] = maxi(int(cos[i]), 0)


static func set_action(r: FishingRiderState, a: int) -> void:
	r.action = a
	r.state_t = 0.0


## The prop is engaged: driving, trolling (workouts) and heading home; never while paused, AFK
## or stale.
static func _thrust_on(st: FishingState, r: FishingRiderState) -> bool:
	if r.paused or r.is_afk():
		return false
	match r.action:
		FishingConst.A_DRIVE, FishingConst.A_HOME:
			return true
		FishingConst.A_CAST, FishingConst.A_WAIT:
			return not st.roam
	return false


## Finishes whatever the rider was doing in the phase that just ended.
static func _leave(st: FishingState, r: FishingRiderState, out: FishingStepOut) -> void:
	match r.action:
		FishingConst.A_FIGHT:
			FishingFight.leave(r)
		FishingConst.A_LAND:
			FishingFight.leave_landing(st, r, out)
	r.end_sent = false


static func _enter(
	st: FishingState, r: FishingRiderState, inp: FishingRiderInput, out: FishingStepOut
) -> void:
	var was := r.action
	if inp.is_cooldown or inp.phase_kind == Wl.COOLDOWN:
		_reel_in(r)
		_clear_menu(r)
		set_action(r, FishingConst.A_HOME)
		if st.roam:
			r.heading = -1
		# The cool-down clears every band itself and refuses directives.
		r.pub_lo = 0
		r.pub_hi = 0
		r.in_band = false
		r.hook_set = false
		return
	match inp.phase_kind:
		Wl.WORK:
			_clear_menu(r)
			if inp.phase_mode == Wl.SIM:
				FishingFight.begin_landing(r, out)
			else:
				FishingFight.begin(st, r, out)
			_reel_in_lure_only(r)
		Wl.RECOVERY:
			if not st.roam:
				_begin_troll(st, r, out)
		Wl.WARMUP:
			set_action(r, FishingConst.A_DRIVE)
			r.tip_n = 0
		_:
			if st.roam and (was == FishingConst.A_LAND or was == FishingConst.A_FIGHT):
				r.hook_set = false
				r.fish.sp = FishingConst.SP_NONE
				r.fight_slot = -1
				publish(r, 0.0, 0.0, out)
				_enter_menu(st, r, true)


# --- Staggers and bands --------------------------------------------------------------------


## Rescue, AFK, pause and stale telemetry stagger the rider; play resumes 10 s after the cause
## ends. Every edge goes to the pull scheduler whatever the action.
static func _update_stagger(st: FishingState, r: FishingRiderState) -> void:
	var cause := r.rescue_now or r.is_afk() or r.paused
	if cause and not r.stagger_on:
		r.stagger_on = true
		r.staggered = true
		r.resume_t = 0.0
		FishingPullScheduler.set_staggered(r.pull, true, st.t)
	elif not cause and r.stagger_on:
		r.stagger_on = false
		r.resume_t = st.t + FishingConst.STAGGER_RESUME_S
		FishingPullScheduler.set_staggered(r.pull, false, st.t)
	if r.staggered and not r.stagger_on and st.t + EPS >= r.resume_t:
		r.staggered = false
		r.resume_t = 0.0


## Publishes a band when its rounded edges change ([0, 0] clears it); the width is rounded on its
## own so a published band keeps it.
static func publish(r: FishingRiderState, lo: float, hi: float, out: FishingStepOut) -> void:
	var ilo := roundi(lo)
	var ihi := ilo + roundi(hi - lo)
	if ilo == r.pub_lo and ihi == r.pub_hi:
		return
	r.pub_lo = ilo
	r.pub_hi = ihi
	out.bands.append([r.peer, ilo, ihi])


## A band's low edge: never under 65 rpm, above the 45 rpm rescue trigger, whatever the rider's
## preferred cadence.
static func band_low(centre: float, half: float) -> float:
	return maxf(FishingConst.BAND_LOW_MIN, centre - half)


## The lure band around preferred + offset: low max(65, centre - 8), width 16; in band = the EMA
## cadence inside it.
static func _lure_band(r: FishingRiderState, offset: float, out: FishingStepOut) -> void:
	var lo := band_low(r.preferred_rpm + offset, FishingConst.LURE_HALF)
	var hi := lo + 2.0 * FishingConst.LURE_HALF
	publish(r, lo, hi, out)
	r.in_band = r.cadence_ema >= lo and r.cadence_ema <= hi


static func _toast(r: FishingRiderState, key: String, out: FishingStepOut) -> void:
	if not r.is_bot:
		out.toasts.append([key, [], r.peer])


## Ends the rider's open-ended phase, once and only after its min_s.
static func request_end(r: FishingRiderState, inp: FishingRiderInput, out: FishingStepOut) -> void:
	if r.end_sent or not inp.phase_open_ended:
		return
	if inp.phase_elapsed_s + EPS < inp.phase_min_s:
		return
	r.end_sent = true
	out.end_phase.append(r.peer)


## The driving load (Free Roam, grade_source "game" phases): FishingBoat.grade_for(v) while the
## prop is engaged, 0 otherwise; sent when it moved >= 0.1 % and at most twice a second.
static func _grade(
	st: FishingState, r: FishingRiderState, inp: FishingRiderInput, out: FishingStepOut
) -> void:
	if inp.phase_mode != Wl.SIM or inp.phase_kind == Wl.WORK or inp.is_cooldown:
		return
	var g := 0.0
	if _thrust_on(st, r):
		g = snappedf(FishingBoat.grade_for(absf(r.v_mps)), FishingConst.GRADE_STEP_PCT)
	if not is_nan(r.grade_sent):
		if absf(g - r.grade_sent) < FishingConst.GRADE_STEP_PCT - EPS:
			return
		if st.tick - r.grade_tick < FishingConst.GRADE_EVERY_TICKS:
			return
	r.grade_sent = g
	r.grade_tick = st.tick
	out.grades.append([r.peer, g])


## Bots: the power band whose centre they ride in SIM (their strategy's effort).
static func _bot_power(r: FishingRiderState, out: FishingStepOut) -> void:
	if r.action == FishingConst.A_FIGHT or r.action == FishingConst.A_HOME:
		return
	var c := roundi(FishingAutopilot.effort_frac(r) * r.ftp)
	if c == r.pub_pw:
		return
	r.pub_pw = c
	out.power_bands.append([r.peer, float(c) * 0.95, float(c) * 1.05])


# --- Free Roam -------------------------------------------------------------------------------


static func _tick_roam(
	st: FishingState,
	r: FishingRiderState,
	inp: FishingRiderInput,
	dt: float,
	confirm: bool,
	spot_dir: int,
	out: FishingStepOut
) -> void:
	if inp.phase_kind == Wl.WARMUP:
		_tips(r, out)
	match r.action:
		FishingConst.A_DRIVE:
			if r.auto_plays() and is_nan(r.stop_x):
				FishingAutopilot.plan_stop(st, r)
			if _blocked(st, r):
				_enter_menu(st, r, false)
			elif _drifts(r):
				set_action(r, FishingConst.A_DRIFT)
		FishingConst.A_DRIFT:
			if FishingBoat.stopped(r):
				_enter_menu(st, r, false)
			elif not r.auto_plays() and not _weak(r):
				set_action(r, FishingConst.A_DRIVE)
		FishingConst.A_MENU:
			_tick_menu(st, r, dt, confirm, spot_dir, out)
		FishingConst.A_CAST:
			r.lure_depth = r.lure_target_depth * minf(1.0, r.state_t / maxf(r.cast_s, EPS))
			if confirm and not r.auto_plays():
				_enter_menu(st, r, false)
			elif r.state_t + EPS >= r.cast_s:
				r.lure_depth = r.lure_target_depth
				r.wait_t = 0.0
				set_action(r, FishingConst.A_WAIT)
		FishingConst.A_WAIT:
			_tick_wait(st, r, inp, dt, confirm, out)


## Under 20 % FTP-equivalent, or paused, AFK or stale: the prop disengages.
static func _weak(r: FishingRiderState) -> bool:
	return (
		r.p_eff_w < FishingConst.DRIFT_P_FRAC * FishingConst.P_EFF_REF_W or r.paused or r.is_afk()
	)


## A human's prop disengages under 20 % FTP-equivalent; Autopilot frees it at its stop (its power
## only sets the speed). Pause, AFK and stale telemetry free it for everyone.
static func _drifts(r: FishingRiderState) -> bool:
	if r.auto_plays():
		return FishingAutopilot.wants_stop(r) or r.paused or r.is_afk()
	return _weak(r)


## Driving into the edge (seaward) or the dock wall stops the boat.
static func _blocked(st: FishingState, r: FishingRiderState) -> bool:
	if r.heading > 0:
		return r.x_m >= st.world.edge_x_m() - EPS
	return r.x_m <= EPS


## Opens the menu: fresh hints after a catch, when none are out or the boat moved on.
static func _enter_menu(st: FishingState, r: FishingRiderState, after_catch: bool) -> void:
	set_action(r, FishingConst.A_MENU)
	r.menu_t = 0.0
	r.drive_on_t = 0.0
	r.scan_t = 0.0
	r.scan_pause_t = 0.0
	r.target_sp = FishingConst.SP_NONE
	r.just_landed = after_catch
	_reel_in(r)
	if st.time_up:
		r.hints.clear()
	elif after_catch or r.hints.is_empty() or absf(r.x_m - r.hints_x) > FishingConst.HINT_REFRESH_M:
		new_hints(st, r)
	_build_menu(r)
	r.selected = 0


static func _build_menu(r: FishingRiderState) -> void:
	r.menu.clear()
	for i in r.hint_count():
		r.menu.append(i)
	r.menu.append(FishingConst.M_DRIVE_ON)
	r.menu.append(FishingConst.M_TURN)


static func _clear_menu(r: FishingRiderState) -> void:
	r.menu.clear()
	r.selected = -1


## Draws HINTS_PER_STOP fish of the zone's species (by rarity) at this x: each [species, dx,
## depth, w], sorted by dx. Depth from the species' range (above the floor), or 3-10 m above the
## floor for near_floor fish (ABYSS_DEPTH_M where there is no floor). The dock offers none.
static func new_hints(st: FishingState, r: FishingRiderState) -> void:
	r.hints.clear()
	r.hints_x = r.x_m
	var zone := st.world.zone_at(r.x_m)
	var weights: Array[float] = []
	weights.resize(FishingConst.SPECIES.size())
	var any := false
	for k in FishingConst.SPECIES.size():
		var def: FishingSpeciesDef = st.species.get(FishingConst.SPECIES[k])
		weights[k] = def.rarity if def != null and def.zones.has(zone) else 0.0
		any = any or weights[k] > 0.0
	if not any:
		return
	var floor_d := st.world.floor_depth_m(r.x_m)
	for i in FishingConst.HINTS_PER_STOP:
		var sp := r.rng.pick_weighted(weights)
		var def: FishingSpeciesDef = st.species[FishingConst.SPECIES[sp]]
		var side := 1.0 if r.rng.unit() < 0.5 else -1.0
		var dx := side * r.rng.range_f(FishingConst.HINT_DX_MIN, FishingConst.HINT_DX_MAX)
		var depth := 0.0
		if def.near_floor:
			var base := floor_d if not is_inf(floor_d) else FishingConst.ABYSS_DEPTH_M
			var gap := r.rng.range_f(FishingConst.FLOOR_GAP_LO, FishingConst.FLOOR_GAP_HI)
			depth = maxf(base - gap, 2.0)
		else:
			depth = r.rng.range_f(def.depth_lo, def.depth_hi)
			if not is_inf(floor_d):
				depth = minf(depth, maxf(floor_d - FishingConst.FLOOR_GAP_LO, 1.0))
		var w := r.rng.unit()
		var k := i
		r.hints.resize(4 * (i + 1))
		while k > 0 and r.hints[4 * (k - 1) + 1] > dx:
			for c in 4:
				r.hints[4 * k + c] = r.hints[4 * (k - 1) + c]
			k -= 1
		r.hints[4 * k] = float(sp)
		r.hints[4 * k + 1] = dx
		r.hints[4 * k + 2] = depth
		r.hints[4 * k + 3] = w


static func _tick_menu(
	st: FishingState,
	r: FishingRiderState,
	dt: float,
	confirm: bool,
	spot_dir: int,
	out: FishingStepOut
) -> void:
	var n := r.menu.size()
	if n == 0:
		return
	r.menu_t += dt
	if r.auto_plays():
		if r.menu_t + EPS >= FishingConst.AUTOPILOT_MENU_S:
			var i := FishingAutopilot.menu_pick(st, r, r.just_landed)
			r.just_landed = false
			if i >= 0:
				_pick(st, r, r.menu[i], out)
			else:
				r.menu_t = 0.0
		return
	if spot_dir != 0:
		r.selected = posmod(r.selected + spot_dir, n)
		r.scan_pause_t = FishingConst.SCAN_PAUSE_S
		r.scan_t = 0.0
		r.menu_t = 0.0
	if confirm:
		_pick(st, r, r.menu[clampi(r.selected, 0, n - 1)], out)
		return
	if r.p_eff_w >= FishingConst.DRIVE_ON_P_FRAC * FishingConst.P_EFF_REF_W and not r.paused:
		r.drive_on_t += dt
		if r.drive_on_t + EPS >= FishingConst.DRIVE_ON_S:
			_pick(st, r, FishingConst.M_DRIVE_ON, out)
			return
	else:
		r.drive_on_t = 0.0
	if not r.pedal_nav:
		return
	if r.scan_pause_t > 0.0:
		r.scan_pause_t = maxf(0.0, r.scan_pause_t - dt)
	else:
		r.scan_t += dt
		if r.scan_t + EPS >= FishingConst.SCAN_INTERVAL_S:
			r.scan_t -= FishingConst.SCAN_INTERVAL_S
			r.selected = posmod(r.selected + 1, n)
	if r.menu_t + EPS >= auto_confirm_s(n):
		_pick(st, r, r.menu[clampi(r.selected, 0, n - 1)], out)


## A pedal_nav menu auto-confirms after two full scan cycles without input.
static func auto_confirm_s(entries: int) -> float:
	return FishingConst.AUTO_CONFIRM_CYCLES * entries * FishingConst.SCAN_INTERVAL_S


static func _pick(st: FishingState, r: FishingRiderState, item: int, out: FishingStepOut) -> void:
	match item:
		FishingConst.M_DRIVE_ON:
			_clear_menu(r)
			set_action(r, FishingConst.A_DRIVE)
			if r.auto_plays() and FishingAutopilot.wants_stop(r):
				r.stop_x = NAN
		FishingConst.M_TURN:
			_clear_menu(r)
			r.heading = -r.heading
			out.events.append(FishingEvents.turn(r.slot, r.heading))
			set_action(r, FishingConst.A_DRIVE)
			if r.auto_plays():
				r.stop_x = NAN
		_:
			if item >= 0 and item < r.hint_count() and not st.time_up:
				_cast(r, item, out)


static func _cast(r: FishingRiderState, i: int, out: FishingStepOut) -> void:
	r.target_sp = int(r.hints[4 * i])
	r.lure_dx = r.hints[4 * i + 1]
	r.lure_target_depth = r.hints[4 * i + 2]
	r.target_w = r.hints[4 * i + 3]
	r.lure_depth = 0.0
	r.cast_s = minf(
		FishingConst.CAST_BASE_S + r.lure_target_depth / FishingConst.LURE_SINK_MPS,
		FishingConst.CAST_MAX_S
	)
	r.selected = i
	r.menu.clear()
	set_action(r, FishingConst.A_CAST)
	out.events.append(FishingEvents.cast(r.slot, r.target_sp, r.lure_dx, r.lure_target_depth))


static func _reel_in(r: FishingRiderState) -> void:
	r.lure_dx = 0.0
	r.lure_depth = 0.0
	r.lure_target_depth = 0.0
	r.wait_t = 0.0


## The lure comes in for a fight: the line now runs to the fish.
static func _reel_in_lure_only(r: FishingRiderState) -> void:
	r.lure_depth = 0.0
	r.lure_target_depth = 0.0


static func _tick_wait(
	st: FishingState,
	r: FishingRiderState,
	inp: FishingRiderInput,
	dt: float,
	confirm: bool,
	out: FishingStepOut
) -> void:
	if r.hook_set:
		request_end(r, inp, out)
		return
	var def: FishingSpeciesDef = st.species.get(FishingConst.SPECIES[maxi(r.target_sp, 0)])
	_lure_band(r, def.band_offset if def != null else 0.0, out)
	if confirm and not r.auto_plays():
		publish(r, 0.0, 0.0, out)
		_enter_menu(st, r, false)
		return
	r.wait_t += dt
	if not bites_open(st, r, inp) or r.wait_t + EPS < FishingConst.ROAM_BITE_MIN_S:
		return
	var h := 1.0 / FishingConst.ROAM_BITE_MEAN_S
	if not r.in_band:
		h *= FishingConst.HAZARD_OUT_OF_BAND
	if r.wait_t + EPS >= FishingConst.ROAM_FORCED_BITE_S or r.rng.unit() < h * dt:
		_roam_bite(st, r, def, out)
		request_end(r, inp, out)


## Free Roam bites need the Roam phase (not the drive-out) past its min_s, play time left and no
## stagger.
static func bites_open(st: FishingState, r: FishingRiderState, inp: FishingRiderInput) -> bool:
	return (
		inp.phase_kind == Wl.FREE
		and inp.phase_open_ended
		and inp.phase_elapsed_s + EPS >= inp.phase_min_s
		and not st.time_up
		and not r.staggered
	)


## The bite: the fight is built from the cast hint and the rest of the plan replanned; the caller
## ends the Roam phase (request_end) in the same tick.
static func _roam_bite(
	st: FishingState, r: FishingRiderState, def: FishingSpeciesDef, out: FishingStepOut
) -> void:
	if def == null:
		return
	var slot := FishingPreroll.roam_slot(def, r.target_w, r.slots.size(), r.rng, r.acc105_s)
	slot.depth_m = r.lure_target_depth
	if slot.range_hi > FishingConst.LONG_PHASE_CAP_PCT + EPS:
		r.acc105_s += slot.max_s
	r.slots.append(slot)
	r.next_slot = slot.index
	r.hook_set = true
	var roam_max := FishingPlanBuilder.roam_max_s(st.play_end_t, st.t)
	out.replans.append([r.peer, FishingPlanBuilder.fight_tail(slot, roam_max)])
	out.events.append(FishingEvents.bite(r.slot, slot.sp))


## Warm-up tips: one every 45 s (humans only).
static func _tips(r: FishingRiderState, out: FishingStepOut) -> void:
	if r.state_t + EPS >= FishingConst.TIP_EVERY_S * float(r.tip_n + 1):
		_toast(r, TIP_PREFIX + str(r.tip_n % FishingConst.TIP_KEYS + 1), out)
		r.tip_n += 1


# --- Workouts ----------------------------------------------------------------------------------


static func _begin_troll(st: FishingState, r: FishingRiderState, out: FishingStepOut) -> void:
	r.wait_t = 0.0
	r.hook_set = false
	r.sched_bit = false
	r.fish.sp = FishingConst.SP_NONE
	r.fish.off_line = false
	r.fish.replacement = false
	r.fight_slot = -1
	r.strain = 0.0
	r.slack = 0.0
	r.gaff = 0.0
	r.r_min_s = maxf(FishingConst.R_MIN_S, st.k_rmin * r.last_fight_len_s)
	if r.next_slot < r.slots.size():
		r.target_sp = r.slots[r.next_slot].sp
		r.lure_dx = -float(r.heading) * FishingConst.TROLL_DX_M
		r.lure_target_depth = FishingConst.TROLL_DEPTH_M
		r.lure_depth = 0.0
		r.cast_s = FishingConst.TROLL_CAST_S
		set_action(r, FishingConst.A_CAST)
	else:
		_cruise(r, out)


## No fish to come: the lure stays in, the boat cruises, the band clears.
static func _cruise(r: FishingRiderState, out: FishingStepOut) -> void:
	_reel_in(r)
	r.target_sp = FishingConst.SP_NONE
	publish(r, 0.0, 0.0, out)
	if r.action != FishingConst.A_DRIVE:
		set_action(r, FishingConst.A_DRIVE)


static func _tick_troll(
	st: FishingState, r: FishingRiderState, inp: FishingRiderInput, dt: float, out: FishingStepOut
) -> void:
	r.wait_t += dt
	if r.action == FishingConst.A_DRIVE:
		return
	if r.hook_set:
		request_end(r, inp, out)
		return
	var slot := r.slots[r.next_slot]
	if not st.scheduled and _no_more_bites(st, r, slot):
		_cruise(r, out)
		return
	_lure_band(r, slot.band_offset, out)
	if st.scheduled and not r.sched_bit and not inp.phase_open_ended:
		if inp.phase_remaining_s <= FishingConst.SCHEDULED_BITE_LEAD_S + EPS:
			r.sched_bit = true
			r.hook_set = true
			out.events.append(FishingEvents.bite(r.slot, slot.sp))
			return
	if r.action == FishingConst.A_CAST:
		r.lure_depth = r.lure_target_depth * minf(1.0, r.state_t / r.cast_s)
		if r.state_t + EPS >= r.cast_s:
			r.lure_depth = r.lure_target_depth
			set_action(r, FishingConst.A_WAIT)
		return
	if st.scheduled or r.staggered or r.wait_t + EPS < r.r_min_s:
		return
	var forced := r.wait_t + EPS >= r.r_min_s + FishingConst.FORCED_BITE_AFTER_S
	if forced or r.rng.unit() < bite_hazard(r) * dt:
		r.hook_set = true
		out.events.append(FishingEvents.bite(r.slot, slot.sp))
		request_end(r, inp, out)


## The workout bite hazard per second: (0.35 + 0.65 x 0.7) / 90 in the lure band, a quarter
## outside it; 0 before R_min and while staggered.
static func bite_hazard(r: FishingRiderState) -> float:
	if r.staggered or r.wait_t + EPS < r.r_min_s:
		return 0.0
	var h := (
		(FishingConst.HAZARD_BASE + FishingConst.HAZARD_STRENGTH * FishingConst.TROLL_STRENGTH)
		/ FishingConst.HAZARD_DIV_S
	)
	if not r.in_band:
		h *= FishingConst.HAZARD_OUT_OF_BAND
	return h


## Base: true when no bite can come any more in this Troll (fishing over, or last call at the
## earliest possible bite).
static func _no_more_bites(st: FishingState, r: FishingRiderState, slot: FishingPlanSlot) -> bool:
	if st.t + EPS >= st.play_end_t:
		return true
	var earliest := st.t + maxf(0.0, r.r_min_s - r.wait_t)
	return last_call_blocks(st, r, slot, earliest)


## Last call: a bite at game time `at` is refused when the fight's max_s + 30 s would end more
## than 5 min after fishing ends, or when the fight time used + T_nom + 30 s would pass the
## fight budget.
static func last_call_blocks(
	st: FishingState, r: FishingRiderState, slot: FishingPlanSlot, at: float
) -> bool:
	if at + slot.max_s + FishingConst.SLOT_GAP_S > st.overtime_end_t + EPS:
		return true
	return r.fight_budget_used_s + slot.budget_s() > st.fight_budget_s + EPS


# --- The end -----------------------------------------------------------------------------------


## Free Roam and Base: once play time is up and no rider has a fish on (Fight, Landing, or a set
## hook waiting for its Fight), or the overtime ran out, the session is over (once). Time-up in
## Free Roam brings every waiting line in.
static func _check_end(st: FishingState, out: FishingStepOut) -> void:
	if st.scheduled or st.trip_over:
		return
	if not st.time_up:
		if st.t + EPS < st.play_end_t:
			return
		st.time_up = true
		out.events.append(FishingEvents.time_up())
		if st.roam:
			for r in st.riders:
				var waiting := r.action == FishingConst.A_WAIT and not r.hook_set
				if r.action == FishingConst.A_CAST or waiting:
					publish(r, 0.0, 0.0, out)
					_enter_menu(st, r, false)
				elif r.action == FishingConst.A_MENU:
					r.hints.clear()
					_build_menu(r)
					r.selected = r.menu.find(FishingConst.M_DRIVE_ON)
	if st.t + EPS < st.overtime_end_t:
		for r in st.riders:
			if r.in_fight() or r.hook_set:
				return
	st.trip_over = true
	out.events.append(FishingEvents.trip_over())
	out.finished = "trip_over"
