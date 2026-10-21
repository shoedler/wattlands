extends "res://tests/net/net_session_test_base.gd"
## The real app's quit chain (W4r2 R9/R10, W3 NET-6; BRIEF 4.6.9, 5.3, 5.5): a window close (or
## the title's Quit) runs App.quit -> goto("quitting") -> the main scene's "quitting" branch ->
## AppServices.quit, and App.quit must still get to leave the hosted room and wait
## QUIT_GRACE_S before the tree quits. Here the real main.gd, AppServices and WlApp run on a
## hosting WlNetSession over a LoopbackHub with two clients; AppServices.quit_hook stands in
## for SceneTree.quit and the App's _quit_tree is recorded, so nothing ends the test process.

const AppFixture := preload("res://tests/app/fakes/app_fixture.gd")
const FakeTrainer := preload("res://tests/app/fakes/fake_trainer.gd")
const MainScene := preload("res://src/app/main.gd")


class QuitRecordingApp:
	extends WlApp

	var quit_codes: Array[int] = []
	var quit_ms: Array[int] = []

	func _quit_tree(code: int) -> void:
		quit_codes.append(code)
		quit_ms.append(Time.get_ticks_msec())


## A trainer service whose device counts as a real trainer (not a MockTrainer).
class RealTrainerService:
	extends "res://tests/app/fakes/fake_trainer.gd"

	func is_mock() -> bool:
		return false


var fx: AppFixture = null
var app: QuitRecordingApp = null
var main: Control = null
## SceneTree.quit requests: [code, the host NetSession's state at that moment].
var tree_quits: Array = []


func before_each() -> void:
	super.before_each()
	fx = AppFixture.new()
	tree_quits = []


func after_each() -> void:
	if main != null and is_instance_valid(main):
		var s: AppScreen = main.get("screen") as AppScreen
		if s != null and is_instance_valid(s):
			s.leave()
		remove_child(main)
		main.free()
	main = null
	if app != null and is_instance_valid(app):
		remove_child(app)
		app.free()
	app = null
	fx.free_all()
	fx = null
	super.after_each()


## The real main scene over the fixture's services, with a real App (inside the tree) that
## hosts `net`. The App's trainer service is `ts` (the fixture's mock trainer by default).
func _open_main(net: WlNetSession, ts: WlTrainerService = null) -> void:
	app = QuitRecordingApp.new()
	app.net_session = net
	app.trainer_service = ts if ts != null else fx.trainer
	app.settings = fx.settings
	app.rides = fx.rides
	app.bus = fx.bus
	add_child(app)
	fx.services.app = app
	fx.services.net = net
	fx.services.quit_hook = func(code: int) -> void:
		tree_quits.append([code, net.state if net != null else ""])
	main = MainScene.new()
	main.set("services", fx.services)
	main.set("skip_boot", true)
	main.set("screens_auto_process", false)
	main.set("scripted_config", AppScriptedConfig.new())
	add_child(main)


func _peer_left_reasons(label: String) -> Array:
	var out: Array = []
	for e: Array in events(label, "peer_left"):
		out.append(e[2])
	return out


func test_a_window_close_while_hosting_leaves_the_room_and_quits_only_after_the_grace() -> void:
	var r := room(["1", "1"])
	var h := r[0]
	assert_eq(h.state, WlNetSession.STATE_HOSTING)
	_open_main(h)
	assert_true(main.get("screen") is AppTitleScreen, "the main scene shows the title")
	clear_logs()
	# A SceneTreeTimer counts the whole frame it was made in, so start on a fresh frame (as a
	# window close does) before timing the grace.
	await wait_process_frames(1)
	var t0 := Time.get_ticks_msec()
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(app.exit_reason, "window_closed")
	assert_eq(tree_quits, [], "AppServices never asks the SceneTree to quit while App.quit runs")
	assert_eq(app.quit_codes.size(), 0, "the tree waits the grace")
	assert_eq(h.state, WlNetSession.STATE_OFFLINE, "App.quit left the room")
	pump()
	for label: String in ["c1", "c2"]:
		assert_true(
			U.same(events(label, "refused"), [["refused", "host_left"]]),
			"%s gets host_left" % label
		)
		assert_false(
			_peer_left_reasons(label).has("dropped"), "%s never sees the host dropped" % label
		)
	await wait_seconds(WlApp.QUIT_GRACE_S + 0.3)
	assert_eq(app.quit_codes, [0] as Array[int], "App.quit ended the tree itself")
	assert_eq(tree_quits, [], "and only App did")
	if app.quit_ms.size() == 1:
		assert_gte(
			app.quit_ms[0] - t0,
			int(WlApp.QUIT_GRACE_S * 1000.0) - 50,
			"after QUIT_GRACE_S of real time"
		)


func test_the_title_quit_while_hosting_takes_the_same_path() -> void:
	var r := room(["1"])
	var h := r[0]
	_open_main(h)
	fx.services.goto("quitting")
	assert_eq(app.state, "quitting")
	assert_true(app.is_quitting(), "the quitting screen state starts App.quit")
	assert_eq(tree_quits, [])
	assert_eq(h.state, WlNetSession.STATE_OFFLINE)
	pump()
	assert_true(U.same(events("c1", "refused"), [["refused", "host_left"]]))
	await wait_seconds(WlApp.QUIT_GRACE_S + 0.3)
	assert_eq(app.quit_codes, [0] as Array[int])
	assert_eq(tree_quits, [])


func test_a_window_close_with_a_real_trainer_waits_the_grace_for_the_shutdown_writes() -> void:
	var ts := RealTrainerService.new()
	ts.dev = MockTrainer.from_spec("erg", 200.0)
	ts.add_child(ts.dev)
	ts.st = TrainerDevice.STATUS_READY
	add_child_autofree(ts)
	_open_main(null, ts)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(tree_quits, [])
	assert_eq(app.quit_codes.size(), 0)
	await wait_seconds(WlApp.QUIT_GRACE_S + 0.3)
	assert_eq(app.quit_codes, [0] as Array[int])
	assert_eq(tree_quits, [])


func test_without_a_room_or_a_real_trainer_the_app_quits_at_once() -> void:
	_open_main(null)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(app.quit_codes, [0] as Array[int], "no grace to wait for")
	assert_eq(tree_quits, [])


func test_quitting_freezes_the_current_screen() -> void:
	_open_main(null, null)
	var s: AppScreen = main.get("screen") as AppScreen
	# Stands in for a GameHost under the session screen: always processing, whatever the pause.
	var child := Node.new()
	child.process_mode = Node.PROCESS_MODE_ALWAYS
	s.add_child(child)
	child.set_process(true)
	s.set_process(true)
	assert_true(child.is_processing())
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(s.is_processing(), "the screen stops ticking")
	assert_false(
		child.is_processing(), "and so does everything under it (a GameHost stops stepping riders)"
	)
	assert_false(s.auto_process)
	assert_false(
		fx.input.action.is_connected(Callable(s, "_on_router_action")), "no more menu input"
	)


func test_services_end_the_tree_when_the_app_is_not_in_the_tree() -> void:
	var lone := QuitRecordingApp.new()
	lone.trainer_service = fx.trainer
	lone.settings = fx.settings
	lone.rides = fx.rides
	lone.bus = fx.bus
	autofree(lone)
	var s := AppServices.new()
	s.app = lone
	var seen: Array[int] = []
	s.quit_hook = func(code: int) -> void: seen.append(code)
	var last_ran: Array[bool] = [false]
	s.quit(3, func() -> void: last_ran[0] = true)
	assert_true(lone.is_quitting())
	assert_false(s.app_ends_tree())
	assert_true(last_ran[0], "last runs")
	assert_eq(
		seen, [3] as Array[int], "a private App outside the tree can't quit it; AppServices does"
	)
