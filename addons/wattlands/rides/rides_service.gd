class_name WlRides
extends Node
## Autoload `Rides` (BRIEF 3.8): creates ride recorders, keeps the Strava connection and the
## upload queue (Paths.upload_queue_path(), retried on the next launch). Owned by rides;
## public API frozen after W0. Secrets and tokens live only in strava.json and never reach
## logs, telemetry, the relay, crash reports or git.
## Network lock (BRIEF 1): while WATTLANDS_NO_NETWORK_INTEGRATIONS=1 the Strava client talks
## only to 127.0.0.1/localhost, never opens a browser, and logs "network integrations locked".
## --strava-base=<url> points both the API and OAuth bases at a mock.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## A new recorder for the local rider (RideRecorder).
func new_recorder() -> RideRecorderApi:
	return RideRecorderApi.new()


## True once Strava tokens exist.
func strava_connected() -> bool:
	return false


## Start the OAuth connect flow with the player's own API app credentials.
func strava_connect(_client_id: String, _client_secret: String) -> void:
	pass


func strava_disconnect() -> void:
	pass


## Upload a saved ride (FIT path + summary); queues it when offline or on failure.
## Progress arrives on EventBus.upload_state_changed(ride_id, state, detail).
func upload(_fit_path: String, _summary: Dictionary) -> void:
	pass


## Retry queued uploads (called at launch and after connect).
func process_queue() -> void:
	pass


func auto_upload_enabled() -> bool:
	return false


## Saved rides, newest first: [{fit_path, summary, uploaded, activity_id}] (P1 history).
func rides() -> Array:
	return []
