class_name IntentRateLimiter
extends RefCounted
## A host's per-peer intent rate limit (BRIEF 2.6). Counted on game ticks, so it is deterministic:
## a peer may have at most `max_per_s` intents accepted within any WINDOW_TICKS consecutive ticks
## (1 s); the rest are dropped silently. A game subclass sets `max_per_s` and adds its own `filter`,
## since what counts as junk before an intent counts differs per game.

const WINDOW_TICKS := Wl.SIM_HZ

var max_per_s: int = 5
## peer -> Array[int] ticks of the accepted intents inside the window.
var _ticks: Dictionary = {}


## True (and counted) when `peer` may send one more intent at `tick`.
func allow(peer: int, tick: int) -> bool:
	var list: Array = _ticks.get(peer, [])
	while not list.is_empty() and int(list[0]) <= tick - WINDOW_TICKS:
		list.pop_front()
	_ticks[peer] = list
	if list.size() >= max_per_s:
		return false
	list.append(tick)
	return true


## An intent's flag as a bool: a bool as is, a number when it is not zero, anything else false.
static func truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	return false
