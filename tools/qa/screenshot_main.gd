extends SceneTree
## The Godot entry of tools/screenshot (BRIEF 3.6, 7.8). Owned by qa. Run windowed, never headless:
##
##   tools/screenshot --game=<id> --content=<id> --at=<s>[,<s>...] [run_game_sim flags] [--out=<dir>]
##   tools/screenshot --scene=res://addons/wattlands/world2d/demo.tscn [--frames=<n>]
##   tools/screenshot --app-screen=title|picker|lobby [--app-game=<id>] [--frames=<n>]
##   tools/screenshot --app-screen=session [--app-role=client|host|solo] [--app-game=<id>]
##                    [--content=<id>] [--at=<s>[,<s>...]] [--app-overlay=menu|panic|discard|none]
##   tools/screenshot --app-screen=results [--app-riders=<1..8>] [--frames=<n>]
##
## (tools/screenshot runs tools/godot.sh --path . --resolution 1920x1080 -s tools/qa/screenshot_main.gd
## -- --mock-trainer=<profile> <flags>; see tools/qa/screenshot_options.gd for every flag.)
##
## Game mode drives GameSimRunner with headless = false (view and HUD built) and run_game_sim's
## slot, role and profile rules: it steps the sim as fast as it can to --settle seconds before each
## --at (sim seconds), steps at normal speed for the rest, and saves the full frame (HUD included,
## the host's view) as <game>_<content>_<players>p_<at>s.png in build/screenshots/<game>/.
## Prints "screenshot: <path>" per PNG. Exit 0 when every shot was saved, 1 when one failed, 2 on
## bad flags. Without a display (headless display server) it prints "screenshot: skipped" and
## exits 0. The wall clock only paces the window here; the sim itself advances in fixed steps.

const Options := preload("res://tools/qa/screenshot_options.gd")
## Longest stretch of fast-forward steps between two rendered frames, so the window keeps
## responding while a long session is skipped.
const FAST_SLICE_MSEC := 50

var _opts: Dictionary = {}
var _failures: int = 0
var _shots: int = 0
## The throwaway profile dir made in _init (removed before quitting), or "".
var _temp_profile: String = ""


func _init() -> void:
	# Runs before the autoloads start: keep the user's real profile, progress and rides untouched.
	if not CmdLine.has("profile-dir"):
		_temp_profile = Paths.make_temp_dir("wattlands_screenshot")
		Paths.set_override(_temp_profile)


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		print(
			"screenshot: skipped (headless display server: nothing to capture; run windowed or under xvfb-run)"
		)
		_finish(0)
		return
	_opts = Options.parse(OS.get_cmdline_user_args())
	if str(_opts["error"]) != "":
		printerr("screenshot: %s" % _opts["error"])
		_finish(2)
		return
	var out_dir := Options.resolve_dir(str(_opts["out"]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	match str(_opts["mode"]):
		"game":
			await _run_game(out_dir)
		"scene":
			await _run_scene(out_dir)
		"app":
			await _run_app(out_dir)
	print("screenshot: %d saved, %d failed" % [_shots, _failures])
	_finish(1 if _failures > 0 or _shots == 0 else 0)


func _finish(code: int) -> void:
	if _temp_profile != "":
		_remove_tree(_temp_profile)
	quit(code)


static func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _run_game(out_dir: String) -> void:
	var game := str(_opts["game"])
	var sim_args: Dictionary = GameSimRunner.parse_args(_opts["sim_args"])
	if str(sim_args.get("error", "")) != "":
		_fail("bad simulation flags: %s" % sim_args["error"])
		return
	sim_args["headless"] = false
	var runner := GameSimRunner.new()
	root.add_child(runner)
	var err := runner.setup(sim_args)
	if err != "":
		_fail("cannot start %s: %s" % [game, err])
		runner.queue_free()
		return
	var content := str(sim_args.get("content", _opts["content"]))
	if content == "" and runner.host != null and runner.host.ctx != null:
		content = runner.host.ctx.content_id
	var players := int(sim_args.get("players", _opts["players"]))
	for at: float in _opts["at"]:
		if not await _advance_to(runner, at):
			_fail(
				(
					"the session ended at %.1f s of sim time, before --at=%s"
					% [runner.sim_seconds(), Options.format_seconds(at)]
				)
			)
			continue
		await _capture(out_dir.path_join(Options.file_name(game, content, players, at)))
	runner.queue_free()


## Steps the session to `at` sim seconds: as fast as possible until --settle seconds before it,
## then one fixed step per 0.05 s of frame time. False when the session ended first.
func _advance_to(runner: GameSimRunner, at: float) -> bool:
	var settle := float(_opts["settle_s"])
	var fast_until := maxf(at - settle, 0.0)
	while runner.sim_seconds() + Wl.SIM_DT <= fast_until + 1e-6:
		if _finished(runner):
			return false
		var slice_end := Time.get_ticks_msec() + FAST_SLICE_MSEC
		while (
			runner.sim_seconds() + Wl.SIM_DT <= fast_until + 1e-6
			and Time.get_ticks_msec() < slice_end
		):
			runner.step()
		await process_frame
	var acc := 0.0
	while runner.sim_seconds() + 1e-6 < at:
		if _finished(runner):
			return false
		await process_frame
		acc += root.get_process_delta_time()
		while acc >= Wl.SIM_DT and runner.sim_seconds() + 1e-6 < at:
			runner.step()
			acc -= Wl.SIM_DT
	return true


func _finished(runner: GameSimRunner) -> bool:
	return runner.host != null and runner.host.is_finished()


func _run_scene(out_dir: String) -> void:
	var path := str(_opts["scene"])
	if not ResourceLoader.exists(path):
		_fail("no scene at %s" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("%s is not a PackedScene" % path)
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	current_scene = inst
	for i in int(_opts["frames"]):
		await process_frame
	await _capture(out_dir.path_join(Options.scene_file_name(path)))
	inst.queue_free()


func _run_app(out_dir: String) -> void:
	var screen := str(_opts["app_screen"])
	var main_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed: PackedScene = null
	if main_path != "":
		packed = load(main_path) as PackedScene
	if packed == null:
		_fail("cannot load the main scene %s" % main_path)
		return
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	var trainer := root.get_node_or_null(^"TrainerService") as WlTrainerService
	if trainer != null:
		trainer.use_mock(str(_opts["mock_trainer"]))
	var app := root.get_node_or_null(^"App") as WlApp
	if app == null:
		_fail("the App autoload is missing")
		return
	if screen == "session":
		await _run_session(out_dir, main, app)
		return
	var params := {}
	var file := Options.app_file_name(screen)
	if screen == "lobby":
		params = {"game_id": str(_opts["app_game"])}
	elif screen == "results":
		params = QaScreenshotResults.params(int(_opts["app_riders"]))
		file = Options.results_file_name(int(_opts["app_riders"]))
	await process_frame
	app.goto(screen, params)
	for i in int(_opts["frames"]):
		await process_frame
	if screen == "results":
		var shown := main.get("screen") as AppResultsScreen
		if shown != null:
			print(QaScreenshotResults.describe(shown))
	await _capture(out_dir.path_join(file))


## The app's session screen (tools/qa/screenshot_session.gd): one shot per --at, then one with
## the overlay open (--app-overlay).
func _run_session(out_dir: String, main: Node, app: WlApp) -> void:
	await process_frame
	var run := QaScreenshotSession.create(self, main, app, _opts)
	var screen: AppSessionScreen = await run.start()
	if screen == null:
		_fail("session: %s" % run.error)
		run.cleanup()
		return
	var role := str(_opts["app_role"])
	var last := 0.0
	for at: float in _opts["at"]:
		if not await run.advance_to(at):
			_fail("session: the app's session ended before %s s" % Options.format_seconds(at))
			continue
		last = at
		print(run.describe(screen))
		await _capture(out_dir.path_join(Options.session_file_name(role, at)))
	var overlay := str(_opts["app_overlay"])
	if overlay != "none" and is_instance_valid(screen) and screen.host != null:
		if overlay == "panic":
			screen.panic()
		else:
			screen.open_menu()
			if overlay == "discard":
				screen.open_discard_confirm()
		for i in 3:
			await process_frame
		print(run.describe(screen))
		await _capture(out_dir.path_join(Options.session_file_name(role, last, overlay)))
	run.cleanup()


## Saves the next fully drawn frame of the window (HUD included) as a PNG.
func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		_fail("the frame for %s was empty" % path)
		return
	var err := img.save_png(path)
	if err != OK:
		_fail("cannot write %s (%s)" % [path, error_string(err)])
		return
	_shots += 1
	print("screenshot: %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _fail(msg: String) -> void:
	_failures += 1
	printerr("screenshot: %s" % msg)
