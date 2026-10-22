extends GutTest
## Brief 4 "rules-level sims": SiegeHeadlessSim steps the pure rules with synthetic riders and
## these tests assert T2, the Breach case, the Overdrive cases and S8 (the 150-enemy cap and the
## 8 KB snapshot). Content is shortened with patches where the assertion allows, so the file
## runs in seconds.

const WAVE_T0 := 80.0
const BREAK := "break"

var _dirs: Array[String] = []


## The sim of `shift_id` trimmed by `trim` (SiegeHeadlessSim.trimmed_shift options) and `extra`
## patches (file key -> merge patch) with the riders `specs`.
func _sim(
	shift_id: String, specs: Array, trim: Dictionary = {}, extra: Dictionary = {}, seed_n: int = 1
) -> SiegeHeadlessSim:
	var patches := extra.duplicate(true)
	if not trim.is_empty():
		patches.merge(SiegeHeadlessSim.trim_patch(shift_id, trim), true)
	return SiegeHeadlessSim.create(shift_id, specs, {"patches": patches, "seed": seed_n})


func _types(sim: SiegeHeadlessSim, type: String) -> Array[float]:
	var out: Array[float] = []
	for lg in sim.events_of(type):
		out.append(lg.t)
	return out


## Overdrive start / end events of slot `slot`: [[t, st, scored, why], ...].
func _od_events(sim: SiegeHeadlessSim, slot: int = 0) -> Array:
	var out: Array = []
	for lg in sim.events_of(SiegeIds.EV_OVERDRIVE):
		if int(lg.event["slot"]) == slot:
			out.append([lg.t, int(lg.event["st"]), int(lg.event["scored"]), str(lg.event["why"])])
	return out


# --- the harness itself -------------------------------------------------------------------------


func test_the_same_seed_replays_identically_and_the_plan_runs_to_the_cooldown() -> void:
	var trim := {"warmup_s": 40, "build_s": 20, "break_s": 20, "wave_s": 90, "max_waves": 2}
	var a := _sim("short", SiegeHeadlessSim.team(4), trim, {}, 5)
	var b := _sim("short", SiegeHeadlessSim.team(4), trim, {}, 5)
	a.run_all()
	b.run_all()
	assert_true(a.finished())
	assert_eq(a.total_s, 40.0 + 20.0 + 90.0 + 20.0 + 90.0 + 180.0, "plan + the 180 s cool-down")
	assert_eq(a.events_log.size(), b.events_log.size())
	assert_eq(a.events_json(), b.events_json(), "same seed, same events")
	assert_eq(JSON.stringify(a.state.to_dict()), JSON.stringify(b.state.to_dict()), "same state")
	assert_true(a.state.done, "the last wave ended")
	assert_eq(_types(a, SiegeIds.EV_WAVE_END).size(), 3, "warm-up wave + 2 waves")
	assert_true(SiegeSnapshotSchema.check(SiegeSnapshot.encode(a.state)) == "")


func test_trimmed_shifts_stay_valid_for_every_content() -> void:
	for id: String in ["short", "vo2", "sweetspot", "endurance", "drill"]:
		var sim := _sim(
			id,
			SiegeHeadlessSim.team(1),
			{"warmup_s": 30, "build_s": 20, "break_s": 20, "wave_s": 150, "max_waves": 2}
		)
		assert_true(sim.content.ok(), "%s: %s" % [id, sim.content.errors])
		assert_gt(sim.total_s, 100.0)


func test_the_tuning_targets_in_balance_json_are_the_briefs() -> void:
	var tuning: Dictionary = SiegeFakes.content("short").balance["tuning"]
	assert_eq(tuning["t1_score"], [64.0, 89.0])
	assert_eq(tuning["t2_ratio"], [0.4, 0.6])
	assert_eq(float(tuning["t3_spread"]), 0.3)
	assert_eq(float(tuning["t4_ram_stop"]), 0.7)


# --- the generator pays 1 denarius per kJ ---------------------------------------------------------


func test_a_generator_rider_earns_one_denarius_per_kj_of_p_eff() -> void:
	# FTP 200 -> P_eff = 1.25 x raw; 200 W raw = 250 W P_eff = 15 kJ in 60 s = 15 denarii.
	var spec := {"ftp": 200.0, "route": "gen", "power_fn": SiegeHeadlessSim.const_w(200.0)}
	var sim := _sim("short", [spec], {"warmup_s": 120, "max_waves": 1})
	sim.run_until(60.0)
	var r := sim.state.rider(1)
	assert_almost_eq(r.gen_denarii, 15.0, 0.015, "within 0.1%")
	assert_almost_eq(r.denarii, 40.0 + 15.0, 0.015)


# --- Overdrive ------------------------------------------------------------------------------------


func _od_wave_sim(specs: Array) -> SiegeHeadlessSim:
	return _sim("short", specs, {"warmup_s": 60, "build_s": 20, "wave_s": 300, "max_waves": 1})


func test_overdrive_lasts_30_s_then_cools_down_for_90_s() -> void:
	var w := WAVE_T0
	var spec := {"ftp": 200.0, "action_at": [w + 10.0, w + 25.0, w + 60.0, w + 125.0, w + 135.0]}
	var sim := _od_wave_sim([spec])
	assert_eq(sim.phase_start(2), w, "the wave starts where the test expects")
	sim.run_until(w + 129.0)
	assert_eq(sim.state.rider(1).od_state, SiegeIds.OD_COOLDOWN, "still cooling 1 s early")
	sim.run_until(w + 131.0)
	assert_eq(sim.state.rider(1).od_state, SiegeIds.OD_READY, "ready 90 s after the end")
	sim.run_until(w + 300.0)
	var ev := _od_events(sim)
	assert_eq(ev.size(), 4, "two Overdrives: %s" % [ev])
	assert_almost_eq(float(ev[0][0]), w + 10.0, 0.06, "starts when asked")
	assert_eq(ev[0][1], SiegeIds.OD_EV_START)
	assert_almost_eq(float(ev[1][0]) - float(ev[0][0]), 30.0, 0.11, "30 s long")
	assert_eq(ev[1][1], SiegeIds.OD_EV_END)
	assert_eq(ev[1][2], 1, "130% FTP held for 10 s or more is a scored sprint")
	assert_almost_eq(
		float(ev[2][0]),
		w + 135.0,
		0.06,
		"the request 5 s before the end of the cooldown was refused"
	)
	assert_almost_eq(float(ev[2][0]) - float(ev[1][0]), 95.0, 0.11, "restarted 5 s after READY")
	assert_almost_eq(float(ev[3][0]) - float(ev[2][0]), 30.0, 0.11)
	assert_eq(sim.state.rider(1).od_scored, 2)
	assert_eq(sim.state.rider(1).od_count, 2)
	assert_eq(sim.stats["od_directives"], 2, "exactly one directive per Overdrive")


func test_overdrive_scores_only_when_the_sprint_rule_held_for_10_s() -> void:
	var lazy := {"ftp": 200.0, "od_pct": 110.0, "action_at": [WAVE_T0 + 10.0]}
	var sim := _od_wave_sim([lazy])
	sim.run_until(WAVE_T0 + 50.0)
	var ev := _od_events(sim)
	assert_eq(ev.size(), 2)
	assert_eq(ev[1][2], 0, "110% FTP is below the 1.2 x FTP sprint rule")
	assert_eq(sim.state.rider(1).od_scored, 0)


func test_overdrive_is_refused_outside_a_wave_with_30_s_left_and_never_in_rescue() -> void:
	var w := WAVE_T0
	var spec := {
		"ftp": 200.0,
		# warm-up wave, build break, rescue, 29 s left, then the cool-down.
		"action_at": [30.0, 70.0, w + 15.0, w + 271.0, w + 320.0],
		"rescue_windows": [[w + 10.0, w + 20.0]],
	}
	var sim := _od_wave_sim([spec])
	sim.run_all()
	assert_eq(_od_events(sim).size(), 0, "no Overdrive started: %s" % [_od_events(sim)])
	assert_eq(sim.stats["od_directives"], 0, "no directive was ever requested")
	assert_eq(sim.state.rider(1).od_state, SiegeIds.OD_READY)


func test_overdrive_starts_with_exactly_30_s_left_and_not_for_bots_or_auto_intents() -> void:
	var w := WAVE_T0
	var human := {"ftp": 200.0, "action_at": [w + 270.0]}
	var bot := {"ftp": 200.0, "bot": true, "action_at": [w + 100.0]}
	var autop := {
		"ftp": 200.0,
		"intents_at": {roundi((w + 100.0) / 0.05): [{"k": "overdrive", "via": "auto"}]}
	}
	var sim := _od_wave_sim([human, bot, autop])
	sim.run_until(w + 302.0)
	assert_eq(_od_events(sim, 0).size(), 2, "30.0 s left is enough")
	assert_eq(_od_events(sim, 1).size(), 0, "bots never")
	assert_eq(_od_events(sim, 2).size(), 0, "an auto-tagged intent never")


func test_a_rescue_in_the_middle_of_an_overdrive_ends_it_with_the_normal_cooldown() -> void:
	var w := WAVE_T0
	var spec := {"ftp": 200.0, "action_at": [w + 10.0], "rescue_windows": [[w + 20.0, w + 30.0]]}
	var sim := _od_wave_sim([spec])
	sim.run_until(w + 21.0)
	var ev := _od_events(sim)
	assert_eq(ev.size(), 2, str(ev))
	assert_eq(ev[1][1], SiegeIds.OD_EV_END)
	assert_eq(ev[1][3], SiegeOverdrive.END_RESCUE)
	assert_almost_eq(float(ev[1][0]), w + 20.0, 0.11)
	var r := sim.state.rider(1)
	assert_eq(r.od_state, SiegeIds.OD_COOLDOWN)
	assert_between(r.od_cd_s, 88.9, 90.0, "the 90 s cooldown from the moment it ended")


func test_a_refused_directive_costs_a_30_s_retry_not_the_cooldown() -> void:
	var w := WAVE_T0
	var spec := {"ftp": 200.0, "action_at": [w + 10.0]}
	var sim := (
		SiegeHeadlessSim
		. create(
			"short",
			[spec],
			{
				"patches":
				SiegeHeadlessSim.trim_patch(
					"short", {"warmup_s": 60, "build_s": 20, "wave_s": 300, "max_waves": 1}
				),
				"od_refuse": "switch_spacing",
			}
		)
	)
	sim.run_until(w + 12.0)
	var ev := _od_events(sim)
	assert_eq(ev.size(), 1, str(ev))
	assert_eq(ev[0][1], SiegeIds.OD_EV_REFUSED)
	assert_eq(ev[0][3], "switch_spacing")
	var r := sim.state.rider(1)
	assert_eq(r.od_state, SiegeIds.OD_COOLDOWN)
	assert_between(r.od_cd_s, 27.0, 30.0)
	assert_eq(r.od_count, 0, "a refused Overdrive is not counted")


func _tower_pad_m(sim: SiegeHeadlessSim, pad: int, until_t: float, sample_at: Array) -> Dictionary:
	var out := {}
	for at in sample_at:
		sim.run_until(at)
		out[at] = sim.state.pad(pad).m
	sim.run_until(until_t)
	return out


func test_overdrive_doubles_the_riders_share_of_tower_output_while_raw_power_is_at_least_ftp(
) -> void:
	# Two riders on the Ballista at pad 3. FAIR_FTP: P_eff = raw x 250 / FTP.
	# A: FTP 200, 220 W raw = 275 W P_eff. B: FTP 220, 110 W raw = 125 W P_eff.
	var w := WAVE_T0
	var a := {
		"ftp": 200.0,
		"route": "3",
		"manual_shop": true,
		"od_pct": 110.0,
		"action_at": [w + 40.0],
		"power_fn": SiegeHeadlessSim.const_w(220.0)
	}
	var b := {
		"ftp": 220.0, "route": "3", "manual_shop": true, "power_fn": SiegeHeadlessSim.const_w(110.0)
	}
	var sim := _od_wave_sim([a, b])
	var m := _tower_pad_m(sim, 3, w + 120.0, [w + 30.0, w + 50.0, w + 80.0])
	assert_almost_eq(
		float(m[w + 30.0]), (275.0 + 125.0) / 250.0, 0.02, "before: sum of P_eff / 250 W"
	)
	assert_almost_eq(
		float(m[w + 50.0]), (2.0 * 275.0 + 125.0) / 250.0, 0.02, "only A's share doubles"
	)
	assert_almost_eq(float(m[w + 80.0]), (275.0 + 125.0) / 250.0, 0.02, "back to 1x after 30 s")


func test_overdrive_does_not_double_output_below_ftp_and_m_caps_at_4() -> void:
	var w := WAVE_T0
	# A rides 190 W (< FTP 200) in its Overdrive: od stays 1.
	var weak := {
		"ftp": 200.0,
		"route": "3",
		"manual_shop": true,
		"action_at": [w + 40.0],
		"power_fn": SiegeHeadlessSim.const_w(190.0)
	}
	var sim := _od_wave_sim([weak])
	var m := _tower_pad_m(sim, 3, w + 60.0, [w + 30.0, w + 50.0])
	assert_almost_eq(float(m[w + 30.0]), 190.0 * 1.25 / 250.0, 0.02)
	assert_almost_eq(float(m[w + 50.0]), float(m[w + 30.0]), 0.02, "no doubling below CP")
	# Two big riders in Overdrive: 2 x (2 x 500 W P_eff) / 250 = 8, capped at 4.0.
	var big := {
		"ftp": 200.0,
		"route": "4",
		"manual_shop": true,
		"action_at": [w + 40.0],
		"power_fn": SiegeHeadlessSim.const_w(400.0)
	}
	var big2 := {
		"ftp": 200.0,
		"route": "4",
		"manual_shop": true,
		"action_at": [w + 40.0],
		"power_fn": SiegeHeadlessSim.const_w(400.0)
	}
	var cap := _od_wave_sim([big, big2])
	var mc := _tower_pad_m(cap, 4, w + 60.0, [w + 30.0, w + 50.0])
	assert_almost_eq(float(mc[w + 30.0]), 4.0, 0.001, "1000 W P_eff / 250 = 4.0 already")
	assert_almost_eq(float(mc[w + 50.0]), 4.0, 0.001, "capped at 4.0 in Overdrive")


# --- T2 ---------------------------------------------------------------------------------------------


func test_t2_a_tower_only_rider_earns_40_to_60_percent_of_a_generator_only_rider() -> void:
	# Two riders on towers (Ballista pad 3, Scorpion pad 4), two on the generator, same FTP and
	# compliance. Earnings (generator pay + bounties) per minute of wave time.
	var tower := {"ftp": 200.0}
	var specs := [
		tower.merged({"route": "3"}),
		tower.merged({"route": "4"}),
		tower.merged({"route": "gen"}),
		tower.merged({"route": "gen"}),
	]
	var sim := _sim(
		"short",
		specs,
		{"warmup_s": 60, "build_s": 60, "break_s": 60, "wave_s": 180, "max_waves": 3}
	)
	sim.run_all()
	var tower_rate := (sim.earned_per_wave_minute(1) + sim.earned_per_wave_minute(2)) / 2.0
	var gen_rate := (sim.earned_per_wave_minute(3) + sim.earned_per_wave_minute(4)) / 2.0
	assert_gt(gen_rate, 0.0)
	var ratio := tower_rate / gen_rate
	assert_between(
		ratio,
		0.4,
		0.6,
		(
			"T2: tower-only %.2f vs generator-only %.2f denarii/min = %.2f"
			% [tower_rate, gen_rate, ratio]
		)
	)


# --- Breach -----------------------------------------------------------------------------------------


func test_breach_four_riders_at_0_w_breach_in_the_first_full_wave() -> void:
	var sim := _sim(
		"short",
		SiegeHeadlessSim.team(4, {"zero": true}),
		{"warmup_s": 60, "build_s": 20, "break_s": 20, "wave_s": 300, "max_waves": 2}
	)
	var w0 := sim.phase_start(sim.phases_of(SiegeIds.ROLE_WAVE)[0])
	var before := {}
	var at_breach := {}
	var after := {}
	var restored_hp := -1.0
	var breach_t := -1.0
	var restore_t := -1.0
	while not sim.finished() and restore_t < 0.0 and sim.now() < w0 + 300.0 + 20.0:
		for r in sim.state.riders:
			before[r.peer] = r.denarii
		var evs := sim.step()
		for e in evs:
			if str(e["type"]) == SiegeIds.EV_BREACH and breach_t < 0.0:
				breach_t = sim.now() - SiegeHeadlessSim.DT
				at_breach = before.duplicate()
			if str(e["type"]) == SiegeIds.EV_GATE_RESTORED and breach_t >= 0.0 and restore_t < 0.0:
				restore_t = sim.now() - SiegeHeadlessSim.DT
				restored_hp = float(sim.state.gate_hp)
				for r in sim.state.riders:
					after[r.peer] = r.denarii
	assert_gte(breach_t, w0, "a Breach after the first full wave began")
	assert_lt(breach_t, w0 + 300.0, "a Breach inside the first full wave")
	assert_gt(restore_t, 0.0, "the gate came back")
	assert_almost_eq(restore_t - breach_t, 10.0, 0.11, "towers stop for 10 s")
	assert_almost_eq(restored_hp, 30.0, 0.5, "the gate is back at 30 HP")
	var lost_any := false
	for peer: int in at_breach:
		var b := floorf(float(at_breach[peer]))
		var expected_keep := floorf(float(at_breach[peer]) * 0.7)
		var a := float(after[peer])
		lost_any = lost_any or a < float(at_breach[peer]) - 0.5
		var kept_ok := (
			absf(a - expected_keep) <= 1.0
			or absf(a - (float(at_breach[peer]) - floorf(0.3 * float(at_breach[peer])))) <= 1.0
		)
		assert_true(
			kept_ok,
			"rider %d: %.1f denarii before, %.1f after (30%% lost, rounded down)" % [peer, b, a]
		)
	assert_true(lost_any, "every rider lost denarii")
	assert_gte(sim.state.breaches, 1)


# --- S8: the cap and the snapshot ------------------------------------------------------------------


func _s8_sim(c_budget_factor: float) -> SiegeHeadlessSim:
	var base := float(SiegeFakes.content("vo2").balance["c_budget"])
	var patches := {"balance": {"c_budget": base * c_budget_factor}}
	patches.merge(
		SiegeHeadlessSim.trim_patch(
			"vo2", {"warmup_s": 90, "build_s": 30, "break_s": 30, "max_waves": 3}
		),
		true
	)
	return SiegeHeadlessSim.create("vo2", SiegeHeadlessSim.team(4), {"patches": patches, "seed": 3})


func test_s8_vo2_with_triple_budget_stays_under_the_cap_and_the_snapshot_limit() -> void:
	var sim := _s8_sim(3.0)
	sim.run_all()
	assert_lte(sim.stats["max_alive"], 150, "at most 150 enemies alive")
	assert_lte(
		sim.stats["max_snapshot_bytes"], SiegeSnapshotSchema.MAX_BYTES, "every snapshot <= 8 KB"
	)
	assert_gt(sim.stats["snapshots"], 1000)
	if int(sim.stats["max_alive"]) >= 150:
		assert_gt(sim.stats["max_queue"], 0, "extra spawns wait in the queue")


func test_s8_a_flood_hits_the_cap_with_the_rest_queued_and_a_small_snapshot() -> void:
	# 30x the budget with riders that do nothing: far more spawns than 150 enemies fit.
	var base := float(SiegeFakes.content("vo2").balance["c_budget"])
	var patches := {"balance": {"c_budget": base * 30.0}}
	patches.merge(
		SiegeHeadlessSim.trim_patch(
			"vo2", {"warmup_s": 90, "build_s": 30, "break_s": 30, "max_waves": 1}
		),
		true
	)
	var specs := SiegeHeadlessSim.team(4, {"zero": true})
	var sim := SiegeHeadlessSim.create("vo2", specs, {"patches": patches, "seed": 4})
	sim.run_all()
	assert_lte(sim.stats["max_alive"], 150)
	assert_lte(
		sim.stats["max_snapshot_bytes"], SiegeSnapshotSchema.MAX_BYTES, "8 KB even at the cap"
	)
	assert_eq(sim.stats["max_alive"], 150, "the cap was reached")
	assert_gt(sim.stats["max_queue"], 0, "the rest of the spawns queued")
	assert_gt(sim.stats["max_snapshot_bytes"], 2500, "the biggest snapshot held ~150 enemies")
