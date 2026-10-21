extends "res://tests/scenarios/lib/scenario_test.gd"
## BRIEF 7.4, rescue (4.6.3): with a verified-FTP mock rider, rescue triggers on a cadence
## collapse in every ERG phase while the applied target is >= 60 % FTP (every WORK interval,
## Easy 30's main set, the warm-up ramp once it passes 60 %) and never while it is below 60 %
## (RECOVERY, COOLDOWN, the warm-up ramp before 60 %). Owned by qa; a W2 gate.
##
## For each built-in session the test reads the rider's validated plan, schedules one
## `cadence_drop` (30 rpm for 8 s) per ERG phase in a single composed MockTrainer profile
## (`at_target_pct=60` where a ramp crosses 60 %, BRIEF 4.2), steps the session tick by tick, and
## checks every collapse episode: rescue within the drop when the applied target was >= 60 % at
## its start, no rescue otherwise. It also checks that rescue never starts outside a collapse.

const DROP_RPM := 30
const DROP_S := 8.0
const COLLAPSE_RPM := 45.0
## Rescue may begin up to this long after the cadence recovered (the 3 s rule plus a sample).
const RESCUE_GRACE_S := 2.0
const MAX_TICKS := int(3.0 * 3600.0 / 0.05)


## The rider's validated plan as phase dictionaries: from the report once the session started,
## else from the game's own build_effort_plans() through PlanValidator.finalize.
func _plan(runner: GameSimRunner, peer: int) -> Array:
	for i in 3:
		runner.step()
	var phases := S.plan_phases(runner.build_report(), peer)
	if not phases.is_empty():
		return phases
	if runner.host != null and runner.host.game != null:
		var raw: Variant = runner.host.game.build_effort_plans().get(peer, null)
		if raw is EffortPlan:
			var fin := PlanValidator.finalize(raw as EffortPlan)
			if fin != null:
				return (fin.to_dict()["phases"] as Array)
	return []


## [{phase, after_s, at_target_pct (or -1), expect_rescue}] for a plan, in time order.
static func schedule(plan: Array) -> Array:
	var out: Array = []
	for i in plan.size():
		var ph: Dictionary = plan[i]
		if str(ph.get("mode", Wl.ERG)) != Wl.ERG:
			continue
		var start := float(ph.get("target_pct", 0.0))
		var end := float(ph.get("ramp_to_pct", start)) if float(ph.get("ramp_to_pct", -1.0)) >= 0.0 else start
		var dur := float(ph.get("min_s", 0.0)) if bool(ph.get("open_ended", false)) else float(ph.get("duration_s", 0.0))
		if dur < 20.0:
			continue
		var lo := minf(start, end)
		var hi := maxf(start, end)
		if hi < S.RESCUE_MIN_PCT - S.EPS:
			out.append({"phase": i, "after_s": minf(10.0, dur / 3.0), "at_target_pct": -1.0, "expect_rescue": false})
		elif lo >= S.RESCUE_MIN_PCT - S.EPS:
			out.append({"phase": i, "after_s": 5.0, "at_target_pct": -1.0, "expect_rescue": true})
		elif end > start:
			# A rising ramp across 60 %: one drop well before the crossing, one after it.
			var t_cross := dur * (S.RESCUE_MIN_PCT - start) / (end - start)
			if t_cross >= 30.0:
				out.append({"phase": i, "after_s": minf(20.0, t_cross / 3.0), "at_target_pct": -1.0, "expect_rescue": false})
			if dur - t_cross >= 20.0:
				out.append({"phase": i, "after_s": 3.0, "at_target_pct": S.RESCUE_MIN_PCT, "expect_rescue": true})
	return out


static func profile(drops: Array) -> String:
	var parts := PackedStringArray(["erg"])
	for d: Dictionary in drops:
		var spec := "cadence_drop:rpm=%d,at_phase=%d,after_s=%s,for_s=%s" % [DROP_RPM, int(d["phase"]), _n(float(d["after_s"])), _n(DROP_S)]
		if float(d["at_target_pct"]) >= 0.0:
			spec += ",at_target_pct=%s" % _n(float(d["at_target_pct"]))
		parts.append(spec)
	return "+".join(parts)


## A number for a profile spec: "3" for 3.0, "6.67" for 6.666.
static func _n(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.2f" % v


func test_schedule_covers_every_erg_phase() -> void:
	# Pure check of the scheduling rule on a VO2-like plan.
	var plan: Array = [
		PlanPhase.erg(Wl.WARMUP, 50, 300, "Warm-up").with_ramp(65).to_dict(),
		PlanPhase.erg(Wl.WORK, 110, 180, "Interval").to_dict(),
		PlanPhase.erg(Wl.RECOVERY, 50, 180, "Easy").to_dict(),
		PlanPhase.sim(Wl.FREE, Wl.GRADE_FLAT, 30, "Sprint").to_dict(),
		PlanPhase.erg(Wl.COOLDOWN, 50, 180, "Cool-down").to_dict(),
	]
	var s := schedule(plan)
	var by_phase := s.map(func(d: Dictionary) -> String: return "%d:%s" % [int(d["phase"]), str(d["expect_rescue"])])
	assert_eq(by_phase, ["0:false", "0:true", "1:true", "2:false", "4:false"])
	assert_eq(profile([s[1]]), "erg+cadence_drop:rpm=30,at_phase=0,after_s=3,for_s=8,at_target_pct=60")


func test_rescue_follows_the_60_percent_rule(p: Variant = use_parameters(S.WORKOUT_SESSIONS)) -> void:
	var content := str(p)
	var probe := start_runner(S.flags(content, report_path("%s_plan" % content)))
	if probe == null:
		return
	var plan := _plan(probe, S.human_peer(probe))
	assert_false(plan.is_empty(), "%s: the rider's validated plan" % content)
	var drops := schedule(plan)
	assert_gt(drops.filter(func(d: Dictionary) -> bool: return bool(d["expect_rescue"])).size(), 0, "%s has ERG time at >= 60 %%" % content)
	assert_gt(drops.filter(func(d: Dictionary) -> bool: return not bool(d["expect_rescue"])).size(), 0, "%s has ERG time below 60 %%" % content)

	var runner := start_runner(S.flags(content, report_path(content), ["--rider=%s" % profile(drops), "--bots=0"]))
	if runner == null:
		return
	var rider := human_rider(runner)
	if rider == null:
		return
	var mock := S.mock_of(rider)
	var episodes: Array = []
	var current: Dictionary = {}
	var stray: Array[String] = []
	var was_rescue := false
	var ticks := 0
	while not runner.host.is_finished() and ticks < MAX_TICKS:
		runner.step()
		ticks += 1
		var t := S.platform_t(runner, rider)
		var st := rider.governor.status()
		var s := mock.last_sample()
		var collapsed := s != null and s.has_cadence() and s.cadence_rpm < COLLAPSE_RPM
		if collapsed and current.is_empty():
			current = {"t": t, "end": -1.0, "phase": int(st.get("phase_index", -1)), "pct": float(st.get("applied_pct", 0.0)), "mode": str(st.get("mode", "")), "rescue": false}
			episodes.append(current)
		if not current.is_empty():
			if not collapsed and float(current["end"]) < 0.0:
				current["end"] = t
			if bool(st.get("rescue", false)):
				current["rescue"] = true
			if float(current["end"]) >= 0.0 and t > float(current["end"]) + RESCUE_GRACE_S:
				current = {}
		var rescue := bool(st.get("rescue", false))
		if rescue and not was_rescue and current.is_empty():
			stray.append("t=%.2f: rescue started without a cadence collapse (phase %d, %.1f %% FTP)" % [t, int(st.get("phase_index", -1)), float(st.get("applied_pct", 0.0))])
		was_rescue = rescue
	assert_true(runner.host.is_finished(), "%s finished" % content)
	assert_eq(stray, [] as Array[String], first(stray))
	assert_eq(episodes.size(), drops.size(), "%s: one collapse per scheduled drop (%s)" % [content, str(episodes)])
	for i in mini(episodes.size(), drops.size()):
		var ep: Dictionary = episodes[i]
		var d: Dictionary = drops[i]
		var where := "%s drop %d (phase %d, %.1f %% FTP at t=%.1f)" % [content, i, int(ep["phase"]), float(ep["pct"]), float(ep["t"])]
		assert_eq(int(ep["phase"]), int(d["phase"]), "%s happened in the scheduled phase" % where)
		assert_eq(ep["mode"], Wl.ERG, "%s: in ERG" % where)
		var at_or_above := float(ep["pct"]) >= S.RESCUE_MIN_PCT - S.EPS
		assert_eq(bool(ep["rescue"]), at_or_above, "%s: rescue iff the applied target was >= 60 %% FTP" % where)
		assert_eq(bool(ep["rescue"]), bool(d["expect_rescue"]), "%s: rescue %s as planned" % [where, "expected" if bool(d["expect_rescue"]) else "not expected"])
