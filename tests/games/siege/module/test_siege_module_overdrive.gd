extends GutTest
## The module's side of Overdrive (brief 2.3, 2.4; ADR "Overdrive refusal handling"): the one
## directive and its exact key set, the sprint band on the rider's own peer, host and governor
## refusals and deferred acks, every safety precondition, bots and auto intents, the cool-down,
## and no lap_marker. `short`: the warm-up wave ends at 300 s, the build break at 420 s, wave 1
## runs 420 s to 720 s.

const K := preload("res://tests/games/siege/module/siege_module_kit.gd")
const F := preload("res://tests/games/siege/siege_fakes.gd")
const FORBIDDEN: Array[String] = [
	"mode_grade", "haptic", "haptic_wind", "target_pct", "target_w", "target_wkg", "crr", "cw"
]

var _events: Array = []
var _laps: Array = []


func _hook(g: SiegeGame) -> void:
	_events = []
	_laps = []
	g.game_event.connect(_on_event)
	g.lap_marker.connect(_on_lap)


func _on_event(e: Dictionary) -> void:
	_events.append(e)


func _on_lap(label: String) -> void:
	_laps.append(label)


func _overdrive_events() -> Array:
	var out: Array = []
	for e: Dictionary in _events:
		if e["type"] == SiegeIds.EV_OVERDRIVE:
			out.append(e)
	return out


func _bands(g: SiegeGame) -> Array:
	return K.hud(g).of("power_band")


func _in_wave(content_id: String = "short", humans: int = 1, bots: int = 0) -> Array:
	var g := K.game(humans, bots, content_id)
	_hook(g)
	var tick := K.run_to(g, 0, 430.0)
	return [g, tick]


func test_an_accepted_overdrive_sends_the_exact_directive_and_shows_the_band() -> void:
	var r := _in_wave()
	var g: SiegeGame = r[0]
	var tick: int = r[1]
	K.step(g, tick, {1: [SiegeIntents.overdrive("action")]})
	var reqs := K.directives(g).requests
	assert_eq(reqs.size(), 1)
	assert_eq(reqs[0][0], 1)
	var d: Dictionary = reqs[0][1]
	var keys: Array = d.keys()
	keys.sort()
	assert_eq(keys, ["duration_s", "mode", "reason", "source"], "exactly these four keys")
	assert_eq(d["mode"], "SIM")
	assert_eq(float(d["duration_s"]), 30.0)
	assert_eq(d["reason"], "overdrive")
	assert_eq(d["source"], "siege")
	for k in FORBIDDEN:
		assert_false(d.has(k), "no %s: it would open another channel" % k)
	var me := g.state.rider_at(0)
	assert_eq(me.od_state, SiegeIds.OD_ACTIVE)
	assert_eq(me.od_count, 1)
	var od := _overdrive_events()
	assert_eq(od.size(), 1)
	assert_eq(od[0]["st"], SiegeIds.OD_EV_START)
	assert_eq(_bands(g).size(), 1)
	_assert_band(_bands(g)[0], 240.0, 280.0)
	# 30 s later it has ended: the band is cleared and the 90 s cool-down runs.
	tick = K.run_to(g, tick + 1, 462.0)
	assert_eq(me.od_state, SiegeIds.OD_COOLDOWN)
	assert_gt(me.od_cd_s, 80.0)
	_assert_band(_bands(g).back(), 0.0, 0.0)
	assert_eq(_overdrive_events().back()["st"], SiegeIds.OD_EV_END)
	assert_eq(K.directives(g).requests.size(), 1, "expiry sends no restore directive")
	assert_eq(_laps, [], "never a lap_marker")
	K.directives(g).requests.clear()
	K.step(g, tick, {1: [SiegeIntents.overdrive("action")]})
	assert_eq(K.directives(g).requests.size(), 0, "the cool-down blocks a second one")
	_free(g)


func test_a_coasting_host_rider_sends_no_request_and_gets_no_refusal_or_retry() -> void:
	# The governor would refuse the SIM block (sim_block_unsafe) once the rider has coasted 3 s;
	# the rules never ask: no request, no refusal toast, no 30 s retry, the rider stays READY.
	var r := _in_wave()
	var g: SiegeGame = r[0]
	var tick: int = r[1]
	var me := g.state.rider_at(0)
	for via: String in ["action", "button", "surge"]:
		var f := F.frame(g.ctx, g.plans, tick, 100.0, {1: [SiegeIntents.overdrive(via)]})
		var tm: Telemetry = f.players[1]
		tm.power_w = 4.0
		tm.p_eff_w = 4.0
		tm.cadence_rpm = 6.0
		g.sim_step(Wl.SIM_DT, f)
		tick += 1
		assert_eq(K.directives(g).requests.size(), 0, "%s while coasting: no request" % via)
		assert_eq(me.od_state, SiegeIds.OD_READY, "%s: still READY, no 30 s retry" % via)
	assert_eq(_overdrive_events().size(), 0, "no refused event")
	assert_false(K.toasts(g).has(["SIEGE_TOAST_OVERDRIVE_REFUSED", [], 1]), "no refusal toast")
	# Pedaling again: the same press goes through.
	K.step(g, tick, {1: [SiegeIntents.overdrive("action")]})
	assert_eq(K.directives(g).requests.size(), 1)
	assert_eq(me.od_state, SiegeIds.OD_ACTIVE)
	_free(g)


func test_a_host_refusal_costs_a_30_second_retry_and_toasts_only_the_rider() -> void:
	var r := _in_wave()
	var g: SiegeGame = r[0]
	K.directives(g).host_refuse = "switch_spacing"
	K.step(g, r[1], {1: [SiegeIntents.overdrive("action")]})
	var me := g.state.rider_at(0)
	assert_eq(me.od_state, SiegeIds.OD_COOLDOWN)
	assert_eq(me.od_cd_s, 30.0, "the retry, not the 90 s cool-down")
	assert_eq(me.od_count, 0)
	var od := _overdrive_events()
	assert_eq([od[0]["st"], od[0]["why"]], [SiegeIds.OD_EV_REFUSED, "switch_spacing"])
	assert_eq(_bands(g), [], "no band for a sprint that never started")
	assert_true(K.toasts(g).has(["SIEGE_TOAST_OVERDRIVE_REFUSED", [], 1]))
	_free(g)


func test_a_governor_refusal_inside_request_cancels_it_and_takes_the_count_back() -> void:
	var r := _in_wave()
	var g: SiegeGame = r[0]
	K.directives(g).governor_refuse = "sim_block_unsafe"
	K.step(g, r[1], {1: [SiegeIntents.overdrive("action")]})
	var me := g.state.rider_at(0)
	assert_eq(me.od_state, SiegeIds.OD_COOLDOWN)
	assert_eq(me.od_cd_s, 30.0)
	assert_eq(me.od_count, 0, "an Overdrive that never ran is not counted")
	var st: Array = []
	for e: Dictionary in _overdrive_events():
		st.append(int(e["st"]))
	assert_eq(st, [SiegeIds.OD_EV_START, SiegeIds.OD_EV_REFUSED])
	for b in _bands(g):
		assert_eq(float(b[3]), 0.0, "the band never stays up")
	_free(g)


func test_a_deferred_governor_ack_cancels_the_running_overdrive_next_tick() -> void:
	var r := _in_wave()
	var g: SiegeGame = r[0]
	var tick: int = r[1]
	var dirs := K.directives(g)
	dirs.governor_refuse = "sim_block_unsafe"
	dirs.defer_acks = true
	K.step(g, tick, {1: [SiegeIntents.overdrive("action")]})
	var me := g.state.rider_at(0)
	assert_eq(me.od_state, SiegeIds.OD_ACTIVE, "a remote rider's answer is still on its way")
	_assert_band(_bands(g).back(), 240.0, 280.0)
	dirs.flush_acks()
	K.step(g, tick + 1)
	assert_eq(me.od_state, SiegeIds.OD_COOLDOWN)
	assert_almost_eq(me.od_cd_s, 30.0 - Wl.SIM_DT, 0.001, "30 s retry, one tick on")
	assert_eq(me.od_count, 0)
	assert_eq(_overdrive_events().back()["st"], SiegeIds.OD_EV_REFUSED)
	_assert_band(_bands(g).back(), 0.0, 0.0)
	_free(g)


func test_a_stale_ack_for_another_directive_changes_nothing() -> void:
	var r := _in_wave()
	var g: SiegeGame = r[0]
	K.step(g, r[1], {1: [SiegeIntents.overdrive("action")]})
	g._on_directive_applied(1, {"id": 999, "refused": true, "reason": "x"})
	K.step(g, r[1] + 1)
	assert_eq(g.state.rider_at(0).od_state, SiegeIds.OD_ACTIVE)
	_free(g)


func test_overdrive_is_refused_in_the_warm_up_breaks_late_waves_and_rescue() -> void:
	var g := K.game()
	_hook(g)
	var overdrive := {1: [SiegeIntents.overdrive("action")]}
	var tick := K.run_to(g, 0, 100.0)
	K.step(g, tick, overdrive)
	tick = K.run_to(g, tick + 1, 350.0)
	K.step(g, tick, overdrive)
	assert_eq(K.directives(g).requests.size(), 0, "warm-up wave and build break")
	tick = K.run_to(g, tick + 1, 430.0)
	g.on_rescue(1, true)
	K.step(g, tick, overdrive)
	assert_eq(K.directives(g).requests.size(), 0, "never in rescue")
	g.on_rescue(1, false)
	tick = K.run_to(g, tick + 1, 695.0)
	K.step(g, tick, overdrive)
	assert_eq(K.directives(g).requests.size(), 0, "25 s of wave left is under 30")
	tick = K.run_to(g, tick + 1, 730.0)
	K.step(g, tick, overdrive)
	assert_eq(g.state.role, SiegeIds.ROLE_BREAK, "break 1: Overdrive is closed")
	assert_eq(K.directives(g).requests.size(), 0)
	_free(g)


func test_the_last_moment_with_30_seconds_left_still_starts_one() -> void:
	var g := K.game()
	var tick := K.run_to(g, 0, 690.0)
	K.step(g, tick, {1: [SiegeIntents.overdrive("action")]})
	assert_almost_eq(g.state.phase_remaining_s, 30.0, 0.001)
	assert_eq(K.directives(g).requests.size(), 1)
	_free(g)


func test_a_surge_needs_the_prompt_but_the_button_does_not() -> void:
	var r := _in_wave()
	var g: SiegeGame = r[0]
	var tick: int = r[1]
	g.state.enemies.clear()
	K.step(g, tick, {1: [SiegeIntents.overdrive("surge")]})
	assert_eq(K.directives(g).requests.size(), 0, "on the mine there is no prompt")
	var me := g.state.rider_at(0)
	me.target = SiegeIds.STATION_BALLISTA
	K.enemy(g.state, SiegeKit.prog_in_band(g.state, SiegeIds.STATION_BALLISTA), 60.0)
	assert_true(g.state.target_hot(SiegeIds.STATION_BALLISTA))
	K.step(g, tick + 1, {1: [SiegeIntents.overdrive("surge")]})
	assert_eq(K.directives(g).requests.size(), 1, "a surge with an enemy in range of its station")
	_free(g)


func test_auto_intents_and_bots_never_start_it() -> void:
	var r := _in_wave("short", 1, 1)
	var g: SiegeGame = r[0]
	var tick: int = r[1]
	var auto_a := {"k": "overdrive", "via": "auto"}
	var auto_b := {"k": "overdrive", "auto": 1}
	K.step(g, tick, {1: [auto_a, auto_b], -1: [SiegeIntents.overdrive("action")]})
	assert_eq(K.directives(g).requests.size(), 0)
	assert_eq(g.state.rider_at(1).od_state, SiegeIds.OD_READY, "a bot")
	assert_eq(g.autopilot_intents(-1), [], "the module itself never supplies an Overdrive")
	_free(g)


func test_the_cool_down_sends_no_directive_and_no_lap_marker() -> void:
	var g := K.game(1, 0, "drill")
	_hook(g)
	var changed: Array = []
	var finished: Array = []
	g.phase_changed.connect(func(i: int) -> void: changed.append(i))
	g.finished.connect(func(why: String) -> void: finished.append(why))
	var tick := K.run_to(g, 0, 125.0)
	assert_eq(g.state.role, SiegeIds.ROLE_COOLDOWN)
	assert_true(g.victory_march(), "the workers march home")
	var spam := [SiegeIntents.overdrive("action"), SiegeIntents.overdrive("surge")]
	for i in 600:
		var intents := {1: spam} if i % 10 == 0 else {}
		K.step(g, tick + i, intents)
	assert_eq(K.directives(g).requests, [], "no directive in the drill or its cool-down")
	assert_eq(_laps, [], "Siege never emits lap_marker")
	assert_eq(changed, [0, 1, 2], "phase_changed once per index")
	assert_eq(finished, ["complete"])
	_free(g)


func _assert_band(call: Array, lo: float, hi: float) -> void:
	assert_eq(call[1], 1, "the rider's own peer")
	assert_almost_eq(float(call[2]), lo, 0.001)
	assert_almost_eq(float(call[3]), hi, 0.001)


## Frees `g` and its context.
func _free(g: SiegeGame) -> void:
	K.F.free_game(g)
