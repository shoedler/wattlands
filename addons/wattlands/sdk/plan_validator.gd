class_name PlanValidator
extends RefCounted
## Validates EffortPlans against BRIEF 4.6 and the warm-up limits, then appends the
## 3-minute cool-down at 50% FTP (BRIEF 3.6). Owned by sdk-runtime; public API frozen after
## W0. It only accepts or rejects (the .zwo importer clamps before it runs).
##
## Rejects a plan whose first 300 s break the warm-up limits (4.6.8: every ERG target,
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


## {"ok": bool, "errors": Array[String], "warnings": Array[String]}. `opts`:
## {"ramp_test": bool} (the FTP test's profile, BRIEF 3.2: duration limits, the long-phase
## cap and the 150% cap do not apply). The warm-up rules always apply to plans, even for a
## rider who skipped warm-up in settings (that only changes the governor).
static func validate(_plan: EffortPlan, _opts: Dictionary = {}) -> Dictionary:
	return {"ok": false, "errors": ["not implemented"], "warnings": []}


## Validate, and on success return a copy with the cool-down appended (cooldown_appended
## = true). Returns null (and push_warning with the errors) when rejected.
static func finalize(_plan: EffortPlan, _opts: Dictionary = {}) -> EffortPlan:
	return null


## The appended cool-down phase (COOLDOWN, ERG 50%, 180 s, lap = true, label "Cool-down").
static func cooldown_phase() -> PlanPhase:
	return PlanPhase.erg(Wl.COOLDOWN, COOLDOWN_PCT, COOLDOWN_S, "Cool-down").with_lap()
