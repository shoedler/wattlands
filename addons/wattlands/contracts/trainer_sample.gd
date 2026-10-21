class_name TrainerSample
extends RefCounted
## One telemetry sample from a TrainerDevice (BRIEF 4.1: TrainerSample {t, power_w,
## cadence_rpm?, speed_kmh?, flags}). Contract, frozen after W0.
## Optional values are -1 when absent; check has_cadence()/has_speed().

const HAS_POWER := 1
const HAS_CADENCE := 2
const HAS_SPEED := 4
## Cadence was estimated from speed (BRIEF 4.5), not measured.
const CADENCE_ESTIMATED := 8
## Power came from the Cycling Power service fallback (0x2A63).
const POWER_FROM_CPS := 16
const HAS_DISTANCE := 32

## Platform time in seconds when the sample arrived.
var t: float = 0.0
var power_w: float = 0.0
var cadence_rpm: float = -1.0
var speed_kmh: float = -1.0
## FTMS total distance (m) if the trainer reports it, else -1.
var distance_m: float = -1.0
var flags: int = 0


static func make(
	p_t: float, p_power_w: float, p_cadence_rpm: float = -1.0, p_speed_kmh: float = -1.0
) -> TrainerSample:
	var s := TrainerSample.new()
	s.t = p_t
	s.power_w = p_power_w
	s.flags = HAS_POWER
	if p_cadence_rpm >= 0.0:
		s.cadence_rpm = p_cadence_rpm
		s.flags |= HAS_CADENCE
	if p_speed_kmh >= 0.0:
		s.speed_kmh = p_speed_kmh
		s.flags |= HAS_SPEED
	return s


func has_cadence() -> bool:
	return (flags & HAS_CADENCE) != 0 and cadence_rpm >= 0.0


func has_speed() -> bool:
	return (flags & HAS_SPEED) != 0 and speed_kmh >= 0.0


func to_dict() -> Dictionary:
	return {
		"t": t,
		"power_w": power_w,
		"cadence_rpm": cadence_rpm,
		"speed_kmh": speed_kmh,
		"distance_m": distance_m,
		"flags": flags
	}
