class_name GovernorWarmup
extends RefCounted
## The BRIEF 4.6.8 warm-up state of one trainer connection: "the first 5 minutes of riding,
## counted from the first pedal stroke after the trainer connects, and reset after 20 minutes
## without pedaling". Owned by trainer-control (added in W2r2).
##
## It lives apart from the SafetyGovernor's session state so it can outlive one governor:
## LocalRider.setup() on the same device object builds a new governor for each session and
## hands this state over (SafetyGovernor.adopt_connection), so a warm-up begun in the menus
## continues into the session and back-to-back sessions don't each get a fresh one. A new
## device object (another trainer, or a rebuilt mock) starts a new state; a reconnect of the
## same trainer keeps it (the governor and its state stay).
##
## Times are seconds on this object's own clock `t`, which the governor holding it advances by
## each tick's dt (platform time), so a copy carries over without rebasing. The rules
## themselves (the 300 s, the 1200 s reset, skip_warmup) stay in SafetyGovernor.

## Platform seconds the governors holding this state have ticked.
var t: float = 0.0
## Clock time of the first pedaling sample of the current warm-up (-1: not started yet).
var started_t: float = -1.0
## The 5 minutes have passed (until 20 minutes without pedaling reset it).
var done: bool = false
## Clock time of the latest pedaling sample (-1: none since the connection).
var last_pedal_t: float = -1.0


## A pedaling sample at the current clock time: starts the warm-up if it hasn't started.
func pedal() -> void:
	last_pedal_t = t
	if started_t < 0.0 and not done:
		started_t = t


## An independent copy (the clock and every time keep their values).
func copy() -> GovernorWarmup:
	var c := GovernorWarmup.new()
	c.t = t
	c.started_t = started_t
	c.done = done
	c.last_pedal_t = last_pedal_t
	return c


## {t, started_t, done, last_pedal_t} for diagnostics and tests.
func to_dict() -> Dictionary:
	return {"t": t, "started_t": started_t, "done": done, "last_pedal_t": last_pedal_t}
