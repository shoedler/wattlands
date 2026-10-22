class_name SiegeIntentLimiter
extends RefCounted
## The host's per-peer intent rate limit (brief 2.6: "drops anything beyond 5/s per peer";
## G0 contract). Counted on game ticks, so it is deterministic: a peer may have at most
## MAX_PER_S intents accepted within any 20 consecutive ticks (1 s); the rest are dropped
## silently. Junk (normalize() == {}) is dropped before it counts. The rules' own Autopilot
## decisions are not intents and never count.

const MAX_PER_S := 5
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


## Normalizes and rate-limits one tick of a peer's raw intents (frame.players[peer].intents).
func filter(peer: int, tick: int, raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Variant in raw:
		var n := SiegeIntents.normalize(it)
		if not n.is_empty() and allow(peer, tick):
			out.append(n)
	return out
