extends LocalRider
## Test double for ui tests: a LocalRider whose telemetry() reports a settable trainer mode.
## Emit gesture_detected by hand to simulate the GestureRecognizer.

var fake_mode: String = Wl.OFF


func telemetry() -> Telemetry:
	var t := Telemetry.new()
	t.peer_id = peer_id
	t.mode = fake_mode
	return t
