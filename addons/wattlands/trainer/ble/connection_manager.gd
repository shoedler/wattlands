class_name FtmsConnectionManager
extends Node
## Finds, connects and keeps a real trainer connected (BRIEF 4.2, 4.4). Owned by ble;
## public API frozen after W0. Picks a BleTransport backend (GDBLE first; the Python
## bridge as P1 fallback), scans for FTMS (advertised 0x1826 or a name containing KICKR),
## connects, hands the link to FtmsClient.begin(), and exposes a ready FtmsTrainer.
## On disconnect it reconnects with exponential backoff (1, 2, 4, 8 s, max 15 s),
## resubscribes, re-requests control and asks the governor to restore the last safe mode.
## Remembers the last device in Paths.last_device_path().
## No adapter (adapter_ready(false, ...)) is reported with push_warning, never an error.

## {"address", "name", "rssi", "services"}
signal device_found(info: Dictionary)
## TrainerDevice.STATUS_* plus detail ("no adapter", "another app may hold control", ...).
signal status_changed(status: String, detail: String)
## A connected, ready trainer (also after every successful reconnect).
signal trainer_ready(device: TrainerDevice)


## Start the backend; with auto_connect, connect to the last device as soon as it is seen.
func start(_auto_connect_last: bool = true) -> void:
	pass


func scan(_seconds: float = 10.0) -> void:
	pass


func stop_scan() -> void:
	pass


func connect_to(_address: String) -> void:
	pass


func disconnect_trainer() -> void:
	pass


## The current trainer device (null until ready).
func device() -> TrainerDevice:
	return null


func last_device() -> Dictionary:
	return {}


## "gdble", "bridge" or "" (none available).
func backend_name() -> String:
	return ""
