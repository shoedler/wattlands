class_name Locks
extends RefCounted
## The run's safety locks (BRIEF 1), read from the process environment. Tested in W0.
##   WATTLANDS_NO_HW_CONTROL=1: FtmsClient refuses Request Control and every control-point
##     write (scan, read and subscribe still work) and logs "hardware control locked".
##   WATTLANDS_NO_NETWORK_INTEGRATIONS=1: the Strava client refuses every host except
##     127.0.0.1 and localhost, never opens a browser, and logs "network integrations locked".
##     (W4) A URL whose authority holds "@", "?", "#", "\", "%" or whitespace is refused too,
##     since HTTPRequest and url_host() could read a different host from it.
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


## True when the URL's authority (after "scheme://", up to the first "/") holds a character
## that URL parsers read differently (W4, RS-1): "@" (user info), "?", "#", a backslash, "%" or
## whitespace and control characters. url_host() ends the authority at "?", "#" or a backslash like a
## browser, but Godot's HTTPRequest (String::parse_url) cuts only at "#" and "/" and then
## drops everything up to the first "@", so "http://127.0.0.1?@other/" reaches `other`.
static func authority_ambiguous(url: String) -> bool:
	var u := url.strip_edges()
	var scheme_end := u.find("://")
	if scheme_end >= 0:
		u = u.substr(scheme_end + 3)
	var slash := u.find("/")
	if slash >= 0:
		u = u.substr(0, slash)
	for i in u.length():
		var c := u.unicode_at(i)
		if c <= 32 or c == 127 or c == 64 or c == 63 or c == 35 or c == 92 or c == 37:
			return true
	return false


## True when `url` is unambiguously on 127.0.0.1 or localhost: its host is loopback and its
## authority has nothing two URL parsers could read differently (authority_ambiguous). The
## network lock and the trainer bridge's loopback rule use it (W4, RS-1).
static func is_loopback_url(url: String) -> bool:
	return not authority_ambiguous(url) and is_loopback_host(url_host(url))


## True if the network lock allows contacting `url` (always true when unlocked). While locked
## only an unambiguous loopback URL passes (is_loopback_url).
## Logs "network integrations locked" (push_warning) when it refuses.
static func network_allows(url: String) -> bool:
	if not network_locked():
		return true
	if is_loopback_url(url):
		return true
	push_warning("%s: refused %s" % [NET_MESSAGE, url_host(url)])
	return false
