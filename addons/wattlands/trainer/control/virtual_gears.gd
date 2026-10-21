class_name VirtualGears
extends RefCounted
## Virtual gears (BRIEF 4.5): 24 gears on shift_up / shift_down, each a SIM grade offset,
## for single-speed riders (and useful with a cassette). Owned by trainer-control; the
## SafetyGovernor holds one per rider and stacks the offset in 4.6.6:
##   base grade = (course grade + mode grade) x difficulty + offset_pct(base), then the user's
##   range clamp.
##
## Tuning: gear g multiplies the trainer's resistance at a fixed reference flywheel speed by
## STEP_RATIO^(g - NEUTRAL), so one step changes resistance at constant flywheel speed by
## about 7% (BRIEF: 6-8%). Resistance follows the FTMS simulation model the trainer uses:
##   F = m g (crr cos th + sin th) + cw v^2      (no wind)
## at REF_SPEED_KMH with REF_MASS_KG, REF_CRR and REF_CW, and the offset is the grade change
## that adds (STEP_RATIO^(g - NEUTRAL) - 1) x F(base) at that speed. For a base grade at or
## above 0% each step is exactly STEP_RATIO at the reference speed; below 0% the steps use the
## flat-road force (so a descent never makes the gears vanish). The approximation, and how the
## step size drifts away from the reference speed, is recorded in
## docs/decisions/trainer-control.md. NEUTRAL (gear 12) adds 0%.

const COUNT := 24
const NEUTRAL := 12
const STEP_RATIO := 1.07
const REF_SPEED_KMH := 30.0
const REF_MASS_KG := 83.0
const REF_CRR := 0.004
const REF_CW := 0.51
const G := 9.80665

var gear: int = NEUTRAL


static func create(p_gear: int = NEUTRAL) -> VirtualGears:
	var v := VirtualGears.new()
	v.gear = clampi(p_gear, 1, COUNT)
	return v


## Move by `delta` gears within 1..COUNT; returns the new gear.
func shift(delta: int) -> int:
	gear = clampi(gear + delta, 1, COUNT)
	return gear


func set_gear(p_gear: int) -> int:
	gear = clampi(p_gear, 1, COUNT)
	return gear


## The current gear's grade offset in % on top of `base_grade_pct`.
func offset_pct(base_grade_pct: float = 0.0) -> float:
	return offset_for(gear, base_grade_pct)


## Grade offset in % for gear `g` on top of `base_grade_pct`.
static func offset_for(g: int, base_grade_pct: float = 0.0) -> float:
	var gg := clampi(g, 1, COUNT)
	if gg == NEUTRAL:
		return 0.0
	var f_base := resistance_n(base_grade_pct)
	var f_ref := maxf(f_base, resistance_n(0.0))
	var k := pow(STEP_RATIO, float(gg - NEUTRAL))
	return grade_for_resistance(f_base + f_ref * (k - 1.0)) - base_grade_pct


## Resistance force in newtons at `grade_pct` and `speed_kmh` (FTMS simulation model).
static func resistance_n(grade_pct: float, speed_kmh: float = REF_SPEED_KMH, mass_kg: float = REF_MASS_KG,
		crr: float = REF_CRR, cw: float = REF_CW) -> float:
	var th := atan(grade_pct / 100.0)
	var v := speed_kmh / 3.6
	return mass_kg * G * (crr * cos(th) + sin(th)) + cw * v * v


## The grade in % whose resistance at `speed_kmh` is `force_n` (inverse of resistance_n).
static func grade_for_resistance(force_n: float, speed_kmh: float = REF_SPEED_KMH, mass_kg: float = REF_MASS_KG,
		crr: float = REF_CRR, cw: float = REF_CW) -> float:
	var v := speed_kmh / 3.6
	# crr cos th + sin th = r sin(th + phi), r = sqrt(1 + crr^2), phi = atan(crr).
	var c := (force_n - cw * v * v) / (mass_kg * G)
	var r := sqrt(1.0 + crr * crr)
	var th := asin(clampf(c / r, -1.0, 1.0)) - atan(crr)
	th = clampf(th, -1.4, 1.4)
	return tan(th) * 100.0
