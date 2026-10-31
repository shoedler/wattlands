extends GutTest
## S18's HUD half (SPEC_TANK 9.2): the matrix's bot runs are headless, with no HUD at all, so this
## builds the real HUD over a crew of humans and bots on Hard and steps it through the depot into
## the first fight. GUT fails the test on any push_error or script error.

const F := preload("res://tests/games/tank/tank_fakes.gd")
const FIGHT_S := 60.0
const REFRESH_EVERY := 20


func _content() -> String:
	return "ambush_15" if (F.manifest()["contents"] as Array).has("ambush_15") else "ashfall_road"


func _run(humans: int, bots: int) -> void:
	var ctx := F.make_ctx(humans, bots, _content(), Wl.SOLO if humans == 1 else Wl.HOST, 1, 1)
	ctx.options["difficulty"] = TankIds.DIFF_HARD
	var game := F.make_game(ctx)
	autofree(game)
	assert_eq(game.state.difficulty, TankIds.DIFF_HARD)
	assert_eq(game.state.crew, humans + bots, "bots count in the crew")
	var ctls: Array[TankHudCtl] = []
	for c: Dictionary in TankHud.spec(game).controls:
		var ctl := c["control"] as TankHudCtl
		ctls.append(ctl)
		add_child_autofree(ctl)
	var clock := F.clock_of(game)
	var ticks := roundi((TankConst.FIRST_S + FIGHT_S) / Wl.SIM_DT)
	var tick := 0
	while tick < ticks:
		tick = F.run(game, clock.plans, tick, Wl.SIM_DT * REFRESH_EVERY, 100.0, clock)
		for ctl in ctls:
			ctl.tick(Wl.SIM_DT * REFRESH_EVERY)
			ctl.refresh()
	for ctl in ctls:
		ctl.queue_redraw()
	await wait_physics_frames(2)
	for ctl in ctls:
		assert_gt(ctl.draws, 0, "%s drew with %d bots" % [ctl.name, bots])


func test_the_hud_runs_with_one_human_and_three_bots_on_hard() -> void:
	await _run(1, 3)


func test_the_hud_runs_with_two_humans_and_two_bots_on_hard() -> void:
	await _run(2, 2)
