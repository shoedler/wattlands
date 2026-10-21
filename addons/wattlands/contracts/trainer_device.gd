class_name TrainerDevice
extends Node
## A smart trainer as the TrainerController sees it (BRIEF 4.1). Contract, frozen after
## W0. Implementations: FtmsTrainer (real, over FtmsClient) and MockTrainer (tests, demos,
## bots).
##
## Safety structure (BRIEF 4.6.11): only TrainerController calls the setters below
## (set_target_power, set_simulation, set_resistance, request_stop);
## tests/arch/test_no_bypass.gd fails on any other call site.
## Devices run with process_mode = PROCESS_MODE_ALWAYS. Time-based behaviour (a mock's
## 1 Hz notifications, its rider model) advances only through tick(dt) on platform time,
## so headless simulations at any --sim-speed stay deterministic.

## A new telemetry sample (about 1 Hz on real trainers).
signal sample_received(sample: TrainerSample)
## "disconnected", "scanning", "connecting", "connected", "ready", "control_lost", "error".
signal status_changed(status: String, detail: String)
## A control-point response: request opcode and FTMS result code (0x01 success ...).
signal control_response(opcode: int, result: int)
## FTMS Machine Status notification (0x2ADA): op code and the raw parameter bytes.
signal machine_status(code: int, data: PackedByteArray)

const STATUS_DISCONNECTED := "disconnected"
const STATUS_SCANNING := "scanning"
const STATUS_CONNECTING := "connecting"
const STATUS_CONNECTED := "connected"
const STATUS_READY := "ready"
const STATUS_CONTROL_LOST := "control_lost"
const STATUS_ERROR := "error"


func device_name() -> String:
	return ""


## True once connected, subscribed and in control (ready for setters).
func is_ready() -> bool:
	return false


func status() -> String:
	return STATUS_DISCONNECTED


## Supported Power Range (0x2AD8): {"min_w": int, "max_w": int, "step_w": int}.
## Defaults to the KICKR CORE's 0..1800 W when unknown.
func power_range() -> Dictionary:
	return {"min_w": 0, "max_w": 1800, "step_w": 1}


## Parsed Fitness Machine Feature (0x2ACC): {"machine": int, "target": int} bit fields.
func features() -> Dictionary:
	return {"machine": 0, "target": 0}


## ERG: target power in whole watts. Controller only.
func set_target_power(_watts: int) -> void:
	pass


## SIM: wind m/s, grade %, crr, cw kg/m. Controller only.
func set_simulation(_wind_mps: float, _grade_pct: float, _crr: float, _cw: float) -> void:
	pass


## RESISTANCE (P1 fallback): level in device units (FTMS 0.1 resolution). Controller only.
func set_resistance(_level: float) -> void:
	pass


## Stop or Pause (0x08 0x01 = stop). Controller only (exit, crash and disconnect paths).
func request_stop() -> void:
	pass


## Advance time-based behaviour by dt platform seconds (mock rider model, timeouts).
func tick(_dt: float) -> void:
	pass
