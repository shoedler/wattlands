class_name TankBots
extends RefCounted
## v4: the bots' seat choices (V1 plan item 8, SPEC_TANK 3.7). Owner: module. Bots fill seats around
## the humans and adapt to how those humans are doing: rack low, a bot loads; hull low, a bot repairs;
## a human on the Gun in band with no light, a bot takes the Lights; a human overworked or in rescue, a
## bot carries the seat next to them; a human on reserve, a bot swaps in until they are back.
##
## They never fight a human: a bot asks only for an empty seat, and a human's move always wins
## (TankSeats.request lands the bot on next_seat first). A bot never causes an effort change for a
## human: it acts on its own seat, on `cover` (a swap with a human on reserve, whose plan the director
## leaves alone) and on eviction. Its own trainer follows through the same TankSeatPlan.follow as any
## rider's, so BRIEF 4.5 holds for it. Nothing here reads the difficulty.
##
## A row's score holds while no human sits on that seat (empty or bot-held): the bot already loading
## must not leave the Loader for the next row, because the score that brought it there is still true.

const BOT_STAY_S := 30.0
const OVERWORKED_S := 15.0
const COVER_AFTER_S := 10.0
## A bot moves only to a seat this much more needed than its own (TankAutopilot's margin).
const SEAT_MARGIN := TankAutopilot.SEAT_MARGIN
## The rack at or below which a human on the Gun needs a Loader.
const RACK_LOW := 1
const SCORE_LOADER_RACK := 5.5
const SCORE_LIGHTS_GUN := 5.0
const SCORE_SECONDARIES := 4.8
const SCORE_LOADER_HELP := 5.2
const SCORE_LIGHTS_HELP := 5.0
const REPAIR_OVERWORKED_ADD := 1.0
## The seats a bot covers for a human on reserve.
const COVER_SEATS: Array[String] = [
	TankIds.ENGINE_DIESEL, TankIds.ENGINE_DYNAMO, TankIds.ENGINE_STEAM
]
const META := &"tank_bots_memo"
const EPS := 1e-6


## The seat this bot wants now: the most needed empty seat when that is SEAT_MARGIN more needed than
## its own, else its own. In a checkpoint, or once the objective is done, it plans for the next fight.
static func seat_wanted(state: TankState, rider: TankRiderState) -> String:
	var score := _planned_needs(state)
	var bar := float(score.get(rider.engine, 0.0)) + SEAT_MARGIN - EPS
	var best := rider.engine
	for engine in TankIds.SEATS:
		if TankSeats.is_free(state, engine) and float(score[engine]) > bar:
			bar = float(score[engine]) + EPS
			best = engine
	return best


## How much each seat is needed now (seat -> score): TankAutopilot.seat_needs plus the rows above,
## read from the humans' seats in `state`. `sit` and `seg` as in seat_needs.
static func needs(state: TankState, sit: Dictionary = {}, seg: String = "") -> Dictionary:
	if sit.is_empty():
		sit = TankAutopilot.situation(state)
	var out := TankAutopilot.seat_needs(state, sit, seg)
	var gun := _human_on(state, TankIds.ENGINE_DYNAMO)
	var rack := int(sit.get("rack", 0))
	if gun != null and rack <= RACK_LOW:
		_raise(state, out, TankIds.ENGINE_STEAM, SCORE_LOADER_RACK)
	if gun != null and gun.in_band and bool(sit.get("far_target", false)):
		_raise(state, out, TankIds.ENGINE_ARC, SCORE_LIGHTS_GUN)
	if bool(sit.get("near_threat", false)):
		_raise(state, out, TankIds.ENGINE_FEED, SCORE_SECONDARIES)
	if _any_human_in_rescue(state) or (gun != null and overworked(state, gun)):
		if rack < TankConst.RACK_MAX:
			_raise(state, out, TankIds.ENGINE_STEAM, SCORE_LOADER_HELP)
		else:
			_raise(state, out, TankIds.ENGINE_ARC, SCORE_LIGHTS_HELP)
	var loader := _human_on(state, TankIds.ENGINE_STEAM)
	if loader != null and overworked(state, loader) and _no_human_on(state, TankIds.ENGINE_REPAIR):
		out[TankIds.ENGINE_REPAIR] = float(out[TankIds.ENGINE_REPAIR]) + REPAIR_OVERWORKED_ADD
	return out


## The bot's automatic seat move this tick in wire form, or {}: at most once a second (the caller,
## TankAutopilot.seat_intent), after BOT_STAY_S on the seat, only to an empty seat, in a fight only if
## its trainer follows at once, never a mode switch in a warm-up.
static func intent(state: TankState, rider: TankRiderState) -> Dictionary:
	if TankSeats.stay_s(state, rider.peer) < BOT_STAY_S - EPS:
		return {}
	var want := seat_wanted(state, rider)
	if want == "" or want == rider.engine or not TankSeats.is_free(state, want):
		return {}
	if not _plans_ahead(state) and not TankSeats.follows_now(state, rider.peer, want):
		return {}
	var ri: TankRiderInput = TankAux.of(state).seat_input.get(rider.peer)
	if TankAutopilot._switches_in_warmup(state, ri, want):
		return {}
	var out := TankIntents.seat(want, TankIds.VIA_AUTO)
	out["auto"] = 1
	return out


## The most needed empty seat for a bot a human just evicted ("" with none; there are always at least
## two: six seats, four riders). Ties in TankIds.SEATS order.
static func next_seat(state: TankState, _bot: TankRiderState) -> String:
	var score := needs(state)
	var best := ""
	var best_score := -INF
	for engine in TankSeats.empty_seats(state):
		if float(score[engine]) > best_score + EPS:
			best_score = float(score[engine])
			best = engine
	return best


## From TankSeats.step every tick: keeps the humans' reserve and out-of-band clocks and, in a WORK
## phase, swaps a human who has been on reserve COVER_AFTER_S on Drive, Gun or Loader with a free bot
## (_free_bot). The human keeps its plan (TankDirector._seat_step skips a rider on reserve) and TankSeats
## lands it back the tick it returns.
static func cover(state: TankState, events: Array[Dictionary]) -> void:
	_note(state)
	if state.in_cooldown() or state.seg.kind != Wl.WORK:
		return
	var aux := TankAux.of(state)
	for r in state.riders:
		if r.is_bot or aux.cover.has(r.peer) or not COVER_SEATS.has(r.engine):
			continue
		if not on_reserve(state, r) or _reserve_s(state, r) < COVER_AFTER_S - EPS:
			continue
		var bot := _free_bot(state, r.engine)
		if bot == null:
			continue
		aux.cover[r.peer] = {"seat": r.engine}
		TankSeats.swap(state, r, bot, events)


## True while the rider is on reserve (its last input; a bare state's flags without one).
static func on_reserve(state: TankState, r: TankRiderState) -> bool:
	var ri: TankRiderInput = TankAux.of(state).seat_input.get(r.peer)
	return ri.on_reserve() if ri != null else r.afk or not r.connected


## True when the human has been out of band OVERWORKED_S on its current seat in a WORK phase.
static func overworked(state: TankState, r: TankRiderState) -> bool:
	var row: Dictionary = _memo(state)["out"].get(r.peer, {})
	if str(row.get("seat", "")) != r.engine:
		return false
	return state.t - float(row.get("since", INF)) >= OVERWORKED_S - EPS


# --- Internals ------------------------------------------------------------------------------------


## True while the bots plan for the next fight (no fight here to follow at once).
static func _plans_ahead(state: TankState) -> bool:
	if state.seg.seg == TankIds.SEG_CHECKPOINT:
		return true
	return state.seg.objective_done and state.seg.open_ended


static func _planned_needs(state: TankState) -> Dictionary:
	if not _plans_ahead(state):
		return needs(state)
	var nxt := TankAutopilot.next_fight_segment(state)
	return needs(state, TankAutopilot.expected(state, nxt), nxt)


static func _raise(state: TankState, out: Dictionary, engine: String, score: float) -> void:
	if _no_human_on(state, engine):
		out[engine] = maxf(float(out[engine]), score)


## The human on `engine`, or null (empty, or a bot's).
static func _human_on(state: TankState, engine: String) -> TankRiderState:
	var st := state.station(engine)
	if st == null or st.is_empty():
		return null
	var holder := state.rider_at(st.slot)
	return holder if holder != null and not holder.is_bot else null


static func _no_human_on(state: TankState, engine: String) -> bool:
	return _human_on(state, engine) == null


static func _any_human_in_rescue(state: TankState) -> bool:
	for r in state.riders:
		if not r.is_bot and r.rescue:
			return true
	return false


## The bot that covers a human on `engine`: not itself covering, off Drive, Gun and Loader or on a seat
## less needed than `engine` (it never leaves a more needed seat for it); the least needed one, ties to
## the lowest slot.
static func _free_bot(state: TankState, engine: String) -> TankRiderState:
	var aux := TankAux.of(state)
	var score := needs(state)
	var covered := {}
	for row: Dictionary in aux.cover.values():
		covered[str(row["seat"])] = true
	var need := float(score[engine])
	var bar := INF
	var best: TankRiderState = null
	for r in state.riders:
		if not r.is_bot or covered.has(r.engine) or on_reserve(state, r):
			continue
		var own := float(score[r.engine])
		if COVER_SEATS.has(r.engine) and own >= need - EPS:
			continue
		if own < bar - EPS:
			bar = own
			best = r
	return best


static func _reserve_s(state: TankState, r: TankRiderState) -> float:
	return state.t - float(_memo(state)["reserve"].get(r.peer, INF))


## Starts and clears each human's reserve clock and its out-of-band clock (per seat, WORK only).
static func _note(state: TankState) -> void:
	var memo := _memo(state)
	var reserve: Dictionary = memo["reserve"]
	var out: Dictionary = memo["out"]
	for r in state.riders:
		if r.is_bot:
			continue
		var away := on_reserve(state, r)
		if not away:
			reserve.erase(r.peer)
		elif not reserve.has(r.peer):
			reserve[r.peer] = state.t
		if away or r.in_band or state.seg.kind != Wl.WORK:
			out.erase(r.peer)
		elif str((out.get(r.peer, {}) as Dictionary).get("seat", "")) != r.engine:
			out[r.peer] = {"seat": r.engine, "since": state.t}


## Host-only clocks on the state as object metadata (like TankAux): never serialized.
static func _memo(state: TankState) -> Dictionary:
	if not state.has_meta(META):
		state.set_meta(META, {"reserve": {}, "out": {}})
	return state.get_meta(META)
