class_name SiegeRoutePredict
extends RefCounted
## Client-side prediction of a route intent (brief 2.6: client_predict "shows route changes at
## once"). Resolves the same way the controls are described (brief 2.4): next / prev walk the
## map's ring skipping empty pads and towers that already carry 2 other riders, "hot" is the
## Autopilot's pick, a pad or the generator is taken as is when allowed. The host decides in the
## end; its route event or the next snapshot overrides this guess.


## The target the rider would move to for the normalized route `to` (SiegeIds.TARGET_GEN, a pad,
## ROUTE_NEXT / PREV / HOT), or -1 when nothing changes.
static func resolve(state: SiegeState, rider: SiegeRiderState, to: int) -> int:
	if state == null or rider == null or state.content == null or state.content.map == null:
		return -1
	var want := -1
	match to:
		SiegeIds.TARGET_GEN:
			want = SiegeIds.TARGET_GEN
		SiegeIds.ROUTE_NEXT:
			want = _walk(state, rider, 1)
		SiegeIds.ROUTE_PREV:
			want = _walk(state, rider, -1)
		SiegeIds.ROUTE_HOT:
			want = SiegeAutopilot.hot_target(state, rider)
		_:
			want = to if _open(state, rider, to) else -1
	return want if want >= 0 and want != rider.target else -1


static func _walk(state: SiegeState, rider: SiegeRiderState, step: int) -> int:
	var map := state.content.map
	var at := rider.target
	for _i in map.ring.size():
		at = map.ring_step(at, step)
		if at == rider.target:
			return -1
		if _open(state, rider, at):
			return at
	return -1


## A built pad with room for the rider (the 2-rider limit counts the others only).
static func _open(state: SiegeState, rider: SiegeRiderState, pad: int) -> bool:
	if not SiegeIds.is_pad(pad) or not state.pad(pad).built():
		return false
	return state.routed_count(pad) - (1 if rider.target == pad else 0) < 2
