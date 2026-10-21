extends GutTest
## StravaClient against server/mock_strava (BRIEF 3.8, 7.5): connect through the locked
## loopback flow, upload and polling, refresh with rotation, duplicates, recovery from 401
## and 429, offline, revoke, tokens only in the Authorization header, and no secret in any
## log. The mock is a Node.js process started here and killed in after_all.

const MockRunner := preload("res://tests/rides/mock_strava_runner.gd")
const Util := preload("res://tests/rides/rides_test_util.gd")
const NOW := 1_800_000_000
const START := 1_800_000_000

var _mock: Node = null
var _mock_ok: bool = false
var _dir: String = ""
var _now: int = NOW
var _opened: Array = []


func before_all() -> void:
	_mock = MockRunner.new()
	add_child(_mock)
	_mock_ok = await _mock.start(NOW)


func after_all() -> void:
	if _mock != null:
		_mock.stop()
		remove_child(_mock)
		_mock.free()
		_mock = null


func before_each() -> void:
	assert_true(_mock_ok, "mock_strava is running (node on PATH)")
	_dir = Paths.make_temp_dir("wattlands_strava")
	Paths.set_override(_dir)
	_now = NOW
	_opened = []
	if _mock_ok:
		await _mock.reset()
		await _mock.set_clock(NOW)
		await _mock.config({"processing_polls": 1})


func after_each() -> void:
	Paths.set_override("")
	Util.remove_tree(_dir)


func _client() -> StravaClient:
	var c := StravaClient.new()
	c.api_base = _mock.api_base()
	c.oauth_base = _mock.oauth_base()
	c.now_func = func() -> int: return _now
	c.poll_interval_s = 0.02
	c.backoff_s = 0.02
	c.request_timeout_s = 10.0
	c.browser_opener = func(url: String) -> void: _opened.append(url)
	add_child_autofree(c)
	c.load_store()
	return c


func _connected_client() -> StravaClient:
	var c := _client()
	var ok: bool = await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_true(ok, "connected")
	return c


## A short saved ride: [fit_path, summary].
func _ride(game: String = "workout") -> Array:
	var rec := RideRecorder.new()
	rec.start(game, "e2e", START, 0.0)
	for i in 61:
		rec.record(float(i), 180.0, 88.0, 30.0)
	rec.stop(60.0)
	var path := rec.save()
	return [path, rec.summary()]


func _store() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Paths.strava_path()))


func _routes() -> Array:
	var out: Array = []
	for r: Dictionary in await _mock.requests():
		out.append("%s:%d" % [str(r["route"]), int(r["status"])])
	return out


# --- Connect -----------------------------------------------------------------------------


func test_connect_through_the_locked_loopback_flow() -> void:
	assert_true(Locks.network_locked(), "tests run with WATTLANDS_NO_NETWORK_INTEGRATIONS=1")
	var c := _client()
	var states: Array = []
	c.state_changed.connect(func(s: String, _d: String) -> void: states.append(s))
	var ok: bool = await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_true(ok)
	assert_true(c.has_tokens())
	assert_eq(c.state(), "connected")
	assert_eq(states, ["connecting", "connected"])
	assert_eq(_opened, [], "no browser while the network lock is set")
	var store := _store()
	assert_eq(store["client_id"], MockRunner.CLIENT_ID)
	assert_eq(
		store["client_secret"],
		MockRunner.CLIENT_SECRET,
		"the secret stays on this PC, in strava.json"
	)
	assert_eq(int(store["expires_at"]), NOW + 21600, "6 h access token")
	assert_ne(str(store["refresh_token"]), "")
	assert_eq(int(store["athlete_id"]), 4242)
	assert_true(str(store["scope"]).split(",").has("activity:write"))
	assert_eq(await _routes(), ["authorize:302", "token:200"])
	var info := c.info()
	assert_false(
		info.has("access_token") or info.has("client_secret") or info.has("refresh_token"),
		"info() has no secrets"
	)


func test_defaults_follow_the_brief() -> void:
	var c := StravaClient.new()
	assert_eq(c.api_base, "https://www.strava.com/api/v3")
	assert_eq(c.oauth_base, "https://www.strava.com/oauth")
	assert_eq(c.poll_interval_s, 3.0, "poll every 3 s")
	assert_eq(c.poll_timeout_s, 120.0, "for up to 2 minutes")
	assert_eq(c.callback_timeout_s, 300.0, "the loopback callback waits up to 5 minutes")
	assert_eq(StravaClient.ACCESS_LIFETIME_S, 21600, "6 h access tokens")
	assert_between(StravaClient.REFRESH_MARGIN_S, 1, 3600, "refresh shortly before expiry")
	assert_eq(c.process_mode, Node.PROCESS_MODE_ALWAYS)
	c.free()


func test_disconnect_when_never_connected_sends_nothing() -> void:
	var c := _client()
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	assert_false(await c.disconnect_account(), "nothing was revoked")
	assert_eq(details, [""], "not a failure")
	assert_eq(await _routes(), [], "no request")


func test_authorize_url_parameters() -> void:
	var c := _client()
	var url := c.authorize_url("12345", "http://127.0.0.1:5000/strava/callback", "abc", false)
	assert_true(url.begins_with(_mock.oauth_base() + "/authorize?"))
	for part in [
		"client_id=12345",
		"response_type=code",
		"approval_prompt=auto",
		"scope=activity%3Awrite",
		"state=abc",
		"redirect_uri=http%3A%2F%2F127.0.0.1%3A5000%2Fstrava%2Fcallback"
	]:
		assert_string_contains(url, part)
	assert_string_contains(
		c.authorize_url("1", "x", "s", true), "scope=activity%3Awrite%2Cprofile%3Aread_all"
	)


func test_connect_rejects_a_forged_state() -> void:
	await _mock.admin(
		HTTPClient.METHOD_POST,
		"/admin/fault",
		{"route": "authorize", "status": 302, "tamper_state": true}
	)
	var c := _client()
	var ok: bool = await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	assert_false(ok)
	assert_push_warning("state doesn't match")
	assert_eq(c.state(), "error")
	assert_false(c.has_tokens())
	assert_false((await _routes()).has("token:200"), "the code is never exchanged")


func test_connect_without_the_upload_permission_fails() -> void:
	# The rider unticked "Upload your activities" on Strava's consent page.
	await _mock.admin(
		HTTPClient.METHOD_POST,
		"/admin/fault",
		{"route": "authorize", "status": 302, "scope": "read"}
	)
	var c := _client()
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	assert_false(await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET))
	assert_eq(details.back(), "scope_missing")
	assert_false(c.has_tokens())
	assert_eq(await _routes(), ["authorize:302"], "the code is never exchanged")


func test_a_redirect_loop_stops_at_max_redirects() -> void:
	var loop_url: String = _mock.oauth_base() + "/authorize?client_id=12345&response_type=code"
	await _mock.admin(
		HTTPClient.METHOD_POST,
		"/admin/fault",
		{"route": "authorize", "status": 302, "count": 20, "location": loop_url}
	)
	var c := _client()
	c.max_redirects = 3
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	assert_false(await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET))
	assert_eq(details.back(), "authorize_failed")
	assert_eq(
		(await _routes()).size(), 4, "the first request plus three redirects, then it gives up"
	)


func test_connect_denied_by_the_rider() -> void:
	await _mock.fault("authorize", 403)
	var c := _client()
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	assert_false(await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET))
	assert_eq(details.back(), "access_denied")


func test_connect_needs_credentials() -> void:
	var c := _client()
	assert_false(await c.connect_account("", "secret"))
	assert_push_warning("client ID and secret")
	assert_eq(c.state(), "error")


func test_connect_with_a_wrong_secret_fails() -> void:
	var c := _client()
	assert_false(await c.connect_account(MockRunner.CLIENT_ID, "wrong-secret"))
	assert_eq(c.state(), "error")
	assert_false(c.has_tokens())
	assert_false(FileAccess.file_exists(Paths.strava_path()))


# --- Upload --------------------------------------------------------------------------------


func test_upload_and_polling() -> void:
	var c: StravaClient = await _connected_client()
	var ride := _ride()
	var progress: Array = []
	c.upload_progress.connect(func(_id: String, s: String, _d: String) -> void: progress.append(s))
	var res: Dictionary = await c.upload_fit(
		str(ride[1]["ride_id"]), str(ride[0]), "Wattlands: Workout", "desc"
	)
	assert_eq(res["state"], "uploaded")
	assert_gt(int(res["activity_id"]), 0)
	assert_gt(int(res["upload_id"]), 0)
	assert_eq(progress, ["uploading", "processing"])
	var ups: Array = await _mock.uploads()
	assert_eq(ups.size(), 1)
	var u: Dictionary = ups[0]
	assert_true(bool(u["fit_valid"]), "the mock's FIT header and CRC check passed")
	assert_eq(u["data_type"], "fit")
	assert_eq(u["trainer"], "1")
	assert_eq(u["name"], "Wattlands: Workout")
	assert_eq(u["description"], "desc")
	assert_eq(u["external_id"], ride[1]["ride_id"], "external_id is the ride UUID")
	assert_eq(u["filename"], str(ride[0]).get_file())
	assert_eq(int(u["bytes"]), FileAccess.get_file_as_bytes(str(ride[0])).size())
	assert_eq(
		await _routes(),
		["authorize:302", "token:200", "upload:201", "upload_status:200", "upload_status:200"]
	)


func test_duplicate_counts_as_uploaded() -> void:
	var c: StravaClient = await _connected_client()
	var ride := _ride()
	var first: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	var second: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(first["state"], "uploaded")
	assert_eq(second["state"], "duplicate")
	assert_eq(int(second["activity_id"]), int(first["activity_id"]), "the existing activity's id")
	assert_eq(
		StravaClient.duplicate_activity_id("x.fit duplicate of activity 123456789"), 123456789
	)
	assert_eq(StravaClient.duplicate_activity_id("no number"), 0)


func test_a_corrupt_fit_fails_permanently() -> void:
	var c: StravaClient = await _connected_client()
	var ride := _ride()
	var bytes := FileAccess.get_file_as_bytes(str(ride[0]))
	bytes[bytes.size() - 1] ^= 0xFF
	var f := FileAccess.open(str(ride[0]), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "failed")
	assert_true(bool(res["permanent"]))
	assert_string_contains(str(res["detail"]), "Improperly formatted")


func test_missing_file_fails_permanently() -> void:
	var c: StravaClient = await _connected_client()
	var res: Dictionary = await c.upload_fit("x", _dir.path_join("nope.fit"), "n", "d")
	assert_eq(res["state"], "failed")
	assert_eq(res["detail"], "missing_file")
	assert_true(bool(res["permanent"]))


func test_processing_timeout_keeps_the_upload_id() -> void:
	var c: StravaClient = await _connected_client()
	c.poll_timeout_s = 0.1
	await _mock.config({"processing_polls": 1000})
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "failed")
	assert_eq(res["detail"], "processing_timeout")
	assert_gt(int(res["upload_id"]), 0, "kept, so a retry polls instead of uploading again")
	assert_false(bool(res["permanent"]))
	await _mock.config({"processing_polls": 0})
	var later: Dictionary = await c.poll_upload(str(ride[1]["ride_id"]), int(res["upload_id"]))
	assert_eq(later["state"], "uploaded")


func test_offline_upload() -> void:
	var c: StravaClient = await _connected_client()
	var probe := TCPServer.new()
	probe.listen(0, "127.0.0.1")
	var dead_port := probe.get_local_port()
	probe.stop()
	c.api_base = "http://127.0.0.1:%d/api/v3" % dead_port
	c.request_timeout_s = 1.5
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "offline")
	assert_false(bool(res["permanent"]))


func test_upload_when_not_connected_is_queued() -> void:
	var c := _client()
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "queued")
	assert_eq(res["detail"], "not_connected")


func test_server_error_is_retryable() -> void:
	var c: StravaClient = await _connected_client()
	await _mock.fault("upload", 500)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "failed")
	assert_eq(res["detail"], "server_error_500")
	assert_false(bool(res["permanent"]))


# --- Tokens --------------------------------------------------------------------------------


func test_refresh_rotates_and_keeps_the_newest_refresh_token() -> void:
	var c: StravaClient = await _connected_client()
	var first := _store()
	assert_true(await c.refresh_tokens())
	var second := _store()
	assert_ne(
		second["refresh_token"], first["refresh_token"], "Strava rotated it; we keep the new one"
	)
	assert_ne(second["access_token"], first["access_token"])
	assert_true(await c.refresh_tokens(), "the newest refresh token works")
	var third := _store()
	assert_ne(third["refresh_token"], second["refresh_token"])
	assert_eq(await _routes(), ["authorize:302", "token:200", "token:200", "token:200"])


func test_refresh_shortly_before_expiry() -> void:
	var c: StravaClient = await _connected_client()
	var before := _store()
	assert_true(await c.ensure_token(), "fresh token: no refresh")
	assert_eq(_store()["access_token"], before["access_token"])
	_now = NOW + 21600 - 60
	await _mock.set_clock(_now)
	assert_true(await c.ensure_token(), "a minute left: refreshed")
	var after := _store()
	assert_ne(after["access_token"], before["access_token"])
	assert_eq(int(after["expires_at"]), _now + 21600)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "uploaded", "the refreshed token works")


func test_expired_token_on_the_server_recovers_with_one_refresh() -> void:
	var c: StravaClient = await _connected_client()
	# The server's clock ran ahead of ours: the token looks fresh here, but the API says 401.
	await _mock.set_clock(NOW + 30000)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "uploaded")
	var routes: Array = await _routes()
	assert_eq(routes.slice(2, 5), ["upload:401", "token:200", "upload:201"])


func test_injected_401_refreshes_once_and_retries() -> void:
	var c: StravaClient = await _connected_client()
	await _mock.fault("upload", 401)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "uploaded")
	var routes: Array = await _routes()
	assert_eq(routes.slice(2, 5), ["upload:401", "token:200", "upload:201"])


func test_a_second_401_gives_up() -> void:
	var c: StravaClient = await _connected_client()
	await _mock.fault("upload", 401, 2)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "failed")
	assert_eq(res["detail"], "unauthorized")
	var routes: Array = await _routes()
	assert_eq(routes.count("token:200"), 2, "one refresh only (plus the connect)")


func test_a_revoked_grant_needs_a_reconnect() -> void:
	var c: StravaClient = await _connected_client()
	var store := _store()
	var basic := Marshalls.utf8_to_base64(
		"%s:%s" % [MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET]
	)
	var req := HTTPRequest.new()
	add_child_autofree(req)
	req.request(
		_mock.oauth_base() + "/revoke",
		["Authorization: Basic " + basic, "Content-Type: application/x-www-form-urlencoded"],
		HTTPClient.METHOD_POST,
		"token=" + str(store["refresh_token"])
	)
	await req.request_completed
	assert_false(await c.refresh_tokens())
	assert_push_warning("no longer valid")
	assert_eq(c.state(), "error")
	assert_false(c.has_tokens())
	assert_eq(
		_store()["client_secret"], MockRunner.CLIENT_SECRET, "credentials kept for the reconnect"
	)


func test_429_backs_off_and_retries() -> void:
	var c: StravaClient = await _connected_client()
	await _mock.fault("upload", 429, 2, 0)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "uploaded")
	var routes: Array = await _routes()
	assert_eq(routes.slice(2, 5), ["upload:429", "upload:429", "upload:201"])
	await _mock.fault("upload_status", 429, 1)
	var ride2 := _ride("other")
	var res2: Dictionary = await c.upload_fit(str(ride2[1]["ride_id"]), str(ride2[0]), "n", "d")
	assert_eq(res2["state"], "uploaded", "a 429 while polling backs off too")


func test_429_gives_up_after_the_retries() -> void:
	var c: StravaClient = await _connected_client()
	c.max_rate_retries = 2
	await _mock.fault("upload", 429, 5)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "failed")
	assert_eq(res["detail"], "rate_limited")
	assert_false(bool(res["permanent"]), "kept for a later retry")
	var routes: Array = await _routes()
	assert_eq(routes.count("upload:429"), 3, "first try plus two retries")


func test_tokens_go_only_in_the_authorization_header() -> void:
	var c: StravaClient = await _connected_client()
	var ride := _ride()
	await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	await c.fetch_athlete()
	for r: Dictionary in await _mock.requests():
		assert_false(bool(r["token_in_query"]), "no token in the URL: %s" % r["path"])
		if str(r["route"]) in ["upload", "upload_status", "athlete"]:
			assert_eq(r["auth"], "bearer", "%s uses the Authorization header" % r["route"])


# --- Disconnect ----------------------------------------------------------------------------


func test_disconnect_revokes_and_deletes() -> void:
	var c: StravaClient = await _connected_client()
	var states: Array = []
	c.state_changed.connect(func(s: String, d: String) -> void: states.append([s, d]))
	assert_true(await c.disconnect_account(), "revoke succeeded")
	assert_false(c.has_tokens())
	assert_eq(states, [["disconnected", ""]])
	var store := _store()
	assert_eq(
		store.get("client_id", ""), MockRunner.CLIENT_ID, "the client id stays for a reconnect"
	)
	assert_false(store.has("client_secret"), "the secret is deleted")
	assert_false(store.has("access_token") or store.has("refresh_token"), "the tokens are deleted")
	var revoke: Array = (await _mock.requests()).filter(
		func(r: Dictionary) -> bool: return r["route"] == "revoke"
	)
	assert_eq(revoke.size(), 1)
	assert_eq(revoke[0]["auth"], "basic", "HTTP Basic client id/secret")
	assert_eq(int(revoke[0]["status"]), 200)
	var st: Dictionary = await _mock.admin(HTTPClient.METHOD_GET, "/admin/state")
	assert_eq(int(st["active_grants"]), 0, "the grant is revoked on the server")


func test_disconnect_offline_still_deletes_locally() -> void:
	var c: StravaClient = await _connected_client()
	c.oauth_base = "http://127.0.0.1:1/oauth"
	c.request_timeout_s = 1.5
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	assert_false(await c.disconnect_account())
	assert_false(c.has_tokens())
	assert_eq(details, ["revoke_failed"])


# --- Secrets ----------------------------------------------------------------------------------


func test_secrets_never_reach_a_log() -> void:
	var cap := Util.LogCapture.new()
	OS.add_logger(cap)
	var c: StravaClient = await _connected_client()
	var store := _store()
	var ride := _ride()
	await _mock.fault("upload", 401)
	await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	await _mock.fault("upload", 429, 1, 0)
	await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	await c.refresh_tokens()
	var latest := _store()
	await c.disconnect_account()
	OS.remove_logger(cap)
	var text := cap.text()
	assert_string_contains(text, "Strava: connected", "the capture works")
	assert_string_contains(text, Locks.NET_MESSAGE)
	for secret: String in [
		MockRunner.CLIENT_SECRET,
		str(store["access_token"]),
		str(store["refresh_token"]),
		str(latest["access_token"]),
		str(latest["refresh_token"])
	]:
		assert_false(text.contains(secret), "a secret or token appeared in the log")


func test_an_expired_token_while_offline_is_offline_not_disconnected() -> void:
	var c: StravaClient = await _connected_client()
	c.oauth_base = "http://127.0.0.1:1/oauth"
	c.request_timeout_s = 1.5
	_now = NOW + 30000
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "offline", "the refresh couldn't reach Strava")
	assert_true(c.has_tokens(), "tokens kept for later")


func test_rejected_client_credentials_ask_for_a_reconnect() -> void:
	var c: StravaClient = await _connected_client()
	await _mock.fault("upload", 401)
	await _mock.fault("token", 401)
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "failed")
	assert_eq(res["detail"], "unauthorized")
	assert_push_warning("credentials were rejected")
	assert_eq(c.state(), "error")
	assert_true(c.has_tokens(), "a 401 from the token endpoint keeps the tokens")


func test_disconnect_falls_back_to_deauthorize() -> void:
	var c: StravaClient = await _connected_client()
	await _mock.fault("revoke", 404)
	assert_true(await c.disconnect_account(), "revoked through /oauth/deauthorize")
	var routes: Array = await _routes()
	assert_eq(routes.slice(2), ["revoke:404", "deauthorize:200"])
	var deauth: Array = (await _mock.requests()).filter(
		func(r: Dictionary) -> bool: return r["route"] == "deauthorize"
	)
	assert_eq(deauth[0]["auth"], "bearer", "the access token goes in the Authorization header")
	assert_false(bool(deauth[0]["token_in_query"]))
	var st: Dictionary = await _mock.admin(HTTPClient.METHOD_GET, "/admin/state")
	assert_eq(int(st["active_grants"]), 0)
