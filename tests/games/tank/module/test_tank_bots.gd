extends GutTest
## TankBots (V1 plan item 8, SPEC_TANK 3.7): every adaptation to the humans has its own test, then a
## human's move always wins, the cover swap with no effort change, the bots' stay and gates, enemy
## counts with bots, and a 30-minute session with a scripted human. The situations hang on TankTargets
## only (far_target, near_threat), so nothing here depends on the gun's ballistics.

const F := preload("res://tests/games/tank/tank_fakes.gd")

const DRIVE := TankIds.ENGINE_DIESEL
const GUN := TankIds.ENGINE_DYNAMO
const LOADER := TankIds.ENGINE_STEAM
const LIGHTS := TankIds.ENGINE_ARC
const FEED := TankIds.ENGINE_FEED
const REPAIR := TankIds.ENGINE_REPAIR
const HUMAN := 1


## Stage 2's Advance with `crew` riders: rider 0 is the human (fallback off), the rest bots; no enemies,
## full hull, the rack at 2 of 3, every rider long on its seat. Bots sit on the start seats.
func _state(crew: int = 4) -> TankState:
	var s := TankFixtures.state(crew)
	s.enemies.clear()
	s.shells.clear()
	s.obstacles.clear()
	s.tick = 20 * 3000
	s.t = s.tick * Wl.SIM_DT
	s.seg.elapsed_s = 200.0
	s.hull.hp_max = 100.0
	s.hull.hp = 100.0
	s.hull.loaded = TankIds.SHELL_NONE
	TankStations.fill_rack(s, 2)
	for i in s.riders.size():
		var r := s.riders[i]
		r.is_bot = i > 0
		r.autopilot = i > 0
		r.fallback = false
		r.afk = false
		r.connected = true
		r.rescue = false
		r.in_band = true
		TankAux.of(s).seat_since[r.peer] = -1.0e9
	_targets(s)
	return s


func _targets(s: TankState) -> void:
	TankTargets.build(s, TankAux.of(s))


func _bot(s: TankState, engine: String) -> TankRiderState:
	return s.rider_at(s.station(engine).slot)


## Clears the seat, moving whoever holds it nowhere: the crew's seats by hand.
func _vacate(s: TankState, engine: String) -> void:
	var st := s.station(engine)
	var r := s.rider_at(st.slot)
	if r != null:
		var ev: Array[Dictionary] = []
		TankSeats.land(s, r, TankSeats.empty_seats(s)[0], ev)
		TankAux.of(s).seat_since[r.peer] = -1.0e9


## Trades the seats of the human and the rider on `engine` by hand, so the human sits on `engine`.
func _human_on(s: TankState, engine: String) -> void:
	var human := s.rider(HUMAN)
	var ev: Array[Dictionary] = []
	if s.station(engine).is_empty():
		TankSeats.land(s, human, engine, ev)
	else:
		TankSeats.swap(s, human, s.rider_at(s.station(engine).slot), ev)
	for r in s.riders:
		TankAux.of(s).seat_since[r.peer] = -1.0e9


func _far(s: TankState) -> void:
	TankFixturesV4._far(s, 91, TankIds.ENEMY_MEDIUM, 1200.0, 0)
	_targets(s)


func _near(s: TankState) -> void:
	TankFixturesV4._near(s, 92, TankIds.ENEMY_RECON, 60.0, 0)
	_targets(s)


func _need(s: TankState, engine: String) -> float:
	return float(TankBots.needs(s)[engine])


func _ask(s: TankState, r: TankRiderState) -> String:
	return str(TankBots.intent(s, r).get("to", ""))


## Runs the bots' clocks for `seconds` of game time (s.t moves, nothing else).
func _clock(s: TankState, seconds: float, events: Array[Dictionary] = []) -> void:
	TankBots.cover(s, events)
	s.t += seconds
	TankBots.cover(s, events)


# --- Row 1: rack low, a human on the Gun, the Loader empty ------------------------------------------


func test_a_low_rack_with_a_human_on_the_gun_calls_a_bot_to_the_loader() -> void:
	var s := _state(3)
	_human_on(s, GUN)
	_vacate(s, LOADER)
	TankStations.fill_rack(s, 1)
	assert_almost_eq(_need(s, LOADER), 5.5, 1e-9, "rack 1")
	TankStations.fill_rack(s, 0)
	assert_almost_eq(_need(s, LOADER), 5.5, 1e-9, "rack 0")
	var bot: TankRiderState = null
	for r in s.riders:
		if r.is_bot and r.engine != DRIVE:
			bot = r
	assert_not_null(bot, "a bot off Drive")
	assert_eq(TankBots.seat_wanted(s, bot), LOADER, "the bot goes and loads")
	assert_eq(_ask(s, bot), LOADER, "and asks for it")
	TankStations.fill_rack(s, 2)
	assert_lt(_need(s, LOADER), 5.5, "rack 2: no call")
	var drive := _state(3)
	TankStations.fill_rack(drive, 0)
	assert_lt(_need(drive, LOADER), 5.5, "a bot on the Gun: the row reads humans only")


func test_a_bot_already_loading_keeps_the_rows_score_and_stays() -> void:
	var s := _state(3)
	_human_on(s, GUN)
	TankStations.fill_rack(s, 1)
	_far(s)
	var loader := _bot(s, LOADER)
	assert_true(loader.is_bot)
	assert_almost_eq(_need(s, LOADER), 5.5, 1e-9, "the bot's own seat keeps the score")
	assert_eq(TankBots.seat_wanted(s, loader), LOADER, "it does not leave for the Lights' 5.0")


# --- Row 2: hull low ---------------------------------------------------------------------------------


func test_a_low_hull_calls_a_bot_to_repairs() -> void:
	var s := _state(4)
	assert_almost_eq(_need(s, REPAIR), 0.05, 1e-9, "a full hull")
	s.hull.hp = 60.0
	assert_almost_eq(_need(s, REPAIR), 0.05, 1e-9, "60%: not yet")
	s.hull.hp = 59.0
	assert_almost_eq(_need(s, REPAIR), 4.2, 1e-9, "below 60%")
	assert_eq(TankBots.seat_wanted(s, _bot(s, LIGHTS)), REPAIR, "the bot on the Lights goes")
	s.hull.hp = 34.0
	assert_almost_eq(_need(s, REPAIR), 5.6, 1e-9, "below 35%")
	assert_eq(TankBots.seat_wanted(s, _bot(s, GUN)), REPAIR, "now the Gun's bot would go too")


func test_a_tow_is_no_reason_to_repair() -> void:
	var s := _state(4)
	s.hull.hp = 0.0
	s.hull.tow_s = 4.0
	assert_almost_eq(_need(s, REPAIR), 0.05, 1e-9)
	assert_eq(TankBots.seat_wanted(s, _bot(s, LIGHTS)), LIGHTS)


# --- Row 3: a human on the Gun in band, no light --------------------------------------------------


func test_a_human_gunner_in_band_with_a_far_target_gets_the_lights() -> void:
	var s := _state(3)
	_human_on(s, GUN)
	_far(s)
	assert_almost_eq(_need(s, LIGHTS), 5.0, 1e-9)
	var bot := _bot(s, DRIVE)
	assert_eq(TankBots.seat_wanted(s, bot), DRIVE, "Drive's 5 keeps its bot: 5.0 is not 0.5 more")
	s.rider(HUMAN).in_band = false
	assert_lt(_need(s, LIGHTS), 5.0, "out of band: the light does not help yet")
	s.rider(HUMAN).in_band = true
	s.enemies.clear()
	_targets(s)
	assert_lt(_need(s, LIGHTS), 5.0, "no far target: no call")
	var other := _state(3)
	_far(other)
	assert_lt(_need(other, LIGHTS), 5.0, "a bot on the Gun: the row reads humans only")


func test_the_lights_call_moves_a_bot_off_a_lesser_seat() -> void:
	var s := _state(4)
	_human_on(s, GUN)
	var bot := _bot(s, LIGHTS)
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	_vacate(s, LIGHTS)
	TankSeats.land(s, bot, REPAIR, [] as Array[Dictionary])
	TankAux.of(s).seat_since[bot.peer] = -1.0e9
	_far(s)
	assert_eq(TankBots.seat_wanted(s, bot), LIGHTS)


# --- Row 4: a near threat ---------------------------------------------------------------------------


func test_a_near_threat_calls_a_bot_to_the_secondaries() -> void:
	var s := _state(4)
	assert_almost_eq(_need(s, FEED), 0.1, 1e-9)
	_near(s)
	assert_almost_eq(_need(s, FEED), 4.8, 1e-9)
	assert_eq(TankBots.seat_wanted(s, _bot(s, LIGHTS)), FEED, "the bot on the Lights goes")
	assert_ne(TankBots.seat_wanted(s, _bot(s, LOADER)), DRIVE, "never the human's seat")


func test_a_human_on_the_secondaries_needs_no_bot_there() -> void:
	var s := _state(3)
	_human_on(s, FEED)
	_near(s)
	assert_almost_eq(_need(s, FEED), 4.7, 1e-9, "the Autopilot's need, no row")
	for r in s.riders:
		if r.is_bot:
			assert_ne(TankBots.seat_wanted(s, r), FEED, "never a human's seat")


# --- Row 5: a human in rescue, or overworked on the Gun ---------------------------------------------


func test_a_human_in_rescue_gets_help_at_the_loader_or_the_lights() -> void:
	var s := _state(3)
	_vacate(s, LOADER)
	TankStations.fill_rack(s, 2)
	s.rider(HUMAN).rescue = true
	assert_almost_eq(_need(s, LOADER), 5.2, 1e-9, "the rack has room: the Loader")
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	assert_almost_eq(_need(s, LIGHTS), 5.0, 1e-9, "rack full: the Lights")
	s.rider(HUMAN).rescue = false
	assert_lt(_need(s, LIGHTS), 5.0, "out of the rescue: no call")


func test_a_human_overworked_on_the_gun_gets_help_after_15_s() -> void:
	var s := _state(3)
	_human_on(s, GUN)
	_vacate(s, LOADER)
	TankStations.fill_rack(s, 2)
	var human := s.rider(HUMAN)
	human.in_band = false
	_clock(s, 14.9)
	assert_false(TankBots.overworked(s, human), "14.9 s")
	assert_lt(_need(s, LOADER), 5.2)
	s.t += 0.1
	assert_true(TankBots.overworked(s, human), "15 s")
	assert_almost_eq(_need(s, LOADER), 5.2, 1e-9)
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	_vacate(s, LIGHTS)
	assert_almost_eq(_need(s, LIGHTS), 5.0, 1e-9, "rack full: the Lights")
	human.in_band = true
	TankBots.cover(s, [] as Array[Dictionary])
	assert_false(TankBots.overworked(s, human), "back in band: the clock is gone")


func test_the_overworked_clock_is_per_seat_and_only_in_work() -> void:
	var s := _state(3)
	_human_on(s, GUN)
	var human := s.rider(HUMAN)
	human.in_band = false
	_clock(s, 20.0)
	assert_true(TankBots.overworked(s, human))
	_human_on(s, LIGHTS)
	assert_false(TankBots.overworked(s, human), "another seat, another clock")
	_human_on(s, GUN)
	s.seg.kind = Wl.RECOVERY
	_clock(s, 20.0)
	assert_false(TankBots.overworked(s, human), "a checkpoint is no work")


# --- Row 6: a human overworked on the Loader ---------------------------------------------------------


func test_a_human_overworked_on_the_loader_raises_repairs_by_one() -> void:
	var s := _state(3)
	_human_on(s, LOADER)
	s.hull.hp = 50.0
	var human := s.rider(HUMAN)
	assert_almost_eq(_need(s, REPAIR), 4.2, 1e-9)
	human.in_band = false
	_clock(s, 15.0)
	assert_almost_eq(_need(s, REPAIR), 5.2, 1e-9, "the hull will pay for it")
	s.hull.hp = 100.0
	assert_almost_eq(_need(s, REPAIR), 1.05, 1e-9, "added to whatever it was")


# --- Row 7: cover -----------------------------------------------------------------------------------


func test_a_bot_covers_a_human_on_reserve_after_10_s() -> void:
	for seat: String in [DRIVE, GUN, LOADER]:
		var s := _state(4)
		_human_on(s, seat)
		_far(s)
		var human := s.rider(HUMAN)
		human.afk = true
		var ev: Array[Dictionary] = []
		_clock(s, 9.9, ev)
		assert_eq(human.engine, seat, "%s: 9.9 s" % seat)
		assert_eq(ev, [] as Array[Dictionary])
		s.t += 0.1
		TankBots.cover(s, ev)
		assert_ne(human.engine, seat, "%s: 10 s" % seat)
		assert_true(_bot(s, seat).is_bot, "%s: a bot on it now" % seat)
		assert_eq(TankAux.of(s).cover[HUMAN]["seat"], seat)
		assert_eq(ev.size(), 2, "two seat events")
		assert_eq(s.station(human.engine).slot, human.slot, "the stations follow")
		assert_eq(s.station(seat).slot, _bot(s, seat).slot)


func test_cover_takes_the_bot_on_the_least_needed_seat() -> void:
	var s := _state(4)
	s.rider(HUMAN).afk = true
	var by_lights := _bot(s, LIGHTS)
	_clock(s, 10.0)
	assert_eq(by_lights.engine, DRIVE, "the Lights' bot takes Drive")
	assert_eq(s.rider(HUMAN).engine, LIGHTS, "and the human holds the Lights")


func test_no_cover_in_a_warm_up_a_checkpoint_or_on_a_lesser_seat() -> void:
	var s := _state(4)
	s.rider(HUMAN).afk = true
	s.seg.kind = Wl.WARMUP
	_clock(s, 20.0)
	assert_eq(s.rider(HUMAN).engine, DRIVE, "a warm-up: no bot's mode switch")
	s.seg.kind = Wl.RECOVERY
	_clock(s, 20.0)
	assert_eq(s.rider(HUMAN).engine, DRIVE, "a checkpoint")
	var lights := _state(4)
	_human_on(lights, LIGHTS)
	lights.rider(HUMAN).afk = true
	_clock(lights, 20.0)
	assert_eq(lights.rider(HUMAN).engine, LIGHTS, "only Drive, Gun and Loader")
	var solo := _state(1)
	solo.rider(HUMAN).afk = true
	_clock(solo, 20.0)
	assert_eq(solo.rider(HUMAN).engine, DRIVE, "no bot")


func test_a_bot_on_a_more_needed_seat_does_not_leave_it_to_cover() -> void:
	var s := _state(2)
	_human_on(s, GUN)
	assert_eq(s.rider_at(s.station(DRIVE).slot).is_bot, true)
	s.rider(HUMAN).afk = true
	_clock(s, 20.0)
	assert_eq(s.rider(HUMAN).engine, GUN, "Drive (5) outranks a Gun with no target")


func test_two_humans_on_reserve_are_covered_by_two_bots() -> void:
	var s := _state(4)
	var second := s.riders[1]
	second.is_bot = false
	second.autopilot = false
	TankStations.fill_rack(s, TankConst.RACK_MAX)
	s.rider(HUMAN).afk = true
	second.connected = false
	_clock(s, 10.0)
	assert_eq(TankAux.of(s).cover.size(), 2, "a drop too")
	assert_true(_bot(s, DRIVE).is_bot)
	assert_true(_bot(s, GUN).is_bot)
	assert_ne(_bot(s, DRIVE), _bot(s, GUN), "two bots")


# --- The cover through the whole module: no effort change for the human --------------------------------


## TankGame on a clock: a human on Drive, three bots. It goes AFK 20 s into stage 1's Advance, a bot
## covers, it returns and lands back on Drive before the director runs: its plan was never touched.
func test_cover_causes_no_split_or_replan_for_the_human() -> void:
	var ctx := F.make_ctx(1, 3)
	ctx.players[0].autopilot = false
	var g: TankGame = autofree(F.make_game(ctx))
	g.state.rider(HUMAN).fallback = false
	var clock := F.clock_of(g)
	var tick := _play(g, clock, 0, 300.0 + 20.0)
	assert_eq(g.state.rider(HUMAN).engine, DRIVE)
	g.on_afk(HUMAN, true)
	tick = _play(g, clock, tick, 12.0)
	assert_ne(g.state.rider(HUMAN).engine, DRIVE, "a bot took Drive")
	assert_true(_bot(g.state, DRIVE).is_bot)
	g.on_afk(HUMAN, false)
	tick = _play(g, clock, tick, 1.0)
	assert_eq(g.state.rider(HUMAN).engine, DRIVE, "back on its seat")
	assert_eq(TankAux.of(g.state).cover, {})
	_play(g, clock, tick, 60.0)
	var dirs := ctx.directives as F.Directives
	assert_eq(_of_peer(dirs.splits, HUMAN), 0, "no split for the human")
	assert_eq(_of_peer(dirs.replans, HUMAN), 0, "no replan for the human")
	assert_gt(
		_of_peer(dirs.splits, -1) + _of_peer(dirs.replans, -1) + _bot_moves(dirs), 0, "bots did"
	)


## A human on Drive, covered: the grade the terrain gives it and its cadence band stay what they would
## be without the swap.
func test_cover_leaves_a_covered_humans_grade_and_band_alone() -> void:
	var ctx := F.make_ctx(1, 3)
	ctx.players[0].autopilot = false
	var g: TankGame = autofree(F.make_game(ctx))
	g.state.rider(HUMAN).fallback = false
	var clock := F.clock_of(g)
	var dirs := ctx.directives as F.Directives
	var tick := _play(g, clock, 0, 320.0)
	assert_eq(g.state.rider(HUMAN).engine, DRIVE)
	g.state.seg.length_m = 1.0e6
	g.on_afk(HUMAN, true)
	tick = _play(g, clock, tick, 12.0)
	assert_ne(g.state.rider(HUMAN).engine, DRIVE, "a bot took Drive")
	var seg := g.state.seg.segment_index
	# A stretch of road with a real grade, so a move's flat 0 cannot pass as the terrain's.
	g.state.hull.distance_m = _graded_road_m(g.content, seg)
	var seen := dirs.course_grades.size()
	var bands := dirs.cadence_bands.size()
	tick = _play(g, clock, tick, 6.0)
	var want := TankDirector.terrain_grade_pct(g.content, seg, g.state.hull.distance_m, false)
	assert_gte(absf(want), 1.0, "a graded stretch")
	var sent := 0
	for row: Array in dirs.course_grades.slice(seen):
		if int(row[0]) == HUMAN:
			sent += 1
			assert_almost_eq(float(row[1]), want, 0.5, "the terrain's grade, never a move's flat")
			assert_ne(float(row[1]), 0.0, "no flat grade for the covered human")
	assert_gt(sent, 0, "the terrain still sends")
	for row: Array in dirs.cadence_bands.slice(bands):
		assert_ne(int(row[0]), HUMAN, "no band change for the covered human")
	var ri := TankRiderInput.new()
	ri.peer = HUMAN
	ri.engine = DRIVE
	assert_false(TankDirector._waits_for_seat(g.state, ri), "never waits while covered")
	var row: Dictionary = TankAux.of(g.state).cover[HUMAN]
	TankAux.of(g.state).cover.erase(HUMAN)
	assert_true(TankDirector._waits_for_seat(g.state, ri), "a real seat move does")
	TankAux.of(g.state).cover[HUMAN] = row


## The swap lands the covered human on the Loader with a shell in the breech, the one seat that would send
## the Loader's band: nothing goes out until it is back.
func test_cover_on_the_loader_sends_no_band() -> void:
	var ctx := F.make_ctx(1, 3)
	ctx.players[0].autopilot = false
	var g: TankGame = autofree(F.make_game(ctx))
	g.state.rider(HUMAN).fallback = false
	var clock := F.clock_of(g)
	var dirs := ctx.directives as F.Directives
	var tick := _play(g, clock, 0, 320.0)
	g.on_afk(HUMAN, true)
	tick = _play(g, clock, tick, 12.0)
	assert_true(TankAux.of(g.state).cover.has(HUMAN), "covered")
	var ev: Array[Dictionary] = []
	var loader := _bot(g.state, LOADER)
	if loader != null:
		TankSeats.land(g.state, loader, TankSeats.empty_seats(g.state)[0], ev)
	TankSeats.land(g.state, g.state.rider(HUMAN), LOADER, ev)
	(g.state.station(LOADER) as TankSteamState).loaded = true
	var ri := TankRiderInput.new()
	ri.peer = HUMAN
	ri.phase_kind = Wl.WORK
	var bands := dirs.cadence_bands.size()
	g.director._loader_step(g.state, ri)
	assert_eq(dirs.cadence_bands.size(), bands, "no band for the covered human on the Loader")
	TankAux.of(g.state).cover.erase(HUMAN)
	g.director._loader_step(g.state, ri)
	assert_eq(dirs.cadence_bands.size(), bands + 1, "a real seat move does send it")


## The first metre of mission segment `seg` from which the next 150 m all read 1% or more one way.
func _graded_road_m(c: TankContent, seg: int) -> float:
	for d in range(0, 3000, 10):
		var lo := INF
		var hi := -INF
		for m in range(d, d + 150, 10):
			var g := TankDirector.terrain_grade_pct(c, seg, float(m), false)
			lo = minf(lo, g)
			hi = maxf(hi, g)
		if lo >= 1.0 or hi <= -1.0:
			return float(d)
	fail_test("no graded stretch in segment %d" % seg)
	return 0.0


## The critic's probe: a bot's cross-mode move late in a segment must not lengthen the human's phase. The
## bot takes a seat of the other mode 5 s before the segment's min_s and the objective is done at once:
## the human's phase still ends at the segment's min_s, by end_phase, nothing refused, no overrun.
func test_a_bots_seat_move_never_lengthens_a_humans_phase() -> void:
	var ctx := F.make_ctx(1, 3)
	ctx.players[0].autopilot = false
	var g: TankGame = autofree(F.make_game(ctx))
	g.state.rider(HUMAN).fallback = false
	var clock := F.clock_of(g)
	var tick := _play(g, clock, 0, 301.0)
	var seg_min := g.state.seg.min_s
	assert_gt(seg_min, 0.0, "an open Advance")
	var start := float(clock._at[HUMAN][1])
	tick = _play(g, clock, tick, seg_min - 6.0)
	var seg := g.state.seg.segment_index
	var bot := _bot(g.state, LOADER)
	assert_true(bot.is_bot)
	var target := ""
	for seat: String in TankSeats.empty_seats(g.state):
		if TankSeatPlan.seat_mode(g.content, seg, seat) == Wl.ERG:
			target = seat
	assert_ne(target, "", "an empty ERG seat")
	var ev: Array[Dictionary] = []
	TankSeats.land(g.state, bot, target, ev)
	var index := int(clock._at[HUMAN][0])
	tick = _play(g, clock, tick, 0.5)
	g.state.hull.distance_m = g.state.seg.length_m + 1.0
	tick = _play(g, clock, tick, 10.0)
	assert_gt(int(clock._at[HUMAN][0]), index, "the human's phase ended")
	var ended := {}
	for c: Dictionary in clock.changes:
		if int(c["peer"]) == HUMAN and int(c["index"]) == index + 1:
			ended = c
	assert_almost_eq(float(ended["t"]) - start, seg_min, 1.0, "at the segment's min_s")
	assert_eq(str(ended["ended_by"]), Wl.ENDED_END_PHASE, "not the platform's cut")
	assert_eq(g.state.score.overruns, 0, "no overrun")
	for b: Dictionary in clock.batches:
		assert_false(bool(b["refused"]), "every end_phase of the batch accepted")


## A bot never holds the segment's end, whatever min_s its own phase has (TankSegments.riders_may_end;
## TankSeatPlan's no_hold keeps such a phase from being sent at all). Forced here: the Loader bot's phase
## has a min_s 40 s past the segment's. The human's phase ends at the segment's min_s by end_phase, and the
## bot's end_phase comes at its own min_s, never refused.
func test_a_bots_own_min_s_never_lengthens_a_humans_phase() -> void:
	var ctx := F.make_ctx(1, 3)
	ctx.players[0].autopilot = false
	var g: TankGame = autofree(F.make_game(ctx))
	g.state.rider(HUMAN).fallback = false
	var clock := F.clock_of(g)
	var tick := _play(g, clock, 0, 301.0)
	var seg_min := g.state.seg.min_s
	var start := float(clock._at[HUMAN][1])
	tick = _play(g, clock, tick, seg_min - 6.0)
	var bot := _bot(g.state, LOADER)
	var at: Array = clock._at[bot.peer]
	var held := (clock.plans[bot.peer] as EffortPlan).phase(int(at[0]))
	assert_true(held.open_ended, "an open phase")
	held.min_s = tick * Wl.SIM_DT - float(at[1]) + 46.0
	var bot_index := int(at[0])
	var index := int(clock._at[HUMAN][0])
	g.state.hull.distance_m = g.state.seg.length_m + 1.0
	tick = _play(g, clock, tick, 10.0)
	assert_gt(int(clock._at[HUMAN][0]), index, "the human's phase ended")
	var ended := {}
	for c: Dictionary in clock.changes:
		if int(c["peer"]) == HUMAN and int(c["index"]) == index + 1:
			ended = c
	assert_almost_eq(float(ended["t"]) - start, seg_min, 1.0, "at the segment's min_s")
	assert_eq(str(ended["ended_by"]), Wl.ENDED_END_PHASE, "not the platform's cut")
	assert_eq(int(clock._at[bot.peer][0]), bot_index, "the bot's own min_s still runs")
	tick = _play(g, clock, tick, 42.0)
	assert_gt(int(clock._at[bot.peer][0]), bot_index, "its end_phase came at its own min_s")
	assert_eq(g.state.score.overruns, 0, "no overrun")
	for b: Dictionary in clock.batches:
		assert_false(bool(b["refused"]), "no end_phase refused")


func _bot_moves(dirs: F.Directives) -> int:
	return _of_peer(dirs.splits, -2) + _of_peer(dirs.replans, -2) + _of_peer(dirs.splits, -3)


func _of_peer(rows: Array, peer: int) -> int:
	return rows.filter(func(row: Array) -> bool: return int(row[0]) == peer).size()


## Steps the module `seconds` with the platform's merge of the bots' autopilot intents.
func _play(
	g: TankGame, clock: F.PhaseClock, from_tick: int, seconds: float, script: Callable = Callable()
) -> int:
	var tick := from_tick
	for _i in roundi(seconds / Wl.SIM_DT):
		var t := tick * Wl.SIM_DT
		clock.advance(t)
		(g.ctx.directives as F.Directives).t = t
		var intents := {}
		for p in g.ctx.players:
			if p.is_bot:
				intents[p.peer_id] = g.autopilot_intents(p.peer_id)
		if script.is_valid():
			var mine: Array = script.call(tick)
			if not mine.is_empty():
				intents[HUMAN] = mine
		g.sim_step(Wl.SIM_DT, F.frame(g.ctx, clock.plans, tick, 100.0, intents, clock))
		tick += 1
	return tick


# --- A human's move always wins ---------------------------------------------------------------------


func _request(s: TankState, peer: int, want: String, step: int = 0) -> Array[Dictionary]:
	var ri := TankRiderInput.new()
	ri.peer = peer
	ri.phase_kind = Wl.WORK
	var ev: Array[Dictionary] = []
	TankSeats.request(s, ri, s.rider(peer), want, step, ev)
	return ev


func test_a_human_takes_a_bots_seat_and_the_bot_lands_on_the_most_needed_empty_seat() -> void:
	var s := _state(4)
	s.hull.hp = 50.0
	var bot := _bot(s, GUN)
	var ev := _request(s, HUMAN, GUN)
	assert_eq(s.rider(HUMAN).engine, GUN, "the human landed")
	assert_eq(bot.engine, REPAIR, "the bot went where it is most needed (the hull)")
	assert_eq(s.station(GUN).slot, s.rider(HUMAN).slot)
	assert_eq(s.station(REPAIR).slot, bot.slot)
	assert_true(s.station(DRIVE).is_empty(), "the human's old seat is free")
	assert_eq(ev.size(), 2, "both raise seat")
	assert_eq(int(ev[0]["s"]), bot.slot, "the bot first")
	assert_eq(int(ev[1]["s"]), s.rider(HUMAN).slot, "then the human")


func test_a_bot_never_takes_a_seat_someone_holds() -> void:
	var s := _state(4)
	var bot := _bot(s, GUN)
	assert_eq(_request(s, bot.peer, DRIVE), [] as Array[Dictionary], "a human's")
	assert_eq(bot.engine, GUN)
	assert_eq(_request(s, bot.peer, LOADER), [] as Array[Dictionary], "another bot's")
	assert_eq(bot.engine, GUN)
	assert_eq(_request(s, bot.peer, FEED).size(), 1, "an empty one")
	assert_eq(bot.engine, FEED)


func test_a_human_never_evicts_another_human() -> void:
	var s := _state(4)
	var other := s.riders[1]
	other.is_bot = false
	assert_eq(_request(s, HUMAN, GUN), [] as Array[Dictionary])
	assert_eq(s.rider(HUMAN).engine, DRIVE)
	assert_eq(other.engine, GUN)


func test_next_and_prev_step_a_human_onto_a_bots_seat_and_a_bot_past_it() -> void:
	var s := _state(4)
	assert_eq(TankSeats.next_free(s, s.rider(HUMAN), 1), GUN, "the bot's seat counts as free")
	assert_eq(TankSeats.next_free(s, _bot(s, GUN), 1), FEED, "for a bot it does not")
	_request(s, HUMAN, "", 0)
	assert_eq(s.rider(HUMAN).engine, DRIVE, "no ask")
	assert_eq(_request(s, HUMAN, GUN, 1).size(), 2)
	assert_eq(s.rider(HUMAN).engine, GUN)


# --- The bot's own gates --------------------------------------------------------------------------


func test_a_bot_stays_30_s_and_asks_only_for_an_empty_seat() -> void:
	var s := _state(4)
	s.hull.hp = 50.0
	var bot := _bot(s, LIGHTS)
	assert_eq(_ask(s, bot), REPAIR)
	var out := TankBots.intent(s, bot)
	assert_true(TankIntents.normalize(out)["auto"], "tagged auto")
	TankAux.of(s).seat_since[bot.peer] = s.t - 29.0
	assert_eq(_ask(s, bot), "", "29 s on the seat")
	TankAux.of(s).seat_since[bot.peer] = s.t - TankBots.BOT_STAY_S
	assert_eq(_ask(s, bot), REPAIR, "30 s")
	var other := _bot(s, GUN)
	TankSeats.land(s, other, REPAIR, [] as Array[Dictionary])
	assert_ne(_ask(s, bot), REPAIR, "held now")


func test_seat_intent_asks_a_bot_through_tank_bots_once_a_second() -> void:
	var s := _state(4)
	s.hull.hp = 50.0
	var bot := _bot(s, LIGHTS)
	assert_eq(str(TankAutopilot.seat_intent(s, bot)["to"]), REPAIR)
	s.tick += 1
	assert_eq(TankAutopilot.seat_intent(s, bot), {}, "off the second")
	s.tick += TankAutopilot.SEAT_EVERY_TICKS - 1
	assert_eq(str(TankAutopilot.seat_intent(s, bot)["to"]), REPAIR)
	TankAux.of(s).seat_since[bot.peer] = s.t - 40.0
	assert_eq(
		str(TankAutopilot.seat_intent(s, bot)["to"]), REPAIR, "40 s: a crew's 60 s is not its"
	)
	bot.connected = false
	assert_eq(TankAutopilot.seat_intent(s, bot), {})


## A cross-mode move its trainer could not follow at once waits: a bot's trainer never waits in a fight.
func test_in_a_fight_a_bot_moves_only_where_its_trainer_follows_at_once() -> void:
	var s := _state(4)
	var h := preload("res://tests/games/tank/effort/tank_effort_harness.gd").new()
	h.build(4)
	var ri: TankRiderInput = h.inputs(2, 10.0, 310.0).riders[3]
	s.hull.hp = 50.0
	var bot := _bot(s, LIGHTS)
	ri.peer = bot.peer
	ri.phase_mode = Wl.ERG
	TankAux.of(s).seat_input[bot.peer] = ri
	TankAux.of(s).last_switch_s[bot.peer] = s.t - 5.0
	s.hull.hp = 100.0
	_near(s)
	assert_eq(TankBots.seat_wanted(s, bot), FEED, "it wants the Secondaries (SIM)")
	assert_eq(_ask(s, bot), "", "from the Lights (ERG), 5 s after a switch: it stays")
	TankAux.of(s).last_switch_s[bot.peer] = s.t - 60.0
	assert_eq(_ask(s, bot), FEED, "60 s after: it goes")


func test_a_bot_never_switches_mode_in_a_warm_up() -> void:
	var s := _state(4)
	_near(s)
	var bot := _bot(s, LIGHTS)
	var ri := TankRiderInput.new()
	ri.peer = bot.peer
	ri.phase_kind = Wl.WARMUP
	ri.phase_mode = Wl.ERG
	TankAux.of(s).seat_input[bot.peer] = ri
	TankAux.of(s).trainer_mode[bot.peer] = Wl.ERG
	assert_eq(_ask(s, bot), "", "ERG to SIM in a warm-up")
	ri.phase_kind = Wl.WORK
	assert_eq(_ask(s, bot), FEED, "in a fight")


func test_in_a_checkpoint_a_bot_plans_for_the_next_fight() -> void:
	var s := _state(3)
	_human_on(s, GUN)
	TankStations.fill_rack(s, 1)
	s.seg.seg = TankIds.SEG_CHECKPOINT
	_vacate(s, LOADER)
	var bot := _bot(s, DRIVE)
	assert_true(TankBots._plans_ahead(s))
	var wants := TankBots.seat_wanted(s, bot)
	assert_eq(wants, LOADER, "the human will fire: the rack comes first")
	assert_eq(_ask(s, bot), LOADER, "no fight here: nothing to follow at once")


# --- Enemy count with bots, and a bot-free crew untouched ---------------------------------------------


func test_enemy_counts_scale_with_the_crew_including_bots() -> void:
	var specs: Array = [{"enemy": "medium", "count": 6}]
	var solo := TankFixtures.state(1)
	var humans := TankFixtures.state(4)
	var mixed := _state(4)
	var counts := TankEncounters.crew_counts(mixed, specs)
	assert_eq(counts, TankEncounters.crew_counts(humans, specs), "a bot counts like a human")
	assert_gt(int(counts[0]), int(TankEncounters.crew_counts(solo, specs)[0]), "and more than solo")
	var ctx := F.make_ctx(1, 3)
	var g: TankGame = autofree(F.make_game(ctx))
	assert_eq(g.state.crew, 4, "state.crew counts bots")


func test_a_crew_of_humans_never_sees_a_cover_or_a_bots_row() -> void:
	var s := _state(4)
	for r in s.riders:
		r.is_bot = false
	s.rider(HUMAN).afk = true
	_clock(s, 60.0)
	assert_eq(TankAux.of(s).cover, {})
	assert_eq(s.rider(HUMAN).engine, DRIVE)


func test_bot_state_is_never_on_the_wire() -> void:
	var s := _state(4)
	s.rider(HUMAN).in_band = false
	_clock(s, 20.0)
	var snap := TankSnapshot.encode(s)
	assert_false(JSON.stringify(snap).contains(TankBots.META), "host-only")


# --- 30 minutes with a scripted human ------------------------------------------------------------------


## The human moves every 45 s to the next seat, bot-held or not. Every tick: a bot is never on the human's
## seat, one rider a seat, the stations and the riders agree. Each bot's real ERG <-> SIM switches are 30 s
## or more apart (BRIEF 4.5), and every plan it sent passed the PlanValidator.
func test_30_minutes_with_a_scripted_human() -> void:
	var ctx := F.make_ctx(1, 3)
	ctx.players[0].autopilot = false
	var g: TankGame = autofree(F.make_game(ctx))
	g.state.rider(HUMAN).fallback = false
	var clock := F.clock_of(g)
	var moves: Array[int] = [0]
	var human_events: Array = [0]
	g.cue.connect(
		func(kind: String, data: Dictionary) -> void:
			if kind == TankEvents.SEAT and int(data["s"]) == 0:
				human_events[0] += 1
	)
	var script := func(tick: int) -> Array:
		if tick % roundi(45.0 / Wl.SIM_DT) != 450 or g.state.in_cooldown():
			return []
		moves[0] += 1
		return [TankIntents.seat("next")]
	var tick := 0
	var bad := 0
	for _s in 1800:
		tick = _play(g, clock, tick, 1.0, script)
		bad += _seat_errors(g.state)
	assert_eq(bad, 0, "no two riders on a seat, a station and its rider agree")
	assert_gt(moves[0], 20, "the human moved, to the cool-down")
	assert_eq(human_events[0], moves[0], "every move landed, and bots moved the human never")
	for row: Dictionary in clock.replan_log:
		if int(row["peer"]) < 0:
			assert_true(bool(row["ok"]), "bot plan %s" % str(row["errors"]))
	for p in ctx.players:
		if p.is_bot:
			assert_gte(_min_switch_gap(clock, p.peer_id), 30.0 - 1e-6, "peer %d" % p.peer_id)


## The human never moves: 30 minutes of bots adapting around it, and no split or replan for the human.
func test_30_minutes_of_bots_never_change_a_still_humans_plan() -> void:
	var ctx := F.make_ctx(1, 3)
	ctx.players[0].autopilot = false
	var g: TankGame = autofree(F.make_game(ctx))
	g.state.rider(HUMAN).fallback = false
	var clock := F.clock_of(g)
	_play(g, clock, 0, 1800.0)
	var dirs := ctx.directives as F.Directives
	assert_eq(_of_peer(dirs.splits, HUMAN), 0)
	assert_eq(_of_peer(dirs.replans, HUMAN), 0)
	assert_eq(g.state.rider(HUMAN).engine, DRIVE, "nobody moved the human")


func _seat_errors(s: TankState) -> int:
	var bad := 0
	var seen := {}
	for r in s.riders:
		if seen.has(r.engine):
			bad += 1
		seen[r.engine] = true
		var st := s.station(r.engine)
		if st == null or st.slot != r.slot or st.peer != r.peer:
			bad += 1
	for st in s.stations:
		if st.slot >= 0 and s.rider_at(st.slot).engine != st.engine:
			bad += 1
	return bad


## The shortest time between two real ERG <-> SIM switches of `peer` on the clock's phase changes.
func _min_switch_gap(clock: F.PhaseClock, peer: int) -> float:
	var plan: EffortPlan = clock.plans[peer]
	var last := -INF
	var gap := INF
	var mode := ""
	for c: Dictionary in clock.changes:
		if int(c["peer"]) != peer or int(c["index"]) >= plan.size():
			continue
		var m := plan.phase(int(c["index"])).mode
		if mode != "" and m != mode:
			gap = minf(gap, float(c["t"]) - last)
			last = float(c["t"])
		mode = m
	return gap
