class_name SiegeAutopilot
extends RefCounted
## Autopilot's routing and shop decisions (brief 2.5). Owner: B2 "module". Pure, static and
## deterministic (reads only the state; no RNG needed). Never changes effort targets and never
## triggers Overdrive.
##
## Who calls it (ADR "Autopilot runs inside the host rules"): SiegeRules (B1) for every rider
## whose route_fallback / shop_fallback is true (bots, Autopilot-on humans and humans who haven't
## routed or bought by hand yet), in slot order: route_choice() once a second, shop_picks() in a
## break at balance.json autopilot.shop_at_s (at most 2 buys per break). GameModule's
## autopilot_intents() returns [] (the platform never calls it for Autopilot-off humans, so the
## rules own every fallback). The HUD's shop panel (B3) also calls shop_picks() on clients for
## its top entry (the recommendation), from the snapshot-rebuilt state.
##
## G0 status: stubs with the final signatures (route: keep the target; shop: nothing).


## The target `rider` should route to now (TARGET_GEN or a pad), or -1 to keep the current one.
## Rules: the tower with the most enemy HP in range (state.enemy_hp_in_range), within the
## 2-rider limit (state.routed_count); none in range: the generator; ties go to the lower pad;
## switch at most once per 8 s (rider.routed_t) and only for >= 25% more enemy HP.
static func route_choice(_state: SiegeState, _rider: SiegeRiderState) -> int:
	return -1


## Autopilot's shop picks for `rider` in this break, best first, as normalized buy intents
## (SiegeIntents.normalize form, "auto": true), at most `max_items`. Order (brief 2.5): repair
## below 50%; build on the road with the most gate damage (Ballista vs Shield walls or rams,
## Caltrop vs Horsemen if that road has none, else Scorpion; no damage yet: Ballista, Scorpion,
## Caltrop in turn on the least-covered road); upgrade the lowest tower on that road; generator
## level; Iron bands; perks; save (an empty list).
static func shop_picks(
	_state: SiegeState, _rider: SiegeRiderState, _max_items: int = 2
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	return out
