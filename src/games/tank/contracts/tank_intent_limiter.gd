class_name TankIntentLimiter
extends IntentRateLimiter
## The host's per-peer intent rate limit (brief 2.6: at most 5 a second per peer; G0 contract).
## Junk and intents the rider's engine doesn't own are dropped before they count. Autopilot intents
## (tagged auto) count like any other.

const MAX_PER_S := TankConst.INTENTS_PER_S


func _init() -> void:
	max_per_s = MAX_PER_S


## Normalizes, ownership-filters (for the rider's current `engine`) and rate-limits one tick of a
## peer's raw intents (frame.players[peer].intents).
func filter(peer: int, tick: int, raw: Array, engine: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in TankIntents.filter_owned(raw, engine):
		if allow(peer, tick):
			out.append(n)
	return out
