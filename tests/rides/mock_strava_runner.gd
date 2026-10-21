extends Node
## Starts server/mock_strava as a Node.js child process for the rides tests (a Node process,
## never Godot), waits for its port file, talks to its /admin API and kills it.
## Add it to the tree (it uses HTTPRequest), then `await start()`.

const SERVER := "res://server/mock_strava/server.mjs"
const CLIENT_ID := "12345"
const CLIENT_SECRET := "mock-client-secret"

var pid: int = -1
var port: int = 0
var _port_file: String = ""


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts the mock; true once it listens. `now` fixes its clock (0 = real time).
func start(now: int = 0) -> bool:
	_port_file = Paths.make_temp_dir("wattlands_mock_strava").path_join("port.txt")
	var args := PackedStringArray([
		ProjectSettings.globalize_path(SERVER), "--port=0", "--port-file=" + _port_file, "--quiet",
		"--parent-pid=%d" % OS.get_process_id(),
	])
	if now > 0:
		args.append("--now=%d" % now)
	pid = OS.create_process("node", args)
	if pid <= 0:
		push_warning("mock_strava: can't start node")
		return false
	for i in 600:
		if FileAccess.file_exists(_port_file):
			var text := FileAccess.get_file_as_string(_port_file).strip_edges()
			if text.is_valid_int():
				port = int(text)
				return true
		await get_tree().create_timer(0.02, true, false, true).timeout
	push_warning("mock_strava: no port file after 12 s")
	return false


func base() -> String:
	return "http://127.0.0.1:%d" % port


func api_base() -> String:
	return base() + "/api/v3"


func oauth_base() -> String:
	return base() + "/oauth"


func stop() -> void:
	if pid > 0:
		OS.kill(pid)
		pid = -1
	if _port_file != "":
		DirAccess.remove_absolute(_port_file)
		DirAccess.remove_absolute(_port_file.get_base_dir())
		_port_file = ""


func _exit_tree() -> void:
	stop()


## Calls the admin API; returns the parsed JSON (Dictionary or Array) or null.
func admin(method: int, path: String, body: Dictionary = {}) -> Variant:
	var req := HTTPRequest.new()
	add_child(req)
	var payload := JSON.stringify(body).to_utf8_buffer() if method == HTTPClient.METHOD_POST else PackedByteArray()
	req.request_raw(base() + path, ["Content-Type: application/json"], method as HTTPClient.Method, payload)
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return null
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


func reset() -> void:
	await admin(HTTPClient.METHOD_POST, "/admin/reset")


func set_clock(now: int) -> void:
	await admin(HTTPClient.METHOD_POST, "/admin/clock", {"now": now})


func config(body: Dictionary) -> void:
	await admin(HTTPClient.METHOD_POST, "/admin/config", body)


func fault(route: String, status: int, count: int = 1, retry_after: Variant = null) -> void:
	var b := {"route": route, "status": status, "count": count}
	if retry_after != null:
		b["retry_after"] = retry_after
	await admin(HTTPClient.METHOD_POST, "/admin/fault", b)


func uploads() -> Array:
	var r: Variant = await admin(HTTPClient.METHOD_GET, "/admin/uploads")
	return r if r is Array else []


func requests() -> Array:
	var r: Variant = await admin(HTTPClient.METHOD_GET, "/admin/requests")
	return r if r is Array else []
