class_name TankRules
extends RefCounted
## Pure, deterministic rules (BRIEF 3.6; brief 2.4): step(state, inputs, dt) reads only its
## arguments and draws randomness only from state.rng (ctx.rng). Owner: rules.
##
## G0 shipped the skeleton the module and the other builders rely on: segment tracking from the
## group's phase (segment, rotation and overrun events), station assignment from each rider's
## plan meta, reserve and all-AFK, the in-band rule of brief 2.3, WORK / in-band time, hull HP at
## each segment end, and a placeholder drive and objective (the tank rolls at a fixed speed and an
## objective is met at 90% of the segment's nominal length) so a session plays end to end. G1 (rules)
## replaces the placeholder with the speed model, Ram, berm, obstacles, the station energy models,
## the gun, enemies, encounters, the boss, damage, breakdown and overrun, keeping these signatures.

## G0 placeholder speed (m/s) until the drive uses SpeedModel.
const PLACEHOLDER_SPEED_MPS := 8.0
## G0 placeholder: an open-ended segment's objective is met at max(min_s, this x nominal length).
const PLACEHOLDER_OBJECTIVE_FRAC := 0.9


## A fresh state (TankState.create) for `players` (ctx.players order) on `mission`.
static func new_state(
	content: TankContent,
	players: Array[PlayerSlot],
	mission: String,
	rotation: bool,
	rng: RandomNumberGenerator
) -> TankState:
	return TankState.create(content, players, mission, rotation, rng)


## Advances the state by dt (always Wl.SIM_DT); returns the events raised (TankEvents), in order.
static func step(state: TankState, inputs: TankInputs, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.tick = inputs.tick
	state.t = inputs.t
	_track_segment(state, inputs, events)
	_assign_stations(state, inputs, events)
	_update_riders(state, inputs, dt)
	_placeholder_drive(state, dt)
	return events


## The rider's in-band rule (brief 2.3 "In band"), on this tick's input. `station` is the room the
## rider works (null treated as none: never in band). Never in band on reserve or in rescue.
static func in_band(state: TankState, r: TankRiderInput, station: TankStationState) -> bool:
	if station == null or r.on_reserve() or r.rescue or state.content == null:
		return false
	var c := state.content
	var seg := state.seg.seg
	if seg == TankIds.SEG_COOLDOWN or seg == TankIds.SEG_NONE:
		return false
	if seg == TankIds.SEG_CHECKPOINT or seg == TankIds.SEG_DEPOT:
		return r.cadence_rpm >= c.num("tanks", "in_band.recovery_cadence_rpm", 60.0)
	if r.mode == Wl.ERG:
		return (
			r.applied_target_w > 0.0
			and r.power_w >= c.num("tanks", "in_band.erg_power_frac", 0.95) * r.applied_target_w
			and r.cadence_rpm >= c.num("tanks", "in_band.erg_cadence_rpm", 60.0)
		)
	if station is TankSteamState:
		var steam := station as TankSteamState
		if steam.loaded or steam.cycling:
			return r.cadence_rpm >= c.num("tanks", "in_band.steam_cycle_cadence_rpm", 50.0)
		return TankConst.steam_building(r.power_w, r.ftp)
	var band: Array = c.value("tanks", "in_band.sim_ftp_pct", [76, 105])
	return r.ftp_pct >= float(band[0]) and r.ftp_pct <= float(band[1])


static func _track_segment(state: TankState, inputs: TankInputs, events: Array[Dictionary]) -> void:
	var ph := inputs.phase
	var sg := state.seg
	if ph.index != sg.phase_index and ph.index >= 0:
		if sg.phase_index >= 0 and sg.phase_index >= state.score.hp_by_segment.size():
			state.score.hp_by_segment.append(ceili(state.hull.hp))
		sg.phase_index = ph.index
		sg.segment_index = ph.segment
		sg.seg = ph.seg
		sg.stage = ph.stage
		sg.kind = ph.kind
		sg.objective_done = false
		sg.regroup = false
		sg.overrun = ph.overran_previous()
		sg.next_encounter = 0
		state.hull.distance_m = 0.0
		state.hull.x_px = 0.0
		var s: Dictionary = state.content.segment(ph.segment) if state.content != null else {}
		sg.length_m = float(s.get("length_m", 0.0))
		if sg.overrun:
			var prev_stage := _prev_stage(state, ph.segment)
			state.score.overruns += 1
			if prev_stage >= 1 and prev_stage <= 3:
				state.score.stage_overrun[prev_stage - 1] = true
			events.append(TankEvents.overrun(_prev_seg(state, ph.segment), prev_stage))
		if (
			sg.seg == TankIds.SEG_CHECKPOINT
			and sg.stage >= 1
			and sg.stage <= 3
			and not state.score.stage_overrun[sg.stage - 1]
		):
			state.score.stages_clean += 1
		if sg.seg == TankIds.SEG_COOLDOWN and state.outcome == "":
			state.outcome = _outcome(state)
		if sg.seg == TankIds.SEG_CHECKPOINT:
			var bonus := state.content.num("tanks", "hull.checkpoint_hp", 20.0)
			state.hull.hp_max += bonus
			state.hull.hp = minf(state.hull.hp + bonus, state.hull.hp_max)
		state.gun_line.active = sg.seg == TankIds.SEG_GUN_LINE
		events.append(TankEvents.segment(ph.index, sg.seg, sg.stage))
	sg.elapsed_s = ph.elapsed_s
	sg.min_s = ph.min_s
	sg.max_s = ph.max_s
	sg.open_ended = ph.open_ended
	sg.plan_elapsed_s = ph.plan_elapsed_s


## The mission's result once the plan's last segment ended: victory when the Behemoth died,
## withdrawn when a mission with a boss ended without its death, complete without a boss (drill).
static func _outcome(state: TankState) -> String:
	if state.score.behemoth_killed:
		return TankIds.OUTCOME_VICTORY
	if state.content != null:
		for s: Variant in state.content.segments():
			if str(s.get("type", "")) == TankIds.SEG_BOSS:
				return TankIds.OUTCOME_WITHDRAWN
	return TankIds.OUTCOME_COMPLETE


## The segment before mission segment `segment` (the cool-down's is the mission's last).
static func _prev(state: TankState, segment: int) -> Dictionary:
	if state.content == null:
		return {}
	var n := state.content.segments().size()
	var i: int = (n - 1) if segment < 0 else (segment - 1)
	return state.content.segment(i)


static func _prev_seg(state: TankState, segment: int) -> String:
	return str(_prev(state, segment).get("type", ""))


static func _prev_stage(state: TankState, segment: int) -> int:
	return int(_prev(state, segment).get("stage", 0))


## Rooms follow each rider's plan meta (rotation is in the plans); a rotation event when they move.
static func _assign_stations(
	state: TankState, inputs: TankInputs, events: Array[Dictionary]
) -> void:
	var moved := false
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		if r == null or ri.engine == "" or ri.engine == r.engine:
			continue
		r.engine = ri.engine
		moved = true
	if not moved:
		return
	for st in state.stations:
		st.slot = -1
		st.peer = 0
	var pairs: Array = []
	for r in state.riders:
		var st := state.station(r.engine)
		if st != null:
			st.slot = r.slot
			st.peer = r.peer
		pairs.append([r.slot, r.engine])
	events.append(TankEvents.rotation(pairs))


static func _update_riders(state: TankState, inputs: TankInputs, dt: float) -> void:
	var reserve_w := 60.0
	if state.content != null:
		reserve_w = state.content.num("tanks", "in_band.reserve_p_eff_w", 60.0)
	state.all_afk = not inputs.riders.is_empty()
	for ri in inputs.riders:
		if not ri.on_reserve():
			state.all_afk = false
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		if r == null:
			continue
		var st := state.station_of(r.slot)
		r.raw_w = ri.power_w
		r.cadence_rpm = ri.cadence_rpm
		r.ftp_pct = ri.ftp_pct
		r.rescue = ri.rescue
		r.afk = ri.afk
		r.connected = ri.connected
		r.in_band = in_band(state, ri, st)
		if not r.is_bot and not r.autopilot:
			for n in ri.intents:
				if TankIntents.is_deliberate(n):
					r.fallback = false
		if st != null:
			st.reserve = ri.on_reserve()
			st.in_band = r.in_band
			st.unpowered = state.all_afk
			st.p_eff_w = 0.0 if state.all_afk else (reserve_w if st.reserve else ri.p_eff_w)
			r.engine_s[TankRiderState.ENGINE_INDEX.get(st.engine, 0)] += dt
		if state.seg.kind == Wl.WORK:
			r.work_s += dt
			if r.in_band:
				r.band_s += dt


## G0 placeholder: the tank rolls at a fixed speed in drive segments and every objective is met at
## 90% of the segment's nominal length (the rules builder replaces this with brief 2.4).
static func _placeholder_drive(state: TankState, dt: float) -> void:
	var sg := state.seg
	var moving := (
		[TankIds.SEG_DEPOT, TankIds.SEG_ADVANCE, TankIds.SEG_SKIRMISH].has(sg.seg)
		and not state.all_afk
	)
	state.hull.speed_mps = PLACEHOLDER_SPEED_MPS if moving else 0.0
	state.hull.distance_m += state.hull.speed_mps * dt
	state.hull.x_px += TankConst.m_to_px(state.hull.speed_mps * dt)
	if sg.open_ended and not sg.objective_done:
		var s: Dictionary = state.content.segment(sg.segment_index) if state.content != null else {}
		if (
			sg.elapsed_s
			>= maxf(sg.min_s, PLACEHOLDER_OBJECTIVE_FRAC * float(s.get("duration_s", 0.0)))
		):
			sg.objective_done = true
			if sg.seg == TankIds.SEG_BOSS:
				state.boss.phase = TankIds.BOSS_DEAD
				state.score.behemoth_killed = true
	sg.regroup = sg.objective_done and sg.elapsed_s < sg.min_s
