class_name FtmsClient
extends Node
## FTMS over a BleTransport (BRIEF 4.1, 4.3, 4.4): discovery, subscriptions, the
## control-point queue and parsing. Owned by trainer-core; public API frozen after W0.
##
## begin() runs the 4.4 flow once the transport is connected: discover services, read
## Feature (0x2ACC) and the ranges (0x2AD6, 0x2AD8), subscribe to Indoor Bike Data (0x2AD2)
## and Machine Status (0x2ADA), enable indications on the Control Point (0x2AD9) FIRST,
## Request Control (0x00), set SIM flat (grade 0), then emit client_ready. Control-point writes are
## serialized: one in flight, 2 s timeout, two retries.
##
## Hardware lock (BRIEF 1): while OS env WATTLANDS_NO_HW_CONTROL=1, Request Control and
## every control-point write are refused and logged "hardware control locked" (scan, read
## and subscribe still work). Only FtmsTrainer calls write_control (4.6.11).

signal client_ready
## Parsed Indoor Bike Data record (FtmsCodec.parse_indoor_bike_data output).
signal bike_data(record: Dictionary)
signal control_response(opcode: int, result: int)
signal machine_status(code: int, data: PackedByteArray)
## Request Control failed with 0x05 or status reported 0xFF (another app holds control).
signal control_lost(detail: String)
signal failed(reason: String)


func attach(_transport: BleTransport) -> void:
	pass


## Run the 4.4 connection flow on the attached, connected transport.
func begin() -> void:
	pass


## Queue a control-point write (opcode + parameters). Refused under the hardware lock.
func write_control(_payload: PackedByteArray) -> void:
	pass


## True while WATTLANDS_NO_HW_CONTROL=1 is set in the environment.
static func hardware_locked() -> bool:
	return OS.get_environment("WATTLANDS_NO_HW_CONTROL") == "1"


func is_ready() -> bool:
	return false


## {"machine": int, "target": int}
func features() -> Dictionary:
	return {"machine": 0, "target": 0}


## {"min_w", "max_w", "step_w"}; KICKR defaults until read.
func power_range() -> Dictionary:
	return {"min_w": 0, "max_w": 1800, "step_w": 1}


## {"min", "max", "step"} resistance level range (0.1 units).
func resistance_range() -> Dictionary:
	return {"min": 0.0, "max": 100.0, "step": 0.1}
