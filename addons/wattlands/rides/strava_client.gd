class_name StravaClient
extends Node
## Strava OAuth, tokens and uploads for the player's own Strava API app (BRIEF 3.8).
## Owned by WlRides; every operation is a coroutine (await it).
##
## Connect: a StravaCallbackServer on 127.0.0.1 (free port) waits up to 5 minutes for
## GET /strava/callback; the browser opens <oauth base>/authorize with response_type=code,
## approval_prompt=auto, scope=activity:write, a random state and
## redirect_uri=http://127.0.0.1:<port>/strava/callback. The state is checked, then the code is
## exchanged at <oauth base>/token (grant_type=authorization_code with the client id and
## secret).
## Tokens: access tokens last 6 hours; ensure_token() refreshes (grant_type=refresh_token)
## within REFRESH_MARGIN_S of expiry and always keeps the newest refresh token (Strava rotates
## them). API calls send the token only in the Authorization header. Client id, secret and
## tokens live only in strava.json (Paths.strava_path()) and are never logged.
## Disconnect: POST <oauth base>/revoke with HTTP Basic client id/secret and the refresh
## token, then the secret and tokens are deleted (the client id stays for a later connect).
## Upload: multipart POST <api base>/uploads (file, data_type=fit, trainer=1, name,
## description, external_id), then GET <api base>/uploads/{id} every poll_interval_s for up
## to poll_timeout_s until activity_id or error. A duplicate counts as uploaded. A 401 is
## retried once after a refresh; a 429 backs off (Retry-After, else backoff_s doubling) up to
## max_rate_retries times.
## Network lock (BRIEF 1): while Locks.network_locked() every request goes through
## Locks.network_allows() (loopback only; a refusal logs "network integrations locked"),
## the browser is never opened, and Connect fetches the authorize URL itself with
## HTTPRequest, following redirects hop by hop (each hop checked), so the mock's redirect
## reaches the loopback callback.

## "disconnected", "connecting", "connected", "error" (EventBus.strava_state_changed).
signal state_changed(state: String, detail: String)
## Intermediate upload states: "uploading", "processing" (WlRides emits the final state).
signal upload_progress(ride_id: String, state: String, detail: String)

const STATE_DISCONNECTED := "disconnected"
const STATE_CONNECTING := "connecting"
const STATE_CONNECTED := "connected"
const STATE_ERROR := "error"

const SCOPE_WRITE := "activity:write"
const SCOPE_PROFILE := "profile:read_all"
const ACCESS_LIFETIME_S := 21600
## Refresh when the access token has less than this left.
const REFRESH_MARGIN_S := 600
const STORE_VERSION := 1

## Bases (WlRides sets them from --strava-base or Settings).
var api_base: String = "https://www.strava.com/api/v3"
var oauth_base: String = "https://www.strava.com/oauth"
## strava.json ("" = Paths.strava_path(), resolved on each load and save).
var store_path: String = ""
var poll_interval_s: float = 3.0
var poll_timeout_s: float = 120.0
var callback_timeout_s: float = 300.0
var request_timeout_s: float = 30.0
## First 429 wait without Retry-After; doubles on each retry.
var backoff_s: float = 15.0
var max_backoff_s: float = 120.0
var max_rate_retries: int = 3
var max_redirects: int = 5
## Unix seconds now (token expiry). Default: the system clock. Tests inject a clock.
var now_func: Callable = Callable()
## Opens the authorize URL in a browser (default OS.shell_open). Never called while the
## network lock is set.
var browser_opener: Callable = Callable()

var _creds: Dictionary = {}
var _state: String = STATE_DISCONNECTED
var _connecting: bool = false
var _cancel_requested: bool = false
var _refreshing: bool = false
var _last_refresh_ok: bool = false
var _last_refresh_result: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- Store ---------------------------------------------------------------------------


func store_file() -> String:
	return store_path if store_path != "" else Paths.strava_path()


## Loads strava.json (missing: disconnected).
func load_store() -> void:
	_creds = {}
	var p := store_file()
	if FileAccess.file_exists(p):
		var parsed: Variant = parse_json(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			_creds = parsed
		else:
			push_warning("Strava: unreadable strava.json; treating as disconnected")
	_state = STATE_CONNECTED if has_tokens() else STATE_DISCONNECTED


func save_store() -> bool:
	var p := store_file()
	var dir := p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Strava: can't write strava.json")
		return false
	var data := _creds.duplicate(true)
	data["version"] = STORE_VERSION
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	# Owner-only on POSIX; Windows keeps the user profile's ACLs.
	if OS.get_name() != "Windows":
		FileAccess.set_unix_permissions(tmp, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	return DirAccess.rename_absolute(tmp, p) == OK


func has_tokens() -> bool:
	return str(_creds.get("refresh_token", "")) != "" and str(_creds.get("access_token", "")) != ""


func state() -> String:
	return _state


func client_id() -> String:
	return str(_creds.get("client_id", ""))


## Public facts about the connection (never the secret or tokens): {connected, client_id,
## athlete_id, athlete_name, scope, expires_at}.
func info() -> Dictionary:
	return {
		"connected": has_tokens(),
		"client_id": client_id(),
		"athlete_id": int(_creds.get("athlete_id", 0)),
		"athlete_name": str(_creds.get("athlete_name", "")),
		"scope": str(_creds.get("scope", "")),
		"expires_at": int(_creds.get("expires_at", 0)),
	}


func has_scope(scope: String) -> bool:
	return str(_creds.get("scope", "")).split(",").has(scope)


## <root>/api/v3 and <root>/oauth for --strava-base=<root> (the mock serves both). A root
## given with either suffix ("<root>/api/v3" or "<root>/oauth") maps the same way.
static func bases_from_root(root: String) -> Dictionary:
	var r := root.strip_edges().trim_suffix("/")
	for suffix: String in ["/api/v3", "/oauth"]:
		if r.ends_with(suffix):
			r = r.substr(0, r.length() - suffix.length())
	return {"api": r + "/api/v3", "oauth": r + "/oauth"}


func now_unix() -> int:
	if now_func.is_valid():
		return int(now_func.call())
	return int(Time.get_unix_time_from_system())


# --- Connect / disconnect ------------------------------------------------------------


## The authorize URL for `redirect_uri` and `oauth_state`.
func authorize_url(p_client_id: String, redirect_uri: String, oauth_state: String, with_profile: bool = false) -> String:
	var scope := SCOPE_WRITE + ("," + SCOPE_PROFILE if with_profile else "")
	return "%s/authorize?client_id=%s&response_type=code&redirect_uri=%s&approval_prompt=auto&scope=%s&state=%s" % [
		oauth_base, p_client_id.uri_encode(), redirect_uri.uri_encode(), scope.uri_encode(), oauth_state.uri_encode()]


## Runs the OAuth flow; true once tokens are stored. `with_profile` adds profile:read_all
## (needed for the FTP and weight import, P1).
func connect_account(p_client_id: String, p_client_secret: String, with_profile: bool = false) -> bool:
	var cid := p_client_id.strip_edges()
	var secret := p_client_secret.strip_edges()
	if cid == "" or secret == "":
		push_warning("Strava: connect needs the client ID and secret of your Strava API app")
		_set_state(STATE_ERROR, "missing_credentials")
		return false
	if _connecting:
		push_warning("Strava: a connect is already running")
		return false
	_connecting = true
	_cancel_requested = false
	_set_state(STATE_CONNECTING, "")
	var ok := await _connect_flow(cid, secret, with_profile)
	_connecting = false
	_cancel_requested = false
	return ok


## Stops waiting for the browser's callback (the connect ends with "error"/"cancelled").
func cancel_connect() -> void:
	if _connecting:
		_cancel_requested = true


func is_connecting() -> bool:
	return _connecting


func _connect_flow(cid: String, secret: String, with_profile: bool) -> bool:
	var cb := StravaCallbackServer.new()
	add_child(cb)
	if not cb.start():
		cb.queue_free()
		_set_state(STATE_ERROR, "callback_listen_failed")
		return false
	var oauth_state := Crypto.new().generate_random_bytes(16).hex_encode()
	var url := authorize_url(cid, cb.redirect_uri(), oauth_state, with_profile)
	if Locks.network_locked():
		print("Strava: %s: no browser; fetching the authorize URL in-app (loopback only)" % Locks.NET_MESSAGE)
		var r := await _fetch_following(url)
		if not cb.done:
			cb.stop()
			cb.queue_free()
			_set_state(STATE_ERROR, "network_locked" if bool(r.get("refused", false)) else "authorize_failed")
			return false
	else:
		if browser_opener.is_valid():
			browser_opener.call(url)
		else:
			OS.shell_open(url)
		var timer := _timer(callback_timeout_s)
		while not cb.done and timer.time_left > 0.0 and not _cancel_requested:
			await get_tree().process_frame
	var params := cb.params.duplicate()
	var got := cb.done
	cb.stop()
	cb.queue_free()
	if not got:
		_set_state(STATE_ERROR, "cancelled" if _cancel_requested else "callback_timeout")
		return false
	if str(params.get("state", "")) != oauth_state:
		push_warning("Strava: the callback's state doesn't match; ignoring it")
		_set_state(STATE_ERROR, "state_mismatch")
		return false
	if params.has("error"):
		_set_state(STATE_ERROR, "access_denied" if str(params["error"]) == "access_denied" else "authorize_error")
		return false
	var code := str(params.get("code", ""))
	var granted := str(params.get("scope", ""))
	if code == "":
		_set_state(STATE_ERROR, "no_code")
		return false
	if granted != "" and not granted.split(",").has(SCOPE_WRITE):
		_set_state(STATE_ERROR, "scope_missing")
		return false
	var body := form_encode({
		"client_id": cid, "client_secret": secret, "code": code,
		"grant_type": "authorization_code",
	})
	var tr := await _request(HTTPClient.METHOD_POST, oauth_base + "/token",
		["Content-Type: application/x-www-form-urlencoded", "Accept: application/json"], body.to_utf8_buffer())
	if int(tr["code"]) != 200:
		_set_state(STATE_ERROR, _failure_detail(tr, "token_exchange_failed"))
		return false
	var j: Variant = parse_json((tr["body"] as PackedByteArray).get_string_from_utf8())
	if not (j is Dictionary) or str((j as Dictionary).get("access_token", "")) == "" or str((j as Dictionary).get("refresh_token", "")) == "":
		_set_state(STATE_ERROR, "token_exchange_failed")
		return false
	var tok: Dictionary = j
	_creds = {
		"client_id": cid,
		"client_secret": secret,
		"access_token": str(tok["access_token"]),
		"refresh_token": str(tok["refresh_token"]),
		"expires_at": _expires_at(tok),
		"scope": granted if granted != "" else SCOPE_WRITE,
	}
	var athlete: Variant = tok.get("athlete", null)
	if athlete is Dictionary:
		_creds["athlete_id"] = int((athlete as Dictionary).get("id", 0))
		_creds["athlete_name"] = ("%s %s" % [str((athlete as Dictionary).get("firstname", "")), str((athlete as Dictionary).get("lastname", ""))]).strip_edges()
	save_store()
	print("Strava: connected")
	_set_state(STATE_CONNECTED, "")
	return true


## Revokes the grant (best effort) and deletes the secret and tokens. True if the revoke
## call succeeded (the local tokens are deleted either way).
func disconnect_account() -> bool:
	var revoked := false
	var refresh := str(_creds.get("refresh_token", ""))
	if refresh != "":
		var basic := Marshalls.utf8_to_base64("%s:%s" % [client_id(), str(_creds.get("client_secret", ""))])
		var r := await _request(HTTPClient.METHOD_POST, oauth_base + "/revoke",
			["Authorization: Basic " + basic, "Content-Type: application/x-www-form-urlencoded"],
			form_encode({"token": refresh, "token_type_hint": "refresh_token"}).to_utf8_buffer())
		revoked = int(r["code"]) == 200
		if int(r["code"]) == 404 or int(r["code"]) == 405:
			# No revoke endpoint at this base: use Strava's deauthorize, token in the header.
			var d := await _request(HTTPClient.METHOD_POST, oauth_base + "/deauthorize",
				["Authorization: Bearer " + str(_creds.get("access_token", ""))], PackedByteArray())
			revoked = int(d["code"]) == 200
	var keep_id := client_id()
	_creds = {}
	if keep_id != "":
		_creds["client_id"] = keep_id
		save_store()
	elif FileAccess.file_exists(store_file()):
		DirAccess.remove_absolute(store_file())
	print("Strava: disconnected")
	# Nothing to revoke (never connected) is not a failure.
	_set_state(STATE_DISCONNECTED, "" if revoked or refresh == "" else "revoke_failed")
	return revoked


# --- Tokens -----------------------------------------------------------------------------


## True when an access token is usable, refreshing it first if it expires within
## REFRESH_MARGIN_S.
func ensure_token() -> bool:
	if not has_tokens():
		return false
	if int(_creds.get("expires_at", 0)) - now_unix() > REFRESH_MARGIN_S:
		return true
	return await refresh_tokens()


## grant_type=refresh_token; stores the new access token, expiry and (rotated) refresh
## token. Concurrent callers share one request.
func refresh_tokens() -> bool:
	if not has_tokens():
		return false
	if _refreshing:
		while _refreshing:
			await get_tree().process_frame
		return _last_refresh_ok
	_refreshing = true
	var r := await _request(HTTPClient.METHOD_POST, oauth_base + "/token",
		["Content-Type: application/x-www-form-urlencoded", "Accept: application/json"],
		form_encode({
			"client_id": client_id(), "client_secret": str(_creds.get("client_secret", "")),
			"grant_type": "refresh_token", "refresh_token": str(_creds.get("refresh_token", "")),
		}).to_utf8_buffer())
	var ok := false
	var code := int(r["code"])
	if code == 200:
		var j: Variant = parse_json((r["body"] as PackedByteArray).get_string_from_utf8())
		if j is Dictionary and str((j as Dictionary).get("access_token", "")) != "":
			var tok: Dictionary = j
			_creds["access_token"] = str(tok["access_token"])
			# Strava rotates refresh tokens: always keep the newest one it sent.
			if str(tok.get("refresh_token", "")) != "":
				_creds["refresh_token"] = str(tok["refresh_token"])
			_creds["expires_at"] = _expires_at(tok)
			save_store()
			ok = true
	elif code == 400:
		# The refresh token is no longer valid (revoked on strava.com): reconnect needed.
		push_warning("Strava: the authorization is no longer valid; reconnect in Settings")
		var keep_id := client_id()
		var keep_secret := str(_creds.get("client_secret", ""))
		_creds = {"client_id": keep_id, "client_secret": keep_secret}
		save_store()
		_set_state(STATE_ERROR, "reauthorize")
	elif code == 401:
		# Strava rejected the client id or secret (the app's secret was changed): reconnect.
		push_warning("Strava: the API app credentials were rejected; reconnect in Settings")
		_set_state(STATE_ERROR, "client_credentials")
	_last_refresh_ok = ok
	_last_refresh_result = {} if ok else r
	_refreshing = false
	return ok


# --- API ----------------------------------------------------------------------------


## An authorized API call: <api base><api_path>. Refreshes once on 401 and backs off on
## 429. Returns _request()'s result ({code, result, headers, body, refused, offline}).
func api(method: int, api_path: String, headers: PackedStringArray = PackedStringArray(), body: PackedByteArray = PackedByteArray()) -> Dictionary:
	if not await ensure_token():
		if has_tokens() and not _last_refresh_result.is_empty():
			# The refresh failed for now (offline, refused, a server error): report that.
			return _last_refresh_result
		return _result(0, HTTPRequest.RESULT_SUCCESS, PackedStringArray(), PackedByteArray(), false, false, "not_connected")
	var refreshed := false
	var attempt := 0
	while true:
		var h := PackedStringArray(headers)
		h.append("Authorization: Bearer " + str(_creds.get("access_token", "")))
		h.append("Accept: application/json")
		var r := await _request(method, api_base + api_path, h, body)
		var code := int(r["code"])
		if code == 401 and not refreshed:
			refreshed = true
			if await refresh_tokens():
				continue
			return r
		if code == 429 and attempt < max_rate_retries:
			var wait := _retry_after(r["headers"] as PackedStringArray)
			if wait < 0.0:
				wait = minf(backoff_s * pow(2.0, attempt), max_backoff_s)
			attempt += 1
			print("Strava: rate limited; retrying in %.1f s" % wait)
			await _timer(wait).timeout
			continue
		return r
	return {}


## Uploads a FIT file and polls until Strava reports the activity. Returns {state, detail,
## activity_id, upload_id, permanent}: state "uploaded", "duplicate", "failed" or
## "offline"; permanent = true when retrying can't help.
func upload_fit(ride_id: String, fit_path: String, activity_name: String, description: String) -> Dictionary:
	if not has_tokens():
		return {"state": "queued", "detail": "not_connected", "upload_id": 0, "permanent": false}
	var bytes := FileAccess.get_file_as_bytes(fit_path)
	if bytes.is_empty():
		return {"state": "failed", "detail": "missing_file", "upload_id": 0, "permanent": true}
	upload_progress.emit(ride_id, "uploading", "")
	var boundary := "WattlandsBoundary" + Crypto.new().generate_random_bytes(12).hex_encode()
	var body := build_multipart(boundary, [
		["data_type", "fit"], ["trainer", "1"], ["name", activity_name],
		["description", description], ["external_id", ride_id],
	], "file", fit_path.get_file(), bytes)
	var r := await api(HTTPClient.METHOD_POST, "/uploads",
		["Content-Type: multipart/form-data; boundary=" + boundary], body)
	var code := int(r["code"])
	if code != 201 and code != 200:
		return _upload_failure(r, 0)
	var j: Variant = parse_json((r["body"] as PackedByteArray).get_string_from_utf8())
	if not (j is Dictionary):
		return {"state": "failed", "detail": "bad_response", "upload_id": 0, "permanent": false}
	var done := _upload_outcome(j)
	if not done.is_empty():
		return done
	return await poll_upload(ride_id, _upload_id(j))


## Polls GET /uploads/{id} until activity_id or error (or poll_timeout_s passes).
func poll_upload(ride_id: String, upload_id: int) -> Dictionary:
	upload_progress.emit(ride_id, "processing", "")
	var waited := 0.0
	while true:
		await _timer(poll_interval_s).timeout
		waited += poll_interval_s
		var r := await api(HTTPClient.METHOD_GET, "/uploads/%d" % upload_id)
		var code := int(r["code"])
		if code == 200:
			var j: Variant = parse_json((r["body"] as PackedByteArray).get_string_from_utf8())
			if j is Dictionary:
				var done := _upload_outcome(j)
				if not done.is_empty():
					return done
		elif code == 404:
			return {"state": "failed", "detail": "upload_not_found", "upload_id": 0, "permanent": false}
		else:
			return _upload_failure(r, upload_id)
		if waited >= poll_timeout_s:
			return {"state": "failed", "detail": "processing_timeout", "upload_id": upload_id, "permanent": false}
	return {}


## GET /athlete (P1 import; ftp and weight need profile:read_all). {} on failure.
func fetch_athlete() -> Dictionary:
	var r := await api(HTTPClient.METHOD_GET, "/athlete")
	if int(r["code"]) != 200:
		return {}
	var j: Variant = parse_json((r["body"] as PackedByteArray).get_string_from_utf8())
	return j if j is Dictionary else {}


# --- Helpers ---------------------------------------------------------------------------


## multipart/form-data for HTTPRequest.request_raw(): `fields` is [[name, value], ...], then
## one file part.
static func build_multipart(boundary: String, fields: Array, file_field: String, filename: String, data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	for f: Array in fields:
		out.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n" % [boundary, str(f[0])]).to_utf8_buffer())
		out.append_array(str(f[1]).to_utf8_buffer())
		out.append_array("\r\n".to_utf8_buffer())
	var safe_name := filename.replace("\"", "").replace("\r", "").replace("\n", "")
	out.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n" % [
		boundary, file_field, safe_name]).to_utf8_buffer())
	out.append_array(data)
	out.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return out


## application/x-www-form-urlencoded.
static func form_encode(fields: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: Variant in fields.keys():
		parts.append("%s=%s" % [str(k).uri_encode(), str(fields[k]).uri_encode()])
	return "&".join(parts)


## The value of header `name` (case-insensitive), or "".
static func header_value(headers: PackedStringArray, name: String) -> String:
	var want := name.to_lower() + ":"
	for h in headers:
		if h.to_lower().begins_with(want):
			return h.substr(want.length()).strip_edges()
	return ""


## Absolute URL for a redirect Location relative to `from`.
static func resolve_url(from: String, location: String) -> String:
	if location.contains("://"):
		return location
	var scheme_end := from.find("://")
	var rest_start := scheme_end + 3 if scheme_end >= 0 else 0
	var slash := from.find("/", rest_start)
	var origin := from if slash < 0 else from.substr(0, slash)
	if location.begins_with("/"):
		return origin + location
	var dir := from.substr(0, from.rfind("/") + 1) if slash >= 0 else origin + "/"
	return dir + location


## One HTTP request through the network lock. Returns {code, result, headers, body,
## refused, offline, detail}.
func _request(method: int, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	if not Locks.network_allows(url):
		return _result(0, HTTPRequest.RESULT_CANT_CONNECT, PackedStringArray(), PackedByteArray(), true, false, "network_locked")
	if not is_inside_tree():
		push_warning("Strava: client not in the scene tree; request skipped")
		return _result(0, HTTPRequest.RESULT_CANT_CONNECT, PackedStringArray(), PackedByteArray(), false, true, "not_in_tree")
	var req := HTTPRequest.new()
	req.max_redirects = 0
	req.timeout = request_timeout_s
	req.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(req)
	var err := req.request_raw(url, headers, method as HTTPClient.Method, body)
	if err != OK:
		req.queue_free()
		return _result(0, HTTPRequest.RESULT_CANT_CONNECT, PackedStringArray(), PackedByteArray(), false, true, "request_failed")
	var res: Array = await req.request_completed
	req.queue_free()
	# Continue on the next frame, outside the HTTPRequest's signal emission, so callers may
	# free this client (and its HTTPRequest child) as soon as they get the result.
	if is_inside_tree():
		await get_tree().process_frame
	var result := int(res[0])
	var code := int(res[1])
	var ok_result := result == HTTPRequest.RESULT_SUCCESS or (result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED and code >= 300 and code < 400)
	if not ok_result or code == 0:
		return _result(0, result, res[2] as PackedStringArray, PackedByteArray(), false, true, "offline")
	return _result(code, result, res[2] as PackedStringArray, res[3] as PackedByteArray, false, false, "")


## GET `url`, following up to max_redirects redirects; every hop passes the network lock.
func _fetch_following(url: String) -> Dictionary:
	var current := url
	for i in max_redirects + 1:
		var r := await _request(HTTPClient.METHOD_GET, current, PackedStringArray(), PackedByteArray())
		var code := int(r["code"])
		if code in [301, 302, 303, 307, 308]:
			var loc := header_value(r["headers"] as PackedStringArray, "Location")
			if loc == "":
				return r
			current = resolve_url(current, loc)
			continue
		return r
	return _result(0, HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, PackedStringArray(), PackedByteArray(), false, false, "too_many_redirects")


static func _result(code: int, result: int, headers: PackedStringArray, body: PackedByteArray, refused: bool, offline: bool, detail: String) -> Dictionary:
	return {"code": code, "result": result, "headers": headers, "body": body,
		"refused": refused, "offline": offline, "detail": detail}


func _upload_outcome(j: Dictionary) -> Dictionary:
	var activity: Variant = j.get("activity_id", null)
	if activity != null and int(activity) > 0:
		return {"state": "uploaded", "detail": "", "activity_id": int(activity), "upload_id": _upload_id(j), "permanent": false}
	var error: Variant = j.get("error", null)
	if error != null and str(error) != "":
		var msg := str(error)
		if msg.to_lower().contains("duplicate"):
			return {"state": "duplicate", "detail": msg, "activity_id": duplicate_activity_id(msg), "upload_id": _upload_id(j), "permanent": false}
		return {"state": "failed", "detail": msg, "upload_id": _upload_id(j), "permanent": true}
	return {}


func _upload_failure(r: Dictionary, upload_id: int) -> Dictionary:
	var code := int(r["code"])
	if bool(r.get("refused", false)):
		return {"state": "failed", "detail": "network_locked", "upload_id": upload_id, "permanent": false}
	if bool(r.get("offline", false)) or code == 0:
		var detail := str(r.get("detail", "offline"))
		return {"state": "queued" if detail == "not_connected" else "offline", "detail": detail, "upload_id": upload_id, "permanent": false}
	if code == 401:
		return {"state": "failed", "detail": "unauthorized", "upload_id": upload_id, "permanent": false}
	if code == 429:
		return {"state": "failed", "detail": "rate_limited", "upload_id": upload_id, "permanent": false}
	if code >= 500:
		return {"state": "failed", "detail": "server_error_%d" % code, "upload_id": upload_id, "permanent": false}
	return {"state": "failed", "detail": _failure_detail(r, "rejected_%d" % code), "upload_id": upload_id, "permanent": true}


## The activity id in a duplicate message ("... duplicate of activity 123"), or 0.
static func duplicate_activity_id(message: String) -> int:
	var re := RegEx.create_from_string("activit(?:y|ies)/?\\s*(\\d+)")
	var m := re.search(message)
	return int(m.get_string(1)) if m != null else 0


static func _upload_id(j: Dictionary) -> int:
	var s := str(j.get("id_str", ""))
	if s.is_valid_int():
		return int(s)
	return int(j.get("id", 0))


## A short reason from a Strava error response (never the request or tokens).
static func _failure_detail(r: Dictionary, fallback: String) -> String:
	if bool(r.get("refused", false)):
		return "network_locked"
	if bool(r.get("offline", false)):
		return "offline"
	var j: Variant = parse_json((r.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if j is Dictionary and (j as Dictionary).has("message"):
		return "%s (%d)" % [str((j as Dictionary)["message"]), int(r["code"])]
	return fallback


func _expires_at(tok: Dictionary) -> int:
	if tok.has("expires_at"):
		return int(tok["expires_at"])
	return now_unix() + int(tok.get("expires_in", ACCESS_LIFETIME_S))


static func _retry_after(headers: PackedStringArray) -> float:
	var v := header_value(headers, "Retry-After")
	return float(v) if v.is_valid_float() else -1.0


func _timer(seconds: float) -> SceneTreeTimer:
	return get_tree().create_timer(maxf(seconds, 0.0), true, false, true)


func _set_state(s: String, detail: String) -> void:
	_state = s
	state_changed.emit(s, detail)


## Parses JSON text without logging an engine error on bad input (JSON.parse_string logs
## one). Returns null when the text isn't JSON.
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
