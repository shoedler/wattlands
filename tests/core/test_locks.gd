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


func test_network_allows_everything_when_unlocked() -> void:
	OS.unset_environment(Locks.NET_ENV)
	assert_true(Locks.network_allows("https://www.strava.com/api/v3/uploads"))
	assert_true(Locks.network_allows("http://127.0.0.1:8899/"))
	OS.set_environment(Locks.NET_ENV, "0")
	assert_true(Locks.network_allows("https://www.strava.com/oauth/token"))
	assert_push_warning_count(0)
	assert_push_error_count(0)
