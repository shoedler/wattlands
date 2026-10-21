extends GutTest
## W4 (RS-1; BRIEF 1 "the Strava client refuses every host except 127.0.0.1 and localhost",
## BRIEF 7.5 "no request leaves loopback"). Locks.url_host() ends the authority at "?", "#" or
## "\" like a browser, but Godot's HTTPRequest (String::parse_url) cuts only at "#" and "/" and
## then drops everything up to the first "@". So "http://127.0.0.1?@HOST/..." passed the lock
## and reached HOST. The lock now refuses any URL whose authority holds "@", "?", "#", "\",
## "%" or whitespace. Adapted from the W3 proof build/w3/rides-strava/test_lock_parser.gd: a
## TCPServer on 127.0.0.2 (a host the lock refuses on its own) stands in for HOST, so nothing
## ever leaves the machine.

var _server: TCPServer = null
var _port: int = 0
var _got_connection: bool = false


func before_each() -> void:
	assert_true(Locks.network_locked(), "the run is network-locked (tools/godot.sh)")
	_server = TCPServer.new()
	assert_eq(_server.listen(0, "127.0.0.2"), OK, "listen on 127.0.0.2")
	_port = _server.get_local_port()
	_got_connection = false


func after_each() -> void:
	if _server != null:
		_server.stop()
	_server = null


## Serves one HTTP 200 on the 127.0.0.2 listener until state.done.
func _serve_once(state: Dictionary) -> void:
	var conn: StreamPeerTCP = null
	var t := 0.0
	while not bool(state["done"]) and t < 8.0:
		if conn == null and _server.is_connection_available():
			conn = _server.take_connection()
			_got_connection = true
		if conn != null:
			conn.poll()
			if conn.get_available_bytes() > 0:
				conn.get_partial_data(conn.get_available_bytes())
				conn.put_data(
					(
						"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
						. to_ascii_buffer()
					)
				)
				conn = null
		await get_tree().process_frame
		t += get_process_delta_time()


func _try(url: String) -> Dictionary:
	var c := StravaClient.new()
	c.request_timeout_s = 5.0
	add_child_autofree(c)
	var state := {"done": false}
	_serve_once(state)
	var r: Dictionary = await c._request(
		HTTPClient.METHOD_GET, url, PackedStringArray(), PackedByteArray()
	)
	state["done"] = true
	await get_tree().process_frame
	return r


func test_plain_127_0_0_2_is_refused() -> void:
	var url := "http://127.0.0.2:%d/api/v3/athlete" % _port
	assert_false(Locks.network_allows(url), "the lock refuses 127.0.0.2")
	assert_push_warning(Locks.NET_MESSAGE)
	var r := await _try(url)
	assert_true(bool(r["refused"]), "refused before any socket")
	assert_push_warning(Locks.NET_MESSAGE)
	assert_false(_got_connection, "nothing reached 127.0.0.2")


func test_question_mark_userinfo_is_refused() -> void:
	var url := "http://127.0.0.1?@127.0.0.2:%d/api/v3/athlete" % _port
	var r := await _try(url)
	assert_true(bool(r["refused"]), "W3: refused=false code=200, the request reached 127.0.0.2")
	assert_push_warning(Locks.NET_MESSAGE)
	assert_false(_got_connection, "nothing reached 127.0.0.2 while network-locked")


func test_backslash_userinfo_is_refused() -> void:
	var url := "http://127.0.0.1\\@127.0.0.2:%d/api/v3/athlete" % _port
	var r := await _try(url)
	assert_true(bool(r["refused"]))
	assert_push_warning(Locks.NET_MESSAGE)
	assert_false(_got_connection, "nothing reached 127.0.0.2 while network-locked")


func test_a_plain_loopback_url_still_goes_out() -> void:
	# The lock still lets loopback through: a request to 127.0.0.1 on a closed port is not
	# refused by the lock (it fails as offline instead).
	var probe := TCPServer.new()
	assert_eq(probe.listen(0, "127.0.0.1"), OK)
	var free_port := probe.get_local_port()
	probe.stop()
	var c := StravaClient.new()
	c.request_timeout_s = 2.0
	add_child_autofree(c)
	var r: Dictionary = await c._request(
		HTTPClient.METHOD_GET,
		"http://127.0.0.1:%d/api/v3/athlete" % free_port,
		PackedStringArray(),
		PackedByteArray()
	)
	assert_false(bool(r["refused"]), "loopback is allowed")
