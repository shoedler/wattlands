class_name AppScriptedConfig
extends RefCounted
## Command-line flags of a scripted peer (docs/ARCHITECTURE.md "Scripted peers (end-to-end test
## contract)"). The app runs as a scripted peer when started with --host or --join=<code>:
##   --host | --join=<code>
##   --game=<id> --content=<id> (host; default the game's e2e_content with --e2e, else
##     default_content) --e2e
##   --wait-peers=<n> (host: start once n human peers including itself are in the lobby and ready)
##   --relay=<ws url> --mock-trainer=<profile> --autopilot --profile-dir=<abs dir> --seed=<n>
##   --sim-speed=<x> --report=<path> --run-seconds=<n> (hard stop, platform seconds)
##   --strava-base=<url> --strava-client-id=<id> --strava-client-secret=<secret>
##   --strava-auto-upload
## The secret is kept for Rides.strava_connect only: describe() and every report leave it out.

var enabled: bool = false
## Wl.HOST or Wl.CLIENT.
var role: String = ""
var join_code: String = ""
var game_id: String = ""
var content_id: String = ""
var e2e: bool = false
var wait_peers: int = 1
var relay: String = ""
var mock_trainer: String = ""
var autopilot: bool = false
var profile_dir: String = ""
var has_seed: bool = false
var seed: int = 0
var sim_speed: float = 1.0
var report_path: String = ""
var run_seconds: float = 0.0
var strava_base: String = ""
var strava_client_id: String = ""
var strava_client_secret: String = ""
var strava_auto_upload: bool = false
## Problems with the flags; a scripted peer with errors quits non-zero at once.
var errors: Array[String] = []


static func from_args(args: PackedStringArray) -> AppScriptedConfig:
	return from_parsed(CmdLine.parse(args))


## From CmdLine.parse() output ({key: [values]}).
static func from_parsed(parsed: Dictionary) -> AppScriptedConfig:
	var c := AppScriptedConfig.new()
	var is_host := parsed.has("host") and _bool(_last(parsed, "host"))
	var is_join := parsed.has("join")
	c.enabled = is_host or is_join
	if not c.enabled:
		return c
	if is_host and is_join:
		c.errors.append("--host and --join are exclusive")
	c.role = Wl.HOST if is_host else Wl.CLIENT
	if is_join:
		var raw := _last(parsed, "join")
		c.join_code = RoomCode.normalize(raw)
		if c.join_code == "":
			c.errors.append("--join: invalid room code")
	c.game_id = _last(parsed, "game")
	c.content_id = _last(parsed, "content")
	c.e2e = parsed.has("e2e") and _bool(_last(parsed, "e2e"))
	if c.role == Wl.HOST and c.game_id == "":
		c.errors.append("--game is required with --host")
	if parsed.has("wait-peers"):
		var w := _last(parsed, "wait-peers")
		if w.is_valid_int() and int(w) >= 1 and int(w) <= Wl.MAX_SLOTS:
			c.wait_peers = int(w)
		else:
			c.errors.append("--wait-peers must be 1..%d" % Wl.MAX_SLOTS)
	c.relay = _last(parsed, "relay")
	c.mock_trainer = _last(parsed, "mock-trainer")
	c.autopilot = parsed.has("autopilot") and _bool(_last(parsed, "autopilot"))
	c.profile_dir = _last(parsed, "profile-dir")
	if parsed.has("seed"):
		var s := _last(parsed, "seed")
		if s.is_valid_int():
			c.has_seed = true
			c.seed = int(s)
		else:
			c.errors.append("--seed must be an integer")
	if parsed.has("sim-speed"):
		var sp := _last(parsed, "sim-speed")
		if sp.is_valid_float() and float(sp) > 0.0:
			c.sim_speed = float(sp)
		else:
			c.errors.append("--sim-speed must be > 0")
	c.report_path = _last(parsed, "report")
	if parsed.has("run-seconds"):
		var rs := _last(parsed, "run-seconds")
		if rs.is_valid_float() and float(rs) >= 0.0:
			c.run_seconds = float(rs)
		else:
			c.errors.append("--run-seconds must be >= 0")
	c.strava_base = _last(parsed, "strava-base")
	c.strava_client_id = _last(parsed, "strava-client-id")
	c.strava_client_secret = _last(parsed, "strava-client-secret")
	c.strava_auto_upload = parsed.has("strava-auto-upload") and _bool(_last(parsed, "strava-auto-upload"))
	if (c.strava_client_id == "") != (c.strava_client_secret == ""):
		c.errors.append("--strava-client-id and --strava-client-secret go together")
	# is_loopback_url, not url_host: an ambiguous authority ("http://127.0.0.1?@other/") reaches
	# `other` through HTTPRequest, so it is refused here up front too (W4 RS-1, W4r2 R22).
	if c.strava_base != "" and Locks.network_locked() and not Locks.is_loopback_url(c.strava_base):
		c.errors.append("--strava-base: %s (only loopback bases)" % Locks.NET_MESSAGE)
	return c


func is_valid() -> bool:
	return enabled and errors.is_empty()


## True when Strava should be connected at start.
func wants_strava_connect() -> bool:
	return strava_client_id != "" and strava_client_secret != ""


## The flags without the secret (for logs and the report).
func describe() -> Dictionary:
	return {
		"role": role, "join": join_code, "game": game_id, "content": content_id, "e2e": e2e,
		"wait_peers": wait_peers, "relay": relay, "mock_trainer": mock_trainer,
		"autopilot": autopilot, "seed": seed if has_seed else null, "sim_speed": sim_speed,
		"report": report_path, "run_seconds": run_seconds, "strava_base": strava_base,
		"strava_connect": wants_strava_connect(), "strava_auto_upload": strava_auto_upload,
	}


static func _last(parsed: Dictionary, key: String) -> String:
	var vals: Variant = parsed.get(key, [])
	if vals is Array and not (vals as Array).is_empty():
		return str((vals as Array)[(vals as Array).size() - 1])
	return ""


static func _bool(s: String) -> bool:
	var v := s.to_lower()
	return not (v == "false" or v == "0" or v == "no" or v == "off")
