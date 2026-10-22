class_name SiegeRouting
extends RefCounted
## Routing (brief 2.4 "Routing", 2.5 "Zero input"). Pure.
##
## Each rider's target is the generator (SiegeIds.TARGET_GEN) or a built pad. Intents: a pad or
## the generator directly; "next" / "prev" step through the targets clockwise (the generator,
## then the map's ring of pads, then the generator again), skipping empty pads and towers that
## already have 2 riders; "hot" picks the tower with the most enemy HP in range. A change
## reconnects after balance.json reconnect_s (2 s) with no output meanwhile. Routing happens in
## waves only; in breaks every rider's output goes to the generator and the target is kept.
##
## Zero input: a rider is Autopilot-routed while route_fallback (until their first deliberate
## route intent; bots never clear it) or autopilot (bots and Autopilot-on humans). The rules ask
## SiegeAutopilot.route_choice once a second in slot order. Auto-tagged route intents are ignored.

## Test seam: when valid, called as route_hook.call(state, rider) -> int instead of
## SiegeAutopilot.route_choice (the module's Autopilot is a separate builder's file).
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


## The target `to` (a pad, TARGET_GEN or SiegeIds.ROUTE_NEXT / PREV / HOT) resolves to for `r`,
## or -1 when nothing changes (no valid target).
static func resolve(state: SiegeState, r: SiegeRiderState, to: int) -> int:
	match to:
		SiegeIds.TARGET_GEN:
			return SiegeIds.TARGET_GEN
		SiegeIds.ROUTE_NEXT:
			return _step(state, r, 1)
		SiegeIds.ROUTE_PREV:
			return _step(state, r, -1)
		SiegeIds.ROUTE_HOT:
			return hot_pad(state, r)
	return to if can_route_to(state, r, to) else -1


## True when `r` may route to pad `pad` now: built, and fewer than 2 other riders on it.
static func can_route_to(state: SiegeState, r: SiegeRiderState, pad: int) -> bool:
	if not SiegeIds.is_pad(pad) or not state.pad(pad).built():
		return false
	var others := state.routed_count(pad) - (1 if r.target == pad else 0)
	return others < 2


## The built pad with the most enemy HP in range that `r` may route to (ties: the lower pad), or
## -1 when no tower has an enemy in range.
static func hot_pad(state: SiegeState, r: SiegeRiderState) -> int:
	var best := -1
	var best_hp := 0.0
	for n in range(1, SiegeIds.PAD_COUNT + 1):
		if not can_route_to(state, r, n):
			continue
		var hp := state.enemy_hp_in_range(n)
		if hp > best_hp:
			best = n
			best_hp = hp
	return best


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
	for r in state.riders:
		if not autopiloted(r) or r.afk or not r.connected or r.reconnect_s > 0.0:
			continue
		var choice := pick(state, r)
		if choice < 0 or choice == r.target:
			continue
		if choice == SiegeIds.TARGET_GEN or can_route_to(state, r, choice):
			set_target(state, r, choice, events)


## Autopilot's choice for `r`: a target, or -1 to keep.
static func pick(state: SiegeState, r: SiegeRiderState) -> int:
	if route_hook.is_valid():
		return int(route_hook.call(state, r))
	return SiegeAutopilot.route_choice(state, r)


static func _step(state: SiegeState, r: SiegeRiderState, dir: int) -> int:
	var seq: Array[int] = [SiegeIds.TARGET_GEN]
	seq.append_array(state.content.map.ring)
	var at := seq.find(r.target)
	if at < 0:
		at = 0
	for i in range(1, seq.size()):
		var cand := seq[posmod(at + dir * i, seq.size())]
		if cand == SiegeIds.TARGET_GEN or can_route_to(state, r, cand):
			return cand
	return -1
