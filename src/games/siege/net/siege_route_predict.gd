class_name SiegeRoutePredict
extends RefCounted
## Client-side prediction of a route intent (brief 2.6: client_predict "shows route changes at
## once"). It resolves exactly like the host's routing (SiegeRouting.resolve: next / prev step
## through the stations skipping full ones, "hot" is Autopilot's pick, a station is taken when it
## has room). The host decides in the end; its route event or the next snapshot overrides this
## guess.


## The station the rider would move to for the normalized route `to` (a station 0..4, ROUTE_NEXT /
## PREV / HOT), or -1 when nothing changes.
static func resolve(state: SiegeState, rider: SiegeRiderState, to: int) -> int:
	if state == null or rider == null or state.content == null or state.path == null:
		return -1
	var want := SiegeRouting.resolve(state, rider, to)
	return want if want >= 0 and want != rider.target else -1
