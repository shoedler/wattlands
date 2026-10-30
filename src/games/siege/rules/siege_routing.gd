class_name SiegeRouting
extends RefCounted
## Routing (brief 2.4 "Routing", 2.5 "Zero input"). Pure.
##
## Each rider's target is a station 0..4 (0 mine, 1 tree ballista, 2 great onager, 3 arrow
## organ, 4 tar works) within the caps (stations.json: 2 / 1 / 2 / 2 / 1). Intents: a station
## directly; "next" / "prev" step 0 -> 1 -> 2 -> 3 -> 4 -> 0 (and back), skipping full stations;
## "mine" (up); "hot" (down) takes Autopilot's pick. A change reconnects after reconnect_s (2 s)
## with no output meanwhile. Routing happens in waves only; in breaks all output goes to the
## mine and every target is kept. The caps limit routing: everyone starts on the mine, and a
## station a rider already holds never pushes them off (ADR "caps gate routing").
##
## Zero input: a rider is Autopilot-routed while route_fallback (until their first deliberate
## route intent; bots never clear it) or autopilot (bots and Autopilot-on humans). The rules ask
## SiegeAutopilot.route_choice once a second in slot order. Auto-tagged route intents are ignored.

## Test seam: when valid, called as route_hook.call(state, rider) -> int instead of
## SiegeAutopilot.route_choice.
static var route_hook: Callable = Callable()


## True while Autopilot routes for `r`.
static func autopiloted(r: SiegeRiderState) -> bool:
	return r.autopilot or r.route_fallback


## Applies one normalized route intent from `r`.
static func intent(
	state: SiegeState, r: SiegeRiderState, it: Dictionary, events: Array[Dictionary]
) -> void:
	if not state.in_wave() or bool(it.get("auto", false)):
		return
	if not r.is_bot:
		r.route_fallback = false
	var target := resolve(state, r, int(it.get("to", 0)))
	if target >= 0:
		set_target(state, r, target, events)


## The station `to` (0..4 or SiegeIds.ROUTE_NEXT / PREV / HOT) resolves to for `r`, or -1 when
## nothing changes (no valid station).
static func resolve(state: SiegeState, r: SiegeRiderState, to: int) -> int:
	match to:
		SiegeIds.ROUTE_NEXT:
			return step_from(state, r, 1)
		SiegeIds.ROUTE_PREV:
			return step_from(state, r, -1)
		SiegeIds.ROUTE_HOT:
			return SiegeAutopilot.hot_target(state, r)
	return to if can_route_to(state, r, to) else -1


## True when `r` may route to station `id` now: a station whose other riders are under its cap
## (a station `r` already holds is always allowed).
static func can_route_to(state: SiegeState, r: SiegeRiderState, id: int) -> bool:
	if not SiegeIds.is_station(id):
		return false
	if r.target == id:
		return true
	return state.routed_count(id) < state.station_cap(id)


## The next station from `r`'s target in direction `dir` (+1 / -1) that has room, or -1.
static func step_from(state: SiegeState, r: SiegeRiderState, dir: int) -> int:
	var n := SiegeIds.STATION_COUNT
	for i in range(1, n):
		var cand := posmod(r.target + dir * i, n)
		if can_route_to(state, r, cand):
			return cand
	return -1


## Moves `r` to `target` (no-op when already there): starts the reconnect, stamps routed_t and
## emits the route event.
static func set_target(
	state: SiegeState, r: SiegeRiderState, target: int, events: Array[Dictionary]
) -> void:
	if target == r.target:
		return
	r.target = target
	r.reconnect_s = state.content.num("reconnect_s", 2.0)
	r.routed_t = state.t
	events.append(SiegeEvents.route(r.slot, target))


## Autopilot's routing once a second (game tick multiple of 20), in slot order, in waves.
static func autopilot(state: SiegeState, inputs: SiegeInputs, events: Array[Dictionary]) -> void:
	if not state.in_wave() or inputs.phase.is_cooldown() or inputs.tick % Wl.SIM_HZ != 0:
		return
	var scores := SiegeAutopilot.scores(state)
	for r in state.riders:
		if not autopiloted(r) or r.afk or not r.connected or r.reconnect_s > 0.0:
			continue
		var choice := pick(state, r, scores)
		if choice < 0 or choice == r.target:
			continue
		if can_route_to(state, r, choice):
			set_target(state, r, choice, events)


## Autopilot's choice for `r`: a station, or -1 to keep.
static func pick(state: SiegeState, r: SiegeRiderState, scores: PackedFloat32Array) -> int:
	if route_hook.is_valid():
		return int(route_hook.call(state, r))
	return SiegeAutopilot.route_choice(state, r, scores)
