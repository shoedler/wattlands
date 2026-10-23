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


func _diesel(state: TankState) -> TankDieselState:
	for st in state.stations:
		if st is TankDieselState:
			return st as TankDieselState
	return null


# --- prompt_of ----------------------------------------------------------------------------------------


func test_the_prompt_follows_the_station_and_the_segment() -> void:
	var s := TankFixtures.state(3)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	var steam_peer := _peer_of(s, TankIds.ENGINE_STEAM)
	var dyn_peer := _peer_of(s, TankIds.ENGINE_DYNAMO)
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_NONE)
	_diesel(s).prompt = true
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_RAM)
	assert_eq(TankCues.prompt_of(s, s.rider(dyn_peer)), TankCues.PROMPT_NONE, "not the dynamo's")
	s.seg.seg = TankIds.SEG_BOSS
	assert_eq(TankCues.prompt_of(s, s.rider(diesel_peer)), TankCues.PROMPT_DODGE, "at the boss")
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 3.0
	assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_OVER)
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 0.0
	assert_eq(TankCues.prompt_of(s, s.rider(steam_peer)), TankCues.PROMPT_NONE)


func test_no_sprint_prompt_outside_work_phases_or_when_the_rider_cannot_act() -> void:
	var s := TankFixtures.state(3)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	_diesel(s).prompt = true
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


func test_the_bulwark_prompts_like_the_diesel() -> void:
	var s := TankFixtures.state(1)
	assert_eq(TankCues.prompt_of(s, s.rider(1)), TankCues.PROMPT_NONE)
	(s.station(TankIds.ENGINE_BULWARK) as TankGearboxState).prompt = true
	assert_eq(TankCues.prompt_of(s, s.rider(1)), TankCues.PROMPT_RAM)
	s.seg.seg = TankIds.SEG_BOSS
	assert_eq(TankCues.prompt_of(s, s.rider(1)), TankCues.PROMPT_DODGE)


# --- the host raises only its own ------------------------------------------------------------------------


func test_the_host_toasts_its_own_riders_prompt_with_its_own_peer() -> void:
	var s := TankFixtures.state(3)
	var diesel_peer := _peer_of(s, TankIds.ENGINE_DIESEL)
	_diesel(s).prompt = true
	var host_ctx := _ctx(3, diesel_peer)
	var cues := TankCues.new(host_ctx)
	cues.on_state(s)
	assert_eq(_keys(_toasts(host_ctx)), ["TANK_PROMPT_RAM"])
	assert_eq(_toasts(host_ctx)[0][3], diesel_peer, "drawn on the host only, never broadcast")
	var other_ctx := _ctx(3, _peer_of(s, TankIds.ENGINE_DYNAMO))
	TankCues.new(other_ctx).on_state(s)
	assert_eq(_toasts(other_ctx), [], "another rider's prompt is not ours")


func test_a_prompt_comes_up_once_and_again_after_it_went_away() -> void:
	var s := TankFixtures.state(1)
	var ctx := _ctx(1, 1, Wl.SOLO)
	var cues := TankCues.new(ctx)
	var box := s.station(TankIds.ENGINE_BULWARK) as TankGearboxState
	cues.on_state(s)
	assert_eq(_toasts(ctx), [])
	box.prompt = true
	for _i in 5:
		cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_PROMPT_RAM"], "once while it stays up")
	box.prompt = false
	cues.on_state(s)
	box.prompt = true
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_PROMPT_RAM", "TANK_PROMPT_RAM"])
	s.seg.seg = TankIds.SEG_BOSS
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx))[-1], "TANK_PROMPT_DODGE", "the prompt changed: say so")


func test_the_steam_overpressure_prompt() -> void:
	var s := TankFixtures.state(3)
	var steam_peer := _peer_of(s, TankIds.ENGINE_STEAM)
	var ctx := _ctx(3, steam_peer)
	var cues := TankCues.new(ctx)
	(s.station(TankIds.ENGINE_STEAM) as TankSteamState).window_s = 5.0
	cues.on_state(s)
	assert_eq(_keys(_toasts(ctx)), ["TANK_PROMPT_OVER"])


func test_the_dynamo_stalled_toast_goes_to_the_whole_crew_once() -> void:
	var s := TankFixtures.state(3)
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


func test_regroup_is_said_once_when_the_objective_is_met_before_min_s() -> void:
	var s := TankFixtures.state(1)
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
	cues.on_event(s, TankEvents.ram(me.slot, true, 5))
	cues.on_event(s, TankEvents.ram(me.slot, false, 0))
	cues.on_event(s, TankEvents.ram(other.slot, true, 5))
	cues.on_event(s, TankEvents.dodge(me.slot))
	cues.on_event(s, TankEvents.dodge(other.slot))
	cues.on_event(s, TankEvents.latch(me.slot, TankIds.SHELL_HEAVY))
	cues.on_event(s, TankEvents.breakdown())
	cues.on_event(s, TankEvents.repaired(40.0))
	assert_eq(
		_keys(_toasts(ctx)),
		[
			"TANK_TOAST_RAM_HIT",
			"TANK_TOAST_RAM_MISS",
			"TANK_TOAST_DODGED",
			"TANK_TOAST_LOADED_HEAVY",
			"TANK_TOAST_BREAKDOWN",
			"TANK_TOAST_REPAIRED"
		],
		"another rider's ram and dodge are not ours"
	)
	assert_eq(_toasts(ctx)[5][2], [40])
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


func test_a_rotation_event_names_the_riders_new_station() -> void:
	var s := TankFixtures.state(3)
	var ctx := _ctx(3, 2)
	var cues := TankCues.new(ctx)
	var me := s.rider(2)
	cues.on_event(
		s,
		TankEvents.rotation(
			[[0, TankIds.ENGINE_STEAM], [1, TankIds.ENGINE_DIESEL], [2, TankIds.ENGINE_DYNAMO]]
		)
	)
	assert_eq(_keys(_toasts(ctx)), ["TANK_TOAST_ROTATION"])
	assert_eq(_toasts(ctx)[0][2], [ctx.strings.t("TANK_ENGINE_DIESEL")], "slot %d" % me.slot)


# --- through the module ------------------------------------------------------------------------------------


func test_a_clients_snapshot_raises_only_its_own_prompt() -> void:
	var host_ctx := F.make_ctx(3)
	var host: TankGame = autofree(F.make_game(host_ctx))
	host.state = TankFixtures.state(3)
	host.state.content = host.content
	var diesel_peer := _peer_of(host.state, TankIds.ENGINE_DIESEL)
	_diesel(host.state).prompt = true
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
		assert_eq(made[peer], ["TANK_PROMPT_RAM"] if peer == diesel_peer else [], "peer %d" % peer)


func test_a_clients_events_raise_its_own_cues() -> void:
	var ctx := F.make_ctx(1, 0, "ashfall_road", Wl.CLIENT, 1)
	var client: TankGame = autofree(F.make_game(ctx))
	client.apply_event(JSON.parse_string(JSON.stringify(TankEvents.ram(0, true, 4))))
	client.apply_event(JSON.parse_string(JSON.stringify(TankEvents.breakdown())))
	assert_eq(_keys(_toasts(ctx)), ["TANK_TOAST_RAM_HIT", "TANK_TOAST_BREAKDOWN"])


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
