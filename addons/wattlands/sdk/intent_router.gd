class_name IntentRouter
extends IntentSink
## `ctx.intents` (BRIEF 3.6): a game's own HUD widgets and the output of local_intents() go
## through send(). The GameHost drains the queue every tick: in HOST and SOLO into the local
## rider's next frame (frame.players[peer].intents), on a CLIENT into Telemetry.intents at
## 5 Hz (at most 32 per message; more are dropped with push_warning). Intents keep their
## order, arrive exactly once and are never edited; one larger than 1 KB of JSON is dropped
## with push_warning. Intents sent before the first tick (from configure) arrive in the
## first frame.

const MAX_INTENT_BYTES := 1024
const MAX_PER_TELEMETRY := 32

var _queue: Array = []


func send(intent: Dictionary) -> void:
	var size := JSON.stringify(intent).to_utf8_buffer().size()
	if size > MAX_INTENT_BYTES:
		push_warning("IntentRouter: intent of %d bytes dropped (max %d)" % [size, MAX_INTENT_BYTES])
		return
	_queue.append(intent.duplicate(true))


## Every queued intent, oldest first; empties the queue.
func take() -> Array:
	var out := _queue
	_queue = []
	return out


func pending() -> int:
	return _queue.size()
