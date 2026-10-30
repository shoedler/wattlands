extends GutTest
## SiegeOverdrive (brief 2.3, 2.4, 4): every precondition, the exact directive, the state
## machine (accepted, host refusal, governor refusal after acceptance, expiry, cancel), the
## od = 2 rule at CP, the scored sprint, and the flow through SiegeRules and SiegeGame.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const FORBIDDEN: Array[String] = [
	"mode_grade", "haptic", "haptic_wind", "target_pct", "target_w", "target_wkg", "crr", "cw"
]

var _content: SiegeContent
var _state: SiegeState
var _human: SiegeRiderState
var _bot: SiegeRiderState


func before_each() -> void:
	_content = F.content("vo2")
	var slots := F.make_slots(2, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	_state = SiegeState.create(_content, slots, Wl.FAIR_FTP, rng)
	_human = _state.rider(1)
	_bot = _state.rider(-1)
	# Both riders are pedaling unless a test says otherwise (a coasting rider is refused).
	for r: SiegeRiderState in [_human, _bot]:
		r.raw_w = 180.0
		r.cadence_rpm = 85.0


func _work(remaining: float = 100.0) -> SiegePhaseInfo:
	var p := SiegePhaseInfo.new()
	p.index = 2
	p.kind = Wl.WORK
	p.role = SiegeIds.ROLE_WAVE
	p.number = 1
	p.duration_s = 120.0
	p.remaining_s = remaining
	p.elapsed_s = 120.0 - remaining
	return p


func _phase(kind: String, role: String) -> SiegePhaseInfo:
	var p := _work()
	p.kind = kind
	p.role = role
	return p


func _intent(via: String, auto: bool = false) -> Dictionary:
	var raw := SiegeIntents.overdrive(via)
	if auto:
		raw["auto"] = 1
	return SiegeIntents.normalize(raw)


## A spearman inside station `id`'s range band.
func _enemy_in_band(id: int) -> void:
	SiegeKit.enemy(_state, SiegeIds.ENEMY_SPEAR, SiegeKit.prog_in_band(_state, id))


func _keys(d: Dictionary) -> Array:
	var k := d.keys().filter(func(x: Variant) -> bool: return x != "id")
	k.sort()
	return k


func test_the_directive_is_exactly_the_brief_s() -> void:
	var d := SiegeOverdrive.directive_dict(_content)
	assert_eq(d, {"mode": "SIM", "duration_s": 30, "reason": "overdrive", "source": "siege"})
	var ed := SiegeOverdrive.directive(_content).to_dict()
	assert_eq(_keys(ed), ["duration_s", "mode", "reason", "source"])
	assert_eq(ed["mode"], "SIM")
	assert_eq(float(ed["duration_s"]), 30.0)
	assert_eq([ed["reason"], ed["source"]], ["overdrive", "siege"])
	for k in FORBIDDEN:
		assert_false(ed.has(k), "no %s" % k)
	var sd := SiegeOverdrive.directive().to_dict()
	assert_eq(_keys(sd), _keys(ed), "the same without content")
	assert_eq(SiegeOverdrive.band_w(_content, 250.0), Vector2(300.0, 350.0))


func test_preconditions() -> void:
	var work := _work()
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), "")
	assert_eq(
		SiegeOverdrive.blocked_reason(_state, _bot, work), SiegeOverdrive.WHY_BOT, "never for bots"
	)
	var warm := _phase(Wl.WARMUP, SiegeIds.ROLE_WARMUP_WAVE)
	assert_eq(
		SiegeOverdrive.blocked_reason(_state, _human, warm), SiegeOverdrive.WHY_NOT_WORK, "warm-up"
	)
	var drill := _phase(Wl.WARMUP, SiegeIds.ROLE_WAVE)
	assert_eq(
		SiegeOverdrive.blocked_reason(_state, _human, drill),
		SiegeOverdrive.WHY_NOT_WORK,
		"the drill's wave"
	)
	var brk := _phase(Wl.RECOVERY, SiegeIds.ROLE_BREAK)
	assert_eq(
		SiegeOverdrive.blocked_reason(_state, _human, brk), SiegeOverdrive.WHY_NOT_WORK, "breaks"
	)
	var bb := _phase(Wl.RECOVERY, SiegeIds.ROLE_BUILD_BREAK)
	assert_eq(
		SiegeOverdrive.blocked_reason(_state, _human, bb),
		SiegeOverdrive.WHY_NOT_WORK,
		"build break"
	)
	var cool := _phase(Wl.COOLDOWN, SiegeIds.ROLE_COOLDOWN)
	assert_eq(
		SiegeOverdrive.blocked_reason(_state, _human, cool),
		SiegeOverdrive.WHY_NOT_WORK,
		"cool-down"
	)
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, _work(30.0)), "", "exactly 30 s left")
	assert_eq(
		SiegeOverdrive.blocked_reason(_state, _human, _work(29.95)), SiegeOverdrive.WHY_TOO_LATE
	)
	_human.rescue = true
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), SiegeOverdrive.WHY_RESCUE)
	_human.rescue = false
	_human.afk = true
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), SiegeOverdrive.WHY_AFK)
	_human.afk = false
	_human.connected = false
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), SiegeOverdrive.WHY_AFK)
	_human.connected = true
	for st: int in [SiegeIds.OD_PENDING, SiegeIds.OD_ACTIVE, SiegeIds.OD_COOLDOWN]:
		_human.od_state = st
		assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), SiegeOverdrive.WHY_NOT_READY)
	_human.od_state = SiegeIds.OD_READY


func test_a_rider_who_is_not_pedaling_cannot_start() -> void:
	var work := _work()
	_enemy_in_band(SiegeIds.STATION_BALLISTA)
	_human.target = SiegeIds.STATION_BALLISTA
	# The platform's not_pedaling rule: both power < 15 W and cadence < 20 rpm.
	_human.raw_w = 0.0
	_human.cadence_rpm = 0.0
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), SiegeOverdrive.WHY_COASTING)
	_human.raw_w = 14.9
	_human.cadence_rpm = 19.9
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), SiegeOverdrive.WHY_COASTING)
	assert_false(SiegeOverdrive.prompt(_state, _human, work), "no prompt while coasting")
	for via: String in [SiegeIds.VIA_BUTTON, SiegeIds.VIA_ACTION, SiegeIds.VIA_SURGE]:
		assert_eq(
			SiegeOverdrive.trigger_reason(_state, _human, work, _intent(via)),
			SiegeOverdrive.WHY_COASTING,
			"%s is refused up front, no SIM block request" % via
		)
		assert_false(SiegeOverdrive.try_start(_state, _human, work, _intent(via)))
	assert_true(_state.od_requests.is_empty(), "nothing is queued for the sink to refuse")
	assert_eq(_human.od_state, SiegeIds.OD_READY, "and the rider stays READY (no 30 s retry)")
	# Either signal alone counts as pedaling.
	_human.raw_w = 15.0
	_human.cadence_rpm = 0.0
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), "")
	_human.raw_w = 0.0
	_human.cadence_rpm = 20.0
	assert_eq(SiegeOverdrive.blocked_reason(_state, _human, work), "")
	assert_true(SiegeOverdrive.prompt(_state, _human, work), "pedaling again: the prompt returns")
	assert_true(SiegeOverdrive.try_start(_state, _human, work, _intent(SiegeIds.VIA_SURGE)))


func test_prompt_needs_an_enemy_in_range_of_the_target_or_a_rush() -> void:
	var work := _work()
	assert_false(SiegeOverdrive.prompt(_state, _human, work), "on the mine, no rush")
	_human.target = SiegeIds.STATION_BALLISTA
	assert_false(SiegeOverdrive.prompt(_state, _human, work), "the ballista, nothing in range")
	_enemy_in_band(SiegeIds.STATION_BALLISTA)
	assert_true(SiegeOverdrive.prompt(_state, _human, work), "a spearman in the ballista's band")
	_human.target = SiegeIds.STATION_MINE
	assert_false(SiegeOverdrive.prompt(_state, _human, work), "the mine is never hot")
	_human.target = SiegeIds.STATION_TAR
	assert_false(SiegeOverdrive.prompt(_state, _human, work), "the tar works: no engine near")
	SiegeKit.enemy(_state, SiegeIds.ENEMY_RAM, _state.path.length_m - 50.0)
	assert_true(SiegeOverdrive.prompt(_state, _human, work), "a ram 50 m from the gate")
	_human.target = SiegeIds.STATION_MINE
	_state.wave.rush_s = 12.0
	assert_true(SiegeOverdrive.prompt(_state, _human, work), "a rush is on")
	assert_false(SiegeOverdrive.prompt(_state, _human, _work(29.0)), "< 30 s left")
	_human.rescue = true
	assert_false(SiegeOverdrive.prompt(_state, _human, work), "rescue")


func test_triggers() -> void:
	var work := _work()
	assert_eq(
		SiegeOverdrive.trigger_reason(_state, _human, work, _intent("action")), "", "ability_1"
	)
	assert_eq(
		SiegeOverdrive.trigger_reason(_state, _human, work, _intent("button")), "", "the HUD button"
	)
	assert_eq(
		SiegeOverdrive.trigger_reason(_state, _human, work, _intent("surge")),
		SiegeOverdrive.WHY_NO_PROMPT,
		"a surge only while the prompt shows"
	)
	_state.wave.rush_s = 5.0
	assert_eq(SiegeOverdrive.trigger_reason(_state, _human, work, _intent("surge")), "")
	assert_eq(
		SiegeOverdrive.trigger_reason(_state, _human, work, _intent("action", true)),
		SiegeOverdrive.WHY_AUTO,
		"never from Autopilot or an auto-confirm"
	)
	assert_eq(
		SiegeOverdrive.trigger_reason(_state, _human, work, _intent("auto")),
		SiegeOverdrive.WHY_AUTO
	)
	assert_eq(
		SiegeOverdrive.trigger_reason(_state, _bot, work, _intent("action")), SiegeOverdrive.WHY_BOT
	)
	var route := SiegeIntents.normalize(SiegeIntents.route("gen"))
	assert_eq(
		SiegeOverdrive.trigger_reason(_state, _human, work, route), SiegeOverdrive.WHY_NOT_INTENT
	)
	var brk := _phase(Wl.RECOVERY, SiegeIds.ROLE_BREAK)
	assert_false(
		SiegeOverdrive.try_start(_state, _human, brk, _intent("action")), "refused in a break"
	)
	assert_eq(_state.od_requests, [] as Array[int])


func test_accepted_runs_30_s_then_cools_down_90_s_from_its_end() -> void:
	assert_true(SiegeOverdrive.try_start(_state, _human, _work(), _intent("action")))
	assert_eq(_human.od_state, SiegeIds.OD_PENDING)
	assert_eq(_state.od_requests, [1] as Array[int])
	assert_eq(_state.take_od_requests(), [1] as Array[int])
	var ev := SiegeOverdrive.on_request_result(_state, 1, true, 41, "")
	assert_eq(ev, [SiegeEvents.overdrive(_human.slot, SiegeIds.OD_EV_START)] as Array[Dictionary])
	assert_eq(
		[_human.od_state, _human.od_s, _human.od_id, _human.od_count],
		[SiegeIds.OD_ACTIVE, 30.0, 41, 1]
	)
	var ends: Array[Dictionary] = []
	for i in 599:
		ends.append_array(SiegeOverdrive.step_rider(_state, _human, 100.0, Wl.SIM_DT))
	assert_eq(ends, [] as Array[Dictionary], "still on after 29.95 s")
	ends = SiegeOverdrive.step_rider(_state, _human, 100.0, Wl.SIM_DT)
	assert_eq(
		ends,
		[SiegeEvents.overdrive(_human.slot, SiegeIds.OD_EV_END, false, "")] as Array[Dictionary]
	)
	assert_eq([_human.od_state, _human.od_cd_s, _human.od_id], [SiegeIds.OD_COOLDOWN, 90.0, 0])
	for i in 1799:
		SiegeOverdrive.step_rider(_state, _human, 100.0, Wl.SIM_DT)
	assert_eq(_human.od_state, SiegeIds.OD_COOLDOWN, "89.95 s into the cooldown")
	SiegeOverdrive.step_rider(_state, _human, 100.0, Wl.SIM_DT)
	assert_eq(_human.od_state, SiegeIds.OD_READY)


func test_host_refusal_cancels_with_a_30_s_retry_and_no_count() -> void:
	SiegeOverdrive.try_start(_state, _human, _work(), _intent("action"))
	var ev := SiegeOverdrive.on_request_result(_state, 1, false, 7, Wl.REFUSE_SIM_BLOCK_UNSAFE)
	assert_eq(
		ev,
		(
			[
				SiegeEvents.overdrive(
					_human.slot, SiegeIds.OD_EV_REFUSED, false, Wl.REFUSE_SIM_BLOCK_UNSAFE
				)
			]
			as Array[Dictionary]
		)
	)
	assert_eq([_human.od_state, _human.od_cd_s, _human.od_count], [SiegeIds.OD_COOLDOWN, 30.0, 0])
	assert_eq(_state.od_requests, [] as Array[int])
	var late := {"id": 7, "refused": true, "reason": Wl.REFUSE_SIM_BLOCK_UNSAFE}
	assert_eq(
		SiegeOverdrive.on_applied(_state, 1, late),
		[] as Array[Dictionary],
		"the router's record: no second event"
	)


func test_governor_refusal_after_acceptance_cancels() -> void:
	SiegeOverdrive.try_start(_state, _human, _work(), _intent("action"))
	SiegeOverdrive.on_request_result(_state, 1, true, 12, "")
	assert_eq(
		SiegeOverdrive.on_applied(_state, 1, {"id": 11, "refused": true, "reason": "x"}),
		[] as Array[Dictionary],
		"another id"
	)
	assert_eq(
		SiegeOverdrive.on_applied(_state, 1, {"id": 12, "refused": false}),
		[] as Array[Dictionary],
		"applied"
	)
	assert_eq(
		SiegeOverdrive.on_applied(_state, 2, {"id": 12, "refused": true}),
		[] as Array[Dictionary],
		"another peer"
	)
	assert_eq(_human.od_state, SiegeIds.OD_ACTIVE)
	var ev := SiegeOverdrive.on_applied(
		_state, 1, {"id": 12, "refused": true, "reason": Wl.REFUSE_SWITCH_SPACING}
	)
	assert_eq(
		ev,
		(
			[
				SiegeEvents.overdrive(
					_human.slot, SiegeIds.OD_EV_REFUSED, false, Wl.REFUSE_SWITCH_SPACING
				)
			]
			as Array[Dictionary]
		)
	)
	assert_eq(
		[_human.od_state, _human.od_cd_s, _human.od_count, _human.od_id],
		[SiegeIds.OD_COOLDOWN, 30.0, 0, 0]
	)
	assert_eq(SiegeOverdrive.multiplier(_state, _human, 500.0), 1.0)


func test_cancel_on_phase_change_rescue_or_afk_starts_the_full_cooldown() -> void:
	for why: String in [
		SiegeOverdrive.END_PHASE, SiegeOverdrive.END_RESCUE, SiegeOverdrive.END_AFK
	]:
		_human.od_state = SiegeIds.OD_READY
		SiegeOverdrive.try_start(_state, _human, _work(), _intent("action"))
		_state.take_od_requests()
		SiegeOverdrive.on_request_result(_state, 1, true, 3, "")
		var ev := SiegeOverdrive.cancel(_state, _human, why)
		assert_eq(
			ev,
			(
				[SiegeEvents.overdrive(_human.slot, SiegeIds.OD_EV_END, false, why)]
				as Array[Dictionary]
			)
		)
		assert_eq([_human.od_state, _human.od_cd_s], [SiegeIds.OD_COOLDOWN, 90.0], why)
	_human.od_state = SiegeIds.OD_READY
	SiegeOverdrive.try_start(_state, _human, _work(), _intent("action"))
	assert_eq(
		SiegeOverdrive.cancel(_state, _human, SiegeOverdrive.END_PHASE), [] as Array[Dictionary]
	)
	assert_eq(_human.od_state, SiegeIds.OD_READY, "a pending request is dropped")
	assert_eq(_state.od_requests, [] as Array[int])
	assert_eq(
		SiegeOverdrive.cancel(_state, _human, SiegeOverdrive.END_PHASE),
		[] as Array[Dictionary],
		"idle: nothing"
	)


func test_od_doubles_output_only_at_or_above_cp() -> void:
	assert_eq(SiegeOverdrive.multiplier(_state, _human, 400.0), 1.0, "not active")
	SiegeOverdrive.try_start(_state, _human, _work(), _intent("action"))
	SiegeOverdrive.on_request_result(_state, 1, true, 1, "")
	assert_eq(_human.ftp, 200.0)
	assert_eq(SiegeOverdrive.multiplier(_state, _human, 200.0), 2.0, "raw power == CP (FTP)")
	assert_eq(SiegeOverdrive.multiplier(_state, _human, 199.9), 1.0)


func test_a_scored_sprint_needs_10_s_in_a_row_at_1_2_ftp() -> void:
	SiegeOverdrive.try_start(_state, _human, _work(), _intent("action"))
	SiegeOverdrive.on_request_result(_state, 1, true, 1, "")
	for i in 199:
		SiegeOverdrive.step_rider(_state, _human, 240.0, Wl.SIM_DT)
	SiegeOverdrive.step_rider(_state, _human, 239.0, Wl.SIM_DT)
	for i in 100:
		SiegeOverdrive.step_rider(_state, _human, 300.0, Wl.SIM_DT)
	assert_false(SiegeOverdrive.scored_now(_state, _human), "9.95 s, a break, then 5 s")
	var ev: Array[Dictionary] = []
	for i in 300:
		ev.append_array(SiegeOverdrive.step_rider(_state, _human, 241.0, Wl.SIM_DT))
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0]["scored"]), 1, "the last 15 s held")
	assert_eq([_human.od_scored, _human.od_count], [1, 1])


func test_through_the_rules_only_valid_intents_start_it() -> void:
	var slots := F.make_slots(1, 1)
	var plans := {}
	for p in slots:
		plans[p.peer_id] = F.with_cooldown(SiegePlanBuilder.build(_content.shift, p, "vo2"))
	var st := SiegeState.create(_content, slots, Wl.FAIR_FTP, RandomNumberGenerator.new())
	var od := [SiegeIntents.normalize(SiegeIntents.overdrive("action"))]
	# Warm-up wave (t 100 s), build break (t 350 s), wave 1 with < 30 s left (t 515 s): refused.
	for t: float in [100.0, 350.0, 515.0]:
		var tick := roundi(t / Wl.SIM_DT)
		SiegeRules.step(st, F.inputs(slots, plans, tick - 1), Wl.SIM_DT)
		SiegeRules.step(st, F.inputs(slots, plans, tick, 100.0, {1: od}), Wl.SIM_DT)
		assert_eq(st.take_od_requests(), [] as Array[int], "no Overdrive at %d s" % t)
	# Wave 1 at 430 s: the human starts; the bot's (auto) intent never does.
	var tick := roundi(430.0 / Wl.SIM_DT)
	var auto := [SiegeIntents.normalize(SiegeIntents.overdrive("auto"))]
	SiegeRules.step(st, F.inputs(slots, plans, tick, 100.0, {1: od, -1: auto}), Wl.SIM_DT)
	assert_eq(st.take_od_requests(), [1] as Array[int])
	assert_eq(st.rider(-1).od_state, SiegeIds.OD_READY)


func test_through_the_module_a_human_s_request_and_its_refusals() -> void:
	for mode: String in ["ok", "host", "governor", "late"]:
		var ctx := F.make_ctx(1, 1, "vo2")
		var g := F.make_game(ctx)
		var plans := F.plans_of(g)
		var dirs: F.Directives = ctx.directives
		var hud: F.Hud = ctx.hud
		match mode:
			"host":
				dirs.host_refuse = Wl.REFUSE_SIM_BLOCK_UNSAFE
			"governor":
				dirs.governor_refuse = Wl.REFUSE_SWITCH_SPACING
			"late":
				dirs.defer_acks = true
				dirs.governor_refuse = Wl.REFUSE_SIM_BLOCK_UNSAFE
		var events: Array = []
		g.game_event.connect(func(e: Dictionary) -> void: events.append(e))
		var tick := roundi(430.0 / Wl.SIM_DT)
		g.sim_step(Wl.SIM_DT, F.frame(ctx, plans, tick))
		var intent := {
			1: [SiegeIntents.overdrive("action")], -1: [{"k": "overdrive", "via": "action"}]
		}
		g.sim_step(Wl.SIM_DT, F.frame(ctx, plans, tick + 1, 100.0, intent))
		assert_eq(dirs.requests.size(), 1, "%s: one request, the human's" % mode)
		if dirs.requests.size() == 1:
			assert_eq(int(dirs.requests[0][0]), 1)
			assert_eq(_keys(dirs.requests[0][1]), ["duration_s", "mode", "reason", "source"])
		if mode == "late":
			g.sim_step(Wl.SIM_DT, F.frame(ctx, plans, tick + 2))
			assert_eq(
				g.state.rider(1).od_state, SiegeIds.OD_ACTIVE, "running until the ack arrives"
			)
			dirs.flush_acks()
			g.sim_step(Wl.SIM_DT, F.frame(ctx, plans, tick + 3))
		var ods := events.filter(
			func(e: Dictionary) -> bool: return e["type"] == SiegeIds.EV_OVERDRIVE
		)
		var bands := hud.of("power_band")
		var toasts := hud.of("toast").filter(
			func(c: Array) -> bool: return c[1] == "SIEGE_TOAST_OVERDRIVE_REFUSED"
		)
		match mode:
			"ok":
				assert_eq(ods.size(), 1)
				assert_eq(int(ods[0]["st"]), SiegeIds.OD_EV_START)
				assert_eq(
					bands, [["power_band", 1, 240.0, 280.0]], "the host's own rider's sprint band"
				)
				assert_eq(g.state.rider(1).od_state, SiegeIds.OD_ACTIVE)
			_:
				assert_eq(int(ods[-1]["st"]), SiegeIds.OD_EV_REFUSED, mode)
				assert_eq(g.state.rider(1).od_state, SiegeIds.OD_COOLDOWN, mode)
				assert_eq(g.state.rider(1).od_cd_s > 29.0, true, mode)
				assert_eq(toasts.size(), 1, "%s: the refusal toast, on the host's own rider" % mode)
				if toasts.size() == 1:
					assert_eq(int(toasts[0][3]), ctx.local_peer)
				assert_eq(
					bands[-1] if not bands.is_empty() else [],
					["power_band", 1, 0.0, 0.0] if not bands.is_empty() else []
				)
		F.free_game(g)
