extends Control
## The app's main scene (BRIEF 3.9 app shell). It shows the screen for App.state (title,
## first run, profile, settings with its rides and FTP-test pages, game picker, lobby with code
## entry, session, results) and switches when App.state_changed fires. At boot it loads the
## profile and settings, starts the trainer backend (auto-connect to the last trainer, or
## --mock-trainer) and retries queued Strava uploads, then shows the title, whose zero-touch
## rules start a ride with no input (BRIEF 3.5).
## Started with --host or --join=<code> it runs as a scripted peer instead (docs/ARCHITECTURE.md,
## the end-to-end test contract): no menus, AppScriptedPeer drives the session.

## Injected before _ready() by tests; built from the autoloads otherwise.
var services: AppServices = null
## Injected by tests; parsed from the command line otherwise.
var scripted_config: AppScriptedConfig = null
## Tests: skip loading settings, starting the trainer and the upload queue.
var skip_boot: bool = false
## Tests: screens advance only through tick(dt).
var screens_auto_process: bool = true
var screen: AppScreen = null
var state: String = ""
var scripted: AppScriptedPeer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = AppStyle.theme()
	if services == null:
		services = AppServices.from_tree(get_tree())
	if scripted_config == null:
		scripted_config = AppScriptedConfig.from_args(CmdLine.args())
	if scripted_config.enabled:
		start_scripted()
		return
	if services.app != null:
		services.app.state_changed.connect(_on_app_state)
	services.navigated.connect(_on_app_state)
	if not skip_boot:
		boot()
	var st := services.app.state if services.app != null else ""
	if st == "" or st == "boot":
		services.goto("title")
	else:
		show_state(st, services.app.params)


func _exit_tree() -> void:
	if services == null:
		return
	if services.app != null and services.app.state_changed.is_connected(_on_app_state):
		services.app.state_changed.disconnect(_on_app_state)
	if services.navigated.is_connected(_on_app_state):
		services.navigated.disconnect(_on_app_state)


## Launch-time work (BRIEF 3.5, 3.8): profile and settings (and the saved master volume), the
## trainer backend (auto-connect to the last trainer), queued uploads.
func boot() -> void:
	if services.settings != null:
		services.settings.load_all()
		AppSettingsScreen.apply_volume(float(services.settings.get_value("master_volume_db", 0.0)))
	if (
		services.trainer != null
		and services.trainer.device() == null
		and services.trainer.status() == TrainerDevice.STATUS_DISCONNECTED
	):
		services.trainer.start()
	if services.rides != null:
		services.rides.process_queue()


func _on_app_state(new_state: String, p: Dictionary) -> void:
	show_state(new_state, p)


## Replace the current screen with the one for `new_state`. "quitting" has no screen: the
## current one is frozen (no more ticks, input or GameHost steps, so App.quit's TrainerService
## alone ticks the shut-down riders while their safe commands go out), then AppServices.quit
## starts App.quit, or does nothing more when App.quit is already running (a window close):
## App.quit ends the tree itself, after its leave and QUIT_GRACE_S (W4r2 R9/R10).
func show_state(new_state: String, p: Dictionary = {}) -> void:
	if new_state == "quitting":
		if screen != null and is_instance_valid(screen):
			screen.freeze()
		services.quit(0)
		return
	var next := make_screen(new_state, p)
	if next == null:
		return
	if screen != null and is_instance_valid(screen):
		screen.leave()
		remove_child(screen)
		screen.queue_free()
	screen = next
	services.previous_state = state
	state = new_state
	screen.name = "Screen_" + new_state
	screen.services = services
	screen.auto_process = screens_auto_process
	add_child(screen)
	screen.enter(p)


## The screen for an App state ("settings" with params.page "rides" or "ftp_test" opens those
## pages); null for states without a screen ("boot").
static func make_screen(new_state: String, p: Dictionary) -> AppScreen:
	match new_state:
		"title":
			return AppTitleScreen.new()
		"first_run":
			return AppFirstRunScreen.new()
		"profile":
			return AppProfileScreen.new()
		"settings":
			match str(p.get("page", "")):
				"rides":
					return AppRidesScreen.new()
				"ftp_test":
					return AppFtpTestScreen.new()
			return AppSettingsScreen.new()
		"picker":
			return AppPickerScreen.new()
		"lobby":
			return AppLobbyScreen.new()
		"session":
			return AppSessionScreen.new()
		"results":
			return AppResultsScreen.new()
	return null


## Scripted peer (--host / --join): a passive status screen and the AppScriptedPeer driver.
func start_scripted() -> void:
	var view := AppScriptedScreen.new()
	view.services = services
	view.auto_process = false
	add_child(view)
	view.enter({})
	screen = view
	state = "scripted"
	scripted = AppScriptedPeer.new()
	scripted.name = "ScriptedPeer"
	scripted.services = services
	scripted.config = scripted_config
	scripted.headless = DisplayServer.get_name() == "headless"
	if not scripted.headless:
		scripted.view_parent = view.view_layer
		scripted.hud_parent = view.hud_layer
	add_child(scripted)
	view.set_status("%s %s" % [scripted_config.role, scripted_config.join_code])
	scripted.start()
