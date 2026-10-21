class_name AppServices
extends RefCounted
## Everything the app shell's screens use, in one place (BRIEF 3.9 app shell). In the app it
## points at the autoloads (App, Settings, TrainerService, NetSession, GameRegistry, Rides, Sfx,
## InputRouter, EventBus); tests build one from fakes, so every screen runs headless without the
## real trainer, relay or Strava. Screens never reach into another module's nodes by path
## (BRIEF 6): they call these services and listen to their signals.

## Emitted by goto() when the App autoload did not move to the requested state itself (its W0
## stub), so the main scene still shows the screen.
signal navigated(state: String, params: Dictionary)

var app: WlApp = null
var settings: WlSettings = null
var trainer: WlTrainerService = null
var net: WlNetSession = null
var registry: WlGameRegistry = null
var rides: WlRides = null
var sfx: WlSfx = null
var input: WlInputRouter = null
var bus: WlEventBus = null
var tree: SceneTree = null

## () -> PedalScanList. Tests swap in a scripted list.
var scan_list_factory: Callable
## () -> GameHost.
var game_host_factory: Callable
## () -> LocalRider (bot riders on the host).
var rider_factory: Callable
## Fixed UTC time for tests (-1: the system clock).
var utc_override: int = -1
## Called by quit() instead of SceneTree.quit (tests).
var quit_hook: Callable
## Last exit code passed to quit().
var quit_code: int = -1
## Title screen visits in this app run (1 = the launch visit; the zero-touch rules use it). A
## title rebuilt over a title (the App's deferred boot shows it a second time at launch) is the
## same visit.
var title_visits: int = 0
## The state the main scene showed before the screen being built now ("" at launch).
var previous_state: String = ""


func _init() -> void:
	scan_list_factory = _default_scan_list
	game_host_factory = _default_game_host
	rider_factory = _default_rider


## Services backed by the autoloads of `p_tree`.
static func from_tree(p_tree: SceneTree) -> AppServices:
	var s := AppServices.new()
	s.tree = p_tree
	var root := p_tree.root
	s.app = root.get_node_or_null("App") as WlApp
	s.settings = root.get_node_or_null("Settings") as WlSettings
	s.trainer = root.get_node_or_null("TrainerService") as WlTrainerService
	s.net = root.get_node_or_null("NetSession") as WlNetSession
	s.registry = root.get_node_or_null("GameRegistry") as WlGameRegistry
	s.rides = root.get_node_or_null("Rides") as WlRides
	s.sfx = root.get_node_or_null("Sfx") as WlSfx
	s.input = root.get_node_or_null("InputRouter") as WlInputRouter
	s.bus = root.get_node_or_null("EventBus") as WlEventBus
	return s


## Move the app to `state` (App.goto). The main scene shows the screen on App.state_changed;
## if the App did not take the state (W0 stub), `navigated` makes main show it anyway.
func goto(state: String, params: Dictionary = {}) -> void:
	if app != null:
		app.goto(state, params)
		if app.state == state:
			return
	navigated.emit(state, params)


func profile() -> RiderProfile:
	if settings == null or settings.profile == null:
		return RiderProfile.new()
	return settings.profile


func make_scan_list() -> PedalScanList:
	return scan_list_factory.call() as PedalScanList


func make_game_host() -> GameHost:
	return game_host_factory.call() as GameHost


func make_rider() -> LocalRider:
	return rider_factory.call() as LocalRider


## Seconds since 1970 (UTC). The app reads the wall clock only here: for a ride's UTC start
## stamp and for a fresh session seed when no --seed is given (BRIEF 3.6, 3.8).
func utc_now() -> int:
	if utc_override >= 0:
		return utc_override
	return int(Time.get_unix_time_from_system())


## Ask TrainerService to stop (false) or resume (true) ticking the device and the menu-time
## rider, while a GameHost or the FTP test ticks the rider itself:
## WlTrainerService.set_external_tick(not on). Handing ticking back sets the rider up afresh as
## the menu rider once its ride is saved (platform). Without it both the service and the
## GameHost would tick one rider on two clocks.
func set_menu_ticking(on: bool) -> void:
	if trainer != null:
		trainer.set_external_tick(not on)


func play_sound(sound: String) -> void:
	if sfx != null:
		sfx.play(sound)


## Quit the app: App.quit (governor shutdown on every local rider), then `last` (the scripted
## peer writes its report and DONE line there, after App.quit, so nothing overwrites them), then
## SceneTree.quit(code).
func quit(code: int = 0, last: Callable = Callable()) -> void:
	quit_code = code
	if quit_hook.is_valid():
		if last.is_valid():
			last.call()
		quit_hook.call(code)
		return
	if app != null:
		app.quit(code)
	if last.is_valid():
		last.call()
	if tree != null:
		tree.quit(code)


func _default_scan_list() -> PedalScanList:
	return PedalScanList.new()


func _default_game_host() -> GameHost:
	return GameHost.new()


func _default_rider() -> LocalRider:
	return LocalRider.new()
