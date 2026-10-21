extends GutTest
## BRIEF 5.1 over the real platform (GameSimRunner, NetSession, LoopbackTransport): a client's
## WorkoutGame records the snapshots the host sends, 0.1 s of host time apart, and its ride
## view draws the other riders between the last two of them and the local rider from its own
## predicted state.

const FRAME := 1.0 / 60.0

var _tmp: String = ""
var _runner: GameSimRunner = null


func before_each() -> void:
	_tmp = Paths.make_temp_dir("workout_client_view")


func after_each() -> void:
	if is_instance_valid(_runner):
		_runner.cleanup()
	_runner = null
	GameSimRunner._remove_tree(_tmp)


func test_a_client_view_interpolates_the_host_snapshots() -> void:
	var args := (
		GameSimRunner
		. parse_args(
			PackedStringArray(
				[
					"--game=workout",
					"--content=e2e",
					"--players=2",
					"--bots=1",
					"--seed=3",
					"--max-sim-seconds=20",
					"--report=" + _tmp.path_join("client_view.json"),
				]
			)
		)
	)
	assert_false(args.has("error"), str(args.get("error", "")))
	args["headless"] = true
	_runner = GameSimRunner.new()
	add_child_autofree(_runner)
	assert_eq(_runner.setup(args), "")
	assert_eq(_runner.run_to_end(), "timeout")
	assert_eq(_runner.clients.size(), 1, "one client")
	var gh := _runner.clients[0]
	var game := gh.game as WorkoutGame
	assert_eq(game.ctx.role, Wl.CLIENT)
	var h := game.history
	assert_eq(h.entries.size(), WorkoutSnapHistory.CAPACITY, "the last 8 snapshots")
	for i in range(1, h.entries.size()):
		assert_almost_eq(
			float(h.entries[i]["t"]) - float(h.entries[i - 1]["t"]), 0.1, 1e-6, "10 Hz host time"
		)
	assert_true(_runner.host.game is WorkoutGame)
	assert_true((_runner.host.game as WorkoutGame).history.is_empty(), "the host keeps none")
	var view := game.make_view() as WorkoutRideView
	add_child_autofree(view)
	view.set_process(false)
	view.advance(FRAME)
	view.advance(0.05)
	assert_almost_eq(view.render_t, h.newest_t() - 0.05, 1e-9, "halfway between the last two")
	var a: Dictionary = h.entries[h.entries.size() - 2]["d"]
	var b: Dictionary = h.entries[h.entries.size() - 1]["d"]
	var local := gh.local_peer()
	var others := 0
	for peer: int in game.state.order:
		if peer == local:
			continue
		others += 1
		assert_gt(float(b[peer]), float(a[peer]), "peer %d rides on" % peer)
		assert_almost_eq(
			view.shown_distance(peer),
			(float(a[peer]) + float(b[peer])) / 2.0,
			1e-6,
			"peer %d is drawn between its last two snapshots" % peer
		)
	assert_eq(others, 2, "the host's rider and the bot")
	var me := game.state.rider(local)
	assert_true(view.local_d >= me.distance_m(), "the local rider moves on its own prediction")
	assert_true(view.local_d <= me.distance_m() + me.speed_mps() * 0.05 + 1e-9, "by at most 0.05 s")
