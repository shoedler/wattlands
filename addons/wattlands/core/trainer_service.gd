class_name WlTrainerService
extends Node
## Autoload `TrainerService`: the app's trainer and its local rider (BRIEF 3.5 zero-touch
## start, 4.4). Owned by platform; public API frozen after W0.
## With --mock-trainer=<profile> it uses a MockTrainer; otherwise an FtmsConnectionManager
## auto-connects the last trainer on launch. It owns the app's LocalRider (created on demand
## for a session) and forwards its gestures to the InputRouter for pedal-scan menus.
## Runs with PROCESS_MODE_ALWAYS; ticks the device and the menu-time rider on platform time
## while no GameHost is running (the GameHost ticks it during a session).

signal status_changed(status: String, detail: String)
signal device_changed(device: TrainerDevice)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Start the configured backend (mock or FTMS auto-connect).
func start() -> void:
	pass


func device() -> TrainerDevice:
	return null


## The app's local rider (creates it around the current device on first use).
func local_rider() -> LocalRider:
	return null


func status() -> String:
	return TrainerDevice.STATUS_DISCONNECTED


func is_mock() -> bool:
	return false


## The FTMS connection manager (null when mocked).
func connection() -> FtmsConnectionManager:
	return null


## Switch to a MockTrainer with `spec` (settings screen "use mock trainer").
func use_mock(_spec: String) -> void:
	pass
