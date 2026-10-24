extends LocalRider
## Test double for ui tests: a LocalRider whose telemetry() reports a settable trainer mode.
## Emit gesture_detected by hand to simulate the GestureRecognizer.

var fake_mode: String = Wl.OFF
var fake_power_w: float = 0.0


func telemetry() -> Telemetry:
	var t := Telemetry.new()
	t.peer_id = peer_id
	t.mode = fake_mode
	t.power_w = fake_power_w
	return t
