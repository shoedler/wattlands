class_name PlanValidator
extends RefCounted
## Validates EffortPlans against BRIEF 4.6 and the warm-up limits, then appends the
## 3-minute cool-down at 50% FTP (BRIEF 3.6). Owned by sdk-runtime; public API frozen after
## W0. It only accepts or rejects (the .zwo importer clamps before it runs).
##
## Rejects a plan whose first 300 s (the half-open window [0, 300): a phase that starts at
## exactly 300 s is outside it) break the warm-up limits (4.6.8: every ERG target,
## ramp end and range_pct bound <= 65% FTP; SIM phases are allowed there because the
## governor clamps their grade to -2..+3 % and drops haptics during warm-up), or whose
## ERG phases break 4.6.1: any target/ramp/range_pct value above 150% or below 0; a phase
## longer than 300 s (worst case: max_s for open-ended phases) above 105%; more than 300 s
## accrued above 105% or 60 s above 120% without an intervening reset of >= 120 consecutive
## seconds of ERG at <= 90% (open-ended phases taken at max_s for accrual and at min_s for
## the reset and for which phases fall inside the first 300 s). Checks range_pct as well as
## target_pct and ramp_to_pct. Warns (not rejects) when two ERG<->SIM switches are less than
## 30 s apart (open-ended phases at min_s). Also rejects structural errors (unknown kind or
## mode, non-positive duration, open-ended without 0 < min_s <= max_s, course without a
## profile, empty plan, a COOLDOWN phase written by the game).
##
## Details (docs/decisions/sdk-runtime.md):
## - A phase's ERG peak is PlanPhase.peak_pct() (target, ramp end and range top). Directives
##   may hold the target anywhere in the effective range for the whole phase, so a phase
##   whose peak is above 105% (120%) accrues its whole worst-case length.
## - Thresholds are inclusive where BRIEF 4.6.1 says so: a peak of exactly 105% is neither
##   capped nor accrued; exactly 300 s (60 s) accrued is allowed; a reset run of exactly
##   120 s at exactly 90% resets.
## - Fixed phases need duration_s > 0; an open-ended phase may have duration_s 0 (its
##   nominal length), but a ramp on it needs duration_s > 0 (C15).
## - A finalized plan (cooldown_appended = true) is accepted when it ends with exactly one
##   standard cool-down; the rules run on the phases before it (C16). The switch-spacing
##   warning always includes the cool-down (appended or about to be).

const COOLDOWN_S := 180.0
const COOLDOWN_PCT := 50.0
const WARMUP_S := 300.0
const WARMUP_MAX_PCT := 65.0
const WARMUP_GRADE_MIN := -2.0
const WARMUP_GRADE_MAX := 3.0
const LONG_PHASE_S := 300.0
const LONG_PHASE_CAP_PCT := 105.0
const LIMIT_105_S := 300.0
const LIMIT_120_S := 60.0
const RESET_PCT := 90.0
const RESET_S := 120.0
const ABS_MAX_PCT := 150.0
const SWITCH_SPACING_S := 30.0
## Above this the 120% duration limit accrues.
const LIMIT_120_PCT := 120.0
## Comparison slack for float thresholds (percent and seconds).
const EPS := 1e-6


## {"ok": bool, "errors": Array[String], "warnings": Array[String]}. `opts`:
## {"ramp_test": bool} (the FTP test's profile, BRIEF 3.2: duration limits, the long-phase
## cap and the 150% cap do not apply). The warm-up rules always apply to plans, even for a
## rider who skipped warm-up in settings (that only changes the governor).
static func validate(plan: EffortPlan, opts: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if plan == null:
		errors.append("plan: null")
		return _result(errors, warnings)
	if plan.phases.is_empty():
		errors.append("plan: no phases")
		return _result(errors, warnings)
	var ramp_test := bool(opts.get("ramp_test", false))
	var phases: Array[PlanPhase] = plan.phases.duplicate()
	if plan.cooldown_appended:
		var last: PlanPhase = phases[phases.size() - 1]
		if not is_standard_cooldown(last):
			errors.append("phase %d: cooldown_appended is set but the last phase is not the standard cool-down (COOLDOWN, ERG %d%%, %d s)" % [phases.size() - 1, int(COOLDOWN_PCT), int(COOLDOWN_S)])
			return _result(errors, warnings)
		phases.pop_back()
		if phases.is_empty():
			errors.append("plan: no phases before the cool-down")
			return _result(errors, warnings)
	for i in phases.size():
		_check_structure(i, phases[i], errors)
	if not errors.is_empty():
		return _result(errors, warnings)
	_check_warmup(phases, errors)
	if not ramp_test:
		_check_caps(phases, errors)
		_check_accrual(phases, errors)
	_check_switch_spacing(phases, warnings)
	return _result(errors, warnings)


## Validate, and on success return a copy with the cool-down appended (cooldown_appended
## = true). Returns null (and push_warning with the errors) when rejected.
static func finalize(plan: EffortPlan, opts: Dictionary = {}) -> EffortPlan:
	var res := validate(plan, opts)
	if not bool(res["ok"]):
		push_warning("PlanValidator: plan rejected: %s" % "; ".join(res["errors"]))
		return null
	var out := plan.duplicate_plan()
	if not out.cooldown_appended:
		out.add(cooldown_phase())
		out.cooldown_appended = true
	return out


## The appended cool-down phase (COOLDOWN, ERG 50%, 180 s, lap = true, label "Cool-down").
static func cooldown_phase() -> PlanPhase:
	return PlanPhase.erg(Wl.COOLDOWN, COOLDOWN_PCT, COOLDOWN_S, "Cool-down").with_lap()


## True for exactly the phase cooldown_phase() builds (label aside).
static func is_standard_cooldown(p: PlanPhase) -> bool:
	return p != null and p.kind == Wl.COOLDOWN and p.mode == Wl.ERG \
		and absf(p.target_pct - COOLDOWN_PCT) < EPS and absf(p.duration_s - COOLDOWN_S) < EPS \
		and not p.open_ended and not p.has_ramp() and p.range_pct.is_empty()


## The plan's length with every open-ended phase at max_s (cool-down included if appended).
static func worst_case_length_s(plan: EffortPlan) -> float:
	return plan.max_length_s() if plan != null else 0.0


## The plan that results from keeping phases 0..current_index of `current` (a finalized
## plan; its cool-down is dropped) and appending `remaining` (phases without a cool-down).
## Not validated (replan validates the result as a whole).
static func spliced(current: EffortPlan, current_index: int, remaining: EffortPlan) -> EffortPlan:
	var out := EffortPlan.new()
	if current != null:
		var keep := mini(current_index + 1, current.phases.size())
		if current.cooldown_appended:
			keep = mini(keep, current.phases.size() - 1)
		for i in keep:
			out.phases.append(current.phases[i].duplicate_phase())
	if remaining != null:
		for p in remaining.phases:
			out.phases.append(p.duplicate_phase())
	return out


static func _result(errors: Array[String], warnings: Array[String]) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func _name(i: int, p: PlanPhase) -> String:
	if p.label != "":
		return "phase %d (%s)" % [i, p.label]
	return "phase %d" % i


static func _fmt(v: float) -> String:
	if is_nan(v) or is_inf(v):
		return str(v)
	var s := String.num(v, 2)
	if s.contains("."):
		s = s.rstrip("0").trim_suffix(".")
	return s


static func _finite(v: float) -> bool:
	return not is_nan(v) and not is_inf(v)


static func _check_structure(i: int, p: PlanPhase, errors: Array[String]) -> void:
	var n := _name(i, p)
	if p.kind == Wl.COOLDOWN:
		errors.append("%s: kind COOLDOWN is appended by the platform; a game never writes one" % n)
		return
	if not Wl.is_phase_kind(p.kind):
		errors.append("%s: unknown kind \"%s\"" % [n, p.kind])
	if p.mode != Wl.ERG and p.mode != Wl.SIM:
		errors.append("%s: unknown mode \"%s\" (ERG or SIM)" % [n, p.mode])
		return
	if not _finite(p.duration_s) or p.duration_s < 0.0:
		errors.append("%s: duration_s must be a finite number >= 0" % n)
	elif not p.open_ended and p.duration_s <= 0.0:
		errors.append("%s: duration_s must be > 0 for a fixed phase" % n)
	if p.open_ended:
		if not _finite(p.min_s) or not _finite(p.max_s) or p.min_s <= 0.0 or p.max_s < p.min_s:
			errors.append("%s: open_ended needs 0 < min_s <= max_s (min_s %s, max_s %s)" % [n, _fmt(p.min_s), _fmt(p.max_s)])
	if p.mode == Wl.ERG:
		if not _finite(p.target_pct) or p.target_pct < 0.0:
			errors.append("%s: target_pct must be a finite number >= 0" % n)
		if p.has_ramp():
			if not _finite(p.ramp_to_pct):
				errors.append("%s: ramp_to_pct must be finite" % n)
			if p.duration_s <= 0.0:
				errors.append("%s: a ramp needs duration_s > 0" % n)
		elif p.ramp_to_pct != PlanPhase.NONE:
			errors.append("%s: ramp_to_pct must be >= 0" % n)
		if not p.range_pct.is_empty():
			if p.range_pct.size() != 2:
				errors.append("%s: range_pct must be [lo, hi]" % n)
			else:
				var lo := float(p.range_pct[0])
				var hi := float(p.range_pct[1])
				if not _finite(lo) or not _finite(hi) or lo < 0.0 or hi < lo:
					errors.append("%s: range_pct must be [lo, hi] with 0 <= lo <= hi (got [%s, %s])" % [n, _fmt(lo), _fmt(hi)])
	else:
		match p.grade_source:
			Wl.GRADE_FLAT, Wl.GRADE_GAME:
				pass
			Wl.GRADE_COURSE:
				_check_course(n, p.course_profile, errors)
			_:
				errors.append("%s: unknown grade_source \"%s\" (flat, course or game)" % [n, p.grade_source])


static func _check_course(n: String, profile: Array, errors: Array[String]) -> void:
	if profile.is_empty():
		errors.append("%s: grade_source course needs a course_profile" % n)
		return
	var prev := -1.0
	for k in profile.size():
		var pt: Variant = profile[k]
		if not (pt is Array) or (pt as Array).size() < 2:
			errors.append("%s: course_profile[%d] must be [distance_m, grade_pct]" % [n, k])
			return
		var d := float(pt[0])
		var g := float(pt[1])
		if not _finite(d) or not _finite(g) or d < 0.0 or d <= prev:
			errors.append("%s: course_profile[%d] needs a finite distance ascending from 0 and a finite grade" % [n, k])
			return
		prev = d


## Start times with open-ended phases at min_s (which phases fall inside the first 300 s
## and where mode switches happen). One more entry than phases: the end.
static func _best_case_starts(phases: Array[PlanPhase]) -> Array[float]:
	var starts: Array[float] = []
	var t := 0.0
	for p in phases:
		starts.append(t)
		t += p.best_case_length_s()
	starts.append(t)
	return starts


static func _check_warmup(phases: Array[PlanPhase], errors: Array[String]) -> void:
	var starts := _best_case_starts(phases)
	for i in phases.size():
		if starts[i] >= WARMUP_S - EPS:
			break
		var p := phases[i]
		if p.mode != Wl.ERG:
			continue
		var n := _name(i, p)
		var checks: Array = [["target_pct", p.target_pct]]
		if p.has_ramp():
			checks.append(["ramp_to_pct", p.ramp_to_pct])
		if p.range_pct.size() == 2:
			checks.append(["range_pct[0]", float(p.range_pct[0])])
			checks.append(["range_pct[1]", float(p.range_pct[1])])
		for c: Array in checks:
			if float(c[1]) > WARMUP_MAX_PCT + EPS:
				errors.append("%s: %s %s%% > %s%% inside the first %d s (warm-up, BRIEF 4.6.8)" % [n, c[0], _fmt(float(c[1])), _fmt(WARMUP_MAX_PCT), int(WARMUP_S)])


static func _check_caps(phases: Array[PlanPhase], errors: Array[String]) -> void:
	for i in phases.size():
		var p := phases[i]
		if p.mode != Wl.ERG:
			continue
		var n := _name(i, p)
		var peak := p.peak_pct()
		if peak > ABS_MAX_PCT + EPS:
			errors.append("%s: peak %s%% > %s%% (BRIEF 4.6.1 ceiling)" % [n, _fmt(peak), _fmt(ABS_MAX_PCT)])
		if p.worst_case_length_s() > LONG_PHASE_S + EPS and peak > LONG_PHASE_CAP_PCT + EPS:
			errors.append("%s: peak %s%% > %s%% in a phase longer than %d s (worst case %s s, BRIEF 4.6.1)" % [n, _fmt(peak), _fmt(LONG_PHASE_CAP_PCT), int(LONG_PHASE_S), _fmt(p.worst_case_length_s())])


static func _check_accrual(phases: Array[PlanPhase], errors: Array[String]) -> void:
	var acc105 := 0.0
	var acc120 := 0.0
	var reset_run := 0.0
	var reported105 := false
	var reported120 := false
	for i in phases.size():
		var p := phases[i]
		if p.mode != Wl.ERG:
			reset_run = 0.0
			continue
		var peak := p.peak_pct()
		if peak <= RESET_PCT + EPS:
			reset_run += p.best_case_length_s()
			if reset_run >= RESET_S - EPS:
				acc105 = 0.0
				acc120 = 0.0
			continue
		reset_run = 0.0
		var length := p.worst_case_length_s()
		if peak > LONG_PHASE_CAP_PCT + EPS:
			acc105 += length
			if acc105 > LIMIT_105_S + EPS and not reported105:
				reported105 = true
				errors.append("%s: %s s accrued above 105%% without a reset (limit %d s, BRIEF 4.6.1)" % [_name(i, p), _fmt(acc105), int(LIMIT_105_S)])
		if peak > LIMIT_120_PCT + EPS:
			acc120 += length
			if acc120 > LIMIT_120_S + EPS and not reported120:
				reported120 = true
				errors.append("%s: %s s accrued above 120%% without a reset (limit %d s, BRIEF 4.6.1)" % [_name(i, p), _fmt(acc120), int(LIMIT_120_S)])


static func _check_switch_spacing(phases: Array[PlanPhase], warnings: Array[String]) -> void:
	var all: Array[PlanPhase] = phases.duplicate()
	all.append(cooldown_phase())
	var starts := _best_case_starts(all)
	var prev_switch_t := -INF
	var prev_switch_i := -1
	for i in range(1, all.size()):
		if all[i].mode == all[i - 1].mode:
			continue
		var t := starts[i]
		if prev_switch_i >= 0 and t - prev_switch_t < SWITCH_SPACING_S - EPS:
			warnings.append("phases %d and %d: ERG<->SIM switches %s s apart (< %d s, BRIEF 4.5)" % [prev_switch_i, i, _fmt(t - prev_switch_t), int(SWITCH_SPACING_S)])
		prev_switch_t = t
		prev_switch_i = i
