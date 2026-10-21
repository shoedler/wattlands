class_name Locks
extends RefCounted
## The run's safety locks (BRIEF 1), read from the process environment. Tested in W0.
##   WATTLANDS_NO_HW_CONTROL=1: FtmsClient refuses Request Control and every control-point
##     write (scan, read and subscribe still work) and logs "hardware control locked".
##   WATTLANDS_NO_NETWORK_INTEGRATIONS=1: the Strava client refuses every host except
##     127.0.0.1 and localhost, never opens a browser, and logs "network integrations locked".
## The shipped game never sets either. The art lock lives in tools/art/generate.mjs alone.

const HW_ENV := "WATTLANDS_NO_HW_CONTROL"
const NET_ENV := "WATTLANDS_NO_NETWORK_INTEGRATIONS"
const HW_MESSAGE := "hardware control locked"
const NET_MESSAGE := "network integrations locked"


static func hw_locked() -> bool:
	return OS.get_environment(HW_ENV) == "1"


static func network_locked() -> bool:
	return OS.get_environment(NET_ENV) == "1"


## The host part of an http(s)/ws(s) URL, lower-case, without port or brackets.
## The authority ends at the first "/", "?", "#" or "\", so "http://a.com#@localhost"
## is a.com (not localhost).
static func url_host(url: String) -> String:
	var u := url.strip_edges()
	var scheme_end := u.find("://")
	if scheme_end >= 0:
		u = u.substr(scheme_end + 3)
	for delim: String in ["/", "?", "#", "\\"]:
		var cut := u.find(delim)
		if cut >= 0:
			u = u.substr(0, cut)
	var at := u.rfind("@")
	if at >= 0:
		u = u.substr(at + 1)
	if u.begins_with("["):
		var close := u.find("]")
		return u.substr(1, close - 1).to_lower() if close > 0 else u.to_lower()
	var colon := u.find(":")
	if colon >= 0:
		u = u.substr(0, colon)
	return u.to_lower()


static func is_loopback_host(host: String) -> bool:
	var h := host.to_lower()
	return h == "127.0.0.1" or h == "localhost"


## True if the network lock allows contacting `url` (always true when unlocked).
## Logs "network integrations locked" (push_warning) when it refuses.
static func network_allows(url: String) -> bool:
	if not network_locked():
		return true
	if is_loopback_host(url_host(url)):
		return true
	push_warning("%s: refused %s" % [NET_MESSAGE, url_host(url)])
	return false
