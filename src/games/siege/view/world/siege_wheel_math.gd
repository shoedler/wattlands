class_name SiegeWheelMath
extends RefCounted
## The treadwheel formulas of brief 3 "Scene" (pure; the wheel view and the tests share them).
##
## Rim speed = 1.2 m/s x P_eff / 250 W, up to 3 m/s. One to three workers walk at the bottom:
## one below 150 W, two up to 300 W, three above, with 20 W of hysteresis. A worker's step rate
## is cadence / 30 Hz and its stride is rim speed / step rate, clamped.

const WHEEL_RADIUS_M := 2.5
const RIM_SPEED_PER_250W := 1.2
const RIM_SPEED_MAX_MPS := 3.0
const REF_W := 250.0
## Cadence divisor: 90 rpm gives 3 steps a second.
const STEP_RATE_DIV := 30.0
const STRIDE_MIN_M := 0.12
const STRIDE_MAX_M := 0.6
## Worker count thresholds (P_eff W): 1 -> 2 at 150 W (inclusive), 2 -> 3 above 300 W.
const WORKERS_2_W := 150.0
const WORKERS_3_W := 300.0
const HYSTERESIS_W := 20.0
const MAX_WORKERS := 3


## Rim speed in m/s for `p_eff_w`: 1.2 x P_eff / 250, never below 0 or above 3.
static func rim_speed(p_eff_w: float) -> float:
	return clampf(RIM_SPEED_PER_250W * p_eff_w / REF_W, 0.0, RIM_SPEED_MAX_MPS)


## The wheel's angular speed in rad/s (rim speed over the 2.5 m radius).
static func angular_speed(p_eff_w: float) -> float:
	return rim_speed(p_eff_w) / WHEEL_RADIUS_M


## Steps per second of a worker at `cadence_rpm`: cadence / 30.
static func step_rate_hz(cadence_rpm: float) -> float:
	return maxf(cadence_rpm, 0.0) / STEP_RATE_DIV


## Stride length in metres: rim speed / step rate, clamped to 0.12 .. 0.6 m (0 with no steps).
static func stride_m(rim_speed_mps: float, step_rate: float) -> float:
	if step_rate <= 0.0 or rim_speed_mps <= 0.0:
		return 0.0
	return clampf(rim_speed_mps / step_rate, STRIDE_MIN_M, STRIDE_MAX_M)


## How many workers walk at `p_eff_w`, given the `current` count (1..3): the count rises at
## its threshold and falls only 20 W below it, so a rider hovering at 150 W or 300 W does not
## flicker.
static func worker_count(p_eff_w: float, current: int = 1) -> int:
	var n := clampi(current, 1, MAX_WORKERS)
	if n < 2 and p_eff_w >= WORKERS_2_W:
		n = 2
	if n < 3 and p_eff_w > WORKERS_3_W:
		n = 3
	if n >= 3 and p_eff_w < WORKERS_3_W - HYSTERESIS_W:
		n = 2
	if n >= 2 and p_eff_w < WORKERS_2_W - HYSTERESIS_W:
		n = 1
	return n


## Local x offsets (m along the tread) of `count` workers at the wheel's bottom.
static func worker_offsets(count: int) -> Array[float]:
	match clampi(count, 1, MAX_WORKERS):
		1:
			return [0.0]
		2:
			return [-0.75, 0.75]
	return [-1.3, 0.0, 1.3]
