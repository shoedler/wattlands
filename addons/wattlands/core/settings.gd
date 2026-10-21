class_name WlSettings
extends Node
## Autoload `Settings`: the rider profile (profile.json) and app settings (settings.json)
## under Paths.user_dir() (BRIEF 3.2, 6). Owned by platform; public API frozen after W0.
## Strava credentials and tokens are NOT here (rides keeps them in strava.json).
##
## App setting keys and defaults:
##   relay_url default_relay_url(), strava_api_base "https://www.strava.com/api/v3",
##   strava_oauth_base "https://www.strava.com/oauth", scaling_mode "FAIR_FTP",
##   last_game "", last_content "", last_device {}, recent_rooms [], locale "en",
##   master_volume_db 0.0, fullscreen false.
## --relay=<url> and --strava-base=<url> override the stored values for this run.
##
## The default relay URL (W4fin, additive) is the project setting
## wattlands/net/default_relay_url when it holds a ws:// or wss:// URL with a host, else
## DEFAULTS.relay_url (ws://localhost:8787/v1). project.godot leaves it unset; a build sets it
## with an override.cfg next to the exe (tools/export_windows.mjs --relay-url=<url>), so a
## friend's copy reaches that relay and the friend types only the room code. Precedence:
## --relay=<url>, then a relay_url the rider chose, then the default. settings.json keeps
## relay_url (with relay_url_custom true) only while the rider's choice differs from the
## default; set_value("relay_url", "") or the default's own value follows the default again,
## and so does a saved "ws://localhost:8787/v1" without relay_url_custom (earlier builds wrote
## the default on every save). relay_url_custom itself can't be set. load_all prints
## "Settings: build default relay URL <url>" once per process when the default isn't built in.
##
## Loading: a missing file leaves the defaults (a normal first run). A corrupt file (bad
## JSON, not an object) gives the defaults with push_warning; a value of the wrong type or
## out of range is dropped or clamped, also with push_warning. Saving writes a temp file and
## renames it over the old one. Other modules may store their own keys (JSON values only);
## the keys above are type-checked and a wrong type is refused with push_error.
## --strava-base=<url> is the root of a Strava-like server: the API base becomes
## <url>/api/v3 and the OAuth base <url>/oauth (the real layout), for this run only.
## Overrides are never written to settings.json.
## Signals: changed(key) and EventBus.settings_changed(key) after set_value; changed("profile")
## and EventBus.profile_changed after save_profile; load_all emits changed(""),
## EventBus.profile_changed and EventBus.settings_changed("") ("" means every key).
## recent_rooms entries are {code (normalized, 6 chars), at (UTC unix seconds), role
## ("HOST" or "CLIENT")}, newest first, at most 8, one per code.

signal changed(key: String)

const MAX_RECENT_ROOMS := 8
const DEFAULTS: Dictionary = {
	"relay_url": "ws://localhost:8787/v1",
	"strava_api_base": "https://www.strava.com/api/v3",
	"strava_oauth_base": "https://www.strava.com/oauth",
	"scaling_mode": "FAIR_FTP",
	"last_game": "",
	"last_content": "",
	"last_device": {},
	"recent_rooms": [],
	"locale": "en",
	"master_volume_db": 0.0,
	"fullscreen": false,
}
## The project setting that holds this build's default relay URL (see above).
const DEFAULT_RELAY_SETTING := "wattlands/net/default_relay_url"
## settings.json marks a relay_url the rider chose with this key (true).
const RELAY_CUSTOM_KEY := "relay_url_custom"
const STRAVA_API_SUFFIX := "/api/v3"
const STRAVA_OAUTH_SUFFIX := "/oauth"
## Ranges a loaded profile.json is clamped into: key -> [min, max].
const PROFILE_RANGES: Dictionary = {
	"weight_kg": [20.0, 300.0],
	"ftp_w": [30.0, 2000.0],
	"cp_w": [30.0, 2000.0],
	"wprime_j": [1000.0, 100000.0],
	"preferred_cadence_rpm": [30.0, 160.0],
	"difficulty_pct": [0.0, 100.0],
	"haptic_intensity_pct": [0.0, 100.0],
	"grade_min_pct": [-10.0, 0.0],
	"grade_max_pct": [0.0, 16.0],
	"scan_interval_s": [0.5, 10.0],
}
const PROFILE_CHOICES: Dictionary = {
	"units": ["metric", "imperial"],
	"drivetrain": ["cassette", "single_speed"],
}

# The build default relay URL load_all printed last (it prints each one once per process).
static var _printed_relay_default: String = ""

var profile: RiderProfile = RiderProfile.new()
## Save settings.json after every set_value (on by default; tests may turn it off).
var autosave: bool = true
## The EventBus to notify; null means the `EventBus` autoload (if any).
var bus: WlEventBus = null

# The stored values; relay_url only while it is the rider's choice (else default_relay_url()).
var _values: Dictionary = {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = _defaults()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Load profile.json and settings.json (missing files leave defaults). Called at startup
## and whenever Paths' override changes (tests).
func load_all() -> void:
	profile = _load_profile()
	_values = _load_settings()
	var relay_default := default_relay_url()
	if relay_default != str(DEFAULTS["relay_url"]) and relay_default != _printed_relay_default:
		print("Settings: build default relay URL %s" % relay_default)
	_printed_relay_default = relay_default
	changed.emit("")
	var b := _bus()
	if b != null:
		b.profile_changed.emit()
		b.settings_changed.emit("")


## Write profile.json and announce the change. (W4r2) The profile is first clamped into
## PROFILE_RANGES (clamp_profile), so every write (the profile screen, the Strava import, the FTP
## test) keeps the ranges a loaded profile gets, and the rider stack set up from it never sees an
## FTP or a weight outside them.
func save_profile() -> bool:
	clamp_profile(profile)
	var ok := _write_json(Paths.profile_path(), profile.to_dict())
	changed.emit("profile")
	var b := _bus()
	if b != null:
		b.profile_changed.emit()
	return ok


func save_settings() -> bool:
	var data := _values.duplicate(true)
	if data.has("relay_url"):
		data[RELAY_CUSTOM_KEY] = true
	return _write_json(Paths.settings_path(), data)


## True once a profile was created (first run creates "Rider", FTP 200, unverified).
func has_profile() -> bool:
	return profile.created


## Replace the profile with a fresh default one named `display_name` (FTP 200, unverified),
## marked created, and save it. The first-run flow (BRIEF 3.5) calls create_profile("Rider").
func create_profile(display_name: String = "Rider") -> bool:
	var p := RiderProfile.new()
	p.display_name = display_name if display_name.strip_edges() != "" else "Rider"
	p.created = true
	profile = p
	return save_profile()


## The value for `key`: a command-line override if one applies, else the stored value
## (a copy), else `default` (for relay_url: default_relay_url()).
func get_value(key: String, default: Variant = null) -> Variant:
	var o := _override(key)
	if o != "":
		return o
	if _values.has(key):
		return _copy(_values[key])
	if key == "relay_url":
		return default_relay_url()
	return default


func set_value(key: String, value: Variant) -> void:
	if key == "":
		push_error("Settings: empty key")
		return
	if key == RELAY_CUSTOM_KEY:
		push_error("Settings: %s is kept by Settings itself; set relay_url instead" % key)
		return
	var checked := _check_value(key, value)
	if not checked["ok"]:
		return
	var clean: Variant = checked["value"]
	if key == "relay_url":
		clean = str(clean).strip_edges()
	if key == "relay_url" and (clean == "" or clean == default_relay_url()):
		# Blank or the default's own value: follow the default again.
		if not _values.has(key):
			return
		_values.erase(key)
	elif _values.has(key) and typeof(_values[key]) == typeof(clean) and _values[key] == clean:
		return
	else:
		_values[key] = clean
	if autosave:
		save_settings()
	changed.emit(key)
	var b := _bus()
	if b != null:
		b.settings_changed.emit(key)


## True when `key` comes from the command line for this run (never saved).
func is_overridden(key: String) -> bool:
	return _override(key) != ""


func relay_url() -> String:
	return str(get_value("relay_url"))


## This build's default relay URL (W4fin, additive): the project setting DEFAULT_RELAY_SETTING
## when it is a ws:// or wss:// URL with a host, else DEFAULTS.relay_url. It ignores --relay and
## the rider's choice; relay_url() applies those.
static func default_relay_url() -> String:
	return _project_relay_url(false)


func strava_api_base() -> String:
	return str(get_value("strava_api_base", DEFAULTS["strava_api_base"]))


func strava_oauth_base() -> String:
	return str(get_value("strava_oauth_base", DEFAULTS["strava_oauth_base"]))


## The lobby's default scaling mode (Wl.FAIR_FTP, Wl.WKG or Wl.RAW).
func scaling_mode() -> String:
	return str(get_value("scaling_mode", Wl.FAIR_FTP))


## Recent rooms, newest first: [{code, at, role}] (copies).
func recent_rooms() -> Array:
	return get_value("recent_rooms", []) as Array


## Remember a room this rider hosted or joined. `role` is Wl.HOST or Wl.CLIENT (any case);
## `at_unix` is the UTC stamp (default: now). The same code moves to the front.
func add_recent_room(code: String, role: String, at_unix: int = -1) -> void:
	var c := RoomCode.normalize(code)
	if c == "":
		push_error('Settings: not a room code: "%s"' % code)
		return
	var r := role.to_upper()
	if r != Wl.HOST and r != Wl.CLIENT:
		push_error('Settings: room role must be HOST or CLIENT, got "%s"' % role)
		return
	var at := at_unix if at_unix >= 0 else int(Time.get_unix_time_from_system())
	var rooms: Array = [{"code": c, "at": at, "role": r}]
	for e: Variant in recent_rooms():
		if rooms.size() >= MAX_RECENT_ROOMS:
			break
		if e is Dictionary and str((e as Dictionary).get("code", "")) != c:
			rooms.append(e)
	set_value("recent_rooms", rooms)


## The last game and content played (zero-touch start, BRIEF 3.5); one save.
func set_last_game(game_id: String, content_id: String) -> void:
	var was_autosave := autosave
	autosave = false
	set_value("last_game", game_id)
	set_value("last_content", content_id)
	autosave = was_autosave
	if autosave:
		save_settings()


## The last trainer ({address, name, ...}, as FtmsConnectionManager.last_device()). Values
## JSON can't hold as themselves (packed arrays, vectors) are stored as JSON writes them.
func set_last_device(info: Dictionary) -> void:
	var clean: Variant = JSON.parse_string(JSON.stringify(info))
	set_value("last_device", clean if clean is Dictionary else {})


# --- loading -------------------------------------------------------------------------


func _load_profile() -> RiderProfile:
	var r := _read_json(Paths.profile_path())
	if r["missing"]:
		return RiderProfile.new()
	if not (r["data"] is Dictionary):
		push_warning(
			(
				"Settings: %s is corrupt (%s); using the default profile"
				% [Paths.profile_path(), r["why"]]
			)
		)
		return RiderProfile.new()
	return RiderProfile.from_dict(_clean_profile(r["data"] as Dictionary))


func _load_settings() -> Dictionary:
	var out := _defaults()
	var relay_default := _project_relay_url(true)
	var r := _read_json(Paths.settings_path())
	if r["missing"]:
		return out
	if not (r["data"] is Dictionary):
		push_warning(
			"Settings: %s is corrupt (%s); using the defaults" % [Paths.settings_path(), r["why"]]
		)
		return out
	var d: Dictionary = r["data"]
	for key: Variant in d.keys():
		var k := str(key)
		var v: Variant = d[key]
		if k == RELAY_CUSTOM_KEY:
			continue
		if DEFAULTS.has(k):
			if not _same_kind(v, DEFAULTS[k]):
				push_warning("Settings: ignoring %s of the wrong type in settings.json" % k)
				continue
			if k == "relay_url":
				var u := str(v).strip_edges()
				var marked: bool = d.get(RELAY_CUSTOM_KEY) == true
				var legacy: bool = u == str(DEFAULTS["relay_url"]) and not marked
				if u == "" or u == relay_default or legacy:
					continue
				v = u
			elif k == "recent_rooms":
				v = _clean_rooms(v as Array)
			elif k == "scaling_mode" and not Wl.SCALING_MODES.has(str(v)):
				push_warning('Settings: unknown scaling_mode "%s" in settings.json' % str(v))
				continue
			elif DEFAULTS[k] is float:
				v = float(v)
		out[k] = v
	return out


## {missing: bool, data: Variant (null when unreadable), why: String}.
static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"missing": true, "data": null, "why": ""}
	var text := FileAccess.get_file_as_string(path)
	if text == "" and FileAccess.get_open_error() != OK:
		return {"missing": false, "data": null, "why": "unreadable"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {
			"missing": false,
			"data": null,
			"why": "line %d: %s" % [json.get_error_line(), json.get_error_message()]
		}
	return {"missing": false, "data": json.data, "why": "not a JSON object"}


## Clamp `p`'s ranged numbers into PROFILE_RANGES in place (W4r2, additive), as loading does: a
## value out of range takes the nearest bound and a NaN or infinite one the default, each with
## push_warning. Returns the keys it changed.
static func clamp_profile(p: RiderProfile) -> PackedStringArray:
	var changed_keys := PackedStringArray()
	if p == null:
		return changed_keys
	var defaults := RiderProfile.new()
	for k: String in PROFILE_RANGES.keys():
		var lim: Array = PROFILE_RANGES[k]
		var f := float(p.get(k))
		var c := f
		if is_nan(f) or is_inf(f):
			c = float(defaults.get(k))
		else:
			c = clampf(f, float(lim[0]), float(lim[1]))
		if c != f:
			push_warning("Settings: profile %s %s out of range, using %s" % [k, str(f), str(c)])
			p.set(k, c)
			changed_keys.append(k)
	return changed_keys


## Keeps the profile keys whose type matches the default and clamps numbers into range.
static func _clean_profile(d: Dictionary) -> Dictionary:
	var template := RiderProfile.new().to_dict()
	var out: Dictionary = {}
	for key: Variant in d.keys():
		var k := str(key)
		if not template.has(k):
			continue
		var v: Variant = d[key]
		if not _same_kind(v, template[k]):
			push_warning("Settings: ignoring profile %s of the wrong type" % k)
			continue
		if PROFILE_RANGES.has(k):
			var lim: Array = PROFILE_RANGES[k]
			var f := float(v)
			if is_nan(f) or is_inf(f):
				push_warning("Settings: ignoring profile %s %s" % [k, str(v)])
				continue
			var c := clampf(f, float(lim[0]), float(lim[1]))
			if c != f:
				push_warning("Settings: profile %s %s out of range, using %s" % [k, str(v), str(c)])
			v = c
		if PROFILE_CHOICES.has(k) and not (PROFILE_CHOICES[k] as Array).has(str(v)):
			push_warning('Settings: unknown profile %s "%s"' % [k, str(v)])
			continue
		out[k] = v
	var gmin := float(out.get("grade_min_pct", template["grade_min_pct"]))
	var gmax := float(out.get("grade_max_pct", template["grade_max_pct"]))
	if gmin > gmax:
		push_warning("Settings: profile grade range is inverted; using the defaults")
		out.erase("grade_min_pct")
		out.erase("grade_max_pct")
	return out


static func _clean_rooms(rooms: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for e: Variant in rooms:
		if out.size() >= MAX_RECENT_ROOMS:
			break
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var c := RoomCode.normalize(str(d.get("code", "")))
		var r := str(d.get("role", "")).to_upper()
		if c == "" or seen.has(c) or (r != Wl.HOST and r != Wl.CLIENT):
			continue
		var at: Variant = d.get("at", 0)
		seen[c] = true
		out.append({"code": c, "at": int(at) if (at is float or at is int) else 0, "role": r})
	return out


## DEFAULTS without relay_url (stored only while it is the rider's choice).
static func _defaults() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	out.erase("relay_url")
	return out


## The project setting DEFAULT_RELAY_SETTING when it is a usable relay URL, else
## DEFAULTS.relay_url; with `warn`, a set but unusable value gets push_warning.
static func _project_relay_url(warn: bool) -> String:
	var built_in := str(DEFAULTS["relay_url"])
	var v: Variant = ProjectSettings.get_setting(DEFAULT_RELAY_SETTING, built_in)
	var is_text := v is String or v is StringName
	var u := str(v).strip_edges() if is_text else ""
	if is_text and u == "":
		return built_in
	if not _is_relay_url(u):
		if warn:
			push_warning(
				(
					'Settings: ignoring %s "%s" (not a ws:// or wss:// URL with a host); using %s'
					% [DEFAULT_RELAY_SETTING, str(v), built_in]
				)
			)
		return built_in
	return u


## True for a ws:// or wss:// URL with a host and no spaces, control characters, quotes or
## backslashes.
static func _is_relay_url(u: String) -> bool:
	var rest := ""
	if u.begins_with("ws://"):
		rest = u.substr(5)
	elif u.begins_with("wss://"):
		rest = u.substr(6)
	else:
		return false
	for i in u.length():
		var c := u.unicode_at(i)
		if c <= 32 or c == 127 or c == 34 or c == 92:
			return false
	var authority := rest.get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	var host := authority.get_slice("@", authority.get_slice_count("@") - 1)
	if host.begins_with("["):
		return host.find("]") > 1
	return host.get_slice(":", 0) != ""


# --- saving and checks -------------------------------------------------------------------


## {ok: bool, value: the checked (normalized) value}; push_error when refused.
static func _check_value(key: String, value: Variant) -> Dictionary:
	if not _is_json_value(value):
		push_error(
			(
				"Settings: %s must be a JSON value (null, bool, number, string, array or dictionary of those)"
				% key
			)
		)
		return {"ok": false, "value": null}
	if not DEFAULTS.has(key):
		return {"ok": true, "value": _copy(value)}
	if not _same_kind(value, DEFAULTS[key]):
		push_error(
			(
				"Settings: %s must be a %s, got %s"
				% [key, type_string(typeof(DEFAULTS[key])), type_string(typeof(value))]
			)
		)
		return {"ok": false, "value": null}
	match key:
		"scaling_mode":
			if not Wl.SCALING_MODES.has(str(value)):
				push_error('Settings: unknown scaling_mode "%s"' % str(value))
				return {"ok": false, "value": null}
		"recent_rooms":
			return {"ok": true, "value": _clean_rooms(value as Array)}
	if DEFAULTS[key] is float:
		return {"ok": true, "value": float(value)}
	return {"ok": true, "value": _copy(value)}


## True for values that survive JSON.stringify and JSON.parse_string as themselves (numbers
## come back as floats): null, bool, int, float, String, StringName, and arrays and
## string-keyed dictionaries of those.
static func _is_json_value(v: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_INT:
			return true
		TYPE_FLOAT:
			var f: float = v
			return not is_nan(f) and not is_inf(f)
		TYPE_ARRAY:
			for e: Variant in v as Array:
				if not _is_json_value(e, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k: Variant in d.keys():
				if not (k is String or k is StringName) or not _is_json_value(d[k], depth + 1):
					return false
			return true
	return false


static func _copy(v: Variant) -> Variant:
	if v is Array:
		return (v as Array).duplicate(true)
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return v


static func _same_kind(a: Variant, b: Variant) -> bool:
	var na := a is int or a is float
	var nb := b is int or b is float
	if na or nb:
		return na and nb
	return typeof(a) == typeof(b)


## The run-only override for `key` ("" when none): --relay and --strava-base.
static func _override(key: String) -> String:
	match key:
		"relay_url":
			return _flag("relay")
		"strava_api_base", "strava_oauth_base":
			var base := _flag("strava-base")
			if base == "":
				return ""
			base = base.trim_suffix("/").trim_suffix(STRAVA_API_SUFFIX).trim_suffix(
				STRAVA_OAUTH_SUFFIX
			)
			return base + (STRAVA_API_SUFFIX if key == "strava_api_base" else STRAVA_OAUTH_SUFFIX)
	return ""


static func _flag(flag_name: String) -> String:
	var v := CmdLine.get_str(flag_name, "").strip_edges()
	return "" if v == "true" else v


static func _write_json(path: String, data: Variant) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning(
			"Settings: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(path)
		if DirAccess.rename_absolute(tmp, path) != OK:
			push_warning("Settings: can't replace %s" % path)
			DirAccess.remove_absolute(tmp)
			return false
	return true


func _bus() -> WlEventBus:
	return bus if bus != null else AutoloadLookup.bus()
