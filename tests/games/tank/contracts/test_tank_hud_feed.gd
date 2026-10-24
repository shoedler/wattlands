extends GutTest
## The two HUD feeds the kit cannot derive by itself (brief 3, HUD): the teammate strip
## (TankGame._feed_status: the engine's name and icon plus in band, every 10 ticks, so the strip
## text follows the rotation) and the hull HP readout (TankGame._feed_hull: whenever the shown
## number changes, on the host after each step and on a client after each snapshot). Both go
## through ctx.hud, which TankFakes.Hud records.

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _status_calls(ctx: GameContext, peer: int) -> Array:
	return (ctx.hud as F.Hud).of("teammate_status").filter(
		func(c: Array) -> bool: return int(c[1]) == peer
	)


func _hull_texts(ctx: GameContext) -> Array:
	var out: Array = []
	for c: Array in (ctx.hud as F.Hud).of("readout"):
		if str(c[1]) == TankHud.READOUT_HULL:
			out.append(str(c[2]))
	return out


## The label of the engine as the strip must show it.
func _label(ctx: GameContext, engine: String) -> String:
	return ctx.strings.t(str(TankIds.ENGINE_LABELS[engine]))


## Consecutive duplicates removed.
func _runs(values: Array) -> Array:
	var out: Array = []
	for v: Variant in values:
		if out.is_empty() or out[-1] != v:
			out.append(v)
	return out


func test_the_strip_gets_every_rider_with_its_engine_name_icon_and_in_band() -> void:
	var ctx := F.make_ctx(3)
	var g: TankGame = autofree(F.make_game(ctx))
	var clock := F.clock_of(g)
	F.run(g, clock.plans, 0, 3.0, 100.0, clock)
	var engines := {1: "diesel", 2: "dynamo", 3: "steam"}
	for peer: int in engines:
		var calls := _status_calls(ctx, peer)
		# 3 s is 60 ticks: the strip is fed on ticks 0, 10, ..., 50.
		assert_eq(calls.size(), 6, "peer %d: every 10 ticks" % peer)
		var s: Dictionary = calls[0][2]
		assert_eq(s["text"], _label(ctx, engines[peer]), "peer %d: the engine's name" % peer)
		assert_eq(s["icon"], TankIds.ENGINE_ICONS[engines[peer]], "peer %d: its icon path" % peer)
		assert_true(s["in_band"] is bool, "peer %d: in_band is a bool" % peer)
	assert_ne(
		_label(ctx, "diesel"), _label(ctx, "dynamo"), "the three engines read differently"
	)
	assert_ne(_label(ctx, "dynamo"), _label(ctx, "steam"))


func test_the_strip_text_follows_the_rotation_through_the_checkpoints() -> void:
	var ctx := F.make_ctx(3)
	var g: TankGame = autofree(F.make_game(ctx))
	var clock := F.clock_of(g)
	F.run_session(g, clock)
	# Slot n's engines by stage: 0 diesel, dynamo, steam, diesel (brief 2.2). The depot's engine is
	# the start engine, so the strip changes at each checkpoint.
	var rows := {
		1: ["diesel", "dynamo", "steam", "diesel"],
		2: ["dynamo", "steam", "diesel", "dynamo"],
		3: ["steam", "diesel", "dynamo", "steam"],
	}
	for peer: int in rows:
		var texts: Array = _status_calls(ctx, peer).map(
			func(c: Array) -> String: return str(c[2]["text"])
		)
		var want: Array = []
		for engine: String in rows[peer]:
			want.append(_label(ctx, engine))
		assert_eq(_runs(texts), want, "peer %d: the strip follows the engine through the stages" % peer)


func test_the_strip_text_stays_put_without_rotation() -> void:
	var ctx := F.make_ctx(3)
	ctx.options["rotation"] = false
	var g: TankGame = autofree(F.make_game(ctx))
	var clock := F.clock_of(g)
	F.run_session(g, clock)
	var start := {1: "diesel", 2: "dynamo", 3: "steam"}
	for peer: int in start:
		var texts: Array = _status_calls(ctx, peer).map(
			func(c: Array) -> String: return str(c[2]["text"])
		)
		assert_eq(_runs(texts), [_label(ctx, start[peer])], "peer %d" % peer)


func test_the_strip_carries_in_band_as_the_rider_goes_in_and_out() -> void:
	var ctx := F.make_ctx(3)
	var g: TankGame = autofree(F.make_game(ctx))
	var clock := F.clock_of(g)
	# 310 s: peer 1 (diesel) is 10 s into the SIM Advance at 90% FTP, inside the 76-105% band.
	var tick := F.run(g, clock.plans, 0, 310.0, 100.0, clock)
	assert_true(bool(_status_calls(ctx, 1)[-1][2]["in_band"]), "90% FTP in the SIM Advance")
	# At 50% of that (45% FTP) the diesel is out of band; the strip says so within 0.5 s.
	F.run(g, clock.plans, tick, 3.0, 50.0, clock)
	assert_false(bool(_status_calls(ctx, 1)[-1][2]["in_band"]), "45% FTP is out of band")


func test_the_hull_readout_is_fed_on_the_first_step_and_only_when_the_number_changes() -> void:
	var ctx := F.make_ctx(1)
	var g: TankGame = autofree(F.make_game(ctx))
	var plans := F.plans_of(g)
	var tick := F.run(g, plans, 0, 0.05)
	var first := _hull_texts(ctx)
	assert_eq(first, [str(ceili(g.state.hull.hp))], "the first step shows the hull")
	tick = F.run(g, plans, tick, 2.0)
	assert_eq(_hull_texts(ctx), first, "an unchanged number is not fed again")
	# A hit: 100.2 HP shows as 101 (HP rounds up, brief 2.8), then the next hit as 88.
	g.state.hull.hp = 100.2
	tick = F.run(g, plans, tick, 0.05)
	g.state.hull.hp = 87.3
	tick = F.run(g, plans, tick, 0.05)
	assert_eq(_hull_texts(ctx), first + ["101", "88"])
	assert_eq((ctx.hud as F.Hud).of("readout").back(), ["readout", TankHud.READOUT_HULL, "88"])


func test_a_whole_session_ends_on_the_final_hull_with_no_repeats() -> void:
	var ctx := F.make_ctx(3)
	var g: TankGame = autofree(F.make_game(ctx))
	var clock := F.clock_of(g)
	F.run_session(g, clock)
	var texts := _hull_texts(ctx)
	assert_gt(texts.size(), 1, "the hull changes over a session (checkpoint repairs at least)")
	assert_eq(texts.back(), str(ceili(g.state.hull.hp)), "the readout ends on the final hull")
	assert_eq(_runs(texts), texts, "a number is fed only when it changes")


func test_a_client_shows_the_hull_of_each_snapshot_it_applies() -> void:
	var host: TankGame = autofree(F.make_game(F.make_ctx(2, 0, "drill", Wl.HOST, 1)))
	var plans := F.plans_of(host)
	F.run(host, plans, 0, 1.0)
	host.state.hull.hp = 73.4
	var snap := host.snapshot()
	var ctx := F.make_ctx(2, 0, "drill", Wl.CLIENT, 2)
	var client: TankGame = autofree(F.make_game(ctx))
	client.apply_snapshot(snap)
	assert_eq(_hull_texts(ctx).back(), "74", "HP rounds up on the client too")
	host.state.hull.hp = 60.0
	client.apply_snapshot(host.snapshot())
	assert_eq(_hull_texts(ctx).back(), "60")
	client.apply_snapshot(host.snapshot())
	assert_eq(_hull_texts(ctx).size(), 2, "the same snapshot twice feeds once")
