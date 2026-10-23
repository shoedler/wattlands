class_name FishingRules
extends RefCounted
## Big Game Fishing's pure rules (brief 2.4): step(state, inputs, dt) at 0.05 s, randomness only
## from each lane's FishingRandom (derived from ctx.seed), every trainer change returned in a
## FishingStepOut for the module to send. G0 version: lanes follow their phases and the trip ends
## on time; fish-rules owns this file and builds spots, bites, tension, tiring, runs, losses,
## landing and points in G1.


## The trip's starting state on every peer. `slots` holds each lane's pre-rolled
## Array[FishingPlanSlot], in slot order.
static func new_state(
	content: FishingContent, players: Array[PlayerSlot], seed: int, slots: Array
) -> FishingState:
	var st := FishingState.new()
	var trip := content.trip
	st.trip_id = trip.id
	st.trip_kind = trip.kind
	st.trip_total_s = FishingPlanBuilder.trip_length_s(trip)
	if trip.is_scheduled():
		st.fishing_end_t = st.trip_total_s
	else:
		st.fishing_end_t = trip.ride_out_s + trip.fishing_s
		st.fight_budget_s = trip.fight_cap_frac * trip.fishing_s
	st.overrun_end_t = st.fishing_end_t + FishingConst.LAST_CALL_OVERRUN_S
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
		l.rng = FishingRandom.derive(seed, p.slot_index, FishingRandom.STREAM_LANE)
		if p.slot_index < slots.size():
			l.slots.assign(slots[p.slot_index])
		st.lanes.append(l)
	return st


static func step(state: FishingState, inputs: Array, dt: float) -> FishingStepOut:
	var out := FishingStepOut.new()
	state.tick += 1
	state.t = state.tick * dt
	for inp: FishingLaneInput in inputs:
		var l := state.lane(inp.slot)
		if l == null or not inp.has_phase:
			continue
		l.power_w = inp.power_w
		var k := 1.0 - exp(-dt / FishingConst.CADENCE_TAU_S)
		l.cadence_ema += (inp.cadence_rpm - l.cadence_ema) * k
		l.phase_index = inp.phase_index
		l.phase_kind = inp.phase_kind
		l.state = _state_for(inp)
	var scheduled := state.trip_kind in [FishingConst.TRIP_THRESHOLD, FishingConst.TRIP_E2E]
	if state.t >= state.fishing_end_t and not state.trip_over and not scheduled:
		if state.lanes.all(func(l: FishingLaneState) -> bool: return not l.in_fight()):
			state.trip_over = true
			out.events.append(FishingEvents.trip_over())
			out.finished = "trip_over"
	return out


static func _state_for(inp: FishingLaneInput) -> int:
	if inp.is_cooldown:
		return FishingConst.ST_HOME
	match inp.phase_kind:
		Wl.WARMUP:
			return FishingConst.ST_RIDE_OUT
		Wl.WORK:
			return FishingConst.ST_LANDING if inp.phase_mode == Wl.SIM else FishingConst.ST_FIGHT
	return FishingConst.ST_IDLE
