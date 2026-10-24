class_name StravaCallbackServer
extends Node
## The OAuth loopback callback (BRIEF 3.8): a TCPServer bound to 127.0.0.1 on a free port
## that waits for GET /strava/callback?code=...&state=... and answers with a short page.
## Other paths get a 404 and the wait goes on. The owner stops it after the first callback
## or when its time window (5 minutes) runs out. Polled in _process; PROCESS_MODE_ALWAYS.
## A connection that sends no complete request within idle_timeout_s is dropped, so idle
## (speculative) browser connections never use up the MAX_CONNECTIONS slots. The page texts
## come from content/strings/rides.csv.

## The first request to CALLBACK_PATH arrived: its decoded query parameters.
signal received(params: Dictionary)

const CALLBACK_PATH := "/strava/callback"
const BIND_ADDRESS := "127.0.0.1"
const MAX_REQUEST_BYTES := 8192
const MAX_CONNECTIONS := 8
const DEFAULT_IDLE_TIMEOUT_S := 10.0

var port: int = 0
var done: bool = false
var params: Dictionary = {}
## Seconds a connection may stay open without sending a complete request.
var idle_timeout_s: float = DEFAULT_IDLE_TIMEOUT_S

var _server: TCPServer = null
var _conns: Array[StreamPeerTCP] = []
var _bufs: Array[PackedByteArray] = []
var _ages: Array[float] = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Listens on 127.0.0.1 with an OS-chosen port. False if it can't.
func start() -> bool:
	stop()
	_server = TCPServer.new()
	var err := _server.listen(0, BIND_ADDRESS)
	if err != OK:
		push_warning("Strava callback: can't listen on %s (%s)" % [BIND_ADDRESS, error_string(err)])
		_server = null
		return false
	port = _server.get_local_port()
	done = false
	params = {}
	set_process(true)
	return true


func is_listening() -> bool:
	return _server != null and _server.is_listening()


## Connections accepted and not yet answered or dropped.
func open_connections() -> int:
	return _conns.size()


## The redirect_uri for this server.
func redirect_uri() -> String:
	return "http://%s:%d%s" % [BIND_ADDRESS, port, CALLBACK_PATH]


func stop() -> void:
	for c in _conns:
		c.disconnect_from_host()
	_conns.clear()
	_bufs.clear()
	_ages.clear()
	if _server != null:
		_server.stop()
		_server = null
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available() and _conns.size() < MAX_CONNECTIONS:
		var c := _server.take_connection()
		if c != null:
			_conns.append(c)
			_bufs.append(PackedByteArray())
			_ages.append(0.0)
	var i := 0
	while i < _conns.size():
		_ages[i] += delta
		if _service(i) or _ages[i] > idle_timeout_s:
			_conns[i].disconnect_from_host()
			_conns.remove_at(i)
			_bufs.remove_at(i)
			_ages.remove_at(i)
		else:
			i += 1


## Reads from connection i; true once it was answered or dropped.
func _service(i: int) -> bool:
	var c := _conns[i]
	c.poll()
	var st := c.get_status()
	if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
		return true
	if st != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var avail := c.get_available_bytes()
	if avail > 0:
		var got: Array = c.get_partial_data(avail)
		if int(got[0]) == OK:
			_bufs[i].append_array(got[1] as PackedByteArray)
	var buf := _bufs[i]
	if buf.size() > MAX_REQUEST_BYTES:
		_respond(c, 431, "Request too large")
		return true
	var text := buf.get_string_from_ascii()
	if text.find("\r\n\r\n") < 0:
		return false
	var line := text.substr(0, text.find("\r\n"))
	var parts := line.split(" ")
	if parts.size() < 2 or parts[0] != "GET":
		_respond(c, 405, "Method not allowed")
		return true
	var target := parts[1]
	var q := target.find("?")
	var path := target if q < 0 else target.substr(0, q)
	if path != CALLBACK_PATH or done:
		_respond(c, 404, "Not found")
		return true
	var query := "" if q < 0 else target.substr(q + 1)
	params = parse_query(query)
	done = true
	if params.has("error"):
		var denied := tr_or(
			"RIDES_CALLBACK_DENIED",
			"Strava did not connect ({error}). You can close this window and return to WATTLANDS."
		)
		_respond(c, 200, denied.xml_escape().format({"error": str(params["error"]).xml_escape()}))
	else:
		_respond(
			c,
			200,
			(
				tr_or(
					"RIDES_CALLBACK_CONNECTING",
					"WATTLANDS is connecting to Strava. You can close this window and return to the game."
				)
				. xml_escape()
			)
		)
	received.emit(params)
	return true


func _respond(c: StreamPeerTCP, code: int, message: String) -> void:
	var reason := {
		200: "OK",
		404: "Not Found",
		405: "Method Not Allowed",
		431: "Request Header Fields Too Large"
	}
	var body := (
		(
			'<!doctype html><html><head><meta charset="utf-8"><title>WATTLANDS</title></head>'
			+ '<body style="font-family:sans-serif"><p>%s</p></body></html>' % message
		)
		. to_utf8_buffer()
	)
	var head := (
		(
			"HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\n"
			+ "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
		)
		% [code, str(reason.get(code, "OK")), body.size()]
	)
	c.put_data(head.to_ascii_buffer())
	c.put_data(body)


## The translation of `key` (content/strings/rides.csv), or `fallback` when there is none.
static func tr_or(key: String, fallback: String) -> String:
	var t := String(TranslationServer.translate(key))
	return fallback if t == key or t == "" else t


## "a=1&b=x%20y" -> {"a": "1", "b": "x y"} ("+" is a space).
static func parse_query(query: String) -> Dictionary:
	var out := {}
	for pair in query.split("&", false):
		var eq := pair.find("=")
		var k := pair if eq < 0 else pair.substr(0, eq)
		var v := "" if eq < 0 else pair.substr(eq + 1)
		out[k.replace("+", " ").uri_decode()] = v.replace("+", " ").uri_decode()
	return out
