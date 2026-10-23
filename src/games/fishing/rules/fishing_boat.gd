class_name FishingBoat
extends RefCounted
## The pedal boat's physics (pure, deterministic, one call per 0.05 s step). Thrust comes from
## the rider's effective power P_eff (the session's scaling mode decides fairness):
##   m dv/dt = thrust - DRAG_QUAD v|v| - DRAG_LIN v,   thrust = heading x P_eff / max(|v|, V0)
## with m = 400 kg; 250 W of P_eff (100 % FTP-equivalent) holds 5 m/s, so a rider at 100 %
## crosses the 9 km roam map in about 30 minutes; 125 W holds 3.9 m/s and 500 W 6.4 m/s.
## Without thrust (drift, menu, fights, pause) a stronger linear drag (DRIFT_DRAG_LIN) brakes the
## boat to a stop within about 15 s. The boat stops
## dead at the dock wall (x 0) and at the world's edge.
## The bow pitch follows 2.5 deg per 100 % throttle plus 20 deg per m/s^2 of forward
## acceleration (hammering lifts the bow), at most 14 deg, smoothed over 0.6 s; the wake is
## 0.6 x |v| / 7 m/s + 0.4 x throttle, 0..1.


## One step: `thrust_on` engages the prop (DRIVE); P_eff in watts.
static func step(
	r: FishingRiderState, p_eff_w: float, thrust_on: bool, edge_x: float, dt: float
) -> void:
	var p := maxf(p_eff_w, 0.0) if thrust_on else 0.0
	var v := r.v_mps
	var thrust := float(r.heading) * p / maxf(absf(v), FishingConst.THRUST_V0)
	var lin := FishingConst.DRAG_LIN if p > 0.0 else FishingConst.DRIFT_DRAG_LIN
	var drag := FishingConst.DRAG_QUAD * v * absf(v) + lin * v
	var a := (thrust - drag) / FishingConst.BOAT_MASS_KG
	var nv := v + a * dt
	# Drag alone never reverses the boat.
	if p <= 0.0 and signf(nv) != signf(v):
		nv = 0.0
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
	var throttle := p / FishingConst.P_EFF_REF_W
	var fwd_a := r.accel * float(r.heading)
	var target := (
		FishingConst.PITCH_PER_THROTTLE * throttle + FishingConst.PITCH_PER_ACCEL * maxf(fwd_a, 0.0)
	)
	target = clampf(target, 0.0, FishingConst.PITCH_MAX_DEG)
	r.pitch_deg += (target - r.pitch_deg) * (1.0 - exp(-dt / FishingConst.PITCH_TAU_S))
	r.wake = clampf(
		(
			FishingConst.WAKE_SPEED * absf(r.v_mps) / FishingConst.WAKE_V_FULL
			+ (1.0 - FishingConst.WAKE_SPEED) * minf(throttle, 1.0)
		),
		0.0,
		1.0
	)


## The steady speed (m/s) a constant P_eff holds (bisection on the force balance).
static func steady_speed(p_eff_w: float) -> float:
	if p_eff_w <= 0.0:
		return 0.0
	var lo := 0.0
	var hi := 20.0
	for i in 40:
		var v := 0.5 * (lo + hi)
		var f := p_eff_w / maxf(v, FishingConst.THRUST_V0)
		var drag := FishingConst.DRAG_QUAD * v * v + FishingConst.DRAG_LIN * v
		if f > drag:
			lo = v
		else:
			hi = v
	return 0.5 * (lo + hi)


## The SIM grade (%) for driving at speed v: 0.5 % + 0.08 v^2, at most 3 % (water drag).
static func grade_for(v_mps: float) -> float:
	return minf(
		FishingConst.GRADE_BASE_PCT + FishingConst.GRADE_PER_V2 * v_mps * v_mps,
		FishingConst.GRADE_MAX_PCT
	)


## True when the boat counts as stopped.
static func stopped(r: FishingRiderState) -> bool:
	return absf(r.v_mps) < FishingConst.STOP_SPEED
