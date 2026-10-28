extends GutTest
## TankDirector against brief 2.3 directive patterns 1-7 and 2.7 haptics: every directive's exact
## dictionary, the bank's sub-step slew, the boiler steps, terrain at 2 Hz, the cadence and power
## bands, the haptic rules, end_phase, nothing SIM-only in an ERG phase and nothing in the
## cool-down. Crew 3 on the v3 landship (no rotation): peer 1 drives the diesel, peer 2 the dynamo,
## peer 3 the steam engine in every phase; the solo rider (crew 1) is peer 1 on the diesel. (v3
## retired the Bulwark's hoist pattern and its tests.)

const H := preload("res://tests/games/tank/effort/tank_effort_harness.gd")

## ashfall_road phase indexes.
const DEPOT := 0
const ADV1 := 1
const GUN1 := 2
const CP1 := 3
const BOSS := 10
const COOLDOWN := 11
## 10 / 3: a bank update of <= 10 points in three sub-steps 1 s apart (brief: "<= 3.3% FTP/s").
const BANK_RATE := 10.0 / 3.0


func _h(crew: int = 3, mission: String = "ashfall_road", rotation: bool = true) -> H:
	var h := H.new()
	h.build(crew, mission, rotation)
	return h


func _dyn(h: H) -> TankDynamoState:
	return h.state.station(TankIds.ENGINE_DYNAMO) as TankDynamoState


func _steam(h: H) -> TankSteamState:
	return h.state.station(TankIds.ENGINE_STEAM) as TankSteamState


func _hit(dmg: float) -> Dictionary:
	return TankEvents.hit(TankEvents.ON_TANK, 0, dmg, TankIds.SHELL_ENEMY, 0.0, 0.0)


func _boss_hit() -> Dictionary:
	return TankEvents.hit(TankEvents.ON_TANK, 0, 20.0, TankIds.SHELL_BOSS_MAIN, 0.0, 0.0)


func _ev(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in list:
		out.append(e)
	return out


func _bank_dict(pct: float) -> Dictionary:
	return {"mode": "ERG", "target_pct": pct, "duration_s": 0.0, "reason": "bank", "source": "tank"}


func _grade_dict(grade: float, reason: String) -> Dictionary:
	return {
		"mode": "SIM", "mode_grade": grade, "duration_s": 0.0, "reason": reason, "source": "tank"
	}


func _haptic_dict(haptic: float, duration: float, reason: String) -> Dictionary:
	return {
		"mode": "SIM", "haptic": haptic, "duration_s": duration, "reason": reason, "source": "tank"
	}


## Asserts `got` ([tick, dict] rows) equals `want` ([tick, dict] rows), floats within 1e-6.
func _assert_rows(got: Array, want: Array, at: String) -> void:
	assert_eq(got.size(), want.size(), "%s: %d rows" % [at, want.size()])
	for i in mini(got.size(), want.size()):
		assert_eq(int(got[i][0]), int(want[i][0]), "%s row %d tick" % [at, i])
		var g: Dictionary = got[i][1]
		var w: Dictionary = want[i][1]
		assert_eq(_sorted(g.keys()), _sorted(w.keys()), "%s row %d keys" % [at, i])
		for k: String in w:
			if w[k] is float:
				assert_almost_eq(
					float(g.get(k, NAN)), float(w[k]), 1e-6, "%s row %d %s" % [at, i, k]
				)
			else:
				assert_eq(g.get(k), w[k], "%s row %d %s" % [at, i, k])


func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


## The rows of `rows` ([tick, ...]) with t0 <= tick < t1.
func _between(rows: Array, t0: int, t1: int) -> Array:
	var out: Array = []
	for r: Array in rows:
		if int(r[0]) >= t0 and int(r[0]) < t1:
			out.append(r)
	return out


## The requests to `peer`.
func _to(h: H, peer: int) -> Array:
	var out: Array = []
	for r: Array in h.requests:
		if int(r[1]) == peer:
			out.append(r)
	return out


## The haptic requests.
func _haptics(h: H) -> Array:
	var out: Array = []
	for r: Array in h.requests:
		if (r[2] as Dictionary).has("haptic"):
			out.append(r)
	return out


# --- Pattern 1: the bank -------------------------------------------------------------------------


## A drained bank in Stage 1's Advance: target 100%, reached from the planned 55% in updates of
## <= 10 points every 5 s, each in three sub-steps 1 s apart.
func test_bank_updates_climb_in_three_sub_steps() -> void:
	var h := _h()
	_dyn(h).bank = 0.0
	h.run_s(ADV1, 30.0)
	var want: Array = []
	var cur := 55.0
	for update in 5:
		var goal := minf(cur + 10.0, 100.0)
		for k in 3:
			var pct := cur + (goal - cur) * float(k + 1) / 3.0 if k < 2 else goal
			want.append([update * 100 + k * 20, _bank_dict(pct)])
		cur = goal
	_assert_rows(h.sent(2, "bank"), want, "bank")
	assert_almost_eq(float(want[-1][1]["target_pct"]), 100.0, 1e-9)
	assert_eq(_to(h, 2).size(), 15)


## A full bank asks the planned 55% (nothing to send); a refilling bank falls by <= 10 points an
## update too.
func test_bank_falls_in_steps_and_holds_when_full() -> void:
	var h := _h()
	_dyn(h).bank = 100.0
	h.run_s(ADV1, 12.0)
	assert_eq(h.sent(2, "bank"), [], "full bank: the plan's 55% stands")
	_dyn(h).bank = 0.0
	h.run_s(ADV1, 18.0)  # updates at 15, 20, 25 s: up to 85
	_dyn(h).bank = 100.0
	h.clear()
	h.run_s(ADV1, 10.0)
	var rows := h.sent(2, "bank")
	assert_eq(rows.size(), 6)
	assert_almost_eq(float(rows[2][1]["target_pct"]), 75.0, 1e-9, "-10 in the first update")
	assert_almost_eq(float(rows[5][1]["target_pct"]), 65.0, 1e-9, "-10 in the next")


## Sub-step slew math: whatever the bank does, consecutive targets move <= 10/3% FTP and are >= 1 s
## apart (<= 3.3% FTP/s, so <= 30 W/s up to FTP 900 W), each update moves <= 10 points, and every
## target stays inside the phase's range.
func test_bank_slew_is_at_most_a_third_of_ten_points_a_second() -> void:
	var h := _h()
	for i in roundi(240.0 / Wl.SIM_DT):
		_dyn(h).bank = 50.0 + 50.0 * sin(float(i) * Wl.SIM_DT / 9.0)
		h.step(ADV1)
	var rows := h.sent(2, "bank")
	assert_gt(rows.size(), 20)
	var prev_t := -1000
	var prev := 55.0
	for r: Array in rows:
		var pct := float(r[1]["target_pct"])
		assert_between(pct, 55.0, 100.0)
		assert_lte(absf(pct - prev), BANK_RATE + 1e-9)
		assert_gte(int(r[0]) - prev_t, 20, "sub-steps >= 1 s apart")
		assert_lte(absf(pct - prev) / 100.0 * 900.0, 30.0 + 1e-6, "<= 30 W/s at FTP 900")
		prev_t = int(r[0])
		prev = pct
	for u in range(0, h.tick, 100):
		var inside := _between(rows, u, u + 100)
		if inside.size() > 1:
			var first := float(inside[0][1]["target_pct"])
			var last := float(inside[-1][1]["target_pct"])
			assert_lte(absf(last - first), 10.0 * 2.0 / 3.0 + 1e-9, "one update <= 10 points")


## The bank never runs in the depot (the plan's ramp), checkpoints, or the diesel's ERG 90% gun line;
## it runs in the gun line and the boss for the dynamo, and the drill's skirmish clamps it to 65%.
func test_bank_only_in_dynamo_phases_with_a_range() -> void:
	var h := _h()
	_dyn(h).bank = 0.0
	h.run_s(DEPOT, 12.0)
	h.run_s(CP1, 12.0)
	for r: Array in h.requests:
		assert_ne(str(r[2].get("reason")), "bank", "no bank in the depot or a checkpoint")
	h.clear()
	h.run_s(GUN1, 6.0)
	assert_eq(h.sent(1, "bank"), [], "the diesel's ERG 90% gun line")
	assert_eq(h.sent(2, "bank").size(), 4, "the dynamo's gun line: 0, 1, 2 and 5 s")
	var d := _h(2, "drill")
	_dyn(d).bank = 0.0
	d.run_s(0, 10.0)
	assert_eq(d.sent(2, "bank"), [], "drill depot")
	d.run_s(1, 30.0)
	var rows := d.sent(2, "bank")
	assert_gt(rows.size(), 0)
	for r: Array in rows:
		assert_between(float(r[1]["target_pct"]), 55.0, 65.0, "drill skirmish range")
	assert_almost_eq(float(rows[-1][1]["target_pct"]), 65.0, 1e-9)


## A refused bank sub-step does not move the director's idea of the target.
func test_a_refused_bank_step_is_not_counted() -> void:
	var h := _h()
	var refusing := RefusingDirectives.new()
	h.ctx.directives = refusing
	_dyn(h).bank = 0.0
	refusing.refuse_reason = "bank"
	h.run_s(ADV1, 5.0)
	refusing.refuse_reason = ""
	h.run_s(ADV1, 1.0)
	var rows := h.sent(2, "bank")
	assert_eq(rows.size(), 4, "3 refused, then the first sub-step of the next update")
	assert_almost_eq(float(rows[3][1]["target_pct"]), 55.0 + BANK_RATE, 1e-9, "from 55 again")


## S1: a rider on reserve gets no bank update; after it is back the first update is again within
## 10 / 3 points of what its governor holds (a restarted client resumes at the plan's 55%, an
## in-process one at what it held), however far the bank target ran while it was away.
func test_bank_restarts_from_the_held_target_after_a_reserve() -> void:
	for how in ["dropped", "afk"]:
		for held in [55.0, 58.0]:
			var h := _h()
			_dyn(h).bank = 0.0
			h.run_s(ADV1, 10.0)
			h.clear()
			if how == "dropped":
				h.connected[2] = false
			else:
				h.afk[2] = true
			h.run_s(ADV1, 30.0)
			assert_eq(h.sent(2, "bank"), [], "%s: nothing is sent to a rider on reserve" % how)
			if how == "dropped":
				h.connected[2] = true
			else:
				h.afk[2] = false
			h.held_pct[2] = held
			_dyn(h).bank = 50.0  # the goal moves: 77.5%
			h.run_s(ADV1, 30.0)
			var rows := h.sent(2, "bank")
			assert_gt(rows.size(), 3, "%s: the bank follows again" % how)
			var prev: float = held
			for r: Array in rows:
				var pct := float(r[1]["target_pct"])
				assert_lte(absf(pct - prev), BANK_RATE + 1e-9, "%s/%s: from %s" % [how, held, prev])
				prev = pct
			assert_lte(float(rows[0][1]["target_pct"]), held + BANK_RATE + 1e-9)
			assert_almost_eq(prev, 77.5, 1e-9, "and reaches the bank's target")


## The bank restarts from the plan when the returning rider's governor reports no ERG target, and
## reseeds undoing the 0.85 unverified factor.
func test_held_pct_falls_back_to_the_plan_and_undoes_the_unverified_factor() -> void:
	var h := _h()
	var ph: PlanPhase = h.plan(2).phase(ADV1)
	var ri := TankRiderInput.new()
	ri.ftp = 200.0
	ri.ftp_verified = true
	ri.mode = Wl.ERG
	assert_eq(TankDirector.held_pct(ri, ph, 55.0), 55.0, "no target reported: the plan")
	ri.applied_target_w = 130.0  # 65%
	assert_almost_eq(TankDirector.held_pct(ri, ph, 55.0), 65.0, 1e-9)
	ri.ftp_verified = false
	ri.applied_target_w = 0.85 * 130.0
	assert_almost_eq(TankDirector.held_pct(ri, ph, 55.0), 65.0, 1e-9, "x0.85 undone")
	ri.applied_target_w = 100.0  # 50% (rescue): clamped into the phase's range
	assert_almost_eq(TankDirector.held_pct(ri, ph, 55.0), 58.8, 0.1)
	ri.mode = Wl.SIM
	assert_eq(TankDirector.held_pct(ri, ph, 55.0), 55.0, "not in ERG: the plan")


# --- Pattern 2: the boiler -----------------------------------------------------------------------


## Full pressure in Stage 1's Advance: 0.5% a second up to 8%, then nothing; a latch drops it to 0
## in one step (at most once per second), the breech cycle holds 0, and it climbs again after.
func test_boiler_rises_half_a_percent_a_second_and_drops_in_one_step() -> void:
	var h := _h()
	_steam(h).pressure_pct = 100.0
	h.run_s(ADV1, 20.0)
	var want: Array = []
	for k in 16:
		want.append([k * 20, _grade_dict(0.5 * (k + 1), "boiler")])
	_assert_rows(h.sent(3, "boiler"), want, "boiler rise")
	h.clear()
	h.run(ADV1, 5)
	_steam(h).loaded = true
	_steam(h).pressure_pct = 0.0
	h.run_s(ADV1, 3.0)
	_steam(h).loaded = false
	_steam(h).cycling = true
	h.run_s(ADV1, 6.0)
	_assert_rows(h.sent(3, "boiler"), [[405, _grade_dict(0.0, "boiler")]], "the latch drop")
	_steam(h).cycling = false
	_steam(h).pressure_pct = 50.0
	h.clear()
	h.run_s(ADV1, 10.0)
	var rows := h.sent(3, "boiler")
	assert_eq(rows.size(), 8, "0.5 .. 4.0")
	assert_almost_eq(float(rows[-1][1]["mode_grade"]), 4.0, 1e-9)


## S1: the boiler sends nothing to a rider on reserve and restarts from 0 when it is back: a
## restarted client rides mode_grade 0, so the first step is <= 0.5%.
func test_boiler_restarts_from_zero_after_a_reserve() -> void:
	var h := _h()
	_steam(h).pressure_pct = 100.0
	h.run_s(ADV1, 14.0)
	assert_almost_eq(float(h.sent(3, "boiler")[-1][1]["mode_grade"]), 7.0, 1e-9)
	h.clear()
	h.connected[3] = false
	h.run_s(ADV1, 10.0)
	assert_eq(h.sent(3, "boiler"), [], "nothing to a dropped steam rider")
	h.connected[3] = true
	h.run_s(ADV1, 5.0)
	var rows := h.sent(3, "boiler")
	assert_gt(rows.size(), 3)
	var prev := 0.0
	for r: Array in rows:
		var g := float(r[1]["mode_grade"])
		assert_lte(g - prev, 0.5 + 1e-9, "rise <= 0.5% from the client's 0")
		prev = g


## Every boiler send is >= 1 s after the previous one and rises <= 0.5%, whatever the pressure.
func test_boiler_spacing_and_rise_limit() -> void:
	var h := _h()
	for i in roundi(120.0 / Wl.SIM_DT):
		var s := _steam(h)
		s.pressure_pct = fmod(float(i) * 0.9, 130.0)
		s.loaded = i % 600 > 520
		h.step(ADV1)
	var rows := h.sent(3, "boiler")
	assert_gt(rows.size(), 20)
	var prev := 0.0
	var prev_t := -1000
	for r: Array in rows:
		var g := float(r[1]["mode_grade"])
		assert_between(g, 0.0, 8.0)
		assert_lte(g - prev, 0.5 + 1e-9, "rise <= 0.5% a step")
		assert_gte(int(r[0]) - prev_t, 20, "<= once per second")
		prev = g
		prev_t = int(r[0])


## The depot (WARMUP): 3% x min(pressure, 1), never above +3% even when pressure overshoots.
func test_boiler_in_the_depot_stays_within_3_percent() -> void:
	var h := _h()
	_steam(h).pressure_pct = 104.0
	h.run_s(DEPOT, 15.0)
	var rows := h.sent(3, "boiler")
	assert_eq(rows.size(), 6, "0.5 .. 3.0")
	for r: Array in rows:
		assert_lte(float(r[1]["mode_grade"]), 3.0)
	assert_almost_eq(float(rows[-1][1]["mode_grade"]), 3.0, 1e-9)
	var d := _h(3, "drill")
	_steam(d).pressure_pct = 50.0
	d.run_s(1, 10.0)
	assert_almost_eq(float(d.sent(3, "boiler")[-1][1]["mode_grade"]), 1.5, 1e-9, "drill skirmish")


## No boiler in a checkpoint (ERG 50% for everyone) or for a rider who isn't on steam.
func test_no_boiler_outside_the_steam_riders_sim_phases() -> void:
	var h := _h()
	_steam(h).pressure_pct = 100.0
	h.run_s(CP1, 10.0)
	for r: Array in h.requests:
		assert_ne(str(r[2].get("reason")), "boiler")
	h.run_s(ADV1, 3.0)
	for r: Array in h.requests:
		assert_eq(int(r[1]), 3, "only the steam rider gets the boiler")


# --- Pattern 4: terrain --------------------------------------------------------------------------


## course_grade at 2 Hz in grade_source "game" phases only: the diesel's Advance, its depot (clamped
## to 0..+2%), never the flat boss, the ERG gun line, the dynamo or the steam engine.
func test_terrain_at_2_hz_in_game_phases() -> void:
	var h := _h()
	h.state.hull.distance_m = 190.0
	h.run_s(ADV1, 2.0)
	var want: Array = []
	for k in 4:
		want.append([k * 10, 2.25])
	assert_eq(
		h.grades_of(1), want, "lerp(1.5, 3.0, 0.5) every 0.5 s (stage 1 points 130 m and 250 m)"
	)
	assert_eq(h.grades_of(2), [])
	assert_eq(h.grades_of(3), [])
	h.clear()
	h.run_s(GUN1, 3.0)
	h.run_s(BOSS, 3.0)
	assert_eq(h.grades, [], "no terrain in the ERG gun line or the flat boss")
	h.state.hull.distance_m = 400.0
	h.run_s(DEPOT, 1.0)
	assert_eq(h.grades_of(1), [[h.tick - 20, 2.0], [h.tick - 10, 2.0]], "depot")
	var b := _h(1)
	b.state.hull.distance_m = 1000.0
	b.run_s(ADV1, 1.0)
	assert_eq(b.grades_of(1).size(), 2, "the solo driver's Advance")


func test_terrain_grade_math() -> void:
	var c := TankFixtures.content()
	assert_almost_eq(TankDirector.terrain_grade_pct(c, ADV1, 0.0, false), 0.0, 1e-9)
	assert_almost_eq(TankDirector.terrain_grade_pct(c, ADV1, 250.0, false), 3.0, 1e-9)
	assert_almost_eq(TankDirector.terrain_grade_pct(c, ADV1, 510.0, false), -2.0, 1e-9)
	assert_almost_eq(TankDirector.terrain_grade_pct(c, ADV1, 9999.0, false), 0.0, 1e-9)
	var peak: Array = c.segment(7)["terrain"][2]
	assert_eq(float(peak[1]), 6.0, "stage 3's steepest point, +6%")
	assert_almost_eq(TankDirector.terrain_grade_pct(c, 7, float(peak[0]), false), 6.0, 1e-9)
	assert_almost_eq(TankDirector.terrain_grade_pct(c, ADV1, 250.0, true), 2.0, 1e-9, "warm-up")
	assert_almost_eq(TankDirector.terrain_grade_pct(c, GUN1, 50.0, false), 0.0, 1e-9, "no terrain")
	assert_eq(TankTerrain.grade_at([], 10.0), 0.0)
	assert_eq(TankTerrain.grade_at([[0, -9], [10, 20]], 5.0), 5.5)
	for seg in [0, 1, 4, 7]:
		for m in range(0, 1600, 25):
			var g := TankDirector.terrain_grade_pct(c, seg, float(m), seg == 0)
			assert_between(g, 0.0 if seg == 0 else -3.0, 2.0 if seg == 0 else 6.0)
			assert_eq(g, TankTerrain.for_segment(c, seg, float(m), seg == 0), "one sampler")


# --- Pattern 5: cadence bands; the power band ----------------------------------------------------


## (60, 120) for everyone at each segment start; (50, 120) while the loader's shell is loaded or
## the breech cycles in a WORK phase, back to (60, 120) after; the warm-up keeps (60, 120).
func test_cadence_bands() -> void:
	var h := _h()
	_steam(h).loaded = true
	h.run_s(DEPOT, 2.0)
	for peer in [1, 2, 3]:
		assert_eq(h.bands_of(peer), [[0, 60.0, 120.0]], "depot peer %d" % peer)
	h.clear()
	_steam(h).loaded = false
	h.run_s(ADV1, 1.0)
	_steam(h).loaded = true
	h.run_s(ADV1, 1.0)
	_steam(h).loaded = false
	_steam(h).cycling = true
	h.run_s(ADV1, 1.0)
	_steam(h).cycling = false
	h.run_s(ADV1, 1.0)
	var t0 := h.tick - 80
	assert_eq(
		h.bands_of(3), [[t0, 60.0, 120.0], [t0 + 20, 50.0, 120.0], [t0 + 60, 60.0, 120.0]], "loader"
	)
	assert_eq(h.bands_of(1), [[t0, 60.0, 120.0]])
	h.clear()
	_steam(h).loaded = true
	h.run_s(CP1, 1.0)
	assert_eq(h.bands_of(3), [[h.tick - 20, 60.0, 120.0]], "checkpoint: the steam rider (peer 3)")


## The power band: 76-105% FTP for the diesel in WORK SIM phases, (0, 0) elsewhere,
## once at each segment start.
func test_power_band_at_each_segment_start() -> void:
	var h := _h()
	for index in [DEPOT, ADV1, GUN1, CP1, BOSS]:
		h.hud().power_band_at.clear()
		h.run_s(index, 1.0)
		var rows := h.hud().power_band_at
		assert_eq(rows.size(), 3, "phase %d: one per rider" % index)
		for r: Array in rows:
			var p := h.ctx.player(int(r[1]))
			var ph := h.plan(int(r[1])).phase(index)
			var want := TankDirector.power_band_pct(h.content, ph)
			assert_almost_eq(float(r[2]), want[0] / 100.0 * p.ftp, 1e-6)
			assert_almost_eq(float(r[3]), want[1] / 100.0 * p.ftp, 1e-6)
			var tempo := ph.kind == Wl.WORK and ph.mode == Wl.SIM
			tempo = tempo and str(ph.meta["engine"]) == "diesel"
			assert_eq(float(r[3]) > 0.0, tempo, "phase %d peer %d" % [index, r[1]])


# --- Pattern 6: haptics (brief 2.7) --------------------------------------------------------------


## A hit of >= 4 damage (medium and up, stations.json haptics.hit.min_damage): every rider in a SIM
## phase gets {SIM, 2.0, 1.5 s, "hit"}; the dynamo (ERG) gets none; a light tank's 2.5 is no haptic.
func test_hit_haptic_reaches_every_sim_rider() -> void:
	var h := _h()
	h.run_s(ADV1, 1.0)
	h.clear()
	h.step(ADV1, _ev([_hit(3.0)]))
	assert_eq(h.requests, [], "below 4 damage")
	h.step(ADV1, _ev([_hit(4.0)]))
	var t := h.tick - 1
	_assert_rows(h.sent(1, "hit"), [[t, _haptic_dict(2.0, 1.5, "hit")]], "diesel")
	_assert_rows(h.sent(3, "hit"), [[t, _haptic_dict(2.0, 1.5, "hit")]], "steam")
	assert_eq(h.sent(2, "hit"), [], "the dynamo is in ERG")


## ED-3: the hit haptic's threshold follows the balance retune. Every enemy gun above the light tank
## (medium, dug-in, heavy, destroyer) must reach `haptics.hit.min_damage` so brief 2.7's "medium and
## up" still fires, and the light tank's gun and the Behemoth's secondary must stay below it.
func test_every_non_light_gun_reaches_the_hit_haptic_threshold() -> void:
	var c := TankFixtures.content("ashfall_road")
	var min_damage := c.num("stations", "haptics.hit.min_damage", -1.0)
	assert_gt(min_damage, 0.0, "the threshold is in stations.json")
	var types: Dictionary = c.value("enemies", "types", {})
	assert_gte(types.size(), 5, "light, medium, destroyer, dug-in and heavy")
	for id: String in types:
		# Events carry the damage rounded to a whole number (TankEvents.hit).
		var dmg := float(roundi(float((types[id] as Dictionary).get("gun", {}).get("damage", 0.0))))
		if id == "light":
			assert_lt(dmg, min_damage, "a light tank's shell is no haptic")
		else:
			assert_gte(dmg, min_damage, "%s: a hit by its gun must fire the hit haptic" % id)
	var sec := float(c.value("enemies", "boss.secondary.damage", 0.0))
	assert_lt(sec, min_damage, "the Behemoth's secondary is no haptic")
	var main := float(c.value("enemies", "boss.main.damage", 0.0))
	assert_gt(main, min_damage, "the main gun has boss_hit anyway")


## A Behemoth main-gun hit is boss_hit {3.0, 2.0 s}, never also the hit haptic; an evaded shot
## (v2 removed the Ram and its haptic) sends nothing.
func test_boss_hit_haptics_and_nothing_for_an_evade() -> void:
	var h := _h()
	h.run_s(BOSS, 1.0)
	h.clear()
	h.step(BOSS, _ev([_hit(12.0), _boss_hit()]))
	var t := h.tick - 1
	_assert_rows(h.sent(1, "boss_hit"), [[t, _haptic_dict(3.0, 2.0, "boss_hit")]], "boss diesel")
	assert_eq(h.sent(1, "hit"), [])
	# Boss seats (v3, no rotation): peer 1 diesel, peer 2 dynamo (ERG), peer 3 steam.
	_assert_rows(h.sent(3, "boss_hit"), [[t, _haptic_dict(3.0, 2.0, "boss_hit")]], "boss steam")
	var r := _h()
	r.run_s(ADV1, 1.0)
	r.clear()
	r.step(ADV1, _ev([TankEvents.evade(9, 3, true, 0)]))
	assert_eq(_haptics(r), [], "an evaded shot is a miss: no haptic")
	r.step(ADV1, _ev([TankEvents.evade(9, 3, false), _hit(10.0)]))
	t = r.tick - 1
	_assert_rows(r.sent(1, "hit"), [[t, _haptic_dict(2.0, 1.5, "hit")]], "the driver")
	_assert_rows(r.sent(3, "hit"), [[t, _haptic_dict(2.0, 1.5, "hit")]], "the crew")


## The game drops a haptic that would start within 15 s of the end of the receiver's last one.
func test_haptic_spacing_of_15_s() -> void:
	var h := _h()
	h.run_s(ADV1, 1.0)
	h.clear()
	h.step(ADV1, _ev([_hit(10.0)]))  # ends 1.5 s later
	var t0 := h.tick - 1
	h.run_s(ADV1, 10.0)
	h.step(ADV1, _ev([_hit(10.0)]))
	h.run(ADV1, roundi(16.5 / Wl.SIM_DT) - (h.tick - t0) - 1)
	h.step(ADV1, _ev([_boss_hit()]))  # 16.45 s after t0: dropped
	h.step(ADV1, _ev([_hit(10.0)]))  # 16.5 s after t0: sent
	var rows := h.sent(1, "hit")
	assert_eq(rows.size(), 2)
	assert_eq(int(rows[1][0]) - t0, roundi(16.5 / Wl.SIM_DT))
	assert_eq(h.sent(1, "boss_hit"), [])


## Never in WARMUP kinds, the first 300 s, the cool-down, to an ERG rider, an opted-out rider or
## one on reserve.
func test_haptic_gates() -> void:
	var events := _ev([_hit(20.0), TankEvents.evade(5, 3, true, 0)])
	var h := _h()
	h.plan_start_s = 400.0
	h.run_s(DEPOT, 1.0)
	h.step(DEPOT, events)
	assert_eq(_haptics(h), [], "WARMUP kind, even past 300 s")
	var w := _h()
	w.plan_start_s = 120.0
	w.run_s(ADV1, 1.0)
	w.step(ADV1, events)
	assert_eq(_haptics(w), [], "the first 300 s")
	var w2 := _h()
	w2.plan_start_s = 299.0
	w2.run_s(ADV1, 0.9)
	w2.step(ADV1, events)  # plan_elapsed 299.9
	w2.step(ADV1, events)  # plan_elapsed 299.95
	assert_eq(_haptics(w2), [], "before 300 s")
	w2.step(ADV1, events)  # plan_elapsed 300.0
	assert_eq(_haptics(w2).size(), 2, "from 300 s on: the hit for the driver and the loader")
	var b := _h(1)
	b.run_s(GUN1, 1.0)
	b.step(GUN1, events)
	assert_eq(b.requests, [], "the solo driver's ERG gun line")
	var e := _h()
	e.applied_mode[1] = Wl.ERG
	e.ctx.players[2].haptics_on = false
	e.run_s(ADV1, 1.0)
	e.step(ADV1, events)
	assert_eq(_haptics(e), [], "applied ERG (peer 1), opted out (peer 3)")
	var a := _h()
	a.afk[1] = true
	a.afk[3] = true
	a.run_s(ADV1, 1.0)
	a.step(ADV1, events)
	assert_eq(_haptics(a), [], "on reserve")
	var d := _h(3, "drill")
	d.plan_start_s = 400.0
	for i in 3:
		d.run_s(i, 1.0)
		d.step(i, events)
	assert_eq(_haptics(d), [], "the drill: no haptics")


# --- Pattern 7 and the cool-down -----------------------------------------------------------------


## end_phase for every rider in one step once the objective is done and min_s has passed; once.
func test_end_phase_all_riders_once_after_min_s() -> void:
	var h := _h()
	h.state.seg.objective_done = true
	h.run_s(ADV1, 89.95)
	assert_eq(h.ended, [], "before min_s")
	h.run_s(ADV1, 5.0)
	assert_eq(h.ended, [[1800, 1], [1800, 2], [1800, 3]], "all three at 90 s, one step")
	h.state.seg.objective_done = false
	h.run_s(DEPOT, 5.0)
	h.state.seg.objective_done = true
	h.run_s(DEPOT, 5.0)
	assert_eq(h.ended.size(), 3, "a fixed phase never ends early")


## The boss waits its `end_hold_s` (the Behemoth's death beat) after the objective is done, so the
## loader's last shell keeps its breech cycle (T3: >= 6 s at grade 0 per shell).
func test_the_boss_holds_a_death_beat_before_end_phase() -> void:
	var h := _h()
	var hold := float(h.content.segment(BOSS).get("end_hold_s", 0.0))
	assert_gte(hold, 6.0, "at least the 6 s breech cycle")
	h.run_s(BOSS, 130.0)
	assert_eq(h.ended, [], "the objective is not done")
	h.state.seg.objective_done = true
	h.run_s(BOSS, hold - 0.5)
	assert_eq(h.ended, [], "the death beat")
	h.run_s(BOSS, 1.0)
	assert_eq(h.ended.size(), 3, "then all three riders in one step")


## S4: the death beat never runs the boss into max_s (an overrun would cost a won mission its
## score): a boss killed with less than the hold left ends at max_s - 0.2 s at the latest.
func test_a_late_boss_kill_ends_before_max_s() -> void:
	var h := _h()
	var max_s := h.plan(1).phase(BOSS).max_s
	h.run_s(BOSS, max_s - 4.0)
	h.state.seg.objective_done = true
	h.run_s(BOSS, 3.9)
	assert_eq(h.ended.size(), 3, "all three riders end in one step")
	var tick_at: int = h.ended[0][0]
	assert_lt(float(tick_at) * Wl.SIM_DT, max_s - 0.05, "before the platform's max_s")
	assert_gt(float(tick_at) * Wl.SIM_DT, max_s - 0.35, "the death beat holds as long as it can")


## RN-5: a refused end_phase is retried on the next tick, never twice for an accepted rider, and a
## rider that keeps being refused is retried at a slow pace (no log flood).
func test_a_refused_end_phase_is_retried() -> void:
	var h := _h()
	var dirs := EndRefusingDirectives.new()
	h.ctx.directives = dirs
	dirs.refuse = {2: 1}
	h.state.seg.objective_done = true
	h.run_s(ADV1, 91.0)
	assert_eq(h.ended, [[1800, 1], [1800, 3], [1801, 2]], "peer 2 is asked again the next tick")
	assert_eq(dirs.calls, [1, 2, 3, 2], "nobody is asked twice once accepted")
	var slow := _h()
	var stuck := EndRefusingDirectives.new()
	slow.ctx.directives = stuck
	stuck.refuse = {2: 1000}
	slow.state.seg.objective_done = true
	slow.run_s(ADV1, 95.0)
	assert_eq(slow.ended.size(), 2, "the others went")
	var asks := stuck.calls.filter(func(p: int) -> bool: return p == 2).size()
	assert_between(asks, 4, 9, "about once a second after the first retry")
	assert_eq(stuck.calls.filter(func(p: int) -> bool: return p == 1).size(), 1)


## Nothing in the cool-down: no request, course grade, band or end_phase, whatever happens.
func test_nothing_is_sent_in_the_cooldown() -> void:
	var h := _h()
	h.run_s(BOSS, 2.0)
	var counts := [h.requests.size(), h.grades.size(), h.bands.size(), h.ended.size()]
	var pb := h.hud().power_band_at.size()
	_dyn(h).bank = 0.0
	_steam(h).pressure_pct = 100.0
	_steam(h).loaded = true
	h.state.seg.objective_done = true
	for i in 400:
		h.step(COOLDOWN, _ev([_hit(30.0), _boss_hit(), TankEvents.evade(3, 3, true, 0)]))
	assert_eq([h.requests.size(), h.grades.size(), h.bands.size(), h.ended.size()], counts)
	assert_eq(h.hud().power_band_at.size(), pb)
	var b := _h(1)
	b.run_s(BOSS, 1.0)
	b.clear()
	b.run_s(COOLDOWN, 10.0)
	assert_eq([b.requests, b.grades, b.bands], [[], [], []])


# --- Whole-plan sweep ----------------------------------------------------------------------------


## Every crew x rotation x content through every phase with every pattern busy (a draining and
## refilling bank, an arc load swinging between 0 and 1, full pressure with latches, rolling
## terrain, hits and boss hits every few seconds): every request matches its
## pattern, nothing SIM-only reaches an ERG phase, every ERG target is 50-100% inside the phase's
## range, haptics only past 300 s in WORK SIM phases and >= 15 s apart, terrain only in
## grade_source "game" phases.
func test_every_directive_in_every_phase_matches_its_pattern() -> void:
	for mission: String in ["ashfall_road", "drill"]:
		for crew in [1, 2, 3, 4]:
			for rotation in [true, false]:
				var h := _h(crew, mission, rotation)
				_sweep(h)
				_check_sweep(h, "%s crew %d rotation %s" % [mission, crew, rotation])


func _sweep(h: H) -> void:
	var n := h.plan(1).size()
	for index in n + 1:
		var ph := h.plan(1).phase(mini(index, n - 1))
		var seconds := minf(ph.duration_s, 40.0) if index < n else 20.0
		for i in roundi(seconds / Wl.SIM_DT):
			var t := float(i) * Wl.SIM_DT
			var dyn := _dyn(h)
			if dyn != null:
				dyn.bank = 0.0 if fmod(t, 30.0) < 15.0 else 100.0
			var arc := h.state.station(TankIds.ENGINE_ARC) as TankArcState
			if arc != null:
				arc.duty = 1.0 if fmod(t, 30.0) < 15.0 else 0.0
			var steam := _steam(h)
			if steam != null:
				steam.pressure_pct = minf(t * 6.0, 150.0)
				steam.loaded = fmod(t, 12.0) > 9.0
			h.state.hull.distance_m = t * 8.0
			var ev: Array[Dictionary] = []
			# A hit at 0 s, a boss hit at 17 s and an evaded shot at 34 s: each haptic lands just
			# past the 15 s spacing of the one before; the hits every 5 s in between are dropped.
			if i == 0 or i % 100 == 50:
				ev.append(_hit(9.0))
			if i == 340:
				ev.append(_boss_hit())
			if i == 680:
				ev.append(TankEvents.evade(4, 3, true, 0))
			h.step(index, ev)


func _check_sweep(h: H, at: String) -> void:
	var keys := {
		"bank": ["mode", "target_pct", "duration_s", "reason", "source"],
		"boiler": ["mode", "mode_grade", "duration_s", "reason", "source"],
		"hit": ["mode", "haptic", "duration_s", "reason", "source"],
		"boss_hit": ["mode", "haptic", "duration_s", "reason", "source"],
		"arc": ["mode", "target_pct", "duration_s", "reason", "source"],
	}
	var haptic_end := {}
	var reasons := {}
	for r: Array in h.requests:
		var peer := int(r[1])
		var d: Dictionary = r[2]
		var index := int(r[3])
		var plan := h.plan(peer)
		var where := "%s peer %d phase %d tick %d %s" % [at, peer, index, r[0], d]
		assert_lt(index, plan.size(), where + ": nothing in the cool-down")
		if index >= plan.size():
			continue
		var ph := plan.phase(index)
		var reason := str(d.get("reason", ""))
		reasons[reason] = true
		assert_has(keys, reason, where)
		assert_eq(str(d.get("source")), "tank", where)
		var want_keys: Array = keys.get(reason, [])
		var got_keys := d.keys()
		got_keys.sort()
		want_keys = want_keys.duplicate()
		want_keys.sort()
		assert_eq(got_keys, want_keys, where)
		if d.has("mode_grade") or d.has("haptic"):
			assert_eq(ph.mode, Wl.SIM, where + ": SIM-only directive in an ERG phase")
		if reason != "bank" and reason != "arc":
			assert_eq(str(d["mode"]), Wl.SIM, where + ": mode ERG belongs to the bank and arc only")
		if d.has("target_pct"):
			assert_eq(str(d["mode"]), Wl.ERG, where + ": bank and arc say mode ERG (brief 2.3)")
			assert_eq(ph.mode, Wl.ERG, where)
			var engine := str(ph.meta["engine"])
			if reason == "bank":
				assert_true(TankDirector.bank_phase(engine, ph), where)
			else:
				assert_true(TankDirector.arc_phase(engine, ph), where)
			var r2 := ph.effective_range()
			assert_between(float(d["target_pct"]), float(r2[0]), float(r2[1]), where)
			assert_between(float(d["target_pct"]), 50.0, 100.0, where)
		if reason == "boiler":
			assert_eq(str(ph.meta["engine"]), "steam", where)
			var top := 3.0 if ph.kind == Wl.WARMUP else 8.0
			assert_between(float(d["mode_grade"]), 0.0, top, where)
		if d.has("haptic"):
			assert_eq(ph.kind, Wl.WORK, where)
			assert_lte(float(d["haptic"]), 3.0, where)
			assert_lte(float(d["duration_s"]), 8.0, where)
			var t := float(r[0]) * Wl.SIM_DT
			assert_gte(h.nominal_start(index), 300.0, where + ": the first 300 s")
			assert_gte(t, float(haptic_end.get(peer, -INF)) + 15.0 - 1e-6, where + ": 15 s")
			haptic_end[peer] = t + float(d["duration_s"])
	for g: Array in h.grades:
		var peer := int(g[1])
		var index := int(g[3])
		var where := "%s course_grade peer %d phase %d" % [at, peer, index]
		assert_lt(index, h.plan(peer).size(), where + ": nothing in the cool-down")
		if index < h.plan(peer).size():
			var ph := h.plan(peer).phase(index)
			assert_eq([ph.mode, ph.grade_source], [Wl.SIM, Wl.GRADE_GAME], where)
			var lo := 0.0 if ph.kind == Wl.WARMUP else -3.0
			var hi := 2.0 if ph.kind == Wl.WARMUP else 6.0
			assert_between(float(g[2]), lo, hi, where)
	for b: Array in h.bands:
		assert_lt(int(b[4]), h.plan(int(b[1])).size(), at + ": no band in the cool-down")
		assert_has([[60.0, 120.0], [50.0, 120.0]], [b[2], b[3]], at)
	if str(h.ctx.content_id) == "ashfall_road":
		for reason: String in ["boiler", "hit", "boss_hit"]:
			if reason != "boiler" or h.ctx.players.size() >= 3:
				assert_true(reasons.has(reason), "%s: the sweep exercised %s" % [at, reason])
		if h.ctx.players.size() >= 2:
			assert_true(reasons.has("bank"), at + ": bank exercised")
		if h.ctx.players.size() == 4:
			assert_true(reasons.has("arc"), at + ": arc exercised")
		assert_false(reasons.has("ram"), at + ": v2 has no Ram haptic")


## A sink that refuses requests with one reason (for the accepted-only bookkeeping).
class RefusingDirectives:
	extends "res://tests/games/tank/tank_fakes.gd".Directives
	var refuse_reason: String = ""

	func request(peer: int, directive: EffortDirective) -> DirectiveResult:
		if directive.reason == refuse_reason:
			requests.append([peer, directive.to_dict()])
			return DirectiveResult.refused("test")
		return super.request(peer, directive)


class EndRefusingDirectives:
	extends "res://tests/games/tank/tank_fakes.gd".Directives
	## peer -> how many end_phase calls to refuse.
	var refuse: Dictionary = {}
	## Every peer end_phase was called for, in order.
	var calls: Array = []

	func end_phase(peer: int) -> bool:
		calls.append(peer)
		if int(refuse.get(peer, 0)) > 0:
			refuse[peer] = int(refuse[peer]) - 1
			return false
		return super.end_phase(peer)
