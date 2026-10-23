class_name TankIntentLimiter
extends RefCounted
## The host's per-peer intent rate limit (brief 2.6: at most 5 a second per peer; G0 contract).
## Counted on game ticks, so it is deterministic: a peer may have at most MAX_PER_S intents
## accepted within any 20 consecutive ticks (1 s); the rest are dropped silently. Junk and
## intents the rider's engine doesn't own are dropped before they count. Autopilot intents
## (tagged auto) count like any other.

const MAX_PER_S := TankConst.INTENTS_PER_S
const WINDOW_TICKS := Wl.SIM_HZ

## peer -> Array[int] ticks of the accepted intents inside the window.
var _ticks: Dictionary = {}


## True (and counted) when `peer` may send one more intent at `tick`.
func allow(peer: int, tick: int) -> bool:
	var list: Array = _ticks.get(peer, [])
	while not list.is_empty() and int(list[0]) <= tick - WINDOW_TICKS:
		list.pop_front()
	_ticks[peer] = list
	if list.size() >= MAX_PER_S:
		return false
	list.append(tick)
	return true


## Normalizes, ownership-filters (for the rider's current `engine`) and rate-limits one tick of a
## peer's raw intents (frame.players[peer].intents).
func filter(peer: int, tick: int, raw: Array, engine: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in TankIntents.filter_owned(raw, engine):
		if allow(peer, tick):
			out.append(n)
	return out
