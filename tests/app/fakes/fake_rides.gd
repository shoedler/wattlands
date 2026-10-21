extends WlRides
## Test double of the Rides autoload: Strava connection flag, recorded uploads and connects.
## Connects record only the client id and whether a secret was passed (never the secret).

var connected: bool = false
var auto: bool = false
var uploads: Array = []
var connects: Array[String] = []
var secret_passed: bool = false
var disconnects: int = 0
var queue_runs: int = 0
var ride_list: Array = []


func strava_connected() -> bool:
	return connected


func strava_connect(client_id: String, client_secret: String) -> void:
	connects.append(client_id)
	secret_passed = client_secret != ""


func strava_disconnect() -> void:
	disconnects += 1
	connected = false


func upload(fit_path: String, summary: Dictionary) -> void:
	uploads.append({"fit_path": fit_path, "summary": summary.duplicate(true)})


func process_queue() -> void:
	queue_runs += 1


func auto_upload_enabled() -> bool:
	return auto


func rides() -> Array:
	return ride_list.duplicate(true)
