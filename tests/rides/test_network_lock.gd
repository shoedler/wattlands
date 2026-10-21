extends GutTest
## The network lock (BRIEF 1, 7.5): while WATTLANDS_NO_NETWORK_INTEGRATIONS=1 no Strava
## request leaves loopback (each refusal logs "network integrations locked"), the browser
## is never opened, and redirects are checked hop by hop. Without the lock (a loopback mock
## only) Connect opens the browser instead.

const MockRunner := preload("res://tests/rides/mock_strava_runner.gd")
const Util := preload("res://tests/rides/rides_test_util.gd")
const NOW := 1_800_000_000
const REAL_API := "https://www.strava.com/api/v3"
const REAL_OAUTH := "https://www.strava.com/oauth"

var _mock: Node = null
var _mock_ok: bool = false
var _dir: String = ""
var _opened: Array = []
var _saved_env: Variant = null


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
	_saved_env = OS.get_environment(Locks.NET_ENV) if OS.has_environment(Locks.NET_ENV) else null
	assert_true(Locks.network_locked(), "the test run is network-locked")
	_dir = Paths.make_temp_dir("wattlands_netlock")
	Paths.set_override(_dir)
	_opened = []
	if _mock_ok:
		await _mock.reset()
		await _mock.set_clock(NOW)


func after_each() -> void:
	if _saved_env == null:
		OS.unset_environment(Locks.NET_ENV)
	else:
		OS.set_environment(Locks.NET_ENV, str(_saved_env))
	Paths.set_override("")
	Util.remove_tree(_dir)


func _client(api: String, oauth: String) -> StravaClient:
	var c := StravaClient.new()
	c.api_base = api
	c.oauth_base = oauth
	c.now_func = func() -> int: return NOW
	c.poll_interval_s = 0.02
	c.browser_opener = func(url: String) -> void: _opened.append(url)
	add_child_autofree(c)
	c.load_store()
	return c


## A client with tokens from the mock, then pointed elsewhere.
func _connected(api: String, oauth: String) -> StravaClient:
	var c := _client(_mock.api_base(), _mock.oauth_base())
	assert_true(await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET))
	c.api_base = api
	c.oauth_base = oauth
	return c


func _ride() -> Array:
	var rec := RideRecorder.new()
	rec.start("workout", "c", NOW, 0.0)
	rec.record(0.0, 100.0, 80.0, 25.0)
	rec.stop(5.0)
	return [rec.save(), rec.summary()]


func test_connect_to_a_real_host_is_refused_without_a_browser() -> void:
	var c := _client(REAL_API, REAL_OAUTH)
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	assert_false(await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET))
	assert_push_warning(Locks.NET_MESSAGE)
	assert_eq(_opened, [], "the browser is never opened while locked")
	assert_eq(details.back(), "network_locked")


func test_upload_to_a_real_host_is_refused() -> void:
	var c: StravaClient = await _connected(REAL_API, REAL_OAUTH)
	var before: int = (await _mock.requests()).size()
	var ride := _ride()
	var res: Dictionary = await c.upload_fit(str(ride[1]["ride_id"]), str(ride[0]), "n", "d")
	assert_eq(res["state"], "failed")
	assert_eq(res["detail"], "network_locked")
	assert_push_warning(Locks.NET_MESSAGE)
	assert_eq((await _mock.requests()).size(), before, "nothing was sent anywhere")


func test_refresh_and_revoke_to_a_real_host_are_refused() -> void:
	var c: StravaClient = await _connected(REAL_API, REAL_OAUTH)
	assert_false(await c.refresh_tokens())
	assert_push_warning(Locks.NET_MESSAGE)
	assert_false(await c.disconnect_account(), "revoke refused")
	assert_push_warning(Locks.NET_MESSAGE)
	assert_false(c.has_tokens(), "local tokens are deleted anyway")


func test_a_redirect_off_loopback_is_not_followed() -> void:
	await _mock.admin(HTTPClient.METHOD_POST, "/admin/fault",
		{"route": "authorize", "status": 302, "location": "https://www.strava.com/oauth/authorize?client_id=1"})
	var c := _client(_mock.api_base(), _mock.oauth_base())
	assert_false(await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET))
	assert_push_warning("refused www.strava.com")
	assert_eq(_opened, [])
	assert_false(c.has_tokens())


func test_every_request_passes_the_lock_check() -> void:
	# A non-loopback host is refused before any socket opens, for every request kind.
	var c := _client("http://192.0.2.1/api/v3", "http://192.0.2.1/oauth")
	var r: Dictionary = await c._request(HTTPClient.METHOD_GET, "http://192.0.2.1/api/v3/athlete", PackedStringArray(), PackedByteArray())
	assert_true(bool(r["refused"]))
	assert_push_warning(Locks.NET_MESSAGE)
	var r2: Dictionary = await c._request(HTTPClient.METHOD_GET, "http://example.com#@127.0.0.1/", PackedStringArray(), PackedByteArray())
	assert_true(bool(r2["refused"]), "userinfo tricks don't pass")
	assert_push_warning(Locks.NET_MESSAGE)


func test_without_the_lock_connect_opens_the_browser() -> void:
	# Only the loopback mock is involved; the "browser" is a stand-in that follows the URL.
	OS.unset_environment(Locks.NET_ENV)
	assert_false(Locks.network_locked())
	var c := _client(_mock.api_base(), _mock.oauth_base())
	c.browser_opener = func(url: String) -> void:
		_opened.append(url)
		var req := HTTPRequest.new()
		add_child_autofree(req)
		req.max_redirects = 4
		req.request(url)
	var ok: bool = await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	OS.set_environment(Locks.NET_ENV, "1")
	assert_true(ok)
	assert_eq(_opened.size(), 1, "the browser opened once")
	var url := str(_opened[0])
	assert_string_contains(url, "response_type=code")
	assert_string_contains(url, "approval_prompt=auto")
	assert_string_contains(url, "scope=activity%3Awrite")
	assert_string_contains(url, "redirect_uri=http%3A%2F%2F127.0.0.1%3A")
	assert_string_contains(url, "%2Fstrava%2Fcallback")
	assert_true(c.has_tokens())


func test_callback_server_binds_loopback_and_times_out() -> void:
	OS.unset_environment(Locks.NET_ENV)
	var c := _client(_mock.api_base(), _mock.oauth_base())
	c.callback_timeout_s = 0.2
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	var ok: bool = await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	OS.set_environment(Locks.NET_ENV, "1")
	assert_false(ok, "nobody came back to the callback")
	assert_eq(details.back(), "callback_timeout")
	assert_string_contains(str(_opened[0]), "127.0.0.1")
	var cb := StravaCallbackServer.new()
	add_child_autofree(cb)
	assert_true(cb.start())
	assert_string_contains(cb.redirect_uri(), "http://127.0.0.1:")
	assert_eq(StravaCallbackServer.parse_query("code=a%2Bb&state=x+y&e"), {"code": "a+b", "state": "x y", "e": ""})
	cb.stop()


## GET `url` straight from the test (loopback only): [result, code, body text]. Resumes on
## the next frame, outside the HTTPRequest's signal, so the request can be freed.
func _http_get(url: String, timeout_s: float = 5.0) -> Array:
	var req := HTTPRequest.new()
	req.timeout = timeout_s
	add_child(req)
	req.request(url)
	var res: Array = await req.request_completed
	req.queue_free()
	await get_tree().process_frame
	return [int(res[0]), int(res[1]), (res[3] as PackedByteArray).get_string_from_utf8()]


func test_callback_page_texts_come_from_the_strings_csv() -> void:
	assert_ne(TranslationServer.translate("RIDES_CALLBACK_CONNECTING"), &"RIDES_CALLBACK_CONNECTING", "the key is in rides.csv")
	assert_ne(TranslationServer.translate("RIDES_CALLBACK_DENIED"), &"RIDES_CALLBACK_DENIED", "the key is in rides.csv")
	var cb := StravaCallbackServer.new()
	add_child_autofree(cb)
	assert_true(cb.start())
	var other: Array = await _http_get("http://127.0.0.1:%d/favicon.ico" % cb.port)
	assert_eq(other[1], 404, "other paths: 404, the wait goes on")
	assert_false(cb.done)
	var denied: Array = await _http_get(cb.redirect_uri() + "?state=s&error=access_denied")
	assert_eq(denied[1], 200)
	assert_string_contains(str(denied[2]), String(TranslationServer.translate("RIDES_CALLBACK_DENIED")).format({"error": "access_denied"}))
	assert_true(cb.done)
	assert_eq(cb.params, {"state": "s", "error": "access_denied"})
	cb.start()
	var ok: Array = await _http_get(cb.redirect_uri() + "?state=s&code=c&scope=read,activity:write")
	assert_string_contains(str(ok[2]), String(TranslationServer.translate("RIDES_CALLBACK_CONNECTING")))
	assert_eq(cb.params["code"], "c")
	cb.stop()


func test_idle_connections_never_block_the_callback() -> void:
	var cb := StravaCallbackServer.new()
	add_child_autofree(cb)
	assert_true(cb.start())
	assert_eq(cb.idle_timeout_s, 10.0, "default")
	cb.idle_timeout_s = 60.0
	# A browser's speculative connections: open, then silent. They fill every slot.
	var idle: Array[StreamPeerTCP] = []
	for i in StravaCallbackServer.MAX_CONNECTIONS:
		var p := StreamPeerTCP.new()
		assert_eq(p.connect_to_host("127.0.0.1", cb.port), OK)
		idle.append(p)
	await wait_until(func() -> bool: return cb.open_connections() == StravaCallbackServer.MAX_CONNECTIONS, 5.0)
	assert_eq(cb.open_connections(), StravaCallbackServer.MAX_CONNECTIONS, "every slot is taken")
	cb.idle_timeout_s = 0.3
	var res: Array = await _http_get(cb.redirect_uri() + "?state=s&code=c", 5.0)
	assert_eq(res[0], HTTPRequest.RESULT_SUCCESS, "the real callback got through once the idle ones were dropped")
	assert_eq(res[1], 200)
	assert_true(cb.done)
	for p in idle:
		p.disconnect_from_host()
	cb.stop()


func test_two_connects_use_different_states() -> void:
	OS.unset_environment(Locks.NET_ENV)
	var urls: Array = []
	var c := _client(_mock.api_base(), _mock.oauth_base())
	c.callback_timeout_s = 0.05
	c.browser_opener = func(url: String) -> void: urls.append(url)
	await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	OS.set_environment(Locks.NET_ENV, "1")
	assert_eq(urls.size(), 2)
	var states: Array = []
	for u: String in urls:
		var q := StravaCallbackServer.parse_query(u.substr(u.find("?") + 1))
		states.append(str(q.get("state", "")))
		assert_eq(str(q.get("state", "")).length(), 32, "128 random bits")
	assert_ne(states[0], states[1], "a fresh random state per connect")


func test_connect_can_be_cancelled() -> void:
	OS.unset_environment(Locks.NET_ENV)
	var c := _client(_mock.api_base(), _mock.oauth_base())
	var details: Array = []
	c.state_changed.connect(func(_s: String, d: String) -> void: details.append(d))
	c.browser_opener = func(_url: String) -> void: c.cancel_connect.call_deferred()
	var ok: bool = await c.connect_account(MockRunner.CLIENT_ID, MockRunner.CLIENT_SECRET)
	OS.set_environment(Locks.NET_ENV, "1")
	assert_false(ok)
	assert_eq(details.back(), "cancelled")
	assert_false(c.is_connecting())
