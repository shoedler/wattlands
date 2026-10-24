class_name FishingBoat
extends RefCounted
## The pedal boat's physics (pure, deterministic, one call per 0.05 s step). The rider's
## effective power P_eff (the session's scaling mode decides fairness) sets a steady speed
##   v_ss = V_FTP x (P_eff / 250 W)^0.6,   V_FTP = 15 m/s
## so 250 W (100 % FTP-equivalent) crosses the 18 km roam map in 20 minutes, 125 W holds
## 9.9 m/s and 500 W 22.7 m/s: a surge visibly accelerates. With the prop engaged the speed
## approaches v_ss exponentially, over ACCEL_TAU_S speeding up and the quicker DECEL_TAU_S slowing
## down. With the prop free (drift, menu, fights, pause) water drag brakes it,
## dv/dt = -(|v| / DRIFT_TAU_S + DRIFT_BRAKE_MPS2), from cruise to a stop in about 3 s. The boat
## stops dead at the dock wall (x 0) and at the world's edge.
## Signed trim (deg, + bow up): a spring-damper toward 3 deg per V_FTP of the steady speed the
## power holds (prop engaged) plus 0.5 deg per m/s^2 of forward acceleration or 0.8 per m/s^2 of
## deceleration, in [-6, 14]. A surge kicks the bow above its steady trim, then it settles; a power
## cut or a hard drop digs the bow in (negative), level again once slow.
## brake (0..1) is the deceleration over 10 m/s^2, smoothed over 0.15 s; the wake is
## 0.6 x |v| / 21 m/s + 0.4 x throttle, 0..1.


## One step: `thrust_on` engages the prop (DRIVE); P_eff in watts.
static func step(
	r: FishingRiderState, p_eff_w: float, thrust_on: bool, edge_x: float, dt: float
) -> void:
	var p := maxf(p_eff_w, 0.0) if thrust_on else 0.0
	var v := r.v_mps
	var nv := 0.0
	if p > 0.0:
		var target := float(r.heading) * steady_speed(p)
		var tau := (
			FishingConst.ACCEL_TAU_S
			if (target - v) * float(r.heading) > 0.0
			else FishingConst.DECEL_TAU_S
		)
		nv = target + (v - target) * exp(-dt / tau)
	else:
		nv = signf(v) * _drift_speed(absf(v), dt)
	r.accel = (nv - v) / dt
	r.v_mps = nv
	r.x_m += nv * dt
	if r.x_m <= 0.0:
		r.x_m = 0.0
		if r.v_mps < 0.0:
			r.v_mps = 0.0
	if r.x_m >= edge_x:
		r.x_m = edge_x
		if r.v_mps > 0.0:
			r.v_mps = 0.0
	r.furthest_x_m = maxf(r.furthest_x_m, r.x_m)
	_trim(r, p, dt)
	var throttle := p / FishingConst.P_EFF_REF_W
	r.wake = clampf(
		(
			FishingConst.WAKE_SPEED * absf(r.v_mps) / FishingConst.WAKE_V_FULL
			+ (1.0 - FishingConst.WAKE_SPEED) * minf(throttle, 1.0)
		),
		0.0,
		1.0
	)


## |v| after dt of drift braking (exact): |v| / DRIFT_TAU_S + DRIFT_BRAKE_MPS2; stops at 0.
static func _drift_speed(speed: float, dt: float) -> float:
	var c := FishingConst.DRIFT_BRAKE_MPS2 * FishingConst.DRIFT_TAU_S
	var ns := (speed + c) * exp(-dt / FishingConst.DRIFT_TAU_S) - c
	return ns if ns > 0.01 else 0.0


## The trim spring-damper and the braking intensity (`p`: the driving P_eff, 0 with the prop
## free).
static func _trim(r: FishingRiderState, p: float, dt: float) -> void:
	var fwd_a := r.accel * float(r.heading)
	var target := (
		FishingConst.TRIM_PER_ACCEL * fwd_a if fwd_a > 0.0 else FishingConst.TRIM_PER_DECEL * fwd_a
	)
	if p > 0.0:
		var vn := minf(steady_speed(p) / FishingConst.V_FTP_MPS, FishingConst.TRIM_SPEED_MAX)
		target += FishingConst.TRIM_PER_SPEED * vn
	target = clampf(target, FishingConst.TRIM_MIN_DEG, FishingConst.TRIM_MAX_DEG)
	var w := FishingConst.TRIM_OMEGA
	r.pitch_rate += (
		(w * w * (target - r.pitch_deg) - 2.0 * FishingConst.TRIM_ZETA * w * r.pitch_rate) * dt
	)
	r.pitch_deg += r.pitch_rate * dt
	if r.pitch_deg > FishingConst.TRIM_MAX_DEG or r.pitch_deg < FishingConst.TRIM_MIN_DEG:
		r.pitch_deg = clampf(r.pitch_deg, FishingConst.TRIM_MIN_DEG, FishingConst.TRIM_MAX_DEG)
		r.pitch_rate = 0.0
	var raw := clampf(-fwd_a / FishingConst.BRAKE_FULL_MPS2, 0.0, 1.0)
	r.brake += (raw - r.brake) * (1.0 - exp(-dt / FishingConst.BRAKE_TAU_S))


## The steady speed (m/s) a constant P_eff holds: V_FTP x (P_eff / 250 W)^0.6.
static func steady_speed(p_eff_w: float) -> float:
	if p_eff_w <= 0.0:
		return 0.0
	var frac := minf(p_eff_w / FishingConst.P_EFF_REF_W, FishingConst.SPEED_P_MAX_FRAC)
	return FishingConst.V_FTP_MPS * pow(frac, FishingConst.SPEED_EXP)


## The SIM grade (%) for driving at speed v: 0.5 % + 2 x (v / V_FTP)^2, at most 3 % (water
## drag: the same felt load at the same share of the cruise speed).
static func grade_for(v_mps: float) -> float:
	var vn := v_mps / FishingConst.V_FTP_MPS
	return minf(
		FishingConst.GRADE_BASE_PCT + FishingConst.GRADE_PER_VN2 * vn * vn,
		FishingConst.GRADE_MAX_PCT
	)


## True when the boat counts as stopped.
static func stopped(r: FishingRiderState) -> bool:
	return absf(r.v_mps) < FishingConst.STOP_SPEED
