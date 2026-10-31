class_name QaScreenshotOptions
extends RefCounted
## The flags of tools/screenshot as tools/qa/screenshot_main.gd sees them (BRIEF 3.6, 7.8).
## Owned by qa. Pure: unit-tested in tests/scenarios/unit/test_screenshot_options.gd.
##
## One mode per run:
##   --game=<id> --at=<s>[,<s>...]   a GameSimRunner session (windowed, view and HUD built) with
##                                   run_game_sim's flags (--content, --players, --bots, --rider,
##                                   --autopilot, --seed, --ftp, --unverified, --haptics-off,
##                                   --options, --player-options, --override, --max-sim-seconds),
##                                   captured from the host's view at each sim second
##   --scene=<res path>              a scene (for example a kit demo) after --frames frames
##   --app-screen=title|picker|lobby the app shell on that screen with a mock trainer
##   --app-screen=session            the app's session screen (HUD, overlay) with
##                                   --app-role=client|host|solo (default client: the app joins
##                                   an in-process host over loopback; tools/qa/screenshot_session.gd),
##                                   shot at each --at (platform seconds of the app's session,
##                                   default 30) plus one with --app-overlay=menu|panic|discard|none
##                                   (default menu)
##   --app-screen=results            the app's results screen with a Workout-like GameResults for
##                                   --app-riders=<1..8> riders (default 1; tools/qa/screenshot_results.gd)
## Screenshot flags: --out=<dir> (alias --screenshot-dir), --frames=<n> (scene and app modes,
## default 30), --settle=<s> (game mode: render this long at normal speed before each shot,
## default 1), --app-game=<id> (lobby and session, default workout), --app-role and
## --app-overlay (session), --app-riders (results), --mock-trainer=<profile> (app mode).
## Every other flag goes to GameSimRunner.parse_args unchanged.

const APP_SCREENS: Array[String] = ["title", "picker", "lobby", "session", "results"]
const APP_ROLES: Array[String] = ["client", "host", "solo"]
const APP_OVERLAYS: Array[String] = ["menu", "panic", "discard", "none"]
## Session shots without --at: this many platform seconds into the app's session.
const DEFAULT_SESSION_AT := 30.0
## Results shots: 1 to this many riders (a full Workout room).
const MAX_RESULTS_RIDERS := 8
const DEFAULT_FRAMES := 30
const DEFAULT_SETTLE_S := 1.0
const DEFAULT_MOCK := "erg:compliance=1.0"
const SCREENSHOT_ROOT := "build/screenshots"
## Flags this tool consumes; they never reach GameSimRunner.parse_args.
const OWN_FLAGS: Array[String] = [
	"at",
	"out",
	"screenshot-dir",
	"scene",
	"frames",
	"app-screen",
	"app-game",
	"settle",
	"mock-trainer",
	"profile-dir",
	"app-role",
	"app-overlay",
	"app-riders",
]


## {error: String ("" when valid), mode: "game" | "scene" | "app", at: Array[float] (sorted,
## unique), out: String (as given, or the default folder), frames: int, settle_s: float,
## scene: String, app_screen: String, app_game: String, app_role: String, app_overlay: String,
## app_riders: int, mock_trainer: String, game: String, content: String, players: int,
## sim_args: PackedStringArray}.
static func parse(args: PackedStringArray) -> Dictionary:
	var o := {
		"error": "",
		"mode": "",
		"at": [],
		"out": "",
		"frames": DEFAULT_FRAMES,
		"settle_s": DEFAULT_SETTLE_S,
		"scene": "",
		"app_screen": "",
		"app_game": "workout",
		"app_role": "client",
		"app_overlay": "menu",
		"app_riders": 1,
		"mock_trainer": DEFAULT_MOCK,
		"game": "",
		"content": "",
		"players": 1,
		"sim_args": PackedStringArray(),
	}
	var sim_args := PackedStringArray()
	var at: Array[float] = []
	for a in args:
		if a == "" or a == "--":
			continue
		if not a.begins_with("--"):
			return _fail(o, 'unexpected argument "%s" (flags look like --name=value)' % a)
		var body := a.substr(2)
		var eq := body.find("=")
		var key := body if eq < 0 else body.substr(0, eq)
		var val := "true" if eq < 0 else body.substr(eq + 1)
		if not OWN_FLAGS.has(key):
			sim_args.append(a)
			match key:
				"game":
					o["game"] = val
				"content":
					o["content"] = val
				"players":
					if not val.is_valid_int() or int(val) < 1:
						return _fail(o, '--players needs a whole number >= 1, got "%s"' % val)
					o["players"] = int(val)
			continue
		match key:
			"at":
				for part in val.split(",", false):
					var p := part.strip_edges()
					if not p.is_valid_float() or float(p) < 0.0:
						return _fail(
							o, '--at needs sim seconds >= 0 separated by commas, got "%s"' % val
						)
					if not at.has(float(p)):
						at.append(float(p))
			"out", "screenshot-dir":
				if val == "" or val == "true":
					return _fail(o, "--%s needs a directory" % key)
				o["out"] = val
			"scene":
				if not (
					val.begins_with("res://") and (val.ends_with(".tscn") or val.ends_with(".scn"))
				):
					return _fail(
						o, '--scene needs a res:// path to a .tscn or .scn file, got "%s"' % val
					)
				o["scene"] = val
			"frames":
				if not val.is_valid_int() or int(val) < 1:
					return _fail(o, '--frames needs a whole number >= 1, got "%s"' % val)
				o["frames"] = int(val)
			"settle":
				if not val.is_valid_float() or float(val) < 0.0:
					return _fail(o, '--settle needs seconds >= 0, got "%s"' % val)
				o["settle_s"] = float(val)
			"app-screen":
				if not APP_SCREENS.has(val):
					return _fail(
						o,
						'--app-screen must be one of %s, got "%s"' % [", ".join(APP_SCREENS), val]
					)
				o["app_screen"] = val
			"app-game":
				o["app_game"] = val
			"app-role":
				if not APP_ROLES.has(val):
					return _fail(
						o, '--app-role must be one of %s, got "%s"' % [", ".join(APP_ROLES), val]
					)
				o["app_role"] = val
			"app-overlay":
				if not APP_OVERLAYS.has(val):
					return _fail(
						o,
						'--app-overlay must be one of %s, got "%s"' % [", ".join(APP_OVERLAYS), val]
					)
				o["app_overlay"] = val
			"app-riders":
				if not val.is_valid_int() or int(val) < 1 or int(val) > MAX_RESULTS_RIDERS:
					return _fail(
						o,
						(
							'--app-riders needs a whole number from 1 to %d, got "%s"'
							% [MAX_RESULTS_RIDERS, val]
						)
					)
				o["app_riders"] = int(val)
			"mock-trainer":
				o["mock_trainer"] = val
			"profile-dir":
				pass
	at.sort()
	o["at"] = at
	o["sim_args"] = sim_args
	var modes := 0
	for m: String in ["game", "scene", "app_screen"]:
		if str(o[m]) != "":
			modes += 1
	if modes != 1:
		return _fail(
			o,
			(
				"give exactly one of --game=<id> (with --at), --scene=<res path> or --app-screen=%s"
				% "|".join(APP_SCREENS)
			)
		)
	if str(o["game"]) != "":
		o["mode"] = "game"
		if at.is_empty():
			return _fail(o, "--game needs --at=<sim seconds>[,<s>...]")
	elif str(o["scene"]) != "":
		o["mode"] = "scene"
	else:
		o["mode"] = "app"
		if str(o["app_screen"]) == "session" and at.is_empty():
			at.append(DEFAULT_SESSION_AT)
	if str(o["out"]) == "":
		o["out"] = default_out(str(o["mode"]), str(o["game"]))
	return o


## build/screenshots/<game>/, build/screenshots/scenes/ or build/screenshots/app/.
static func default_out(mode: String, game: String) -> String:
	match mode:
		"game":
			return SCREENSHOT_ROOT.path_join(game)
		"scene":
			return SCREENSHOT_ROOT.path_join("scenes")
	return SCREENSHOT_ROOT.path_join("app")


## An absolute output folder: res:// and user:// are globalized, relative paths start at the
## project root.
static func resolve_dir(dir: String) -> String:
	if dir.begins_with("res://") or dir.begins_with("user://"):
		return ProjectSettings.globalize_path(dir).replace("\\", "/")
	var d := dir.replace("\\", "/")
	if d.is_absolute_path():
		return d.simplify_path()
	return ProjectSettings.globalize_path("res://").replace("\\", "/").path_join(d).simplify_path()


## <game>_<content>_<players>p_<at>s.png, for example siege_short_4p_360s.png.
static func file_name(game: String, content: String, players: int, at: float) -> String:
	return "%s_%s_%dp_%ss.png" % [game, content, players, format_seconds(at)]


## "90" for 90.0, "90.5" for 90.5, "0.25" for 0.25.
static func format_seconds(at: float) -> String:
	if is_equal_approx(at, roundf(at)):
		return str(int(roundf(at)))
	var s := "%.2f" % at
	while s.ends_with("0"):
		s = s.left(-1)
	return s


## A PNG name for a scene: its folder and file name, so both demo.tscn files differ
## (res://addons/wattlands/world2d/demo.tscn -> world2d_demo.png).
static func scene_file_name(scene_path: String) -> String:
	var p := scene_path.trim_prefix("res://")
	var parent := p.get_base_dir().get_file()
	var base := p.get_file().get_basename()
	return ("%s_%s.png" % [parent, base]) if parent != "" else ("%s.png" % base)


static func app_file_name(screen: String) -> String:
	return "app_%s.png" % screen


## app_results_<riders>p.png.
static func results_file_name(riders: int) -> String:
	return "app_results_%dp.png" % riders


## app_session_<role>_<at>s.png, or app_session_<role>_<at>s_<overlay>.png for the overlay shot.
static func session_file_name(app_role: String, at: float, overlay: String = "") -> String:
	var base := "app_session_%s_%ss" % [app_role, format_seconds(at)]
	return (base + "_" + overlay + ".png") if overlay != "" else (base + ".png")


static func _fail(o: Dictionary, msg: String) -> Dictionary:
	o["error"] = msg
	return o
