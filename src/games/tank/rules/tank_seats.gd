class_name TankSeats
extends RefCounted
## Seats (v3 brief "One tank, five seats", "Seat choice and switching"; owner: rules). Pure: time
## only through the inputs, no random draws.
##
## - The rider's seat is its plan's: each tick the rider sits where its current plan phase's meta
##   says ("engine"). A move lands when the platform starts the replanned phase (TankSeatPlan, sent
##   by TankDirector): the stations' slots follow, the rider's sprint rule restarts and the `seat`
##   event goes out.
## - The seat lock: seat_lock_s counts TankConst.SEAT_LOCK_S (60 s) down from the rider's last plan
##   boundary (every phase start: a segment boundary, or the split of a seat switch, so every
##   trainer-mode change of that rider). A seat intent is refused while it runs.
## - A seat intent asks for an empty seat: a named one, or the next / previous empty one in
##   TankIds.SEATS order (wrapping, skipping manned seats and those another rider is moving to).
##   It is refused while the lock runs, on reserve, in the cool-down, for a manned or claimed
##   seat, and when no replan for it passes TankSeatPlan.check (a mode change within 60 s of a
##   planned one, a move that could only land in the cool-down). Accepted, the rider's seat_target
##   claims the seat until the move lands; asking for its own seat again cancels the move.


static func step(state: TankState, inputs: TankInputs, events: Array[Dictionary]) -> void:
	var aux := TankAux.of(state)
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		if r == null:
			continue
		if ri.phase_index != int(aux.seat_phase.get(ri.peer, -2)):
			aux.seat_phase[ri.peer] = ri.phase_index
			aux.seat_since[ri.peer] = state.t
		if ri.engine != "" and ri.engine != r.engine:
			land(state, r, ri.engine, events)
		var since := float(aux.seat_since.get(ri.peer, state.t))
		r.seat_lock_s = maxf(TankConst.SEAT_LOCK_S - (state.t - since), 0.0)
		aux.seat_now[ri.peer] = can_land_now(ri)
		if ri.phase_kind == Wl.COOLDOWN or ri.engine == "":
			r.seat_target = ""
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		if r == null:
			continue
		for n in ri.intents:
			if str(n.get("k", "")) == TankIds.INTENT_SEAT:
				request(state, ri, r, TankIntents.seat_wanted(n, r.engine), int(n.get("d", 0)))


## Rider `r` now sits on `engine` (its plan's seat): the stations follow and the seat event goes
## out. A seat someone else holds is never taken (the claim keeps that from happening; a stray one
## is refused with a warning).
static func land(
	state: TankState, r: TankRiderState, engine: String, events: Array[Dictionary]
) -> void:
	var to := state.station(engine)
	if to != null and to.slot >= 0 and to.slot != r.slot:
		push_warning("tank: seat %s is held by slot %d; slot %d stays" % [engine, to.slot, r.slot])
		return
	var from := r.engine
	var old := state.station(from)
	if old != null and old.slot == r.slot:
		old.slot = -1
		old.peer = 0
	if to != null:
		to.slot = r.slot
		to.peer = r.peer
	r.engine = engine
	if r.seat_target == engine:
		r.seat_target = ""
	if state.content != null:
		r.sprint_rule(state.content.num("tanks", "evade.sprint_window_s", 3.0)).reset()
	if from != "":
		events.append(TankEvents.seat(r.slot, from, engine))


## Judges rider `r`'s ask for seat `want` ("" for none; `step` +1 / -1 when it came from next or
## prev, which skip to the next empty seat that way). Returns true when the move is accepted (or a
## pending one cancelled).
static func request(
	state: TankState, ri: TankRiderInput, r: TankRiderState, want: String, step: int
) -> bool:
	if want == "" or ri.on_reserve() or ri.phase_kind == Wl.COOLDOWN or ri.engine == "":
		return false
	if step != 0:
		want = next_free(state, r, step)
	if want == r.engine:
		var had := r.seat_target != ""
		r.seat_target = ""
		return had
	if r.seat_lock_s > 0.0 or not is_free(state, want, r):
		return false
	if want == r.seat_target:
		return true
	if ri.plan != null and not plan_allows(state, ri, want):
		return false
	r.seat_target = want
	return true


## True when a move asked for now would land at once (a split: the rider's open-ended phase is past
## its own min_s with room for a 60 s rest before its max_s), not at the phase's end. The
## Autopilot seats riders only then (TankAux.seat_now), so its moves never land in the next segment.
static func can_land_now(ri: TankRiderInput) -> bool:
	return (
		ri.phase_open_ended
		and ri.phase_elapsed_s >= ri.phase_min_s - 1e-6
		and ri.phase_remaining_s > TankConst.SEAT_LOCK_S + 1.0
	)


## True when the plan of `ri` lets it move to `engine` (TankSeatPlan.can_move from its phase now).
static func plan_allows(state: TankState, ri: TankRiderInput, engine: String) -> bool:
	return TankSeatPlan.can_move(
		state.content,
		ri.plan,
		ri.phase_index,
		ri.phase_open_ended,
		ri.phase_elapsed_s,
		ri.phase_min_s,
		ri.seg_offset_s,
		engine
	)


## True when `engine` is a seat of the tank that nobody sits on and no other rider is moving to.
static func is_free(state: TankState, engine: String, r: TankRiderState) -> bool:
	var st := state.station(engine)
	if st == null or not st.is_empty():
		return false
	for o in state.riders:
		if o != r and o.seat_target == engine:
			return false
	return true


## The next seat from rider `r`'s in TankIds.SEATS order (`step` +1 next, -1 previous, wrapping)
## that is free for it; its own seat when none is.
static func next_free(state: TankState, r: TankRiderState, step: int) -> String:
	var at := r.engine
	for _i in TankIds.SEATS.size():
		at = TankIds.seat_step(at, signi(step))
		if at == r.engine:
			break
		if is_free(state, at, r):
			return at
	return r.engine


## The seats nobody sits on (in TankIds.SEATS order).
static func empty_seats(state: TankState) -> Array[String]:
	var out: Array[String] = []
	for engine in TankIds.SEATS:
		var st := state.station(engine)
		if st != null and st.is_empty():
			out.append(engine)
	return out
