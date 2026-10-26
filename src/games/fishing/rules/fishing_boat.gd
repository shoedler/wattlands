class_name FishingBoat
extends RefCounted
## The pedal boat as a small rigid body on the water (pure, deterministic, one call per 0.05 s
## step): surge (speed), heave (hull height) and pitch, plus the planing level. The pedals drive
## a turbo: shaft power = TURBO_GAIN x P_eff (the session's scaling mode decides fairness).
##
## Surge, along the heading (mass BOAT_MASS_KG):
##   thrust = shaft / (u+ + THRUST_V0_MPS)  (u+ = forward speed, 0 when backing): strong at rest,
##       falling with speed; it reacts to every pedal stroke the step it arrives.
##   drag   = D0(s) x (1 + HUMP_K x hump(s) x (1 - plane)) x (1 - plane_cut x plane), where
##       D0(s) = TURBO_GAIN x 250 W x (s / V_FTP)^(1 / 0.6) / (s + THRUST_V0_MPS), so in
##       displacement a constant P_eff holds V_FTP x (P_eff / 250 W)^0.6 (15 m/s at 100 %);
##       hump(s) = exp(-((s - HUMP_V_MPS) / HUMP_W_MPS)^2) is the displacement hump the hull
##       pushes through; plane_cut makes the planing cruise PLANE_SPEED_GAIN (7 %) faster at the
##       same power. Backing (towed stern first) doubles it; with the prop free a windmilling
##       prop adds FREE_N_PER_MPS x s + FREE_N x min(1, s / FREE_SOFT_MPS): from cruise to a
##       stop in about 3.5 s.
##   tow    = the line tension (FishingRiderState.tow_n, FishingFight) along the line toward the
##       fish: its horizontal part pulls the boat back toward the fish, its vertical part pulls
##       the stern down (heave and pitch below).
## Planing: the latch sets once the forward speed reaches PLANE_ON_MPS (70 % FTP-equivalent gets
## there, 66 % does not) and clears under PLANE_OFF_MPS (about 55 %); the level climbs to 1 over
## PLANE_RISE_S and falls over PLANE_FALL_S.
## Heave and pitch are buoyancy spring-dampers toward the equilibrium the forces set:
##   heave -> HEAVE_PLANE_M x plane - HEAVE_SQUAT_M x hump x (1 - plane)
##            - HEAVE_DIG_M x braking force / F_ref - HEAVE_TOW_M x stern pull / TOW_MAX_N
##   pitch -> PITCH_THRUST_DEG x thrust / F_ref - PITCH_DRAG_DEG x drag / F_ref
##            + PITCH_HUMP_DEG x hump x (1 - plane) + PITCH_PLANE_DEG x plane
##            + PITCH_TOW_DEG x stern pull / TOW_MAX_N        (F_ref: the drag at V_FTP)
## The thrust line sits below the drag: a surge lifts the bow, the hump squats the stern, on the
## plane the hull rises and flattens with the transom at the waterline, and drag with no thrust
## (braking) digs the bow in. The prop sits STERN_ARM_M behind the hull's centre:
## prop depth = PROP_REST_M - heave + STERN_ARM_M x sin(pitch), never under PROP_MIN_M (the prop
## never leaves the water). The boat stops dead at the dock wall (x 0) and the world's edge.
## brake (0..1) is the deceleration over 10 m/s^2, smoothed over 0.15 s; the wake is
## 0.6 x |v| / 21 m/s + 0.4 x throttle, 0..1.

const EPS := 1e-6


## One step: `thrust_on` engages the prop (DRIVE); P_eff in watts. r.tow_n (set by the fight)
## tows the boat along the line.
static func step(
	r: FishingRiderState, p_eff_w: float, thrust_on: bool, edge_x: float, dt: float
) -> void:
	var p := clampf(p_eff_w, 0.0, FishingConst.SPEED_P_MAX_FRAC * FishingConst.P_EFF_REF_W)
	if not thrust_on:
		p = 0.0
	var hd := float(r.heading)
	var u := r.v_mps * hd
	var thrust := FishingConst.TURBO_GAIN * p / (maxf(u, 0.0) + FishingConst.THRUST_V0_MPS)
	var dr := drag(absf(u), r.plane)
	if u < 0.0:
		dr *= FishingConst.REVERSE_DRAG
	if not thrust_on:
		dr += free_prop_drag(absf(u))
	var tow := _tow(r)
	var nu := u + (thrust - signf(u) * dr + tow.x) / FishingConst.BOAT_MASS_KG * dt
	if p <= 0.0 and tow.x == 0.0 and (signf(nu) != signf(u) or absf(nu) < 0.01):
		nu = 0.0
	var nv := nu * hd
	r.accel = (nv - r.v_mps) / dt
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
	_plane(r, r.v_mps * hd, dt)
	_hull(r, thrust, dr, tow.y, dt)
	var throttle := p / FishingConst.P_EFF_REF_W
	r.wake = clampf(
		(
			FishingConst.WAKE_SPEED * absf(r.v_mps) / FishingConst.WAKE_V_FULL
			+ (1.0 - FishingConst.WAKE_SPEED) * minf(throttle, 1.0)
		),
		0.0,
		1.0
	)


## Hull drag (N) at speed s (m/s, >= 0) and planing level `plane`.
static func drag(s: float, plane: float) -> float:
	if s <= 0.0:
		return 0.0
	var shaft := FishingConst.TURBO_GAIN * FishingConst.P_EFF_REF_W
	var d0 := (
		shaft
		* pow(s / FishingConst.V_FTP_MPS, 1.0 / FishingConst.SPEED_EXP)
		/ (s + FishingConst.THRUST_V0_MPS)
	)
	var hump_f := 1.0 + FishingConst.HUMP_K * hump(s) * (1.0 - plane)
	return d0 * hump_f * (1.0 - plane_cut() * plane)


## The free (windmilling) prop's extra drag (N) at speed s.
static func free_prop_drag(s: float) -> float:
	if s <= 0.0:
		return 0.0
	return (
		FishingConst.FREE_N_PER_MPS * s
		+ FishingConst.FREE_N * minf(1.0, s / FishingConst.FREE_SOFT_MPS)
	)


## The displacement hump's shape at speed s: 1 at HUMP_V_MPS.
static func hump(s: float) -> float:
	var k := (s - FishingConst.HUMP_V_MPS) / FishingConst.HUMP_W_MPS
	return exp(-k * k)


## The drag cut on the plane that makes the cruise PLANE_SPEED_GAIN faster at the same power.
static func plane_cut() -> float:
	return 1.0 - pow(1.0 + FishingConst.PLANE_SPEED_GAIN, -1.0 / FishingConst.SPEED_EXP)


## The drag at V_FTP in displacement (N): the scale of the pitch moments.
static func ref_force() -> float:
	return (
		FishingConst.TURBO_GAIN
		* FishingConst.P_EFF_REF_W
		/ (FishingConst.V_FTP_MPS + FishingConst.THRUST_V0_MPS)
	)


## The line's pull: x along the heading (negative: toward the fish behind the stern), y the
## downward pull on the stern (N).
static func _tow(r: FishingRiderState) -> Vector2:
	if r.tow_n <= 0.0:
		return Vector2.ZERO
	var line := Vector2(r.fish.d, r.fish.depth_m())
	if line.length() < EPS:
		return Vector2.ZERO
	var dir := line.normalized()
	return Vector2(-r.tow_n * dir.x, r.tow_n * dir.y)


static func _plane(r: FishingRiderState, u: float, dt: float) -> void:
	if not r.planing and u >= FishingConst.PLANE_ON_MPS:
		r.planing = true
	elif r.planing and u < FishingConst.PLANE_OFF_MPS:
		r.planing = false
	var up := dt / FishingConst.PLANE_RISE_S
	var down := dt / FishingConst.PLANE_FALL_S
	r.plane = clampf(r.plane + (up if r.planing else -down), 0.0, 1.0)


## Heave and pitch spring-dampers, the prop depth and the brake intensity.
static func _hull(r: FishingRiderState, thrust: float, dr: float, pull_z: float, dt: float) -> void:
	var f_ref := ref_force()
	var hu := hump(absf(r.v_mps)) * (1.0 - r.plane) if r.v_mps != 0.0 else 0.0
	var dig := minf(maxf(dr - thrust, 0.0) / f_ref, FishingConst.DIG_MAX)
	var pull := pull_z / FishingConst.TOW_MAX_N
	var h_eq := (
		FishingConst.HEAVE_PLANE_M * r.plane
		- FishingConst.HEAVE_SQUAT_M * hu
		- FishingConst.HEAVE_DIG_M * dig
		- FishingConst.HEAVE_TOW_M * pull
	)
	r.heave_rate += _spring(
		h_eq - r.heave_m, r.heave_rate, FishingConst.HEAVE_OMEGA, FishingConst.HEAVE_ZETA, dt
	)
	r.heave_m += r.heave_rate * dt
	var p_eq := (
		FishingConst.PITCH_THRUST_DEG * thrust / f_ref
		- FishingConst.PITCH_DRAG_DEG * dr / f_ref
		+ FishingConst.PITCH_HUMP_DEG * hu
		+ FishingConst.PITCH_PLANE_DEG * r.plane
		+ FishingConst.PITCH_TOW_DEG * pull
	)
	r.pitch_rate += _spring(
		p_eq - r.pitch_deg, r.pitch_rate, FishingConst.PITCH_OMEGA, FishingConst.PITCH_ZETA, dt
	)
	r.pitch_deg += r.pitch_rate * dt
	if r.pitch_deg > FishingConst.TRIM_MAX_DEG or r.pitch_deg < FishingConst.TRIM_MIN_DEG:
		r.pitch_deg = clampf(r.pitch_deg, FishingConst.TRIM_MIN_DEG, FishingConst.TRIM_MAX_DEG)
		r.pitch_rate = 0.0
	var sink := FishingConst.STERN_ARM_M * sin(deg_to_rad(r.pitch_deg))
	r.prop_depth_m = maxf(FishingConst.PROP_MIN_M, FishingConst.PROP_REST_M - r.heave_m + sink)
	var fwd_a := r.accel * float(r.heading)
	var raw := clampf(-fwd_a / FishingConst.BRAKE_FULL_MPS2, 0.0, 1.0)
	r.brake += (raw - r.brake) * (1.0 - exp(-dt / FishingConst.BRAKE_TAU_S))


## A damped spring's rate change over dt: omega^2 x offset - 2 zeta omega x rate.
static func _spring(offset: float, rate: float, omega: float, zeta: float, dt: float) -> float:
	return (omega * omega * offset - 2.0 * zeta * omega * rate) * dt


## The displacement steady speed (m/s) a constant P_eff holds: V_FTP x (P_eff / 250 W)^0.6.
static func steady_speed(p_eff_w: float) -> float:
	if p_eff_w <= 0.0:
		return 0.0
	var frac := minf(p_eff_w / FishingConst.P_EFF_REF_W, FishingConst.SPEED_P_MAX_FRAC)
	return FishingConst.V_FTP_MPS * pow(frac, FishingConst.SPEED_EXP)


## The cruise speed (m/s) a constant P_eff reaches from rest: on the plane (x 1.07) from 70 %
## FTP-equivalent, else steady_speed().
static func cruise_speed(p_eff_w: float) -> float:
	var v := steady_speed(p_eff_w)
	if p_eff_w >= FishingConst.PLANE_P_FRAC * FishingConst.P_EFF_REF_W:
		v *= 1.0 + FishingConst.PLANE_SPEED_GAIN
	return v


## The SIM grade (%) for driving at speed v: 0.5 % + 2 x (v' / V_FTP)^2, at most 3 %, where v'
## is v without the planing gain (water drag: the same felt load at the same power share;
## getting onto the plane does not make pedaling heavier).
static func grade_for(v_mps: float, plane: float = 0.0) -> float:
	var vn := v_mps / (1.0 + FishingConst.PLANE_SPEED_GAIN * plane) / FishingConst.V_FTP_MPS
	return minf(
		FishingConst.GRADE_BASE_PCT + FishingConst.GRADE_PER_VN2 * vn * vn,
		FishingConst.GRADE_MAX_PCT
	)


## True when the boat counts as stopped.
static func stopped(r: FishingRiderState) -> bool:
	return absf(r.v_mps) < FishingConst.STOP_SPEED
