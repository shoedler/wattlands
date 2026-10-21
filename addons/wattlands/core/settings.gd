class_name WlSettings
extends Node
## Autoload `Settings`: the rider profile (profile.json) and app settings (settings.json)
## under Paths.user_dir() (BRIEF 3.2, 6). Owned by platform; public API frozen after W0.
## Strava credentials and tokens are NOT here (rides keeps them in strava.json).
##
## App setting keys and defaults:
##   relay_url "ws://localhost:8787/v1", strava_api_base "https://www.strava.com/api/v3",
##   strava_oauth_base "https://www.strava.com/oauth", scaling_mode "FAIR_FTP",
##   last_game "", last_content "", last_device {}, recent_rooms [], locale "en",
##   master_volume_db 0.0, fullscreen false.
## --relay=<url> and --strava-base=<url> override the stored values for this run.
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

var profile: RiderProfile = RiderProfile.new()
## Save settings.json after every set_value (on by default; tests may turn it off).
var autosave: bool = true
## The EventBus to notify; null means the `EventBus` autoload (if any).
var bus: WlEventBus = null

var _values: Dictionary = {}


func _init() -> void:
	_values = DEFAULTS.duplicate(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Load profile.json and settings.json (missing files leave defaults). Called at startup
## and whenever Paths' override changes (tests).
func load_all() -> void:
	profile = _load_profile()
	_values = _load_settings()
	changed.emit("")
	var b := _bus()
	if b != null:
		b.profile_changed.emit()
		b.settings_changed.emit("")


func save_profile() -> bool:
	var ok := _write_json(Paths.profile_path(), profile.to_dict())
	changed.emit("profile")
	var b := _bus()
	if b != null:
		b.profile_changed.emit()
	return ok


func save_settings() -> bool:
	return _write_json(Paths.settings_path(), _values)


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
## (a copy), else `default`.
func get_value(key: String, default: Variant = null) -> Variant:
	var o := _override(key)
	if o != "":
		return o
	if _values.has(key):
		return _copy(_values[key])
	return default


func set_value(key: String, value: Variant) -> void:
	if key == "":
		push_error("Settings: empty key")
		return
	var checked := _check_value(key, value)
	if not checked["ok"]:
		return
	var clean: Variant = checked["value"]
	if _values.has(key) and typeof(_values[key]) == typeof(clean) and _values[key] == clean:
		return
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
	return str(get_value("relay_url", DEFAULTS["relay_url"]))


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
		push_error("Settings: not a room code: \"%s\"" % code)
		return
	var r := role.to_upper()
	if r != Wl.HOST and r != Wl.CLIENT:
		push_error("Settings: room role must be HOST or CLIENT, got \"%s\"" % role)
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


## The last trainer ({address, name, ...}, as FtmsConnectionManager.last_device()).
func set_last_device(info: Dictionary) -> void:
	set_value("last_device", info)


# --- loading -------------------------------------------------------------------------


func _load_profile() -> RiderProfile:
	var r := _read_json(Paths.profile_path())
	if r["missing"]:
		return RiderProfile.new()
	if not (r["data"] is Dictionary):
		push_warning("Settings: %s is corrupt (%s); using the default profile" % [Paths.profile_path(), r["why"]])
		return RiderProfile.new()
	return RiderProfile.from_dict(_clean_profile(r["data"] as Dictionary))


func _load_settings() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var r := _read_json(Paths.settings_path())
	if r["missing"]:
		return out
	if not (r["data"] is Dictionary):
		push_warning("Settings: %s is corrupt (%s); using the defaults" % [Paths.settings_path(), r["why"]])
		return out
	var d: Dictionary = r["data"]
	for key: Variant in d.keys():
		var k := str(key)
		var v: Variant = d[key]
		if DEFAULTS.has(k):
			if not _same_kind(v, DEFAULTS[k]):
				push_warning("Settings: ignoring %s of the wrong type in settings.json" % k)
				continue
			if k == "recent_rooms":
				v = _clean_rooms(v as Array)
			elif k == "scaling_mode" and not Wl.SCALING_MODES.has(str(v)):
				push_warning("Settings: unknown scaling_mode \"%s\" in settings.json" % str(v))
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
		return {"missing": false, "data": null,
			"why": "line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	return {"missing": false, "data": json.data, "why": "not a JSON object"}


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
			push_warning("Settings: unknown profile %s \"%s\"" % [k, str(v)])
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


# --- saving and checks -------------------------------------------------------------------


## {ok: bool, value: the checked (normalized) value}; push_error when refused.
static func _check_value(key: String, value: Variant) -> Dictionary:
	if value is Object or value is Callable or value is Signal:
		push_error("Settings: %s must be a JSON value" % key)
		return {"ok": false, "value": null}
	if not DEFAULTS.has(key):
		return {"ok": true, "value": _copy(value)}
	if not _same_kind(value, DEFAULTS[key]):
		push_error("Settings: %s must be a %s, got %s" % [key, type_string(typeof(DEFAULTS[key])), type_string(typeof(value))])
		return {"ok": false, "value": null}
	match key:
		"scaling_mode":
			if not Wl.SCALING_MODES.has(str(value)):
				push_error("Settings: unknown scaling_mode \"%s\"" % str(value))
				return {"ok": false, "value": null}
		"recent_rooms":
			return {"ok": true, "value": _clean_rooms(value as Array)}
	if DEFAULTS[key] is float:
		return {"ok": true, "value": float(value)}
	return {"ok": true, "value": _copy(value)}


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
			base = base.trim_suffix("/").trim_suffix(STRAVA_API_SUFFIX).trim_suffix(STRAVA_OAUTH_SUFFIX)
			return base + (STRAVA_API_SUFFIX if key == "strava_api_base" else STRAVA_OAUTH_SUFFIX)
	return ""


static func _flag(flag_name: String) -> String:
	var v := CmdLine.get_str(flag_name, "").strip_edges()
	return "" if v == "true" else v


static func _write_json(path: String, data: Variant) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Settings: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
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
