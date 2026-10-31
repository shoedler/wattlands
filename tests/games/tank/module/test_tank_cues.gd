extends GutTest
## Prompts, toasts and banners are per peer (brief 2.6): each peer raises its own rider's, the host
## through ctx.local_peer, a client from apply_event / apply_snapshot, nothing for another rider
## and nothing broadcast.

const F := preload("res://tests/games/tank/tank_fakes.gd")


func _ctx(crew: int, local: int, role: String = Wl.HOST) -> GameContext:
	return F.make_ctx(crew, 0, "ashfall_road", role, local)


func _toasts(ctx: GameContext) -> Array:
	return (ctx.hud as F.Hud).of("toast")


func _banners(ctx: GameContext) -> Array:
	return (ctx.hud as F.Hud).of("banner")


func _keys(calls: Array) -> Array:
	return calls.map(func(c: Array) -> String: return str(c[1]))


## The rider on `engine` in the fixture state.
func _peer_of(state: TankState, engine: String) -> int:
	for r in state.riders:
		if r.engine == engine:
			return r.peer
	return 0


## Sets every enemy's telegraph to `seconds` (the fixture's destroyer is the one telegraphing).
func _telegraph(state: TankState, seconds: float) -> void:
	for e in state.enemies:
		e.telegraph_s = seconds if e.code == TankIds.enemy_code(TankIds.ENEMY_DESTROYER) else 0.0


# --- prompt_of ----------------------------------------------------------------------------------------


func test_the_evade_prompt_follows_the_telegraph_and_the_riders_own_flag() -> void:
	var s := TankFixtures.state(3)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	var steam_peer := _peer_of(s, TankIds.ENGINE_STEAM)
	var dyn_peer := _peer_of(s, TankIds.ENGINE_DYNAMO)
	_telegraph(s, 0.0)
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_NONE)
	_telegraph(s, 2.5)
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_EVADE)
	assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_EVADE, "steam is SIM too")
	assert_eq(TankCues.prompt_of(s, s.rider(dyn_peer)), TankCues.PROMPT_NONE, "an ERG rider")
	s.rider(diesel_peer).can_evade = false
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_NONE, "its own flag")
	_telegraph(s, 0.0)
	s.boss.telegraph_s = 4.0
	assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_EVADE, "the Behemoth")
	s.boss.telegraph_s = 0.0
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 3.0
	assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_OVER)
	_telegraph(s, 1.0)
	assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_EVADE, "evade first")
	_telegraph(s, 0.0)
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 0.0
	assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_NONE)


func test_no_sprint_prompt_outside_work_phases_or_when_the_rider_cannot_act() -> void:
	var s := TankFixtures.state(3)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	_telegraph(s, 2.5)
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 4.0
	var steam_peer := _peer_of(s, TankIds.ENGINE_STEAM)
	for kind in [Wl.WARMUP, Wl.RECOVERY, Wl.COOLDOWN, ""]:
		s.seg.kind = kind
		assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_NONE, kind)
		assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_NONE, kind)
	s.seg.kind = Wl.WORK
	s.rider(diesel_peer).afk = true
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_NONE, "AFK")
	s.rider(diesel_peer).afk = false
	s.rider(diesel_peer).rescue = true
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_NONE, "in a rescue hold")
	assert_eq(TankCues.prompt_of(null, null), TankCues.PROMPT_NONE)


func test_the_solo_driver_evades_like_any_diesel_rider() -> void:
	var s := TankFixtures.state(1)
	_telegraph(s, 0.0)
	assert_eq(TankCues.prompt_of(s, s.rider(1)), TankCues.PROMPT_NONE)
	_telegraph(s, 2.0)
	assert_eq(TankCues.prompt_of(s, s.rider(1)), TankCues.PROMPT_EVADE)
	s.seg.seg = TankIds.SEG_BOSS
	_telegraph(s, 0.0)
	s.boss.telegraph_s = 5.0
	assert_eq(TankCues.prompt_of(s, s.rider(1)), TankCues.PROMPT_EVADE)


# --- the host raises only its own ------------------------------------------------------------------------


func test_the_host_toasts_its_own_riders_prompt_with_its_own_peer() -> void:
	var s := TankFixtures.state(3)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	_telegraph(s, 2.5)
	var host_ctx := _ctx(3, diesel_peer)
	var cues := TankCues.new(host_ctx)
	cues.on_state(s)
	assert_eq(_keys(_toasts(host_ctx)), ["TANK_PROMPT_EVADE"])
	assert_eq(_toasts(host_ctx)[0][3], diesel_peer, "drawn on the host only, never broadcast")
	var other_ctx := _ctx(3, _peer_of(s, TankIds.ENGINE_DYNAMO))
	TankCues.new(other_ctx).on_state(s)
	assert_eq(_toasts(other_ctx), [], "the dynamo rider (ERG) cannot evade: no prompt")


func test_a_prompt_comes_up_once_and_again_after_it_went_away() -> void:
	var s := TankFixtures.state(1)
	var ctx := _ctx(1, 1, Wl.SOLO)
	var cues := TankCues.new(ctx)
	_telegraph(s, 0.0)
	cues.on_state(s)
	assert_eq(_toasts(ctx), [])
	_telegraph(s, 2.5)
	for _i in 5:
		cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_PROMPT_EVADE"], "once while it stays up")
	_telegraph(s, 0.0)
	cues.on_state(s)
	_telegraph(s, 2.5)
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_PROMPT_EVADE", "TANK_PROMPT_EVADE"])
	s.rider(1).can_evade = false
	cues.on_state(s)
	assert_eq(_toasts(ctx).size(), 2, "it went away: nothing more to say")


func test_the_steam_overpressure_prompt() -> void:
	var s := TankFixtures.state(3)
	var steam_peer := _peer_of(s, TankIds.ENGINE_STEAM)
	var ctx := _ctx(3, steam_peer)
	var cues := TankCues.new(ctx)
	_telegraph(s, 0.0)
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 5.0
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_PROMPT_OVER"])


func test_the_dynamo_stalled_toast_goes_to_the_whole_crew_once() -> void:
	var s := TankFixtures.state(3)
	_telegraph(s, 0.0)
	var peers := [
		_peer_of(s, TankIds.ENGINE_DIESEL),
		_peer_of(s, TankIds.ENGINE_DYNAMO),
		_peer_of(s, TankIds.ENGINE_STEAM)
	]
	var ctxs: Array[GameContext] = []
	var cues: Array[TankCues] = []
	for p: int in peers:
		var c := _ctx(3, p)
		ctxs.append(c)
		cues.append(TankCues.new(c))
		cues[-1].on_state(s)
	(s.station(TankIds.ENGINE_DYNAMO) as TankDynamoState).stalled = true
	for i in 3:
		cues[i].on_state(s)
		cues[i].on_state(s)
		assert_eq(_keys(_toasts(ctxs[i])), ["TANK_TOAST_DYNAMO_STALLED"], "peer %d" % peers[i])


func test_a_rescue_hold_staggers_its_own_rider_and_stalls_the_dynamo() -> void:
	var s := TankFixtures.state(3)
	_telegraph(s, 0.0)
	var dyn_peer := _peer_of(s, TankIds.ENGINE_DYNAMO)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	var ctx := _ctx(3, diesel_peer)
	var cues := TankCues.new(ctx)
	cues.on_state(s)
	s.rider(dyn_peer).rescue = true
	cues.on_state(s)
	assert_eq(
		_keys(_toasts(ctx)), ["TANK_TOAST_DYNAMO_STALLED"], "the crew sees the stall, not a stagger"
	)
	s.rider(dyn_peer).rescue = false
	cues.on_state(s)
	s.rider(diesel_peer).rescue = true
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx))[-1], "TANK_TOAST_STAGGER", "and its own rescue is a stagger")
	var dyn_ctx := _ctx(3, dyn_peer)
	var dyn_cues := TankCues.new(dyn_ctx)
	s.rider(diesel_peer).rescue = false
	dyn_cues.on_state(s)
	s.rider(dyn_peer).rescue = true
	dyn_cues.on_state(s)
	assert_eq(
		_keys(_toasts(dyn_ctx)), ["TANK_TOAST_DYNAMO_STALLED"], "no stagger on top of the stall"
	)


func test_the_arc_stalled_toast_goes_to_the_whole_crew_once() -> void:
	var s := TankFixtures.state(4)
	_telegraph(s, 0.0)
	var arc_peer := _peer_of(s, TankIds.ENGINE_ARC)
	var ctxs: Array[GameContext] = []
	var cues: Array[TankCues] = []
	for r in s.riders:
		var c := _ctx(4, r.peer)
		ctxs.append(c)
		cues.append(TankCues.new(c))
		cues[-1].on_state(s)
	s.rider(arc_peer).rescue = true
	for i in ctxs.size():
		cues[i].on_state(s)
		cues[i].on_state(s)
		assert_eq(_keys(_toasts(ctxs[i])), ["TANK_TOAST_ARC_STALLED"], "slot %d" % i)
	s.rider(arc_peer).rescue = false
	(s.station(TankIds.ENGINE_ARC) as TankArcState).stalled = true
	cues[0].on_state(s)
	assert_eq(_toasts(ctxs[0]).size(), 1, "still the same stall")


func test_regroup_is_said_once_when_the_objective_is_met_before_min_s() -> void:
	var s := TankFixtures.state(1)
	_telegraph(s, 0.0)
	var ctx := _ctx(1, 1, Wl.SOLO)
	var cues := TankCues.new(ctx)
	s.seg.regroup = true
	cues.on_state(s)
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_TOAST_REGROUP"])


# --- events --------------------------------------------------------------------------------------------


func test_event_cues_for_the_local_rider() -> void:
	var s := TankFixtures.state(3)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	var me := s.rider(diesel_peer)
	var other := s.rider(_peer_of(s, TankIds.ENGINE_DYNAMO))
	var ctx := _ctx(3, diesel_peer)
	var cues := TankCues.new(ctx)
	cues.on_event(s, TankEvents.evade(13, 3, true, other.slot))
	cues.on_event(s, TankEvents.evade(13, 3, false))
	cues.on_event(s, TankEvents.latch(other.slot, TankIds.SHELL_HEAVY))
	cues.on_event(s, TankEvents.latch(me.slot, TankIds.SHELL_HEAVY))
	cues.on_event(s, TankEvents.breakdown())
	cues.on_event(s, TankEvents.repaired(40.0))
	assert_eq(
		_keys(_toasts(ctx)),
		[
			"TANK_TOAST_EVADED",
			"TANK_TOAST_LOADED_HEAVY",
			"TANK_TOAST_BREAKDOWN",
			"TANK_TOAST_REPAIRED"
		],
		"an evaded shot is good news for the whole crew; another rider's latch is not ours"
	)
	assert_eq(_toasts(ctx)[3][2], [40])
	for t: Array in _toasts(ctx):
		assert_eq(t[3], diesel_peer)


func test_latch_toasts_name_the_shell() -> void:
	var s := TankFixtures.state(3)
	var steam_peer := _peer_of(s, TankIds.ENGINE_STEAM)
	var ctx := _ctx(3, steam_peer)
	var cues := TankCues.new(ctx)
	var slot := s.rider(steam_peer).slot
	for shell in [
		TankIds.SHELL_LIGHT, TankIds.SHELL_HEAVY, TankIds.SHELL_OVER, TankIds.SHELL_ENEMY
	]:
		cues.on_event(s, TankEvents.latch(slot, shell))
	assert_eq(
		_keys(_toasts(ctx)),
		["TANK_TOAST_LOADED_LIGHT", "TANK_TOAST_LOADED_HEAVY", "TANK_TOAST_OVERPRESSURE"]
	)


func test_overrun_and_boss_events() -> void:
	var s := TankFixtures.state(1)
	var ctx := _ctx(1, 1, Wl.SOLO)
	var cues := TankCues.new(ctx)
	cues.on_event(s, TankEvents.overrun(TankIds.SEG_ADVANCE, 1))
	cues.on_event(s, TankEvents.overrun(TankIds.SEG_GUN_LINE, 1))
	cues.on_event(s, TankEvents.overrun(TankIds.SEG_BOSS, 4))
	assert_eq(
		_keys(_toasts(ctx)),
		[
			"TANK_TOAST_OVERRUN_ADVANCE",
			"TANK_TOAST_OVERRUN_GUN_LINE",
			"TANK_TOAST_BEHEMOTH_WITHDRAWS"
		]
	)
	for phase in [
		TankIds.BOSS_PHASE_1, TankIds.BOSS_PHASE_2, TankIds.BOSS_DEAD, TankIds.BOSS_WITHDRAWN
	]:
		cues.on_event(s, TankEvents.boss_phase(phase))
	assert_eq(
		_keys(_banners(ctx)),
		[
			"TANK_BANNER_BOSS",
			"TANK_BANNER_BOSS_PHASE2",
			"TANK_BANNER_VICTORY",
			"TANK_BANNER_WITHDRAWN"
		]
	)
	cues.on_event(s, TankEvents.boss_phase(TankIds.BOSS_NONE))
	assert_eq(_banners(ctx).size(), 4)


func test_a_segment_event_banners_the_segments_label() -> void:
	var s := TankFixtures.state(1)
	var ctx := _ctx(1, 1, Wl.SOLO)
	var cues := TankCues.new(ctx)
	cues.on_event(s, TankEvents.segment(4, TankIds.SEG_ADVANCE, 2))
	var b: Array = _banners(ctx)[0]
	assert_eq([b[1], b[4]], ["TANK_BANNER_SEGMENT", 1])
	assert_eq(b[2], [ctx.strings.t("TANK_PHASE_ADVANCE_2")])
	cues.on_event(s, TankEvents.segment(99, TankIds.SEG_COOLDOWN, 0))
	assert_eq(_banners(ctx).size(), 1, "the cool-down has no label of Tank's")


func test_a_seat_event_names_the_riders_new_seat_to_that_rider_only() -> void:
	var s := TankFixtures.state(3)
	var ctx := _ctx(3, 2)
	var cues := TankCues.new(ctx)
	var me := s.rider(2)
	cues.on_event(s, TankEvents.seat(me.slot + 1, TankIds.ENGINE_DIESEL, TankIds.ENGINE_ARC))
	assert_eq(_toasts(ctx).size(), 0, "another rider's move")
	cues.on_event(s, TankEvents.seat(me.slot, me.engine, TankIds.ENGINE_FEED))
	assert_eq(_keys(_toasts(ctx)), ["TANK_TOAST_SEAT"])
	assert_eq(_toasts(ctx)[0][2], [ctx.strings.t("TANK_SEAT_SECONDARIES")], "slot %d" % me.slot)


# --- through the module ------------------------------------------------------------------------------------


func test_a_clients_snapshot_raises_only_its_own_prompt() -> void:
	var host_ctx := F.make_ctx(3)
	var host: TankGame = autofree(F.make_game(host_ctx))
	host.state = TankFixtures.state(3)
	host.state.content = host.content
	var dyn_peer := _peer_of(host.state, TankIds.ENGINE_DYNAMO)
	_telegraph(host.state, 2.5)
	var wire: Variant = JSON.parse_string(JSON.stringify(host.snapshot()))
	wire = Protocol.apply_int_fields(wire, host.int_fields()["snapshot"])
	var made := {}
	for peer in [1, 2, 3]:
		var ctx := F.make_ctx(3, 0, "ashfall_road", Wl.CLIENT, peer)
		var client: TankGame = autofree(F.make_game(ctx))
		client.apply_snapshot(wire)
		client.apply_snapshot(wire)
		made[peer] = _keys(_toasts(ctx))
	for peer in [1, 2, 3]:
		var want := [] if peer == dyn_peer else ["TANK_PROMPT_EVADE"]
		assert_eq(made[peer], want, "peer %d: its own rider's flag from the snapshot" % peer)


func test_a_clients_events_raise_its_own_cues() -> void:
	var ctx := F.make_ctx(1, 0, "ashfall_road", Wl.CLIENT, 1)
	var client: TankGame = autofree(F.make_game(ctx))
	client.apply_event(JSON.parse_string(JSON.stringify(TankEvents.evade(4, 3, true, 0))))
	client.apply_event(JSON.parse_string(JSON.stringify(TankEvents.breakdown())))
	assert_eq(_keys(_toasts(ctx)), ["TANK_TOAST_EVADED", "TANK_TOAST_BREAKDOWN"])


func test_a_full_session_never_broadcasts_a_toast_or_banner() -> void:
	var ctx := F.make_ctx(3, 0, "ashfall_road", Wl.HOST, 1)
	var g: TankGame = autofree(F.make_game(ctx))
	var clock := F.clock_of(g)
	F.run_session(g, clock, 1.0)
	var all: Array = _toasts(ctx) + _banners(ctx)
	assert_gt(all.size(), 5, "segment banners at least")
	for c: Array in all:
		assert_eq(c[c.size() - 1], 1, "%s is for the host's own rider (peer 1)" % c[1])
	var banner_keys := _keys(_banners(ctx))
	assert_eq(
		banner_keys.filter(func(k: String) -> bool: return k == "TANK_BANNER_SEGMENT").size(), 11
	)


func test_a_rider_going_to_reserve_is_said_once_and_the_first_call_only_records() -> void:
	var s := TankFixtures.state(3)
	# No telegraph: peer 1 sits on Drive (v3) and would get its "Surge to evade" prompt.
	s.enemies.clear()
	s.rider(3).afk = true
	var ctx := _ctx(3, 1)
	var cues := TankCues.new(ctx)
	cues.on_state(s)
	assert_eq(_toasts(ctx), [], "already on reserve when we joined: not news")
	s.rider(2).afk = true
	cues.on_state(s)
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_TOAST_RESERVE"])
	assert_eq(_toasts(ctx)[0][2], [ctx.player(2).name])
	s.rider(2).afk = false
	cues.on_state(s)
	s.rider(2).connected = false
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_TOAST_RESERVE", "TANK_TOAST_RESERVE"], "a drop too")


func test_no_power_is_said_when_every_rider_is_away() -> void:
	var s := TankFixtures.state(2)
	var ctx := _ctx(2, 1)
	var cues := TankCues.new(ctx)
	cues.on_state(s)
	for r in s.riders:
		r.afk = true
	s.all_afk = true
	cues.on_state(s)
	assert_has(_keys(_toasts(ctx)), "TANK_TOAST_ALL_AFK")
	assert_eq(_keys(_toasts(ctx)).count("TANK_TOAST_RESERVE"), 2)
	var n := _toasts(ctx).size()
	cues.on_state(s)
	assert_eq(_toasts(ctx).size(), n, "once")


# --- v4 ----------------------------------------------------------------------------------------------


func test_the_v4_events_toast_the_whole_crew_once_each() -> void:
	for local in [1, 2]:
		var s := TankFixtures.state(2)
		var ctx := _ctx(2, local)
		var cues := TankCues.new(ctx)
		cues.on_event(s, TankEvents.stage_restart(TankIds.SEG_ADVANCE, 2, 84.0))
		cues.on_event(s, TankEvents.ambush(41, TankIds.enemy_code(TankIds.ENEMY_RECON)))
		cues.on_event(s, TankEvents.escaped(41, TankIds.enemy_code(TankIds.ENEMY_RECON)))
		assert_eq(
			_keys(_toasts(ctx)),
			["TANK_TOAST_RESTART", "TANK_TOAST_AMBUSH", "TANK_TOAST_ESCAPED"],
			"peer %d" % local
		)
		for c: Array in _toasts(ctx):
			assert_eq(c[3], local, "drawn for the local rider only")
		assert_eq(_banners(ctx), [], "no platform banner: the HUD's plate shows TANK LOST")


func test_every_v4_toast_key_is_a_real_string() -> void:
	var csv := FileAccess.get_file_as_string("res://content/tank/strings.csv")
	for key in ["TANK_TOAST_RESTART", "TANK_TOAST_AMBUSH", "TANK_TOAST_ESCAPED"]:
		assert_true(csv.contains(key + ","), key)


func test_tank_lost_raises_no_toast_of_its_own() -> void:
	var s := TankFixtures.state(2)
	var ctx := _ctx(2, 1)
	var cues := TankCues.new(ctx)
	cues.on_event(s, TankEvents.tank_lost(1, TankIds.SEG_ADVANCE, 2))
	assert_eq(_toasts(ctx), [])


## "Surge to evade" holds through the flight: a surge can still make an evadable shell miss.
func test_an_evadable_shell_in_the_air_keeps_the_evade_prompt() -> void:
	var s := TankFixtures.state(3)
	s.enemies.clear()
	s.shells.clear()
	var peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	s.rider(peer).can_evade = true
	assert_false(TankCues.telegraph_running(s))
	var shell := TankShellState.new()
	shell.far = true
	shell.left_s = 2.0
	s.shells.append(shell)
	assert_false(TankCues.telegraph_running(s), "not evadable")
	shell.evadable = true
	assert_true(TankCues.telegraph_running(s))
	assert_eq(TankCues.prompt_of(s, s.rider(peer)), TankCues.PROMPT_EVADE)
	shell.left_s = 0.0
	assert_false(TankCues.telegraph_running(s), "landed")
