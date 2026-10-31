class_name SiegeIntentLimiter
extends IntentRateLimiter
## The host's per-peer intent rate limit (brief 2.6: "drops anything beyond 5/s per peer";
## G0 contract). Junk (normalize() == {}) is dropped before it counts. The rules' own Autopilot
## decisions are not intents and never count.

const MAX_PER_S := 5


func _init() -> void:
	max_per_s = MAX_PER_S


## Normalizes and rate-limits one tick of a peer's raw intents (frame.players[peer].intents).
func filter(peer: int, tick: int, raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Variant in raw:
		var n := SiegeIntents.normalize(it)
		if not n.is_empty() and allow(peer, tick):
			out.append(n)
	return out
