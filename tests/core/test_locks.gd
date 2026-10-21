extends GutTest
## Locks (BRIEF 1): the hardware and network locks read from the environment, URL host
## parsing, and the network lock's loopback-only rule (refusals warn, never error).

## Environment before each test: name -> value, for the variables that were set.
var _saved: Dictionary = {}


func before_each() -> void:
	_saved.clear()
	for k: String in [Locks.HW_ENV, Locks.NET_ENV]:
		if OS.has_environment(k):
			_saved[k] = OS.get_environment(k)


func after_each() -> void:
	for k: String in [Locks.HW_ENV, Locks.NET_ENV]:
		if _saved.has(k):
			OS.set_environment(k, str(_saved[k]))
		else:
			OS.unset_environment(k)


func test_hw_lock_follows_the_environment() -> void:
	OS.set_environment(Locks.HW_ENV, "1")
	assert_true(Locks.hw_locked())
	OS.set_environment(Locks.HW_ENV, "0")
	assert_false(Locks.hw_locked())
	OS.set_environment(Locks.HW_ENV, "yes")
	assert_false(Locks.hw_locked(), "only \"1\" locks")
	OS.unset_environment(Locks.HW_ENV)
	assert_false(Locks.hw_locked())


func test_network_lock_follows_the_environment() -> void:
	OS.set_environment(Locks.NET_ENV, "1")
	assert_true(Locks.network_locked())
	OS.set_environment(Locks.NET_ENV, "0")
	assert_false(Locks.network_locked())
	OS.unset_environment(Locks.NET_ENV)
	assert_false(Locks.network_locked())


func test_the_test_run_is_locked() -> void:
	# tools/godot.sh and tools/run_tests set both locks for every automated run (BRIEF 1).
	assert_true(Locks.hw_locked(), "WATTLANDS_NO_HW_CONTROL=1 in the test process")
	assert_true(Locks.network_locked(), "WATTLANDS_NO_NETWORK_INTEGRATIONS=1 in the test process")


func test_messages() -> void:
	assert_eq(Locks.HW_MESSAGE, "hardware control locked")
	assert_eq(Locks.NET_MESSAGE, "network integrations locked")


func test_url_host() -> void:
	var cases := {
		"http://example.com": "example.com",
		"https://Example.COM:8443/path?q=1": "example.com",
		"http://localhost": "localhost",
		"ws://localhost:8787/v1": "localhost",
		"wss://relay.example.org/v1": "relay.example.org",
		"http://127.0.0.1:9000/oauth/callback": "127.0.0.1",
		"http://user:pass@127.0.0.1:9000/x": "127.0.0.1",
		"https://user@www.strava.com/api/v3": "www.strava.com",
		"http://[::1]:8080/x": "::1",
		"https://[2001:DB8::1]/": "2001:db8::1",
		"ws://[::1]": "::1",
		"http://host?x=1": "host",
		"http://host:80?x=1": "host",
		"http://host#frag": "host",
		"localhost:3000/v1": "localhost",
		"  HTTP://LOCALHOST:8787  ": "localhost",
	}
	for url: String in cases.keys():
		assert_eq(Locks.url_host(url), cases[url], url)


func test_url_host_ignores_tricks_after_the_authority() -> void:
	assert_eq(Locks.url_host("http://evil.example#@localhost/"), "evil.example")
	assert_eq(Locks.url_host("http://evil.example?@localhost/"), "evil.example")
	assert_eq(Locks.url_host("http://evil.example/@localhost"), "evil.example")
	assert_eq(Locks.url_host("http://evil.example\\@localhost"), "evil.example")
	assert_eq(Locks.url_host("http://localhost.evil.example/"), "localhost.evil.example")


func test_is_loopback_host() -> void:
	assert_true(Locks.is_loopback_host("127.0.0.1"))
	assert_true(Locks.is_loopback_host("localhost"))
	assert_true(Locks.is_loopback_host("LocalHost"))
	assert_false(Locks.is_loopback_host("127.0.0.2"))
	assert_false(Locks.is_loopback_host("localhost.example"))
	assert_false(Locks.is_loopback_host("::1"), "only 127.0.0.1 and localhost")
	assert_false(Locks.is_loopback_host(""))


func test_network_allows_only_loopback_when_locked() -> void:
	OS.set_environment(Locks.NET_ENV, "1")
	assert_true(Locks.network_allows("http://127.0.0.1:8899/oauth/token"))
	assert_true(Locks.network_allows("http://localhost:8899/api/v3/uploads"))
	assert_true(Locks.network_allows("ws://localhost:8787/v1"))
	assert_push_warning_count(0)
	var refused := [
		"https://www.strava.com/api/v3/uploads",
		"https://www.strava.com/oauth/authorize",
		"http://localhost.evil.example/",
		"http://evil.example#@localhost/",
		"http://[::1]:8899/",
		"http://10.0.0.5/",
	]
	for url: String in refused:
		assert_false(Locks.network_allows(url), url)
		assert_push_warning("network integrations locked", url)


## W4 (RS-1): URLs whose authority two parsers read differently. url_host() (browser-style)
## sees 127.0.0.1 in the first two, but HTTPRequest's String::parse_url connects to the host
## after the "@". The lock refuses every URL whose authority holds "@", "?", "#", "\", "%" or
## whitespace, whatever url_host() says.
func test_network_lock_refuses_ambiguous_authorities() -> void:
	OS.set_environment(Locks.NET_ENV, "1")
	var refused := [
		"http://127.0.0.1?@evil.example:8899/api/v3/athlete",
		"http://127.0.0.1\\@evil.example:8899/api/v3/athlete",
		"http://localhost?@evil.example/",
		"http://127.0.0.1#@evil.example/",
		"http://user@127.0.0.1:8899/",
		"http://127.0.0.1@evil.example/",
		"http://127.0.0.1%2f@evil.example/",
		"http://127.0.0.1 @evil.example/",
		"http://127.0.0.1\t:8899/",
	]
	for url: String in refused:
		assert_true(Locks.authority_ambiguous(url), url)
		assert_false(Locks.is_loopback_url(url), url)
		assert_false(Locks.network_allows(url), url)
		assert_push_warning("network integrations locked", url)
	var allowed := [
		"http://127.0.0.1:8899/oauth/token?x=1&y=@2",
		"http://localhost:8899/api/v3/uploads#frag@x",
		"ws://127.0.0.1:8765",
		"http://127.0.0.1:8899/strava/callback?code=a@b\\c",
	]
	for url: String in allowed:
		assert_false(Locks.authority_ambiguous(url), url)
		assert_true(Locks.is_loopback_url(url), url)
		assert_true(Locks.network_allows(url), url)


## W4r2 (RS residual): url_host() and authority_ambiguous() take whatever precedes the first
## "://" as the scheme, but WebSocketPeer reads a scheme-less URL as ws://, so
## "127.0.0.2:8765/x://127.0.0.1" connected the trainer bridge to 127.0.0.2. A URL must start
## with http://, https://, ws:// or wss:// (any case), and "[" or "]" in the authority (an IPv6
## host, never loopback here) is ambiguous.
func test_loopback_needs_a_known_scheme_and_no_brackets() -> void:
	OS.set_environment(Locks.NET_ENV, "1")
	var refused := [
		"127.0.0.2:8765/x://127.0.0.1",
		"evil:8765/://127.0.0.1/",
		"127.0.0.1:8765/",
		"localhost:8899/api",
		"ftp://127.0.0.1/",
		"file://localhost/x",
		" http://127.0.0.1:8899/",
		"://127.0.0.1/",
		"http://[127.0.0.1]127.0.0.2:8899/",
		"http://[127.0.0.1]:8899]127.0.0.2/",
		"ws://[::1]:8765",
	]
	for url: String in refused:
		assert_false(Locks.is_loopback_url(url), url)
		assert_false(Locks.network_allows(url), url)
		assert_push_warning("network integrations locked", url)
	assert_eq(Locks.url_host("127.0.0.2:8765/x://127.0.0.1"), "127.0.0.1", "url_host() alone is fooled")
	assert_false(Locks.has_known_scheme("127.0.0.2:8765/x://127.0.0.1"))
	var allowed := [
		"http://127.0.0.1:8899/oauth/token",
		"HTTP://LOCALHOST:8899/api/v3",
		"https://localhost/",
		"ws://127.0.0.1:8765",
		"wss://localhost:8765/v1",
	]
	for url: String in allowed:
		assert_true(Locks.has_known_scheme(url), url)
		assert_true(Locks.is_loopback_url(url), url)
		assert_true(Locks.network_allows(url), url)


## The parser HTTPRequest uses, for the record: the cases above really do reach the host after
## the "@" (this is why url_host() alone can't be trusted with them).
func test_godot_parse_url_reads_the_host_after_the_at() -> void:
	var cases := {
		"http://127.0.0.1?@evil.example:8899/api": "evil.example",
		"http://127.0.0.1\\@evil.example:8899/api": "evil.example",
	}
	OS.set_environment(Locks.NET_ENV, "1")
	for url: String in cases.keys():
		assert_eq(str(_parse_like_http_request(url)["host"]), cases[url], url)
		assert_eq(Locks.url_host(url), "127.0.0.1", "url_host() alone is fooled: " + url)
		assert_false(Locks.network_allows(url), url)
		assert_push_warning("network integrations locked", url)


## String::parse_url as HTTPRequest applies it (scheme, then cut at "#", then at "/", then drop
## everything up to the first "@", then the port).
static func _parse_like_http_request(url: String) -> Dictionary:
	var base := url
	var pos := base.find("://")
	if pos != -1:
		base = base.substr(pos + 3)
	pos = base.find("#")
	if pos != -1:
		base = base.substr(0, pos)
	pos = base.find("/")
	if pos != -1:
		base = base.substr(0, pos)
	pos = base.find("@")
	if pos != -1:
		base = base.substr(pos + 1)
	pos = base.rfind(":")
	return {"host": base.substr(0, pos) if pos != -1 else base}


func test_network_allows_everything_when_unlocked() -> void:
	OS.unset_environment(Locks.NET_ENV)
	assert_true(Locks.network_allows("https://www.strava.com/api/v3/uploads"))
	assert_true(Locks.network_allows("http://127.0.0.1:8899/"))
	OS.set_environment(Locks.NET_ENV, "0")
	assert_true(Locks.network_allows("https://www.strava.com/oauth/token"))
	assert_push_warning_count(0)
	assert_push_error_count(0)
