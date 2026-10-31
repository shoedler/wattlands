class_name TankSeats
extends RefCounted
## Seats (v3 brief "One tank, five seats"; 0.3.1 "seats without a lock"; owner: rules). Pure: time
## only through the inputs, no random draws.
##
## - A seat intent asks for an empty seat: a named one, or the next / previous empty one in
##   TankIds.SEATS order (wrapping, skipping manned seats). There is no seat lock (0.3.1): any rider
##   may move at any time outside the cool-down (not on reserve), and the move lands in the same
##   tick: the stations' slots follow, the rider's sprint rule restarts and the `seat` event goes out.
## - v4: a human's move always wins. To a human a bot's seat counts as free (is_free_for): the bot lands
##   on TankBots.next_seat first, then the human lands. A bot takes only an empty seat. A bot covering a
##   human on reserve swaps seats with it (`swap`, TankBots.cover) and the human lands back when it
##   returns (`_cover_returns`).
## - The rider's trainer follows the seat (TankSeatPlan.follow, sent by TankDirector): a same-mode
##   move at once, an ERG <-> SIM one once the rider's last switch is 30 s old (BRIEF 4.5), or at the
##   segment's end. Meanwhile the seat works from the rider's power against its own band
##   (TankRules.in_band) and the HUD shows the wait (TankRiderState.mode_wait_s, mode_to).
## - Every rider's trainer switches are tracked here: TankAux.last_switch_s (the game time the
##   rider's plan phase mode last changed) and TankAux.trainer_mode.


static func step(state: TankState, inputs: TankInputs, events: Array[Dictionary]) -> void:
	var aux := TankAux.of(state)
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		if r == null:
			continue
		var was := str(aux.trainer_mode.get(ri.peer, ""))
		if ri.phase_mode != "" and ri.phase_mode != was:
			if was != "":
				aux.last_switch_s[ri.peer] = state.t
			aux.trainer_mode[ri.peer] = ri.phase_mode
		aux.seat_input[ri.peer] = ri
		if not aux.seat_since.has(ri.peer):
			aux.seat_since[ri.peer] = state.t
		if r.engine != TankIds.ENGINE_DIESEL:
			aux.off_drive_seg[ri.peer] = state.seg.segment_index
		if ri.phase_kind == Wl.COOLDOWN:
			r.mode_wait_s = 0.0
			r.mode_to = ""
	_cover_returns(state, inputs, events)
	TankBots.cover(state, events)
	for ri in inputs.riders:
		var r := state.rider(ri.peer)
		if r == null:
			continue
		for n in ri.intents:
			if str(n.get("k", "")) == TankIds.INTENT_SEAT:
				request(
					state, ri, r, TankIntents.seat_wanted(n, r.engine), int(n.get("d", 0)), events
				)


## Rider `r` now sits on `engine`: the stations follow and the seat event goes out. A seat someone
## else holds is never taken (refused with a warning).
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
	_seated(state, r)
	if from != "" and from != engine:
		events.append(TankEvents.seat(r.slot, from, engine))


## v4: riders `a` and `b` trade seats in one step (a bot covering a human on reserve): `land` refuses a
## held seat, so this writes both stations and both riders itself. Two seat events.
static func swap(
	state: TankState, a: TankRiderState, b: TankRiderState, events: Array[Dictionary]
) -> void:
	var sa := state.station(a.engine)
	var sb := state.station(b.engine)
	if sa == null or sb == null or a == b:
		return
	var from_a := a.engine
	var from_b := b.engine
	sa.slot = b.slot
	sa.peer = b.peer
	sb.slot = a.slot
	sb.peer = a.peer
	a.engine = from_b
	b.engine = from_a
	_seated(state, a)
	_seated(state, b)
	events.append(TankEvents.seat(a.slot, from_a, from_b))
	events.append(TankEvents.seat(b.slot, from_b, from_a))


## What every landing restarts: the stay, the Drive bookkeeping and the sprint rule.
static func _seated(state: TankState, r: TankRiderState) -> void:
	var aux := TankAux.of(state)
	aux.seat_since[r.peer] = state.t
	if r.engine != TankIds.ENGINE_DIESEL:
		aux.off_drive_seg[r.peer] = state.seg.segment_index
	if state.content != null:
		r.sprint_rule(state.content.num("tanks", "evade.sprint_window_s", 3.0)).reset()


## v4: the tick a covered human is back (before the director runs, so its plan never moves) it lands on
## the seat it left, the bot evicted if one holds it. A seat another human took in the meantime stays
## theirs.
static func _cover_returns(state: TankState, inputs: TankInputs, events: Array[Dictionary]) -> void:
	var aux := TankAux.of(state)
	if aux.cover.is_empty():
		return
	for ri in inputs.riders:
		if ri.on_reserve() or not aux.cover.has(ri.peer):
			continue
		var seat := str(aux.cover[ri.peer]["seat"])
		aux.cover.erase(ri.peer)
		var r := state.rider(ri.peer)
		if r == null or r.engine == seat or state.in_cooldown() or ri.phase_kind == Wl.COOLDOWN:
			continue
		if is_free_for(state, r, seat) and _evict(state, seat, events):
			land(state, r, seat, events)


## Clears `engine` of the bot on it, which lands on TankBots.next_seat. True when the seat is free now.
static func _evict(state: TankState, engine: String, events: Array[Dictionary]) -> bool:
	var st := state.station(engine)
	if st == null or st.is_empty():
		return st != null
	var bot := state.rider_at(st.slot)
	if bot == null or not bot.is_bot:
		return false
	var to := TankBots.next_seat(state, bot)
	if to == "":
		return false
	land(state, bot, to, events)
	return true


## Judges rider `r`'s ask for seat `want` ("" for none; `step` +1 / -1 when it came from next or
## prev, which skip to the next empty seat that way) and lands it at once. Returns true when the
## rider moved.
static func request(
	state: TankState,
	ri: TankRiderInput,
	r: TankRiderState,
	want: String,
	step: int,
	events: Array[Dictionary]
) -> bool:
	if want == "" or ri.on_reserve() or ri.phase_kind == Wl.COOLDOWN or r.engine == "":
		return false
	if state.in_cooldown():
		return false
	if step != 0:
		want = next_free(state, r, step)
	if want == r.engine or not is_free_for(state, r, want):
		return false
	if not _evict(state, want, events):
		return false
	land(state, r, want, events)
	return true


## True when the trainer of rider `peer` (its last input, TankAux.seat_input) would follow a move to
## `engine` at once (TankSeatPlan.follow: a split now, or no change needed). Without that input (a
## test's bare state) it is true. `no_hold` (a bot): TankSeatPlan.follow's, and a switch left for the
## segment's end does not count as following.
static func follows_now(state: TankState, peer: int, engine: String, no_hold: bool = false) -> bool:
	var aux := TankAux.of(state)
	var ri: TankRiderInput = aux.seat_input.get(peer)
	if ri == null or ri.plan == null:
		return true
	var f := TankSeatPlan.follow(
		state.content,
		ri,
		engine,
		float(aux.last_switch_s.get(peer, -INF)),
		state.t,
		state.seg.objective_done and state.seg.open_ended,
		true,
		no_hold
	)
	var action := int(f["action"])
	if no_hold and float(f["wait_s"]) != 0.0:
		return false
	return action == TankSeatPlan.FOLLOW_SPLIT or action == TankSeatPlan.FOLLOW_NONE


## The Autopilot's minimum stay for this crew (TankConst.AUTO_STAY_S, a solo rider AUTO_STAY_SOLO_S).
static func auto_stay_s(state: TankState) -> float:
	return TankConst.AUTO_STAY_SOLO_S if state.riders.size() == 1 else TankConst.AUTO_STAY_S


## Seconds rider `peer` has sat on its seat (since its last move, or since it joined).
static func stay_s(state: TankState, peer: int) -> float:
	return state.t - float(TankAux.of(state).seat_since.get(peer, -INF))


## The mode (Wl.ERG or Wl.SIM) a rider on `engine` rides in the current segment ("" outside one).
static func seat_mode(state: TankState, engine: String) -> String:
	return TankSeatPlan.seat_mode(state.content, state.seg.segment_index, engine)


## True when rider `ri`'s next plan phase is a checkpoint (fixed, ERG 50% for every seat).
static func checkpoint_next(ri: TankRiderInput) -> bool:
	var nxt := ri.phase_index + 1
	if ri.plan == null or ri.phase_index < 0 or nxt >= ri.plan.size():
		return false
	var ph := ri.plan.phase(nxt)
	return str(ph.meta.get("seg", "")) == TankIds.SEG_CHECKPOINT and not ph.open_ended


## True when `engine` is a seat of the tank that nobody sits on.
static func is_free(state: TankState, engine: String) -> bool:
	var st := state.station(engine)
	return st != null and st.is_empty()


## v4: true when rider `r` may land on `engine`: the seat is free, or `r` is human and a bot holds it
## (a human's seat move always wins; TankBots moves the bot first).
static func is_free_for(state: TankState, r: TankRiderState, engine: String) -> bool:
	if is_free(state, engine):
		return true
	if r == null or r.is_bot:
		return false
	var st := state.station(engine)
	if st == null:
		return false
	var holder := state.rider_at(st.slot)
	return holder != null and holder.is_bot


## The next seat from rider `r`'s in TankIds.SEATS order (`step` +1 next, -1 previous, wrapping)
## that is free for it (v4: a human's next seat may be a bot's); its own seat when none is.
static func next_free(state: TankState, r: TankRiderState, step: int) -> String:
	var at := r.engine
	for _i in TankIds.SEATS.size():
		at = TankIds.seat_step(at, signi(step))
		if at == r.engine:
			break
		if is_free_for(state, r, at):
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
